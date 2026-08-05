import Foundation

/// 「等目标元素出现 → 再操作」的原语。
///
/// spec 2.3.2 是实测结论：按下启动语音成功后**立即**查找 Stop voice chat 会报找不到，
/// 等界面渲染完成后重试则存在。语音浮层的渲染晚于 kAXPressAction 返回。
/// 任何「按完就假设下一个元素已就位」的代码都会随机失败。
public struct AXLocator: Sendable {
    private let access: any AXAccess
    private let pollInterval: TimeInterval

    public init(access: any AXAccess, pollInterval: TimeInterval = 0.3) {
        self.access = access
        self.pollInterval = pollInterval
    }

    /// 本次等待实际使用的轮询间隔。
    /// 不钳制的话，`pollInterval` 大于 `timeout` 时实际等待由前者主导，
    /// 可远超调用方声明的超时——「禁止无限等待」就成了空话。
    private func effectiveInterval(for timeout: TimeInterval) -> TimeInterval {
        max(0.01, min(pollInterval, timeout / 2))
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

        let mismatches = ChatGPTLabels.structuralMismatches(candidates, among: lastNodes)
        if !mismatches.isEmpty {
            throw BridgeError.elementNotFound(
                "找到了标签为「\(candidates[0])」的元素 \(mismatches.count) 个，但都结构不符，"
                + "不是真正的控制按钮（很可能是侧边栏里的同名历史会话）。"
                + "下一步：确认 ChatGPT 窗口停在对话界面而不是设置或侧边栏；"
                + "若 ChatGPT 刚更新过，运行 axprobe dump 查看当前界面结构。")
        }
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到「\(candidates[0])」。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话；"
            + "若 ChatGPT 刚更新过，运行 axprobe dump 查看当前界面结构。")
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

        // 「有多个文本框、不敢猜」与「根本没有文本框」是两种完全不同的处境，
        // 处置方式也不同。报同一句通用错误，等于把 composer 那层防护浪费掉一半。
        let candidates = ChatGPTLabels.candidateComposers(among: lastNodes)
        if candidates.count > 1 {
            let described = candidates.map { "「\($0.descriptionText)」" }.joined(separator: "、")
            throw BridgeError.elementNotFound(
                "界面上有 \(candidates.count) 个文本框（\(described)），无法确定哪个是 ChatGPT 的输入框，"
                + "不敢乱猜——猜错会把考官提示词写进搜索框之类的地方，而你只会看到「什么都没发生」。"
                + "下一步：确认 ChatGPT 停在普通对话界面（不是搜索、不是重命名会话）后重试；"
                + "若 ChatGPT 刚更新过，运行 axprobe dump 把新的输入框描述报给开发者。")
        }
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到 ChatGPT 的输入框。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话，然后重试。")
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
