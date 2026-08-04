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

    // ⚠️ 这两个用例的输入必须是「本来就非法」的，且必须断言 repair 的**输出字符串**。
    // 原因：macOS 的 Foundation 容忍尾随逗号（实测 JSONSerialization 接受 {"a":1,}），
    // 所以用 {"a":1,} 当输入时，repair 开头的「已合法就原样返回」会直接短路，
    // removeTrailingCommas 根本不会执行——测试照样是绿的，但守护的是 JSONDecoder
    // 的容错而不是我们的代码。改用单引号强制走进修复分支。

    func testRemovesTrailingCommaInObject() throws {
        let repairedText = JSONRepair.repair("{'a':1,}")
        XCTAssertFalse(repairedText.contains(",}"), "对象的尾随逗号未被移除：\(repairedText)")
        XCTAssertEqual(try JSONValue.decode(from: repairedText)["a"], .number(1))
    }

    func testRemovesTrailingCommaInArray() throws {
        let repairedText = JSONRepair.repair("{'a':[1,2,]}")
        XCTAssertFalse(repairedText.contains(",]"), "数组的尾随逗号未被移除：\(repairedText)")
        XCTAssertEqual(try JSONValue.decode(from: repairedText)["a"]?.arrayValue?.count, 2)
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

    // ⚠️ 原版输入 {"note":"it's fine"} 本就是合法 JSON（单引号出现在双引号字符串内部，
    // 对 JSON 语法完全无害），repair() 开头「已合法就原样返回」直接短路，根本没有走进
    // 逐字符扫描循环，跟 testLeavesValidJSONUnchanged 测的是同一件事。换成本来就非法、
    // 必须靠单引号识别（stringDelimiter == "'" 分支）才能修好的输入：整个对象用单引号
    // 包裹，值内部还嵌着需要转义的双引号，逼 repair() 真正走进
    // `character == "\"" && stringDelimiter == "'"` 那条转义分支。
    func testEscapesDoubleQuotesInsideSingleQuotedStrings() throws {
        let messy = #"{'note':'it is "fine"'}"#
        let repairedText = JSONRepair.repair(messy)
        XCTAssertTrue(repairedText.contains(#"\"fine\""#),
                      "单引号字符串内部的双引号没有被转义：\(repairedText)")
        let value = try JSONValue.decode(from: repairedText)
        XCTAssertEqual(value["note"], .string(#"it is "fine""#))
    }

    func testLeavesValidJSONUnchanged() {
        let input = #"{"a":[1,2],"b":"x"}"#
        XCTAssertEqual(JSONRepair.repair(input), input)
    }
}
