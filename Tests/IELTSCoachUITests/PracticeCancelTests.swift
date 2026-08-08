import ChatGPTBridge
import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 「取消」这颗按钮到底取消了什么。
///
/// 复审第 1、3、6 条都落在这一片：
///
/// - **第 1 条**：按了取消之后，本工具还会继续操作 ChatGPT（实测取消之后还有 3 到 6 次
///   真实操作）——剪贴板被清空再覆盖、复盘请求照发、明确放弃的这一场最后带着完整复盘
///   出现在训练记录里；开练途中取消时录音还会被**重新打开一遍**，而那之后再没有任何
///   东西能把它关掉。
/// - **第 3 条**：练完那一刻连点两下「我练完了」，两条收尾链路同时跑起来。
/// - **第 6 条**：点「放弃这一场」时那条本该被看见的录音警告在同一帧被关掉，
///   逐字稿去哪儿了、录音留在哪儿，一个字都没交代。
///
/// **全程用假 Bridge 与假录音器，一次也不碰真实 ChatGPT、一次也不开麦克风（铁律 3）。**
///
/// 这一组每条测试都靠 `FakeBridge` 的闸门把某一步**卡在跑到一半**的状态上——
/// 缺陷只发生在那一瞬（一步已经甩到主线程外面，用户这时按下取消）。
/// 每一次等待都带超时，实现有问题时这些测试要红，不能挂死（铁律 5）。
@MainActor
final class PracticeCancelTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-cancel-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    // MARK: - 第 1 条：取消之后一次 ChatGPT 操作、一次剪贴板操作都不许再有

    /// 等复盘那一分钟里按下「放弃这一场」。
    ///
    /// 这是最容易撞上的一条：「取消」按钮在这一步上挂得最久（默认等 ChatGPT 写复盘 60 秒）。
    ///
    /// 修之前实测：取消之后 ChatGPT 仍会收到那段一千多字的复盘请求提示词并开始作答，
    /// 用户的剪贴板被清空再覆盖成复盘内容（他刚复制的东西没了，全程没有一个字的提示），
    /// 这一场最后还会带着完整复盘报告出现在「训练记录」里。
    func testCancellingDuringTheWrapUpStopsEveryFurtherChatGPTAndClipboardOperation() async throws {
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success(Self.rawReview)
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "endVoice"
        bridge.gate = gate
        // 用户在按下取消之前刚刚自己复制的东西。取消之后它必须一个字都不变。
        let pasteboard = FakePasteboard(contents: "用户刚复制的一段账号密码")
        let runner = self.runner(bridge: bridge, pasteboard: pasteboard)

        try await runner.start(setup: Self.setup())
        bridge.clearCalls()

        let wrapUp = Task { try? await runner.finishPractice() }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success,
                       "收尾链路根本没跑到「结束语音」这一步，这条测试等于空转")

        // 就是这一瞬：一步正甩在主线程外面跑着，用户按下了「放弃这一场」。
        runner.cancel()
        gate.signal()
        _ = await wrapUp.value

        XCTAssertEqual(bridge.calls, ["endVoice"],
                       "取消之后本工具还在操作 ChatGPT：\(bridge.calls)。"
                           + "「endVoice」那一下是取消之前就已经甩出去的，收不回来；"
                           + "它之后的每一次都发生在用户已经把注意力转走之后——"
                           + "他多半正切回去用 ChatGPT 做别的事，突然被塞进一段一千多字的提示词。")
        XCTAssertEqual(pasteboard.readString(), "用户刚复制的一段账号密码",
                       "取消之后剪贴板还是被动了。用户刚复制的那段文字/账号/链接就这么没了，"
                           + "而全程一个字的提示都没有。")
        XCTAssertNil(try StateStore(directory: directory).load().sessions.first?.reportPath
                        .nonEmpty,
                     "用户明确「放弃」的这一场，最后在「训练记录」里显示成一场"
                         + "正常完成、带完整复盘报告的练习")
        XCTAssertEqual(try StateStore(directory: directory).load().issues.count, 0,
                       "放弃的这一场还往错题本里塞了条目")
        guard case .abandoned = runner.stage else {
            return XCTFail("取消之后界面该停在「已经放弃」那张交代卡片上，实际停在 \(runner.stage)")
        }
    }

    /// 开练途中按「取消」。**这条最凶**：修之前，取消之后录音会被重新打开一遍，
    /// 而那之后再没有任何东西会去调 `finish()`——系统状态栏那个橙点会一直亮着，
    /// 麦克风一直开着，只能退出整个应用才停得下来。
    func testCancellingWhileStartingUpNeverReopensTheMicrophone() async throws {
        let bridge = FakeBridge()
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "startVoice"
        bridge.gate = gate
        let recording = FakeRecording()
        // 没在录的时候真实的协调器 `finish()` 返回 nil，这里照实模拟。
        recording.outcome = nil
        let runner = self.runner(bridge: bridge, recording: recording)

        let launch = Task { try? await runner.start(setup: Self.setup()) }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success,
                       "开练链路根本没跑到「启动语音」这一步，这条测试等于空转")

        runner.cancel()
        gate.signal()
        _ = await launch.value

        XCTAssertEqual(recording.beginCount, 0,
                       "取消之后麦克风又被打开了一遍，而这一次再也没有任何东西能把它关掉——"
                           + "橙点一直亮着，只能退出整个应用")
        XCTAssertFalse(runner.isRecording)
        XCTAssertEqual(bridge.calls, ["newChat", "startVoice"],
                       "取消之后本工具还在操作 ChatGPT：\(bridge.calls)")
        guard case .abandoned = runner.stage else {
            return XCTFail("取消之后界面该停在「已经放弃」那张交代卡片上，实际停在 \(runner.stage)")
        }
    }

    /// 在**开练的最后一步**（发考官提示词）上按取消。
    ///
    /// 这一条和上一条不是重复：上一条卡在中间某一步，后面还有一次 `run(...)`，
    /// 那次的**前置**检查就把链路拦下来了。而这一步跑完之后再没有 `run(...)` 了——
    /// 紧接着的两句是「开始采逐字稿」和 `beginRecording()`（重新打开麦克风）。
    /// 拦住它们的只有 `run(_:ticket:_:)` 里那次**后置**复验。
    ///
    /// 复审复现时的突变实测：只去掉那一次后置复验，上一条照样是绿的，这一条会红。
    func testCancellingOnTheLastStartupStepStillNeverOpensTheMicrophone() async throws {
        let bridge = FakeBridge()
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "sendText"          // 开练的最后一步：发考官提示词
        bridge.gate = gate
        let recording = FakeRecording()
        recording.outcome = nil
        let runner = self.runner(bridge: bridge, recording: recording)

        let launch = Task { try? await runner.start(setup: Self.setup()) }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success, "开练链路根本没跑到最后一步，这条测试等于空转")

        runner.cancel()
        gate.signal()
        _ = await launch.value

        XCTAssertEqual(recording.beginCount, 0,
                       "取消发生在最后一步上，麦克风还是被打开了——而那之后再没有任何东西"
                           + "会去调 `finish()`：橙点一直亮着，只能退出整个应用")
        XCTAssertFalse(runner.isRecording)
        guard case .abandoned = runner.stage else {
            return XCTFail("取消之后界面被改成了 \(runner.stage)，那张交代卡片被盖掉了")
        }
    }

    /// 取消之后那条链路**不许把界面从「已经放弃」改回去**。
    ///
    /// 改回去的后果不只是难看：`.failed` 会摆出一颗「从头再试一次」，
    /// 而那颗按钮按下去的第一步是新建会话——用户刚放弃，它又开一场。
    func testTheAbandonedRunNeverRepaintsTheScreenAfterwards() async throws {
        let bridge = FakeBridge()
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "waitComposer"
        bridge.gate = gate
        // 这一步被卡住之后才失败：没有守卫的话，这条链路会走进 `fail(_:retry:)`，
        // 把「已经放弃」那张卡片盖成一句「这一步没成功」外加一颗重试按钮。
        bridge.failAt = .waitingComposer
        let runner = self.runner(bridge: bridge)

        let launch = Task { try? await runner.start(setup: Self.setup()) }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success, "开练链路根本没跑到被卡住那一步，这条测试等于空转")
        runner.cancel()
        gate.signal()
        _ = await launch.value

        guard case .abandoned = runner.stage else {
            return XCTFail("放弃之后那条链路又把界面改成了 \(runner.stage)——"
                           + "用户看到的是一句「这一步没成功」和一颗「从头再试一次」，"
                           + "而他刚按的是放弃")
        }
        XCTAssertNil(runner.retry, "放弃之后不该还摆着一颗重试按钮")
    }

    // MARK: - 第 3 条：连点两下「我练完了」

    /// 那颗按钮挂着回车快捷键（`.keyboardShortcut(.defaultAction)`），
    /// 练完那一刻双击、或者急着结束连按两下回车都非常容易。
    ///
    /// 修之前实测：整条收尾链路会跑两遍，复盘请求被打进 ChatGPT 两遍
    ///（用户回到 ChatGPT 会看到同一段长提示词贴了两次、它也答了两次）；
    /// 而且两条链路会同时驱动同一台 AX 驱动器，那是一次真实的数据竞争。
    func testDoubleClickingIAmDoneOnlyRunsTheWrapUpOnce() async throws {
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success(Self.rawReview)
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "endVoice"
        bridge.gate = gate
        let runner = self.runner(bridge: bridge)

        try await runner.start(setup: Self.setup())
        bridge.clearCalls()

        let first = Task { try? await runner.finishPractice() }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success, "第一下点击根本没跑起来，这条测试等于空转")

        // 第二下点击。第一下这时正卡在「结束语音」上。
        let second = Task { try? await runner.finishPractice() }
        // 第二下若真的跑了起来，它同样会走到「结束语音」那道闸上再放行一次 `gateReached`。
        // 等不到，就说明重入守卫拦住了它。**带超时**：实现有问题时这里要红，不能挂死。
        let secondReached = await Self.waitOffMain(bridge.gateReached, seconds: 2)
        XCTAssertEqual(secondReached, .timedOut,
                       "连点两下「我练完了」，第二下把整条收尾链路又跑了一遍")

        // **放行的次数要够两条链路用。** 只 signal 一次的话，守卫一旦失效，
        // 第二条链路会永远卡在闸上，这条测试就挂死在下面那句 `await` 上而不是
        // 红在断言上——挂死的测试等于没有测试（铁律 5）。多出来的 signal 无害。
        for _ in 0..<4 { gate.signal() }
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(bridge.calls, ["endVoice", "sendText", "waitReply", "copy"],
                       "收尾链路跑了不止一遍：\(bridge.calls)。"
                           + "用户回到 ChatGPT 会看到同一段一千多字的复盘请求贴了两次、"
                           + "它也答了两次；两条链路同时驱动同一台 AX 驱动器还会段错误。")
        XCTAssertEqual(runner.stage, .done, "第二下点击不该把这一场的结果搅掉")
        XCTAssertEqual(try StateStore(directory: directory).load().sessions.count, 1,
                       "同一场练习留下了不止一条训练记录")
    }

    // MARK: - 第 6 条：放弃时那三件事必须交代清楚

    /// 「插拔耳机导致中途断过」「写盘失败，已录到的部分保存在某处」这类提示确实生成了，
    /// 但窗口在同一帧被关掉，一帧都没画出来。
    ///
    /// **这是最硬的一条**：真发生过的故障，唯一的出口被同一次点击关掉了。
    func testTheRecordingWarningSurvivesAbandoning() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        recording.outcome = RecordingOutcome(
            relativePath: "recordings/2026-08-06T10-00-00Z.m4a", duration: 92,
            interruptions: [RecordingInterruption(at: Date(), recovered: true)],
            warning: "录音中途因为插拔耳机断了一下，已自动接上。下一步：回听时留意这一小段。")
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())
        runner.cancel()

        let notice = try XCTUnwrap(runner.recordingNotice,
                                   "放弃这一场时那条录音警告被吞掉了")
        XCTAssertTrue(notice.contains("插拔耳机"), "实际是：\(notice)")
    }

    /// 放弃时必须逐条交代：ChatGPT 那通语音要不要自己挂、已经采到的逐字稿去哪儿了、
    /// 已经录下的那一段留在哪儿。
    ///
    /// 修之前：逐字稿就地蒸发、录音在磁盘上变成没人认领的文件，
    /// 而界面上一个字都没有（窗口在同一帧关掉了）。
    func testAbandoningSaysWhereTheTranscriptAndTheRecordingWent() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        recording.beginOutcome = .started(relativePath: "recordings/2026-08-06T10-00-00Z.m4a")
        recording.outcome = RecordingOutcome(
            relativePath: "recordings/2026-08-06T10-00-00Z.m4a", duration: 92,
            interruptions: [], warning: nil)
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())
        runner.cancel()

        guard case .abandoned(let said) = runner.stage else {
            return XCTFail("放弃之后界面停在 \(runner.stage)，那里一个字都没交代"
                           + "逐字稿和录音去哪儿了")
        }
        XCTAssertTrue(said.contains("不会再操作 ChatGPT"),
                      "没说清「按下去之后它到底还会不会动我的 ChatGPT」：\(said)")
        XCTAssertTrue(said.contains("语音通话不会被自动挂断"),
                      "ChatGPT 那边的通话还开着，不说的话用户的麦克风一直开着而他毫不知情：\(said)")
        XCTAssertTrue(said.contains("recordings/2026-08-06T10-00-00Z.m4a"),
                      "录音在磁盘上成了没人认领的文件，却没告诉用户它在哪儿：\(said)")
        XCTAssertTrue(said.contains("训练记录"),
                      "没说清这一场进不进训练记录：\(said)")
        XCTAssertTrue(said.contains("下一步"), "只说了发生什么，没说下一步做什么：\(said)")
        // 「下一步」里指名的按钮必须在界面上真的存在（铁律 4）。
        PracticeRunnerTests.assertEveryNamedButtonExists(in: said)
    }

    /// 收尾走到一半才放弃时，这一场早就落盘了（那是刻意的：取复盘之前先记下来，
    /// 后面任何一步失败都不至于让用户白练）。**那就得如实说它在哪儿**，
    /// 不能顺嘴说成「已经丢掉了」。
    func testAbandoningDuringTheWrapUpSaysTheSessionIsAlreadyInTheHistory() async throws {
        let bridge = FakeBridge()
        bridge.voiceActive = true
        let gate = DispatchSemaphore(value: 0)
        bridge.gateAt = "endVoice"
        bridge.gate = gate
        let runner = self.runner(bridge: bridge)

        try await runner.start(setup: Self.setup())
        let wrapUp = Task { try? await runner.finishPractice() }
        let reached = await Self.waitOffMain(bridge.gateReached, seconds: 5)
        XCTAssertEqual(reached, .success, "收尾链路根本没跑起来，这条测试等于空转")
        runner.cancel()
        gate.signal()
        _ = await wrapUp.value

        guard case .abandoned(let said) = runner.stage else {
            return XCTFail("放弃之后界面停在 \(runner.stage)")
        }
        let sessionID = try XCTUnwrap(runner.finishedSessionID)
        XCTAssertTrue(said.contains(sessionID),
                      "这一场其实已经躺在「训练记录」里了，交代里却没有它的编号：\(said)")
        XCTAssertFalse(said.contains("跟着一起丢掉了"),
                       "这一场并没有丢，说成丢了会让用户以为白练了一场：\(said)")
    }

    /// 逐字稿真的被丢掉时，**得说丢了几条**，不能含糊过去。
    func testAbandoningBeforeTheWrapUpSaysTheTranscriptIsGone() async throws {
        let bridge = FakeBridge()
        let sampler = CountingSampler(turns: 3)
        let runner = Self.samplingRunner(bridge: bridge, sampler: sampler, directory: directory)

        try await runner.start(setup: Self.setup())
        await Self.waitForTranscript(runner, atLeast: 3)
        XCTAssertEqual(runner.transcriptTurnCount, 3, "这条测试的前提是真的采到了几条")
        runner.cancel()

        guard case .abandoned(let said) = runner.stage else {
            return XCTFail("放弃之后界面停在 \(runner.stage)")
        }
        XCTAssertTrue(said.contains("3 条对话"),
                      "丢掉了 3 条对话，交代里却没说丢了多少：\(said)")
        XCTAssertTrue(said.contains("不会进「训练记录」"),
                      "没说清这一场不会进训练记录：\(said)")
    }

    /// 逐字稿那句提示**不许再承诺「仍然会存进训练记录，不会丢」**——
    /// 取消路径上的实现与它正相反（复审第 6 条实测）。
    func testTheTranscriptNoticeDoesNotPromiseSomethingCancelDoesNotDo() async throws {
        let bridge = FakeBridge()
        let runner = Self.samplingRunner(bridge: bridge, sampler: CountingSampler(turns: 2),
                                         directory: directory)

        try await runner.start(setup: Self.setup())
        await Self.waitForTranscript(runner, atLeast: 2)
        runner.cancel()

        let notice = try XCTUnwrap(runner.transcriptNotice)
        XCTAssertFalse(notice.contains("仍然会存进"),
                       "这句话与取消路径上的实现正相反：那一场根本不落盘，"
                           + "采到的对话就地丢掉。实际是：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "改完之后仍要有下一步：\(notice)")
    }

    // MARK: - 装置

    private func runner(bridge: FakeBridge,
                        pasteboard: FakePasteboard = FakePasteboard(contents: ""),
                        recording: FakeRecording? = nil) -> PracticeRunner {
        PracticeRunner(bridge: bridge,
                       pasteboard: pasteboard,
                       directory: directory,
                       recording: recording,
                       now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// 一台真的会采逐字稿的运行器。采样节拍压到 20 毫秒，好让测试不必等两秒半。
    private static func samplingRunner(bridge: FakeBridge,
                                       sampler: any TranscriptSampling,
                                       directory: DataDirectory) -> PracticeRunner {
        PracticeRunner(bridge: bridge,
                       pasteboard: FakePasteboard(contents: ""),
                       directory: directory,
                       transcript: sampler,
                       samplingInterval: 0.02,
                       now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// 等采样跑上一拍。**次数封顶**：采不出来时这条测试要红在下一句断言上，
    /// 不能在这儿挂死（铁律 5）。
    private static func waitForTranscript(_ runner: PracticeRunner, atLeast count: Int) async {
        for _ in 0..<200 {
            if runner.transcriptTurnCount >= count { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "p1-home-001", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }

    private static let rawReview = """
        <<<IELTS_REVIEW_JSON:gui-1700000000>>>
        {"summary":"这次整体还行。",
         "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能直接修饰动词"}],
         "priority_target":{"id":"logic-explain","label":"回答后补一个原因和例子","status":"new",
                            "evidence":["I just like it."]}}
        <<<END_IELTS_REVIEW_JSON:gui-1700000000>>>
        """

    /// 在主线程之外等一个信号量。**必须带超时**：实现有问题时这些测试要红，
    /// 不能挂死在这儿（铁律 5）。
    private static func waitOffMain(_ semaphore: DispatchSemaphore,
                                    seconds: Int) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + .seconds(seconds)))
            }
        }
    }
}

/// 一开口就交出固定条数对话的假采样器。**不碰真实 ChatGPT**：
/// 这里要的只是「逐字稿里确实有东西」，好让「丢了几条」那句话有依据。
private final class CountingSampler: TranscriptSampling, @unchecked Sendable {
    private let turns: Int
    private var swept = false

    init(turns: Int) { self.turns = turns }

    func sample() -> TranscriptSweep {
        // 第一次是背景板（`TranscriptCollector.begin` 拿它当基线），要空的；
        // 之后每次都交出同样几段，拼接器会把它们并成 `turns` 条。
        defer { swept = true }
        guard swept else { return TranscriptSweep(fragments: [], failure: nil) }
        return TranscriptSweep(
            fragments: (0..<turns).map {
                TranscriptFragment(speaker: $0.isMultiple(of: 2) ? .examiner : .learner,
                                   text: "第 \($0 + 1) 段说的话，长度足够长以免被过滤掉。")
            },
            failure: nil)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
