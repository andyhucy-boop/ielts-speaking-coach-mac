import Foundation

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var lengthDays: Int             // 7 | 14 | 30
    public var createdAt: String
    public var days: [PlanDay]

    public var isComplete: Bool { days.allSatisfy(\.isComplete) }
}

public struct PlanDay: Codable, Equatable, Sendable, Identifiable {
    public var id: Int                     // 第几天，从 1 开始
    public var questionIds: [String]
    public var completedQuestionIds: [String]

    /// 上游规则：当天全部题目都完成，这一天才算完成。
    public var isComplete: Bool {
        !questionIds.isEmpty && Set(questionIds).isSubset(of: Set(completedQuestionIds))
    }
}
