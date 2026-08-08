import XCTest
@testable import ChatGPTBridge

final class AXElementRefEpochTests: XCTestCase {
    func testPressRejectsElementFromStaleSnapshot() {
        let access = FakeAXAccess()
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 0, epoch: 0), role: "AXButton",
                                       descriptionText: "Stop voice chat",
                                       childCount: 1, childRoles: ["AXImage"])]
        let stale = access.snapshotTree()[0].element
        _ = access.snapshotTree()   // 开启新代次，旧引用应当失效
        XCTAssertFalse(access.press(stale),
                       "过期代次的引用必须被拒绝，否则会静默命中新树里同编号的另一个元素")
        XCTAssertTrue(access.pressedElements.isEmpty, "被拒绝的引用一次都不能真的按下去")
    }
}
