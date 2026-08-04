import Foundation

public enum PlanBuilder {
    public static let supportedLengths = [7, 14, 30]

    public static func build(questions: [Question], lengthDays: Int,
                             createdAt: String) throws -> TrainingPlan {
        guard supportedLengths.contains(lengthDays) else {
            throw CoachError.planImpossible(
                "计划天数只支持 7、14、30 天，收到的是 \(lengthDays)。下一步：重新选择一个受支持的天数。")
        }
        guard !questions.isEmpty else {
            throw CoachError.planImpossible(
                "题库里没有题目，无法生成计划。下一步：先在「题库」里导入一份题库。")
        }

        // 均匀分配：前 remainder 天各多分 1 题
        let base = questions.count / lengthDays
        let remainder = questions.count % lengthDays

        var days: [PlanDay] = []
        var cursor = 0
        for dayIndex in 0..<lengthDays {
            let take = base + (dayIndex < remainder ? 1 : 0)
            let slice = Array(questions[cursor..<min(cursor + take, questions.count)])
            cursor += take
            days.append(PlanDay(id: dayIndex + 1, questionIds: slice.map(\.id),
                                completedQuestionIds: []))
        }

        return TrainingPlan(lengthDays: lengthDays, createdAt: createdAt, days: days)
    }

    /// 把某题标记为已完成。同一题重复标记不会产生重复项。
    public static func markCompleted(plan: TrainingPlan, questionID: String) -> TrainingPlan {
        var updated = plan
        for index in updated.days.indices
        where updated.days[index].questionIds.contains(questionID)
            && !updated.days[index].completedQuestionIds.contains(questionID) {
            updated.days[index].completedQuestionIds.append(questionID)
        }
        return updated
    }
}
