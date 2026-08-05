import XCTest
@testable import ChatGPTBridge

final class ChatGPTLabelsTests: XCTestCase {
    private func node(_ id: Int, role: String, desc: String, childRoles: [String]) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: role, descriptionText: desc,
                       childCount: childRoles.count, childRoles: childRoles)
    }

    func testMatchesIconOnlyStartVoiceButton() {
        let button = node(1, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [button])?.element,
                       AXElementRef(rawID: 1))
    }

    func testRejectsSidebarRowWithSameLabel() {
        // 侧边栏会话行：标签命中但结构不符（嵌套按钮而非单个图标）
        let row = node(2, role: "AXButton", desc: "New voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        XCTAssertNil(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row]),
                     "侧边栏同名会话行不得被当成控制按钮")
    }

    func testPrefersControlButtonWhenSidebarRowComesFirst() {
        // 深度优先遍历里侧边栏常常排在前面 —— 不能取第一个命中
        let row = node(2, role: "AXButton", desc: "New voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        let button = node(3, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row, button])?.element,
                       AXElementRef(rawID: 3))
    }

    func testAcceptsCheckBoxControls() {
        // 静音类控件是 AXCheckBox subrole=AXToggleButton，同样单个 AXImage 子节点
        let mute = node(4, role: "AXCheckBox", desc: "Mute microphone", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(["Mute microphone"], among: [mute])?.element,
                       AXElementRef(rawID: 4))
    }

    func testStartVoiceCandidatesCoverAllObservedLabels() {
        // 实测在同一台机器上先后出现过这三种，缺一会导致启动语音失败
        for observed in ["Start voice chat", "Start new voice chat", "New voice chat"] {
            XCTAssertTrue(ChatGPTLabels.startVoice.contains(observed), "候选集合缺少实测标签：\(observed)")
        }
    }
}
