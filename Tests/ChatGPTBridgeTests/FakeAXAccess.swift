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
    /// `wakeAccessibilityTree(timeout:)` 每次被要求等多久。
    ///
    /// 为什么要记下来：这个超时是 `preflight()` 里唯一一个**没有从构造函数注入**的等待值
    /// （写死的 8.0 秒）。假环境里它立刻返回，所以「谁把它偷偷改小」在耗时上一点痕迹都没有，
    /// 只有真机上才会表现为「无障碍树还没醒就说读不到对话内容」。记下实参，
    /// 才能让 `testPreflightWakesTheAccessibilityTreeWithTheMeasuredTimeout` 有东西可断言。
    private(set) var wakeTimeouts: [TimeInterval] = []
    /// 当前代次。镜像 `LiveAXAccess` 的行为：每次 `snapshotTree()` 递增，并把新值
    /// 盖印到 `nodes` 里所有元素的 `AXElementRef` 上；`press`/`setValue` 拒绝代次
    /// 不匹配的引用。测试里手写的 `AXElementRef` 字面量代次值会在这里被覆盖——
    /// 唯一权威的代次来源是这个计数器，不是调用方传入的字面量。
    private var currentEpoch = 0

    /// 按下某元素后对树做的变更。用于模拟「按下启动语音 → Voice chat active 出现」。
    var onPress: ((AXElementRef, inout [AXNodeSnapshot]) -> Void)?
    var pressSucceeds = true

    /// 发送回车后对树做的变更。用于模拟「ChatGPT 真收到了 → 输入框被清空」。
    /// **默认什么都不做**——setValue 写进composer 的文字会原样留在那里，这正是
    /// 「回车没生效」该有的默认状态。需要模拟"发送成功"的测试必须显式设置这个钩子，
    /// 不能让"自动清空"成为默认行为，否则「操作后验证」这条防线在测试里永远测不出东西。
    var onSendReturnKey: ((inout [AXNodeSnapshot]) -> Void)?

    /// 每次 `snapshotTree()` 取树**之前**执行，参数是本次取树的序号（从 1 开始）。
    /// 用来模拟「界面随一次次采样而变化」——例如 ChatGPT 流式输出时越来越长的回复。
    ///
    /// 为什么按采样序号而不是按墙上时钟（`asyncAfter`）：被测代码的判据是
    /// 「连续几次采样之间变没变」，按时钟摆状态的话，慢机器上同一段中间态会被多采几次，
    /// 正确实现反而会提前认定「不再增长」而返回——测试时红时绿，且红的是对的实现。
    /// 按序号摆状态则与机器快慢无关，每次跑的执行路径完全一样。
    var onSnapshot: ((Int, inout [AXNodeSnapshot]) -> Void)?

    func isTargetInstalled() -> Bool { installed }
    func isTargetRunning() -> Bool { running }
    func isAccessibilityTrusted() -> Bool { trusted }
    func launchTarget() throws { running = true }
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool {
        wakeTimeouts.append(timeout)
        return wakeSucceeds
    }
    func snapshotTree() -> [AXNodeSnapshot] {
        snapshotCount += 1
        onSnapshot?(snapshotCount, &nodes)
        currentEpoch += 1
        nodes = nodes.map { node in
            var stamped = node
            stamped.element = AXElementRef(rawID: node.element.rawID, epoch: currentEpoch)
            return stamped
        }
        return nodes
    }
    func setValue(_ text: String, on element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        setValues.append((element, text))
        // 真的把文字写进对应节点——这样「发送后验证输入框是否变了」才有东西可验证。
        // 之前这里只记录不改状态，composer 的 value 永远是初始的 ""，会让新增的
        // 操作后验证变成一句永远为真的死代码。
        if let idx = nodes.firstIndex(where: { $0.element.rawID == element.rawID }) {
            nodes[idx].value = text
        }
        return true
    }
    func press(_ element: AXElementRef) -> Bool {
        guard element.epoch == currentEpoch else { return false }
        pressedElements.append(element)
        guard pressSucceeds else { return false }
        onPress?(element, &nodes)
        return true
    }
    func sendReturnKey() -> Bool {
        returnKeyCount += 1
        onSendReturnKey?(&nodes)
        return true
    }
}

/// 可编程的假剪贴板，供 ClipboardFallbackTests / AXDriverTests 使用。
///
/// 从 struct 换成 class：`clear()` 需要真的改掉内容，并且这个改动要能被调用方
/// （`copyLatestAssistantMessage` 拿到的是 `any PasteboardAccess`）后续的 `readString()`
/// 感知到。struct 是值语义，函数参数拿到的只是一份拷贝，在其内部调用再多 mutating
/// 方法也不会影响调用方手里那个实例——用 class 才能让「测试里按下按钮的回调改动剪贴板」
/// 与「production 代码随后读取剪贴板」看到的是同一份状态。
final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private(set) var contents: String
    private(set) var wasCleared = false

    init(contents: String) { self.contents = contents }

    func readString() -> String? { contents }
    func clear() { contents = ""; wasCleared = true }

    /// 测试专用：模拟「按下复制按钮后，ChatGPT 真的把内容写进了剪贴板」。
    /// 不叫 `write`，避免和某个真实协议方法同名造成误解——这纯粹是测试装置。
    func simulateExternalWrite(_ text: String) { contents = text }
}
