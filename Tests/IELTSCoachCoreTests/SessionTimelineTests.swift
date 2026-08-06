import XCTest
@testable import IELTSCoachCore

final class SessionTimelineTests: XCTestCase {

    /// 第 day 天的第 seq 场练习。id 用 "YYYY-MM-DD-NNN" 这种文档形状。
    private func session(day: Int, seq: Int = 1, startedAt: String? = nil) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: sessionID(day: day, seq: seq), questionId: "q",
                               focusPart: .part1,
                               startedAt: startedAt ?? "\(stamp)T10:00:00Z",
                               endedAt: "\(stamp)T10:30:00Z", goal: "",
                               transcript: [], reportPath: "", recordingPath: "")
    }

    private func sessionID(day: Int, seq: Int = 1) -> String {
        String(format: "2026-07-%02d-%03d", day, seq)
    }

    private func issue(_ id: String, sessions: [String]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said", correction: "fix", whyItMatters: "why",
                    occurrences: sessions.count, sourceSessionIds: sessions,
                    lastSeenAt: "2026-07-10T10:00:00Z")
    }

    private func word(_ id: String, sessions: [String]) -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: "good", betterExpression: "remarkable",
                         collocation: "a remarkable improvement", priority: "high",
                         sourceSessionIds: sessions)
    }

    private func target(_ key: String, session: String) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "补一个例子", status: "new", evidence: [],
                         sourceSessionId: session, createdAt: "2026-07-10T10:00:00Z")
    }

    private func state(sessions: [PracticeSession], issues: [IssueRecord] = [],
                       vocabulary: [VocabularyRecord] = [],
                       targets: [RetrainingTarget] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.issues = issues
        value.vocabulary = vocabulary
        value.targets = targets
        return value
    }

    func testOrdersMostRecentFirst() {
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 3), session(day: 1), session(day: 2)]))
        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 3), sessionID(day: 2), sessionID(day: 1)])
    }

    func testFallsBackToDatePrefixOfTheIDWhenStartedAtIsEmpty() {
        // Phase 4 之前的数据、或写入时漏了 startedAt 的记录，
        // 不能因此被整条排除在趋势之外。
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 2, startedAt: ""), session(day: 1)]))
        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2), sessionID(day: 1)])
        XCTAssertTrue(timeline.undatedSessionIDs.isEmpty)
    }

    /// **复审补入。** 计划的 9 条测试里没有一条能分辨同刻场次的顺序，
    /// 把 `build` 的比较器换成不带 tie-break 的 `{ $0.value > $1.value }`，10 条依然全绿。
    ///
    /// 这里造的正是 `parseDayPrefix` 兜底分支要救的那种数据：同一天三场以上、
    /// `startedAt` 全为空，于是全部退回当天 00:00 UTC，`Date` 完全相同。
    /// 没有 tie-break 时排序结果就等于字典的遍历顺序，而 Swift 的 String 哈希每个进程
    /// 重新播种——同一份数据每次打开，落进「最近 5 场」和「之前 5 场」的场次会不一样，
    /// 趋势结论跟着翻转。用 6 场是为了让这条测试在突变下必红：
    /// 6 场同刻恰好排成倒序的概率是 1/720。
    func testSessionsAtTheSameInstantGetAStableOrder() {
        let timeline = SessionTimeline.build(state: state(
            sessions: (1...6).map { session(day: 2, seq: $0, startedAt: "") }))

        XCTAssertEqual(timeline.orderedSessionIDs,
                       (1...6).reversed().map { sessionID(day: 2, seq: $0) },
                       "同一时刻的场次必须按 id 倒序，排序不能由字典的遍历顺序决定")
    }

    func testIncludesIssueOnlySessionsAndReportsThemAsUnmatched() {
        // 错题档案引用了一场 state.sessions 里没有的练习：
        // 它确实练过，必须并入时间轴，否则「之前那批」会凭空少一场；
        // 但也必须报出来，否则用户在训练记录页看不到它却影响了趋势。
        let orphan = "2026-07-05T09:00:00Z"
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 9), session(day: 1)],
            issues: [issue("i1", sessions: [orphan])]))

        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 9), orphan, sessionID(day: 1)])
        XCTAssertEqual(timeline.unmatchedSessionIDs, [orphan])
    }

    /// **计划外补入（Phase 7 Task 2 实施时）。** 计划给的 9 条测试只喂 `issues`，
    /// 一条都没喂 `vocabulary` / `targets`——实测把 `build` 里那两行整行删掉，
    /// 9 条全绿。也就是说「词汇本、重训目标里引用到的场次也要并进时间轴」
    /// 这条产品行为当时没有任何测试守着。
    ///
    /// 它守两件事：
    /// 1. 三个档案的场次都要并进时间轴。漏掉词汇/目标独有的那几场，
    ///    「之前那批」就凭空变小，同样的出现次数会被算成「变多了」——
    ///    用户会以为自己练退步了。这正是计划里突变 B 要守的那条，只是换了数据源。
    /// 2. `unmatchedSessionIDs` 的顺序固定为 issues → vocabulary → targets。
    ///    `build` 的注释说这个顺序是刻意的，但原来没有测试能分辨顺序被换掉。
    func testIncludesSessionsReferencedOnlyByVocabularyOrTargets() {
        let fromIssue = "2026-07-08T09:00:00Z"
        let fromWord = "2026-07-07T09:00:00Z"
        let fromTarget = "2026-07-06T09:00:00Z"

        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 9), session(day: 1)],
            issues: [issue("i1", sessions: [fromIssue])],
            vocabulary: [word("v1", sessions: [fromWord])],
            targets: [target("t1", session: fromTarget)]))

        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 9), fromIssue, fromWord, fromTarget, sessionID(day: 1)],
                       "词汇本与重训目标里引用到的场次也练过，必须并进时间轴")
        XCTAssertEqual(timeline.unmatchedSessionIDs, [fromIssue, fromWord, fromTarget],
                       "unmatched 的顺序必须固定为 issues → vocabulary → targets")
    }

    /// **复审补入。** `build` 对档案里引用到的 id 是 `CoachTime.parse(id) ?? parseDayPrefix(id)`，
    /// 但原来那条孤儿测试用的 `2026-07-05T09:00:00Z` 恰好和别的场次不同天，
    /// 于是把 `CoachTime.parse(id)` 整个删掉、只留 `parseDayPrefix(id)`，10 条依然全绿——
    /// 精度丢了也看不出来。
    ///
    /// 这里让孤儿和正式记录落在同一天：只按日期前缀解析的话，孤儿会退成当天 00:00，
    /// 排到 10:00 那场记录后面，顺序整个反过来。同一天里谁在前是真会改变窗口划分的。
    func testKeepsTheTimeOfDayOfArchiveOnlySessions() {
        let orphan = "2026-07-05T23:00:00Z"
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 5, startedAt: "2026-07-05T10:00:00Z")],
            issues: [issue("i1", sessions: [orphan])]))

        XCTAssertEqual(timeline.orderedSessionIDs, [orphan, sessionID(day: 5)],
                       "孤儿场次的 23:00 晚于当天 10:00 的记录，必须排在它前面")
    }

    func testReportsUndatableIDsAndKeepsThemOutOfTheOrder() {
        // pending-reviews 的 requestID 混进来过一次就会毁掉窗口划分。
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456"])]))

        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2)])
        XCTAssertEqual(timeline.undatedSessionIDs, ["sync-1754123456"])
    }

    func testWarningsExplainWhatHappenedAndWhatToDoNext() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456", "2026-07-05T09:00:00Z"])]))

        XCTAssertEqual(timeline.warnings.count, 2)
        for warning in timeline.warnings {
            XCTAssertTrue(warning.contains("下一步"), "警告必须说明下一步做什么：\(warning)")
        }
    }

    /// **复审补入。** 原文案说这些练习「只在问题档案里留了记录」，
    /// 但 `testIncludesSessionsReferencedOnlyByVocabularyOrTargets` 已经证明
    /// `unmatchedSessionIDs` 同样会来自 `vocabulary` 和 `targets`。
    /// 一场只被词汇引用的练习，用户按提示翻遍问题档案也找不到，
    /// 只会得出「数据坏了」的结论——那就不是「说清发生了什么」。
    func testUnmatchedWarningNamesEveryPageTheseSessionsCanShowUpOn() {
        let orphan = "2026-07-05T09:00:00Z"
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 9)],
            vocabulary: [word("v1", sessions: [orphan])]))

        XCTAssertEqual(timeline.unmatchedSessionIDs, [orphan])
        XCTAssertEqual(timeline.warnings.count, 1)
        let warning = timeline.warnings[0]
        for page in ["问题档案", "我的词汇", "复训中心"] {
            XCTAssertTrue(warning.contains(page),
                          "三处档案都会引用到这种场次，文案不能只点名其中一处：\(warning)")
        }
        XCTAssertTrue(warning.contains(orphan), "得给出具体 id，用户才有得可查：\(warning)")
        XCTAssertTrue(warning.contains("下一步"), "警告必须说明下一步做什么：\(warning)")
    }

    /// **复审补入。** 原文案的下一步是「检查这几条记录的 startedAt 是不是空的：sync-1754123456」，
    /// 可 `sync-…` 这种 id 只存在于 `issues[].sourceSessionIds` 里，
    /// 根本没有对应的 session 记录、没有 startedAt 字段可查——用户照着找会扑空。
    /// 两种来源都得说到。
    func testUndatedWarningCoversBothRealRecordsAndArchiveOnlyIDs() {
        // state.sessions 里的一条记录：startedAt 空，id 也没有日期前缀，两条路都解析不出时间。
        let broken = PracticeSession(id: "legacy-session", questionId: "q", focusPart: .part1,
                                     startedAt: "", endedAt: "", goal: "",
                                     transcript: [], reportPath: "", recordingPath: "")
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2), broken],
            issues: [issue("i1", sessions: ["sync-1754123456"])]))

        XCTAssertEqual(timeline.undatedSessionIDs, ["legacy-session", "sync-1754123456"])
        XCTAssertEqual(timeline.warnings.count, 1)
        let warning = timeline.warnings[0]
        XCTAssertTrue(warning.contains("sessions") && warning.contains("startedAt"),
                      "真有训练记录的那种，下一步是去 sessions 里补 startedAt：\(warning)")
        XCTAssertTrue(warning.contains("sourceSessionIds"),
                      "sync-… 这种 id 只存在于档案的引用里，没有 startedAt 可查，"
                      + "文案必须把这种情况也说到：\(warning)")
        XCTAssertTrue(warning.contains("sync-1754123456"), "得给出具体 id：\(warning)")
        XCTAssertTrue(warning.contains("下一步"), "警告必须说明下一步做什么：\(warning)")
    }

    func testNoWarningsWhenEverythingLinesUp() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2), session(day: 1)],
            issues: [issue("i1", sessions: [sessionID(day: 1)])]))
        XCTAssertTrue(timeline.warnings.isEmpty, "数据正常时不该吓唬用户")
    }

    func testRecentAndEarlierWindowsSplitTheTimeline() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...10).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5),
                       (6...10).reversed().map { sessionID(day: $0) })
        XCTAssertEqual(timeline.earlierWindow(size: 5),
                       (1...5).reversed().map { sessionID(day: $0) })
    }

    func testWindowsShrinkGracefullyWhenThereAreNotEnoughSessions() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...7).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5).count, 5)
        XCTAssertEqual(timeline.earlierWindow(size: 5).count, 2, "只剩 2 场就只给 2 场，不能越界")
        XCTAssertEqual(SessionTimeline.build(state: state(sessions: []))
                        .earlierWindow(size: 5), [])
    }

    func testWindowRejectsNonsenseArguments() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...3).map { session(day: $0) }))
        XCTAssertEqual(timeline.window(size: 0, offset: 0), [])
        XCTAssertEqual(timeline.window(size: 5, offset: 99), [])
        XCTAssertEqual(timeline.window(size: -1, offset: 0), [])
    }
}
