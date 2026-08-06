import IELTSCoachAudio
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假权限查询。真实实现的返回值取决于跑测试这台机器授过什么权，
/// 直接依赖它的测试今天绿明天红。
final class FakeMicrophoneAuthorizer: MicrophoneAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var current: MicrophonePermissionState
    private let afterRequest: MicrophonePermissionState
    private(set) var requestCount = 0

    init(current: MicrophonePermissionState, afterRequest: MicrophonePermissionState? = nil) {
        self.current = current
        self.afterRequest = afterRequest ?? current
    }

    func currentStatus() -> MicrophonePermissionState {
        lock.withLock { current }
    }

    /// 计划里这两个方法写的是 `lock.lock(); defer { lock.unlock() }`。**那样编不过**：
    /// Swift 6 把 `NSLock.lock()` / `unlock()` 标成了「不可在异步上下文里调用」
    /// （跨 await 持锁会把线程连同锁一起交出去）。改成 `withLock`——
    /// 同一把锁、同样的互斥，只是临界区被括进闭包里，天然跨不过 await。
    /// 同文件外的 `AppStateTests` 里那几个假实现用的也是 `withLock`。
    func requestAccess() async -> MicrophonePermissionState {
        lock.withLock {
            requestCount += 1
            current = afterRequest
            return current
        }
    }
}

