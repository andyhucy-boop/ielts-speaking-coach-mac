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

        for entry in (root["part1"]?.arrayValue ?? []) {
            let topic = entry["raw"]?.stringValue ?? ""
            for question in (entry["questions"]?.arrayValue ?? []) {
                guard let prompt = question.stringValue, !prompt.isEmpty else { continue }
                questions.append(Question(
                    id: questionID(part: 1, topic: topic, prompt: prompt), part: 1, topic: topic, prompt: prompt,
                    source: title, sourceUrl: sourceUrl, importLevel: importLevel))
            }
        }

        for entry in (root["part23"]?.arrayValue ?? []) {
            let topic = entry["raw"]?.stringValue ?? ""
            let part3Prompts = (entry["part3Questions"]?.arrayValue ?? [])
                .compactMap(\.stringValue).filter { !$0.isEmpty }

            for question in (entry["part2Questions"]?.arrayValue ?? []) {
                guard let prompt = question.stringValue, !prompt.isEmpty else { continue }
                questions.append(Question(
                    id: questionID(part: 2, topic: topic, prompt: prompt), part: 2, topic: topic, prompt: prompt,
                    followups: part3Prompts, source: title, sourceUrl: sourceUrl,
                    importLevel: importLevel))
            }
            for prompt in part3Prompts {
                questions.append(Question(
                    id: questionID(part: 3, topic: topic, prompt: prompt), part: 3, topic: topic, prompt: prompt,
                    source: title, sourceUrl: sourceUrl, importLevel: importLevel))
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

    /// 按 id 去重，同 id 时新导入的覆盖旧的；保持「已有在前、新增在后」的稳定顺序。
    public static func merge(existing: [Question], incoming: [Question]) -> [Question] {
        // ⚠️ 不能用 Dictionary(uniqueKeysWithValues:) —— 用户手工拼题库时同一批内
        // 出现重复 id 极常见（复制粘贴忘改编号），那个构造器遇到重复 key 会直接
        // fatalError 闪退整个 App，而不是报错。逐个赋值，同 id 后者覆盖前者。
        var byID: [String: Question] = [:]
        for question in incoming { byID[question.id] = question }
        var merged: [Question] = []
        for question in existing {
            merged.append(byID.removeValue(forKey: question.id) ?? question)
        }
        // 用 byID.removeValue 取值而不是直接 append 循环变量 question：
        // incoming 内若有重复 id，循环变量会是「第一次出现的那份」，但
        // byID 里存的是「同一批内最后一份」。必须取 byID 里的，否则重复 id
        // 场景下会错误地保留第一份而不是按约定的「后者覆盖前者」。
        for question in incoming {
            guard let deduplicated = byID.removeValue(forKey: question.id) else { continue }
            merged.append(deduplicated)
        }
        return merged
    }
}
