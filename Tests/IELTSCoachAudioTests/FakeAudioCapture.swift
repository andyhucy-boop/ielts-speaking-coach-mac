import AVFoundation
import Foundation
@testable import IELTSCoachAudio

/// 可编程的假麦克风。
///
/// 有了它，「插拔耳机」这条路径可以在没有麦克风、没有权限、也不用真去拔线的
/// 情况下完整测到——这正是把 AVAudioEngine 藏在 protocol 后面的全部理由。
///
/// **下面每一处状态都是真的用锁保护的**，不是靠「只有测试线程碰」这句话糊过去：
/// 「用户在设备切换的那一瞬间点了练完」这类测试必须真的开第二条线程，
/// 假实现自己先有数据竞争的话，测出来的红绿就没有意义了。
final class FakeCaptureEngine: AudioCaptureEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var configurationChangeHandler: (@Sendable () -> Void)?
    private var starts = 0
    private var stops = 0
    private var running = false
    private var failStartAt: Int?
    private var startHook: (@Sendable (Int) -> Void)?
    private var stopHook: (@Sendable (Int) -> Void)?
    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// stop() 之后仍然留着的那份回调，专门用来模拟「还在路上的缓冲区」。
    private var lastSink: (@Sendable (AVAudioPCMBuffer) -> Void)?

    var onConfigurationChange: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return configurationChangeHandler }
        set { lock.lock(); configurationChangeHandler = newValue; lock.unlock() }
    }

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }

    /// 采集器现在是不是开着的。真实实现里这一位就是「麦克风灯还亮不亮」。
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// 第几次调用 start 要抛错（1 表示第一次）。nil 表示每次都成功。
    var failStartAtCall: Int? {
        get { lock.lock(); defer { lock.unlock() }; return failStartAt }
        set { lock.lock(); failStartAt = newValue; lock.unlock() }
    }

    /// 在 start() 执行到一半时插一脚，参数是「这是第几次 start」。
    /// 真实的 AVAudioEngine 重启要花上百毫秒，「重启还没返回」这条缝
    /// 只有把那段时间撑开才测得到。
    var onStartCall: (@Sendable (Int) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return startHook }
        set { lock.lock(); startHook = newValue; lock.unlock() }
    }

    /// 同上，但插在 stop() 里，参数是「这是第几次 stop」。
    ///
    /// 用户点「练完」时 `finish()` 的第一件事就是停采集，而真实的采集器停下来要等
    /// 采集队列上的活做完（`CaptureWorkQueue`）——「收尾已经开始、还没收完」这条缝
    /// 就在这段时间里。设备变化正好在这时候来，是这条缝里唯一会开麦克风的事。
    var onStopCall: (@Sendable (Int) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return stopHook }
        set { lock.lock(); stopHook = newValue; lock.unlock() }
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        lock.lock()
        starts += 1
        let call = starts
        let shouldFail = failStartAt == call
        let hook = startHook
        lock.unlock()

        if shouldFail {
            throw RecordingEngineError.engineStartFailed("测试用的启动失败。下一步：这是测试。")
        }
        // 钩子一定要在锁外调：它里面会有另一条线程回头调 stop()。
        hook?(call)

        lock.lock()
        sink = onBuffer
        lastSink = onBuffer
        running = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stops += 1
        let call = stops
        sink = nil
        running = false
        let hook = stopHook
        lock.unlock()
        // 钩子一定要在锁外调，理由同 start()：它里面会有另一条线程回头调进来。
        hook?(call)
    }

    /// 模拟麦克风送来一段音频。
    func deliver(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let target = sink; lock.unlock()
        target?(buffer)
    }

    /// 模拟**已经在路上、stop() 拦不住**的那一两个缓冲区。
    ///
    /// 这不是假设出来的边缘情况：`AVAudioEngine.stop()` 与 `removeTap` 都不保证
    /// 调用返回时音频线程上没有正在执行的 tap 回调。`AACSegmentWriter.write` 里
    /// 「已经收尾了就安静丢掉」那条守卫防的就是它。
    /// 用 `deliver` 测不到这条路径——`stop()` 已经把 sink 清掉了，
    /// 缓冲区根本到不了 `RecordingSession`，测的就成了假麦克风自己。
    func deliverAfterStop(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let target = lastSink; lock.unlock()
        target?(buffer)
    }

    /// 模拟用户插拔耳机 / 切换声卡。
    func unplugHeadphones() {
        lock.lock(); let handler = configurationChangeHandler; lock.unlock()
        handler?()
    }
}

final class FakeSegmentWriter: AudioSegmentWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    private var finishes = 0
    private var failWrite = false
    private var seconds: TimeInterval = 12
    private var finishHook: (@Sendable () -> Void)?

    var writtenCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
    var finishCount: Int { lock.lock(); defer { lock.unlock() }; return finishes }

    var failOnWrite: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failWrite }
        set { lock.lock(); failWrite = newValue; lock.unlock() }
    }

    /// finish() 报告的时长。设成 0 就是「一秒都没录到」。
    var secondsToReport: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return seconds }
        set { lock.lock(); seconds = newValue; lock.unlock() }
    }

    /// 在 finish() 执行到一半时插一脚。
    /// 真实的 finish() 要把 m4a 的索引写出去，是实打实的磁盘操作；
    /// 「收尾还没落定的那条缝」只有把这段时间撑开才测得到。
    var onFinish: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return finishHook }
        set { lock.lock(); finishHook = newValue; lock.unlock() }
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); let shouldFail = failWrite; lock.unlock()
        if shouldFail {
            throw RecordingEngineError.writeFailed("测试用的写入失败。下一步：这是测试。")
        }
        lock.lock(); writes += 1; lock.unlock()
    }

    func finish() -> TimeInterval {
        lock.lock()
        finishes += 1
        let hook = finishHook
        let reported = seconds
        lock.unlock()
        hook?()      // 锁外：钩子里那条线程会回头调到这个假写入器上
        return reported
    }
}

/// 造一段音频数据。内容是什么无所谓——编排层只是把它转手交给写入器。
func makePCMBuffer(sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
    buffer.frameLength = 1_024
    return buffer
}
