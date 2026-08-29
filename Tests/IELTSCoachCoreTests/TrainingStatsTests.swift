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

    /// 新冒出来的毛病绝不能被算进「出现变少的」。
    ///
    /// 上一条测试里三个毛病的趋势分别是 .gone / .decreasing / .increasing，
    /// **没有一个是 .fresh 或 .notEnoughData**——所以把这两种也加进过滤条件，
    /// 1033 条测试照样全绿（实测过）。首页那格会因此虚报：
    /// 第一次犯的错、以及样本还不够判断的错，都会被说成「在变少」，
    /// 而这个数字正是用户判断「有没有进步」的唯一依据，虚报比不显示更糟。
    func testImprovingIgnoresBrandNewIssues() {
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        // 只在最近 5 场（第 6–10 天）里出现过，之前从没犯过 → .fresh
        let fresh = IssueRecord(id: "fresh", learnerSaid: "s", correction: "c", whyItMatters: "w",
                                occurrences: 2,
                                sourceSessionIds: ["2026-07-09-001", "2026-07-10-001"],
                                lastSeenAt: "2026-07-10T10:00:00Z")
        let stats = compute(state((1...10).map(julySession), issues: [fresh]))
        XCTAssertEqual(stats.improvingIssueCount, 0, "第一次犯的毛病不是「在变少」")
        XCTAssertEqual(stats.trackedIssueCount, 1)
    }

    func testImprovingIgnoresIssuesWithTooFewSessionsToJudge() {
        // 只有 6 场：「之前那批」只剩 1 场，IssueTrendAnalyzer 给的是 .notEnoughData。
        // 判不出来就不能算进「在变少」那一格。
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        let issue = IssueRecord(id: "unknown", learnerSaid: "s", correction: "c",
                                whyItMatters: "w", occurrences: 1,
                                sourceSessionIds: ["2026-07-01-001"],
                                lastSeenAt: "2026-07-01T10:00:00Z")
        let stats = compute(state((1...6).map(julySession), issues: [issue]))
        XCTAssertEqual(stats.improvingIssueCount, 0, "样本不够就不能说人家在进步")
        XCTAssertEqual(stats.trackedIssueCount, 1)
    }

    func testSessionExactlyAtTheCapIsCountedInFullAndNotFlagged() {
        // 边界：恰好 2 小时是正常的长练习，不是「忘了点我练完了」。
        // 把 `raw > 上限` 写成 `>=`，全套测试照样全绿（实测过）——
        // 那样每一场恰好 2 小时的练习都会被无端标成「记录可能不准」。
        XCTAssertEqual(TrainingStats.maxCountedMinutesPerSession, 120, "单场计入上限是 2 小时")
        let stats = compute(state([
            session("a", started: "2026-08-05T08:00:00Z", ended: "2026-08-05T10:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 120)
        XCTAssertEqual(stats.cappedSessionCount, 0)
        XCTAssertEqual(stats.sessionsMissingDuration, 0)
    }

    func testDiagnosticsOnlyCoverThisWeek() {
        // 两个诊断字段是给「本周开口时长」这一格做解释用的。
        // 把上上周那场缺结束时间的练习也算进来，界面会说「本周有 1 场算不出时长」，
        // 用户回头去本周的记录里找，一场都找不到——比不提示更让人困惑。
        let stats = compute(state([
            session("old-missing", started: "2026-07-20T10:00:00Z", ended: ""),
            session("old-overlong", started: "2026-07-21T06:00:00Z", ended: "2026-07-21T10:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklyDone, 0)
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.sessionsMissingDuration, 0, "上周的场次不该出现在本周的诊断里")
        XCTAssertEqual(stats.cappedSessionCount, 0, "上周的场次不该出现在本周的诊断里")
        XCTAssertEqual(stats.totalSessions, 2)
    }

    func testDurationIsRoundedToTheNearestMinuteNotTruncated() {
        // 90 秒记成 1 分钟的话，每一场都会少算最多一分钟，
        // 「本周开口时长」会常年比实际偏小，而用户无从察觉。
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:01:30Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 2)
    }

    // MARK: - 趋势那一格的场次口径

    /// `trendSessionCount` 数的必须是**趋势真正用的那条时间轴**上的场次，
    /// 不是 `state.sessions.count`。
    ///
    /// 两者不相等是日常：在训练记录页删掉几条旧记录、或早期用命令行练过几场，
    /// 档案里都会留下 `state.sessions` 里没有的场次 id。首页第四格的大号数字走的是
    /// `IssueTrendAnalyzer`（也就是这条时间轴），脚注要是改用 `totalSessions` 判
    /// 「够不够看出趋势」，同一张卡片就会自己跟自己打架。
    func testTrendSessionCountFollowsTheTimelineNotTheRecordedSessions() {
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        // 训练记录里只有 7 场；第 8 场（07-08）只在错题档案里被引用到。
        let issue = IssueRecord(id: "gone", learnerSaid: "s", correction: "c", whyItMatters: "w",
                                occurrences: 3,
                                sourceSessionIds: ["2026-07-01-001", "2026-07-02-001",
                                                   "2026-07-08-001"],
                                lastSeenAt: "2026-07-08T10:00:00Z")
        let stats = compute(state((1...7).map(julySession), issues: [issue]))
        XCTAssertEqual(stats.totalSessions, 7)
        XCTAssertEqual(stats.trendSessionCount, 8,
                       "只在档案里留了记录的那一场也参与窗口划分，必须算进这个口径")
        XCTAssertEqual(stats.archiveOnlySessionCount, 1,
                       "训练记录页看不到的那一场必须能被界面点出来")
        XCTAssertEqual(stats.improvingIssueCount, 1,
                       "8 场就够划出窗口了，这个毛病最近没再出现 → 已经在「变少」里")
    }

    func testArchiveOnlySessionCountIsZeroWhenEveryReferencedSessionIsRecorded() {
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        let issue = IssueRecord(id: "i", learnerSaid: "s", correction: "c", whyItMatters: "w",
                                occurrences: 1, sourceSessionIds: ["2026-07-01-001"],
                                lastSeenAt: "2026-07-01T10:00:00Z")
        let stats = compute(state((1...8).map(julySession), issues: [issue]))
        XCTAssertEqual(stats.trendSessionCount, 8)
        XCTAssertEqual(stats.archiveOnlySessionCount, 0)
    }

    func testEmptyStateProducesAllZerosWithoutCrashing() {
        let stats = compute(CoachState.empty())
        XCTAssertEqual(stats.weeklyDone, 0)
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.improvingIssueCount, 0)
        XCTAssertEqual(stats.trackedIssueCount, 0)
        XCTAssertEqual(stats.trendSessionCount, 0)
        XCTAssertEqual(stats.archiveOnlySessionCount, 0)
        XCTAssertEqual(stats.weeklyGoal, 5)
    }
}

/// 「一场练了多久」这件事全工程只有一份算法（2026-08-20）。
///
/// 首页那句「有 N 场超过 2 小时，已按 2 小时计入（多半是忘了点结束）。
/// 下一步：到训练记录页核对这几场」在这之前是一张空头支票——
/// 那一页每行只有日期，既没时刻也没时长，**没有任何字段能用来认出是哪几场**。
final class SessionDurationTests: XCTestCase {

    private func session(from start: String, to end: String) -> PracticeSession {
        PracticeSession(id: "s1", questionId: "q1", focusPart: .part1,
                        startedAt: start, endedAt: end, goal: "",
                        transcript: [], reportPath: "", recordingPath: "")
    }

    func testAnOrdinarySessionReadsInMinutes() {
        let value = session(from: "2026-08-20T10:00:00Z", to: "2026-08-20T10:12:00Z")
        XCTAssertEqual(TrainingStats.minutes(of: value), 12)
        XCTAssertEqual(TrainingStats.durationText(of: value), "12 分钟")
    }

    /// **逐行显示不截断。** 截断（超过 2 小时按 2 小时计）是汇总那一侧的事；
    /// 这一行要如实说「3 小时 12 分钟」，那正是他要据以认出「哪几场忘了点结束」的东西。
    func testALongSessionIsShownInFullSoItCanBeRecognised() {
        let value = session(from: "2026-08-20T10:00:00Z", to: "2026-08-20T13:12:00Z")
        XCTAssertEqual(TrainingStats.minutes(of: value), 192)
        XCTAssertEqual(TrainingStats.durationText(of: value), "3 小时 12 分钟")
        XCTAssertGreaterThan(192, TrainingStats.maxCountedMinutesPerSession,
                             "这条测试要的就是一场超过截断线的练习")
    }

    /// 读不出来时说「时长未知」，**不是「0 分钟」**——
    /// 练了 40 分钟却看到 0 分钟，他会以为工具坏了。
    func testAnUnfinishedSessionSaysUnknownInsteadOfZero() {
        XCTAssertNil(TrainingStats.minutes(of: session(from: "2026-08-20T10:00:00Z", to: "")))
        XCTAssertEqual(TrainingStats.durationText(of: session(from: "2026-08-20T10:00:00Z", to: "")),
                       "时长未知")
        // 结束早于开始（手改过的 state.json）同样算读不出来。
        XCTAssertNil(TrainingStats.minutes(
            of: session(from: "2026-08-20T10:00:00Z", to: "2026-08-20T09:00:00Z")))
    }

    /// **汇总和逐行必须是同一套算法。** 各算各的话，「本周开口时长 38 分钟」
    /// 和逐行加起来的数会对不上，而用户没办法知道哪个是真的。
    func testTheWeeklyTotalAgreesWithTheSumOfTheRows() {
        var state = CoachState.empty()
        state.sessions = [session(from: "2026-08-19T10:00:00Z", to: "2026-08-19T10:12:00Z"),
                          session(from: "2026-08-20T10:00:00Z", to: "2026-08-20T10:08:00Z")]
        for index in state.sessions.indices { state.sessions[index].id = "s\(index)" }

        let now = ISO8601DateFormatter().date(from: "2026-08-21T10:00:00Z")!
        let stats = TrainingStats.compute(state: state, now: now,
                                          calendar: Calendar(identifier: .iso8601))
        let rowsTotal = state.sessions.compactMap(TrainingStats.minutes(of:)).reduce(0, +)
        XCTAssertEqual(stats.weeklySpokenMinutes, rowsTotal)
        XCTAssertEqual(rowsTotal, 20)
    }
}
