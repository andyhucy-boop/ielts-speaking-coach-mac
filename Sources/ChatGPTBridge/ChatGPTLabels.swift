import Foundation
import IELTSCoachCore

/// ChatGPT.app 的界面特征。**ChatGPT 改版时只改这个文件。**
/// 别处不得硬编码任何界面标签。
public enum ChatGPTLabels {
    /// 启动语音。实测在同一台机器上先后出现过三种标签，全部保留。
    public static let startVoice = ["Start voice chat", "Start new voice chat", "New voice chat"]
    public static let stopVoice = ["Stop voice chat"]
    /// 语音进行中的标志。实测为会话级常驻，静默不消失（spec 2.3.3）。
    public static let voiceActiveIndicator = "Voice chat active"
    /// 输入框的 description。
    ///
    /// **⚠️ 别再拿它区分「普通聊天」和「语音通话」——2026-08-08 实测这一版
    /// ChatGPT 两种状态下都叫 `Work with ChatGPT`。** 要判断状态请用
    /// `isInVoiceCall(_:)`（看的是同行的通话控制按钮）。
    ///
    /// 两个取值都保留：`Message ChatGPT` 是更早的版本用的，用户机器上的版本
    /// 未必一致，多认一个不会错——但**它们不再承担区分状态的职责**。
    public static let normalComposerDescription = "Message ChatGPT"
    public static let voiceComposerDescription = "Work with ChatGPT"
    /// 两者合集，供通用查找使用。
    public static let composerDescriptions = [normalComposerDescription, voiceComposerDescription]
    /// 别名，兼容旧的单数写法。发提示词时界面处于 `composerDescriptions[0]` 那个状态。
    public static let composerDescription = composerDescriptions[0]
    /// 发送按钮。实测模拟回车不会发送（文字留在输入框里），必须按这个按钮。
    public static let sendMessage = ["Send", "发送"]

    /// 新建会话。**每次练习都要先按它** —— Live 语音只能在还没发送过任何消息的
    /// 会话里启动，而这一点从 AX 树上看不出来，是用户实际使用时发现的。
    /// 旧会话仍保留在侧边栏，不丢数据。
    public static let newChat = ["New chat", "新建对话"]

    /// ChatGPT 回复下方的复制按钮。
    /// **不要写成 "Copy message"** —— 那是用户自己那条消息的复制按钮（挨着 Edit message），
    /// 复制的是提示词而不是复盘。两者结构相同，只能靠标签精确区分。
    public static let copyAssistantMessage = ["Copy", "复制"]

    /// **用户自己**那条消息下方的复制按钮（spec 2.3.9 实测，挨着 `Edit message`）。
    /// 与 `copyAssistantMessage` 结构完全相同（都是单个 AXImage 子节点），
    /// **只能靠标签精确区分**。逐字稿靠这两个标签判断每段话是谁说的，搞反会让整份记录的
    /// 说话人全反，而且不报错、不崩溃。
    public static let copyUserMessage = ["Copy message", "复制消息"]

    /// 控制元素的合法 role。静音类是 AXCheckBox（subrole=AXToggleButton），
    /// 启停语音是 AXButton，两者结构判据相同（实测确认）。
    static let controlRoles: Set<String> = ["AXButton", "AXCheckBox"]

    /// 按标签 + 结构双重条件查找控制元素。
    ///
    /// **只按标签匹配是缺陷**（spec 2.3.1）：ChatGPT 每开一次语音就自动生成一条
    /// 名为 "New voice chat" 的侧边栏会话，而侧边栏在深度优先遍历里常常排在真按钮前面。
    /// 只取第一个命中会点中历史会话——实测发生过，且返回码是成功的。
    /// **图标形状优先，叶子形状兜底。**
    ///
    /// `isIconOnlyControl` 现在认两种形状（图标按钮、叶子按钮，见那边的说明）。
    /// 但同一个标签在树上可能两种都有——2026-08-30 实测：通话进行中时，
    /// 输入框那一行是图标形状的 `Stop voice chat`，而另一个面板里还挂着一颗
    /// 叶子形状的 `Start new voice chat`。
    /// 一视同仁地取「第一个命中」，就会随深度优先的遍历顺序碰运气。
    ///
    /// 分两趟：先找图标形状的（这是改版前唯一认的形状，历来对的那一批都在这里），
    /// 一个都没有时才退到叶子形状。**候选标签的优先级不变**——仍是按 `candidates`
    /// 的顺序逐个试，只是每个标签内部先图标后叶子。
    public static func matchControl(_ candidates: [String],
                                    among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        for candidate in candidates {
            if let hit = nodes.first(where: { isControl($0, labelled: candidate, iconOnly: true) }) {
                return hit
            }
            if let hit = nodes.first(where: { isControl($0, labelled: candidate, iconOnly: false) }) {
                return hit
            }
        }
        return nil
    }

