import Foundation
import XCTest

@testable import ChatGPTBridge

/// 命令行练完一场，可能整场复盘一个字都不留（2026-08-08 复审第 13 条）。
///
/// 复现路径：用户按设计的主路径在 ChatGPT 里结束通话，顺手回终端敲了一下回车。
/// `waitForSessionEnd` 那时已经由 AX 自动判出「语音结束」提前返回，**没有人消费这次按键**，
/// 于是它变成一个粘滞标志，横跨接下来的几十秒。等两条自动取复盘都失败、走到手动兜底时，
/// 「请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车」这句话刚打出来，
/// 下一行就是「❌ 剪贴板是空的」并退出——用户连读完那句话的时间都没有。
final class ConsoleEnterWaiterTests: XCTestCase {

    /// 一台假键盘：`press()` 之前一直挂着，`press()` 之后放行一行。
    ///
    /// 不用真 stdin：测试进程的 stdin 不可控，而且真按下去就没法精确地
    /// 把「用户什么时候按的」摆在某个时刻。
    private final class FakeKeyboard: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = 0
        private(set) var reads = 0

        func press() { lock.lock(); pending += 1; lock.unlock() }

        /// 交给 `ConsoleEnterWaiter` 的那一下「读一行」。有待处理的按键就立刻返回，
        /// 没有就阻塞着等——与真的 `readLine()` 行为一致。
        func readLine() -> String? {
            lock.lock(); reads += 1; lock.unlock()
            while true {
                lock.lock()
                if pending > 0 { pending -= 1; lock.unlock(); return "" }
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }

    private func waiter(_ keyboard: FakeKeyboard) -> ConsoleEnterWaiter {
        ConsoleEnterWaiter(pollInterval: 0.005, readLine: { keyboard.readLine() })
    }

    /// 这条测试就是那个缺陷本身：提示打印**之前**按下的回车，
    /// 不许被算成用户对这句提示的回答。
    func testAKeypressThatArrivedBeforeThePromptDoesNotSatisfyTheFreshWait() {
        let keyboard = FakeKeyboard()
        let enter = waiter(keyboard)

        // ① 上一段流程：用户在 ChatGPT 里结束通话，顺手按了一下回车。
        //    自动判出语音结束的那条路不消费它，标志就这么粘着。
        enter.arm()
        keyboard.press()
        let stuck = expectation(description: "粘滞标志立起来了")
        DispatchQueue.global().async {
            while !enter.isPressed { Thread.sleep(forTimeInterval: 0.005) }
            stuck.fulfill()
        }
        wait(for: [stuck], timeout: 5)

        // ② 几十秒后走到手动兜底。**只起一个等待线程**：起两个的话，
        //    放行时谁抢到那次按键是随机的，测试会时红时绿。
        let returned = Flag()
        let released = expectation(description: "按下新的回车之后放行")
        DispatchQueue.global().async {
            enter.waitForFreshPress()
            returned.raise()
            released.fulfill()
        }

        // ③ 用户还在 ChatGPT 里复制，什么都没按——这一步必须还在等。
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(returned.isRaised,
                       "提示打出来之前按的那一下回车被当成了对这句提示的回答，"
                           + "手动兜底 0 秒就穿过去了——用户根本来不及复制（复审第 13 条）。")

        // ④ 读完提示、复制好、按下回车——这时才放行。
        keyboard.press()
        wait(for: [released], timeout: 5)
    }

    /// 跨线程读写的一个布尔。裸的局部变量捕获不进 `@Sendable` 闭包。
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func raise() { lock.lock(); value = true; lock.unlock() }
        var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// 反过来也要成立：`waitForPress()` 认早就按下的那一次。
    /// `waitForSessionEnd` 靠它消费「用户按回车主动结束这一场」的那一下——
    /// 要是它也开始丢旧标志，那条路会挂死在一次已经发生过的按键上。
    func testWaitForPressStillAcceptsAKeypressThatAlreadyHappened() {
        let keyboard = FakeKeyboard()
        let enter = waiter(keyboard)
        enter.arm()
        keyboard.press()

        let done = expectation(description: "旧按键被消费掉")
        DispatchQueue.global().async {
            enter.waitForPress()
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(enter.isPressed, "消费之后标志必须清掉，否则下一次等待又会 0 秒穿过去")
    }

    /// 只起一个读线程：两个线程同时读 stdin 时内核只唤醒一个，另一个永远阻塞。
    func testOnlyOneReaderThreadIsEverStarted() {
        let keyboard = FakeKeyboard()
        let enter = waiter(keyboard)
        enter.arm()
        enter.arm()
        enter.arm()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(keyboard.reads, 1, "同时有两个线程在读 stdin，必然有一个永远醒不过来")
    }
}

/// 手动兜底那一步：提示 → 等一次新的回车 → 读剪贴板 → 失败还能再试。
final class ManualReviewCaptureTests: XCTestCase {

    /// 按键计数。`readLine` 那个闭包要求 `@Sendable`，裸的局部变量捕获不进去。
    private final class PressCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// 立刻放行的假键盘：这里要测的是「读到没读到、说了什么」，不是等待时序
    ///（时序归 `ConsoleEnterWaiterTests`）。
    private func instantWaiter(onPress: @escaping @Sendable () -> Void = {}) -> ConsoleEnterWaiter {
        ConsoleEnterWaiter(pollInterval: 0.005, readLine: { onPress(); return "" })
    }

    private let review = String(repeating: "复盘正文。", count: 80)

    func testReturnsWhatTheUserPastedOnTheFirstTry() {
        let pasteboard = FakePasteboard(contents: review)
        var lines: [String] = []
        let text = ManualReviewCapture.read(pasteboard: pasteboard,
                                            enter: instantWaiter()) { lines.append($0) }
        XCTAssertEqual(text, review)
        XCTAssertTrue(lines.contains { $0.contains("⌘C") }, "提示必须打出来：\(lines)")
    }

    /// 第一次没选中就按了 ⌘C，不该赔上一整场：还能再试。
    func testAnEmptyClipboardIsNotTheEndOfTheSession() {
        let pasteboard = FakePasteboard(contents: "")
        let presses = PressCounter()
        let waiter = instantWaiter {
            if presses.bump() == 2 {
                pasteboard.simulateExternalWrite(String(repeating: "好的复盘。", count: 80))
            }
        }
        var lines: [String] = []
        let text = ManualReviewCapture.read(pasteboard: pasteboard,
                                            enter: waiter) { lines.append($0) }
        XCTAssertNotNil(text, "第二次粘对了就该读回来，不能一次失败就整场作废")
        XCTAssertTrue(lines.contains { $0.contains("剪贴板是空的") }, "第一次为什么失败得说出来：\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("再试") }, "得告诉用户还能再来一次：\(lines)")
    }

    /// 试满次数还是不行时：**不许无限等下去**，而且必须如实说清这一场什么都没保住、
    /// 以及一条真做得到的下一步。
    func testGivingUpSaysNothingWasSavedAndPointsAtSomethingThatReallyWorks() {
        let pasteboard = FakePasteboard(contents: "")
        let presses = PressCounter()
        var lines: [String] = []
        let text = ManualReviewCapture.read(pasteboard: pasteboard,
                                            enter: instantWaiter { _ = presses.bump() }) {
            lines.append($0)
        }
        XCTAssertNil(text)
        XCTAssertEqual(presses.count, ManualReviewCapture.maxAttempts, "每一次重试都要等一次新的按键")
        let last = lines.last ?? ""
        XCTAssertTrue(last.contains("一个字都没有落盘"), "不许让用户以为这一场已经存下来了：\(last)")
        XCTAssertTrue(last.contains("coach reimport"), "得给一条真能补回错题和词汇的路：\(last)")
        XCTAssertTrue(last.contains("pending-reviews"), "得说清那份原文该放到哪儿：\(last)")
        XCTAssertTrue(last.contains("下一步"), "每一句面向用户的话都要有下一步（铁律 4）")
    }

    /// 上一条的牙齿：那段话里不许再出现一个根本不存在的命令。
    /// 从前 `AXDriver` 就写过「用 coach practice --from-clipboard 继续」，而那个 flag 不存在。
    func testTheGiveUpMessageDoesNotNameACommandThatDoesNotExist() {
        let text = ManualReviewCapture.remaining(after: ManualReviewCapture.maxAttempts)
        XCTAssertFalse(text.contains("--from-clipboard"),
                       "coach practice 没有这个 flag，它会被当成题号：\(text)")
    }
}
