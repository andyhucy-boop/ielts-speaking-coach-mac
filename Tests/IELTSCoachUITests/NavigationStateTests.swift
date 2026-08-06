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
    ///
    /// **只问「文件里出现过 `openRetrainingCenter(` 吗」是不够的。** 复审实测：
    /// 把两张卡片上按钮的动作从 `act(route)` 改回 `startPractice(route)`
    ///（`act(_:)` 的声明原样留着，里面那句跳转也还在），941 条全绿——
    /// 而那时那张卡片又弹回普通练习 sheet，正是上面那个失败形态。
    /// `act(_:)` 不返回 `some View`，`RenderReachabilitySweepTests` 的可达性扫描也看不见它，
    /// 两道防线一起漏。所以这里分两头钉：**按钮真的调 `act(`**，
    /// 而且 **`act(_:)` 的 `.retrain` 那一支真的跳页**。
    func testTheTodayPageRoutesTheRetrainCardToTheRetrainingCenter() throws {
        let today = try SourceGuard.code("Today/TodayView.swift")

        // 一、两张卡片上那颗按钮都必须把决定权交给 `act(_:)`。
        for card in ["private func primaryCard", "private func secondaryCard"] {
            let body = try SourceGuard.memberBody(of: card, in: today)
            XCTAssertTrue(
                body.contains("act(route)"),
                "\(card) 那颗按钮没有走 `act(_:)`。「复训一个旧问题」会当场弹出普通练习 sheet："
                    + "那一场既不带单点目标、也不会挂进复训台账，用户以为自己在复训，"
                    + "其实只是又练了一道题——而且界面上看不出任何异样。"
                    + "下一步：按钮的动作改回 `act(route)`。实际取到的是：\n\(body)")
            XCTAssertFalse(
                body.contains("startPractice("),
                "\(card) 里直接调了 `startPractice(_:)`，绕开了 `act(_:)` 里那一支判断。"
                    + "四条路线里有一条不是开练，绕过去它就会被当成普通练习。"
                    + "实际取到的是：\n\(body)")
            XCTAssertTrue(
                body.contains("actionTitle(route)"),
                "\(card) 的按钮文字是写死的。「复训一个旧问题」点下去是换一页不是开练，"
                    + "写「开始练习」就是骗人。下一步：改回 `actionTitle(route)`。")
        }

        // 二、`act(_:)` 的 `.retrain` 那一支必须跳到复训中心，而且到此为止。
        let act = try SourceGuard.functionBody(named: "act", in: today)
        let retrainBranch = try SourceGuard.memberBody(of: "guard route != .retrain else", in: act)
        XCTAssertTrue(
            retrainBranch.contains("app.navigation.openRetrainingCenter("),
            "`act(_:)` 的 `.retrain` 那一支没有跳到复训中心。"
                + "下一步：那一支改成 `app.navigation.openRetrainingCenter(preselecting: nil)`。"
                + "实际取到的是：\n\(retrainBranch)")
        XCTAssertTrue(
            retrainBranch.contains("return"),
            "`.retrain` 那一支跳完页没有 `return`，接着又把普通练习 sheet 弹了出来——"
                + "用户会同时被换页并被塞进一场不带目标的练习。实际取到的是：\n\(retrainBranch)")
        XCTAssertTrue(
            act.contains("startPractice(route)"),
            "`act(_:)` 里没有 `startPractice(route)`，另外三条路线点下去什么都不会发生。"
                + "实际取到的是：\n\(act)")

        // 三、按钮文字：这条路线点下去是换一页，不是开练。
        let title = try SourceGuard.functionBody(named: "actionTitle", in: today)
        XCTAssertTrue(
            title.contains("route == .retrain") && title.contains("去复训中心"),
            "「复训一个旧问题」那颗按钮不再单独取名。写成「开始练习」的话，"
                + "用户点下去看到的是换了一页，会以为自己点错了。实际取到的是：\n\(title)")
    }
}
