import XCTest
@testable import IELTSCoachCore

final class CoachTimeTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testParsesPlainISO8601() throws {
        // 命令行现在就是用 ISO8601DateFormatter() 的默认选项写的，这条必须过。
        //
        // 常量说明（2026-08-07 实现时修正）：计划里写的是 1785664800，
        // 但 `date -u -r 1785664800` 是 2026-08-02T10:00:00Z，差了整三天。
        // 2026-08-05T10:00:00Z 的正确 epoch 是 1785924000（`date -u -j -f ... +%s` 实测）。
        // 这是计划里的笔误，不是放宽断言——accuracy 仍是 1 秒。
        //
        // 另：计划里写的 `XCTAssertEqual(date?.timeIntervalSince1970, ..., accuracy: 1)`
        // 编译不过——带 accuracy 的重载没有 Optional 版本。改成先 XCTUnwrap 再比，
        // 断言反而更严（解析不出来时会明确失败，而不是被 Optional 吞掉）。
        let date = try XCTUnwrap(CoachTime.parse("2026-08-05T10:00:00Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1785924000, accuracy: 1)
    }

    func testParsesFractionalSeconds() {
        // ISO8601DateFormatter 的默认选项解析不了小数秒。少了这条容错，
        // 任何用 .withFractionalSeconds 写出来的时间戳都会被当成「没有时间」，
        // 统计会静默算少而不报错。
        XCTAssertNotNil(CoachTime.parse("2026-08-05T10:00:00.123Z"),
                        "带小数秒的时间戳必须也能解析")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertNotNil(CoachTime.parse("  2026-08-05T10:00:00Z\n"))
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertNil(CoachTime.parse(""))
        XCTAssertNil(CoachTime.parse("   "))
        XCTAssertNil(CoachTime.parse("昨天下午"))
    }

    func testParsesDayPrefixFromSessionIDStyle() {
        // PracticeSession.id 的文档形状是 "YYYY-MM-DD-NNN"
        let date = CoachTime.parseDayPrefix("2026-08-05-003")
        XCTAssertEqual(CoachTime.dayString(date ?? .distantPast, calendar: utc), "2026-08-05")
    }

    func testParsesDayPrefixFromFullTimestamp() {
        // 命令行归档时用的 sessionID 是完整 ISO8601 时间戳，前十位同样是日期
        let date = CoachTime.parseDayPrefix("2026-08-05T14:03:11Z")
        XCTAssertEqual(CoachTime.dayString(date ?? .distantPast, calendar: utc), "2026-08-05")
    }

    func testRejectsDayPrefixThatIsNotADate() {
        // pending-reviews 里的 requestID 长这样，绝不能被当成日期
        XCTAssertNil(CoachTime.parseDayPrefix("sync-1754123456"))
        XCTAssertNil(CoachTime.parseDayPrefix("短"))
    }

    func testDayStringUsesTheGivenCalendarTimeZone() {
        // 晚上练的一场，UTC 日期和本地日期会差一天。「最近一次：8 月 6 日」
        // 显示成 8 月 5 日，用户会以为记录错了。
        let date = CoachTime.parse("2026-08-05T23:30:00Z")!
        XCTAssertEqual(CoachTime.dayString(date, calendar: utc), "2026-08-05")
        XCTAssertEqual(CoachTime.dayString(date, calendar: shanghai), "2026-08-06")
    }
}
