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
    /// 「按复制按钮」那一步的闸门。设上之后，`copyLatestAssistantMessage` 一进来先放行
    /// `copyStarted`，再卡在这里等 `signal()`——测试因此能在这一步**跑到一半**时
    /// 检查界面这时显示的是哪一步（实测最长 10 秒，界面在这段时间里说的必须是这一步的事）。
    /// 卡的是后台线程，主线程照常跑，`PracticeRunner` 的阶段更新不受影响。
    var copyGate: DispatchSemaphore?
    let copyStarted = DispatchSemaphore(value: 0)

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
        if let copyGate {
            copyStarted.signal()
            copyGate.wait()
        }
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
    ///
    /// **断言的是 `userFacingText`，不是 `.failed` 的关联值。** 界面上那行字画的是
    /// `runner.stage.userFacingText`（`PracticeSheet.stageBlock`），这是失败信息上屏的唯一路径；
    /// 只断言关联值的话，把 `PracticeStage.failed` 那一支改成 `return "操作失败。"`
    /// 一样绿——而用户看到的就只剩这四个字。
    func testFailureKeepsTheActionableMessageFromTheBridge() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = Self.runner(bridge: bridge)
        try? await runner.start(setup: Self.setup())
        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        let shown = runner.stage.userFacingText
        XCTAssertTrue(shown.contains("假装失败。下一步：这是测试用的。"),
                      "桥那边的原话没画到界面上，用户看不到到底哪里出的问题")
        XCTAssertTrue(shown.contains("启动语音"), "得说清断在哪一步，否则无从下手")
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

        // 档案真的动了，还得让用户看得见动了多少。只画一句「完成」的话，
        // 「复盘写得完整、档案却纹丝不动」这种静默失败永远没人发现。
        let notice = try XCTUnwrap(runner.archiveNotice, "存档之后必须交代进了多少条、原文存在哪儿")
        XCTAssertTrue(notice.contains("错题本 1 条"), "没说错题本进了几条：\(notice)")
        XCTAssertTrue(notice.contains("词汇本 1 条"), "没说词汇本进了几条：\(notice)")
        XCTAssertTrue(notice.contains("重训目标 1 个"), "没说重训目标进了几个：\(notice)")
        XCTAssertTrue(notice.contains(Self.pendingPath(in: directory).path),
                      "没说复盘原文存在哪儿，用户想自己核对时无从下手：\(notice)")
        XCTAssertFalse(notice.contains("⚠️"), "这一份复盘整份都归进档案了，不该报警：\(notice)")
    }

    /// **静默的 0 必须说出来。** 顶层 `must_correct` 明明有内容，却一条都没归进档案——
    /// 多半是 ChatGPT 用的字段名和本工具读的对不上。这种失败不报错、不崩溃，
    /// 只是悄悄什么都不做，是本项目已知最危险的失败形态。
    ///
    /// 这条测试守的是 `archiveNotice` 的**内容**：把那段话整个换成一句「完成」，它必须变红。
    func testTheNoticeCallsOutFieldsThatWentNowhere() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success(Self.reviewWithUnreadableIssues)
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()
        XCTAssertEqual(runner.stage, .done, "字段读不进去不算失败，复盘本身是完整的")

        let notice = try XCTUnwrap(runner.archiveNotice, "存档之后必须有交代")
        XCTAssertTrue(notice.contains("must_correct"),
                      "复盘里的 must_correct 一条都没归进档案，这件事必须点名说出来：\(notice)")
        XCTAssertTrue(notice.contains("错题本 0 条"),
                      "归进去 0 条这件事得直接写出来，不能只显示一个「完成」：\(notice)")
        XCTAssertTrue(notice.contains(Self.pendingPath(in: directory).path),
                      "得把复盘原文的路径给出来，用户才能打开对照着看：\(notice)")
        XCTAssertTrue(notice.contains("下一步"),
                      "只说「没归进去」不说该做什么，用户没法处理（铁律 6）：\(notice)")
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

        let pending = Self.pendingPath(in: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path),
                      "解析失败了，但原文必须已经在盘上——不然用户练的这一场就白练了")
        let saved = try String(contentsOf: pending, encoding: .utf8)
        XCTAssertTrue(saved.contains("这一段根本不是 JSON"))

        guard case .failed = runner.stage else { return XCTFail("解析失败该进失败态") }
        let shown = runner.stage.userFacingText
        XCTAssertTrue(shown.contains(pending.path), "得把原文存在哪儿告诉用户")
        XCTAssertTrue(shown.contains("下一步"))
        Self.assertPointsAtTheButtonThatIsActuallyThere(runner)
    }

    /// **解析失败那句话，一个字都不许把用户支到界面上不存在的地方。**
    ///
    /// 这句话是拼出来的：`PracticeRunner.archive` 把 `ReviewParser` 抛出来的错原样嵌进去。
    /// 而 `ReviewParser` 在 `IELTSCoachCore` 里，`coach` 命令行也在用它，它那句
    /// 「下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次」是命令行时代的说法——
    /// `grep -rn 'Button(' Sources/IELTSCoachUI/` 全仓库没有这颗按钮。
    ///
    /// **Core 的文案不能改**（命令行那边照它做是对的），该退让的是界面这一侧：
    /// 只取诊断、丢掉它自带的「下一步」，然后由界面写一句界面上真做得到的下一步。
    ///
    /// 这条同时钉住诊断没被一起砍掉——只剩一句「解析不出来」的话，
    /// 用户分不出是 ChatGPT 输出被截断了，还是压根就没按格式写。
    func testAParseFailureNeverRepeatsTheCommandLineEraNextStep() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success("ChatGPT 这次只回了一段闲聊，没有 JSON。"
                                     + String(repeating: "凑长度", count: 80))
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        try? await runner.finishPractice()

        guard case .failed = runner.stage else { return XCTFail("解析失败该进失败态") }
        let shown = runner.stage.userFacingText

        XCTAssertFalse(shown.contains("补生成复盘报告"),
                       "把 `ReviewParser` 那句命令行时代的「下一步」原样转述给了界面用户，"
                           + "而界面上没有这颗按钮，照着找会找不到（铁律 4）。原话：\(shown)")
        XCTAssertTrue(shown.contains("没有返回可识别的标准复盘JSON"),
                      "诊断被一起砍掉了。只说「解析不出来」的话，用户分不出是输出被截断了"
                          + "还是压根没按格式写：\(shown)")
        Self.assertEveryNamedButtonExists(in: shown)
    }

    /// 同一类毛病还能从别处溜过去：`PracticeStage` 每一步那句话里也在指按钮
    /// （`.idle` 指「开始练习」、`.practicing` 指「我练完了」）。
    /// 那几句是写死的字面量，改了按钮标题却忘了改这里，用户照样找不到。
    func testEveryStageThatTellsTheUserToClickSomethingNamesARealButton() {
        var checked = 0
        for stage in Self.allStages {
            let targets = SourceGuard.clickTargets(in: stage.userFacingText)
            guard !targets.isEmpty else { continue }
            checked += 1
            Self.assertEveryNamedButtonExists(in: stage.userFacingText)
        }
        XCTAssertGreaterThanOrEqual(checked, 2,
                                    "一步都没扫到「点『…』」，这条测试等于空转")
    }

    /// 「下一步」里指名的那颗按钮，必须就是这时界面上真会画出来的那一颗。
    ///
    /// 界面画的是 `runner.retry` 对应的那一颗（`PracticeSheet` 只在 `.failed` 时按
    /// `runner.retry` 画一颗，`.needsManualCopy` 时画「我已经复制好了」）。
    /// 文案里指了另一颗的话，用户拿着一句「再用「X」这条路重来」在界面上找不到 X。
    ///
    /// **这条断言之前只比对另外两种 `PracticeRetry`，于是漏掉了一整类。**
    /// 实测：解析失败那句话是把 `error.localizedDescription` 原样嵌进去拼出来的，
    /// 而那个 error 来自 `ReviewParser`（Core，命令行也在用），原话是
    /// 「下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次」——
    /// **全 App 没有这颗按钮**，用户照着找会找不到，而这条断言当时是绿的。
    ///
    /// 所以现在改成：把这句话里每一处「点『X』」都揪出来，逐个对着
    /// **从源码里读出来的**按钮清单查。清单是读出来的不是手写的，
    /// 所以将来改了按钮标题、或者新加一种重试，这里会跟着变红而不是悄悄失效。
    static func assertPointsAtTheButtonThatIsActuallyThere(
        _ runner: PracticeRunner, file: StaticString = #filePath, line: UInt = #line) {
        let shown = runner.stage.userFacingText
        guard let retry = runner.retry else {
            return XCTFail("这时候界面上一颗重试按钮都没有", file: file, line: line)
        }
        XCTAssertTrue(shown.contains("「\(retry.buttonTitle)」"),
                      "「下一步」没指出该点哪颗按钮：\(shown)", file: file, line: line)
        for other in PracticeRetry.allCases where other.buttonTitle != retry.buttonTitle {
            XCTAssertFalse(shown.contains("「\(other.buttonTitle)」"),
                           "「下一步」指的「\(other.buttonTitle)」这时界面上根本没有"
                               + "（画出来的是「\(retry.buttonTitle)」）：\(shown)",
                           file: file, line: line)
        }
        assertEveryNamedButtonExists(in: shown, file: file, line: line)
    }

    /// 一句面向用户的话里，凡是「点『X』」，X 都得是界面上真有的按钮。
    ///
    /// 清单 = 界面模块里字面写死的 `Button("…")` ∪ `PracticeRetry` 那几个算出来的标题
    /// （后者画出来的是 `Button(retry.buttonTitle)`，扫不到字面标题）。
    /// 两边都不是手写的：新加一种重试、改一颗按钮的字，清单自己会跟着变。
    static func assertEveryNamedButtonExists(
        in message: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let buttons = try SourceGuard.literalButtonTitles()
                .union(PracticeRetry.allCases.map(\.buttonTitle))
            let named = SourceGuard.clickTargets(in: message)
            XCTAssertFalse(named.isEmpty,
                           "这句话里一处「点『…』」都没有，这条检查等于空转：\(message)",
                           file: file, line: line)
            for target in named where !buttons.contains(target) {
                XCTFail("这句话让用户去点「\(target)」，而界面上没有这颗按钮（铁律 4）。"
                            + "界面上真有的是：\(buttons.sorted().joined(separator: "、"))。"
                            + "原话：\(message)",
                        file: file, line: line)
            }
        } catch {
            XCTFail("读不到按钮清单，这条检查等于空转：\(error)", file: file, line: line)
        }
    }

    /// 手动 ⌘C 那条路上解析也失败时：**不许判成失败态**（复盘还在 ChatGPT 窗口里），
    /// 且「下一步」指的按钮同样得是这时界面上真有的那一颗。
    func testAParseFailureOnTheClipboardPathStillPointsAtTheRightButton() async throws {
        let directory = try Self.temporaryDirectory()
        let pasteboard = FakePasteboard(contents: "")
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .failure(.elementNotFound("没找到复制按钮。下一步：测试用的。"))
        bridge.captureResult = .failure(.elementNotFound("AX 树里也没读到。下一步：测试用的。"))
        let runner = Self.runner(bridge: bridge, pasteboard: pasteboard, directory: directory)

        try await runner.start(setup: Self.setup())
        try await runner.finishPractice()

        pasteboard.simulateUserCopied("复制是复制到了，但这段不是 JSON。" + String(repeating: "凑长度", count: 80))
        try await runner.captureReviewFromClipboard()

        guard case .needsManualCopy = runner.stage else {
            return XCTFail("解析失败不该把这条路堵死——复盘还完整地在 ChatGPT 窗口里，能再复制一次")
        }
        let shown = runner.stage.userFacingText
        XCTAssertTrue(shown.contains(Self.pendingPath(in: directory).path), "得把原文存在哪儿告诉用户")
        XCTAssertTrue(shown.contains("下一步"))
        Self.assertPointsAtTheButtonThatIsActuallyThere(runner)
    }

    // MARK: - 取复盘的三级降级

    /// **阶段先设、再 await。** 取复盘的第一级（按 ChatGPT 自己的复制按钮）最长要等 10 秒，
    /// 这 10 秒里界面显示的必须是「正在取复盘」，而不是上一步那句
    /// 「正在请 ChatGPT 写复盘…这一步可能要一分钟左右」——那会让用户以为还在等 ChatGPT 写字。
    ///
    /// 顺带守住进度清单：`.capturingReview` 在 happy path 上永远不出现的话，
    /// 「取回复盘」那一格从来不会作为当前步骤亮起，进度看着像是直接跳过了一步。
    func testTheStageSwitchesToCapturingBeforeTheCopyButtonStepRuns() async throws {
        let directory = try Self.temporaryDirectory()
        let bridge = FakeBridge()
        bridge.voiceActive = true
        bridge.copyResult = .success(Self.rawReview)
        let gate = DispatchSemaphore(value: 0)
        bridge.copyGate = gate
        let runner = Self.runner(bridge: bridge, directory: directory)

        try await runner.start(setup: Self.setup())
        let finishing = Task { try await runner.finishPractice() }

        // 等「按复制按钮」这一步真的跑进去了。**不在主线程上 wait**：阶段更新要靠主线程，
        // 卡住主线程的话读到的永远是旧值。超时兜底，避免实现有问题时整个测试挂死（铁律 7）。
        let started = await Self.waitOffMain(bridge.copyStarted, seconds: 5)
        if started == .success {
            XCTAssertEqual(runner.stage, .capturingReview,
                           "复制按钮那一步已经在跑了，界面显示的却还是上一步：\(runner.stage.userFacingText)")
        }
        gate.signal()
        _ = try? await finishing.value

        XCTAssertEqual(started, .success, "「按复制按钮」这一步 5 秒内没跑起来，这条测试等于空转")
        XCTAssertEqual(runner.stage, .done)
    }

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

        guard case .needsManualCopy = runner.stage else {
            return XCTFail("两条自动路都断了应当转到「请手动复制」，而不是失败或静默")
        }
        // 断言的是 `userFacingText`——那才是界面上真会画出来的那行字。
        let message = runner.stage.userFacingText
        XCTAssertTrue(message.contains("⌘C"), "得告诉用户具体怎么复制")
        XCTAssertTrue(message.contains("下一步"))
        Self.assertPointsAtTheButtonThatIsActuallyThere(runner)

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
        guard case .failed = runner.stage else {
            return XCTFail("没有正在进行的练习却要收尾，得说清楚，不能装作没事")
        }
        XCTAssertTrue(runner.stage.userFacingText.contains("下一步"),
                      "界面上画出来的那行字得说清下一步做什么：\(runner.stage.userFacingText)")
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

    /// 顶层 `must_correct` 有内容，但里面的字段名（`said` / `fix`）不是本工具读的那几个。
    /// 解析得过、归档却一条都进不去——`ArchiveOutcome.skipped` 要报的就是这种。
    static let reviewWithUnreadableIssues = """
        <<<IELTS_REVIEW_JSON:\(requestID)>>>
        {"summary":"这份复盘的字段名和本工具读的对不上。",
         "must_correct":[{"said":"I very like it.","fix":"I really like it."}],
         "priority_target":{"id":"logic-explain","label":"回答后补一个原因和例子","status":"new",
                            "evidence":["I just like it."]}}
        <<<END_IELTS_REVIEW_JSON:\(requestID)>>>
        """

    /// 在主线程之外等一个信号量，等到了再回到主线程。**必须带超时**：实现有问题时
    /// 这条测试要红，不能挂死在这儿（铁律 7）。
    static func waitOffMain(_ semaphore: DispatchSemaphore, seconds: Int) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + .seconds(seconds)))
            }
        }
    }

    /// 复盘原文的落盘路径。运行器要在交代里把它给出来，用户才能自己打开对照。
    static func pendingPath(in directory: DataDirectory) -> URL {
        directory.pendingReviewsDirectory.appending(path: "\(requestID).txt")
    }

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
