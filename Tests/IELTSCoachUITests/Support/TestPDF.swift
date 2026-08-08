import CoreGraphics
import CoreText
import Foundation

/// 现场生成一份**真** PDF，供「真的碰 PDFKit 的那一行」用。
///
/// ## 为什么需要它
///
/// 全项目唯一碰 PDFKit 的是 `QuestionBankFileReader.pdfPlainText`（`PDFDocument(url:)?.string`）。
/// 在这之前，所有 PDF 测试都靠注入假的取文字闭包，那一行本身一个测试都没有——
/// 复审实测过三个突变，全量测试一条都不红：
///
/// 1. `pdfPlainText` 改成 `{ _ = url; return nil }`（根本不调 PDFKit）；
/// 2. `QuestionBankImport.importFile` 的默认参数换成 `{ _ in nil }`；
/// 3. `QuestionBankFileReader.text` 的默认参数换成 `{ _ in nil }`。
///
/// 三处任何一处坏掉，用户选任何一份真实 PDF 都会被告知「这多半是扫描件」，
/// 而那份 PDF 明明是文字版——用户照着提示去做文字识别，白忙一场。
///
/// 补上之后还漏了第四种，因为这里**只会画一页**：
///
/// 4. `pdfPlainText` 改成 `PDFDocument(url:)?.page(at: 0)?.string`（只读第一页）。
///
/// 只有一页的样本里「读第一页」与「读全文」是同一件事，所以那几条守卫问的都是
/// 「有没有文字出来」，没人问「是不是全都出来了」。见 `data(pages:)`。
///
/// ## 为什么不用仓库里那份真实 PDF
///
/// 仓库根目录确实有用户那份 81 页的题库 PDF，但它在 `.gitignore` 里、不在版本控制中：
/// 换台机器、换个克隆目录就没有了。测试**不能依赖它存在**，
/// 否则这几条守卫会在别的机器上悄悄变成「跳过」——那又是一种空转。
///
/// 所以这里用 CoreGraphics + CoreText 现场画一份含已知文字的极小 PDF：
/// 内容是我们自己写进去的，读出来是什么就该等于什么，断言有明确依据。
///
/// ## 边界
///
/// 它画的是最规整的几页文字，代表不了真实题库那种双栏、带页眉页脚的排版；
/// 那部分归人工拿真实 PDF 验收（导入后的题数、题干长相）。
/// 它能守住的是「取文字这条路还通不通」「每一页的文字是不是都出来了」——
/// 那正是已经被证明能悄悄坏掉的两处。
enum TestPDF {

    enum Failure: Error, CustomStringConvertible {
        case cannotCreateConsumer
        case cannotCreateContext

        var description: String {
            switch self {
            case .cannotCreateConsumer:
                return "造不出 CGDataConsumer，测试用的 PDF 生成不了，"
                    + "这一组守卫会失去依据。下一步：确认测试跑在 macOS 上（CoreGraphics 可用）。"
            case .cannotCreateContext:
                return "造不出 PDF 用的 CGContext，测试用的 PDF 生成不了。"
                    + "下一步：同上，确认 CoreGraphics 可用。"
            }
        }
    }

    /// 单页：每行画一行文字，返回一份真 PDF 的字节。
    ///
    /// **只画一页的样本守不住「是不是全都出来了」。** 见 `data(pages:)` 的说明——
    /// 需要多页的地方一律用那一个。
    static func data(lines: [String], fontSize: CGFloat = 14) throws -> Data {
        try data(pages: [lines], fontSize: fontSize)
    }

    /// 多页：每个内层数组画成一页，返回一份真 PDF 的字节。
    ///
    /// ## 为什么必须能画多页
    ///
    /// 之前这里只有 `data(lines:)`，从头到尾只 `beginPDFPage` 一次，
    /// 于是四条「真的碰 PDFKit」的守卫问的都是「有没有文字出来」，
    /// **没人问「是不是全都出来了」**。实测：把 `QuestionBankFileReader.pdfPlainText` 的
    /// `PDFDocument(url: url)?.string` 改成 `PDFDocument(url: url)?.page(at: 0)?.string`
    /// （只读第一页），全量测试一条都不红。
    ///
    /// 而用户那份题库是 **81 页**。只读第一页的后果是静默丢题：导入成功、没有任何警告、
    /// 只进来第一页那几道，用户要翻到「训练题库」页数题才可能发现（铁律 5）。
    ///
    /// 所以拿它画样本时，**把断言要比的内容跨到第二页去**——只读第一页时那几行会当场消失。
    ///
    /// ## 页与页之间怎么接
    ///
    /// PDFKit 的 `PDFDocument.string` 把各页的文字用 `\n` 接起来（实测），
    /// 所以 `meaningfulLines(of:)` 切出来的就是各页行的拼接，跟画进去的顺序一致。
    ///
    /// 字体用 Helvetica，中文靠 CoreText 的字体回退（题库里 Part 2 的话题标签、
    /// 「Part1 必 考 题」这类分区标题都是中文，抽不出中文的话这组测试就名不副实了）。
    static func data(pages: [[String]], fontSize: CGFloat = 14) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw Failure.cannotCreateConsumer
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Failure.cannotCreateContext
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        for page in pages {
            context.beginPDFPage(nil)
            var baseline = mediaBox.height - 72
            for line in page {
                let attributed = NSAttributedString(string: line, attributes: [.font: font])
                let typeset = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: 54, y: baseline)
                CTLineDraw(typeset, context)
                baseline -= fontSize * 1.6
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// 一份「有页面、有内容、但一个字都没有」的 PDF——扫描件的形状（整页都是图）。
    ///
    /// 用它守「真实的扫描件会不会被正确解释」，而不是靠注入一个返回 nil 的假闭包：
    /// PDFKit 对这种文件返回的是**空串**而不是 nil，这个区别只有拿真文件才试得出来。
    static func imageOnlyPageData() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw Failure.cannotCreateConsumer
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Failure.cannotCreateContext
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 100, y: 100, width: 300, height: 300))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// 把 PDFKit 抽出来的整段文字切成「去掉首尾空白、丢掉空行」的若干行。
    ///
    /// 断言前做这一步，是为了让比较盯住内容本身：行末有没有多一个空格、
    /// 换行用的是 `\n` 还是 `\r\n`，都不该让这组测试红——那些不是它要守的东西。
    static func meaningfulLines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
