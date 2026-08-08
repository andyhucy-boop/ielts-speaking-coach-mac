import Foundation

/// 首页四格统计。
///
/// **这里不会、也不许出现任何形式的雅思分数预测**（DEFINITION-OF-DONE 第 4 节）。
/// 第四格是「出现变少的毛病有几个」——一个用户能自己数出来核对的计数，
/// 不是对他水平的评判。
public struct TrainingStats: Equatable, Sendable {
    public let weeklyDone: Int
    public let weeklyGoal: Int
    public let totalSessions: Int
    public let weeklySpokenMinutes: Int
    /// 趋势是 .gone 或 .decreasing 的毛病个数。
    public let improvingIssueCount: Int
    /// 问题档案里一共有几个毛病，给「N 个里的 M 个」这种说法用。
    public let trackedIssueCount: Int

    /// **趋势那一格的场次口径**：`SessionTimeline` 上真正参与窗口划分的场次数
    /// （训练记录里的，加上只在档案里留了记录、但时间读得出来的那些）。
    ///
    /// **界面上凡是要说「场次够不够看出趋势」，只能用这个数，不许用 `totalSessions`。**
    /// 两个口径经常不相等（在训练记录页删掉几条旧记录、或用命令行练过几场，
    /// 都会让档案里引用到的场次多于 `state.sessions`），而 `improvingIssueCount`
    /// 走的是 `IssueTrendAnalyzer` → `SessionTimeline` 这一条。拿 `totalSessions`
    /// 去判「够不够」，就会出现同一张卡片上大号数字写着「出现变少的毛病 1 个」、
    /// 紧挨着的脚注写着「还看不出来，再练 1 次才会显示」——数字已经在显示了，
    /// 而那句「下一步」承诺的是一件已经发生的事（2026-08-08 复审第 12 条实测复现）。
    public let trendSessionCount: Int
    /// 只在错题/词汇/复训目标档案里留了记录、训练记录页看不到的场次数。
    /// 非 0 时界面必须解释：它们算进了趋势，但用户在训练记录页数不出来。
    public let archiveOnlySessionCount: Int

    // MARK: 诊断字段。非 0 时界面必须解释，禁止静默吞掉。

    /// 本周有记录、但算不出时长的场次（缺 endedAt，或 endedAt 不晚于 startedAt）。
    public let sessionsMissingDuration: Int
    /// 本周超过 maxCountedMinutesPerSession 被截断的场次。
    public let cappedSessionCount: Int
    /// startedAt 与 id 都解析不出时间、因此进不了任何一周的场次。
    public let undatedSessionCount: Int

    /// 单场计入上限。忘了点「我练完了」会让一场记成好几个小时，
    /// 「本周开口时长 743 分钟」会让整个统计失去可信度。
    public static let maxCountedMinutesPerSession = 120

    public init(weeklyDone: Int, weeklyGoal: Int, totalSessions: Int,
                weeklySpokenMinutes: Int, improvingIssueCount: Int, trackedIssueCount: Int,
                trendSessionCount: Int, archiveOnlySessionCount: Int,
                sessionsMissingDuration: Int, cappedSessionCount: Int,
                undatedSessionCount: Int) {
        self.weeklyDone = weeklyDone; self.weeklyGoal = weeklyGoal
        self.totalSessions = totalSessions; self.weeklySpokenMinutes = weeklySpokenMinutes
        self.improvingIssueCount = improvingIssueCount; self.trackedIssueCount = trackedIssueCount
        self.trendSessionCount = trendSessionCount
        self.archiveOnlySessionCount = archiveOnlySessionCount
        self.sessionsMissingDuration = sessionsMissingDuration
        self.cappedSessionCount = cappedSessionCount
        self.undatedSessionCount = undatedSessionCount
    }

    /// - Parameters:
    ///   - calendar: 默认用 ISO8601 日历（周一为一周之始）。测试必须显式传入
    ///     固定时区的日历，否则结果随运行机器的时区变化。
    public static func compute(state: CoachState,
                               now: Date = Date(),
                               calendar: Calendar = Calendar(identifier: .iso8601)) -> TrainingStats {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)

        var weeklyDone = 0
        var minutes = 0
        var missingDuration = 0
        var capped = 0
        var undated = 0

        for session in state.sessions {
            // 「一场练习算在什么时候」全项目只有 PracticeSessionOrder 一份规则，
            // 别在这里另写：少一次兜底，这里的「本周训练 N 次」就会和别处对不上。
            guard let started = PracticeSessionOrder.startDate(of: session) else {
                undated += 1
                continue
            }
            guard let week, week.contains(started) else { continue }
            weeklyDone += 1

            guard let ended = CoachTime.parse(session.endedAt), ended > started else {
                // 缺结束时间、或结束时间早于开始时间。按 0 计入，但必须报出来——
                // 用户练了 40 分钟却看到 0 分钟，会以为工具坏了。
                missingDuration += 1
                continue
            }

            let raw = Int((ended.timeIntervalSince(started) / 60).rounded())
            if raw > maxCountedMinutesPerSession {
                capped += 1
                minutes += maxCountedMinutesPerSession
            } else {
                minutes += raw
            }
        }

        let trends = IssueTrendAnalyzer.analyze(state: state)
        let improving = trends.filter { $0.trend == .gone || $0.trend == .decreasing }.count
        // 趋势那一格的两个数字必须出自同一条时间轴：`improving` 是
        // `IssueTrendAnalyzer` 算的，而它内部走的正是 `SessionTimeline`。
        // 这里再取一次同一条轴，界面上「够不够看出趋势」才和「看出来了几个」同口径。
        let timeline = SessionTimeline.build(state: state)

        return TrainingStats(
            weeklyDone: weeklyDone,
            weeklyGoal: state.settings.weeklyGoal,
            totalSessions: state.sessions.count,
            weeklySpokenMinutes: minutes,
            improvingIssueCount: improving,
            trackedIssueCount: state.issues.count,
            trendSessionCount: timeline.orderedSessionIDs.count,
            archiveOnlySessionCount: timeline.unmatchedSessionIDs.count,
            sessionsMissingDuration: missingDuration,
            cappedSessionCount: capped,
            undatedSessionCount: undated)
    }
}
