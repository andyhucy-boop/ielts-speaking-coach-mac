import Foundation

/// 把所有练习场次按时间排成一条轴，供「最近 N 场 vs 之前 N 场」的窗口划分使用。
///
/// **为什么窗口按场次而不按天数：** 用户可能两周没练。按天数划窗口的话，
/// 「最近 14 天」里一场都没有，所有毛病都会显示成「变少了」——那是在骗人。
public struct SessionTimeline: Equatable, Sendable {
    /// 按时间倒序，最近的一场在最前。
    public let orderedSessionIDs: [String]
    /// 在错题/词汇/目标档案里被引用、但 `state.sessions` 里没有对应记录的场次。
    /// 它们仍然参与窗口划分（确实练过），但必须让用户知道。
    public let unmatchedSessionIDs: [String]
    /// 连日期都解析不出来的 id。不参与任何窗口计算。
    public let undatedSessionIDs: [String]

    public init(orderedSessionIDs: [String], unmatchedSessionIDs: [String],
                undatedSessionIDs: [String]) {
        self.orderedSessionIDs = orderedSessionIDs
        self.unmatchedSessionIDs = unmatchedSessionIDs
        self.undatedSessionIDs = undatedSessionIDs
    }

    public static func build(state: CoachState) -> SessionTimeline {
        var timestamps: [String: Date] = [:]
        var undated: [String] = []
        var unmatched: [String] = []

        // ① 训练记录本身。优先用 startedAt，缺失时退回从 id 的日期前缀解析。
        for session in state.sessions {
            if let date = CoachTime.parse(session.startedAt)
                ?? CoachTime.parseDayPrefix(session.id) {
                timestamps[session.id] = date
            } else if !undated.contains(session.id) {
                undated.append(session.id)
            }
        }
        let recorded = Set(state.sessions.map(\.id))

        // ② 档案里引用到的场次。顺序固定（issues → vocabulary → targets），
        //    保证同一份数据每次得到同样的 unmatched 顺序，测试才有确定性。
        var referenced: [String] = []
        for issue in state.issues { referenced.append(contentsOf: issue.sourceSessionIds) }
        for record in state.vocabulary { referenced.append(contentsOf: record.sourceSessionIds) }
        for target in state.targets { referenced.append(target.sourceSessionId) }

        for id in referenced {
            guard timestamps[id] == nil, !undated.contains(id) else { continue }
            // 档案里的 sessionID 可能是完整时间戳，也可能是 "YYYY-MM-DD-NNN"，两种都试
            if let date = CoachTime.parse(id) ?? CoachTime.parseDayPrefix(id) {
                timestamps[id] = date
                if !recorded.contains(id), !unmatched.contains(id) { unmatched.append(id) }
            } else {
                undated.append(id)
            }
        }

        // 同一时刻的两场按 id 倒序，保证排序是确定的——不确定的排序会让
        // 同一份数据每次打开显示不同的趋势。
        let ordered = timestamps
            .sorted { $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value }
            .map(\.key)

        return SessionTimeline(orderedSessionIDs: ordered,
                               unmatchedSessionIDs: unmatched,
                               undatedSessionIDs: undated)
    }

    /// 界面必须显示这些警告。静默地把有问题的数据算进趋势，
    /// 等于给用户一个他无法核对的结论。
    public var warnings: [String] {
        var result: [String] = []
        if !unmatchedSessionIDs.isEmpty {
            result.append(
                "有 \(unmatchedSessionIDs.count) 次练习只在问题档案里留了记录，训练记录页看不到它们"
                + "（多半是早期用命令行练的）。它们仍按时间算进趋势，所以趋势本身是对的。"
                + "下一步：如果你在训练记录页找不到这几次，不用管这条提示；"
                + "如果你觉得根本没练过，去数据目录里的 state.json 核对一下。")
        }
        if !undatedSessionIDs.isEmpty {
            let sample = undatedSessionIDs.prefix(3).joined(separator: "、")
            result.append(
                "有 \(undatedSessionIDs.count) 条练习记录读不出时间，没有参与趋势计算，"
                + "因此「最近有没有变少」可能偏乐观。"
                + "下一步：打开数据目录里的 state.json，检查这几条记录的 startedAt 是不是空的：\(sample)")
        }
        return result
    }

    /// 从时间轴上取一段。参数不合理时返回空数组，不崩、不越界。
    public func window(size: Int, offset: Int) -> [String] {
        guard size > 0, offset >= 0, offset < orderedSessionIDs.count else { return [] }
        let end = min(offset + size, orderedSessionIDs.count)
        return Array(orderedSessionIDs[offset..<end])
    }

    public func recentWindow(size: Int) -> [String] { window(size: size, offset: 0) }

    public func earlierWindow(size: Int) -> [String] { window(size: size, offset: size) }
}
