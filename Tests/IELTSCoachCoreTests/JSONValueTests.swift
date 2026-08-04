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
}
