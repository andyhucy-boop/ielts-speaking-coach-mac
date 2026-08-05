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
            do { try access.launchTarget() } catch {
                messages.append("❌ 没能启动 ChatGPT：\(error.localizedDescription)。"
                    + "下一步：手动打开 ChatGPT 并进入一个会话，然后重试。")
                return BridgeReadiness(ok: false, messages: messages)
            }
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
        // 实测模拟回车不会发送——文字会原样留在输入框里，必须按 Send 按钮。
        let sendButton = try locator.waitForControl(ChatGPTLabels.sendMessage, timeout: shortTimeout)
        guard access.press(sendButton.element) else {
            throw BridgeError.actionFailed("按下发送按钮失败。"
                + "下一步：确认 ChatGPT 窗口没有被弹窗挡住，然后重试。")
        }
        // 操作后验证。kAXPressAction 返回 true 不代表 ChatGPT 真收到了——按钮被禁用、
        // 焦点跑掉时它也可能返回 true。而这条路径失败被当成成功的后果特别严重：
        // 考官提示词没发出去，语音却正常启动，ChatGPT 就是个普通聊天机器人，
        // 用户要练完一整场、等复盘出来是一团乱麻才发现不对。
        //
        // 判据必须是「输入框空了」，不能是「内容和我写的不一样」——
        // AX 读回的值与写入值不可能逐字节相同（换行与空白会被规范化），
        // 后者一开始就成立，等于没验证。这是本项目第二次栽在
        // 「验证只问现在是不是目标态、没问到底变没变」上。
        try locator.waitUntil({ nodes in
            guard let composer = ChatGPTLabels.composer(among: nodes) else { return false }
            return composer.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, timeout: shortTimeout, describing: "提示词发送到 ChatGPT")
    }

    public func startVoice() throws {
        // 前置校验，防的是「验证没区分『变成了』和『本来就是』」这个陷阱：
        // 语音已经在跑时按「启动」，ChatGPT 多半什么都不做，而下面的
        // waitUntil(isVoiceActive) 会立刻通过——我们以为启动成功了，实际上用户是
        // 接着上一场没结束的通话在练，本次的考官提示词（可能是不同的 Part、
        // 不同的反馈模式）完全没生效，而 App 显示一切正常。
        guard !isVoiceActive() else {
            throw BridgeError.stateNotReached(
                "ChatGPT 里已经有一场语音通话在进行中，不能再开一场。"
                + "下一步：先在 ChatGPT 窗口里结束当前通话，再重新开始练习。")
        }
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

    /// 等 ChatGPT 把上一条消息回复完。
    ///
    /// 判据：界面上出现了一段足够长的新文本，且在连续两次采样间**不再增长**
    /// （流式输出结束）。用户实测确认必须等它回复完再进语音，否则语音会话
    /// 可能不带考官设定就开始了 —— 这一点从 AX 树上看不出来。
    public func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int = 60) throws {
        var previousLongest = 0
        var stableTicks = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let longest = access.snapshotTree()
                .filter { $0.role == "AXStaticText" }
                .map(\.value.count).max() ?? 0
            if longest >= minimumLength && longest == previousLongest {
                stableTicks += 1
                if stableTicks >= 3 { return }
            } else {
                stableTicks = 0
            }
            previousLongest = longest
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw BridgeError.stateNotReached(
            "等了 \(Int(timeout)) 秒，ChatGPT 还没把考官指令回复完。"
            + "下一步：切到 ChatGPT 窗口看看它是不是还在输出；"
            + "如果它已经回复完了，说明本工具的判断有误，请把这条错误告诉开发者。")
    }

    public func endVoice() throws {
        // 同样是前置校验：没有通话在跑时「结束通话」若被当成成功，
        // 会掩盖「我们对语音状态的判断本来就错了」这件事。
        guard isVoiceActive() else {
            throw BridgeError.stateNotReached(
                "ChatGPT 里没有正在进行的语音通话，无从结束。"
                + "下一步：看一眼 ChatGPT 窗口确认通话是否已经结束；若已结束，直接继续取复盘即可。")
        }
        let button = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下结束语音按钮失败。"
                + "下一步：切到 ChatGPT 窗口手动结束通话。")
        }
        try locator.waitUntil({ !ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话结束")
    }

    /// 读回复盘。`expectedMarker` 给出时**必须**命中它——
    /// 只挑「最长的文本」是个假阳性温床：用户自己粘贴过的长文、更早轮次残留在树上的消息、
    /// 设置面板里的长段说明，都可能比真复盘更长。取错的后果是存进档案的「复盘」根本不是复盘，
    /// 而解析器只检查有没有那几个字段，很可能不报错。
    public func captureLatestAssistantMessage(expectedMarker: String? = nil) throws -> String {
        let allTexts = access.snapshotTree()
            .filter { $0.role == "AXStaticText" }
            .map(\.value)

        if let marker = expectedMarker {
            let matching = allTexts.filter { $0.contains(marker) }
            guard let best = matching.max(by: { $0.count < $1.count }) else {
                throw BridgeError.elementNotFound(
                    "在 ChatGPT 窗口里没找到带本次标记的复盘，它可能还没输出完、或者没按要求的格式输出。"
                    + "下一步：等它输出完再重试；若已经输出完但格式不对，"
                    + "在 ChatGPT 里选中整段复盘按 ⌘C，然后按提示继续。")
            }
            return best
        }

        // 未给标记时退回旧行为（原有的 ≥40 字符取最长），保持既有测试不变
        let texts = allTexts.filter { $0.count >= 40 }
        guard let longest = texts.max(by: { $0.count < $1.count }) else {
            throw BridgeError.elementNotFound(
                "没能从 ChatGPT 窗口读到足够长的文字，复盘可能还没生成完。"
                + "下一步：等 ChatGPT 输出完再重试；若已经输出完，请在 ChatGPT 里选中复盘全文按 ⌘C，"
                + "然后用 coach practice --from-clipboard 继续。")
        }
        return longest
    }
}
