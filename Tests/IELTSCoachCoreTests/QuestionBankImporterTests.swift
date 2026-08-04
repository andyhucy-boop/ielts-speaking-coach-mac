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
}
