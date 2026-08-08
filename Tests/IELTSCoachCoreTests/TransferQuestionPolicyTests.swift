import XCTest
@testable import IELTSCoachCore

final class TransferQuestionPolicyTests: XCTestCase {
    private func question(_ id: String, part: Int, topic: String) -> Question {
        Question(id: id, part: part, topic: topic, prompt: "prompt-\(id)")
    }

    private func target(_ key: String = "k", session: String = "s0") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "补一个原因和例子", status: "new",
                         evidence: [], sourceSessionId: session, createdAt: "t")
    }

    private func session(_ id: String, question: String, link: RetrainingLink?) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private let original = Question(id: "p1-home-001", part: 1, topic: "Home",
                                    prompt: "Do you live in a house or a flat?")

    func testExcludesTheOriginalQuestion() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    /// Part 1 要短、Part 3 要展开，同一个目标在两者里的达成标准不一样。
    /// 跨 Part 换题验证的根本不是同一件事。
    func testNeverCrossesParts() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p2-trip-001", part: 2, topic: "Travel"),
                        question("p3-edu-001", part: 3, topic: "Education"),
                        question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    /// 换题验证的意义在于换语境。同话题的题目太接近原题，等于换汤不换药，
    /// 所以不同话题的必须排前面。
    func testDifferentTopicComesFirst() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-home-002", part: 1, topic: "Home"),
                        question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001", "p1-home-002"])
    }

    func testSameTopicIsKeptButMarked() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-home-002", part: 1, topic: "  home  ")],
            sessions: [])
        XCTAssertEqual(result.count, 1, "题库小的时候不能直接不给题，否则用户当场卡死")
        XCTAssertTrue(result[0].sameTopicAsOriginal, "大小写与空白不同不等于话题不同")
    }

    func testExcludesQuestionsAlreadyUsedForThisTarget() {
        let l = RetrainingLink(targetKey: "k", sourceSessionId: "s0",
                               originalQuestionId: "p1-home-001")
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-work-001", part: 1, topic: "Work"),
                        question("p1-food-001", part: 1, topic: "Food")],
            sessions: [session("s1", question: "p1-work-001", link: l)])
        XCTAssertEqual(result.map(\.id), ["p1-food-001"],
                       "同一个目标不该反复拿同一道题「验证」")
    }

    /// 另一个目标练过这道题，不影响这个目标——否则题库会被越练越空。
    func testDoesNotExcludeQuestionsUsedForAnotherTarget() {
        let other = RetrainingLink(targetKey: "another", sourceSessionId: "s0",
                                   originalQuestionId: "p1-home-001")
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-work-001", part: 1, topic: "Work")],
            sessions: [session("s1", question: "p1-work-001", link: other)])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    /// targetKey 跨 session 会重复（Records.swift 里白纸黑字写着）。只按 targetKey 排除，
    /// 另一份复盘里同名目标练过的题会被从这个目标的候选里剔掉，题库越练越空，
    /// 而界面上一点异常都看不出来。**计划里那条「按 targetID 匹配」的注释，
    /// 靠计划自带的两条测试都钉不住**（一条 key 相同、一条 key 不同，都区分不出两种写法）。
    func testDoesNotExcludeQuestionsUsedForASameKeyTargetFromAnotherReview() {
        let sameKeyOtherReview = RetrainingLink(targetKey: "k", sourceSessionId: "s-other",
                                                originalQuestionId: "p1-home-001")
        let result = TransferQuestionPolicy.candidates(
            for: target("k", session: "s0"), originalQuestion: original,
            questions: [original, question("p1-work-001", part: 1, topic: "Work")],
            sessions: [session("s1", question: "p1-work-001", link: sameKeyOtherReview)])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"],
                       "另一次复盘里同名目标练过的题，不该从这个目标的候选里消失")
    }

    func testKeepsBankOrderForTiedCandidates() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-work-001", part: 1, topic: "Work"),
                        question("p1-food-001", part: 1, topic: "Food"),
                        question("p1-sport-001", part: 1, topic: "Sport")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001", "p1-food-001", "p1-sport-001"],
                       "顺序必须稳定，否则同一页每次打开都换个样")
    }

    func testEmptyWhenTheBankHasNothingElseInThisPart() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p3-edu-001", part: 3, topic: "Education")],
            sessions: [])
        XCTAssertTrue(result.isEmpty, "返回空，由界面给「去导入更多题目」的空状态")
    }
}
