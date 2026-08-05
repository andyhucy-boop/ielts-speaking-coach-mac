import XCTest
@testable import ChatGPTBridge

final class AXLocatorTests: XCTestCase {
    // brief 里写的是 `AXElementRef(rawID: id)`，但 epoch 已在上一提交（004c9d0）里
    // 变成无默认值的必填参数，字面照抄编译不过。这里传 epoch: 0 —— 具体值不重要，
    // 因为 FakeAXAccess.snapshotTree() 每次调用都会用当前代次盖印 nodes 里所有元素，
    // 传入的字面量只是占位。
    private static func control(_ id: Int, _ desc: String) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: "AXButton",
                       descriptionText: desc, childCount: 1, childRoles: ["AXImage"])
    }

    func testFindsControlAlreadyPresent() throws {
        let access = FakeAXAccess()
        access.nodes = [Self.control(1, "Stop voice chat")]
        let locator = AXLocator(access: access, pollInterval: 0.01)
        let result = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.5)
        // 同样因为 epoch 必填：返回的引用来自最后一次快照，其代次就是 access.snapshotCount。
        XCTAssertEqual(result.element, AXElementRef(rawID: 1, epoch: access.snapshotCount))
    }

    func testWaitsForControlThatAppearsLate() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        // 第 3 次快照时元素才出现，模拟语音浮层渲染延迟
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [Self.control(2, "Stop voice chat")]
        }
        let result = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 2.0)
        XCTAssertEqual(result.element, AXElementRef(rawID: 2, epoch: access.snapshotCount))
    }

    func testTimeoutErrorIsChineseAndActionable() {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.1)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("下一步"), "超时错误缺少下一步指引：\(message)")
            XCTAssertTrue(message.contains("Stop voice chat"), "错误信息应指明找的是什么：\(message)")
        }
    }

    func testTimeoutReportsStructuralMismatchesWhenLabelMatched() {
        let access = FakeAXAccess()
        // 标签对上了但结构不符——这正是「点中侧边栏同名会话」那个 bug 的现场
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 3, epoch: 0), role: "AXButton",
                                       descriptionText: "New voice chat",
                                       childCount: 3, childRoles: ["AXGroup", "AXButton", "AXButton"])]
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForControl(ChatGPTLabels.startVoice, timeout: 0.1)) { error in
            XCTAssertTrue("\(error)".contains("结构不符"),
                          "标签命中但结构不符时，错误信息必须说清楚，否则用户完全看不出问题在哪：\(error)")
        }
    }

    func testWaitUntilPollsUntilConditionHolds() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 4, epoch: 0), role: "AXImage",
                                           descriptionText: ChatGPTLabels.voiceActiveIndicator)]
        }
        try locator.waitUntil({ ChatGPTLabels.isVoiceActive($0) }, timeout: 2.0,
                              describing: "语音开始")
    }

    func testPollsRepeatedlyRatherThanSnapshottingOnce() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        _ = try? locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.1)
        XCTAssertGreaterThan(access.snapshotCount, 2,
                             "必须反复取快照，只取一次就等于没有等待重试")
    }

    func testComposerTimeoutDistinguishesAmbiguityFromAbsence() {
        let access = FakeAXAccess()
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea",
                           descriptionText: "Search"),
            AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXTextArea",
                           descriptionText: "Rename chat")
        ]
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForComposer(timeout: 0.1)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("2 个文本框"), "应说清有几个候选：\(message)")
            XCTAssertTrue(message.contains("Search"), "应列出候选的描述，否则用户无从判断：\(message)")
            XCTAssertTrue(message.contains("下一步"))
        }
    }

    // waitForNode 是给 AXDriver.waitForVoiceComposer 用的通用轮询原语——
    // 与 waitForControl/waitForComposer 的区别是它接受任意匹配函数，且找不到时
    // 返回 nil 而不是抛错（错误信息由调用方根据场景自己拼，见 AXDriverTests）。

    func testWaitForNodeKeepsPollingUntilPredicateMatches() throws {
        let access = FakeAXAccess()
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea",
                                       descriptionText: "Message ChatGPT")]
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXTextArea",
                                           descriptionText: "Work with ChatGPT")]
        }
        let locator = AXLocator(access: access, pollInterval: 0.01)
        let found = locator.waitForNode(matching: { nodes in
            nodes.first { $0.descriptionText == "Work with ChatGPT" }
        }, timeout: 1.0)
        XCTAssertEqual(found?.element.rawID, 2,
                       "谓词命中「Message ChatGPT」时不能提前返回，必须等到目标节点出现")
    }

    func testWaitForNodeReturnsNilOnTimeout() {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        let found = locator.waitForNode(matching: { $0.first }, timeout: 0.1)
        XCTAssertNil(found)
    }

    func testComposerTimeoutWhenNoTextAreaAtAll() {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForComposer(timeout: 0.1)) { error in
            let message = "\(error)"
            XCTAssertFalse(message.contains("个文本框（"), "没有候选时不该报歧义错误：\(message)")
            XCTAssertTrue(message.contains("下一步"))
        }
    }
}
