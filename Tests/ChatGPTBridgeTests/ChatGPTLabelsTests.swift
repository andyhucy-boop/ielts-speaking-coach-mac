import XCTest
@testable import ChatGPTBridge

final class ChatGPTLabelsTests: XCTestCase {
    private func node(_ id: Int, role: String, desc: String, childRoles: [String]) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id, epoch: 0), role: role, descriptionText: desc,
                       childCount: childRoles.count, childRoles: childRoles)
    }

    func testMatchesIconOnlyStartVoiceButton() {
        let button = node(1, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [button])?.element,
                       AXElementRef(rawID: 1, epoch: 0))
    }

    func testRejectsSidebarRowWithSameLabel() {
        // 侧边栏会话行：标签命中但结构不符（嵌套按钮而非单个图标）
        let row = node(2, role: "AXButton", desc: "New voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        XCTAssertNil(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row]),
                     "侧边栏同名会话行不得被当成控制按钮")
    }

    func testPrefersControlButtonWhenSidebarRowComesFirst() {
        // ⚠️ 两者标签必须**相同**，否则这条测试是装饰性的：
        // matchControl 按候选集合顺序查找，标签不同时靠优先级就能选对，
        // 结构判据根本不会被执行，删掉它这条测试照样绿。
        // 标签相同时，唯一的区分依据才是结构。
        let row = node(2, role: "AXButton", desc: "Start voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        let button = node(3, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row, button])?.element,
                       AXElementRef(rawID: 3, epoch: 0),
                       "侧边栏行排在前面时仍必须选中结构合法的那个")
    }

    func testAcceptsCheckBoxControls() {
        // 静音类控件是 AXCheckBox subrole=AXToggleButton，同样单个 AXImage 子节点
        let mute = node(4, role: "AXCheckBox", desc: "Mute microphone", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(["Mute microphone"], among: [mute])?.element,
                       AXElementRef(rawID: 4, epoch: 0))
    }

    func testStartVoiceCandidatesCoverAllObservedLabels() {
        // 实测在同一台机器上先后出现过这三种，缺一会导致启动语音失败
        for observed in ["Start voice chat", "Start new voice chat", "New voice chat"] {
            XCTAssertTrue(ChatGPTLabels.startVoice.contains(observed), "候选集合缺少实测标签：\(observed)")
        }
    }

    func testComposerUsesTheOnlyTextAreaWhenDescriptionDoesNotMatch() {
        // 只有一个文本框 → 无歧义，可以用
        let onlyOne = AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0),
                                     role: "AXTextArea", descriptionText: "改版后的新描述")
        XCTAssertEqual(ChatGPTLabels.composer(among: [onlyOne])?.element,
                       AXElementRef(rawID: 1, epoch: 0))
    }

    func testComposerRefusesToGuessAmongMultipleTextAreas() {
        // 两个以上 → 必须失败，不能闭眼取第一个
        let search = AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0),
                                    role: "AXTextArea", descriptionText: "Search")
        let rename = AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0),
                                    role: "AXTextArea", descriptionText: "Rename chat")
        XCTAssertNil(ChatGPTLabels.composer(among: [search, rename]),
                     "有多个文本框时猜错的后果是把考官提示词写进搜索框，且用户毫无线索")
        XCTAssertEqual(ChatGPTLabels.candidateComposers(among: [search, rename]).count, 2)
    }

    func testStructuralMismatchesReportsWrongRoleWithIconOnlyChild() {
        // label 命中、只有一个 AXImage 子节点、但 role 不是控制类 —— 必须被报告
        let odd = AXNodeSnapshot(element: AXElementRef(rawID: 9, epoch: 0), role: "AXGroup",
                                 descriptionText: "Start voice chat",
                                 childCount: 1, childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.structuralMismatches(ChatGPTLabels.startVoice, among: [odd]).count, 1,
                       "role 不符的元素也该进诊断，否则排查时看到的情况比实际更干净")
    }
}
