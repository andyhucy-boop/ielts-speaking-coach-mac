import XCTest
@testable import IELTSCoachCore

final class JSONRepairTests: XCTestCase {
    private func repaired(_ s: String) throws -> JSONValue {
        try JSONValue.decode(from: JSONRepair.repair(s))
    }

    func testConvertsSingleQuotesToDouble() throws {
        let value = try repaired("{'summary':'ok'}")
        XCTAssertEqual(value["summary"], .string("ok"))
    }

    func testRemovesTrailingCommaInObject() throws {
        let value = try repaired(#"{"a":1,}"#)
        XCTAssertEqual(value["a"], .number(1))
    }

    func testRemovesTrailingCommaInArray() throws {
        let value = try repaired(#"{"a":[1,2,]}"#)
        XCTAssertEqual(value["a"]?.arrayValue?.count, 2)
    }

    func testHandlesUpstreamCombinedCase() throws {
        let value = try repaired("{'summary':'ok','must_correct':[],'priority_target':{'id':'expand'},}")
        XCTAssertEqual(value["summary"], .string("ok"))
        XCTAssertEqual(value["must_correct"]?.arrayValue?.count, 0)
        XCTAssertEqual(value["priority_target"]?["id"], .string("expand"))
    }

    func testClosesTruncatedTail() throws {
        let value = try repaired(#"{"a":1,"b":{"c":2"#)
        XCTAssertEqual(value["a"], .number(1))
    }

    func testDoesNotTouchQuotesInsideStrings() throws {
        let value = try repaired(#"{"note":"it's fine"}"#)
        XCTAssertEqual(value["note"], .string("it's fine"))
    }

    func testLeavesValidJSONUnchanged() {
        let input = #"{"a":[1,2],"b":"x"}"#
        XCTAssertEqual(JSONRepair.repair(input), input)
    }
}
