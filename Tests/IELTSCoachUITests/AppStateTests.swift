import ChatGPTBridge
import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 假的麦克风权限查询。**测试里绝不允许构造 `SystemMicrophoneAuthorizer`**
/// （Phase 5 计划 Global Constraints）：`swift test` 跑的是没有 bundle id、
/// 没有 Info.plist 的命令行进程；何况真实实现的返回值取决于跑测试这台机器授过什么权，
/// 直接依赖它的测试今天绿明天红。
///
/// 这里一律答「没授权」：本文件只关心「造出来的是不是那台真协调器」，
/// 而没授权是最安全的那个答案——就算谁误调了 `begin()` 也一定录不起来。
private struct StubMicrophoneAuthorizer: MicrophoneAuthorizing {
    func currentStatus() -> MicrophonePermissionState { .denied }
    func requestAccess() async -> MicrophonePermissionState { .denied }
}

/// 记下「App 到底把什么交到了录音器手上」的假工厂。**不碰麦克风（铁律 5）。**
///
/// 断言落在「交出去的开关快照与目录」上而不是「工厂被调了几次」：调用次数对不对，
/// 换不来用户练完之后真的有一个能回放的文件。
private final class RecordingFactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private let recording: any PracticeRecording
    private var handedStore: RecordingStore?
    private var handedSettings: CoachSettings?

    init(_ recording: any PracticeRecording = FakeRecording()) { self.recording = recording }

    var store: RecordingStore? { lock.withLock { handedStore } }
    var settings: CoachSettings? { lock.withLock { handedSettings } }

    /// 注入给 `AppState` 的那一份工厂。
    var make: @Sendable (RecordingStore, CoachSettings) -> any PracticeRecording {
        { [self] store, settings in
            lock.withLock {
                handedStore = store
                handedSettings = settings
            }
            return recording
        }
    }
}

/// 可数次数的假 preflight。**全程不接触真实 ChatGPT（铁律 5）。**
/// 计数会在后台线程上被改（`recheckPermission` 特意把检查挪出主线程），所以要加锁。
private final class PreflightSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0
    private let result: BridgeReadiness

    init(_ result: BridgeReadiness = BridgeReadiness(ok: true, messages: ["✅ 环境就绪"])) {
        self.result = result
    }

    var calls: Int { lock.withLock { invocations } }

    func run() -> BridgeReadiness {
        lock.withLock { invocations += 1 }
        return result
    }
}

