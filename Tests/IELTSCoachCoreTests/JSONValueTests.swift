import XCTest
@testable import IELTSCoachCore

final class JSONValueTests: XCTestCase {
    func testDecodesNestedObject() throws {
        let value = try JSONValue.decode(from: #"{"a":[1,"x",true,null],"b":{"c":2}}"#)
        XCTAssertEqual(value["a"]?.arrayValue?.count, 4)
        XCTAssertEqual(value["a"]?.arrayValue?[1].stringValue, "x")
        XCTAssertEqual(value["b"]?["c"], .number(2))
    }

    func testRoundTripsThroughEncoding() throws {
        let original = try JSONValue.decode(from: #"{"must_correct":[],"priority_target":{"id":"expand"}}"#)
        let data = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(original, again)
    }

    func testThrowsChineseErrorOnMalformedJSON() {
        XCTAssertThrowsError(try JSONValue.decode(from: #"{"a":1,"b":"#)) { error in
            let message = (error as? CoachError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("不是合法的 JSON"), "错误信息不对：\(message)")
            XCTAssertTrue(message.contains("下一步"), "错误信息缺少下一步指引：\(message)")
        }
    }
}

extension JSONValueTests {
    func testIntValueOnlyAcceptsWholeNumbers() {
        XCTAssertEqual(JSONValue.number(20).intValue, 20)
        XCTAssertEqual(JSONValue.number(-3).intValue, -3)
        // 3.5 静默截断成 3 是最坏的处理方式：调用方以为自己传的是 3.5，
        // 拿到的行为却是 3，而且没有任何提示。
        XCTAssertNil(JSONValue.number(3.5).intValue)
        XCTAssertNil(JSONValue.string("20").intValue, "字符串不能被当成数字")
        XCTAssertNil(JSONValue.bool(true).intValue)
        XCTAssertNil(JSONValue.null.intValue)
    }

    /// 计划里的实现是「先判整数、再 `value <= Double(Int.max)`、最后 `Int(value)`」。
    /// `Double(Int.max)` 实际是 2^63，比 `Int.max` 大 1，所以参数恰好是 2^63 时
    /// 那个写法会通过范围判断、然后在转换处崩溃。MCP 的参数是模型给的，
    /// 一个超大数字就能把 server 打死，而客户端只会显示「服务器没响应」。
    /// 这条钉住：越界的数字必须安静地返回 nil，不许崩。
    func testIntValueRejectsNumbersOutsideIntRangeInsteadOfCrashing() {
        XCTAssertNil(JSONValue.number(Double(Int.max)).intValue, "2^63 超出 Int 范围")
        XCTAssertNil(JSONValue.number(-Double(Int.max) * 2).intValue, "-2^64 超出 Int 范围")
        XCTAssertNil(JSONValue.number(.infinity).intValue)
        XCTAssertNil(JSONValue.number(.nan).intValue)
        XCTAssertEqual(JSONValue.number(Double(Int.min)).intValue, Int.min, "-2^63 本身是合法的 Int")
    }

    func testDoubleAndBoolAccessors() {
        XCTAssertEqual(JSONValue.number(1.5).doubleValue, 1.5)
        XCTAssertNil(JSONValue.string("1.5").doubleValue)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertNil(JSONValue.number(0).boolValue, "0 不是 false，JSON 里这是两种类型")
    }
}
