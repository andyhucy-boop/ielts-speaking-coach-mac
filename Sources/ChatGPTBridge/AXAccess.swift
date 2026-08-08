import Foundation

/// 原始 Accessibility 调用的接缝。**唯一目的是可测性** ——
/// 有了它，AXDriver 里那些「结构筛选、等待重试、操作后验证、降级」的逻辑
/// 才能在没有 ChatGPT 的环境下被测试。
public protocol AXAccess: Sendable {
    /// 目标应用是否已安装
    func isTargetInstalled() -> Bool
    /// 目标应用是否正在运行
    func isTargetRunning() -> Bool
    /// 是否已获得辅助功能权限
    func isAccessibilityTrusted() -> Bool
    /// 向系统申请辅助功能权限，返回申请后是否已获授权。
    ///
    /// **这不只是弹个对话框——它是让本应用出现在「系统设置 › 隐私与安全性 › 辅助功能」
    /// 那份列表里的唯一办法。** 只调 `isAccessibilityTrusted()`（被动查询）的话，
    /// 系统永远不会把这个应用登记进那份列表，用户去设置里翻遍了也找不到它，
    /// 只能自己点「+」去文件系统里找 `.app` ——而它在 `.build/` 下，Finder 默认隐藏。
    ///
    /// 2026-08-08 实测：用户第一次装好就卡在这儿，报「系统中没搜到这个软件」。
    /// 1859 条测试全绿，产品的第一步却走不通——这是真机验收才发现得了的那一类。
    ///
    /// 系统对同一个应用身份**只会弹一次**。已经拒绝过之后再调不会再弹，
    /// 那时唯一的出路是去系统设置里手动勾（此时列表里已经有它了）。
    func requestAccessibilityTrust() -> Bool
    /// 启动目标应用（已在运行则无操作）
    func launchTarget() throws
    /// 唤醒 Chromium 的惰性无障碍树。返回是否观察到 AXWebArea。
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool
    /// 深度优先遍历当前树，返回全部节点快照。
    /// **每次调用都会开启新的代次，此前取得的 `AXElementRef` 随即失效。**
    func snapshotTree() -> [AXNodeSnapshot]
    /// 设置元素的 kAXValueAttribute。返回是否成功。
    /// **元素来自过期代次时必须返回 false，不得操作任何元素。**
    func setValue(_ text: String, on element: AXElementRef) -> Bool
    /// 对元素执行 kAXPressAction。返回是否成功。
    /// **注意：返回 true 不等于动作生效**（spec 2.3.1），调用方必须另行验证状态变化。
    /// **元素来自过期代次时必须返回 false，不得操作任何元素。**
    func press(_ element: AXElementRef) -> Bool
    /// 向目标应用发送回车键
    func sendReturnKey() -> Bool
}
