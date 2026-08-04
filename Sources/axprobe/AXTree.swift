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
