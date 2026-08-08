import XCTest

@testable import ChatGPTBridge

/// 守住 2026-08-08 真机 dump 得出的结论：**输入框的 description 区分不了语音状态。**
///
/// 两份 AX dump 对比（空对话 677 节点 / 通话中 1048 节点）：
///
/// | | 空对话 | 通话中 |
/// |---|---|---|
/// | 输入框 desc | `Work with ChatGPT` | `Work with ChatGPT` |
/// | 同行按钮 | `Dictate`、`Start new voice chat` | `Mute speakers`、`Mute microphone`、`Stop voice chat` |
///
/// 此前的判据是「desc == Work with ChatGPT」，它在空对话里就成立，
/// 于是 `waitForVoiceComposer` 立刻返回、根本不等，考官提示词被打进旧对话的输入框。
/// 用户报的两句话——「压根就没有等到语音对话中提示框出现的那一刻」
/// 与「又另外创建了一个文字对话」——是同一个根因的两个侧面。
final class VoiceComposerDetectionTests: XCTestCase {

    /// 空对话那一屏（按真实 dump 的结构造）。
    private func idleTree() -> [AXNodeSnapshot] {
        [
            node(role: "AXTextArea", desc: "Work with ChatGPT"),
            iconButton(desc: "Dictate"),
            iconButton(desc: "Start new voice chat"),
        ]
    }

    /// 通话中那一屏。
    private func voiceTree() -> [AXNodeSnapshot] {
        [
            node(role: "AXTextArea", desc: "Work with ChatGPT"),
            iconButton(desc: "Mute speakers"),
            iconButton(desc: "Mute microphone"),
            iconButton(desc: "Stop voice chat"),
        ]
    }

    func testAnIdleChatIsNotMistakenForAVoiceCall() {
        XCTAssertFalse(ChatGPTLabels.isInVoiceCall(idleTree()),
                       "空对话被当成了通话中——这正是那个缺陷：判据一成立就不等了")
        XCTAssertNil(ChatGPTLabels.voiceComposer(among: idleTree()),
                     "空对话里不该找得到「语音输入框」。找得到的话，考官提示词会被"
                     + "打进旧对话的框，而语音那边一个字都收不到")
    }

    func testAnActiveVoiceCallIsRecognisedAndItsComposerFound() {
        XCTAssertTrue(ChatGPTLabels.isInVoiceCall(voiceTree()))
        XCTAssertNotNil(ChatGPTLabels.voiceComposer(among: voiceTree()),
                        "通话中却找不到输入框——那会一直等到超时，练习起不来")
    }

    /// 两种状态的输入框 description **相同**。这条把真机事实钉进测试里：
    /// 哪天有人想「用 desc 判断状态不是更简单吗」，这条会告诉他为什么不行。
    func testTheComposerDescriptionIsIdenticalInBothStatesSoItCannotDiscriminate() {
        let idle = ChatGPTLabels.composer(among: idleTree())?.descriptionText
        let voice = ChatGPTLabels.composer(among: voiceTree())?.descriptionText
        XCTAssertEqual(idle, voice,
                       "真机实测这一版 ChatGPT 两种状态的输入框同名。"
                       + "若哪天它们真的不同了，可以简化判据——但要先有新的 dump 为证。")
    }

    // MARK: - 造节点

    private func node(role: String, desc: String, children: [String] = []) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: abs(desc.hashValue % 10_000), epoch: 0),
                       role: role, descriptionText: desc, childRoles: children)
    }

    /// 只有一个 AXImage 子节点的控制按钮——`matchControl` 的结构判据要求这个形状。
    private func iconButton(desc: String) -> AXNodeSnapshot {
        node(role: "AXButton", desc: desc, children: ["AXImage"])
    }
}
