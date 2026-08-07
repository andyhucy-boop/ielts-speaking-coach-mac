import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class HomeStatsTests: XCTestCase {

    /// 固定「现在」= 2026-08-05T12:00:00Z（周三），上海时区下本周是 08-03 ~ 08-09。
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

    private func julySession(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return session("\(stamp)-001", started: "\(stamp)T10:00:00Z", ended: "\(stamp)T10:30:00Z")
    }

    private func issue(_ id: String, occurrences: Int, days: [Int]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix", whyItMatters: "why",
                    occurrences: occurrences,
                    sourceSessionIds: days.map { String(format: "2026-07-%02d-001", $0) },
                    lastSeenAt: String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    private func model(_ value: CoachState) -> TodayViewModel {
        TodayViewModel(state: value, today: now, calendar: calendar)
    }

    private func thisWeekState(weeklyGoal: Int? = nil) -> CoachState {
        var value = CoachState.empty()
        value.sessions = [
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T10:20:00Z")
        ]
        if let weeklyGoal { value.settings.weeklyGoal = weeklyGoal }
        return value
    }

    // MARK: - 每周目标可配置

    func testWeekProgressGoalComesFromSettingsNotAHardcodedFive() {
        // ROADMAP 第 5 节：每周训练目标由用户配置，默认 5。
        XCTAssertEqual(model(thisWeekState()).weekProgress.goal, 5)
        XCTAssertEqual(model(thisWeekState(weeklyGoal: 3)).weekProgress.goal, 3)
        XCTAssertEqual(model(thisWeekState()).weekProgress.done, 2)
    }

    // MARK: - 四格

    func testFourTilesInAFixedOrderWithStableIDs() {
        let tiles = model(thisWeekState()).statTiles
        XCTAssertEqual(tiles.map(\.id), ["week", "total", "minutes", "improving"])
    }

    func testTileValuesRenderTheRealNumbers() {
        let tiles = model(thisWeekState(weeklyGoal: 4)).statTiles
        func tile(_ id: String) -> StatTile? { tiles.first { $0.id == id } }
        XCTAssertEqual(tile("week")?.value, "2/4")
        XCTAssertEqual(tile("week")?.unit, "次")
        XCTAssertEqual(tile("total")?.value, "3")
        XCTAssertEqual(tile("minutes")?.value, "42")
        XCTAssertEqual(tile("minutes")?.unit, "分钟")
    }

    func testEveryTileHasNonEmptyCaptionAndFootnote() {
        // 空脚注等于一块没人看得懂的数字。空白会让用户以为程序坏了。
        for value in [thisWeekState(), CoachState.empty()] {
            for tile in model(value).statTiles {
                XCTAssertFalse(tile.caption.isEmpty, "\(tile.id) 缺 caption")
                XCTAssertFalse(tile.value.isEmpty, "\(tile.id) 缺 value")
                XCTAssertFalse(tile.footnote.isEmpty, "\(tile.id) 缺脚注")
            }
        }
    }

    func testWeekFootnoteTellsYouHowManyMoreOrThatYouAreDone() {
        let notDone = model(thisWeekState(weeklyGoal: 5)).statTiles.first { $0.id == "week" }
        XCTAssertTrue(notDone?.footnote.contains("还差 3 次") == true, notDone?.footnote ?? "")
        XCTAssertTrue(notDone?.footnote.contains("下一步") == true)

        let done = model(thisWeekState(weeklyGoal: 1)).statTiles.first { $0.id == "week" }
        XCTAssertTrue(done?.footnote.contains("已经完成") == true, done?.footnote ?? "")
    }

    func testMinutesFootnoteExplainsMissingEndTimes() {
        var value = CoachState.empty()
        value.sessions = [session("a", started: "2026-08-05T10:00:00Z", ended: "")]
        let tile = model(value).statTiles.first { $0.id == "minutes" }
        XCTAssertTrue(tile?.footnote.contains("没有结束时间") == true, tile?.footnote ?? "")
        XCTAssertTrue(tile?.footnote.contains("下一步") == true)
    }

    func testMinutesFootnoteExplainsCappedSessions() {
        var value = CoachState.empty()
        value.sessions = [session("a", started: "2026-08-05T06:00:00Z",
                                  ended: "2026-08-05T10:00:00Z")]
        let tile = model(value).statTiles.first { $0.id == "minutes" }
        XCTAssertTrue(tile?.footnote.contains("小时") == true, tile?.footnote ?? "")
        XCTAssertTrue(tile?.footnote.contains("下一步") == true)
    }

    func testImprovingFootnoteSaysHowManyMoreSessionsAreNeeded() {
        // 练习太少时说「0 个毛病在变少」会被误读成「一点没进步」。
        // 必须说清是「还看不出来」，并给出还差几场。
        var value = CoachState.empty()
        value.sessions = (1...3).map(julySession)
        value.issues = [issue("a", occurrences: 1, days: [1])]
        let tile = model(value).statTiles.first { $0.id == "improving" }
        let needed = IssueTrendAnalyzer.minimumSessionsForTrend - 3
        XCTAssertTrue(tile?.footnote.contains("再练 \(needed) 次") == true, tile?.footnote ?? "")
    }

    func testImprovingTileCountsGoneAndDecreasing() {
        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = [issue("gone", occurrences: 2, days: [1, 2]),
                        issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
                        issue("up", occurrences: 4, days: [1, 8, 9, 10])]
        let tile = model(value).statTiles.first { $0.id == "improving" }
        XCTAssertEqual(tile?.value, "2")
        XCTAssertEqual(tile?.unit, "个")
    }

    // MARK: - 「你的问题正在怎么变化」

    func testIssueChangesAreSortedByOccurrencesAndCappedAtFive() {
        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = (1...7).map { issue("i\($0)", occurrences: $0, days: [$0 % 10 + 1]) }
        let changes = model(value).issueChanges
        XCTAssertEqual(changes.count, 5, "首页只放最要紧的五条，剩下的去问题档案页看")
        XCTAssertEqual(changes.map(\.id), ["i7", "i6", "i5", "i4", "i3"])
    }

    func testIssueChangesAreEmptyWhenTheArchiveIsEmpty() {
        XCTAssertTrue(model(CoachState.empty()).issueChanges.isEmpty)
    }

    // MARK: - 绝不预测分数

    func testNoScorePredictionInAnyUserFacingText() {
        // DEFINITION-OF-DONE 第 4 节第一条：不预测雅思分数。
        // 给「你大概 6.5 分」这种数字既不准也有害——
        // 会让人盯着数字而不是盯着问题。
        //
        // 不要为了让这条测试变绿去改下面的词表。它存在的意义就是拦住那件事。
        let banned = ["分数", "评分", "打分", "得分", "预测", "band", "Band", "BAND",
                      "几分", "水平分", "6.5", "7.0", "score", "Score"]

        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = [issue("gone", occurrences: 2, days: [1, 2]),
                        issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
                        issue("up", occurrences: 4, days: [1, 8, 9, 10]),
                        issue("fresh", occurrences: 2, days: [9, 10])]

        var texts: [String] = []
        for tile in model(value).statTiles {
            texts += [tile.caption, tile.value, tile.unit, tile.footnote]
        }
        for row in model(value).issueChanges {
            texts += [row.detail, row.trend.badge, row.trend.explanation, row.lastSeenText]
        }
        for trend in IssueTrend.allCases {
            texts += [trend.badge, trend.explanation]
        }
        // 空数据下的文案也要扫——空状态最容易被顺手写上一句「预计能到几分」
        for tile in model(CoachState.empty()).statTiles {
            texts += [tile.caption, tile.footnote]
        }

        for text in texts {
            for word in banned {
                XCTAssertFalse(text.contains(word),
                               "「\(text)」里出现了被禁止的分数用语「\(word)」"
                               + "（DEFINITION-OF-DONE 第 4 节）")
            }
        }
    }
}
