import XCTest
@testable import IELTSCoachCore

final class SessionTimelineTests: XCTestCase {

    /// 第 day 天的一场练习。id 用 "YYYY-MM-DD-001" 这种文档形状。
    private func session(day: Int, startedAt: String? = nil) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: startedAt ?? "\(stamp)T10:00:00Z",
                               endedAt: "\(stamp)T10:30:00Z", goal: "",
                               transcript: [], reportPath: "", recordingPath: "")
    }

    private func sessionID(day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func issue(_ id: String, sessions: [String]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said", correction: "fix", whyItMatters: "why",
                    occurrences: sessions.count, sourceSessionIds: sessions,
                    lastSeenAt: "2026-07-10T10:00:00Z")
    }

    private func state(sessions: [PracticeSession], issues: [IssueRecord] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.issues = issues
        return value
    }

    func testOrdersMostRecentFirst() {
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 3), session(day: 1), session(day: 2)]))
        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 3), sessionID(day: 2), sessionID(day: 1)])
    }

    func testFallsBackToDatePrefixOfTheIDWhenStartedAtIsEmpty() {
        // Phase 4 之前的数据、或写入时漏了 startedAt 的记录，
        // 不能因此被整条排除在趋势之外。
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 2, startedAt: ""), session(day: 1)]))
        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2), sessionID(day: 1)])
        XCTAssertTrue(timeline.undatedSessionIDs.isEmpty)
    }

    func testIncludesIssueOnlySessionsAndReportsThemAsUnmatched() {
        // 错题档案引用了一场 state.sessions 里没有的练习：
        // 它确实练过，必须并入时间轴，否则「之前那批」会凭空少一场；
        // 但也必须报出来，否则用户在训练记录页看不到它却影响了趋势。
        let orphan = "2026-07-05T09:00:00Z"
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 9), session(day: 1)],
            issues: [issue("i1", sessions: [orphan])]))

        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 9), orphan, sessionID(day: 1)])
        XCTAssertEqual(timeline.unmatchedSessionIDs, [orphan])
    }

    func testReportsUndatableIDsAndKeepsThemOutOfTheOrder() {
        // pending-reviews 的 requestID 混进来过一次就会毁掉窗口划分。
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456"])]))

        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2)])
        XCTAssertEqual(timeline.undatedSessionIDs, ["sync-1754123456"])
    }

    func testWarningsExplainWhatHappenedAndWhatToDoNext() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456", "2026-07-05T09:00:00Z"])]))

        XCTAssertEqual(timeline.warnings.count, 2)
        for warning in timeline.warnings {
            XCTAssertTrue(warning.contains("下一步"), "警告必须说明下一步做什么：\(warning)")
        }
    }

    func testNoWarningsWhenEverythingLinesUp() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2), session(day: 1)],
            issues: [issue("i1", sessions: [sessionID(day: 1)])]))
        XCTAssertTrue(timeline.warnings.isEmpty, "数据正常时不该吓唬用户")
    }

    func testRecentAndEarlierWindowsSplitTheTimeline() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...10).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5),
                       (6...10).reversed().map { sessionID(day: $0) })
        XCTAssertEqual(timeline.earlierWindow(size: 5),
                       (1...5).reversed().map { sessionID(day: $0) })
    }

    func testWindowsShrinkGracefullyWhenThereAreNotEnoughSessions() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...7).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5).count, 5)
        XCTAssertEqual(timeline.earlierWindow(size: 5).count, 2, "只剩 2 场就只给 2 场，不能越界")
        XCTAssertEqual(SessionTimeline.build(state: state(sessions: []))
                        .earlierWindow(size: 5), [])
    }

    func testWindowRejectsNonsenseArguments() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...3).map { session(day: $0) }))
        XCTAssertEqual(timeline.window(size: 0, offset: 0), [])
        XCTAssertEqual(timeline.window(size: 5, offset: 99), [])
        XCTAssertEqual(timeline.window(size: -1, offset: 0), [])
    }
}