/// 可以卡在半路的假 preflight。
///
/// 真实的 `preflight()` 要跑最多十秒（`NSWorkspace.open` 拉起 ChatGPT +
/// `wakeAccessibilityTree(timeout: 8.0)`），而「这十秒里界面在说什么」正是要测的东西。
/// 所以这里让它停在「正在跑」的那一刻，测试趁机去看状态。
/// **全程不接触真实 ChatGPT（铁律 5），也不无限等待（铁律 5）**——等不到就报错收工。
private final class GatedPreflight: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private let proceed = DispatchSemaphore(value: 0)
    private let result: BridgeReadiness

    init(_ result: BridgeReadiness) { self.result = result }

    /// 注入给 AppState 的那一份。跑在后台线程上（`recheckPermission` 特意把它挪出主线程）。
    func run() -> BridgeReadiness {
        lock.withLock { running = true }
        proceed.wait()
        lock.withLock { running = false }
        return result
    }

    var isRunning: Bool { lock.withLock { running } }

    /// 放它走。先放行也没关系——信号量会记着，`run()` 到了不会停。
    func letItFinish() { proceed.signal() }

    /// 等到 preflight 真的开跑。**有上限**，等不到就让测试红着收工，绝不无限等。
    func waitUntilRunning(timeout: TimeInterval = 5,
                          file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !isRunning {
            guard Date() < deadline else {
                XCTFail("等了 \(timeout) 秒，注入的 preflight 一次都没被调用。"
                        + "下一步：确认 recheckPermission 真的会去跑 preflight。",
                        file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-ui-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 构造 AppState 不许去驱动 ChatGPT

    func testCreatingAppStateDoesNotRunTheEnvironmentCheck() async {
        let spy = PreflightSpy()
        let app = AppState(directory: directory, preflight: { spy.run() })

        // preflight 会启动 ChatGPT 并最多轮询 8 秒等无障碍树醒过来。放在构造函数里，
        // 等于窗口还没画出来就先冻住十秒（DESIGN-SYSTEM 第 5 节：超过 300ms 必须有反馈）。
        XCTAssertEqual(spy.calls, 0, "构造 AppState 不该顺手去驱动 ChatGPT")
        XCTAssertTrue(app.isCheckingPermission, "还没查出结论前必须是「正在检查」")

        await app.startInitialPermissionCheckIfNeeded()
        XCTAssertEqual(spy.calls, 1)
        XCTAssertFalse(app.isCheckingPermission)
    }

    func testInitialCheckRunsOnlyOnceNoMatterHowOftenTheViewAsks() async {
        // `.task` 会随视图切换重新触发。没有这道闸就是死循环：
        // 查完 → 换屏 → 又触发检查 → isCheckingPermission 变回 true → 换回等待屏 → 再查。
        let spy = PreflightSpy()
        let app = AppState(directory: directory, preflight: { spy.run() })

        await app.startInitialPermissionCheckIfNeeded()
        await app.startInitialPermissionCheckIfNeeded()
        await app.startInitialPermissionCheckIfNeeded()

        XCTAssertEqual(spy.calls, 1, "首次环境检查被重复触发了")
    }

    func testRecheckAlwaysRunsAgainBecauseTheUserAskedForIt() async {
        let spy = PreflightSpy()
        let app = AppState(directory: directory, preflight: { spy.run() })

        await app.startInitialPermissionCheckIfNeeded()
        await app.recheckPermission()

        XCTAssertEqual(spy.calls, 2, "用户点了「重新检查」就必须真的再查一次")
    }

    // MARK: - 重查的那十秒里，界面必须一直在说话

    /// **这条是问题 3 的判据。**
    ///
    /// `recheckPermission()` 里的 `isCheckingPermission = true` 是「用户点了『重新检查』
    /// 期间界面有反馈」的唯一实现：`RootRouter` 靠它切到「正在检查运行环境…」那一屏。
    /// 复审实测把这一行删掉，245 条全绿——首次检查那条路径有测试（初值就是 true），
    /// 重查这条没有。删掉之后，用户点完按钮要对着一动不动的授权页等最多十秒，且零反馈。
    ///
    /// 所以这里把 preflight 卡在半路，趁它还在跑的时候去看界面该显示哪一屏。
    func testRecheckSaysItIsCheckingWhileThePreflightIsStillRunning() async {
        let gate = GatedPreflight(BridgeReadiness(ok: false, messages: [
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能…"
        ]))
        let app = AppState(directory: directory, preflight: { gate.run() })

        gate.letItFinish()                       // 首次检查不卡
        await app.startInitialPermissionCheckIfNeeded()
        XCTAssertFalse(app.isCheckingPermission, "首次检查跑完了却还说在检查")

        let recheck = Task { await app.recheckPermission() }
        await gate.waitUntilRunning()             // 这一次卡住，模拟真实的那十秒

        XCTAssertTrue(app.isCheckingPermission,
                      "重查已经在跑了，AppState 却说没在检查。"
                          + "下一步：确认 `recheckPermission` 那条路径上还有没有 "
                          + "`isCheckingPermission = true`。")
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: app.isCheckingPermission,
                              permission: app.permission, questionCount: 0,
                              hasCompletedOnboarding: false, onboardingDismissed: false),
            .checkingEnvironment,
            "重查的这十秒里路由一路返回引导页：用户点完「重新检查」，"
                + "屏幕上一个像素都不会变，只能对着授权那一步干等。")

        gate.letItFinish()
        await recheck.value
        XCTAssertFalse(app.isCheckingPermission, "查完了还挂着「正在检查」，界面会一直转圈")
    }

    // MARK: - 「重新检查」按下去必须有反馈

    /// 重查结论和上一次一样时，`permission` 和 `permissionMessages` 都不变，页面别处
    /// 一个像素都不会变。这个计数是那句「已重新检查，仍未通过」唯一的触发条件。
    func testEachRecheckIsCountedSoThePageCanSayItAlreadyChecked() async throws {
        let app = appOverFakeChatGPT(installed: true, trusted: false)

        await app.startInitialPermissionCheckIfNeeded()
        XCTAssertEqual(app.recheckAttempts, 0,
                       "开机第一次自动检查被算成了「用户点的重新检查」——"
                           + "用户会在开机第一眼看到「已重新检查，仍未通过」，"
                           + "那是在回答一个他还没问的问题")
        XCTAssertNil(PermissionStatus.recheckNotice(completedAttempts: app.recheckAttempts,
                                                    state: app.permission,
                                                    host: .app(name: "IELTS Speaking Coach")))

        await app.recheckPermission()
        XCTAssertEqual(app.recheckAttempts, 1, "用户点了「重新检查」，这一次没被记下来")

        // 结论一模一样：state / messages 都没变，页面上唯一会变的就是这句话。
        XCTAssertEqual(app.permission, .needsAccessibility)
        let notice = try XCTUnwrap(
            PermissionStatus.recheckNotice(completedAttempts: app.recheckAttempts,
                                           state: app.permission,
                                           host: .app(name: "IELTS Speaking Coach")),
            "重查完了，页面还是一个字都不说，用户分不清是「查过了还是不行」还是「按钮坏了」")
        XCTAssertTrue(notice.text.contains("已重新检查"), notice.text)

        await app.recheckPermission()
        XCTAssertEqual(app.recheckAttempts, 2, "连按两次，第二次没被记下来——文案一字不变，"
                       + "第二次又回到「按钮是不是坏了」")
    }

    // MARK: - preflight 说了什么，界面就得看到什么

    /// 让 `AXDriver.preflight()` 的**真实输出**流过 AppState，而不是喂一份手写的
    /// `BridgeReadiness`——后者管不住「AppState 把消息丢了」以外的任何退化。
    private func appOverFakeChatGPT(installed: Bool, trusted: Bool) -> AppState {
        let access = FakeAXAccess()
        access.installed = installed
        access.trusted = trusted
        return AppState(directory: directory, preflight: {
            AXDriver(access: access,
                     locator: AXLocator(access: access, pollInterval: 0.01),
                     shortTimeout: 0.2, stateTimeout: 0.2,
                     host: .app(name: "IELTS Speaking Coach")).preflight()
        })
    }

    func testCarriesThePreflightVerdictAndItsOriginalMessages() async {
        let app = appOverFakeChatGPT(installed: true, trusted: false)
        await app.startInitialPermissionCheckIfNeeded()

        XCTAssertEqual(app.permission, .needsAccessibility)
        XCTAssertTrue(app.permissionMessages.joined().contains("辅助功能"),
                      "preflight 的原文必须带到界面上，否则权限页下方的「检查结果原文」是空的："
                      + app.permissionMessages.joined())
    }

    func testReadyEnvironmentIsRecognized() async {
        let app = appOverFakeChatGPT(installed: true, trusted: true)
        await app.startInitialPermissionCheckIfNeeded()
        XCTAssertEqual(app.permission, .ready)
    }

    // MARK: - 读不到训练数据不许闷着（铁律 7）

    func testCorruptedStateFileIsReportedWithTheFileAndTheNextStep() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)

        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })

        let message = try XCTUnwrap(app.loadError,
                                    "读不到训练数据却一声不吭，用户会以为自己的练习记录没了")
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        XCTAssertTrue(message.contains(directory.stateFile.path),
                      "得指名是哪个文件出了事，否则用户无从下手：" + message)
        XCTAssertTrue(app.state.questions.isEmpty, "读失败时不该冒充出一份有内容的状态")
    }

    func testUnexpectedFailureStillGetsAChineseNextStep() throws {
        // 数据目录该在的位置被一个同名文件占了。这时抛出来的是系统的 NSError：
        // 既没有「下一步」，措辞也未必是中文。直接把 localizedDescription 摆给用户，
        // 等于把他扔在半路（铁律 6）。
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-ui-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = DataDirectory(root: root)

        let app = AppState(directory: blocked, preflight: { .init(ok: true, messages: []) })

        let message = try XCTUnwrap(app.loadError)
        XCTAssertTrue(message.contains("下一步"),
                      "系统给的报错不带下一步，必须由我们补上：" + message)
        XCTAssertTrue(message.contains(blocked.stateFile.path),
                      "得指名是哪个文件出了事：" + message)
    }

    func testReloadClearsTheErrorAndPicksUpTheDataOnceItIsReadable() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        XCTAssertNotNil(app.loadError)

        var fixed = CoachState.empty()
        fixed.questions = [Question(id: "q1", part: 1, topic: "Home",
                                    prompt: "Do you live in a house or a flat?")]
        try JSONEncoder().encode(fixed).write(to: directory.stateFile)

        app.reload()

        XCTAssertNil(app.loadError, "问题已经解决还挂着旧错误，用户会以为没修好")
        XCTAssertEqual(app.state.questions.map(\.id), ["q1"])
    }

    func testMissingStateFileIsNotAnError() throws {
        // 第一次打开本应用时 state.json 根本不存在，这是正常的，不该吓唬用户。
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        XCTAssertNil(app.loadError)
        XCTAssertTrue(app.state.questions.isEmpty)
    }

    // MARK: - 导入题库必须真的落盘（铁律 7）

    private func importResult(_ questions: [Question], title: String = "季度题库") -> ImportResult {
        ImportResult(
            questions: questions,
            source: QuestionSource(title: title, sourceUrl: "",
                                   importedAt: "2026-08-06T00:00:00Z",
                                   importLevel: "full-question", questionCount: questions.count),
            warnings: [])
    }

    func testImportMergesIntoTheBankAndWritesItToDisk() throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })

        let outcome = try app.applyImport(importResult([
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?"),
            Question(id: "q2", part: 2, topic: "Skills", prompt: "Describe a useful skill.")
        ]))

        XCTAssertEqual(outcome.importedCount, 2)
        XCTAssertEqual(outcome.totalCount, 2)
        XCTAssertEqual(app.state.questions.map(\.id), ["q1", "q2"],
                       "导入完界面上的题库没跟着变，用户会以为导入没生效")

        // **这一段是这条测试的牙齿。** 只改内存不落盘的话上面三条照样全绿，
        // 而用户重开一次 App 题就没了。所以换一个全新的 StateStore 从磁盘再读一遍。
        let onDisk = try StateStore(directory: directory).load()
        XCTAssertEqual(onDisk.questions.map(\.id), ["q1", "q2"], "题库没有写进 state.json")
        XCTAssertEqual(onDisk.questionSources.map(\.title), ["季度题库"],
                       "没记下这批题是从哪份文件来的")
    }

    func testImportingTheSameQuestionAgainUpdatesItInsteadOfDuplicating() throws {
        // 雅思题库每季度换题，二次导入是常态。同 id 必须覆盖，不能变成两道一模一样的题。
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        _ = try app.applyImport(importResult([
            Question(id: "q1", part: 1, topic: "Home", prompt: "旧的题干")
        ]))

        let outcome = try app.applyImport(importResult([
            Question(id: "q1", part: 1, topic: "Home", prompt: "新的题干")
        ], title: "秋季题库"))

        XCTAssertEqual(outcome.totalCount, 1, "同一道题被导入成了两道")
        XCTAssertEqual(app.state.questions.map(\.prompt), ["新的题干"], "重新导入没有覆盖旧题干")
    }

    /// **复审第 10 条走界面这条路的判据。**
    ///
    /// 「导入题库」按钮通往合并的唯一生产路径就是 `applyImport`。
    /// `QuestionStatusAcrossImportsTests` 测的是 `merge` 这个纯函数，跨不过这一层——
    /// 哪天有人在 `applyImport` 里顺手补一句「导入完把 status 归位」，那边照样全绿。
    ///
    /// 用户会经历的：换季导完，题库页顶上「已经练过 N 题」的数字掉下去、
    /// 每道题右边的勾消失，全程没有提示、没有报错，而引导页刚保证过「换季重新导入是安全的」。
    func testASeasonalReimportThroughTheImportButtonKeepsThePracticedMarks() throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        _ = try app.applyImport(importResult([
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?")
        ], title: "夏季题库"))
        // 练完一场（`ReviewArchiver` 就是这么标的），顺带留下证明它练过的那条记录。
        try StateStore(directory: directory).mutate { state in
            state.questions[0].status = "practiced"
            state.sessions = [PracticeSession(
                id: "2026-08-06-001", questionId: "q1", focusPart: .part1,
                startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                goal: "", transcript: [], reportPath: "", recordingPath: "")]
        }
        app.reload()

        _ = try app.applyImport(importResult([
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?"),
            Question(id: "q2", part: 2, topic: "Skills", prompt: "Describe a useful skill.")
        ], title: "秋季题库"))

        XCTAssertEqual(app.state.questions.first { $0.id == "q1" }?.status, "practiced",
                       "换季重新导入把「已练」标记抹回「没练过」了——题库页那个数字会掉下去，"
                           + "而这个标记丢了就再也回不来")
        XCTAssertEqual(app.state.questions.first { $0.id == "q2" }?.status, "new",
                       "新题被误标成练过了")
        XCTAssertEqual(try StateStore(directory: directory).load()
                        .questions.first { $0.id == "q1" }?.status, "practiced",
                       "内存里对了，磁盘上还是抹掉的——重开一次 App 又没了")
    }

    // MARK: - 删除按钮不许删掉别的东西（复审第 4 条）

    /// **这条走的是删除按钮唯一的生产路径 `AppState.deleteSession`，用真实文件系统。**
    ///
    /// `SessionDeleterTests` 那几条直接 new 一台 `SessionDeleter`；
    /// 而按钮走的是这里这条路，`AppState` 在中间还会 `reload()` 一次——
    /// 修之前那一次 reload 读到的是「文件不存在 → 静默返回一份空数据」，
    /// 于是用户眼睁睁看着所有东西在点一下之后消失，同时被告知一切正常。
    ///
    /// 触发前提不是纯理论：本工具自己的录音错误提示会引导用户
    /// 「打开数据目录里的 state.json，检查这一条的 recordingPath 字段」。
    func testDeletingASessionWithATamperedPathDoesNotWipeTheWholeDataFile() throws {
        let session = PracticeSession(
            id: "2026-08-06-001", questionId: "q1", focusPart: .part1,
            startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
            goal: "", transcript: [],
            reportPath: "", recordingPath: "recordings/../state.json")
        try StateStore(directory: directory).mutate { state in
            state.sessions = [session]
            state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "题干")]
        }
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })

        let notice = app.deleteSession(session)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path),
                      "state.json 被删掉了：全部练习记录、错题本、词汇本、复训目标、题库、"
                          + "设置在点一下之后一次性消失")
        XCTAssertNotNil(notice, "拒绝了却一个字都不说，用户只会以为按钮坏了（铁律 5）")
        XCTAssertEqual(app.state.sessions.map(\.id), ["2026-08-06-001"],
                       "路径不合法时那一条要留着——它是用户找到那条坏路径的唯一线索")
        XCTAssertEqual(try StateStore(directory: directory).load().questions.count, 1,
                       "题库跟着没了")
    }

    // MARK: - 「记录对话逐字稿」开关必须真的落盘（铁律 7）
    //
    // **Phase 10 Task 16 之后，这个开关的写入口只剩 `CoachSettingsViewModel` 一处**
    //（`AppState.setTranscriptEnabled` 已删）。这三条跟着改走那条路，
    // 断言一条没放宽——它们守的从来不是某个方法名，而是「拨过去的开关真的到了磁盘上」。

    /// **这条的牙齿在最后那三行。**
    ///
    /// 只改内存不落盘的话，前面几条照样全绿：界面上开关确实拨过去了，
    /// 用户关掉 App 再打开却发现它自己弹了回来。而这个开关管的是「练习时记不记逐字稿」，
    /// 弹回去意味着用户以为关掉了、实际还在记——界面显示的状态和真实行为对不上，
    /// 是本项目最不能接受的那一种失败。
    ///
    /// 所以这里换一个全新的 `StateStore` 从磁盘再读一遍（与题库导入那条同一个手法）。
    func testTurningTheTranscriptSwitchOffSurvivesARestart() throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        let settings = CoachSettingsViewModel(app: app, directory: directory)
        XCTAssertTrue(app.state.settings.transcriptEnabled, "ROADMAP 第 5 节写明默认是开的")

        settings.setTranscriptEnabled(false)

        XCTAssertNil(settings.error, "写成功了却挂着一条错误信息")
        XCTAssertFalse(app.state.settings.transcriptEnabled,
                       "拨完开关主窗口那份状态没跟着变，训练记录页那一行还写着「开」")
        XCTAssertFalse(try StateStore(directory: directory).load().settings.transcriptEnabled,
                       "开关只改了内存没写进 state.json——用户关掉 App 再打开它就弹回来了")
    }

    func testTurningItBackOnAlsoSticks() throws {
        // 单向测试是个常见的空转陷阱：`{ $0.settings.transcriptEnabled = false }`
        // 这种写死取值的实现，只测「关」的话是绿的。
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        let settings = CoachSettingsViewModel(app: app, directory: directory)
        settings.setTranscriptEnabled(false)

        settings.setTranscriptEnabled(true)

        XCTAssertTrue(app.state.settings.transcriptEnabled)
        XCTAssertTrue(try StateStore(directory: directory).load().settings.transcriptEnabled,
                      "再打开的那一次没写进 state.json")
    }

    /// 写盘失败必须让用户看见（铁律 7）。
    ///
    /// 静默失败在这里格外要命：用户以为逐字稿已经关掉了，实际上练习时还在记。
    func testAFailedWriteSaysSoInsteadOfLettingTheSwitchLie() throws {
        // 数据目录该在的位置被一个同名文件占了，`store.mutate` 必然抛错。
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-ui-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = DataDirectory(root: root)
        let app = AppState(directory: blocked, preflight: { .init(ok: true, messages: []) })
        let settings = CoachSettingsViewModel(app: app, directory: blocked)

        settings.setTranscriptEnabled(false)

        let message = try XCTUnwrap(settings.error, "写盘失败却一声不吭")
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        // **开关不许撒谎。** 没存进去就得照旧显示「开」——显示成「关」而练习还在记，
        // 正是这条测试名字里那个 lie。
        XCTAssertTrue(settings.transcriptEnabled,
                      "没存进去却显示成「关」，用户以为逐字稿停了，实际上还在记")
    }

    // MARK: - 删一条训练记录（复审 BI-1：这条路径此前一条行为测试都没有）

    /// 造一条练习记录，顺手把它的复盘报告真的写到磁盘上。
    ///
    /// **报告文件必须真的存在**：`SessionDeleter` 里那句 `guard fileRemover.fileExists`
    /// 会跳过不存在的文件，拿一个空路径来测的话，「复盘报告有没有被删掉」永远是真的。
    private func recordSession(id: String, reportPath: String) throws -> PracticeSession {
        try Data("{\"summary\":\"这份复盘必须跟着记录一起消失\"}".utf8)
            .write(to: directory.root.appending(path: reportPath))
        let session = PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                                      startedAt: "2026-08-06T10:00:00Z",
                                      endedAt: "2026-08-06T10:20:00Z",
                                      goal: "", transcript: [],
                                      reportPath: reportPath, recordingPath: "")
        try StateStore(directory: directory).mutate { $0.sessions.append(session) }
        return session
    }

    /// **这条是复审 BI-1 的判据。**
    ///
    /// `AppState.deleteSession(_:)` 是删除按钮通往 `SessionDeleter` 的**唯一**生产路径，
    /// 此前守着它的只有 `HistoryViewTests` 里一句扫源码的「视图里调了它」——
    /// 那句话对函数体里写了什么一无所知。复审实测过两次突变，656 条一条不红：
    ///
    /// - 整个函数体换成 `_ = session; return nil`；
    /// - 只删掉里面那句 `reload()`。
    ///
    /// 后果是用户点「删除这一场」、在确认框里确认，记录没删、复盘报告还留在磁盘上，
    /// 而 `deletionFailure` 是 nil，界面一个字都不会说——界面显示的状态和真实行为对不上，
    /// 正是本项目最忌讳的那一种失败。
    ///
    /// `SessionDeleterTests` 那 8 条跨不过 `AppState` 这一层：它们直接 new 一台
    /// `SessionDeleter` 来测，删除按钮走的却是这里这条路。
    func testDeletingASessionTakesItOffThePageAndOffTheDisk() throws {
        let reportPath = "reports/2026-08-06-001.json"
        let reportURL = directory.root.appending(path: reportPath)
        let session = try recordSession(id: "2026-08-06-001", reportPath: reportPath)
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        XCTAssertEqual(app.state.sessions.map(\.id), ["2026-08-06-001"],
                       "前提就没成立：这条记录压根没进到界面读的那份 state 里，"
                           + "下面「删掉之后没了」就成了一句废话。")

        let failure = app.deleteSession(session)

        XCTAssertNil(failure,
                     "一切顺利却返回了一段给用户看的说明，界面会挂出「这次删除只做完了一半」："
                         + (failure ?? ""))
        // **这一条咬的是 `reload()`。** 不重读的话那一行还留在界面上，
        // 用户会再点一次删除，而这一次删的是一条已经不存在的记录。
        XCTAssertTrue(app.state.sessions.isEmpty,
                      "删完没有重读，界面上那一行还在——用户会以为删除按钮坏了，再点一次。")
        XCTAssertTrue(try StateStore(directory: directory).load().sessions.isEmpty,
                      "记录只从内存里去掉了，没写进 state.json——关掉 App 再打开它就回来了。")
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path),
                       "这一场的复盘报告还躺在磁盘上（\(reportURL.path)）。"
                           + "确认框里明写着「它的复盘报告都会从磁盘上消失」，那就得真的消失。")
    }

    /// 复盘报告删不掉时，那段中文说明必须一路传到界面上（铁律 7）。
    ///
    /// 没有这一条的话，`deleteSession` 里的 `return failure` 改成 `return nil` 不会有人红：
    /// 记录照样从列表里消失，用户完全不知道磁盘上还躺着一个孤儿复盘文件。
    func testAReportThatCannotBeDeletedIsSaidOutLoudInsteadOfSwallowed() throws {
        // 以 root 跑测试时权限位拦不住 unlink，这条什么也测不到——直接跳过，不假装绿。
        try XCTSkipIf(getuid() == 0, "以 root 身份跑时权限位拦不住删除，这条测不到东西")
        let reportPath = "reports/2026-08-06-002.json"
        let session = try recordSession(id: "2026-08-06-002", reportPath: reportPath)
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        // 把 reports 目录设成不可写：里面的文件删不掉，而 state.json 在数据目录根上，
        // 照常写得进去——这正是「记录删了、文件没删掉」那一半失败。
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: directory.reportsDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: directory.reportsDirectory.path)
        }

        let message = try XCTUnwrap(app.deleteSession(session),
                                    "复盘报告没删掉却一声不吭。用户永远不会知道磁盘上还躺着它。")

        XCTAssertTrue(message.contains(reportPath),
                      "没说清是哪个文件没删掉，用户拿这句话找不到东西：" + message)
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        XCTAssertTrue(app.state.sessions.isEmpty,
                      "文件删不掉把记录本身的删除也拦下了——用户会卡在一条删不掉的记录上，"
                          + "而他真正想做的只是让它从列表里消失。")
    }

    // MARK: - 内嵌播放器必须接到同一个数据目录上（Phase 5 复审 2026-08-07）

    /// **这条守的是「接错了也全绿」那一类，本项目栽过四次。**
    ///
    /// `makeRecordingPlaybackViewModel(for:)` 此前没有任何运行期测试：守着它的只有
    /// `RecordingPlayerViewTests` 里一句扫源码的「HistoryView 调了它」——那句话证明
    /// 「调了」，不证明「调出来的东西指向同一个数据目录」。复审实测把这个方法里的
    /// `store` 与 `recordings` 双双换成另一个目录，827 条一条不红。
    ///
    /// 后果正是这个方法自己的文档注释写着的那一条：训练记录页上每一场都显示
    /// 「录音文件找不到了」，而文件其实好端端地躺在磁盘上；删录音则会写进一个
    /// 不相干的 state.json，用户点完删除，这边的记录一个字都没变。
    ///
    /// `RecordingPlaybackViewModelTests` 那一组跨不过 `AppState` 这一层：
    /// 它们自己把 `store` 和 `recordings` 传了进去，接线接到哪儿它们看不见。
    func testTheEmbeddedPlayerReadsAndWritesTheSameDataDirectoryAsTheApp() throws {
        let audioURL = directory.recordingsDirectory.appending(path: "x.m4a")
        try Data(repeating: 0x41, count: 128).write(to: audioURL)
        let session = PracticeSession(id: "2026-08-07-001", questionId: "q1", focusPart: .part1,
                                      startedAt: "2026-08-07T10:00:00Z",
                                      endedAt: "2026-08-07T10:20:00Z",
                                      goal: "", transcript: [],
                                      reportPath: "reports/2026-08-07-001.json",
                                      recordingPath: "recordings/x.m4a")
        try StateStore(directory: directory).mutate { $0.sessions = [session] }
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })

        let viewModel = app.makeRecordingPlaybackViewModel(for: session)

        // 读的这一头：播放器找的必须是**这个**目录里的那条 m4a。
        XCTAssertEqual(viewModel.state, .ready(audioURL),
                       "播放器去别处找这条录音了（实际是 \(viewModel.state)）。"
                           + "真机上训练记录页每一场都会显示「录音文件找不到了」，"
                           + "而文件好端端地躺在 \(audioURL.path)。")

        viewModel.delete()

        // 写的那一头：删录音必须落在**这个**目录的 state.json 上。
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path),
                       "用户点了删除，音频文件还在 \(audioURL.path)。")
        XCTAssertEqual(try StateStore(directory: directory).load().sessions.first?.recordingPath,
                       "",
                       "删完录音，这个目录的 state.json 里那条 recordingPath 还指着已经不在的"
                           + "文件——播放器把清除写进了另一个 state.json。用户重开 App，"
                           + "这一场会显示「录音文件找不到了」，而且永远清不掉。")
        XCTAssertEqual(viewModel.notice, "录音已删除。这次练习的题目、逐字稿和复盘都还在。",
                       "一切顺利却没有告诉用户删成功了，或者说的不是这句："
                           + (viewModel.notice ?? "（一个字都没说）"))
    }

    // MARK: - 采样器必须真的接到练习上（复审 BI-2）

    // Phase 4 的十三个任务没有一个认领「把 AXTranscriptSampler 接到 App 上」这件事：
    // `makePracticeRunner()` 不传 `transcript:`，默认值是 nil，`TranscriptCollector.begin()`
    // 第一行 `guard let sampler else { return }` 直接返回。后果是**真机上练一场，
    // 逐字稿一定是空的**——不管「记录对话逐字稿」开关是开是关，界面上也看不出任何异样。
    // `PracticeRunnerArchiveTests` 那一组测的是「给了采样器之后拼得对不对」，
    // 它们全绿也证明不了「App 会给采样器」，因为它们自己把采样器传了进去。
    //
    // 下面三条各守一段，缺一段这个缺口就能再溜回来：
    // 1. 开关开着 → 练一场，逐字稿真的进了训练记录（守「接上了」）
    // 2. 开关关掉 → 采样器一次都不被问到（守「开关真的管用」）
    // 3. 生产默认那一份工厂造出来的真的是 `AXTranscriptSampler`（守「真机上采的是 AX 树」）

    /// 开关开着时，从 `makePracticeRunner()` 拿到的那台驱动器**真的会去采样**，
    /// 而且采到的东西真的落进了 `state.sessions` 里那条记录。
    ///
    /// **这条是 BI-2 的判据。** 全程用假 Bridge 与假采样器，不碰真实 ChatGPT（铁律 5）。
    func testPracticeStartedFromTheAppRecordsTheTranscriptWhenTheSwitchIsOn() async throws {
        let sampler = Self.scriptedSampler()
        let app = Self.appState(directory: directory, sampler: sampler)
        XCTAssertTrue(app.state.settings.transcriptEnabled, "前提没成立：开关默认就该是开的")

        let runner = app.makePracticeRunner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        // 断言落在「内容」上而不是「采样器被调了几次」：调用次数对不对，
        // 换不来用户在训练记录里看到的那几行字。
        XCTAssertEqual(runner.transcriptTurnCount, 2,
                       "练习面板上那行「已记录 N 条对话」会一直是 0，"
                           + "因为 App 根本没把采样器交给驱动器。")
        let session = try XCTUnwrap(try StateStore(directory: directory).load().sessions.first)
        XCTAssertEqual(session.transcript.map(\.text),
                       ["Do you live in a house or a flat?", "I live in a flat with my parents."],
                       "这一场的逐字稿是空的——训练记录点开只会显示「这一场没有逐字稿…」，"
                           + "成品标准第 5 条（考官问过的每一个问题都能找到）当场落空。")
        XCTAssertEqual(session.transcript.map(\.role), ["assistant", "user"])
    }

    /// 开关关掉时，采样器**一次都不该被问到**。
    ///
    /// 只有上面那条的话，「不管开关一律注入」也是绿的——而那意味着用户明明关掉了，
    /// 练习时还在读 ChatGPT 窗口上的字。界面显示的状态和真实行为对不上，
    /// 是本项目最不能接受的那一种失败。
    func testTurningTheSwitchOffReallyStopsTheSampling() async throws {
        let sampler = Self.scriptedSampler()
        let app = Self.appState(directory: directory, sampler: sampler)
        // 走用户真正会走的那条路：设置窗口的「练习偏好」（Phase 10 Task 16 起唯一的写入口）。
        CoachSettingsViewModel(app: app, directory: directory).setTranscriptEnabled(false)

        let runner = app.makePracticeRunner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        XCTAssertEqual(sampler.sampleCount, 0,
                       "用户把「记录对话逐字稿」关掉了，练习时却还在读 ChatGPT 窗口上的字。")
        XCTAssertTrue(try XCTUnwrap(try StateStore(directory: directory).load().sessions.first)
            .transcript.isEmpty)
        XCTAssertNil(runner.transcriptNotice, "用户自己关掉的功能不该报警")
    }

    /// 生产默认那一份工厂造出来的必须是真的 `AXTranscriptSampler`。
    ///
    /// 上面两条都是拿假采样器测的：把生产默认换成一个永远返回空的采样器，它们照样全绿，
    /// 而真机上逐字稿仍然是空的——这正是 BI-2 那个缺口的形状，所以这一层也得有人守。
    ///
    /// **构造它没有副作用**：`LiveAXAccess.init` 是空的，`sample()` 不被调用就不碰
    /// 任何 AX 接口，更不会启动 ChatGPT（铁律 5）。这与 `AppState.liveBridge` 同理，
    /// 与一按下去就会启动 ChatGPT 的 `livePreflight` 不同。
    func testTheProductionDefaultReallyBuildsAnAXTranscriptSampler() {
        let sampler = AppState.liveTranscriptSampler()

        XCTAssertTrue(sampler is AXTranscriptSampler,
                      "真机上练习时用的不是从 ChatGPT 的无障碍树上采样的那一个，"
                          + "而是 \(type(of: sampler))。逐字稿会永远是空的，"
                          + "而所有拿假采样器写的测试都照样全绿。")
    }

    // MARK: - 录音也必须真的接到练习上（Phase 5 复审 2026-08-06）

    // 上面那个缺口在 Phase 5 原样长出了第二遍：整份 Phase 5 计划的十一个任务里，
    // 没有一个认领「把 `PracticeRecordingCoordinator` 接到 App 上」——`makePracticeRunner()`
    // 不传 `recording:`，默认值是 nil，于是 `PracticeRunner.beginRecording()` 里的
    // `recording?.begin(...)` 得到 nil，走 `.none` 分支安静地什么都不做。后果是
    // **真机上这个 .app 永远不会录音**：录音开关拨到哪儿都一样，练习界面上不会出现
    // 「正在录音」，训练记录里不会有任何录音，而且没有任何一处报错。
    // `PracticeRunnerRecordingTests` 那十一条全绿也证明不了「App 会给录音器」，
    // 因为它们自己把录音器传了进去。
    //
    // 下面三条各守一段，缺一段这个缺口就能再溜回来：
    // 1. 从 `makePracticeRunner()` 拿到的驱动器真的在录，路径真的进了训练记录（守「接上了」）
    // 2. 交给录音器的开关快照与目录是**磁盘上此刻**那一份（守「设置窗口里拨的开关真的算数」）
    // 3. 生产默认那一份工厂造出来的真的是 `PracticeRecordingCoordinator`（守「真机上录的是真麦克风」）

    /// 从 `makePracticeRunner()` 拿到的那台驱动器**真的会录音**，
    /// 而且这次的录音路径真的落进了 `state.sessions` 里那条记录。
    ///
    /// 全程用假 Bridge 与假录音器，不碰真实 ChatGPT、不碰麦克风（铁律 5）。
    func testPracticeStartedFromTheAppReallyRecords() async throws {
        let recording = FakeRecording()
        let app = Self.appState(directory: directory, sampler: Self.scriptedSampler(),
                                recording: recording)

        let runner = app.makePracticeRunner()
        try await runner.start(setup: Self.setup())

        XCTAssertEqual(recording.beginCount, 1,
                       "App 根本没把录音器交给驱动器：真机上练一场，一秒都不会被录下来。")
        XCTAssertTrue(runner.isRecording, "练习界面上那行「正在录音」永远不会出现。")

        try await runner.finishPractice()

        let session = try XCTUnwrap(try StateStore(directory: directory).load().sessions.first)
        XCTAssertEqual(session.recordingPath, "recordings/x.m4a",
                       "训练记录里这一场没有录音，Task 9 的内嵌播放器届时永远没得可放。")
    }

    /// 交给录音器的那份开关快照，必须是**磁盘上此刻**那一份。
    ///
    /// 录音开关是在系统「设置」窗口（⌘,，Task 8）里拨的，那个窗口有它自己的 `StateStore`，
    /// 不经过这个 `AppState`。只信内存里那份的话，用户刚打开开关、转身开练，
    /// 录音器收到的还是启动 App 那一刻的旧值——设置窗口里开关明明开着，练完却一个录音都没有，
    /// 而且不会有任何报错。这是本项目最不能接受的那种失败：界面显示的状态和真实行为对不上。
    ///
    /// 顺带守住目录：录音器的 `RecordingStore` 必须和训练数据在同一个目录下，
    /// 否则录音落在别处，训练记录里那条相对路径指向的文件根本不存在。
    func testTheRecorderGetsTheSwitchThatIsOnDiskRightNow() throws {
        let factory = RecordingFactorySpy()
        let app = Self.appState(directory: directory, sampler: Self.scriptedSampler(),
                                factory: factory)
        XCTAssertFalse(app.state.settings.recordingEnabled, "前提没成立：录音开关默认就该是关的")

        // 模拟「用户刚在设置窗口里打开了录音开关」：另一个 StateStore，不经过这个 AppState。
        try StateStore(directory: directory).mutate {
            $0.settings = RecordingConsent.enable($0.settings, at: "2026-08-06T22:00:00+08:00")
        }
        _ = app.makePracticeRunner()

        let handed = try XCTUnwrap(factory.settings)
        XCTAssertTrue(handed.recordingEnabled,
                      "用户在设置窗口里打开的录音开关没送到录音器手上——"
                          + "开关看着是开的，练完却什么都没录，且没有任何报错。")
        XCTAssertEqual(handed.recordingConsentAt, "2026-08-06T22:00:00+08:00",
                       "同意时间戳没跟着送到，`RecordingConsent.readiness` 会判成 blocked。")
        XCTAssertEqual(try XCTUnwrap(factory.store).directory.root, directory.root,
                       "录音会落在另一个目录里，训练记录里那条相对路径指向的文件根本不存在。")
    }

    /// 开关关着时，交到录音器手上的快照也必须是**关着**的。
    ///
    /// 只有上面那条的话，「一律按开着传」也是绿的——而那意味着用户没开这个功能、
    /// 也没同意过，麦克风却在练习时开着。录音的隐私成本正是它默认关掉的理由。
    func testTheRecorderIsNotToldTheSwitchIsOnWhenItIsOff() throws {
        let factory = RecordingFactorySpy()
        let app = Self.appState(directory: directory, sampler: Self.scriptedSampler(),
                                factory: factory)

        _ = app.makePracticeRunner()

        let handed = try XCTUnwrap(factory.settings)
        XCTAssertFalse(handed.recordingEnabled,
                       "用户没开录音开关，App 却按开着的告诉录音器——麦克风会在他不知情时打开。")
        XCTAssertTrue(handed.recordingConsentAt.isEmpty)
    }

    /// 生产默认那一份工厂造出来的必须是真的 `PracticeRecordingCoordinator`。
    ///
    /// 上面三条都是拿假录音器测的：把生产默认换成一个什么都不做的空实现，它们照样全绿，
    /// 而真机上一秒都录不下来——这正是那个缺口的形状，所以这一层也得有人守。
    ///
    /// **跑的是生产代码本身**，只把权限查询换成假的：Phase 5 计划的 Global Constraints
    /// 写明「单元测试里绝不允许碰真硬件，不许构造 `SystemMicrophoneAuthorizer`」
    /// （`swift test` 跑的是没有 bundle id、没有 Info.plist 的命令行进程）。
    ///
    /// **构造协调器没有副作用**：不开麦克风、不建文件，`begin()` 不被调用就什么都不发生
    /// （与 `AppState.liveBridge` 同理）。这里更是把开关关着的设置传进去，
    /// 就算谁误调了 `begin()` 也只会拿到 `.skippedByUser`。
    func testTheProductionDefaultReallyBuildsARecordingCoordinator() {
        let recording = AppState.liveRecording(authorizer: { StubMicrophoneAuthorizer() })(
            RecordingStore(directory: directory),
            CoachSettings(recordingEnabled: false, recordingConsentAt: ""))

        XCTAssertTrue(recording is PracticeRecordingCoordinator,
                      "真机上练习时用的不是那台会开麦克风的协调器，而是 \(type(of: recording))。"
                          + "录音会永远是空的，而所有拿假录音器写的测试都照样全绿。")
    }

    // MARK: - 设置窗口里拨的录音开关必须让主窗口重读（Task 16 复审 2026-08-08）

    /// **走生产那条路：`app.makeRecordingSettingsViewModel()`。**
    ///
    /// 这根线（`onChange: { app.reload() }`）此前只有
    /// `RecordingSettingsViewModelTests.testTurningRecordingOnTellsTheMainWindowToRefresh`
    /// 在「守」，而那条自己 new 了一台视图模型、自己把 `{ app.reload() }` 传了进去：
    /// 它证明的是「只要接上这根线，reload 就会发生」，证明不了**生产路径真的接了**。
    /// 实测（2026-08-08）：把工厂里 `onChange:` 那一整行删掉——那个参数有默认值 `{}`，
    /// 编译照过——`swift test` 1670 条一条不红。这条测试补的就是那个缺口。
    ///
    /// 少了这根线的后果：用户在设置窗口开了录音、转身开练，主窗口手上那份 `state`
    /// 还是旧的，`makePracticeRunner()` 交给录音器的快照按「关」算，
    /// 练完一秒录音都没有，而且没有任何报错。
    ///
    /// 权限查询注入假的：`swift test` 跑的是没有 bundle id、没有 Info.plist 的命令行进程，
    /// 不许构造 `SystemMicrophoneAuthorizer`（Phase 5 Global Constraints、铁律 5）。
    func testTheRecordingSettingsViewModelFromTheAppTellsTheMainWindowToRefresh() async throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        let viewModel = app.makeRecordingSettingsViewModel(
            authorizer: FakeMicrophoneAuthorizer(current: .granted))
        XCTAssertFalse(app.state.settings.recordingEnabled, "前提没成立：录音开关默认就该是关的")

        await viewModel.setEnabled(true)

        // 前两条只是把「开关这一格自己确实开成了、也确实落了盘」摆清楚，
        // 免得下面那条因为别的原因红了却被读成「少了 onChange」。
        XCTAssertTrue(viewModel.enabled, "前提没成立：这一格自己都没开起来")
        XCTAssertTrue(try StateStore(directory: directory).load().settings.recordingEnabled,
                      "前提没成立：这一格自己那份 StateStore 都没把开关写进 state.json")
        // ↓ 这一条才是这条测试的牙齿：工厂上那句 `onChange: { app.reload() }` 被删掉时，
        //   上面两条照样绿，只有它会红。
        XCTAssertTrue(app.state.settings.recordingEnabled,
                      "在设置窗口开了录音，主窗口这份 AppState 还是旧的——"
                          + "`AppState.makeRecordingSettingsViewModel()` 上那句 "
                          + "`onChange: { app.reload() }` 没了。"
                          + "下一步：把它接回去；不然用户转身开练，"
                          + "交给录音器的快照仍按「关」算，练完一秒录音都没有且不报错。")
    }

    // MARK: - 学习计划页要能写训练数据（Phase 8 Task 9）

    /// **这条钉的是「改了、真的存下来了、页面上也跟着变了」三件事。**
    ///
    /// Phase 8 的计划把 `mutate` 判成「无法在单元测试里构造，交给人工验收」，
    /// 依据是「`AppState.init` 会调 `recheckPermission()` → `AXDriver.preflight()`，
    /// 而 preflight 会真的启动 ChatGPT」。**这个依据对现在的代码已经不成立**：
    /// 环境检查早就搬出了 `init`（`testCreatingAppStateDoesNotRunTheEnvironmentCheck` 钉着这件事），
    /// 而且 `preflight` 是注入进来的。所以这条路径不但测得了，还必须测——
    /// 它是学习计划页写盘的唯一出口，改坏了用户会以为计划存下来了，重开 App 才发现没有。
    func testMutateWritesThroughToDiskAndRefreshesWhatThePageReads() throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        XCTAssertNil(app.state.plan, "前提就没成立：还没生成计划时 plan 就已经有值了")

        let failure = app.mutate {
            $0.plan = TrainingPlan(
                lengthDays: 7, createdAt: "2026-08-07T00:00:00Z",
                days: [PlanDay(id: 1, questionIds: ["q1"], completedQuestionIds: [])],
                focusPart: .part2)
        }

        XCTAssertNil(failure, "写成功了却返回了一段给用户看的说明：" + (failure ?? ""))
        // 咬的是 `reload()`：不重读的话计划页显示的还是改之前那份，
        // 用户会以为「生成计划」这颗按钮坏了，再点一次。
        XCTAssertEqual(app.state.plan?.lengthDays, 7,
                       "改完没重读，页面上显示的还是改之前那份训练数据")
        XCTAssertEqual(app.state.plan?.focusPart, .part2)
        // **这一段是这条测试的牙齿。** 只改内存不落盘的话上面三条照样全绿，
        // 而用户关掉 App 再打开，辛苦排的计划就没了（与题库导入那条同一个手法）。
        let onDisk = try StateStore(directory: directory).load()
        XCTAssertEqual(onDisk.plan?.days.first?.questionIds, ["q1"],
                       "计划只改了内存没写进 state.json——关掉 App 再打开它就没了")
        XCTAssertEqual(onDisk.plan?.focusPart, .part2)
    }

    /// 写盘失败必须说清「发生了什么 + 下一步做什么」，而且必须是中文（铁律 6、7）。
    ///
    /// **不能直接把 `error.localizedDescription` 摆给用户**：目录被占、权限不足这类失败
    /// 抛出来的是系统 NSError，它只说发生了什么，不说下一步，措辞也未必是中文——
    /// 这正是 `describeLoadFailure` 当初存在的理由，写盘这一侧同样需要。
    func testMutateSaysWhatFailedAndWhatToDoNextInsteadOfPretendingItSaved() throws {
        // 数据目录该在的位置被一个同名文件占了，`store.mutate` 必然抛错。
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-ui-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = DataDirectory(root: root)
        let app = AppState(directory: blocked, preflight: { .init(ok: true, messages: []) })

        let message = try XCTUnwrap(
            app.mutate { $0.plan = nil },
            "写盘失败却返回了 nil。调用方据此认为改动生效了，用户看到的是一句「已生成」，"
                + "下次打开才发现什么都没变——静默失败里最伤人的一种（铁律 7）。")

        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        XCTAssertTrue(message.contains(blocked.stateFile.path),
                      "没指名是哪个文件出了事，用户无从下手：" + message)
        XCTAssertTrue(message.contains("可写"),
                      "没告诉用户该去确认什么，「下一步」等于没写：" + message)
    }

    /// 错误自带中文的「下一步」时**原样交出去，不许再包一层**。
    ///
    /// `CoachError` 的每一条消息都是照「发生了什么 + 下一步做什么」写的；
    /// 外面再套一句「这次改动没能保存：…下一步：确认数据目录可写」，用户会读到两个互相矛盾的
    /// 「下一步」，而真正该做的那一步被埋在中间。
    func testMutatePassesThroughAnErrorThatAlreadyCarriesItsOwnChineseNextStep() throws {
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        let reason = "题库里没有 Part 2（个人陈述）的题目，生成不了计划。"
            + "下一步：换一个重点 Part，或到「训练题库」页导入含该 Part 的题目。"

        let message = try XCTUnwrap(app.mutate { _ in throw CoachError.planImpossible(reason) })

        XCTAssertEqual(message, reason,
                       "错误自带的中文说明被改写了。它是照「发生了什么 + 下一步」写好的，"
                           + "外面再包一层会让用户读到两个「下一步」。")
        XCTAssertNil(try StateStore(directory: directory).load().plan,
                     "改动抛错了却还是写了盘——半截改动落进 state.json 比不改更糟")
    }

    // MARK: - 上面几条用的装置

    /// 注入假 Bridge、假采样器与假录音器的 `AppState`。
    /// **不碰真实 ChatGPT、不碰麦克风（铁律 5）。**
    ///
    /// `makeBridge` 交出去的那台假 Bridge 会正常吐出一份合法复盘，
    /// 好让 `finishPractice()` 一路走到归档——逐字稿与录音路径正是在归档那一步
    /// 落进训练记录的。
    private static func appState(directory: DataDirectory,
                                 sampler: any TranscriptSampling,
                                 recording: any PracticeRecording = FakeRecording()) -> AppState {
        appState(directory: directory, sampler: sampler,
                 factory: RecordingFactorySpy(recording))
    }

    private static func appState(directory: DataDirectory,
                                 sampler: any TranscriptSampling,
                                 factory: RecordingFactorySpy) -> AppState {
        let bridge = FakeBridge()
        bridge.copyResult = .success(rawReview)
        return AppState(directory: directory,
                        preflight: { .init(ok: true, messages: []) },
                        makeBridge: { bridge },
                        makeTranscriptSampler: { sampler },
                        makeRecording: factory.make)
    }

    private static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "p1-home-001", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }

    /// 背景板一次（`begin`），之后每一次都是完整的这一场（`tick` / `finish`）。
    /// 与 `PracticeRunnerArchiveTests.scriptedSampler` 同一套脚本，理由见那边的注释。
    private static func scriptedSampler() -> FakeTranscriptSampler {
        let background = TranscriptFragment(speaker: .learner,
                                            text: "You will act as an IELTS Speaking examiner.")
        return FakeTranscriptSampler([
            TranscriptSweep(fragments: [background]),
            TranscriptSweep(fragments: [
                background,
                TranscriptFragment(speaker: .examiner, text: "Do you live in a house or a flat?"),
                TranscriptFragment(speaker: .learner, text: "I live in a flat with my parents.")
            ])
        ])
    }

    private static let rawReview = """
        <<<IELTS_REVIEW_JSON:appstate-test>>>
        {"summary":"这次整体还行。",
         "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能直接修饰动词"}],
         "vocabulary":[],"priority_target":null}
        <<<END_IELTS_REVIEW_JSON:appstate-test>>>
        """
}
