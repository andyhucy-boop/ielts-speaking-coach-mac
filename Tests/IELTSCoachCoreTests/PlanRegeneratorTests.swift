import XCTest
@testable import IELTSCoachCore

final class PlanRegeneratorTests: XCTestCase {

    // MARK: - 工具

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    /// 14 道 Part 1 + 14 道 Part 2。够分 7 天，也够分 14 天。
    private func bank() -> [Question] {
        (1...14).map { q("a\($0)", 1) } + (1...14).map { q("b\($0)", 2) }
    }

    /// 30 道 Part 1：7、14、30 三种周期都排得满，用来验反复改周期。
    private func bigBank() -> [Question] {
        (1...30).map { q("a\($0)", 1) }
    }

    private func state(questions: [Question], plan: TrainingPlan? = nil) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.plan = plan
        return s
    }

    private func completed(_ plan: TrainingPlan) -> Set<String> {
        Set(plan.days.flatMap(\.completedQuestionIds))
    }

    // MARK: - 核心：重新生成不能丢进度

    func testCarriesCompletedQuestionsAcrossACycleChange() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "2026-08-06T00:00:00Z").plan
        // 练完前两天
        for id in plan.days[0].questionIds + plan.days[1].questionIds {
            plan = PlanBuilder.markCompleted(plan: plan, questionID: id)
        }
        s.plan = plan
        let done = completed(plan)
        XCTAssertEqual(done.count, 4, "14 题分 7 天，每天 2 题，两天就是 4 题")

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 14, focusPart: .part1,
                                                         createdAt: "2026-08-07T00:00:00Z")
        XCTAssertEqual(regenerated.plan.lengthDays, 14)
        XCTAssertEqual(completed(regenerated.plan), done, "换周期后，练过的题必须还是练过的")
        XCTAssertEqual(Set(regenerated.carriedOver), done)
        XCTAssertTrue(regenerated.dropped.isEmpty)
        // 进度保住了，但用户看不见——等于没保住。数据层对了还必须当面说出来，
        // 而且要带上道数：只说「已完成」三个字，dropped 那句里也有，抓不住这里的丢失。
        XCTAssertTrue(regenerated.summary.contains("4 道题仍然算已完成"),
                      "练了 3 天的人点重新生成，界面必须当面告诉他那几道题还算练过，"
                      + "否则他只能自己去翻计划页数格子。实际文案：\(regenerated.summary)")
    }

    func testCarriesProgressWhenTheFocusPartNarrows() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .fullMock,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a1")
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "b1")
        s.plan = plan

        let narrowed = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                      createdAt: "t2")
        XCTAssertEqual(completed(narrowed.plan), ["a1"], "还在范围内的那道题保持已完成")
        XCTAssertEqual(narrowed.carriedOver, ["a1"])
        XCTAssertEqual(narrowed.dropped, ["b1"], "b1 是 Part 2，新计划里没有它")
    }

    func testReportsCompletedQuestionsThatTheBankNoLongerHas() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a1")
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a2")
        s.plan = plan
        // 换季重新导入，出题方把 a1 删掉了
        s.questions = s.questions.filter { $0.id != "a1" }

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                         createdAt: "t2")
        XCTAssertEqual(regenerated.dropped, ["a1"])
        XCTAssertEqual(regenerated.carriedOver, ["a2"])
        XCTAssertTrue(regenerated.summary.contains("没有丢"),
                      "必须明确告诉用户那次练习的记录还在，否则 dropped 看起来就像数据被删了")
    }

    /// 成品标准第 12 条：题库换季重新导入后，旧的练习记录不能错位。
    /// 题目 id 是内容哈希，同一道题重新导入后 id 不变，所以进度照样对得上。
    func testKeepsProgressAfterASeasonalReimport() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a5")
        s.plan = plan
        // 换季：新增 6 道 Part 1 排在最前面，整体顺序全变了，但老题的 id 没变
        s.questions = (1...6).map { q("new\($0)", 1) } + s.questions

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                         createdAt: "t2")
        XCTAssertTrue(completed(regenerated.plan).contains("a5"),
                      "换季重新导入后，练过的题不能变回没练过")
        XCTAssertTrue(regenerated.dropped.isEmpty)
    }

    /// **补充（计划之外）：参数一个都没改就点了「重新生成」。**
    /// 这是真实使用里最常发生的一次点击——用户只是想换一批题、或者以为点了会刷新，
    /// 而它恰恰是最容易被实现成「重新开始」的一条路径：
    /// 天数与重点 Part 都没变，很容易让人以为「反正一样，直接覆盖就行」。
    func testRegeneratingWithTheSameSettingsStillKeepsProgress() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a3")
        s.plan = plan

        let again = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                   createdAt: "t2")
        XCTAssertEqual(completed(again.plan), ["a3"],
                       "什么都没改就点了重新生成，练过的题照样不能变回没练过")
        XCTAssertEqual(again.carriedOver, ["a3"])
        XCTAssertTrue(again.dropped.isEmpty)
    }

    /// **补充（计划之外）：连着改好几次周期。**
    /// 用户会来回试 7/14/30 天。只要有一次搬运失手，进度就永久没了，
    /// 而单次搬运正确并不能保证连着搬三次还正确（新计划会成为下一次的旧计划）。
    func testProgressSurvivesAChainOfRegenerations() throws {
        var s = state(questions: bigBank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        for id in plan.days[0].questionIds {
            plan = PlanBuilder.markCompleted(plan: plan, questionID: id)
        }
        s.plan = plan
        let done = completed(plan)
        XCTAssertEqual(done.count, 5, "30 题分 7 天，前两天各 5 题")

        for (days, createdAt) in [(14, "t2"), (30, "t3"), (7, "t4")] {
            let outcome = try PlanRegenerator.regenerate(state: s, lengthDays: days,
                                                         focusPart: .part1, createdAt: createdAt)
            s.plan = outcome.plan
            XCTAssertEqual(completed(outcome.plan), done,
                           "改成 \(days) 天之后，练过的 \(done.count) 道题必须还是练过的")
            XCTAssertEqual(Set(outcome.carriedOver), done)
            XCTAssertTrue(outcome.dropped.isEmpty, "题库一道没变，不该有题掉出范围")
        }
    }

    /// **补充（计划之外）：搬运要落在正确的那一天，不只是「集合里有」。**
    /// 换周期之后同一道题几乎一定会挪到别的天上；标记若留在原来的下标上，
    /// 那一天会显示成已完成、真正含这道题的那天却还显示没做完，
    /// 而「集合相等」这类断言看不出这种错位。
    func testCarryOverProgressMarksTheDayThatActuallyHoldsTheQuestion() {
        let old = TrainingPlan(lengthDays: 7, createdAt: "t1",
                               days: [PlanDay(id: 1, questionIds: ["a1", "a2"],
                                              completedQuestionIds: ["a1"])],
                               focusPart: .part1)
        let fresh = TrainingPlan(
            lengthDays: 14, createdAt: "t2",
            days: [PlanDay(id: 1, questionIds: ["x1"], completedQuestionIds: []),
                   PlanDay(id: 2, questionIds: ["x2"], completedQuestionIds: []),
                   PlanDay(id: 3, questionIds: ["a1", "a2"], completedQuestionIds: [])],
            focusPart: .part1)

        let carried = PlanRegenerator.carryOverProgress(from: old, to: fresh)
        XCTAssertEqual(carried.days[2].completedQuestionIds, ["a1"],
                       "a1 现在排在第 3 天，已完成的标记要跟着落到第 3 天")
        XCTAssertTrue(carried.days[0].completedQuestionIds.isEmpty, "没练过的题不能被标成练过")
        XCTAssertTrue(carried.days[1].completedQuestionIds.isEmpty)
        XCTAssertEqual(carried.days.map(\.questionIds), fresh.days.map(\.questionIds),
                       "搬运进度不能动题目本身的排布")
        XCTAssertEqual(PlanRegenerator.carryOverProgress(from: nil, to: fresh), fresh,
                       "没有旧计划时原样返回，不能凭空造出已完成")
    }

    // MARK: - 其余行为

    func testWorksWhenThereIsNoOldPlan() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part2, createdAt: "t")
        XCTAssertEqual(outcome.plan.days.count, 7)
        XCTAssertTrue(outcome.carriedOver.isEmpty)
        XCTAssertTrue(outcome.dropped.isEmpty)
        // 题数是用户判断这份计划靠不靠谱的唯一数字，报错了得当场看出来。
        // bank() 里 Part 2 正好 14 道，与 7 天周期不同号，不会靠巧合蒙对。
        XCTAssertTrue(outcome.summary.contains("共 14 道题"),
                      "摘要要说清这次排了多少题。实际文案：\(outcome.summary)")
    }

    func testRegeneratingTwiceGivesTheSamePlan() throws {
        var s = state(questions: bank())
        s.plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                createdAt: "t1").plan
        let again = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                   createdAt: "t1")
        XCTAssertEqual(again.plan, s.plan, "同样的题库、同样的参数，重新生成不该产生不一样的计划")
    }

    func testStoresTheFocusPartOnThePlan() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part2, createdAt: "t")
        XCTAssertEqual(outcome.plan.focusPart, .part2)
        XCTAssertTrue(outcome.plan.days.flatMap(\.questionIds).allSatisfy { $0.hasPrefix("b") },
                      "选了 Part 2 就只能排 Part 2 的题")
    }

    func testSummaryAlwaysSaysWhatToDoNext() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part1, createdAt: "t")
        XCTAssertTrue(outcome.summary.contains("下一步"),
                      "所有面向用户的文案都要说明下一步做什么")
    }

    // MARK: - 拒绝

    func testRefusesWhenThePartHasFewerQuestionsThanDays() {
        let s = state(questions: (1...5).map { q("b\($0)", 2) })
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                            focusPart: .part2, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("5"))
            XCTAssertTrue(error.localizedDescription.contains("下一步"))
        }
    }

    func testRefusesWhenThePartHasNoQuestions() {
        let s = state(questions: (1...10).map { q("a\($0)", 1) })
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                            focusPart: .part3, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Part 3"))
            XCTAssertTrue(error.localizedDescription.contains("下一步"))
        }
    }

    func testRejectsUnsupportedCycleLength() {
        let s = state(questions: bank())
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 10,
                                                            focusPart: .part1, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("7、14、30"))
        }
    }

    /// 拒绝的判据必须与界面预览用的判据完全一致，
    /// 否则会出现「预览说能生成、点下去却报错」。
    func testRefusalMatchesPlanScopeBlockingReason() {
        for count in 0...20 {
            for days in PlanBuilder.supportedLengths {
                let s = state(questions: (0..<count).map { q("b\($0)", 2) })
                let blocked = PlanScope.blockingReason(questionCount: count, lengthDays: days,
                                                       focusPart: .part2) != nil
                var threw = false
                do {
                    _ = try PlanRegenerator.regenerate(state: s, lengthDays: days,
                                                       focusPart: .part2, createdAt: "t")
                } catch { threw = true }
                XCTAssertEqual(threw, blocked, "题数 \(count)、周期 \(days) 天：两处判断不一致")
            }
        }
    }

    // MARK: - apply 的边界

    /// 「重新生成计划」是重排今后练什么，不是清空练过什么。
    /// 顺手把 question.status 重置成 new、或清掉 sessions 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史。这条测试就是为了让那种改动立刻变红。
    func testApplyOnlyTouchesThePlan() throws {
        var s = state(questions: bank())
        s.questions[0].status = "practiced"
        s.sessions = [PracticeSession(id: "s1", questionId: "a1", focusPart: .part1,
                                      startedAt: "2026-08-01T00:00:00Z",
                                      endedAt: "2026-08-01T00:10:00Z",
                                      goal: "回答后补一个原因和例子", transcript: [],
                                      reportPath: "reports/s1.json", recordingPath: "")]
        s.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                correction: "I really like it", whyItMatters: "very 不能修饰动词",
                                occurrences: 3, sourceSessionIds: ["s1"],
                                lastSeenAt: "2026-08-01T00:10:00Z")]
        s.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good", betterExpression: "rewarding",
                                         collocation: "a rewarding trip", priority: "high",
                                         sourceSessionIds: ["s1"])]
        s.targets = [RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子",
                                      status: "new", evidence: ["I just like it."],
                                      sourceSessionId: "s1", createdAt: "2026-08-01T00:10:00Z")]
        let before = s

        let outcome = try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                     focusPart: .part1, createdAt: "t")
        PlanRegenerator.apply(outcome, to: &s)

        XCTAssertEqual(s.plan, outcome.plan)
        XCTAssertEqual(s.questions, before.questions, "题目的已练标记不能被重新生成计划清掉")
        XCTAssertEqual(s.sessions, before.sessions)
        XCTAssertEqual(s.issues, before.issues)
        XCTAssertEqual(s.vocabulary, before.vocabulary)
        XCTAssertEqual(s.targets, before.targets)
        XCTAssertEqual(s.settings, before.settings)
    }
}
