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

    func testMatchesIconOnlySendButton() {
        // 实测发送按钮结构：AXButton desc="Send"，唯一子节点 AXImage
        let button = node(5, role: "AXButton", desc: "Send", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.sendMessage, among: [button])?.element,
                       AXElementRef(rawID: 5, epoch: 0))
    }

    func testSendMessageCandidatesCoverAllObservedLabels() {
        for observed in ["Send", "发送"] {
            XCTAssertTrue(ChatGPTLabels.sendMessage.contains(observed), "候选集合缺少标签：\(observed)")
        }
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

    func testComposerDescriptionsCoverBothObservedStates() {
        // 实测输入框 description 随状态而变：普通聊天是 "Message ChatGPT"，
        // 语音会话进行中是 "Work with ChatGPT"。发提示词时是前者，此前代码只认后者。
        for observed in ["Message ChatGPT", "Work with ChatGPT"] {
            XCTAssertTrue(ChatGPTLabels.composerDescriptions.contains(observed), "候选集合缺少实测标签：\(observed)")
        }
    }

    func testComposerMatchesEitherObservedDescriptionEvenWithOtherTextAreasPresent() {
        // 界面上还有别的文本框时，精确匹配分支必须能命中两种候选描述中的任意一种——
        // 不能靠「只有一个 AXTextArea」的兜底才蒙对。
        for desc in ChatGPTLabels.composerDescriptions {
            let target = AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0),
                                        role: "AXTextArea", descriptionText: desc)
            let other = AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0),
                                       role: "AXTextArea", descriptionText: "Search")
            XCTAssertEqual(ChatGPTLabels.composer(among: [target, other])?.element,
                           AXElementRef(rawID: 1, epoch: 0),
                           "候选描述「\(desc)」应命中精确匹配分支")
        }
    }

    // voiceComposer(among:) 是【发进错误的输入框】那条修复的核心判据：实测第 9~11 秒
    // **这条测试的前提在 2026-08-08 被真机 dump 更正过。**
    //
    // 原来写的是「必须精确匹配语音态描述」，前提是两种状态的输入框叫不同的名字。
    // 实测这一版 ChatGPT **两种状态下都叫 `Work with ChatGPT`**，那个判据在空对话里
    // 就成立——`waitForVoiceComposer` 立刻返回、根本不等，考官提示词被打进旧对话的框。
    // 用户报的「压根就没有等到语音对话中提示框出现的那一刻」就是它。
    //
    // 现在的判据是同一行上的通话控制按钮。
    func testVoiceComposerNeedsTheCallControlsNotJustTheDescription() {
        let composer = AXNodeSnapshot(element: AXElementRef(rawID: 2, epoch: 0), role: "AXTextArea",
                                      descriptionText: ChatGPTLabels.voiceComposerDescription)
        let startVoice = AXNodeSnapshot(element: AXElementRef(rawID: 3, epoch: 0), role: "AXButton",
                                        descriptionText: "Start new voice chat",
                                        childCount: 1, childRoles: ["AXImage"])
        let stopVoice = AXNodeSnapshot(element: AXElementRef(rawID: 4, epoch: 0), role: "AXButton",
                                       descriptionText: "Stop voice chat",
                                       childCount: 1, childRoles: ["AXImage"])

        XCTAssertNil(ChatGPTLabels.voiceComposer(among: [composer, startVoice]),
                     "空对话那一屏：输入框名字虽然一样，但摆的是 Start new voice chat，"
                     + "不能当成语音输入框——认了就等于不等，提示词会发进旧对话")
        XCTAssertEqual(ChatGPTLabels.voiceComposer(among: [composer, stopVoice])?.element,
                       AXElementRef(rawID: 2, epoch: 0),
                       "通话中那一屏：摆的是 Stop voice chat，这时才是真的语音输入框")
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

    func testNewChatCandidatesCoverAllObservedLabels() {
        for observed in ["New chat", "新建对话"] {
            XCTAssertTrue(ChatGPTLabels.newChat.contains(observed), "候选集合缺少标签：\(observed)")
        }
    }

    func testMatchesIconOnlyNewChatButton() {
        // 实测新建会话按钮结构：AXButton desc="New chat"，唯一子节点 AXImage
        // （spec 2.3.5：Live 语音只能在未发送过消息的会话里启动，所以每次练习前都要按它）。
        let button = node(6, role: "AXButton", desc: "New chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.newChat, among: [button])?.element,
                       AXElementRef(rawID: 6, epoch: 0))
    }

    func testCopyAssistantMessageCandidatesCoverAllObservedLabels() {
        for observed in ["Copy", "复制"] {
            XCTAssertTrue(ChatGPTLabels.copyAssistantMessage.contains(observed), "候选集合缺少标签：\(observed)")
        }
    }

    // 核心场景（派单点名要求）：界面上每条助手消息下方都有一个复制按钮，取第一个
    // 会复制到最早那条回复，必须取最后一个。matchControl 返回第一个匹配，不能直接复用。
    //
    // 突变验证：把下面这行的 matchLastControl 换成 matchControl（等价于把实现里的
    // nodes.last(where:) 换回 nodes.first(where:)），这条测试会红——
    // XCTAssertEqual failed: ("1") is not equal to ("3")。
    func testMatchLastControlReturnsLastAmongMultipleAssistantCopyButtons() {
        let first = node(1, role: "AXButton", desc: "Copy", childRoles: ["AXImage"])
        let second = node(2, role: "AXButton", desc: "Copy", childRoles: ["AXImage"])
        let third = node(3, role: "AXButton", desc: "Copy", childRoles: ["AXImage"])
        XCTAssertEqual(
            ChatGPTLabels.matchLastControl(ChatGPTLabels.copyAssistantMessage,
                                           among: [first, second, third])?.element,
            AXElementRef(rawID: 3, epoch: 0),
            "界面上每条助手消息下方都有一个复制按钮，必须取最后一个（最新一条）；"
            + "取第一个会把复盘复制到最早那条回复")
    }

    // 两个复制按钮必须靠标签精确区分：用户自己那条消息的复制按钮标签是 "Copy message"
    // （挨着 Edit message），ChatGPT 回复下方的复制按钮标签是 "Copy"（挨着 Good response）。
    // 结构完全相同（单个 AXImage 子节点的 AXButton），只能靠标签区分。
    func testMatchLastControlDoesNotConfuseUserCopyMessageWithAssistantCopy() {
        let userCopy = node(1, role: "AXButton", desc: "Copy message", childRoles: ["AXImage"])
        let assistantCopy = node(2, role: "AXButton", desc: "Copy", childRoles: ["AXImage"])
        XCTAssertEqual(
            ChatGPTLabels.matchLastControl(ChatGPTLabels.copyAssistantMessage,
                                           among: [userCopy, assistantCopy])?.element,
            AXElementRef(rawID: 2, epoch: 0),
            "不能把用户自己消息的 Copy message 按钮当成 ChatGPT 回复的 Copy 按钮")
    }

    func testMatchLastControlRejectsStructuralMismatch() {
        // 与 matchControl 对称：结构不符（非单个 AXImage 子节点）的同名元素不得被选中。
        let row = node(2, role: "AXButton", desc: "Copy",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        XCTAssertNil(ChatGPTLabels.matchLastControl(ChatGPTLabels.copyAssistantMessage, among: [row]))
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
