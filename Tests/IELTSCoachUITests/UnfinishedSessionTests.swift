import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// **练到一半崩了 / 误关窗口 / Mac 重启**之后那一场去哪儿了。
///
/// 在这之前：一场练习在按下「我练完了」之前磁盘上一个字都没有，
/// 这半小时就等于没发生过——不进「本周 N/5」、计划不前进、题目不打「已练」，
/// 录音变成一个没人认领的孤儿文件。
@MainActor
final class UnfinishedSessionTests: XCTestCase {

    private func turn(_ text: String, at time: String) -> PracticeSession.TranscriptTurn {
        PracticeSession.TranscriptTurn(role: "user", text: text, capturedAt: time)
    }

    private func session(turns: [PracticeSession.TranscriptTurn]) -> PracticeSession {
        PracticeSession(id: "2026-08-20-001", questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-20T10:00:00Z", endedAt: "", goal: "",
                        transcript: turns, reportPath: "", recordingPath: "")
    }

    private func state(with session: PracticeSession?) -> CoachState {
        var state = CoachState.empty()
        state.questions = [Question(id: "q1", part: 1, topic: "Home",
                                    prompt: "Do you live in a house or a flat?")]
        state.currentSession = session
        return state
    }

    // MARK: - 什么时候值得问

    func testAnInterruptedSessionWithTranscriptIsOffered() {
        let interrupted = session(turns: [turn("I live in a flat.", at: "2026-08-20T10:03:00Z")])
        XCTAssertNotNil(UnfinishedSession.pending(in: state(with: interrupted)))
    }

    /// **一条什么都没采到的记录不值得问。** 开练几秒就崩了的那种，
    /// 用户点「存下来」得到的是一条空记录——比不问更让人困惑。
    func testASessionThatCapturedNothingIsNotOffered() {
        XCTAssertNil(UnfinishedSession.pending(in: state(with: session(turns: []))))
        XCTAssertNil(UnfinishedSession.pending(in: state(with: nil)))
    }

    // MARK: - 那张卡片说什么

    func testTheNoticeSaysWhatHappenedAndWhatBothButtonsDo() {
        let interrupted = session(turns: [turn("a", at: "2026-08-20T10:03:00Z"),
                                          turn("b", at: "2026-08-20T10:05:00Z")])
        let notice = UnfinishedSession.notice(for: interrupted, in: state(with: interrupted))
        XCTAssertTrue(notice.contains("2 条对话"), notice)
        XCTAssertTrue(notice.contains("Do you live in a house or a flat?"),
                      "没说练的是哪道题，用户认不出是哪一场：\(notice)")
        XCTAssertTrue(notice.contains("一个字没丢"),
                      "没说东西还在，那两颗按钮就没人敢按：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), notice)
        // 两颗按钮各自的后果都要说清——尤其「算进本周次数」这一条。
        XCTAssertTrue(notice.contains("本周次数"), notice)
    }

    // MARK: - 收下

    func testKeepingItMovesTheSessionIntoTheRealRecord() {
        let interrupted = session(turns: [turn("a", at: "2026-08-20T10:03:00Z")])
        var value = state(with: interrupted)
        UnfinishedSession.keep(interrupted, in: &value)

        XCTAssertEqual(value.sessions.map(\.id), ["2026-08-20-001"])
        XCTAssertNil(value.currentSession, "收下之后那个占位没清掉，下次开 App 会再问一遍")
    }

    /// **`endedAt` 用最后一次采到逐字稿的时间，不是现在。**
    ///
    /// 用现在的话，一场昨天崩掉的练习会被算成「从昨天练到今天」，
    /// 首页那个「本周开口时长」当场多出十几个小时——
    /// 那正是 `TrainingStats` 里「超过 2 小时按 2 小时计」在兜的坑，不该再往里扔一次。
    func testTheEndTimeComesFromTheLastCapturedTurnNotFromNow() {
        let interrupted = session(turns: [turn("a", at: "2026-08-20T10:03:00Z"),
                                          turn("b", at: "2026-08-20T10:12:00Z")])
        var value = state(with: interrupted)
        UnfinishedSession.keep(interrupted, in: &value)
        XCTAssertEqual(value.sessions.first?.endedAt, "2026-08-20T10:12:00Z")
    }

    /// 同一条被收两次时不许变成两条记录（连点两下那颗按钮）。
    func testKeepingItTwiceDoesNotDuplicateTheRecord() {
        let interrupted = session(turns: [turn("a", at: "2026-08-20T10:03:00Z")])
        var value = state(with: interrupted)
        UnfinishedSession.keep(interrupted, in: &value)
        value.currentSession = interrupted
        UnfinishedSession.keep(interrupted, in: &value)
        XCTAssertEqual(value.sessions.count, 1)
    }

    // MARK: - 丢掉

    /// 卡片上承诺「已经归进错题本和词汇本的内容不受影响」——那句话得是真的。
    func testDiscardingOnlyClearsThePlaceholder() {
        let interrupted = session(turns: [turn("a", at: "2026-08-20T10:03:00Z")])
        var value = state(with: interrupted)
        value.issues = [IssueRecord(id: "i1", learnerSaid: "a", correction: "b",
                                    whyItMatters: "c", occurrences: 1,
                                    sourceSessionIds: ["s0"], lastSeenAt: "t")]
        UnfinishedSession.discard(in: &value)

        XCTAssertNil(value.currentSession)
        XCTAssertTrue(value.sessions.isEmpty)
        XCTAssertEqual(value.issues.count, 1, "丢这一场把错题本也动了——卡片上那句承诺就成了假话")
    }
}
