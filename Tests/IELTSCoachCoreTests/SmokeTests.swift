import XCTest
@testable import IELTSCoachCore

final class SmokeTests: XCTestCase {
    func testJSONValueEquality() {
        XCTAssertEqual(JSONValue.string("a"), JSONValue.string("a"))
    }
}
