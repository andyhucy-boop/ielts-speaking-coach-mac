import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class SaveSessionReviewToolTests: XCTestCase {
    private var directory: DataDirectory!
    private var harness: ServerHarness!

    /// 一份结构完全正确的复盘，字段名与 ReviewRequestPrompt 规定的严格一致（spec 2.3.8）。
    private static let goodReview = """
    好的，这是你这次的复盘。

    <<<IELTS_REVIEW_JSON:sync-2026-08-06-001>>>
    {
      "summary": "整体流利度不错，细节偏少。",
      "must_correct": [
        {"learner_said": "I very like it.", "correction": "I really like it.",
         "why_it_matters": "very 不能直接修饰动词"}
      ],
      "natural_upgrades": [],
      "vocabulary": [
        {"basic": "good", "better": "rewarding", "collocation": "a rewarding experience",
         "priority": "high"}
      ],
      "habits": [],
      "logic_feedback": [],
      "answer_upgrades": [],
      "priority_target": {"id": "logic-explain", "label": "回答后补一个原因和例子",
                          "status": "new", "evidence": ["I just like it."]}
    }
    <<<END_IELTS_REVIEW_JSON:sync-2026-08-06-001>>>
    """

    /// 顶层键齐全、但每条内部的字段名是 ChatGPT 自己发挥的那一版（spec 2.3.8 实测记录）。
    /// 解析能过，归档一条都进不去——这正是最危险的形态。
    private static let wrongFieldNames = """
    <<<IELTS_REVIEW_JSON:x>>>
    {"must_correct": [{"issue": "very like", "examples": "I very like it.", "fix": "really"}],
     "vocabulary": [{"word": "good", "upgrade": "rewarding"}],
     "priority_target": {"id": "t1", "label": "L", "status": "new", "evidence": []}}
    <<<END_IELTS_REVIEW_JSON:x>>>
    """

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                             opener: FakeDashboardOpener()))
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "p1-home", part: 1, topic: "Home", prompt: "Q?")]
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func selectQuestion() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
    }

    func testArchivesEverythingAndClosesTheCurrentSession() throws {
        try selectQuestion()
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.goodReview)])

        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        XCTAssertEqual(payload["issuesAdded"]?.intValue, 1)
        XCTAssertEqual(payload["vocabularyAdded"]?.intValue, 1)
        XCTAssertEqual(payload["reportPath"]?.stringValue, "reports/2026-08-06-001.json")
        XCTAssertEqual(payload["skipped"]?.arrayValue?.count, 0)

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].learnerSaid, "I very like it.")
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.questions[0].status, "practiced", "练过的题要被标记")
        XCTAssertNil(state.currentSession, "存完复盘这一场就结束了，不能还挂在 currentSession 上")
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.sessions[0].id, "2026-08-06-001")
        XCTAssertEqual(state.sessions[0].reportPath, "reports/2026-08-06-001.json")
        XCTAssertFalse(state.sessions[0].endedAt.isEmpty)

        let reportFile = directory.reportsDirectory.appending(path: "2026-08-06-001.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportFile.path))
        let saved = try JSONValue.decode(from: String(contentsOf: reportFile, encoding: .utf8))
        XCTAssertEqual(saved["priority_target"]?["id"]?.stringValue, "logic-explain",
                       "reports/ 里存的必须是解析后的复盘本身")
    }

    func testKeepsTheRawTextWhenParsingFails() throws {
        try selectQuestion()
        let result = try harness.callTool("save_session_review",
                                          ["reviewText": .string("ChatGPT 这次答的完全不是复盘")])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))

        // 关键：原文必须已经落盘，而且路径要告诉用户。
        let pending = directory.pendingReviewsDirectory.appending(path: "2026-08-06-001.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path),
                      "解析失败也不能丢原文——用户练了一整场换来的就是它")
        XCTAssertEqual(try String(contentsOf: pending, encoding: .utf8), "ChatGPT 这次答的完全不是复盘")
        XCTAssertTrue(result.text.contains(pending.path), "错误信息里必须给出原文的路径")

        let state = try StateStore(directory: directory).load()
        XCTAssertTrue(state.issues.isEmpty)
        XCTAssertNotNil(state.currentSession, "没存成的话这一场还没结束，选择要留着")
    }

    func testReportsSilentlyEmptyArchivesInsteadOfClaimingSuccess() throws {
        try selectQuestion()
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.wrongFieldNames)])

        let skipped = try XCTUnwrap(payload["skipped"]?.arrayValue).compactMap(\.stringValue)
        XCTAssertEqual(Set(skipped), ["must_correct", "vocabulary"],
                       "顶层键存在却一条都没归进去，必须报出来（spec 2.3.8）")
        let warning = try XCTUnwrap(payload["warning"]?.stringValue)
        XCTAssertTrue(warning.contains("must_correct"))
        XCTAssertTrue(warning.contains("下一步"))
        XCTAssertTrue(warning.contains("reimport"), "要告诉用户这场练习还能补救，不必重练")
    }

    func testRejectsSessionIdThatCouldEscapeTheDataDirectory() throws {
        let result = try harness.callTool("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "sessionId": .string("../../escaped")
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))
        let escaped = directory.root.deletingLastPathComponent().appending(path: "escaped.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testEmptyReviewTextIsRejected() throws {
        let result = try harness.callTool("save_session_review", ["reviewText": .string("   ")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))

        // 断言必须能把「参数校验拦住了」与「落到下面 ReviewParser 才失败」分开：
        // 后者的文案是「没有返回可识别的标准复盘JSON」，既不含 reviewText 也不含「空」。
        // 只断言 isError + 「下一步」的话，把必填校验整个删掉这条测试照样是绿的。
        XCTAssertTrue(result.text.contains("reviewText"),
                      "要说清是哪个参数不对，否则和解析失败的报错分不开：\(result.text)")
        XCTAssertTrue(result.text.contains("空"),
                      "要说清这个参数是空的，而不是内容看不懂：\(result.text)")

        // 更要命的是：校验没拦住的话，一段纯空白会被当成复盘原文真的写进 pending-reviews，
        // 变成一个谁也导不进去的垃圾文件。
        let pending = directory.pendingReviewsDirectory.appending(path: "2026-08-06-001.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path),
                       "一段纯空白不该落盘成待处理的复盘")
    }

    func testExplicitQuestionIdThatContradictsTheCurrentSelectionIsRejected() throws {
        // 显式题号与当前选题对不上时，让谁赢都会造出互相矛盾的三份记录：
        // 归档按一道题推进计划、练习记录写着另一道题、返回负载报的是第三种说法。
        // 唯一诚实的做法是停下来问清楚（铁律 7）。
        try StateStore(directory: directory).mutate { state in
            state.questions.append(Question(id: "p3-work", part: 3, topic: "Work", prompt: "Q?"))
        }
        try selectQuestion()                                  // 选的是 p1-home

        let result = try harness.callTool("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "questionId": .string("p3-work")
        ])

        XCTAssertTrue(result.isError, "题号对不上不能当作成功")
        XCTAssertTrue(result.text.contains("p3-work"), "要说清传进来的是哪个：\(result.text)")
        XCTAssertTrue(result.text.contains("p1-home"), "也要说清在案的是哪个：\(result.text)")
        XCTAssertTrue(result.text.contains("下一步"))

        // 拦下来就什么都不能改：两道题谁被练过还没定，磁盘上更不能留下半份记录。
        let state = try StateStore(directory: directory).load()
        XCTAssertTrue(state.sessions.isEmpty, "没存成就不该留下练习记录")
        XCTAssertTrue(state.issues.isEmpty, "没存成就不该往错题本里并东西")
        XCTAssertEqual(state.questions.first(where: { $0.id == "p3-work" })?.status, "new",
                       "没被认定练过的题不许标记成 practiced")
        XCTAssertEqual(state.questions.first(where: { $0.id == "p1-home" })?.status, "new")
        XCTAssertEqual(state.currentSession?.questionId, "p1-home",
                       "选择要原样留着，用户改好参数就能直接重存")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.pendingReviewsDirectory.appending(path: "2026-08-06-001.txt").path),
                       "参数就不合法，不该先落盘再报错")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001.json").path))
    }

    func testNewRecordTakesItsFocusPartFromTheQuestionItself() throws {
        // 没走过 set_training_selection、但显式给了题号：这时会新建一条练习记录，
        // focusPart 只能从题库里的题推出来。它会进 state.sessions，
        // list_practice_history 与 get_dashboard_data 都照着它显示，记错就是全错。
        try StateStore(directory: directory).mutate { state in
            state.questions.append(Question(id: "p2-describe", part: 2, topic: "Describe", prompt: "Q?"))
        }
        let payload = try harness.callToolJSON("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "questionId": .string("p2-describe")
        ])
        XCTAssertEqual(payload["questionId"]?.stringValue, "p2-describe")

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.sessions[0].questionId, "p2-describe")
        XCTAssertEqual(state.sessions[0].focusPart, .part2,
                       "新建的记录要按题目自身的 part 定，不能一律记成全真模考")
    }

    func testWorksWithoutAnySelectionByGeneratingItsOwnSessionID() throws {
        // 没走过 set_training_selection 也要能存——用户可能是在 ChatGPT 里
        // 自己练完才想起来存档，不该因为少了一步就把复盘拒之门外。
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.goodReview)])
        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.issues.count, 1)
    }

    func testSavingTwiceForTheSameSessionDoesNotDuplicateTheSessionRow() throws {
        try selectQuestion()
        _ = try harness.callToolJSON("save_session_review", ["reviewText": .string(Self.goodReview)])
        _ = try harness.callToolJSON("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "sessionId": .string("2026-08-06-001")
        ])
        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.sessions.count, 1, "同一个 sessionId 存两次不能变成两条练习记录")
        XCTAssertEqual(state.sessions[0].questionId, "p1-home",
                       "第二次没传 questionId，已经在案的题号不能被清空")
    }
}
