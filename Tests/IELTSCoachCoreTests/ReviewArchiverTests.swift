import XCTest
@testable import IELTSCoachCore

final class ReviewArchiverTests: XCTestCase {
    private let report = try! JSONValue.decode(from: """
    {"summary":"ok",
     "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                      "why_it_matters":"very 不能修饰动词"}],
     "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding experience",
                    "priority":"high"}],
     "answer_upgrades":[],
     "priority_target":{"id":"logic-explain-example","label":"补一个原因和例子",
                        "status":"new","evidence":["I just like it."]}}
    """)

    private func baseState() -> CoachState {
        var state = CoachState.empty()
        state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "P")]
        state.plan = try! PlanBuilder.build(questions: state.questions, lengthDays: 7,
                                            createdAt: "2026-08-04T00:00:00Z")
        return state
    }

    func testAddsNewIssue() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "2026-08-04-001", questionID: "q1",
                                           at: "2026-08-04T10:00:00Z")
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].learnerSaid, "I very like it.")
        XCTAssertEqual(state.issues[0].occurrences, 1)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["2026-08-04-001"])
    }

    func testIncrementsOccurrenceForRepeatedIssue() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1")
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2")
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].occurrences, 2)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1", "s2"])
        XCTAssertEqual(state.issues[0].lastSeenAt, "t2")
    }

    func testDoesNotDuplicateSessionIDWhenArchivedTwice() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1")
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2")
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1"])
    }

    func testAddsVocabulary() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.vocabulary[0].basicWord, "good")
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding")
        XCTAssertEqual(state.vocabulary[0].priority, "high")
    }

    func testAppendsRetrainingTarget() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.targets[0].id, "logic-explain-example")
        XCTAssertEqual(state.targets[0].sourceSessionId, "s1")
    }

    func testAdvancesPlanProgress() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(state.plan?.days[0].completedQuestionIds, ["q1"])
    }

    func testMarksQuestionPracticed() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(state.questions[0].status, "practiced")
    }

    func testHandlesReportWithNoIssuesOrVocabulary() {
        let sparse = try! JSONValue.decode(from: #"{"must_correct":[],"priority_target":{"id":"t1"}}"#)
        let state = ReviewArchiver.archive(report: sparse, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(state.issues.isEmpty)
        XCTAssertTrue(state.vocabulary.isEmpty)
        XCTAssertEqual(state.targets.count, 1)
    }
}
