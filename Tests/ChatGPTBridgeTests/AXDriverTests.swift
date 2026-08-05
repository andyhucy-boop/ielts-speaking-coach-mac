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
    private func driver(_ access: FakeAXAccess) -> AXDriver {
        AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01))
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
        try driver(access).sendText("你好")
        XCTAssertEqual(access.setValues.count, 1)
        XCTAssertEqual(access.setValues[0].1, "你好")
        XCTAssertEqual(access.returnKeyCount, 1, "写入之后必须真的发送")
    }

    func testStartVoiceVerifiesIndicatorAppeared() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat")]
        access.onPress = { _, nodes in nodes.append(self.voiceActive(9)) }
        try driver(access).startVoice()
        // brief 原文断言 `[AXElementRef(rawID: 1)]`，同样缺 epoch。
        // waitForControl 在第一次 snapshotTree() 就命中，此时代次为 1；随后 waitUntil
        // 里的验证轮询还会继续调用 snapshotTree()（代次递增），但那不影响已经记录下来的
        // pressedElements——它是按下那一刻的代次快照，是 1，不是断言时的 access.snapshotCount。
        XCTAssertEqual(access.pressedElements, [AXElementRef(rawID: 1, epoch: 1)])
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
}

final class ClipboardFallbackTests: XCTestCase {
    func testReadsPlainTextFromPasteboard() throws {
        let pasteboard = FakePasteboard(contents: "  <<<IELTS_REVIEW_JSON>>>x<<<END_IELTS_REVIEW_JSON>>>  ")
        XCTAssertEqual(try ClipboardFallback.readReview(from: pasteboard),
                       "<<<IELTS_REVIEW_JSON>>>x<<<END_IELTS_REVIEW_JSON>>>")
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
}
