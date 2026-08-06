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
/// 弹出来，与滚动位置无关。扫源码用的是共用的 `SourceGuard`——它读不到文件会抛错，
/// 不会拿一段空串把下面每条断言都变成永远绿。
///
/// **这条测试的边界要说清**：它只能证明「有一个绑到导入结果的模态呈现」，
/// 证明不了弹出来的东西好不好看、排版对不对 —— 那部分仍归人工验收。
/// 但「用户看不看得见」这一条不是版面观感，它决定这一页有没有完成计划要求的事。
/// （弹窗里那些警告到底有没有被画出来，由 `QuestionBankImportResultSheetTests` 守。）
final class QuestionBankViewTests: XCTestCase {

    private static let view = "QuestionBank/QuestionBankView.swift"

    func testImportResultIsPresentedAsASheetInsteadOfPaintedIntoTheScrollingPage() throws {
        SourceGuard.assertRenders(
            "struct QuestionBankView", in: Self.view,
            because: "没扫到 QuestionBankView 的源码，这条测试等于空转。下一步：确认文件还在。")

        SourceGuard.assertRenders(
            ".sheet(item: $feedback)", in: Self.view,
            because: "导入结果没有弹出来，而是画进了滚动页面里。触发按钮在页面最底下、页面远超一屏，"
                + "画在页面里的结果会落在屏幕外，用户选完文件回来什么交代也看不到，"
                + "计划要求逐条显示的那些警告尤其。"
                + "下一步：把结果交给 `.sheet(item: $feedback)` 呈现，"
                + "或换一种同样与滚动位置无关的办法（并同步改这条测试）。")

        SourceGuard.assertRenders(
            "QuestionBankImportFeedback", in: Self.view,
            because: "页面没有引用 QuestionBankImportFeedback，上面那条断言很可能扫到了别的 sheet。"
                + "下一步：确认导入结果确实是由这个类型驱动呈现的。")
    }

    /// 同一招守另一条也「只有一根线、断了功能就整个废掉」的东西：
    /// 用户选完文件之后，这一页走的必须是 `QuestionBankImport.importFile(at:)` 那一条收口过的路。
    ///
    /// 背景：认格式、取文字、解析这三步各自都有测试，但「三步在界面里有没有真的串起来」
    /// 一度无人守——把取文字那一步换回 `String(contentsOf:encoding:.utf8)`，
    /// 真实 PDF 必然读不出来、导入功能整个废掉，而全部测试一条都不红。
    /// 三步已收进 `importFile`，`QuestionBankPDFImportTests` 守着它本身；
    /// 这里守的是最后那一段——视图确实调的是它，而不是自己另拼一条。
    ///
    /// 边界同上：扫源码证明不了运行时行为，只能证明这一页没有绕开那个入口。
    func testTheImportPathGoesThroughTheOneComposedEntryPoint() throws {
        SourceGuard.assertRenders(
            "struct QuestionBankView", in: Self.view,
            because: "没扫到 QuestionBankView 的源码，这条测试等于空转。下一步：确认文件还在。")

        SourceGuard.assertRenders(
            "QuestionBankImport.importFile(at:", in: Self.view,
            because: "这一页没有走 `QuestionBankImport.importFile(at:)`。认格式、取文字、解析三步"
                + "在界面里自己拼一遍的话，取文字那一步一旦写成按 UTF-8 读文件，"
                + "真实 PDF 就再也导不进来，而没有任何一条测试会红。"
                + "下一步：把导入改回调 `QuestionBankImport.importFile(at:)`（它已被"
                + "`QuestionBankPDFImportTests` 覆盖），或换一种同样可测的收口方式并同步改这条测试。")

        SourceGuard.assertOmits(
            "String(contentsOf: url", in: Self.view,
            because: "这一页又开始自己按文本读用户选中的文件了。PDF 不是文本文件，这样读必然失败，"
                + "而报出来的「另存为 UTF-8」对一份 PDF 是做不到的事。"
                + "下一步：读文件交给 `QuestionBankFileReader.text(at:format:)`（`importFile` 已经在用）。")
    }
}
