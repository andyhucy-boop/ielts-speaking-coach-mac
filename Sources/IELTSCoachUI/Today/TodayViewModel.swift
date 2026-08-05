import Foundation
import IELTSCoachCore

/// 今日训练页上的四条练习路线。
///
/// 每条都自带中文标题与副标题：卡片上只有一个动词的话，用户点之前不知道会发生什么。
public enum PracticeRoute: String, CaseIterable, Identifiable, Sendable {
    case planToday, freePick, continueLast, retrain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .planToday: return "按计划练今天"
        case .freePick: return "从题库自由选题"
        case .continueLast: return "继续上次练习"
        case .retrain: return "复训一个旧问题"
        }
    }

    public var subtitle: String {
        switch self {
        case .planToday: return "按学习计划安排的今日题目"
        case .freePick: return "先选 Part，再挑具体题目"
        case .continueLast: return "接着上次那道题再练"
        case .retrain: return "带上一次复盘给出的目标"
        }
    }
}

/// 今日训练页的取数逻辑：今天练什么、哪几条路线现在真的走得通、本周练了几次、最近练了什么。
///
/// 单独分出来是因为 `View` 几乎没法单元测试，而「把 `CoachState` 变成界面要显示的东西」
/// 这段完全可测。判据是「把这里改成空实现，`TodayViewModelTests` 会不会红」。
public struct TodayViewModel: Sendable {
    /// 本周目标次数。写成常量而不是散在两处字面量：`weekProgress.goal` 和界面上那句
    /// 「还差几次」必须是同一个数，否则会出现「3/5」旁边写着「还差 4 次」。
    public static let weeklyGoal = 5

    public let state: CoachState
    private let today: Date

    /// `today` 可注入，测试才能钉住「本周」的边界；生产用默认值。
    public init(state: CoachState, today: Date = Date()) {
        self.state = state
        self.today = today
    }

    /// 计划里第一个未完成的那天的题目。
    ///
    /// **按「第一个没做完的」取，不是按日历日期取。** 用户请两天假回来，看到的应该是
    /// 上次没做完的那天，而不是「今天是第 5 天」然后把第 3、4 天悄悄跳过去。
    ///
    /// 题目从题库里按 id 反查；题库里已经没有的 id 会被跳过（换季重新导入之后会出现），
    /// 全都查不到时这里返回空，「按计划练今天」那条路线随之不显示——
    /// 显示一张点开是空的卡片，比不显示更糟。
    public var todayQuestions: [Question] {
        guard let plan = state.plan,
              let day = plan.days.first(where: { !$0.isComplete && !$0.questionIds.isEmpty })
        else { return [] }
        return day.questionIds.compactMap { id in state.questions.first { $0.id == id } }
    }

    /// 只显示前提成立的路线。**显示一条点了没用的路线，比不显示更糟**——
    /// 用户点下去什么也不发生，会以为程序坏了，而这一页是他每天打开的第一眼。
    ///
    /// 顺序有意义：排在第一位的那条就是页面上唯一的主行动（规范第 4 节）。
    public var availableRoutes: [PracticeRoute] {
        var routes: [PracticeRoute] = []
        if !todayQuestions.isEmpty { routes.append(.planToday) }
        if !state.questions.isEmpty { routes.append(.freePick) }
        if !state.sessions.isEmpty { routes.append(.continueLast) }
        // 已经退休的目标不算数：那是已经改掉的毛病，再拿它复训是白练一场。
        if state.targets.contains(where: { $0.status != "retired" }) { routes.append(.retrain) }
        return routes
    }

    /// 本周练了几次 / 目标几次。
    ///
    /// 周历用 ISO 8601（周一起算），与国内习惯一致；用 `.gregorian` 的话一周从周日开始，
    /// 周日练的那一次会被算进下一周。
    public var weekProgress: (done: Int, goal: Int) {
        let calendar = Calendar(identifier: .iso8601)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return (0, Self.weeklyGoal)
        }
        let formatter = ISO8601DateFormatter()
        let done = state.sessions.filter { session in
            // 认不出的时间戳不计入。宁可少算也不能多算：把一条时间不明的记录算进本周，
            // 进度条就成了一个说不清来历的数字。
            guard let started = formatter.date(from: session.startedAt) else { return false }
            return week.contains(started)
        }.count
        return (done, Self.weeklyGoal)
    }

    /// 最近五次练习，最近的在最前面。
    ///
    /// 按 `startedAt` 字符串排序而不是先解析成 `Date`：这些时间戳都由本工具写入，
    /// 格式统一（`ISO8601DateFormatter` 的 `withInternetDateTime`，全是 Z 时区），
    /// 这种形状下字典序与时间序一致。**换成别的写入格式时这里要跟着改。**
    public var recentSessions: [PracticeSession] {
        Array(state.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }
}
