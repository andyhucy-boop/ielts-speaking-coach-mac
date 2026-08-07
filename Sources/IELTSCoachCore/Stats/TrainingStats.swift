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
                sessionsMissingDuration: Int, cappedSessionCount: Int,
                undatedSessionCount: Int) {
        self.weeklyDone = weeklyDone; self.weeklyGoal = weeklyGoal
        self.totalSessions = totalSessions; self.weeklySpokenMinutes = weeklySpokenMinutes
        self.improvingIssueCount = improvingIssueCount; self.trackedIssueCount = trackedIssueCount
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

        return TrainingStats(
            weeklyDone: weeklyDone,
            weeklyGoal: state.settings.weeklyGoal,
            totalSessions: state.sessions.count,
            weeklySpokenMinutes: minutes,
            improvingIssueCount: improving,
            trackedIssueCount: state.issues.count,
            sessionsMissingDuration: missingDuration,
            cappedSessionCount: capped,
            undatedSessionCount: undated)
    }
}
