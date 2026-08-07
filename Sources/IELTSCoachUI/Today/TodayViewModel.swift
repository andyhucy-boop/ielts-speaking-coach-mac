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
    /// 练完一场之后，有没有代码把这一场记进 `CoachState.sessions`。
    ///
    /// **2026-08-06 起是 `true`**：Phase 4 Task 6 把 `PracticeRunner.upsertSession` 接上了——
    /// 在这一页练完一整场，会话编号、题目、起止时间、逐字稿、复盘报告路径都会进
    /// `state.sessions`，于是「本周训练 N/5」「最近练习」「继续上次练习」这三处开始动。
    /// （此前是 `false`，因为全工程没有任何一行往 `state.sessions` 里写东西：
    /// `PracticeCommand` 走完一整场只调 `ReviewArchiver.archive`，
    /// 而它只动 `issues` / `vocabulary` / `targets` / `plan` / `questions`。）
    ///
    /// 这个常量存在的唯一理由，是让界面能在没接上时把这件事说出来而不是装作没有
    /// （铁律 6、铁律 7）；接上之后那句交代自己就消失。
    ///
    /// `TodayViewModelTests.testPracticeRecordingFlagMatchesWhetherAnyCodeWritesSessions`
    /// 扫 `Sources/` 钉着这个值：代码和它脱钩的两个方向都会变红。
    public static let practiceRecordingIsWired = true

    /// 「本周训练」和「最近练习」旁边要补的那句交代；记录接上之后是 `nil`。
    ///
    /// 参数可注入是为了让「接上之后这句话会不会消失」也有测试管得住——
    /// 直接读常量的话，`true` 那一支永远跑不到。
    public static func unwiredRecordingNotice(isWired: Bool = practiceRecordingIsWired) -> String? {
        guard !isWired else { return nil }
        return "这一版还不会把练习记录写进训练数据：在这一页练完一整场之后，上面的「本周训练」次数、"
            + "下面的「最近练习」都不会变，「继续上次练习」那条路线也不会出现——不是你的练习没生效。"
            + "下一步：照常练。练出来的错题、词汇、复训目标和计划进度都会正常入库，"
            + "复盘原文也会存进数据目录；训练记录要等下一版接上，接上之后这两处才会开始动。"
    }

    public let state: CoachState
    private let today: Date
    /// 周历用 ISO 8601（周一起算），与国内习惯一致；用 `.gregorian` 的话一周从周日开始，
    /// 周日练的那一次会被算进下一周。
    ///
    /// 可注入是为了让测试能钉住时区：`Calendar(identifier: .iso8601)` 用的是运行机器的时区，
    /// 断言「本周有 2 次」在别的时区上会变成 1 次或 3 次。
    private let calendar: Calendar
    /// 在 init 里算一次就好。放成 computed var 的话，四格 + 进度条会重复算四五遍。
    public let stats: TrainingStats

    /// `today` 可注入，测试才能钉住「本周」的边界；生产用默认值。
    public init(state: CoachState,
                today: Date = Date(),
                calendar: Calendar = Calendar(identifier: .iso8601)) {
        self.state = state
        self.today = today
        self.calendar = calendar
        self.stats = TrainingStats.compute(state: state, now: today, calendar: calendar)
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
        // 题库空 = 四条路线全走不通，一条都不排。
        // 「继续上次练习」「复训一个旧问题」看着只依赖历史记录，其实同样要按 id 去题库反查
        // 那道题（见下面的 `plannedQuestion(for:)`）——库空了它们哪也去不了，显示出来就是两个
        // 点了没用的按钮。换季重新导入题库（先清空再导）时用户正好停在这一格上。
        guard !state.questions.isEmpty else { return [] }

        var routes: [PracticeRoute] = []
        if !todayQuestions.isEmpty { routes.append(.planToday) }
        if !state.questions.isEmpty { routes.append(.freePick) }
        if !state.sessions.isEmpty { routes.append(.continueLast) }
        // 已经退休的目标不算数：那是已经改掉的毛病，再拿它复训是白练一场。
        if state.targets.contains(where: { $0.status != "retired" }) { routes.append(.retrain) }
        return routes
    }

    // MARK: - 点「开始练习」之后要练哪道题、按什么设置练

    /// 最近记下的那个还没退休的复训目标。`targets` 按归档顺序追加，越靠后越新。
    ///
    /// 已经退休的目标是已经改掉的毛病，拿它复训是白练一场。
    public var liveTarget: RetrainingTarget? {
        state.targets.last { $0.status != "retired" }
    }

    /// 这条路线上已经定下来的那道题。**nil 表示这道题得由用户当场自己挑。**
    ///
    /// 三种情况都会返回 nil，界面对它们的处置是同一个（弹一个挑题的列表）：
    /// 自由选题、计划里排不出题、以及「上次那道题在题库里已经没有了」——
    /// 最后这一种在换季重新导入题库之后就会发生，硬拿那个 id 去练的话，
    /// 考官提示词里的题干是空的，用户对着 ChatGPT 干瞪眼却不知道为什么。
    public func plannedQuestion(for route: PracticeRoute) -> Question? {
        switch route {
        case .planToday:
            return todayQuestions.first
        case .freePick:
            // 自由选题的意思就是这道题由用户当场挑，这里定不下来是正常的。
            return nil
        case .continueLast:
            guard let last = recentSessions.first else { return nil }
            return state.questions.first { $0.id == last.questionId }
        case .retrain:
            guard let target = liveTarget,
                  let source = state.sessions.first(where: { $0.id == target.sourceSessionId })
            else { return nil }
            return state.questions.first { $0.id == source.questionId }
        }
    }

    /// 这条路线要带的本次目标。只有「复训一个旧问题」有。
    ///
    /// 目标必须真的进到考官提示词里（`ExaminerPrompt` 的「本次唯一目标」那段），
    /// 否则「带着这个目标重练」只是句口号：复盘不会针对它给反馈，
    /// 改进闭环（成品标准第 2 节）当场断掉。
    public func goal(for route: PracticeRoute) -> String {
        route == .retrain ? (liveTarget?.label ?? "") : ""
    }

    /// 把一道题变成一场练习的设置。
    ///
    /// `focusPart` 取这道题自己的 Part——它决定 ChatGPT 按哪套规则考
    /// （`ExaminerPrompt.partRules`：Part 2 是一分钟准备 + 两分钟长回答，Part 1 是 6–10 个短问题）。
    /// 定错了，用户练的就是另一种题型，而界面上一点异样都看不出来。
    ///
    /// 时长与 `coach practice` 保持一致：Part 2 一场就一道题，四分钟足够；其余六分钟。
    public func practiceSetup(question: Question, route: PracticeRoute) -> SessionSetup {
        SessionSetup(question: question,
                     focusPart: FocusPart(rawValue: "Part \(question.part)") ?? .fullMock,
                     durationMinutes: question.part == 2 ? 4 : 6,
                     goal: goal(for: route))
    }

    /// 挑题时可选的题目。按 Part、再按题库原有顺序。
    public var pickableQuestions: [Question] {
        state.questions.enumerated()
            .sorted { ($0.element.part, $0.offset) < ($1.element.part, $1.offset) }
            .map(\.element)
    }

    /// 本周练了几次 / 目标几次。
    ///
    /// 目标次数来自 `settings.weeklyGoal`（ROADMAP 第 5 节：用户可配置，默认 5）。
    /// **不许在这里写死 5**：写死之后用户改了目标，首页还按 5 算，
    /// 「3/5」旁边的进度条与设置面板里说的目标对不上，而他没有任何办法知道哪个是真的。
    public var weekProgress: (done: Int, goal: Int) { (stats.weeklyDone, stats.weeklyGoal) }

    // MARK: - 首页四格

    /// 首页四格。顺序与 id 固定，视图按顺序渲染即可。
    ///
    /// **四格里没有一格是分数、评级或水平判断**（DEFINITION-OF-DONE 第 4 节）。
    /// `HomeStatsTests.testNoScorePredictionInAnyUserFacingText` 把这四格的每一个字段
    /// 连同趋势文案一起扫一遍，命中禁用词就红。
    public var statTiles: [StatTile] {
        [weekTile, totalTile, minutesTile, improvingTile]
    }

    private var weekTile: StatTile {
        var footnote: String
        if stats.weeklyDone >= stats.weeklyGoal {
            footnote = "本周目标已经完成。下一步：想继续练就继续，目标只是下限，不是上限。"
        } else {
            footnote = "离本周目标还差 \(stats.weeklyGoal - stats.weeklyDone) 次。"
                + "下一步：回到上面点「开始练习」，再练一场。"
        }
        // 读不出时间的那几场不能悄悄消失：用户明明练过，本周次数却不动，
        // 不说清楚他只会以为工具坏了（铁律 7）。
        if stats.undatedSessionCount > 0 {
            footnote += "另有 \(stats.undatedSessionCount) 场练习读不出时间，没能算进本周。"
                + "下一步：到训练记录页核对这几场。"
        }
        return StatTile(id: StatTile.weekID, caption: "本周训练",
                        value: "\(stats.weeklyDone)/\(stats.weeklyGoal)",
                        unit: "次", footnote: footnote)
    }

    private var totalTile: StatTile {
        let footnote = stats.totalSessions == 0
            ? "还没有任何练习记录。下一步：回到上面点「开始练习」，练第一场。"
            : "从第一场到现在的全部练习都算在里面。下一步：到训练记录页可以逐场回看。"
        return StatTile(id: "total", caption: "累计训练",
                        value: "\(stats.totalSessions)", unit: "次", footnote: footnote)
    }

    private var minutesTile: StatTile {
        var footnote = "按每场练习的开始与结束时间统计。"
        if stats.sessionsMissingDuration > 0 {
            footnote += "有 \(stats.sessionsMissingDuration) 场没有结束时间，没算进去。"
                + "下一步：练完记得点「我练完了」，时长才会被记上。"
        }
        if stats.cappedSessionCount > 0 {
            let hours = TrainingStats.maxCountedMinutesPerSession / 60
            footnote += "有 \(stats.cappedSessionCount) 场超过 \(hours) 小时，"
                + "已按 \(hours) 小时计入（多半是忘了点结束）。"
                + "下一步：到训练记录页核对这几场。"
        }
        if stats.sessionsMissingDuration == 0 && stats.cappedSessionCount == 0 {
            footnote += "下一步：想让这个数字变大，就多练几场，不用刻意拉长单场时间。"
        }
        return StatTile(id: "minutes", caption: "本周开口时长",
                        value: "\(stats.weeklySpokenMinutes)", unit: "分钟", footnote: footnote)
    }

    /// 第四格。**这里不是分数、不是评级。** 它是「问题档案里趋势为
    /// 『最近没再出现』或『出现变少了』的毛病有几个」——一个用户能自己数出来核对的计数。
    private var improvingTile: StatTile {
        let footnote: String
        if stats.trackedIssueCount == 0 {
            footnote = "问题档案还是空的。"
                + "下一步：练一场并让 ChatGPT 生成复盘，反复出现的毛病会自动记到这里。"
        } else if stats.totalSessions < IssueTrendAnalyzer.minimumSessionsForTrend {
            // 场次不够时说「0 个毛病在变少」会被误读成「一点没进步」。
            // 必须说清是「还看不出来」，并给出还差几场。
            let needed = IssueTrendAnalyzer.minimumSessionsForTrend - stats.totalSessions
            footnote = "练习场次还不够，暂时看不出哪个毛病在变少。"
                + "下一步：再练 \(needed) 次，这里会自动开始显示。"
        } else {
            footnote = "档案里一共 \(stats.trackedIssueCount) 个问题，这里只数「最近变少了」的那些。"
                + "下一步：到问题档案页看每个毛病的具体变化。"
        }
        return StatTile(id: "improving", caption: "出现变少的毛病",
                        value: "\(stats.improvingIssueCount)", unit: "个", footnote: footnote)
    }

    /// 首页的「你的问题正在怎么变化」列表：按出现次数取最要紧的五条。
    /// 剩下的去问题档案页看——首页塞十几条只会让人不想看。
    ///
    /// 排序与趋势**原样**来自 `IssueArchiveViewModel`，这里不另排一份：
    /// 首页和问题档案页给出两套顺序的话，用户不知道该信哪个，
    /// 而只有视图模型那一处有测试守着。
    public var issueChanges: [IssueArchiveRow] {
        Array(IssueArchiveViewModel(state: state, calendar: calendar).rows.prefix(5))
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
