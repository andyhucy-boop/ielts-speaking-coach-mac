import Foundation

/// 「等目标元素出现 → 再操作」的原语。
///
/// spec 2.3.2 是实测结论：按下启动语音成功后**立即**查找 Stop voice chat 会报找不到，
/// 等界面渲染完成后重试则存在。语音浮层的渲染晚于 kAXPressAction 返回。
/// 任何「按完就假设下一个元素已就位」的代码都会随机失败。
public struct AXLocator: Sendable {
    private let access: any AXAccess
    private let pollInterval: TimeInterval
    /// 决定「下一步」该让用户勾选谁、该拿什么办法收集诊断信息。见 `HostEnvironment`。
    /// 与 `AXDriver` 同一个理由：只装了 `.app` 的用户手上根本没有 `axprobe` 这个命令。
    private let host: HostEnvironment

    public init(access: any AXAccess, pollInterval: TimeInterval = 0.3,
                host: HostEnvironment = .current) {
        self.access = access
        self.pollInterval = pollInterval
        self.host = host
    }

    /// 本次等待实际使用的轮询间隔。
    /// 不钳制的话，`pollInterval` 大于 `timeout` 时实际等待由前者主导，
    /// 可远超调用方声明的超时——「禁止无限等待」就成了空话。
    private func effectiveInterval(for timeout: TimeInterval) -> TimeInterval {
        max(0.01, min(pollInterval, timeout / 2))
    }

    /// 整棵树一个节点都读不到时的那句话。
    ///
    /// **这一支必须单独存在。** 没有辅助功能权限时，AX 接口对每一次调用都返回失败，
    /// 快照因此是空的——而从前这里一律报「等了 5 秒仍未找到「New chat」。下一步：确认
    /// ChatGPT 窗口可见且已打开一个会话」，把用户支去检查一个完全正确的东西，
    /// 真正的病因（权限）一个字都没提（2026-08-08 复审第 8 条）。
    ///
    /// 权限只是**最常见**的原因，不是唯一的（ChatGPT 没开、无障碍树没醒也一样读不到），
    /// 所以两条都写，按可能性排序。
    private func unreadableTreeError(lookingFor what: String) -> BridgeError {
        .elementNotFound(
            "一个界面元素都没读到（连 ChatGPT 的窗口都读不出来），所以也就找不到「\(what)」。"
            + "最常见的原因是没有拿到系统的辅助功能权限——本工具全靠它替你操作 ChatGPT，"
            + "在引导里点过「先跳过」、或者换了一台电脑，都会是这个状态。"
            + "下一步：打开「系统设置 › 隐私与安全性 › 辅助功能」，"
            + "把\(host.accessibilityGrantee)加进列表并打开它的开关，然后\(host.retryInstruction)。"
            + "开关本来就是开着的话，多半是 ChatGPT 没开着或没停在会话界面上——"
            + "把它打开、进到一个会话里再试一次；仍然不行就\(host.diagnosticsInstruction)。")
    }

    public func waitForControl(_ candidates: [String], timeout: TimeInterval) throws -> AXNodeSnapshot {
        var lastNodes: [AXNodeSnapshot] = []
        let deadline = Date().addingTimeInterval(timeout)
        let interval = effectiveInterval(for: timeout)
        repeat {
            lastNodes = access.snapshotTree()
            if let hit = ChatGPTLabels.matchControl(candidates, among: lastNodes) { return hit }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline

        // 一个节点都没读到 = 病因多半在权限，而不在「ChatGPT 窗口有没有打开会话」。
        guard !lastNodes.isEmpty else {
            throw unreadableTreeError(lookingFor: candidates[0])
        }

        let mismatches = ChatGPTLabels.structuralMismatches(candidates, among: lastNodes)
        if !mismatches.isEmpty {
            throw BridgeError.elementNotFound(
                "找到了标签为「\(candidates[0])」的元素 \(mismatches.count) 个，但都结构不符，"
                + "不是真正的控制按钮（很可能是侧边栏里的同名历史会话）。"
                + "下一步：确认 ChatGPT 窗口停在对话界面而不是设置或侧边栏；"
                + "若 ChatGPT 刚更新过，\(host.diagnosticsInstruction)。")
        }
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到「\(candidates[0])」。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话；"
            + "若 ChatGPT 刚更新过，\(host.diagnosticsInstruction)。")
    }

