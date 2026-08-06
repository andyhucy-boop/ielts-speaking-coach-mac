import Foundation

/// 一次 AX 采样里读到的一个文本碎片。
///
/// 由 `ChatGPTBridge` 的采样器产出，由 `TranscriptAssembler` 消费。
/// 定义在 Core 是为了让两边共享同一个数据结构而不产生反向依赖
/// （Bridge 依赖 Core，Core 不依赖任何人）。
public struct TranscriptFragment: Equatable, Sendable {
    public let speaker: TranscriptSpeaker
    public let text: String

    public init(speaker: TranscriptSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}
