import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PracticeRouteResolverTests: XCTestCase {

    // MARK: - 构造 state 的工具

    private func q(_ id: String, _ part: Int = 1) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "P-\(id)")
    }

    private func session(_ id: String, question: String, startedAt: String,
                         goal: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: goal, transcript: [],
                        reportPath: "reports/\(id).json", recordingPath: "")
    }

    private func target(_ key: String, label: String, session: String,
                        status: String = "new", evidence: [String] = []) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: label, status: status, evidence: evidence,
                         sourceSessionId: session, createdAt: "2026-08-01T00:00:00Z")
    }

    private func state(questions: [Question] = [], planDays: [PlanDay]? = nil,
                       sessions: [PracticeSession] = [], targets: [RetrainingTarget] = [],
                       issues: [IssueRecord] = []) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.sessions = sessions
        s.targets = targets
        s.issues = issues
        if let planDays {
            s.plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z",
                                  days: planDays, focusPart: .part1)
        }
        return s
    }

    // MARK: - 按计划练今天

    func testPlanTodayPicksTheFirstQuestionThatIsNotDoneYet() {
        let s = state(questions: [q("a"), q("b"), q("c")],
                      planDays: [PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a"]),
                                 PlanDay(id: 2, questionIds: ["c"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(route: .planToday, state: s) else {
            return XCTFail("应当能开练")
        }
        XCTAssertEqual(setup.question.id, "b", "a 今天已经练过了，再给它一次计划不会前进")
    }

    /// 上一条只覆盖「同一天内跳过已练的题」。这条覆盖的是**整天跳过**：
    /// 第 1 天全部练完之后，「按计划练今天」要走到第 2 天去。
    /// 停在已完成的那一天上，pending 会是空的，用户会被告知「题目在题库里找不到了」——
    /// 题一道没丢，这条路线却从此永远开不了练。
    func testPlanTodaySkipsDaysThatAreAlreadyFinished() {
        let s = state(questions: [q("a"), q("b")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
                                 PlanDay(id: 2, questionIds: ["b"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(route: .planToday, state: s) else {
            return XCTFail("第 1 天已经练完，第 2 天还有题，应当能开练")
        }
        XCTAssertEqual(setup.question.id, "b", "第 1 天整天都练完了，今天该练第 2 天")
    }

    /// 题数少于天数时 `PlanBuilder` 会给尾部若干天分 0 题（`PlanScope.blockingReason` 的注释
    /// 写的就是这件事），而空天的 `isComplete` 恒为 false（`PlanDay.isComplete` 要求
    /// `!questionIds.isEmpty`）。只按 `!isComplete` 挑天，解析器会永远停在一个空天上。
    func testPlanTodaySkipsDaysThatGotNoQuestionsAtAll() {
        let s = state(questions: [q("a"), q("b")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
                                 PlanDay(id: 2, questionIds: [], completedQuestionIds: []),
                                 PlanDay(id: 3, questionIds: ["b"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(route: .planToday, state: s) else {
            return XCTFail("第 2 天一道题都没分到，应当跳过它去练第 3 天")
        }
        XCTAssertEqual(setup.question.id, "b", "空天不是「今天的题」，停在它上面这条路线就废了")
    }

    /// 真实形态：空天全在尾部。真正有题的那几天练完之后，
    /// 用户该看到的是「练完了」，而不是「你的题丢了」——题一道没丢。
    func testPlanTodaySaysEverythingIsDoneWhenOnlyEmptyTailDaysRemain() {
        let s = state(questions: [q("a")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
                                 PlanDay(id: 2, questionIds: [], completedQuestionIds: [])])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: s) else { return XCTFail("尾部空天不该被当成「今天的题」") }
        XCTAssertTrue(message.contains("已经全部练完"), "该说的是「练完了」")
        XCTAssertFalse(message.contains("找不到"), "题一道没丢，不许告诉用户题丢了")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testPlanTodayHonoursAnExplicitPickAmongTodaysQuestions() {
        let s = state(questions: [q("a"), q("b")],
                      planDays: [PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .planToday, state: s, selectedQuestionID: "b") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
    }

    func testPlanTodayIgnoresAPickThatIsNotOnTodaysList() {
        let s = state(questions: [q("a"), q("b"), q("c")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: []),
                                 PlanDay(id: 2, questionIds: ["b", "c"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .planToday, state: s, selectedQuestionID: "c") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "a", "点了明天的题也只能练今天的，否则计划进度会乱")
    }

    func testPlanTodayUnavailableWithoutAPlan() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: state(questions: [q("a")])) else {
            return XCTFail("没有计划时不该能开练")
        }
        XCTAssertTrue(message.contains("学习计划"), "要告诉用户去哪儿生成计划")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testPlanTodayUnavailableWhenEverythingIsDone() {
        let s = state(questions: [q("a")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"])])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: s) else { return XCTFail("练完了不该还能「按计划练今天」") }
        // 只断言「下一步」分不出任何一条文案——解析器里每一条都含「下一步」。
        // 「你练完了」和「你的题丢了」对用户是两件完全不同的事，必须逐条钉住。
        XCTAssertTrue(message.contains("已经全部练完"), "要告诉用户是练完了，不是出错了")
        XCTAssertFalse(message.contains("找不到"), "题一道没丢，不许告诉用户题丢了")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testPlanTodayUnavailableWhenTodaysQuestionVanishedFromTheBank() {
        let s = state(questions: [q("other")],
                      planDays: [PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: s) else { return XCTFail("题没了就不该假装能练") }
        // 「重新生成」两条文案里都有，分不开它们；要钉的是「题丢了」这件事本身。
        XCTAssertTrue(message.contains("找不到了"), "要告诉用户是题丢了")
        XCTAssertFalse(message.contains("全部练完"), "题还没练完，不许说练完了")
        XCTAssertTrue(message.contains("重新生成"))
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 从题库自由选题

    func testFreePickNeedsASelection() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .freePick, state: state(questions: [q("a")])) else {
            return XCTFail("没选题就不该开练")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testFreePickUsesTheSelectedQuestion() {
        let s = state(questions: [q("a"), q("b", 2)])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "b") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
        XCTAssertEqual(setup.focusPart, .part2)
        XCTAssertEqual(setup.durationMinutes, 4, "Part 2 是一张 cue card，4 分钟")
    }

    func testFreePickRejectsAnUnknownQuestionID() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .freePick, state: state(questions: [q("a")]),
            selectedQuestionID: "nope") else { return XCTFail("题库里没有这道题就不该开练") }
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 继续上次练习

    func testContinueLastUsesTheMostRecentSession() {
        let s = state(questions: [q("a"), q("b")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z"),
                                 session("s2", question: "b", startedAt: "2026-08-04T10:00:00Z")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
    }

    func testContinueLastCarriesTheGoalFromThatSession() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z",
                                         goal: "回答后补一个原因和例子")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.goal, "回答后补一个原因和例子",
                       "「继续上次」的意思就是接着上次那件事再练一遍")
    }

    func testContinueLastUnavailableWithoutSessions() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .continueLast, state: state(questions: [q("a")])) else {
            return XCTFail("没有练习记录就没有「上次」")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testContinueLastUnavailableWhenThatQuestionIsGone() {
        let s = state(questions: [q("other")],
                      sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("题没了就不该假装能练") }
        XCTAssertTrue(message.contains("复盘报告"), "要告诉用户那次练习本身没丢")
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 复训一个旧问题

    func testRetrainBringsTheTargetInAsTheSessionGoal() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("logic-explain", label: "回答后补一个原因和例子", session: "s1")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "a", "复训先重答提出这个目标的那道原题")
        XCTAssertEqual(setup.goal, "回答后补一个原因和例子")
    }

    func testRetrainPrefersTheTargetRankedFirst() {
        // RetrainingPolicy.rank 会把「证据命中高频错题」的目标排前面。
        let s = state(questions: [q("a"), q("b")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z"),
                                 session("s2", question: "b", startedAt: "2026-08-02T10:00:00Z")],
                      targets: [target("t1", label: "目标一", session: "s1"),
                                target("t2", label: "目标二", session: "s2",
                                       evidence: ["I very like it"])],
                      issues: [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                           correction: "I really like it",
                                           whyItMatters: "very 不能修饰动词", occurrences: 4,
                                           sourceSessionIds: ["s2"],
                                           lastSeenAt: "2026-08-02T10:00:00Z")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.goal, "目标二")
        XCTAssertEqual(setup.question.id, "b")
    }

    /// 复训的全部意义就是**先重答提出这个目标的那道原题**。
    /// 这里排第一的目标出自较早的 s1，而 state 里还有更新的 s2——
    /// 「按 sourceSessionId 反查」和「随手拿最近那一场」在这个 state 上结果不同。
    /// 拿错了不会报错也不会崩：goal 还是对的，界面上一点异样都没有，
    /// 用户只是在拿别的题练一个不对应的目标。
    func testRetrainUsesTheSessionThatRaisedTheTargetNotTheLatestOne() {
        let s = state(questions: [q("a"), q("b")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z"),
                                 session("s2", question: "b", startedAt: "2026-08-05T10:00:00Z")],
                      targets: [target("t1", label: "目标一", session: "s1",
                                       evidence: ["I very like it"]),
                                target("t2", label: "目标二", session: "s2")],
                      issues: [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                           correction: "I really like it",
                                           whyItMatters: "very 不能修饰动词", occurrences: 4,
                                           sourceSessionIds: ["s1"],
                                           lastSeenAt: "2026-08-01T10:00:00Z")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.goal, "目标一", "证据命中高频错题的目标排第一")
        XCTAssertEqual(setup.question.id, "a",
                       "要练的是提出这个目标的那一场（s1）的原题，不是最近那一场（s2）的")
    }

    func testRetrainIgnoresRetiredTargets() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("t1", label: "已经改掉了", session: "s1", status: "retired")])
        guard case .unavailable = PracticeRouteResolver.resolve(route: .retrain, state: s) else {
            return XCTFail("已退休的目标不该还能被复训")
        }
    }

    /// 复盘里 priority_target 的 label 可能是空的（RetrainingPolicy.extractTarget 用的是 ?? ""）。
    /// 空目标带进 ExaminerPrompt，「本次唯一目标」那一整段会被跳过，
    /// 于是「复训」和普通练习一模一样——不报错、不崩溃，只是白练一场。
    ///
    /// **跨阶段决策 6（2026-08-06）：回落成 `targetKey` 照常开练，不拒绝。**
    /// 用户是来练英语的，因为一个内部字段是空的就不让他练，代价不成比例。
    /// 这与 Phase 6 的 `RetrainingSetupBuilder.goalText(for:)` 是同一个口径——
    /// **两条路径必须一致**，否则从复训中心进和从今日训练页进会是两种行为。
    func testRetrainFallsBackToTheTargetKeySoTheGoalIsNeverBlank() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("t1", label: "   ", session: "s1")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("label 是空的不该挡住练习") }
        XCTAssertEqual(setup.goal, "t1", "label 为空时要回落成 targetKey")
        XCTAssertFalse(setup.goal.isEmpty,
                       "goal 一旦是空串，复训会静默退化成普通练习——这是决策 6 真正要挡的东西")
    }

    /// 这条要挡的是「那条训练记录已被删除」：**sessions 非空、但没有一条 id 对得上**。
    /// 只用空 sessions 测，等于只测了「一场练习都没有」，
    /// 「查不到就退回随便一场」这种兜底会一路绿灯地混过去——
    /// 那样复训会去重答别人的题，goal 还是对的，用户看不出任何异样。
    /// 第二个 state 保留「一场练习都没有」这条老路径，两种都得挡住。
    func testRetrainUnavailableWhenTheSourceSessionIsGone() {
        let states = [
            state(questions: [q("a"), q("b")],
                  sessions: [session("s2", question: "b", startedAt: "2026-08-05T10:00:00Z")],
                  targets: [target("t1", label: "补一个例子", session: "missing")]),
            state(questions: [q("a")],
                  targets: [target("t1", label: "补一个例子", session: "missing")])
        ]
        for s in states {
            guard case .unavailable(let message) = PracticeRouteResolver.resolve(
                route: .retrain, state: s) else { return XCTFail("找不到出处就不该开练") }
            XCTAssertTrue(message.contains("哪一次练习"), "要说清丢的是「这个目标的出处」")
            XCTAssertTrue(message.contains("下一步"))
        }
    }

    /// 出处那一场还在，但它当时练的那道题已经不在题库里了（换季重新导入）。
    /// 这是另一条分支，报的也该是另一件事。
    func testRetrainUnavailableWhenTheOriginalQuestionLeftTheBank() {
        let s = state(questions: [q("other")],
                      sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("t1", label: "补一个例子", session: "s1")])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("原题没了就不该假装能练") }
        XCTAssertTrue(message.contains("原题"), "丢的是原题，不是目标的出处")
        XCTAssertFalse(message.contains("哪一次练习"))
        XCTAssertTrue(message.contains("下一步"))
    }

    func testRetrainUnavailableWithoutAnyTarget() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .retrain, state: state(questions: [q("a")])) else {
            return XCTFail("没有目标就不该能复训")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - SessionSetup 的取值

    func testDurationAndFocusPartFollowTheQuestionsPart() {
        let cases: [(Int, Int, FocusPart)] = [(1, 6, .part1), (2, 4, .part2), (3, 6, .part3)]
        for (part, minutes, focus) in cases {
            let s = state(questions: [q("x", part)])
            guard case .ready(let setup) = PracticeRouteResolver.resolve(
                route: .freePick, state: s, selectedQuestionID: "x") else {
                return XCTFail("Part \(part) 解析失败")
            }
            XCTAssertEqual(setup.durationMinutes, minutes)
            XCTAssertEqual(setup.focusPart, focus)
        }
    }

    func testOutOfRangePartFallsBackToFullMockInsteadOfCrashing() {
        let s = state(questions: [q("x", 9)])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "x") else { return XCTFail("不该解析失败") }
        XCTAssertEqual(setup.focusPart, .fullMock)
    }

    func testDefaultsFlowIntoTheSetup() {
        let s = state(questions: [q("a")])
        let defaults = RouteDefaults(feedbackTiming: .immediate, part2PrepMode: .learnerControlled)
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "a", defaults: defaults) else {
            return XCTFail("应当能开练")
        }
        XCTAssertEqual(setup.feedbackTiming, .immediate)
        XCTAssertEqual(setup.part2PrepMode, .learnerControlled)
    }

    // MARK: - 可用路线

    private func assortedStates() -> [CoachState] {
        [
            CoachState.empty(),
            state(questions: [q("a"), q("b")]),
            state(questions: [q("a"), q("b")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])]),
            state(questions: [q("a")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"])]),
            // 第 1 天整天练完、第 2 天还有题
            state(questions: [q("a"), q("b")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
                             PlanDay(id: 2, questionIds: ["b"], completedQuestionIds: [])]),
            // 题数少于天数时尾部会有分不到题的空天
            state(questions: [q("a")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
                             PlanDay(id: 2, questionIds: [], completedQuestionIds: [])]),
            state(questions: [q("other")],
                  planDays: [PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")]),
            state(questions: [q("other")],
                  sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                  targets: [target("t1", label: "补一个例子", session: "s1")]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                  targets: [target("t1", label: "", session: "s1")]),
            state(questions: [q("other")],
                  targets: [target("t1", label: "补一个例子", session: "missing")]),
            // 目标的出处那一条记录被删过，但别的练习记录还在
            state(questions: [q("a"), q("b")],
                  sessions: [session("s2", question: "b", startedAt: "2026-08-05T10:00:00Z")],
                  targets: [target("t1", label: "补一个例子", session: "missing")]),
            // 出处还在，它当时练的那道题被换季导入删掉了
            state(questions: [q("other")],
                  sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")],
                  targets: [target("t1", label: "补一个例子", session: "s1")])
        ]
    }

    /// 本阶段最重要的一条不变量：**界面上显示出来的路线，点下去一定能开练。**
    /// 显示一条点了没用的路线，用户只会以为程序坏了。
    /// 「自由选题」除外——它天生要先选题才能解析出题目。
    func testEveryShownRouteCanActuallyStart() {
        for s in assortedStates() {
            for route in PracticeRouteResolver.availableRoutes(state: s, preferring: .planToday)
            where route != .freePick {
                guard case .ready = PracticeRouteResolver.resolve(route: route, state: s) else {
                    return XCTFail("路线「\(route.title)」显示了却开不了练")
                }
            }
        }
    }

    /// 显示条件只能比 Phase 3 的前提判断更严，不能更松。
    func testShownRoutesNeverExceedPhase3Preconditions() {
        for s in assortedStates() {
            let shown = Set(PracticeRouteResolver.availableRoutes(state: s, preferring: .planToday))
            let preconditions = Set(TodayViewModel(state: s).availableRoutes)
            XCTAssertTrue(shown.isSubset(of: preconditions),
                          "显示的路线超出了今日训练页的前提判断：\(shown.subtracting(preconditions))")
        }
    }

    func testPreferredRouteComesFirst() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")])
        XCTAssertEqual(PracticeRouteResolver.availableRoutes(state: s, preferring: .continueLast),
                       [.continueLast, .freePick])
        XCTAssertEqual(PracticeRouteResolver.availableRoutes(state: s, preferring: .freePick),
                       [.freePick, .continueLast])
    }

    /// 默认路线是「按计划练今天」，但根本没有计划——
    /// 它不能因为「是默认」就被塞进列表。
    func testUnavailablePreferredRouteDoesNotSneakIn() {
        let routes = PracticeRouteResolver.availableRoutes(state: state(questions: [q("a")]),
                                                           preferring: .planToday)
        XCTAssertEqual(routes, [.freePick])
    }

    func testNoRoutesAtAllWhenThereIsNothingToPractice() {
        XCTAssertTrue(PracticeRouteResolver.availableRoutes(state: CoachState.empty(),
                                                            preferring: .planToday).isEmpty)
    }
}
