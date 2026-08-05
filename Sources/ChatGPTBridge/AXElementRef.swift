import Foundation

/// 元素的不透明引用。真实实现里包着 AXUIElement，测试实现里就是一个整数 id。
/// 这样上层逻辑不直接接触 AXUIElement，才能在没有 ChatGPT 的情况下被测试。
public struct AXElementRef: Hashable, Sendable {
    public let rawID: Int
    /// 快照代次，每次 `snapshotTree()` 递增。
    ///
    /// **不能省。** rawID 每次快照都从 0 重新编号，若不校验代次，跨快照复用旧引用时
    /// `press`/`setValue` 不会安全失败，而会**静默命中新树里编号相同的另一个元素** ——
    /// 比「找不到」危险得多。而 AXLocator/AXDriver 的核心就是轮询（反复取快照），
    /// 「拿到元素 → 等某个状态 → 按下它」是极自然的写法，正好会踩中。
    public let epoch: Int
    public init(rawID: Int, epoch: Int) { self.rawID = rawID; self.epoch = epoch }
}

/// 元素在某一时刻的属性快照。
public struct AXNodeSnapshot: Equatable, Sendable {
    public var element: AXElementRef
    public var role: String
    public var subrole: String
    public var title: String
    public var value: String
    public var descriptionText: String
    /// kAXIdentifierAttribute。**不能省** —— axprobe dump 靠它区分元素，
    /// 实测 640 个节点里有 152 个（24%）带这个属性。ChatGPT 改版后做取证对比时，
    /// 标签本身会变（已见过三种语音按钮标签），identifier 是少数相对稳定的线索。
    public var identifier: String
    public var childCount: Int
    public var childRoles: [String]

    public init(element: AXElementRef, role: String, subrole: String = "", title: String = "",
                value: String = "", descriptionText: String = "", identifier: String = "",
                childCount: Int = 0, childRoles: [String] = []) {
        self.element = element; self.role = role; self.subrole = subrole
        self.title = title; self.value = value; self.descriptionText = descriptionText
        self.identifier = identifier
        self.childCount = childCount; self.childRoles = childRoles
    }

    /// 标签优先取 description，为空时退到 title。ChatGPT 的控件两者都可能承载文字。
    public var label: String { descriptionText.isEmpty ? title : descriptionText }

    /// spec 2.3.1 的结构判据：真控制按钮的子节点恰好一个且为 AXImage。
    /// 侧边栏会话行嵌套 AXButton（含 Pin chat / Archive chat），不满足此条件。
    public var isIconOnlyControl: Bool { childRoles == ["AXImage"] }
}
