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
    /// **通话中那一屏**：输入框 + 通话控制按钮。
    ///
    /// 2026-08-08 真机 dump 推翻了「靠 description 区分状态」这个前提——
    /// 这一版 ChatGPT 的输入框在空对话和通话中都叫 `Work with ChatGPT`。
    /// 真正随状态变的是同一行上的按钮（空对话有 `Start new voice chat`，
    /// 通话中有 `Stop voice chat`），所以造树时必须把它们摆上，
    /// 否则造出来的是一棵**现实中不存在**的树。
    private func voiceComposerTree(_ id: Int) -> [AXNodeSnapshot] {
        [
            AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXTextArea",
                           descriptionText: ChatGPTLabels.voiceComposerDescription),
            control(9001, "Stop voice chat"),
        ]
    }

    /// **空对话那一屏**：同样的输入框，但摆的是 `Start new voice chat`。
    private func idleComposerTree(_ id: Int) -> [AXNodeSnapshot] {
        [
            AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXTextArea",
                           descriptionText: ChatGPTLabels.voiceComposerDescription),
            control(9002, "Start new voice chat"),
        ]
    }
    // 修复轮第 4 条（我在上一轮报告里提出的疑虑）：brief 原版 helper 没有覆盖默认的
    // shortTimeout(5.0)/stateTimeout(当时是 8.0，本轮改成 25.0，见下方
    // testDefaultTimeoutsMatchRealMeasuredStartupDelay)，导致「预期失败」的测试要真的
    // 等到超时才拿到结果。这里显式传短超时，让整个测试类的耗时从约 13 秒降到 1 秒以内。
    //
    // Task 10（第二次耗时回归）：光有 shortTimeout/stateTimeout 还不够。sendText 等 Send 按钮、
    // waitForAssistantReply 的采样间隔、复制之后等剪贴板这三处的节奏，此前是写死在
    // AXDriver 里的字面量（2.0 / 0.5 / 0.8 秒），测试无从缩短——本类 33 条测试因此白等
    // 11.4 秒，占全套 16 秒的七成。现在这三处也从构造函数注入，**产品默认值一个没动**
    // （由 testDefaultPacingValuesMatchTheMeasuredOnes 钉住），测试统一传短值。
    private func driver(_ access: FakeAXAccess,
                        sendButtonTimeout: TimeInterval = 0.05,
                        replySampleInterval: TimeInterval = 0.01,
                        clipboardSettleDelay: TimeInterval = 0.02) -> AXDriver {
        AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                 shortTimeout: 0.05, stateTimeout: 0.05,
                 sendButtonTimeout: sendButtonTimeout,
                 replySampleInterval: replySampleInterval,
                 clipboardSettleDelay: clipboardSettleDelay)
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

    // 与上面那条同样的作用，守的是 Task 10 新注入的三个节奏值：它们能从构造函数传短值
    // 是为了让测试跑得快，**产品默认值必须原样不动**（铁律 9）。这三个数都不是随手写的：
    //
    // - 2.0 秒等 Send 按钮：实测普通聊天下写完文字按钮才出现，而语音模式下第 4 秒起
    //   它就永远不再出现——等太短会漏掉刚要出现的按钮，等太久则每次语音发送都白等。
    // - 0.5 秒采样间隔：连续三次不增长才算回复完，间隔太密会把流式输出的一次停顿
    //   误判成结束。
    // - 0.8 秒等剪贴板：按下复制按钮到 ChatGPT 真的写进剪贴板之间有延迟，不等就会
    //   读到刚被清空的空剪贴板。
    //
    // 谁把这三个默认值调小来「让测试快一点」，这条测试就变红。
    func testDefaultPacingValuesMatchTheMeasuredOnes() {
        let access = FakeAXAccess()
        let sut = AXDriver(access: access, locator: AXLocator(access: access))
        XCTAssertEqual(sut.sendButtonTimeout, 2.0,
                       "等 Send 按钮的默认时长不能改——语音模式下它永远不出现，靠等满这段时间才退回回车")
        XCTAssertEqual(sut.replySampleInterval, 0.5,
                       "判断「回复完了」的采样间隔不能改——间隔太密会把流式输出的停顿当成结束")
        XCTAssertEqual(sut.clipboardSettleDelay, 0.8,
                       "按下复制按钮后等剪贴板的时长不能改——不等会读到刚被自己清空的空剪贴板")
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

    // 修问题 15 时顺手堵上的同类漏洞：`preflight()` 里 `wakeAccessibilityTree(timeout: 8.0)`
    // 是本类唯一一个**没有从构造函数注入**的等待值。它躲过了本文件所有的耗时断言——
    // 假环境里这个方法立刻返回，谁把 8.0 改成 0.5 都不会让任何测试变慢、更不会变红，
    // 只有真机上才会表现成「无障碍树没能唤醒」，而用户拿到的是一句读不到对话内容的警告。
    //
    // 不把它也改成注入参数（那要动产品接口，且没有任何测试需要缩短它——假环境不等待），
    // 改成把实参记下来直接断言。谁改这个数，这条测试当场变红。
    func testPreflightWakesTheAccessibilityTreeWithTheMeasuredTimeout() {
        let access = FakeAXAccess()
        _ = driver(access).preflight()
        XCTAssertEqual(access.wakeTimeouts, [8.0],
                       "preflight 必须给无障碍树 8 秒醒过来的时间，且只唤醒一次；"
                       + "实际传的是 \(access.wakeTimeouts)。这个数改小了在假环境里毫无迹象，"
                       + "只有真机上会变成「无障碍树没能唤醒」")
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
        try driver(access).sendText("你好", into: .any)
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
        try driver(access).sendText("你好", into: .any)
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
        try driver(access).sendText("你好", into: .any)
        XCTAssertEqual(access.returnKeyCount, 1, "没有 Send 按钮时必须退回模拟回车")
        XCTAssertTrue(access.pressedElements.isEmpty, "没有按钮可按，不该留下任何 press 记录")
    }

    // 上面那条「没有 Send 按钮就退回回车」有个前提：得先真的等一会儿。实测 Send 按钮是
    // **写完文字之后**才出现的，写入的那一瞬间树上还没有它——立刻放弃就会在普通聊天状态下
    // 也走回车，而回车在普通聊天状态下实测无效（spec 2.3.4），提示词根本发不出去。
    //
    // 这条测试让按钮晚 0.02 秒才出现，并给足 1 秒的等待窗口：实现若不等（例如把
    // waitForControl 的 timeout 写成 0）会立刻退回回车，断言当场变红。
    //
    // **这里原本还写着「它同时证明构造函数传进去的 sendButtonTimeout 真被用上了」——那句话是错的**，
    // 已删除。它给的窗口是 1 秒、按钮 0.02 秒就出现，所以把 timeout 写死成产品默认的 2.0 秒，
    // 按钮照样等得到，这条断言照样绿（复审实测：写死后 37 条全绿，只有耗时从 1.1 秒涨到 5.1 秒）。
    // 「注入的值真被用上了」由下面那条 testSendTextWaitsOnlyTheSendButtonTimeoutItWasGiven
    // 用耗时上下界来证明，本条只管「等不等」这件事。
    func testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 写入文字的这一刻，Send 按钮还没出现
        access.onPress = { _, nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        // 整树替换而不是 append：nodes 会被轮询线程并发读写，赋一份新数组与本文件
        // 其余 asyncAfter 用例的写法一致（见 testWaitForVoiceComposerKeepsWaiting…）。
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            access.nodes = [
                AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea",
                               value: "你好", descriptionText: ChatGPTLabels.composerDescription),
                AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXButton",
                               descriptionText: "Send", childCount: 1, childRoles: ["AXImage"])
            ]
        }

        try driver(access, sendButtonTimeout: 1.0).sendText("你好", into: .any)

        XCTAssertEqual(access.pressedElements.map(\.rawID), [2],
                       "Send 按钮是写完文字之后才出现的，必须等它出现再按，不能立刻退回回车")
        XCTAssertEqual(access.returnKeyCount, 0, "等到了按钮就不该再模拟回车")
    }

    // 耗时回归的守门测试（Task 10 遗漏的第三个）。上面那条
    // testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately 的注释里
    // 写着「它同时证明构造函数传进去的 sendButtonTimeout 真被用上了」——**那句话是错的**：
    // 它给的等待窗口是 1.0 秒、按钮 0.02 秒就出现，所以实现把 timeout 写死成 2.0 秒时，
    // 按钮照样等得到，那条断言照样绿。
    //
    // 复审实测：把 AXDriver.sendText 里的 `timeout: sendButtonTimeout` 改回字面量 `2.0`
    //（等价于「注入的参数被彻底无视」），AXDriverTests 37 条仍然全绿，唯一的变化是
    // 本类耗时从 1.1 秒跳到 5.1 秒——正是 Task 10 要根治的那种「只表现为套件变慢、
    // 没人发现」的回归，原样复发。三个注入的节奏值里，另外两个都写了耗时断言
    //（testWaitForAssistantReplySamplesAtTheIntervalItWasGiven /
    // testCopyLatestAssistantMessageWaitsOnlyTheClipboardDelayItWasGiven），
    // 只有这一个漏了。
    //
    // 这里补上同样做法的断言：语音模式的现场（Send 按钮永远不会出现）必须等满
    // sendButtonTimeout 才退回回车，给 0.05 秒就只该等 0.05 秒。写死回 2.0 秒当场变红。
    //
    // 铁律 7：产品默认值 2.0 一个字都没动（由 testDefaultPacingValuesMatchTheMeasuredOnes
    // 钉住），要短超时就在这里显式传参。
    func testSendTextWaitsOnlyTheSendButtonTimeoutItWasGiven() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 没有 Send 按钮——语音模式下的真实现场，等多久都不会出现
        access.onSendReturnKey = { nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }

        let started = Date()
        try driver(access, sendButtonTimeout: 0.05).sendText("考官提示词", into: .any)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(access.returnKeyCount, 1, "等满之后必须真的退回回车，否则这段等待没有意义")
        XCTAssertGreaterThanOrEqual(elapsed, 0.04,
                                    "只等了 \(elapsed) 秒就退回回车——比传入的 0.05 秒还短，"
                                    + "说明根本没等 Send 按钮出现。实测按钮是写完文字之后才出现的，"
                                    + "不等就会在普通聊天状态下走回车，而回车实测发不出去")
        XCTAssertLessThan(elapsed, 0.5,
                          "等 Send 按钮的时长应当用传入的 0.05 秒；实际耗时 \(elapsed) 秒，"
                          + "说明实现里的超时是写死的，测试没法把它调快")
    }

    // 两条路都没能让输入框变空——必须响亮报错，不能静默判定成功（呼应第 2 条修复
    // 强调过的教训：验证要问「到底变没变」，不能只问「现在是不是目标态」）。
    func testSendTextFailsActionablyWhenNeitherButtonNorReturnKeyClearsComposer() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 没有 Send 按钮；onSendReturnKey 保持默认（什么都不做）
        XCTAssertThrowsError(try driver(access).sendText("考官提示词", into: .any)) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
        }
        XCTAssertEqual(access.returnKeyCount, 1, "仍应该尝试过回车这条路")
        XCTAssertTrue(access.pressedElements.isEmpty)
    }

    func testSendTextFailsWhenComposerStillHoldsTheText() {
        let access = FakeAXAccess()
        access.nodes = [composer(1), sendButton(2)]   // 按了 Send，但输入框没被清空 —— 模拟「发送没生效」
        XCTAssertThrowsError(try driver(access).sendText("考官提示词", into: .any)) { error in
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
        XCTAssertThrowsError(try driver(access).sendText("考官提示词", into: .any)) { error in
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
        try driver(access).sendText("你好", into: .any)
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
        XCTAssertThrowsError(try driver(access).sendText("考官提示词", into: .any)) { error in
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
        access.nodes = voiceComposerTree(1)
        let found = try driver(access).waitForVoiceComposer(timeout: 0.5)
        XCTAssertEqual(found.element.rawID, 1)
    }

    // 【发进错误的输入框】的核心场景。**前提在 2026-08-08 被真机 dump 更正过：**
    // 原来以为空对话的输入框叫 "Message ChatGPT"、语音的叫 "Work with ChatGPT"，
    // 靠名字就能分辨。实测这一版 ChatGPT 两种状态下都叫 "Work with ChatGPT"——
    // 于是旧判据在空对话那一屏就成立，根本不等，考官提示词被打进旧对话的输入框。
    // 现在两屏的区别只有同行的按钮（Start new voice chat / Stop voice chat）。
    func testWaitForVoiceComposerKeepsWaitingWhileOnlyNormalComposerIsPresent() throws {
        let access = FakeAXAccess()
        // 空对话那一屏：输入框已经在了（而且和通话中同名），但摆的是 Start new voice chat。
        // 这正是缺陷现场——旧判据只看 description，在这里就会返回，根本不等。
        access.nodes = idleComposerTree(1)
        // 直接构造节点而不是调用 self.voiceComposer(_:)：DispatchQueue.global().asyncAfter
        // 的闭包是 @Sendable 的，捕获 self（非 Sendable 的 XCTestCase 子类）会触发警告；
        // 与本文件另一处 asyncAfter 用例
        // （testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately）写法一致。
        //
        // 已知隐患（本次未改，见报告）：后台改 access.nodes 与 snapshotTree() 内部的
        // 「读—map—写回」不是原子的，后台那次写有极小概率被盖掉，此测试随即空等到超时而假红。
        // 本次跑突变验证时真的撞见过一次。想去掉这个隐患，用新加的 access.onSnapshot
        // 按采样序号摆状态即可（见 FakeAXAccess），但 AXLocatorTests 里还有三处同样的写法，
        // 应当一并处理，不适合在这条复审里顺手改。
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            // 切到通话中那一屏：输入框换了一个（新会话），并且摆上了 Stop voice chat。
            // 描述文字与上一屏**完全相同**——这正是真机的样子，也正是为什么
            // 判据不能靠 description。
            access.nodes = [
                AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXTextArea",
                               descriptionText: ChatGPTLabels.voiceComposerDescription),
                AXNodeSnapshot(element: AXElementRef(rawID: 9001, epoch: 0), role: "AXButton",
                               descriptionText: "Stop voice chat",
                               childCount: 1, childRoles: ["AXImage"]),
            ]
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
        // 逐次采样看到的文本长度。关键在中间三档：**已经超过 minimumLength(60)、
        // 但还在继续变长**——这正是「ChatGPT 还在往外吐字」的样子，也是唯一能把
        // 「等它不再增长」和「一够长就返回」两种实现区分开的状态。
        //
        // 这条测试此前摆的中间态只有 20 字符（够不到门槛），两种实现表现完全一致，
        // 于是把 waitForAssistantReply 的整段稳定判据换成 `if longest >= minimumLength { return }`
        // 也照样全绿——而那正是「回复还没完就进语音 → 考官设定丢失」的故障路径。
        let lengthsPerSample = [0, 72, 96, 150]      // 第 2 次采样起就已经够长，但一直在涨
        let finalLength = 180                        // 第 5 次采样起停止增长
        access.onSnapshot = { sample, nodes in
            let length = sample <= lengthsPerSample.count ? lengthsPerSample[sample - 1] : finalLength
            nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                                    value: String(repeating: "考", count: length))]
        }

        try driver(access).waitForAssistantReply(timeout: 5)

        // 断言采样次数而不是耗时：耗时 =（采样次数 - 1）× 采样间隔，两者等价，
        // 但采样次数不受机器快慢和调度抖动影响，不会在 CI 上时红时绿。
        //
        // 第 5 次采样才第一次看到最终文本，此后还要连续三次采到同样长度才算流式结束，
        // 因此最早只能在第 8 次采样返回。少于 8 次 = 在它还在涨的时候就返回了。
        XCTAssertGreaterThanOrEqual(access.snapshotCount, 8,
                                    "文本已经够长但还在继续变长时就返回了（只采了 \(access.snapshotCount) 次）——"
                                    + "真机上这等于 ChatGPT 还没说完就被判定回复完，"
                                    + "带着残缺的考官设定进语音")
        // 上界防的是反方向：把「连续三次」悄悄改大，每多一次真机上就多等 0.5 秒。
        XCTAssertLessThanOrEqual(access.snapshotCount, 10,
                                 "停止增长后等了 \(access.snapshotCount - 5) 次采样才返回，超过约定的三次；"
                                 + "真机采样间隔 0.5 秒，每多一次就让用户多等半秒")
    }

    // 耗时回归的守门测试（Task 10）：采样间隔必须用构造时传进来的值。
    // 写死 0.5 秒的话，「连续三次不增长」最少要 1.5 秒，光这三条 waitForAssistantReply
    // 测试就要白等 4 秒。这里给 0.01 秒的间隔，正常应在几十毫秒内返回；
    // 把实现改回写死的 0.5 秒，耗时会跳到 1.5 秒以上，这条断言当场变红——
    // 也就是说这个回归下次会被测试抓住，而不是只表现为「套件慢了」。
    func testWaitForAssistantReplySamplesAtTheIntervalItWasGiven() throws {
        let access = FakeAXAccess()
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                           value: String(repeating: "考官反馈内容", count: 10))   // 60 字符，一开始就够长
        ]
        let started = Date()
        try driver(access, replySampleInterval: 0.01).waitForAssistantReply(timeout: 5)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.5,
                          "采样间隔应当用传入的 0.01 秒（三次采样约 0.03 秒）；实际耗时 \(elapsed) 秒，"
                          + "说明实现里的间隔是写死的，测试没法把它调快")
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

    // 同上，守的是「按下复制按钮之后等剪贴板」那一步。写死 0.8 秒时，两条走到这一步的
    // 测试各白等 0.8 秒。传 0.02 秒应当在几十毫秒内返回；改回写死会跳到 0.8 秒以上，变红。
    func testCopyLatestAssistantMessageWaitsOnlyTheClipboardDelayItWasGiven() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Copy")]
        let pasteboard = FakePasteboard(contents: "")
        let review = "<<<IELTS_REVIEW_JSON:sync-2>>>" + String(repeating: "复盘内容", count: 60)
            + "<<<END_IELTS_REVIEW_JSON:sync-2>>>"
        access.onPress = { _, _ in pasteboard.simulateExternalWrite(review) }

        let started = Date()
        let captured = try driver(access, clipboardSettleDelay: 0.02)
            .copyLatestAssistantMessage(pasteboard: pasteboard, timeout: 0.5)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(captured, review)
        XCTAssertLessThan(elapsed, 0.3,
                          "等剪贴板的时长应当用传入的 0.02 秒；实际耗时 \(elapsed) 秒，"
                          + "说明实现里的等待是写死的，测试没法把它调快")
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

    // MARK: - 每一处等待点都得用注入进来的那个值

    /// 一处等待点的探针：跑它最慢的那条路，量实际等了多久。
    private struct PacingProbe {
        /// 出错时报给人看的「是哪一步」。
        let step: String
        /// 这一步真的用上了它该用的那个值时，至少要等这么久。
        /// 低于它 = 压根没等（或者用错了另一个更短的参数）。
        let atLeast: TimeInterval
        /// 这条路是不是「等满超时然后报错」。一并断言，免得探针摆错了现场——
        /// 本该等满超时的那条路要是提前成功返回，下界虽然也会红，但报错指不到病根。
        let expectsFailure: Bool
        let run: () throws -> Void
    }

    /// 上面三条耗时断言各守一个参数的**一个**调用点。但同一类缺陷不止能从
    /// `sendButtonTimeout` 溜过去——修问题 15 时我把另外两个注入值也各写死了一遍，结果一样：
    ///
    /// - `timeout: shortTimeout` 五处全换成字面量 `5.0`：37 条全绿，本类耗时 1.2 秒 → 30.9 秒。
    /// - `timeout: stateTimeout` 两处全换成字面量 `25.0`：37 条全绿，本类耗时 1.2 秒 → 26.2 秒。
    ///
    /// 也就是说 AXDriver 里**每一个**等待点都能被写死回去而不掉一根头发，只表现为套件变慢。
    /// 而「一个参数补一条耗时断言」仍然守不住：光 `shortTimeout` 就有五个调用点，
    /// 只守其中一个，另外四个照样溜。
    ///
    /// 所以这条测试按**调用点**扫：每一处会真的等待的地方各跑一遍它最慢的那条路，各给上下界。
    ///
    /// - 下界 `atLeast`：这一步确实等到了它该等的那个值。
    /// - 上界 `atMost`（0.5 秒）：产品里那些实测定下来的字面量——2.0（等 Send 按钮）、
    ///   5.0（shortTimeout）、25.0（stateTimeout）、0.5 × 3（采样间隔连等三次）、
    ///   0.8（等剪贴板）——全都在这条线之上。任何一处被写死回去，那一步当场超时变红，
    ///   而且错误信息直接点名是哪一步。
    ///
    /// 顺带守住了「以后新加的节奏值又被写成字面量」：新的等待只要落在这些公开方法里，
    /// 而按实测定下来的等待值不可能小于半秒，照样顶穿上界。
    ///
    /// **为什么没用 `Tests/IELTSCoachUITests/Support/SourceGuard.swift`**（派单要求先读它）：
    /// 读了。它是扫源码的守门员，装在 IELTSCoachUITests 那个 target 里，本 target 看不见它；
    /// 更要紧的是扫源码只能证明「源码里没写字面量」，证明不了「注入的这个值真的被读到了」。
    /// 这里能直接量时间，量出来的证据比扫出来的强，所以没有跨 target 去搬它。
    ///
    /// **它拦不住什么**：`shortTimeout` 被误写成 `stateTimeout` 这种张冠李戴——两个都是注入值，
    /// 都会跟着变短。那类问题归各方法自己的行为测试。
    func testEveryWaitingPathHonorsTheInjectedPacingValues() {
        // 五个注入值各给一个短值，且**故意不全相同**：下界报错时能一眼看出是哪一个没被用上。
        let short: TimeInterval = 0.02
        let state: TimeInterval = 0.06
        let sendButtonWait: TimeInterval = 0.06
        let sample: TimeInterval = 0.02
        let clipboard: TimeInterval = 0.04
        // 由调用方逐次传入的超时（waitForVoiceComposer / copyLatestAssistantMessage 的形参），
        // 和上面五个注入值是同一类东西：写死了同样没人管。
        let callerGiven: TimeInterval = 0.06
        // 产品里最小的那个实测字面量是 0.5 秒（采样间隔，而且要连等三次 = 1.5 秒）。
        // 上界压在 0.5，任何一个字面量都顶得穿；而各步真实耗时都在 0.07 秒以内，留了七倍余量。
        let atMost: TimeInterval = 0.5

        func sut(_ access: FakeAXAccess) -> AXDriver {
            AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                     shortTimeout: short, stateTimeout: state,
                     sendButtonTimeout: sendButtonWait, replySampleInterval: sample,
                     clipboardSettleDelay: clipboard)
        }
        let clearComposerOnReturn: (inout [AXNodeSnapshot]) -> Void = { nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        let review = "<<<IELTS_REVIEW_JSON:sync-sweep>>>" + String(repeating: "复盘内容", count: 60)
            + "<<<END_IELTS_REVIEW_JSON:sync-sweep>>>"

        // 每个探针一套独立的假环境：共用一个会让前一步留下的 press/snapshot 记录串味。
        let composerWithoutSendButton = FakeAXAccess()
        composerWithoutSendButton.nodes = [composer(1)]
        composerWithoutSendButton.onSendReturnKey = clearComposerOnReturn

        let emptyTreeForSendText = FakeAXAccess()
        let composerThatNeverClears = FakeAXAccess()
        composerThatNeverClears.nodes = [composer(1), sendButton(2)]   // 按了 Send，界面纹丝不动

        let emptyTreeForNewChat = FakeAXAccess()
        let emptyTreeForStartVoice = FakeAXAccess()

        let voiceNeverStarts = FakeAXAccess()
        voiceNeverStarts.nodes = [control(1, "Start voice chat")]      // onPress 为 nil：按了但没起来

        let voiceRunningWithoutStopButton = FakeAXAccess()
        voiceRunningWithoutStopButton.nodes = [voiceActive(9)]

        let voiceNeverEnds = FakeAXAccess()
        voiceNeverEnds.nodes = [control(1, "Stop voice chat"), voiceActive(9)]

        let onlyNormalComposer = FakeAXAccess()
        onlyNormalComposer.nodes = [composer(1)]                       // 语音输入框始终不出现

        let stableReply = FakeAXAccess()
        stableReply.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXStaticText",
                           value: String(repeating: "考官反馈内容", count: 10))   // 一开始就够长且不再增长
        ]

        let noCopyButton = FakeAXAccess()
        let copyButtonThatWrites = FakeAXAccess()
        copyButtonThatWrites.nodes = [control(1, "Copy")]
        let sweepPasteboard = FakePasteboard(contents: "")
        copyButtonThatWrites.onPress = { _, _ in sweepPasteboard.simulateExternalWrite(review) }

        let probes: [PacingProbe] = [
            PacingProbe(step: "sendText 等 Send 按钮出现（sendButtonTimeout）",
                        atLeast: sendButtonWait * 0.8, expectsFailure: false) {
                try sut(composerWithoutSendButton).sendText("考官提示词", into: .any)
            },
            PacingProbe(step: "sendText 找 ChatGPT 输入框（shortTimeout）",
                        atLeast: short * 0.8, expectsFailure: true) {
                try sut(emptyTreeForSendText).sendText("考官提示词", into: .any)
            },
            PacingProbe(step: "sendText 验证输入框回到空态（shortTimeout）",
                        atLeast: short * 0.8, expectsFailure: true) {
                try sut(composerThatNeverClears).sendText("考官提示词", into: .any)
            },
            PacingProbe(step: "startNewChat 找「新建会话」按钮（shortTimeout）",
                        atLeast: short * 0.8, expectsFailure: true) {
                try sut(emptyTreeForNewChat).startNewChat()
            },
            PacingProbe(step: "startVoice 找语音按钮（shortTimeout）",
                        atLeast: short * 0.8, expectsFailure: true) {
                try sut(emptyTreeForStartVoice).startVoice()
            },
            PacingProbe(step: "startVoice 等语音真的起来（stateTimeout）",
                        atLeast: state * 0.8, expectsFailure: true) {
                try sut(voiceNeverStarts).startVoice()
            },
            PacingProbe(step: "endVoice 找结束语音按钮（shortTimeout）",
                        atLeast: short * 0.8, expectsFailure: true) {
                try sut(voiceRunningWithoutStopButton).endVoice()
            },
            PacingProbe(step: "endVoice 等语音真的结束（stateTimeout）",
                        atLeast: state * 0.8, expectsFailure: true) {
                try sut(voiceNeverEnds).endVoice()
            },
            PacingProbe(step: "waitForVoiceComposer 用调用方传进来的超时",
                        atLeast: callerGiven * 0.8, expectsFailure: true) {
                try sut(onlyNormalComposer).waitForVoiceComposer(timeout: callerGiven)
            },
            // 连等三次不增长才算流式结束，所以至少要睡三个采样间隔。
            PacingProbe(step: "waitForAssistantReply 两次采样之间的间隔（replySampleInterval）",
                        atLeast: sample * 2.5, expectsFailure: false) {
                try sut(stableReply).waitForAssistantReply(timeout: 5)
            },
            PacingProbe(step: "copyLatestAssistantMessage 找复制按钮，用调用方传进来的超时",
                        atLeast: callerGiven * 0.8, expectsFailure: true) {
                _ = try sut(noCopyButton)
                    .copyLatestAssistantMessage(pasteboard: FakePasteboard(contents: ""),
                                                timeout: callerGiven)
            },
            PacingProbe(step: "copyLatestAssistantMessage 按下之后等剪贴板（clipboardSettleDelay）",
                        atLeast: clipboard * 0.8, expectsFailure: false) {
                let captured = try sut(copyButtonThatWrites)
                    .copyLatestAssistantMessage(pasteboard: sweepPasteboard, timeout: 0.5)
                XCTAssertEqual(captured, review, "等够了就该把复盘原样取回来")
            }
        ]

        for probe in probes {
            let started = Date()
            var thrown: Error?
            do { try probe.run() } catch { thrown = error }
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertEqual(thrown != nil, probe.expectsFailure,
                           "「\(probe.step)」这一步摆的现场不对："
                           + (probe.expectsFailure
                              ? "本该等满超时后报错，却成功返回了"
                              : "本该走通，却抛了 \(String(describing: thrown))"))
            XCTAssertGreaterThanOrEqual(elapsed, probe.atLeast,
                                        "「\(probe.step)」只用了 \(elapsed) 秒，"
                                        + "比它该等的 \(probe.atLeast) 秒还短——这一步没有真的等，"
                                        + "或者用错了别的参数。真机上这等于「按完就假设下一个元素已就位」，"
                                        + "会随机失败（spec 2.3.2）")
            XCTAssertLessThan(elapsed, atMost,
                              "「\(probe.step)」等了 \(elapsed) 秒，远超注入的短值——"
                              + "说明这一处的等待时长是写死的字面量，注入的参数被无视了。"
                              + "产品默认值必须原样保留（铁律 7），要短超时就在测试里显式传参；"
                              + "写死回去的后果是这套测试只会变慢，没人发现（Task 10 的耗时回归）")
        }
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
