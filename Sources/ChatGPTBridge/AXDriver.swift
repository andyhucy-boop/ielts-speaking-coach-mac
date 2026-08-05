import Foundation

public final class AXDriver: CoachBridge {
    private let access: any AXAccess
    private let locator: AXLocator
    private let shortTimeout: TimeInterval
    private let stateTimeout: TimeInterval

    public init(access: any AXAccess, locator: AXLocator,
                shortTimeout: TimeInterval = 5.0, stateTimeout: TimeInterval = 8.0) {
        self.access = access; self.locator = locator
        self.shortTimeout = shortTimeout; self.stateTimeout = stateTimeout
    }

    public func preflight() -> BridgeReadiness {
        var messages: [String] = []
        var ok = true
        if !access.isTargetInstalled() {
            messages.append("❌ 没找到 ChatGPT（新版桌面应用）。"
                + "下一步：从 openai.com/chatgpt/download 安装。注意 ChatGPT Classic 没有 live 语音，不能用。")
            ok = false
        }
        if !access.isAccessibilityTrusted() {
            messages.append("❌ 没有辅助功能权限，无法驱动 ChatGPT。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把运行本工具的终端加进去并勾选，然后重跑。")
            ok = false
        }
        guard ok else { return BridgeReadiness(ok: false, messages: messages) }

        if !access.isTargetRunning() {
            try? access.launchTarget()
        }
        if !access.wakeAccessibilityTree(timeout: 8.0) {
            messages.append("⚠️ ChatGPT 的无障碍树没能唤醒，可能读不到对话内容。"
                + "下一步：把 ChatGPT 窗口切到前台并打开一个会话，然后重跑；仍失败请运行 axprobe dump 收集诊断信息。")
        }
        messages.append("✅ 环境就绪")
        return BridgeReadiness(ok: true, messages: messages)
    }

    public func sendText(_ text: String) throws {
        let composer = try locator.waitForComposer(timeout: shortTimeout)
        guard access.setValue(text, on: composer.element) else {
            throw BridgeError.actionFailed("写入 ChatGPT 输入框失败。"
                + "下一步：确认 ChatGPT 窗口没有被弹窗挡住，然后重试。")
        }
        guard access.sendReturnKey() else {
            throw BridgeError.actionFailed("文字已写入输入框但没能发送。"
                + "下一步：切到 ChatGPT 窗口手动按一下回车。")
        }
    }

    public func startVoice() throws {
        let button = try locator.waitForControl(ChatGPTLabels.startVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下语音按钮失败。"
                + "下一步：确认 ChatGPT 窗口在前台，然后重试。")
        }
        // kAXPressAction 返回成功不等于动作生效（spec 2.3.1），必须验证状态真的变了
        try locator.waitUntil({ ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话开始")
    }

    public func isVoiceActive() -> Bool { ChatGPTLabels.isVoiceActive(access.snapshotTree()) }

    public func endVoice() throws {
        let button = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下结束语音按钮失败。"
                + "下一步：切到 ChatGPT 窗口手动结束通话。")
        }
        try locator.waitUntil({ !ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话结束")
    }

    /// 读回最新的助手消息。取 AXStaticText 里最长的一条——
    /// 复盘 JSON 远长于界面上任何其他文字，这个启发式在实测中稳定。
    public func captureLatestAssistantMessage() throws -> String {
        let texts = access.snapshotTree()
            .filter { $0.role == "AXStaticText" }
            .map(\.value)
            .filter { $0.count >= 40 }
        guard let longest = texts.max(by: { $0.count < $1.count }) else {
            throw BridgeError.elementNotFound(
                "没能从 ChatGPT 窗口读到足够长的文字，复盘可能还没生成完。"
                + "下一步：等 ChatGPT 输出完再重试；若已经输出完，请在 ChatGPT 里选中复盘全文按 ⌘C，"
                + "然后用 coach practice --from-clipboard 继续。")
        }
        return longest
    }
}
