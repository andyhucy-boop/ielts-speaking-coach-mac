import Foundation
import IELTSCoachCore

public struct HistoryRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let session: PracticeSession
    public let dateText: String
    public let partText: String
    public let questionText: String
    /// 题目已经不在题库里（换季导入过新题库）。界面要把这一行标出来，
    /// **但绝不能因此把这条记录藏起来**——凭空消失会让用户以为练习记录丢了。
    public let questionIsMissing: Bool
    public let turnCountText: String
    /// 这一场练了多久（「12 分钟」/「3 小时 12 分钟」/「时长未知」）。
    ///
    /// **它是首页那句「下一步：到训练记录页核对这几场」唯一能兑现的方式。**
    /// 那句话说的是「有 N 场超过 2 小时，已按 2 小时计入（多半是忘了点结束）」，
    /// 而在这之前这一页每行只有日期，既没时刻也没时长——照着来的人
    /// **没有任何字段可以用来认出是哪几场**（铁律 4）。
    ///
    /// 顺带也是他判断一场练得实不实的直接依据：说了 12 分钟还是 3 分钟。
    public let durationText: String
    public let reviewStatusText: String
    public let hasReport: Bool
    /// Phase 5 会在这一行下面挂回听播放器。
    public let hasRecording: Bool
}

public struct HistoryMonth: Equatable, Identifiable, Sendable {
    /// `"2026-08"`，或时间解析不出来时的 `"unknown"`。
    public let id: String
    public let title: String
    public let rows: [HistoryRow]
}

/// 训练记录页要显示的东西。纯数据变换，不碰文件、不碰界面。
public struct HistoryViewModel: Sendable {
    public let months: [HistoryMonth]

    public init(state: CoachState, timeZone: TimeZone = .current) {
        let calendar = HistoryViewModel.calendar(in: timeZone)
        let questions = Dictionary(state.questions.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })

        // 先算出每条记录的时刻（可能为 nil），再排序、再分组。
        let dated: [(session: PracticeSession, moment: Date?)] = state.sessions.map {
            ($0, HistoryViewModel.moment(of: $0))
        }
        // 新的在前；时间不详的一律排到最后，但保持它们彼此之间按 id 倒序，顺序稳定。
        let sorted = dated.sorted { left, right in
            switch (left.moment, right.moment) {
            case let (l?, r?): return l == r ? left.session.id > right.session.id : l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.session.id > right.session.id
            }
        }

        var order: [String] = []
        var buckets: [String: [HistoryRow]] = [:]
        var titles: [String: String] = [:]

        for entry in sorted {
            let key: String
            let title: String
            let dateText: String
            if let moment = entry.moment {
                let parts = calendar.dateComponents([.year, .month, .day], from: moment)
                let year = parts.year ?? 0
                let month = parts.month ?? 0
                key = String(format: "%04d-%02d", year, month)
                // 月份标题自己拼，不走 DateFormatter 的本地化格式——那个会跟着用户的
                // 系统语言变，这一层就再也没法写死断言了。
                title = "\(year) 年 \(month) 月"
                dateText = "\(month) 月 \(parts.day ?? 0) 日"
            } else {
                // **这一支绝不能改成 `continue`。** 时间解析不出来的记录（命令行时代的
                // `sync-1785940167` 那种 id）跳过去的话，用户会以为这些练习记录丢了。
                key = "unknown"
                title = "时间不详"
                dateText = "时间不详"
            }

            if buckets[key] == nil { order.append(key); titles[key] = title }
            buckets[key, default: []].append(
                HistoryViewModel.row(for: entry.session, dateText: dateText, questions: questions))
        }

        months = order.map { HistoryMonth(id: $0, title: titles[$0] ?? $0, rows: buckets[$0] ?? []) }
    }

    public var isEmpty: Bool { months.isEmpty }
    public var totalCount: Int { months.reduce(0) { $0 + $1.rows.count } }

    // MARK: - 私有

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// 这条记录发生在什么时候。
    ///
    /// 优先用 `startedAt`；它为空或解析不了时，退回从 id 的日期前缀解析——
    /// 决策 1 之前用命令行练的那些记录，id 是 ISO8601 时间戳，`startedAt` 可能是空的。
    /// **两条路都解析不出来时返回 nil，那条记录归到「时间不详」，绝不丢弃。**
    static func moment(of session: PracticeSession) -> Date? {
        for formatter in isoFormatters {
            if let date = formatter.date(from: session.startedAt) { return date }
            if let date = formatter.date(from: session.id) { return date }
        }
        // "2026-08-06-001" / "2026-08-06T14:03:11Z" 都以 yyyy-MM-dd 开头
        let prefix = String(session.id.prefix(10))
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: prefix)
    }

    /// **每次现造，不缓存成 `static let`。**
    ///
    /// 计划里写的是 `private static let isoFormatters: [ISO8601DateFormatter] = { … }()`，
    /// 那份在 Swift 6 的严格并发下编不过：`ISO8601DateFormatter` 不是 `Sendable`，
    /// 而 `HistoryViewModel` 是 `Sendable` 且不带全局 actor，于是一个非隔离的静态存储属性
    /// 持有它就成了「可跨线程共享的可变状态」。
    /// （`ReviewReportView` 里那份同类写法之所以没事，是因为它整个类型标了 `@MainActor`。）
    ///
    /// 用 `nonisolated(unsafe)` 消警告是另一条路，但 `DateFormatter` 家族的线程安全
    /// 从来只是「文档上说 macOS 10.9 之后安全」，不值得为一次几微秒的构造去赌。
    /// 这个属性一条记录只调一次。
    private static var isoFormatters: [ISO8601DateFormatter] {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }

    private static func row(for session: PracticeSession, dateText: String,
                            questions: [String: Question]) -> HistoryRow {
        let question = questions[session.questionId]
        let questionText = question?.prompt
            ?? "这道题已经不在题库里了（id：\(session.questionId)）。"
        let turnCount = session.transcript.count
        return HistoryRow(
            id: session.id,
            session: session,
            dateText: dateText,
            partText: session.focusPart.rawValue,
            questionText: questionText,
            questionIsMissing: question == nil,
            // 「0 条对话」看起来像出了什么问题；「没有逐字稿」是在陈述事实。
            turnCountText: turnCount > 0 ? "\(turnCount) 条对话" : "没有逐字稿",
            // 走 `TrainingStats` 那一份算法，不在这里另算：另算的话，
            // 首页「本周开口时长」和这一页逐行加起来的数会对不上。
            durationText: TrainingStats.durationText(of: session),
            reviewStatusText: session.reportPath.isEmpty ? "没有复盘" : "复盘已存档",
            hasReport: !session.reportPath.isEmpty,
            hasRecording: !session.recordingPath.isEmpty)
    }
}
