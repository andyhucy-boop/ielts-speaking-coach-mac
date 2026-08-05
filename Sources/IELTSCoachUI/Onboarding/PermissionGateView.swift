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
    let host: HostEnvironment
    let onRecheck: () -> Void
    let onSkip: () -> Void
    /// 真正去打开系统设置的那一下。抽成闭包是为了让「返回 false 时到底会不会告诉用户」
    /// 这件事有测试管得住（`View` 本身无法单元测试）。
    let openURL: (URL) -> Bool
    /// 真正去写剪贴板的那一下，同上。
    let writeToPasteboard: (String) -> Bool

    /// 点了按钮之后的反馈。`nil` 表示还没点过。
    @State private var notice: ActionNotice?

    public init(state: PermissionState, messages: [String],
                host: HostEnvironment = .current,
                onRecheck: @escaping () -> Void, onSkip: @escaping () -> Void,
                openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
                writeToPasteboard: @escaping (String) -> Bool = { text in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    return pasteboard.setString(text, forType: .string)
                }) {
        self.state = state; self.messages = messages; self.host = host
        self.onRecheck = onRecheck; self.onSkip = onSkip
        self.openURL = openURL; self.writeToPasteboard = writeToPasteboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(PermissionStatus.title(for: state)).font(.title2).bold()
            Text(PermissionStatus.guidance(for: state, host: host))
                .font(.body).textSelection(.enabled)

            if let notice {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.isFailure ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            }

            if !messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("检查结果原文").font(.caption).foregroundStyle(.secondary)
                    ForEach(messages, id: \.self) {
                        Text($0).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 8) {
                if state == .needsAccessibility {
                    Button("打开系统设置") {
                        notice = PermissionStatus.openSettings(host: host, using: openURL)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("重新检查", action: onRecheck)
                } else {
                    // 每页只有一个主行动：没有「打开系统设置」时，主行动是「重新检查」
                    Button("重新检查", action: onRecheck).buttonStyle(.borderedProminent)
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
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}

#Preview {
    PermissionGateView(
        state: .needsAccessibility,
        messages: ["❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能，"
                   + "把「IELTS Speaking Coach」加进去并勾选，然后回到本应用点「重新检查」。"],
        host: .app(name: "IELTS Speaking Coach"),
        onRecheck: {}, onSkip: {})
}
