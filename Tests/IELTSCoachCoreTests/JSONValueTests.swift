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
