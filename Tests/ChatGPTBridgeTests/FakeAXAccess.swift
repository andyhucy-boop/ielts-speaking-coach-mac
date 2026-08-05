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

    /// 按下某元素后对树做的变更。用于模拟「按下启动语音 → Voice chat active 出现」。
    var onPress: ((AXElementRef, inout [AXNodeSnapshot]) -> Void)?
    var pressSucceeds = true

    func isTargetInstalled() -> Bool { installed }
    func isTargetRunning() -> Bool { running }
    func isAccessibilityTrusted() -> Bool { trusted }
    func launchTarget() throws { running = true }
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool { wakeSucceeds }
    func snapshotTree() -> [AXNodeSnapshot] { snapshotCount += 1; return nodes }
    func setValue(_ text: String, on element: AXElementRef) -> Bool {
        setValues.append((element, text)); return true
    }
    func press(_ element: AXElementRef) -> Bool {
        pressedElements.append(element)
        guard pressSucceeds else { return false }
        onPress?(element, &nodes)
        return true
    }
    func sendReturnKey() -> Bool { returnKeyCount += 1; return true }
}
