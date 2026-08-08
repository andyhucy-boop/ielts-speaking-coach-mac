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

    // MARK: - IssueRecord.occurrences 的读盘迁移

    private func issueJSON(occurrences: String, sourceSessionIds: String) -> Data {
        Data("""
        {"id":"issue-1-s1","learnerSaid":"I very like it.","correction":"I really like it.",
         "whyItMatters":"very 不能修饰动词","occurrences":\(occurrences),
         "sourceSessionIds":\(sourceSessionIds),"lastSeenAt":"t1"}
        """.utf8)
    }

    /// **老档案里虚高的「出现次数」要在读盘这一刻修回来。**
    ///
    /// 修好之前的 `ReviewArchiver` 每次命中都 `+= 1`，同一场复盘补录一次就多加一遍，
    /// 而 `sourceSessionIds` 是干净的。用户不该为了拿到真实数字去手工编辑 state.json——
    /// 何况他根本无从知道自己的数字是虚的。
    func testInflatedOccurrencesAreRepairedOnDecode() throws {
        let record = try JSONDecoder().decode(
            IssueRecord.self, from: issueJSON(occurrences: "5", sourceSessionIds: #"["s1","s2"]"#))
        XCTAssertEqual(record.occurrences, 2,
                       "两场练习里犯过，档案却说 5 次——用户会以为老毛病越来越严重")
        XCTAssertEqual(record.sourceSessionIds, ["s1", "s2"], "场次本身不许改动")
    }

    /// 没虚高的档案要原样读出来。少了这条，把迁移写成 `occurrences = 0`
    /// 或者 `occurrences = 1` 都能让上面那条以外的断言蒙混过关。
    func testHealthyOccurrencesAreLeftAlone() throws {
        let record = try JSONDecoder().decode(
            IssueRecord.self, from: issueJSON(occurrences: "3",
                                              sourceSessionIds: #"["s1","s2","s3"]"#))
        XCTAssertEqual(record.occurrences, 3)
    }

    /// `sourceSessionIds` 为空时**不动**：算回来会变成 0，
    /// 等于把一条真实存在的错题说成「一次都没犯过」，比留着一个偏大的数更糟。
    func testOccurrencesAreNotZeroedWhenThereAreNoSourceSessions() throws {
        let record = try JSONDecoder().decode(
            IssueRecord.self, from: issueJSON(occurrences: "4", sourceSessionIds: "[]"))
        XCTAssertEqual(record.occurrences, 4, "没有场次可依据时，不许把数字抹成 0")
    }

    /// 编码那一半必须仍由 Swift 合成：手写了 `init(from:)` 之后若把 `encode(to:)`
    /// 一起接管而漏掉某个键，state.json 会静默少一个字段。
    func testIssueRecordStillEncodesEveryField() throws {
        let record = IssueRecord(id: "issue-1-s1", learnerSaid: "I very like it.",
                                 correction: "I really like it.", whyItMatters: "why",
                                 occurrences: 2, sourceSessionIds: ["s1", "s2"], lastSeenAt: "t1")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(IssueRecord.self, from: data)
        XCTAssertEqual(decoded, record, "编码/解码不是一对一，state.json 会悄悄丢字段")
    }
}
