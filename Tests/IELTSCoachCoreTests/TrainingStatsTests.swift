import XCTest
@testable import IELTSCoachCore

final class TrainingStatsTests: XCTestCase {

    /// 固定「现在」= 2026-08-05T12:00:00Z。用 ISO 日历 + 上海时区，
    /// 本周是 2026-08-03（周一）00:00 CST 到 2026-08-10 00:00 CST。
    private let now = CoachTime.parse("2026-08-05T12:00:00Z")!

    private var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func session(_ id: String, started: String, ended: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: started,
                        endedAt: ended, goal: "", transcript: [],
                        reportPath: "", recordingPath: "")
    }

    private func state(_ sessions: [PracticeSession],
                       issues: [IssueRecord] = [],
                       weeklyGoal: Int? = nil) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.issues = issues
        if let weeklyGoal { value.settings.weeklyGoal = weeklyGoal }
        return value
    }

    private func compute(_ value: CoachState) -> TrainingStats {
        TrainingStats.compute(state: value, now: now, calendar: calendar)
    }

    // MARK: - 本周次数与累计次数

    func testWeeklyDoneCountsOnlyThisWeekButTotalCountsEverything() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T10:20:00Z")
        ]))
        XCTAssertEqual(stats.weeklyDone, 2)
        XCTAssertEqual(stats.totalSessions, 3, "累计次数不该被「本周」筛掉")
    }

    func testWeeklyGoalComesFromSettingsAndDefaultsToFive() {
        XCTAssertEqual(compute(state([])).weeklyGoal, 5)
        XCTAssertEqual(compute(state([], weeklyGoal: 3)).weeklyGoal, 3)
    }

    // MARK: - 本周开口时长

    func testWeeklySpokenMinutesSumsThisWeeksDurations() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T11:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 42, "30 + 12，上周那场不算")
        XCTAssertEqual(stats.sessionsMissingDuration, 0)
    }

    func testMissingEndTimeIsReportedInsteadOfSilentlyCountingZero() {
        // 用户练了一场却显示 0 分钟，他会认为工具坏了。必须能解释。
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "")
        ]))
        XCTAssertEqual(stats.weeklyDone, 1, "没有结束时间不影响「练了几场」")
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.sessionsMissingDuration, 1)
    }

    func testEndTimeEarlierThanStartTimeIsReportedNotSubtracted() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T09:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 0, "负时长绝不能被加进去")
        XCTAssertEqual(stats.sessionsMissingDuration, 1)
    }

    func testOverlongSessionIsCappedAndReported() {
        // 忘了点「我练完了」，一场记成 4 小时。
        // 「本周开口时长 240 分钟」会让整个统计失去可信度。
        let stats = compute(state([
            session("a", started: "2026-08-05T06:00:00Z", ended: "2026-08-05T10:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, TrainingStats.maxCountedMinutesPerSession)
        XCTAssertEqual(stats.cappedSessionCount, 1)
    }

    func testUndatableSessionIsReportedAndExcludedFromTheWeek() {
        let stats = compute(state([
            session("sync-1754123456", started: "", ended: ""),
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z")
        ]))
        XCTAssertEqual(stats.weeklyDone, 1)
        XCTAssertEqual(stats.undatedSessionCount, 1)
        XCTAssertEqual(stats.totalSessions, 2, "读不出时间也还是练过的一场")
    }

    func testSessionWithoutStartedAtFallsBackToTheDateInItsID() {
        // Phase 4 之前的记录可能只有 id。不能因此整条丢掉。
        let stats = compute(state([session("2026-08-05-001", started: "", ended: "")]))
        XCTAssertEqual(stats.weeklyDone, 1)
        XCTAssertEqual(stats.undatedSessionCount, 0)
    }

    // MARK: - 出现变少的毛病

    func testImprovingCountsGoneAndDecreasingOnly() {
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        func issue(_ id: String, days: [Int]) -> IssueRecord {
            IssueRecord(id: id, learnerSaid: "s-\(id)", correction: "c", whyItMatters: "w",
                        occurrences: days.count,
                        sourceSessionIds: days.map { String(format: "2026-07-%02d-001", $0) },
                        lastSeenAt: "2026-07-10T10:00:00Z")
        }
        let stats = compute(state((1...10).map(julySession), issues: [
            issue("gone", days: [1, 2]),                 // .gone
            issue("down", days: [1, 2, 3, 4, 10]),       // .decreasing
            issue("up", days: [1, 8, 9, 10])             // .increasing
        ]))
        XCTAssertEqual(stats.improvingIssueCount, 2)
        XCTAssertEqual(stats.trackedIssueCount, 3)
    }

    func testEmptyStateProducesAllZerosWithoutCrashing() {
        let stats = compute(CoachState.empty())
        XCTAssertEqual(stats.weeklyDone, 0)
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.improvingIssueCount, 0)
        XCTAssertEqual(stats.trackedIssueCount, 0)
        XCTAssertEqual(stats.weeklyGoal, 5)
    }
}
