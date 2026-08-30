import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 今日训练页：用户每天打开 App 的第一眼。
///
/// 这一页要回答三个问题——今天练什么、这周练够了没有、上次练的是什么。
///
/// **最要紧的一条：显示出来的每一条路线，点下去一定能开练。**
/// 排路线与解析路线走的是同一段代码（`PracticeRouteResolver`），不是两处各判一次——
/// Phase 3 的前提判断只问「有没有计划 / 有没有记录 / 有没有目标」，而前提成立不等于
/// 开得了练：今天那道题可能已被换季导入删掉、复训目标的来源记录可能被单条删过。
/// 显示一条点了没用的路线，比不显示更糟：用户点下去什么也不发生，会以为程序坏了。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `PrimaryActionCard` / `SectionHeader` /
/// `EmptyStateView`、`Palette` / `Spacing` / `Radius` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
@MainActor
struct TodayView: View {
    let app: AppState
    /// 空状态那个按钮要把用户送到「训练题库」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `ReviewReportView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void
    /// 「改目标」那颗按钮要把设置窗口停到哪一栏。
    ///
    /// **它和 `RootView` 工具栏那颗齿轮是同一个对象**（由 App 层下发）：
    /// 两颗按钮打开的是**同一个窗口**的同一栏，不是各弹各的面板。
    let navigator: SettingsNavigator
    /// 打开 ⌘, 那个设置窗口。用系统给的这一个，不要私有 selector。
    @Environment(\.openSettings) private var openSettings

    /// 正在进行的这一场。非 nil 时弹出 `PracticeSheet`，由它驱动 ChatGPT。
    ///
    /// **这就是 Task 9 的交付物**：点一下就真的开练，全程不需要打开终端（成品标准第 2 条）。
    /// 上一版这里弹的是一张写着 `swift run coach practice <id>` 的卡片。
    @State private var launch: PracticeLaunch?

    /// 每条路线上一次「点了却开不了」时，解析器给出的那句中文说明。
    ///
    /// **必须存在页面状态里，不能一闪而过**：那段文字本身写的就是下一步该做什么
    /// （「到「学习计划」页重新生成计划，已经练过的进度不会丢」这一类），
    /// 一闪就没了等于没说，而用户这时候正想开练。
    ///
    /// 按路线分开存：三张卡片同时挂着各自的说明是正常的，共用一处会互相盖掉。
    @State private var blockedRoutes: [PracticeRoute: String] = [:]

    private var model: TodayViewModel { TodayViewModel(state: app.state) }

    /// 开一场练习要用的那两项用户偏好（考官何时给反馈、Part 2 的一分钟怎么处理）。
    ///
    /// **不能省。** 省掉的话 `SessionSetup` 会走参数默认值，于是用户在学习计划页
    /// 把「反馈时机」改成「当场点出」之后，从这一页开的每一场仍然是全程零反馈，
    /// 而界面上一个字都不会提——界面显示的状态和真实行为对不上（铁律 7）。
    private var defaults: RouteDefaults { RouteDefaults(settings: app.state.settings) }

    /// 用户在学习计划页选的默认练习路线。它决定卡片的顺序，也就决定哪一张是主行动。
    private var preferredRoute: PracticeRoute {
        PracticeRoutePreference.route(fromSettings: app.state.settings.defaultRoute)
    }

    /// 这一页现在真的能开练的那几条路线，默认路线排在最前面。
    ///
    /// **走解析器而不是 `TodayViewModel.availableRoutes`**：后者只判前提成立，
    /// 而 `PracticeRouteResolver.availableRoutes` 是拿解析同一条路线的那段代码试着解一遍，
    /// 解得出来才收进列表——这是「显示出来的每一条都点得动」唯一守得住的做法
    /// （`PracticeRouteResolverTests.testEveryShownRouteCanActuallyStart` 钉着这条不变量）。
    private var availableRoutes: [PracticeRoute] {
        PracticeRouteResolver.availableRoutes(state: app.state,
                                              preferring: preferredRoute, defaults: defaults)
    }

