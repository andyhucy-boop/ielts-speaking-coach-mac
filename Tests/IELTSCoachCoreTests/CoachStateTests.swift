import XCTest
@testable import IELTSCoachCore

final class CoachStateTests: XCTestCase {
    func testEmptyStateMatchesUpstreamShape() throws {
        let state = CoachState.empty()
        XCTAssertEqual(state.schemaVersion, 3)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertNil(state.plan)
        XCTAssertNil(state.currentSession)
        XCTAssertFalse(state.settings.recordingEnabled)
        XCTAssertEqual(state.questionCursor.part1, 0)
    }

    func testEncodesUpstreamCamelCaseKeys() throws {
        let data = try JSONEncoder().encode(CoachState.empty())
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["schemaVersion", "currentSession", "questionSources", "questionCursor"] {
            XCTAssertTrue(raw.contains("\"\(key)\""), "缺字段：\(key)")
        }
    }

    func testDecodesUpstreamStateJSON() throws {
        let json = """
        {"schemaVersion":3,"learner":{"displayName":"Andy","createdAt":"2026-01-01T00:00:00.000Z"},
        "currentSession":null,"sessions":[],"targets":[],"issues":[],"vocabulary":[],"plan":null,
        "questions":[{"id":"p3-education-001","part":3,"topic":"Education",
        "prompt":"Should schools teach practical skills?","followups":["Which ones?"],
        "source":"Imported bank","sourceUrl":"","importLevel":"full-question","status":"new"}],
        "questionSources":[],"settings":{"recordingEnabled":false,"recordingConsentAt":""},
        "questionCursor":{"part1":0,"part2":0,"part3":0}}
        """
        let state = try JSONDecoder().decode(CoachState.self, from: Data(json.utf8))
        XCTAssertEqual(state.learner.displayName, "Andy")
        XCTAssertEqual(state.questions.count, 1)
        XCTAssertEqual(state.questions[0].part, 3)
        XCTAssertEqual(state.questions[0].followups, ["Which ones?"])
    }

    func testMigratesMissingOptionalFields() throws {
        // 上游 ensureWorkspace 会补齐缺失字段，解码必须容忍最小 JSON
        let minimal = #"{"schemaVersion":3,"learner":{"displayName":"","createdAt":"2026-01-01T00:00:00.000Z"}}"#
        let state = try JSONDecoder().decode(CoachState.self, from: Data(minimal.utf8))
        XCTAssertTrue(state.questions.isEmpty)
        XCTAssertTrue(state.issues.isEmpty)
        XCTAssertNil(state.plan)
    }
}
