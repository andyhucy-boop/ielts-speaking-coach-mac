import Foundation
import IELTSCoachCore
import UniformTypeIdentifiers

/// 把题库变成界面要显示的样子：按 Part 筛、按话题分组、数一数练过几道。
///
/// 单独拆出来是因为 `View` 几乎无法单元测试，而这段映射完全可测。
public struct QuestionBankViewModel: Sendable {
    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    public func filtered(part: Int?) -> [Question] {
        guard let part else { return questions }
        return questions.filter { $0.part == part }
    }

    /// 按话题分组，话题按名称排序，组内保持题库原有顺序。
    ///
    /// **话题必须排序，组内必须不排序。** 前者：不排序的话，同一份题库每次打开
    /// 话题的先后都跟着导入顺序走，用户找不到上次看到的那一组。
    /// 后者：组内顺序就是题库里的顺序，那是用户自己排的，不该被我们重排。
    public func groupedByTopic(part: Int?) -> [(topic: String, questions: [Question])] {
        let subset = filtered(part: part)
        var order: [String] = []
        var buckets: [String: [Question]] = [:]
        for question in subset {
            if buckets[question.topic] == nil { order.append(question.topic) }
            buckets[question.topic, default: []].append(question)
        }
        return order.sorted().map { ($0, buckets[$0] ?? []) }
    }

    public var counts: (total: Int, practiced: Int) {
        (questions.count, questions.filter { $0.status == "practiced" }.count)
    }
}

/// 一次导入的结果，界面据此给用户一句交代。
public struct QuestionBankImportOutcome: Equatable, Sendable {
    /// 这个文件里解析出多少道题。
    public let importedCount: Int
    /// 合并之后题库共多少道题。
    public let totalCount: Int
    /// 导入器给出的逐条警告（哪一行有问题、该怎么改）。
    public let warnings: [String]

    public init(importedCount: Int, totalCount: Int, warnings: [String]) {
        self.importedCount = importedCount
        self.totalCount = totalCount
        self.warnings = warnings
    }

    /// 导入完成后显示的那句话。铁律 6：同时说清「发生了什么」和「下一步做什么」。
    ///
    /// **一道题都没进来时不能说成一次成功的导入。** 「已导入 0 道题 ✅」会让用户
    /// 以为是自己的题库本来就空，而真正的原因（某一行缺 id、表头写错）就在下面那堆警告里，
    /// 他却没有被告知要去看。
    public var summary: String {
        guard importedCount > 0 else {
            let tail = warnings.isEmpty
                ? "下一步：确认这份文件确实是题库 CSV（第一行要有 id,part,topic,prompt 四列）"
                    + "或本工具导出的题库 JSON，改好后再导入一次。"
                : "下一步：照下面 \(warnings.count) 条警告把文件改好，再导入一次。"
            return "这个文件里没有解析出任何题目，题库没有变化（现共 \(totalCount) 道题）。" + tail
        }
        let head = "已导入 \(importedCount) 道题，题库现共 \(totalCount) 道题。"
        guard warnings.isEmpty else {
            return head + "下面 \(warnings.count) 条警告指出了文件里有问题的行，"
                + "下一步：改好之后可以再导入一次，同一道题会被覆盖而不是变成两道。"
        }
        return head + "下一步：到「今日训练」页开始练习。"
    }
}

/// 一次导入之后要给用户看的那张交代：语气、标题、正文、逐条警告。
///
/// **它必须弹出来，不能只画在页面上。** 触发导入的按钮在这一页的最底下，而题库有几十个
/// 话题时页面远超一屏。结果画在页面里，真实路径就成了「用户滚到底 → 点导入 → 选完文件 →
/// 面板关闭 → 结果出现在屏幕外的页面顶端」，用户什么也看不到——
/// 而计划要求逐条摆出来的那些警告（「第 7 行缺 id，那道题没进来」）恰恰是不看就再也不会知道的。
/// 呈现方式由 `QuestionBankView` 的 `.sheet` 负责，`QuestionBankViewTests` 扫源码守着。
///
/// 拆成一个独立类型是为了可测：语气选错（一道题没进来却给绿色对勾）、
/// 警告被吞掉，留在 `View` 里就一条测试都写不了。
public struct QuestionBankImportFeedback: Identifiable, Sendable {
    /// 这次导入到底算什么。**「一道题都没进来」单独一档**：
    /// 它既不是成功（不能给绿色对勾），也不是失败（文件读到了、也解析了）。
    public enum Tone: Equatable, Sendable {
        /// 真的导进去了。
        case done
        /// 文件读到了、解析了，但一道题都没进来。
        case nothing
        /// 根本没读成或没解析成。
        case failed
    }

    public let id = UUID()
    public let tone: Tone
    public let title: String
    public let message: String
    public let warnings: [String]

    public init(outcome: QuestionBankImportOutcome) {
        let cameIn = outcome.importedCount > 0
        tone = cameIn ? .done : .nothing
        title = cameIn ? "导入完成" : "这次一道题都没有导入"
        message = outcome.summary
        warnings = outcome.warnings
    }

    public init(failureMessage: String) {
        tone = .failed
        title = "导入没有成功"
        message = failureMessage
        warnings = []
    }
}

