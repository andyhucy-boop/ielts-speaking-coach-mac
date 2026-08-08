import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class ToolArgumentsTests: XCTestCase {
    private func arguments(_ pairs: [String: JSONValue]) -> ToolArguments {
        ToolArguments(.object(pairs))
    }

    private func message(from error: any Error) -> String {
        ((error as? ToolInputError)?.message) ?? "\(error)"
    }

    func testRequiredStringReturnsTrimmedValue() throws {
        let args = arguments(["questionId": .string("  p1-abc  ")])
        XCTAssertEqual(try args.requiredString("questionId", hint: "h"), "p1-abc")
    }

    func testRequiredStringCanKeepTheRawTextUntouched() throws {
        // 复盘原文两端的空白要原样留着——那是 ChatGPT 输出的一部分，
        // 存进 pending-reviews 的应该是它真正输出的样子。
        let args = arguments(["reviewText": .string("\n复盘\n")])
        XCTAssertEqual(try args.requiredString("reviewText", trimmed: false, hint: "h"), "\n复盘\n")
    }

    func testRequiredStringComplainsWhenMissing() {
        XCTAssertThrowsError(try arguments([:]).requiredString("questionId", hint: "先看题库拿题号。")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("questionId"), "错误信息要指名道姓说是哪个参数")
            XCTAssertTrue(text.contains("先看题库拿题号。"), "调用方给的 hint 必须出现在文案里")
        }
    }

    func testRequiredStringRejectsWrongTypeInsteadOfCoercing() {
        XCTAssertThrowsError(try arguments(["questionId": .number(3)]).requiredString("questionId", hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("字符串"))
        }
    }

    func testRequiredStringRejectsBlank() {
        XCTAssertThrowsError(try arguments(["questionId": .string("   ")]).requiredString("questionId", hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("空"))
        }
    }

    func testOptionalStringTreatsBlankAndNullAsAbsent() throws {
        XCTAssertNil(try arguments([:]).optionalString("goal"))
        XCTAssertNil(try arguments(["goal": .null]).optionalString("goal"))
        XCTAssertNil(try arguments(["goal": .string("  ")]).optionalString("goal"))
        XCTAssertEqual(try arguments(["goal": .string(" 补一个例子 ")]).optionalString("goal"), "补一个例子")
    }

    func testOptionalStringRejectsWrongTypeInsteadOfSilentlyDroppingIt() {
        // 「键在、但类型不对」不是「没传」。悄悄当成没传的后果是实打实的：
        // save_session_review 会新开一场会话而不是把复盘追加到指定会话上，
        // list_practice_history 会返回一份看着对、其实没过滤的全量历史，
        // 而用户和模型都收不到任何提示。铁律 7：禁止静默失败。
        // 同一个文件里 requiredString / optionalInt / optionalChoice 遇到类型不符都报错，
        // 只有 optionalString 吞掉的话，7 个 tool 就都建在这个例外上了。
        XCTAssertThrowsError(try arguments(["goal": .number(12345)]).optionalString("goal")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("goal"), "错误信息要指名道姓说是哪个参数：\(text)")
            XCTAssertTrue(text.contains("字符串"), "要说清「必须是字符串」：\(text)")
        }
        XCTAssertThrowsError(try arguments(["goal": .bool(true)]).optionalString("goal"))
        XCTAssertThrowsError(try arguments(["goal": .array([.string("a")])]).optionalString("goal"))
    }

    func testOptionalIntUsesTheDefaultWhenAbsent() throws {
        let value = try arguments([:]).optionalInt("limit", in: 1...200, default: 20, hint: "h")
        XCTAssertEqual(value, 20)
    }

    func testOptionalIntRejectsOutOfRangeInsteadOfClamping() {
        // 夹紧 = 调用方以为自己传的是 0、拿到的却是 1 的行为，且没有任何提示。
        // 这正是本项目反复消灭的那类静默失败。
        XCTAssertThrowsError(try arguments(["limit": .number(0)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "传 1–200。")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("1"))
            XCTAssertTrue(text.contains("200"))
            XCTAssertTrue(text.contains("传 1–200。"))
        }
        XCTAssertThrowsError(try arguments(["limit": .number(999)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h"))
    }

    func testOptionalIntRejectsFractionsAndStrings() {
        XCTAssertThrowsError(try arguments(["limit": .number(3.5)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("整数"))
        }
        XCTAssertThrowsError(try arguments(["limit": .string("12")])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h"))
    }

    func testOptionalChoiceFallsBackWhenAbsentOrNull() throws {
        XCTAssertEqual(try arguments([:]).optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h"), "a")
        XCTAssertEqual(try arguments(["mode": .null])
            .optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h"), "a")
    }

    func testOptionalChoiceRejectsUnknownValueAndListsWhatIsAllowed() {
        XCTAssertThrowsError(try arguments(["mode": .string("c")])
            .optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("c"))
            XCTAssertTrue(text.contains("a"))
            XCTAssertTrue(text.contains("b"))
        }
    }

    func testEveryErrorMessageTellsTheCallerWhatToDoNext() {
        // 逐条兜住「禁止只报错不给出路」。漏一条都算不合格。
        let failures: [() throws -> Any] = [
            { try self.arguments([:]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .number(1)]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .string(" ")]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .number(1)]).optionalString("k") as Any },
            { try self.arguments(["k": .number(0)]).optionalInt("k", in: 1...9, default: 5, hint: "改这里。") },
            { try self.arguments(["k": .number(1.5)]).optionalInt("k", in: 1...9, default: 5, hint: "改这里。") },
            { try self.arguments(["k": .string("x")]).optionalChoice("k", allowed: ["y"], default: "y", hint: "改这里。") }
        ]
        for (index, failure) in failures.enumerated() {
            XCTAssertThrowsError(try failure(), "第 \(index) 条本应报错") { error in
                XCTAssertTrue(self.message(from: error).contains("下一步"),
                              "第 \(index) 条的错误信息没有说下一步做什么：\(self.message(from: error))")
            }
        }
    }
}
