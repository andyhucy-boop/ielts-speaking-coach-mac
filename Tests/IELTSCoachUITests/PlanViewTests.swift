import Foundation
import SwiftUI
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

/// 学习计划页的视图层守卫，一条对一条地钉住计划 Task 9 Step 4 给这一页的 A–H 八组验收要求。
///
/// ## 为什么这一页需要这么一份测试
///
/// 计划 Task 9 Step 6 写着「本任务不做突变验证，验收由 Task 11 人工完成」，理由是
/// 「计划页的全部判断都在 Task 3–6 的纯函数里」。**那句话只对了一半**：判断确实在纯函数里，
/// 但「这些判断有没有被画到屏幕上」从来不是纯函数管得住的事，而这正是本项目栽过四次的地方
/// （删掉 `PracticeSheet` 的两句渲染 → 369 条全绿；删掉导入结果里的警告 → 279 条全绿；
/// 把 `PracticeSheet.body` 里两句一起摘掉 → 465 条全绿）。
/// `HistoryViewTests` / `RetrainingCenterViewTests` / `IssueArchiveViewTests` 的文件注释里
/// 都写过同一个结论：**人工验收只跑一次，回归会发生无数次。**
///
/// 所以这一页照那三页的办法办：能抽成纯函数的（文案、进度、锚点、选项标题）真跑起来验，
/// 剩下的接线扫源码。
///
/// ## 边界
///
/// 扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——
/// 那部分归 Task 11 的人工验收。它拦得住的是：整段渲染被删、数据源被换掉、
/// 阻断原因被吞掉、写好的组件没摆进页面。
@MainActor
final class PlanViewTests: XCTestCase {

    private static let view = "Plan/PlanView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向几十处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        XCTAssertTrue(try Self.viewCode().contains("struct PlanView"),
                      "没扫到 PlanView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 装置

    private func state(plan: TrainingPlan?, questions: [Question] = []) -> CoachState {
        var state = CoachState.empty()
        state.plan = plan
        state.questions = questions
        return state
    }

    private func plan(lengthDays: Int, focusPart: FocusPart,
                      days: [PlanDay] = [PlanDay(id: 1, questionIds: ["q1"],
                                                 completedQuestionIds: [])]) -> TrainingPlan {
        TrainingPlan(lengthDays: lengthDays, createdAt: "2026-08-07T00:00:00Z",
                     days: days, focusPart: focusPart)
    }

    // MARK: - 要求 A：还没有计划时的空状态

