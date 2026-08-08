import Foundation
import XCTest
@testable import IELTSCoachAudio

/// 一面用锁保护的旗子。跨线程读写标志位，测试自己先有数据竞争的话，
/// 测出来的红绿就没有意义了（同一条理由 `FakeAudioCapture` 里已经写过）。
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// 数「同一时刻有几条活在跑」。用锁数在场人数，而不是用一个裸的 Bool——
/// 裸 Bool 测出来的「重叠」可能是探针自己的数据竞争。
private final class OverlapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var overlapped = false

    var sawOverlap: Bool { lock.lock(); defer { lock.unlock() }; return overlapped }

    func enter() {
        lock.lock()
        active += 1
        if active > 1 { overlapped = true }
        lock.unlock()
    }

    func leave() { lock.lock(); active -= 1; lock.unlock() }
}

/// `CaptureWorkQueue` 是 `AVAudioEngineCapture` 里唯一能不碰麦克风就测到的那部分：
/// 「什么时候可以就地停引擎、什么时候必须挪走」以及「两条线不能同时进采集器」。
///
/// 这两条都不是洁癖，都是真实存在的路径：
///
/// - 磁盘写满 → `AACSegmentWriter.write` 抛错 → `RecordingSession.append` 当场收摊 →
///   在 **tap 回调里**调 `stop()`。`AVAudioEngine.stop()` / `removeTap` 会等当前这条
///   tap 回调返回，就地做就是自锁：麦克风一直开着，用户连「我练完了」都点不动。
/// - 设备变化的通知走主线程（`AVAudioEngineCapture` 把观察者注册在 `queue: .main`），
///   写盘失败的收摊走音频线程。`RecordingSession` 只保证「finish() 会等设备变化处理完」，
///   不保证这两条线不撞上，所以采集器自己内部那点状态必须是互斥的。
final class CaptureWorkQueueTests: XCTestCase {
    /// 不在 tap 回调里的 `stop()` 必须**做完再返回**。
    ///
    /// 用户点「我练完了」走的就是这条：`RecordingSession.finish()` 里
    /// `engine.stop()` 一返回就去关文件、算时长、报结果。这时候麦克风要是还开着，
    /// 就再没有别人会去关它了。
    func testOutsideATapCallbackTheWorkIsDoneBeforeTheCallReturns() {
        let queue = CaptureWorkQueue()
        let occupied = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)

        // 先把工作台占住。真实场景就是「音频线程刚扔过来一次拆 tap，还没做完」。
        Thread.detachNewThread {
            queue.perform { occupied.signal(); release.wait() }
        }
        XCTAssertEqual(occupied.wait(timeout: .now() + 5), .success, "占位的那条活没跑起来")

        Thread.detachNewThread {
            queue.performOffTheTapThread { }
            returned.signal()
        }
        XCTAssertEqual(
            returned.wait(timeout: .now() + 0.3), .timedOut,
            "工作台还占着就返回了：练完之后 stop() 会在麦克风真的关掉之前返回，那盏灯没人再去关")

