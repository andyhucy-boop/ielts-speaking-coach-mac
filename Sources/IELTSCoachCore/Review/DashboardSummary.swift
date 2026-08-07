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
    /// 诊断字段：`startedAt` 与 id 都解析不出时间、因此进不了任何一周的场次。
    /// 它们仍然算进 `sessionTotal`，只是没算进 `weekDone`。
    ///
    /// **非 0 时调用方必须把 `warnings` 原样说给用户听**（铁律 7）：
    /// 数字算少了却一个字都不报，用户没有任何办法发现。首页四格走的是
    /// `TrainingStats.undatedSessionCount`（`TodayViewModel.weekTile` 里那句
    /// 「另有 N 场练习读不出时间」），MCP 这边靠这个字段说同一件事。
    public let undatedSessionCount: Int
    public let issueTotal: Int
    public let vocabularyTotal: Int
    public let topIssues: [IssueRecord]
    public let nextTargets: [RetrainingTarget]
    public let plan: PlanProgress?

    public init(questionTotal: Int, questionPracticed: Int, sessionTotal: Int, weekDone: Int,
                weekGoal: Int, undatedSessionCount: Int, issueTotal: Int, vocabularyTotal: Int,
                topIssues: [IssueRecord], nextTargets: [RetrainingTarget], plan: PlanProgress?) {
        self.questionTotal = questionTotal; self.questionPracticed = questionPracticed
        self.sessionTotal = sessionTotal; self.weekDone = weekDone; self.weekGoal = weekGoal
        self.undatedSessionCount = undatedSessionCount
        self.issueTotal = issueTotal; self.vocabularyTotal = vocabularyTotal
        self.topIssues = topIssues; self.nextTargets = nextTargets; self.plan = plan
    }

    /// 「这些数字为什么可能偏小」的中文说明，每条都同时说清发生了什么与下一步做什么。
    /// 界面与 MCP 都必须把它显示出来——`get_dashboard_data` 要把它拼进 note，
    /// 否则用户在 Codex 里看到的本周次数少一次，而屏幕上没有任何线索。
    /// 没有问题时返回空数组：次次都喊警告，真出问题时就没人看了。
    public var warnings: [String] {
        guard undatedSessionCount > 0 else { return [] }
        // 措辞不把话说满：读不出时间的那几场也可能本来就不在本周，
        // 所以说的是「可能少了」而不是「一定少了」——统计里说满了话，
        // 用户核对一次发现对不上，以后所有提示他都不会再信。
        return ["有 \(undatedSessionCount) 场练习读不出练习时间"
            + "（startedAt 空着或写坏了，场次 id 也不以 YYYY-MM-DD 开头），"
            + "它们进不了任何一周，所以「本周训练 \(weekDone)/\(weekGoal)」可能比你实际练的次数少。"
            + "下一步：打开数据目录里的 state.json，在 sessions 里找到这几条记录，"
            + "把 startedAt 补成练习当天的时间戳（形如 2026-08-05T10:00:00Z），补上就会计进本周。"]
    }

    /// - Parameter weeklyGoal: 传 nil 就用用户在设置里定的那个数
    ///   （`CoachSettings.weeklyGoal`，Phase 7 Task 1 加的）。
    ///   **不要写死 5。** 写死的话，用户把每周目标改成 3，App 首页显示 3、
    ///   Codex 里问 `get_dashboard_data` 却回 5，两处数字对不上，而且没人会想到去查这里。
    public static func build(state: CoachState, now: Date, weeklyGoal: Int? = nil,
                             topIssueLimit: Int = 5, targetLimit: Int = 3) -> DashboardSummary {
        let goal = weeklyGoal ?? state.settings.weeklyGoal
        // 「本周练了几次」不在这里重算，直接取首页四格用的那一份（TrainingStats.compute）。
        //
        // 2026-08-07 复审修正：这里原本自己写了一遍，只认 `CoachTime.parse(startedAt)`，
        // 而 TrainingStats 在 startedAt 缺失时还会退回 `CoachTime.parseDayPrefix(session.id)`
        // ——Phase 4 之前的记录、或写入时漏了 startedAt 的记录，时间就只剩在 id 里。
        // 后果是同一份 state.json，App 首页显示「本周 1/5」、Codex 里问 get_dashboard_data
        // 回 0/5，两边都不报错，用户没有任何办法判断哪个是真的。
        // 想改「本周怎么算」，改 TrainingStats.compute 那一处；Core 里只许有一份。
        let stats = TrainingStats.compute(state: state, now: now)

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
            weekDone: stats.weeklyDone,
            weekGoal: goal,
            undatedSessionCount: stats.undatedSessionCount,
            issueTotal: state.issues.count,
            vocabularyTotal: state.vocabulary.count,
            topIssues: IssueRanking.top(state.issues, limit: topIssueLimit),
            nextTargets: Array(RetrainingPolicy.rank(targets: state.targets, issues: state.issues)
                .prefix(targetLimit)),
            plan: planProgress)
    }
}
