import Foundation

/// **独占 stdin 的「等回车」读取器。整个流程只能有一个线程在读。**
///
/// 两个线程同时等回车时，内核只会唤醒其中一个，另一个永远阻塞——
/// 这正是「AX 自动探测到语音结束（手动线程仍挂着）→ 取复盘失败 → 剪贴板兜底
/// 又调一次 readLine」这条路径上会发生的事，直接违反「禁止无限等待」。
///
/// ## 为什么它住在 ChatGPTBridge 而不是 `coach` 里
///
/// 从前它是 `PracticeCommand` 里的一个私有嵌套类。`coach` 是可执行 target，
/// 没有测试 target，于是这段等待逻辑**一行都没有测试**——复审只能在测试里
/// 逐字复刻一份替身来复现缺陷，而复刻出来的替身证明不了生产代码有没有被改坏。
/// 挪到库里之后，`ConsoleEnterWaiterTests` 跑的就是这一份实现本身。
/// 它与 `ClipboardFallback` 是同一件事的两半（手动兜底：⌘C + 回车），放在一起。
public final class ConsoleEnterWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var pressed = false
    private var reading = false
    /// 真正去读一行的那一下。**做成接缝只为可测性**：测试要在没有真实键盘、
    /// 也不阻塞测试进程的前提下，把「用户什么时候按的回车」精确地摆到某个时刻。
    /// 生产代码走的永远是默认实现。
    private let readLine: @Sendable () -> String?
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 0.1,
                readLine: @escaping @Sendable () -> String? = { Swift.readLine() }) {
        self.pollInterval = pollInterval
        self.readLine = readLine
    }

    /// 确保有且只有一个后台线程在读 stdin。已在读或已按下时不再新起线程。
    public func arm() {
        lock.lock(); defer { lock.unlock() }
        guard !reading, !pressed else { return }
        reading = true
        Thread.detachNewThread { [self] in
            _ = readLine()
            lock.lock(); pressed = true; reading = false; lock.unlock()
        }
    }

    public var isPressed: Bool { lock.lock(); defer { lock.unlock() }; return pressed }

    /// 阻塞直到用户按回车，并消费掉这次按键。
    ///
    /// **早就按下的那一次也算数**：`waitForSessionEnd` 用它来消费「用户按回车主动结束
    /// 这一场」的那一下，那时按键本来就已经发生了。
    public func waitForPress() {
        arm()
        while !isPressed { Thread.sleep(forTimeInterval: pollInterval) }
        lock.lock(); pressed = false; lock.unlock()
    }

    /// 阻塞直到用户按下**这一句提示之后**的那次回车。
    ///
    /// ## 为什么必须有这一个，而不能一律用 `waitForPress()`
    ///
    /// 自动判出「语音已经结束」时，`waitForSessionEnd` 会直接返回，
    /// 而后台那个读 stdin 的线程仍然挂着。用户按设计的主路径在 ChatGPT 里结束通话，
    /// 顺手回终端敲了一下回车——这一下被记成一个**粘滞标志**，没有任何人消费它，
    /// 而它会一直留到几十秒后取复盘失败、走到手动兜底那一步。那时屏幕上刚打出
    /// 「请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车」，下一行紧接着就是
    /// 「❌ 剪贴板是空的」并退出：用户连读完那句话的时间都没有，整场复盘一个字都没落盘
    ///（2026-08-08 复审第 13 条，实测「0.000 秒穿过去」）。
    ///
    /// 所以这里先把旧标志丢掉，再等一次新的。丢掉的那一下不是用户对这句提示的回答，
    /// 它属于上一段流程。
    public func waitForFreshPress() {
        lock.lock()
        pressed = false
        lock.unlock()
        waitForPress()
    }
}

/// 手动兜底：请用户自己 ⌘C，再从剪贴板把复盘读回来。
///
/// 两条自动路径（按 ChatGPT 的复制按钮、直接读 AX 树）都失败时才会走到这里。
/// 抽成一个可测的纯逻辑，是因为它是**整条命令行练习流程里最后一道能救回这一场的闸门**：
/// 这一步返回 nil，这一场的复盘原文一个字都不会落盘，训练记录里也不会有这一场，
/// 用户唯一的出路是重新练一整场。
public enum ManualReviewCapture {
    /// 最多让用户试几次。
    ///
    /// **既不能是 1，也不能是无限。** 1 次意味着手一抖（没选中就按了 ⌘C）就赔上一整场；
    /// 无限则违反「禁止无限等待」，而且用户会分不清「它还在等我」和「它卡住了」。
    public static let maxAttempts = 3

    /// - Parameters:
    ///   - report: 打印一行给用户看。做成参数是为了让「到底说了什么」可测——
    ///     直接 `print` 的话，测试只能证明它返回了 nil，证明不了用户读到了什么。
    /// - Returns: 读到的复盘原文；`maxAttempts` 次都没读到时返回 nil。
    public static func read(pasteboard: any PasteboardAccess,
                            enter: ConsoleEnterWaiter,
                            report: (String) -> Void) -> String? {
        for attempt in 1...maxAttempts {
            report("\n请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车。")
            // **必须是 waitForFreshPress。** 用 waitForPress 的话，用户在结束通话时
            // 顺手按的那一下回车会让这里 0 秒穿过去，他根本来不及复制（复审第 13 条）。
            enter.waitForFreshPress()
            do {
                return try ClipboardFallback.readReview(from: pasteboard)
            } catch {
                report("❌ \(error.localizedDescription)")
                report(remaining(after: attempt))
            }
        }
        return nil
    }

    /// 每次读失败之后那句话。**必须说清「这一场现在还什么都没保住」**——
    /// 用户以为练习已经存下来了，才会心安理得地按 Ctrl-C 走人。
    static func remaining(after attempt: Int) -> String {
        let left = maxAttempts - attempt
        guard left > 0 else {
            return "   已经试了 \(maxAttempts) 次都没从剪贴板读到复盘，这一场就到这里了。"
                + "这一场的复盘原文一个字都没有落盘，「训练记录」「复盘报告」里也不会有它。"
                + "下一步：ChatGPT 窗口里那份复盘还在，先别关。"
                + "把它整段复制下来，粘进数据目录的 pending-reviews/ 里存成一个 .txt 文件"
                + "（默认在「资源库 › Application Support › IELTS Speaking Coach」），"
                + "再运行 coach reimport，错题和词汇就能补进档案；"
                + "「训练记录」和「复盘报告」两页补不回这一场，那两页要有得重新练一次。"
        }
        return "   这一场还什么都没保住：复盘原文没落盘，训练记录里也没有它。"
            + "下一步：回 ChatGPT 里把整段复盘（含首尾标记）选中按 ⌘C，"
            + "再回到这里按一次回车，还可以再试 \(left) 次。"
    }
}
