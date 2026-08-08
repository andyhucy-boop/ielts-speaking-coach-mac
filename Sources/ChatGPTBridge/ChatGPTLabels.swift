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
    /// 输入框的 description **随状态而变**（实测）：普通聊天是 "Message ChatGPT"，
    /// 语音会话进行中是 "Work with ChatGPT"。此前只认后者，是因为最初的 AX 结构
    /// 全部在语音会话中采集，把语音态特征当成了通用特征。
    /// 普通聊天状态的输入框。
    public static let normalComposerDescription = "Message ChatGPT"
    /// 语音模式下的输入框。**实测比 Voice chat active 还晚约 3 秒出现。**
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
    public static func matchControl(_ candidates: [String],
                                    among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        for candidate in candidates {
            if let hit = nodes.first(where: {
                controlRoles.contains($0.role) && $0.label == candidate && $0.isIconOnlyControl
            }) { return hit }
        }
        return nil
    }

    /// 取**最后一个**匹配的控制元素。
    /// 界面上每条助手消息下方都有一个复制按钮，取第一个会复制到最早那条回复。
    /// `matchControl` 返回第一个匹配，此处必须取最后一个（深度优先顺序 ≈ 文档顺序，
    /// 最后一个即最新一条）。
    public static func matchLastControl(_ candidates: [String],
                                        among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        for candidate in candidates {
            if let hit = nodes.last(where: {
                controlRoles.contains($0.role) && $0.label == candidate && $0.isIconOnlyControl
            }) { return hit }
        }
        return nil
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

    /// 专门找**语音模式**的输入框。不能用通用的 composer(among:) —— 语音起来后
    /// 有约 3 秒窗口界面上摆的仍是普通输入框，那时发送会发进错误的框。
    public static func voiceComposer(among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        nodes.first { $0.role == "AXTextArea" && $0.descriptionText == voiceComposerDescription }
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
