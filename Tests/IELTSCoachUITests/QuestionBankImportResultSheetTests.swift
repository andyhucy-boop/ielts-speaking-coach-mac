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

    /// 上一条只问到「有一个 `ForEach`、`feedback.warnings` 出现过两次」，
    /// **管不到那个 `ForEach` 里到底画的是什么**。已实测的两条溜法：
    ///
    /// - 把 `Label(warning, …)` 换成一句泛泛的话（`Text("文件里有几行有问题")`）→ 全绿。
    ///   那时弹窗上会出现 N 行一模一样的废话，而「第 7 行缺 id」这句唯一有用的线索没了。
    /// - `feedback.warnings.prefix(1)` 只画第一条 → 全绿。
    ///   一份坏掉的 CSV 可能有几十行毛病，用户照着改好第一行、再导入，又只看到下一条，
    ///   得来回几十趟——而且他不知道后面还有，那是静默截断（铁律 5）。
    ///
    /// 所以这里切进 `ForEach` 的闭包体里问：那一行画的是不是循环变量本身。
    func testEachWarningRowPrintsThatWarningInsteadOfAGenericSentence() throws {
        let body = try SourceGuard.memberBody(of: "var body",
                                              in: try SourceGuard.code(Self.sheet))

        // 「只画前几条」这一支先查：它一并会把下面那个 `ForEach(` 的锚点改掉
        // （`warnings.prefix(1).enumerated()`），先切再查的话报出来的会是一句
        // 「找不到这段声明」，看的人得自己反推是被截断了。
        XCTAssertFalse(
            body.contains(".prefix(") || body.contains(".dropFirst(")
                || body.contains(".dropLast(") || body.contains("feedback.warnings.first"),
            "警告只画了一部分，剩下的被静默截掉了（铁律 5）：用户不知道后面还有，"
                + "照着看得见的那条改完再导入，又冒出下一条，一份有几十行毛病的 CSV 要来回几十趟。"
                + "下一步：全部画出来——它们本来就在一个 `ScrollView` 里，挤不下能翻，不必截断。"
                + "实际取到的 body 是：\n\(body)")

        let row = try SourceGuard.memberBody(
            of: "ForEach(Array(feedback.warnings.enumerated())", in: body)

        // 至少两次：一次是闭包参数 `{ _, warning in`，一次是真的把它画出来。
        // 只出现一次 = 参数收下了却没用，画出来的是一句和这条警告无关的话。
        //
        // 必须用 `standaloneOccurrences` 而不是 `occurrences`：后者是纯子串计数，
        // 同一行里的颜色令牌 `Palette.warning` 会被算作一次，把这条断言凑满——
        // 2026-08-06 复核实测，那时把 `Label(warning, …)` 换成一句泛泛之词是**全绿**的，
        // 这条守卫等于不存在。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.standaloneOccurrences(of: "warning", in: row), 2,
            "警告那一行没有把这条警告本身画出来（`warning` 在闭包里只出现了一次，"
                + "也就是收下了参数却没用）。用户看到的会是 N 行一模一样的泛泛之词，"
                + "而「跳过第 7 行：缺少 id。下一步：给这道题一个唯一编号。」这句唯一能让他"
                + "修好文件的话不见了。"
                + "下一步：把 `Label(warning, systemImage: \"exclamationmark.triangle\")` 放回去。"
                + "实际取到的那一行是：\n\(row)")
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
