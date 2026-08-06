import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingCenterViewModelTests: XCTestCase {
    private func target(_ key: String, session: String, evidence: [String],
                        status: String = "new") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "目标-\(key)", status: status,
                         evidence: evidence, sourceSessionId: session,
                         createdAt: "2026-08-0\(session.count)T10:00:00Z")
    }

    private func session(_ id: String, question: String,
                         link: RetrainingLink? = nil) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "reports/\(id).json",
                        recordingPath: "", retraining: link)
    }

    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "prompt-\(id)")
    }

    /// 排序是 RetrainingPolicy.rank 的职责，界面不许另排一套。
    func testPendingFollowsRetrainingPolicyRank() {
        var state = CoachState.empty()
        state.targets = [target("rare", session: "s1", evidence: ["I just like it."]),
                         target("common", session: "s2", evidence: ["I very like it."])]
        state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                    correction: "I really like it.", whyItMatters: "",
                                    occurrences: 5, sourceSessionIds: ["s2"], lastSeenAt: "t")]
        state.sessions = [session("s1", question: "q1"), session("s2", question: "q2")]
        state.questions = [question("q1"), question("q2")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.map(\.id), ["common@s2", "rare@s1"])
        XCTAssertEqual(vm.pending.map(\.target),
                       RetrainingPolicy.rank(targets: state.targets, issues: state.issues),
                       "顺序必须与 RetrainingPolicy.rank 完全一致")
    }

    func testRetiredTargetsLeavePendingButAreStillListed() {
        var state = CoachState.empty()
        state.targets = [target("live", session: "s1", evidence: []),
                         target("done", session: "s2", evidence: [], status: "retired")]
        state.sessions = [session("s1", question: "q1"), session("s2", question: "q2")]
        state.questions = [question("q1"), question("q2")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.map(\.id), ["live@s1"])
        XCTAssertEqual(vm.retired.map(\.id), ["done@s2"],
                       "退休的目标不能凭空消失——用户会以为记录丢了")
    }

    func testStatusLabelReflectsProgress() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: [])]
        let l = RetrainingLink(targetKey: "k", sourceSessionId: "s0", originalQuestionId: "q1")
        state.sessions = [session("s0", question: "q1"),
                          session("s1", question: "q1", link: l)]
        state.questions = [question("q1")]

        let onlyOriginal = RetrainingCenterViewModel(state: state)
        XCTAssertTrue(onlyOriginal.pending[0].statusLabel.contains("换题验证"),
                      "只重练了原题时，必须提醒还差换题验证——这是本产品的价值所在")

        state.sessions.append(session("s2", question: "q9", link: l))
        let withTransfer = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(withTransfer.pending[0].progress.stage, .triedTransfer)
        XCTAssertTrue(withTransfer.pending[0].statusLabel.contains("1"),
                      "换题验证做过几次要显示出来")
    }

    /// 计划里的八条测试没有一条走到 `.notStarted` 那个分支——把它改成空串仍然全绿。
    /// 列表里一行没有状态文字，用户只会以为界面坏了（DESIGN-SYSTEM 第 4 节：空白页会被当成程序坏了）。
    func testNotStartedTargetStillSaysWhereItStands() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: [])]
        state.sessions = [session("s0", question: "q1")]
        state.questions = [question("q1")]

        let item = RetrainingCenterViewModel(state: state).pending[0]
        XCTAssertEqual(item.progress.stage, .notStarted)
        XCTAssertFalse(item.statusLabel.isEmpty,
                       "一次都没练过的目标也要有状态文字，空白会被当成界面坏了")
        XCTAssertFalse(item.statusLabel.contains("已"),
                       "一次都没练过，不许说「已…」——那是在替用户宣称他练过")
    }

    /// 换季导入新题库后旧题可能不在了（DEFINITION-OF-DONE 硬标准第 12 条）。
    /// 这时必须说清楚，而不是让这一条从列表里消失。
    func testMissingSourceQuestionIsReportedNotHidden() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: ["I just like it."])]
        state.sessions = [session("s0", question: "已经不在题库里的题")]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.count, 1)
        XCTAssertEqual(vm.pending[0].sourceIssue, .questionMissing)
        XCTAssertNil(vm.pending[0].originalQuestion)
        XCTAssertFalse(vm.pending[0].canRetryOriginal)
        XCTAssertTrue(vm.pending[0].sourceIssue!.message.contains("下一步"))
    }

    func testMissingSourceSessionIsReportedNotHidden() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "被删掉的记录", evidence: [])]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.count, 1)
        XCTAssertEqual(vm.pending[0].sourceIssue, .sessionMissing)
        XCTAssertTrue(vm.pending[0].sourceIssue!.message.contains("下一步"))
    }

    func testHealthyItemCarriesTheOriginalQuestionAndNoIssue() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: [])]
        state.sessions = [session("s0", question: "q1")]
        state.questions = [question("q1")]

        let item = RetrainingCenterViewModel(state: state).pending[0]
        XCTAssertNil(item.sourceIssue)
        XCTAssertEqual(item.originalQuestion?.id, "q1")
        XCTAssertTrue(item.canRetryOriginal)
    }

    /// targetKey 跨 session 会重复。按 key 查会取到错的那一条，
    /// 用户点开 A 目标却看到 B 目标的证据。
    func testLookupUsesFullIdentityNotJustTargetKey() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: ["老的那句"]),
                         target("k", session: "s1", evidence: ["新的那句"])]
        state.sessions = [session("s0", question: "q1"), session("s1", question: "q1")]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.item(id: "k@s1")?.target.evidence, ["新的那句"])
        XCTAssertEqual(vm.item(id: "k@s0")?.target.evidence, ["老的那句"])
        XCTAssertNil(vm.item(id: "k@不存在"))
    }

    func testEmptyStateSaysWhatToDoNext() {
        let vm = RetrainingCenterViewModel(state: .empty())
        XCTAssertTrue(vm.pending.isEmpty)
        XCTAssertTrue(vm.emptyStateMessage.contains("下一步"))
    }
}
