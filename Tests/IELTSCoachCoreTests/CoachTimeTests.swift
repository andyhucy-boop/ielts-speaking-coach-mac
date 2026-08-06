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

    func testParsesTimestampWithSurroundingWhitespace() {
        // 守的是行为契约：带前后空白的时间戳照样得解析出来（比如从文件里整行读进来的）。
        //
        // ⚠️ 这条测试**守不住 CoachTime.swift 里那一行 trim**，这是实测结论，别再拿它当
        // 「trim 的单元测试」用：macOS 26.5.2 上 ISO8601DateFormatter 会自己跳过前导空白
        //（普通空格、\n、\t、NBSP U+00A0、U+2028、U+3000 全都跳），尾部还允许挂垃圾
        //（"2026-08-05T10:00:00Zabc" 都能解析成功）。带不带小数秒都一样。
        // 也就是说目前**不存在**任何一个输入能让「删掉 trim」变红——trim 是对
        // Foundation 这个未写进文档的宽容行为的保险，不是可观测行为。
        // 真正能守住 trim 的是下面 testParsesDayPrefixWithSurroundingWhitespace，
        // 因为 parseDayPrefix 要靠 prefix(10) 截字符串，空白会把截取窗口顶歪。
        XCTAssertNotNil(CoachTime.parse("  2026-08-05T10:00:00Z\n"),
                        "带前后空白的时间戳必须能解析")
        XCTAssertNotNil(CoachTime.parse("  2026-08-05T10:00:00.123Z\n"),
                        "带前后空白的小数秒时间戳必须能解析")
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

    func testParsesDayPrefixWithSurroundingWhitespace() {
        // parseDayPrefix 靠 prefix(10) 截前十位。不 trim 的话，前导空白会把截取窗口
        // 顶歪成 "  2026-08-"，一条正常的 session id 就被当成「没有日期」丢掉，
        // 统计静默算少。这条是 CoachTime.swift 里 trim 的真实约束。
        let date = CoachTime.parseDayPrefix("  2026-08-05-003\n")
        XCTAssertEqual(CoachTime.dayString(date ?? .distantPast, calendar: utc), "2026-08-05",
                       "带前后空白的 session id 必须仍能取出日期")
    }

    func testRejectsDayPrefixThatIsNotADate() {
        // pending-reviews 里的 requestID 长这样，绝不能被当成日期
        XCTAssertNil(CoachTime.parseDayPrefix("sync-1754123456"))
        XCTAssertNil(CoachTime.parseDayPrefix("短"))
    }

    func testRejectsDayPrefixThatIsAnImpossibleDate() {
        // 守 isLenient = false。宽松模式下 DateFormatter 会把非法日期「顺延」成别的日期
        //（实测：2026-13-45 → 2027-02-14，2026-02-30 → 2026-03-02），
        // 一条坏掉的 session id 就被静默归进错误的周/月——算错比算少更难发现。
        XCTAssertNil(CoachTime.parseDayPrefix("2026-13-45-001"),
                     "非法月日必须拒绝，不能被宽松解析成别的日期")
        XCTAssertNil(CoachTime.parseDayPrefix("2026-02-30-001"),
                     "2 月 30 日必须拒绝，不能被宽松顺延成 3 月 2 日")
    }

    func testDayStringUsesTheGivenCalendarTimeZone() {
        // 晚上练的一场，UTC 日期和本地日期会差一天。「最近一次：8 月 6 日」
        // 显示成 8 月 5 日，用户会以为记录错了。
        let date = CoachTime.parse("2026-08-05T23:30:00Z")!
        XCTAssertEqual(CoachTime.dayString(date, calendar: utc), "2026-08-05")
        XCTAssertEqual(CoachTime.dayString(date, calendar: shanghai), "2026-08-06")
    }

    func testStringFromProducesTheProjectTimestampShape() throws {
        // string(from:) 是 parse 的另一半：写出去的形状一旦变了（少个 Z、带上小数秒、
        // 换成本地时区），下游 CoachTime.parse 会返回 nil，统计静默算少。
        // 所以这里锁死具体字面量——UTC、无小数秒、以 Z 结尾。
        let date = try XCTUnwrap(CoachTime.parse("2026-08-05T10:00:00Z"))
        XCTAssertEqual(CoachTime.string(from: date), "2026-08-05T10:00:00Z")
    }

    func testStringFromRoundTripsThroughParse() throws {
        // 写出去的必须读得回来，且时刻不变。
        let original = Date(timeIntervalSince1970: 1785924000)   // 2026-08-05T10:00:00Z
        let text = CoachTime.string(from: original)
        let reparsed = try XCTUnwrap(CoachTime.parse(text),
                                     "string(from:) 写出的时间戳必须能被 parse 读回来")
        XCTAssertEqual(reparsed.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 1)
    }
}
