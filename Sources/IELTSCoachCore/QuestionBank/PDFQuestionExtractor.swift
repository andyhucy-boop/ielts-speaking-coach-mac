import Foundation

/// 从题库 PDF 抽出的**纯文本**里提取题目。
///
/// **只吃纯文本，不碰 PDFKit。** 取文字那一步（`PDFDocument(url:)?.string`）很薄，放在 UI 层，
/// 这样 `IELTSCoachCore` 只依赖 Foundation 的约束不被破坏，而真正难的解析部分完全可测。
///
/// 解析规则来自对用户手上那份真实季度题库的实测（2026-08-06，81 页，PDFKit 抽出 2515 行），
/// **不是按想象中的题库排版写的**。真实文件的四个坑：
///
/// 1. 前 196 行是目录，靠点号引导识别（正文里不会出现连续四个以上的点）
/// 2. 分区标题带字符间空格（`Part1 必 考 题`、`Part 1 T opics`），必须去掉全部空白再比
/// 3. 页码、分支分隔符 `/` 混在正文行里
/// 4. **题干、提示点、追问都会在任意位置折行**，续行没有任何标记
///
/// 第 4 条是本文件的核心难点：不处理折行的话，`(not a teacher)` 会变成一道独立的「题」，
/// 而真正的题目缺一截——提出来的东西看着有几百条，其实大半是残片。
public enum PDFQuestionExtractor {

    // MARK: - 对外入口

    /// 把 PDF 抽出的纯文本解析成题库。
    ///
    /// 一道题都没提出来时**不静默返回空**：`warnings` 里必须有一条说清发生了什么、下一步做什么。
    public static func extract(plainText: String, sourceTitle: String,
                               sourceUrl: String) throws -> ImportResult {
        let lines = joinWrappedLines(dropNoise(plainText))
        var builder = Builder(sourceTitle: sourceTitle, sourceUrl: sourceUrl)
        for line in lines { builder.consume(line) }
        builder.finish()

        return ImportResult(
            questions: builder.questions,
            source: QuestionSource(title: sourceTitle, sourceUrl: sourceUrl,
                                   importedAt: ISO8601DateFormatter().string(from: Date()),
                                   importLevel: "full-question",
                                   questionCount: builder.questions.count),
            warnings: builder.warnings(textLineCount: lines.count))
    }

    // MARK: - 第一遍：扔垃圾

