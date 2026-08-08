import XCTest
@testable import IELTSCoachCore

final class RetrainingPolicyTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    func testExtractsPriorityTarget() throws {
        let value = try report("""
        {"must_correct":[],"priority_target":{"id":"logic-explain-example",
        "label":"Add a reason and example after the main claim","status":"new",
        "evidence":["I just like it."]}}
        """)
        let target = RetrainingPolicy.extractTarget(from: value, sessionID: "2026-08-04-001",
                                                    createdAt: "2026-08-04T10:00:00Z")
        XCTAssertEqual(target?.targetKey, "logic-explain-example")
        XCTAssertEqual(target?.label, "Add a reason and example after the main claim")
        XCTAssertEqual(target?.status, "new")
        XCTAssertEqual(target?.evidence, ["I just like it."])
        XCTAssertEqual(target?.sourceSessionId, "2026-08-04-001")
    }

    func testReturnsNilWhenPriorityTargetMissing() throws {
        XCTAssertNil(RetrainingPolicy.extractTarget(
            from: try report(#"{"must_correct":[]}"#),
            sessionID: "s1", createdAt: "t"))
    }

    /// **id 缺失或只有空白时不许把目标丢掉。**
    ///
    /// 提示词是要求给全的，但没有任何校验拦得住 ChatGPT 漏写一个键。真实后果：
    /// 复盘报告页照常画那张最显眼的深色卡片「下一次只盯这一个」，`state.targets` 一条不加，
    /// 用户转身打开复训中心看到的是「还没有待复训的目标。下一步：先完整练一场」——
    /// 一句在他刚练完一整场、复盘也确实给了目标的前提下**字面上为假**的话。
    func testABlankTargetIDFallsBackToTheSessionInsteadOfDroppingTheTarget() throws {
        for json in [#"{"priority_target":{"id":"  ","label":"补一个原因和例子"}}"#,
                     #"{"priority_target":{"label":"补一个原因和例子"}}"#] {
            let target = RetrainingPolicy.extractTarget(
                from: try report(json), sessionID: "2026-08-08-001", createdAt: "t")
            XCTAssertNotNil(target, "id 缺失就把整个目标丢掉了，改进闭环当场断掉：\(json)")
            XCTAssertEqual(target?.label, "补一个原因和例子")
            XCTAssertEqual(target?.targetKey, "target-2026-08-08-001",
                           "兜底 key 必须只由会话编号决定，否则同一场归档两次会变成两条目标")
            XCTAssertEqual(target?.sourceSessionId, "2026-08-08-001")
        }
    }

    /// 兜底 key 只由会话编号决定——掺进时间戳或随机数的话，同一场复盘归档两次就是两条目标，
    /// `ReviewArchiver` 那条「同一场重复入库不新增」的幂等当场破掉。
    func testTheFallbackKeyIsStableAcrossCalls() throws {
        let value = try report(#"{"priority_target":{"label":"补一个原因和例子"}}"#)
        let first = RetrainingPolicy.extractTarget(from: value, sessionID: "s1", createdAt: "t1")
        let second = RetrainingPolicy.extractTarget(from: value, sessionID: "s1", createdAt: "t2")
        XCTAssertEqual(first?.targetKey, second?.targetKey)
    }

    /// id 和 label 都没有才算「这份复盘没给目标」——那时连要盯什么都说不出来，兜底也造不出内容。
    /// 这条不能省：没有它，`extractTarget` 退化成「只要 priority_target 是个对象就造一条」，
    /// 上面那条照样绿，而档案里会多出一条没有标题、点开什么都没有的目标。
    func testReturnsNilWhenTheTargetHasNeitherIDNorLabel() throws {
        for json in [#"{"priority_target":{"status":"new"}}"#,
                     #"{"priority_target":{"id":" ","label":"  "}}"#,
                     #"{"priority_target":{}}"#] {
            XCTAssertNil(RetrainingPolicy.extractTarget(
                from: try report(json), sessionID: "s1", createdAt: "t"),
                         "既没有 id 也没有 label，却造出了一条空目标：\(json)")
        }
    }

    /// 形状不对（写成字符串、数组）时同样是 nil，而不是崩溃或造出一条空目标。
    func testReturnsNilWhenTheTargetIsNotAnObject() throws {
        for json in [#"{"priority_target":"补一个原因和例子"}"#,
                     #"{"priority_target":["补一个原因和例子"]}"#,
                     #"{"priority_target":null}"#] {
            XCTAssertNil(RetrainingPolicy.extractTarget(
                from: try report(json), sessionID: "s1", createdAt: "t"), json)
        }
    }

    func testDefaultsStatusToNewWhenAbsent() throws {
        let target = RetrainingPolicy.extractTarget(
            from: try report(#"{"priority_target":{"id":"t1","label":"L"}}"#),
            sessionID: "s1", createdAt: "t")
        XCTAssertEqual(target?.status, "new")
    }

    func testRankPutsTargetsBackedByRepeatedIssuesFirst() {
        let targets = [
            RetrainingTarget(targetKey: "rare", label: "L1", status: "new", evidence: ["I just like it."],
                             sourceSessionId: "s1", createdAt: "t"),
            RetrainingTarget(targetKey: "common", label: "L2", status: "new", evidence: ["I very like it."],
                             sourceSessionId: "s2", createdAt: "t")
        ]
        let issues = [
            IssueRecord(id: "i1", learnerSaid: "I very like it.", correction: "I really like it.",
                        whyItMatters: "", occurrences: 5, sourceSessionIds: ["s1", "s2"], lastSeenAt: "t")
        ]
        XCTAssertEqual(RetrainingPolicy.rank(targets: targets, issues: issues).first?.targetKey, "common")
    }

    func testRankExcludesRetiredTargets() {
        let targets = [
            RetrainingTarget(targetKey: "done", label: "L", status: "retired", evidence: [],
                             sourceSessionId: "s1", createdAt: "t"),
            RetrainingTarget(targetKey: "live", label: "L", status: "new", evidence: [],
                             sourceSessionId: "s2", createdAt: "t")
        ]
        let ranked = RetrainingPolicy.rank(targets: targets, issues: [])
        XCTAssertEqual(ranked.map(\.targetKey), ["live"])
    }
}
