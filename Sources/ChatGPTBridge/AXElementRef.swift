import Foundation

/// 元素的不透明引用。真实实现里包着 AXUIElement，测试实现里就是一个整数 id。
/// 这样上层逻辑不直接接触 AXUIElement，才能在没有 ChatGPT 的情况下被测试。
public struct AXElementRef: Hashable, Sendable {
    public let rawID: Int
    public init(rawID: Int) { self.rawID = rawID }
}

/// 元素在某一时刻的属性快照。
public struct AXNodeSnapshot: Equatable, Sendable {
    public var element: AXElementRef
    public var role: String
    public var subrole: String
    public var title: String
    public var value: String
    public var descriptionText: String
    public var childCount: Int
    public var childRoles: [String]

    public init(element: AXElementRef, role: String, subrole: String = "", title: String = "",
                value: String = "", descriptionText: String = "",
                childCount: Int = 0, childRoles: [String] = []) {
        self.element = element; self.role = role; self.subrole = subrole
        self.title = title; self.value = value; self.descriptionText = descriptionText
        self.childCount = childCount; self.childRoles = childRoles
    }

    /// 标签优先取 description，为空时退到 title。ChatGPT 的控件两者都可能承载文字。
    public var label: String { descriptionText.isEmpty ? title : descriptionText }

    /// spec 2.3.1 的结构判据：真控制按钮的子节点恰好一个且为 AXImage。
    /// 侧边栏会话行嵌套 AXButton（含 Pin chat / Archive chat），不满足此条件。
    public var isIconOnlyControl: Bool { childRoles == ["AXImage"] }
}