    /// 逐行丢掉目录项、页码、分支分隔符与空行。
    private static func dropNoise(_ plainText: String) -> [String] {
        var kept: [String] = []
        for raw in plainText.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // 目录项：点号引导。**不能按「以数字结尾」判断**——目录项自己也会折行，
            // 「1- Describe … (not a」那一行既不含点也不以数字结尾。
            if line.range(of: "\\.{4,}", options: .regularExpression) != nil { continue }
            // 页码：整行只有数字。
            if line.allSatisfy(\.isNumber) { continue }
            // Part 1 里学生 / 工作者两条分支之间的分隔符。
            if line == "/" { continue }
            kept.append(line)
        }
        return kept
    }

    // MARK: - 第二遍：合并折行

    /// 把 PDF 折行产生的续行接回上一行。
    ///
    /// **判据是「这一行以什么开头」，不是「上一行有多长」。**
    /// 计划里原本写的是「不是结构行就接到上一行末尾」，那条规则会把连续的普通行**全部**并成一行：
    /// 一张 cue card 的四条提示点会变成一条，两道相邻的 Part 3 追问也会变成一道——
    /// 计划自带的 `testWrappedFollowupQuestionIsJoined`（期望两条追问）当场就红。
    ///
    /// 真实文件里的续行都是被右边距截断的半句话，一律以小写字母或标点开头
    /// （`(not a teacher)`、`learning from someone like a friend…`）；
    /// 而每一道新的题目、每一条新的提示点都以大写字母、数字或汉字开头。所以按首字符判断。
    private static func joinWrappedLines(_ lines: [String]) -> [String] {
        var joined: [String] = []
        for line in lines {
            if let previous = joined.last, canAbsorbContinuation(previous),
               isContinuation(line, of: previous) {
                joined[joined.count - 1] = previous + " " + line
            } else {
                joined.append(line)
            }
        }
        return joined
    }

    /// 英语句子不可能停在这七个词上，所以下一行必然是它的后半截——
    /// 哪怕那半截以大写的专有名词开头（真实文件里的
    /// 「…sporting events like the」+「Olympics?」、「…globally important as」+「English in the future?」）。
    ///
    /// **这张表是刻意选窄的。** `like` / `with` / `about` / `of` / `for` / `to` 都能合法收尾：
    /// 「What it is like」「Who you were with」「What it is made of」全是真实 cue card 的提示点。
    /// 把它们算进来，99 张 cue card 的提示点会成片被粘掉。
    private static let danglingWords: Set<String> = ["the", "a", "an", "and", "or", "as", "than"]

    /// 光秃秃的追问尾巴。**它不可能是一道独立的题**：没有上下文，拿来练也没法答。
    /// 真实文件里是「…or a small family business?」换行之后的「Why?」。
    private static let bareTails: Set<String> = ["why?", "whynot?", "whyorwhynot?", "why/whynot?"]

    /// 这一行是不是上一行被截断的后半截。
    ///
    /// 主判据是**首字符**：真实文件里的续行几乎都以小写字母或标点开头
    /// （`(not a teacher)`、`learning from someone like…`），而每一道新题、每一条新提示点
    /// 都以大写字母、数字或汉字开头。1276 道题里 1269 道靠这一条就分得清。
    ///
    /// 剩下两种形状要另外两条判据兜住，见 `danglingWords` 与 `bareTails`。
    private static func isContinuation(_ line: String, of previous: String) -> Bool {
        guard case .text = classify(line) else { return false }
        let compact = line.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
        if bareTails.contains(compact) { return true }
        if endsWithDanglingWord(previous) { return true }
        guard let first = line.unicodeScalars.first else { return false }
        if CharacterSet.uppercaseLetters.contains(first) { return false }
        if CharacterSet.decimalDigits.contains(first) { return false }
        if isCJK(first) { return false }
        return true
    }

    private static func endsWithDanglingWord(_ line: String) -> Bool {
        guard let last = line.split(separator: " ").last else { return false }
        return danglingWords.contains(last.lowercased())
    }

    /// 只有题目本身能接续行。分区标题、类别标签、`You should say`、`Part3` 都是独立的一行，
    /// 往它们后面接东西只会把结构弄坏。
    private static func canAbsorbContinuation(_ line: String) -> Bool {
        switch classify(line) {
        case .text, .numbered: return true
        default: return false
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x4DBF).contains(scalar.value)      // 扩展 A
            || (0x4E00...0x9FFF).contains(scalar.value)   // 基本区
            || (0xF900...0xFAFF).contains(scalar.value)   // 兼容表意
    }

    // MARK: - 行的种类

    /// 当前落在哪个分区。分区之外（封面、目录）的内容一律不当成题目。
    enum Region: Equatable {
        case none
        case part1
        case part23
    }

    private enum LineKind {
        /// 分区标题，如「Part1 必 考 题」「Part 1 T opics」。
        case sectionHeader(Region)
        /// Part 2/3 的中文类别标签：人物 / 地点 / 物品 / 事件。
        case categoryLabel(String)
        /// cue card 的「You should say」。真实文件里**没有冒号**。
        case youShouldSay
        /// cue card 之后追问的开始标记。真实文件里是「Part3」，中间没有空格。
        case part3Marker
        /// 编号项，如「1-Study and work」。带的是去掉编号后的正文。
        case numbered(String)
        /// 其余的正文行。
        case text
    }

    private static let categoryLabels: Set<String> = ["人物", "地点", "物品", "事件"]

    /// 判断一行属于哪一种。
    ///
    /// **所有结构判断都在「去掉全部空白」之后做。** PDF 抽出来的分区标题是
    /// 「Part1 必 考 题」「Part 1 T opics」「You should say」，按原样匹配一个都对不上。
    private static func classify(_ line: String) -> LineKind {
        let compact = line.components(separatedBy: .whitespacesAndNewlines).joined()
        let label = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":：."))

        if compact.contains("必考题") || compact.contains("保留题") || compact.contains("新题") {
            return .sectionHeader(region(ofHeader: compact))
        }
        // 「Part 1 T opics」「Part 2 & 3 T opics」这类总标题也是分区的开始。
        if compact.lowercased().contains("topics"), compact.hasPrefix("Part") {
            return .sectionHeader(region(ofHeader: compact))
        }
        if compact == "Part3" || compact == "Part3:" { return .part3Marker }
        if label.lowercased() == "youshouldsay" { return .youShouldSay }
        if categoryLabels.contains(label) { return .categoryLabel(label) }
        if let body = numberedBody(line) { return .numbered(body) }
        return .text
    }

    /// 分区标题指向哪个分区。**认不出时归 `.none`**——宁可少提，也不要把 Part 2 的
    /// cue card 一股脑算进 Part 1，那样练习时会拿一张 cue card 当 Part 1 的问题问。
    private static func region(ofHeader compact: String) -> Region {
        if compact.contains("Part1") { return .part1 }
        if compact.contains("Part2") || compact.contains("Part3") { return .part23 }
        return .none
    }

    /// 「1-Study and work」→「Study and work」。编号与正文之间可能有空格，也可能没有。
    private static func numberedBody(_ line: String) -> String? {
        guard let range = line.range(of: "^\\d+\\s*[-—–]\\s*", options: .regularExpression) else {
            return nil
        }
        let body = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : body
    }

    private static func isCueCardStart(_ body: String) -> Bool {
        let lower = body.lowercased()
        return lower.hasPrefix("describe") || lower.hasPrefix("talk about")
    }

    // MARK: - 第三遍：按分区解析

    /// 逐行累积成题目。
    ///
    /// 单独拆一个类型是因为 cue card 要**攒完才能落地**：题干出现时它的四条提示点和一串追问
    /// 都还没读到，得等下一个编号项或分区标题到来才知道这一张收完了。
    private struct Builder {
        let sourceTitle: String
        let sourceUrl: String

        private(set) var questions: [Question] = []

        private var region: Region = .none
        private var part1Topic: String?
        private var category = ""
        private var cue: PendingCue?
        private var cueSlot: CueSlot = .beforeBullets

        /// 攒到一半的 cue card。
        private struct PendingCue {
            var topic: String
            var prompt: String
            var followups: [String] = []
            var part3: [String] = []
        }

        /// cue card 里此刻读到哪一段了。
        private enum CueSlot {
            /// 题干读完了，还没遇到 `You should say`。
            case beforeBullets
            /// `You should say` 之后的提示点。
            case bullets
            /// `Part3` 之后的追问。
            case part3
        }

        // 下面三个计数不是给日志用的，是给用户看的警告。**不许静默丢内容**：
        // 丢掉的每一类都要有一条说得清「丢了什么、下一步怎么办」的话。
        private var unrecognisedNumbered: [String] = []
        private var orphanLines = 0
        private var sawSectionHeader = false

        init(sourceTitle: String, sourceUrl: String) {
            self.sourceTitle = sourceTitle
            self.sourceUrl = sourceUrl
        }

        mutating func consume(_ line: String) {
            switch PDFQuestionExtractor.classify(line) {
            case .sectionHeader(let newRegion):
                flushCue()
                region = newRegion
                part1Topic = nil
                category = ""
                sawSectionHeader = true

            case .categoryLabel(let name):
                flushCue()
                category = name

            case .youShouldSay:
                cueSlot = .bullets

            case .part3Marker:
                cueSlot = .part3

            case .numbered(let body):
                switch region {
                case .part1:
                    // 极少数情况下编号行本身就是问题（题目自带序号）。以问号结尾就按题目算。
                    if body.hasSuffix("?") {
                        appendPart1(prompt: body)
                    } else {
                        part1Topic = body
                    }
                case .part23:
                    flushCue()
                    if PDFQuestionExtractor.isCueCardStart(body) {
                        cue = PendingCue(topic: category, prompt: body)
                        cueSlot = .beforeBullets
                    } else {
                        unrecognisedNumbered.append(body)
                    }
                case .none:
                    break   // 封面与目录里的编号行，丢掉
                }

            case .text:
                switch region {
                case .part1:
                    guard part1Topic != nil else { orphanLines += 1; break }
                    appendPart1(prompt: line)
                case .part23:
                    guard cue != nil else { orphanLines += 1; break }
                    switch cueSlot {
                    case .bullets: cue?.followups.append(line)
                    case .part3: cue?.part3.append(line)
                    case .beforeBullets: orphanLines += 1
                    }
                case .none:
                    break
                }
            }
        }

        mutating func finish() { flushCue() }

        private mutating func appendPart1(prompt: String) {
            let topic = part1Topic ?? ""
            questions.append(Question(
                id: QuestionBankImporter.questionID(part: 1, topic: topic, prompt: prompt),
                part: 1, topic: topic, prompt: prompt,
                source: sourceTitle, sourceUrl: sourceUrl))
        }

        /// 把攒完的 cue card 落成一道 Part 2 加若干道 Part 3。
        ///
        /// Part 3 追问的 `topic` 用的是**它所属 cue card 的题干**：追问单独拿出来练时
        /// 「你觉得这种品质重要吗」没有上下文就没法答，得知道它跟着哪张卡。
        private mutating func flushCue() {
            guard let finished = cue else { return }
            cue = nil
            cueSlot = .beforeBullets
            questions.append(Question(
                id: QuestionBankImporter.questionID(part: 2, topic: finished.topic,
                                                    prompt: finished.prompt),
                part: 2, topic: finished.topic, prompt: finished.prompt,
                followups: finished.followups,
                source: sourceTitle, sourceUrl: sourceUrl))
            for prompt in finished.part3 {
                questions.append(Question(
                    id: QuestionBankImporter.questionID(part: 3, topic: finished.prompt,
                                                        prompt: prompt),
                    part: 3, topic: finished.prompt, prompt: prompt,
                    source: sourceTitle, sourceUrl: sourceUrl))
            }
        }

        // MARK: - 警告

        /// 每一条都要同时说清「发生了什么」和「下一步做什么」（铁律 6）。
        func warnings(textLineCount: Int) -> [String] {
            var warnings: [String] = []

            if questions.isEmpty {
                warnings.append(
                    "这份 PDF 里没有解析出任何题目（读到 \(textLineCount) 行文字"
                        + (sawSectionHeader
                            ? "，也找到了分区标题，但标题下面没有可识别的题目"
                            : "，但没有找到「Part1 必考题」「Part2 & 3 保留题」这类分区标题")
                        + "）。下一步：确认选的是雅思口语季度题库那份 PDF；"
                        + "若它的排版与常见题库差别很大，可以先把题目整理成 CSV"
                        + "（第一行写 id,part,topic,prompt,followups）再从本页导入。")
                // **这里不能 return。** 下面两条说的正是「到底丢了什么」——
                // 一道题都没提出来时，那恰恰是用户最需要看到的东西，
                // 只给一句「没解析出任何题目」等于把真正的线索扔了（铁律 7）。
            }

            if !unrecognisedNumbered.isEmpty {
                let examples = unrecognisedNumbered.prefix(3).joined(separator: "」「")
                warnings.append(
                    "Part 2/3 区里有 \(unrecognisedNumbered.count) 个编号项不是以 Describe 或 "
                        + "Talk about 开头，没有被当成 cue card，例如「\(examples)」。"
                        + "下一步：到「训练题库」页对照检查这几道题在不在；"
                        + "缺了的话把它们补进一份 CSV 再导入一次，同一道题会被覆盖而不是变成两道。")
            }

            if orphanLines > 0 {
                warnings.append(
                    "有 \(orphanLines) 行文字出现在任何题目之外（分区标题与第一道题之间、"
                        + "或 cue card 题干与 You should say 之间），没有被收进题库。"
                        + "下一步：导入后到「训练题库」页翻一遍，若发现某个话题少了题，"
                        + "把缺的几道补进 CSV 再导入一次。")
            }

            return warnings
        }
    }
}
