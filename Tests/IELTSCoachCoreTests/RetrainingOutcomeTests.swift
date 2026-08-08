import XCTest
@testable import IELTSCoachCore

final class RetrainingOutcomeTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    func testNoReportMeansWeSimplyDoNotKnow() {
        XCTAssertEqual(RetrainingOutcome.judge(report: nil, targetKey: "logic-explain"), .noReport)
    }

    func testSameTargetNamedAgain() throws {
        let value = try report(#"""
        {"must_correct":[],"priority_target":{"id":"logic-explain","label":"补一个原因和例子",
         "status":"new","evidence":["I just like it."]}}
        """#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"), .namedAgain)
    }

    func testDifferentTargetMeansItWasNotNamedAgain() throws {
        let value = try report(#"""
        {"must_correct":[],"priority_target":{"id":"tense-consistency","label":"时态别乱跳",
         "status":"new","evidence":[]}}
        """#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)
    }

    func testNoPriorityTargetAtAllMeansItWasNotNamedAgain() throws {
        let value = try report(#"{"must_correct":[],"summary":"整体不错"}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)
    }

    /// 一份根本不成形的「复盘」（比如解析降级后拿到的是一个字符串）不能被当成通过。
    /// 把没认出来的东西当成好消息，正是本项目栽过跟头的那一类。
    func testGarbageReportIsUnknownNotAPass() throws {
        XCTAssertEqual(RetrainingOutcome.judge(report: .string("ChatGPT 说了一堆没有 JSON 的话"),
                                               targetKey: "logic-explain"), .noReport)
        XCTAssertEqual(RetrainingOutcome.judge(report: .array([]), targetKey: "logic-explain"),
                       .noReport)
        XCTAssertEqual(RetrainingOutcome.judge(report: .null, targetKey: "logic-explain"), .noReport)
    }

    /// ChatGPT 输出的 id 可能带前后空白；`RetrainingPolicy.extractTarget` 也是去空白后再用的，
    /// 两处判据不一致会导致「明明是同一个目标却说没被点名」。
    func testWhitespaceAroundIDsDoesNotChangeTheVerdict() throws {
        let value = try report(#"{"priority_target":{"id":"  logic-explain  ","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"), .namedAgain)
    }

    /// 上一条只钉住了「复盘里的 id 带空白」这一侧。判据有两侧，另一侧（传进来的 targetKey
    /// 带空白）没人守，去掉那一处 trimming 全部测试照样绿——本项目消灭空转的老账。
    /// 后果同样具体：目标那侧多一个空格，换题验证就会一律报「这一次没有再被点名」，
    /// 而这是好消息方向的静默错判，用户不会察觉。
    func testWhitespaceAroundTheStoredTargetKeyDoesNotChangeTheVerdict() throws {
        let value = try report(#"{"priority_target":{"id":"logic-explain","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "  logic-explain\n"),
                       .namedAgain)
    }

    func testBlankIDIsTreatedAsNotNamedAgain() throws {
        let value = try report(#"{"priority_target":{"id":"   ","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)

        // 上面那条断言其实钉不住「空白 id」这道守卫本身：targetKey 是 "logic-explain"，
        // 守卫拿掉以后空串跟它一比仍然不等，照样返回 .notNamedAgain，结果一模一样。
        // 守卫唯一改变行为的输入是「两边都空白」，所以必须显式钉住这一格。
        // 后果具体：targetKey 空白是能发生的——`RetrainingPolicy.extractTarget` 虽然挡了，
        // 但台账是从磁盘 JSON 解码回来的，`RetrainingLink(targetKey:)` 也是公开构造器，
        // 旧数据或绕过 extractTarget 的调用方都能塞进一个空白 key。没有守卫时，
        // 「台账里没记住目标」和「这份复盘没给出目标」两个空串会判等，
        // 于是报「又被点名了」——凭两处「什么都没有」编出一个命中。
        let blank = try report(#"{"priority_target":{"id":"   ","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: blank, targetKey: "  "), .notNamedAgain)
    }
}
