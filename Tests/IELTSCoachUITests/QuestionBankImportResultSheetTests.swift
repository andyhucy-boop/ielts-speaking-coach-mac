import Foundation
import XCTest

@testable import IELTSCoachUI

/// 导入结果弹窗里**那几条警告到底有没有被画出来**。
///
/// **这一条补的是一个已实测能溜过去的洞**：把 `QuestionBankImportResultSheet` 里
/// 渲染警告的那一段（`if !feedback.warnings.isEmpty { … ForEach … }`）整段删掉，
/// **279 条全绿**。而用户那边看到的是：弹窗第一行明明白白写着
/// 「导入 38 题（共 41 条）。下面 2 条警告指出了文件里有问题的行」——
/// 而下面什么都没有。
///
/// 这比「什么都不显示」更糟：文案在指着一处不存在的东西，用户会以为是自己没看见，
/// 或者以为程序坏了；那两条「第 7 行缺 id」是他修好自己题库文件的唯一线索，
/// 不看就再也不会知道。
///
/// `QuestionBankViewModelTests` 只测到 `feedback.warnings` 这个数组是对的
/// （`testFeedbackKeepsEveryWarning`），**数组对不对和有没有画出来是两件事**——
/// 本项目已经在四个地方分别栽过这同一跤，这里补上最后那一段。
///
/// 边界：扫源码证明不了排版好不好看、滚不滚得动，那归人工验收；
/// 它证明的是「这段渲染还在，而且在被渲染的那棵树里」。
final class QuestionBankImportResultSheetTests: XCTestCase {

    private static let sheet = "QuestionBank/QuestionBankImportResultSheet.swift"

    /// 弹窗的 `body` 里必须真的逐条画出 `feedback.warnings`。
    func testEveryWarningIsActuallyPaintedInTheBody() throws {
        SourceGuard.assertRenders(
            "struct QuestionBankImportResultSheet", in: Self.sheet,
            because: "没扫到这张弹窗的源码，这条测试等于空转。下一步：确认文件还在。")

        // 扫 `body` 那一段，不扫全文：`#Preview` 里也各写着一份 `warnings:`，
        // 扫全文的话，把 body 里那段渲染整段删掉，预览里的残影照样扫得到，测试仍然是绿的。
        SourceGuard.assertRenders(
            "feedback.warnings", inBodyOf: "var body", of: Self.sheet, atLeast: 2,
            because: "弹窗没有把 `feedback.warnings` 画出来（至少要两处：判空一次、遍历一次）。"
                + "而上面那句总结文案会照常说「下面 N 条警告指出了文件里有问题的行」——"
                + "文案指着一处不存在的东西，用户只会以为是自己没看见。"
                + "下一步：把那段 `if !feedback.warnings.isEmpty { ForEach… }` 放回 body。")

        SourceGuard.assertRenders(
            "ForEach", inBodyOf: "var body", of: Self.sheet,
            because: "警告没有被**逐条**摆出来。只显示一个条数（「有 2 条警告」）等于没说："
                + "用户要的是「第 7 行缺 id」那句具体的话，那是他修好自己文件的唯一线索。"
                + "下一步：用 `ForEach` 把每一条都画出来。")
    }

    /// 弹窗那句总结（导入了几题、共几条）也得在，否则用户不知道这一趟到底成没成。
    func testTheSummaryLineIsShownToo() throws {
        SourceGuard.assertRenders(
            "feedback.message", inBodyOf: "var body", of: Self.sheet,
            because: "弹窗没有显示那句总结。用户点完导入回来只看到一个标题，"
                + "不知道进来了几道题。下一步：把 `feedback.message` 画回 body。")
        SourceGuard.assertRenders(
            "feedback.title", inBodyOf: "var body", of: Self.sheet,
            because: "弹窗没有标题。下一步：把 `feedback.title` 画回 body。")
    }

    /// 一份坏掉的 CSV 可能有几十条警告。挤不下时必须能翻，不能截断——
    /// 被截掉的那几行正是用户最需要的那几行。
    func testTheWarningListCanScrollInsteadOfBeingCutOff() throws {
        SourceGuard.assertRenders(
            "ScrollView", inBodyOf: "var body", of: Self.sheet,
            because: "警告那一段不在可滚动的容器里。一份坏掉的 CSV 可能有几十条警告，"
                + "挤不下就会被静默截断，而被截掉的恰恰是用户还没读到的那几行。"
                + "下一步：把正文那段放回 `ScrollView` 里。")
    }

    /// 「一道题都没进来」不能画成绿色对勾。
    ///
    /// 用户扫一眼绿勾就会走开，而真正的原因全在下面那几条警告里——
    /// 这正是本项目最怕的静默失败形态（铁律 5）。
    func testNothingImportedIsNotDressedUpAsSuccess() throws {
        let tone = try SourceGuard.memberBody(of: "private var tint",
                                              in: try SourceGuard.code(Self.sheet))
        XCTAssertTrue(
            tone.contains("case .nothing: return Palette.warning"),
            "「一道题都没进来」没有用警告色。用户扫一眼绿色对勾就会走开，"
                + "而一道题都没进来的原因全在下面那几条警告里。"
                + "下一步：把 `.nothing` 的配色改回 `Palette.warning`。实际取到的是：\n\(tone)")

        let symbol = try SourceGuard.memberBody(of: "private var symbolName",
                                                in: try SourceGuard.code(Self.sheet))
        XCTAssertFalse(
            symbol.contains("case .nothing: return \"checkmark.circle\""),
            "「一道题都没进来」用的是打勾图标。下一步：换成 `exclamationmark.triangle`。")
    }
}
