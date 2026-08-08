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
        // 用 first 而不是 [0]：跳过说明丢了的时候，这里该是一条红的断言，
        // 不该是一次数组越界崩溃——崩溃会把整轮测试打断，后面的结果全看不到。
        XCTAssertTrue((document.skipped.first ?? "").contains("下一步"))
    }

    func testRecordWithEmptyBackIsSkippedWithAnActionableMessage() {
        let document = tsv([record("v1", basic: "good", better: "", collocation: "")])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        let message = document.skipped.first ?? ""
        XCTAssertTrue(message.contains("good"), "说明里要指出是哪一条被跳过了：\(message)")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testEmptyVocabularySaysSoInsteadOfHandingOverAnEmptyFile() {
        let document = tsv([])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue((document.skipped.first ?? "").contains("下一步"))
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

    // MARK: - 计划里的测试没覆盖到的地方（补齐空转，2026-08-07）
    //
    // 下面每一条都对应一处「把产品代码改坏、上面 13 条测试全绿」的地方。

    /// 计划里的 TSV 断言只用了 `high` 一档，`ankiTag` 写死成任何常量都不会被发现。
    /// 标签错了的后果不是报错，是用户在 Anki 里按 `ielts-speaking::high` 筛出一堆
    /// 本该「先放着」的词——他会照着这个顺序背下去。
    func testTagColumnFollowsTheNormalizedPriorityForEveryLevel() {
        let expected: [(raw: String, tag: String)] = [
            ("high", "ielts-speaking ielts-speaking::high"),
            ("normal", "ielts-speaking ielts-speaking::normal"),
            ("low", "ielts-speaking ielts-speaking::low"),
            ("紧急", "ielts-speaking ielts-speaking::normal")     // 没见过的写法归到 normal
        ]
        for (raw, tag) in expected {
            let document = tsv([record("v1", basic: "good", priority: raw)])
            let columns = dataLines(document)[0].components(separatedBy: "\t")
            XCTAssertEqual(columns[2], tag, "priority=\(raw) 的标签列不对")
        }
    }

    /// `title` 是要显示在「我的词汇」页上的中文档次名（Task 7 用它分组）。
    /// 计划里一条都没测：三档全返回空字符串，13 条测试照样全绿，
    /// 界面上就是三个没有名字的分组。
    func testEveryPriorityLevelHasItsOwnChineseTitle() {
        let titles = VocabularyPriority.allCases.map(\.title)
        for title in titles {
            XCTAssertFalse(title.trimmingCharacters(in: .whitespaces).isEmpty, "有档次没有中文名")
        }
        XCTAssertEqual(Set(titles).count, VocabularyPriority.allCases.count,
                       "三档的名字必须互不相同，否则界面上分不出哪组是哪组")
        XCTAssertEqual(VocabularyPriority.high.title, "优先记")
    }

    /// `deckName` / `noteType` 是 `export` 的公开参数。计划里只测了默认值，
    /// 实现把它们原地忽略、写死成默认值，13 条测试全绿。
    func testDeckNameAndNoteTypeComeFromTheArguments() throws {
        let text = VocabularyExporter.export([record("v1", basic: "good")],
                                             format: .ankiTSV,
                                             deckName: "雅思口语::生词",
                                             noteType: "Basic (and reversed card)",
                                             exportedAt: exportedAt, calendar: utc).text
        XCTAssertTrue(text.contains("#deck:雅思口语::生词"), "牌组名没有用传进来的值：\(text)")
        XCTAssertTrue(text.contains("#notetype:Basic (and reversed card)"), "笔记类型没有用传进来的值")

        let json = VocabularyExporter.export([record("v1", basic: "good")],
                                             format: .ankiConnectJSON,
                                             deckName: "雅思口语::生词",
                                             noteType: "Basic (and reversed card)",
                                             exportedAt: exportedAt, calendar: utc).text
        let note = try XCTUnwrap(try JSONValue.decode(from: json)["params"]?["notes"]?.arrayValue?.first)
        XCTAssertEqual(note["deckName"]?.stringValue, "雅思口语::生词")
        XCTAssertEqual(note["modelName"]?.stringValue, "Basic (and reversed card)")
    }

    /// 文件头里的牌组名同样要清洗。带换行的牌组名会在文件开头凭空多出一行，
    /// Anki 按第二行指令导入，卡片全进错牌组——而且不报任何错。
    func testDeckNameWithNewlinesCannotInjectASecondHeaderLine() {
        let text = VocabularyExporter.export([record("v1", basic: "good")],
                                             format: .ankiTSV,
                                             deckName: "牌组\n#deck:别的牌组",
                                             exportedAt: exportedAt, calendar: utc).text
        let deckLines = text.split(separator: "\n").filter { $0.hasPrefix("#deck:") }
        XCTAssertEqual(deckLines.count, 1, "牌组名里的换行必须被清洗掉，不能多出一条 #deck 指令：\(text)")
    }

    /// 文件名的日期必须按传进来的日历算。计划里那条用的是 01:00Z——
    /// 在东八区仍是同一天，所以实现把 `calendar` 参数丢掉直接用 `.current`，
    /// 那条测试照样过。晚上练完导出，文件名会写成前一天。
    func testFileNameDayFollowsTheGivenCalendarNotTheMachineTimeZone() {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let lateNight = CoachTime.parse("2026-08-06T23:30:00Z")!

        XCTAssertEqual(VocabularyExporter.export([record("v1", basic: "good")], format: .ankiTSV,
                                                 exportedAt: lateNight, calendar: utc)
                        .suggestedFileName, "ielts-vocabulary-2026-08-06.txt")
        XCTAssertEqual(VocabularyExporter.export([record("v1", basic: "good")], format: .ankiTSV,
                                                 exportedAt: lateNight, calendar: shanghai)
                        .suggestedFileName, "ielts-vocabulary-2026-08-07.txt")
    }

    /// 同一个词会被多次复盘推荐，重复导入不该在牌组里堆出十张一样的卡。
    /// `options` 整段删掉，计划里那两条 AnkiConnect 测试都不会红。
    func testAnkiConnectNotesRefuseDuplicatesWithinTheDeck() throws {
        let document = VocabularyExporter.export([record("v1", basic: "good")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        let note = try XCTUnwrap(
            try JSONValue.decode(from: document.text)["params"]?["notes"]?.arrayValue?.first)
        let options = try XCTUnwrap(note["options"], "AnkiConnect 的 options 段不见了")
        XCTAssertEqual(options["allowDuplicate"], .bool(false))
        XCTAssertEqual(options["duplicateScope"]?.stringValue, "deck")
    }

    /// `sanitize` 的替换顺序不能变——先 `\r\n` 再 `\r`、`\n`。
    /// 顺序反了，Windows 换行会变成两个 `<br>`，卡片背面凭空多出一行空行。
    /// 计划里的测试只用了 `\n`，换成什么顺序都是绿的。
    func testWindowsLineEndingsBecomeExactlyOneBreak() {
        let document = tsv([record("v1", basic: "good", better: "line1\r\nline2",
                                   collocation: "")])
        let columns = dataLines(document)[0].components(separatedBy: "\t")
        XCTAssertEqual(columns[1], "line1<br>line2", "\\r\\n 必须只换出一个 <br>")
    }

    /// 单独的 `\r`（老 Mac 换行）也必须换成 `<br>`。它原样留在字段里，
    /// Anki 那边按 `\r` 断行、这个文件按 `\n` 断行，同一张卡在两处显示不一样，
    /// 而且导入时不会有任何提示。
    func testLoneCarriageReturnIsAlsoReplaced() {
        let document = tsv([record("v1", basic: "good", better: "line1\rline2",
                                   collocation: "")])
        XCTAssertEqual(dataLines(document)[0].components(separatedBy: "\t")[1], "line1<br>line2",
                       "单独的 \\r 必须被替换成 <br>")
    }

    // MARK: - 纯换行的字段不许绕过两道跳过闸门（复审发现，2026-08-07）
    //
    // `sanitize` 原来先把 `\n` 换成 `<br>`、最后才按 `.whitespaces`（**不含换行**）
    // 修剪，于是判空时字符串已经是 `<br>` 了：两处 `guard !...isEmpty` 都判不出来，
    // 卡片照导、`skipped` 里一个字都没有——正是本项目最危险的那种「静默的 0」。
    // 可达路径不是理论上的：ReviewArchiver 只对 `basic` 做了
    // `.whitespacesAndNewlines` 修剪，`better` / `collocation` 是原样入库的，
    // ChatGPT 复盘里一个 `"better": "\n"` 就会一路变成一张背面空白的卡。

    /// 正面只有一个换行：用户在 Anki 里拿到的是一张正面完全空白的卡，
    /// 而导出界面显示「导出 1 条、跳过 0 条」，他不会去查。
    func testNewlineOnlyBasicWordIsSkippedInsteadOfExportingABlankFront() {
        let document = tsv([record("v1", basic: "\n")])
        XCTAssertEqual(document.exportedCount, 0, "正面只有换行的卡片不能被导出去")
        XCTAssertTrue(dataLines(document).isEmpty, "文件里不该有这条数据行：\(document.text)")
        XCTAssertEqual(document.skipped.count, 1, "跳过必须有说明，不能静默少导")
        XCTAssertTrue((document.skipped.first ?? "").contains("下一步"))
    }

    /// 背面两个字段都只有换行：背面清洗出来是 `<br><br><br>`，
    /// 在 Anki 里就是三行空行——「记它没有意义」正是计划里写明要跳过的那一格。
    func testNewlineOnlyBackIsSkippedInsteadOfExportingABlankBack() {
        let document = tsv([record("v1", basic: "good", better: "\n", collocation: "\r\n")])
        XCTAssertEqual(document.exportedCount, 0, "背面只有换行的卡片不能被导出去")
        XCTAssertTrue(dataLines(document).isEmpty, "文件里不该有这条数据行：\(document.text)")
        XCTAssertEqual(document.skipped.count, 1, "跳过必须有说明，不能静默少导")
        let message = document.skipped.first ?? ""
        XCTAssertTrue(message.contains("good"), "说明里要指出是哪一条被跳过了：\(message)")
        XCTAssertTrue(message.contains("下一步"))
    }

    /// 同一个错的轻症版本：计划的清洗规则写的是「首尾空白 → 去掉」，换行也是空白。
    /// 先换 `<br>` 再修剪，等于把首尾的换行留成了 `<br>`——
    /// 卡片正面顶上、背面末尾各多出一行空行。
    func testLeadingAndTrailingNewlinesDoNotBecomeStrayBreaks() {
        let document = tsv([record("v1", basic: "\ngood\n", better: "\nrewarding\n",
                                   collocation: "")])
        let columns = (dataLines(document).first ?? "").components(separatedBy: "\t")
        guard columns.count == 3 else {
            return XCTFail("这条有内容，不该被跳过，应当导出一行三列：\(document.text)")
        }
        XCTAssertEqual(columns[0], "good", "正面首尾的换行必须去掉，不能留成 <br>")
        XCTAssertEqual(columns[1], "rewarding", "背面首尾的换行必须去掉，不能留成 <br>")
    }

    /// AnkiConnect 走的是同一段筛选逻辑，但它是**直接写进用户牌组**的那条路——
    /// TSV 至少还能在导入对话框里瞄一眼，这条 curl 完就进去了。
    func testAnkiConnectAlsoRefusesNewlineOnlyCards() throws {
        let document = VocabularyExporter.export([record("v1", basic: "\n"),
                                                  record("v2", basic: "good", better: "\n",
                                                         collocation: "\n")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 2, "两条都要有说明")
        let notes = try XCTUnwrap(
            try JSONValue.decode(from: document.text)["params"]?["notes"]?.arrayValue)
        XCTAssertTrue(notes.isEmpty, "空白卡片不能进 addNotes 请求：\(document.text)")
    }
}
