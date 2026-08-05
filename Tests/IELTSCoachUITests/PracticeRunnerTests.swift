import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 可编程的假 Bridge，用于测试整条状态流转。**全程不接触真实 ChatGPT（铁律 5）。**
///
/// 计划 Task 9 给的版本只能记调用名，这里多存了三样东西，因为没有它们下面几条测试就没有牙齿：
/// - `sentTexts`：考官提示词到底发出去了什么。只断言「调过 sendText」的话，
///   把提示词换成空字符串测试照样绿——而那正是「练完一整场才发现 ChatGPT 根本没进考官角色」。
/// - `voiceActive`：`finishPractice` 里「语音还开着才去结束」那个分支的两边都要走到。
/// - `copyResult` / `captureResult`：取复盘的三级降级，每一级都要能单独制造失败。
///
/// 内部状态加锁：这些方法由 `PracticeRunner` 在后台线程上调用（AX 调用是阻塞的，
/// 放在主线程上会让窗口冻住十几秒），测试在主线程读它们。
final class FakeBridge: CoachBridge, @unchecked Sendable {
    /// 在哪一步抛错。nil 表示全程成功。
    var failAt: PracticeStage?
    /// `isVoiceActive()` 返回什么。
    var voiceActive = false
    /// `copyLatestAssistantMessage` 的结果：成功返回文本，失败抛错。
    var copyResult: Result<String, BridgeError> = .success("")
    /// `captureLatestAssistantMessage` 的结果。
    var captureResult: Result<String, BridgeError> = .success("")

    private let lock = NSLock()
    private var recordedCalls: [String] = []
    private var recordedTexts: [String] = []
    private var recordedMarkers: [String?] = []

    var calls: [String] { lock.withLock { recordedCalls } }
    var sentTexts: [String] { lock.withLock { recordedTexts } }
    var expectedMarkers: [String?] { lock.withLock { recordedMarkers } }

    func clearCalls() { lock.withLock { recordedCalls = [] } }

    private func step(_ name: String, _ stage: PracticeStage) throws {
        lock.withLock { recordedCalls.append(name) }
        if failAt == stage {
            throw BridgeError.actionFailed("假装失败。下一步：这是测试用的。")
        }
    }

    func preflight() -> BridgeReadiness { BridgeReadiness(ok: true, messages: []) }

    func startNewChat() throws { try step("newChat", .newChat) }

    func startVoice() throws { try step("startVoice", .startingVoice) }

    func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot {
        try step("waitComposer", .waitingComposer)
        return AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea")
    }

    func sendText(_ text: String) throws {
        // 考官提示词与复盘请求走的是同一个方法，按次序区分：第一次是开练时的考官提示词，
        // 之后都是收尾时的复盘请求。用 `failAt` 去猜的话，`failAt = .requestingReview`
        // 会连开练那一次 sendText 一起打掉，测试就跑不到收尾阶段了。
        let isFirst = lock.withLock { recordedTexts.append(text); return recordedTexts.count == 1 }
        try step("sendText", isFirst ? .sendingPrompt : .requestingReview)
    }

    func isVoiceActive() -> Bool { lock.withLock { voiceActive } }

    func endVoice() throws { try step("endVoice", .endingVoice) }

    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int) throws {
        try step("waitReply", .requestingReview)
    }

    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String {
        lock.withLock { recordedCalls.append("captureAX"); recordedMarkers.append(expectedMarker) }
        return try captureResult.get()
    }

    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                    timeout: TimeInterval) throws -> String {
        lock.withLock { recordedCalls.append("copy") }
        return try copyResult.get()
    }
}

/// 剪贴板的假实现。`Tests/ChatGPTBridgeTests/` 里有一个同名的，但那是另一个测试 target 的
/// 内部类型，跨 target 取不到——照计划的要求在这里另建一个，不跨 target 引用。
final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String

    init(contents: String) { self.stored = contents }

    func readString() -> String? { lock.withLock { stored } }
    func clear() { lock.withLock { stored = "" } }

    /// 测试专用：模拟「用户在 ChatGPT 里选中整段复盘按了 ⌘C」。
    /// 不叫 `write`，避免和某个真实协议方法同名造成误解——这纯粹是测试装置。
    func simulateUserCopied(_ text: String) { lock.withLock { stored = text } }
}

@MainActor
final class PracticeRunnerTests: XCTestCase {

    // MARK: - 每一步都要有话对用户说

