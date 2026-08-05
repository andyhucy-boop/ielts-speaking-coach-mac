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
}
