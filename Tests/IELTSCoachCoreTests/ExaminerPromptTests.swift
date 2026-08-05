import XCTest
@testable import IELTSCoachCore

final class ExaminerPromptTests: XCTestCase {
    private let question = Question(id: "p2-skill-001", part: 2, topic: "Skills",
                                    prompt: "Describe a useful skill you learned",
                                    followups: ["How you learned it", "Why it is useful"])

    private func setup(focusPart: FocusPart = .part2,
                        feedbackTiming: FeedbackTiming = .deferred,
                        part2PrepMode: Part2PrepMode = .countdown) -> SessionSetup {
        SessionSetup(question: question, focusPart: focusPart, durationMinutes: 4, goal: "",
                     feedbackTiming: feedbackTiming, part2PrepMode: part2PrepMode)
    }

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
        // 停止口令按 brief 第 3 节要求由中文改英文（testStopCommandIsEnglish 覆盖两种模式）。
        XCTAssertTrue(text.contains("stop the test"))
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

    func testDeferredTimingForbidsMidSessionFeedback() {
        let text = ExaminerPrompt.build(setup: setup(feedbackTiming: .deferred))
        XCTAssertTrue(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."))
        XCTAssertFalse(text.contains("After each answer"))
    }

    func testImmediateTimingAsksForOneShortChineseCorrection() {
        let text = ExaminerPrompt.build(setup: setup(feedbackTiming: .immediate))
        XCTAssertTrue(text.contains("After each answer"))
        XCTAssertTrue(text.contains("at most two sentences"))
        XCTAssertFalse(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."),
                       "immediate 模式不能同时出现「全程不反馈」的指令，两者自相矛盾")
        XCTAssertFalse(text.contains("I will save all feedback until the end"),
                       "immediate 模式的开场白不能说「反馈留到最后」")
    }

    func testCountdownPrepAnnouncesOneMinute() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .part2, part2PrepMode: .countdown))
        XCTAssertTrue(text.contains("Announce one minute of preparation"))
    }

    func testLearnerControlledPrepDoesNotRush() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .part2, part2PrepMode: .learnerControlled))
        XCTAssertTrue(text.contains("say \"I'm ready\""))
        XCTAssertFalse(text.contains("Announce one minute of preparation"))
    }

    func testStopCommandIsEnglish() {
        for timing in FeedbackTiming.allCases {
            let text = ExaminerPrompt.build(setup: setup(feedbackTiming: timing))
            XCTAssertTrue(text.contains("stop the test"), "停止口令应为英文：\(timing)")
            XCTAssertFalse(text.contains("结束训练"), "不应再出现中文停止口令：\(timing)")
        }
    }

    func testAllModesRequireChineseCommentary() {
        for timing in FeedbackTiming.allCases {
            for prep in Part2PrepMode.allCases {
                let text = ExaminerPrompt.build(
                    setup: setup(focusPart: .part2, feedbackTiming: timing, part2PrepMode: prep))
                XCTAssertTrue(text.contains("in 中文"), "缺少中文点评要求：\(timing)/\(prep)")
            }
        }
    }

    func testReviewRequestRequiresChineseCommentary() {
        let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: .part2)
        XCTAssertTrue(text.contains("一律用中文"))
    }
}