    func testEveryStageHasUserFacingChineseText() {
        for stage in Self.allStages {
            XCTAssertFalse(stage.userFacingText.isEmpty, "\(stage) 没有给用户看的说明")
        }
    }

    /// 上面那条自己没有牙齿：`userFacingText` 全部返回同一个「请稍候」它照样绿。
    /// 每一步说的必须是**这一步**的事——用户盯着这行字判断程序有没有卡住。
    func testEveryStageSaysSomethingDifferent() {
        let texts = Self.allStages.map(\.userFacingText)
        XCTAssertEqual(Set(texts).count, texts.count,
                       "有两步给用户看的是同一句话，用户分不出程序走到哪儿了")
    }

    func testStartingVoiceTextWarnsAboutTheWait() {
        // 实测启动语音约需 9 秒（spec 2.3.7）。这 9 秒里界面必须说明它在等什么、要等多久，
        // 否则用户会以为程序卡死了。
        let text = PracticeStage.startingVoice.userFacingText
        XCTAssertTrue(text.contains("秒"), "启动语音耗时较长，提示必须写明大约要等多久")
        XCTAssertTrue(text.contains("10 秒"),
                      "只说「要等一会儿」不够。实测 9 秒，写明约 10 秒用户才知道该不该继续等")
    }

    /// 进度清单靠这个次序决定哪几步已经打上勾。次序错了，界面会在「正在启动语音」时
    /// 把后面的步骤也标成已完成，用户以为快好了，其实才走到第二步。
    func testStageOrderFollowsTheSpecSequence() {
        let sequence: [PracticeStage] = [.idle, .newChat, .startingVoice, .waitingComposer,
                                         .sendingPrompt, .practicing, .endingVoice,
                                         .requestingReview, .capturingReview, .archiving, .done]
        for (earlier, later) in zip(sequence, sequence.dropFirst()) {
            XCTAssertLessThan(earlier.order, later.order, "\(earlier) 排在了 \(later) 后面")
        }
        XCTAssertEqual(PracticeStage.needsManualCopy("x").order,
                       PracticeStage.capturingReview.order,
                       "等用户手动复制仍停在「取复盘」这一格，不该显示成已经往下走了")
    }

    // MARK: - 开练：顺序不能改

    func testStagesRunInOrderUpToPracticing() async throws {
        let bridge = FakeBridge()
        let runner = Self.runner(bridge: bridge)
        try await runner.start(setup: Self.setup())
        XCTAssertEqual(bridge.calls, ["newChat", "startVoice", "waitComposer", "sendText"],
                       "必须先新建会话、再启动语音、等语音输入框出现，最后才发提示词")
        XCTAssertEqual(runner.stage, .practicing)
    }

    /// 发出去的必须是这道题的考官提示词。
    ///
    /// 只断言「调过 sendText」的话，把参数换成空字符串测试照样绿——而那意味着用户对着一个
    /// 普通聊天机器人练完整整一场，等复盘出来是一团乱麻才发现不对（成品标准第 3 条）。
    func testTheExaminerPromptForThisQuestionIsWhatGetsSent() async throws {
        let bridge = FakeBridge()
        let runner = Self.runner(bridge: bridge)
        let setup = Self.setup()
        try await runner.start(setup: setup)
        let sent = try XCTUnwrap(bridge.sentTexts.first)
        XCTAssertEqual(sent, ExaminerPrompt.build(setup: setup))
        XCTAssertTrue(sent.contains(setup.question.prompt), "提示词里得有今天这道题")
    }

