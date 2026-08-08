import XCTest
@testable import IELTSCoachCore

/// `coach prompt` 背后的那一点逻辑。
///
/// 这个命令是排障工具：提示词是这个工具唯一真正的产品，而在它之前，
/// 想看一眼提示词全文只有两条路——真的驱动一次 ChatGPT（铁律 3 禁止），
/// 或者临时写探针。逻辑放在 Core 就是为了让这几条能跑起来（`coach` 没有测试 target）。
final class PromptPreviewTests: XCTestCase {

    // MARK: - --part 的取值

    func testAcceptsEveryWayAPartIsWrittenOnTheCommandLine() {
        let cases: [String: FocusPart] = [
            "1": .part1, "part1": .part1, "Part 1": .part1,
            "2": .part2, "PART 2": .part2,
            "3": .part3, "part-3": .part3,
            "2+3": .part2And3, "part2and3": .part2And3, "2 + 3": .part2And3,
            "mock": .fullMock, "full mock": .fullMock, "full_mock": .fullMock
        ]
        for (token, expected) in cases {
            XCTAssertEqual(PromptPreview.focusPart(forToken: token), expected, "记号：\(token)")
        }
    }

    /// **认不出来必须返回 nil。**
    ///
    /// 猜一个默认值糊弄过去的后果是：用户想看 Part 3，拿到的是一份 Part 1 的提示词，
    /// 而屏幕上没有任何交代——他会照着这份不相干的文本去判断改动有没有生效。
    func testRefusesATokenItDoesNotRecognise() {
        for token in ["", "4分", "three", "part4", "part 5", "全真"] {
            XCTAssertNil(PromptPreview.focusPart(forToken: token),
                         "「\(token)」不该被认成某一档")
        }
    }

    /// 错误提示里念出来的那几个取值，必须真的都认得（铁律 4：下一步得说得出口）。
    func testEveryTokenTheErrorMessageOffersIsActuallyAccepted() {
        for token in PromptPreview.acceptedPartTokens {
            XCTAssertNotNil(PromptPreview.focusPart(forToken: token),
                            "错误提示让用户写「\(token)」，可它自己不认这个写法")
        }
        XCTAssertEqual(Set(PromptPreview.acceptedPartTokens.compactMap {
            PromptPreview.focusPart(forToken: $0)
        }), Set(FocusPart.allCases),
        "错误提示念出来的取值没有覆盖全部考法——有一档用户在命令行上写不出来")
    }

    // MARK: - 示例题

    /// **示例题必须照题库真实的建模长**，否则打出来的提示词和真练时的不是同一个形状，
    /// 这个命令就成了自欺。
    func testTheSamplePart1AndPart3QuestionsAreShapedLikeTheRealBank() {
        for part in [FocusPart.part1, .part3] {
            let question = PromptPreview.sampleQuestion(for: part)
            XCTAssertTrue(TopicQuestions.isTopicQuestion(question),
                          "\(part) 的示例题不是「一话题一题」的形状：\(question)")
            XCTAssertFalse(question.followups.isEmpty,
                           "\(part) 的示例题没有参考问句，提示词里那一栏会整段消失")
        }
    }

    /// Part 3 的示例题刻意用了用户翻车当天那张卡：它同时带着诱导性的 `Describe` 开头
    /// **和**一个斜杠，所以 `coach prompt --part 3` 打出来的主题行正好就是要验的东西。
    func testTheSamplePart3QuestionIsTheOneThatActuallyBrokeOnTheLearnersMachine() {
        let question = PromptPreview.sampleQuestion(for: .part3)
        XCTAssertEqual(question.prompt, "Describe a shop/store you enjoy visiting")

        let text = ExaminerPrompt.build(setup: PromptPreview.setup(focusPart: .part3))
        XCTAssertTrue(text.contains("Part 3 theme: a shop or store you enjoy visiting"),
                      "示例题打出来的主题行不是用户要的那一行：\n\(text)")
        XCTAssertFalse(text.contains("Describe a shop/store you enjoy visiting"),
                       "示例题的原句还留在提示词里：\n\(text)")
    }

    /// 出 cue card 的那几档，示例题必须真的是一张 Part 2 的卡（带提示点）。
    func testTheSampleQuestionForEveryCueCardModeIsARealCueCard() {
        for part in [FocusPart.part2, .part2And3, .fullMock] {
            let question = PromptPreview.sampleQuestion(for: part)
            XCTAssertEqual(question.part, 2, "\(part) 的示例题不是 Part 2 的题")
            XCTAssertFalse(question.followups.isEmpty,
                           "\(part) 的示例 cue card 没有 You should say 的提示点")
        }
    }

    // MARK: - 组装

    /// **时长必须走 `FocusPart.defaultDurationMinutes`。**
    ///
    /// 在这里另写一份数字的话，命令行打出来的提示词和真练时发出去的那一份会在时长上
    /// 悄悄不一样——而这个命令存在的全部意义就是「看到的就是发出去的」。
    func testDurationComesFromTheFocusPartItselfSoThePreviewMatchesTheRealSession() {
        for part in FocusPart.allCases {
            XCTAssertEqual(PromptPreview.setup(focusPart: part).durationMinutes,
                           part.defaultDurationMinutes, "\(part) 的时长和真练时对不上")
        }
    }

    /// 给了题就用给的那道，不许悄悄换成示例题。
    func testUsesTheSuppliedQuestionInsteadOfTheSampleWhenOneIsGiven() {
        let mine = Question(id: "p3-mine", part: 3, topic: "Describe a law you know about",
                            prompt: "Describe a law you know about")
        let setup = PromptPreview.setup(focusPart: .part3, question: mine)
        XCTAssertEqual(setup.question.id, "p3-mine")
        XCTAssertTrue(ExaminerPrompt.build(setup: setup)
            .contains("Part 3 theme: a law you know about"))
    }

    /// 反馈时机与 Part 2 那一分钟的偏好都要穿过去，否则用户看到的和他设置的不是一回事。
    func testThreadsFeedbackTimingAndPrepModeThroughToThePrompt() {
        let immediate = ExaminerPrompt.build(
            setup: PromptPreview.setup(focusPart: .part2, feedbackTiming: .immediate))
        XCTAssertTrue(immediate.contains("After each answer"))

        let selfPaced = ExaminerPrompt.build(
            setup: PromptPreview.setup(focusPart: .part2, part2PrepMode: .learnerControlled))
        XCTAssertTrue(selfPaced.contains("say \"I'm ready\""))
        XCTAssertFalse(selfPaced.contains("Announce one minute of preparation"))
    }

    /// 五档都要能打出一份完整的提示词——这个命令的用途就是「五份各读一遍」。
    func testEveryModeRendersACompletePrompt() {
        for part in FocusPart.allCases {
            let text = ExaminerPrompt.build(setup: PromptPreview.setup(focusPart: part))
            XCTAssertTrue(text.contains("I will act as the examiner."), "\(part) 缺开场白")
            XCTAssertTrue(text.contains("Section rules"), "\(part) 缺 section rules")
            XCTAssertTrue(text.contains("The simulation is complete."), "\(part) 缺收尾指令")
        }
    }
}
