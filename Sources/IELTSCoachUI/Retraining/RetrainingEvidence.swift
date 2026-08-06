import Foundation
import IELTSCoachCore

/// 复训第一步要给学员看的全部材料。
public struct RetrainingEvidence: Equatable, Sendable {
    /// 复盘摘出来的原话。
    public let quotes: [String]
    /// 当时那道题的完整原答。
    public let originalAnswer: String
    /// 复盘给的高分版。**只在第一步显示**，见 RetrainingStep。
    public let modelAnswer: String
    /// 复盘写的「改了什么」。
    public let changes: [String]
    /// 逐字稿里学员自己说过的话。
    public let learnerTurns: [PracticeSession.TranscriptTurn]
    /// 材料不齐时的中文说明（发生了什么 + 下一步）。齐全时为 nil。
    public let missingNote: String?

    public init(quotes: [String], originalAnswer: String, modelAnswer: String,
                changes: [String], learnerTurns: [PracticeSession.TranscriptTurn],
                missingNote: String?) {
        self.quotes = quotes; self.originalAnswer = originalAnswer
        self.modelAnswer = modelAnswer; self.changes = changes
        self.learnerTurns = learnerTurns; self.missingNote = missingNote
    }
}

public enum RetrainingEvidenceBuilder {
    /// - Parameters:
    ///   - report: 目标来源那次练习的复盘。读不到就传 nil——**不要为了「看起来正常」编一份空的**。
    ///   - transcript: 那次练习的逐字稿。Phase 4 之前的老记录可能是空的，属正常。
    public static func build(target: RetrainingTarget,
                             report: JSONValue?,
                             transcript: [PracticeSession.TranscriptTurn]) -> RetrainingEvidence {
        let quotes = target.evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Phase 4 的逐字稿里说话人判不出来时记的是 "unknown"，绝不猜。
        // 这里只留 "user"，`unknown` 会被自然跳过——这是可接受的降级，
        // **不要为了「多点内容」把 unknown 也算成学员说过的话**：
        // 把考官的问题当成学员的原话摆出来，比少一块内容糟得多。
        let learnerTurns = transcript.filter {
            $0.role == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let report, report.objectValue != nil else {
            return RetrainingEvidence(
                quotes: quotes, originalAnswer: "", modelAnswer: "", changes: [],
                learnerTurns: learnerTurns,
                missingNote: "这个目标来源那次练习的复盘报告读不到，屏幕上只剩复盘当时摘出来的原话。"
                    + "下一步：到「复盘报告」页确认那份报告还在不在；就算读不到，也可以带着目标继续复训。")
        }

        let upgrades = report["answer_upgrades"]?.arrayValue ?? []
        let usable = upgrades.filter { !($0["original_answer"] ?? .null).isBlank }
        // 先找含有证据原话的那一条；找不到再退回第一条可用的。
        // 直接取第一条会让学员看到另一道题的答案，「回看证据」整个就是错的。
        let matched = usable.first { entry in
            let original = entry["original_answer"]?.stringValue ?? ""
            return quotes.contains { original.localizedCaseInsensitiveContains($0) }
        } ?? usable.first

        guard let matched else {
            return RetrainingEvidence(
                quotes: quotes, originalAnswer: "", modelAnswer: "", changes: [],
                learnerTurns: learnerTurns,
                missingNote: "这份复盘里没有可对照的原答（answer_upgrades 是空的，"
                    + "或者字段名与本工具读的对不上）。"
                    + "下一步：上面的原话仍然可用；想看完整原答，到「复盘报告」页打开那次的完整报告。")
        }

        return RetrainingEvidence(
            quotes: quotes,
            originalAnswer: matched["original_answer"]?.stringValue ?? "",
            modelAnswer: matched["revised_answer"]?.stringValue ?? "",
            changes: (matched["changes"]?.arrayValue ?? []).compactMap(\.stringValue),
            learnerTurns: learnerTurns,
            missingNote: nil)
    }
}
