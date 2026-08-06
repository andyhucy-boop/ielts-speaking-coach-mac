import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingSetupBuilderTests: XCTestCase {
    private func target(label: String, key: String = "logic-explain") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: label, status: "new", evidence: [],
                         sourceSessionId: "s0", createdAt: "t")
    }

    private func question(_ id: String, part: Int) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "prompt-\(id)")
    }

    /// 复训会话的定义就在这一条上：考官提示词必须带上单点目标。
    func testRetrainingPromptCarriesTheSinglePointGoal() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "回答后补一个原因和例子"),
                                                     question: question("q1", part: 1))
        let prompt = ExaminerPrompt.build(setup: setup)
        XCTAssertTrue(prompt.contains("本次唯一目标：回答后补一个原因和例子"),
                      "没带上目标，这场就只是普通练习")
    }

    /// 目标是给考官看的，不是给学员听的。**考官一旦在考试过程中把它念出来，
    /// 等于提前把答案告诉学员**，这场复训就测不出「是真会了还是被提示了」。
    /// 这条守着 `ExaminerPrompt` 里那句禁令不被人顺手删掉。
    func testExaminerIsToldNotToSayTheGoalOutLoudDuringTheExam() {
        let prompt = ExaminerPrompt.build(
            setup: RetrainingSetupBuilder.makeSetup(target: target(label: "回答后补一个原因和例子"),
                                                    question: question("q1", part: 1)))
        XCTAssertTrue(prompt.contains("考试过程中不要提及这个目标"),
                      "考官会把目标念出来，等于提前告诉考生答案")
    }

    /// 对照组：普通练习的提示词里不该有目标段落。
    /// 两条一起看，才证明「区分」是真的存在，而不是两边都一样。
    func testPlainPracticePromptHasNoGoalBlock() {
        let plain = SessionSetup(question: question("q1", part: 1), focusPart: .part1,
                                 durationMinutes: 6, goal: "")
        XCTAssertFalse(ExaminerPrompt.build(setup: plain).contains("本次唯一目标"))
    }

    /// `RetrainingPolicy.extractTarget` 允许 label 为空（它只强制 id 非空）。
    /// label 一空，goal 就是空串，这场复训会**静默退化成普通练习**——
    /// 不报错、界面照常、只是这一场和复训毫无关系。
    func testEmptyLabelFallsBackToTargetKeySoTheGoalIsNeverBlank() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "   ", key: "logic-explain"),
                                                     question: question("q1", part: 1))
        XCTAssertEqual(setup.goal, "logic-explain")
        XCTAssertTrue(ExaminerPrompt.build(setup: setup).contains("本次唯一目标：logic-explain"))
    }

    func testGoalIsTrimmed() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "  补一个例子\n"),
                                                     question: question("q1", part: 1))
        XCTAssertEqual(setup.goal, "补一个例子")
    }

    func testFocusPartFollowsTheQuestionPart() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q1", part: 1)).focusPart,
                       .part1)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q2", part: 2)).focusPart,
                       .part2)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q3", part: 3)).focusPart,
                       .part3)
    }

    /// 题库里出现越界的 part（导入时可能有脏数据）不能让复训直接崩，
    /// 落到 full mock 是 FocusPart 里唯一的兜底取值。
    func testOutOfRangePartFallsBackToFullMock() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q9", part: 9)).focusPart,
                       .fullMock)
    }

    /// Part 2 是一段长答，时长与其他 Part 不同。与 coach practice 的既有取值保持一致。
    func testPart2GetsAShorterTargetLength() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q2", part: 2)).durationMinutes, 4)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q1", part: 1)).durationMinutes, 6)
    }

    func testCarriesTheChosenPracticeModes() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                     question: question("q2", part: 2),
                                                     feedbackTiming: .immediate,
                                                     part2PrepMode: .learnerControlled)
        XCTAssertEqual(setup.feedbackTiming, .immediate)
        XCTAssertEqual(setup.part2PrepMode, .learnerControlled)
    }
}
