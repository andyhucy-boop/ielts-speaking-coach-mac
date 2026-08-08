import Foundation

/// 设置窗口的四个分区。**恰好四个，且六个用户可配置项全在里面**——
/// 多出第五个分区，或者哪个设置又跑到别的页面上去，都意味着这次合并白做了。
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case recording
    case goals
    case practice
    case data

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recording: return "录音"
        case .goals: return "训练目标"
        case .practice: return "练习偏好"
        case .data: return "数据与隐私"
        }
    }

    public var systemImage: String {
        switch self {
        case .recording: return "mic"
        case .goals: return "target"
        case .practice: return "slider.horizontal.3"
        case .data: return "folder"
        }
    }

    /// 这一栏管什么。没有这句话，用户得挨个点进去猜。
    public var summary: String {
        switch self {
        case .recording:
            return "要不要录下你的回答、麦克风权限、录音占了多少地方。"
        case .goals:
            return "每周想练几次。首页那格「本周 N/M 次」用的就是它。"
        case .practice:
            return "默认从哪条路线开练、考官什么时候给反馈、Part 2 的一分钟准备怎么算、"
                + "要不要记录对话逐字稿。"
        case .data:
            return "你的数据存在哪儿、占了多少、怎么备份和搬走。"
        }
    }
}
