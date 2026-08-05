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

/// 点了按钮之后要显示给用户的一句话。
/// **成功也要有反馈**：只在失败时才说话，用户分不清「成功了」和「点了没反应」。
public struct ActionNotice: Equatable, Sendable {
    public let text: String
    public let isFailure: Bool
    public init(text: String, isFailure: Bool) {
        self.text = text
        self.isFailure = isFailure
    }
}

public enum PermissionStatus {
    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static func evaluate(readiness: BridgeReadiness) -> PermissionState {
        if readiness.ok { return .ready }
        let joined = readiness.messages.joined()
        // 顺序有意义：两样都缺时先引导装 ChatGPT——没有目标应用，给了权限也没用
        //
        // 这里认的是 AXDriver 写死的文案。生产者与消费者靠子串耦合，看不出来也测不出来，
        // 所以 PermissionStatusTests 里有一组测试让 preflight 的**真实输出**流过这里；
        // 改 AXDriver 的措辞而不同步改这里，那组测试会红。
        if joined.contains("没找到 ChatGPT") { return .needsChatGPT }
        if joined.contains("辅助功能") { return .needsAccessibility }
        return .unknown
    }

    /// 页面标题。放在这里而不是 View 里，是为了让诊断信息复用同一套说法。
    public static func title(for state: PermissionState) -> String {
        switch state {
        case .ready: return "环境就绪"
        case .needsAccessibility: return "还差一步：辅助功能权限"
        case .needsChatGPT: return "还没装 ChatGPT"
        case .unknown: return "环境检查没通过"
        }
    }

    /// 每种状态要显示的「发生了什么 + 下一步做什么」。
    ///
    /// **下一步必须是用户在当前宿主里真做得到的事。** 两条踩过的坑：
    /// 一是让 `.app` 用户去辅助功能列表里勾终端（勾了也不生效）；
    /// 二是让只装了 `.app` 的用户去终端跑 `axprobe dump`（包里根本没有这个命令）。
    /// 所以「勾谁」交给 `HostEnvironment`，「怎么收集诊断」一律用界面上的按钮。
    public static func guidance(for state: PermissionState, host: HostEnvironment) -> String {
        switch state {
        case .ready:
            return "已经能驱动 ChatGPT 了，可以直接开始练习。"
        case .needsAccessibility:
            return "本应用要替你点 ChatGPT 的界面，这需要系统的辅助功能权限，现在还没拿到。"
                + "下一步：点「打开系统设置」，在「隐私与安全性 › 辅助功能」里把"
                + "\(host.accessibilityGrantee)加进列表并打开它的开关，然后回到这里点「重新检查」。"
        case .needsChatGPT:
            return "没在这台电脑上找到 ChatGPT 桌面应用，没有它就没法练。"
                + "下一步：到 openai.com/chatgpt/download 下载安装"
                + "（ChatGPT Classic 没有 live 语音，用不了），装好后回到这里点「重新检查」。"
        case .unknown:
            return "环境检查没通过，但失败原因不在已知的几种里，所以这里给不出针对性的修法。"
                + "下一步：先读下面的「检查结果原文」；若仍看不出问题，点「复制诊断信息」，"
                + "把复制到的内容发给开发者。"
        }
    }

    /// 打开「系统设置 › 隐私与安全性 › 辅助功能」。
    ///
    /// `open` 是真正干活的那一下（生产代码传 `NSWorkspace.shared.open`）。
    /// **返回值必须消费**：`NSWorkspace.open` 在 AppKit 上是 `@discardableResult`，
    /// 丢掉它编译器不会警告，而用户看到的是一个「点了没反应」的按钮。
    public static func openSettings(host: HostEnvironment,
                                    using open: (URL) -> Bool) -> ActionNotice {
        let manualPath = "系统设置 › 隐私与安全性 › 辅助功能"
        guard open(systemSettingsURL) else {
            return ActionNotice(
                text: "没能打开系统设置。下一步：手动打开「\(manualPath)」，"
                    + "把\(host.accessibilityGrantee)加进列表并打开它的开关，然后回到这里点「重新检查」。",
                isFailure: true)
        }
        // 就算系统接受了这个 URL，也不保证一定停在「辅助功能」那一栏（锚点认不认由系统定），
        // 所以成功提示里同样写清到了那儿要做什么、找哪一栏。
        return ActionNotice(
            text: "已打开系统设置。下一步：在「\(manualPath)」里把\(host.accessibilityGrantee)"
                + "加进列表并打开它的开关，然后回到这里点「重新检查」。",
            isFailure: false)
    }

    /// 把诊断信息写进剪贴板。`write` 是真正干活的那一下，返回是否写成功。
    public static func copyDiagnostics(state: PermissionState,
                                       messages: [String],
                                       host: HostEnvironment,
                                       systemVersion: String = ProcessInfo.processInfo
                                           .operatingSystemVersionString,
                                       using write: (String) -> Bool) -> ActionNotice {
        let ok = write(diagnosticsText(state: state, messages: messages,
                                       host: host, systemVersion: systemVersion))
        guard ok else {
            return ActionNotice(
                text: "没能把诊断信息写进剪贴板。下一步：直接选中下面的「检查结果原文」按 ⌘C 复制，"
                    + "连同你的系统版本一起发给开发者。",
                isFailure: true)
        }
        return ActionNotice(text: "诊断信息已复制到剪贴板，粘贴给开发者即可。", isFailure: false)
    }

    /// 一份可以直接粘给开发者的诊断信息。用户在图形界面里做得到的只有「复制粘贴」，
    /// 所以这份文本要自带排查所需的全部上下文，不能指望他再去跑命令。
    public static func diagnosticsText(state: PermissionState,
                                       messages: [String],
                                       host: HostEnvironment,
                                       systemVersion: String = ProcessInfo.processInfo
                                           .operatingSystemVersionString) -> String {
        let hostText: String
        switch host {
        case .app(let name): hostText = ".app（\(name)）"
        case .commandLine: hostText = "命令行"
        }
        var lines = [
            "IELTS Speaking Coach 环境诊断",
            "状态：\(title(for: state))",
            "宿主：\(hostText)",
            "系统：\(systemVersion)",
            "检查结果原文："
        ]
        lines += messages.isEmpty ? ["（没有任何消息——这本身就不正常，请一并说明）"]
                                  : messages.map { "- \($0)" }
        return lines.joined(separator: "\n")
    }
}
