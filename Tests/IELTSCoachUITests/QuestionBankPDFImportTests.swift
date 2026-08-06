import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 用户手上的季度题库是 PDF（仓库根目录那份 81 页的文件）。
/// 这一组守的是「选中一份 PDF 之后到底发生了什么」这条路上最容易断的三处。
final class QuestionBankPDFImportTests: XCTestCase {

    /// 照抄真实 PDF 抽出来的片段（含一处折行的 cue card 题干），**分成两页**。
    ///
    /// 页边界刻意切在 cue card 的提示点与它的 `Part3` 追问之间：
    /// 用户那份题库有 81 页，而「取文字那一步只读第一页」是一个能悄悄坏掉的形状——
    /// 实测把 `QuestionBankFileReader.pdfPlainText` 里的 `PDFDocument(url: url)?.string`
    /// 改成 `PDFDocument(url: url)?.page(at: 0)?.string`，在补这一版之前全量测试一条不红，
    /// 而用户会得到一份「导入成功、没有警告、只有第一页那几道题」的题库（铁律 5）。
    /// 切在这儿，只读第一页时第 3 条 prompt 当场消失，下面逐条比 prompt 的断言立刻红。
    private static let pdfPages: [[String]] = [
        ["Part 1 T opics",
         "Part1 必 考 题",
         "1-Study and work",
         "Do you work or are you a student?",
         "Part2 & 3 保 留 题",
         "人物",
         "1-Describe one of your friends who learned a skill from someone",
         "(not a teacher)",
         "You should say",
         "Who he/she is"],
        ["Part3",
         "Is it necessary to continue learning after finishing formal education?"]
    ]

    /// 同一份内容的纯文本形态（注入假闭包的那几条用它）。
    /// **从 `pdfPages` 拼出来，不另抄一份**：两处各写各的话，改了一处忘了另一处，
    /// 「真 PDF 那条路」和「假闭包那条路」比的就不再是同一份样本了。
    private static let pdfPlainText = pdfPages.flatMap { $0 }.joined(separator: "\n")

    // MARK: - 分派

    /// PDF 必须走 `PDFQuestionExtractor`。
    ///
    /// 走错的两种后果都很难看：被 `parse` 拒掉，用户白选一趟文件；
    /// 被当成 CSV，则整份 PDF 的文字会被塞成一堆没有 id 的行，一声不吭地污染题库。
    func testPDFGoesToThePDFExtractorInsteadOfBeingRejectedOrTreatedAsCSV() throws {
        let result = try QuestionBankImport.parse(fileName: "季度题库.pdf", text: Self.pdfPlainText)
        XCTAssertEqual(result.questions.filter { $0.part == 1 }.count, 1)
        XCTAssertEqual(result.questions.filter { $0.part == 2 }.count, 1)
        XCTAssertEqual(result.questions.filter { $0.part == 3 }.count, 1)
        XCTAssertEqual(result.source.title, "季度题库",
                       "题库来源要用文件名（去掉扩展名），否则看不出题是从哪份文件来的")
    }

    // MARK: - 三步真的串起来了吗

    /// **认格式 → 取文字 → 解析，这三步各自都有测试，唯独「串没串起来」原先一条都没有。**
    /// 而那正是决定用户选中 PDF 之后到底有没有题的那一根线：把这条路上取文字那一步换回
    /// `String(contentsOf:encoding:.utf8)`（本次改动之前的读法），真实 PDF 必然读不出来、
    /// 功能整个废掉——而在补这条测试之前，那样改一条测试都不红。
    ///
    /// 所以三步收进 `QuestionBankImport.importFile(at:pdfText:)`，界面只调它，
    /// 这条测试从这一头进、断言另一头出来的是 `PDFQuestionExtractor` 的产物。
    ///
    /// 文件内容刻意写成非法 UTF-8（0xFF）：谁把取文字那一步换成按文本读，这里立刻抛错。
    func testChoosingAPDFRunsFormatDetectionTextExtractionAndParsingAsOnePath() throws {
        let url = try makeTemporaryFile(named: "季度题库.pdf",
                                        bytes: Data([0x25, 0x50, 0x44, 0x46, 0xFF, 0xFE, 0x00]))
        let result = try QuestionBankImport.importFile(at: url,
                                                      pdfText: { _ in Self.pdfPlainText })

        // 逐条比 prompt，不只比条数：CSV 导入器不可能产出「(not a teacher)」这种
        // 折行合并后的题干，所以这份列表本身就证明走的是 PDFQuestionExtractor。
        XCTAssertEqual(result.questions.map(\.prompt), [
            "Do you work or are you a student?",
            "Describe one of your friends who learned a skill from someone (not a teacher)",
            "Is it necessary to continue learning after finishing formal education?"
        ], "PDF 那条路没有走通，或者中途换了导入器")
        XCTAssertEqual(result.questions.map(\.part), [1, 2, 3])
        XCTAssertEqual(result.source.title, "季度题库",
                       "来源标题要从文件名（去掉扩展名）来，否则看不出题是从哪份文件来的")
    }

