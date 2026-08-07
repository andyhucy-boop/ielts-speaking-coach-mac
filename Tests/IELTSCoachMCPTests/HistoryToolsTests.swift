import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class HistoryToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                             opener: FakeDashboardOpener()))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, question: String, startedAt: String,
                         reportPath: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: "", transcript: [],
                        reportPath: reportPath, recordingPath: "")
    }

    // MARK: - list_practice_history

    func testEmptyHistoryExplainsHowToGetStarted() throws {
        let payload = try harness.callToolJSON("list_practice_history")
        XCTAssertEqual(payload["total"]?.intValue, 0)
        XCTAssertEqual(payload["sessions"]?.arrayValue?.count, 0)
        XCTAssertTrue((payload["note"]?.stringValue ?? "").contains("下一步"),
                      "空列表不能只回一个 0——用户不知道该干什么")
    }

    func testNewestFirstAndLimitApplies() throws {
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "Q1?")]
            state.sessions = [
                session("2026-08-01-001", question: "q1", startedAt: "2026-08-01T10:00:00Z"),
                session("2026-08-06-001", question: "q1", startedAt: "2026-08-06T10:00:00Z"),
                session("2026-08-03-001", question: "q1", startedAt: "2026-08-03T10:00:00Z")
            ]
        }
        let payload = try harness.callToolJSON("list_practice_history", ["limit": .number(2)])
        XCTAssertEqual(payload["total"]?.intValue, 3, "total 是全量，不是这次返回的条数")
        XCTAssertEqual(payload["returned"]?.intValue, 2)
        XCTAssertEqual(payload["sessions"]?.arrayValue?.compactMap { $0["sessionId"]?.stringValue },
                       ["2026-08-06-001", "2026-08-03-001"])
    }

    func testRowsCarryTheQuestionTextAndReportFlag() throws {
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 2, topic: "Skills", prompt: "Describe a skill.")]
            state.sessions = [session("2026-08-06-001", question: "q1",
                                      startedAt: "2026-08-06T10:00:00Z",
                                      reportPath: "reports/2026-08-06-001.json")]
        }
        let row = try XCTUnwrap(try harness.callToolJSON("list_practice_history")["sessions"]?
            .arrayValue?.first)
        XCTAssertEqual(row["questionPrompt"]?.stringValue, "Describe a skill.")
        XCTAssertEqual(row["topic"]?.stringValue, "Skills")
        XCTAssertEqual(row["part"]?.intValue, 2)
        XCTAssertEqual(row["hasReport"], JSONValue.bool(true))
        XCTAssertEqual(row["questionMissing"], JSONValue.bool(false))
        XCTAssertEqual(row["transcriptTurns"]?.intValue, 0, "逐字稿是 Phase 4 的事，现在如实报 0")
    }

    func testDeletedQuestionIsMarkedInsteadOfSilentlyBlank() throws {
        // 换季重新导入题库后，旧记录指向的题可能已经不在了。
        // 显示成空白会让用户以为记录坏了，必须明确标出来。
        try StateStore(directory: directory).mutate { state in
            state.sessions = [session("2026-08-06-001", question: "已经没了",
                                      startedAt: "2026-08-06T10:00:00Z")]
        }
        let row = try XCTUnwrap(try harness.callToolJSON("list_practice_history")["sessions"]?
            .arrayValue?.first)
        XCTAssertEqual(row["questionMissing"], JSONValue.bool(true))
        XCTAssertEqual(row["questionId"]?.stringValue, "已经没了")
    }

    func testOutOfRangeLimitIsRejectedInsteadOfClamped() throws {
        for bad in [JSONValue.number(0), .number(9999), .number(2.5), .string("10")] {
            let result = try harness.callTool("list_practice_history", ["limit": bad])
            XCTAssertTrue(result.isError, "limit=\(bad) 本该被拒绝")
            XCTAssertTrue(result.text.contains("下一步"))
        }
    }

    // MARK: - get_dashboard_data

    func testDashboardReportsCountsPlanAndTargets() throws {
        try StateStore(directory: directory).mutate { state in
            let questions = (1...14).map {
                Question(id: "q\($0)", part: 1, topic: "T", prompt: "P\($0)")
            }
            state.questions = questions
            state.plan = try! PlanBuilder.build(questions: questions, lengthDays: 7,
                                                createdAt: "2026-08-01T00:00:00Z")
            state.sessions = [session("2026-08-05-001", question: "q1",
                                      startedAt: "2026-08-05T12:00:00Z")]
            // occurrences 恒等于 sourceSessionIds.count（IssueRecord 在读盘时会算回来），
            // 所以想让这条错题「出现过 3 次」，就必须给三个不同的来源场次。
            state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                        correction: "I really like it.", whyItMatters: "w",
                                        occurrences: 3, sourceSessionIds: ["s1", "s2", "s3"],
                                        lastSeenAt: "t")]
            state.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good",
                                                 betterExpression: "rewarding", collocation: "c",
                                                 priority: "high", sourceSessionIds: ["s"])]
            state.targets = [RetrainingTarget(targetKey: "logic-explain", label: "补例子",
                                              status: "new", evidence: ["I very like it."],
                                              sourceSessionId: "s", createdAt: "t")]
        }

        let payload = try harness.callToolJSON("get_dashboard_data")
        XCTAssertEqual(payload["questionTotal"]?.intValue, 14)
        XCTAssertEqual(payload["sessionTotal"]?.intValue, 1)
        XCTAssertEqual(payload["weekDone"]?.intValue, 1, "环境固定在 2026-08-06，这条属于同一周")
        XCTAssertEqual(payload["weekGoal"]?.intValue, 5)
        XCTAssertEqual(payload["issueTotal"]?.intValue, 1)
        XCTAssertEqual(payload["vocabularyTotal"]?.intValue, 1)
        XCTAssertEqual(payload["plan"]?["currentDay"]?.intValue, 1)
        XCTAssertEqual(payload["plan"]?["lengthDays"]?.intValue, 7)
        XCTAssertEqual(payload["todayQuestions"]?.arrayValue?.count, 2, "14 题分 7 天，每天 2 题")
        XCTAssertEqual(payload["todayQuestions"]?.arrayValue?.first?["prompt"]?.stringValue, "P1",
                       "计划里存的是题号，返回给模型的必须是能读的题干")
        XCTAssertEqual(payload["nextTargets"]?.arrayValue?.first?["label"]?.stringValue, "补例子")
        XCTAssertEqual(payload["topIssues"]?.arrayValue?.first?["occurrences"]?.intValue, 3)
    }

    func testDashboardOnAnEmptyWorkspaceTellsTheUserWhatToDoNext() throws {
        let payload = try harness.callToolJSON("get_dashboard_data")
        XCTAssertEqual(payload["questionTotal"]?.intValue, 0)
        XCTAssertEqual(payload["plan"], JSONValue.null)
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("下一步"))
        XCTAssertTrue(note.contains("题库"), "题库空是最需要先解决的事，note 要点出来")
    }

    func testFinishedPlanReportsCurrentDayAsNullInsteadOfDroppingTheKey() throws {
        // 计划全部做完时 currentDay 没有值。Swift 合成的编码器会让这个键整个消失，
        // 于是「计划做完了」和「工具忘了返回这个字段」在负载上长得一模一样，
        // 模型分不出来——键必须还在，值是 null。
        try StateStore(directory: directory).mutate { state in
            let questions = (1...7).map {
                Question(id: "q\($0)", part: 1, topic: "T", prompt: "P\($0)")
            }
            state.questions = questions
            var plan = try! PlanBuilder.build(questions: questions, lengthDays: 7,
                                              createdAt: "2026-08-01T00:00:00Z")
            for question in questions {
                plan = PlanBuilder.markCompleted(plan: plan, questionID: question.id)
            }
            state.plan = plan
        }
        let plan = try XCTUnwrap(try harness.callToolJSON("get_dashboard_data")["plan"])
        XCTAssertEqual(plan["completedDays"]?.intValue, 7)
        XCTAssertEqual(plan["currentDay"], JSONValue.null, "键不许消失，值是 null")
    }

    func testDashboardTakesNoArgumentsAndIgnoresNone() throws {
        // 无参工具最容易被写成「随便传什么都当没看见」。这里确认它至少能被正常调用。
        XCTAssertNoThrow(try harness.callToolJSON("get_dashboard_data"))
    }

    func testSessionsWithNoReadableTimeAreCountedAndExplained() throws {
        // 「本周训练 N/5」少算了一次却一个字都不提，用户没有任何办法发现（铁律 7）。
        // App 首页在四格里说了这件事，Codex 这边必须说同一件事。
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 1, topic: "T", prompt: "P1")]
            state.sessions = [
                session("2026-08-05-001", question: "q1", startedAt: "2026-08-05T12:00:00Z"),
                session("no-date-001", question: "q1", startedAt: "")
            ]
        }
        let payload = try harness.callToolJSON("get_dashboard_data")
        XCTAssertEqual(payload["undatedSessionCount"]?.intValue, 1)
        XCTAssertEqual(payload["sessionTotal"]?.intValue, 2, "读不出时间也仍然是一场练习")
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("读不出"), "数字算少了却一个字不提，就是静默失败")
        XCTAssertTrue(note.contains("下一步"), "只说算少了、不说怎么补，用户照样做不了什么")
    }
}
