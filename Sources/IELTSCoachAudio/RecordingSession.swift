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
///
/// ## 三条线程，一把锁
///
/// 同时碰这个对象的有三条线：**音频回调线程**（`append`）、
/// **设备变化通知线程**（`handleConfigurationChange`）、
/// **点「练完」的界面线程**（`finish`）。它们之间的每一条缝都是要丢东西的：
///
/// - 「文件已关」与「时长是多少」如果不是一起发布的，并发的 `finish()` 会读到
///   一个还没写回去的 0，把一条真录音当成「一秒都没录到」删掉；
/// - 「还在录吗」的判断与随后的 `engine.start()` 如果不是互斥的，收尾之后
///   麦克风会停在开着的状态，中断警告也会写在 `finish()` 读完之后，用户看不到；
/// - **重启采集的那段时间里，文件可能已经被另一条线关掉了。** 拿重启前的判断去宣告
///   「已经自动接上继续录」，用户就会被骗着继续说，而麦克风开着、文件已关，
///   后面每一个字都不进任何文件——他练完点开回听才发现后半段没了，
///   而且永远搞不清哪半段丢了、为什么丢。
///
/// 三条都实测复现过，所以下面的规矩不是洁癖：
///
/// 1. 所有可变状态一律在 `state` 里读写；
/// 2. `finish()` 必须等**已经在跑**的设备变化处理完，再去收尾；
/// 3. 锁里允许的慢动作只有 `writer.write` 与 `writer.finish`；
///    **绝不能握着锁去调 `engine.stop()`**——真实的 `AVAudioEngine` 停下来时会等
///    当前那条 tap 回调返回，而 tap 回调正卡在这把锁上，那就是死锁；
/// 4. 松开锁做过慢动作（`engine.stop()` / `engine.start()`）之后，**重新拿锁时
///    要重新判断**：松手期间别的线可能已经把文件关了、也可能已经开始收尾了。
///    松手之前的判断在松手之后一律不作数。
public final class RecordingSession: @unchecked Sendable {
    public typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter

    private let engine: AudioCaptureEngine
    private let writerFactory: WriterFactory
    private let fileURL: URL
    private let relativePath: String
    private let clock: @Sendable () -> Date

    /// 保护下面全部状态，同时当条件变量用：`finish()` 靠它等设备变化那一段落定。
    private let state = NSCondition()
    /// 非 nil 表示文件还开着；关掉之后置 nil，**`nil` 就是「已经关了」**。
    private var writer: AudioSegmentWriter?
    private var interruptions: [RecordingInterruption] = []
    private var warnings: [String] = []
    private var duration: TimeInterval = 0
    /// `finish()` 已经接管收尾：不再写新数据，也不再为设备变化重启采集。
    private var stopped = false
    /// 正在处理中的设备变化条数。`finish()` 必须等它归零，理由见 `finish()`。
    private var deviceChangesInFlight = 0

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
        state.lock(); writer = made; state.unlock()

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

    /// 收尾并给出结果。由界面线程调用（用户点「练完」）。
    public func finish() -> RecordingOutcome {
        state.lock()
        // 先立规矩：从这一刻起不再写新数据，也不再为设备变化重启采集。
        // 这一位必须在等待**之前**置上，否则等的过程中新来的设备变化又会去开麦克风。
        stopped = true
        // 再等**已经在跑**的那一段设备变化处理完。抢在它前面收尾有两个后果，
        // 复审都实测复现过：
        //   1. 它的 `engine.start()` 会在我们 `stop()` 之后才返回，
        //      采集器就停在已启动状态——练习结束了麦克风还开着，再没人去关；
        //   2. 它写进 `warnings` 的「已经自动接上继续录」在我们读完之后才落地，
        //      用户永远看不到那条——正是本任务要消灭的「悄悄少了一段」。
        // 等的是一段**确定会结束**的临界区（一次采集器重启），不是外部事件，
        // 所以这里不是「无限等待」。
        //
        // 另一条要等的路径不需要额外机关：写盘失败时的收尾是握着这把锁一次做完的，
        // 上面那句 `state.lock()` 本身就把它等到了。
        while deviceChangesInFlight > 0 { state.wait() }
        state.unlock()

        engine.stop()
        engine.onConfigurationChange = nil
        closeWriter()

        state.lock()
        var allWarnings = warnings
        let seconds = duration
        let capturedInterruptions = interruptions
        state.unlock()

        let hasAudio = seconds > 0
        if !hasAudio { allWarnings.append(disposeOfTheEmptyFile()) }

        return RecordingOutcome(
            relativePath: hasAudio ? relativePath : "",
            duration: seconds,
            interruptions: capturedInterruptions,
            warning: allWarnings.isEmpty ? nil : allWarnings.joined(separator: "\n"))
    }

