import Foundation

/// ChatGPT.app 的界面特征。**ChatGPT 改版时只改这个文件。**
/// 别处不得硬编码任何界面标签。
public enum ChatGPTLabels {
    /// 启动语音。实测在同一台机器上先后出现过三种标签，全部保留。
    public static let startVoice = ["Start voice chat", "Start new voice chat", "New voice chat"]
    public static let stopVoice = ["Stop voice chat"]
    /// 语音进行中的标志。实测为会话级常驻，静默不消失（spec 2.3.3）。
    public static let voiceActiveIndicator = "Voice chat active"
    public static let composerDescription = "Work with ChatGPT"

    /// 按标签 + 结构双重条件查找控制元素。
    ///
    /// **只按标签匹配是缺陷**（spec 2.3.1）：ChatGPT 每开一次语音就自动生成一条
    /// 名为 "New voice chat" 的侧边栏会话，而侧边栏在深度优先遍历里常常排在真按钮前面。
    /// 只取第一个命中会点中历史会话——实测发生过，且返回码是成功的。
    public static func matchControl(_ candidates: [String],
                                    among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        let controlRoles: Set<String> = ["AXButton", "AXCheckBox"]
        for candidate in candidates {
            if let hit = nodes.first(where: {
                controlRoles.contains($0.role) && $0.label == candidate && $0.isIconOnlyControl
            }) { return hit }
        }
        return nil
    }

    /// 标签命中但结构不符的元素。查找失败时用它给出有用的诊断，而不是干巴巴一句「没找到」。
    public static func structuralMismatches(_ candidates: [String],
                                           among nodes: [AXNodeSnapshot]) -> [AXNodeSnapshot] {
        nodes.filter { candidates.contains($0.label) && !$0.isIconOnlyControl }
    }

    public static func composer(among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        nodes.first { $0.role == "AXTextArea" && $0.descriptionText == composerDescription }
            ?? nodes.first { $0.role == "AXTextArea" }
    }

    public static func isVoiceActive(_ nodes: [AXNodeSnapshot]) -> Bool {
        nodes.contains { $0.role == "AXImage" && $0.descriptionText == voiceActiveIndicator }
    }
}
