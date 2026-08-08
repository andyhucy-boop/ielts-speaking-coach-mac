import XCTest
@testable import IELTSCoachCore

/// `FocusPart` 是「这一场按哪套考法跑」的唯一出处：`ExaminerPrompt` 照它选规则、
/// `ReviewRequestPrompt` 照它选回答长度标准、`PracticeSession` 把它存进训练记录、
/// `PlanScope` 照它排计划。所以它的三条规则各自都得有测试钉着。
final class FocusPartTests: XCTestCase {

    // MARK: - 取值本身

    /// raw value **写进过用户机器上的 state.json**，改一个字就等于让那些练习记录的 Part
    /// 变成别的东西。所以逐个钉死。
    func testRawValuesAreFrozenBecauseTheyAreAlreadyOnDisk() {
        XCTAssertEqual(FocusPart.part1.rawValue, "Part 1")
        XCTAssertEqual(FocusPart.part2.rawValue, "Part 2")
        XCTAssertEqual(FocusPart.part3.rawValue, "Part 3")
        XCTAssertEqual(FocusPart.part2And3.rawValue, "Part 2 + Part 3")
        XCTAssertEqual(FocusPart.fullMock.rawValue, "full mock")
        XCTAssertEqual(FocusPart.allCases.count, 5)
    }

    // MARK: - 从题目自身的 Part 推

    func testInferenceFollowsTheQuestionsOwnPart() {
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 1), .part1)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 2), .part2)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 3), .part3)
    }

    /// 越界的 part（手改坏的 state.json）落到 full mock，不崩、不拒绝开练。
    func testOutOfRangePartFallsBackToFullMockInsteadOfCrashing() {
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 9), .fullMock)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 0), .fullMock)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: -1), .fullMock)
    }

    /// **「Part 2 + Part 3 连着练」永远不会被推出来。**
    ///
    /// 它只可能是用户当场明确选的。一道 Part 2 的题默认就该按 Part 2 考——
    /// 悄悄升级成「连着练」等于替用户改了这一场的考法，而屏幕上没有任何交代。
    func testTheCombinedModeIsNeverInferredOnItsOwn() {
        for part in [1, 2, 3, 9] {
            XCTAssertNotEqual(FocusPart.inferred(fromQuestionPart: part), .part2And3,
                              "part \(part) 被自动推成了「Part 2 + Part 3 连着练」")
        }
    }

    // MARK: - 用户明确选的模式怎么落地

    /// 没有明确选择时，一律按题目自身的 Part。
    func testWithoutAModeItIsExactlyTheInferredPart() {
        for part in [1, 2, 3, 9] {
            XCTAssertEqual(FocusPart.forSession(mode: nil, questionPart: part),
                           FocusPart.inferred(fromQuestionPart: part))
        }
    }

    /// **只有 Part 2 的题能进「连着练」这一档。**
    ///
    /// 一张 Part 1 的话题卡做不出「两分钟长陈述 + 延伸讨论」，硬按组合档考的话，
    /// 考官只能自己编一张 cue card，而用户挑的那道题一次都不会被问到。
    func testTheCombinedModeOnlyTakesEffectOnAPart2Question() {
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 2), .part2And3)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 1), .part1)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 3), .part3)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 9), .fullMock)
    }

    /// **`fullMock` 当模式传进来时不许把这一场变成一整场模考。**
    ///
    /// 「全真模考」作为学习计划的重点 Part，含义是「把三个 Part 的题交错排开」
    /// （`PlanScope.select`），每一天仍然是练那道题自己的 Part。
    /// 这里若返回 `.fullMock`，用户按计划练的每一天都会突然变成一整场三 Part 模考——
    /// 一次没有任何界面提示的行为突变。
    func testAFullMockPlanStillPracticesEachDaysOwnPart() {
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 1), .part1)
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 2), .part2)
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 3), .part3)
    }

    /// 单 Part 的模式与推断结果一致，不会把一道题拧成别的 Part。
    ///
    /// 这条挡的是「模式一律照抄」那种写法：那样的话，学习计划的重点 Part 是 Part 2、
    /// 而某一天排进来一道 Part 1 的题时，这一场会按 Part 2 的规则考一道 Part 1 的题。
    func testASinglePartModeNeverOverridesTheQuestionsOwnPart() {
        for mode in [FocusPart.part1, .part2, .part3] {
            for part in [1, 2, 3] {
                XCTAssertEqual(FocusPart.forSession(mode: mode, questionPart: part),
                               FocusPart.inferred(fromQuestionPart: part),
                               "mode \(mode) + part \(part) 把题目拧成了别的 Part")
            }
        }
    }

    // MARK: - 时长

    func testDurationsMatchTheRealExamShape() {
        XCTAssertEqual(FocusPart.part1.defaultDurationMinutes, 6)
        XCTAssertEqual(FocusPart.part2.defaultDurationMinutes, 4)
        XCTAssertEqual(FocusPart.part3.defaultDurationMinutes, 6)
        XCTAssertEqual(FocusPart.fullMock.defaultDurationMinutes, 6)
    }

    /// **连着练必须比单练 Part 2 长。** 它是一段两分钟陈述加一整段讨论；
    /// 沿用 Part 2 的 4 分钟的话，提示词里写着「这一场约 4 分钟」，
    /// 而实际要考两段——考官会为了对上时间把 Part 3 砍成一两问。
    func testTheCombinedModeIsLongerThanPart2Alone() {
        XCTAssertEqual(FocusPart.part2And3.defaultDurationMinutes, 9)
        XCTAssertGreaterThan(FocusPart.part2And3.defaultDurationMinutes,
                             FocusPart.part2.defaultDurationMinutes)
    }

    // MARK: - 旧数据 / 旧版本

    /// 新增取值只影响「新版本写、旧版本读」这一个方向，而那条路早就铺好了：
    /// 认不出来的 focusPart 按 full mock 处理，绝不因为一个取值让整份数据读不出来。
    func testAnOlderAppReadingTheNewValueFallsBackInsteadOfBricking() throws {
        let session = """
        {"id":"2026-08-08-001","questionId":"p2-x","focusPart":"Part 2 + Part 3",
         "startedAt":"2026-08-08T10:00:00Z","endedAt":"","goal":"","transcript":[],
         "reportPath":"","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self,
                                               from: Data(session.utf8))
        XCTAssertEqual(decoded.focusPart, .part2And3, "本版本必须原样读出这个取值")

        let plan = """
        {"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 2 + Part 3","days":[]}
        """
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: Data(plan.utf8)).focusPart,
                       .part2And3)
    }

    /// 存下去还能原样读回来——存的时候写成别的字符串，训练记录页那一列就会变。
    func testTheNewValueSurvivesARoundTrip() throws {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-08T00:00:00Z", days: [],
                                focusPart: .part2And3)
        let data = try JSONEncoder().encode(plan)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Part 2 + Part 3"))
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data).focusPart, .part2And3)
    }
}