    // MARK: - 私有

    private func append(_ buffer: AVAudioPCMBuffer) {
        state.lock()
        guard !stopped, let target = writer else { state.unlock(); return }

        var captureMustStop = false
        do {
            // 整段写入都在锁里：写入器不是线程安全的，写到一半被另一条线程把文件
            // 关掉，轻则写坏 m4a 的索引，重则崩在 AVAudioFile 里。
            try target.write(buffer)
        } catch {
            // 写不进去就立刻收摊，但**必须先把文件正常关掉**——
            // 已经录下的部分是用户练了半小时换来的，不能跟着错误一起蒸发。
            //
            // 关文件、写回时长、追加警告三件事都在这一次持锁里做完：
            // 并发的 `finish()` 要么排在我们前面什么都没看见，要么看到完整的结果，
            // 不会读到「文件已关、时长还是 0」这种半截状态。
            closeWriterLocked()
            warnings.append(
                "录音在中途写不下去了：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响。"
                + "下一步：确认磁盘还有空间，然后重新练一次。")
            captureMustStop = true
        }
        state.unlock()

        // `engine.stop()` 一定要在锁外：我们**就在** tap 回调里，
        // 真实的采集器停下来时会等当前这条回调返回，握着锁去 stop 就是死锁。
        if captureMustStop { engine.stop() }
    }

    /// 输入设备变了（插拔耳机、切换声卡、蓝牙断连）。
    ///
    /// AVAudioEngine 此时已经停了，输入节点的格式也变了，之前装的 tap 失效。
    /// **不重新装 tap 再启动的话，后面一句话都录不到，而且不会抛任何错误。**
    private func handleConfigurationChange() {
        state.lock()
        // 已经收尾、或者文件已经关了，就什么都不做——尤其不能去动采集器：
        // `finish()` 可能正在 `stop()`，我们一个 `start()` 就把麦克风又打开了。
        guard !stopped, writer != nil else { state.unlock(); return }
        // 宣告「这一段正在跑」。`finish()` 会等它归零，因此下面这一整段
        // ——停采集、重启采集、记中断、写警告——对收尾来说是原子的。
        deviceChangesInFlight += 1
        state.unlock()

        defer {
            state.lock()
            deviceChangesInFlight -= 1
            state.broadcast()          // 可能有个 finish() 正等着这一段落定
            state.unlock()
        }

        engine.stop()
        let at = clock()
        do {
            try engine.start(onBuffer: { [weak self] buffer in self?.append(buffer) })
            state.lock()
            // **重启成功不等于还录得下去。**
            //
            // 上面那道守卫过了之后到这一行，中间隔着一整次 `engine.stop()`——真实的
            // 采集器停下来时会等当前那条 tap 回调返回，那就是几十毫秒的窗口。就在这个
            // 窗口里，音频线程上的写盘失败可能已经把文件关掉了（`append` 的 catch 分支：
            // 磁盘满了就当场关文件，保住已经录到的部分）。这时候照着稿子念
            // 「已经自动接上继续录」，用户就会接着说下去，而实际上**文件已经关了、
            // 麦克风还开着**，后面每一个字都不进任何文件。等他练完点开回听才发现后半段
            // 没了，而且永远搞不清是哪半段、为什么。
            //
            // 所以宣告恢复之前必须重新确认写入端还活着：`writer == nil` 就是「已经关了」。
            // 这一次实测复现过（`testRestartDoesNotClaimRecoveryWhenTheFileWasClosedDuringTheRestart`），
            // 别把这个判断改回无条件。
            //
            // **这里只问 `writer`，不问 `stopped`。** `stopped` 为真而文件还开着，说明
            // 用户刚点了「练完」、`finish()` 正等着我们这一段落定：它会把文件正常关好、
            // 把麦克风关掉，这次切换也确实接上过，中断照实报给用户才对
            // （`testFinishDuringADeviceChangeStopsTheMicrophoneAndStillReportsTheInterruption`）。
            // 真正不能宣告恢复的，是文件已经关掉的那一种。
            let writeSideIsAlive = writer != nil
            if writeSideIsAlive {
                interruptions.append(RecordingInterruption(at: at, recovered: true))
                warnings.append(
                    "录音中途因为音频输入设备变化（多半是插拔了耳机）断了一下，已经自动接上继续录，"
                    + "切换的那一两秒没有录进去。"
                    + "下一步：回听时留意这一小段；若刚好是关键回答，把这道题再练一次。")
            } else {
                interruptions.append(RecordingInterruption(at: at, recovered: false))
                warnings.append(
                    "录音中途因为音频输入设备变化（多半是插拔了耳机）断了一下，这一次没有接着录："
                    + "录音文件在那之前已经因为写入失败关掉了，麦克风也已经关上，"
                    + "后面说的话不会再录进去。"
                    + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响。"
                    + "下一步：点「我练完了」结束这次练习并回听已经录到的部分；"
                    + "下一次练习会重新开始录。")
            }
            state.unlock()
            // 文件都关了，麦克风却是我们刚刚亲手重新打开的——不关掉它，练习结束前
            // 那盏灯就一直亮着，而它录下的东西没有任何人收。
            // 锁外调，理由同 `append` 里那一句：真实的采集器停下来会等 tap 回调返回。
            if !writeSideIsAlive { engine.stop() }
        } catch {
            // 接不回来就收尾。**先关文件再报错**：已经录到的部分必须留在磁盘上。
            state.lock()
            closeWriterLocked()
            interruptions.append(RecordingInterruption(at: at, recovered: false))
            warnings.append(
                "录音在中途停了，因为音频输入设备变了而且接不回来：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响，可以接着练完。"
                + "下一步：把耳机插回去，或到「系统设置 › 声音 › 输入」重新选一个麦克风；"
                + "下一次练习会重新开始录。")
            state.unlock()
        }
    }