    var body: some View {
        CoachPage {
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
                    weekBars
                    recordingNotice
                    // 摆在路线**上面**：这是一条要他当场决定的事，
                    // 排到下面去的话，他会先开始新的一场，然后那条旧记录
                    // 会一直挂在那儿每天问他一遍。
                    unfinishedSessionCard
                    routes
                    recentPractice
                    issueTrends
                }
        }
        // 重读放在 onDismiss 上而不是 onClose 里：存档会改 state.json（错题本、词汇本、
        // 复训目标、计划进度），不重读的话这一页显示的还是开练之前那份，用户会以为没生效。
        // 挂在 onDismiss 上，是为了让「不是从按钮走的那些关闭方式」也照样重读。
        .sheet(item: $launch, onDismiss: { app.reload() }) { launch in
            PracticeSheet(runner: launch.runner,
                          route: launch.route,
                          preselected: launch.preselected,
                          candidates: model.pickableQuestions,
                          // 弹层里默认勾上的那几个 Part 跟着学习计划的「重点 Part」走，
                          // 两处 Part 选择因此看起来是一件事的两个层次，而不是两套设置。
                          // 规则在 `PracticePicker.defaultParts(forPlanFocus:)`（那边有测试）；
                          // 在这儿另写一遍的话，两处迟早给出不同的默认值。
                          defaultParts: PracticePicker.defaultParts(
                              forPlanFocus: app.state.plan?.focusPart),
                          planFocusPart: app.state.plan?.focusPart,
                          // 在弹层里当场挑的那道题同样走解析器的取值，不在这里另拼一份：
                          // 另拼的那份一定会漏掉 feedbackTiming / part2PrepMode，
                          // 于是「自由选题」这条路线成了唯一不听用户练习偏好的一条。
                          //
                          // 第二个参数是用户在弹层上当场勾出来的那几个 Part。
                          // 丢掉它，那三个勾选框就成了点得动、却什么都不改的装饰品。
                          //
                          // **走 `chosen:` 而不是 `mode:`**：`mode:` 是给学习计划的
                          // 重点 Part 用的，会被过滤，三个全勾会被静默降级成单 Part。
                          // 一个都没勾（mode 为 nil）时才回到「按题目自己的 Part 考」。
                          //
                          // `bank:` 是给「这张 cue card 自己那组 Part 3 追问」配对用的
                          //（`LinkedPart3`）；不传的话连着练那一场会白白扔掉题库里的真题。
                          //
                          // 第三个参数是他在弹层里写的那句「这一场只盯什么」。
                          // 丢掉它的话，那个输入框就成了打得进字、却什么都不改的装饰品——
                          // 而整条管道（考官提示词的「本次唯一目标」、训练记录、复盘请求）
                          // 早就修好了在等它。
                          makeSetup: { question, mode, goal in
                              guard let mode else {
                                  return PracticeRouteResolver.setup(
                                      for: question, goal: goal, defaults: defaults,
                                      bank: app.state.questions)
                              }
                              return PracticeRouteResolver.setup(
                                  for: question, goal: goal, defaults: defaults,
                                  chosen: mode, bank: app.state.questions)
                          },
                          // 抽出来的一整组同样走解析器取值，不在这里另拼一份：
                          // 另拼的那份一定会漏掉 feedbackTiming / part2PrepMode，
                          // 而且时长与考法要按**真的抽到的**那几段算（见那个方法的说明）。
                          makeDrawSetup: { draw, goal in
                              PracticeRouteResolver.setup(forDraw: draw, goal: goal,
                                                          defaults: defaults,
                                                          bank: app.state.questions)
                          },
                          onClose: { self.launch = nil })
        }
    }

    /// 点这条路线（或路线里某一道题）之后干什么。
    ///
    /// **「复训一个旧问题」不在这一页开练**：复训要先挑目标、回看证据、撤掉提示，
    /// 之后才开口（Phase 6 的三步流程）。在这里直接弹练习 sheet 的话，那一场既不带单点目标、
    /// 也不会挂进复训台账——用户以为自己在复训，其实只是又练了一道题，而且看不出任何异样。
    ///
    /// 其余三条一律**先解析一次**，两种结果各有各的去处：解得出来就开练，
    /// 解不出来就把解析器那句中文留在这张卡片下面。只处理 `.ready`、把 `.unavailable`
    /// 丢掉的话，用户点下去界面纹丝不动——本项目最不能接受的那一类。
    ///
    /// - Parameter questionID: 用户在今日题目列表里点的那一道；nil 表示由解析器决定
    ///   （「按计划练今天」自动挑今天第一道没练的）。
    private func act(_ route: PracticeRoute, questionID: String? = nil) {
        guard route != .retrain else {
            // 不预先选目标：复训中心按 `RetrainingPolicy.rank` 排的第一条就是最该练的那个，
            // 这一页再挑一次只会给出第二套说法。
            app.navigation.openRetrainingCenter(preselecting: nil)
            return
        }
        // 「从题库自由选题」的题目本来就要用户当场挑。还没挑时解析器会说「还没选题。
        // 下一步：先在题目列表里点一道题」——那句话在这里不是故障而是流程的下一步，
        // 而且这张卡片上根本没有题目列表，摆出来等于把用户指向一个不存在的地方（铁律 6）。
        // 所以直接开挑题弹层，题目在那儿选。
        // 「随机抽题」同理，而且更彻底：它**任何时候**都要先进弹层
        //（数量、练过的要不要、按抽题，三步都在那儿），解析器永远解不出一场来。
        if route == .randomDraw || (route.picksMaterialInTheSheet && questionID == nil) {
            blockedRoutes[route] = nil
            startPractice(route, setup: nil)
            return
        }
        switch PracticeRouteResolver.resolve(route: route, state: app.state,
                                             selectedQuestionID: questionID, defaults: defaults) {
        case .ready(let setup):
            // 上一次挡住这条路线的那句话要清掉，否则开练之后它还挂在卡片下面，
            // 用户会以为这一场没真的开起来。
            blockedRoutes[route] = nil
            startPractice(route, setup: setup)
        case .unavailable(let message):
            blockedRoutes[route] = message
        }
    }

    /// 这条路线的按钮上写什么。**「复训一个旧问题」不能也叫「开始练习」**：
    /// 点下去是换一页，不是开练，写「开始练习」就是骗人。
    private func actionTitle(_ route: PracticeRoute) -> String {
        route == .retrain ? "去复训中心" : "开始练习"
    }

    /// 开一场新的练习。**每一场都新造一台驱动器**：它带着「这一场是哪道题」的状态，
    /// 复用同一台会让上一场的残留影响下一场。
    ///
    /// - Parameter setup: 已经解析定下来的这一场；nil 表示题目要在 sheet 里当场挑
    ///   （「从题库自由选题」）。
    private func startPractice(_ route: PracticeRoute, setup: SessionSetup?) {
        launch = PracticeLaunch(route: route, preselected: setup, runner: app.makePracticeRunner())
    }

    // MARK: - 顶部：问候与日期

    private var header: some View {
        PageHeader(number: 1, label: "TODAY", title: SidebarItem.today.title,
                   lede: "\(greeting)。今天是 \(Self.dayDisplay.string(from: Date()))。")
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
        // **`alignment: .top` 不是可选项。** `GridItem` 的纵向对齐默认是居中，
        // 而这四格高度天差地别（「本周训练」那格多一根进度条和一颗按钮，
        // 「出现变少的毛病」那格的脚注有四行）。居中的结果是四张卡片的上下边
        // 各自错开十几点，看着就像布局坏了——这是改版前首页最扎眼的一处。
        // 顶对齐 + 每格纵向撑满（见 `statCard`），四条上边和四条下边才各自齐平。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.md,
                                     alignment: .top)],
                  alignment: .leading, spacing: Spacing.md) {
            ForEach(model.statTiles) { tile in
                statCard(tile)
            }
        }
    }

    private func statCard(_ tile: StatTile) -> some View {
        let isWeek = tile.id == StatTile.weekID
        return CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(tile.caption)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    // 等宽数字（规范第 1 节末行、第 6 节最后一条）：「3/5」跳到「10/5」、
                    // 「9」跳到「10」时整行不许横向抖一下。`Typography.number` 自带
                    // `.monospacedDigit()`，这里再写一次是为了让这条要求在视图上看得见。
                    // 「本周训练」那一格用最大的那一档：这一页真正要看的就是它，
                    // 四格全用同一个字号等于一个都没突出（见 `Typography.numberHero`）。
                    Text(tile.value)
                        .font(isWeek ? Typography.numberHero : Typography.number)
                        .monospacedDigit()
                        .foregroundStyle(isWeek ? Palette.accent : Palette.textPrimary)
                    Text(tile.unit)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }

                if tile.id == StatTile.weekID { weekProgressBar }

                // **脚注不许因为「太长了不好看」就不显示**：它是这一格里唯一说清
                // 「下一步做什么」的地方（铁律 6）。
                //
                // 它同时是这一格里最长的一段中文，所以要加行距——不加的话
                // 四行方块字会糊成一堵墙，而墙里写的正是下一步该干什么。
                Text(tile.footnote)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .coachParagraph()

                // 把这一格纵向撑满，四张卡片的下边才齐平（配合上面那个 `.top`）。
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 「本周训练」那一格里的进度条与「改目标」按钮。
    /// 目标次数来自设置（`weekProgress.goal`），不是写死的 5。
    ///
    /// 「改目标」这颗按钮打开的是**设置窗口本体**，并停在「训练目标」那一栏
    /// （Phase 10 Task 16）。从前它弹的是一张这一页专用的小面板，
    /// 于是每周目标有了两份界面——那正是这次合并要消灭的东西。
    ///
    /// **首页这颗按钮不撤。** 这一格写着「本周 3/5 次」，旁边不给一个改目标的入口，
    /// 用户看得见目标却不知道去哪儿改；而深链接同时满足两边：
    /// 一个窗口、一份状态、两条到达路径。
    private var weekProgressBar: some View {
        let progress = model.weekProgress
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ProgressView(value: Double(min(progress.done, progress.goal)),
                         total: Double(max(progress.goal, 1)))
                .tint(Palette.accent)
                .accessibilityLabel("本周训练进度")
                .accessibilityValue("\(progress.done) 次，共 \(progress.goal) 次")
            // 不用 `.link` 样式：那个样式画的是**系统强调色**，不在 `Palette` 里，
            // 也就不受那张对比度矩阵管，深色下更不跟着走。
            Button("改目标") { navigator.open(.goals); openSettings() }
                .buttonStyle(.plain)
                .font(Typography.label)
                .foregroundStyle(Palette.accent)
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
            NoticeCard(.warning, text)
        }
    }

    // MARK: - 今天练什么：四条路线只显示有意义的

    private var routes: some View {
        let available = availableRoutes
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 2, label: "PRACTICE ROUTES", title: "今天练什么？")
            if available.isEmpty {
                noRouteCard
            } else {
                // 顺序原样来自解析器（默认路线在最前），这一页不再排一次。
                // **排在第一位的那条是这一页唯一的主行动**（规范第 4 节：每页最多一个），
                // 所以「哪一张是主行动」只能按顺序第一张定，不能另挑一条——
                // 另挑的话，用户在学习计划页改了默认路线，最醒目的那块却纹丝不动。
                ForEach(Array(available.enumerated()), id: \.element) { index, route in
                    routeBlock(route, isPrimary: index == 0)
                }
            }
        }
    }

    /// 一条路线在页面上占的那一块：卡片本身 + 它下面那句「刚才为什么开不了」。
    ///
    /// 两样必须绑在一起画。说明单独摆在别处的话，三张卡片各自的失败原因就分不清是谁的了。
    @ViewBuilder
    private func routeBlock(_ route: PracticeRoute, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isPrimary {
                primaryCard(route)
            } else {
                // 次一级用 `CoachCard` + 次一级按钮——两个同样醒目的紫色大块
                // 会让人不知道该点哪个。
                secondaryCard(route)
            }
            blockedNotice(route)
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

    /// 次一级的路线卡片。**整块可点**（`CoachActionCard`）。
    ///
    /// 改版前这里是「卡片 + 右上角一颗 `.bordered` 按钮」，而卡片有一千点宽：
    /// 标题在最左、按钮在最右，中间一大片空白。卡片本来就长得像能点的东西，
    /// 用户第一下多半点在卡片上，然后什么也不发生。
    ///
    /// 主色仍然只给第一张（`primaryCard`）——规范第 4 节：每页最多一个主行动。
    private func secondaryCard(_ route: PracticeRoute) -> some View {
        CoachActionCard(actionLabel: "\(route.title)。\(actionTitle(route))",
                        action: { act(route) }) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(route.title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(route.subtitle)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                routeDetail(route)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    /// 这条路线刚才点下去为什么没开起来。
    ///
    /// **那段文字要一直留在卡片下面，直到这条路线真的能开练。** 它本身写的就是
    /// 下一步该做什么（「到「学习计划」页重新生成计划，已经练过的进度不会丢」这一类），
    /// 做成几秒后自动消失的浮层等于没说，而用户这时候正想开练。
    ///
    /// 文字可选中：用户要把这句话复制去核对题目 id 或者反馈给开发者。
    @ViewBuilder
    private func blockedNotice(_ route: PracticeRoute) -> some View {
        if let message = blockedRoutes[route] {
            NoticeCard(.warning, message)
        }
    }

    /// 本周七天各练了几次。四格上面那个「3/5」只说了总数，
    /// 这一排说的是**节奏**：是三天各练一次，还是周日一口气补了三次。
    ///
    /// **读不出时间的那几场不在这里**，那件事由「本周训练」那一格的脚注说
    ///（两处各说一遍是骚扰，一处都不说才是静默）。
    private var weekBars: some View {
        let bars = model.weekBars
        let peak = max(bars.map(\.count).max() ?? 0, 1)
        return CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("本周节奏")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                // **一根柱子都没有时要说一句话。** 七个空槽不配任何文字，
                // 看着就是一块没画完的东西——而本项目对空状态的要求是
                // 「说清现状」（铁律 6）。下一步不在这儿说：上面「本周训练」那一格
                // 的脚注已经写着「点下面的「开始练习」」，两处各说一遍是骚扰。
                if bars.allSatisfy({ $0.count == 0 }) {
                    Text("这周还没有练过。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    ForEach(bars) { bar in
                        VStack(spacing: Spacing.xs) {
                            // 等宽数字：某一天从 1 跳到 2 时这一列不该横向抖。
                            Text(bar.count > 0 ? "\(bar.count)" : " ")
                                .font(Typography.label)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                            // **画一整条底槽，柱子长在里面。** 改版前没练的那天只画一根
                            // 4pt 高的小墩子，七天连起来像一排断掉的东西；有了底槽，
                            // 「这天是 0」和「这天练了 2 次」才是同一把尺子上的两个读数。
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: Radius.control)
                                    .fill(Palette.surfaceSubtle)
                                    .frame(height: 44)
                                RoundedRectangle(cornerRadius: Radius.control)
                                    .fill(bar.isToday ? Palette.accent : Palette.cardBorderStrong)
                                    .frame(height: max(bar.count > 0 ? 8 : 0,
                                                       CGFloat(bar.count) / CGFloat(peak) * 44))
                            }
                            .frame(maxWidth: .infinity)
                            Text(bar.isToday ? "今" : bar.label)
                                .font(Typography.label)
                                .foregroundStyle(bar.isToday
                                                 ? Palette.accent : Palette.textSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("周\(bar.label)练了 \(bar.count) 次")
                    }
                }
            }
        }
    }

    /// **上一场练习没有正常结束**（崩溃、误关窗口、Mac 重启）时那张卡片。
    ///
    /// 在这之前，一场练习在按下「我练完了」之前磁盘上一个字都没有，
    /// 中途崩掉就等于没发生过。现在开练那一刻就占好位置、逐字稿边采边存
    /// （`PracticeRunner.beginSessionRecord`），这张卡片是它的出口。
    ///
    /// **两颗按钮都要有，一颗都不能省**：自动收下会让「本周训练」凭空多一次
    /// （他可能只是开了个头就去干别的了），自动丢掉丢的是他半小时的东西。
    /// 这两种情况在数据上分不开，分得开的唯一办法是问他（见 `UnfinishedSession`）。
    @ViewBuilder
    private var unfinishedSessionCard: some View {
        if let session = UnfinishedSession.pending(in: app.state) {
            NoticeCard(.warning, UnfinishedSession.notice(for: session, in: app.state)) {
                HStack(spacing: Spacing.sm) {
                    Button("存进训练记录") { keepUnfinished(session) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                    Button("丢掉这一场") { discardUnfinished() }
                        .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func keepUnfinished(_ session: PracticeSession) {
        app.mutate { UnfinishedSession.keep(session, in: &$0) }
    }

    private func discardUnfinished() {
        app.mutate { UnfinishedSession.discard(in: &$0) }
    }

    /// 每条路线卡片里那几行「具体是什么」。
    ///
    /// 没有这几行，四张卡片就只剩四个动词，用户点之前不知道会练到什么。
    /// 颜色不在这里设：主行动卡片是白字、普通卡片是主文字色，两边各自的容器已经定好了。
    @ViewBuilder
    private func routeDetail(_ route: PracticeRoute) -> some View {
        switch route {
        case .planToday: planTodayDetail
        case .freePick: freePickDetail
        case .randomDraw: randomDrawDetail
        case .continueLast: continueLastDetail
        case .retrain: retrainDetail
        }
    }

    /// 「随机抽题练一场」：现在有多少题可抽、其中多少还没练过。
    ///
    /// **「没练过多少道」是这张卡片非说不可的一件事**：这条路线的卖点之一就是
    /// 「只抽没练过的」，而那个开关有没有用，全看这个数字还剩多少。
    /// 数字从 `RandomDrawViewModel` 出，与弹层里每个步进器下面那一行同一个出处——
    /// 这一页另数一份的话，两处迟早对不上。
    private var randomDrawDetail: some View {
        let model = RandomDrawViewModel(questions: app.state.questions)
        let fresh = ExamPart.allCases.reduce(0) { $0 + model.fresh(inPart: $1) }
        // 等宽数字：抽完一场之后这两个数会变，行宽不许跟着抖（规范第 6 节最后一条）。
        return Text("题库里现在有 \(app.state.questions.count) 道题，其中 \(fresh) 道还没练过。"
                    + "点右边那颗按钮之后先定每个 Part 抽几道，抽出来才会开始。")
            .font(Typography.body)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 「按计划练今天」：今天是第几天、今天有哪几道题、哪几道已经练过了。
    ///
    /// **第几天不能省**：学习计划页说「第 5 天」，这一页什么都不说的话，
    /// 用户没法把两页对上，也不知道自己落下了几天。
    @ViewBuilder
    private var planTodayDetail: some View {
        if let day = model.planDay {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // 等宽数字：从第 9 天跳到第 10 天时这一行不许横向抖（规范第 6 节最后一条）。
                Text("计划的第 \(day.id) 天，共 \(day.questionIds.count) 道题，"
                     + "已经练完 \(day.completedQuestionIds.count) 道。")
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                // 用下标而不是 `\.id` 做身份：题库正常情况下 id 唯一，但用户手工编辑过
                // state.json 之后未必如此，而 ForEach 遇到重复 id 会错乱地复用行。
                ForEach(Array(model.todayQuestions.enumerated()), id: \.offset) { _, question in
                    planQuestionRow(question,
                                    isCompleted: day.completedQuestionIds.contains(question.id))
                }
            }
        }
    }

    /// 今天要练的一道题。**整行可点，点哪一道就练哪一道。**
    ///
    /// 计划里一天排两题，不能点的话，用户想先练第二道就没有任何办法——
    /// 点整张卡片走的是「今天第一道没练的」。
    ///
    /// **练过的必须打勾**：一天两题练完一题回来看，卡片和练之前一模一样的话，
    /// 用户不知道自己练过了没有，只能再点一次。图标只用 SF Symbols，不用 emoji（规范第 4 节）。
    private func planQuestionRow(_ item: Question, isCompleted: Bool) -> some View {
        Button {
            act(.planToday, questionID: item.id)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                Text("Part \(item.part) · \(promptText(item))")
                    .font(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted
                            ? "已经练过：Part \(item.part) \(promptText(item))"
                            : "还没练：Part \(item.part) \(promptText(item))")
    }

    /// 「从题库自由选题」：先说清题库里有多少题，否则这张卡片上只剩一个动词。
    private var freePickDetail: some View {
        // 等宽数字：导完一批题从「12」跳到「120」时这一行不许横向抖（规范第 6 节最后一条）。
        Text("题库里现在有 \(app.state.questions.count) 道题。"
             + "点右边那颗按钮之后先挑一道，挑好才会开始。")
            .font(Typography.body)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 「继续上次练习」：上次练的哪道题、什么时候练的、上次盯的是什么目标。
    ///
    /// **上次的目标不能省**：这条路线的意思就是接着上次那件事再练一遍
    /// （解析器会把它一并带进这一场），不显示的话，它和「随便再练一道」在用户眼里没有区别。
    @ViewBuilder
    private var continueLastDetail: some View {
        if let last = model.recentSessions.first {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("上次练的：\(topicText(last)) · \(questionText(last))")
                    .font(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("练的时间：\(dateText(last.startedAt))")
                    .font(Typography.secondary)
                    .monospacedDigit()
                if !last.goal.isEmpty {
                    Text("上次盯的目标：\(last.goal)")
                        .font(Typography.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 「复训一个旧问题」：这一场要盯的目标原文，以及它出自哪一次练习。
    ///
    /// **目标原文取的是解析器算出来的 `setup.goal`，不是 `TodayViewModel.liveTarget?.label`。**
    /// 那两个挑的不是同一个目标（一个是「最后记下的」，一个是 `RetrainingPolicy.rank`
    /// 排第一的），而且 label 是空白时解析器会回落成 targetKey。取错了，
    /// 屏幕上写的和提示词里发的就是两码事，而界面上看不出任何异样。
    ///
    /// 不显示目标的话，这条路线和普通练习在用户眼里没有区别——他开练之前不知道自己要改什么。
    @ViewBuilder
    private var retrainDetail: some View {
        if case .ready(let setup) = PracticeRouteResolver.resolve(route: .retrain,
                                                                  state: app.state,
                                                                  defaults: defaults),
           let origin = model.retrainOrigin {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("排在最前面的目标：\(setup.goal)")
                    .font(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("它出自 \(dateText(origin.session.startedAt)) 那一场练习的复盘。"
                     + "到复训中心可以先回看当时的证据，再决定重练哪一个。")
                    .font(Typography.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 题库有题、却一条路线都解析得出来。**按现在的规则走不到这里**
    /// （题库非空就至少有「从题库自由选题」），留着是因为解析规则以后会改，
    /// 而那时这里若什么都不画，用户看到的是一块无法解释的空白。
    ///
    /// 三样一个不少：说明现状、说明下一步、一颗能直接点的按钮。按钮送去「学习计划」——
    /// 一条路线都排不出来时，能做的就是先有一份计划。
    private var noRouteCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("暂时没有可以直接开始的路线")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("题库里有 \(app.state.questions.count) 道题，"
                     + "但四条路线现在都定不出具体该练哪一道。"
                     + "下一步：到「学习计划」页生成一份计划，回到这一页就能按计划开练；"
                     + "也可以用「从题库自由选题」自己挑一道。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .coachParagraph()
                    .coachReadingColumn()
                Button("去学习计划") { onGo(.plan) }
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
                // 这一整块只在题库非空时才渲染，那时解析器至少排得出「从题库自由选题」。
                Button("开始练习") { act(availableRoutes.first ?? .freePick) }
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

    /// 上次那道题的话题。**题库里已经没有这道题时要说出来**，不给一段空白——
    /// 空白会让人以为这一行坏了（换季重新导入题库之后就会出现）。
    private func topicText(_ session: PracticeSession) -> String {
        guard let question = app.state.questions.first(where: { $0.id == session.questionId }) else {
            return "（题库里已经没有这道题了）"
        }
        return question.topic.isEmpty ? "（这道题没有话题）" : question.topic
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
        navigator: SettingsNavigator())
}

// 点了「开始练习」之后弹出来的那张 sheet 的预览在 `Session/PracticeSheet.swift` 里，
// 且刻意用一个一次也不碰真实 ChatGPT 的空壳 Bridge（铁律 5）。
