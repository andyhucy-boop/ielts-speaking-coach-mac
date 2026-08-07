import Foundation

public struct PlanProgress: Equatable, Sendable {
    public let lengthDays: Int
    public let completedDays: Int
    /// 第一个还没做完的那天（从 1 开始）。全部做完时为 nil。
    public let currentDay: Int?
    public let todayQuestionIds: [String]

    public init(lengthDays: Int, completedDays: Int, currentDay: Int?, todayQuestionIds: [String]) {
        self.lengthDays = lengthDays; self.completedDays = completedDays
        self.currentDay = currentDay; self.todayQuestionIds = todayQuestionIds
    }
}

/// 首页与 MCP 的 get_dashboard_data 共用的聚合结果。纯函数：吃进 state，吐出数字，不做 IO。
public struct DashboardSummary: Equatable, Sendable {
    public let questionTotal: Int
    public let questionPracticed: Int
    public let sessionTotal: Int
    public let weekDone: Int
    public let weekGoal: Int
    public let issueTotal: Int
    public let vocabularyTotal: Int
    public let topIssues: [IssueRecord]
    public let nextTargets: [RetrainingTarget]
    public let plan: PlanProgress?

    public init(questionTotal: Int, questionPracticed: Int, sessionTotal: Int, weekDone: Int,
                weekGoal: Int, issueTotal: Int, vocabularyTotal: Int, topIssues: [IssueRecord],
                nextTargets: [RetrainingTarget], plan: PlanProgress?) {
        self.questionTotal = questionTotal; self.questionPracticed = questionPracticed
        self.sessionTotal = sessionTotal; self.weekDone = weekDone; self.weekGoal = weekGoal
        self.issueTotal = issueTotal; self.vocabularyTotal = vocabularyTotal
        self.topIssues = topIssues; self.nextTargets = nextTargets; self.plan = plan
    }

    /// - Parameter weeklyGoal: 传 nil 就用用户在设置里定的那个数
    ///   （`CoachSettings.weeklyGoal`，Phase 7 Task 1 加的）。
    ///   **不要写死 5。** 写死的话，用户把每周目标改成 3，App 首页显示 3、
    ///   Codex 里问 `get_dashboard_data` 却回 5，两处数字对不上，而且没人会想到去查这里。
    public static func build(state: CoachState, now: Date, weeklyGoal: Int? = nil,
                             topIssueLimit: Int = 5, targetLimit: Int = 3) -> DashboardSummary {
        let goal = weeklyGoal ?? state.settings.weeklyGoal
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        // 用 CoachTime.parse 而不是裸的 ISO8601DateFormatter（Phase 7 Task 1）：
        // 后者解析不了带小数秒的时间戳，那类记录会被静默当成「没有时间」而不计入本周——
        // 数字算少了却不报错，正是本项目最忌讳的失败形态。
        //
        // 解析不出时间的会话不计入本周，但仍计入总数——
        // 旧数据或手工改过的数据不该让这个数字变成 0 或者崩掉。
        let weekDone = state.sessions.filter { session in
            guard let week, let started = CoachTime.parse(session.startedAt) else { return false }
            return week.contains(started)
        }.count

        let planProgress = state.plan.map { plan -> PlanProgress in
            let firstIncomplete = plan.days.first { !$0.isComplete && !$0.questionIds.isEmpty }
            return PlanProgress(lengthDays: plan.lengthDays,
                                completedDays: plan.days.filter(\.isComplete).count,
                                currentDay: firstIncomplete?.id,
                                todayQuestionIds: firstIncomplete?.questionIds ?? [])
        }

        return DashboardSummary(
            questionTotal: state.questions.count,
            questionPracticed: state.questions.filter { $0.status == "practiced" }.count,
            sessionTotal: state.sessions.count,
            weekDone: weekDone,
            weekGoal: goal,
            issueTotal: state.issues.count,
            vocabularyTotal: state.vocabulary.count,
            topIssues: IssueRanking.top(state.issues, limit: topIssueLimit),
            nextTargets: Array(RetrainingPolicy.rank(targets: state.targets, issues: state.issues)
                .prefix(targetLimit)),
            plan: planProgress)
    }
}
