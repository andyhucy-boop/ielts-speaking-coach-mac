import XCTest
@testable import IELTSCoachCore

final class PlanBuilderTests: XCTestCase {
    private func questions(_ count: Int) -> [Question] {
        (1...count).map { Question(id: "q\($0)", part: 1, topic: "T", prompt: "P\($0)") }
    }

    func testCoversEveryQuestionExactlyOnce() throws {
        let plan = try PlanBuilder.build(questions: questions(30), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        let scheduled = plan.days.flatMap(\.questionIds)
        XCTAssertEqual(scheduled.count, 30)
        XCTAssertEqual(Set(scheduled).count, 30)
    }

    func testDistributesAsEvenlyAsPossible() throws {
        let plan = try PlanBuilder.build(questions: questions(30), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        let counts = plan.days.map(\.questionIds.count)
        // 30 / 7 = 4 余 2 → 前两天 5 题，其余 4 题
        XCTAssertEqual(counts, [5, 5, 4, 4, 4, 4, 4])
    }

    func testCreatesExactlyRequestedNumberOfDays() throws {
        for length in [7, 14, 30] {
            let plan = try PlanBuilder.build(questions: questions(60), lengthDays: length,
                                             createdAt: "2026-08-04T00:00:00Z")
            XCTAssertEqual(plan.days.count, length)
        }
    }

    func testRejectsUnsupportedLength() {
        XCTAssertThrowsError(try PlanBuilder.build(questions: questions(10), lengthDays: 5,
                                                   createdAt: "2026-08-04T00:00:00Z"))
    }

    func testRejectsEmptyQuestionSet() {
        XCTAssertThrowsError(try PlanBuilder.build(questions: [], lengthDays: 7,
                                                   createdAt: "2026-08-04T00:00:00Z")) { error in
            XCTAssertTrue("\(error)".contains("题库里没有题目"))
        }
    }

    func testFewerQuestionsThanDaysLeavesTrailingDaysEmpty() throws {
        let plan = try PlanBuilder.build(questions: questions(3), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        XCTAssertEqual(plan.days.prefix(3).map(\.questionIds.count), [1, 1, 1])
        XCTAssertTrue(plan.days.suffix(4).allSatisfy { $0.questionIds.isEmpty })
    }

    func testDayCompletesOnlyWhenAllItsQuestionsDone() throws {
        // 必须用 7/14/30 之一 —— supportedLengths 只接受这三档（上游的产品规则）。
        // 14 题分 7 天，每天恰好 2 题，同样能验「当天题目全做完才算完成」。
        var plan = try PlanBuilder.build(questions: questions(14), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        XCTAssertEqual(plan.days[0].questionIds.count, 2)
        plan = PlanBuilder.markCompleted(plan: plan, questionID: plan.days[0].questionIds[0])
        XCTAssertFalse(plan.days[0].isComplete)
        plan = PlanBuilder.markCompleted(plan: plan, questionID: plan.days[0].questionIds[1])
        XCTAssertTrue(plan.days[0].isComplete)
        XCTAssertFalse(plan.isComplete)
    }

    func testEmptyDayIsNeverComplete() throws {
        let plan = try PlanBuilder.build(questions: questions(1), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        XCTAssertFalse(plan.days[6].isComplete)
    }

    // 文档注释承诺「同一题重复标记不会产生重复项」，但一直没有测试验证。
    // markCompleted 里 `!contains` 去重守卫删掉后没有任何测试变红——重复处理
    // pending-review（例如用户对同一题反复点了「已复盘」）会把 completedQuestionIds
    // 灌胀出重复项，进而污染依赖去重计数的进度展示。
    func testMarkCompletedIsIdempotentForSameQuestion() throws {
        let plan = try PlanBuilder.build(questions: questions(14), lengthDays: 7,
                                         createdAt: "2026-08-04T00:00:00Z")
        let questionID = plan.days[0].questionIds[0]
        var marked = plan
        for _ in 0..<3 {
            marked = PlanBuilder.markCompleted(plan: marked, questionID: questionID)
        }
        XCTAssertEqual(marked.days[0].completedQuestionIds.count, 1,
                       "重复标记同一题不应产生重复的 completedQuestionIds 项")
    }
}
