import Foundation
import PDFKit
import XCTest

/// `TestPDF` 自己的自测（`SourceGuard` 的做法照搬：**守门员自己也要被守**）。
///
/// 为什么值得单独测：靠它生成 PDF 的那几条守卫，一旦它悄悄改成生成一份空白 PDF，
/// 会集体红在「PDFKit 取不出文字」上——那时人会去怀疑产品代码，而问题在测试辅助里。
/// 这几条把责任分清楚：它们绿而别处红，说明产品代码真的坏了。
final class TestPDFTests: XCTestCase {

    func testItProducesAFileThatPDFKitAcceptsAsARealOnePagePDF() throws {
        let data = try TestPDF.data(lines: ["Hello"])
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)),
                      "生成的不是 PDF（开头不是 %PDF）")
        let document = try XCTUnwrap(PDFDocument(data: data), "PDFKit 打不开生成的文件")
        XCTAssertEqual(document.pageCount, 1)
    }

    func testTheTextItDrawsCanBeReadBackIncludingChinese() throws {
        // 题库 PDF 的分区标题是「Part1 必 考 题」这种汉字间带空格的中文，
        // 生成器画不出中文的话，靠它的那几条测试就只覆盖了英文那一半。
        let lines = ["Part1 必 考 题", "1-Study and work", "Do you work or are you a student?"]
        let document = try XCTUnwrap(PDFDocument(data: try TestPDF.data(lines: lines)))
        XCTAssertEqual(TestPDF.meaningfulLines(of: document.string ?? ""), lines)
    }

    /// 多页样本必须**真的是多页**，而且第二页的文字要跟第一页分得开。
    ///
    /// 这条是「只读第一页」那组守卫的地基：`QuestionBankPDFImportTests` 靠把断言要比的
    /// 内容放到第二页来抓那个突变。要是这里画出来的其实只有一页（或者第二页是空的），
    /// 那几条守卫会退回成「只问有没有文字出来」，而且没有任何迹象。
    ///
    /// 所以两头都断言：整份文档读得到两页的全部文字，而**单看第一页读不到第二页那行**——
    /// 后半句才是样本真的能区分「读全」和「只读第一页」的证据。
    func testItCanDrawMoreThanOnePageAndTheSecondPageIsReadBackToo() throws {
        let firstPage = ["Part1 必 考 题", "1-Study and work"]
        let secondPage = ["Do you work or are you a student?", "第二页最后一行"]
        let document = try XCTUnwrap(
            PDFDocument(data: try TestPDF.data(pages: [firstPage, secondPage])))

        XCTAssertEqual(document.pageCount, 2, "样本没画成两页，「只读第一页」那组守卫就失去依据")
        XCTAssertEqual(TestPDF.meaningfulLines(of: document.string ?? ""), firstPage + secondPage,
                       "整份文档读回来的文字跟画进去的对不上：\(document.string ?? "")")

        let onlyFirst = TestPDF.meaningfulLines(of: document.page(at: 0)?.string ?? "")
        XCTAssertEqual(onlyFirst, firstPage,
                       "第一页单独读出来的不是第一页那几行：\(onlyFirst)")
        XCTAssertFalse(onlyFirst.contains(where: secondPage.contains),
                       "第二页的文字跑到第一页上了，样本区分不了「读全」和「只读第一页」")
    }

    /// `data(lines:)` 仍然是一页——它是 `data(pages:)` 的单页写法，
    /// 不能因为改成转调就悄悄变成多页（扫描件那条对照样本要求「真有一页」）。
    func testTheSinglePageHelperStillDrawsExactlyOnePage() throws {
        let document = try XCTUnwrap(PDFDocument(data: try TestPDF.data(lines: ["a", "b"])))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(TestPDF.meaningfulLines(of: document.string ?? ""), ["a", "b"])
    }

    func testTheImageOnlyPageHasAPageButNoText() throws {
        let document = try XCTUnwrap(PDFDocument(data: try TestPDF.imageOnlyPageData()))
        XCTAssertEqual(document.pageCount, 1, "扫描件样本得真有一页，否则测的是「空文件」而不是扫描件")
        XCTAssertTrue((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "这份样本本该一个字都没有，实际读出：\(document.string ?? "")")
    }

    /// `meaningfulLines` 只许去掉首尾空白与空行，不许顺手把内容也抹平——
    /// 它要是把什么都归一成空数组，用它做的每一条比较都会变成「空 == 空」。
    func testMeaningfulLinesKeepsTheContentAndOnlyDropsBlankLines() {
        XCTAssertEqual(TestPDF.meaningfulLines(of: "  a  \n\n b\n"), ["a", "b"])
        XCTAssertEqual(TestPDF.meaningfulLines(of: "a b"), ["a b"], "行内的空格不许动")
        XCTAssertEqual(TestPDF.meaningfulLines(of: " \n \n"), [])
    }
}
