import Foundation

/// 语音结束判定状态机的状态。
///
/// 新目标提供了直接信号（`AXImage desc="Voice chat active"`），因此无需依赖
/// 「语音界面消失 且 输入框重新出现」这类间接启发式；仍需去抖动，
/// 因为轮询可能撞上界面重绘的瞬间空窗。
public struct VoiceEndState: Equatable, Sendable {
    public var seenActive: Bool = false
    public var inactiveTicks: Int = 0
    public var shouldFinalize: Bool = false
    public var reason: String = ""

    public init() {}

    public init(seenActive: Bool, inactiveTicks: Int, shouldFinalize: Bool, reason: String) {
        self.seenActive = seenActive
        self.inactiveTicks = inactiveTicks
        self.shouldFinalize = shouldFinalize
        self.reason = reason
    }
}

/// 语音结束判定状态机。
///
/// 依据「语音活跃」信号直接推断，不再对译上游 voice-end-policy.mjs 的
/// 界面消失/输入框重现启发式（该前提在新目标上不成立：输入框与语音控制
/// 条并排共存）。仅保留去抖动以吸收轮询撞上界面重绘瞬间空窗的情况。
public enum VoiceEndPolicy {
    /// 轮询间隔 500ms → 约 1.5 秒去抖。
    public static let requiredInactiveTicks = 3

    public static func advance(previous: VoiceEndState, voiceActive: Bool, busy: Bool) -> VoiceEndState {
        let seenActive = previous.seenActive || voiceActive

        let inactiveTicks = (!busy && seenActive && !voiceActive)
            ? previous.inactiveTicks + 1
            : 0

        let shouldFinalize = !busy && inactiveTicks >= requiredInactiveTicks

        return VoiceEndState(
            seenActive: seenActive,
            inactiveTicks: inactiveTicks,
            shouldFinalize: shouldFinalize,
            reason: shouldFinalize ? "voice-indicator-gone" : ""
        )
    }
}
