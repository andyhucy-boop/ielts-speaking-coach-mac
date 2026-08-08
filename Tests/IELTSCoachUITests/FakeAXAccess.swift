import ChatGPTBridge
import Foundation

/// 只为一件事存在：让 `AXDriver.preflight()` 的**真实输出**流过
/// `PermissionStatus.evaluate`，把消息的生产者和消费者绑在一起。
///
/// 为什么必须这样绑：`evaluate` 靠子串「没找到 ChatGPT」「辅助功能」认消息，而这两个词
/// 是写死在 `AXDriver` 里的文案。只用手写字符串的测试，看不见「有人改了 AXDriver 的措辞、
/// evaluate 悄悄退化成 .unknown」这次退化——界面会从「去 openai.com 下载」变成
/// 「失败原因不在已知的几种里」，而测试全绿。
///
/// 两个开关（installed / trusted）就够覆盖首次启动会遇到的四种组合，其余方法返回默认值。
/// **不与 `ChatGPTBridgeTests` 里的同名类共用**——那是另一个测试 target 的内部类型，跨
/// target 取不到；重复这二十行，比把测试装置搬进产品代码划算。
/// 全程不接触真实 ChatGPT（铁律 5）。
final class FakeAXAccess: AXAccess, @unchecked Sendable {
    var installed = true
    var trusted = true

    func isTargetInstalled() -> Bool { installed }
    func isTargetRunning() -> Bool { true }
    func isAccessibilityTrusted() -> Bool { trusted }
    /// 记下被调过几次——「申请权限」按钮点了到底有没有真的去申请，靠这个断言。
    private(set) var trustRequests = 0
    func requestAccessibilityTrust() -> Bool { trustRequests += 1; return trusted }
    func launchTarget() throws {}
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool { true }
    func snapshotTree() -> [AXNodeSnapshot] { [] }
    func setValue(_ text: String, on element: AXElementRef) -> Bool { false }
    func press(_ element: AXElementRef) -> Bool { false }
    func sendReturnKey() -> Bool { false }
}
