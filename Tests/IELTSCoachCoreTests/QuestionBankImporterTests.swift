import XCTest
@testable import IELTSCoachCore

final class QuestionBankImporterTests: XCTestCase {
    func testImportsUpstreamSampleCSV() throws {
        let csv = """
        id,part,topic,prompt,followups
        p1-home-001,1,Home,What do you like most about your home?,
        p2-skill-001,2,Skills,Describe a useful skill you learned,"How you learned it|Why it is useful"
        """
        let result = try QuestionBankImporter.importCSV(csv, sourceTitle: "样例题库")
        XCTAssertEqual(result.questions.count, 2)
        XCTAssertEqual(result.questions[0].part, 1)
        XCTAssertTrue(result.questions[0].followups.isEmpty)
        XCTAssertEqual(result.questions[1].followups, ["How you learned it", "Why it is useful"])
        XCTAssertEqual(result.source.questionCount, 2)
    }

    func testCSVWithCommaInsideQuotedPrompt() throws {
        let csv = """
        id,part,topic,prompt,followups
        p3-x-001,3,Tech,"Has technology, on balance, helped us?",
        """
        let result = try QuestionBankImporter.importCSV(csv, sourceTitle: "t")
        XCTAssertEqual(result.questions[0].prompt, "Has technology, on balance, helped us?")
    }

    func testRejectsCSVWithoutRequiredHeaders() {
        XCTAssertThrowsError(try QuestionBankImporter.importCSV("a,b\n1,2", sourceTitle: "t")) { error in
            XCTAssertTrue("\(error)".contains("表头"))
        }
    }

    func testWarnsOnInvalidPartAndSkipsRow() throws {
        let csv = """
        id,part,topic,prompt,followups
        good-001,1,Home,Fine question,
        bad-001,9,Home,Bad part,
        """
        let result = try QuestionBankImporter.importCSV(csv, sourceTitle: "t")
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("bad-001"))
    }

    func testImportsUpstreamSampleJSON() throws {
        let json = """
        {"title":"Open sample","sourceUrl":"","importedAt":"2026-08-04T00:00:00.000Z",
         "importLevel":"full-question",
         "part1":[{"raw":"Daily routines","questions":["What part do you enjoy most?","Has it changed?"]}],
         "part23":[{"raw":"A useful skill",
                    "part2Questions":["Describe a useful skill you learned."],
                    "part3Questions":["Which skills should schools teach?"]}]}
        """
        let result = try QuestionBankImporter.importJSON(json, sourceTitle: "忽略，用文件里的 title")
        XCTAssertEqual(result.source.title, "Open sample")
        XCTAssertEqual(result.questions.filter { $0.part == 1 }.count, 2)
        XCTAssertEqual(result.questions.filter { $0.part == 2 }.count, 1)
        XCTAssertEqual(result.questions.filter { $0.part == 3 }.count, 1)
        XCTAssertEqual(result.questions.first { $0.part == 1 }?.topic, "Daily routines")
    }

    func testMergeDeduplicatesByIDPreferringIncoming() {
        let existing = [Question(id: "q1", part: 1, topic: "Old", prompt: "old")]
        let incoming = [Question(id: "q1", part: 1, topic: "New", prompt: "new"),
                        Question(id: "q2", part: 2, topic: "X", prompt: "x")]
        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == "q1" }?.topic, "New")
    }

    func testMergeSurvivesDuplicateIDsWithinIncoming() {
        let existing = [Question(id: "q1", part: 1, topic: "Old", prompt: "old")]
        let incoming = [
            Question(id: "dup", part: 1, topic: "第一次", prompt: "a"),
            Question(id: "dup", part: 1, topic: "第二次", prompt: "b"),   // 同一批内重复
            Question(id: "q2", part: 2, topic: "X", prompt: "x")
        ]
        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.count, 3, "重复 id 应被去重，不应崩溃")
        XCTAssertEqual(Set(merged.map(\.id)), ["q1", "dup", "q2"])
        XCTAssertEqual(merged.first { $0.id == "dup" }?.topic, "第二次", "同 id 应后者覆盖前者")
    }

    func testJSONImportProducesPositionIndependentIDs() throws {
        let makeJSON: (Bool) -> String = { withExtraTopicFirst in
            let extra = withExtraTopicFirst
                ? #"{"raw":"新插入的话题","questions":["A brand new question?"]},"#
                : ""
            return """
            {"title":"t","sourceUrl":"","importedAt":"2026-08-04T00:00:00.000Z",
             "importLevel":"full-question",
             "part1":[\(extra){"raw":"Daily routines","questions":["What part do you enjoy most?"]}]}
            """
        }
        let first = try QuestionBankImporter.importJSON(makeJSON(false), sourceTitle: "t")
        let second = try QuestionBankImporter.importJSON(makeJSON(true), sourceTitle: "t")

        let originalID = try XCTUnwrap(first.questions.first { $0.topic == "Daily routines" }?.id)
        let afterInsertID = try XCTUnwrap(second.questions.first { $0.topic == "Daily routines" }?.id)
        XCTAssertEqual(originalID, afterInsertID,
                       "在前面插入一个 topic 后，原有题目的 id 变了 —— 二次导入会毁掉练习记录")
    }

    func testWarnsOnMissingID() throws {
        // 必须让 part 合法（1/2/3），否则「缺少 id」这条警告几乎不可达——
        // 缺 id 的行通常 part 也是空的，会被 part 分支先拦下（见源码注释）。
        let csv = """
        id,part,topic,prompt,followups
        ,1,Home,A question with no id,
        """
        let result = try QuestionBankImporter.importCSV(csv, sourceTitle: "t")
        XCTAssertTrue(result.warnings.contains { $0.contains("缺少 id") },
                      "缺少 id 的行没有产生警告，实际警告：\(result.warnings)")
        XCTAssertTrue(result.questions.isEmpty)
    }

    func testWarnsOnUnterminatedQuote() throws {
        let csv = """
        id,part,topic,prompt,followups
        p1-a-001,1,Home,"这条题干的引号没有闭合,
        p1-a-002,1,Home,正常的题目,
        """
        let result = try QuestionBankImporter.importCSV(csv, sourceTitle: "t")
        XCTAssertTrue(result.warnings.contains { $0.contains("双引号没有闭合") },
                      "未闭合引号没有产生警告，题目会静默丢失。实际警告：\(result.warnings)")
    }
}