    /// 关文件，并把时长**在同一次持锁里**写回去。调用方必须已经持有 `state`。
    ///
    /// 两件事之间只要有一条缝（先置「已关」、解锁、再慢慢写 m4a 索引、最后才写回
    /// 时长），并发的 `finish()` 就会读到那个还没写回去的 0，把它当成
    /// 「一秒都没录到」：删掉文件、返回空路径、还告诉用户什么都没录到。
    /// **那不是静默丢录音，是主动删。** 复审已实测复现，别再把它拆开。
    ///
    /// 重复调用只有第一次生效：`writer == nil` 就是「已经关了」。
    private func closeWriterLocked() {
        guard let target = writer else { return }
        writer = nil
        duration = target.finish()
    }

    private func closeWriter() {
        state.lock()
        closeWriterLocked()
        state.unlock()
    }

    /// 一秒都没录到：收拾那个空文件，并说清楚发生了什么、下一步做什么。
    ///
    /// **删成功与删失败是两套说法，不能共用一套。** 删失败时（文件被别的程序占着、
    /// 权限不对、只读卷）那个 0 字节文件还留在 recordings/ 里：
    /// `RecordingStore.usage()` 会把它算进占用，`orphanFileNames`（明写「不主动删」）
    /// 会把它当成孤儿报出来。这时候还念「已经删掉了」，界面上就会同时出现
    /// 「已经删掉了」和「有 1 个孤儿录音占着地方」两句互相打脸的话。
    private func disposeOfTheEmptyFile() -> String {
        let nothingRecorded = "这次一秒录音都没录到"
        let checkTheMicrophone =
            "打开「系统设置 › 声音 › 输入」，确认选中的麦克风在你说话时有输入电平；"
            + "若暂时不需要录音，到「录音设置」（⌘,）把开关关掉，界面就不会再提这件事。"

        let manager = FileManager.default
        do {
            try manager.removeItem(at: fileURL)
            return "\(nothingRecorded)，已经把空文件删掉了。下一步：\(checkTheMicrophone)"
        } catch {
            guard manager.fileExists(atPath: fileURL.path) else {
                // 文件本来就不在（多半根本没建出来）。没什么可删的，就别提删除这件事，
                // 免得用户去数据目录里找一个不存在的文件。
                return "\(nothingRecorded)。下一步：\(checkTheMicrophone)"
            }
            return "\(nothingRecorded)，那个 0 字节的空文件还留在 \(relativePath)，"
                + "删它的时候失败了：\(error.localizedDescription)。"
                + "它会被算进录音占用，也会在「录音设置」里被当成孤儿录音报出来。"
                + "下一步：先确认没有别的程序正开着这个文件，"
                + "再到「录音设置」（⌘,）点「打开录音文件夹」把它删掉；"
                + "另外还要\(checkTheMicrophone)"
        }
    }
}
