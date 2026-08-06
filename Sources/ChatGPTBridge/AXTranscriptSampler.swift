import Foundation
import IELTSCoachCore

/// 从 ChatGPT 的 AX 树里采一次对话文本。
///
/// **只做采样，不做拼接。** 拼接去重在 `IELTSCoachCore.TranscriptAssembler`，
/// 那边是纯字符串逻辑、能测到底；这边只负责「树长什么样 → 碎片是什么」，
/// 走 `AXAccess` 接缝，用 `FakeAXAccess` 摆出任意一棵树来测。
///
/// 说话人判别依据 spec 2.3.9：一条消息的文本节点排在它自己那个复制按钮**前面**
/// （`snapshotTree()` 是深度优先前序遍历，顺序 ≈ 文档顺序），
/// 而 `Copy message` 属于用户自己那条、`Copy` 属于 ChatGPT 的回复。
/// **判不出来就记 `.unknown`，绝不猜。**
public struct AXTranscriptSampler: TranscriptSampling {
    private let access: any AXAccess
    /// 短于这个长度的文本一律丢掉。界面上到处是单字符的装饰性文本节点，
    /// 它们混进逐字稿只会让人看不下去。
    private let minimumLength: Int

    public init(access: any AXAccess, minimumLength: Int = 2) {
        self.access = access
        self.minimumLength = minimumLength
    }

    public func sample() -> TranscriptSweep {
        let nodes = access.snapshotTree()
        // 树整个是空的 = 这一次真的没读到（应用被切走、树塌了、权限出问题）。
        // 这与「树有内容但还没人说话」是两回事，后者不是失败。
        guard !nodes.isEmpty else { return .unavailable }

        var fragments: [TranscriptFragment] = []
        var pending: [String] = []

        for node in nodes {
            if node.role == "AXStaticText" {
                let value = node.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= minimumLength { pending.append(node.value) }
                continue
            }
            if let speaker = ChatGPTLabels.speakerMarker(node) {
                fragments.append(contentsOf: pending.map {
                    TranscriptFragment(speaker: speaker, text: $0)
                })
                pending.removeAll()
            }
        }

        // 扫完还剩下的：多半是正在流式输出、复制按钮还没渲染出来的那条消息。
        // **不许丢掉**——那正是刚说完的最后一句话。判不出说话人就记 unknown。
        fragments.append(contentsOf: pending.map {
            TranscriptFragment(speaker: .unknown, text: $0)
        })

        return TranscriptSweep(fragments: fragments, failure: nil)
    }
}
