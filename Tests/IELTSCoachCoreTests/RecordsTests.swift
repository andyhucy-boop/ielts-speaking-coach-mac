import XCTest
@testable import IELTSCoachCore

final class RecordsTests: XCTestCase {
    // targetKey 是 Swift 侧改的名字，但 state.json 必须仍然写 "id"，
    // 否则会和上游 Windows 版的存档格式对不上。
    func testRetrainingTargetEncodesTargetKeyAsIDForUpstreamCompatibility() throws {
        let target = RetrainingTarget(targetKey: "logic-explain-example", label: "补一个原因和例子",
                                      status: "new", evidence: ["I just like it."],
                                      sourceSessionId: "s1", createdAt: "2026-08-04T10:00:00Z")
        let data = try JSONEncoder().encode(target)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"id\":\"logic-explain-example\""),
                     "state.json 里这个字段的键名必须仍是 id：\(raw)")
        XCTAssertFalse(raw.contains("\"targetKey\""), "targetKey 不应该出现在编码后的 JSON 里：\(raw)")
    }

    func testRetrainingTargetDecodesFromUpstreamIDField() throws {
        let json = """
        {"id":"logic-explain-example","label":"L","status":"new","evidence":[],
         "sourceSessionId":"s1","createdAt":"t"}
        """
        let target = try JSONDecoder().decode(RetrainingTarget.self, from: Data(json.utf8))
        XCTAssertEqual(target.targetKey, "logic-explain-example")
    }

    // Identifiable.id 拼上 sourceSessionId 是为了让 SwiftUI 的 ForEach 不会因为
    // 两个不同 session 给出同一个 targetKey 而渲染错乱；targetKey 本身允许重复。
    func testRetrainingTargetIdentifiableIDIsUniquePerSession() {
        let sessionOne = RetrainingTarget(targetKey: "logic-explain-example", label: "L", status: "new",
                                          evidence: [], sourceSessionId: "s1", createdAt: "t")
        let sessionTwo = RetrainingTarget(targetKey: "logic-explain-example", label: "L", status: "new",
                                          evidence: [], sourceSessionId: "s2", createdAt: "t")
        XCTAssertEqual(sessionOne.id, "logic-explain-example@s1")
        XCTAssertNotEqual(sessionOne.id, sessionTwo.id, "跨 session 重复的 targetKey 不应产生相同的 Identifiable id")
    }
}
