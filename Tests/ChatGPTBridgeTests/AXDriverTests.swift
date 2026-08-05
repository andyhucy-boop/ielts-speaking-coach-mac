import XCTest
@testable import ChatGPTBridge

final class AXDriverTests: XCTestCase {
    // brief 里写的是 `AXElementRef(rawID: id)`，但 epoch 已在上一提交（004c9d0）里
    // 变成无默认值的必填参数，字面照抄编译不过。这里传 epoch: 0 —— 具体值不重要，
    // 因为 FakeAXAccess.snapshotTree() 每次调用都会用当前代次盖印 nodes 里所有元素，
    // 传入的字面量只是占位。与 AXLocatorTests.swift 的处理方式保持一致。
    private func composer(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXTextArea",
                       descriptionText: ChatGPTLabels.composerDescription)
    }
    private func control(_ id: Int, _ desc: String) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXButton",
                       descriptionText: desc, childCount: 1, childRoles: ["AXImage"])
    }
    // 实测发送按钮的结构：AXButton desc="Send"，唯一子节点 AXImage —— 与 control(_:_:) 相同的
    // 结构判据，单独起名是为了让调用处一眼看出这是发送按钮而不是随便一个控制按钮。
    private func sendButton(_ id: Int, _ desc: String = "Send") -> AXNodeSnapshot {
        control(id, desc)
    }
    private func voiceActive(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXImage",
                       descriptionText: ChatGPTLabels.voiceActiveIndicator)
    }
    // 语音模式下的输入框（description = "Work with ChatGPT"），与 composer(_:) 区分开——
    // 后者用的是普通聊天态的描述，两者不能互相冒充。
    private func voiceComposer(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXTextArea",
                       descriptionText: ChatGPTLabels.voiceComposerDescription)
    }
    // 修复轮第 4 条（我在上一轮报告里提出的疑虑）：brief 原版 helper 没有覆盖默认的
    // shortTimeout(5.0)/stateTimeout(当时是 8.0，本轮改成 25.0，见下方
    // testDefaultTimeoutsMatchRealMeasuredStartupDelay)，导致「预期失败」的测试要真的
    // 等到超时才拿到结果。这里显式传短超时，让整个测试类的耗时从约 13 秒降到 1 秒以内。
    private func driver(_ access: FakeAXAccess) -> AXDriver {
        AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                 shortTimeout: 0.2, stateTimeout: 0.2)
    }

    // 【超时太短】的直接回归测试：用户逐秒采样 25 秒实测，Live 语音第 9 秒才出现
    // Voice chat active，旧默认 8 秒正好卡在它起来的前一秒。这是首次真机联调失败的
    // 直接原因。这里不模拟真的等 9/25 秒（会让测试套件变慢），只断言默认值本身对不对——
    // 数值层面的正确性由这条测试兜底，实际等待行为已由 AXLocatorTests 的
    // waitUntil/waitForNode 相关用例覆盖。
    func testDefaultTimeoutsMatchRealMeasuredStartupDelay() {
        let access = FakeAXAccess()
        let sut = AXDriver(access: access, locator: AXLocator(access: access))
        XCTAssertEqual(sut.shortTimeout, 5.0)
        XCTAssertEqual(sut.stateTimeout, 25.0,
                       "实测 Live 语音第 9 秒才出现 Voice chat active；旧默认 8 秒正好卡在前一秒，"
                       + "25 秒才留得出余量")
    }

    func testPreflightFailsWhenTargetMissing() {
        let access = FakeAXAccess(); access.installed = false
        let readiness = driver(access).preflight()
        XCTAssertFalse(readiness.ok)
        XCTAssertTrue(readiness.messages.joined().contains("下一步"))
    }

    func testPreflightFailsWithoutAccessibilityPermission() {
        let access = FakeAXAccess(); access.trusted = false
        let readiness = driver(access).preflight()
        XCTAssertFalse(readiness.ok)
        XCTAssertTrue(readiness.messages.joined().contains("辅助功能"))
    }

    // 实测模拟回车不会发送——文字会原样留在输入框里，必须按 Send 按钮。这条测试
    // 原名 testSendTextWritesComposerThenPressesReturn，按回车已被证实不管用后改为按按钮，
    // 断言对象也从 returnKeyCount 换成了「按下的是 Send 按钮」。
    func testSendTextWritesComposerThenPressesSendButton() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]
        // 模拟「按下 Send 后 ChatGPT 真的收到了，输入框被清空」。
        access.onPress = { _, nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        try driver(access).sendText("你好")
        XCTAssertEqual(access.setValues.count, 1)
        XCTAssertEqual(access.setValues[0].1, "你好")
        XCTAssertEqual(access.pressedElements.map(\.rawID), [2], "必须按下 Send 按钮")
    }

    // 第 2 条缺陷的直接回归测试（本轮改名前叫 testSendTextNeverCallsSendReturnKey）：
    // Send 按钮存在时必须优先走按钮这条路，不能因为「反正回车也是条备选路径」就
    // 绕过按钮直接模拟回车——按钮路径是普通聊天状态下唯一实测有效的路径。
    // 回车路径本身没有退场：本次故障（语音模式没有 Send 按钮）恰恰要求把它加回来，
    // 见下面 testSendTextFallsBackToReturnKeyWhenNoSendButtonExists。
    func testSendTextPrefersSendButtonOverReturnKeyWhenButtonExists() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]
        access.onPress = { _, nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        try driver(access).sendText("你好")
        XCTAssertEqual(access.returnKeyCount, 0, "Send 按钮在时必须走按钮，不能绕过去模拟回车")
    }

    // 第 3 条【语音模式没有 Send 按钮】的直接回归测试：实测第 4 秒起 Send 按钮就消失了，
    // 整个语音期间（采样到第 25 秒）都没再出现过。语音模式下写完提示词必须退回模拟回车，
    // 不能死等一个根本不会出现的按钮，否则 sendText 在语音模式下永远发不出去东西。
    func testSendTextFallsBackToReturnKeyWhenNoSendButtonExists() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 没有 Send 按钮——语音模式下的真实现场
        access.onSendReturnKey = { nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        try driver(access).sendText("你好")
        XCTAssertEqual(access.returnKeyCount, 1, "没有 Send 按钮时必须退回模拟回车")
        XCTAssertTrue(access.pressedElements.isEmpty, "没有按钮可按，不该留下任何 press 记录")
    }

    // 两条路都没能让输入框变空——必须响亮报错，不能静默判定成功（呼应第 2 条修复
    // 强调过的教训：验证要问「到底变没变」，不能只问「现在是不是目标态」）。
    func testSendTextFailsActionablyWhenNeitherButtonNorReturnKeyClearsComposer() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 没有 Send 按钮；onSendReturnKey 保持默认（什么都不做）
        XCTAssertThrowsError(try driver(access).sendText("考官提示词")) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
        }
        XCTAssertEqual(access.returnKeyCount, 1, "仍应该尝试过回车这条路")
        XCTAssertTrue(access.pressedElements.isEmpty)
    }

    func testSendTextFailsWhenComposerStillHoldsTheText() {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]   // 按了 Send，但输入框没被清空 —— 模拟「发送没生效」
        XCTAssertThrowsError(try driver(access).sendText("考官提示词")) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
        }
    }

    // 第 3 条缺陷的直接回归测试：本项目第二次栽在「验证只问现在是不是目标态、
    // 没问到底变没变」上。旧判据是「composer.value != 写入值」——但 AX 读回的值
    // 与写入值不可能逐字节相同（换行/空白会被规范化），旧判据在这里会一开始就为真，
    // 把「根本没清空、只是被规范化了」误判成「发送成功」。
    func testSendTextDoesNotFalselySucceedWhenComposerTextIsMerelyNormalized() {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]
        access.onPress = { _, nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" {
                // AX 读回值被规范化（多了个换行），但输入框并没有真的清空。
                nodes[i].value = "考官提示词\n"
            }
        }
        XCTAssertThrowsError(try driver(access).sendText("考官提示词")) { error in
            XCTAssertTrue("\(error)".contains("下一步"),
                          "输入框只是内容被规范化、并未清空时必须继续判定为未发送")
        }
    }

    // 第 3 次栽在「验证判据与实际观测对不上」（spec 2.3.6）：实测空输入框的 value
    // 不是空字符串，而是「换行 + 输入框自己的 description」，例如 "\nMessage ChatGPT"。
    // 上一轮改的判据是「等到 value 变空」，永远等不到——消息明明发出去了也会超时。
    // 这条测试直接用故障现场实测到的占位符字符串构造场景，是本次故障的直接回归测试。
    func testSendTextRecognizesObservedPlaceholderValueAsSentState() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]
        access.onPress = { _, nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" {
                // 实测：ChatGPT 输入框空态的 value 是这个确切的字符串，不是 ""。
                nodes[i].value = "\nMessage ChatGPT"
            }
        }
        try driver(access).sendText("你好")
        XCTAssertEqual(access.pressedElements.map(\.rawID), [2],
                       "占位符状态必须被识别为「已发送」，不能超时")
    }

    // guard...else { return false } 而不是原来的 `?? true`：输入框从树上找不到时
    // 必须继续等，不能被当成发送成功。
    func testSendTextKeepsWaitingWhenComposerDisappearsFromTree() {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]
        access.onPress = { _, nodes in
            nodes.removeAll { $0.role == "AXTextArea" }
        }
        XCTAssertThrowsError(try driver(access).sendText("考官提示词")) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
        }
    }

    // 【流程顺序反了】的修复（spec 2.3.5）：Live 语音只能在还没发送过任何消息的会话里
    // 启动，这一点从 AX 树上看不出来，是用户实测发现的。每次练习开始前都要先按
    // 「新建会话」，保证这个前提成立，否则 startVoice 会静默失败——按钮按得下去，
    // 但语音起不来。

    func testStartNewChatPressesButton() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "New chat")]
        try driver(access).startNewChat()
        XCTAssertEqual(access.pressedElements.map(\.rawID), [1])
    }

    func testStartNewChatFailsActionablyWhenButtonNotFound() {
        let access = FakeAXAccess()
        access.nodes = []   // 界面上完全没有「新建会话」按钮
        XCTAssertThrowsError(try driver(access).startNewChat()) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
        }
        XCTAssertTrue(access.pressedElements.isEmpty)
    }

    func testStartNewChatFailsActionablyWhenPressReturnsFalse() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "New chat")]
        access.pressSucceeds = false   // kAXPressAction 本身就失败
        XCTAssertThrowsError(try driver(access).startNewChat()) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
            XCTAssertTrue("\(error)".contains("新建"), "错误信息应指明按的是哪个按钮：\(error)")
        }
    }

    // waitForVoiceComposer 曾经是对 locator.waitForComposer 的纯转发，本轮改掉了——
    // 转发版会在实测第 9~11 秒那个窗口里命中还没切换过来的普通输入框（description 仍是
    // "Message ChatGPT"），把考官提示词发进错误的地方。以下三条是本次故障的直接回归测试。

    func testWaitForVoiceComposerFindsVoiceComposerWhenAlreadyPresent() throws {
        let access = FakeAXAccess()
        access.nodes = [voiceComposer(1)]
        let found = try driver(access).waitForVoiceComposer(timeout: 0.5)
        XCTAssertEqual(found.element.rawID, 1)
    }

    // 【发进错误的输入框】的核心场景，本次故障的直接现场：树里只有普通输入框
    // "Message ChatGPT" 时必须继续等，不能提前返回；等语音输入框
    // "Work with ChatGPT" 出现才能返回。这条测试改回旧的「转发 waitForComposer」实现时
    // 会立刻变红——旧实现见到 composer(1) 就直接返回了，根本不会等 voiceComposer(2) 出现。
    func testWaitForVoiceComposerKeepsWaitingWhileOnlyNormalComposerIsPresent() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 只有 "Message ChatGPT"——实测第 9~11 秒那个窗口
        // 直接构造节点而不是调用 self.voiceComposer(_:)：DispatchQueue.global().asyncAfter
        // 的闭包是 @Sendable 的，捕获 self（非 Sendable 的 XCTestCase 子类）会触发警告；
        // 与本文件其余 asyncAfter 用例（如 testWaitForAssistantReplyWaitsForStreamingToStopBeforeReturning）
        // 保持同样的写法。
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXTextArea",
                                           descriptionText: ChatGPTLabels.voiceComposerDescription)]
        }
        let found = try driver(access).waitForVoiceComposer(timeout: 1.0)
        XCTAssertEqual(found.element.rawID, 2,
                       "必须等到语音输入框出现，不能命中窗口期里的普通输入框")
    }

    func testWaitForVoiceComposerFailsActionablyWhenItNeverAppears() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 一直只有普通输入框，语音输入框始终没出现
        XCTAssertThrowsError(try driver(access).waitForVoiceComposer(timeout: 0.1)) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
            XCTAssertTrue("\(error)".contains("语音"))
        }
    }

    func testStartVoiceVerifiesIndicatorAppeared() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat")]
        access.onPress = { _, nodes in nodes.append(self.voiceActive(9)) }
        try driver(access).startVoice()
        // 上一轮我把这里断言的 epoch 硬编码成具体数值（当时是 2），但协调者这轮点破了
        // 这个写法本身就是脆弱点：调用链前面任何一次新增/删减 snapshotTree() 调用都会让
        // 硬编码的代次错位（这轮 sendText 的验证又新增了一次快照，波及范围只会越来越大）。
        // 代次校验的正确性已由 AXElementRefEpochTests.testPressRejectsElementFromStaleSnapshot
        // 单独覆盖，这里只需要断言「按下的是哪个元素」，改成只比 rawID。
        XCTAssertEqual(access.pressedElements.map(\.rawID), [1])
    }

    func testStartVoiceFailsWhenIndicatorNeverAppears() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat")]
        access.onPress = nil   // 按下了但界面没变 —— 正是「假阳性点击」的现场
        XCTAssertThrowsError(try driver(access).startVoice()) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
            XCTAssertTrue(error is BridgeError)
        }
    }

    func testStartVoiceRejectsSidebarRowAndReportsWhy() {
        let access = FakeAXAccess()
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 5, epoch: 0), role: "AXButton",
                                       descriptionText: "New voice chat",
                                       childCount: 3, childRoles: ["AXGroup", "AXButton", "AXButton"])]
        XCTAssertThrowsError(try driver(access).startVoice()) { error in
            XCTAssertTrue("\(error)".contains("结构不符"))
        }
        XCTAssertTrue(access.pressedElements.isEmpty, "结构不符的元素一次都不能按")
    }

    func testEndVoiceVerifiesIndicatorDisappeared() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Stop voice chat"), voiceActive(9)]
        access.onPress = { _, nodes in nodes.removeAll { $0.descriptionText == ChatGPTLabels.voiceActiveIndicator } }
        try driver(access).endVoice()
        XCTAssertFalse(ChatGPTLabels.isVoiceActive(access.nodes))
    }

    func testCaptureReturnsLongestAssistantText() throws {
        let access = FakeAXAccess()
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText", value: "短"),
            AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXStaticText",
                           value: String(repeating: "复盘内容", count: 40))
        ]
        let captured = try driver(access).captureLatestAssistantMessage()
        XCTAssertTrue(captured.count > 100)
    }

    func testCaptureFailsWithActionableMessageWhenNothingReadable() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]
        XCTAssertThrowsError(try driver(access).captureLatestAssistantMessage()) { error in
            XCTAssertTrue("\(error)".contains("⌘C"), "读不到时必须提示用户改用剪贴板：\(error)")
            XCTAssertTrue("\(error)".contains("下一步"))
        }
    }

    func testCaptureRequiresMarkerWhenGiven() {
        let access = FakeAXAccess()
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                           value: String(repeating: "用户自己粘贴的一大段无关文字", count: 20)),
            AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXStaticText",
                           value: "<<<IELTS_REVIEW_JSON:sync-9>>>{\"must_correct\":[]}<<<END_IELTS_REVIEW_JSON:sync-9>>>")
        ]
        let captured = try? driver(access).captureLatestAssistantMessage(expectedMarker: "sync-9")
        XCTAssertEqual(captured?.contains("sync-9"), true,
                       "给了标记就必须命中标记，不能因为别的文本更长就取错")
    }

    func testStartVoiceRefusesWhenVoiceAlreadyActive() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat"), voiceActive(9)]   // 语音已在跑
        XCTAssertThrowsError(try driver(access).startVoice()) { error in
            XCTAssertTrue("\(error)".contains("已经有一场语音通话"))
            XCTAssertTrue("\(error)".contains("下一步"))
        }
        XCTAssertTrue(access.pressedElements.isEmpty,
                      "语音已在跑时一次都不能按下启动——否则会静默接管上一场通话，本次提示词失效")
    }

    func testEndVoiceRefusesWhenNoVoiceRunning() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Stop voice chat")]   // 按钮在，但没有 voiceActive 标志
        XCTAssertThrowsError(try driver(access).endVoice()) { error in
            XCTAssertTrue("\(error)".contains("没有正在进行的语音通话"))
        }
        XCTAssertTrue(access.pressedElements.isEmpty)
    }

    // 第 4 条缺陷：发完提示词必须等 ChatGPT 回复完再进语音，否则语音会话可能不带
    // 考官设定就开始了。判据是「够长的文本连续三次采样不再增长」。

    func testWaitForAssistantReplyReturnsOnceTextIsLongEnoughAndStopsGrowing() throws {
        let access = FakeAXAccess()
        // 文本从一开始就是最终长度、后续快照不再变化——应在连续三次采样后返回。
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                           value: String(repeating: "考官反馈内容", count: 10))   // 60 字符
        ]
        try driver(access).waitForAssistantReply(timeout: 5)
    }

    func testWaitForAssistantReplyWaitsForStreamingToStopBeforeReturning() throws {
        let access = FakeAXAccess()
        let finalText = String(repeating: "考官反馈内容", count: 10)   // 60 字符
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText", value: "")
        ]
        // 模拟流式输出：先出现一段还没达到门槛长度的文本，随后才涨到最终长度并停止变化。
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                                           value: String(finalText.prefix(20)))]
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                                           value: finalText)]
        }
        try driver(access).waitForAssistantReply(timeout: 5)
    }

    func testWaitForAssistantReplyThrowsActionableErrorWhenTextNeverLongEnough() {
        let access = FakeAXAccess()
        access.nodes = []   // 没有任何文本，也就永远达不到 minimumLength
        XCTAssertThrowsError(try driver(access).waitForAssistantReply(timeout: 0.1)) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
            XCTAssertTrue("\(error)".contains("回复完"))
        }
    }

    // spec 2.3.9：复盘在 AX 树里被切成大量碎片节点（连定界标记本身都被拆成三段），
    // captureLatestAssistantMessage(expectedMarker:) 找的是「某个节点包含完整标记」，
    // 这样的节点根本不存在。改用 ChatGPT 自己的复制按钮，再从剪贴板读。

    func testCopyLatestAssistantMessageThrowsActionableErrorWhenButtonNotFound() {
        let access = FakeAXAccess()
        access.nodes = []   // 界面上完全没有复制按钮
        let pasteboard = FakePasteboard(contents: "")
        XCTAssertThrowsError(
            try driver(access).copyLatestAssistantMessage(pasteboard: pasteboard, timeout: 0.1)
        ) { error in
            XCTAssertTrue("\(error)".contains("复制按钮"))
            XCTAssertTrue("\(error)".contains("下一步"))
        }
        XCTAssertFalse(pasteboard.wasCleared, "按钮都没找到就不该动用户的剪贴板")
    }

    func testCopyLatestAssistantMessagePressesLastCopyButtonAndReadsClipboard() throws {
        let access = FakeAXAccess()
        access.nodes = [
            control(1, "Copy message"),   // 用户自己那条消息的复制按钮——不能被按
            control(2, "Copy"),           // 更早一轮助手回复的复制按钮
            control(3, "Copy")            // 最新一条助手回复的复制按钮——要的是它
        ]
        let pasteboard = FakePasteboard(contents: "")
        let review = "<<<IELTS_REVIEW_JSON:sync-1>>>" + String(repeating: "复盘内容", count: 40)
            + "<<<END_IELTS_REVIEW_JSON:sync-1>>>"
        // 模拟按下复制按钮后 ChatGPT 真的把内容写进了剪贴板。
        access.onPress = { _, _ in pasteboard.simulateExternalWrite(review) }

        let captured = try driver(access).copyLatestAssistantMessage(pasteboard: pasteboard, timeout: 0.5)

        XCTAssertEqual(access.pressedElements.map(\.rawID), [3],
                       "必须按下最后一个 Copy 按钮，不能按用户自己消息的 Copy message，"
                       + "也不能按更早一轮的 Copy")
        XCTAssertEqual(captured, review)
    }

    func testCopyLatestAssistantMessageFailsActionablyWhenPressFails() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Copy")]
        access.pressSucceeds = false   // kAXPressAction 本身就失败
        let pasteboard = FakePasteboard(contents: "")
        XCTAssertThrowsError(
            try driver(access).copyLatestAssistantMessage(pasteboard: pasteboard, timeout: 0.5)
        ) { error in
            XCTAssertTrue("\(error)".contains("按下复制按钮失败"))
            XCTAssertTrue("\(error)".contains("下一步"))
        }
    }

    // 防「静默拿到错误数据」的关键测试（派单点名要求）：剪贴板里是上一次复盘留下的
    // 旧内容，这次复制按钮虽然按下去了，但 ChatGPT 没有真的写剪贴板（onPress 保持默认，
    // 什么都不做）。若实现忘了在按钮之前调用 pasteboard.clear()，这里会静默返回
    // 上面那段 200+ 字符的旧内容——看起来像一份正常复盘，实际文不对题。
    //
    // 突变验证：把 AXDriver.copyLatestAssistantMessage 里的 `pasteboard.clear()` 那一行
    // 注释掉，这条测试会红——XCTAssertThrowsError 不会抛错，因为读到的是 staleReview。
    func testCopyLatestAssistantMessageFailsRatherThanReturningStaleClipboardContentWhenChatGPTDoesNotWrite() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Copy")]
        let staleReview = "<<<IELTS_REVIEW_JSON:sync-OLD>>>" + String(repeating: "上一次的旧复盘", count: 40)
            + "<<<END_IELTS_REVIEW_JSON:sync-OLD>>>"
        let pasteboard = FakePasteboard(contents: staleReview)
        // access.onPress 保持默认（nil）：按钮真的按下去了，但界面/剪贴板都没有变化——
        // 这正是「复制功能悄悄失效」的故障现场。

        XCTAssertThrowsError(
            try driver(access).copyLatestAssistantMessage(pasteboard: pasteboard, timeout: 0.5)
        ) { error in
            XCTAssertTrue("\(error)".contains("剪贴板是空的"),
                          "按钮之前必须先清空剪贴板；不清空的话这里会静默返回上一次复盘的旧内容："
                          + "\(error)")
        }
        XCTAssertTrue(pasteboard.wasCleared, "按下复制按钮之前必须调用一次 clear()")
        XCTAssertEqual(access.pressedElements.map(\.rawID), [1], "按钮确实被按下了，只是剪贴板没被写")
    }
}

