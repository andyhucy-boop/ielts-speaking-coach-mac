import Foundation

public struct ImportResult: Equatable, Sendable {
    public let questions: [Question]
    public let source: QuestionSource
    public let warnings: [String]

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(questions: [Question], source: QuestionSource, warnings: [String]) {
        self.questions = questions; self.source = source; self.warnings = warnings
    }
}

public enum QuestionBankImporter {
    private static let requiredHeaders = ["id", "part", "topic", "prompt"]

    // MARK: - CSV

    public static func importCSV(_ text: String, sourceTitle: String) throws -> ImportResult {
        let parsed = parseCSV(text)
        let rows = parsed.rows
        guard let header = rows.first else {
            throw CoachError.questionBankInvalid("题库文件是空的。下一步：确认导出时选中了内容再重试。")
        }
        let columns = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for required in requiredHeaders where !columns.contains(required) {
            throw CoachError.questionBankInvalid(
                "题库表头缺少必需列「\(required)」。下一步：确保第一行是 id,part,topic,prompt,followups。")
        }
        func value(_ row: [String], _ name: String) -> String {
            guard let index = columns.firstIndex(of: name), index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }

        var questions: [Question] = []
        var warnings: [String] = []

        if parsed.unterminatedQuote {
            warnings.append("题库里有一个双引号没有闭合，从该处起后面的内容可能被整体吞掉了，导致大量题目丢失。"
                + "下一步：检查题干里的英文引号是否成对；若题干本身要包含引号，请写成两个连续的引号。")
        }

        for row in rows.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            // 先查 id 再查 part：反过来的话「缺少 id」这条警告几乎不可达，
            // 因为缺 id 的行通常 part 也是空的，会被 part 分支先拦下。
            let id = value(row, "id")
            guard !id.isEmpty else {
                warnings.append("跳过一行：缺少 id。下一步：给每道题一个唯一编号，例如 p1-home-001。")
                continue
            }
            guard let part = Int(value(row, "part")), (1...3).contains(part) else {
                warnings.append("跳过第 \(id) 行：part 必须是 1、2 或 3。下一步：把该行的 part 改成 1、2 或 3。")
                continue
            }
            let followups = value(row, "followups")
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            questions.append(Question(id: id, part: part, topic: value(row, "topic"),
                                      prompt: value(row, "prompt"), followups: followups,
                                      source: sourceTitle))
        }

