import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 练完一场之后到底留下了什么：`state.sessions` 里那条训练记录、逐字稿、
/// `reports/<id>.json`，以及每一条失败路径上「已经产生的内容一点都不能丢」。
///
/// Phase 5 / 6 / 7 三个阶段都在等这条记录（首页四格、复训挂钩、录音归位），
/// 而写这份计划时全工程没有任何一行代码往 `state.sessions` 里写过东西。
///
/// **全程用假 Bridge 与假采样器，一次也不碰真实 ChatGPT（铁律 5）。**
@MainActor
final class PracticeRunnerArchiveTests: XCTestCase {
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
    }

    // MARK: - 会话记录（Phase 5 / 6 / 7 都在等这个）

    func testAFinishedPracticeLandsInStateSessions() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup(goal: "回答后补一个原因和例子"))
        try await runner.finishPractice()

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.count, 1, "练完一场必须留下一条训练记录")
        let session = try XCTUnwrap(saved.sessions.first)
        XCTAssertEqual(session.questionId, "p1-home-001")
        XCTAssertEqual(session.focusPart, .part1)
        XCTAssertEqual(session.goal, "回答后补一个原因和例子")
        XCTAssertFalse(session.startedAt.isEmpty, "没有开始时间的记录没法按月分组")
        XCTAssertFalse(session.endedAt.isEmpty)
    }

    /// 决策 1：新产生的编号一律是 `YYYY-MM-DD-NNN`，不再是 ISO8601 时间戳。
    func testTheSessionIDUsesTheNewShape() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        let id = try XCTUnwrap(try store.load().sessions.first?.id)
        XCTAssertEqual(id, "2026-08-06-001")
        XCTAssertEqual(runner.finishedSessionID, id, "Phase 6 要靠它把这一场和复训目标挂钩")
    }

    func testASecondPracticeOnTheSameDayGetsTheNextNumber() async throws {
        try store.mutate {
            $0.sessions.append(PracticeSession(id: "2026-08-06-003", questionId: "q",
                                               focusPart: .part1, startedAt: "", endedAt: "",
                                               goal: "", transcript: [], reportPath: "",
                                               recordingPath: ""))
        }
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        XCTAssertEqual(runner.finishedSessionID, "2026-08-06-004")
        XCTAssertEqual(try store.load().sessions.count, 2, "不能把已有的记录冲掉")
    }

    func testTheParsedReviewIsWrittenToReportsAndLinkedFromTheSession() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        let session = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(session.reportPath, "reports/2026-08-06-001.json",
                       "必须是相对数据目录的路径——写成绝对路径的话，换台电脑拷目录就全打不开了")
        let file = directory.root.appending(path: session.reportPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // reports/ 里存的必须是解析后的复盘本身，不是带定界标记的原文
        let json = try JSONValue.decode(from: String(contentsOf: file, encoding: .utf8))
        XCTAssertNotNil(json["must_correct"])
    }

    func testTheRawReviewIsOnDiskBeforeItIsEverParsed() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        let pending = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
            .filter { $0.hasSuffix(".txt") }
        XCTAssertEqual(pending, ["2026-08-06-001.txt"],
                       "原文必须先落盘再解析——练了半小时换来的复盘不能因为解析出错就没了。"
                       + "文件名也必须就是这一场的会话编号，否则「重新导入待处理的复盘」"
                       + "认不出它属于哪一场")
    }

    // MARK: - 逐字稿

    func testTheTranscriptEndsUpOnThePracticeSession() async throws {
        let runner = self.runner(sampler: Self.scriptedSampler())
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        let session = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(session.transcript.map(\.text),
                       ["Do you live in a house or a flat?", "I live in a flat with my parents."])
        XCTAssertEqual(session.transcript.map(\.role), ["assistant", "user"])
        XCTAssertEqual(runner.transcriptTurnCount, 2)
    }

    /// 练习进行中那个节拍必须真的在跑。
    ///
    /// 计划里没有这一条，但少了它，把 `start` 里那个每隔几秒 `tick()` 一次的 Task
    /// 整个删掉，其余每一条都照样绿——因为 `begin()` 和 `finish()` 各自也会采一次，
    /// 两次就够拼出上面那条测试要的两句话了。而真机上一场练习二十分钟、
    /// 十几轮问答，只靠首尾两次采样，中间说过的话一句都不会进逐字稿，
    /// 且界面上看不出任何异样（成品标准第 5 条当场落空）。
    ///
    /// 节拍值走注入（默认仍是实测定的 2.5 秒，铁律 9：要短就在测试里传参）。
    func testSamplingKeepsRunningWhileThePracticeIsInProgress() async throws {
        let sampler = Self.scriptedSampler()
        let runner = self.runner(sampler: sampler, samplingInterval: 0.02)
        try await runner.start(setup: Self.setup())

        // 带上限地等，绝不无限等待（铁律 7）。
        let ticked = await Self.waitUntil(seconds: 3) { sampler.sampleCount >= 4 }
        XCTAssertTrue(ticked,
                      "练习进行中一直没有再采样（只采到 \(sampler.sampleCount) 次）。"
                      + "那样的话中间十几轮问答一句都不会进逐字稿。")
        try await runner.finishPractice()
    }

    /// 中途放弃之后必须真的停下来。
    ///
    /// 计划的突变表里那一行（「`start` 的 catch 里的 `stopSampling()` 删掉」）实测不会变红，
    /// 原因是 `start` 里 `beginCollectingTranscript()` 之后再没有会抛错的语句，
    /// 那句 `stopSampling()` 在当前结构下打不出任何差别。
    /// **真正需要守的是这一条**：用户点「放弃这一场」之后，那个每隔几秒跑一次的
    /// 采样还在不在。还在的话，他接下来在 ChatGPT 里做的别的事会被一句句折进
    /// 这一场的逐字稿里，而界面上看不出任何异样。
    ///
    /// **它守的是行为，不是某一行。** `cancel()` 里那两句（`stopSampling()` 与
    /// `collector.abandon(...)`）互为冗余，实测：删掉任意一句这条仍绿，
    /// 两句一起删才变红（「采样次数从 3 涨到了 4」）。这是刻意的——
    /// 一句负责让 Task 别再空转，一句负责让采到的东西不再并进这一场，
    /// 少哪一句都还剩另一条防线；两句都没了才是真的没停。
    func testGivingUpMidwayStopsTheSampling() async throws {
        let sampler = Self.scriptedSampler()
        let runner = self.runner(sampler: sampler, samplingInterval: 0.02)
        try await runner.start(setup: Self.setup())
        let started = await Self.waitUntil(seconds: 3) { sampler.sampleCount >= 3 }
        XCTAssertTrue(started, "采样都没跑起来，这条测试等于空转")

        runner.cancel()
        let countAtCancel = sampler.sampleCount
        // 再给它十几个节拍的时间。涨了一次都算没停下来。
        let grew = await Self.waitUntil(seconds: 0.4) { sampler.sampleCount > countAtCancel }
        XCTAssertFalse(grew,
                       "取消之后还在读 ChatGPT 的界面（采样次数从 \(countAtCancel) 涨到了 "
                       + "\(sampler.sampleCount)）。用户放弃之后多半已经在用 ChatGPT 做别的事了，"
                       + "那些内容会被折进这一场的逐字稿里。")
    }

    func testNoSamplerMeansAnEmptyTranscriptAndNoComplaint() async throws {
        let runner = self.runner(sampler: nil)
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        XCTAssertTrue(try XCTUnwrap(try store.load().sessions.first).transcript.isEmpty)
        XCTAssertNil(runner.transcriptNotice, "用户自己关掉的功能不该报警")
    }

    /// **本阶段的硬约束。** 采样一路失败，练习必须照常走完，
    /// 而且练完要如实告诉用户逐字稿不完整。
    func testSamplingFailureNeverBreaksThePractice() async throws {
        let alwaysFailing = FakeTranscriptSampler([
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容")
        ])
        let runner = self.runner(sampler: alwaysFailing)
        try await runner.start(setup: Self.setup())

        XCTAssertEqual(runner.stage, .practicing, "采样失败绝不能把练习打断")
        try await runner.finishPractice()
        XCTAssertEqual(runner.stage, .done, "练习必须照常走完")

        let notice = try XCTUnwrap(runner.transcriptNotice, "不完整就必须说出来，不能装作正常")
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertEqual(try store.load().sessions.count, 1, "逐字稿没采到，这一场也照样要记下来")
    }

    // MARK: - 失败路径：已经产生的内容一点都不能丢（成品标准第 7 条）

    func testWhenTheReviewCannotBeParsedThePracticeIsStillRecorded() async throws {
        let bridge = Self.bridge(returning: "ChatGPT 这次输出了一段没有定界标记的闲聊"
                                 + String(repeating: "凑长度", count: 80))
        let runner = self.runner(bridge: bridge, sampler: Self.scriptedSampler())
        try await runner.start(setup: Self.setup())
        try? await runner.finishPractice()

        guard case .failed(let message) = runner.stage else {
            return XCTFail("解析不了就该停在失败态，不能假装成功")
        }
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertFalse(message.contains("终端"),
                       "不许把用户推回终端——界面里已经有「重新导入待处理的复盘」了")
        // 指的必须是**这份复盘能真的补回来**的那条路。
        //
        // 原先这里认的是「重新导入」——而那条路读的是盘上那份**已经坏掉**的原文，
        // 再导一百遍还是同一份。这句话前半段刚让用户「回 ChatGPT 重新输出一次」，
        // 后半段却把他指向一个收不下新内容的入口（铁律 4）。
        // 现在指的是复盘报告页那颗「从剪贴板补录这一场的复盘」。
        XCTAssertTrue(message.contains("从剪贴板补录"), "要指出界面里那个真能补回来的入口")
        XCTAssertTrue(message.contains("复盘报告"), "没说这颗按钮在哪一页")

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.count, 1, "复盘挂了，练习本身和逐字稿都还得在")
        // 用 XCTUnwrap 而不是 `sessions[0]`：这条一旦真的红了（记录没落库），
        // 下标会直接 `Index out of range` 把 xctest 进程打死，
        // 那一轮连 `Executed N tests` 的汇总都打不出来，同轮其余失败全部丢失。
        // 一条红掩盖全部，是本项目最不能接受的测试写法。
        let session = try XCTUnwrap(saved.sessions.first)
        XCTAssertEqual(session.transcript.count, 2)
        XCTAssertTrue(session.reportPath.isEmpty, "没有报告就不要假装有")
    }

    func testTheRawReviewSurvivesAParseFailure() async throws {
        let bridge = Self.bridge(returning: "没有定界标记的闲聊"
                                 + String(repeating: "凑长度", count: 80))
        let runner = self.runner(bridge: bridge)
        try await runner.start(setup: Self.setup())
        try? await runner.finishPractice()

        let pending = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(pending.count, 1, "解析失败时原文更不能丢")
        XCTAssertEqual(pending.first, "2026-08-06-001.txt")
    }

    func testAFailureDuringStartStopsCollectingAndRecordsNothing() async {
        let bridge = Self.bridge()
        bridge.failAt = .startingVoice
        let sampler = Self.scriptedSampler()
        let runner = self.runner(bridge: bridge, sampler: sampler)
        try? await runner.start(setup: Self.setup())

        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertNil(runner.finishedSessionID, "根本没练成，不能留下一条训练记录")
        XCTAssertEqual((try? store.load())?.sessions.count, 0)
        // 断言的不是 `stage`（它早就红了），而是采样器有没有被启动过：
        // 考官提示词还没发出去就开始采样的话，采到的全是别的东西，
        // 而且那个 Task 会在练习早就结束之后继续空转。
        XCTAssertEqual(sampler.sampleCount, 0,
                       "练都没练起来就开始采样了——逐字稿必须等考官提示词发出去之后才开始收集")
    }

    // MARK: - 测试装置

    // MARK: - 随机抽题：一场抽到的整组题都要记下来

    /// 一场抽了 3 道全练了，训练记录却只记开场那一道的话，另外两道会永远停在「新题」：
    /// 「只抽没练过的」一遍遍把它们再抽出来，训练题库页那个「已练 N / 258」也永远偏小——
    /// 两样都不报错。
    func testADrawnSessionRecordsEveryQuestionItWasGiven() async throws {
        let drawn = [Question(id: "p1-home-001", part: 1, topic: "Home",
                              prompt: "Do you live in a house or a flat?"),
                     Question(id: "p1-food-001", part: 1, topic: "Food",
                              prompt: "How often do you cook?"),
                     Question(id: "p2-shop-001", part: 2, topic: "Place",
                              prompt: "Describe a shop you enjoy visiting.")]
        try store.mutate { $0.questions = drawn }

        let runner = self.runner()
        try await runner.start(setup: SessionSetup(question: drawn[0], focusPart: .part1And2,
                                                   durationMinutes: 11, goal: "",
                                                   drawnQuestions: drawn))
        try await runner.finishPractice()

        let saved = try store.load()
        let session = try XCTUnwrap(saved.sessions.first)
        XCTAssertEqual(session.drawnQuestionIds, drawn.map(\.id))
        // 读盘那一刻「已练」标记就该全部算回来（`CoachState.reconcilePracticedStatus`）。
        XCTAssertEqual(saved.questions.filter { $0.status == "practiced" }.map(\.id),
                       drawn.map(\.id),
                       "抽到的题只有开场那一道被标成已练，另外两道会被当成新题一遍遍再抽出来")
    }

    /// 反过来：普通练习**不许**多写这个字段。写了的话，普通练习的 state.json
    /// 形状就变了，而这个字段做 Optional 的全部意义就是不动它。
    func testAnOrdinaryPracticeDoesNotRecordADraw() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()
        XCTAssertNil(try store.load().sessions.first?.drawnQuestionIds)
    }

    private static func setup(goal: String = "") -> SessionSetup {
        SessionSetup(question: Question(id: "p1-home-001", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: goal)
    }

    private let fixedNow = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

    private static func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private static func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }

    /// 背景板一次（`begin`），之后每一次都是完整的这一场（`tick` / `finish`）。
    ///
    /// **不像计划里那样写三个逐步变长的 sweep**：那份脚本要正好被消费三次才拼得出两句话，
    /// 而 `begin` + `finish` 只消费两次，中间那次要靠真等 2.5 秒的节拍——
    /// 靠 sleep 碰运气的测试比没有还糟。这里改成「背景板 + 稳定的最终画面」，
    /// 采几次都得到同一个结果（`TranscriptAssembler` 的去重本来就该做到这一点），
    /// 断言与计划完全一致。
    private static func scriptedSampler() -> FakeTranscriptSampler {
        FakeTranscriptSampler([
            TranscriptSweep(fragments: [learner("You will act as an IELTS Speaking examiner.")]),
            TranscriptSweep(fragments: [learner("You will act as an IELTS Speaking examiner."),
                                        examiner("Do you live in a house or a flat?"),
                                        learner("I live in a flat with my parents.")])
        ])
    }

    /// 会正常交出一份合法复盘的假 Bridge。
    ///
    /// 计划让往 `FakeBridge` 上加一个 `reviewText` 属性，但那份 `FakeBridge` 已经有了
    /// 等价的 `copyResult`（Phase 3 就做成可编程的了），再加一个只会有两个接缝干同一件事。
    private static func bridge(returning review: String = rawReview) -> FakeBridge {
        let bridge = FakeBridge()
        bridge.copyResult = .success(review)
        return bridge
    }

    private static let rawReview = """
        <<<IELTS_REVIEW_JSON:archive-test>>>
        {"summary":"这次整体还行，问题集中在动词修饰上。",
         "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能直接修饰动词"}],
         "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding trip",
                        "priority":"high"}],
         "priority_target":{"id":"logic-explain","label":"回答后补一个原因和例子","status":"new",
                            "evidence":["I just like it."]}}
        <<<END_IELTS_REVIEW_JSON:archive-test>>>
        """

    private func runner(bridge: FakeBridge = PracticeRunnerArchiveTests.bridge(),
                        sampler: (any TranscriptSampling)? = nil,
                        samplingInterval: TimeInterval = 2.5) -> PracticeRunner {
        PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                       directory: directory, transcript: sampler,
                       samplingInterval: samplingInterval,
                       now: { [fixedNow] in fixedNow })
    }

    /// 轮询等一个条件成立，**必须带上限**：条件永远不成立时这条测试要红，
    /// 不能挂死在这儿（铁律 7）。
    private static func waitUntil(seconds: Double,
                                  _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
