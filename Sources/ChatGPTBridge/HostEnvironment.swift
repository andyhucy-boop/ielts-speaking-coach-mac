import Foundation

/// 本工具当前跑在哪种宿主里。
///
/// **为什么这件事必须进产品代码而不是在界面里改文案：** 辅助功能（TCC）授权的对象是
/// 发起 AX 调用的进程被系统归属到的那个应用——从终端跑 `coach` / `axprobe`，归属的是
/// 终端；双击 `.app` 跑，归属的是本应用。preflight 的提示只写死一种，另一种宿主的用户
/// 照着做会白忙一场：授权了错误的对象，回来重试仍然失败，而且没有任何线索说明为什么。
///
/// 同一个理由也适用于「收集诊断信息」：`scripts/build-app.sh` 只把 `IELTSCoachApp` 拷进
/// `Contents/MacOS`，只装了 `.app` 的用户手上没有 `axprobe` 这个命令，让他去终端跑它
/// 等于给了一个他做不到的下一步。
public enum HostEnvironment: Equatable, Sendable {
    /// 运行在 `.app` 包里。`name` 是用户在「系统设置 › 辅助功能」列表里看到的那个名字。
    case app(name: String)
    /// 从终端运行的命令行进程（`swift run`、`.build/release/coach` 等）。
    case commandLine

    /// 当前进程的宿主。
    public static var current: HostEnvironment { detect(bundle: .main) }

    /// 判据是「`Bundle` 指向的是不是一个 `.app` 包」。命令行可执行文件的 `Bundle.main`
    /// 指向的是可执行文件所在的**目录**（没有 `.app` 后缀），这正好与 TCC 的归属规则一致：
    /// 不在 .app 里跑，授权就落在拉起它的终端上。
    public static func detect(bundle: Bundle) -> HostEnvironment {
        guard bundle.bundleURL.pathExtension == "app" else { return .commandLine }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        // 读不到名字也绝不能退回 .commandLine —— 那会让 .app 用户看到「去勾选终端」
        return .app(name: name ?? "本应用")
    }

    /// 「要在辅助功能列表里勾选谁」这句话该怎么说。
    public var accessibilityGrantee: String {
        switch self {
        case .app(let name): return "「\(name)」"
        case .commandLine: return "运行本工具的终端"
        }
    }

    /// 授权/处理完之后「怎么再来一次」。
    public var retryInstruction: String {
        switch self {
        case .app: return "回到本应用点「重新检查」"
        case .commandLine: return "重新运行本命令"
        }
    }

    /// 收集诊断信息的办法。必须是用户在**这个**宿主里真做得到的动作。
    public var diagnosticsInstruction: String {
        switch self {
        case .app: return "在权限页点「复制诊断信息」，把内容反馈给开发者"
        case .commandLine: return "运行 axprobe dump 收集诊断信息"
        }
    }
}
