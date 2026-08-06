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
    private var observer: (any NSObjectProtocol)?
    private var tapped = false

    public init() {}

    public func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
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
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            onBuffer(buffer)
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

    /// 允许在没 start 过时调用，必须无害。注意此路径**不碰 inputNode**——
    /// 碰它会在没权限的进程里触发麦克风初始化。
    public func stop() {
        if engine.isRunning { engine.stop() }
        guard tapped else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapped = false
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if engine.isRunning { engine.stop() }
    }
}
