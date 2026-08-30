import Foundation
import IELTSCoachCore

/// 问题档案页顶上的四档筛选。
///
/// 「正在变少」把 `.gone` 和 `.decreasing` 收在一起：对用户来说这两件事是同一个消息
/// （这个毛病在往好的方向走），分成两档只会让他每次都要点两下才看得全。
public enum IssueFilter: String, CaseIterable, Identifiable, Sendable {
    case all, recurring, new, improving

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .recurring: return "反复出现"
        case .new: return "新问题"
        case .improving: return "正在变少"
        }
    }
}

/// 列表里的一行。**界面要显示的每一样东西都在这儿算好**，视图不再自己拼字符串——
/// 视图里拼出来的文案没有任何测试管得住。
public struct IssueArchiveRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// 学员的原话。英文原样保留，不翻译。
    public let learnerSaid: String
    public let correction: String
    public let whyItMatters: String
    public let occurrences: Int
    /// 出现在几场不同的练习里。
    public let sessionCount: Int
    public let isNew: Bool
    public let trend: IssueTrend
    public let detail: String
    public let lastSeenText: String
    /// **现在张嘴练什么**（`IssueRecord.miniDrill`）。空串时那一行整行不画。
    ///
    /// 这一页此前只有「你说错了 / 该说成 / 为什么要改」，一条也没告诉他此刻该做什么——
    /// 而这一页恰恰是他反复回来看的地方。页面级的下一步（「去开一场复训」）是有的，
    /// 缺的是**这一条错误自己**的练法。
    public let miniDrill: String

    public init(id: String, learnerSaid: String, correction: String, whyItMatters: String,
                occurrences: Int, sessionCount: Int, isNew: Bool, trend: IssueTrend,
                detail: String, lastSeenText: String, miniDrill: String = "") {
        self.id = id; self.learnerSaid = learnerSaid; self.correction = correction
        self.whyItMatters = whyItMatters; self.occurrences = occurrences
        self.sessionCount = sessionCount; self.isNew = isNew; self.trend = trend
        self.detail = detail; self.lastSeenText = lastSeenText; self.miniDrill = miniDrill
    }
}

/// 问题档案页的视图模型：把 `state.issues` 排好序、配上趋势，变成界面直接能画的一串行。
///
/// **这一页不做任何形式的分数预测或水平判断**（DEFINITION-OF-DONE 第 4 节）：
/// 只回答「这个毛病出现了几次、最近有没有变少」。
public struct IssueArchiveViewModel: Sendable {
    public let rows: [IssueArchiveRow]
    /// 时间轴发现的数据问题。**非空时界面必须显示**——埋在 Core 里没人看得见，
    /// 等于没检查。
    public let dataWarnings: [String]

    public init(state: CoachState,
                calendar: Calendar = .current,
                windowSize: Int = IssueTrendAnalyzer.defaultWindowSize) {
        // ⚠️ 不能用 Dictionary(uniqueKeysWithValues:)：state.json 被外部工具改坏、
        // 或上游写入过重复 id 时，它会 fatalError 闪退整个 App 而不是报错。
        // 本项目在 QuestionBankImporter.merge 里已经为同一个坑写过注释。
        var byID: [String: IssueTrendResult] = [:]
        for result in IssueTrendAnalyzer.analyze(state: state, windowSize: windowSize) {
            byID[result.issueID] = result
        }

        // **时间先一次性解析好，再排序。**（decorate-sort-undecorate）
        //
        // 原来是在比较器里 `CoachTime.parse(...)`，于是解析次数从 n 变成
        // 「比较次数 × 2」——2026-08-30 实测 30 条错题排一次要比较 393 次
        // （错题是按归档顺序追加的，也就是最旧的在前，几乎正好是想要的顺序的反向，
        // Swift 的排序因此要做远多于 n log n 的比较），合计 816 次解析。
        // 而当时 `CoachTime.parse` 每次还要新建两个 formatter，一次视图模型构造 121 ms。
        //
        // 现在解析 n 次（30 次），比较器里只比已经算好的 `Date`。
        let dated = state.issues.map { ($0, CoachTime.parse($0.lastSeenAt)) }

        // 出现次数倒序 → 最近一次出现时间倒序 → id 升序。
        // 第三级是为了让排序**完全确定**——不确定的排序会让同一份数据每次打开的顺序
        // 都不一样，用户会以为记录被改了。
        let sorted = dated.sorted { left, right in
            if left.0.occurrences != right.0.occurrences {
                return left.0.occurrences > right.0.occurrences
            }
            let leftSeen = left.1 ?? .distantPast
            let rightSeen = right.1 ?? .distantPast
            if leftSeen != rightSeen { return leftSeen > rightSeen }
            return left.0.id < right.0.id      // 第三级：让排序完全确定
        }

        rows = sorted.map { issue, parsedLastSeen in
            let trend = byID[issue.id]
            // 复用上面那一次解析，不再解析第二遍。
            let lastSeen = parsedLastSeen
                .map { "最近一次：" + CoachTime.dayString($0, calendar: calendar) }
            return IssueArchiveRow(
                id: issue.id,
                learnerSaid: issue.learnerSaid,
                correction: issue.correction,
                whyItMatters: issue.whyItMatters,
                occurrences: issue.occurrences,
                // 同一场被记了两遍时只算一场：这一行回答的是「出现在几场练习里」。
                sessionCount: Set(issue.sourceSessionIds).count,
                isNew: trend?.isNew ?? false,
                trend: trend?.trend ?? .notEnoughData,
                detail: trend?.detail ?? IssueTrend.notEnoughData.explanation,
                // 读不出时间就说读不出，不要拿一个猜的日期糊弄过去
                lastSeenText: lastSeen ?? "最近一次：时间不详",
                miniDrill: issue.miniDrill)
        }

        dataWarnings = SessionTimeline.build(state: state).warnings
    }

    public func rows(filter: IssueFilter) -> [IssueArchiveRow] {
        switch filter {
        case .all: return rows
        case .recurring: return rows.filter { $0.occurrences >= 2 }
        case .new: return rows.filter(\.isNew)
        case .improving: return rows.filter { $0.trend == .gone || $0.trend == .decreasing }
        }
    }

    public var counts: (total: Int, new: Int, improving: Int) {
        (rows.count, rows(filter: .new).count, rows(filter: .improving).count)
    }
}