    public func waitForComposer(timeout: TimeInterval) throws -> AXNodeSnapshot {
        var lastNodes: [AXNodeSnapshot] = []
        let deadline = Date().addingTimeInterval(timeout)
        let interval = effectiveInterval(for: timeout)
        repeat {
            lastNodes = access.snapshotTree()
            if let hit = ChatGPTLabels.composer(among: lastNodes) { return hit }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline

        guard !lastNodes.isEmpty else {
            throw unreadableTreeError(lookingFor: "ChatGPT 的输入框")
        }

        // 「有多个文本框、不敢猜」与「根本没有文本框」是两种完全不同的处境，
        // 处置方式也不同。报同一句通用错误，等于把 composer 那层防护浪费掉一半。
        let candidates = ChatGPTLabels.candidateComposers(among: lastNodes)
        if candidates.count > 1 {
            let described = candidates.map { "「\($0.descriptionText)」" }.joined(separator: "、")
            throw BridgeError.elementNotFound(
                "界面上有 \(candidates.count) 个文本框（\(described)），无法确定哪个是 ChatGPT 的输入框，"
                + "不敢乱猜——猜错会把考官提示词写进搜索框之类的地方，而你只会看到「什么都没发生」。"
                + "下一步：确认 ChatGPT 停在普通对话界面（不是搜索、不是重命名会话）后重试；"
                + "若 ChatGPT 刚更新过，\(host.diagnosticsInstruction)，"
                + "把上面这几个输入框的描述一并报给开发者。")
        }
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到 ChatGPT 的输入框。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话，然后重试。")
    }

    /// 轮询直到 `matching` 从树里挑出目标节点，返回该节点；超时返回 nil。
    ///
    /// 用于「通用查找会命中错误目标」的场景——例如语音输入框：语音已经启动后仍有约 3 秒
    /// 窗口，界面上摆的还是普通输入框，`waitForComposer` 见到它就会满足；必须换一个
    /// 只认目标节点本身的谓词持续轮询，才不会在这个窗口里提前返回。不复用 `waitForControl`/
    /// `waitForComposer` 的专用错误信息，是因为不同调用方对「没找到」要给出的下一步指引不同，
    /// 由调用方自己根据 nil 结果拼错误更合适。
    public func waitForNode(matching: ([AXNodeSnapshot]) -> AXNodeSnapshot?,
                            timeout: TimeInterval) -> AXNodeSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        let interval = effectiveInterval(for: timeout)
        repeat {
            if let hit = matching(access.snapshotTree()) { return hit }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline
        return nil
    }

    /// 轮询直到条件成立。用于「操作后验证状态真的变了」——
    /// kAXPressAction 返回成功不等于动作生效（spec 2.3.1）。
    public func waitUntil(_ condition: ([AXNodeSnapshot]) -> Bool, timeout: TimeInterval,
                          describing what: String) throws {
        let deadline = Date().addingTimeInterval(timeout)
        let interval = effectiveInterval(for: timeout)
        repeat {
            if condition(access.snapshotTree()) { return }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline
        throw BridgeError.stateNotReached(
            "等了 \(Int(timeout)) 秒，\(what)仍未发生。这通常意味着刚才那一下点击虽然返回成功，"
            + "但 ChatGPT 并没有真的响应。"
            + "下一步：切到 ChatGPT 窗口看看它现在是什么状态——如果界面和你预期的不一样，"
            + "手动把它调整到正确状态后重新开始；如果 ChatGPT 最近更新过，"
            + "它的界面可能变了，请把这条错误告诉开发者。")
    }
}
