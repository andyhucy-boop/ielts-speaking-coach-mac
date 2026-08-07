import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 今日训练页：用户每天打开 App 的第一眼。
///
/// 这一页要回答三个问题——今天练什么、这周练够了没有、上次练的是什么。
///
/// **最要紧的一条：四条路线只显示前提成立的那几条**（`TodayViewModel.availableRoutes`）。
/// 显示一条点了没用的路线，比不显示更糟：用户点下去什么也不发生，会以为程序坏了。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `PrimaryActionCard` / `SectionHeader` /
/// `EmptyStateView`、`Palette` / `Spacing` / `Radius` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
@MainActor
struct TodayView: View {
    let app: AppState
    /// 空状态那个按钮要把用户送到「训练题库」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `ReviewReportView`、`PlaceholderView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void
    /// 「本周训练」那一格里的「改目标」按钮翻的就是它。
    ///
    /// **是 `@Binding` 而不是本页自己的 `@State`**：`RootView` 工具栏那颗齿轮翻的是同一份，
    /// 各存各的话两颗按钮会开出两张不同的面板，其中一张改完另一张显示的还是旧值。
    /// 面板本身挂在 `RootView` 上（`WeeklyGoalSheet`），这一页只负责把开关翻过去。
    @Binding var showingWeeklyGoal: Bool

    /// 正在进行的这一场。非 nil 时弹出 `PracticeSheet`，由它驱动 ChatGPT。
    ///
    /// **这就是 Task 9 的交付物**：点一下就真的开练，全程不需要打开终端（成品标准第 2 条）。
    /// 上一版这里弹的是一张写着 `swift run coach practice <id>` 的卡片。
    @State private var launch: PracticeLaunch?

    private var model: TodayViewModel { TodayViewModel(state: app.state) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header
                // 题库空时整页只做一件事：把用户送去导入。
                //
                // 判据用「题库是不是空的」而不是「有没有可用路线」：两者现在等价
                // （`availableRoutes` 在题库空时返回空数组），但它们说的不是同一件事——
                // 「一条路线都排不出来」还有别的成因，那种情况该显示的是 `noRouteCard`
                // 那句「到训练题库看一眼题库是不是正常」。对一个刚装好、还没导过题库的人说
                // 「你的题库可能不正常」，只会让他去找一个根本不存在的毛病。
                //
                // `TodayViewTests.testEmptyBankTakesOverTheWholePageInsteadOfShowingRoutes` 钉着这个分支。
                if app.state.questions.isEmpty {
                    emptyBank
                } else {
                    // 四格摆在这一支里而不是页头，是因为它们的脚注里写着
                    // 「点下面的「开始练习」」——题库空的时候那颗按钮根本不在页面上，
                    // 照着做的人会一直找。同屏矛盾指令这个坑，本项目在权限页上踩过一次。
                    //
                    // **下面这个顺序不是随手排的**：`statsRow` 在 `routes` 前面，
                    // 所以那句话里的方向词必须是「下面」。挪动这两段的先后时要一起改文案，
                    // `TodayViewTests.testTileFootnotesPointTowardWhereTheStartButtonActuallyIs`
                    // 会把没改的那一次拦下来。
                    statsRow
                    recordingNotice
                    routes
                    recentPractice
                    issueTrends
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        // 重读放在 onDismiss 上而不是 onClose 里：存档会改 state.json（错题本、词汇本、
        // 复训目标、计划进度），不重读的话这一页显示的还是开练之前那份，用户会以为没生效。
        // 挂在 onDismiss 上，是为了让「不是从按钮走的那些关闭方式」也照样重读。
        .sheet(item: $launch, onDismiss: { app.reload() }) { launch in
            PracticeSheet(runner: launch.runner,
                          route: launch.route,
                          preselected: launch.preselected,
                          candidates: model.pickableQuestions,
                          makeSetup: { model.practiceSetup(question: $0, route: launch.route) },
                          onClose: { self.launch = nil })
        }
    }

    /// 点这条路线上那颗按钮之后干什么。
    ///
    /// **「复训一个旧问题」不在这一页开练**：复训要先挑目标、回看证据、撤掉提示，
    /// 之后才开口（Phase 6 的三步流程）。在这里直接弹练习 sheet 的话，那一场既不带单点目标、
    /// 也不会挂进复训台账——用户以为自己在复训，其实只是又练了一道题，而且看不出任何异样。
    private func act(_ route: PracticeRoute) {
        guard route != .retrain else {
            // 不预先选目标：复训中心按 `RetrainingPolicy.rank` 排的第一条就是最该练的那个，
            // 这一页再挑一次只会给出第二套说法。
            app.navigation.openRetrainingCenter(preselecting: nil)
            return
        }
        startPractice(route)
    }

    /// 这条路线的按钮上写什么。**「复训一个旧问题」不能也叫「开始练习」**：
    /// 点下去是换一页，不是开练，写「开始练习」就是骗人。
    private func actionTitle(_ route: PracticeRoute) -> String {
        route == .retrain ? "去复训中心" : "开始练习"
    }

    /// 开一场新的练习。**每一场都新造一台驱动器**：它带着「这一场是哪道题」的状态，
    /// 复用同一台会让上一场的残留影响下一场。
    private func startPractice(_ route: PracticeRoute) {
        launch = PracticeLaunch(
            route: route,
            preselected: model.plannedQuestion(for: route)
                .map { model.practiceSetup(question: $0, route: route) },
            runner: app.makePracticeRunner())
    }

    // MARK: - 顶部：问候与日期

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(number: 1, label: "TODAY", title: SidebarItem.today.title)
            Text("\(greeting)。今天是 \(Self.dayDisplay.string(from: Date()))。")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var greeting: String {
        let name = app.state.learner.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let period: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: period = "早上好"
        case 12..<18: period = "下午好"
        case 18..<23: period = "晚上好"
        default: period = "夜深了"
        }
        // 还没填过名字时不硬凑一个称呼——「早上好，」后面挂个空字符串比不称呼更难看。
        return name.isEmpty ? period : "\(period)，\(name)"
    }

