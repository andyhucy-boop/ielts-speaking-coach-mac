import AppKit
import ChatGPTBridge
import SwiftUI

/// 环境未就绪时挡在前面的引导页。用户可以跳过——spec 第 7 节规定授权可跳过，
/// 跳过后运行在半自动模式（界面其余部分仍可用，只是没法自动驱动 ChatGPT）。
///
/// 页面自带一段面向图形界面的「下一步」文案（`guidance`），而不是只把 `preflight()`
/// 的原文摆出来：那些消息是 Phase 2 为命令行写的，里面让用户「把运行本工具的终端
/// 加进辅助功能」——在 .app 里要勾的是本应用而不是终端，照着做会白忙一场。
/// 原文仍完整显示在下方，可选中复制，便于排查。
public struct PermissionGateView: View {
    let state: PermissionState
    let messages: [String]
    let onRecheck: () -> Void
    let onSkip: () -> Void

    public init(state: PermissionState, messages: [String],
                onRecheck: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.state = state; self.messages = messages
        self.onRecheck = onRecheck; self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2).bold()
            Text(guidance).font(.body).textSelection(.enabled)

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
                        NSWorkspace.shared.open(PermissionStatus.systemSettingsURL)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("重新检查", action: onRecheck)
                } else {
                    // 每页只有一个主行动：没有「打开系统设置」时，主行动是「重新检查」
                    Button("重新检查", action: onRecheck).buttonStyle(.borderedProminent)
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

    private var title: String {
        switch state {
        case .ready: return "环境就绪"
        case .needsAccessibility: return "还差一步：辅助功能权限"
        case .needsChatGPT: return "还没装 ChatGPT"
        case .unknown: return "环境检查没通过"
        }
    }

    /// 每种状态都要同时说清「发生了什么」和「下一步做什么」——只说失败不说下一步不算合格。
    private var guidance: String {
        switch state {
        case .ready:
            return "已经能驱动 ChatGPT 了，可以直接开始练习。"
        case .needsAccessibility:
            return "本应用要替你点 ChatGPT 的界面，这需要系统的辅助功能权限，现在还没拿到。"
                + "下一步：点「打开系统设置」，在「隐私与安全性 › 辅助功能」里把"
                + "「IELTS Speaking Coach」加进列表并打开它的开关，然后回到这里点「重新检查」。"
        case .needsChatGPT:
            return "没在这台电脑上找到 ChatGPT 桌面应用，没有它就没法练。"
                + "下一步：到 openai.com/chatgpt/download 下载安装"
                + "（ChatGPT Classic 没有 live 语音，用不了），装好后回到这里点「重新检查」。"
        case .unknown:
            return "环境检查没通过，但失败原因不在已知的几种里，所以这里给不出针对性的修法。"
                + "下一步：先读下面的「检查结果原文」；若仍看不出问题，"
                + "在终端运行 axprobe dump 收集诊断信息，再把它连同原文一起反馈。"
        }
    }
}

#Preview {
    PermissionGateView(state: .needsAccessibility,
                       messages: ["❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能，把本应用加进去并勾选。"],
                       onRecheck: {}, onSkip: {})
}
