import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 用户手上的季度题库是 PDF（仓库根目录那份 81 页的文件）。
/// 这一组守的是「选中一份 PDF 之后到底发生了什么」这条路上最容易断的三处。
final class QuestionBankPDFImportTests: XCTestCase {

    /// 照抄真实 PDF 抽出来的片段（含一处折行的 cue card 题干）。
    private static let pdfPlainText = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        Part2 & 3 保 留 题
        人物
        1-Describe one of your friends who learned a skill from someone
        (not a teacher)
        You should say
        Who he/she is
        Part3
        Is it necessary to continue learning after finishing formal education?
        """

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
