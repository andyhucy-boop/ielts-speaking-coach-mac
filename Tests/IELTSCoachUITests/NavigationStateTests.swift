import XCTest
@testable import IELTSCoachUI

@MainActor
final class NavigationStateTests: XCTestCase {
    func testOpenRetrainingCenterSelectsThePageAndRemembersTheTarget() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: "logic-explain@s0")
        XCTAssertEqual(nav.selection, .retraining)
        XCTAssertEqual(nav.pendingRetrainingTargetID, "logic-explain@s0")
    }

    func testOpeningWithoutATargetJustSwitchesPage() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: nil)
        XCTAssertEqual(nav.selection, .retraining)
        XCTAssertNil(nav.pendingRetrainingTargetID)
    }

    /// 只消费一次。不清空的话，用户在复训中心点开别的目标，
    /// 界面每次重绘都会把他弹回最初那个目标——他会以为点不动。
    func testPendingTargetIsConsumedOnlyOnce() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: "logic-explain@s0")
        XCTAssertEqual(nav.consumePendingRetrainingTarget(), "logic-explain@s0")
        XCTAssertNil(nav.consumePendingRetrainingTarget())
        XCTAssertNil(nav.pendingRetrainingTargetID)
    }

    func testDefaultsToToday() {
        XCTAssertEqual(NavigationState().selection, .today)
    }

    // MARK: - 接线（不在计划的 Step 1 里，理由见各自注释）

    /// **导航状态写好了、页面不读它，等于没写。**
    ///
    /// 上面四条全绿也说明不了任何事：`NavigationState` 可以完美工作，而 `RootView`
    /// 仍然用它自己那个 `@State private var selection` 渲染。那时今日训练页上
    /// 「复训一个旧问题」点下去，`app.navigation.selection` 老老实实变成 `.retraining`，
    /// **屏幕上却一个像素都不动**——用户会以为这颗按钮是坏的。
    ///
    /// 这正是本项目反复栽的那一类（写好了没接上），而它一行编译错误都不会有。
    /// 扫源码不执行代码，拦不住「代码还在但跑不到」；拦得住的是接线被整段拿掉。
    func testTheRootViewTakesItsSelectionFromTheNavigationState() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(
            root.contains("app.navigation.selection"),
            "RootView 没有从 `AppState.navigation` 取当前选中页。跨页跳转"
                + "（今日训练 →「复训一个旧问题」）改的是导航状态，而这一页照自己那份 "
                + "`@State` 渲染，点下去屏幕不会有任何变化。"
                + "下一步：把侧边栏与 detail 都改成读 `app.navigation.selection`。")
        XCTAssertFalse(
            root.contains("@State private var selection"),
            "RootView 又自己持有了一份选中页。两份状态一定会走岔——"
                + "`NavigationState` 那份变了，屏幕上显示的是另一份。"
                + "下一步：删掉这个 `@State`，只留 `app.navigation.selection` 一处。")
        XCTAssertTrue(
            root.contains("case .retraining: RetrainingCenterView("),
            "侧边栏点「复训中心」还是落到占位页——`.retraining` 已经标成做好了，"
                + "用户点进来会看到「这一页还没做」。"
                + "下一步：在 detail 的 switch 里接上 `RetrainingCenterView`。")
    }

    /// 「复训一个旧问题」那张卡片必须真的跳到复训中心。
    ///
    /// 不接的话它会走 `startPractice`，弹出普通练习的 sheet——那一场既不带单点目标、
    /// 也不会挂进复训台账，用户以为自己在复训，其实只是又练了一道题。
    func testTheTodayPageRoutesTheRetrainCardToTheRetrainingCenter() throws {
        let today = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(
            today.contains("app.navigation.openRetrainingCenter("),
            "今日训练页的「复训一个旧问题」没有跳到复训中心。"
                + "下一步：那条路线的动作改成 `app.navigation.openRetrainingCenter(preselecting: nil)`。")
    }
}
