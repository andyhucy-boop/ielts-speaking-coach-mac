import Foundation
import XCTest

@testable import IELTSCoachUI

/// 今日训练页上那几件**没法靠数据断言守住、但决定用户看不看得见**的事。
///
/// 三件，都是复审真去改了代码、真跑了测试、真看到全绿才报出来的：
///
/// 1. 「拷贝命令」按钮把 `NSPasteboard.setString` 的返回值丢了，且成功时界面零变化——
///    把整个按钮体换成 `_ = hint`，`swift test` 照样全绿。
/// 2. 「题库空时整页只显示导入引导」这个分支删掉之后，`swift test` 照样全绿。
/// 3. 「训练记录这一版还没接上」这句交代有没有真的画在页面上。
///
/// 前两条本项目都已有对应的范式（`PermissionStatus.copyDiagnostics` 的
/// `ActionNotice`、`QuestionBankViewTests` 的扫源码），这里照着用。
///
/// **扫源码这条路的边界要说清**，边界是实测出来的，不是估计的：
/// - 拦得住的是真实的退化形态——按钮体被掏空、显示那段被删掉、写好的组件没摆进页面、
///   分支被整段拿掉。这四种都真去改了代码、真看到这里变红。
/// - 拦不住的是「代码还在但跑不到」，比如把条件改成 `if let copyNotice, false`：
///   扫源码不执行代码，也就判断不了条件的真假（实测这一种确实溜过去了）。
///   要拦这一种得把界面真的渲染出来（ViewInspector / 快照测试），本项目还没有那套工具。
/// - 画出来好不好看、位置对不对同样不在这里，归 Task 11 人工验收。
///
/// 但「用户看不看得见」不是版面观感，它决定这一页有没有做到计划要求的事。
final class TodayViewTests: XCTestCase {

    // MARK: - 「拷贝命令」：写剪贴板可能失败，失败必须说出来

    private func hint(_ commands: [String]) -> PracticeStartHint {
        PracticeStartHint(route: .planToday, questionLine: nil, commands: commands)
    }

    func testCopyCommandsPutsEveryCommandOnThePasteboard() {
        var written: String?
        _ = hint(["swift run coach questions list",
                  "swift run coach practice p1-home-001"]).copyCommands { text in
            written = text
            return true
        }
        let text = written ?? ""
        XCTAssertTrue(text.contains("swift run coach questions list"))
        XCTAssertTrue(text.contains("swift run coach practice p1-home-001"),
                      "两条命令要一起进剪贴板——只复制第一条，用户粘出来的是半截流程")
    }

    func testCopyCommandsReportsFailureAndGivesAManualFallback() {
        let notice = hint(["swift run coach practice p1-home-001"]).copyCommands { _ in false }
        XCTAssertTrue(notice.isFailure,
                      "`NSPasteboard.setString` 会返回 false（别的进程正占着剪贴板时）。"
                          + "丢掉这个返回值，用户粘出来的是上一次复制的东西")
        XCTAssertTrue(notice.text.contains("没能"), "失败要说出来，不能假装复制成功")
        XCTAssertTrue(notice.text.contains("下一步"), "只说失败不说下一步，用户还是卡在这儿")
        XCTAssertTrue(notice.text.contains("⌘C"), "得留一条不靠剪贴板 API 的退路")
    }

    func testCopyCommandsSuccessAlsoSaysSomething() {
        let notice = hint(["swift run coach practice p1-home-001"]).copyCommands { _ in true }
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("已复制"),
                      "成功时界面一个像素都不变的话，用户分不清是复制好了还是按钮坏了")
        XCTAssertTrue(notice.text.contains("下一步"), "复制完要说清接下来去哪儿粘")
    }

    /// 上面三条只管得住那个函数**算得对**，管不住页面**画不画**它。
    /// 这一条补上后半截：那句交代必须真的进到 sheet 的 body 里。
    func testTheSheetActuallyPaintsTheCopyNotice() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct PracticeStartHintSheet"),
            "没扫到 PracticeStartHintSheet 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewSource.path)

        XCTAssertTrue(
            code.contains("hint.copyCommands("),
            "「拷贝命令」按钮没有调 copyCommands，多半又把 setString 的返回值丢了。"
                + "下一步：按钮里调 `hint.copyCommands(using:)`，把它返回的 ActionNotice 存起来。")

        XCTAssertTrue(
            code.contains("Text(copyNotice.text)"),
            "copyCommands 的结果没有画出来，用户点完按钮界面零变化，分不清是复制好了还是按钮坏了。"
                + "下一步：照 PermissionGateView 的做法用 `@State private var copyNotice: ActionNotice?` "
                + "接住它并显示；换别的显示办法就同步改这条测试。")
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
                + Self.viewSource.path)

        XCTAssertTrue(
            code.contains("if app.state.questions.isEmpty {"),
            "题库空时整页不再单独走一条分支。用户会看到「题库里有 0 道题，但四条路线的前提"
                + "一条都不成立」——那句话是给「题库坏了」准备的，而他只是还没导入过。"
                + "下一步：把 `if app.state.questions.isEmpty { emptyBank } else { … }` 加回来；"
                + "换一种同样能只显示导入引导的写法，就同步改这条测试。")

        // 声明一次、用一次。只数「出现过」的话，把分支里那句 `emptyBank` 删掉、
        // 只留下面那个 `private var emptyBank` 的声明，这条断言照样绿。
        XCTAssertGreaterThanOrEqual(
            DesignSystemTests.occurrences(of: "emptyBank", in: code), 2,
            "emptyBank 只在源码里出现了一次，也就是光有声明、没人用它——题库空时画出来的是别的东西。"
                + "下一步：确认题库空的那一支显示的确实是那张导入引导。")
    }

    // MARK: - 训练记录这一版还没接上，这件事要说出来

    /// 「本周训练 N/5」和「最近练习」在当前工程里永远不会动：
    /// 全工程没有任何一行往 `CoachState.sessions` 里写东西（接线归 Phase 4，
    /// `TodayViewModelTests.testPracticeRecordingFlagMatchesWhetherAnyCodeWritesSessions`
    /// 扫源码钉着这个事实）。不说这句话，用户在终端练完回到这一页看到的还是 0 次、
    /// 还是「还没有练习记录」，只会以为程序坏了。
    func testThePageSaysPracticeIsNotRecordedYet() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewSource.path)

        XCTAssertTrue(
            code.contains("TodayViewModel.unwiredRecordingNotice("),
            "页面没有交代「训练记录还没接上」。用户照这一页自己弹出来的提示在终端练完一整场，"
                + "回到这一页看到的还是「0/5 次」「还没有练习记录」，会以为程序坏了。"
                + "下一步：把 `TodayViewModel.unwiredRecordingNotice()` 画到页面上"
                + "（记录接上之后它返回 nil，那块交代自己就消失了）。")

        // 同上：光有 `private var recordingNotice` 的声明不算数，页面 body 里得真的摆上它。
        XCTAssertGreaterThanOrEqual(
            DesignSystemTests.occurrences(of: "recordingNotice", in: code), 2,
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

    static var viewSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources/IELTSCoachUI/Today/TodayView.swift")
    }

    /// 注释里必然要解释「为什么这么写」，连注释一起扫的话这些测试会被自己的说明绊倒。
    static func todayViewCode() throws -> String {
        DesignSystemTests.strippingLineComments(
            try String(contentsOf: viewSource, encoding: .utf8))
    }
}
