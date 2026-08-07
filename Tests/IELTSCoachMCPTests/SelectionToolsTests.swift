import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class SelectionToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        opener = FakeDashboardOpener()
        harness = ServerHarness(environment: makeEnvironment(directory: directory, opener: opener))
        try StateStore(directory: directory).mutate { state in
            state.questions = [
                Question(id: "p1-home", part: 1, topic: "Home",
                         prompt: "Do you live in a house or a flat?"),
                Question(id: "p2-skill", part: 2, topic: "Skills",
                         prompt: "Describe a useful skill you learned.",
                         followups: ["what it is", "how you learned it"])
            ]
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - set_training_selection

    func testSelectionIsWrittenIntoCurrentSession() throws {
        let payload = try harness.callToolJSON("set_training_selection", [
            "questionId": .string("p2-skill"),
            "goal": .string("回答后补一个原因和例子")
        ])
        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        XCTAssertEqual(payload["focusPart"]?.stringValue, "Part 2", "没传 focusPart 时按题目自身的 part 推断")

        let session = try XCTUnwrap(StateStore(directory: directory).load().currentSession)
        XCTAssertEqual(session.questionId, "p2-skill")
        XCTAssertEqual(session.focusPart, .part2)
        XCTAssertEqual(session.goal, "回答后补一个原因和例子")
        XCTAssertEqual(session.endedAt, "", "刚选完题，练习还没结束")
        XCTAssertEqual(session.reportPath, "")
    }

    func testFocusPartCanBeOverriddenForFullMock() throws {
        let payload = try harness.callToolJSON("set_training_selection", [
            "questionId": .string("p1-home"),
            "focusPart": .string("full mock")
        ])
        XCTAssertEqual(payload["focusPart"]?.stringValue, "full mock")
        XCTAssertEqual(try StateStore(directory: directory).load().currentSession?.focusPart, .fullMock)
    }

    func testUnknownQuestionIsRejectedAndNothingIsWritten() throws {
        let result = try harness.callTool("set_training_selection", ["questionId": .string("不存在")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("不存在"))
        XCTAssertTrue(result.text.contains("下一步"))
        XCTAssertNil(try StateStore(directory: directory).load().currentSession,
                     "选题失败时不能留下半个选择——下一次 get_training_context 会拿它去练")
    }

    func testMissingQuestionIdIsRejectedWithInstructions() throws {
        let result = try harness.callTool("set_training_selection")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("questionId"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testUnknownFocusPartIsRejectedWithTheAllowedValues() throws {
        let result = try harness.callTool("set_training_selection", [
            "questionId": .string("p1-home"), "focusPart": .string("Part 9")
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Part 1"))
        XCTAssertTrue(result.text.contains("full mock"))
    }

    // MARK: - get_training_context

    func testBuildsExaminerPromptFromTheSelectedQuestion() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p2-skill")])
        let payload = try harness.callToolJSON("get_training_context")

        XCTAssertEqual(payload["question"]?["id"]?.stringValue, "p2-skill")
        XCTAssertEqual(payload["durationMinutes"]?.intValue, 4, "Part 2 默认 4 分钟，与 coach practice 一致")
        XCTAssertEqual(payload["feedbackTiming"]?.stringValue, "deferred")
        XCTAssertEqual(payload["part2PrepMode"]?.stringValue, "countdown")

        let prompt = try XCTUnwrap(payload["examinerPrompt"]?.stringValue)
        // 提示词必须是 ExaminerPrompt 生成的那一份，不是 MCP 层自己拼的。
        // 这三条分别来自契约段、题目段、Part 2 规则段。
        XCTAssertTrue(prompt.contains("You will act as an IELTS Speaking examiner."))
        XCTAssertTrue(prompt.contains("Describe a useful skill you learned."))
        XCTAssertTrue(prompt.contains("Section rules (Part 2)"))
        XCTAssertTrue(prompt.contains("how you learned it"), "followups 要一起进提示词")
    }

    func testDefaultDurationForNonPart2IsSixMinutes() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")
        XCTAssertEqual(payload["durationMinutes"]?.intValue, 6)
    }

    func testImmediateFeedbackChangesTheContract() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context",
                                               ["feedbackTiming": .string("immediate")])
        let prompt = try XCTUnwrap(payload["examinerPrompt"]?.stringValue)
        XCTAssertTrue(prompt.contains("ONE short correction"))
        XCTAssertFalse(prompt.contains("I will save all feedback until the end"),
                       "immediate 模式下开场白也要跟着换，不能只换反馈规则")
    }

    func testReviewRequestPromptIsIncludedAndCarriesAMatchingMarker() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")
        let requestID = try XCTUnwrap(payload["reviewRequestId"]?.stringValue)
        let reviewPrompt = try XCTUnwrap(payload["reviewRequestPrompt"]?.stringValue)
        XCTAssertTrue(reviewPrompt.contains("<<<IELTS_REVIEW_JSON:\(requestID)>>>"))
        XCTAssertTrue(reviewPrompt.contains("vocabulary 必须是数组"),
                      "复盘指令必须是 ReviewRequestPrompt 那一份——它把每条内部的字段名都写死了（spec 2.3.8）")
    }

    func testTheSameSelectionAlwaysYieldsTheSameReviewRequestId() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let first = try harness.callToolJSON("get_training_context")["reviewRequestId"]?.stringValue
        let second = try harness.callToolJSON("get_training_context")["reviewRequestId"]?.stringValue
        XCTAssertEqual(first, second, "同一场练习问两次上下文，标记必须一致，否则复盘对不上号")
    }

    func testWithoutASelectionItSaysWhatToDoNext() throws {
        let result = try harness.callTool("get_training_context")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("set_training_selection"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testSelectedQuestionDisappearingFromTheBankIsExplained() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        try StateStore(directory: directory).mutate { $0.questions = [] }   // 模拟换季重新导入
        let result = try harness.callTool("get_training_context")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("p1-home"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testOutOfRangeDurationIsRejected() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let result = try harness.callTool("get_training_context", ["durationMinutes": .number(0)])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testContextCarriesActiveTargetsAndRecurringIssues() throws {
        try StateStore(directory: directory).mutate { state in
            // sourceSessionIds 必须真有 4 条：IssueRecord 的解码器把非空档案的
            // occurrences 一律算回 sourceSessionIds.count（Records.swift 第 82 行，
            // 专门修老档案里虚高的次数）。写 occurrences: 4 + 一条 sourceSessionId，
            // 读回来就是 1，测的是解码器而不是这个工具。
            state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                        correction: "I really like it.", whyItMatters: "w",
                                        occurrences: 4, sourceSessionIds: ["s1", "s2", "s3", "s4"],
                                        lastSeenAt: "t")]
            state.targets = [
                RetrainingTarget(targetKey: "retired", label: "旧的", status: "retired",
                                 evidence: [], sourceSessionId: "s0", createdAt: "t"),
                RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                                 evidence: ["I very like it."], sourceSessionId: "s1", createdAt: "t")
            ]
        }
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")

        let targets = try XCTUnwrap(payload["activeTargets"]?.arrayValue)
        XCTAssertEqual(targets.compactMap { $0["id"]?.stringValue }, ["logic-explain"],
                       "已退休的目标不能出现在下一场练习的上下文里")
        let issues = try XCTUnwrap(payload["recurringIssues"]?.arrayValue)
        XCTAssertEqual(issues.first?["learnerSaid"]?.stringValue, "I very like it.")
        XCTAssertEqual(issues.first?["occurrences"]?.intValue, 4)
    }
}
