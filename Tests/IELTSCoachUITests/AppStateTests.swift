import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

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
                              permission: app.permission, permissionSkipped: false),
            .checkingEnvironment,
            "重查的这十秒里路由一路返回权限页：用户点完「重新检查」，"
                + "屏幕上一个像素都不会变，只能对着授权页干等。")

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

    // MARK: - 「记录对话逐字稿」开关必须真的落盘（铁律 7）

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
        XCTAssertTrue(app.state.settings.transcriptEnabled, "ROADMAP 第 5 节写明默认是开的")

        app.setTranscriptEnabled(false)

        XCTAssertNil(app.loadError, "写成功了却挂着一条错误信息")
        XCTAssertFalse(app.state.settings.transcriptEnabled,
                       "拨完开关内存里的状态没跟着变，界面上开关会自己弹回去")
        XCTAssertFalse(try StateStore(directory: directory).load().settings.transcriptEnabled,
                       "开关只改了内存没写进 state.json——用户关掉 App 再打开它就弹回来了")
    }

    func testTurningItBackOnAlsoSticks() throws {
        // 单向测试是个常见的空转陷阱：`{ $0.settings.transcriptEnabled = false }`
        // 这种写死取值的实现，只测「关」的话是绿的。
        let app = AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
        app.setTranscriptEnabled(false)

        app.setTranscriptEnabled(true)

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
        let app = AppState(directory: DataDirectory(root: root),
                           preflight: { .init(ok: true, messages: []) })

        app.setTranscriptEnabled(false)

        let message = try XCTUnwrap(app.loadError, "写盘失败却一声不吭")
        // 点名是哪个开关。构造 AppState 时读盘也会失败并留下一条**别的**错误信息，
        // 只断言「loadError 非空」的话，`setTranscriptEnabled` 里的 catch 整个删掉照样绿。
        XCTAssertTrue(message.contains("记录对话逐字稿"),
                      "没说清是哪个设置没保存上，用户不知道刚才那一下到底生效没有：" + message)
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
    }
}
