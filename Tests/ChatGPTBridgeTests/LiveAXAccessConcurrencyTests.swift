import XCTest

@testable import ChatGPTBridge

/// `LiveAXAccess` 被两条线程同时调用时，它手上那三样可变状态还站得住吗。
///
/// **为什么这件事要紧**（复审第 3 条）：`PracticeRunner` 每一步都把阻塞的 AX 调用甩到
/// `Task.detached` 上跑，而「我练完了」那颗按钮挂着回车快捷键——练完那一刻连按两下，
/// 两条收尾链路就同时进来了。重入那一层已经由运行器的守卫堵住（`PracticeCancelTests`
/// 里那条），这里是第二道：采样器、命令行、将来任何一个并发调用点都不该再有机会踩这一脚。
///
/// `@unchecked Sendable` 是一句承诺，不是一道保护。没有锁的时候：
///
/// - `elementMap` 是 Swift 原生字典，两条线程同时改它会当场段错误（复审用逐字复刻
///   同一套无锁写法的替身证过：8 次运行 8 次段错误，ThreadSanitizer 明确报数据竞争）；
/// - `currentEpoch += 1` 不是原子操作，**丢掉一次 +1 就意味着一个本该作废的旧引用
///   会被当成有效的**，于是 `press` 按到新树里同编号的另一个控件上——用户看到的是
///   「按钮明明在，按下去没反应」，或者更糟：按到了别的东西。
///
/// **一次也不碰真实 ChatGPT（铁律 3）**：这里造的 `LiveAXAccess` 走的是
/// 「找不到目标 App」那道接缝，所以整趟不会读任何一个真实的无障碍节点。
/// 走的仍然是这个类自己那几行加锁逻辑——清映射、重置 rawID、代次 +1、按代次取元素，
/// 一行都不掺假；掺假的只有「树里有什么」，而这几条问的恰恰不是那个。
final class LiveAXAccessConcurrencyTests: XCTestCase {

    /// 一台不会去碰真实 ChatGPT 的 `LiveAXAccess`。
    private func detachedAccess() -> LiveAXAccess {
        LiveAXAccess(locateApp: { nil })
    }

    /// 前提先钉住：这台接缝换掉之后确实还在跑同一段代码（快照返回空、代次照涨）。
    /// 不钉的话，接缝要是哪天短路成「什么都不做」，下面两条就成了空转。
    func testTheDetachedSeamStillRunsTheRealBookkeeping() {
        let access = detachedAccess()
        XCTAssertFalse(access.isTargetRunning(), "接缝没生效，这一组会去碰真实 ChatGPT")
        XCTAssertEqual(access.snapshotTree(), [], "找不到目标时快照该是空的")
        XCTAssertEqual(access.currentEpoch, 1, "代次那一句 `+1` 没跑，下面两条就没有依据")
    }

    func testTheEpochNeverLosesAnIncrementUnderConcurrentSnapshots() {
        let access = detachedAccess()
        let threads = 8
        let perThread = 500

        DispatchQueue.concurrentPerform(iterations: threads) { _ in
            for _ in 0..<perThread { _ = access.snapshotTree() }
        }

        XCTAssertEqual(access.currentEpoch, threads * perThread,
                       "\(threads * perThread) 次 `snapshotTree()` 只把代次推到了 "
                           + "\(access.currentEpoch)——丢掉的那几次 `+1` 不是计数不准而已："
                           + "代次是「此前取得的 AXElementRef 已经作废」的唯一判据，"
                           + "丢一次就有一个本该作废的旧引用被当成有效的，"
                           + "`press` 会按到新树里同编号的另一个控件上。"
                           + "下一步：确认 `LiveAXAccess` 那三样可变状态还在同一把锁里。")
    }

    /// 一边快照、一边按、一边写值，**不许崩**。
    ///
    /// 上一条问的是「有没有丢 +1」，这一条问的是「会不会当场炸」——
    /// 无锁时两条线程同时改 `elementMap` 那本字典正是段错误的现场。
    /// 断言只有一条，真正的判据是**这个进程还活着跑到了那一行**。
    func testPressingWhileSnapshottingDoesNotCrash() {
        let access = detachedAccess()
        let stale = AXElementRef(rawID: 0, epoch: 0)

        DispatchQueue.concurrentPerform(iterations: 8) { slot in
            for _ in 0..<500 {
                switch slot % 3 {
                case 0: _ = access.snapshotTree()
                case 1: _ = access.press(stale)
                default: _ = access.setValue("x", on: stale)
                }
            }
        }

        XCTAssertFalse(access.press(stale),
                       "拿着一个早就作废的代次还能按下去——旧引用的作废判据失效了")
    }
}