@MainActor
final class RecordingSettingsViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private var recordings: RecordingStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
        recordings = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func makeViewModel(_ authorizer: FakeMicrophoneAuthorizer,
                               now: Date = Date(timeIntervalSince1970: 1_785_931_530))
    -> RecordingSettingsViewModel {
        RecordingSettingsViewModel(store: store, recordings: recordings,
                                   authorizer: authorizer, now: { now })
    }

    // MARK: - 默认关

    func testStartsOffOnAFreshInstall() {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.consentAt, "")
    }

    // MARK: - 打开

    func testTurningOnWithPermissionAlreadyGrantedPersistsConsent() async throws {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await viewModel.setEnabled(true)

        XCTAssertTrue(viewModel.enabled)
        XCTAssertFalse(viewModel.consentAt.isEmpty)
        // 必须真的落盘，不能只是界面上变了个样子。
        let saved = try StateStore(directory: directory).load()
        XCTAssertTrue(saved.settings.recordingEnabled)
        XCTAssertEqual(saved.settings.recordingConsentAt, viewModel.consentAt)
    }

    func testTurningOnPromptsExactlyOnceWhenPermissionWasNeverAsked() async {
        let authorizer = FakeMicrophoneAuthorizer(current: .notDetermined, afterRequest: .granted)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertEqual(authorizer.requestCount, 1, "还没问过就该弹一次系统对话框")
        XCTAssertTrue(viewModel.enabled)
    }

    /// **本任务最要紧的一条。** 权限没拿到时开关必须停在「关」。
    /// 显示成「开」却什么都不录，用户练完发现没录音时完全无从查起。
    func testTheSwitchStaysOffWhenThePermissionIsRefused() async throws {
        let authorizer = FakeMicrophoneAuthorizer(current: .notDetermined, afterRequest: .denied)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertFalse(viewModel.enabled, "没权限时开关必须停在关")
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("下一步"))
        // **这一条钉的是那颗「出路按钮」的前置条件。** 用户在系统弹窗上点了「不允许」之后，
        // `permission` 必须跟着变成 `.denied`——`RecordingSettingsView.needsSystemSettings`
        // 只看这个属性，它停在 `.notDetermined` 的话，那张带「打开系统设置」的卡片根本不出现，
        // 而 macOS 一辈子只弹一次系统对话框：用户从此没有任何出路，只能对着开关反复拨。
        // 只断言 notice 的文案是不够的（文案对了、按钮不出现，一样是死路）。
        XCTAssertEqual(viewModel.permission, .denied,
                       "在系统弹窗上被拒之后，权限状态必须落到 .denied，"
                           + "否则界面上那张「打开系统设置」的卡片不会出现")
        let saved = try StateStore(directory: directory).load()
        XCTAssertFalse(saved.settings.recordingEnabled, "更不能把「开」写进 state.json")
    }

    /// 被拒过之后再点开关**不能再去弹窗**——系统不会弹，用户只会对着界面干等。
    /// 必须直接给「去系统设置」的引导。
    func testAlreadyDeniedDoesNotPromptAgainAndPointsAtSystemSettings() async throws {
        let authorizer = FakeMicrophoneAuthorizer(current: .denied)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertEqual(authorizer.requestCount, 0, "被拒过就别再弹了，系统根本不会弹")
        XCTAssertFalse(viewModel.enabled)
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("系统设置"))
    }

    // MARK: - 关闭与重新打开

    func testTurningOffClearsTheConsentAndSaysRecordingsAreKept() async throws {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await viewModel.setEnabled(true)
        await viewModel.setEnabled(false)

        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.consentAt, "")
        let saved = try StateStore(directory: directory).load()
        XCTAssertEqual(saved.settings.recordingConsentAt, "")
        // 关开关不等于删录音，必须说清楚，否则用户会以为录音也一起没了。
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("不会被删除"))
    }

    func testTurningItBackOnRecordsAFreshConsentTime() async {
        let authorizer = FakeMicrophoneAuthorizer(current: .granted)
        let first = makeViewModel(authorizer, now: Date(timeIntervalSince1970: 1_785_931_530))
        await first.setEnabled(true)
        let firstConsent = first.consentAt
        await first.setEnabled(false)

        let second = makeViewModel(authorizer, now: Date(timeIntervalSince1970: 1_786_931_530))
        await second.setEnabled(true)

        XCTAssertNotEqual(second.consentAt, firstConsent)
        XCTAssertFalse(second.consentAt.isEmpty)
    }

    // MARK: - 事后被撤销权限

    /// **开过之后权限没了，是另一条路。** 前面那两条测的都是「拨开关的当下没拿到权限」；
    /// 这一条测的是用户先前在有权限时开过（`state.json` 里 `recordingEnabled=true`），
    /// 后来在系统设置里把麦克风关掉、或换了台机器 / 重装后 TCC 被重置。
    ///
    /// 这时候 `RecordingConsent.readiness` 会判 `.blocked`，练习一秒都不会录，
    /// 而开关如果照着磁盘显示成「开」，界面就在说一件不成立的事——
    /// 正是这个类型开头那句注释要挡的：「显示成「开」却什么都不录，
    /// 用户练完发现没录音时完全无从查起」。
    func testTheSwitchGoesBackToOffWhenThePermissionIsRevokedAfterConsent() async throws {
        // 先在有权限的时候正常开一次：磁盘上因此有了 recordingEnabled=true + 同意时间。
        let consented = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await consented.setEnabled(true)
        XCTAssertTrue(consented.enabled, "前提没成立：有权限时开关本来就该是开的")

        // 用户后来把麦克风权限收回去了。重开这一页（= 新建一份视图模型）。
        let revoked = makeViewModel(FakeMicrophoneAuthorizer(current: .denied))

        XCTAssertFalse(revoked.enabled,
                       "权限已经不在手里，开关必须停在「关」——照着磁盘显示成「开」，"
                           + "等于告诉用户正在录，而实际上一秒都不会录")
        XCTAssertEqual(revoked.permission, .denied)
        // 但**不许替用户撤回同意**：那是他给过的授权，权限给回来之后仍然算数，
        // 而且 refresh() 是读盘操作，不该反过来写盘。
        let saved = try StateStore(directory: directory).load()
        XCTAssertTrue(saved.settings.recordingEnabled,
                      "开关只是显示成关，磁盘上那次同意不该被悄悄抹掉")
        // 文案得把这个「开关是关的、但你确实同意过」的错位说清楚，并给出下一步。
        XCTAssertTrue(revoked.consentText.contains(revoked.consentAt),
                      "同意时间还在磁盘上，就得照实说出来")
        XCTAssertTrue(revoked.consentText.contains("下一步"),
                      "得告诉用户怎么把权限拿回来，光说「关了」不算合格")
    }

    /// 权限给回来之后开关自己回到「开」——那次同意仍然算数，不用再拨一次。
    /// 少了这一条，把 `enabled` 写死成 `false` 也能骗过上面那条。
    func testTheSwitchIsOnAgainOnceThePermissionComesBack() async {
        let consented = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await consented.setEnabled(true)

        _ = makeViewModel(FakeMicrophoneAuthorizer(current: .denied))
        let restored = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))

        XCTAssertTrue(restored.enabled, "同意还在磁盘上、权限也回来了，开关就该是开的")
        XCTAssertFalse(restored.consentAt.isEmpty)
    }

    // MARK: - 占用提示

    func testUsageReflectsWhatIsOnDisk() throws {
        try Data(repeating: 0x41, count: 2_048)
            .write(to: directory.recordingsDirectory.appending(path: "a.m4a"))
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        XCTAssertEqual(viewModel.usage.count, 1)
        XCTAssertEqual(viewModel.usage.bytes, 2_048)
    }

    /// 没有任何训练记录指向的录音要报出来。不主动删——那是用户的录音——
    /// 但得让他知道有东西在占地方。
    func testOrphanRecordingsAreReportedWithAWayToDealWithThem() throws {
        try Data(repeating: 0x41, count: 16)
            .write(to: directory.recordingsDirectory.appending(path: "orphan.m4a"))
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        let notice = try XCTUnwrap(viewModel.orphanNotice)
        XCTAssertTrue(notice.contains("1 个"))
        XCTAssertTrue(notice.contains("下一步"))
    }

    func testNoOrphanNoticeWhenEveryRecordingIsReferenced() throws {
        try Data(repeating: 0x41, count: 16)
            .write(to: directory.recordingsDirectory.appending(path: "kept.m4a"))
        try store.mutate { state in
            state.sessions = [PracticeSession(id: "2026-08-06-001", questionId: "q1",
                                              focusPart: .part1, startedAt: "t", endedAt: "t",
                                              goal: "", transcript: [], reportPath: "",
                                              recordingPath: "recordings/kept.m4a")]
        }
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        XCTAssertNil(viewModel.orphanNotice)
    }
}
