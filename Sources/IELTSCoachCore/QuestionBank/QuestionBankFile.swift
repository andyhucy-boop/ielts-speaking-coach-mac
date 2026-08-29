import Foundation

/// 一份题库文件的格式。**这个枚举是全工程唯一的真源。**
///
/// 文件面板放行什么、`parse` 认什么、拒绝文案里列的是哪几种、页面上那几句「支持 …」，
/// 以及命令行 `coach questions import` 认什么，全部从这里推出来。
///
/// ## 它为什么在 Core 而不在界面模块里
///
/// 从前这段逻辑只住在 `IELTSCoachUI`，而命令行自己写了一份「不是 .json 就当 CSV」。
/// 两份实现的差别不是理论问题，已经真实咬过一次：Task 8 给界面加了 PDF，
/// 命令行还在按 CSV 解析 PDF——一份二进制被当成表格灌进题库，一声不吭。
/// 反过来也一样：命令行的 `default:` 分支意味着 `coach questions import 讲义.docx`
/// 会走进 CSV 解析器，然后抛一句「题库表头缺少必需列「id」」——
/// 用户手上那份根本不是 CSV，这句话把他指向一个不存在的问题。
///
/// 所以格式判定、读文件、分派解析这三步收在 Core 里，界面与命令行都只调它。
/// **PDFKit 不在这里**：Core 只许依赖 Foundation（铁律 7），
/// 所以「把 PDF 抽成纯文本」是一个注入进来的闭包，两个调用方各自传自己的实现。
public enum QuestionBankFormat: String, CaseIterable, Sendable {
    case csv
    case json
    /// 用户手上的季度题库就是这个：由调用方用 PDFKit 抽出纯文本，
    /// 再交给 `PDFQuestionExtractor`（它只吃字符串，所以留在 Core 里）。
    case pdf

    /// 文件名扩展名，一律小写（判定时会把用户的文件名先转小写，
    /// 从 Excel 导出的常是 `.CSV`）。
    public var fileExtension: String { rawValue }

    /// 写给用户看的说明，进「支持 …」那几句文案。
    public var displayName: String {
        switch self {
        case .csv: return "CSV（第一行 id,part,topic,prompt）"
        case .json: return "本工具导出的 JSON"
        case .pdf: return "PDF（雅思口语季度题库原文，须是文字版而非扫描件）"
        }
    }

    /// 这种格式用哪个导入器。**新增 case 时这里编不过，这是故意的。**
    public func makeImportResult(text: String, sourceTitle: String) throws -> ImportResult {
        switch self {
        case .csv: return try QuestionBankImporter.importCSV(text, sourceTitle: sourceTitle)
        case .json: return try QuestionBankImporter.importJSON(text, sourceTitle: sourceTitle)
        case .pdf:
            // 这里的 text 已经是调用方用 PDFKit 抽出来的纯文本了。
            return try PDFQuestionExtractor.extract(
                plainText: text, sourceTitle: sourceTitle, sourceUrl: "")
        }
    }
}

/// 从「用户指定的一个文件」到「一批题目」的**唯一一条路**。界面与命令行都只调它。
public enum QuestionBankFile {

    /// 把一份 PDF 抽成纯文本。Core 里没有实现——PDFKit 不许进 Core（铁律 7）。
    public typealias PDFTextExtractor = (URL) -> String?

    // MARK: - 清单（写给用户看的那几句话全从这里推）

    /// 认得的扩展名。
    public static var supportedExtensions: [String] {
        QuestionBankFormat.allCases.map(\.fileExtension)
    }

    /// 写给用户看的扩展名清单，如「.csv、.json、.pdf」。
    public static var supportedExtensionList: String {
        QuestionBankFormat.allCases.map { ".\($0.fileExtension)" }.joined(separator: "、")
    }

    /// 写给用户看的、带一句说明的格式清单。
    public static var supportedFormatList: String {
        QuestionBankFormat.allCases.map(\.displayName).joined(separator: "、")
    }

    // MARK: - 认格式

    /// 按扩展名认格式。**不认识的扩展名必须报错，不能默默当成 CSV。**
    public static func format(ofFileName fileName: String) throws -> QuestionBankFormat {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let format = QuestionBankFormat(rawValue: ext) else {
            // 没有扩展名时不能拼成「扩展名是「.」」——那句话读起来像程序自己出了错。
            let what = ext.isEmpty ? "没有扩展名" : "扩展名是「.\(ext)」"
            throw CoachError.questionBankInvalid(
                "「\(fileName)」\(what)，本工具只认 \(supportedExtensionList) "
                    + "这 \(QuestionBankFormat.allCases.count) 种题库文件。"
                    + "下一步：把题库另存为 CSV（第一行是 id,part,topic,prompt,followups）再导入；"
                    + "若你手上是季度题库的原文 PDF，直接选那份 PDF 就行。")
        }
        return format
    }

