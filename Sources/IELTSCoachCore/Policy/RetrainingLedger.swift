import Foundation

/// 一个复训目标走到哪一步了。
public enum RetrainingStage: String, Equatable, Sendable, CaseIterable {
    /// 还没为它练过任何一场。
    case notStarted
    /// 重答过原题，但还没换题验证。
    case retriedOriginal
    /// 已经换过题练——**这一步才是本产品真正的价值**：
    /// 只重练原题，分不清是真会了还是只记住了那个答案。
    case triedTransfer
}

/// `RetrainingTarget.status` 的合法取值。原本只写在注释里，这里固化成类型，
/// 免得各处拼字符串拼错一个字母就静默失效。
public enum RetrainingStatus: String, Equatable, Sendable, CaseIterable {
    case new, selected, retired
}

public struct RetrainingProgress: Equatable, Sendable {
    public let targetID: String
    /// 重答原题的会话 id，按 sessions 里的先后顺序。
    public let originalRetrySessionIDs: [String]
    /// 换题验证的会话 id，按 sessions 里的先后顺序。
    public let transferSessionIDs: [String]

    public init(targetID: String, originalRetrySessionIDs: [String],
                transferSessionIDs: [String]) {
        self.targetID = targetID
        self.originalRetrySessionIDs = originalRetrySessionIDs
        self.transferSessionIDs = transferSessionIDs
    }

    public var stage: RetrainingStage {
        if !transferSessionIDs.isEmpty { return .triedTransfer }
        if !originalRetrySessionIDs.isEmpty { return .retriedOriginal }
        return .notStarted
    }
}

/// 复训台账。全是纯函数：吃进 state，吐出结果或就地改 state，不做任何 IO。
public enum RetrainingLedger {
    public static func progress(for target: RetrainingTarget,
                                sessions: [PracticeSession]) -> RetrainingProgress {
        // 必须按 targetID（key + 来源 session）匹配，不能只按 targetKey：
        // targetKey 跨 session 会重复，只按它匹配会让两份复盘里同名的目标串台。
        let mine = sessions.filter { $0.retraining?.targetID == target.id }
        return RetrainingProgress(
            targetID: target.id,
            originalRetrySessionIDs: mine.filter { $0.retrainingKind == .original }.map(\.id),
            transferSessionIDs: mine.filter { $0.retrainingKind == .transfer }.map(\.id))
    }

    /// 把复训标记挂到一条训练记录上。
    /// - Returns: 挂上了返回 true。**返回 false 时调用方必须把这件事告诉用户**，
    ///   不能当作没发生——用户会以为复训被记下了，其实台账是空的。
    @discardableResult
    public static func attach(_ link: RetrainingLink, toSessionWithID sessionID: String,
                              in state: inout CoachState) -> Bool {
        guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }
        if let existing = state.sessions[index].retraining {
            // 已经挂给别的目标了就不动它。覆盖会把另一个目标的进度悄悄抹掉。
            return existing == link
        }
        state.sessions[index].retraining = link
        return true
    }

    /// 改一个复训目标的状态。`targetID` 是 `RetrainingTarget.id`（即 "key@来源session"）。
    /// - Returns: 找到并改了返回 true；找不到返回 false，调用方须据此提示用户。
    @discardableResult
    public static func setStatus(_ status: RetrainingStatus, of targetID: String,
                                 in state: inout CoachState) -> Bool {
        guard let index = state.targets.firstIndex(where: { $0.id == targetID }) else {
            return false
        }
        state.targets[index].status = status.rawValue
        return true
    }
}
