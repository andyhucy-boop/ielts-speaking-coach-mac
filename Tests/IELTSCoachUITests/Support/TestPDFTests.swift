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
