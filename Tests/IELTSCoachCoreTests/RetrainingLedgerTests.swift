import XCTest
@testable import IELTSCoachCore

final class RetrainingLedgerTests: XCTestCase {
    private func target(_ key: String, session: String, status: String = "new") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "补一个原因和例子", status: status,
                         evidence: ["I just like it."], sourceSessionId: session,
                         createdAt: "2026-08-05T10:00:00Z")
    }

    private func session(_ id: String, question: String,
                         link: RetrainingLink? = nil) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private func link(_ key: String, source: String, original: String) -> RetrainingLink {
        RetrainingLink(targetKey: key, sourceSessionId: source, originalQuestionId: original)
    }

    // MARK: - progress

    /// 用例里必须同时有「没挂钩的普通练习」和「挂在别的目标上的复训会话」：
    /// 只放普通练习的话，它们的 retrainingKind 恒为 nil，progress 怎么写都是空数组，
    /// 这条测试就一点约束力都没有（本项目消灭空转测试的老账）。
    func testProgressIsNotStartedWhenNothingIsLinkedToThisTarget() {
        let othersLink = link("k2", source: "s0", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1"),                   // 普通练习，没挂钩
                       session("s2", question: "q2"),                   // 普通练习，没挂钩
                       session("s3", question: "q1", link: othersLink), // 别的目标的原题重答
                       session("s4", question: "q9", link: othersLink)])// 别的目标的换题验证
        XCTAssertEqual(progress.targetID, "k@s0",
                       "进度必须自报是哪个目标的，否则界面拿它对号入座时会串台")
        XCTAssertEqual(progress.stage, .notStarted)
        XCTAssertTrue(progress.originalRetrySessionIDs.isEmpty,
                      "没挂钩的普通练习、以及挂在别的目标上的复训，都不算这个目标的进度")
        XCTAssertTrue(progress.transferSessionIDs.isEmpty,
                      "没挂钩的普通练习、以及挂在别的目标上的复训，都不算这个目标的进度")
    }

    func testProgressSeparatesOriginalRetriesFromTransfers() {
        let l = link("k", source: "s0", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1", link: l),      // 重答原题
                       session("s2", question: "q9", link: l),      // 换题验证
                       session("s3", question: "q1", link: l)])     // 又重答一次原题
        XCTAssertEqual(progress.originalRetrySessionIDs, ["s1", "s3"])
        XCTAssertEqual(progress.transferSessionIDs, ["s2"])
        XCTAssertEqual(progress.stage, .triedTransfer)
    }

    func testStageIsRetriedOriginalUntilAQuestionIsSwapped() {
        let l = link("k", source: "s0", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1", link: l)])
        XCTAssertEqual(progress.stage, .retriedOriginal,
                       "只重练了原题就说「验证过了」，正是这个产品要防的事")
    }

    /// targetKey 跨 session 会重复。只按 key 匹配，两个不同复盘里同名的目标会串台，
    /// 用户会看到「已换题验证」而其实验证的是另一个目标。
    func testProgressMatchesFullIdentityNotJustTargetKey() {
        let mine = link("k", source: "s0", original: "q1")
        let someoneElses = link("k", source: "s-other", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q9", link: someoneElses)])
        XCTAssertTrue(progress.transferSessionIDs.isEmpty,
                      "别的复盘里同名目标的复训会话，不能算进这个目标的进度")
        XCTAssertEqual(RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q9", link: mine)]).transferSessionIDs, ["s1"])
    }

    // MARK: - attach

    func testAttachWritesTheLinkOntoTheSession() {
        var state = CoachState.empty()
        state.sessions = [session("s1", question: "q9")]
        let l = link("k", source: "s0", original: "q1")
        XCTAssertTrue(RetrainingLedger.attach(l, toSessionWithID: "s1", in: &state))
        XCTAssertEqual(state.sessions[0].retraining, l)
        XCTAssertEqual(state.sessions[0].retrainingKind, .transfer)
    }

    /// 挂不上必须能被调用方发现。静默返回成功，用户会看到「复训已记录」，
    /// 而台账里其实什么都没有——本项目已知最危险的失败形态。
    func testAttachReportsFailureWhenTheSessionIsNotThere() {
        var state = CoachState.empty()
        state.sessions = [session("s1", question: "q9")]
        XCTAssertFalse(RetrainingLedger.attach(link("k", source: "s0", original: "q1"),
                                               toSessionWithID: "不存在的记录", in: &state))
        XCTAssertNil(state.sessions[0].retraining)
    }

    func testAttachDoesNotOverwriteALinkThatBelongsToAnotherTarget() {
        var state = CoachState.empty()
        let existing = link("k1", source: "s0", original: "q1")
        state.sessions = [session("s1", question: "q9", link: existing)]
        XCTAssertFalse(RetrainingLedger.attach(link("k2", source: "s0", original: "q1"),
                                               toSessionWithID: "s1", in: &state))
        XCTAssertEqual(state.sessions[0].retraining, existing, "已有的挂钩不许被覆盖")
    }

    func testAttachIsIdempotentForTheSameLink() {
        var state = CoachState.empty()
        let l = link("k", source: "s0", original: "q1")
        state.sessions = [session("s1", question: "q9", link: l)]
        XCTAssertTrue(RetrainingLedger.attach(l, toSessionWithID: "s1", in: &state),
                      "重复挂同一个 link 不算失败——重试路径上会发生")
    }

    // MARK: - setStatus

    func testSetStatusFlipsTheTarget() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        XCTAssertTrue(RetrainingLedger.setStatus(.selected, of: "k@s0", in: &state))
        XCTAssertEqual(state.targets[0].status, "selected")
        XCTAssertTrue(RetrainingLedger.setStatus(.retired, of: "k@s0", in: &state))
        XCTAssertEqual(state.targets[0].status, "retired")
    }

    /// 同名不同来源的两个目标，改一个不能连累另一个。
    func testSetStatusOnlyTouchesTheTargetWithTheMatchingFullIdentity() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0"), target("k", session: "s1")]
        XCTAssertTrue(RetrainingLedger.setStatus(.retired, of: "k@s1", in: &state))
        XCTAssertEqual(state.targets[0].status, "new")
        XCTAssertEqual(state.targets[1].status, "retired")
    }

    func testSetStatusReportsFailureForAnUnknownTarget() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        XCTAssertFalse(RetrainingLedger.setStatus(.retired, of: "k@不存在", in: &state))
        XCTAssertEqual(state.targets[0].status, "new")
    }

    /// 取消退休：`.new` 写进 status 的必须正好是 "new"。这一条钉的是 `.new` 的 rawValue——
    /// 它一旦拼错，status 会变成一个既不是 "retired" 也不是 "new" 的值，
    /// rank 不报错、照常把它排进推荐，用户看不出任何异常。属于禁止的静默失败。
    func testSetStatusBackToNewUnretiresTheTarget() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", status: "retired")]
        XCTAssertTrue(RetrainingLedger.setStatus(.new, of: "k@s0", in: &state))
        XCTAssertEqual(state.targets[0].status, "new")
        XCTAssertEqual(RetrainingPolicy.rank(targets: state.targets, issues: []).map(\.id),
                       ["k@s0"], "取消退休后必须真的回到推荐里")
    }

    /// 退休之后必须真的从推荐里消失——RetrainingPolicy.rank 认的就是这个字符串。
    func testRetiredTargetDropsOutOfRank() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        _ = RetrainingLedger.setStatus(.retired, of: "k@s0", in: &state)
        XCTAssertTrue(RetrainingPolicy.rank(targets: state.targets, issues: []).isEmpty)
    }
}
