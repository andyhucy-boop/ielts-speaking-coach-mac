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

    /// 导出的文本里那一列「原来的说法」。`#` 开头的是 Anki 导入指令，不是卡片。
    private func exportedWords(_ document: ExportDocument) -> [String] {
        document.text.split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("#") }
            .map { $0.components(separatedBy: "\t")[0] }
    }

    /// 这个字是不是汉字。用来问「档次名真的是中文吗」——
    /// 只问「非空」的话，返回英文 case 名照样绿（铁律 6 要求面向用户的文案必须中文）。
    private func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
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
            let title = filter.title
            XCTAssertFalse(title.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(filter) 缺少中文标题")
            // 只问「非空」的话，把三档改成 `return rawValue`（分段控件上显示
            // high / normal / low）照样全绿——实测过。铁律 6：面向用户的文案必须中文。
            XCTAssertNotEqual(title, filter.rawValue,
                              "\(filter) 的档次名退化成了英文 case 名「\(filter.rawValue)」，"
                                  + "筛选控件上会显示一串英文。")
            XCTAssertTrue(containsChinese(title),
                          "\(filter) 的档次名「\(title)」里一个汉字都没有。")
        }
        XCTAssertEqual(Set(VocabularyFilter.allCases.map(\.title)).count,
                       VocabularyFilter.allCases.count,
                       "四档的名字必须互不相同，否则筛选控件上分不出点的是哪一档")
    }

    /// 筛选控件上的三个档次名**必须就是 `VocabularyPriority` 那三个名字**，不许手抄一份。
    ///
    /// 拿 `VocabularyFilter.high.title` 去比对同一个属性产出的字符串是自证式断言：
    /// 档次名一起变英文时它同样恒真。所以这里钉的是「委托关系」——
    /// 而 `VocabularyPriority.high.title` 在 Core 那边（`VocabularyExporterTests`）
    /// 已经被钉成了「优先记」，两条合起来档次名就不可能悄悄退化。
    func testFilterTitlesAreExactlyThePriorityTitles() {
        XCTAssertEqual(VocabularyFilter.high.title, VocabularyPriority.high.title)
        XCTAssertEqual(VocabularyFilter.normal.title, VocabularyPriority.normal.title)
        XCTAssertEqual(VocabularyFilter.low.title, VocabularyPriority.low.title)
        XCTAssertEqual(VocabularyFilter.all.title, "全部",
                       "「全部」这一档不对应任何优先级，名字只能钉死在这儿")
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
        XCTAssertEqual(exportedWords(document), ["aaa", "ccc"], "导出顺序必须与界面上看到的一致")
    }

    /// **重复 id 时，导出的必须还是屏幕上那几行。**
    ///
    /// `state.json` 被外部工具改坏、或上游写入过重复 id 时，靠 `id` 回头查一张
    /// 「id → 记录」的表把行映射回记录，每个 id 只留得下最后一条：
    /// 屏幕上明明是「aaa」「bbb」两行，导出的却是两份「bbb」——
    /// 少了一个词、多了一张重复卡，而且一声不吭（`skipped` 是空的）。
    /// 用户要到 Anki 里才会发现。Task 6 为同一个场景写了
    /// `IssueArchiveViewModelTests.testDuplicateIssueIDsDoNotCrash`。
    func testDuplicateIDsStillExportExactlyWhatIsOnScreen() {
        let model = VocabularyViewModel(state: state([
            record("dup", basic: "aaa", priority: "high"),
            record("dup", basic: "bbb", priority: "high")
        ]))
        XCTAssertEqual(model.rows.map(\.basicWord), ["aaa", "bbb"],
                       "两条都该显示在屏幕上，一条都不许被合并掉")

        let document = model.exportDocument(format: .ankiTSV, filter: .all,
                                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(exportedWords(document), ["aaa", "bbb"],
                       "导出的内容和屏幕上显示的不是一回事：少一个词、多一张重复卡")
        XCTAssertEqual(document.exportedCount, 2)
        XCTAssertTrue(document.skipped.isEmpty,
                      "两条都该导出去，不该有任何一条被跳过：\(document.skipped)")
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
        // 这里问的是 `VocabularyPriority.high.title` 而不是 `VocabularyFilter.high.title`：
        // 后者和被测那句话是同一个属性产出的，档次名一起变英文时这条断言恒真（自证式断言）。
        // Core 那边已经把 `VocabularyPriority.high.title` 钉成了「优先记」。
        XCTAssertTrue(document.skipped[0].contains(VocabularyPriority.high.title),
                      "要指出是哪个筛选下没有内容：\(document.skipped[0])")
        XCTAssertTrue(document.skipped[0].contains("下一步"))
        XCTAssertFalse(document.skipped[0].contains("词汇本还是空的"))
    }
}
