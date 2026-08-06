import ChatGPTBridge
import Foundation

/// **`CaseIterable` 不是顺手加的**：权限页上的每一句话（标题、引导语、重查反馈）
/// 都是按状态分叉的 `switch`，而分叉出来的文案没有任何编译期约束——
/// 少写一档、两档写反，编译器都不会吭声。测试要问出「每一档都说对了吗」，
/// 就得能把所有档位数一遍；手写数组的话，新加一个状态它自己不会长出来。
public enum PermissionState: Equatable, Sendable, CaseIterable {
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
    ///
    /// **每一档说的必须是那一档真正缺的东西。** 这四句是权限页最上面那行字，
    /// 也是用户唯一一眼就会读完的那句：把 `.needsAccessibility` 和 `.needsChatGPT`
    /// 的标题对调（复制粘贴时最常见的错），装了 ChatGPT 只是没给权限的用户
    /// 会看到「还没装 ChatGPT」，跑去重装一遍应用——而真正卡住他的开关一直没动。
    /// `PermissionStatusTests` 里那组标题断言就是冲着这次对调来的。
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

    /// 用户点完「重新检查」之后要显示的那句话。**`nil` 表示这一刻不该说话。**
    ///
    /// 为什么必须有：重查的结论和上一次一样时（授权没生效、TCC 还没刷新、勾错了对象），
    /// `state` 和 `permissionMessages` 都不变，**页面不会有任何一个像素变化**——
    /// 用户分不清是「查过了还是不行」还是「按钮坏了」。而这一页上按得最多的正是这颗按钮：
    /// 去系统设置勾完开关回来，第一件事就是按它。
    /// 同一屏上「打开系统设置」连「点了没反应」都当成必须修的缺陷（见 `openSettings`），
    /// 最关键的这颗反而没有反馈，说不过去。
    ///
    /// - Parameters:
    ///   - completedAttempts: 已经**跑完**的重查次数（`AppState.recheckAttempts`）。
    ///     0 表示用户还没点过——这时先摆一句「仍未通过」，是还没查就下的结论。
    ///     次数要露出来：连按两次而文案一字不差的话，第二次又变回「点了没反应」。
    ///   - state: 这一次查出来的结论。`.ready` 返回 nil——那一刻整页会被主界面换掉，
    ///     换屏本身就是最强的反馈，再挂一句话只会在切换的瞬间闪一下。
    public static func recheckNotice(completedAttempts: Int,
                                     state: PermissionState,
                                     host: HostEnvironment) -> ActionNotice? {
        guard completedAttempts > 0 else { return nil }
        guard let outcome = stillFailing(state, host: host) else { return nil }
        let attempt = completedAttempts > 1 ? "（第 \(completedAttempts) 次）" : ""
        return ActionNotice(
            text: "已重新检查\(attempt)，仍未通过：\(outcome.cause)。下一步：\(outcome.next)",
            isFailure: true)
    }

    /// 重查之后仍然没过时的「卡在哪儿 + 换个做法做什么」。
    ///
    /// **下一步不能把上面那段 `guidance` 原样再说一遍**：用户就是照着它做完才回来点的按钮，
    /// 重复一遍等于没说。所以这里给的是「照做了却仍然不行」时才用得上的那一条
    /// （勾错了对象、开关刚打开系统还没放行、装成了 ChatGPT Classic）。
    ///
    /// 每一句「下一步」照样按宿主分叉：`.app` 用户手上没有 `axprobe`，
    /// 也不该被支去勾终端——这个坑本项目已经踩过一次。
    private static func stillFailing(_ state: PermissionState,
                                     host: HostEnvironment) -> (cause: String, next: String)? {
        switch state {
        case .ready:
            return nil
        case .needsAccessibility:
            return ("还是没有拿到辅助功能权限",
                    "确认「隐私与安全性 › 辅助功能」列表里勾的是\(host.accessibilityGrantee)、"
                        + "而且它的开关是打开的；开关刚打开时，系统对已经在运行的程序不一定马上放行，"
                        + "把它完全退出再重新打开一次通常就好了。还是不行就\(host.diagnosticsInstruction)。")
        case .needsChatGPT:
            return ("还是没找到 ChatGPT 桌面应用",
                    "确认装的是 openai.com/chatgpt/download 上的那个桌面应用、并且已经拖进"
                        + "「应用程序」文件夹（ChatGPT Classic 没有 live 语音，用不了）；"
                        + "装好后先手动打开它一次，再\(host.retryInstruction)。")
        case .unknown:
            return ("环境检查还是没通过，失败原因也不在已知的几种里",
                    "\(host.diagnosticsInstruction)，并说明你刚才做过哪些操作；"
                        + "下面的「检查结果原文」是同一份内容，也可以自己先读一遍。")
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
