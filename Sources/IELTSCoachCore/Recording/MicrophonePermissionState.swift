import Foundation

/// 系统麦克风权限的状态。
///
/// 放在 Core（只依赖 Foundation）是刻意的：判定与文案是纯逻辑，与 AVFoundation
/// 的具体枚举无关，因此可以在完全不碰音频框架的情况下完整测试。音频 target 只负责
/// 把 AVAuthorizationStatus 映射到这里。
public enum MicrophonePermissionState: String, Equatable, Sendable, CaseIterable {
    /// 已授权，可以录。
    case granted
    /// 还没问过。**只有这种状态下弹系统对话框才有用。**
    case notDetermined
    /// 用户拒绝过。macOS 不会再弹第二次，只能让用户自己去系统设置里打开。
    case denied
    /// 被描述文件、MDM 或家长控制限制，用户自己也改不了。
    case restricted

    /// 能不能通过弹系统对话框拿到权限。
    public var canPrompt: Bool { self == .notDetermined }

    /// 给用户看的说明。granted 时为 nil（没什么要说的）。
    /// 其余每一条都必须同时说清「发生了什么」和「下一步做什么」。
    public var guidance: String? {
        switch self {
        case .granted:
            return nil
        case .notDetermined:
            return "还没有麦克风权限，所以现在还录不了。"
                + "下一步：点「开启录音」，系统会弹出一个对话框，请在那个对话框上点「允许」。"
        case .denied:
            return "麦克风权限被拒绝过，系统不会再弹第二次对话框。"
                + "下一步：打开「系统设置 › 隐私与安全性 › 麦克风」，"
                + "把「IELTS Speaking Coach」那一项打开，然后回到这里再点一次开关。"
        case .restricted:
            return "这台电脑的麦克风被系统策略限制了（例如描述文件或家长控制），本应用改不了。"
                + "下一步：找管理这台电脑的人解除限制；在那之前录音用不了，其余功能不受影响。"
        }
    }

    /// 系统设置里麦克风那一页。被拒之后这是唯一的出路。
    public static let systemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}
