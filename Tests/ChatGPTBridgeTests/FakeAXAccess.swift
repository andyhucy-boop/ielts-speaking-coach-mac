import Foundation
@testable import ChatGPTBridge

/// 可编程的假 AX 环境。测试通过设置 `nodes` 来摆出任意元素树，
/// 通过 `onPress` / `onSetValue` 注入「按下之后树会怎么变」的行为。
final class FakeAXAccess: AXAccess, @unchecked Sendable {
    var installed = true
    var running = true
    var trusted = true
    var wakeSucceeds = true
    var nodes: [AXNodeSnapshot] = []

    private(set) var pressedElements: [AXElementRef] = []
    private(set) var setValues: [(AXElementRef, String)] = []
    private(set) var returnKeyCount = 0
    private(set) var snapshotCount = 0
    /// 当前代次。镜像 `LiveAXAccess` 的行为：每次 `snapshotTree()` 递增，并把新值
    /// 盖印到 `nodes` 里所有元素的 `AXElementRef` 上；`press`/`setValue` 拒绝代次
    /// 不匹配的引用。测试里手写的 `AXElementRef` 字面量代次值会在这里被覆盖——
    /// 唯一权威的代次来源是这个计数器，不是调用方传入的字面量。
    private var currentEpoch = 0

    /// 按下某元素后对树做的变更。用于模拟「按下启动语音 → Voice chat active 出现」。
    var onPress: ((AXElementRef, inout [AXNodeSnapshot]) -> Void)?
    var pressSucceeds = true

    func isTargetInstalled() -> Bool { installed }
    func isTargetRunning() -> Bool { running }
    func isAccessibilityTrusted() -> Bool { trusted }
    func launchTarget() throws { running = true }
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool { wakeSucceeds }
    func snapshotTree() -> [AXNodeSnapshot] {
        snapshotCount += 1
        currentEpoch += 1
        nodes = nodes.map { node in
            var stamped = node
            stamped.element = AXElementRef(rawID: node.element.rawID, epoch: currentEpoch)
            return stamped
        }
        return nodes
    }
    func setValue(_ text: String, on element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        setValues.append((element, text)); return true
    }
    func press(_ element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        pressedElements.append(element)
        guard pressSucceeds else { return false }
        onPress?(element, &nodes)
        return true
    }
    func sendReturnKey() -> Bool { returnKeyCount += 1; return true }
}
