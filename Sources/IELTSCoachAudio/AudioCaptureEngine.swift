import AVFoundation
import Foundation

/// 麦克风采集的抽象。真实实现是 `AVAudioEngineCapture`；测试里用假实现。
///
/// **实现方在设备变化时只负责「报告」，不得自作主张重启。** 重启与否、重启失败
/// 怎么办、要不要告诉用户，全部由 `RecordingSession` 决定——那一段逻辑必须可测，
/// 藏进真实实现里就再也测不到了。
public protocol AudioCaptureEngine: AnyObject {
    /// 输入设备发生变化（插拔耳机、切换声卡、蓝牙断连）时被调用。
    var onConfigurationChange: (@Sendable () -> Void)? { get set }

    /// 开始采集。每采到一段音频就调用一次 onBuffer。
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws

    /// 停止采集。允许在没 start 过的时候调用，必须是无害的。
    func stop()
}

/// 一个正在写入的录音文件。
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