    func testFailureStopsTheChain() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = Self.runner(bridge: bridge)
        try? await runner.start(setup: Self.setup())
        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertFalse(bridge.calls.contains("sendText"), "前一步失败后不能继续往下走")
    }

    /// 失败信息必须原样带上桥那边写好的中文说明（它自带「下一步」），并说清断在哪一步。
    ///
    /// 换成一句自己编的「练习失败」，用户就只剩重启一条路可走（铁律 6）。
    func testFailureKeepsTheActionableMessageFromTheBridge() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = Self.runner(bridge: bridge)
        try? await runner.start(setup: Self.setup())
        guard case .failed(let message) = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertTrue(message.contains("假装失败。下一步：这是测试用的。"),
                      "桥那边的原话被吞掉了，用户看不到到底哪里出的问题")
        XCTAssertTrue(message.contains("启动语音"), "得说清断在哪一步，否则无从下手")
    }

    /// 桥以外的失败（磁盘、系统 API）抛出来的是不带「下一步」的 NSError。
    /// 直接透传等于给用户一句他做不了任何事的英文报错。
    func testFailureWithoutANextStepGetsOne() {
        let bare = NSError(domain: "test", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "something went wrong"])
        let described = PracticeRunner.describeFailure(bare, at: .archiving)
        XCTAssertTrue(described.contains("something went wrong"), "原始报错不能丢")
        XCTAssertTrue(described.contains("下一步"), "系统报错不带「下一步」，这里必须补上")
    }

    /// 「重试」到底该重做什么，取决于断在哪个阶段——**这个区分不是锦上添花**。
    ///
    /// 开练阶段失败时重做整条链路，第一步是按「新建会话」；而收尾阶段（请复盘、取复盘、存档）
    /// 失败时若也去按「新建会话」，那条刚练完、复盘还在里面的会话当场就没了，
    /// 用户练的半小时连同复盘一起蒸发，界面上看着还像是「重试了一下」。
    func testRetryPointsAtTheRightThingToRedo() async throws {
        let startFailure = FakeBridge()
        startFailure.failAt = .startingVoice
        let a = Self.runner(bridge: startFailure)
        try? await a.start(setup: Self.setup())
        XCTAssertEqual(a.retry, .restart, "还没练呢，重试就该从头再来一遍")

        let wrapUpFailure = FakeBridge()
        wrapUpFailure.failAt = .requestingReview
        let b = Self.runner(bridge: wrapUpFailure, directory: try Self.temporaryDirectory())
        try await b.start(setup: Self.setup())
        try? await b.finishPractice()
        XCTAssertEqual(b.retry, .wrapUp,
                       "练已经练完了，重试只该重做收尾。跑去新建会话会把这条带着复盘的会话冲掉")
    }

    // MARK: - 练完：结束语音 → 请复盘 → 取回 → 先落盘再解析 → 归档

    func testFinishPracticeRunsTheWrapUpInOrderAndArchives() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success(Self.rawReview)
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        bridge.clearCalls()
        try await runner.finishPractice()

        XCTAssertEqual(bridge.calls, ["endVoice", "sendText", "waitReply", "copy"],
                       "必须先结束语音再请复盘——语音还开着时发文字，ChatGPT 未必收得到")
        XCTAssertEqual(runner.stage, .done)

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.issues.count, 1, "错题本该从 0 变正（成品标准第 4 条）")
        XCTAssertEqual(state.vocabulary.count, 1, "词汇本该从 0 变正")
        XCTAssertEqual(state.targets.count, 1, "重训目标该从 0 变正")
    }

    /// 语音已经结束（用户自己在 ChatGPT 里挂了）时不该再去按一次结束——
    /// `AXDriver.endVoice` 在没有通话时会直接抛错，整场练习的复盘就取不回来了。
    func testFinishPracticeSkipsEndingVoiceWhenTheCallIsAlreadyOver() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = false
        bridge.copyResult = .success(Self.rawReview)
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        bridge.clearCalls()
        try await runner.finishPractice()

        XCTAssertFalse(bridge.calls.contains("endVoice"))
        XCTAssertEqual(runner.stage, .done)
    }

    /// **先落盘再解析。** 练了半小时换来的复盘，不能因为解析出错就没了（成品标准第 7 条）。
    ///
    /// 反过来写（先解析成功才落盘）时，这条会红：文件根本不会存在。
    func testTheRawReviewIsWrittenToDiskBeforeParsing() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success("这一段根本不是 JSON，解析一定失败。" + String(repeating: "凑长度", count: 80))
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        try? await runner.finishPractice()

        let pending = directory.pendingReviewsDirectory.appending(path: "\(Self.requestID).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path),
                      "解析失败了，但原文必须已经在盘上——不然用户练的这一场就白练了")
        let saved = try String(contentsOf: pending, encoding: .utf8)
        XCTAssertTrue(saved.contains("这一段根本不是 JSON"))

        guard case .failed(let message) = runner.stage else { return XCTFail("解析失败该进失败态") }
        XCTAssertTrue(message.contains(pending.path), "得把原文存在哪儿告诉用户")
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 取复盘的三级降级

    func testFallsBackToReadingTheAccessibilityTreeWhenTheCopyButtonFails() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .failure(.elementNotFound("没找到复制按钮。下一步：测试用的。"))
        bridge.captureResult = .success(Self.rawReview)
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        XCTAssertEqual(runner.stage, .done, "第一条路断了还有第二条，不该直接判失败")
        XCTAssertEqual(bridge.expectedMarkers, [ReviewRequestPrompt.marker(requestID: Self.requestID).open],
                       "AX 兜底必须带本次复盘的标记——不带就退回「取界面上最长的那段文字」，"
                           + "很可能取到别的东西，而解析器只看字段齐不齐，多半不会报错")
    }

    /// 两条自动路都断了时**不许判失败了事**：复盘还完整地在 ChatGPT 窗口里，
    /// 用户手动 ⌘C 一次就能救回来，这一场就不算白练（成品标准第 7 条）。
    func testBothAutomaticCapturesFailingAsksTheUserToCopyManually() async throws {
        let directory = try Self.temporaryDirectory()
        let pasteboard = FakePasteboard(contents: "")
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .failure(.elementNotFound("没找到复制按钮。下一步：测试用的。"))
        bridge.captureResult = .failure(.elementNotFound("AX 树里也没读到。下一步：测试用的。"))
        let runner = Self.runner(bridge: bridge, pasteboard: pasteboard, directory: directory)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        guard case .needsManualCopy(let message) = runner.stage else {
            return XCTFail("两条自动路都断了应当转到「请手动复制」，而不是失败或静默")
        }
        XCTAssertTrue(message.contains("⌘C"), "得告诉用户具体怎么复制")
        XCTAssertTrue(message.contains("下一步"))

        // 用户照做之后，点一下就该把这一场救回来。
        pasteboard.simulateUserCopied(Self.rawReview)
        try await runner.captureReviewFromClipboard()
        XCTAssertEqual(runner.stage, .done)
        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.issues.count, 1, "手动兜底救回来的复盘一样要归档")
    }

    // MARK: - 中途取消

    /// 取消之后再点「我练完了」，不该去驱动 ChatGPT——那时候用户可能已经在用它做别的事了。
    func testCancelStopsTheRunAndFinishRefusesToDriveChatGPT() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        runner.cancel()
        XCTAssertEqual(runner.stage, .idle)

        bridge.clearCalls()
        try? await runner.finishPractice()
        XCTAssertEqual(bridge.calls, [], "取消之后不该再有任何一次 ChatGPT 操作")
        guard case .failed(let message) = runner.stage else {
            return XCTFail("没有正在进行的练习却要收尾，得说清楚，不能装作没事")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 测试装置

    /// 时间戳可注入，本次复盘请求的 id 才是确定的（下面几条要按 id 去找落盘文件）。
    static let requestID = "gui-1700000000"

    static let allStages: [PracticeStage] = [
        .idle, .newChat, .startingVoice, .waitingComposer, .sendingPrompt, .practicing,
        .endingVoice, .requestingReview, .capturingReview, .needsManualCopy("手动复制说明"),
        .archiving, .done, .failed("出事了。下一步：重试。")
    ]

    static let rawReview = """
        <<<IELTS_REVIEW_JSON:\(requestID)>>>
        {"summary":"这次整体还行，问题集中在动词修饰与词汇精度上。",
         "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能直接修饰动词"}],
         "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding trip",
                        "priority":"high"}],
         "priority_target":{"id":"logic-explain","label":"回答后补一个原因和例子","status":"new",
                            "evidence":["I just like it."]}}
        <<<END_IELTS_REVIEW_JSON:\(requestID)>>>
        """

    static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "q1", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }

    private static func runner(bridge: FakeBridge,
                               pasteboard: FakePasteboard = FakePasteboard(contents: ""),
                               directory: DataDirectory? = nil) -> PracticeRunner {
        PracticeRunner(bridge: bridge,
                       pasteboard: pasteboard,
                       directory: directory ?? DataDirectory(root: URL(fileURLWithPath: "/dev/null")),
                       now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private static var createdDirectories: [URL] = []

    /// 每条测试一个临时目录：**绝不碰用户真实的训练数据**。
    static func temporaryDirectory() throws -> DataDirectory {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-runner-tests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        createdDirectories.append(root)
        return DataDirectory(root: root)
    }

    override class func tearDown() {
        for url in createdDirectories { try? FileManager.default.removeItem(at: url) }
        createdDirectories = []
        super.tearDown()
    }
}
