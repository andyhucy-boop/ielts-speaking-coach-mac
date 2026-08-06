import XCTest
@testable import IELTSCoachCore

final class IssueTrendAnalyzerTests: XCTestCase {

    private func sessionID(_ day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func session(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: "\(stamp)T10:00:00Z", endedAt: "\(stamp)T10:30:00Z",
                               goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, days: [Int]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix-\(id)",
                    whyItMatters: "why-\(id)", occurrences: days.count,
                    sourceSessionIds: days.map(sessionID),
                    lastSeenAt: String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    /// `sessionCount` 场练习（第 1 天到第 sessionCount 天，每天一场）。
    private func state(sessionCount: Int, issues: [IssueRecord]) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessionCount > 0 ? (1...sessionCount).map(session) : []
        value.issues = issues
        return value
    }

    private func result(_ state: CoachState, _ issueID: String) throws -> IssueTrendResult {
        try XCTUnwrap(IssueTrendAnalyzer.analyze(state: state).first { $0.issueID == issueID })
    }

    // MARK: - 四种确定的趋势

    func testDecreasingWhenRecentHitsAreFewer() throws {
        // 10 场：最近 5 场是第 6–10 天，之前 5 场是第 1–5 天。
        // 之前犯了 4 场，最近只犯 1 场。
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3, 4, 10])]), "i")
        XCTAssertEqual(outcome.trend, .decreasing)
        XCTAssertEqual(outcome.recentHits, 1)
        XCTAssertEqual(outcome.earlierHits, 4)
    }

    func testGoneWhenAbsentFromTheRecentWindow() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3])]), "i")
        XCTAssertEqual(outcome.trend, .gone)
        XCTAssertFalse(outcome.isNew)
    }

    func testIncreasingWhenRecentHitsAreMore() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 8, 9, 10])]), "i")
        XCTAssertEqual(outcome.trend, .increasing)
    }

    func testSteadyWhenTheRateIsUnchanged() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [2, 3, 7, 8])]), "i")
        XCTAssertEqual(outcome.trend, .steady)
    }

    // MARK: - 窗口大小不等时必须比频率，不能比次数

    func testUnequalWindowsAreComparedByRateNotByRawCount() throws {
        // 9 场：最近 5 场（第 5–9 天），之前只有 4 场（第 1–4 天）。
        // 两个窗口各犯 2 场：2/5 = 40% < 2/4 = 50%，是在变少。
        // 若实现成直接比次数（2 vs 2），会误判成「还是老样子」。
        let outcome = try result(state(sessionCount: 9,
                                       issues: [issue("i", days: [3, 4, 8, 9])]), "i")
        XCTAssertEqual(outcome.recentHits, 2)
        XCTAssertEqual(outcome.earlierHits, 2)
        XCTAssertEqual(outcome.recentWindowSize, 5)
        XCTAssertEqual(outcome.earlierWindowSize, 4)
        XCTAssertEqual(outcome.trend, .decreasing, "窗口不等大时必须比频率")
    }

    // MARK: - 样本不够就不给结论

    func testNotEnoughDataWhenTheEarlierWindowIsTooSmall() throws {
        // 6 场：最近 5 场吃掉第 2–6 天，之前只剩第 1 天这一场。
        // 拿 1 场当「之前」再说「变少了」，那是拿噪声当结论。
        let outcome = try result(state(sessionCount: 6,
                                       issues: [issue("i", days: [1, 6])]), "i")
        XCTAssertEqual(outcome.trend, .notEnoughData)
    }

    func testNoSessionsAtAllStillProducesAResultInsteadOfCrashing() throws {
        let outcome = try result(state(sessionCount: 0,
                                       issues: [issue("i", days: [])]), "i")
        XCTAssertEqual(outcome.trend, .notEnoughData)
        XCTAssertEqual(outcome.recentHits, 0)
    }

    // MARK: - 新问题

    func testFirstTimeIssueIsMarkedNewInsteadOfIncreasing() throws {
        // 之前根本不存在的毛病，按频率算必然是 0 → N，
        // 显示成「比之前更常出现了」是错的。
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [9, 10])]), "i")
        XCTAssertTrue(outcome.isNew)
        XCTAssertEqual(outcome.trend, .fresh)
    }

    func testIssueWithHistoryOlderThanBothWindowsIsNotNew() throws {
        // 12 场：窗口覆盖第 3–12 天，第 1 天在两个窗口之外。
        // 这个毛病老早就犯过，不能标成「新问题」。
        let outcome = try result(state(sessionCount: 12,
                                       issues: [issue("i", days: [1, 12])]), "i")
        XCTAssertFalse(outcome.isNew)
        XCTAssertNotEqual(outcome.trend, .fresh)
    }

    // MARK: - hits 必须从窗口交集算，不能拿 occurrences 顶替

    func testHitsCountSessionsInTheWindowNotTheLifetimeTotal() throws {
        // `occurrences` 的语义是「一共在几场练习里犯过」（Phase 4 收窄，
        // 恒等于 sourceSessionIds.count），它**不分窗口**——回答不了
        // 「最近 5 场里犯了几场」。所以 hits 只能用窗口交集算。
        //
        // 下面这条记录 occurrences = 7 而只有 1 个 sourceSessionId，是刻意造出来的
        // 不一致状态（真盘上读不到：IssueRecord 的解码器会在读盘时把它修回 1）。
        // 它在这里的唯一作用是当探针：只要实现拿 occurrences 当 hits，这条立刻变红。
        var record = issue("i", days: [10])
        record.occurrences = 7
        let outcome = try result(state(sessionCount: 10, issues: [record]), "i")
        XCTAssertEqual(outcome.recentHits, 1, "hits 必须来自窗口交集，不是 occurrences")
        XCTAssertEqual(outcome.occurrences, 7, "occurrences 原样带出来给列表排序用")
    }

    // MARK: - 文案

    func testEveryTrendHasBadgeAndActionableExplanation() {
        for trend in IssueTrend.allCases {
            XCTAssertFalse(trend.badge.isEmpty, "\(trend) 缺少列表标签")
            XCTAssertTrue(trend.explanation.contains("下一步"),
                          "\(trend) 的说明必须告诉用户下一步做什么：\(trend.explanation)")
        }
    }

    func testDetailQuotesTheActualNumbers() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3, 4, 10])]), "i")
        XCTAssertTrue(outcome.detail.contains("1"))
        XCTAssertTrue(outcome.detail.contains("4"))
    }

    func testAnalyzeCoversEveryIssueExactlyOnce() {
        let value = state(sessionCount: 10, issues: [issue("a", days: [1]),
                                                     issue("b", days: [10])])
        let results = IssueTrendAnalyzer.analyze(state: value)
        XCTAssertEqual(results.map(\.issueID), ["a", "b"], "顺序与 state.issues 一致，不得重排")
    }
}