    // MARK: - 四格统计

    /// 首页四格。**内容一格不落地来自 `TodayViewModel.statTiles`**，这里不另算一份：
    /// 视图里现拼的数字与文案没有任何测试管得住，而「绝不预测分数」那条红线
    /// （`HomeStatsTests.testNoScorePredictionInAnyUserFacingText`）正是扫那四格的字符串。
    ///
    /// 窗口窄时自动折成两行（`.adaptive`）：四格挤成一条会把脚注压成一列单字，
    /// 而脚注正是「下一步做什么」所在的地方，不能因为窗口小就读不了。
    private var statsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.md)],
                  alignment: .leading, spacing: Spacing.md) {
            ForEach(model.statTiles) { tile in
                statCard(tile)
            }
        }
    }

    private func statCard(_ tile: StatTile) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(tile.caption)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    // 等宽数字（规范第 1 节末行、第 6 节最后一条）：「3/5」跳到「10/5」、
                    // 「9」跳到「10」时整行不许横向抖一下。`Typography.number` 自带
                    // `.monospacedDigit()`，这里再写一次是为了让这条要求在视图上看得见。
                    Text(tile.value)
                        .font(Typography.number)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text(tile.unit)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }

                if tile.id == StatTile.weekID { weekProgressBar }

                // **脚注不许因为「太长了不好看」就不显示**：它是这一格里唯一说清
                // 「下一步做什么」的地方（铁律 6）。
                Text(tile.footnote)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 「本周训练」那一格里的进度条与「改目标」按钮。
    /// 目标次数来自设置（`weekProgress.goal`），不是写死的 5。
    ///
    /// 「改目标」这颗按钮由 Task 9 补齐（Task 8 交付时 `WeeklyGoalSheet` 还不存在，
    /// 先摆一颗点了没反应的按钮是本项目最不能接受的那一类，所以当时按住没做）。
    /// 它翻的是 `RootView` 手上那份 `showingWeeklyGoal`，与工具栏齿轮同一个开关。
    private var weekProgressBar: some View {
        let progress = model.weekProgress
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ProgressView(value: Double(min(progress.done, progress.goal)),
                         total: Double(max(progress.goal, 1)))
                .tint(Palette.accent)
                .accessibilityLabel("本周训练进度")
                .accessibilityValue("\(progress.done) 次，共 \(progress.goal) 次")
            Button("改目标") { showingWeeklyGoal = true }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - 训练记录还没接上，这件事得说出来

    /// 「本周训练 N/5」和「最近练习」这两处，在当前工程里**练完也不会动**——
    /// 没有任何代码往 `state.sessions` 里写记录（见 `TodayViewModel.practiceRecordingIsWired`）。
    ///
    /// 不说这句话的话，用户在这一页练完一整场（Task 9 之后按钮真的会开练），回来看到的还是
    /// 「0/5 次」「还没有练习记录」，只会以为程序坏了（铁律 6、铁律 7）。
    /// 记录接上之后 `unwiredRecordingNotice()` 返回 nil，这块自己就消失。
    ///
    /// 位置在本周进度（头部右侧）与「最近练习」之间：它解释的正是这两处。
    /// 题库空的那一支刻意**不显示**它——那时整页只做「去导入题库」这一件事，
    /// 多一块交代只会分散注意；导完题库回到这一页就会看到。
    @ViewBuilder
    private var recordingNotice: some View {
        if let text = TodayViewModel.unwiredRecordingNotice() {
            CoachCard {
                Label {
                    Text(text)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                }
            }
        }
    }

    // MARK: - 今天练什么：四条路线只显示有意义的

    private var routes: some View {
        let available = model.availableRoutes
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 2, label: "PRACTICE ROUTES", title: "今天练什么？")
            if let primary = available.first {
                // 排在第一位的那条是这一页唯一的主行动（规范第 4 节：每页最多一个）。
                // 其余用 `CoachCard` + 次一级按钮——两个同样醒目的紫色大块会让人不知道该点哪个。
                primaryCard(primary)
                ForEach(Array(available.dropFirst())) { route in
                    secondaryCard(route)
                }
            } else {
                noRouteCard
            }
        }
    }

    private func primaryCard(_ route: PracticeRoute) -> some View {
        PrimaryActionCard(title: route.title,
                          subtitle: route.subtitle,
                          actionTitle: actionTitle(route),
                          action: { act(route) }) {
            routeDetail(route)
        }
    }

    private func secondaryCard(_ route: PracticeRoute) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(route.title)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(route.subtitle)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                    routeDetail(route)
                }
                Spacer(minLength: Spacing.sm)
                Button(actionTitle(route)) { act(route) }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// 每条路线卡片里那几行「具体是什么」。
    ///
    /// 没有这几行，四张卡片就只剩四个动词，用户点之前不知道会练到什么。
    /// 颜色不在这里设：主行动卡片是白字、普通卡片是主文字色，两边各自的容器已经定好了。
    @ViewBuilder
    private func routeDetail(_ route: PracticeRoute) -> some View {
        switch route {
        case .planToday:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // 用下标而不是 `\.id` 做身份：题库正常情况下 id 唯一，但用户手工编辑过
                // state.json 之后未必如此，而 ForEach 遇到重复 id 会错乱地复用行。
                ForEach(Array(model.todayQuestions.enumerated()), id: \.offset) { _, question in
                    Text("Part \(question.part) · \(promptText(question))")
                        .font(Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .continueLast:
            if let last = model.recentSessions.first {
                Text("上次练的：\(questionText(last))")
                    .font(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .retrain:
            if let target = model.liveTarget {
                Text("上次复盘留下的目标：\(target.label)")
                    .font(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .freePick:
            EmptyView()
        }
    }

    /// 题库有题、却一条路线都排不出来。**按现在的规则走不到这里**
    /// （题库非空就至少有「从题库自由选题」），留着是因为 `availableRoutes` 的规则以后会改，
    /// 而那时这里若什么都不画，用户看到的是一块无法解释的空白。
    private var noRouteCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("现在没有可以开始的练习路线")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("题库里有 \(app.state.questions.count) 道题，但四条路线的前提一条都不成立。"
                     + "下一步：到「训练题库」看一眼题库是不是正常，若不正常就重新导入一次。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                Button("去训练题库") { onGo(.questionBank) }
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - 最近练习

    private var recentPractice: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .bottom, spacing: Spacing.md) {
                SectionHeader(number: 3, label: "RECENT PRACTICE", title: "最近练习")
                if !model.recentSessions.isEmpty {
                    Button("看复盘报告") { onGo(.reviewReports) }
                        .buttonStyle(.bordered)
                }
            }
            if model.recentSessions.isEmpty {
                noSessionCard
            } else {
                CoachCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(model.recentSessions.enumerated()), id: \.offset) { index, session in
                            if index > 0 { Divider() }
                            sessionRow(session)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PracticeSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(dateText(session.startedAt))
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(questionText(session))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !session.goal.isEmpty {
                    Text("当时的目标：\(session.goal)")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Spacer(minLength: Spacing.sm)
            reportBadge(session)
        }
    }

    /// 这一次有没有留下复盘。**没留下的那几次必须看得出来**——
    /// 一律画成一样，用户永远不会发现自己有一场练习的复盘没存上（铁律 7）。
    /// 图标只用 SF Symbols，不用 emoji（规范第 4 节）。
    @ViewBuilder
    private func reportBadge(_ session: PracticeSession) -> some View {
        if session.reportPath.isEmpty {
            Label("没有复盘", systemImage: "exclamationmark.triangle")
                .font(Typography.label)
                .foregroundStyle(Palette.warning)
        } else {
            Label("有复盘", systemImage: "doc.text")
                .font(Typography.label)
                .foregroundStyle(Palette.success)
        }
    }

    /// 题库里有题、但一次都还没练过。
    ///
    /// 这里刻意**不用** `EmptyStateView`：它的按钮是紫色实心，而这一页上方已经有一张
    /// 紫色的主行动卡片了（规范第 4 节：每页最多一个主行动）。
    /// 但「说明现状 + 说明下一步 + 一个能直接点的按钮」三样一个不少。
    private var noSessionCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("还没有练习记录")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(noSessionHint)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                Button("去训练题库看看有哪些题") { onGo(.questionBank) }
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    /// 这句话必须和上面那块 `recordingNotice` 对得上。
    ///
    /// 原来的写法无条件承诺「练完第一场之后，这里会按时间倒序列出最近五次」——而这一版练完
    /// 它也不会变，那就成了同一屏上两条互相矛盾的话，用户多半照着做得到的那条去做，
    /// 然后发现没用。本项目在权限页上吃过一次同屏矛盾指令的亏（见 `PermissionGateView` 的说明），
    /// 修法一样：不在视图里挑着显示，而是让两处都跟着同一个 `practiceRecordingIsWired` 走。
    private var noSessionHint: String {
        guard TodayViewModel.practiceRecordingIsWired else {
            return "这一版还不会把练习记录存进训练数据，所以练完之后这里仍然是空的"
                + "（上面那条说明写了详情）。下一步：用上面那张紫色卡片直接开练——"
                + "练出来的错题、词汇和复训目标都会正常入库，这一场不会白练。"
        }
        return "练完第一场之后，这里会按时间倒序列出最近五次：练的哪道题、当时定的目标、"
            + "复盘有没有存下来。下一步：用上面那张紫色卡片开始第一场；"
            + "想先看看有哪些题可以练，就去「训练题库」翻一翻。"
    }

    // MARK: - 你的问题正在怎么变化

    /// 首页只放最要紧的五条，剩下的去问题档案页看（`TodayViewModel.issueChanges`）。
    ///
    /// **这一块不出现任何分数、评级或水平判断**（成品标准第 4 节第一条）：
    /// 每条只说「这个毛病在几场练习里犯过、最近有没有变少」。
    /// 顺序与趋势原样来自视图模型，这一页不排、不筛、不藏——
    /// 首页和问题档案页给出两套顺序的话，用户不知道该信哪个。
    private var issueTrends: some View {
        let rows = model.issueChanges
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 4, label: "ISSUE TRENDS", title: "你的问题正在怎么变化")
            if rows.isEmpty {
                noIssueCard
            } else {
                CoachCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // 用下标做身份：state.json 被外部工具改坏时会出现重复的错题 id，
                        // 而 ForEach 遇到重复 id 会错乱地复用行。
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider() }
                            issueRow(row)
                        }
                    }
                }
                Button("查看全部问题") { onGo(.issues) }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// 一条 = 一个毛病。**趋势的颜色只是辅助，`badge` 那几个字始终在**——
    /// 只靠颜色区分，对色觉障碍用户等于没有标记（规范第 4 节）。
    /// 颜色取 `IssueArchiveView.trendColor`，两页共用一处，不各画各的。
    private func issueRow(_ row: IssueArchiveRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("当时说的：\(row.learnerSaid)")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.detail)
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(row.trend.badge)
                    .font(Typography.label)
                    .foregroundStyle(IssueArchiveView.trendColor(row.trend))
                // 等宽数字：从 9 跳到 10 时这一列不许横向抖（规范第 6 节最后一条）。
                Text("\(row.occurrences) 次")
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// 还没记到任何反复出现的问题。
    ///
    /// 与 `noSessionCard` 同一个理由，这里刻意**不用** `EmptyStateView`：
    /// 它的按钮是紫色实心，而这一页上方已经有一张紫色的主行动卡片了
    /// （规范第 4 节：每页最多一个主行动）。三样一个不少：说明现状、说明下一步、
    /// 一个能直接点的按钮。
    private var noIssueCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("还没有记录到反复出现的问题")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("练一场并让 ChatGPT 生成复盘，这里就会开始积累：哪个毛病犯过几场、"
                     + "最近有没有变少。下一步：点下面的「开始练习」，练一场。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 走 `act` 而不是直接开练：排在第一位的那条就是这一页的主行动，
                // 两处各挑各的会给出两套说法。`?? .freePick` 只是兜底——
                // 这一整块只在题库非空时才渲染，那时 `availableRoutes` 至少有「从题库自由选题」。
                Button("开始练习") { act(model.availableRoutes.first ?? .freePick) }
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - 题库还是空的

    /// 题库空时整页只显示这一件事。三样缺一不可：说明现状、说明下一步、一个能直接点的按钮。
    private var emptyBank: some View {
        EmptyStateView(
            message: "题库还是空的",
            hint: "没有题目，四条练习路线一条都走不通。"
                + "下一步：到「训练题库」页导入你的题库文件（\(QuestionBankImport.supportedExtensionList)），"
                + "导完回到这一页就能开始。",
            actionTitle: "去训练题库",
            action: { onGo(.questionBank) })
    }

    // MARK: - 文案小工具

    private func promptText(_ question: Question) -> String {
        question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt
    }

    private func questionText(_ session: PracticeSession) -> String {
        if let question = app.state.questions.first(where: { $0.id == session.questionId }) {
            return promptText(question)
        }
        return session.questionId.isEmpty
            ? "（这次练习没有记下题目）"
            : "（题库里已经没有这道题了：\(session.questionId)）"
    }

    private static let timestampParser = ISO8601DateFormatter()

    private static let dateDisplay: DateFormatter = {
        let formatter = DateFormatter()
        // 不写死格式，跟随用户在系统里设的地区。
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// 认不出来的时间戳原样显示，**不显示成空白**——空白会让人以为这一行坏了。
    private func dateText(_ iso: String) -> String {
        guard let date = Self.timestampParser.date(from: iso) else { return iso }
        return Self.dateDisplay.string(from: date)
    }
}

/// 一场正要开始的练习：走哪条路线、题定下来了没有、以及驱动它的那台运行器。
///
/// 每按一次「开始练习」都新造一份（含一台新的 `PracticeRunner`）：运行器带着
/// 「这一场是哪道题」的状态，复用同一台会让上一场的残留影响下一场。
struct PracticeLaunch: Identifiable {
    let id = UUID()
    let route: PracticeRoute
    /// 已经替用户定下来的这一场；nil 表示要在 sheet 里先挑一道题。
    let preselected: SessionSetup?
    let runner: PracticeRunner
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("题库还是空的") {
    TodayView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-today")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in },
        showingWeeklyGoal: .constant(false))
}

// 点了「开始练习」之后弹出来的那张 sheet 的预览在 `Session/PracticeSheet.swift` 里，
// 且刻意用一个一次也不碰真实 ChatGPT 的空壳 Bridge（铁律 5）。
