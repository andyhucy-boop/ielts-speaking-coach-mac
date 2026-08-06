import Foundation

/// 把一场练习标记成「某个复训目标的复训会话」。
///
/// **为什么要同时记 targetKey 和 sourceSessionId：** `RetrainingTarget.targetKey` 跨 session
/// 会重复（见 Records.swift 里的注释）。只记 targetKey，会把两份不同复盘里同名的目标
/// 混成一个，复训进度就会串台——界面显示「已经换题验证过了」，其实验证的是另一次复盘
/// 里的那个目标。
public struct RetrainingLink: Codable, Equatable, Sendable {
    public var targetKey: String
    public var sourceSessionId: String

    /// 目标来源那次练习用的题目 id。**必须存下来，不能靠回查 sourceSessionId 得到**：
    /// 训练记录允许单条删除，源 session 被删之后就再也回查不到了，
    /// 而「这次算原题重练还是换题验证」必须永远能判定。
    public var originalQuestionId: String

    public init(targetKey: String, sourceSessionId: String, originalQuestionId: String) {
        self.targetKey = targetKey
        self.sourceSessionId = sourceSessionId
        self.originalQuestionId = originalQuestionId
    }

    /// 与 `RetrainingTarget.id` 同构，两边才对得上。
    public var targetID: String { "\(targetKey)@\(sourceSessionId)" }
}

/// 一场复训会话在复训里扮演的角色。
public enum RetrainingKind: String, Equatable, Sendable, CaseIterable {
    /// 重答原题。
    case original
    /// 换一道题验证——**这一项才是本产品的价值所在**：
    /// 只重练原题，分不清是真会了还是只记住了那个答案。
    case transfer
}

extension PracticeSession {
    /// 这场练习在复训里扮演什么角色。不是复训会话时为 nil。
    ///
    /// **派生而非存储**：存一个 kind 字段就有「存的值与实际题目对不上」的可能，
    /// 而这两者一旦不一致，「换题验证做过没有」这个最核心的判断就会出错。
    public var retrainingKind: RetrainingKind? {
        guard let link = retraining else { return nil }
        return questionId == link.originalQuestionId ? .original : .transfer
    }
}
