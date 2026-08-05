import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// `LiveAXAccess` 相关的错误。
public enum ChatGPTBridgeError: Error, Sendable {
    /// 目标应用未安装，无法启动。
    case targetNotInstalled
    /// 已尝试启动目标应用，但系统报告启动失败。
    case launchFailed
}

/// `AXAccess` 的真实实现，直接调用 AXUIElement / ApplicationServices API。
/// **本文件是全项目里唯一允许直接触碰 AXUIElement 的地方**——
/// 其余逻辑一律通过 `AXAccess` 接缝间接访问，这样才能在没有 ChatGPT 的环境下被测试。
public final class LiveAXAccess: AXAccess, @unchecked Sendable {
    /// 新版 ChatGPT.app，唯一支持 live 语音、本工具驱动的目标。
    public static let targetBundleID = "com.openai.codex"
    /// ChatGPT Classic，没有 live 语音，仅用于「装错了」的误装提示。
    public static let classicBundleID = "com.openai.chat"

    /// rawID -> 真实 AXUIElement 的映射。**每次 `snapshotTree()` 都会清空并重建**——
    /// AXUIElement 在界面重绘后会失效，缓存旧引用会操作到已经消失的元素，
    /// 症状是「按钮明明在，按下去没反应」，且极难排查。
    private var elementMap: [Int: AXUIElement] = [:]
    private var nextID = 0
    /// 当前代次。**只递增，从不重置**——`snapshotTree()` 每次调用都 +1，
    /// 并把新值盖到本次遍历产生的所有 `AXElementRef` 上。`press`/`setValue`
    /// 拒绝任何代次不匹配的引用，防止跨快照复用旧引用时静默命中新树里同编号的另一个元素。
    private var currentEpoch = 0

    public init() {}

    // MARK: - AXAccess

    public func isTargetInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.targetBundleID) != nil
    }

    public func isTargetRunning() -> Bool {
        appElement() != nil
    }

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func launchTarget() throws {
        guard !isTargetRunning() else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.targetBundleID) else {
            throw ChatGPTBridgeError.targetNotInstalled
        }
        guard NSWorkspace.shared.open(url) else {
            throw ChatGPTBridgeError.launchFailed
        }
    }

    /// 唤醒 Chromium 的惰性无障碍树。两个属性设置均返回错误码属正常现象，
    /// 判据是随后能否找到 AXWebArea —— 实测树会从约 234 节点扩展到约 675 节点。
    public func wakeAccessibilityTree(timeout: TimeInterval) -> Bool {
        guard let app = appElement() else { return false }
        for flag in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            _ = AXUIElementSetAttributeValue(app, flag as CFString, kCFBooleanTrue)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if containsWebArea(app) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return containsWebArea(app)
    }

    /// 深度优先遍历当前树，返回全部节点快照。
    /// **每次调用都清空并重建 rawID 映射，并开启新的代次**——此前取得的 `AXElementRef` 随即失效。
    public func snapshotTree() -> [AXNodeSnapshot] {
        elementMap.removeAll()
        nextID = 0
        currentEpoch += 1
        guard let app = appElement() else { return [] }
        var result: [AXNodeSnapshot] = []
        walk(app, depth: 0, into: &result)
        return result
    }

    public func setValue(_ text: String, on element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        guard let axElement = elementMap[element.rawID] else { return false }
        return AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    /// **注意：返回 true 不等于动作生效**，调用方必须另行验证状态变化。
    public func press(_ element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        guard let axElement = elementMap[element.rawID] else { return false }
        return AXUIElementPerformAction(axElement, kAXPressAction as CFString) == .success
    }

    public func sendReturnKey() -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - 内部实现

    private func appElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == Self.targetBundleID }) else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return "" }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let list = raw as? [AXUIElement] else { return [] }
        return list
    }

    /// 只判断树里是否存在 AXWebArea，不分配 rawID——供 `wakeAccessibilityTree` 轮询用，
    /// 避免每次轮询都无谓地重建 rawID 映射。
    private func containsWebArea(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 60) -> Bool {
        guard depth <= maxDepth else { return false }
        if string(element, kAXRoleAttribute as String) == "AXWebArea" { return true }
        for child in children(element) {
            if containsWebArea(child, depth: depth + 1, maxDepth: maxDepth) { return true }
        }
        return false
    }

    /// 深度优先遍历并分配 rawID。maxDepth 防止异常树导致无限递归。
    private func walk(_ element: AXUIElement, depth: Int, maxDepth: Int = 60, into result: inout [AXNodeSnapshot]) {
        guard depth <= maxDepth else { return }
        let id = nextID
        nextID += 1
        elementMap[id] = element

        let kids = children(element)
        let snapshot = AXNodeSnapshot(
            element: AXElementRef(rawID: id, epoch: currentEpoch),
            role: string(element, kAXRoleAttribute as String),
            subrole: string(element, kAXSubroleAttribute as String),
            title: string(element, kAXTitleAttribute as String),
            value: string(element, kAXValueAttribute as String),
            descriptionText: string(element, kAXDescriptionAttribute as String),
            identifier: string(element, kAXIdentifierAttribute as String),
            childCount: kids.count,
            childRoles: kids.map { string($0, kAXRoleAttribute as String) }
        )
        result.append(snapshot)

        for child in kids {
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &result)
        }
    }
}
