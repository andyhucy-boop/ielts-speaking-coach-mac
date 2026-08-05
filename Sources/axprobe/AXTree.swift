import AppKit
import ApplicationServices
import Foundation

struct AXNode {
    var role: String
    var subrole: String
    var title: String
    var value: String
    var descriptionText: String
    var identifier: String
    var frame: String
    var depth: Int
    var childCount: Int
}

enum AXTree {
    static func appElement(bundleID: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return "" }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let list = raw as? [AXUIElement] else { return [] }
        return list
    }

    static func node(_ element: AXUIElement, depth: Int) -> AXNode {
        AXNode(
            role: string(element, kAXRoleAttribute as String),
            subrole: string(element, kAXSubroleAttribute as String),
            title: string(element, kAXTitleAttribute as String),
            value: string(element, kAXValueAttribute as String),
            descriptionText: string(element, kAXDescriptionAttribute as String),
            identifier: string(element, kAXIdentifierAttribute as String),
            frame: string(element, "AXFrame"),
            depth: depth,
            childCount: children(element).count
        )
    }

    /// 深度优先遍历。maxDepth 防止无限递归。
    static func walk(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 60,
                     visit: (AXNode, AXUIElement) -> Void) {
        guard depth <= maxDepth else { return }
        visit(node(element, depth: depth), element)
        for child in children(element) {
            walk(child, depth: depth + 1, maxDepth: maxDepth, visit: visit)
        }
    }

    /// 找输入框：优先 AXTextArea / AXTextField，其次任何带 value 的可编辑元素。
    static func findComposerText(bundleID: String = Doctor.targetBundleID) -> String? {
        guard let app = appElement(bundleID: bundleID) else { return nil }
        var best: String?
        walk(app) { node, _ in
            guard best == nil else { return }
            if node.role == "AXTextArea" || node.role == "AXTextField" {
                best = node.value
            }
        }
        return best
    }
}

extension AXTree {
    /// 唤醒 Chromium 的惰性无障碍树。两个属性设置均返回错误码属正常现象，
    /// 判据是随后能否找到 AXWebArea —— 实测树会从约 234 节点扩展到约 675 节点。
    static func wake(_ app: AXUIElement, timeout: TimeInterval = 8.0) {
        for flag in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            _ = AXUIElementSetAttributeValue(app, flag as CFString, kCFBooleanTrue)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var found = false
            walk(app) { node, _ in if node.role == "AXWebArea" { found = true } }
            if found { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// 按 role 与（可选的）description 找第一个匹配元素。
    static func findElement(role: String, description: String?,
                            bundleID: String = Doctor.targetBundleID) -> AXUIElement? {
        guard let app = appElement(bundleID: bundleID) else { return nil }
        var result: AXUIElement?
        walk(app) { node, element in
            guard result == nil, node.role == role else { return }
            if let want = description, node.descriptionText != want { return }
            result = element
        }
        return result
    }

    /// 判断元素是否为"纯图标控制按钮"结构：唯一子节点、且该子节点 role 为 AXImage。
    /// 背景：真正的语音开关一类控制按钮长这样；而侧边栏会话行、列表项等即使
    /// description 恰好撞名，结构上也不会是这个形状（比如内部还嵌套着
    /// "Pin chat"/"Archive chat" 等子按钮）。用结构而不是文字来判定，
    /// 可以避免把同名的历史记录条目误当成控制按钮按下去。
    static func isIconOnlyControl(_ element: AXUIElement) -> Bool {
        let kids = children(element)
        return kids.count == 1 && string(kids[0], kAXRoleAttribute as String) == "AXImage"
    }

    /// 返回元素直接子节点的 role 列表，供诊断信息使用。
    static func childRoles(_ element: AXUIElement) -> [String] {
        children(element).map { string($0, kAXRoleAttribute as String) }
    }
}
