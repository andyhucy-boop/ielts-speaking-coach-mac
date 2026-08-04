import XCTest
@testable import IELTSCoachCore

final class ExaminerPromptTests: XCTestCase {
    private let question = Question(id: "p2-skill-001", part: 2, topic: "Skills",
                                    prompt: "Describe a useful skill you learned",
                                    followups: ["How you learned it", "Why it is useful"])

    func testIncludesQuestionAndFollowups() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("Describe a useful skill you learned"))
        XCTAssertTrue(text.contains("How you learned it"))
    }

    func testCarriesExaminerContractVerbatim() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("I will act as the examiner."))
        XCTAssertTrue(text.contains("结束训练"))
    }

    func testPart2AnnouncesPreparationAndSpeakingTime() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("one minute of preparation"))
        XCTAssertTrue(text.contains("up to two minutes"))
    }

    func testPart1UsesShortQuestionRule() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p1-home-001", part: 1, topic: "Home", prompt: "Tell me about your home"),
            focusPart: .part1, durationMinutes: 5, goal: ""))
        XCTAssertTrue(text.contains("6–10 short questions"))
        XCTAssertFalse(text.contains("one minute of preparation"))
    }

    func testIncludesSingleGoalWhenProvided() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: "减少 filler words"))
        XCTAssertTrue(text.contains("减少 filler words"))
    }

    func testOmitsGoalSectionWhenEmpty() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertFalse(text.contains("本次唯一目标"))
    }

    func testForbidsFeedbackDuringExam() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."))
    }

    func testReviewRequestEmbedsRequestIDInBothMarkers() {
        let text = ReviewRequestPrompt.build(requestID: "sync-123", focusPart: .part2)
        XCTAssertTrue(text.contains("<<<IELTS_REVIEW_JSON:sync-123>>>"))
        XCTAssertTrue(text.contains("<<<END_IELTS_REVIEW_JSON:sync-123>>>"))
        XCTAssertTrue(text.contains("SYNC_REQUEST_ID:sync-123"))
    }

    func testReviewRequestCarriesAnswerUpgradePolicy() {
        let text = ReviewRequestPrompt.build(requestID: "sync-123", focusPart: .part2)
        XCTAssertTrue(text.contains("90至120秒"))
        XCTAssertTrue(text.contains("逐题高分版生成规则"))
    }

    func testBuildCoversEveryFocusPartCase() {
        // partRules 是手写的 [FocusPart: String] 字典，删掉 assertionFailure 之后
        // build() 里改成了强制解包；这条测试逐 case 跑一遍，保证字典没有漏掉某个
        // FocusPart case（否则会在这里而不是生产环境里炸出来）。
        for part in FocusPart.allCases {
            let text = ExaminerPrompt.build(setup: SessionSetup(
                question: question, focusPart: part, durationMinutes: 4, goal: ""))
            XCTAssertTrue(text.contains("Section rules"), "缺少 \(part) 的 section rules")
        }
    }

    func testReviewRequestOutputIsParseableEndToEnd() throws {
        // 用一份符合指令要求的假回复，验证 ReviewParser 能吃下自己发出的格式
        let (open, close) = ReviewRequestPrompt.marker(requestID: "sync-9")
        let fake = """
        \(open)
        {"summary":"ok","must_correct":[],"answer_upgrades":[{"question":"Q",\
        "original_answer":"a","revised_answer":"b","changes":[]}],"priority_target":{"id":"t"}}
        \(close)
        """
        XCTAssertEqual(try ReviewParser.parse(fake, requireAnswerUpgrades: true)["summary"],
                       .string("ok"))
    }
}
