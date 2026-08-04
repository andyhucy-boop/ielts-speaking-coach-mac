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
        XCTAssertEqual(target?.id, "logic-explain-example")
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

    func testReturnsNilWhenTargetIDIsBlank() throws {
        XCTAssertNil(RetrainingPolicy.extractTarget(
            from: try report(#"{"priority_target":{"id":"  ","label":"x"}}"#),
            sessionID: "s1", createdAt: "t"))
    }

    func testDefaultsStatusToNewWhenAbsent() throws {
        let target = RetrainingPolicy.extractTarget(
            from: try report(#"{"priority_target":{"id":"t1","label":"L"}}"#),
            sessionID: "s1", createdAt: "t")
        XCTAssertEqual(target?.status, "new")
    }

    func testRankPutsTargetsBackedByRepeatedIssuesFirst() {
        let targets = [
            RetrainingTarget(id: "rare", label: "L1", status: "new", evidence: ["I just like it."],
                             sourceSessionId: "s1", createdAt: "t"),
            RetrainingTarget(id: "common", label: "L2", status: "new", evidence: ["I very like it."],
                             sourceSessionId: "s2", createdAt: "t")
        ]
        let issues = [
            IssueRecord(id: "i1", learnerSaid: "I very like it.", correction: "I really like it.",
                        whyItMatters: "", occurrences: 5, sourceSessionIds: ["s1", "s2"], lastSeenAt: "t")
        ]
        XCTAssertEqual(RetrainingPolicy.rank(targets: targets, issues: issues).first?.id, "common")
    }

    func testRankExcludesRetiredTargets() {
        let targets = [
            RetrainingTarget(id: "done", label: "L", status: "retired", evidence: [],
                             sourceSessionId: "s1", createdAt: "t"),
            RetrainingTarget(id: "live", label: "L", status: "new", evidence: [],
                             sourceSessionId: "s2", createdAt: "t")
        ]
        let ranked = RetrainingPolicy.rank(targets: targets, issues: [])
        XCTAssertEqual(ranked.map(\.id), ["live"])
    }
}
