import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假采样器：按脚本一次返回一个 sweep，用完之后重复最后一个。
final class FakeTranscriptSampler: TranscriptSampling, @unchecked Sendable {
    private var script: [TranscriptSweep]
    private(set) var sampleCount = 0

    init(_ script: [TranscriptSweep]) { self.script = script }

    func sample() -> TranscriptSweep {
        defer { sampleCount += 1 }
        guard !script.isEmpty else { return TranscriptSweep(fragments: []) }
        let index = min(sampleCount, script.count - 1)
        return script[index]
    }
}

/// 会自己往前走的假时钟：每问一次时间就前进 3 秒（真机上的采样节拍就是 2~3 秒）。
///
/// **为什么不像计划里那样把 `clock` 存在测试类上、闭包里写 `{ self.now() }`：**
/// 那份写法在 Swift 6 语言模式下编不过，实测两条错误——
/// `capture of 'self' with non-Sendable type 'TranscriptCollectorTests' in a '@Sendable' closure`
/// 与 `call to main actor-isolated instance method 'now()' in a synchronous nonisolated context`。
/// 根因是 `@Sendable` 闭包不继承 actor 隔离，而 `TranscriptCollector.init` 收的正是
/// `@Sendable () -> Date`（与 `PracticeRunner` 的写法一致，刻意保持，不为了迁就测试去改产品代码）。
/// 所以把时钟单拎成一个自带锁的小类型，行为与计划完全一致。
final class SteppingClock: @unchecked Sendable {
    /// 起点。第一次 `next()` 返回的是它 + 3 秒。
    static let start = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

    private let lock = NSLock()
    private var current = SteppingClock.start

    func next() -> Date {
        lock.withLock {
            current = current.addingTimeInterval(3)
            return current
        }
    }
}

