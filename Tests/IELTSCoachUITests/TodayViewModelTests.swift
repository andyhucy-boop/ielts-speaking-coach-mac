import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 今日训练页的取数逻辑。
///
/// 这一页是用户每天打开 App 的第一眼，最要紧的一条是**只显示前提成立的路线**：
/// 显示一条点了没用的路线，比不显示更糟——用户点下去什么也不发生，会以为程序坏了。
/// 下面一半的测试都在守这件事。
final class TodayViewModelTests: XCTestCase {
    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "P-\(id)")
    }

    private func state(plan: TrainingPlan?, questions: [Question],
                       sessions: [PracticeSession] = []) -> CoachState {
        var s = CoachState.empty()
        s.plan = plan; s.questions = questions; s.sessions = sessions
        return s
    }

    private func practiceSession(_ id: String, startedAt: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: "", transcript: [],
                        reportPath: "", recordingPath: "")
    }

    private func retrainingTarget(_ key: String, status: String) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "L", status: status, evidence: [],
                         sourceSessionId: "s1", createdAt: "t")
    }

    // MARK: - 今天该练哪几道题

    func testTodayQuestionsComeFromFirstIncompletePlanDay() throws {
        let questions = (1...14).map { question("q\($0)") }
        let plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        let vm = TodayViewModel(state: state(plan: plan, questions: questions))
        XCTAssertEqual(vm.todayQuestions.count, 2, "14 题分 7 天，每天 2 题")
        XCTAssertEqual(vm.todayQuestions.map(\.id), plan.days[0].questionIds)
    }

    func testTodaySkipsCompletedDays() throws {
        let questions = (1...14).map { question("q\($0)") }
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for id in plan.days[0].questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) }
        let vm = TodayViewModel(state: state(plan: plan, questions: questions))
        XCTAssertEqual(vm.todayQuestions.map(\.id), plan.days[1].questionIds)
    }

    // MARK: - 四条路线只显示有意义的

    func testRouteUnavailableWhenItsPreconditionIsMissing() {
        // 没有计划就不该显示「按计划练今天」，点了也没用
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")]))
        XCTAssertFalse(vm.availableRoutes.contains(.planToday))
        XCTAssertTrue(vm.availableRoutes.contains(.freePick), "有题库就该能自由选题")
    }

    func testContinueLastUnavailableWithoutSessions() {
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")]))
        XCTAssertFalse(vm.availableRoutes.contains(.continueLast))
    }

    func testFreePickUnavailableWhenBankIsEmpty() {
        let vm = TodayViewModel(state: state(plan: nil, questions: []))
        XCTAssertTrue(vm.availableRoutes.isEmpty, "题库空时一条路线都不该显示")
    }

    func testRetrainAvailableOnlyWithLiveTargets() {
        var withRetired = state(plan: nil, questions: [question("a")])
        withRetired.targets = [retrainingTarget("t1", status: "retired")]
        XCTAssertFalse(TodayViewModel(state: withRetired).availableRoutes.contains(.retrain),
                       "已退休的目标不该让「复训」路线出现")

        var withLive = withRetired
        withLive.targets.append(retrainingTarget("t2", status: "new"))
        XCTAssertTrue(TodayViewModel(state: withLive).availableRoutes.contains(.retrain))
    }

    /// 顺序不是随手排的：页面上第一条路线就是那一个主行动（规范第 4 节「每个页面最多一个主行动」）。
    /// 把「按计划练今天」挤到后面去，等于让用户每天先自己想练什么——那正是这个产品要消掉的杂事。
    func testRoutesAreOrderedWithThePlannedOneFirst() throws {
        let questions = (1...14).map { question("q\($0)") }
        let plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        var s = state(plan: plan, questions: questions,
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.targets = [retrainingTarget("t1", status: "new")]
        XCTAssertEqual(TodayViewModel(state: s).availableRoutes,
                       [.planToday, .freePick, .continueLast, .retrain])
    }

    /// 路线的文案是用户唯一能据以选择的东西。少一句副标题，那张卡片就只剩一个动词，
    /// 用户点之前不知道会发生什么（铁律 6：说清「发生了什么 + 下一步做什么」）。
    func testEveryRouteHasDistinctChineseCopy() {
        for route in PracticeRoute.allCases {
            XCTAssertFalse(route.title.isEmpty, "\(route) 缺标题")
            XCTAssertFalse(route.subtitle.isEmpty, "\(route) 缺副标题")
        }
        let titles = PracticeRoute.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "有两条路线叫同一个名字")
    }

    // MARK: - 本周进度与最近练习

    func testWeekProgressCountsOnlyThisWeek() {
        let s = state(plan: nil, questions: [question("a")], sessions: [
            practiceSession("in", startedAt: "2026-08-05T10:00:00Z"),
            practiceSession("also-in", startedAt: "2026-08-03T10:00:00Z"),
            practiceSession("out", startedAt: "2026-07-20T10:00:00Z")
        ])
        let vm = TodayViewModel(state: s,
                                today: ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z")!)
        XCTAssertEqual(vm.weekProgress.done, 2)
        XCTAssertEqual(vm.weekProgress.goal, 5)
    }

    /// 「最近练习」要真的是最近的几次，且最多五条。
    /// 按 `state.sessions` 的原顺序直接切前五条，看到的会是**最早**的五次——
    /// 这一页存在的理由之一就是「上次练了什么」。
    func testRecentSessionsAreNewestFirstAndCappedAtFive() {
        let sessions = (1...7).map { practiceSession("s\($0)", startedAt: "2026-08-0\($0)T10:00:00Z") }
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")], sessions: sessions))
        XCTAssertEqual(vm.recentSessions.map(\.id), ["s7", "s6", "s5", "s4", "s3"])
    }
}
