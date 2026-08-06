import AVFoundation
import Foundation

/// 麦克风采集的抽象。真实实现是 `AVAudioEngineCapture`；测试里用假实现。
///
/// **实现方在设备变化时只负责「报告」，不得自作主张重启。** 重启与否、重启失败
/// 怎么办、要不要告诉用户，全部由 `RecordingSession` 决定——那一段逻辑必须可测，
/// 藏进真实实现里就再也测不到了。
///
/// ## 线程约定（实现方必须遵守，写在这里是因为漏掉哪一条都会丢用户的录音）
///
/// - 这个 protocol 的方法与属性会被**三条线程**碰：界面线程（start/stop/收尾）、
///   系统的音频线程（`onBuffer`）、系统的通知线程（`onConfigurationChange`）。
///   实现方要自己保证内部状态的线程安全，`RecordingSession` 不替它兜底。
/// - `RecordingSession` 这一侧的两个回调都可以在任意线程上被调用，它自己有锁。
public protocol AudioCaptureEngine: AnyObject {
    /// 输入设备发生变化（插拔耳机、切换声卡、蓝牙断连）时被调用。
    ///
    /// **这个属性会被跨线程读写**：`RecordingSession` 在界面线程上装它、收尾时摘它，
    /// 而系统的通知线程随时可能读它来发起回调。实现方**必须**用一把锁（或等价手段）
    /// 把它的读写包起来——一个裸的 stored property 在这里就是一次真实的数据竞争。
    ///
    /// 回调里会调到 `stop()` 与 `start(onBuffer:)`，所以实现方不要握着自己的锁去发它。
    var onConfigurationChange: (@Sendable () -> Void)? { get set }

    /// 开始采集。每采到一段音频就调用一次 onBuffer。
    ///
    /// onBuffer 在音频线程上被调用，实现方不必替它做任何序列化；
    /// 但**它可能反过来调到 `stop()`**（写盘失败时当场收摊），见下。
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws

    /// 停止采集。允许在没 start 过的时候调用，必须是无害的。
    ///
    /// **可能在 `onBuffer` 回调里被调用**，因此 `stop()` 不得等待
    /// 「当前这条 onBuffer 回调返回」——那是自锁，练习会当场卡死。
    func stop()
}

/// 一个正在写入的录音文件。
///
/// **不会被并发调用。** `RecordingSession` 把 `write` 与 `finish` 串在同一把锁里，
/// 实现方不必自己加锁。作为交换，这两个方法都**不得回调到 session**
/// （session 正握着那把锁，回调进去就是死锁），也不得长时间阻塞——
/// 用户点了「练完」的那条线程正等着 `finish` 返回。
public protocol AudioSegmentWriter: AnyObject {
    /// 把一段麦克风音频写进文件。
    ///
    /// **输入格式与上一段不同时（用户换了设备），实现方必须自己重建转换器
    /// 继续往同一个文件里写，而不是抛错。** 换设备不该换文件，更不该丢录音。
    func write(_ buffer: AVAudioPCMBuffer) throws

    /// 关掉文件并返回已写入的秒数。重复调用只有第一次真的关文件，
    /// 但每次都要返回同一个时长。
    @discardableResult
    func finish() -> TimeInterval
}