    /// 题库来源的名字：文件名去掉扩展名。练习记录里靠它看出题是从哪份文件来的。
    public static func sourceTitle(ofFileName fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 按扩展名选导入器（文本已经在手上时用它）。
    public static func parse(fileName: String, text: String) throws -> ImportResult {
        try format(ofFileName: fileName)
            .makeImportResult(text: text, sourceTitle: sourceTitle(ofFileName: fileName))
    }

    // MARK: - 读文件

    /// 把用户选中的那个文件读成 `parse` 要的纯文本。
    ///
    /// **单独一步是因为 PDF 不是文本文件。** CSV / JSON 用 UTF-8 读，PDF 交给
    /// `pdfText`——拿 PDF 去按 UTF-8 读必然失败，而失败之后那句
    /// 「用文本编辑另存为 UTF-8」对一份 PDF 是**做不到**的事，
    /// 用户会照着去试然后卡住（铁律 6）。
    public static func text(at url: URL, format: QuestionBankFormat,
                            pdfText: PDFTextExtractor) throws -> String {
        let fileName = url.lastPathComponent
        switch format {
        case .csv, .json:
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw CoachError.questionBankInvalid(
                    "读不到「\(fileName)」的内容，它多半不是 UTF-8 编码的文本"
                        + "（系统说：\(error.localizedDescription)）。"
                        + "下一步：用「文本编辑」打开它，选「文件 › 存储为」并把编码设成 UTF-8，"
                        + "再回来导入一次。")
            }
        case .pdf:
            // 空串与 nil 要一视同仁：PDFKit 对「有页面但一个字都没有」的扫描件返回的是空串，
            // 放它过去只会在下一步变成一句莫名其妙的「没有解析出任何题目」，
            // 而真正的原因没人告诉用户。
            let text = pdfText(url) ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoachError.questionBankInvalid(
                    "「\(fileName)」里没有可提取的文字，它多半是扫描件（整页都是图片）。"
                        + "下一步：换一份文字版 PDF；"
                        + "或者用系统「预览」打开它，全选（⌘A）之后看看能不能复制出文字："
                        + "复制出来是乱码或者一个字都粘不出来，就说明确实是扫描件，"
                        + "需要先做一次文字识别，"
                        + "再把题目整理成 CSV（第一行 id,part,topic,prompt,followups）导入。")
            }
            return text
        }
    }

    // MARK: - 一条路走到底

    /// **用户指定一个文件之后，从这里到题目只有这一条路。**
    ///
    /// 认格式 → 取文字 → 解析。三步的顺序不能换：PDF 不能按 UTF-8 文本读，
    /// 而「这是不是 PDF」只有认完格式才知道。
    ///
    /// 收成一个函数，是因为三步各自都有测试、唯独「三步有没有真的串起来」测不到——
    /// 而那恰恰是决定用户选完 PDF 之后到底有没有题的那一根线。
    public static func importFile(at url: URL,
                                  pdfText: PDFTextExtractor) throws -> ImportResult {
        let fileName = url.lastPathComponent
        let format = try format(ofFileName: fileName)
        let text = try text(at: url, format: format, pdfText: pdfText)
        return try format.makeImportResult(text: text,
                                           sourceTitle: sourceTitle(ofFileName: fileName))
    }

    // MARK: - 失败翻译

    /// 把导入过程中的任何失败翻译成用户能照做的一句话。
    ///
    /// `CoachError` 的文案本来就按铁律 6 写好了，原样透传；
    /// 而磁盘满、文件被占、编码不对这类失败抛出来的是系统 `NSError`——
    /// 它只说发生了什么，不说下一步，措辞还未必是中文。
    public static func describeFailure(_ error: any Error, fileName: String) -> String {
        let detail = error.localizedDescription
        if detail.contains("下一步") { return detail }
        return "导入「\(fileName)」时失败：\(detail)。"
            + "下一步：确认这个文件没有被 Excel 之类的程序占用、磁盘还有剩余空间，然后重试；"
            + "若反复失败，把文件另存一份新的再导入。"
    }
}
