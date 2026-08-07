import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class CoachSettingsViewModelTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "settings-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    /// **注入一个假的环境检查，绝不让测试碰真的 ChatGPT（铁律 5）。**
    ///
    /// 计划 Task 15 这里写的是 `AppState(directory:checksPermissionOnLaunch: false)`，
    /// 理由是「`AppState.init` 会调 `recheckPermission()` → `AXDriver.preflight()`，
    /// 而它会真的去启动 ChatGPT 并最多等 8 秒」。**那段描述对不上今天的代码**：
    /// Phase 8 之后 `AppState.init` 只做 `reload()`（读本地 JSON），环境检查搬到了
    /// 异步的 `startInitialPermissionCheckIfNeeded()` / `recheckPermission()`，
    /// 由 `RootView` 的 `.task` 调用。所以那个开关今天没有任何东西可关，
    /// 加进去只会是一个恒等于 no-op 的参数。
    ///
    /// 改成注入 `preflight`（全仓库现有 20 多处测试的写法）：真实性更强——
    /// 就算将来有人把 preflight 调回构造函数里，跑到的也仍然是这个假实现。
    private func makeAppState() -> AppState {
        AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
    }

    private func viewModel(_ app: AppState) -> CoachSettingsViewModel {
        CoachSettingsViewModel(app: app, directory: directory)
    }

    // MARK: - 分区

    func testThereAreExactlyFourSections() {
        // 断言确切数量而不是「至少四个」：多出来的第五个分区
        // 意味着又有设置散到别处去了，那正是这次合并要消灭的事。
        XCTAssertEqual(SettingsSection.allCases,
                       [.recording, .goals, .practice, .data])
    }

    func testEverySectionHasATitleAnIconAndOneLineOfWhatItIsFor() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty, "\(section) 没标题")
            XCTAssertFalse(section.systemImage.isEmpty, "\(section) 没图标")
            XCTAssertFalse(section.summary.isEmpty,
                           "\(section) 没写这一栏管什么——用户得点进去猜")
        }
    }

    func testSectionTitlesAreUnique() {
        let titles = SettingsSection.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "有两个分区重名")
    }

    // MARK: - 读

    func testReadsWhateverIsOnDisk() throws {
        try StateStore(directory: directory).mutate { state in
            state.settings.weeklyGoal = 7
            state.settings.feedbackTiming = .immediate
            state.settings.part2PrepMode = .learnerControlled
        }
        let settings = viewModel(makeAppState())
        XCTAssertEqual(settings.weeklyGoal, 7)
        XCTAssertEqual(settings.feedbackTiming, .immediate)
        XCTAssertEqual(settings.part2PrepMode, .learnerControlled)
    }

    /// 「记录对话逐字稿」（Phase 4 Task 2 的字段，默认开）也归练习偏好这一分区。
    /// 默认值那一支单独断一次：写成 `true` 常量也能骗过下面那条「关掉之后是 false」。
    func testReadsTheTranscriptSwitchFromDisk() throws {
        let fresh = viewModel(makeAppState())
        XCTAssertTrue(fresh.transcriptEnabled, "这个开关默认是开的（跨阶段决策 5）")

        try StateStore(directory: directory).mutate { $0.settings.transcriptEnabled = false }
        let reopened = viewModel(makeAppState())
        XCTAssertFalse(reopened.transcriptEnabled)
    }

    // MARK: - 写

    func testChangingAGoalPersistsAndIsVisibleImmediately() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(9)

        XCTAssertNil(settings.error)
        XCTAssertEqual(settings.weeklyGoal, 9)
        XCTAssertEqual(app.state.settings.weeklyGoal, 9, "主窗口读的是同一个 AppState")
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 9,
                       "还得真的落盘，不能只是界面上变了个样子")
    }

    /// **本任务最要紧的一条。** 「在设置窗口改了，主窗口立刻看到」。
    /// 两个视图模型代表两个窗口，它们背后是同一个 AppState。
    func testASecondWindowSeesTheChangeWithoutBeingTold() {
        let app = makeAppState()
        let settingsWindow = viewModel(app)
        let mainWindow = viewModel(app)

        settingsWindow.setWeeklyGoal(9)
        settingsWindow.setFeedbackTiming(.immediate)

        XCTAssertEqual(mainWindow.weeklyGoal, 9,
                       "另一个窗口还显示旧的每周目标——这正是「设置散在两处」最难查的那种 bug")
        XCTAssertEqual(mainWindow.feedbackTiming, .immediate)
    }

    func testOutOfRangeGoalsAreClampedNotRejected() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(999)
        // 界面上的 Stepper 有边界，但手改过的 state.json、别的版本写进来的值都会走到这里。
        // 归一，不报错——一个坏掉的目标数字不该让人没法用设置页。
        XCTAssertEqual(settings.weeklyGoal, CoachSettings.defaultWeeklyGoal)
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal,
                       CoachSettings.defaultWeeklyGoal)
    }

    func testChangingTheDefaultRouteRoundTripsThroughTheStringInSettings() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        for route in PracticeRoute.allCases {
            settings.setDefaultRoute(route)
            XCTAssertEqual(settings.defaultRoute, route, "\(route) 存下去再读回来变了样")
        }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.defaultRoute,
                       PracticeRoutePreference.rawValue(for: PracticeRoute.allCases.last!))
    }

    func testEveryPracticePreferenceLandsOnDisk() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setFeedbackTiming(.immediate)
        settings.setPart2PrepMode(.learnerControlled)

        let saved = try StateStore(directory: directory).load().settings
        XCTAssertEqual(saved.feedbackTiming, .immediate)
        XCTAssertEqual(saved.part2PrepMode, .learnerControlled)
    }

    /// 「记录对话逐字稿」的写入口。照抄「反馈时机」那两条：落盘 + 另一个窗口立刻看得到。
    /// **Task 16 会把 `AppState.setTranscriptEnabled` 删掉，从此这里是唯一入口。**
    func testTurningOffTheTranscriptSwitchPersistsAndIsVisibleInBothWindows() throws {
        let app = makeAppState()
        let settingsWindow = viewModel(app)
        let mainWindow = viewModel(app)

        settingsWindow.setTranscriptEnabled(false)

        XCTAssertNil(settingsWindow.error)
        XCTAssertFalse(settingsWindow.transcriptEnabled)
        XCTAssertFalse(mainWindow.transcriptEnabled, "另一个窗口还显示「记录逐字稿：开」")
        XCTAssertFalse(try StateStore(directory: directory).load().settings.transcriptEnabled,
                       "还得真的落盘——不落盘的话下次开练照样在记录，而开关显示的是关")
    }

    func testChangingOneSettingDoesNotResetTheOthers() throws {
        // CoachSettings 被 Phase 5 / 7 / 8 各加过字段。
        // 用「整体替换」的写法很容易把别人的字段顺手清成默认值，而且不会报错。
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(7)
        settings.setFeedbackTiming(.immediate)
        settings.setPart2PrepMode(.learnerControlled)
        settings.setWeeklyGoal(8)

        let saved = try StateStore(directory: directory).load().settings
        XCTAssertEqual(saved.weeklyGoal, 8)
        XCTAssertEqual(saved.feedbackTiming, .immediate, "改每周目标把反馈时机清掉了")
        XCTAssertEqual(saved.part2PrepMode, .learnerControlled, "改每周目标把准备模式清掉了")
    }

    // MARK: - 写不进去的时候

    func testAFailedWriteSaysSoAndDoesNotPretendItWorked() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        // 把数据目录换成一个不可写的位置，制造真实的写盘失败。
        try FileManager.default.removeItem(at: directory.root)
        try Data("不是目录".utf8).write(to: directory.root)

        settings.setWeeklyGoal(9)

        let message = try XCTUnwrap(settings.error, "写盘失败却什么都不说")
        XCTAssertTrue(message.contains("下一步"), "没告诉用户下一步做什么：\(message)")
        XCTAssertNotEqual(settings.weeklyGoal, 9,
                          "没存进去却显示成 9 —— 用户下次打开会发现又变回去了，且永远不知道为什么")
    }

    // MARK: - 数据与隐私

    func testDataSectionShowsTheRealDirectoryAndItsUsage() throws {
        try Data(repeating: 0x41, count: 2_048)
            .write(to: directory.recordingsDirectory.appending(path: "a.m4a"))
        let settings = viewModel(makeAppState())
        settings.refreshUsage()

        XCTAssertEqual(settings.dataDirectoryURL, directory.root)
        XCTAssertEqual(settings.usage.totalBytes, 2_048)
        XCTAssertFalse(settings.usage.summaryText.isEmpty)
    }

    // MARK: - 文案

    func testTheWeeklyGoalHintComesFromTheSharedEditorNotAFreshCopy() {
        // WeeklyGoalEditor 是 Phase 7 定的文案，测试也在那边。
        // 设置窗口再写一份「还差几次」的句子，两处迟早说不一样的话。
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(5)
        XCTAssertEqual(settings.weeklyGoalHint,
                       WeeklyGoalEditor.hint(done: 0, goal: 5))
    }
}
