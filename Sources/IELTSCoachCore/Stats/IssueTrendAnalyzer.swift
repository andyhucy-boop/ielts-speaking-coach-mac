import Foundation

/// 一个毛病最近的走向。
///
/// **这里不出现任何形式的分数。** 产品明确不做雅思分数预测
/// （DEFINITION-OF-DONE 第 4 节）：给「你大概 6.5 分」这种数字既不准也有害，
/// 会让人盯着数字而不是盯着问题。这里只回答「这个毛病出现了几次、最近有没有变少」。
public enum IssueTrend: String, Equatable, Sendable, CaseIterable {
    /// 最近才第一次出现的新毛病。
    case fresh
    /// 最近这一批练习里一次都没再出现。
    case gone
    case decreasing
    case steady
    case increasing
    /// 练习场次还不够，给不出可信的结论。
    case notEnoughData

    /// 列表里的短标签。
    public var badge: String {
        switch self {
        case .fresh: return "新问题"
        case .gone: return "最近没再出现"
        case .decreasing: return "出现变少了"
        case .steady: return "还是老样子"
        case .increasing: return "出现变多了"
        case .notEnoughData: return "还看不出趋势"
        }
    }

    /// 一句话说明「发生了什么 + 下一步做什么」。
    public var explanation: String {
        switch self {
        case .fresh:
            return "这是最近才冒出来的新毛病，之前没犯过。"
                + "下一步：先别急着当成老毛病治，看它下次还会不会出现。"
        case .gone:
            return "最近这几场练习里一次都没再出现。"
                + "下一步：换一道同类型的题再练一次，确认是真改掉了，而不是碰巧没说到。"
        case .decreasing:
            return "比之前少了。"
                + "下一步：保持现在的做法，别急着换目标——正在见效的东西不要中途改。"
        case .steady:
            return "和之前一样多，没有变化。"
                + "下一步：到复训中心把它设成下一次的单点目标，一次只盯这一个。"
        case .increasing:
            return "比之前更常出现了。"
                + "下一步：到复训中心带着这个问题重练一次，再换一道题验证。"
        case .notEnoughData:
            return "练习场次还不够，看不出它在变多还是变少。"
                + "下一步：再练几场，这里会自动开始显示趋势。"
        }
    }
}

public struct IssueTrendResult: Equatable, Sendable, Identifiable {
    public let issueID: String
    /// 档案里记的累计场次（「一共在几场练习里犯过」），原样带出来给列表排序用。
    public let occurrences: Int
    /// 最近这批练习里，有几场犯了这个毛病。
    public let recentHits: Int
    /// 再往前那批练习里，有几场犯了这个毛病。
    public let earlierHits: Int
    public let recentWindowSize: Int
    public let earlierWindowSize: Int
    public let isNew: Bool
    public let trend: IssueTrend

    public var id: String { issueID }

    public init(issueID: String, occurrences: Int, recentHits: Int, earlierHits: Int,
                recentWindowSize: Int, earlierWindowSize: Int, isNew: Bool, trend: IssueTrend) {
        self.issueID = issueID; self.occurrences = occurrences
        self.recentHits = recentHits; self.earlierHits = earlierHits
        self.recentWindowSize = recentWindowSize; self.earlierWindowSize = earlierWindowSize
        self.isNew = isNew; self.trend = trend
    }

    /// 把结论背后的原始数字摆出来，让用户能自己核对。
    public var detail: String {
        guard trend != .notEnoughData else {
            // `occurrences` 数的是场次不是次数（见 IssueRecord 的注释），文案要跟着说「场」。
            return "目前一共在 \(occurrences) 场练习里犯过它。练习场次还不够，看不出它在变多还是变少。"
        }
        return "最近 \(recentWindowSize) 场练习里有 \(recentHits) 场犯了它，"
             + "再往前 \(earlierWindowSize) 场里有 \(earlierHits) 场。"
    }
}

public enum IssueTrendAnalyzer {
    public static let defaultWindowSize = 5
    /// 「之前那批」少于这个数就不给趋势——拿 1 场当作「之前」再说「变少了」，
    /// 那是拿噪声当结论。
    public static let minimumEarlierWindow = 3
    /// 至少练满这么多场，才可能出现确定的趋势。界面用它来告诉用户「还差几场」。
    public static let minimumSessionsForTrend = defaultWindowSize + minimumEarlierWindow

    public static func analyze(state: CoachState,
                               windowSize: Int = defaultWindowSize) -> [IssueTrendResult] {
        analyze(state: state, timeline: SessionTimeline.build(state: state),
                windowSize: windowSize)
    }

    /// 时间轴由调用方给的那一版。
    ///
    /// **给已经建过时间轴的调用方用。** `IssueArchiveViewModel` 同时要趋势和
    /// `timeline.warnings`，走上面那个重载的话同一份输入要建两遍时间轴，
    /// 而建一遍要把全部练习记录的时间戳解析一轮。
    public static func analyze(state: CoachState,
                               timeline: SessionTimeline,
                               windowSize: Int = defaultWindowSize) -> [IssueTrendResult] {
        let recent = Set(timeline.recentWindow(size: windowSize))
        let earlier = Set(timeline.earlierWindow(size: windowSize))
        let inWindows = recent.union(earlier)

        return state.issues.map { issue in
            // hits 只能用「窗口 ∩ sourceSessionIds」算，不能拿 `occurrences` 顶替：
            // `occurrences` 是**不分窗口**的总数（「一共在几场练习里犯过」，
            // Phase 4 之后恒等于 sourceSessionIds.count），
            // 而这里要问的是「最近这 5 场里犯了几场」。
            let sources = Set(issue.sourceSessionIds)
            let recentHits = sources.intersection(recent).count
            let earlierHits = sources.intersection(earlier).count
            let hasOlderHistory = !sources.subtracting(inWindows).isEmpty
            let isNew = recentHits > 0 && earlierHits == 0 && !hasOlderHistory

            let trend: IssueTrend
            if earlier.count < minimumEarlierWindow {
                trend = .notEnoughData
            } else if isNew {
                // 之前根本不存在的毛病，按频率算必然是「变多了」，那是错的
                trend = .fresh
            } else if recentHits == 0 {
                trend = .gone
            } else {
                // 交叉相乘 = 比较 recentHits/recent.count 与 earlierHits/earlier.count，
                // 全程整数，不引入浮点相等判断。两个窗口大小可能不等
                // （总共 9 场时 recent 有 5 场、earlier 只有 4 场），
                // 直接比次数会把「5 场犯 2 次」和「4 场犯 2 次」判成没变化。
                let left = recentHits * earlier.count
                let right = earlierHits * recent.count
                if left < right { trend = .decreasing }
                else if left > right { trend = .increasing }
                else { trend = .steady }
            }

            return IssueTrendResult(issueID: issue.id, occurrences: issue.occurrences,
                                    recentHits: recentHits, earlierHits: earlierHits,
                                    recentWindowSize: recent.count,
                                    earlierWindowSize: earlier.count,
                                    isNew: isNew, trend: trend)
        }
    }
}
