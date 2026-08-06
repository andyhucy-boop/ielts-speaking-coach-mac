import AVFoundation
import Foundation
import IELTSCoachCore

/// 查询与申请麦克风权限。做成 protocol 是为了让视图模型能用假实现测试——
/// 真实实现的返回值取决于跑测试这台机器授过什么权，直接依赖它的测试今天绿明天红。
public protocol MicrophoneAuthorizing: Sendable {
    func currentStatus() -> MicrophonePermissionState
    /// 弹一次系统对话框。
    ///
    /// **只有 `currentStatus() == .notDetermined` 时调用才有意义。** 用户拒绝过之后
    /// macOS 不再弹窗，这个方法会立刻返回 `.denied`——调用方必须据此给出「去系统设置」
    /// 的引导，而不是让用户等一个不会出现的对话框。
    func requestAccess() async -> MicrophonePermissionState
}

public struct SystemMicrophoneAuthorizer: MicrophoneAuthorizing {
    public init() {}

    public func currentStatus() -> MicrophonePermissionState {
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func requestAccess() async -> MicrophonePermissionState {
        let current = currentStatus()
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    /// 映射单独拆成静态函数是为了能测：AVAuthorizationStatus 的四个值可以直接写出来，
    /// 而 AVCaptureDevice 的真实状态测不了。
    public static func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        // 认不出来的新状态一律按「录不了」处理。**绝不能默认成 granted**——
        // 那会让 App 以为自己在录音，用户练完却什么都没有，且没有任何线索。
        @unknown default: return .denied
        }
    }
}