        return ImportResult(
            questions: questions,
            source: QuestionSource(title: sourceTitle, sourceUrl: "",
                                   importedAt: ISO8601DateFormatter().string(from: Date()),
                                   importLevel: "full-question", questionCount: questions.count),
            warnings: warnings)
    }

    /// 支持双引号包裹的字段（内部可含逗号与换行）与 "" 转义。
    /// 返回解析结果与「是否存在未闭合的双引号」。后者必须上报——
    /// 引号不闭合会把其后所有内容（含行分隔符）吞成一个字段，导致大量行静默消失。
    private static func parseCSV(_ text: String) -> (rows: [[String]], unterminatedQuote: Bool) {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func nextCharacter() -> Character? {
            if let held = pending { pending = nil; return held }
            return iterator.next()
        }

        while let character = nextCharacter() {
            if inQuotes {
                if character == "\"" {
                    if let peek = nextCharacter() {
                        if peek == "\"" { field.append("\"") } else { inQuotes = false; pending = peek }
                    } else { inQuotes = false }
                } else { field.append(character) }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n":
                row.append(field); field = ""
                rows.append(row); row = []
            case "\r": break
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return (rows, inQuotes)
    }

    // MARK: - JSON

    public static func importJSON(_ text: String, sourceTitle: String) throws -> ImportResult {
        guard let root = try? JSONValue.decode(from: text), root.objectValue != nil else {
            throw CoachError.questionBankInvalid("题库 JSON 无法解析。下一步：确认文件是完整的 JSON 再重试。")
        }
        let title = root["title"]?.stringValue ?? sourceTitle
        let sourceUrl = root["sourceUrl"]?.stringValue ?? ""
        let importLevel = root["importLevel"]?.stringValue ?? "full-question"

        var questions: [Question] = []
        var warnings: [String] = []

        // **这份 JSON 的形状本来就是「一个话题一组问句」**（`part1: [{raw, questions}]`），
        // 与新模型一一对应：`raw` 是话题，`questions` 是这个话题下的参考问句。
        // 从前把它拆成一问一题，是把上游已经分好的组又打散了一遍。
        for entry in (root["part1"]?.arrayValue ?? []) {
            let topic = entry["raw"]?.stringValue ?? ""
            let prompts = (entry["questions"]?.arrayValue ?? [])
                .compactMap(\.stringValue).filter { !$0.isEmpty }
            guard !topic.isEmpty || !prompts.isEmpty else { continue }
            var question = TopicQuestions.part1(topic: topic, prompts: prompts,
                                                source: title, sourceUrl: sourceUrl)
            question.importLevel = importLevel
            questions.append(question)
        }

        for entry in (root["part23"]?.arrayValue ?? []) {
            let topic = entry["raw"]?.stringValue ?? ""
            let part3Prompts = (entry["part3Questions"]?.arrayValue ?? [])
                .compactMap(\.stringValue).filter { !$0.isEmpty }
            let cueCards = (entry["part2Questions"]?.arrayValue ?? [])
                .compactMap(\.stringValue).filter { !$0.isEmpty }

            for prompt in cueCards {
                // **Part 2 的 `followups` 不再塞 Part 3 的问句。** 那一栏在提示词里
                // 是「cue card 上要覆盖的提示点」，把 Part 3 的抽象问题放进去，
                // 考官会在两分钟独白里追着问社会议题——那是 Part 3 的事。
                // 这份 JSON 不携带 cue card 的提示点，所以就是空的。
                questions.append(Question(
                    id: questionID(part: 2, topic: topic, prompt: prompt), part: 2,
                    topic: topic, prompt: prompt,
                    source: title, sourceUrl: sourceUrl, importLevel: importLevel))
            }
            guard !part3Prompts.isEmpty else { continue }
            // 一张 cue card 一道 Part 3。条目里一张 cue card 都没有时（上游确实有这种
            // 只列讨论题的条目），退回用条目自己的 `raw` 当归属，不丢内容。
            for cueCard in (cueCards.isEmpty ? [topic] : cueCards) {
                var question = TopicQuestions.part3(cueCard: cueCard, prompts: part3Prompts,
                                                    source: title, sourceUrl: sourceUrl)
                question.importLevel = importLevel
                questions.append(question)
            }
        }

        if questions.isEmpty {
            warnings.append("这份题库没有解析出任何题目。"
                + "下一步：确认 JSON 顶层含 part1 或 part23 字段，且它们是非空数组。")
        }

        return ImportResult(
            questions: questions,
            source: QuestionSource(
                title: title, sourceUrl: sourceUrl,
                importedAt: root["importedAt"]?.stringValue ?? ISO8601DateFormatter().string(from: Date()),
                importLevel: importLevel, questionCount: questions.count),
            warnings: warnings)
    }

    // MARK: - 内容哈希 id

    /// 确定性哈希（FNV-1a 64 位）。**不能用 Swift 的 hashValue** —— 它每次进程启动
    /// 都换种子，同一份题库两次导入会得到不同 id。
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 36)
    }

    /// 由内容而非位置生成 id。位置式编号在用户导入更新版题库时会整体错位：
    /// 中间插入或删除一个 topic，后面所有题的 id 都变，merge 会把无关内容
    /// 覆盖到旧 id 上、未变的题被当成新题追加、练习记录错位。
    /// 雅思口语题库每季度换题，二次导入是常态而非边缘情况。
    ///
    /// **`internal` 而不是 `private` 是为了让 `PDFQuestionExtractor` 用同一份实现。**
    /// PDF 导入自己再写一遍哈希，两条路生成的 id 就会对不上：同一道题从 CSV 导一次、
    /// 从 PDF 再导一次会变成两道，`merge` 也去不掉重。
    static func questionID(part: Int, topic: String, prompt: String) -> String {
        "p\(part)-\(stableHash("\(topic)|\(prompt)"))"
    }

    // MARK: - 合并

    /// 一次合并的结果。**不是只有题目**：题库重建模那一刻，
    /// 有些旧题会被新的话题题吸收掉，挂在它们身上的练习记录必须跟着搬家。
    public struct MergeResult: Equatable, Sendable {
        /// 合并之后的题库。
        public let questions: [Question]
        /// 旧 id → 新 id。被话题题吸收掉的那些旧题。
        ///
        /// **调用方必须拿它去调 `QuestionBankMigration.remapQuestionIDs`。**
        /// 不搬的话，用户那场练习会在训练记录页显示「这道题已经不在题库里了」——
        /// 数据都在，只是再也对不上号（这正是把返回值从 `[Question]` 换成一个
        /// 结构体的理由：忘了处理时编译器会说话，而不是等用户发现历史成了孤儿）。
        public let replacements: [String: String]

        public init(questions: [Question], replacements: [String: String]) {
            self.questions = questions
            self.replacements = replacements
        }
    }

    /// 按 id 去重，同 id 时新导入的**内容**覆盖旧的（但「已练」标记留着）；
    /// 保持「已有在前、新增在后」的稳定顺序。
    ///
    /// ## 除了按 id 去重，还要认「碎片」
    ///
    /// 题库从「一问一题」改成「一话题一题」之后，用户库里那 281 道 Part 1「题」
    /// 与 885 道 Part 3「题」全都是新模型下某一道话题题的**参考问句**。
    /// 只按 id 合并的话，它们一道不少地留在库里，新的 59+99 道话题题追加在后面，
    /// 题库从 1265 道涨到 1422 道——用户会以为导入把题库搞坏了。
    ///
    /// 所以这里多认一条：新导入的话题题会吸收题库里**同 part、同话题、且题干正好是
    /// 它某一条参考问句**的旧题（判据见 `TopicQuestions.supersedes`，刻意选窄，
    /// 不按来源猜，免得吃掉用户自己用 CSV 加的题）。被吸收的旧题从题库里去掉，
    /// 它的「已练」标记升到吸收它的那道话题题上，它的 id 进 `replacements`。
    public static func merge(existing: [Question], incoming: [Question]) -> MergeResult {
        // ⚠️ 不能用 Dictionary(uniqueKeysWithValues:) —— 用户手工拼题库时同一批内
        // 出现重复 id 极常见（复制粘贴忘改编号），那个构造器遇到重复 key 会直接
        // fatalError 闪退整个 App，而不是报错。逐个赋值，同 id 后者覆盖前者。
        var byID: [String: Question] = [:]
        for question in incoming { byID[question.id] = question }

        // 这一批里的话题题，按 (part, 话题) 索引，用来认旧题库里的碎片。
        // 用字典而不是每次线性扫 incoming：真实题库两边都是上千条，
        // 平方级的比对会让一次导入卡住好几秒，而那期间界面没有任何反馈。
        var topicQuestions: [String: Question] = [:]
        for question in incoming where TopicQuestions.isTopicQuestion(question) {
            topicQuestions["\(question.part)|\(question.topic)"] = question
        }
        var replacements: [String: String] = [:]
        // 被吸收的碎片里练过的那些，它们的「已练」要升到吸收它们的话题题上。
        var practicedByAbsorption: Set<String> = []

        var merged: [Question] = []
        for question in existing {
            guard var updated = byID.removeValue(forKey: question.id) else {
                // 不是同一道题，再问一句：它是不是这一批里某道话题题的一条参考问句。
                if let owner = topicQuestions["\(question.part)|\(question.topic)"],
                   TopicQuestions.supersedes(owner, question) {
                    replacements[question.id] = owner.id
                    if question.status == "practiced" { practicedByAbsorption.insert(owner.id) }
                    continue        // 碎片本身不再留在题库里
                }
                merged.append(question)
                continue
            }
            // **`status` 从旧的那份原样带过来，不许被导入文件覆盖。**
            //
            // 「练过没有」是用户的进度，不是题库内容。导入器写出来的每道题
            // `status` 都是 "new"，整条覆盖就等于：换季重新导入一次，
            // 凡是新包里也有的题（内容一个字没改的那些）「已练」标记全部清零——
            // 题库页顶上「已经练过」的数字掉下去、每道题右边的勾消失、
            // 终端列表里的 ✓ 消失、ChatGPT 侧读到的已练数跟着变小，
            // 全程没有提示、没有报错，而引导页刚保证过「换季重新导入是安全的」。
            // **雅思题库每季度换题，这是日常，不是边缘情况。**
            //
            // 项目自己在 `PlanRegenerator` 的注释里写着「顺手把 status 重置成 new……
            // 会让用户一次点击丢掉全部历史」——导入这条路曾经正好在犯它。
            //
            // 反向也不许：导入文件里写着 practiced 的题，本机没练过就还是没练过，
            // 否则用户会拿到假的正反馈。
            updated.status = question.status
            merged.append(updated)
        }
        // 用 byID.removeValue 取值而不是直接 append 循环变量 question：
        // incoming 内若有重复 id，循环变量会是「第一次出现的那份」，但
        // byID 里存的是「同一批内最后一份」。必须取 byID 里的，否则重复 id
        // 场景下会错误地保留第一份而不是按约定的「后者覆盖前者」。
        for question in incoming {
            guard let deduplicated = byID.removeValue(forKey: question.id) else { continue }
            merged.append(deduplicated)
        }

        // 「已练」升级放在最后统一做：吸收它的那道话题题既可能是这次新追加的，
        // 也可能早就在题库里（第二次导入同一份 PDF）。分散在上面两个循环里写，
        // 必然漏掉其中一种。
        if !practicedByAbsorption.isEmpty {
            merged = merged.map { question in
                guard practicedByAbsorption.contains(question.id), question.status != "practiced"
                else { return question }
                var upgraded = question
                upgraded.status = "practiced"
                return upgraded
            }
        }
        return MergeResult(questions: merged, replacements: replacements)
    }
}
