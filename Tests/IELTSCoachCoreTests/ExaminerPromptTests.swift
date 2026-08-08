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

    /// **DEFINITION-OF-DONE 第 4 节第一条：不预测雅思分数。**
    ///
    /// 这条红线此前在复盘这条路上没有任何守卫：七条输出要求里一条都没禁止 ChatGPT 打分。
    /// 之所以一直没透出来，纯粹是因为 `summary` 压根没被显示——
    /// 而「把 summary 显示出来」正是复审第 2 条要修的事，两件事必须同时做完。
    /// 界面这一侧拦不住：`summary` 是 ChatGPT 写的，扫源码扫不到它。
    /// 唯一能拦的地方就是这份提示词。
    func testReviewRequestForbidsAnyBandScoreOrLevelJudgement() {
        for part in FocusPart.allCases {
            let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: part)
            XCTAssertTrue(text.contains("不要给任何形式的雅思分数、评级或水平判断"),
                          "\(part) 的复盘请求里没有禁止打分这一条。"
                              + "「你大概 6.5 分」既不准也有害，会让学员盯着数字"
                              + "而不是盯着具体哪句话该怎么改（DEFINITION-OF-DONE 第 4 节）。")
            XCTAssertTrue(text.contains("summary 里同样一个字都不许出现"),
                          "禁令没有点名 summary。整体总结是唯一一段连贯的话，"
                              + "也是最容易顺手写上一句「大概 6.5」的地方——"
                              + "而它现在会原样显示在复盘报告页上。")
        }
    }

    /// 提示词要 ChatGPT 输出的每一个顶层键，界面上都得有人显示。
    /// 这条钉的是那张键表本身没有被悄悄缩水——它是「复盘里有哪些内容」的唯一出处，
    /// 而 `ReviewReportViewModel` 的分区表照着它写。
    func testReviewRequestStillAsksForTheHabitsAndLogicFeedbackBlocks() {
        let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: .part2)
        for key in ["summary", "must_correct", "natural_upgrades", "vocabulary",
                    "habits", "logic_feedback", "answer_upgrades", "priority_target"] {
            XCTAssertTrue(text.contains(key), "复盘请求里不再要 \(key) 这一项了")
        }
        XCTAssertTrue(text.contains(#""fix": 下次怎么改"#),
                      "口语习惯少了「下次怎么改」这一格。只说「你有这个毛病」而不说怎么改，"
                          + "正是本项目铁律 4 要拦的那种话。")
    }

    func testFullMockThreadsPart2PrepMode() {
        let countdown = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, part2PrepMode: .countdown))
        XCTAssertTrue(countdown.contains("Announce one minute of preparation"),
                      "全真模考里有 Part 2，准备时间模式必须传进去")

        let learnerLed = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, part2PrepMode: .learnerControlled))
        XCTAssertTrue(learnerLed.contains("say \"I'm ready\""))
        XCTAssertFalse(learnerLed.contains("Announce one minute of preparation"),
                       "用户选了自己决定，不该再出现倒计时指令")
    }

    func testFullMockDoesNotCancelImmediateCorrections() {
        let text = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, feedbackTiming: .immediate))
        XCTAssertTrue(text.contains("After each answer"))
        XCTAssertTrue(text.contains("does NOT cancel"),
                      "必须明确「不在各 Part 之间总结」不等于「整场不给反馈」，否则会静默覆盖当场点评")
        XCTAssertFalse(text.contains("without pausing for feedback between them"),
                       "这句歧义表述应已被替换")
    }
}