    func testTheEmptyStateSaysWhatIsMissingWhyItMattersAndWhereToGoNext() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "emptyState(scroller)", inBodyOf: "var body: some View", of: Self.view,
            because: "还没有计划时这一页不再走空状态那一支，用户看到的是一片空白"
                + "（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。")
        let empty = try SourceGuard.memberBody(of: "private func emptyState", in: code)
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "空状态没走 `EmptyStateView`，那三样（现状 / 下一步 / 一颗按钮）"
                          + "就没人管得住了。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("你还没有学习计划"),
                      "空状态没说清现状。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("今日训练"),
                      "空状态没说清「有了计划之后会得到什么」——用户不知道排这份计划图什么。"
                          + "实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("下一步"),
                      "空状态只说了现状，没说现在该干什么（铁律 6）。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("Self.formAnchor"),
                      "空状态那颗按钮点下去哪儿也不去。计划要求它指向本页下方的生成表单，"
                          + "而这一页可能很长，光写一句「在下面」用户还得自己找。"
                          + "实际取到的是：\n\(empty)")
    }

    // MARK: - 要求 B：生成 / 调整表单

    /// 有计划时两个选择器的初值取自现有计划；没有计划时用 `PlanDraft()` 的默认值。
    ///
    /// 抽成纯函数是因为扫源码只问得出「这儿有个 Picker」，问不出它一进来选中的是哪一档。
    func testTheFormStartsFromTheExistingPlanAndFallsBackToTheDefaults() {
        let fresh = PlanView.initialDraft(PlanViewModel(state: state(plan: nil)))
        XCTAssertEqual(fresh, PlanDraft(),
                       "还没有计划时表单的初值不是 `PlanDraft()` 的默认值（7 天、全真模考）")

        let existing = PlanView.initialDraft(
            PlanViewModel(state: state(plan: plan(lengthDays: 14, focusPart: .part3))))
        XCTAssertEqual(existing.lengthDays, 14,
                       "已有计划时周期选择器没有停在现有计划的周期上——用户点进来看到的是 7 天，"
                           + "以为自己排的是 7 天计划")
        XCTAssertEqual(existing.focusPart, .part3,
                       "已有计划时重点 Part 选择器没有停在现有计划的重点上")
    }

    /// 手改过的 state.json 里可能是 10 天这种界面上根本没有的档位。
    /// 直接拿它当初值的话，分段控件一档都不会高亮，用户看到的是一个没有选中项的控件。
    func testAPlanLengthTheControlCannotShowFallsBackInsteadOfLeavingItBlank() {
        let odd = PlanView.initialDraft(
            PlanViewModel(state: state(plan: plan(lengthDays: 10, focusPart: .part1))))
        XCTAssertTrue(PlanBuilder.supportedLengths.contains(odd.lengthDays),
                      "周期初值是 \(odd.lengthDays) 天，而分段控件只有 "
                          + "\(PlanBuilder.supportedLengths) 三档，那个控件会一档都不高亮")
        XCTAssertEqual(odd.focusPart, .part1, "重点 Part 是认得的，不该跟着一起丢掉")
    }

    func testThePeriodPickerOffersExactlyWhatThePlanBuilderSupports() throws {
        let picker = try SourceGuard.memberBody(of: "private var lengthPicker",
                                                in: try Self.viewCode())
        XCTAssertTrue(picker.contains("PlanBuilder.supportedLengths"),
                      "周期选项是手抄的一份，不是 `PlanBuilder.supportedLengths`。"
                          + "以后加一档，界面上不会出现，而 Core 那边的测试照样绿。"
                          + "实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains(".pickerStyle(.segmented)"),
                      "周期选择器不是分段控件（计划要求 B）。实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains("lengthBinding"),
                      "周期选择器没和草稿绑起来，点了不会有任何变化。实际取到的是：\n\(picker)")
        SourceGuard.assertRenders(
            "lengthPicker", inBodyOf: "private var form", of: Self.view,
            because: "周期选择器写好了却没摆进表单，用户只能生成默认的 7 天计划。")
    }

    func testTheFocusPickerOffersEveryPartAndSpellsThemOutInChinese() throws {
        let picker = try SourceGuard.memberBody(of: "private var focusPicker",
                                                in: try Self.viewCode())
        XCTAssertTrue(picker.contains("FocusPart.allCases"),
                      "重点 Part 的选项是手抄的一份，不是 `FocusPart.allCases`。"
                          + "实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains("PlanScope.label(for:"),
                      "选项没用 `PlanScope.label(for:)` 显示，用户看到的会是 `part1` `fullMock` "
                          + "这种英文 case 名（铁律 6：面向用户的文案必须中文），"
                          + "而且与 Core 报错里的说法对不上。实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains("focusBinding"),
                      "重点 Part 选择器没和草稿绑起来。实际取到的是：\n\(picker)")
        SourceGuard.assertRenders(
            "focusPicker", inBodyOf: "private var form", of: Self.view,
            because: "重点 Part 选择器写好了却没摆进表单，用户永远只能生成全真模考。")
    }

    /// 预览那句话真跑一遍。扫源码问不出它到底说了什么。
    func testThePreviewLineQuotesTheCountTheDaysAndThePerDaySplit() {
        let text = PlanView.previewText(
            PlanDraftPreview(questionCount: 18, perDayText: "每天 2–3 题",
                             canBuild: true, blockingReason: ""),
            draft: PlanDraft(lengthDays: 7, focusPart: .part2))
        XCTAssertEqual(text, "Part 2（个人陈述）现在 18 题，分 7 天，每天 2–3 题",
                       "预览那句话和计划里逐字给的样子对不上：\(text)")
    }

    func testThePreviewIsRecomputedFromTheOneAndOnlyFeasibilityJudgement() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("PlanDraftPreviewBuilder.preview(state:"),
                      "预览不是从 `PlanDraftPreviewBuilder.preview(state:draft:)` 来的。"
                          + "自己在视图里再算一份的话，就会出现「预览说能生成、点下去却报错」——"
                          + "最伤信任的一类界面缺陷。")
        let line = try SourceGuard.memberBody(of: "private var previewLine", in: code)
        XCTAssertTrue(line.contains("Self.previewText("),
                      "能生成时那句话不是从 `previewText` 来的，上面那条真跑起来的测试"
                          + "就在测一段没人用的实现。实际取到的是：\n\(line)")
        XCTAssertTrue(line.contains("preview.blockingReason"),
                      "不能生成时没有把 `blockingReason` 全文显示出来。"
                          + "只把按钮灰掉、让用户猜为什么，是这一页最容易犯的错"
                          + "（计划要求 B 明写「禁用的按钮旁边必须有这段文字」）。"
                          + "实际取到的是：\n\(line)")
        XCTAssertTrue(line.contains("Palette.warning"),
                      "阻断原因没被标出来，会混在正文里没人注意到。实际取到的是：\n\(line)")
        SourceGuard.assertRenders(
            "previewLine", inBodyOf: "private var form", of: Self.view,
            because: "预览写好了却没摆进表单，用户点「生成计划」之前完全不知道会得到什么。")
    }

    func testTheGenerateButtonIsDisabledExactlyWhenThePlanCannotBeBuilt() throws {
        let button = try SourceGuard.memberBody(of: "private var generateButton",
                                                in: try Self.viewCode())
        XCTAssertTrue(button.contains(".disabled(!preview.canBuild)"),
                      "生成按钮没有跟着可行性判据禁用。点下去必然报错的按钮还亮着，"
                          + "用户会以为是自己哪里点错了。实际取到的是：\n\(button)")
        XCTAssertTrue(button.contains("Self.generateButtonTitle(hasPlan:"),
                      "按钮文案不是从 `generateButtonTitle(hasPlan:)` 来的。"
                          + "实际取到的是：\n\(button)")
        XCTAssertTrue(button.contains("requestGenerate()"),
                      "生成按钮点下去什么都不发生——按钮点了没反应是本项目最不能接受的那一类。"
                          + "实际取到的是：\n\(button)")
        SourceGuard.assertRenders(
            "generateButton", inBodyOf: "private var form", of: Self.view,
            because: "生成按钮写好了却没摆进表单，这一页就只能看不能用。")
    }

    func testTheButtonSaysGenerateTheFirstTimeAndRegenerateAfterwards() {
        XCTAssertEqual(PlanView.generateButtonTitle(hasPlan: false), "生成计划")
        XCTAssertEqual(PlanView.generateButtonTitle(hasPlan: true), "重新生成计划",
                       "已经有计划时按钮还写着「生成计划」，用户不知道点下去会把现在这份重排")
    }

    // MARK: - 要求 C：重新生成必须先确认

    func testRegeneratingAsksFirstButTheFirstTimeDoesNot() throws {
        let request = try SourceGuard.functionBody(named: "requestGenerate",
                                                   in: try Self.viewCode())
        XCTAssertTrue(request.contains("model.hasPlan"),
                      "「要不要先确认」没有看有没有现成的计划。第一次生成也弹一次确认框，"
                          + "等于凭空多一次点击；已有计划却不确认，则是悄悄重排了用户的安排。"
                          + "实际取到的是：\n\(request)")
        XCTAssertTrue(request.contains("isConfirmingRegenerate = true"),
                      "已有计划时没有弹确认框。实际取到的是：\n\(request)")
        XCTAssertTrue(request.contains("generate()"),
                      "还没有计划时点了按钮不会真的去生成。实际取到的是：\n\(request)")
    }

    /// 确认框那段话逐字来自计划 Task 9 要求 C。
    ///
    /// 它要回答用户按下按钮前唯一关心的问题：**我练过的那些会不会白练。**
    /// 改写它之前先想清楚这一点。
    func testTheRegenerateDialogPromisesProgressIsKeptAndSaysWhatHappensNext() {
        XCTAssertEqual(PlanView.regenerateConfirmationTitle, "重新生成计划？")
        XCTAssertEqual(
            PlanView.regenerateConfirmationMessage,
            "已经练过的题仍然算已完成，练习记录、复盘、错题本、词汇本都不受影响。\n"
                + "下一步：确认后会按你选的周期和重点 Part，重排今后的每日安排。",
            "重新生成的确认文案和计划里逐字给的那段对不上。"
                + "这段话要回答的是「我练过的会不会白练」——那是用户按下这颗按钮前唯一关心的事。")
    }

    func testTheRegenerateDialogIsActuallyWiredToThePage() throws {
        let code = try Self.viewCode()
        let body = try SourceGuard.memberBody(of: "var body: some View", in: code)
        XCTAssertTrue(body.contains("Self.regenerateConfirmationTitle"),
                      "确认框写好了却没挂在页面上，「重新生成」会不问一声就直接重排。"
                          + "实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("Self.regenerateConfirmationMessage"),
                      "确认框只有标题没有正文，用户读不到「练过的还算数」这句关键的话。"
                          + "实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("$isConfirmingRegenerate"),
                      "确认框没和 `isConfirmingRegenerate` 绑起来。实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("Button(\"重新生成\")"),
                      "确认框里没有那颗「重新生成」按钮，弹出来只能取消。实际取到的是：\n\(body)")

        // 只问「有没有这颗按钮」是不够的：把它的动作掏空成 `Button("重新生成") { }`，
        // 上面那条照样绿，而用户点下去什么都不会发生（铁律 7）。
        // 切的是确认框自己那一段，不是整个 body——`requestGenerate()` 里另有一处
        // `generate()` 的调用，扫全文的话，把按钮的动作掏空也扫得到那处残影。
        let dialog = try SourceGuard.memberBody(of: "$isConfirmingRegenerate", in: code)
        XCTAssertTrue(dialog.contains("Button(\"重新生成\") { generate() }"),
                      "确认框里那颗「重新生成」按钮没接上 `generate()`——按钮在、点了不动，"
                          + "用户会一直点。实际取到的是：\n\(dialog)")
        XCTAssertTrue(dialog.contains("Button(\"取消\", role: .cancel)"),
                      "确认框里没有那颗「取消」（计划要求 C 明写按钮是「重新生成」/「取消」）。"
                          + "没有 `.cancel` 那一颗，回车与 ESC 就没有落点，"
                          + "用户想反悔却退不出去。实际取到的是：\n\(dialog)")
    }

    // MARK: - 要求 D：生成之后的落盘与回话

    func testGeneratingGoesThroughTheRegeneratorAndSaysWhatHappenedEitherWay() throws {
        let generate = try SourceGuard.functionBody(named: "generate", in: try Self.viewCode())
        XCTAssertTrue(generate.contains("PlanRegenerator.regenerate("),
                      "生成没走 `PlanRegenerator`。自己拼一份的话，「重新生成不丢进度」"
                          + "那条硬底线就没人守了（Task 4 的全部测试都在 PlanRegenerator 上）。"
                          + "实际取到的是：\n\(generate)")
        XCTAssertTrue(generate.contains("app.mutate"),
                      "生成的结果没有落盘。用户排完计划关掉 App，什么都不会留下。"
                          + "实际取到的是：\n\(generate)")
        XCTAssertTrue(generate.contains("PlanRegenerator.apply(outcome, to: &$0)"),
                      "落盘时没有走 `PlanRegenerator.apply`。它刻意只写 `plan` 一个字段，"
                          + "顺手清掉别的字段会让用户一次点击丢掉全部历史。"
                          + "实际取到的是：\n\(generate)")
        XCTAssertTrue(generate.contains("outcome.summary"),
                      "生成成功之后一个字都不说。那段摘要里写着「你之前练过的 N 道题仍然算已完成」，"
                          + "正是用户最想确认的一句。实际取到的是：\n\(generate)")
        XCTAssertTrue(generate.contains("notice = failure"),
                      "写盘失败时把 `mutate` 返回的中文说明丢掉了。用户会以为计划已经排好，"
                          + "下次打开才发现没有（铁律 7）。实际取到的是：\n\(generate)")
        XCTAssertTrue(generate.contains("Self.generationFailureText("),
                      "`regenerate` 抛错时没有把原因显示出来。实际取到的是：\n\(generate)")
    }

    /// 生成失败时那句话真跑一遍：错误自带中文「下一步」时原样交出去，
    /// 拿到系统 NSError 时必须由我们补上（铁律 6）。
    func testGenerationFailuresAlwaysReachTheUserWithANextStep() {
        let reason = "题库里没有 Part 2（个人陈述）的题目，生成不了计划。"
            + "下一步：换一个重点 Part，或到「训练题库」页导入含该 Part 的题目。"
        XCTAssertEqual(PlanView.generationFailureText(CoachError.planImpossible(reason)), reason,
                       "`CoachError` 自带的中文说明被改写了，用户会读到两个「下一步」")

        let system = NSError(domain: NSCocoaErrorDomain, code: 4,
                             userInfo: [NSLocalizedDescriptionKey: "The file doesn’t exist."])
        let text = PlanView.generationFailureText(system)
        XCTAssertTrue(text.contains("下一步"),
                      "系统给的报错不带下一步，必须由我们补上，否则用户被扔在半路：" + text)
        XCTAssertTrue(text.contains("The file doesn’t exist."),
                      "把原始报错整个吞掉了，出问题时没人查得下去：" + text)
    }

    func testTheNoticeIsActuallyShownOnTheScreen() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "noticeCard(notice)", inBodyOf: "var body: some View", of: Self.view,
            because: "生成 / 删除 / 存偏好之后要说的那句话没有摆进页面——"
                + "成功和失败都会变成「点了没反应」（铁律 7）。")
        let card = try SourceGuard.memberBody(of: "private func noticeCard", in: code)
        XCTAssertTrue(card.contains("message"),
                      "提示卡片没有显示传进来的那段话。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("textSelection(.enabled)"),
                      "那段话不可选中。里面可能带着文件路径和原始报错，用户要能复制出来。"
                          + "实际取到的是：\n\(card)")
    }

    // MARK: - 要求 E：计划概览

    func testThePlanHeadlineNamesBothThePeriodAndTheFocusPart() {
        let text = PlanView.planTitleText(lengthDays: 14, focusPart: .part2)
        XCTAssertTrue(text.contains("14 天计划"), "概览标题里没有周期：\(text)")
        XCTAssertTrue(text.contains(PlanScope.label(for: .part2)),
                      "概览标题里没有重点 Part，或者没用 `PlanScope.label(for:)` 那份中文说法："
                          + text)
    }

    func testTheProgressLineQuotesBothNumbersAndTheBarMatchesThem() {
        let text = PlanView.progressText(done: 3, total: 14)
        XCTAssertTrue(text.contains("3"), "进度里没有已完成的题数：\(text)")
        XCTAssertTrue(text.contains("14"), "进度里没有总题数：\(text)")
        XCTAssertTrue(text.contains("题"), "进度没说清这两个数字数的是题还是天：\(text)")

        XCTAssertEqual(PlanView.progressFraction(done: 3, total: 6), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PlanView.progressFraction(done: 14, total: 14), 1, accuracy: 0.0001)
        // 一道题都没排的计划（题少于天数时尾部会留空天）会让分母是 0。
        // 直接相除得到 NaN，SwiftUI 的进度条画 NaN 会崩。
        XCTAssertEqual(PlanView.progressFraction(done: 0, total: 0), 0, accuracy: 0.0001,
                       "总题数为 0 时进度条的取值不是 0——相除会得到 NaN，画出来会崩")
    }

    func testTheProgressRowUsesTheViewModelNumbersAndMonospacedDigits() throws {
        let row = try SourceGuard.memberBody(of: "private var progressRow", in: try Self.viewCode())
        XCTAssertTrue(row.contains("model.progress"),
                      "进度不是从 `PlanViewModel.progress` 来的。视图里再数一遍的话，"
                          + "会出现「概览说 3 题、下面列表里勾了 5 道」。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains("Self.progressText("),
                      "进度那句话不是从 `progressText` 来的，上面那条真跑起来的测试"
                          + "就在测一段没人用的实现。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains("Self.progressFraction("),
                      "进度条的取值不是从 `progressFraction` 来的。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains(".monospacedDigit()"),
                      "进度数字没用等宽数字。从 9 跳到 10 时整行会横向抖一下"
                          + "（规范第 6 节最后一条）。实际取到的是：\n\(row)")
    }

    /// 「第几天」按进度走、不按日历——**这句话必须写在屏幕上**。
    ///
    /// 不写的话，请假两天回来的人看到「今天是第 3 天」会以为自己落后了，
    /// 而这一页最不该做的就是让人不想练（计划 Task 5 的注释、范围边界第一行）。
    func testTheDayNumberExplainsItselfSoNobodyThinksTheyAreBehind() {
        let note = PlanView.todayNote(dayNumber: 3)
        XCTAssertTrue(note.contains("第 3 天"), "没说清今天是第几天：\(note)")
        XCTAssertTrue(note.contains("日历"),
                      "没说清「第几天」不按日历走。请假两天回来的人会以为自己落后了：" + note)
        XCTAssertTrue(note.contains("停"),
                      "没告诉用户中间停几天回来计划还在原地等他：" + note)
    }

    func testTheFinishedPlanSaysSoAndOffersTheNextThingToDo() {
        XCTAssertTrue(PlanView.finishedText.contains("练完"),
                      "练完了却不说，用户会一直找剩下的题：" + PlanView.finishedText)
        XCTAssertTrue(PlanView.finishedText.contains("下一步"),
                      "练完之后没给下一步，这一页就成了死路（铁律 6）：" + PlanView.finishedText)
    }

    /// 计划在、题却一道都没排（题数少于天数的老计划，或手改过的 state.json）。
    /// **这一支不许留白**：概览上什么都不说的话，用户会以为程序坏了。
    func testAPlanWithNoQuestionsAtAllStillSaysSomething() {
        XCTAssertFalse(PlanView.emptyPlanNote.isEmpty)
        XCTAssertTrue(PlanView.emptyPlanNote.contains("下一步"),
                      "一道题都没有的计划只说了现状，没说怎么办：" + PlanView.emptyPlanNote)
    }

    func testTheOverviewShowsAllThreeCasesAndNeverGoesBlank() throws {
        let summary = try SourceGuard.memberBody(of: "private var planSummary",
                                                 in: try Self.viewCode())
        for (needle, why) in [
            ("Self.planTitleText(", "「N 天计划 · 重点 Part」那行标题"),
            ("progressRow", "进度条那一段"),
            ("Self.finishedText", "练完了的那句话"),
            ("Self.todayNote(", "「今天是第几天」以及它不按日历走的说明"),
            ("Self.emptyPlanNote", "一道题都没排时的兜底说明——少了它这一支会是一片空白")
        ] {
            XCTAssertTrue(summary.contains(needle),
                          "计划概览里没有\(why)（`\(needle)`）。实际取到的是：\n\(summary)")
        }
        XCTAssertTrue(summary.contains("model.isFinished"),
                      "概览没有区分「练完了」和「还在练」。实际取到的是：\n\(summary)")
        SourceGuard.assertRenders(
            "planSummary", inBodyOf: "var body: some View", of: Self.view,
            because: "整个计划概览没摆进 `body`，用户看不到自己练到哪儿了。")
    }

    // MARK: - 要求 F：每日拆分

    func testTheDailyBreakdownComesFromTheViewModelRows() throws {
        let list = try SourceGuard.memberBody(of: "private var dayList", in: try Self.viewCode())
        XCTAssertTrue(list.contains("model.dayRows"),
                      "每日拆分不是从 `PlanViewModel.dayRows` 来的。视图里自己拼一份的话，"
                          + "「题目已不在题库里」那种行会悄悄变成空白。实际取到的是：\n\(list)")
        XCTAssertTrue(list.contains("dayCard(row)"),
                      "遍历了每一天却没画出来，这一页只剩一个概览。实际取到的是：\n\(list)")
        SourceGuard.assertRenders(
            "dayList", inBodyOf: "var body: some View", of: Self.view,
            because: "每日拆分没摆进 `body`，用户看不到今天到底要练哪几道题。")
    }

    func testEveryDayShowsItsNumberItsCountAndWhetherItIsDone() throws {
        let card = try SourceGuard.memberBody(of: "private func dayCard", in: try Self.viewCode())
        for (needle, why) in [
            ("Self.dayTitle(", "「第 N 天」"),
            ("Self.dayCountText(", "当天有几道题"),
            ("Self.dayStatusText(", "这一天练完了没有"),
            ("row.isToday", "今天那一天的标记"),
            // **不能只问「这段代码里出现过 Palette.accent 吗」**：那句「今天练这几道」的
            // 标签里也有一个，于是把日期本身的高亮整个换成 textPrimary 照样是绿的
            // （本次实测：突变 M11 一条测试都没红）。所以改成问「配色是不是由 isToday 决定的」，
            // 具体配成什么颜色由下面那条真跑起来的测试管。
            ("Self.dayTitleColor(isToday: row.isToday)", "今天那一天的强调色接线（计划要求 F）"),
            ("questionRow(", "当天每一道题"),
            ("Self.dayAnchor(", "滚动锚点——没有它「默认滚到今天」就无从谈起")
        ] {
            XCTAssertTrue(card.contains(needle),
                          "每天那张卡片里没有\(why)（`\(needle)`）。实际取到的是：\n\(card)")
        }
        XCTAssertTrue(card.contains(".monospacedDigit()"),
                      "天数与题数没用等宽数字，从第 9 天翻到第 10 天时整列会抖"
                          + "（规范第 6 节最后一条）。实际取到的是：\n\(card)")
    }

    /// 「今天」那一天必须是**唯一**被强调色标出来的一天。
    ///
    /// 抽成纯函数与 `IssueArchiveView.trendColor` 同一个理由：扫源码问不出
    /// 「isToday 那一天到底被画成了什么颜色」，而只问「这段代码里有没有 `Palette.accent`」
    /// 会被同一段里那句「今天练这几道」的标签顶满——实测过，把日期本身的高亮整个删掉，
    /// 40 条一条不红。
    func testTodayIsTheOnlyDayPaintedInTheAccentColour() {
        XCTAssertEqual(PlanView.dayTitleColor(isToday: true), Palette.accent,
                       "今天那一天没有用强调色标出来。30 天的计划一眼扫过去，"
                           + "用户找不到自己该练哪一天（计划要求 F 指名用 `Palette.accent`）")
        XCTAssertEqual(PlanView.dayTitleColor(isToday: false), Palette.textPrimary,
                       "每一天都被标成了强调色，那等于一天都没标")
    }

    func testTheDayHeadlinesAndBadgesActuallySayTheRightThing() {
        XCTAssertEqual(PlanView.dayTitle(3), "第 3 天")
        XCTAssertTrue(PlanView.dayCountText(total: 2).contains("2"),
                      "当天题数那一格没有数字：" + PlanView.dayCountText(total: 2))
        XCTAssertNotEqual(PlanView.dayStatusText(isComplete: true),
                          PlanView.dayStatusText(isComplete: false),
                          "练完和没练完显示的是同一句话，那这个标记等于没有")
        XCTAssertTrue(PlanView.dayStatusText(isComplete: true).contains("完"),
                      "练完那一天的标记看不出是「完成」：" + PlanView.dayStatusText(isComplete: true))
    }

    func testEveryQuestionRowShowsThePartTheTopicAndThePrompt() throws {
        let row = try SourceGuard.memberBody(of: "private func questionRow", in: try Self.viewCode())
        for (needle, why) in [
            ("Self.partBadgeText(", "Part 徽标"),
            ("item.topic", "话题"),
            ("item.prompt", "题干"),
            ("item.isCompleted", "这道题练过没有"),
            ("item.isMissing", "题目还在不在题库里"),
            ("Palette.warning", "题目不在题库里时的警示色（计划要求 F 指名用它）")
        ] {
            XCTAssertTrue(row.contains(needle),
                          "题目那一行里没有\(why)（`\(needle)`）。实际取到的是：\n\(row)")
        }
    }

    /// 题目已经不在题库里的那一行，`part` 是 0、`topic` 是空的。
    /// **徽标不能因此变成空白**——一行只剩半句话，用户会以为界面坏了。
    func testARowWhoseQuestionIsGoneStillCarriesAReadableBadge() {
        XCTAssertEqual(PlanView.partBadgeText(part: 2), "Part 2")
        let gone = PlanView.partBadgeText(part: 0)
        XCTAssertFalse(gone.isEmpty, "题目已失效的那一行徽标是空白的")
        XCTAssertFalse(gone.contains("0"),
                       "题目已失效的那一行显示成了「Part 0」，那是个不存在的东西：" + gone)
    }

    /// 「默认滚动到今天」这件事只有锚点对得上才成立。
    func testTheScrollAnchorsAreUniqueAndTheTodayJumpIsWiredUp() throws {
        XCTAssertNotEqual(PlanView.dayAnchor(1), PlanView.dayAnchor(2),
                          "两天的滚动锚点一样，滚到哪一天全看运气")
        XCTAssertNotEqual(PlanView.dayAnchor(1), PlanView.formAnchor,
                          "第一天和生成表单共用一个锚点，「去下面生成」会跳到列表上")

        let code = try Self.viewCode()
        let jump = try SourceGuard.functionBody(named: "scrollToToday", in: code)
        XCTAssertTrue(jump.contains("model.todayNumber"),
                      "滚动的目标不是「今天」那一天。实际取到的是：\n\(jump)")
        XCTAssertTrue(jump.contains("Self.dayAnchor("),
                      "滚动用的锚点不是 `dayAnchor`，滚过去的位置和卡片挂的 id 对不上。"
                          + "实际取到的是：\n\(jump)")
        SourceGuard.assertRenders(
            "scrollToToday(scroller)", inBodyOf: "var body: some View", of: Self.view,
            because: "「默认滚动到今天」写好了却没人调用，30 天计划打开来停在第 1 天，"
                + "用户每次都得自己滚到底。")
    }

    // MARK: - 要求 G：删除计划

    func testDeletingThePlanAsksFirstAndPromisesWhatSurvives() {
        XCTAssertEqual(PlanView.deleteConfirmationTitle, "删除计划？")
        XCTAssertEqual(
            PlanView.deleteConfirmationMessage,
            "删掉之后「今日训练」页的「按计划练今天」会消失，但练习记录、复盘和题目的已练标记都还在。\n"
                + "下一步：随时可以回到这一页重新生成一份计划。",
            "删除计划的确认文案和计划里逐字给的那段对不上。"
                + "它要回答的是「删了会不会连练习记录一起没」——那是用户按下这颗按钮前唯一关心的事。")
    }

    func testTheDeleteButtonIsWiredAndClearlySecondary() throws {
        let code = try Self.viewCode()
        let section = try SourceGuard.memberBody(of: "private var deleteSection", in: code)
        XCTAssertTrue(section.contains("Button(\"删除计划\""),
                      "页面底部没有删除计划的入口。实际取到的是：\n\(section)")
        XCTAssertTrue(section.contains("isConfirmingDelete = true"),
                      "删除按钮点下去不会弹确认框——要么没反应，要么直接删了。"
                          + "实际取到的是：\n\(section)")
        XCTAssertFalse(section.contains(".borderedProminent"),
                       "删除按钮做成了和主行动一样醒目的样式。整页只能有一个主行动"
                           + "（DESIGN-SYSTEM 第 4 节），而这一页的主行动是「生成计划」。"
                           + "实际取到的是：\n\(section)")
        SourceGuard.assertRenders(
            "deleteSection", inBodyOf: "var body: some View", of: Self.view,
            because: "删除入口写好了却没摆进页面，用户没有任何办法撤掉一份排错的计划。")

        let body = try SourceGuard.memberBody(of: "var body: some View", in: code)
        XCTAssertTrue(body.contains("Self.deleteConfirmationTitle")
                          && body.contains("Self.deleteConfirmationMessage"),
                      "删除的确认框没挂在页面上。实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("$isConfirmingDelete"),
                      "删除确认框没和 `isConfirmingDelete` 绑起来。实际取到的是：\n\(body)")

        // **这一段是补的。** 上面四条断言的是标题常量、正文常量和 `$isConfirmingDelete`，
        // 恰好把那颗真正执行删除的按钮整个漏在外面：实测把
        // `Button("删除", role: .destructive) { deletePlan() }` 整颗删掉，1331 条一条不红——
        // 确认框弹出来只剩「取消」，用户没有任何办法撤掉一份排错的计划，
        // `deletePlan()` 连同它下面那条「只动 plan 一个字段」的测试一起变成死代码。
        // 重新生成那一侧本来就有 `Button("重新生成")` 的守卫，删除这一侧是漏写不是取舍。
        //
        // 切确认框自己那一段而不是整个 body：`deleteSection` 里还有一颗
        // `Button("删除计划", role: .destructive)`，扫全文的话那颗残影会替这颗挡枪。
        let dialog = try SourceGuard.memberBody(of: "$isConfirmingDelete", in: code)
        XCTAssertTrue(dialog.contains("Button(\"删除\", role: .destructive)"),
                      "删除确认框里没有那颗「删除」按钮（计划要求 G 明写按钮是「删除」/「取消」）。"
                          + "弹出来只剩「取消」，用户没有任何办法撤掉一份排错的计划。"
                          + "实际取到的是：\n\(dialog)")
        XCTAssertTrue(dialog.contains("{ deletePlan() }"),
                      "确认框里那颗「删除」按钮没接上 `deletePlan()`——按钮在、点了不动，"
                          + "而界面上没有任何迹象说明什么都没发生（铁律 7）。"
                          + "实际取到的是：\n\(dialog)")
        XCTAssertTrue(dialog.contains("Button(\"取消\", role: .cancel)"),
                      "删除确认框里没有那颗「取消」。删除是不可逆的动作，"
                          + "没有 `.cancel` 那一颗，回车与 ESC 就没有落点，"
                          + "用户想反悔却退不出去。实际取到的是：\n\(dialog)")
    }

    /// **删除计划只许动 `plan` 一个字段。**
    ///
    /// 确认框里逐字承诺了「练习记录、复盘和题目的已练标记都还在」，那就必须真的还在。
    /// 顺手清掉 `sessions`、把题目状态重置成 new 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史——而界面上不会有任何异样。
    ///
    /// 这条真跑起来，而且比对的是**整份 `CoachState`**：多改任何一个字段都会红。
    /// 只扫源码问「有没有 `$0.plan = nil`」是不够的——本次实测过，
    /// 在它后面加一句 `$0.sessions = []`，41 条一条不红。
    func testDeletingThePlanTouchesNothingButThePlan() {
        var before = CoachState.empty()
        before.plan = plan(lengthDays: 7, focusPart: .part2)
        before.questions = [Question(id: "q1", part: 1, topic: "Home",
                                     prompt: "Do you live in a house or a flat?")]
        before.sessions = [PracticeSession(id: "2026-08-06-001", questionId: "q1",
                                           focusPart: .part1, startedAt: "2026-08-06T10:00:00Z",
                                           endedAt: "2026-08-06T10:20:00Z", goal: "",
                                           transcript: [], reportPath: "reports/a.json",
                                           recordingPath: "")]
        before.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                     correction: "I really like it.",
                                     whyItMatters: "very 不能直接修饰动词", occurrences: 2,
                                     sourceSessionIds: ["2026-08-06-001"],
                                     lastSeenAt: "2026-08-06T10:20:00Z")]
        before.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good",
                                              betterExpression: "solid", collocation: "a solid grasp",
                                              priority: "high",
                                              sourceSessionIds: ["2026-08-06-001"])]
        before.targets = [RetrainingTarget(targetKey: "add-a-reason", label: "补一个原因",
                                           status: "pending", evidence: ["I like it."],
                                           sourceSessionId: "2026-08-06-001",
                                           createdAt: "2026-08-06T10:20:00Z")]

        var after = before
        PlanView.clearPlan(&after)

        XCTAssertNil(after.plan, "点了删除，计划还在")
        var expected = before
        expected.plan = nil
        XCTAssertEqual(after, expected,
                       "删除计划顺手改了别的字段。确认框里逐字承诺过「练习记录、复盘和"
                           + "题目的已练标记都还在」——一次点击丢掉全部历史，是这一页能犯的最重的错。")
    }

    func testDeletingOnlyClearsThePlanAndSaysSoAfterwards() throws {
        let delete = try SourceGuard.functionBody(named: "deletePlan", in: try Self.viewCode())
        XCTAssertTrue(delete.contains("app.mutate"),
                      "删除没有落盘，用户重开 App 计划又回来了。实际取到的是：\n\(delete)")
        XCTAssertTrue(delete.contains("Self.clearPlan"),
                      "删除动作不是走 `clearPlan`，上面那条「只动 plan 一个字段」的测试"
                          + "就在测一段没人用的实现。实际取到的是：\n\(delete)")
        XCTAssertTrue(delete.contains("Self.deletedNotice"),
                      "删完一个字都不说。实际取到的是：\n\(delete)")

        // **这两条是补的，而且必须是这两条。** 上面三条只查了 `app.mutate`、`Self.clearPlan`、
        // `Self.deletedNotice` 三个词出现过没有，于是实测把这一句换成
        // `_ = app.mutate(Self.clearPlan)` 加一句 `notice = Self.deletedNotice`，
        // 三个词全都还在，1331 条一条不红——而那正是铁律 7 点名的静默失败：
        // 磁盘写不进去，界面照样宣布「计划已经删掉了……都还在」，
        // 用户下次打开发现计划还在，只会以为是程序坏了。
        // 存偏好那一侧的 `save` 一直断言的是 `notice = app.mutate`（有牙），
        // 同一份文件里这一侧写松了，是漏写不是取舍。
        XCTAssertTrue(delete.contains("notice = app.mutate("),
                      "写盘失败时 `mutate` 返回的那句中文说明被丢掉了（多半是写成了 "
                          + "`_ = app.mutate(…)`）。删除失败却显示「计划已经删掉了」，"
                          + "是本项目最不能接受的那一种失败（铁律 7）。实际取到的是：\n\(delete)")
        XCTAssertTrue(delete.contains("?? Self.deletedNotice"),
                      "「计划已经删掉了」那句话不是失败消息的兜底，而是无条件显示的。"
                          + "写盘失败时用户会同时被告知「删掉了」和什么都没发生。"
                          + "实际取到的是：\n\(delete)")
        XCTAssertTrue(PlanView.deletedNotice.contains("下一步"),
                      "删完那句话没说下一步做什么（铁律 6）：" + PlanView.deletedNotice)
        XCTAssertTrue(PlanView.deletedNotice.contains("还在"),
                      "删完那句话没说清练习记录与复盘都还在，用户会担心自己删掉了历史："
                          + PlanView.deletedNotice)
    }

    // MARK: - 要求 H：三项练习偏好搬走之后，这一页只留一条路
    //
    // **Phase 10 Task 16 把那三个控件搬进了设置窗口。** 它们影响的是每一场练习，
    // 不只是这份计划；当初落在这一页页尾，只是因为那时还没有设置窗口。
    // 那三条「控件长什么样、绑到哪个字段」的断言跟着控件一起搬去了
    // `SettingsWindowViewTests` 与 `PracticePreferenceEditorTests`——**一条都没丢**。
    //
    // 这里留下的是搬家之后这一页该有的样子：既不许把控件留在原地
    // （`SettingsHomeContractTests` 会当场变红），也不许什么都不留
    // （用户从前在这儿改这几项，突然一片空白只会让他以为功能没了）。

    func testThePreferenceSectionIsStillOnThePageAsASignpost() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "preferences", inBodyOf: "var body: some View", of: Self.view,
            because: "那一整块没摆进页面，从前在这儿改偏好的用户会以为功能被删了。")
        let block = try SourceGuard.memberBody(of: "private var preferences", in: code)
        XCTAssertTrue(block.contains("SectionHeader("),
                      "这一块没有区块标题，会和上面的计划糊成一片。实际取到的是：\n\(block)")
        XCTAssertTrue(block.contains("默认练习路线、反馈时机、Part 2 准备时间都在设置里改"),
                      "少了那句说明。只摆一颗按钮的话，用户不知道按下去会看到什么。"
                          + "实际取到的是：\n\(block)")
        XCTAssertTrue(block.contains("Button(\"打开设置 › 练习偏好\")"),
                      "只写了一句「去设置里改」却没给按钮，用户读完还得自己去翻菜单——"
                          + "DESIGN-SYSTEM 第 4 节要的三样（现状 / 下一步 / 能直接点的按钮）缺了一样。"
                          + "实际取到的是：\n\(block)")
        XCTAssertTrue(block.contains("navigator.open(.practice)"),
                      "按钮没有把设置窗口定到「练习偏好」那一栏，用户点开落在「录音」上。"
                          + "实际取到的是：\n\(block)")
        XCTAssertTrue(block.contains("openSettings()"),
                      "按钮没有真的打开设置窗口，点下去什么都不会发生。实际取到的是：\n\(block)")
    }

    /// **那三个控件必须真的不在这一页了。**
    ///
    /// 上一条只问「路标在不在」，把控件留在路标旁边它照样绿——而那就是
    /// 「练习偏好有两个家」本身：两处各写一次盘，谁后写谁说了算，用户看到的是随机结果。
    /// 源码层面 `SettingsHomeContractTests` 从写入口那一头守着同一件事，
    /// 这一条从界面这一头守：控件、绑定、共用卡片，一个都不许留。
    func testTheThreePreferenceControlsReallyLeftThisPage() throws {
        let code = try Self.viewCode()
        for leftover in ["routePreference", "feedbackPreference", "prepPreference",
                         "preferenceCard", "routeBinding", "feedbackBinding", "prepBinding",
                         "PracticeRoutePreference"] {
            XCTAssertFalse(code.contains(leftover),
                           "这一页里还留着 `\(leftover)`。练习偏好现在只有一个家"
                               + "（设置窗口的「练习偏好」那一栏）；留在这儿就是两个入口，"
                               + "而两个入口迟早会显示两个不一样的取值。"
                               + "下一步：把它删掉，这一页只留那条深链接。")
        }
    }

    // MARK: - 接线：这一页得真的挂在侧边栏上

    func testTheSidebarActuallyRoutesToThisPage() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(root.contains("case .plan: PlanView(app: app"),
                      "`RootView` 的 detail 分支里没有这一页，侧边栏点「学习计划」落到的还是"
                          + "那张「还没做」的占位页——而 `SidebarItem.plan.isImplemented` "
                          + "已经写成 true，占位页连说明都不会有。")
    }

    /// 这一页只说「排了什么、练到哪儿」，不许出现任何形式的雅思分数预测或水平判断
    /// （DEFINITION-OF-DONE 第 4 节）。
    func testThisPageNeverPredictsABandScore() throws {
        let code = try Self.viewCode()
        for banned in ["band", "Band", "分数", "评分", "打分", "几分", "水平判断", "预测"] {
            XCTAssertFalse(code.contains(banned),
                           "学习计划页里出现了「\(banned)」。本项目不得出现任何形式的雅思分数预测"
                               + "或水平判断（DEFINITION-OF-DONE 第 4 节）。")
        }
    }
}
