import XCTest
@testable import IELTSCoachCore

final class PracticeSessionOrderTests: XCTestCase {

    private func session(_ id: String, startedAt: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: startedAt,
                        endedAt: "", goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    func testPrefersStartedAtOverTheDateInTheID() {
        // id 只精确到天，startedAt 精确到秒。两者都有时必须以 startedAt 为准，
        // 否则同一天的几场会被当成同一时刻，顺序全靠 tie-break 顶着。
        let ordered = PracticeSessionOrder.newestFirst([
            session("2026-08-01-001", startedAt: "2026-08-06T10:00:00Z"),
            session("2026-08-06-002", startedAt: "2026-08-01T10:00:00Z")
        ]).ordered
        XCTAssertEqual(ordered.map(\.id), ["2026-08-01-001", "2026-08-06-002"])
    }

    func testFallsBackToTheDateInTheIDWhenStartedAtIsUnusable() {
        // startedAt 空着、时间只剩在 id 里的记录是真实存在的数据。
        // 没有这条兜底，用户今天练的那场会被排到列表最后。
        for broken in ["", "   ", "昨天下午"] {
            let ordered = PracticeSessionOrder.newestFirst([
                session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z"),
                session("2026-08-06-001", startedAt: broken)
            ]).ordered
            XCTAssertEqual(ordered.map(\.id), ["2026-08-06-001", "2026-08-01-001"],
                           "startedAt 是「\(broken)」时应退回按 id 里的日期排")
        }
    }

    func testSessionsWithNoReadableTimeAreKeptAtTheEndAndNamed() {
        // 两处都读不出时间的场次仍然是一次真练习，不许悄悄丢掉；
        // 但它排不进时间轴，所以放最后并单独列出来，让调用方有东西可说。
        let result = PracticeSessionOrder.newestFirst([
            session("no-date-002", startedAt: ""),
            session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z"),
            session("no-date-001", startedAt: "")
        ])
        XCTAssertEqual(result.ordered.map(\.id), ["2026-08-01-001", "no-date-002", "no-date-001"])
        XCTAssertEqual(result.undatedIDs, ["no-date-002", "no-date-001"])
    }

    func testSameInstantFallsBackToIDDescendingSoTheOrderIsStable() {
        // Swift 的 sorted 不保证稳定。同一天多场、startedAt 全空时，
        // 兜底会让它们拿到完全相同的 Date，不定死 tie-break 的话，
        // 同一份数据每次打开可能给出不同的顺序。
        let ids = ["2026-08-06-001", "2026-08-06-002", "2026-08-06-003"]
        for attempt in 0..<20 {
            let ordered = PracticeSessionOrder.newestFirst(ids.shuffled().map {
                session($0, startedAt: "")
            }).ordered
            XCTAssertEqual(ordered.map(\.id),
                           ["2026-08-06-003", "2026-08-06-002", "2026-08-06-001"],
                           "第 \(attempt) 次打乱后顺序变了")
        }
    }

    func testStartDateAgreesWithTheRuleTrainingStatsAndSessionTimelineUse() {
        // 这条规则只许有一份：MCP 的历史列表、首页四格、趋势窗口都从这里取时间。
        XCTAssertNotNil(PracticeSessionOrder.startDate(
            of: session("no-date-001", startedAt: "2026-08-06T10:00:00Z")))
        XCTAssertNotNil(PracticeSessionOrder.startDate(
            of: session("2026-08-06-001", startedAt: "")))
        XCTAssertNil(PracticeSessionOrder.startDate(of: session("no-date-001", startedAt: "")))
    }
}
