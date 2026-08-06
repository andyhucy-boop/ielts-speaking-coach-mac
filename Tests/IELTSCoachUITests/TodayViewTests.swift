import Foundation
import XCTest

@testable import IELTSCoachUI

/// 今日训练页上那几件**没法靠数据断言守住、但决定用户看不看得见**的事。
///
/// 扫源码这条路的边界要说清，边界是实测出来的，不是估计的：
/// - 拦得住的是真实的退化形态——按钮体被掏空、显示那段被删掉、写好的组件没摆进页面、
///   分支被整段拿掉。这几种都真去改了代码、真看到这里变红。
/// - 拦不住的是「代码还在但跑不到」，比如把条件改成 `if let x, false`：
///   扫源码不执行代码，也就判断不了条件的真假（实测这一种确实溜过去了）。
///   要拦这一种得把界面真的渲染出来（ViewInspector / 快照测试），本项目还没有那套工具。
/// - 画出来好不好看、位置对不对同样不在这里，归 Task 11 人工验收。
///
/// 但「用户看不看得见」不是版面观感，它决定这一页有没有做到计划要求的事。
final class TodayViewTests: XCTestCase {

    // MARK: - 「开始练习」必须真的开练（本阶段的交付物）

    /// **这一条就是 Task 9 的交付判据。**
    ///
    /// 上一版的「开始练习」弹出来的是一张写着 `swift run coach practice <id>` 的卡片，
    /// 让用户自己去开终端——直接违反成品标准第 2 条「全程不需要打开终端」。
    /// 把驱动接进按钮之后，这一页里就不该再有任何一句「去终端敲命令」。
    func testTheStartButtonActuallyLaunchesAPracticeInsteadOfSendingTheUserToATerminal() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("PracticeSheet("),
            "「开始练习」没有弹出 PracticeSheet，也就没有把 ChatGPT 驱动接进界面。"
                + "下一步：按钮改成弹 `PracticeSheet` 并由它调 `runner.start(setup:)`。")

        for forbidden in ["终端", "命令行", "swift run coach"] {
            XCTAssertFalse(
                code.contains(forbidden),
                "今日训练页里还留着「\(forbidden)」。这一页现在能直接开练了，"
                    + "再把用户支去命令行，就是给他一条比按钮更麻烦、而且已经不必要的路"
                    + "（成品标准第 2 条）。下一步：把那段文案删掉或改写。")
        }
    }

    /// 一场练习的设置（哪道题、哪个 Part、带什么目标）必须来自 `TodayViewModel`，
    /// 而不是在视图里现拼。视图里拼的那份没有任何测试管得住——
    /// `TodayViewModelTests` 里那几条 `practiceSetup` 的断言会当场退化成空转。
    func testTheSetupHandedToTheRunnerComesFromTheViewModel() throws {
        let code = try Self.todayViewCode()
        XCTAssertTrue(
            code.contains("model.practiceSetup(") || code.contains(".practiceSetup("),
            "视图自己拼了 SessionSetup。下一步：改成调 `TodayViewModel.practiceSetup(question:route:)`，"
                + "那样 Part、时长、目标这三样才有测试守着。")
    }

    // MARK: - 题库空时，整页只做「去导入」这一件事

    /// 这个分支一度是这一页的头等大事，却没有任何测试钉住：整段删掉、无条件渲染
    /// `routes` + `recentPractice`，`swift test` 全绿。
    ///
    /// 删掉之后用户看到的是：`noRouteCard` 那句「题库里有 0 道题，但四条路线的前提一条都不成立。
    /// 下一步：到「训练题库」看一眼题库是不是正常，若不正常就重新导入一次」——
    /// 对一个刚装好、还没导过题库的人来说，这句话是在说他的题库坏了。
    func testEmptyBankTakesOverTheWholePageInsteadOfShowingRoutes() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("if app.state.questions.isEmpty {"),
            "题库空时整页不再单独走一条分支。用户会看到「题库里有 0 道题，但四条路线的前提"
                + "一条都不成立」——那句话是给「题库坏了」准备的，而他只是还没导入过。"
                + "下一步：把 `if app.state.questions.isEmpty { emptyBank } else { … }` 加回来；"
                + "换一种同样能只显示导入引导的写法，就同步改这条测试。")

        // 声明一次、用一次。只数「出现过」的话，把分支里那句 `emptyBank` 删掉、
        // 只留下面那个 `private var emptyBank` 的声明，这条断言照样绿。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: "emptyBank", in: code), 2,
            "emptyBank 只在源码里出现了一次，也就是光有声明、没人用它——题库空时画出来的是别的东西。"
                + "下一步：确认题库空的那一支显示的确实是那张导入引导。")
    }

    // MARK: - 训练记录这一版还没接上，这件事要说出来

    /// 「本周训练 N/5」和「最近练习」在当前工程里永远不会动：
    /// 全工程没有任何一行往 `CoachState.sessions` 里写东西（接线归 Phase 4，
    /// `TodayViewModelTests.testPracticeRecordingFlagMatchesWhetherAnyCodeWritesSessions`
    /// 扫源码钉着这个事实）。不说这句话，用户练完回到这一页看到的还是 0 次、
    /// 还是「还没有练习记录」，只会以为程序坏了。
    func testThePageSaysPracticeIsNotRecordedYet() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("TodayViewModel.unwiredRecordingNotice("),
            "页面没有交代「训练记录还没接上」。用户在这一页练完一整场，"
                + "回来看到的还是「0/5 次」「还没有练习记录」，会以为程序坏了。"
                + "下一步：把 `TodayViewModel.unwiredRecordingNotice()` 画到页面上"
                + "（记录接上之后它返回 nil，那块交代自己就消失了）。")

        // 同上：光有 `private var recordingNotice` 的声明不算数，页面 body 里得真的摆上它。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: "recordingNotice", in: code), 2,
            "recordingNotice 只在源码里出现了一次，也就是写好了却没摆进页面，用户一个字也看不到。"
                + "下一步：把它放回 body 里（本周进度与「最近练习」之间）。")

        XCTAssertTrue(
            code.contains("TodayViewModel.practiceRecordingIsWired"),
            "「还没有练习记录」那张卡片还在无条件承诺「练完第一场之后，这里会按时间倒序列出最近五次」，"
                + "而这一版练完它也不会变——同一屏上两条互相矛盾的话，用户会照着做不到的那条去做。"
                + "本项目在权限页上已经吃过一次同屏矛盾指令的亏。"
                + "下一步：让那句话跟着 `TodayViewModel.practiceRecordingIsWired` 走，"
                + "记录接上之后再恢复原来的说法。")
    }

    // MARK: - 扫源码用的小工具

    static let viewRelativePath = "Today/TodayView.swift"

    /// 注释里必然要解释「为什么这么写」，连注释一起扫的话这些测试会被自己的说明绊倒。
    ///
    /// 走 `SourceGuard`：文件挪了位置或改了名会**抛错**，而不是拿一段空串继续跑——
    /// 空串会让下面每条 `contains` 恒假、每条 `!contains` 恒真。
    static func todayViewCode() throws -> String { try SourceGuard.code(viewRelativePath) }
}
