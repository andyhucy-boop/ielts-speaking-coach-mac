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

    /// 上面那条只覆盖了「题库空 **且** 没练过、没目标」这一格，而那一格里四条路线本来就都排不出来。
    /// 真正会漏的是这一格：题库空、但以前练过、还留着没退休的复训目标——
    /// 「继续上次练习」和「复训一个旧问题」看着只依赖历史记录，其实同样要按 id 去题库反查那道题
    /// （`TodayView.plannedQuestion`），库空了它们哪也去不了。
    ///
    /// 换季重新导入题库（先清空再导）时用户就正好停在这一格上。
    func testNoRouteSurvivesAnEmptyBankEvenWithHistoryAndLiveTargets() {
        var s = state(plan: nil, questions: [],
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.targets = [retrainingTarget("t1", status: "new")]
        XCTAssertEqual(
            TodayViewModel(state: s).availableRoutes, [],
            "题库空时「继续上次练习」「复训一个旧问题」照样走不通——两条最后都要拿题库里的一道题去练。"
                + "显示出来等于给用户两个点了没用的按钮，而这一页是他每天打开的第一眼。")
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

    /// 副标题描述的操作步骤得和弹层里真有的东西对得上（复审第 9 条）。
    ///
    /// ## 这条测试的来历，和它现在为什么是双向的
    ///
    /// 副标题一度写着「先选 Part，再挑具体题目」，而那时弹层里只有一张平铺列表——
    /// 一个**不存在的两步选择**，用户会先去找那个筛选器。当时的修法是把话改成一步，
    /// 并留下一条「哪天筛选器真做出来了，这条会红」的单向断言。
    ///
    /// **那一天到了**，而且又往前走了一步：`PracticeSheet.partSection` 里现在是三个
    /// 绑到 `partBinding(for:)` 的勾选框，**可以多勾**（用户原话：「我要多选 Part one
    /// 和 Part two，练完这个练那个」）。所以这条是**双向**的：
    ///
    /// - 副标题说了「先勾 Part」，弹层里却没有那几个勾选框 → 红（老毛病回来了）；
    /// - 弹层里有勾选框，副标题却只字不提 → 也红（用户不知道还能勾，仍旧一路滚）；
    /// - 勾选框能多勾，副标题却不说「可多选」→ 也红（他不会去勾第二个，
    ///   而多选正是这一轮加的东西）。
    ///
    /// 突变证明：把 `partSection` 里那几颗 Toggle 换成 `EmptyView()` 这条会红；
    /// 只把副标题改回一步的说法，这条也会红。
    func testTheFreePickSubtitleMatchesWhatTheSheetActuallyHas() throws {
        let subtitle = PracticeRoute.freePick.subtitle
        let sheet = try SourceGuard.code("Session/PracticeSheet.swift")

        // 「弹层里真的有那几个 Part 勾选框」的判据：Toggle 的标题走 `partTitle(forPart:)`，
        // 而它绑的是 `partBinding(for:)`。只问 `contains("Toggle(")` 不够——
        // 那样随便哪个别的开关都能把它凑绿。
        let hasPartTicks = sheet.contains("PracticePicker.partTitle(forPart: part)")
            && sheet.contains("isOn: partBinding(for: part)")
        let subtitlePromisesPartStep = subtitle.contains("Part")

        XCTAssertTrue(
            hasPartTicks,
            "挑题弹层里没有那几个绑到 `partBinding(for:)` 的 Part 勾选框了。"
                + "用户要的第一件事就是「先勾这一场练哪几个 Part」，没有它，258 道题只能一路滚。"
                + "下一步：把 `PracticeSheet.partSection` 里那三颗 Toggle 放回去；"
                + "真要撤掉这个功能，副标题（`PracticeRoute.freePick.subtitle`）也得一起改回一步的说法。")

        XCTAssertEqual(
            subtitlePromisesPartStep, hasPartTicks,
            "副标题说的步骤和弹层里真有的东西对不上。副标题：「\(subtitle)」；"
                + "弹层里\(hasPartTicks ? "有" : "没有") Part 勾选框。"
                + "下一步：两边改成一致——有勾选框就在副标题里说清「先勾 Part 再挑题」，"
                + "没有就别写，否则用户会去找一个不存在的控件（复审第 9 条就是这么来的）。")

        XCTAssertTrue(subtitle.contains("多选") || subtitle.contains("几个"),
                      "副标题没提「可以多勾」。这一轮加的正是多选 Part，"
                          + "不说的话用户勾完一个就去挑题了，功能等于没做。副标题：「\(subtitle)」")

        XCTAssertFalse(subtitle.contains("搜索") && !sheet.contains("searchable"),
                       "副标题提到了搜索，弹层里却没有搜索框：\(subtitle)")
    }

    // MARK: - 点「开始练习」到底要练哪道题、按什么设置练

    /// 这几条守的是 Task 9 那颗按钮背后的取数：点下去之后要拿哪道题、带什么目标、按哪个 Part
    /// 的规则考。原来这段逻辑写在 `TodayView` 里（`plannedQuestion`），而 `View` 测不了——
    /// 于是「继续上次练习」指向一道题库里已经没有的题」这类错误只能等真机上撞见。

    func testPlannedQuestionForPlanTodayIsTheFirstOfTodaysPlanDay() throws {
        let questions = (1...14).map { question("q\($0)") }
        let plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        let vm = TodayViewModel(state: state(plan: plan, questions: questions))
        XCTAssertEqual(vm.plannedQuestion(for: .planToday)?.id, plan.days[0].questionIds.first)
    }

    /// 「从题库自由选题」的意思就是这道题由用户当场挑，这里定不下来是正常的。
    /// 硬塞一道给他，那条路线的名字就成了假话。
    func testPlannedQuestionForFreePickIsNilBecauseTheUserPicks() {
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")]))
        XCTAssertNil(vm.plannedQuestion(for: .freePick))
    }

    /// 上次练的那道题**必须回题库里反查**，不能拿会话里记的 id 直接开练。
    /// 换季重新导入题库之后，那个 id 很可能已经不存在了——拿它去练，
    /// 考官提示词里的题干就是空的，用户对着 ChatGPT 干瞪眼。
    func testPlannedQuestionForContinueLastMustStillExistInTheBank() {
        var gone = state(plan: nil, questions: [question("a")],
                         sessions: [PracticeSession(id: "s1", questionId: "换季前的老题", focusPart: .part1,
                                                    startedAt: "2026-08-05T10:00:00Z", endedAt: "",
                                                    goal: "", transcript: [], reportPath: "",
                                                    recordingPath: "")])
        XCTAssertNil(TodayViewModel(state: gone).plannedQuestion(for: .continueLast),
                     "题库里已经没有这道题了，就不该硬给一个练不了的 id")

        gone.questions.append(question("换季前的老题"))
        XCTAssertEqual(TodayViewModel(state: gone).plannedQuestion(for: .continueLast)?.id, "换季前的老题")
    }

    func testPlannedQuestionForRetrainFollowsTheTargetBackToItsSession() {
        var s = state(plan: nil, questions: [question("a"), question("b")],
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.sessions[0].questionId = "b"
        s.targets = [retrainingTarget("t1", status: "new")]   // sourceSessionId 是 "s1"
        XCTAssertEqual(TodayViewModel(state: s).plannedQuestion(for: .retrain)?.id, "b",
                       "复训要重练的是当初留下这个目标的那道题")
    }

    /// 复训那一场必须把目标带进考官提示词，否则「带着这个目标重练」就只是句口号——
    /// 复盘里也不会针对它给反馈，改进闭环（成品标准第 2 节）当场断掉。
    func testRetrainCarriesTheTargetAsThisSessionsGoal() {
        var s = state(plan: nil, questions: [question("a")],
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.targets = [retrainingTarget("t1", status: "new")]
        let vm = TodayViewModel(state: s)
        XCTAssertEqual(vm.goal(for: .retrain), "L", "retrainingTarget 的 label 就是这一场的目标")
        XCTAssertEqual(vm.goal(for: .planToday), "", "其余路线不带目标")
    }

    /// 已经退休的目标是已经改掉的毛病，拿它复训是白练一场。
    func testRetiredTargetsAreNotUsedForRetraining() {
        var s = state(plan: nil, questions: [question("a")],
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.targets = [retrainingTarget("t1", status: "retired")]
        XCTAssertEqual(TodayViewModel(state: s).goal(for: .retrain), "")
        XCTAssertNil(TodayViewModel(state: s).plannedQuestion(for: .retrain))
    }

    /// `focusPart` 决定 ChatGPT 按哪个 Part 的规则考（`ExaminerPrompt.partRules`）：
    /// Part 2 是「给一分钟准备 + 两分钟长回答」，Part 1 是「6–10 个短问题」。
    /// 定错了，用户练的就是另一种题型，而界面上一点异样都看不出来。
    func testPracticeSetupTakesTheFormatFromTheQuestionsOwnPart() {
        let vm = TodayViewModel(state: state(plan: nil, questions: []))
        let part1 = Question(id: "a", part: 1, topic: "Home", prompt: "P")
        let part2 = Question(id: "b", part: 2, topic: "Skills", prompt: "Q")

        let one = vm.practiceSetup(question: part1, route: .planToday)
        XCTAssertEqual(one.focusPart, .part1)
        XCTAssertEqual(one.durationMinutes, 6)
        XCTAssertEqual(one.goal, "")

        let two = vm.practiceSetup(question: part2, route: .planToday)
        XCTAssertEqual(two.focusPart, .part2)
        XCTAssertEqual(two.durationMinutes, 4, "Part 2 是长回答，一场就一道题，不需要六分钟")
    }

    func testPracticeSetupForRetrainCarriesTheGoalIntoTheExaminerPrompt() {
        var s = state(plan: nil, questions: [question("a")],
                      sessions: [practiceSession("s1", startedAt: "2026-08-05T10:00:00Z")])
        s.targets = [retrainingTarget("t1", status: "new")]
        let setup = TodayViewModel(state: s).practiceSetup(question: question("a"), route: .retrain)
        XCTAssertEqual(setup.goal, "L")
        XCTAssertTrue(ExaminerPrompt.build(setup: setup).contains("本次唯一目标：L"),
                      "目标得真的进到发给 ChatGPT 的提示词里，不能只存在界面上")
    }

    // MARK: - 复训卡片上那句「这个目标出自哪一次练习」（Task 10）

    /// **卡片上说的那一次，必须就是解析器真的要重练的那一次。**
    ///
    /// 这里有两套「挑哪个目标」的说法，而且它们经常不一致：
    ///
    /// - `TodayViewModel.liveTarget` 取的是**最后记下**的那个没退休的目标；
    /// - `PracticeRouteResolver.resolveRetrain` 走的是 `RetrainingPolicy.rank(targets:issues:)`
    ///   的第一个——证据命中高频错题的排前面。
    ///
    /// 卡片按前者显示、点下去按后者开练的话，用户看着「补一个原因和例子」点开始，
    /// 练的却是另一个毛病，而屏幕上没有任何异样。所以 `retrainOrigin` 必须跟着 `rank` 走。
    func testTheRetrainOriginPointsAtTheTargetTheResolverWillActuallyPractice() {
        // 两个都没退休的目标：t-ranked 的证据命中一条犯过 5 场的老毛病，权重高；
        // t-latest 后记下、但一条证据都没有，权重 0。
        // 于是 rank 挑第一个，而「最后记下的」是第二个——两套说法在这份数据上分道扬镳。
        var s = state(plan: nil, questions: [question("a"), question("b")],
                      sessions: [practiceSession("s-ranked", startedAt: "2026-08-01T10:00:00Z"),
                                 practiceSession("s-latest", startedAt: "2026-08-05T10:00:00Z")])
        s.sessions[0].questionId = "a"
        s.sessions[1].questionId = "b"
        s.issues = [IssueRecord(id: "i1", learnerSaid: "I like it because it is good.",
                                correction: "", whyItMatters: "", occurrences: 5,
                                sourceSessionIds: ["x1", "x2", "x3", "x4", "x5"],
                                lastSeenAt: "2026-08-01T10:00:00Z")]
        s.targets = [
            RetrainingTarget(targetKey: "logic-example", label: "回答后补一个原因和例子",
                             status: "new", evidence: ["I like it because it is good."],
                             sourceSessionId: "s-ranked", createdAt: "2026-08-01T11:00:00Z"),
            RetrainingTarget(targetKey: "fillers", label: "少说 you know", status: "new",
                             evidence: [], sourceSessionId: "s-latest",
                             createdAt: "2026-08-05T11:00:00Z")
        ]
        let vm = TodayViewModel(state: s)

        // 先钉住这份数据真的能把两套说法分开，否则下面那条断言是恰好通过。
        XCTAssertEqual(vm.liveTarget?.targetKey, "fillers",
                       "这份数据没能让「最后记下的」和「rank 排第一的」分开，这条测试等于空转")

        guard let origin = vm.retrainOrigin else {
            return XCTFail("复训卡片查不到这个目标的出处，而解析器明明能开练")
        }
        XCTAssertEqual(origin.target.targetKey, "logic-example",
                       "复训卡片指的目标不是解析器真要练的那个（`RetrainingPolicy.rank` 排第一的）。"
                           + "用户看着一句话点开始，练的却是另一个毛病。")
        XCTAssertEqual(origin.session.id, "s-ranked",
                       "「出自哪一次练习」指到了别的一场，用户回去翻复盘会翻错")

        // 与解析器当场对一遍：卡片上写的目标原文，就是提示词里会发出去的那一段。
        guard case .ready(let setup) = PracticeRouteResolver.resolve(route: .retrain, state: s) else {
            return XCTFail("这份数据下复训路线本该能开练，解析器却说不行")
        }
        XCTAssertEqual(setup.goal, "回答后补一个原因和例子")
        XCTAssertEqual(origin.target.label, setup.goal,
                       "卡片上的目标和真正发给考官的那一段对不上")
    }

    /// 目标的来源那一场被单条删掉时，卡片不许硬编一个出处。
    /// 那时解析器本来就会返回「找不到这个目标是哪一次练习提出来的」，两边得是同一个判断。
    func testTheRetrainOriginIsNilWhenTheSourceSessionWasDeleted() {
        var s = state(plan: nil, questions: [question("a")],
                      sessions: [practiceSession("s-kept", startedAt: "2026-08-05T10:00:00Z")])
        s.sessions[0].questionId = "a"
        s.targets = [RetrainingTarget(targetKey: "t", label: "L", status: "new", evidence: [],
                                      sourceSessionId: "已经被删掉的那一场",
                                      createdAt: "2026-08-01T11:00:00Z")]
        XCTAssertNil(TodayViewModel(state: s).retrainOrigin,
                     "来源记录已经不在了，卡片就不该指出一个查不到的出处")
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

    // MARK: - 训练记录还没接上：界面不许说自己做得到

    /// 「本周训练 N/5」和「最近练习」这两处，在当前工程里**永远不会动**：
    /// 全工程没有任何一行往 `CoachState.sessions` 里写东西。不交代这件事，
    /// 用户在终端练完一整场回到这一页，看到的还是 0 次、还是「还没有练习记录」。
    func testUnwiredRecordingNoticeSaysWhatHappensAndWhatToDoNext() throws {
        let text = try XCTUnwrap(TodayViewModel.unwiredRecordingNotice(isWired: false))
        XCTAssertTrue(text.contains("本周训练"), "得指名道姓说清是哪两处不会动")
        XCTAssertTrue(text.contains("最近练习"))
        XCTAssertTrue(text.contains("下一步"), "只说「记录还没接上」不说下一步，用户还是不知道该干什么")
    }

    /// 这句交代是 Task 9 之前写的，那时候练习只能在终端里进行，所以它把用户支去命令行。
    /// 现在界面自己就能开练（成品标准第 2 条），再提终端就是给用户一条更麻烦、
    /// 而且已经不必要的路。
    func testUnwiredRecordingNoticeNoLongerSendsTheUserToATerminal() throws {
        let text = try XCTUnwrap(TodayViewModel.unwiredRecordingNotice(isWired: false))
        for forbidden in ["终端", "命令行"] {
            XCTAssertFalse(text.contains(forbidden),
                           "这句交代里还留着「\(forbidden)」，而现在点一下按钮就能开练。"
                               + "下一步：改写成「在这一页练完之后…」。")
        }
    }

    /// 记录接上（Phase 4）之后这句话必须自己消失，否则界面会对着一个已经能用的功能说它不能用。
    func testUnwiredRecordingNoticeDisappearsOnceRecordingIsWired() {
        XCTAssertNil(TodayViewModel.unwiredRecordingNotice(isWired: true))
    }

    /// `practiceRecordingIsWired` 是一句关于**代码现状**的断言，而不是随手写下的常量。
    /// 它和真实代码脱钩的两个方向都很难看：
    /// - 还是 false、但已经有人在写 sessions 了 → 页面对着能用的功能说它不能用；
    /// - 改成了 true、但根本没人写 sessions → 页面又开始默默撒谎。
    ///
    /// 所以这里扫一遍 `Sources/`。扫源码这一招在本项目有先例
    /// （`PreviewSafetyTests`、`QuestionBankViewTests`、`DesignSystemTests`）。
    func testPracticeRecordingFlagMatchesWhetherAnyCodeWritesSessions() throws {
        let sources = try Self.sourcesDirectory
        let files = try SourceGuard.swiftFiles(in: sources, describedAs: "Sources")
        XCTAssertGreaterThan(
            files.count, 10,
            "只扫到 \(files.count) 个源文件，这条测试多半在空转。下一步：确认目录还在——"
                + sources.path)

        var writers: [String] = []
        for file in files where file.lastPathComponent != "CoachState.swift" {
            let code = SourceGuard.stripLineComments(
                try SourceGuard.read(contentsOf: file, describedAs: file.lastPathComponent))
            if Self.writesToSessions(code) { writers.append(file.lastPathComponent) }
        }

        if TodayViewModel.practiceRecordingIsWired {
            XCTAssertFalse(
                writers.isEmpty,
                "practiceRecordingIsWired 是 true，但全工程没有任何一行往 state.sessions 里写。"
                    + "今日训练页会照着这个值把「训练记录还没接上」那句交代收起来，"
                    + "于是「本周训练 N/5」和「最近练习」重新变回不会动、也没人解释的两块。"
                    + "下一步：要么把它改回 false，要么把写记录那段真的接上。")
        } else {
            XCTAssertTrue(
                writers.isEmpty,
                "\(writers.joined(separator: "、")) 已经在往 state.sessions 里写记录了，"
                    + "但 practiceRecordingIsWired 还是 false，页面会继续对用户说"
                    + "「这一版还不会把练习记录写进训练数据」——对着一个已经能用的功能说它不能用。"
                    + "下一步：把 TodayViewModel.practiceRecordingIsWired 改成 true。")
        }
    }

    /// 上面那条测试全靠 `writesToSessions` 认得出写入。它认不出的话，
    /// 上面那条会一路绿到 Phase 4 之后——正是它要防的那种静默。
    func testTheSessionWriteScannerActuallyDetectsAWrite() {
        XCTAssertTrue(Self.writesToSessions("state.sessions.append(session)"))
        XCTAssertTrue(Self.writesToSessions("            updated.sessions += [session]"))
        XCTAssertTrue(Self.writesToSessions("state.sessions = state.sessions + [session]"))
        XCTAssertTrue(Self.writesToSessions("sessions.append(session)"), "写在 CoachState 扩展里的形式")

        XCTAssertFalse(Self.writesToSessions("Array(state.sessions.sorted { $0.startedAt > $1.startedAt })"),
                       "只是读，不该被当成写")
        XCTAssertFalse(Self.writesToSessions("private var sessions: [PracticeSession] {"),
                       "计算属性的声明不该被当成写")
        XCTAssertFalse(Self.writesToSessions("let practiced = app.state.sessions.count"))
    }

    // MARK: - 扫源码用的小工具

    /// 全工程的源码根。**不写死绝对路径**——由 `SourceGuard` 从测试文件往上找到含
    /// `Package.swift` 的那一层，换台机器照样能跑（成品标准第 10 条）。
    static var sourcesDirectory: URL {
        get throws { try SourceGuard.repositoryRoot().appending(path: "Sources") }
    }

    /// 这段代码里有没有往某个 `.sessions` 数组里写东西。
    ///
    /// 带点的几种覆盖 `state.sessions.append(...)` 这类最常见的写法；不带点的
    /// `sessions.append(` / `sessions +=` 覆盖写在 `CoachState` 自己的扩展里的形式。
    /// 刻意**不认**不带点的 `sessions = `：那会把 `let sessions = …` 这种局部变量也算进来。
    static func writesToSessions(_ code: String) -> Bool {
        [".sessions.append(", ".sessions.insert(", ".sessions.remove", ".sessions +=",
         ".sessions = ", "sessions.append(", "sessions.insert(", "sessions +="]
            .contains { code.contains($0) }
    }
}
