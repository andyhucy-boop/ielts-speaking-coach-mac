import XCTest
@testable import IELTSCoachCore

/// 第一次导入题库之后自动排一份计划（2026-08-08 复审第 9 条）。
///
/// 缺陷原样：引导的最后一步写着「首页已经给你排好今天练什么了」，
/// 而**导入题库从来不生成计划**——没有计划，「按计划练今天」那张卡片整块不显示，
/// 首页排得出来的唯一路线是「从题库自由选题」。用户每一场都得自己从整份季度题库
/// （几百道题、一张平铺列表）里挑一道。
final class PlanBootstrapTests: XCTestCase {

    private func questions(_ count: Int) -> [Question] {
        (1...max(count, 1)).prefix(count).map {
            Question(id: "q\($0)", part: ($0 - 1) % 3 + 1, topic: "t\($0)", prompt: "p\($0)")
        }
    }

    private func state(_ count: Int, plan: TrainingPlan? = nil) -> CoachState {
        var value = CoachState.empty()
        value.questions = questions(count)
        value.plan = plan
        return value
    }

    private func bootstrap(_ value: CoachState, hadQuestionsBefore: Bool = false)
        -> PlanRegenerationOutcome? {
        PlanBootstrap.planForFirstImport(state: value, hadQuestionsBefore: hadQuestionsBefore,
                                         createdAt: "2026-08-08T00:00:00Z")
    }

    // MARK: - 排不排

    func testAFirstImportGetsAPlan() throws {
        let outcome = try XCTUnwrap(bootstrap(state(21)),
                                    "第一次导入题库之后没有排出计划，"
                                        + "首页的「按计划练今天」就不会出现，引导那句承诺落空")
        XCTAssertEqual(outcome.plan.days.flatMap(\.questionIds).count, 21,
                       "题库里的题要全部排进去")
        XCTAssertEqual(outcome.plan.focusPart, .fullMock)
    }

    /// **换季重新导入不许被塞回一份计划。** 那时用户手上那份计划里有他练过的进度，
    /// 而且他可能刚在学习计划页把计划删掉——一声不吭地重建，是把他明确做过的选择推翻。
    func testAReimportIntoANonEmptyBankDoesNotGetAPlan() {
        XCTAssertNil(bootstrap(state(21), hadQuestionsBefore: true))
    }

    func testAnExistingPlanIsNeverTouched() throws {
        let existing = try PlanBuilder.build(questions: questions(21), lengthDays: 14,
                                             createdAt: "2026-01-01T00:00:00Z")
        XCTAssertNil(bootstrap(state(21, plan: existing)))
    }

    /// 题目少于最短周期（7 天）时排不出计划——硬排会留下整天没题可练的空天，
    /// 那样的计划永远显示不出「已完成」。这时宁可不排。
    func testTooFewQuestionsMeansNoPlanRatherThanABrokenOne() {
        XCTAssertNil(bootstrap(state(6)))
        XCTAssertNil(bootstrap(state(0)))
    }

    // MARK: - 周期怎么挑

    /// 一场练习就是一道题。7 天计划套在 300 道题上等于每天 43 题，那不叫「排好了」。
    func testTheLengthKeepsTheDailyLoadAsSmallAsItCan() {
        XCTAssertNil(PlanBootstrap.defaultLength(questionCount: 6), "最短也要 7 道题")
        XCTAssertEqual(PlanBootstrap.defaultLength(questionCount: 7), 7)
        XCTAssertEqual(PlanBootstrap.defaultLength(questionCount: 21), 7, "每天正好 3 题")
        XCTAssertEqual(PlanBootstrap.defaultLength(questionCount: 22), 14,
                       "22 道排 7 天是每天 3–4 题，超了就换更长的周期")
        XCTAssertEqual(PlanBootstrap.defaultLength(questionCount: 60), 30)
        XCTAssertEqual(PlanBootstrap.defaultLength(questionCount: 300), 30,
                       "都超上限时退回最长的一档，把每天的量压到最低")
    }

    /// 挑出来的周期必须是**真排得出来**的那一档：`PlanScope` 放行、`PlanBuilder` 也接受。
    /// 只测「挑了几天」而不测「排不排得出来」的话，边界上（题数刚好等于周期）会静默失败。
    func testEveryChosenLengthIsActuallyBuildable() {
        for count in [7, 8, 13, 14, 15, 21, 22, 29, 30, 31, 100, 300] {
            guard let length = PlanBootstrap.defaultLength(questionCount: count) else {
                return XCTFail("\(count) 道题应该排得出计划")
            }
            XCTAssertTrue(PlanBuilder.supportedLengths.contains(length), "\(count) → \(length)")
            XCTAssertNil(PlanScope.blockingReason(questionCount: count, lengthDays: length,
                                                  focusPart: PlanBootstrap.defaultFocusPart),
                         "\(count) 道题排 \(length) 天被 PlanScope 拦住了")
            XCTAssertNotNil(bootstrap(state(count)), "\(count) 道题应该排得出计划")
        }
    }

    // MARK: - 排好之后说什么

    func testTheNoticeSaysWhatWasCreatedAndWhereToChangeIt() throws {
        let outcome = try XCTUnwrap(bootstrap(state(30)))
        let text = PlanBootstrap.notice(for: outcome)
        XCTAssertTrue(text.contains("\(outcome.plan.lengthDays) 天"), text)
        XCTAssertTrue(text.contains("30 道题"), text)
        XCTAssertTrue(text.contains("下一步"), text)
        XCTAssertTrue(text.contains("学习计划"),
                      "凭空多出一份计划，得告诉用户去哪儿改周期和重点 Part：\(text)")
    }

    /// **这句话里指的必须是一颗真按钮。** 「按计划练今天」是卡片标题，不是按钮；
    /// 真正要点的是那张卡片右下角的「开始练习」（`TodayView.actionTitle`）。
    /// 指一个点不动的东西比不写还糟，用户会一直点标题。
    func testTheNoticePointsAtTheButtonNotTheCardTitle() throws {
        let text = PlanBootstrap.notice(for: try XCTUnwrap(bootstrap(state(30))))
        XCTAssertTrue(text.contains("「开始练习」"), text)
        XCTAssertFalse(text.contains("点「按计划练今天」"),
                       "「按计划练今天」是卡片标题不是按钮：\(text)")
    }
}
