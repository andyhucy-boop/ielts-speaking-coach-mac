import XCTest
@testable import IELTSCoachCore

final class ReviewArchiverTests: XCTestCase {
    private let report = try! JSONValue.decode(from: """
    {"summary":"ok",
     "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                      "why_it_matters":"very 不能修饰动词"}],
     "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding experience",
                    "priority":"high"}],
     "answer_upgrades":[],
     "priority_target":{"id":"logic-explain-example","label":"补一个原因和例子",
                        "status":"new","evidence":["I just like it."]}}
    """)

    private func baseState() -> CoachState {
        var state = CoachState.empty()
        state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "P")]
        state.plan = try! PlanBuilder.build(questions: state.questions, lengthDays: 7,
                                            createdAt: "2026-08-04T00:00:00Z")
        return state
    }

    func testAddsNewIssue() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "2026-08-04-001", questionID: "q1",
                                           at: "2026-08-04T10:00:00Z").state
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].learnerSaid, "I very like it.")
        XCTAssertEqual(state.issues[0].occurrences, 1)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["2026-08-04-001"])
    }

    func testIncrementsOccurrenceForRepeatedIssue() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].occurrences, 2)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1", "s2"])
        XCTAssertEqual(state.issues[0].lastSeenAt, "t2")
    }

    /// **同一场练习的复盘归档两次，「出现次数」不许变成 2。**
    ///
    /// 这条路走得到：`markImported` 改名失败（`.imported` 那个名字被占）时归档已经做完、
    /// 文件却还在待处理列表里；用户手工去掉 `.imported` 后缀重来；界面那条路和
    /// `coach reimport` 各导一次。`occurrences` 是「这个毛病在变多还是变少」的全部依据，
    /// 虚高的后果不是显示错一个数——是用户以为老毛病越来越严重，而他其实正在变好。
    func testArchivingTheSameSessionTwiceDoesNotInflateOccurrences() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.issues[0].occurrences, 1, "同一场归档两次，出现次数被加了两遍")
        // 「最后一次见到」同样要幂等：s1 这一场发生在什么时候是固定的，
        // 第二次归档只是补录，不该把它说成刚刚才犯过。
        XCTAssertEqual(state.issues[0].lastSeenAt, "t1",
                       "重复归档同一场，把「最后一次见到」改成了补录的时刻")
    }

    /// 归档过一次之后，**新的一场**里再犯同一个错，该加的还是要加——
    /// 幂等不等于从此不再计数。没有这条的话，把 `occurrences += 1` 整段删掉
    /// （永远停在 1）也能让上面那条绿。
    func testANewSessionStillIncrementsOccurrences() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t3").state
        XCTAssertEqual(state.issues[0].occurrences, 2)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1", "s2"])
        XCTAssertEqual(state.issues[0].lastSeenAt, "t3")
    }

    /// 幂等的完整含义：同一份复盘归档第二次，整个 state 一个字节都不该变。
    /// 只盯着 `occurrences` 的话，别的字段偷偷变了照样看不出来。
    func testArchivingTheSameReviewTwiceIsAWholeStateNoOp() {
        let once = ReviewArchiver.archive(report: report, into: baseState(),
                                          sessionID: "s1", questionID: "q1", at: "t1").state
        let twice = ReviewArchiver.archive(report: report, into: once,
                                           sessionID: "s1", questionID: "q1", at: "t2").state
        XCTAssertEqual(once, twice, "同一份复盘归档第二次改动了训练档案")
    }

    func testDoesNotDuplicateSessionIDWhenArchivedTwice() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        // 这条断言不能省：只查 sourceSessionIds 的话，即使归并逻辑退化成
        // 「每次都新增一条错题记录」，issues[0] 依然是第一条、依然只含 s1，测试照样绿。
        XCTAssertEqual(state.issues.count, 1, "同一 session 重复入库不应新增错题记录")
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1"])
        // 同理：词汇按 basicWord 去重、重训目标按 targetKey+sourceSessionId 去重，各自的
        // 守卫删掉后没有任何测试失败——只查内容不查数量的话，即使每次都新增一条重复记录，
        // vocabulary[0]/targets[0] 依然是第一条、内容不变，测试照样绿。
        XCTAssertEqual(state.vocabulary.count, 1, "同一 session 重复入库不应新增词汇记录")
        XCTAssertEqual(state.targets.count, 1, "同一 session 重复入库不应新增重训目标记录")
    }

    func testAddsVocabulary() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.vocabulary[0].basicWord, "good")
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding")
        XCTAssertEqual(state.vocabulary[0].priority, "high")
    }

    func testAppendsRetrainingTarget() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.targets[0].targetKey, "logic-explain-example")
        XCTAssertEqual(state.targets[0].sourceSessionId, "s1")
    }

    func testAdvancesPlanProgress() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.plan?.days[0].completedQuestionIds, ["q1"])
    }

    func testMarksQuestionPracticed() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.questions[0].status, "practiced")
    }

    func testHandlesReportWithNoIssuesOrVocabulary() {
        let sparse = try! JSONValue.decode(from: #"{"must_correct":[],"priority_target":{"id":"t1"}}"#)
        let outcome = ReviewArchiver.archive(report: sparse, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.state.issues.isEmpty)
        XCTAssertTrue(outcome.state.vocabulary.isEmpty)
        XCTAssertEqual(outcome.state.targets.count, 1)
        // must_correct 是空数组、vocabulary 键根本不存在：两者都不算「存在且非空但没归进去」，
        // 不应该报警——报警是留给「有内容却没归进去」这种真正可疑的情况。
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    // MARK: - skipped：归档 0 条时必须报警（spec 2.3.8 的直接现场）

    /// 真机实测到的故障现场：ChatGPT 把 must_correct 的字段名写成了
    /// issue/examples/fix，而不是 ReviewArchiver 读的 learner_said/correction/why_it_matters。
    /// 数组本身非空，但一条都识别不出来——这正是「归档 0 条不等于没错题」的典型样本。
    func testSkippedReportsMustCorrectWhenFieldNamesDoNotMatch() {
        let mismatched = try! JSONValue.decode(from: """
        {"summary":"ok",
         "must_correct":[{"issue":"filler words","examples":["um","like"],"fix":"pause instead"}],
         "priority_target":{"id":"t1"}}
        """)
        let outcome = ReviewArchiver.archive(report: mismatched, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.contains("must_correct"))
        XCTAssertTrue(outcome.state.issues.isEmpty, "字段名对不上时不应该凭空造出一条空白错题记录")
    }

    /// 同一类故障的 vocabulary 版本：真机实测里 ChatGPT 把 vocabulary 整体输出成了
    /// 一个对象（{"useful_replacements":...,"pronunciation":...}）而不是数组。
    func testSkippedReportsVocabularyWhenShapeIsWrong() {
        let wrongShape = try! JSONValue.decode(from: """
        {"summary":"ok",
         "vocabulary":{"useful_replacements":["rewarding"],"pronunciation":"n/a"},
         "priority_target":{"id":"t1"}}
        """)
        let outcome = ReviewArchiver.archive(report: wrongShape, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.contains("vocabulary"))
        XCTAssertTrue(outcome.state.vocabulary.isEmpty)
    }

    /// 反面对照：字段名正确时不应该报 skipped。
    func testSkippedIsEmptyWhenFieldNamesMatch() {
        let outcome = ReviewArchiver.archive(report: report, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.isEmpty)
        XCTAssertEqual(outcome.state.issues.count, 1)
        XCTAssertEqual(outcome.state.vocabulary.count, 1)
    }
}
