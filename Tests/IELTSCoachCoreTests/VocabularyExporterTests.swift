import XCTest
@testable import IELTSCoachCore

final class VocabularyExporterTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let exportedAt = CoachTime.parse("2026-08-06T01:00:00Z")!

    private func record(_ id: String, basic: String, better: String = "rewarding",
                        collocation: String = "a rewarding trip",
                        priority: String = "high") -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: basic, betterExpression: better,
                         collocation: collocation, priority: priority,
                         sourceSessionIds: ["2026-08-01-001"])
    }

    private func tsv(_ records: [VocabularyRecord]) -> ExportDocument {
        VocabularyExporter.export(records, format: .ankiTSV,
                                  exportedAt: exportedAt, calendar: utc)
    }

    /// 去掉文件头之后的数据行。
    private func dataLines(_ document: ExportDocument) -> [String] {
        document.text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }

    // MARK: - 优先级归一

    func testPriorityNormalizationHandlesEveryShapeChatGPTMightEmit() {
        XCTAssertEqual(VocabularyPriority.normalize("high"), .high)
        XCTAssertEqual(VocabularyPriority.normalize("  HIGH "), .high)
        XCTAssertEqual(VocabularyPriority.normalize("low"), .low)
        // ChatGPT 写过 "medium"；上游默认值是 "normal"；也可能整个字段是空的。
        // 任何没见过的写法都当普通，不能崩、也不能凭空多出一个档次。
        XCTAssertEqual(VocabularyPriority.normalize("medium"), .normal)
        XCTAssertEqual(VocabularyPriority.normalize("normal"), .normal)
        XCTAssertEqual(VocabularyPriority.normalize(""), .normal)
        XCTAssertEqual(VocabularyPriority.normalize("紧急"), .normal)
    }

    func testPrioritySortRankPutsHighFirst() {
        XCTAssertLessThan(VocabularyPriority.high.sortRank, VocabularyPriority.normal.sortRank)
        XCTAssertLessThan(VocabularyPriority.normal.sortRank, VocabularyPriority.low.sortRank)
    }

    // MARK: - TSV

    func testTSVHeaderTellsAnkiEverythingItNeeds() {
        let text = tsv([record("v1", basic: "good")]).text
        for directive in ["#separator:tab", "#html:true", "#notetype:Basic",
                          "#deck:IELTS Speaking Coach", "#tags column:3"] {
            XCTAssertTrue(text.contains(directive), "文件头缺少 \(directive)")
        }
    }

    func testTSVRowHasThreeColumnsInTheDeclaredOrder() {
        let document = tsv([record("v1", basic: "good")])
        let lines = dataLines(document)
        XCTAssertEqual(lines.count, 1)
        let columns = lines[0].components(separatedBy: "\t")
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0], "good")
        XCTAssertEqual(columns[1], "rewarding<br>a rewarding trip")
        XCTAssertEqual(columns[2], "ielts-speaking ielts-speaking::high")
        XCTAssertEqual(document.exportedCount, 1)
    }

    func testTabsAndNewlinesInsideFieldsCannotBreakTheTable() {
        // 一个制表符就是一次分列，一个换行就是一条新记录。
        // 不清洗的话，一条卡片会被静默切成两条或多出一列，
        // 用户在 Anki 里根本不会发现。
        let document = tsv([record("v1", basic: "a\tb", better: "line1\nline2",
                                   collocation: "", priority: "normal")])
        let lines = dataLines(document)
        XCTAssertEqual(lines.count, 1, "换行必须被替换掉，不能变成第二行")
        let columns = lines[0].components(separatedBy: "\t")
        XCTAssertEqual(columns.count, 3, "制表符必须被替换掉，不能多出一列")
        XCTAssertEqual(columns[0], "a b")
        XCTAssertEqual(columns[1], "line1<br>line2")
    }

    func testRecordWithoutBasicWordIsSkippedWithAnActionableMessage() {
        let document = tsv([record("v1", basic: "   "), record("v2", basic: "good")])
        XCTAssertEqual(document.exportedCount, 1)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("下一步"))
    }

    func testRecordWithEmptyBackIsSkippedWithAnActionableMessage() {
        let document = tsv([record("v1", basic: "good", better: "", collocation: "")])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("good"), "说明里要指出是哪一条被跳过了")
        XCTAssertTrue(document.skipped[0].contains("下一步"))
    }

    func testEmptyVocabularySaysSoInsteadOfHandingOverAnEmptyFile() {
        let document = tsv([])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("下一步"))
        XCTAssertTrue(dataLines(document).isEmpty)
    }

    func testExportOrderFollowsTheGivenOrder() {
        let document = tsv([record("v1", basic: "a"), record("v2", basic: "b")])
        XCTAssertEqual(dataLines(document).map { $0.components(separatedBy: "\t")[0] },
                       ["a", "b"], "导出顺序必须等于传入顺序，界面才能所见即所得")
    }

    // MARK: - AnkiConnect JSON

    func testAnkiConnectPayloadIsAValidAddNotesRequest() throws {
        let document = VocabularyExporter.export([record("v1", basic: "good")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        let root = try JSONValue.decode(from: document.text)
        XCTAssertEqual(root["action"]?.stringValue, "addNotes")
        XCTAssertEqual(root["version"], .number(6))

        let notes = try XCTUnwrap(root["params"]?["notes"]?.arrayValue)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0]["deckName"]?.stringValue, "IELTS Speaking Coach")
        XCTAssertEqual(notes[0]["modelName"]?.stringValue, "Basic")
        XCTAssertEqual(notes[0]["fields"]?["Front"]?.stringValue, "good")
        XCTAssertEqual(notes[0]["fields"]?["Back"]?.stringValue, "rewarding<br>a rewarding trip")
        XCTAssertEqual(notes[0]["tags"]?.arrayValue?.compactMap(\.stringValue),
                       ["ielts-speaking", "ielts-speaking::high"])
        XCTAssertEqual(document.exportedCount, 1)
    }

    func testAnkiConnectSkipsTheSameRecordsAsTSV() throws {
        let document = VocabularyExporter.export([record("v1", basic: "")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        let notes = try XCTUnwrap(
            try JSONValue.decode(from: document.text)["params"]?["notes"]?.arrayValue)
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - 文件名与使用说明

    func testSuggestedFileNameCarriesTheDateAndTheRightExtension() {
        XCTAssertEqual(tsv([record("v1", basic: "good")]).suggestedFileName,
                       "ielts-vocabulary-2026-08-06.txt")
        XCTAssertEqual(VocabularyExporter.export([record("v1", basic: "good")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
                        .suggestedFileName,
                       "ielts-vocabulary-2026-08-06.json")
    }

    func testEveryFormatExplainsHowToUseItIncludingTheNextStep() {
        for format in VocabularyExportFormat.allCases {
            XCTAssertFalse(format.title.isEmpty, "\(format) 缺少显示名")
            XCTAssertTrue(format.howToUse.contains("下一步"),
                          "\(format) 必须告诉用户拿到文件之后干什么：\(format.howToUse)")
        }
    }
}
