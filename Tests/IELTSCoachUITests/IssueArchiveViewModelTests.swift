import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class IssueArchiveViewModelTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var shanghai: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func sessionID(_ day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func session(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: "\(stamp)T10:00:00Z", endedAt: "\(stamp)T10:30:00Z",
                               goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, occurrences: Int, days: [Int],
                       lastSeen: String? = nil) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix-\(id)",
                    whyItMatters: "why-\(id)", occurrences: occurrences,
                    sourceSessionIds: days.map(sessionID),
                    lastSeenAt: lastSeen
                        ?? String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    private func state(_ issues: [IssueRecord], sessionCount: Int = 10) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessionCount > 0 ? (1...sessionCount).map(session) : []
        value.issues = issues
        return value
    }

    private func viewModel(_ value: CoachState) -> IssueArchiveViewModel {
        IssueArchiveViewModel(state: value, calendar: utc)
    }

    // MARK: - 排序

    func testRowsAreSortedByOccurrencesDescending() {
        // 「错题按出现次数排序」是这一页的第一条产品要求。
        let model = viewModel(state([
            issue("a", occurrences: 2, days: [1]),
            issue("b", occurrences: 9, days: [2]),
            issue("c", occurrences: 5, days: [3])
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["b", "c", "a"])
    }

    func testTiesAreBrokenByLastSeenThenByIDSoTheOrderIsStable() {
        // 不确定的排序会让同一份数据每次打开顺序都不一样，
        // 用户会以为记录被改了。
        let model = viewModel(state([
            issue("z", occurrences: 3, days: [1], lastSeen: "2026-07-05T10:00:00Z"),
            issue("a", occurrences: 3, days: [1], lastSeen: "2026-07-05T10:00:00Z"),
            issue("m", occurrences: 3, days: [1], lastSeen: "2026-07-09T10:00:00Z")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["m", "a", "z"])
    }

    // MARK: - 行内容

    func testRowCarriesTrendAndNewFlagFromTheAnalyzer() {
        let model = viewModel(state([
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        let down = model.rows.first { $0.id == "down" }
        let fresh = model.rows.first { $0.id == "fresh" }
        XCTAssertEqual(down?.trend, .decreasing)
        XCTAssertEqual(fresh?.trend, .fresh)
        XCTAssertEqual(fresh?.isNew, true)
        XCTAssertEqual(down?.isNew, false)
    }

    func testSessionCountDeduplicatesRepeatedSessionIDs() {
        var record = issue("a", occurrences: 4, days: [1])
        record.sourceSessionIds = [sessionID(1), sessionID(1), sessionID(2)]
        XCTAssertEqual(viewModel(state([record])).rows[0].sessionCount, 2)
    }

    func testLastSeenTextUsesTheGivenCalendar() {
        let value = state([
            issue("a", occurrences: 1, days: [5], lastSeen: "2026-07-05T23:30:00Z")
        ])
        XCTAssertEqual(viewModel(value).rows[0].lastSeenText, "最近一次：2026-07-05")
        // 同一个时间戳换一个时区就该是另一天。**两个方向都断言**，否则这条测试
        // 在恰好等于 UTC 的机器上会退化成「随便拿哪个日历都过」——
        // 而这一行正是为了防「晚上练的那一场显示成前一天」。
        XCTAssertEqual(
            IssueArchiveViewModel(state: value, calendar: shanghai).rows[0].lastSeenText,
            "最近一次：2026-07-06",
            "日期没按传进来的日历（含时区）算。北京时间晚上练的一场会显示成前一天，"
                + "用户会以为记录错了。")
    }

    func testUnparsableLastSeenSaysSoInsteadOfShowingAWrongDate() {
        let model = viewModel(state([
            issue("a", occurrences: 1, days: [5], lastSeen: "")
        ]))
        XCTAssertEqual(model.rows[0].lastSeenText, "最近一次：时间不详")
    }

    func testDuplicateIssueIDsDoNotCrash() {
        // state.json 被外部工具改坏、或上游写入过重复 id 时，
        // 用 Dictionary(uniqueKeysWithValues:) 建索引会 fatalError 闪退整个 App。
        let model = viewModel(state([
            issue("dup", occurrences: 3, days: [1]),
            issue("dup", occurrences: 1, days: [2])
        ]))
        XCTAssertEqual(model.rows.count, 2)
    }

    // MARK: - 筛选与计数

    func testFiltersReturnTheRightSubsets() {
        let model = viewModel(state([
            issue("once", occurrences: 1, days: [1]),
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        XCTAssertEqual(Set(model.rows(filter: .all).map(\.id)), ["once", "down", "fresh"])
        XCTAssertEqual(Set(model.rows(filter: .recurring).map(\.id)), ["down", "fresh"])
        XCTAssertEqual(model.rows(filter: .new).map(\.id), ["fresh"])
        XCTAssertEqual(Set(model.rows(filter: .improving).map(\.id)), ["once", "down"])
    }

    func testCountsMatchTheFilters() {
        let model = viewModel(state([
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        XCTAssertEqual(model.counts.total, 2)
        XCTAssertEqual(model.counts.new, 1)
        XCTAssertEqual(model.counts.improving, 1)
    }

    func testEveryFilterHasAChineseTitle() {
        for filter in IssueFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty, "\(filter) 缺少中文标题")
        }
    }

    // MARK: - 空与异常

    func testEmptyArchiveProducesNoRowsAndNoWarnings() {
        let model = viewModel(CoachState.empty())
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.dataWarnings.isEmpty)
        XCTAssertEqual(model.counts.total, 0)
    }

    func testDataWarningsAreSurfacedFromTheTimeline() {
        // 时间轴发现的问题必须一路传到界面上。埋在 Core 里没人看得见，
        // 等于没检查。
        var value = state([issue("a", occurrences: 1, days: [1])])
        value.issues[0].sourceSessionIds.append("sync-1754123456")
        let model = viewModel(value)
        XCTAssertFalse(model.dataWarnings.isEmpty)
        XCTAssertTrue(model.dataWarnings.joined().contains("下一步"))
    }
}
