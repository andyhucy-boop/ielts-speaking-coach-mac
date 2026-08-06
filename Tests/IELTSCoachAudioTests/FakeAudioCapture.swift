import AVFoundation
import Foundation
@testable import IELTSCoachAudio

/// 可编程的假麦克风。
///
/// 有了它，「插拔耳机」这条路径可以在没有麦克风、没有权限、也不用真去拔线的
/// 情况下完整测到——这正是把 AVAudioEngine 藏在 protocol 后面的全部理由。
///
/// `@unchecked Sendable` 只在测试里成立：下面这些状态全部只被测试线程碰。
final class FakeCaptureEngine: AudioCaptureEngine, @unchecked Sendable {
    var onConfigurationChange: (@Sendable () -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// 第几次调用 start 要抛错（1 表示第一次）。nil 表示每次都成功。
    var failStartAtCall: Int?

    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// stop() 之后仍然留着的那份回调，专门用来模拟「还在路上的缓冲区」。
    private var lastSink: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        startCount += 1
        if failStartAtCall == startCount {
            throw RecordingEngineError.engineStartFailed("测试用的启动失败。下一步：这是测试。")
        }
        sink = onBuffer
        lastSink = onBuffer
    }

    func stop() { stopCount += 1; sink = nil }

    /// 模拟麦克风送来一段音频。
    func deliver(_ buffer: AVAudioPCMBuffer) { sink?(buffer) }

    /// 模拟**已经在路上、stop() 拦不住**的那一两个缓冲区。
    ///
    /// 这不是假设出来的边缘情况：`AVAudioEngine.stop()` 与 `removeTap` 都不保证
    /// 调用返回时音频线程上没有正在执行的 tap 回调。`AACSegmentWriter.write` 里
    /// 「已经收尾了就安静丢掉」那条守卫防的就是它。
    /// 用 `deliver` 测不到这条路径——`stop()` 已经把 sink 清掉了，
    /// 缓冲区根本到不了 `RecordingSession`，测的就成了假麦克风自己。
    func deliverAfterStop(_ buffer: AVAudioPCMBuffer) { lastSink?(buffer) }

    /// 模拟用户插拔耳机 / 切换声卡。
    func unplugHeadphones() { onConfigurationChange?() }
}

final class FakeSegmentWriter: AudioSegmentWriter, @unchecked Sendable {
    private(set) var writtenCount = 0
    private(set) var finishCount = 0
    var failOnWrite = false
    /// finish() 报告的时长。设成 0 就是「一秒都没录到」。
    var secondsToReport: TimeInterval = 12

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if failOnWrite {
            throw RecordingEngineError.writeFailed("测试用的写入失败。下一步：这是测试。")
        }
        writtenCount += 1
    }

    func finish() -> TimeInterval { finishCount += 1; return secondsToReport }
}

/// 造一段音频数据。内容是什么无所谓——编排层只是把它转手交给写入器。
func makePCMBuffer(sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
    buffer.frameLength = 1_024
    return buffer
}
