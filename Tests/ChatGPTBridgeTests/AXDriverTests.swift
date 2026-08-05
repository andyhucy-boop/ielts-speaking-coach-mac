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
    private func voiceActive(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXImage",
                       descriptionText: ChatGPTLabels.voiceActiveIndicator)
    }
    // 修复轮第 4 条（我在上一轮报告里提出的疑虑）：brief 原版 helper 没有覆盖默认的
    // shortTimeout(5.0)/stateTimeout(8.0)，导致「预期失败」的测试要真的等到超时才
    // 拿到结果。这里显式传短超时，让整个测试类的耗时从约 13 秒降到 1 秒以内。
    private func driver(_ access: FakeAXAccess) -> AXDriver {
        AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                 shortTimeout: 0.2, stateTimeout: 0.2)
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

    func testSendTextWritesComposerThenPressesReturn() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]
        // 修复轮加了「发送后验证输入框真的变了」，FakeAXAccess.setValue 现在会把文字
        // 真的写进节点；这里显式模拟「ChatGPT 收到后清空了输入框」，否则 sendText 会
        // 因为 composer 仍然等于刚写入的文字而误判成「回车没生效」。
        access.onSendReturnKey = { nodes in
            for i in nodes.indices where nodes[i].role == "AXTextArea" { nodes[i].value = "" }
        }
        try driver(access).sendText("你好")
        XCTAssertEqual(access.setValues.count, 1)
        XCTAssertEqual(access.setValues[0].1, "你好")
        XCTAssertEqual(access.returnKeyCount, 1, "写入之后必须真的发送")
    }

    func testSendTextFailsWhenComposerStillHoldsTheText() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]   // 输入框内容不会变 —— 模拟「回车没生效」
        XCTAssertThrowsError(try driver(access).sendText("考官提示词")) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
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