@MainActor
final class TranscriptCollectorTests: XCTestCase {
    private func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }
    private func sweep(_ fragments: [TranscriptFragment]) -> TranscriptSweep {
        TranscriptSweep(fragments: fragments)
    }

    private func makeCollector(sampler: (any TranscriptSampling)?) -> TranscriptCollector {
        let clock = SteppingClock()
        return TranscriptCollector(sampler: sampler, now: { clock.next() })
    }

    // MARK: - 正常路径

    func testWhatWasOnScreenAtTheStartIsTreatedAsBackground() {
        let sampler = FakeTranscriptSampler([
            sweep([learner("You will act as an IELTS Speaking examiner.")]),   // begin：背景板
            sweep([learner("You will act as an IELTS Speaking examiner."),
                   examiner("Do you live in a house or a flat?")])            // tick
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()

        XCTAssertEqual(collector.turns.map(\.text), ["Do you live in a house or a flat?"],
                       "练习开始时就在屏幕上的考官提示词不算对话")
    }

    func testFinishTakesOneLastSampleSoTheClosingLineIsNotLost() {
        let sampler = FakeTranscriptSampler([
            sweep([]),
            sweep([examiner("Do you live in a house or a flat?")]),
            sweep([examiner("Do you live in a house or a flat?"),
                   learner("I live in a flat with my parents.")])
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()
        collector.finish()

        XCTAssertEqual(collector.turns.count, 2, "finish 必须再采一次，否则最后一句话会丢")
        XCTAssertFalse(collector.isCollecting)
    }

    func testTickingAfterFinishDoesNothing() {
        let sampler = FakeTranscriptSampler([sweep([]), sweep([examiner("Q?")])])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.finish()
        let countAfterFinish = sampler.sampleCount
        collector.tick()
        XCTAssertEqual(sampler.sampleCount, countAfterFinish,
                       "已经结束了还在采样，只会把复盘 JSON 采进逐字稿")
    }

    /// 注入的时钟必须真的被用上。
    ///
    /// 计划的突变表里没有这一条，但少了它，把实现里的 `now()` 换成写死的 `Date()`
    /// 整套测试照样全绿——而 `capturedAt` 正是「训练记录」里排时间、
    /// 以及 Phase 5 录音对齐要用的东西，写死之后就再也测不住了。
    func testTheInjectedClockIsWhatStampsEachTurn() {
        let sampler = FakeTranscriptSampler([sweep([]), sweep([examiner("Q?")])])
        let collector = makeCollector(sampler: sampler)
        collector.begin()     // 背景板不问时间
        collector.tick()      // 第一次问时间：起点 + 3 秒

        XCTAssertEqual(collector.turns.first?.capturedAt, "2026-08-06T10:00:03Z",
                       "逐字稿上的时间必须来自注入的时钟，不能是写死的 Date()")
    }

    // MARK: - 采样失败绝不中断

    /// **本任务的核心。** 中间失败几次，前后采到的内容都要在，
    /// 而且必须在 `notice` 里如实说出来。
    func testAFailedSampleNeitherThrowsNorLosesAnything() throws {
        let sampler = FakeTranscriptSampler([
            sweep([]),
            sweep([examiner("Do you live in a house or a flat?")]),
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容"),
            sweep([examiner("Do you live in a house or a flat?"),
                   learner("I live in a flat.")])
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()
        collector.tick()        // 这一次失败
        collector.tick()
        collector.finish()

        XCTAssertEqual(collector.turns.count, 2, "失败前后采到的内容都要在")
        XCTAssertEqual(collector.samplingFailureCount, 1)
        let notice = try XCTUnwrap(collector.notice)
        XCTAssertTrue(notice.contains("下一步"))
    }

    func testAFailedBaselineIsRecordedAndCollectionStillStarts() {
        let sampler = FakeTranscriptSampler([
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容"),
            sweep([examiner("Do you live in a house or a flat?")])
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        XCTAssertTrue(collector.isCollecting, "背景板没采到也要照常开始收集")
        collector.tick()
        collector.finish()
        XCTAssertEqual(collector.samplingFailureCount, 1)
        XCTAssertEqual(collector.turns.count, 1)
    }

    func testAbandonKeepsWhatWasAlreadyCollected() throws {
        let sampler = FakeTranscriptSampler([
            sweep([]), sweep([examiner("Do you live in a house or a flat?")])
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()
        collector.abandon(reason: "练习中途出错了")

        XCTAssertFalse(collector.isCollecting)
        XCTAssertEqual(collector.turns.count, 1, "练习失败了，已经采到的话也不能丢")
        XCTAssertTrue(try XCTUnwrap(collector.notice).contains("练习中途出错了"))
    }

    /// `abandon` 不许把已经记下的「采样失败」说明顶掉。
    ///
    /// 计划的突变表里没有这一条，而实测：把 `abandon` 里
    /// `let existing = notice.map { $0 + " " } ?? ""` 那一句去掉（直接覆盖 `notice`），
    /// 其余八条测试全绿——用户只会看到「这一场没有正常走完」，
    /// 看不到「中间有 1 次没能读到界面，那几秒说的话可能没记进来」。
    /// 而后者正是他判断逐字稿缺在哪里的唯一依据，丢掉它就是静默地少几分钟对话。
    func testAbandonDoesNotSwallowTheSamplingFailureNote() throws {
        let sampler = FakeTranscriptSampler([
            sweep([]),
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容")
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()        // 这一次失败
        collector.abandon(reason: "练习中途出错了")

        let notice = try XCTUnwrap(collector.notice)
        XCTAssertTrue(notice.contains("没能读到 ChatGPT 的界面内容"),
                      "采样失败的说明不能被「没正常走完」这句顶掉")
        XCTAssertTrue(notice.contains("练习中途出错了"), "也要说清这一场为什么没走完")
        XCTAssertTrue(notice.contains("下一步"), "两句叠在一起之后仍要有下一步")
    }

    // MARK: - 用户关掉了开关

    func testNoSamplerMeansSilentlyDoingNothing() {
        let collector = makeCollector(sampler: nil)
        collector.begin()
        collector.tick()
        collector.finish()

        XCTAssertTrue(collector.turns.isEmpty)
        XCTAssertNil(collector.notice, "用户自己关掉的功能，不该为此报警")
        XCTAssertEqual(collector.samplingFailureCount, 0)
        XCTAssertFalse(collector.isCollecting)
    }

    func testNoNoiseWhenEverythingWentFine() {
        let sampler = FakeTranscriptSampler([
            sweep([]), sweep([examiner("Q?"), learner("A.")])
        ])
        let collector = makeCollector(sampler: sampler)
        collector.begin()
        collector.tick()
        collector.finish()
        XCTAssertNil(collector.notice)
    }
}
