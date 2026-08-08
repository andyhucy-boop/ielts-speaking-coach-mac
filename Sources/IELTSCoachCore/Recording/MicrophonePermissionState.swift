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
    ///
    /// ## 「下一步」里点名的那个开关，界面上必须真有，而且名字要一模一样
    ///
    /// 这几句话有两个出口，而**两个出口都不在这一页上**：
    ///
    /// - 录音设置页（⌘,）的 `consentText` / `notice`；
    /// - 练习进行中那张 sheet 的 `recordingNotice`（`RecordingConsent.readiness` 判 `.blocked`
    ///   时把这句话原样带过去）——那时用户正在练习界面上，设置窗口根本没开。
    ///
    /// 所以「下一步」必须把路指全：先说去哪儿（`录音设置`，⌘,），再说拨哪个开关。
    /// 原来这里写的是「点「开启录音」」，而**全 App 没有任何按钮或开关叫这个名字**
    /// （`grep -rn "开启录音" Sources/` 只命中这句文案自己）；屏幕上那颗开关叫
    /// 「保存我的回答录音」（`RecordingSettingsView` 里的 `Toggle`）。
    /// 用户照着找一颗不存在的开关，比不给下一步还糟——本项目已经栽过一次同样的跤
    /// （`ReviewParser` 那句「点「补生成复盘报告」」是命令行时代的说法）。
    ///
    /// **开关标题是照抄过来的字面量，不是引用的常量**，这是刻意的：扫源码的守卫
    /// （`SourceGuard.literalControlTitles`）只认得 `Toggle("…")` 里的字面标题，
    /// 改成共享常量就等于把那条守卫关掉。两处会不会走岔由
    /// `RecordingSettingsViewTests.testTheMicrophoneGuidanceNamesTheSwitchThatIsActuallyOnThisPage`
    /// 盯着——它从视图源码里读出那颗开关真正的标题，再回来查这几句话。
    ///
    /// `restricted` 不提这个开关：那种情况用户自己改不了，让他去拨一个拨不动的开关
    /// 同样是空指一步。
    public var guidance: String? {
        switch self {
        case .granted:
            return nil
        case .notDetermined:
            return "还没有麦克风权限，所以现在还录不了。"
                + "下一步：到「录音设置」（⌘,）点一下「保存我的回答录音」这个开关，"
                + "系统会弹出一个对话框，请在那个对话框上点「允许」。"
        case .denied:
            return "麦克风权限被拒绝过，系统不会再弹第二次对话框。"
                + "下一步：打开「系统设置 › 隐私与安全性 › 麦克风」，"
                + "把「IELTS Speaking Coach」那一项打开，"
                + "然后回到「录音设置」（⌘,）点一下「保存我的回答录音」这个开关。"
        case .restricted:
            return "这台电脑的麦克风被系统策略限制了（例如描述文件或家长控制），本应用改不了。"
                + "下一步：找管理这台电脑的人解除限制；在那之前录音用不了，其余功能不受影响。"
        }
    }

    /// 系统设置里麦克风那一页。被拒之后这是唯一的出路。
    public static let systemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}
