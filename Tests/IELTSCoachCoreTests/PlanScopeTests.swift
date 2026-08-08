import XCTest
@testable import IELTSCoachCore

final class PlanScopeTests: XCTestCase {

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    /// 模拟题库的自然顺序：Part 1 一整块，然后 Part 2，然后 Part 3。
    private var bank: [Question] {
        [q("a1", 1), q("a2", 1), q("a3", 1), q("b1", 2), q("b2", 2), q("c1", 3)]
    }

    func testSinglePartKeepsOnlyThatPartInBankOrder() {
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part1).map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part2).map(\.id), ["b1", "b2"])
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part3).map(\.id), ["c1"])
    }

    /// 照搬题库顺序去分 7 天，会出现前几天全是 Part 1、最后几天全是 Part 3。
    /// 那不叫全真模考。
    func testFullMockInterleavesAcrossParts() {
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .fullMock).map(\.id),
                       ["a1", "b1", "c1", "a2", "b2", "a3"])
    }

    func testFullMockKeepsEveryQuestionExactlyOnce() {
        let selected = PlanScope.select(from: bank, focusPart: .fullMock)
        XCTAssertEqual(selected.count, bank.count)
        XCTAssertEqual(Set(selected.map(\.id)), Set(bank.map(\.id)))
    }

    /// state.json 是纯文本、可以手改；PDF 提取器也可能吐出意外的 part。
    /// 认不出 Part 的题既不能被丢掉，也不能让轮转卡在死循环里。
    func testFullMockSurvivesOutOfRangePartValues() {
        let dirty = bank + [q("x", 9)]
        let selected = PlanScope.select(from: dirty, focusPart: .fullMock)
        XCTAssertEqual(selected.count, dirty.count)
        XCTAssertEqual(selected.last?.id, "x", "认不出 Part 的题排在最后，但不能被丢掉")
    }

    func testEmptyBankSelectsNothing() {
        XCTAssertTrue(PlanScope.select(from: [], focusPart: .fullMock).isEmpty)
        XCTAssertTrue(PlanScope.select(from: [], focusPart: .part2).isEmpty)
    }

    func testNoBlockingReasonWhenThereAreEnoughQuestions() {
        XCTAssertNil(PlanScope.blockingReason(questionCount: 7, lengthDays: 7, focusPart: .part1))
        XCTAssertNil(PlanScope.blockingReason(questionCount: 40, lengthDays: 30, focusPart: .fullMock))
    }

    /// 题数少于天数时 PlanBuilder 会给尾部若干天分 0 题，而空天的 isComplete
    /// 永远是 false，「计划完成」这件事就再也不会发生。所以要在生成前拦住。
    func testBlockingReasonWhenFewerQuestionsThanDays() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 12, lengthDays: 30, focusPart: .part2))
        XCTAssertTrue(reason.contains("12"), "要说清现在有多少题")
        XCTAssertTrue(reason.contains("30"), "要说清想分几天")
        XCTAssertTrue(reason.contains("改成 7 天"), "12 道题最多撑 7 天，要给一个真的办得到的建议")
        XCTAssertTrue(reason.contains("下一步"))
    }

    func testBlockingReasonWhenEvenTheShortestCycleIsImpossible() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 3, lengthDays: 7, focusPart: .part2))
        XCTAssertFalse(reason.contains("改成"),
                       "3 道题连 7 天都分不满，不能建议一个同样办不到的天数")
        XCTAssertTrue(reason.contains("至少 7 道"))
        XCTAssertTrue(reason.contains("下一步"))
    }

    /// 这个 Part 一道题都没有，是唯一一个「换个重点 Part 就立刻解决」的情形，
    /// 所以必须走专属文案而不是通用的「分不满几天」那条：
    /// 后者会说出「只有 0 道题」这种病句，更要命的是只剩「去导入更多题目」这一条建议——
    /// Part 2 没题时导入一批 Part 1 的题根本解决不了问题（铁律 6：下一步必须真的办得到）。
    func testBlockingReasonWhenThatPartHasNoQuestionsAtAll() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 0, lengthDays: 7, focusPart: .part2))
        XCTAssertTrue(reason.contains("Part 2"), "要说清是哪个 Part 没题")
        XCTAssertTrue(reason.contains("训练题库"), "要指出去哪儿解决")
        XCTAssertTrue(reason.contains("下一步"))
        XCTAssertTrue(reason.contains("换一个重点 Part"),
                      "一道题都没有时，唯一一键可解的下一步就是换个重点 Part，不能只让用户去导入")
        XCTAssertFalse(reason.contains("分不满"),
                       "一道题都没有时不该落进「分不满几天」那条通用文案")
    }

    /// 天数不受支持这道闸门原来只长在 `PlanBuilder.build` 里，界面预览照不到，
    /// 于是出现过「预览说能生成、点下去却撞一个报错」。可行性判据必须只有这一处。
    func testBlockingReasonWhenCycleLengthIsUnsupported() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 21, lengthDays: 10, focusPart: .part1))
        XCTAssertTrue(reason.contains("10"), "要说清现在选的是几天")
        XCTAssertTrue(reason.contains("7、14、30"), "要说清哪几档才受支持")
        XCTAssertTrue(reason.contains("下一步"))
    }

    func testLabelsAreChineseAndDistinct() {
        let labels = FocusPart.allCases.map(PlanScope.label(for:))
        XCTAssertEqual(Set(labels).count, labels.count, "每个重点 Part 的说明不能重名")
        XCTAssertTrue(PlanScope.label(for: .fullMock).contains("全真模考"))
        XCTAssertTrue(PlanScope.label(for: .part1).contains("Part 1"))
    }

    /// **「Part 2 + Part 3 连着练」的名字要让人一眼看懂它会发生什么。**
    ///
    /// 这个名字会出现在学习计划页那组单选按钮上、以及开练弹层那句默认档位说明里。
    /// 只写「Part 2 + Part 3」的话，用户分不清它和「全真模考」差在哪儿。
    func testTheCombinedModeSaysWhatActuallyHappensInIt() {
        let label = PlanScope.label(for: .part2And3)
        XCTAssertTrue(label.contains("Part 2"), label)
        XCTAssertTrue(label.contains("Part 3"), label)
        XCTAssertTrue(label.contains("连着练"), "没说清是「连着」练的：" + label)
        XCTAssertFalse(label.contains("模考"), "别让人以为这是三个 Part 的全真模考：" + label)
    }

    /// 「连着练」排的就是 Part 2 那批 cue card。
    ///
    /// **Part 3 那批题刻意不排**：题库里 Part 3 的题干本来就是它所属 cue card 的原文
    /// （`TopicQuestions.part3`），排进来会让同一张卡在计划里占掉两天。
    func testTheCombinedModeSchedulesTheCueCardsAndNothingElse() {
        let bank = [Question(id: "a1", part: 1, topic: "T", prompt: "p"),
                    Question(id: "b1", part: 2, topic: "事件", prompt: "Describe a law"),
                    Question(id: "c1", part: 3, topic: "Describe a law", prompt: "Describe a law")]
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part2And3).map(\.id), ["b1"])
    }
}
