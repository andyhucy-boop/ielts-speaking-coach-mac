import Foundation
import IELTSCoachCore

/// 计划页表单上的当前选择。还没落盘，只是用户正在挑的东西。
public struct PlanDraft: Equatable, Sendable {
    public var lengthDays: Int
    public var focusPart: FocusPart

    public init(lengthDays: Int = 7, focusPart: FocusPart = .fullMock) {
        self.lengthDays = lengthDays
        self.focusPart = focusPart
    }
}

public struct PlanDraftPreview: Equatable, Sendable {
    public let questionCount: Int
    /// 形如「每天 3 题」或「每天 3–4 题」；不能生成时为空字符串
    public let perDayText: String
    public let canBuild: Bool
    /// 不能生成时的中文说明（发生了什么 + 下一步）；能生成时为空字符串
    public let blockingReason: String

    public init(questionCount: Int, perDayText: String, canBuild: Bool, blockingReason: String) {
        self.questionCount = questionCount; self.perDayText = perDayText
        self.canBuild = canBuild; self.blockingReason = blockingReason
    }
}

public enum PlanDraftPreviewBuilder {
    /// 可行性判据**只有一处**：`PlanScope.blockingReason`。
    /// 这里绝对不能再写一套自己的判断——预览说能生成、点下去却报错，
    /// 是最伤信任的一类界面缺陷。
    public static func preview(state: CoachState, draft: PlanDraft) -> PlanDraftPreview {
        let count = PlanScope.select(from: state.questions, focusPart: draft.focusPart).count
        if let reason = PlanScope.blockingReason(questionCount: count,
                                                 lengthDays: draft.lengthDays,
                                                 focusPart: draft.focusPart) {
            return PlanDraftPreview(questionCount: count, perDayText: "",
                                    canBuild: false, blockingReason: reason)
        }
        let base = count / draft.lengthDays
        let remainder = count % draft.lengthDays
        let perDay = remainder == 0 ? "每天 \(base) 题" : "每天 \(base)–\(base + 1) 题"
        return PlanDraftPreview(questionCount: count, perDayText: perDay,
                                canBuild: true, blockingReason: "")
    }
}
