import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class VocabularyViewModelTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let exportedAt = CoachTime.parse("2026-08-06T01:00:00Z")!

    private func record(_ id: String, basic: String, priority: String,
                        sessions: [String] = ["s1"]) -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: basic, betterExpression: "better-\(basic)",
                         collocation: "colloc-\(basic)", priority: priority,
                         sourceSessionIds: sessions)
    }

    private func state(_ records: [VocabularyRecord]) -> CoachState {
        var value = CoachState.empty()
        value.vocabulary = records
        return value
    }

    // MARK: - 排序

    func testRowsAreSortedByPriorityFirst() {
        // 「按优先级」是这一页的产品要求。
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "low"),
            record("v2", basic: "bbb", priority: "normal"),
            record("v3", basic: "ccc", priority: "high")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["v3", "v2", "v1"])
    }

    func testWithinTheSamePriorityMoreSessionsComeFirst() {
        // 反复被推荐的词更该先记。
        let model = VocabularyViewModel(state: state([
            record("once", basic: "aaa", priority: "high", sessions: ["s1"]),
            record("thrice", basic: "zzz", priority: "high", sessions: ["s1", "s2", "s3"])
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["thrice", "once"])
    }

    func testTiesAreBrokenDeterministically() {
        let model = VocabularyViewModel(state: state([
            record("v2", basic: "zebra", priority: "high"),
            record("v1", basic: "apple", priority: "high")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["v1", "v2"], "同优先级同场次时按词升序，顺序必须固定")
    }

    func testUnknownPriorityLandsInNormalWithoutCrashing() {
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "紧急")
        ]))
        XCTAssertEqual(model.rows[0].priority, .normal)
    }

    func testSessionCountDeduplicates() {
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "high", sessions: ["s1", "s1", "s2"])
        ]))
        XCTAssertEqual(model.rows[0].sessionCount, 2)
    }

    // MARK: - 筛选与计数

    func testFiltersReturnTheRightSubsets() {
        let model = VocabularyViewModel(state: state([
            record("h", basic: "aaa", priority: "high"),
            record("n", basic: "bbb", priority: "normal"),
            record("l", basic: "ccc", priority: "low")
        ]))
        XCTAssertEqual(model.rows(filter: .all).map(\.id), ["h", "n", "l"])
        XCTAssertEqual(model.rows(filter: .high).map(\.id), ["h"])
        XCTAssertEqual(model.rows(filter: .normal).map(\.id), ["n"])
        XCTAssertEqual(model.rows(filter: .low).map(\.id), ["l"])
    }

    func testCounts() {
        let model = VocabularyViewModel(state: state([
            record("h1", basic: "aaa", priority: "high"),
            record("h2", basic: "bbb", priority: "high"),
            record("n1", basic: "ccc", priority: "normal")
        ]))
        XCTAssertEqual(model.counts.total, 3)
        XCTAssertEqual(model.counts.high, 2)
    }

    func testEveryFilterHasAChineseTitle() {
        for filter in VocabularyFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty, "\(filter) 缺少中文标题")
        }
    }

    // MARK: - 导出

    func testExportOnlyIncludesTheCurrentFilter() {
        // 用户筛到「优先记」再点导出，却拿到全部词汇，是典型的界面骗人。
        let model = VocabularyViewModel(state: state([
            record("h", basic: "aaa", priority: "high"),
            record("n", basic: "bbb", priority: "normal")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .high,
                                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 1)
        XCTAssertTrue(document.text.contains("aaa"))
        XCTAssertFalse(document.text.contains("bbb"))
    }

    func testExportFollowsTheDisplayedOrder() {
        let model = VocabularyViewModel(state: state([
            record("l", basic: "ccc", priority: "low"),
            record("h", basic: "aaa", priority: "high")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .all,
                                            exportedAt: exportedAt, calendar: utc)
        let words = document.text.split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("#") }
            .map { $0.components(separatedBy: "\t")[0] }
        XCTAssertEqual(words, ["aaa", "ccc"], "导出顺序必须与界面上看到的一致")
    }

    func testExportingAnEmptyVocabularyExplainsItselfInsteadOfFailingSilently() {
        let document = VocabularyViewModel(state: CoachState.empty())
            .exportDocument(format: .ankiTSV, filter: .all,
                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertFalse(document.skipped.isEmpty)
        XCTAssertTrue(document.skipped.joined().contains("下一步"))
    }

    func testExportingAFilterWithNoMatchesSaysItIsTheFilterNotAnEmptyBook() {
        // 词汇本明明不空，却告诉用户「词汇本还是空的」，会让他去找一个不存在的问题。
        let model = VocabularyViewModel(state: state([
            record("n", basic: "bbb", priority: "normal")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .high,
                                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains(VocabularyFilter.high.title),
                      "要指出是哪个筛选下没有内容：\(document.skipped[0])")
        XCTAssertTrue(document.skipped[0].contains("下一步"))
        XCTAssertFalse(document.skipped[0].contains("词汇本还是空的"))
    }
}
