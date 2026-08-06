import XCTest
@testable import IELTSCoachCore

final class SessionIDTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let noon = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!

    private func session(_ id: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: "",
                        endedAt: "", goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    // MARK: - next：新产生的编号一律是新形状

    func testFirstSessionOfTheDayIsNumberedOne() {
        XCTAssertEqual(SessionID.next(existing: [], now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testContinuesFromTheHighestNumberNotTheCount() {
        // 用「已有条数 + 1」会在有空缺时撞号：只剩 003 时会算出 002，
        // 而 002 可能只是被删掉的那条（训练记录允许单条删除，见 Task 9）。
        // 撞号意味着两次练习的复盘写到同一个 reports/<id>.json 上，后一次直接盖掉前一次。
        let existing = [session("2026-08-06-003")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-004")
    }

    func testCountsOnlyTheSameDay() {
        let existing = [session("2026-08-05-009"), session("2026-08-06-001")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-002")
    }

    func testIgnoresSessionIDsInOtherFormats() {
        // 旧数据里的 sessionID 是 ISO8601 时间戳（coach practice 当初就是这么生成的），
        // 不能因为解析不出编号就崩，也不能让它影响今天的编号。
        let existing = [session("2026-08-06T10:00:00Z"), session("随便什么")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testUsesTheGivenTimeZoneNotTheMachineOne() {
        // 东八区的凌晨 1 点，在 UTC 还是前一天的 17 点。编号里的日期必须跟着传入的时区走，
        // 否则用户在午夜前后练的两场会被编到看起来矛盾的日期上。
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let lateNight = ISO8601DateFormatter().date(from: "2026-08-06T17:00:00Z")!
        XCTAssertEqual(SessionID.next(existing: [], now: lateNight, timeZone: shanghai),
                       "2026-08-07-001")
        XCTAssertEqual(SessionID.next(existing: [], now: lateNight, timeZone: utc),
                       "2026-08-06-001")
    }

    // MARK: - validated：旧编号必须仍然读得进来（决策 1）

    func testValidatedAcceptsTheNewShape() throws {
        XCTAssertEqual(try SessionID.validated("2026-08-06-001"), "2026-08-06-001")
        XCTAssertEqual(try SessionID.validated("  sync-1785940167 "), "sync-1785940167")
    }

    /// **决策 1 的守卫。** 用户现有的 state.json 里就是这种 id。
    /// 拒绝它 = 已有练习记录全部失效。
    func testValidatedStillAcceptsTheOldISO8601IDs() throws {
        XCTAssertEqual(try SessionID.validated("2026-08-05T14:03:11Z"), "2026-08-05T14:03:11Z")
        XCTAssertEqual(try SessionID.validated("2026-08-05T14:03:11+08:00"),
                       "2026-08-05T14:03:11+08:00")
    }

    func testValidatedRejectsAnythingThatCouldEscapeTheDataDirectory() {
        // 这个字符串会直接拼进 pending-reviews/<id>.txt 和 reports/<id>.json。
        for bad in ["../evil", "a/b", "..", ".", "", "   ", "a\u{0000}b", "~/secret", "a\\b"] {
            XCTAssertThrowsError(try SessionID.validated(bad), "「\(bad)」不该被放行") { error in
                XCTAssertTrue("\(error.localizedDescription)".contains("下一步"),
                              "错误信息必须告诉用户下一步做什么")
            }
        }
    }
}
