import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingEvidenceTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    private func target(evidence: [String]) -> RetrainingTarget {
        RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                         evidence: evidence, sourceSessionId: "s0", createdAt: "t")
    }

    private func turn(_ role: String, _ text: String) -> PracticeSession.TranscriptTurn {
        PracticeSession.TranscriptTurn(role: role, text: text, capturedAt: "2026-08-05T10:00:00Z")
    }

    /// 一份复盘里通常有好几道题的原答。必须挑出**含有这条证据原话**的那一条，
    /// 否则学员看到的是另一道题的答案，整个「回看证据」就是错的。
    func testPicksTheUpgradeEntryThatContainsTheEvidenceQuote() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Do you like your hometown?","original_answer":"It is fine, nothing special.",
           "revised_answer":"It's a comfortable place...","changes":["补了原因"]},
          {"question":"Do you like reading?","original_answer":"I just like it.",
           "revised_answer":"I like it because it helps me switch off.","changes":["补了原因","补了例子"]}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["I just like it."]), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "I just like it.")
        XCTAssertEqual(evidence.modelAnswer, "I like it because it helps me switch off.")
        XCTAssertEqual(evidence.changes, ["补了原因", "补了例子"])
        XCTAssertNil(evidence.missingNote)
    }

    func testFallsBackToTheFirstUsableEntryWhenNothingMatches() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Q1","original_answer":"","revised_answer":"空原答的这条要跳过"},
          {"question":"Q2","original_answer":"Something I actually said.","revised_answer":"Better."}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["对不上的一句话"]), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "Something I actually said.")
        XCTAssertNil(evidence.missingNote, "有可用的原答就不算缺材料")
    }

    /// 报告读不到要说清楚。空着不说，用户只会看到一片空白，以为程序坏了。
    func testMissingReportIsExplainedNotSilentlyEmpty() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["I just like it."]), report: nil, transcript: [])
        XCTAssertEqual(evidence.quotes, ["I just like it."], "原话来自 state，报告读不到也还在")
        XCTAssertEqual(evidence.originalAnswer, "")
        let note = try? XCTUnwrap(evidence.missingNote)
        XCTAssertTrue((note ?? "").contains("下一步"))
    }

    /// ChatGPT 曾把数组输出成对象（spec 2.3.8）。界面绝不能崩，最多是这一块没内容。
    func testSurvivesWrongShapedAnswerUpgrades() throws {
        let value = try report(#"{"answer_upgrades":{"question":"Q","original_answer":"A"}}"#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: []), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "")
        XCTAssertNotNil(evidence.missingNote)
    }

    func testKeepsOnlyLearnerTurnsFromTheTranscript() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: []), report: nil,
            transcript: [turn("assistant", "Do you like reading?"),
                         turn("user", "I just like it."),
                         turn("user", "   "),
                         turn("assistant", "Why?")])
        XCTAssertEqual(evidence.learnerTurns.map(\.text), ["I just like it."],
                       "考官说的话不是「你说过的话」；空白轮次也不该占一行")
    }

    func testBlankQuotesAreDropped() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["  ", "I just like it.", ""]), report: nil, transcript: [])
        XCTAssertEqual(evidence.quotes, ["I just like it."])
    }

    func testQuoteMatchingIgnoresCase() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Q1","original_answer":"Nothing here.","revised_answer":"X"},
          {"question":"Q2","original_answer":"I JUST LIKE IT, really.","revised_answer":"Y"}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["i just like it"]), report: value, transcript: [])
        XCTAssertEqual(evidence.modelAnswer, "Y")
    }

    /// 计划里那七条查 `quotes` 与 `learnerTurns` 时走的都是「报告读不到」那条分支
    /// （`report: nil`），查正常路径时又一律不传逐字稿。于是**挑中原答之后那条正常返回里，
    /// 这两样有没有被带出来，谁都没问过**——把它们写成 `[]`，七条全绿，
    /// 而学员在第一步只看得到原答和高分版，「回到你真正说过的话」整块凭空消失，
    /// 屏幕上还看不出任何异常。
    func testTheMatchedPathStillCarriesTheQuotesAndTheLearnerTurns() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Do you like reading?","original_answer":"I just like it.",
           "revised_answer":"I like it because it helps me switch off.","changes":["补了原因"]}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["I just like it."]), report: value,
            transcript: [turn("assistant", "Do you like reading?"),
                         turn("user", "I just like it.")])
        XCTAssertNil(evidence.missingNote, "这一条走的必须是材料齐全那条路径")
        XCTAssertEqual(evidence.quotes, ["I just like it."])
        XCTAssertEqual(evidence.learnerTurns.map(\.text), ["I just like it."])
    }
}
