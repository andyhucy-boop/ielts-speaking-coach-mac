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

    /// spec 2.3.1 的结构判据：**它要挡的是「侧边栏里的同名历史会话」**。
    ///
    /// ChatGPT 每开一次语音就自动生成一条名叫 "New voice chat" 的会话挂在侧边栏，
    /// 而侧边栏在深度优先遍历里常排在真按钮前面——只按标签取第一个命中会点中历史会话，
    /// 而且 `kAXPressAction` 返回成功（spec 2.3.1，实测发生过）。
    ///
    /// 真控制按钮有**两种**形状，两种都要认：
    ///
    ///   · **图标按钮**：恰好一个 `AXImage` 子节点。
    ///     `Pin chat`、`Dictate`、`Start new voice chat` 现在都是这一种。
    ///   · **叶子按钮**：一个子节点都没有。
    ///     `New chat`、`Search`、`Recents` 现在是这一种。
    ///
    /// 而历史会话行**一定不是叶子**：它里面裹着一个 `AXGroup`，装着 `Pin chat`
    /// 与 `Chat actions`。所以「子节点为空」这一条不会把它放进来。
    ///
    /// ## 2026-08-30：只认第一种曾经把「新建会话」整个卡死
    ///
    /// 用户报障：「找到了标签为「New chat」的元素 2 个，但都结构不符」。
    /// 拿 `axprobe dump` 读当时的树（ChatGPT 26.820.60940）看到的是：
    ///
    /// ```
    /// AXButton title="New chat" children=0     ← 顶部工具条，与 Search / Switch mode 并排
    /// AXButton desc="New chat"  children=0     ← 侧边栏工具条，与 Recents 并排
    /// ```
    ///
    /// 两颗都是真按钮，只是这一版把里面那个 `AXImage` 去掉了，于是
    /// `childRoles == ["AXImage"]` 把它们双双判成「结构不符」——
    /// 而错误信息还在猜「很可能是侧边栏里的同名历史会话」，把人往错的方向指。
    ///
    /// **同一份树里那条真的历史会话仍然被挡着**（`AXButton desc="New voice chat" children=4`），
    /// 所以这次放宽没有把当初要防的那个坑放回来。`AXElementRefTests` 拿这两组
    /// 实测形状各钉了一条。
    public var isIconOnlyControl: Bool { childRoles == ["AXImage"] || childCount == 0 }

    /// 输入框是否处于「空」状态。**空态的 value 不是空字符串**（spec 2.3.6，实测）——
    /// 是「换行 + 该元素自己的 description」，例如 `"\nMessage ChatGPT"`。
    /// 这是本项目第三次栽在「验证判据与实际观测对不上」，前两次分别是
    /// 「按下返回成功但点中了别的元素」（2.3.1）和「内容≠写入值永远成立」（2.3.4）。
    /// 别处若也要判断输入框是否为空，复用这个属性，不要重新发明判据。
    public var isEmptyComposer: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == descriptionText
    }
}
