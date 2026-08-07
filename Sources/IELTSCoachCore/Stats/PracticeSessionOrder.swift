import Foundation

/// 「一场练习发生在什么时候」以及「按时间从新到旧怎么排」的唯一一份规则。
///
/// **为什么必须只有一份：** `startedAt` 空着、时间只剩在 id 里的记录是真实存在的数据
/// （Phase 4 之前的记录、写入时漏了 `startedAt` 的记录）。`TrainingStats.compute` 与
/// `SessionTimeline.build` 都按这种数据兜底处理，谁少写一次兜底，同一份 `state.json`
/// 就会在两处给出互相矛盾的答案——首页说「本周练了 1 次」，历史列表却把今天这场排到最后
/// 甚至被 limit 截掉——而两边都不报错，用户没有任何办法判断哪个是真的。
///
/// 想改「一场练习算在什么时候」，改这里；不要在调用方各写一份。
public enum PracticeSessionOrder {
    /// 一场练习的开始时间：优先 `startedAt`，读不出来时退回 id 的日期前缀。
    ///
    /// 两处都读不出来时返回 `nil`。**返回 nil 的场次调用方必须显式告诉用户**（铁律 7）：
    /// 它排不进时间轴，静默塞在某个位置等于给出一个用户无法核对的顺序。
    public static func startDate(startedAt: String, id: String) -> Date? {
        CoachTime.parse(startedAt) ?? CoachTime.parseDayPrefix(id)
    }

    public static func startDate(of session: PracticeSession) -> Date? {
        startDate(startedAt: session.startedAt, id: session.id)
    }

    /// 按开始时间从新到旧排。
    ///
    /// - 同一时刻的两场按 id 倒序，与 `SessionTimeline` 用的是同一条 tie-break：
    ///   Swift 的 `sorted` 不保证稳定，不定死的话同一天多场（兜底后时间完全相同）
    ///   每次得到的顺序可能不一样。
    /// - 读不出时间的场次**不许丢**——它确实练过。它们排在最后（内部也按 id 倒序保证确定），
    ///   并由 `undatedIDs` 原样列出来，好让调用方把「这几条排不进时间轴」说给用户听。
    public static func newestFirst(_ sessions: [PracticeSession])
        -> (ordered: [PracticeSession], undatedIDs: [String]) {
        var dated: [(session: PracticeSession, date: Date)] = []
        var undated: [PracticeSession] = []
        for session in sessions {
            if let date = startDate(of: session) {
                dated.append((session, date))
            } else {
                undated.append(session)
            }
        }
        let orderedDated = dated
            .sorted { $0.date == $1.date ? $0.session.id > $1.session.id : $0.date > $1.date }
            .map(\.session)
        let orderedUndated = undated.sorted { $0.id > $1.id }
        return (orderedDated + orderedUndated, orderedUndated.map(\.id))
    }
}
