import Foundation
import XCTest

@testable import IELTSCoachUI

/// 训练题库页里**唯一没法靠数据断言守住、但又决定用户看不看得见**的那件事：
/// 导入完成之后，那张交代到底出现在哪儿。
///
/// 背景：这一页的触发按钮（`importCard`）在页面最底下，而题库有几十个话题时，
/// 页面远超一屏（窗口 minHeight 600）。结果卡片一度是画在页面顶端的 —— 真实路径是
/// 「用户滚到底 → 点导入 → 选完文件 → 面板关闭 → 结果出现在屏幕外的页面顶端」，
/// 用户什么交代也看不到。计划 Task 4 Step 3 要求把 `ImportResult.warnings` **逐条**显示出来
/// （「你的 CSV 第 7 行缺 id，那道题没进来」），而那些警告不看就再也不会知道。
///
/// `swift test` 不画界面，也量不出滚动位置，所以这里退一步扫源码：结果必须走 `.sheet`
/// 弹出来，与滚动位置无关。扫源码这一招在本项目有先例
/// （`PreviewSafetyTests`、`DesignSystemTests.testDesignSystemTakesFontsFromTypographyTokens`）。
///
/// **这条测试的边界要说清**：它只能证明「有一个绑到导入结果的模态呈现」，
/// 证明不了弹出来的东西好不好看、排版对不对 —— 那部分仍归 Task 11 人工验收。
/// 但「用户看不看得见」这一条不是版面观感，它决定这一页有没有完成计划要求的事。
final class QuestionBankViewTests: XCTestCase {
    func testImportResultIsPresentedAsASheetInsteadOfPaintedIntoTheScrollingPage() throws {
        let source = try String(contentsOf: Self.viewSource, encoding: .utf8)
        // 注释里必然要解释「为什么是 sheet」，连注释一起扫的话这条测试会被自己的说明绊倒。
        let code = DesignSystemTests.strippingLineComments(source)

        // 防空转：文件挪了位置或改了名，上面读到的会是一段空字符串，下面全部退化成永远绿。
        XCTAssertTrue(
            code.contains("struct QuestionBankView"),
            "没扫到 QuestionBankView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewSource.path)

        XCTAssertTrue(
            code.contains(".sheet(item: $feedback)"),
            "导入结果没有弹出来，而是画进了滚动页面里。触发按钮在页面最底下、页面远超一屏，"
                + "画在页面里的结果会落在屏幕外，用户选完文件回来什么交代也看不到，"
                + "计划要求逐条显示的那些警告尤其。"
                + "下一步：把结果交给 `.sheet(item: $feedback)` 呈现，"
                + "或换一种同样与滚动位置无关的办法（并同步改这条测试）。")

        XCTAssertTrue(
            code.contains("QuestionBankImportFeedback"),
            "页面没有引用 QuestionBankImportFeedback，上面那条断言很可能扫到了别的 sheet。"
                + "下一步：确认导入结果确实是由这个类型驱动呈现的。")
    }

    /// 被扫的文件。
    static var viewSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources/IELTSCoachUI/QuestionBank/QuestionBankView.swift")
    }
}
