import ChatGPTBridge
import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 可编程的假录音器。练习流程的接线因此完全不需要真麦克风就能测（铁律 5）。
///
/// 除了计划给的四个成员，这里多存了两样东西——**没有它们，本文件里最要紧的两条测试
/// 就没有牙齿**：
///
/// - `callsAtBegin`：`begin` 被调用的那一刻，Bridge 已经走到哪一步了。
///   只断言「`begin` 被调过一次」的话，把 `begin` 挪到 `start(setup:)` 的第一行照样绿——
///   而那时录到的是用户等 ChatGPT 启动语音的那 9 秒沉默（spec 2.3.7）。
/// - `callsAtFinish`：`finish` 被调用的那一刻，收尾走到哪一步了。
///   只断言「`finish` 被调过一次」的话，把它挪到 `finishPractice()` 的最后一行照样绿——
///   而那时取复盘那几十秒（结束语音、请 ChatGPT 写复盘、等它写完）全被录进文件里。
final class FakeRecording: PracticeRecording, @unchecked Sendable {
    var beginOutcome: RecordingBeginOutcome = .started(relativePath: "recordings/x.m4a")
    var outcome: RecordingOutcome? = RecordingOutcome(relativePath: "recordings/x.m4a",
                                                      duration: 300,
                                                      interruptions: [],
                                                      warning: nil)
    /// 由测试注入：问一句「此刻 Bridge 被调过哪些方法」。
    var observeCalls: (@Sendable () -> [String])?

    private(set) var beginCount = 0
    private(set) var finishCount = 0
    private(set) var callsAtBegin: [String] = []
    private(set) var callsAtFinish: [String] = []

    func begin(startedAt: Date) -> RecordingBeginOutcome {
        beginCount += 1
        callsAtBegin = observeCalls?() ?? []
        return beginOutcome
    }

    func finish() -> RecordingOutcome? {
        finishCount += 1
        callsAtFinish = observeCalls?() ?? []
        return outcome
    }
}

