import AppKit
import ChatGPTBridge
import SwiftUI

/// 环境未就绪时挡在前面的引导页。用户可以跳过——spec 第 7 节规定授权可跳过，
/// 跳过后运行在半自动模式（界面其余部分仍可用，只是没法自动驱动 ChatGPT）。
///
/// **页面上出现的每一句「下一步」，都必须是用户在当前宿主里真做得到的事。**
/// 这里踩过一次：`preflight()` 的消息是 Phase 2 为命令行写的，让用户「把运行本工具的
/// 终端加进辅助功能」，而页面上方的引导语说的是「把本应用加进列表」——同一屏两条互相
/// 矛盾的指令，照原文做的用户会去授权终端，回来点「重新检查」仍然失败。
/// 修法不是在视图里挑着显示，而是从源头统一：`AXDriver` 和 `PermissionStatus.guidance`
/// 都按 `HostEnvironment` 决定「勾谁」，所以下方原样展示的原文与上方的引导语不会打架。
///
/// 同理，「收集诊断信息」不再让用户去终端跑 `axprobe`——`scripts/build-app.sh` 只把
/// `IELTSCoachApp` 拷进包里，只装了 `.app` 的用户没有那个命令。改成页面上的
/// 「复制诊断信息」按钮。
public struct PermissionGateView: View {
    let state: PermissionState
    let messages: [String]
    /// 用户已经查完几次「重新检查」。**故意不给默认值**：忘了接线就编译不过，
    /// 比事后靠一条扫源码的测试去发现要早得多。
    ///
    /// 值来自 `AppState`，不是本视图的 `@State`——重查期间整页会被
    /// 「正在检查运行环境…」换掉，本视图连同它的 `@State` 一起销毁重建。
    let recheckAttempts: Int
    let host: HostEnvironment
    let onRecheck: () -> Void
    let onSkip: () -> Void
    /// 真正去打开系统设置的那一下。抽成闭包是为了让「返回 false 时到底会不会告诉用户」
    /// 这件事有测试管得住（`View` 本身无法单元测试）。
    let openURL: (URL) -> Bool
    /// 真正去写剪贴板的那一下，同上。
    let writeToPasteboard: (String) -> Bool

    /// 点了「打开系统设置」「复制诊断信息」之后的反馈。`nil` 表示还没点过。
    ///
    /// 这两颗按钮的反馈可以留在 `@State` 里，因为它们不换屏；
    /// 「重新检查」不行——它会把整页换成等待屏，见 `recheckAttempts`。
    @State private var notice: ActionNotice?

    public init(state: PermissionState, messages: [String],
                recheckAttempts: Int,
                host: HostEnvironment = .current,
                onRecheck: @escaping () -> Void, onSkip: @escaping () -> Void,
                openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
                writeToPasteboard: @escaping (String) -> Bool = { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    return pasteboard.setString(text, forType: .string)
                }) {
        self.state = state; self.messages = messages
        self.recheckAttempts = recheckAttempts; self.host = host
        self.onRecheck = onRecheck; self.onSkip = onSkip
        self.openURL = openURL; self.writeToPasteboard = writeToPasteboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(PermissionStatus.title(for: state))
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(PermissionStatus.guidance(for: state, host: host))
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)

            // 「重新检查」的反馈。查出来的结论和上次一样时，这一页别处一个像素都不会变，
            // 用户分不清是「查过了还是不行」还是「按钮坏了」。
            if let recheckNotice = PermissionStatus.recheckNotice(
                completedAttempts: recheckAttempts, state: state, host: host) {
                noticeLine(recheckNotice)
            }

            if let notice { noticeLine(notice) }

            if !messages.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("检查结果原文")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    ForEach(messages, id: \.self) {
                        Text($0)
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                if state == .needsAccessibility {
                    Button("打开系统设置") {
                        notice = PermissionStatus.openSettings(host: host, using: openURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    Button("重新检查", action: onRecheck)
                } else {
                    // 每页只有一个主行动：没有「打开系统设置」时，主行动是「重新检查」
                    Button("重新检查", action: onRecheck)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                }
                if state != .ready {
                    Button("复制诊断信息") {
                        notice = PermissionStatus.copyDiagnostics(
                            state: state, messages: messages, host: host, using: writeToPasteboard)
                    }
                }
                Button("先跳过", action: onSkip)
            }

            Text("「先跳过」后可以先浏览题库和历史复盘；在上面的问题解决之前，"
                 + "自动驱动 ChatGPT 的练习没法进行。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 640, alignment: .leading)
    }

    /// 两处反馈走同一套排版。抽出来是为了让两处的字体、颜色、可选中永远一致——
    /// 各写一份的话，「失败」那一处的红迟早会和另一处对不上。
    ///
    /// **失败用 `Palette.danger` 而不是 `Color.red`。** 系统红在深色底上是一个刺眼
    /// 且对比度不足的红，而 `Palette.danger` 两套外观各有取值，
    /// 都在 `AppearanceContrastTests` 那张矩阵里过了 4.5:1。
    @ViewBuilder private func noticeLine(_ notice: ActionNotice) -> some View {
        Text(notice.text)
            .font(Typography.secondary)
            .foregroundStyle(notice.isFailure ? Palette.danger : Palette.textSecondary)
            .textSelection(.enabled)
    }
}

/// 预览的是最常见的那一屏：勾完开关回来点了一次「重新检查」，还是没过。
#Preview {
    PermissionGateView(
        state: .needsAccessibility,
        messages: ["❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能，"
                   + "把「IELTS Speaking Coach」加进去并勾选，然后回到本应用点「重新检查」。"],
        recheckAttempts: 1,
        host: .app(name: "IELTS Speaking Coach"),
        onRecheck: {}, onSkip: {})
}
