import AVFoundation
import Foundation

/// 把麦克风送来的 PCM 转成固定格式的 AAC，写进一个 .m4a 文件。
///
/// **为什么输出格式写死：** 练到一半插拔耳机，输入设备的采样率会变
/// （常见是 48000 ↔ 44100）。若按第一段输入的格式建文件，格式一变就写不进去，
/// 只能另起一个文件，回听时用户得自己拼。这里改成「输出格式写死、输入变了就
/// 重建转换器」，换设备不换文件，用户听到的是连续的一条。
public final class AACSegmentWriter: AudioSegmentWriter, @unchecked Sendable {
    /// 44.1 kHz 单声道 64 kbps：人声足够清楚，一小时约 28 MB。
    /// 练口语不需要立体声，也不需要更高码率——那只会让磁盘占用翻倍。
    public static let sampleRate: Double = 44_100
    public static let bitRate = 64_000

    private let outputFormat: AVAudioFormat
    /// 刻意是 var 且是 Optional：finish() 时必须把它置 nil。
    /// m4a 的索引（moov atom）在文件对象释放时才写出去，不释放的话
    /// 播放器要么打不开，要么显示时长为 0。
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var writtenFrames: AVAudioFramePosition = 0
    private let lock = NSLock()

    public init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate
        ]
        let opened: AVAudioFile
        do {
            opened = try AVAudioFile(forWriting: url, settings: settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw RecordingEngineError.writeFailed(
                "建不了录音文件 \(url.path)：\(error.localizedDescription)。这次不会录音，练习本身不受影响。"
                + "下一步：确认数据目录可写、磁盘还有空间，然后重新开始一次练习。")
        }
        self.file = opened
        self.outputFormat = opened.processingFormat
    }

    public func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        // 已经收尾了，音频线程上还在路上的缓冲区安静丢掉，不要崩。
        guard let file else { return }

        if converterInputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                throw RecordingEngineError.formatUnsupported(
                    "麦克风换成了本工具转换不了的音频格式"
                    + "（\(Int(buffer.format.sampleRate)) Hz，\(buffer.format.channelCount) 声道）。"
                    + "已经录到的部分不会丢。"
                    + "下一步：到「系统设置 › 声音 › 输入」换一个常见的麦克风，再练一次。")
            }
            converter = made
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        // 采样率变了之后输出帧数跟输入不是一比一，容量要按比例算，
        // 再多留 1024 帧给重采样滤波器的延迟。算少了会被截断，也就是丢音频。
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw RecordingEngineError.writeFailed(
                "内存不够，装不下转换后的音频。已经录到的部分不会丢。"
                + "下一步：关掉一些别的程序，然后重新开始一次练习。")
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            // 一次只喂一个缓冲区。喂完之后报 noDataNow，让转换器把手上的东西吐出来。
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw RecordingEngineError.writeFailed(
                "音频转换失败：\(conversionError?.localizedDescription ?? "未知原因")。"
                + "已经录到的部分不会丢。"
                + "下一步：重新开始一次练习；若反复出现，到「系统设置 › 声音 › 输入」换一个麦克风。")
        }

        guard output.frameLength > 0 else { return }
        try file.write(from: output)
        writtenFrames += AVAudioFramePosition(output.frameLength)
    }

    @discardableResult
    public func finish() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        // 这一行不能省：m4a 的索引在文件对象释放时才写出去。
        file = nil
        return Double(writtenFrames) / outputFormat.sampleRate
    }
}