    /// 一个节点是不是「标签为 `label` 的真控制按钮」。
    /// - Parameter iconOnly: true 只认图标形状（恰好一个 `AXImage` 子节点）；
    ///   false 只认叶子形状（没有子节点）。
    private static func isControl(_ node: AXNodeSnapshot, labelled label: String,
                                  iconOnly: Bool) -> Bool {
        guard controlRoles.contains(node.role), node.label == label else { return false }
        return iconOnly ? node.childRoles == ["AXImage"] : node.childCount == 0
    }

    /// 取**最后一个**匹配的控制元素。
    /// 界面上每条助手消息下方都有一个复制按钮，取第一个会复制到最早那条回复。
    /// `matchControl` 返回第一个匹配，此处必须取最后一个（深度优先顺序 ≈ 文档顺序，
    /// 最后一个即最新一条）。
    public static func matchLastControl(_ candidates: [String],
                                        among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        for candidate in candidates {
            // 同 `matchControl`：图标形状优先，叶子形状兜底。
            if let hit = nodes.last(where: { isControl($0, labelled: candidate, iconOnly: true) }) {
                return hit
            }
            if let hit = nodes.last(where: { isControl($0, labelled: candidate, iconOnly: false) }) {
                return hit
            }
        }
        return nil
    }

    /// **界面上现在有几条已经写完的助手回复。**
    ///
    /// 数的是助手消息下方那颗复制按钮，而不是文本节点——因为**那颗按钮要等这条消息
    /// 输出完之后才渲染出来**（`AXTranscriptSampler` 里记着这件事）。
    /// 所以「它变多了」恰好等价于「新的这条已经写完了」，这正是等回复要的信号。
    ///
    /// 上游用的是「助手回合数变多 + Stop 按钮消失」两个条件；本工具的 AX 树上没有
    /// 「停止生成」这个可靠标签（真查过，只有挂断语音那颗 `stopVoice`），
    /// 而复制按钮的渲染时机把两件事合成了一件，够用且更稳。
    public static func assistantReplyCount(among nodes: [AXNodeSnapshot]) -> Int {
        nodes.filter {
            controlRoles.contains($0.role) && $0.isIconOnlyControl
                && copyAssistantMessage.contains($0.label)
        }.count
    }

    /// 判据必须与 `matchControl` **对称**（role + label + 结构三重）。只查 label 和结构的话，
    /// 会漏报「label 命中、role 不符、但恰好只有一个 AXImage 子节点」的元素，
    /// 让诊断看起来比实际情况更干净——排查时反而误导人。
    public static func structuralMismatches(_ candidates: [String],
                                            among nodes: [AXNodeSnapshot]) -> [AXNodeSnapshot] {
        nodes.filter {
            candidates.contains($0.label) && !(controlRoles.contains($0.role) && $0.isIconOnlyControl)
        }
    }

    /// 找输入框。**不做无条件兜底。**
    ///
    /// 退到「任意 AXTextArea」会踩 `matchControl` 刻意规避的同款反模式：界面上若有别的
    /// 多行文本框（搜索框、重命名会话的输入框，或改版后被 Chromium 映射成 AXTextArea 的
    /// 任何东西），考官提示词会被**静默**写进去——用户只看到「点了开始什么都没发生」，
    /// 毫无线索可查。**响亮的失败比静默的错误好。**
    ///
    /// 折中：整个界面只有一个 AXTextArea 时不存在歧义，用它是安全的；
    /// 两个以上时返回 nil，由调用方报错并列出候选供诊断。
    public static func composer(among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        if let exact = nodes.first(where: {
            $0.role == "AXTextArea" && composerDescriptions.contains($0.descriptionText)
        }) { return exact }
        let textAreas = nodes.filter { $0.role == "AXTextArea" }
        return textAreas.count == 1 ? textAreas[0] : nil
    }

