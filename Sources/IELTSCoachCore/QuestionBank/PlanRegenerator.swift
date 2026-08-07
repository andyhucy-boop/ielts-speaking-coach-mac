import Foundation

public struct PlanRegenerationOutcome: Equatable, Sendable {
    public let plan: TrainingPlan
    /// 从旧计划带过来、且仍在新计划里的已完成题 id，顺序与它们在新计划里的出现顺序一致。
    public let carriedOver: [String]
    /// 旧计划里已完成、但新计划范围内已经没有的题 id
    ///（换了重点 Part，或换季重新导入时被出题方删掉）。
    public let dropped: [String]
    /// 给用户看的中文说明：发生了什么 + 下一步做什么。
    public let summary: String

    public init(plan: TrainingPlan, carriedOver: [String], dropped: [String], summary: String) {
        self.plan = plan; self.carriedOver = carriedOver
        self.dropped = dropped; self.summary = summary
    }
}

/// 重新生成学习计划。**唯一的硬要求：已经练过的题，重新生成之后还是练过的。**
public enum PlanRegenerator {

    /// 把旧计划里「已完成」的标记搬到新计划上。
    ///
    /// 只按题目 id 匹配。题目 id 是内容哈希（见 QuestionBankImporter.questionID），
    /// 换季重新导入题库后同一道题的 id 不变，所以这个搬运在换季场景下依然成立——
    /// 这正是成品标准第 12 条守的东西。
    public static func carryOverProgress(from old: TrainingPlan?,
                                         to fresh: TrainingPlan) -> TrainingPlan {
        guard let old else { return fresh }
        let alreadyDone = Set(old.days.flatMap(\.completedQuestionIds))
        var updated = fresh
        for id in fresh.days.flatMap(\.questionIds) where alreadyDone.contains(id) {
            updated = PlanBuilder.markCompleted(plan: updated, questionID: id)
        }
        return updated
    }

    public static func regenerate(state: CoachState, lengthDays: Int, focusPart: FocusPart,
                                  createdAt: String) throws -> PlanRegenerationOutcome {
        let selected = PlanScope.select(from: state.questions, focusPart: focusPart)
        if let reason = PlanScope.blockingReason(questionCount: selected.count,
                                                 lengthDays: lengthDays, focusPart: focusPart) {
            throw CoachError.planImpossible(reason)
        }

        // lengthDays 不在 7/14/30 里时由 PlanBuilder 抛错，它的消息已经说清了下一步。
        var fresh = try PlanBuilder.build(questions: selected, lengthDays: lengthDays,
                                          createdAt: createdAt)
        fresh.focusPart = focusPart

        let carriedPlan = carryOverProgress(from: state.plan, to: fresh)
        let carriedOver = carriedPlan.days.flatMap(\.completedQuestionIds)

        let freshIDs = Set(fresh.days.flatMap(\.questionIds))
        var seen = Set<String>()
        let dropped = (state.plan?.days.flatMap(\.completedQuestionIds) ?? [])
            .filter { !freshIDs.contains($0) && seen.insert($0).inserted }

        return PlanRegenerationOutcome(
            plan: carriedPlan, carriedOver: carriedOver, dropped: dropped,
            summary: summary(lengthDays: lengthDays, focusPart: focusPart,
                             questionCount: selected.count,
                             carriedOver: carriedOver.count, dropped: dropped.count))
    }

    /// **只写 plan，别的一个字段都不碰。**
    /// 「重新生成计划」是重排今后练什么，不是清空练过什么。顺手把 question.status
    /// 重置成 new、或清掉 sessions 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史。
    public static func apply(_ outcome: PlanRegenerationOutcome, to state: inout CoachState) {
        state.plan = outcome.plan
    }

    // MARK: - 文案

    private static func summary(lengthDays: Int, focusPart: FocusPart, questionCount: Int,
                                carriedOver: Int, dropped: Int) -> String {
        var text = "已生成 \(lengthDays) 天计划：\(PlanScope.label(for: focusPart))，共 \(questionCount) 道题。"
        if carriedOver > 0 {
            text += "你之前练过的 \(carriedOver) 道题仍然算已完成。"
        }
        if dropped > 0 {
            text += "另有 \(dropped) 道练过的题不在新计划范围内（换了重点 Part，或换季重新导入时题库里没有它了）；"
                + "它们的练习记录与复盘仍然保留在「训练记录」和「复盘报告」里，没有丢。"
        }
        text += "下一步：回「今日训练」页点「按计划练今天」就能开始。"
        return text
    }
}
