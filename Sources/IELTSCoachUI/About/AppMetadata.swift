import Foundation

/// 这份 App 是怎么签的，以及这对拿到它的人意味着什么。
/// 取值由 `scripts/build-app.sh` 写进 Info.plist 的 `IELTSSignatureChannel`。
public enum SignatureChannel: String, Equatable, Sendable, CaseIterable {
    case selfSigned = "self-signed"
    case developerID = "developer-id"
    case unknown

    public static func from(_ raw: String?) -> SignatureChannel {
        guard let raw, let channel = SignatureChannel(rawValue: raw) else { return .unknown }
        return channel
    }

    public var title: String {
        switch self {
        case .selfSigned: return "自签名（未经 Apple 公证）"
        case .developerID: return "Developer ID 签名，已通过 Apple 公证"
        case .unknown: return "无签名信息（从源码直接运行）"
        }
    }

    /// 发生了什么。
    public var explanation: String {
        switch self {
        case .selfSigned:
            return "这份 App 用作者本机生成的证书签名，没有购买 Apple 开发者账号做公证。"
                + "Apple 对所有未公证的 App 都会拦一下，这与它本身是否安全无关。"
        case .developerID:
            return "这份 App 用 Apple 签发的 Developer ID 证书签名，并且通过了 Apple 的公证。"
        case .unknown:
            return "现在跑的是从源码直接启动的开发版本，没有打包成 .app，因此读不到签名信息。"
        }
    }

    /// 下一步做什么。
    ///
    /// **自签名那句为什么不写「点「仍要打开」」：** 那颗按钮是 macOS 系统设置自己的，
    /// 不是本 App 的控件。本项目把「点「X」」这种写法留给自家控件——
    /// `RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists`
    /// 会把界面模块里每一处「点「X」」拿去跟真实的 `Button` / `Toggle` 清单核对，
    /// 写成「点「仍要打开」」会被它当场报成幽灵控件（本任务实测报出过），
    /// 而它给的两条出路——改指自家按钮、或者把这颗按钮做出来——在这里一条都不成立。
    /// 全项目指向系统设置的文案（`PermissionStatus`、`MicrophonePermissionState`、`AXDriver`）
    /// 也都是「打开 / 到 …」而不是「点 …」，这里跟着同一套写法。
    public var nextStep: String {
        switch self {
        case .selfSigned:
            return "拷给别人时，对方第一次打开会被系统拦下。"
                + "让他打开「系统设置 › 隐私与安全性」，在「安全性」一节找到被阻止的这一条，"
                + "按下那里的「仍要打开」，再确认一次。"
        case .developerID:
            return "对方双击即可打开，不会被系统拦下。"
        case .unknown:
            return "要得到可以拷给别人的版本，运行 scripts/package-app.sh。"
        }
    }
}

/// 关于页与诊断信息要显示的「这是哪一份 App」。
///
/// **为什么每个字段都要有兜底：** `swift run IELTSCoachApp` 直接跑时没有 App bundle，
/// `Bundle.main.infoDictionary` 是 nil。关于页这时不能变成一片空白 ——
/// 空白页会让用户以为程序坏了（DESIGN-SYSTEM.md 第 4 节的原则，对关于页同样成立）。
public struct AppMetadata: Equatable, Sendable {
    public static let unknownValue = "未知（开发运行）"

    public let displayName: String
    public let bundleIdentifier: String
    public let shortVersion: String
    public let buildNumber: String
    public let buildCommit: String
    public let buildDate: String
    public let signingIdentity: String
    public let channel: SignatureChannel

    public init(displayName: String, bundleIdentifier: String, shortVersion: String,
                buildNumber: String, buildCommit: String, buildDate: String,
                signingIdentity: String, channel: SignatureChannel) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
        self.buildCommit = buildCommit
        self.buildDate = buildDate
        self.signingIdentity = signingIdentity
        self.channel = channel
    }

    public static func from(infoDictionary: [String: Any]?) -> AppMetadata {
        func value(_ key: String) -> String {
            guard let raw = infoDictionary?[key] else { return unknownValue }
            // String(describing:) 兼顾 plist 里被写成 <integer> 的值（常见事故），
            // 也保证 String 原样返回。
            let text = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? unknownValue : text
        }
        return AppMetadata(
            displayName: value("CFBundleDisplayName"),
            bundleIdentifier: value("CFBundleIdentifier"),
            shortVersion: value("CFBundleShortVersionString"),
            buildNumber: value("CFBundleVersion"),
            buildCommit: value("IELTSBuildCommit"),
            buildDate: value("IELTSBuildDate"),
            signingIdentity: value("IELTSSigningIdentity"),
            channel: SignatureChannel.from(infoDictionary?["IELTSSignatureChannel"] as? String))
    }

    public static var current: AppMetadata { from(infoDictionary: Bundle.main.infoDictionary) }

    public var versionLine: String { "\(shortVersion)（构建 \(buildNumber)）" }
}
