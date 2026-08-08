import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 训练记录页要显示什么，全在这里钉死。
///
/// 这一层是纯数据变换（不碰文件、不碰界面），所以每一条都能问出「把逻辑挖空会不会变红」。
/// 三件事是这一层的命门，也是下面每一节分别守的：
///
/// 1. **一条记录都不许消失。** 时间解析不出来的（`sync-1785940167` 那种命令行时代的 id）
///    要归到「时间不详」而不是被 `continue` 掉——凭空消失会让用户以为练习记录丢了。
/// 2. **题目不在题库里要说出来。** 换季导入新题库后旧题会不在（成品标准第 12 条），
///    此时显示「已经不在题库里了（id：xxx）」，不是空白，更不是把整行跳过。
/// 3. **月份标题自己拼。** 用 `DateFormatter` 的本地化格式的话，标题会跟着用户的系统语言变，
///    这一层就再也没法写死断言了。
final class HistoryViewModelTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func session(_ id: String, startedAt: String, questionId: String = "q1",
                         part: FocusPart = .part1, turns: Int = 0,
                         reportPath: String = "", recordingPath: String = "") -> PracticeSession {
        PracticeSession(
            id: id, questionId: questionId, focusPart: part,
            startedAt: startedAt, endedAt: startedAt, goal: "",
            transcript: (0..<turns).map {
                PracticeSession.TranscriptTurn(role: $0 % 2 == 0 ? "assistant" : "user",
                                               text: "T\($0)", capturedAt: startedAt)
            },
            reportPath: reportPath, recordingPath: recordingPath)
    }

    private func state(_ sessions: [PracticeSession],
                       questions: [Question] = [Question(id: "q1", part: 1, topic: "Home",
                                                         prompt: "Do you live in a house or a flat?")])
        -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.questions = questions
        return value
    }

    // MARK: - 分组

    func testGroupsByMonthNewestFirst() {
        let model = HistoryViewModel(state: state([
            session("2026-07-30-001", startedAt: "2026-07-30T10:00:00Z"),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z"),
            session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.map(\.id), ["2026-08", "2026-07"])
        XCTAssertEqual(model.months[0].title, "2026 年 8 月")
        XCTAssertEqual(model.months[0].rows.count, 2)
        XCTAssertEqual(model.totalCount, 3)
    }

    func testRowsWithinAMonthAreNewestFirst() {
        let model = HistoryViewModel(state: state([
            session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z"),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months[0].rows.map(\.id), ["2026-08-06-001", "2026-08-01-001"])
    }

    /// 决策 1 之前的记录只有 ISO8601 形状的 id，且当时根本没往 sessions 里写过
    /// `startedAt`。这类记录必须照样能按月份归位，不能因为解析不出来就消失。
    ///
    /// 注意这一条走的是**从 id 整串按 ISO8601 解析**那条路（`2026-08-05T14:03:11Z`
    /// 本身就是个合法时间戳），**不是**日期前缀那条。下面那条才是前缀那条——
    /// 计划里只有这一条，而突变验证当场证明了它盖不住前缀解析：把前缀那一段整块删掉，
    /// 这一条照样绿。
    func testFallsBackToTheDatePrefixOfTheSessionIDWhenStartedAtIsMissing() {
        let model = HistoryViewModel(state: state([
            session("2026-08-05T14:03:11Z", startedAt: "")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.map(\.id), ["2026-08"])
        XCTAssertEqual(model.months[0].rows[0].dateText, "8 月 5 日")
    }

    /// **日期前缀那条路唯一的守卫。**
    ///
    /// 决策 1 之后的新式 id 是 `2026-08-06-001`，整串不是合法 ISO8601 时间戳，
    /// ISO8601 那两个 formatter 都认不出来。`startedAt` 再一空（练到一半被强杀、
    /// 或命令行那边落库时没写这个字段），能救这条记录的就只剩「取前 10 个字符按
    /// yyyy-MM-dd 解析」这一手。没有它，这条记录会掉进「时间不详」——
    /// 记录还在，但明明知道是哪天练的却显示不出来。
    ///
    /// 这一条是突变验证逼出来的：把 `moment(of:)` 里前缀那一段整块删掉（直接
    /// `return nil`），计划里原有的 11 条**一条都不红**。
    func testFallsBackToTheDatePrefixOfANewStyleSessionIDThatIsNotATimestamp() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.map(\.id), ["2026-08"],
                       "新式 id 加空 startedAt 掉进了「时间不详」，"
                           + "而 id 里明明写着是哪一天")
        XCTAssertEqual(model.months[0].rows[0].dateText, "8 月 6 日")
    }

    /// 连日期都解析不出来的记录（比如 `sync-1785940167`）也不许丢——
    /// 凭空消失会让用户以为练习记录没了。归到「时间不详」，排在最后。
    func testUnparseableRecordsGoToTheirOwnBucketAtTheEndInsteadOfVanishing() {
        let model = HistoryViewModel(state: state([
            session("sync-1785940167", startedAt: ""),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.count, 2)
        XCTAssertEqual(model.months.last?.title, "时间不详")
        XCTAssertEqual(model.months.last?.rows.map(\.id), ["sync-1785940167"])
        XCTAssertEqual(model.totalCount, 2, "一条都不能少")
    }

    func testGroupingUsesTheGivenTimeZone() {
        // UTC 的 7 月 31 日 17 点，在东八区已经是 8 月 1 日。
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let sessions = [session("2026-07-31-001", startedAt: "2026-07-31T17:00:00Z")]
        XCTAssertEqual(HistoryViewModel(state: state(sessions), timeZone: utc).months.map(\.id),
                       ["2026-07"])
        XCTAssertEqual(HistoryViewModel(state: state(sessions), timeZone: shanghai).months.map(\.id),
                       ["2026-08"])
    }

    // MARK: - 每一行显示什么

    func testARowShowsDatePartQuestionTurnCountAndReviewStatus() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", part: .part2,
                    turns: 12, reportPath: "reports/2026-08-06-001.json")
        ]), timeZone: utc)

        let row = model.months[0].rows[0]
        XCTAssertEqual(row.dateText, "8 月 6 日")
        XCTAssertEqual(row.partText, "Part 2")
        XCTAssertEqual(row.questionText, "Do you live in a house or a flat?")
        XCTAssertFalse(row.questionIsMissing)
        XCTAssertEqual(row.turnCountText, "12 条对话")
        XCTAssertEqual(row.reviewStatusText, "复盘已存档")
        XCTAssertTrue(row.hasReport)
        XCTAssertFalse(row.hasRecording)
    }

    func testNoReportIsSaidPlainlyRatherThanLeftBlank() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)
        XCTAssertEqual(model.months[0].rows[0].reviewStatusText, "没有复盘")
        XCTAssertFalse(model.months[0].rows[0].hasReport)
    }

    func testNoTranscriptIsSaidPlainlyRatherThanShowingZero() {
        // 「0 条对话」看起来像出了什么问题；「没有逐字稿」是在陈述事实。
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", turns: 0)
        ]), timeZone: utc)
        XCTAssertEqual(model.months[0].rows[0].turnCountText, "没有逐字稿")
    }

    /// 换季导入新题库后旧题可能不在了（成品标准第 12 条）。
    /// 那一行必须还在，而且要说清楚发生了什么。
    func testAQuestionThatIsNoLongerInTheBankIsSpelledOutNotHidden() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", questionId: "gone-001")
        ]), timeZone: utc)

        let row = model.months[0].rows[0]
        XCTAssertTrue(row.questionIsMissing)
        XCTAssertTrue(row.questionText.contains("gone-001"),
                      "要带上题目 id，用户才有办法自己去查")
        XCTAssertTrue(row.questionText.contains("题库"))
    }

    func testARecordingIsFlaggedSoPhase5CanHangThePlayerThere() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z",
                    recordingPath: "recordings/2026-08-06T10-00-00Z.m4a")
        ]), timeZone: utc)
        XCTAssertTrue(model.months[0].rows[0].hasRecording)
    }

    // MARK: - 空

    func testEmptyStateIsEmptyNotACrash() {
        let model = HistoryViewModel(state: state([]), timeZone: utc)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.months.isEmpty)
        XCTAssertEqual(model.totalCount, 0)
    }
}
