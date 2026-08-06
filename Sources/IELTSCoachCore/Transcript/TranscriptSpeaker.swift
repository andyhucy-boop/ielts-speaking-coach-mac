import Foundation

/// 逐字稿里一条对话是谁说的。
///
/// raw value 直接写进 `PracticeSession.TranscriptTurn.role`，与上游 state.json 兼容：
/// `"user"` 是学员，`"assistant"` 是考官（ChatGPT）。
///
/// **`unknown` 是本项目新增的第三个取值。** 实测（spec 2.3.9）里，界面上区分
/// 「谁说的」靠的是消息下方那个复制按钮（`Copy message` 属于用户自己那条，
/// `Copy` 属于 ChatGPT 的回复），而正在流式输出的消息还没有按钮。判不出来时
/// 老老实实记成 `unknown`，**不许猜**——猜错会让复训时「回看自己说过的话」
/// 显示成考官说的话，而这种错误没有任何信号提示。
///
/// 下游消费方（Phase 6 的证据装配）只挑 `role == "user"`，`unknown` 会被自然跳过，
/// 属于可接受的降级；同时 `TranscriptAssembler.completenessNote` 会如实告诉用户
/// 有多少条没能判断。
public enum TranscriptSpeaker: String, Codable, Equatable, Sendable, CaseIterable {
    case learner = "user"
    case examiner = "assistant"
    case unknown = "unknown"
}