final class ClipboardFallbackTests: XCTestCase {
    func testReadsPlainTextFromPasteboard() throws {
        // 门槛从 40 提到 200 后，brief 原版的 51 字符载荷（两个定界标记 + 1 个字符）
        // 会被新门槛挡下，测试本身先红了一次。补足到 200+ 字符，同时保留原意：
        // 校验首尾空白被裁掉、内容原样返回。
        let body = String(repeating: "x", count: 200)
        let payload = "<<<IELTS_REVIEW_JSON>>>\(body)<<<END_IELTS_REVIEW_JSON>>>"
        let pasteboard = FakePasteboard(contents: "  \(payload)  ")
        XCTAssertEqual(try ClipboardFallback.readReview(from: pasteboard), payload)
    }

    func testEmptyPasteboardGivesActionableChineseError() {
        XCTAssertThrowsError(try ClipboardFallback.readReview(from: FakePasteboard(contents: ""))) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("剪贴板"))
            XCTAssertTrue(message.contains("下一步"))
        }
    }

    func testTooShortContentIsRejected() {
        // 用户可能没选中就按了 ⌘C，剪贴板里是上一次复制的零碎内容
        XCTAssertThrowsError(try ClipboardFallback.readReview(from: FakePasteboard(contents: "ok"))) { error in
            XCTAssertTrue("\(error)".contains("太短"))
        }
    }

    func testModeratelyLongButNonReviewContentIsStillRejected() {
        // 门槛从 40 提到 200：光两个定界标记加起来就超过 40 字符，旧门槛形同虚设。
        // 这里验证一段 100 字符左右、明显不是复盘 JSON 的内容依然会被挡在门外。
        let notAReview = String(repeating: "这不是复盘", count: 20)   // 100 字符
        XCTAssertThrowsError(try ClipboardFallback.readReview(from: FakePasteboard(contents: notAReview))) { error in
            XCTAssertTrue("\(error)".contains("太短"))
        }
    }
}
