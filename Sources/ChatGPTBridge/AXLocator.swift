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

    public func waitForControl(_ candidates: [String], timeout: TimeInterval) throws -> AXNodeSnapshot {
        var lastNodes: [AXNodeSnapshot] = []
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            lastNodes = access.snapshotTree()
            if let hit = ChatGPTLabels.matchControl(candidates, among: lastNodes) { return hit }
            Thread.sleep(forTimeInterval: pollInterval)
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
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = ChatGPTLabels.composer(among: access.snapshotTree()) { return hit }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到 ChatGPT 的输入框。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话，然后重试。")
    }

    /// 轮询直到条件成立。用于「操作后验证状态真的变了」——
    /// kAXPressAction 返回成功不等于动作生效（spec 2.3.1）。
    public func waitUntil(_ condition: ([AXNodeSnapshot]) -> Bool, timeout: TimeInterval,
                          describing what: String) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition(access.snapshotTree()) { return }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        throw BridgeError.stateNotReached(
            "等了 \(Int(timeout)) 秒，\(what)仍未发生。"
            + "下一步：看一眼 ChatGPT 窗口当前的状态；若与预期不符，运行 axprobe dump 收集诊断信息。")
    }
}
