import AVFoundation
import Foundation

/// 真实的麦克风采集。**只录麦克风，不录任何系统音频**——
/// 录 ChatGPT 的声音需要「屏幕录制」权限，这个代价已经明确判定为不值
/// （DEFINITION-OF-DONE 第 4 节、ROADMAP 3.3）。考官问了什么由逐字稿给文字。
///
/// **本类不做单元测试。** 一调 start() 就打开真麦克风，而 `swift test` 跑的是
/// 没有 bundle id、没有 Info.plist 的命令行进程，调用会崩溃或挂住。
/// 它的正确性由 Task 11 的人工验收保证；编排逻辑的正确性由 RecordingSession 的
/// 单元测试保证——这正是把它藏在 protocol 后面的理由。
///
/// 唯一不碰硬件、因而必须测的那一部分（什么时候可以就地停引擎、
/// 两条线不能同时进采集器）被拆进了 `CaptureWorkQueue`，见
/// `CaptureWorkQueueTests`。
public final class AVAudioEngineCapture: AudioCaptureEngine, @unchecked Sendable {
    /// `AudioCaptureEngine` 明写这个属性会被跨线程读写（界面线程装它、通知线程读它），
    /// 裸的 stored property 在这里就是一次真实的数据竞争，所以加锁存取。
    /// 发回调时**不握锁**——回调里会调到 `stop()` / `start(onBuffer:)`。
    public var onConfigurationChange: (@Sendable () -> Void)? {
        get { callbackLock.lock(); defer { callbackLock.unlock() }; return _onConfigurationChange }
        set { callbackLock.lock(); _onConfigurationChange = newValue; callbackLock.unlock() }
    }

    private var _onConfigurationChange: (@Sendable () -> Void)?
    private let callbackLock = NSLock()

    private let engine = AVAudioEngine()
    /// 下面这两位**只在 `work` 上读写**（`deinit` 除外，理由见那里）。
    /// 它们同样是跨线程的：设备变化走主线程，写盘失败后的收摊走音频线程。
    /// 不互斥的话 `tapped` 会被撕裂——`removeTap` 调两次，或者 tap 装上了
    /// `tapped` 却是 false，此后 `stop()` 直接返回，练完了麦克风还挂着一个 tap。
    private var observer: (any NSObjectProtocol)?
    private var tapped = false
    private let work = CaptureWorkQueue()

    public init() {}

    public func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        // 身处 tap 回调时不能往工作台上排同步的活：工作台上的活会等 tap 回调返回，
        // 反过来等就是死锁（铁律 7：禁止无限等待）。走到这里说明调用方违反了
        // `AudioCaptureEngine` 的约定——onBuffer 里只允许调 `stop()`。
        // 今天 `RecordingSession` 不会这么干（重启采集是主线程上的事），
        // 这条守卫是为了万一有人改了那边：宁可这次不重启，也不能把整个界面挂住。
        guard !work.isInsideTapCallback else {
            throw RecordingEngineError.engineStartFailed(
                "录音在中途重启麦克风时撞上了内部的调用时序问题，这次没有重启采集，"
                + "已经录到的部分不会丢，练习本身不受影响。"
                + "下一步：点「我练完了」结束这次练习并回听已经录到的部分；"
                + "下一次练习会重新开始录。")
        }
        try work.perform { try startOnTheWorkQueue(onBuffer: onBuffer) }
    }

    /// 允许在没 start 过时调用，必须无害。注意此路径**不碰 inputNode**——
    /// 碰它会在没权限的进程里触发麦克风初始化。
    ///
    /// **这里绝不能就地停引擎。** `AudioCaptureEngine.stop()` 的契约明写它可能在
    /// onBuffer 回调里被调用（磁盘写满时 `RecordingSession.append` 当场收摊），
    /// 而 `AVAudioEngine.stop()` / `removeTap(onBus:)` 会等当前这条 tap 回调返回。
    /// 判断与挪走这件事交给 `CaptureWorkQueue`：在 tap 回调里就挪到队列上做，
    /// 在别的线程上仍然是「返回时麦克风已经真的关了」——用户点「我练完了」时
    /// `RecordingSession.finish()` 指望的就是后面这一条。
    public func stop() {
        work.performOffTheTapThread { [self] in
            if engine.isRunning { engine.stop() }
            guard tapped else { return }
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
    }

    deinit {
        // 这里不排队：还有活排在 `work` 上时，那条活强引用着 self，deinit 根本不会
        // 被调到；能走到这里就说明没有别的线程还在碰这些状态了。
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if engine.isRunning { engine.stop() }
    }

    // MARK: - 私有（以下全部在 `work` 上跑）

    private func startOnTheWorkQueue(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        // 每次 start 都要重新读一次输入格式。拔了耳机之后格式会变，
        // 拿着旧格式去装 tap 会直接崩。
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingEngineError.noInputDevice(
                "系统现在没有可用的麦克风输入设备，这次不会录音，练习本身不受影响。"
                + "下一步：到「系统设置 › 声音 › 输入」里选一个麦克风，然后重新开始一次练习。")
        }

        if tapped { input.removeTap(onBus: 0); tapped = false }
        // 捕获 `work` 而不是 self：tap 由引擎持有，捕获 self 就是一个环。
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [work] buffer, _ in
            // 打上「这条线程正在跑 tap 回调」的标记。回调里会调到 `stop()`
            // （写盘失败时当场收摊），`stop()` 靠这个标记决定不要就地停引擎。
            work.markingTapCallback { onBuffer(buffer) }
        }
        tapped = true

        if observer == nil {
            // 插拔耳机、切换声卡、蓝牙断连都会发这个通知，同时引擎会停下来。
            // 这里只负责报告，重启与否由 RecordingSession 决定——那段逻辑必须可测。
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                self?.onConfigurationChange?()
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapped = false
            throw RecordingEngineError.engineStartFailed(
                "打不开麦克风：\(error.localizedDescription)。这次不会录音，练习本身不受影响。"
                + "下一步：确认没有别的程序独占麦克风（视频会议、录屏工具常见），"
                + "再到「系统设置 › 隐私与安全性 › 麦克风」确认本应用是打开的。")
        }
    }
}