        release.signal()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success, "工作台腾出来了却还是没返回")
    }

    /// 身处 tap 回调时，`stop()` 必须**立刻返回**，把拆 tap / 停引擎挪到别处做。
    ///
    /// 这就是磁盘写满那条路径。就地做等于「在 tap 回调里等 tap 回调结束」，
    /// `AudioCaptureEngine.stop()` 的契约明写这是自锁。
    func testInsideATapCallbackTheCallReturnsWithoutWaitingForTheWork() {
        let queue = CaptureWorkQueue()
        let occupied = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        let workDone = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            queue.perform { occupied.signal(); release.wait() }
        }
        XCTAssertEqual(occupied.wait(timeout: .now() + 5), .success, "占位的那条活没跑起来")

        Thread.detachNewThread {
            queue.markingTapCallback {
                queue.performOffTheTapThread { workDone.signal() }
            }
            returned.signal()
        }
        XCTAssertEqual(
            returned.wait(timeout: .now() + 5), .success,
            "在 tap 回调里停引擎却等了起来——这就是磁盘写满时把整个练习卡死的那次自锁")
        XCTAssertEqual(
            workDone.wait(timeout: .now() + 0.3), .timedOut,
            "活没有排到工作台上：它必须和别的拆 tap / 装 tap 排成一队，不能自己另开一条线")

        release.signal()
        XCTAssertEqual(
            workDone.wait(timeout: .now() + 5), .success,
            "推迟不等于不做：拆 tap、停引擎这件事最后必须真的发生，否则麦克风一直开着")
    }

    /// 标记只对**打标记的那条线程**成立。
    ///
    /// 音频线程正在跑 tap 回调，不代表界面线程也在。做成一个全局开关的话，
    /// 用户点「我练完了」时 `stop()` 会以为自己身处 tap 回调而改成异步——
    /// `finish()` 返回时麦克风还开着。
    func testTheTapCallbackMarkOnlyAppliesToTheThreadThatSetIt() {
        let queue = CaptureWorkQueue()
        let inside = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            queue.markingTapCallback { inside.signal(); release.wait() }
        }
        XCTAssertEqual(inside.wait(timeout: .now() + 5), .success, "假 tap 回调没跑起来")

        XCTAssertFalse(queue.isInsideTapCallback,
                       "另一条线程正在跑 tap 回调，被当成了「这条线程也在」")
        let done = Flag()
        queue.performOffTheTapThread { done.set() }
        XCTAssertTrue(done.isSet, "界面线程的 stop() 被推迟了：finish() 返回时麦克风还开着")

        release.signal()
    }

    /// tap 回调返回之后标记要摘掉。
    ///
    /// 不摘的话，这条线程往后每一次 `stop()` 都会被当成「在 tap 回调里」而改成异步。
    /// 音频线程是被复用的，所以这不是理论问题。
    func testTheMarkIsGoneOnceTheTapCallbackReturns() {
        let queue = CaptureWorkQueue()

        queue.markingTapCallback {
            XCTAssertTrue(queue.isInsideTapCallback,
                          "tap 回调里没打上标记，写盘失败时的 stop() 就会当场自锁")
        }

        XCTAssertFalse(queue.isInsideTapCallback, "标记没摘掉：这条线程之后的 stop() 全都会被推迟")
        let done = Flag()
        queue.performOffTheTapThread { done.set() }
        XCTAssertTrue(done.isSet, "标记没摘掉：stop() 不再是「返回时麦克风已经关了」")
    }

    /// 两条活不能同时在跑。
    ///
    /// 采集器内部的 `tapped` / `observer` 就靠这一条保证线程安全：主线程处理设备变化
    /// （停引擎、重新装 tap）与音频线程写盘失败后的收摊是真的会撞上的。撞上之后
    /// `tapped` 被撕裂，轻则 `removeTap` 调两次，重则 tap 装上了 `tapped` 却是 false，
    /// 此后 `stop()` 直接返回——练习结束了，输入节点上还挂着一个 tap。
    func testWorkNeverRunsConcurrently() {
        let queue = CaptureWorkQueue()
        let probe = OverlapProbe()
        let group = DispatchGroup()

        for index in 0..<20 {
            DispatchQueue.global().async(group: group) {
                let body: @Sendable () -> Void = {
                    probe.enter()
                    Thread.sleep(forTimeInterval: 0.002)
                    probe.leave()
                }
                if index.isMultiple(of: 2) {
                    queue.perform(body)
                } else {
                    queue.performOffTheTapThread(body)
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success, "20 条活没能在 10 秒里跑完")
        XCTAssertFalse(probe.sawOverlap,
                       "两条线同时进了采集器：`tapped` / `observer` 会被撕裂")
    }
}
