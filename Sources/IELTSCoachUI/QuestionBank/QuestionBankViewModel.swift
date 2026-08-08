import Foundation
import IELTSCoachCore
import PDFKit
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

    /// 题库还是「一问一题」旧结构时，摆在这一页上的那句话。已经是新结构就返回 nil。
    ///
    /// **为什么需要它。** 重建模发生在导入那一刻（见 `QuestionBankImporter.merge`），
    /// 而不是打开 App 时自动改用户的数据——悄悄重排他上千道题、连题号一起换掉，
    /// 是把一件他没要求过的事做了，还没法撤销。代价是：不再导入一次的话，
    /// 他的题库就一直停在旧结构上，而旧结构下 Part 1 的一个话题被拆成六道「题」、
    /// Part 3 的一张卡被拆成九道，学习计划会把同一张卡排成九天、每天练一句。
    /// 所以这一页必须主动说一句，并指向这一页上真实存在的那颗导入按钮。
    ///
    /// 判据是「同一个话题下有两道以上的题」（见 `TopicQuestions.legacyShapedCount`），
    /// 不是「题干和话题不一样」——后者会把用户自己用 CSV 加的、一个话题只写一道的题
    /// 也算成旧结构，那句提示就永远消不掉，等于骚扰。
    public var legacyShapeNotice: String? {
        let count = TopicQuestions.legacyShapedCount(in: questions)
        guard count > 0 else { return nil }
        return "你的题库里有 \(count) 道题还是旧结构：同一个话题被拆成了好几道「题」。"
            + "真实考试里一个话题就是一道题，底下那些问句是考官挑着问的参考，不会全问一遍。"
            + "下一步：点这一页最下面的「导入题库…」，把同一份题库文件再选一次——"
            + "重复的会被合并进话题里，一个问句都不会丢，练过的记录也会跟着搬到新的题上。"
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
    /// 这次导入顺手替用户排了一份学习计划时，要告诉他的那句话；没排就是 nil。
    ///
    /// **凭空多出一份计划却不吭声是不行的**：用户会以为是上一次用留下的，
    /// 也不知道去哪儿改周期或重点 Part（见 `PlanBootstrap.notice`）。
    public let planNotice: String?
    /// 这次导入吸收掉了多少道旧结构（一问一题）的题目。
    public let absorbedCount: Int
    /// 因此改写了多少处旧题号引用（练习记录、复训链接、学习计划）。
    public let remappedReferenceCount: Int

    public init(importedCount: Int, totalCount: Int, warnings: [String],
                planNotice: String? = nil,
                absorbedCount: Int = 0, remappedReferenceCount: Int = 0) {
        self.importedCount = importedCount
        self.totalCount = totalCount
        self.warnings = warnings
        self.planNotice = planNotice
        self.absorbedCount = absorbedCount
        self.remappedReferenceCount = remappedReferenceCount
    }

    /// 题库重建模那一句交代。没有吸收任何旧题时返回 nil（绝大多数导入都是这样）。
    ///
    /// **必须说出来。** 用户导入前题库 1265 道、导入后 258 道，中间少掉的一千多道
    /// 没有一句解释的话，他只会认为导入把题库弄坏了——而实际上一个问句都没丢，
    /// 它们变成了话题题下面的参考问句。挂在旧题号上的历史记录也在同一次写盘里搬了家，
    /// 这件事同样得说，否则他会自己去翻训练记录求证。
    public var remodelNotice: String? {
        guard absorbedCount > 0 else { return nil }
        let history = remappedReferenceCount > 0
            ? "你练过的记录已经跟着指到新的题上（改写了 \(remappedReferenceCount) 处题号），"
            : "没有任何练习记录指向被合并的那些题，"
        return "这次顺带把题库改成了「一个话题一道题」：\(absorbedCount) 道旧结构的题"
            + "并进了它们所属的话题，原来的问句一句没丢，成了那道题下面的参考问句"
            + "（练习时考官从中挑几个问，不会全问一遍）。\(history)"
            + "下一步：在这一页上方按 Part 筛一遍，看看新的分组；"
            + "题数变了，学习计划可以到「学习计划」页重新生成一份，练过的进度不会丢。"
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
        // 重建模那一句排在最前，并且**有警告时也照说**：题库总数一次少掉一千多道，
        // 这是用户第一眼看到、也最会误解成「导入把题库弄坏了」的事。
        // 它自带「下一步」，所以说了它就不再接别的「下一步」——
        // 两个互相矛盾的下一步，用户不知道该照哪个做。
        if let remodelNotice {
            guard warnings.isEmpty else {
                return head + remodelNotice
                    + "另外，下面 \(warnings.count) 条警告指出了文件里有问题的行，改好之后可以再导入一次。"
            }
            return head + remodelNotice
        }
        guard warnings.isEmpty else {
            return head + "下面 \(warnings.count) 条警告指出了文件里有问题的行，"
                + "下一步：改好之后可以再导入一次，同一道题会被覆盖而不是变成两道。"
            // ⚠️ 有警告这一支刻意**不**接 planNotice：那时用户该先去改文件，
            // 再堆一段计划说明只会把「有几行没进来」这件更要紧的事挤下去。
            // 计划确实排好了，回首页就看得到，且学习计划页随时能改。
        }
        // 顺手排了计划的话，这句话接在后面——凭空多出一份计划却不吭声，
        // 用户会以为是上一次用留下的（复审第 9 条）。
        if let planNotice { return head + planNotice }
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

/// 界面这一侧的导入门面。**认格式、读文件、分派解析这三步全在
/// `IELTSCoachCore.QuestionBankFile` 里**，这里只补界面独有的那一件事：
/// `NSOpenPanel` 要的 `UTType` 清单。
///
/// ## 为什么搬去了 Core
///
/// 这段逻辑从前只住在界面模块，而命令行（`Sources/coach/QuestionsCommand.swift`）
/// 自己写了一份「不是 .json 就当 CSV」。两份实现的差别已经真实咬过一次：
/// Task 8 给界面加了 PDF，命令行还在按 CSV 解析 PDF。
/// 搬进 Core 之后两条路调的是同一个函数，**再也没有「两边不一样」的余地**——
/// 这一点由 `QuestionBankImportParityTests` 守着。
public enum QuestionBankImport {
    /// 题库格式。真源在 Core（`QuestionBankFormat`），这里只是个旧名字。
    public typealias Format = QuestionBankFormat

    /// 文件面板放行的扩展名。
    public static var supportedExtensions: [String] { QuestionBankFile.supportedExtensions }

    /// 文件面板放行的类型。视图直接把它交给 `NSOpenPanel.allowedContentTypes`。
    public static var allowedContentTypes: [UTType] { Format.allCases.map(\.contentType) }

    /// 写给用户看的扩展名清单，如「.csv、.json、.pdf」。
    public static var supportedExtensionList: String { QuestionBankFile.supportedExtensionList }

    /// 写给用户看的、带一句说明的格式清单。
    public static var supportedFormatList: String { QuestionBankFile.supportedFormatList }

    /// 按扩展名认格式。**不认识的扩展名必须报错，不能默默当成 CSV。**
    public static func format(ofFileName fileName: String) throws -> Format {
        try QuestionBankFile.format(ofFileName: fileName)
    }

    /// 题库来源的名字：文件名去掉扩展名。
    public static func sourceTitle(ofFileName fileName: String) -> String {
        QuestionBankFile.sourceTitle(ofFileName: fileName)
    }

    /// 按扩展名选导入器。
    public static func parse(fileName: String, text: String) throws -> ImportResult {
        try QuestionBankFile.parse(fileName: fileName, text: text)
    }

    /// **用户选中一个文件之后，从这里到题目只有这一条路。**
    ///
    /// `pdfText` 默认走 PDFKit，测试里注入假实现——单元测试里造不出一份真 PDF。
    public static func importFile(
        at url: URL,
        pdfText: QuestionBankFile.PDFTextExtractor = QuestionBankFileReader.pdfPlainText
    ) throws -> ImportResult {
        try QuestionBankFile.importFile(at: url, pdfText: pdfText)
    }

    /// 把导入过程中的任何失败翻译成用户能照做的一句话。
    /// `AppState.describeLoadFailure` 已经为「读状态」做过同样的事，这里是导入这一侧。
    public static func describeFailure(_ error: any Error, fileName: String) -> String {
        QuestionBankFile.describeFailure(error, fileName: fileName)
    }
}

/// 文件面板放行的类型。
///
/// **写成系统常量，不用 `UTType(filenameExtension:)` 去查。**
/// 那个构造器查不到时返回 nil，`compactMap` 会把这一项静默丢掉（铁律 7）；
/// 全丢掉时 `allowedContentTypes` 变成空数组，而空数组对 `NSOpenPanel`
/// 的意思不是「什么都不放行」，恰恰是「放行一切文件类型」。
extension QuestionBankFormat {
    public var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .pdf: return .pdf
        }
    }
}

/// 把用户选中的那个文件读成纯文本。规则在 `QuestionBankFile.text(at:format:pdfText:)`；
/// 这里只提供界面这一侧的默认 PDF 取文实现。
///
/// **PDFKit 只能在 Core 之外出现**（铁律 7：Core 只依赖 Foundation），
/// 所以「怎么把 PDF 抽成文字」是一个注入进去的闭包。
public enum QuestionBankFileReader {
    /// 默认实现：PDFKit。命令行那一侧有它自己的一份（`Sources/coach/QuestionsCommand.swift`），
    /// 两份都只是「把 PDF 变成字符串」这一步，规则本身共用 Core 那一份。
    public static func pdfPlainText(at url: URL) -> String? { PDFDocument(url: url)?.string }

    public static func text(at url: URL, format: QuestionBankFormat,
                            pdfText: QuestionBankFile.PDFTextExtractor = pdfPlainText) throws -> String {
        try QuestionBankFile.text(at: url, format: format, pdfText: pdfText)
    }
}
