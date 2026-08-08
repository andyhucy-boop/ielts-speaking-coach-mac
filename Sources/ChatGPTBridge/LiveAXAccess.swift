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
    ///
    /// **不是 `private`，是为了让并发安全那条测试问得出「+1 到底加了几次」。**
    /// 快照返回的节点列表在 ChatGPT 没运行时是空的（测试环境正是如此，铁律 3），
    /// 代次因此没有别的出口；而丢掉的那几次 +1 恰恰是这个类不加锁时最要命的后果。
    private(set) var currentEpoch = 0

    /// 这三样可变状态的锁。
    ///
    /// **`@unchecked Sendable` 是一句承诺，不是一道保护。** 这个类此前把
    /// `elementMap` / `nextID` / `currentEpoch` 裸露在多线程下：`PracticeRunner`
    /// 每一步都把阻塞的 AX 调用甩到 `Task.detached` 上跑，而「我练完了」那颗按钮
    /// 挂着回车快捷键——连按两下就有两条链路同时进来。后果分两层：
    ///
    /// - `elementMap` 是 Swift 原生字典，两条线程同时改它会当场段错误
    ///   （复审用逐字复刻同一套无锁写法的替身证过：8 次运行 8 次段错误，
    ///   ThreadSanitizer 明确报数据竞争）；
    /// - `currentEpoch += 1` 不是原子操作，丢掉一次 +1 就意味着**一个本该作废的
    ///   旧引用会被当成有效的**，于是 `press` 按到新树里同编号的另一个控件上——
    ///   用户看到的是「按钮明明在，按下去没反应」，或者更糟：按到了别的东西。
    ///
    /// 重入的那一层已经由 `PracticeRunner` 的守卫堵住了，这里是第二道：
    /// 逐字稿采样器、命令行、将来任何一个并发调用点都不该再有机会踩这一脚。
    private let lock = NSLock()

    /// 「找到目标 App 的那个 AXUIElement」这一步。
    ///
    /// **做成一道可替换的接缝只为一件事**：并发安全那组测试要把这个类的可变状态
    ///（rawID 映射、代次）真真切切地跑上几千次，而开发机上 ChatGPT 十有八九正开着——
    /// 照原样跑会去遍历它的真实无障碍树（几千趟，慢得离谱，而且等于在碰真实 ChatGPT，
    /// 铁律 3）。测试换成一句「找不到目标」，走的仍然是这个类自己那几行加锁逻辑，
    /// 一行都不掺假。生产代码走的永远是下面那个默认实现。
    private let locateApp: () -> AXUIElement?

    public init() {
        self.locateApp = LiveAXAccess.runningTargetApplication
    }

    /// **仅供测试**（`internal`，不进公开 API）。见 `locateApp` 的说明。
    init(locateApp: @escaping () -> AXUIElement?) {
        self.locateApp = locateApp
    }

    // MARK: - AXAccess

    public func isTargetInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.targetBundleID) != nil
    }

    public func isTargetRunning() -> Bool {
        locateApp() != nil
    }

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityTrust() -> Bool {
        // 带 prompt 的这个变体做两件事，第二件才是关键：
        // 1. 没授权时弹出系统对话框
        // 2. **把本应用登记进「系统设置 › 隐私与安全性 › 辅助功能」那份列表**
        //
        // 只用 AXIsProcessTrusted() 的话第 2 件永远不会发生，用户在设置里根本找不到这个应用。
        // 已经拒绝过之后再调不会再弹对话框，但那时列表里已经有它了，用户能自己勾上。
        // 键名写成字面量而不是 kAXTrustedCheckOptionPrompt：后者是个全局 var，
        // Swift 6 的严格并发检查会报「not concurrency-safe because it involves shared mutable state」。
        // 字面量的值与它完全相同，且是 Apple 文档里公开的常量名，不会变。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
    ///
    /// **整趟遍历都在锁里**：中途放锁的话，另一条线程的 `snapshotTree()` 会一边清空
    /// `elementMap` 一边让这一趟往里塞，那正是段错误的现场。
    public func snapshotTree() -> [AXNodeSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        elementMap.removeAll()
        nextID = 0
        currentEpoch += 1
        guard let app = appElement() else { return [] }
        var result: [AXNodeSnapshot] = []
        walk(app, depth: 0, into: &result)
        return result
    }

    /// 「验代次」+「取元素」。**两件事必须在同一把锁里**：分开的话，两句之间来一次
    /// `snapshotTree()`，验过的代次就已经作废，取到的是新树里同编号的另一个元素。
    ///
    /// **抽成一个函数只为一件事：让代次校验本身测得到。** 它此前只以两行三元表达式
    /// 的形态活在 `press`/`setValue` 里，而唯一碰得到它的测试走的是「找不到目标 App」
    /// 那道接缝——那时 `elementMap` 恒为空，`press` 无论如何都返回 false。
    /// 于是把这两处的 `element.epoch == currentEpoch` 整个删掉，全套测试没有一条会红
    /// （本次终审实测过）。而真删掉之后，本工具会在 ChatGPT 里**按到编号相同的另一个控件**：
    /// 用户看到的是「按钮明明在，按下去没反应」，或者更糟——按到了别的东西。
    /// 现在 `LiveAXAccessEpochGuardTests` 直接问这个函数，删一个字它就红。
    func resolve(_ element: AXElementRef) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return element.epoch == currentEpoch ? elementMap[element.rawID] : nil
    }

    public func setValue(_ text: String, on element: AXElementRef) -> Bool {
        guard let axElement = resolve(element) else { return false }
        return AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    /// **注意：返回 true 不等于动作生效**，调用方必须另行验证状态变化。
    public func press(_ element: AXElementRef) -> Bool {
        guard let axElement = resolve(element) else { return false }
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

    private func appElement() -> AXUIElement? { locateApp() }

    /// 生产环境真正用的那一步：在正在运行的进程里找目标 App。
    private static func runningTargetApplication() -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == targetBundleID }) else { return nil }
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
