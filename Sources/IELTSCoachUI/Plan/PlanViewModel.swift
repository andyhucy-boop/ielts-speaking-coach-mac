import Foundation
import IELTSCoachCore

public struct PlanQuestionRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// 题目已不在题库里时为 0
    public let part: Int
    public let topic: String
    /// 题目已不在题库里时，这里放的是中文说明（发生了什么 + 下一步），不是空字符串
    public let prompt: String
    public let isCompleted: Bool
    public let isMissing: Bool

    public init(id: String, part: Int, topic: String, prompt: String,
                isCompleted: Bool, isMissing: Bool) {
        self.id = id; self.part = part; self.topic = topic; self.prompt = prompt
        self.isCompleted = isCompleted; self.isMissing = isMissing
    }
}

public struct PlanDayRow: Equatable, Identifiable, Sendable {
    /// 第几天，从 1 开始
    public let id: Int
    public let items: [PlanQuestionRow]
    public let isComplete: Bool
    public let isToday: Bool

    public init(id: Int, items: [PlanQuestionRow], isComplete: Bool, isToday: Bool) {
        self.id = id; self.items = items; self.isComplete = isComplete; self.isToday = isToday
    }
}

public struct PlanViewModel: Sendable {
    public let state: CoachState

    public init(state: CoachState) { self.state = state }

    public var hasPlan: Bool { state.plan != nil }
    public var lengthDays: Int? { state.plan?.lengthDays }
    public var focusPart: FocusPart? { state.plan?.focusPart }

    /// 「今天」是第一个还有题没做完的那一天，**与日历日期无关**。
    /// 计划里没有日期字段，进度只随「练完一题」前进——用日历推进会让请假两天的人
    /// 一打开就看到「落后 2 天」，那只会让人不想练。
    /// 全部做完时返回 nil。
    public var todayNumber: Int? {
        state.plan?.days.first { !$0.isComplete && !$0.questionIds.isEmpty }?.id
    }

    /// 进度按**题目**算，不按天算。
    public var progress: (done: Int, total: Int) {
        guard let plan = state.plan else { return (0, 0) }
        let scheduled = plan.days.flatMap(\.questionIds)
        let done = Set(plan.days.flatMap(\.completedQuestionIds))
        return (scheduled.filter { done.contains($0) }.count, scheduled.count)
    }

    /// **不能用 TrainingPlan.isComplete。** 题数少于天数时尾部会留下没有题的空天，
    /// 而 PlanDay.isComplete 要求 questionIds 非空，空天永远不算完成——
    /// 那样的计划永远显示不出「已完成」，用户会一直以为自己还差一点。
    /// 旧版本与命令行生成的计划正是这种形状。
    public var isFinished: Bool {
        let current = progress
        return current.total > 0 && current.done == current.total
    }

    public var dayRows: [PlanDayRow] {
        guard let plan = state.plan else { return [] }
        let today = todayNumber
        // uniquingKeysWith 不能省：手工拼的题库里同一个 id 出现两次很常见，
        // Dictionary(uniqueKeysWithValues:) 遇到重复 key 会 fatalError 闪退整个 App。
        let byID = Dictionary(state.questions.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })

        return plan.days.filter { !$0.questionIds.isEmpty }.map { day in
            let done = Set(day.completedQuestionIds)
            let items = day.questionIds.map { id -> PlanQuestionRow in
                guard let question = byID[id] else {
                    // 空白行会让用户以为程序坏了。这里必须说清发生了什么和下一步做什么。
                    return PlanQuestionRow(
                        id: id, part: 0, topic: "",
                        prompt: "这道题已经不在题库里了（换季重新导入时可能被删掉）。"
                            + "下一步：在本页重新生成计划把它换掉，已经练过的进度不会丢。",
                        isCompleted: done.contains(id), isMissing: true)
                }
                return PlanQuestionRow(id: id, part: question.part, topic: question.topic,
                                       prompt: question.prompt,
                                       isCompleted: done.contains(id), isMissing: false)
            }
            return PlanDayRow(id: day.id, items: items,
                              isComplete: day.isComplete, isToday: day.id == today)
        }
    }
}