/// 录音接进练习流程之后，四条接线规则各自守住了没有。
///
/// 四条规则（计划 Task 7「必须遵守的四条接线规则」）：
/// 1. 录音在考官提示词发出去之后才开始；
/// 2. 录音起不来不能把练习也拖垮；
/// 3. 每一条会走到头的路径都要收尾（成功、开练失败、取复盘失败、中途取消）；
/// 4. 收尾要在结束语音之前做。
///
/// **全程用假 Bridge 与假录音器，一次也不碰真实 ChatGPT、一次也不碰麦克风（铁律 5）。**
@MainActor
final class PracticeRunnerRecordingTests: XCTestCase {
    /// **每一个 runner 都必须拿到这个临时目录，一个都不能漏。**
    ///
    /// `PracticeRunner.init` 的 `directory:` 默认值是 `.resolve()`，也就是**用户真实的数据目录**；
    /// 而 `finishPractice()` 会往那里写一条训练记录、一份 reports/*.json 和一份
    /// pending-reviews/*.txt。不传 `directory:` 的测试会在用户的 state.json 里种下几条假练习
    /// 记录——**测试全绿，数据已经脏了**。所以下面每一个 runner 都走 `self.runner(...)`。
    private var directory: DataDirectory!
    private var store: StateStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
        store = nil
    }

    private let fixedNow = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

    private func runner(bridge: FakeBridge = PracticeRunnerRecordingTests.bridge(),
                        recording: FakeRecording) -> PracticeRunner {
        recording.observeCalls = { [weak bridge] in bridge?.calls ?? [] }
        return PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                              directory: directory, recording: recording,
                              now: { [fixedNow] in fixedNow })
    }

    /// 会正常交出一份合法复盘的假 Bridge：**默认走完整的 happy path**。
    ///
    /// 刻意不用光秃秃的 `FakeBridge()`：那一份的 `copyResult` 是空串，收尾必然停在解析失败上，
    /// 于是「归档那一步有没有把录音路径写进去」这类断言永远走不到归档，测的就不是它该测的东西。
    private static func bridge(returning review: String = rawReview) -> FakeBridge {
        let bridge = FakeBridge()
        bridge.copyResult = .success(review)
        return bridge
    }

    private static let rawReview = """
        <<<IELTS_REVIEW_JSON:recording-test>>>
        {"summary":"这次整体还行，问题集中在动词修饰上。",
         "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能直接修饰动词"}],
         "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding trip",
                        "priority":"high"}],
         "priority_target":{"id":"logic-explain","label":"回答后补一个原因和例子","status":"new",
                            "evidence":["I just like it."]}}
        <<<END_IELTS_REVIEW_JSON:recording-test>>>
        """

    private static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "p1-home-001", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }

    // MARK: - 规则 1：录音在考官提示词发出去之后才开始

    /// 更早开始只会录到用户等 ChatGPT 启动语音的那 9 秒沉默（spec 2.3.7）。
    ///
    /// **断言的是「`begin` 那一刻 Bridge 已经走完哪几步」**，不是「`begin` 被调过」——
    /// 后者在 `begin` 被挪到 `start` 第一行时照样绿。
    func testRecordingStartsOnlyAfterTheExaminerPromptWasSent() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertEqual(bridge.calls, ["newChat", "startVoice", "waitComposer", "sendText"])
        XCTAssertEqual(recording.beginCount, 1)
        XCTAssertEqual(recording.callsAtBegin, ["newChat", "startVoice", "waitComposer", "sendText"],
                       "录音在考官提示词发出去之前就开了，录到的会是等 ChatGPT 启动语音的那 9 秒沉默")
        XCTAssertTrue(runner.isRecording)
        XCTAssertEqual(runner.stage, .practicing)
        XCTAssertEqual(runner.recordingRelativePath, "recordings/x.m4a")
    }

    // MARK: - 规则 2：录音起不来不能把练习拖垮

    /// 录音是增强，不是必需，跟 Phase 4 的逐字稿是同一条原则（ROADMAP 3.2）。
    /// 一个没给麦克风权限的用户本来只是听不了回放，若因此连练都练不了，
    /// 那就是拿一个可选功能把主功能废掉了。
    func testAFailedRecordingDoesNotStopThePractice() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        recording.beginOutcome = .failed("打不开麦克风。下一步：到系统设置里检查权限。")
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertEqual(runner.stage, .practicing, "录音失败不该让练习失败")
        XCTAssertFalse(runner.isRecording)
        XCTAssertTrue(try XCTUnwrap(runner.recordingNotice).contains("下一步"))
    }

    /// 开关关着是默认状态，不是故障——不能拿提示去骚扰用户。
    func testSwitchedOffMeansNoNoticeAndNoIndicator() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        recording.beginOutcome = .skippedByUser
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertFalse(runner.isRecording)
        XCTAssertNil(runner.recordingNotice, "没开开关是默认状态，不该报警")
        XCTAssertEqual(runner.recordingRelativePath, "")
    }

    // MARK: - 规则 3：每一条走到头的路径都要收尾

    /// 练习中途失败时，已经录下的部分不能跟着一起丢。
    func testRecordingIsFinalizedWhenTheStartSequenceFailsMidway() async {
        let bridge = Self.bridge()
        bridge.failAt = .startingVoice
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)

        try? await runner.start(setup: Self.setup())

        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertEqual(recording.finishCount, 1, "失败路径上也必须把录音收尾")
    }

    /// 取复盘那一步失败是真实发生过的事（spec 2.3.9）。
    /// 那时候用户已经练了半小时，录音一秒都不能丢。
    ///
    /// **不用 `bridge.failAt = .capturingReview`**：取复盘那两级降级走的是
    /// `copyResult` / `captureResult`，根本不经过 `failAt` 的那道闸，设了等于没设，
    /// 这条测试就会悄悄退化成一条 happy path。
    func testRecordingIsFinalizedWhenTheReviewStepFails() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        bridge.copyResult = .failure(.actionFailed("假装复制按钮不灵。下一步：这是测试用的。"))
        bridge.captureResult = .failure(.actionFailed("假装读不到。下一步：这是测试用的。"))
        try await runner.finishPractice()

        guard case .needsManualCopy = runner.stage else {
            return XCTFail("这条测试要的就是取复盘失败那条路，实际停在 \(runner.stage)")
        }
        XCTAssertEqual(recording.finishCount, 1)
        XCTAssertEqual(runner.recordingRelativePath, "recordings/x.m4a",
                       "复盘失败了，录音路径也还得在")
    }

    func testCancelAlsoFinalizesTheRecording() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        runner.cancel()

        XCTAssertEqual(recording.finishCount, 1)
        XCTAssertFalse(runner.isRecording, "取消之后界面上不该还挂着「正在录音」")
    }

    // MARK: - 规则 4：收尾要在结束语音之前

    /// 用户点「我练完了」的那一刻就已经不说话了。晚一步关文件，
    /// 结束语音、请 ChatGPT 写复盘、等它写完那几十秒就全被录进去了。
    func testTheRecordingIsClosedBeforeTheWrapUpTalksToChatGPT() async throws {
        let bridge = Self.bridge()
        // 语音还开着，收尾时才会真的去按「结束通话」——不设这一条的话，
        // 下面那句「收尾时还没按过 endVoice」是恒真的。
        bridge.voiceActive = true
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        try await runner.finishPractice()

        XCTAssertTrue(bridge.calls.contains("endVoice"), "这一场根本没走到结束语音，上面那句就白断言了")
        XCTAssertEqual(recording.callsAtFinish,
                       ["newChat", "startVoice", "waitComposer", "sendText"],
                       "录音收尾时收尾链路已经动过 ChatGPT 了——"
                           + "结束语音、请复盘、等它写完那几十秒会被一起录进文件里")
    }

    // MARK: - 中断过就得让用户看见

    /// 哪怕录音自动接上了，中间那一两秒确实没录到。
    func testTheRecordingWarningReachesTheUserAfterFinishing() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        recording.outcome = RecordingOutcome(
            relativePath: "recordings/x.m4a", duration: 300,
            interruptions: [RecordingInterruption(at: Date(), recovered: true)],
            warning: "录音中途因为插拔耳机断了一下，已自动接上。下一步：回听时留意这一小段。")
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        try await runner.finishPractice()

        XCTAssertTrue(try XCTUnwrap(runner.recordingNotice).contains("耳机"))
    }

    /// 开录时那条「这次没录上」的提示，不能被收尾时的中断警告顶掉——
    /// 两件事都发生过的话，用户两件都得知道。
    func testAStartFailureNoticeSurvivesTheFinishingWarning() async throws {
        let bridge = Self.bridge()
        let recording = FakeRecording()
        recording.beginOutcome = .failed("打不开麦克风。下一步：到系统设置里检查权限。")
        recording.outcome = RecordingOutcome(
            relativePath: "", duration: 0, interruptions: [],
            warning: "这一场一秒都没录到，那个空文件已经删掉了。下一步：检查麦克风。")
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        try await runner.finishPractice()

        let notice = try XCTUnwrap(runner.recordingNotice)
        XCTAssertTrue(notice.contains("打不开麦克风"), "开录时那条提示被顶掉了")
        XCTAssertTrue(notice.contains("一秒都没录到"), "收尾时那条警告没说出来")
    }

    // MARK: - 录音路径落进训练记录

    /// 依赖 P4-2：`PracticeRunner` 往 `state.sessions` 里落会话记录（Phase 4 已交付）。
    /// 没有这一条，训练记录页永远挂不上播放器——录音录了也听不到。
    func testTheRecordingPathIsStoredOnThePracticeSession() async throws {
        let recording = FakeRecording()
        let runner = self.runner(recording: recording)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        // 从同一个临时目录读回来。**不要另建一个指向别处的 StateStore**——
        // 那样测的就不是 runner 到底写到哪儿去了。
        let saved = try store.load()
        XCTAssertEqual(saved.sessions.last?.recordingPath, "recordings/x.m4a")
    }

    /// 一秒都没录到时 `RecordingOutcome.relativePath` 是空串（见 `RecordingSession.finish()`：
    /// 那个空文件已经被删掉了）。这时候**绝不能**往训练记录里写一个指向已删文件的路径——
    /// 训练记录页会据此画出一个点了没声音的播放器。
    func testNothingRecordedMeansNoRecordingPathOnTheSession() async throws {
        let recording = FakeRecording()
        recording.outcome = RecordingOutcome(
            relativePath: "", duration: 0, interruptions: [],
            warning: "这一场一秒都没录到，那个空文件已经删掉了。下一步：检查麦克风是不是被别的程序占着。")
        let runner = self.runner(recording: recording)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        XCTAssertEqual(try store.load().sessions.last?.recordingPath, "",
                       "没录到东西却留下路径，训练记录页会画出一个点了没声音的播放器")
    }
}