/// 从文件到 `ImportResult` 这一段的纯逻辑：挑导入器、把失败翻译成人话。
///
/// 与 `QuestionBankView` 分开是为了可测——`NSOpenPanel` 没法在单元测试里跑，
/// 但「哪个扩展名走哪个导入器」「失败了跟用户怎么说」这两件事完全可测，
/// 而它们恰恰是最容易出错又最容易被漏掉的部分。
public enum QuestionBankImport {
    /// 这一页认得的题库格式。**这个枚举是唯一真源。**
    ///
    /// 文件面板放行什么（`allowedContentTypes`）、`parse` 认什么、拒绝文案里列的是哪几种、
    /// 页面上那几句「支持 …」，全部从这里推出来。
    ///
    /// 之前这份清单在六处各写各的字面量（`supportedExtensions`、`parse` 的分派、拒绝文案、
    /// 文件面板的 message、空状态的提示、导入卡片的副标题），只是**恰好**一致，
    /// 没有任何构造上或测试上的耦合：把 `supportedExtensions` 改成 `["csv", "json", "pdf"]`，
    /// 面板就会放行 PDF、`parse` 抛错、拒绝文案还在说「只认 .csv 和 .json」——
    /// 而全部 272 条测试无一变红。而 Task 8 要动的恰恰就是这一行。
    ///
    /// 现在加一个 case，下面三个 `switch` 立刻不完备，**编译就过不去**；
    /// 硬填上去的话，`testEveryFormatTheFilePanelLetsThroughIsActuallyParsed` 会红
    /// （没人给这种格式补样本 = 没人验证过 `parse` 真的认它）。
    public enum Format: String, CaseIterable, Sendable {
        case csv
        case json

        /// 文件名扩展名，一律小写（`parse` 会把用户的文件名先转小写再匹配，
        /// 从 Excel 导出的常是 `.CSV`）。
        public var fileExtension: String { rawValue }

        /// 文件面板放行的类型。
        ///
        /// **写成系统常量，不用 `UTType(filenameExtension:)` 去查。**
        /// 那个构造器查不到时返回 nil，`compactMap` 会把这一项静默丢掉（铁律 7）；
        /// 全丢掉时 `allowedContentTypes` 变成空数组，而空数组对 `NSOpenPanel`
        /// 的意思不是「什么都不放行」，恰恰是「放行一切文件类型」。
        public var contentType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            case .json: return .json
            }
        }

        /// 写给用户看的说明，进「支持 …」那几句文案。
        public var displayName: String {
            switch self {
            case .csv: return "CSV（第一行 id,part,topic,prompt）"
            case .json: return "本工具导出的 JSON"
            }
        }

        /// 这种格式用哪个导入器。**新增 case 时这里编不过，这是故意的**——
        /// 命令行那份实现（`Sources/coach/QuestionsCommand.swift`）走的是
        /// 「不是 .json 就当 CSV」，在终端里尚可（路径是用户自己敲的），
        /// 放到界面上就不行：一份 PDF 被当成 CSV 解析，会把二进制垃圾当成题目
        /// 灌进题库，而且一声不吭。
        func makeImportResult(text: String, sourceTitle: String) throws -> ImportResult {
            switch self {
            case .csv: return try QuestionBankImporter.importCSV(text, sourceTitle: sourceTitle)
            case .json: return try QuestionBankImporter.importJSON(text, sourceTitle: sourceTitle)
            }
        }
    }

    /// 文件面板放行的扩展名。
    public static var supportedExtensions: [String] { Format.allCases.map(\.fileExtension) }

    /// 文件面板放行的类型。视图直接把它交给 `NSOpenPanel.allowedContentTypes`。
    public static var allowedContentTypes: [UTType] { Format.allCases.map(\.contentType) }

    /// 写给用户看的扩展名清单，如「.csv、.json」。
    public static var supportedExtensionList: String {
        Format.allCases.map { ".\($0.fileExtension)" }.joined(separator: "、")
    }

    /// 写给用户看的、带一句说明的格式清单，
    /// 如「CSV（第一行 id,part,topic,prompt）、本工具导出的 JSON」。
    public static var supportedFormatList: String {
        Format.allCases.map(\.displayName).joined(separator: "、")
    }

    /// 按扩展名选导入器。**不认识的扩展名必须报错，不能默默当成 CSV。**
    public static func parse(fileName: String, text: String) throws -> ImportResult {
        let name = fileName as NSString
        let ext = name.pathExtension.lowercased()
        let title = name.deletingPathExtension
        guard let format = Format(rawValue: ext) else {
            // 没有扩展名时不能拼成「扩展名是「.」」——那句话读起来像程序自己出了错。
            let what = ext.isEmpty ? "没有扩展名" : "扩展名是「.\(ext)」"
            throw CoachError.questionBankInvalid(
                "「\(fileName)」\(what)，本页只认 \(supportedExtensionList) "
                    + "这 \(Format.allCases.count) 种题库文件。"
                    + "下一步：把题库另存为 CSV（第一行是 id,part,topic,prompt,followups）再导入。")
        }
        return try format.makeImportResult(text: text, sourceTitle: title)
    }

    /// 把导入过程中的任何失败翻译成用户能照做的一句话。
    ///
    /// `CoachError` 的文案本来就按铁律 6 写好了，原样透传；
    /// 而磁盘满、文件被占、编码不对这类失败抛出来的是系统 `NSError`——
    /// 它只说发生了什么，不说下一步，措辞还未必是中文。
    /// `AppState.describeLoadFailure` 已经为「读状态」做过同样的事，这里是导入这一侧。
    public static func describeFailure(_ error: any Error, fileName: String) -> String {
        let detail = error.localizedDescription
        if detail.contains("下一步") { return detail }
        return "导入「\(fileName)」时失败：\(detail)。"
            + "下一步：确认这个文件没有被 Excel 之类的程序占用、磁盘还有剩余空间，然后重试；"
            + "若反复失败，把文件另存一份新的再导入。"
    }
}
