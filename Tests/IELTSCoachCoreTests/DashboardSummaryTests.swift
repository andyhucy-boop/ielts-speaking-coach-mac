import XCTest
@testable import IELTSCoachCore

final class DashboardSummaryTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func session(_ id: String, startedAt: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, said: String, occurrences: Int) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: said, correction: "c", whyItMatters: "w",
                    occurrences: occurrences, sourceSessionIds: ["s"], lastSeenAt: "t")
    }

    private func target(_ key: String, status: String, evidence: [String] = []) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "L-\(key)", status: status, evidence: evidence,
                         sourceSessionId: "s-\(key)", createdAt: "t")
    }

    private func question(_ id: String, status: String = "new") -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "P-\(id)", status: status)
    }

    func testEmptyStateProducesAllZerosAndNoPlan() {
        let summary = DashboardSummary.build(state: .empty(), now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.questionTotal, 0)
        XCTAssertEqual(summary.sessionTotal, 0)
        XCTAssertEqual(summary.weekDone, 0)
        XCTAssertEqual(summary.weekGoal, 5)
        XCTAssertNil(summary.plan)
        XCTAssertTrue(summary.topIssues.isEmpty)
    }

    /// 2026-08-06 跨阶段复审补入：每周目标是用户设置里的东西（Phase 7 Task 1）。
    /// 写死 5 的话，App 首页显示 3、Codex 里问出来是 5，两处数字对不上而且没人查得到。
    func testWeekGoalFollowsTheUsersSetting() {
        var state = CoachState.empty()
        state.settings.weeklyGoal = 3
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekGoal, 3)
    }

    func testCountsPracticedQuestions() {
        var state = CoachState.empty()
        state.questions = [question("a", status: "practiced"), question("b"), question("c", status: "practiced")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.questionTotal, 3)
        XCTAssertEqual(summary.questionPracticed, 2)
    }

    func testWeekProgressCountsOnlyThisWeek() {
        // 取的日期离周界都超过 14 小时，任何时区下都不会漂到隔壁周去，
        // 免得这条测试在别的机器上莫名其妙地红。2026-08-03 是周一。
        var state = CoachState.empty()
        state.sessions = [
            session("in-1", startedAt: "2026-08-05T12:00:00Z"),
            session("in-2", startedAt: "2026-08-04T12:00:00Z"),
            session("out", startedAt: "2026-07-20T12:00:00Z")
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 2)
        XCTAssertEqual(summary.sessionTotal, 3)
    }

    func testUnparsableStartedAtDoesNotCountAndDoesNotCrash() {
        var state = CoachState.empty()
        state.sessions = [session("weird", startedAt: "上周三下午")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 0)
        XCTAssertEqual(summary.sessionTotal, 1)
    }

    // MARK: - 本周次数必须与首页四格是同一个数（2026-08-07 复审补入）

    /// Phase 4 之前的数据、或写入时漏了 `startedAt` 的记录，时间只剩在 id 的日期前缀里
    /// （`SessionTimelineTests.testFallsBackToDatePrefixOfTheIDWhenStartedAtIsEmpty` 里
    /// 说的就是这种真实数据）。`TrainingStats`（首页四格）会退回从 id 取时间，
    /// 这里也必须退回：否则同一份 state.json，App 首页显示「本周 1/5」、
    /// Codex 里问 `get_dashboard_data` 回 0/5，两边都不报错，用户无从判断谁是真的。
    func testWeekDoneFallsBackToTheDateInTheSessionIDLikeTheHomeScreenDoes() {
        var state = CoachState.empty()
        state.sessions = [session("2026-08-05-001", startedAt: "")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 1, "startedAt 空但 id 带日期的记录必须算进本周")
        XCTAssertEqual(summary.undatedSessionCount, 0, "它的时间读得出来，不该算成「读不出时间」")
    }

    /// 直接把两个数放在一起比。谁改了其中一处而没改另一处，这条就红。
    func testWeekDoneAgreesWithTheHomeScreenStatOnTheSameState() {
        // 各条日期离周界都超过 14 小时，任何时区下都不会漂到隔壁周。
        var state = CoachState.empty()
        state.sessions = [
            session("2026-08-05-001", startedAt: ""),                     // 时间只在 id 里
            session("2026-08-04-001", startedAt: "2026-08-04T12:00:00Z"), // 本周
            session("2026-07-20-001", startedAt: "2026-07-20T12:00:00Z"), // 上上周
            session("sync-1754123456", startedAt: "")                     // 两处都读不出时间
        ]
        let now = date("2026-08-05T12:00:00Z")
        let stats = TrainingStats.compute(state: state, now: now)
        let summary = DashboardSummary.build(state: state, now: now)

        XCTAssertEqual(summary.weekDone, stats.weeklyDone,
                       "App 首页与 MCP 的 get_dashboard_data 必须是同一个数")
        XCTAssertEqual(summary.weekDone, 2)
        XCTAssertEqual(summary.undatedSessionCount, stats.undatedSessionCount)
        XCTAssertEqual(summary.undatedSessionCount, 1)
        XCTAssertEqual(summary.sessionTotal, 4, "读不出时间也还是练过的一场")
    }

    /// 数字算少了却一个字都不报，正是本项目最忌讳的失败形态（铁律 7）。
    /// 首页四格会说「另有 N 场练习读不出时间，没能算进本周」，
    /// MCP 这边必须有同一句话可说，否则用户在 Codex 里看到的少一次也不知道。
    func testUndatedSessionsAreCountedAndExplainedInsteadOfSilentlyDropped() throws {
        var state = CoachState.empty()
        state.sessions = [session("weird", startedAt: "上周三下午"),
                          session("2026-08-05-002", startedAt: "2026-08-05T12:00:00Z")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 1)
        XCTAssertEqual(summary.sessionTotal, 2)
        XCTAssertEqual(summary.undatedSessionCount, 1)

        let warning = try XCTUnwrap(summary.warnings.first, "有算不进去的场次就必须有话说")
        XCTAssertTrue(warning.contains("1 场"), "要说清楚是几场，光说「有数据读不出来」没法核对：\(warning)")
        XCTAssertTrue(warning.contains("下一步"),
                      "只说发生了什么、不说下一步做什么，等于没说（铁律 6）：\(warning)")
    }

    func testNoWarningWhenEverySessionHasATime() {
        var state = CoachState.empty()
        state.sessions = [session("2026-08-05-001", startedAt: "2026-08-05T12:00:00Z"),
                          session("2026-08-04-001", startedAt: "")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.undatedSessionCount, 0)
        XCTAssertTrue(summary.warnings.isEmpty,
                      "没有出问题就别报警——次次都喊，真出问题时没人会看：\(summary.warnings)")
    }

    func testPlanProgressPointsAtTheFirstIncompleteDay() throws {
        var state = CoachState.empty()
        let questions = (1...14).map { question("q\($0)") }
        state.questions = questions
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for id in plan.days[0].questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) }
        state.plan = plan

        let progress = try XCTUnwrap(DashboardSummary.build(state: state,
                                                            now: date("2026-08-05T12:00:00Z")).plan)
        XCTAssertEqual(progress.lengthDays, 7)
        XCTAssertEqual(progress.completedDays, 1)
        XCTAssertEqual(progress.currentDay, 2)
        XCTAssertEqual(progress.todayQuestionIds, plan.days[1].questionIds)
    }

    func testFinishedPlanHasNoCurrentDay() throws {
        var state = CoachState.empty()
        let questions = (1...7).map { question("q\($0)") }
        state.questions = questions
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for day in plan.days { for id in day.questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) } }
        state.plan = plan

        let progress = try XCTUnwrap(DashboardSummary.build(state: state,
                                                            now: date("2026-08-05T12:00:00Z")).plan)
        XCTAssertNil(progress.currentDay)
        XCTAssertTrue(progress.todayQuestionIds.isEmpty)
    }

    func testTopIssuesAreOrderedByOccurrencesAndTruncated() {
        var state = CoachState.empty()
        state.issues = [
            issue("i1", said: "a", occurrences: 1),
            issue("i2", said: "b", occurrences: 9),
            issue("i3", said: "c", occurrences: 5)
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"),
                                             topIssueLimit: 2)
        XCTAssertEqual(summary.topIssues.map(\.id), ["i2", "i3"])
        XCTAssertEqual(summary.issueTotal, 3, "截断的是展示条数，总数必须是全量")
    }

    /// 回归护栏，**没有对应的突变**：Swift 的 `sorted` 在小数组上恰好是稳定的，
    /// 把 offset 兜底去掉这条也可能不变红。留着它是为了将来换排序实现时兜住，
    /// 别把它当成「这段逻辑被测住了」的证据。
    func testEqualOccurrencesKeepTheirOriginalOrder() {
        var state = CoachState.empty()
        state.issues = [issue("i1", said: "a", occurrences: 3),
                        issue("i2", said: "b", occurrences: 3),
                        issue("i3", said: "c", occurrences: 3)]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.topIssues.map(\.id), ["i1", "i2", "i3"])
    }

    func testRetiredTargetsAreExcludedAndTheRestAreRanked() {
        var state = CoachState.empty()
        state.issues = [issue("i1", said: "I very like it.", occurrences: 4)]
        state.targets = [
            target("cold", status: "new"),
            target("retired-one", status: "retired", evidence: ["I very like it."]),
            target("hot", status: "new", evidence: ["I very like it."])
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.nextTargets.map(\.targetKey), ["hot", "cold"],
                       "证据命中高频错题的目标要排前面，已退休的一个都不能出现")
    }

    func testTargetLimitIsRespected() {
        var state = CoachState.empty()
        state.targets = (1...5).map { target("t\($0)", status: "new") }
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"),
                                             targetLimit: 2)
        XCTAssertEqual(summary.nextTargets.count, 2)
    }
}
