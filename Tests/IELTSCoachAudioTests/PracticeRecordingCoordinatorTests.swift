import AVFoundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachAudio

/// 造了几个采集器。
///
/// 不能直接在 `engineFactory` 里数测试类上的一个 Int：那个闭包是 `@Sendable` 的，
/// 而 `XCTestCase` 不是 `Sendable`，捕获它在 Swift 6 语言模式下直接编不过
/// （`capture of 'self' with non-Sendable type ... in a '@Sendable' closure`）。
/// 这个计数正是「开关关着时连采集器都不造」那条断言的全部依据，不能省掉，
/// 所以换成一个自带锁、可以安全跨线程的小盒子。
private final class EngineFactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0

    var count: Int { lock.lock(); defer { lock.unlock() }; return made }
    func recordOne() { lock.lock(); made += 1; lock.unlock() }
}

final class PracticeRecordingCoordinatorTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: RecordingStore!
    private var engine: FakeCaptureEngine!
    private var writer: FakeSegmentWriter!
    private var engineCounter: EngineFactoryCounter!
    private var enginesMade: Int { engineCounter.count }

    /// 2026-08-06T10:45:30Z 的 Unix 时间戳。
    ///
    /// **计划里写的是 1_785_931_530，那个数是错的**——它对应 2026-08-05T12:05:30Z，
    /// 跟它自己注释里写的「2026-08-06T10:45:30Z」差了近一天。Task 3 的
    /// `RecordingStoreTests` 已经踩过同一个坑并改正，这里用同一个正确的数，
    /// 两处对「同一时刻」的说法才是一致的。
    /// 复核：`date -r 1786013130 -u` → 2026-08-06T10:45:30Z。
    private let startedAt = Date(timeIntervalSince1970: 1_786_013_130)

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = RecordingStore(directory: directory)
        engine = FakeCaptureEngine()
        writer = FakeSegmentWriter()
        engineCounter = EngineFactoryCounter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func enabledSettings() -> CoachSettings {
        RecordingConsent.enable(CoachState.empty().settings, at: "2026-08-01T00:00:00Z")
    }

    private func makeCoordinator(settings: CoachSettings,
                                 permission: MicrophonePermissionState) -> PracticeRecordingCoordinator {
        let engine = self.engine!
        let writer = self.writer!
        let counter = self.engineCounter!
        return PracticeRecordingCoordinator(
            store: store,
            settings: settings,
            permission: permission,
            engineFactory: { counter.recordOne(); return engine },
            writerFactory: { url in
                FileManager.default.createFile(atPath: url.path, contents: Data())
                return writer
            })
    }

    /// 开关关着时**连麦克风都不碰**。碰了就会在系统的「最近使用麦克风」里
    /// 留下记录，而用户明明没开这个功能——这是隐私问题，不只是逻辑问题。
    func testDoesNotTouchTheMicrophoneWhenTheSwitchIsOff() {
        let coordinator = makeCoordinator(settings: CoachState.empty().settings, permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt), .skippedByUser)
        XCTAssertEqual(enginesMade, 0, "开关关着就不该造出采集器")
        XCTAssertEqual(engine.startCount, 0)
    }

    /// 开关开着但没权限，必须是 failed 并带一条能照着做的说明。
    /// **混成 skippedByUser 就是静默失败**：用户以为在录，练完却什么都没有。
    func testMissingPermissionIsReportedNotSilentlySkipped() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .denied)
        guard case .failed(let message) = coordinator.begin(startedAt: startedAt) else {
            return XCTFail("开关开着却录不了，必须明说")
        }
        XCTAssertTrue(message.contains("系统设置"))
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertEqual(engine.startCount, 0)
    }

    func testStartedRecordingIsNamedAfterTheStartInstant() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt),
                       .started(relativePath: "recordings/2026-08-06T10-45-30Z.m4a"))
        XCTAssertEqual(engine.startCount, 1)
    }

    /// 同一秒里重开一场（上一场刚崩）不能覆盖掉前一场已经录好的内容。
    func testASecondRecordingInTheSameSecondDoesNotOverwriteTheFirst() throws {
        let existing = directory.recordingsDirectory.appending(path: "2026-08-06T10-45-30Z.m4a")
        try Data("已经录好的内容".utf8).write(to: existing)

        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt),
                       .started(relativePath: "recordings/2026-08-06T10-45-30Z-2.m4a"))
        XCTAssertEqual(try Data(contentsOf: existing).count,
                       Data("已经录好的内容".utf8).count, "前一场的录音不能被动过")
    }

    /// 麦克风打不开时同样是 failed，不是 skipped。
    func testEngineFailureIsReportedAsFailed() {
        engine.failStartAtCall = 1
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        guard case .failed(let message) = coordinator.begin(startedAt: startedAt) else {
            return XCTFail("采集起不来必须明说")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    /// 起不来的那一次不能在 recordings/ 里留下一个刚建出来的空文件。
    ///
    /// 这条不是洁癖：`RecordingSession.start()` 抛错时会把写入器关掉，但**关掉不等于删掉**
    /// （它的注释里明写了这一点，并把收拾空文件的责任交给这里）。留着它的话，
    /// `RecordingStore.usage()` 会把它算进录音占用，`orphanFileNames`（明写「不主动删」）
    /// 会把它当成孤儿报出来——用户一次都没录成，「录音设置」里却说他有一个孤儿录音占着地方。
    func testAFailedStartLeavesNoOrphanFileBehind() throws {
        engine.failStartAtCall = 1
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        guard case .failed = coordinator.begin(startedAt: startedAt) else {
            return XCTFail("采集起不来必须明说")
        }

        XCTAssertEqual(try store.existingFileNames(), [],
                       "起不来的那一次不该在 recordings/ 里留下文件")
        XCTAssertEqual(try store.orphanFileNames(referencedPaths: []), [],
                       "一次都没录成，界面上不该冒出一个孤儿录音")
    }

    func testFinishReturnsTheOutcomeOfWhatWasRecorded() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        _ = coordinator.begin(startedAt: startedAt)
        engine.deliver(makePCMBuffer())

        let outcome = coordinator.finish()
        XCTAssertEqual(outcome?.relativePath, "recordings/2026-08-06T10-45-30Z.m4a")
        XCTAssertEqual(outcome?.duration, 12)
    }

    /// 没在录的时候收尾必须无害——PracticeRunner 在任何失败路径上都会调它，
    /// 包括那些根本没开始录的路径。
    func testFinishWithoutBeginIsHarmless() {
        let coordinator = makeCoordinator(settings: CoachState.empty().settings, permission: .granted)
        XCTAssertNil(coordinator.finish())
    }

    func testFinishTwiceDoesNotReturnAStaleOutcome() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        _ = coordinator.begin(startedAt: startedAt)
        XCTAssertNotNil(coordinator.finish())
        XCTAssertNil(coordinator.finish(), "第二次收尾时已经没有正在进行的录音了")
    }
}
