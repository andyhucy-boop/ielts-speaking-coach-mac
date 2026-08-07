import XCTest
@testable import IELTSCoachCore

final class TrainingPlanCodableTests: XCTestCase {

    /// 这条守的是最贵的那种失败：用户硬盘上已经有一份 state.json，
    /// 里面的 plan 是旧版本写的、没有 focusPart 字段。若解码要求这个字段必须存在，
    /// 整份 state.json 会解不出来，StateStore 会报「训练数据文件已损坏」，
    /// 用户的全部练习记录当场看不见了。
    func testDecodesLegacyPlanWithoutFocusPart() throws {
        let legacy = """
        {"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z",
         "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]}
        """
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: Data(legacy.utf8))
        XCTAssertEqual(plan.focusPart, .fullMock, "旧计划没有这个字段时按全真模考处理")
        XCTAssertEqual(plan.lengthDays, 7)
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertEqual(plan.days[0].completedQuestionIds, ["q1"], "已完成的题不能在解码时丢掉")
    }

    func testDecodesFocusPartWhenPresent() throws {
        let json = """
        {"lengthDays":14,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 2","days":[]}
        """
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.focusPart, .part2)
    }

    func testEncodesFocusPartSoItSurvivesARoundTrip() throws {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z",
                                days: [PlanDay(id: 1, questionIds: ["q1"], completedQuestionIds: [])],
                                focusPart: .part3)
        let data = try JSONEncoder().encode(plan)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"focusPart\""),
                      "字段没写进去，重开 App 就忘了用户选的重点 Part")
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data).focusPart, .part3)
    }

    /// PlanBuilder.build 与 Phase 0–2 的测试都用三参数构造。
    /// 加字段不能把它们打断——那会变成一次跨阶段的返工。
    func testThreeArgumentInitStillCompilesAndDefaultsToFullMock() {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z", days: [])
        XCTAssertEqual(plan.focusPart, .fullMock)
    }
}
