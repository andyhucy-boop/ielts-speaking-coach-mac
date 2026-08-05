import ChatGPTBridge
import Foundation

public enum PermissionState: Equatable, Sendable {
    case ready
    case needsAccessibility
    case needsChatGPT
    /// preflight 报了失败，但消息不是我们认识的任何一种。
    /// **不能当成 ready** —— 那会让用户点进去撞一堵墙且没有线索。
    case unknown
}

public enum PermissionStatus {
    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static func evaluate(readiness: BridgeReadiness) -> PermissionState {
        if readiness.ok { return .ready }
        let joined = readiness.messages.joined()
        // 顺序有意义：两样都缺时先引导装 ChatGPT——没有目标应用，给了权限也没用
        if joined.contains("没找到 ChatGPT") { return .needsChatGPT }
        if joined.contains("辅助功能") { return .needsAccessibility }
        return .unknown
    }
}