    /// 反过来的一半：同一个入口喂一份 CSV，仍走 CSV 导入器、仍读文件本身。
    /// 只测 PDF 的话，把 `importFile` 写成「一律当 PDF」也能全绿。
    func testTheSameEntryPointStillImportsACSVFromTheFileItself() throws {
        let csv = "id,part,topic,prompt\np1-1,1,Home,Do you live in a house or a flat?"
        let url = try makeTemporaryFile(named: "季度题库.csv", bytes: Data(csv.utf8))
        let result = try QuestionBankImport.importFile(
            at: url, pdfText: { _ in "这段绝不该被用到" })
        XCTAssertEqual(result.questions.map(\.prompt), ["Do you live in a house or a flat?"])
        XCTAssertEqual(result.source.title, "季度题库")
    }

    /// 认不出的扩展名要在这个入口上就被拒掉，而且拒绝的话要能照做（铁律 6）。
    func testAnUnsupportedExtensionIsRejectedAtThisEntryPoint() throws {
        let url = try makeTemporaryFile(named: "季度题库.docx", bytes: Data("x".utf8))
        XCTAssertThrowsError(
            try QuestionBankImport.importFile(at: url, pdfText: { _ in nil })
        ) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("季度题库.docx"), message)
            XCTAssertTrue(message.contains("下一步"), message)
        }
    }

    // MARK: - PDF 的文字从哪儿来

    /// **PDF 不是文本文件。** 用 `String(contentsOf:encoding:.utf8)` 读它必然失败，
    /// 而失败之后那句「另存为 UTF-8 再导入」对一份 PDF 是完全做不到的事——
    /// 用户会照着去「文本编辑」里试，然后卡在那儿。
    func testPDFTextComesFromPDFKitInsteadOfReadingTheFileAsUTF8() throws {
        // 0xFF 在 UTF-8 里永远非法：这份内容按文本读一定会抛错。
        let url = try makeTemporaryFile(named: "季度题库.pdf",
                                        bytes: Data([0x25, 0x50, 0x44, 0x46, 0xFF, 0xFE, 0x00]))
        let text = try QuestionBankFileReader.text(at: url, format: .pdf,
                                                   pdfText: { _ in "Part1 必 考 题" })
        XCTAssertEqual(text, "Part1 必 考 题",
                       "PDF 的文字必须由 PDFKit 取，不能拿去当 UTF-8 文本读")
    }

    /// 扫描件（整页都是图片）取不出文字。这时要说清它是扫描件、下一步能做什么，
    /// 不能报成编码问题（铁律 6、7）。
    func testAScannedPDFIsExplainedAsSuchInsteadOfAsAnEncodingProblem() throws {
        // 文件名里刻意不出现「扫描」二字，否则下面那条断言可能只是扫到了回显的文件名。
        let url = try makeTemporaryFile(named: "季度题库.pdf", bytes: Data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertThrowsError(
            try QuestionBankFileReader.text(at: url, format: .pdf, pdfText: { _ in nil })
        ) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("扫描件"),
                          "取不出文字最常见的原因就是扫描件，不说的话用户无从下手：" + message)
            XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
            XCTAssertTrue(message.contains("季度题库.pdf"), "得指名是哪个文件：" + message)
        }
    }

    /// PDFKit 对「有页面但一个字都没有」的文件返回的是空串而不是 nil。
    /// 空串一路走下去会变成「解析出 0 道题」，用户看到的是一句莫名其妙的
    /// 「这份 PDF 里没有解析出任何题目」，而真正的原因（扫描件）没人告诉他。
    func testAPDFWhoseTextIsBlankIsTreatedTheSameAsAScannedOne() throws {
        let url = try makeTemporaryFile(named: "季度题库.pdf", bytes: Data([0x25, 0x50, 0x44, 0x46]))
        XCTAssertThrowsError(
            try QuestionBankFileReader.text(at: url, format: .pdf, pdfText: { _ in "   \n \n" })
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("扫描件"),
                          error.localizedDescription)
        }
    }

    /// 反过来的一半：CSV / JSON 仍然读文件本身，不许被 PDF 那条支路顺手接管。
    func testTextFormatsAreStillReadFromTheFileItself() throws {
        let csv = "id,part,topic,prompt\np1-1,1,Home,Do you live in a house or a flat?"
        let url = try makeTemporaryFile(named: "季度题库.csv", bytes: Data(csv.utf8))
        let text = try QuestionBankFileReader.text(at: url, format: .csv,
                                                   pdfText: { _ in "这段绝不该被用到" })
        XCTAssertEqual(text, csv)
    }

    /// 文本格式读不出来时（不是 UTF-8、文件被删）也要给出能照做的下一步。
    func testANonUTF8TextFileSaysHowToFixTheEncoding() throws {
        let url = try makeTemporaryFile(named: "季度题库.csv", bytes: Data([0xFF, 0xFE, 0x41, 0x00]))
        XCTAssertThrowsError(
            try QuestionBankFileReader.text(at: url, format: .csv, pdfText: { _ in nil })
        ) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("UTF-8"), message)
            XCTAssertTrue(message.contains("下一步"), message)
            XCTAssertTrue(message.contains("季度题库.csv"), "得指名是哪个文件：" + message)
        }
    }

    // MARK: - 真的碰 PDFKit 的那一行
    //
    // ⚠️ 上面每一条都是注入一个假的取文字闭包测出来的，所以**真正调 PDFKit 的那一行
    // 一个测试都没有**。复审实测过三个突变，全量测试一条都不红：
    //
    //   1. `QuestionBankFileReader.pdfPlainText` 改成 `{ _ = url; return nil }`；
    //   2. `QuestionBankImport.importFile` 的默认参数换成 `{ _ in nil }`；
    //   3. `QuestionBankFileReader.text` 的默认参数换成 `{ _ in nil }`。
    //
    // 三处任何一处坏掉，用户选任何一份真实的文字版 PDF 都会被告知「这多半是扫描件」，
    // 然后照着提示去做一次根本不需要的文字识别。
    //
    // ⚠️ 补上之后还漏了第四种，因为**样本只有一页**：
    //
    //   4. `pdfPlainText` 改成 `PDFDocument(url: url)?.page(at: 0)?.string`（只读第一页）。
    //
    // 只有一页的样本里「读第一页」和「读全文」是同一件事，所以那三条守卫问的都是
    // 「有没有文字出来」，没人问「是不是全都出来了」。对用户那份 81 页题库，
    // 后果比上面三种更难发现：导入成功、没有任何警告、只进来第一页那几道题（铁律 5）。
    //
    // 下面这几条用 `TestPDF` 现场画一份含已知文字的真 PDF 来堵这四个口子，
    // 并且**把断言要比的内容跨到第二页去**。
    // **不用仓库根目录那份真实的 81 页 PDF**：它在 .gitignore 里、不在版本控制中，
    // 换台机器就没有了，依赖它等于让这些守卫在别处悄悄失效。

    /// 最底下那一行：`PDFDocument(url:)?.string`。
    ///
    /// 一正一反两半都要有——只测正的话，把这个函数写成 `return "Part1 必 考 题"` 也能全绿。
    ///
    /// **样本是两页的**，而且第二页那两行也写进了断言：只问「有没有文字出来」的话，
    /// 把这一行改成 `?.page(at: 0)?.string` 照样绿，而用户那份 81 页题库会只进来第一页。
    func testPDFKitReallyPullsTheTextOutOfEveryPageOfARealPDF() throws {
        let firstPage = ["Part 1 T opics", "Part1 必 考 题", "1-Study and work",
                         "Do you work or are you a student?"]
        let secondPage = ["2-Accommodation", "Do you live in a house or a flat?"]
        let url = try makeTemporaryFile(
            named: "季度题库.pdf", bytes: try TestPDF.data(pages: [firstPage, secondPage]))

        let text = try XCTUnwrap(
            QuestionBankFileReader.pdfPlainText(at: url),
            "PDFKit 没从一份真 PDF 里取出任何文字。这一行是全项目唯一碰 PDFKit 的地方，"
                + "它一断，用户选任何 PDF 都会被误判成扫描件。")
        XCTAssertEqual(TestPDF.meaningfulLines(of: text), firstPage + secondPage,
                       "取出来的文字跟画进去的对不上。少了第二页那几行的话，"
                           + "这一行只读了第一页——用户那份 81 页题库会静默丢掉 80 页的题："
                           + "\(text)")
    }

    /// 反的那一半：不是 PDF 的文件必须取不出文字（`nil`），而不是回一段写死的东西。
    func testPDFKitReportsNothingForAFileThatIsNotAPDFAtAll() throws {
        let url = try makeTemporaryFile(named: "季度题库.pdf",
                                        bytes: Data([0xFF, 0xFE, 0x00, 0x01, 0x02]))
        XCTAssertNil(QuestionBankFileReader.pdfPlainText(at: url),
                     "一堆随机字节被当成了 PDF 并「取出」了文字——这一行没有在读文件")
    }

    /// 中间那一层的默认参数：`text(at:format:)` 不传 `pdfText` 时必须走 PDFKit。
    ///
    /// 这里**刻意不传** `pdfText`，走的就是产品代码里的那个默认值。
    /// 默认值一旦被换成 `{ _ in nil }`，这条会红在「扫描件」那句话上。
    ///
    /// 样本同样是两页的，第二页那两行也在断言里（理由见上一条）。
    func testTextUsesPDFKitByDefaultSoARealPDFIsNotMistakenForAScan() throws {
        let firstPage = ["Part 1 T opics", "Part1 必 考 题", "1-Study and work",
                         "Do you work or are you a student?"]
        let secondPage = ["2-Accommodation", "Do you live in a house or a flat?"]
        let url = try makeTemporaryFile(
            named: "季度题库.pdf", bytes: try TestPDF.data(pages: [firstPage, secondPage]))

        let text = try QuestionBankFileReader.text(at: url, format: .pdf)

        XCTAssertEqual(TestPDF.meaningfulLines(of: text), firstPage + secondPage,
                       "不传 pdfText 时没有走 PDFKit，或者只取了第一页的文字：\(text)")
    }

    /// 最外面那一层的默认参数：界面调的就是 `importFile(at:)` 这一个入口（不传 `pdfText`）。
    ///
    /// 这条是从用户的角度看的那一整条路：一份真 PDF 进去，题目出来。
    /// 断言逐条比 prompt，与上面那条注入假文字的测试期望完全一致——
    /// 差别只在于文字这次是真的从 PDF 里抽出来的。
    ///
    /// **样本是两页的，第 3 道题只在第二页上。** 取文字那一步一旦只读第一页
    /// （`?.page(at: 0)?.string`），这条会红在少了一条 prompt 上——
    /// 而用户看到的会是「导入成功，3 道题变 2 道」，一句警告都没有。
    func testImportFileUsesPDFKitByDefaultSoEveryPageOfAChosenPDFYieldsQuestions() throws {
        let url = try makeTemporaryFile(
            named: "季度题库.pdf", bytes: try TestPDF.data(pages: Self.pdfPages))

        let result = try QuestionBankImport.importFile(at: url)

        XCTAssertEqual(result.questions.map(\.prompt), [
            "Do you work or are you a student?",
            "Describe one of your friends who learned a skill from someone (not a teacher)",
            // ↓ 这一条只画在第二页上：少了它就说明取文字那一步只读了第一页。
            "Is it necessary to continue learning after finishing formal education?"
        ], "选中一份真 PDF 之后没有导出全部题目。取文字那一步没走 PDFKit、只读了第一页，"
            + "或者三步没有串起来——用户会看到「这多半是扫描件」，或者一份静默少了题的题库。")
        XCTAssertEqual(result.questions.map(\.part), [1, 2, 3])
        XCTAssertEqual(result.source.title, "季度题库")
    }

    /// 真正的扫描件（整页都是图、一个字都没有）也要走通同一条路并说清楚。
    ///
    /// 上面那条同名的测试是拿假闭包返回 nil 试的；真实文件里 PDFKit 返回的是**空串**，
    /// 这个区别只有拿真文件才试得出来。两条都要有：
    /// 空串那条分支要是漏了，用户看到的会是一句莫名其妙的「没有解析出任何题目」。
    func testARealImageOnlyPDFIsExplainedAsAScannedFile() throws {
        let url = try makeTemporaryFile(named: "季度题库.pdf",
                                        bytes: try TestPDF.imageOnlyPageData())
        XCTAssertThrowsError(try QuestionBankImport.importFile(at: url)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("扫描件"),
                          "整页都是图的 PDF 没被解释成扫描件：" + message)
            XCTAssertTrue(message.contains("下一步"), message)
            XCTAssertTrue(message.contains("季度题库.pdf"), message)
        }
    }

    // MARK: -

    private func makeTemporaryFile(named name: String, bytes: Data) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-pdf-import-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: name)
        try bytes.write(to: url)
        return url
    }
}
