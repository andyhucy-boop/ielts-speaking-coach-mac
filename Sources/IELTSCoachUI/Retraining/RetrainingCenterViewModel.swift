import Foundation
import IELTSCoachCore

/// 目标 → 来源练习 → 原题 这条链断在哪里。
/// **断了要说清楚，不能把这一条从列表里藏掉**——凭空消失会让用户以为练习记录丢了。
public enum RetrainingSourceIssue: Equatable, Sendable {
    /// 目标来源的那次练习记录已经不在了（多半是在训练记录里被单条删除）。
    case sessionMissing
    /// 记录还在，但题库里已经没有那道题了（多半是换季导入了新题库）。
    case questionMissing

    public var message: String {
        switch self {
        case .sessionMissing:
            return "这个目标来自的那次练习记录已经不在了，找不回当时练的是哪道题。"
                + "下一步：仍然可以带着这个目标从题库里自己挑一道题练；"
                + "「重答原题」这一条则用不了了。"
        case .questionMissing:
            return "当时那道题已经不在题库里了，多半是换季导入了新题库。"
                + "下一步：仍然可以带着这个目标从题库里自己挑一道题练；"
                + "想重答原题，就重新导入包含那道题的题库。"
        }
    }
}

public struct RetrainingItem: Equatable, Sendable, Identifiable {
    public let target: RetrainingTarget
    public let progress: RetrainingProgress
    /// 目标来源那次练的题。链断了就是 nil，此时 `sourceIssue` 非 nil。
    public let originalQuestion: Question?
    public let sourceIssue: RetrainingSourceIssue?

    public init(target: RetrainingTarget, progress: RetrainingProgress,
                originalQuestion: Question?, sourceIssue: RetrainingSourceIssue?) {
        self.target = target; self.progress = progress
        self.originalQuestion = originalQuestion; self.sourceIssue = sourceIssue
    }

    public var id: String { target.id }

    /// 「带着本题进入复训」这条路能不能走。
    public var canRetryOriginal: Bool { originalQuestion != nil }

    public var statusLabel: String {
        switch progress.stage {
        case .notStarted:
            return "还没开始复训"
        case .retriedOriginal:
            return "已重答原题 \(progress.originalRetrySessionIDs.count) 次，还差换题验证"
        case .triedTransfer:
            return "已换题验证 \(progress.transferSessionIDs.count) 次"
        }
    }
}

public struct RetrainingCenterViewModel: Sendable {
    public let state: CoachState

    public init(state: CoachState) { self.state = state }

    /// 待复训目标。**顺序直接来自 `RetrainingPolicy.rank`**：证据命中高频错题的排前面，
    /// 已退休的不参与。不要在这里另排一套——那会造出第二套说法。
    public var pending: [RetrainingItem] {
        RetrainingPolicy.rank(targets: state.targets, issues: state.issues).map(makeItem)
    }

    /// 已退休的目标。仍然列出来（折叠区），退休不等于删除。
    public var retired: [RetrainingItem] {
        state.targets
            .filter { $0.status == RetrainingStatus.retired.rawValue }
            .reversed()
            .map(makeItem)
    }

    public func item(id: String) -> RetrainingItem? {
        // 按完整身份（key@来源session）查，不能只按 targetKey：
        // targetKey 跨 session 会重复，按 key 查会取到错的那一条。
        guard let target = state.targets.first(where: { $0.id == id }) else { return nil }
        return makeItem(target)
    }

    public var emptyStateMessage: String {
        "还没有待复训的目标。下一步：先完整练一场，复盘会给出一个具体目标，它会自动出现在这里。"
    }

    // MARK: - 私有

    private func makeItem(_ target: RetrainingTarget) -> RetrainingItem {
        let progress = RetrainingLedger.progress(for: target, sessions: state.sessions)

        guard let source = state.sessions.first(where: { $0.id == target.sourceSessionId }) else {
            return RetrainingItem(target: target, progress: progress,
                                  originalQuestion: nil, sourceIssue: .sessionMissing)
        }
        guard let question = state.questions.first(where: { $0.id == source.questionId }) else {
            return RetrainingItem(target: target, progress: progress,
                                  originalQuestion: nil, sourceIssue: .questionMissing)
        }
        return RetrainingItem(target: target, progress: progress,
                              originalQuestion: question, sourceIssue: nil)
    }
}
