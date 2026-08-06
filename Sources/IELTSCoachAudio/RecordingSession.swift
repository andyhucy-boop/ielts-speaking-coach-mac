import AVFoundation
import Foundation

/// 录音中途的一次中断（换了音频输入设备）。
public struct RecordingInterruption: Equatable, Sendable {
    public let at: Date
    /// 是否自动接上了。**接上了也必须告诉用户**——切换的那一两秒确实没录到。
    public let recovered: Bool

    public init(at: Date, recovered: Bool) { self.at = at; self.recovered = recovered }
}

public struct RecordingOutcome: Equatable, Sendable {
    /// 相对数据目录的路径，例如 "recordings/2026-08-06T10-45-30Z.m4a"。
    /// **一秒都没录到时是空字符串**——给一个指向空文件的路径，
    /// 只会让训练记录页显示一个点了没声音的播放器。
    public let relativePath: String
    public let duration: TimeInterval
    public let interruptions: [RecordingInterruption]
    /// 非 nil 时界面**必须**显示。中文，写明发生了什么与下一步做什么。
    public let warning: String?

    public init(relativePath: String, duration: TimeInterval,
                interruptions: [RecordingInterruption], warning: String?) {
        self.relativePath = relativePath; self.duration = duration
        self.interruptions = interruptions; self.warning = warning
    }
}

/// 一次练习的录音编排：启动采集、把音频交给写入器、处理设备切换、收尾。
///
/// 只依赖 `AudioCaptureEngine` 与 `AudioSegmentWriter` 两个 protocol，
/// 因此整条逻辑（含插拔耳机）可以用假实现完整测试，不碰任何硬件。
public final class RecordingSession: @unchecked Sendable {
    public typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter

    private let engine: AudioCaptureEngine
    private let writerFactory: WriterFactory
    private let fileURL: URL
    private let relativePath: String
    private let clock: @Sendable () -> Date

    // 音频回调来自另一条线程，下面这些状态一律用锁保护。
    private let lock = NSLock()
    private var writer: AudioSegmentWriter?
    private var interruptions: [RecordingInterruption] = []
    private var warnings: [String] = []
    private var duration: TimeInterval = 0
    /// 文件是否已经关掉了（不管是正常收尾还是出错收尾）。
    private var closed = false

    public init(engine: AudioCaptureEngine,
                writerFactory: @escaping WriterFactory,
                fileURL: URL,
                relativePath: String,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.writerFactory = writerFactory
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.clock = clock
    }

    public func start() throws {
        let made = try writerFactory(fileURL)
        lock.lock(); writer = made; lock.unlock()

        engine.onConfigurationChange = { [weak self] in self?.handleConfigurationChange() }
        do {
            try engine.start(onBuffer: { [weak self] buffer in self?.append(buffer) })
        } catch {
            // 采集起不来也要把刚建出来的文件关掉：句柄不放，m4a 的索引就写不出去，
            // 文件对象也会一直吊着。
            //
            // **关掉不等于删掉。** 那个 0 字节的文件还留在 recordings/ 里，会被算进
            // 占用、也会被 `RecordingStore.orphanFileNames` 当成孤儿。删它的逻辑
            // `finish()` 里已经有了（「一秒都没录到就删掉空文件」），但 `start()` 抛错时
            // 调用方拿不到 outcome，多半不会再调 `finish()`——计划里 Task 6 的
            // `begin()` catch 分支正是这样。收拾这个空文件是调用方的事，不是这里的。
            closeWriter()
            throw error
        }
    }

    public func finish() -> RecordingOutcome {
        engine.stop()
        engine.onConfigurationChange = nil
        closeWriter()

        lock.lock()
        var allWarnings = warnings
        let seconds = duration
        let capturedInterruptions = interruptions
        lock.unlock()

        let hasAudio = seconds > 0
        if !hasAudio {
            // 空文件不留：它占着 recordings 目录、会被算进占用、还会被当成孤儿报警，
            // 而里面一点声音都没有。删掉它，然后把「为什么没录到」说清楚。
            try? FileManager.default.removeItem(at: fileURL)
            allWarnings.append(
                "这次一秒录音都没录到，已经把空文件删掉了。"
                + "下一步：打开「系统设置 › 声音 › 输入」，确认选中的麦克风在你说话时有输入电平；"
                + "若暂时不需要录音，到「录音设置」（⌘,）把开关关掉，界面就不会再提这件事。")
        }

        return RecordingOutcome(
            relativePath: hasAudio ? relativePath : "",
            duration: seconds,
            interruptions: capturedInterruptions,
            warning: allWarnings.isEmpty ? nil : allWarnings.joined(separator: "\n"))
    }

    // MARK: - 私有

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let target = closed ? nil : writer
        lock.unlock()
        guard let target else { return }

        do {
            try target.write(buffer)
        } catch {
            // 写不进去就立刻收摊，但**必须先把文件正常关掉**——
            // 已经录下的部分是用户练了半小时换来的，不能跟着错误一起蒸发。
            engine.stop()
            closeWriter()
            lock.lock()
            warnings.append(
                "录音在中途写不下去了：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响。"
                + "下一步：确认磁盘还有空间，然后重新练一次。")
            lock.unlock()
        }
    }

    /// 输入设备变了（插拔耳机、切换声卡、蓝牙断连）。
    ///
    /// AVAudioEngine 此时已经停了，输入节点的格式也变了，之前装的 tap 失效。
    /// **不重新装 tap 再启动的话，后面一句话都录不到，而且不会抛任何错误。**
    private func handleConfigurationChange() {
        lock.lock()
        let stillRecording = !closed
        lock.unlock()
        guard stillRecording else { return }

        engine.stop()
        let at = clock()
        do {
            try engine.start(onBuffer: { [weak self] buffer in self?.append(buffer) })
            lock.lock()
            interruptions.append(RecordingInterruption(at: at, recovered: true))
            warnings.append(
                "录音中途因为音频输入设备变化（多半是插拔了耳机）断了一下，已经自动接上继续录，"
                + "切换的那一两秒没有录进去。"
                + "下一步：回听时留意这一小段；若刚好是关键回答，把这道题再练一次。")
            lock.unlock()
        } catch {
            // 接不回来就收尾。**先关文件再报错**：已经录到的部分必须留在磁盘上。
            closeWriter()
            lock.lock()
            interruptions.append(RecordingInterruption(at: at, recovered: false))
            warnings.append(
                "录音在中途停了，因为音频输入设备变了而且接不回来：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响，可以接着练完。"
                + "下一步：把耳机插回去，或到「系统设置 › 声音 › 输入」重新选一个麦克风；"
                + "下一次练习会重新开始录。")
            lock.unlock()
        }
    }

    /// 关文件。重复调用只有第一次生效——文件不能被关两次。
    private func closeWriter() {
        lock.lock()
        guard !closed, let target = writer else { lock.unlock(); return }
        closed = true
        writer = nil
        lock.unlock()

        let seconds = target.finish()
        lock.lock(); duration = seconds; lock.unlock()
    }
}