    /// 界面此刻是不是真的处在语音通话里。
    ///
    /// **判据是通话控制按钮，不是输入框的 description。**
    ///
    /// 2026-08-08 真机实测（两份 AX dump 对比）推翻了此前的假设：
    /// 这一版 ChatGPT 的输入框在**两种状态下都叫 `Work with ChatGPT`**。
    /// 真正随状态变化的是输入框那一行工具栏上的按钮——
    ///
    /// | | 空对话 | 通话中 |
    /// |---|---|---|
    /// | 输入框 desc | `Work with ChatGPT` | `Work with ChatGPT` |
    /// | 同行按钮 | `Dictate`、`Start new voice chat` | `Mute speakers`、`Mute microphone`、`Stop voice chat` |
    ///
    /// 这张表 2026-08-30 在 26.820.60940 上复核过，**输入框那一行仍然如此**；
    /// 变的是别的面板（见下面那段）。
    ///
    /// ## 2026-08-30：撤掉「`Start new voice chat` 不在」那一半
    ///
    /// 那一半原本是想确认「界面确实已经切到通话那一屏」。它在 08-08 那一版成立，
    /// 但**它是在用「证据不存在」去推断状态**，而这次实测（26.820.60940）它不成立了：
    ///
    /// 通话进行中时 AX 树里有**两个窗口**（`AXDialog` 的通话面板 + `AXStandardWindow`
    /// 的主窗口），主窗口别的面板上仍然挂着一颗 `Start new voice chat`
    /// （叶子形状，`children=0`）、侧边栏还有一条 `title="New voice chat"`。
    /// 于是「start 不在」永远不成立，`waitForVoiceComposer` 一直等到 20 秒超时——
    /// 用户报的就是这个。
    ///
    /// 现在只认正面证据：**`Stop voice chat` 在，就是在通话里**。
    /// 这颗按钮只在通话进行时存在（08-08 与 08-30 两份 dump 都印证），
    /// 而且它就在输入框那一行上——`Mute speakers` / `Mute microphone` / `Stop voice chat`
    /// 这一组换掉了空对话时的 `Dictate` / `Start new voice chat`。
    ///
    /// 「万一界面还停在旧对话上」这个担心由 `composer(among:)` 兜着：
    /// 它只在整棵树恰好只有一个 `AXTextArea` 时才返回（实测通话中就是 1 个），
    /// 有歧义时返回 nil，调用方响亮地失败而不是往错的框里写字。
    public static func isInVoiceCall(_ nodes: [AXNodeSnapshot]) -> Bool {
        matchControl(stopVoice, among: nodes) != nil
    }

    /// 专门找**语音会话里那个**输入框。
    ///
    /// **不能靠 description 认**（见 `isInVoiceCall`）：两种状态同名，
    /// 那个判据一开始就成立，`waitForVoiceComposer` 会立刻返回、根本不等，
    /// 于是考官提示词被打进旧对话的输入框——用户报的正是这个：
    /// 「压根就没有等到语音对话中提示框出现的那一刻」「又另外创建了一个文字对话」。
    ///
    /// 现在的做法是先确认界面真的在通话里，再取输入框。
    public static func voiceComposer(among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        guard isInVoiceCall(nodes) else { return nil }
        return composer(among: nodes)
    }

    /// 界面上全部的文本框。`composer` 找不到时用于给出可执行的诊断。
    public static func candidateComposers(among nodes: [AXNodeSnapshot]) -> [AXNodeSnapshot] {
        nodes.filter { $0.role == "AXTextArea" }
    }

    public static func isVoiceActive(_ nodes: [AXNodeSnapshot]) -> Bool {
        nodes.contains { $0.role == "AXImage" && $0.descriptionText == voiceActiveIndicator }
    }

    /// 这个节点能不能用来判定「前面攒的那些文本是谁说的」。
    ///
    /// 判据与 `matchControl` 对称（role + label + 结构三重，见 spec 2.3.1）：
    /// 侧边栏里可能存在同名的会话行，但它嵌套着 AXButton（Pin chat / Archive chat），
    /// 不是单个 AXImage 子节点，不满足结构判据。只按标签匹配会让说话人判别随机出错。
    ///
    /// **必须先判 `copyUserMessage` 再判 `copyAssistantMessage`** ——
    /// 两个集合的元素是精确相等比较，不存在前缀吞并问题，但顺序写反了读起来容易误解，
    /// 保持「先用户、后助手」这个固定顺序。
    public static func speakerMarker(_ node: AXNodeSnapshot) -> TranscriptSpeaker? {
        guard controlRoles.contains(node.role), node.isIconOnlyControl else { return nil }
        if copyUserMessage.contains(node.label) { return .learner }
        if copyAssistantMessage.contains(node.label) { return .examiner }
        return nil
    }
}
