import AppKit
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

    /// 点了「开始练习」之后要交代的话。非 nil 时弹出来。
    ///
    /// **本阶段还不能在界面里真的开练**（计划 Task 6：「本阶段只显示与选择，不实际发起练习」），
    /// 驱动接进按钮是紧接着的 Task 9。在那之前，点下去必须把「现在为什么还练不了」和
    /// 「那现在怎么练」一次说清（铁律 6）——什么都不发生是最坏的一种。
    @State private var startHint: PracticeStartHint?

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
                    recordingNotice
                    routes
                    recentPractice
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .sheet(item: $startHint) { hint in
            PracticeStartHintSheet(hint: hint, onDismiss: { startHint = nil })
        }
    }

    // MARK: - 顶部：问候、日期、本周进度

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(number: 1, label: "TODAY", title: SidebarItem.today.title)
                Text("\(greeting)。今天是 \(Self.dayDisplay.string(from: Date()))。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.md)
            weekCard.frame(width: 240)
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

    private var weekCard: some View {
        let progress = model.weekProgress
        let remaining = max(progress.goal - progress.done, 0)
        return CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("本周训练")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                // 等宽数字由 `Typography.number` 带着（规范第 1 节最后一行）：
                // 3/5 跳到 10/5 时整行不能横向抖一下。
                Text("\(progress.done)/\(progress.goal) 次")
                    .font(Typography.number)
                    .foregroundStyle(Palette.textPrimary)
                ProgressView(value: Double(min(progress.done, progress.goal)),
                             total: Double(progress.goal))
                    .tint(Palette.accent)
                    .accessibilityLabel("本周训练进度")
                    .accessibilityValue("\(progress.done) 次，共 \(progress.goal) 次")
                if remaining == 0 {
                    Text("本周目标已经达成，再练都是多赚的。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.success)
                } else {
                    Text("还差 \(remaining) 次达成本周目标。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: - 训练记录还没接上，这件事得说出来

    /// 「本周训练 N/5」和「最近练习」这两处，在当前工程里**练完也不会动**——
    /// 没有任何代码往 `state.sessions` 里写记录（见 `TodayViewModel.practiceRecordingIsWired`）。
    ///
    /// 不说这句话的话，用户照这一页自己弹出来的提示在终端练完一整场，回到这一页看到的还是
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
                          actionTitle: "开始练习",
                          action: { startHint = hint(for: route) }) {
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
                Button("开始练习") { startHint = hint(for: route) }
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
            if let target = liveTarget {
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
                + "（上面那条说明写了详情）。下一步：用上面那张紫色卡片挑一道题，照弹出来的提示到终端开练——"
                + "练出来的错题、词汇和复训目标都会正常入库，这一场不会白练。"
        }
        return "练完第一场之后，这里会按时间倒序列出最近五次：练的哪道题、当时定的目标、"
            + "复盘有没有存下来。下一步：用上面那张紫色卡片开始第一场；"
            + "想先看看有哪些题可以练，就去「训练题库」翻一翻。"
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

    // MARK: - 点了「开始练习」之后说什么

    private var liveTarget: RetrainingTarget? {
        // 最近记下的那个还没退休的目标。`targets` 按归档顺序追加，越靠后越新。
        app.state.targets.last { $0.status != "retired" }
    }

    /// 这条路线上要练的那道题。定不下来时返回 nil，提示里会改成「先挑一道」。
    private func plannedQuestion(for route: PracticeRoute) -> Question? {
        switch route {
        case .planToday:
            return model.todayQuestions.first
        case .continueLast:
            guard let last = model.recentSessions.first else { return nil }
            // 题库里已经没有这道题时（换季重新导入之后会发生）不能硬给一个练不了的 id。
            return app.state.questions.first { $0.id == last.questionId }
        case .retrain:
            guard let target = liveTarget,
                  let source = app.state.sessions.first(where: { $0.id == target.sourceSessionId })
            else { return nil }
            return app.state.questions.first { $0.id == source.questionId }
        case .freePick:
            // 自由选题的意思就是这道题由用户当场挑，这里定不下来是正常的。
            return nil
        }
    }

    private func hint(for route: PracticeRoute) -> PracticeStartHint {
        let question = plannedQuestion(for: route)
        let goal = route == .retrain ? liveTarget?.label ?? "" : ""
        let goalFlag = goal.isEmpty ? "" : #" --goal "\#(goal)""#
        let commands: [String]
        if let question {
            commands = ["swift run coach practice \(question.id)\(goalFlag)"]
        } else {
            // 题还没定下来时，第一条命令是「先看看有哪些题」——直接甩一个 <题目id> 占位符
            // 而不说去哪儿找 id，用户照样敲不出来。
            commands = ["swift run coach questions list",
                        "swift run coach practice <上一条列出来的题目id>\(goalFlag)"]
        }
        return PracticeStartHint(
            route: route,
            questionLine: question.map { "Part \($0.part) · \(promptText($0))" },
            commands: commands)
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

/// 点了「开始练习」之后要交代的内容。
struct PracticeStartHint: Identifiable {
    let id = UUID()
    let route: PracticeRoute
    /// 这条路线上已经定下来的那道题；nil 表示要用户自己挑一道。
    let questionLine: String?
    /// 要用户照着敲的命令，按先后顺序。
    let commands: [String]

    /// 把命令写进剪贴板。`write` 是真正干活的那一下，返回是否写成功。
    ///
    /// **返回值必须消费**：`NSPasteboard.setString` 是 `@discardableResult`，丢掉它编译器
    /// 不会吭声，而别的进程正占着剪贴板时它会返回 false——用户按 ⌘V 粘出来的是上一次复制的
    /// 东西（很可能是一段别的命令），照着敲下去后果不好说。**成功也要有反馈**：
    /// 点完按钮界面一个像素都不变的话，用户分不清是复制好了还是按钮坏了。
    /// 这两条都照 `PermissionStatus.copyDiagnostics` 的范式来。
    func copyCommands(using write: (String) -> Bool) -> ActionNotice {
        guard write(commands.joined(separator: "\n")) else {
            return ActionNotice(
                text: "没能把命令写进剪贴板（多半是别的程序正占着它）。"
                    + "下一步：直接选中上面那几行命令按 ⌘C 复制，再粘进「终端」运行。",
                isFailure: true)
        }
        return ActionNotice(
            text: commands.count > 1
                ? "\(commands.count) 行命令都已复制到剪贴板。"
                    + "下一步：打开「终端」，进到本工具的源码目录，按 ⌘V 粘贴后逐行回车。"
                : "命令已复制到剪贴板。下一步：打开「终端」，进到本工具的源码目录，按 ⌘V 粘贴后回车。",
            isFailure: false)
    }
}

/// 本阶段点「开始练习」弹出来的交代。
///
/// **它是临时的**：计划 Task 9 会把练习驱动接进那个按钮，到时这个 sheet 换成 `PracticeSheet`。
/// 在那之前，这一页必须把两件事一次说清（铁律 6）：
/// 现在为什么还不能在界面里开练，以及**现在到底怎么练**——
/// 只说「暂未实现」而不给出路，等于让用户对着一个死按钮。
struct PracticeStartHintSheet: View {
    let hint: PracticeStartHint
    let onDismiss: () -> Void
    /// 真正去写剪贴板的那一下。抽成闭包是为了让「写失败时到底会不会告诉用户」这件事
    /// 有测试管得住（`View` 本身没法单元测试），与 `PermissionGateView` 的做法一致。
    let writeToPasteboard: (String) -> Bool

    /// 点了「拷贝命令」之后的反馈。`nil` 表示还没点过。
    @State private var copyNotice: ActionNotice?

    init(hint: PracticeStartHint,
         onDismiss: @escaping () -> Void,
         writeToPasteboard: @escaping (String) -> Bool = { text in
             let pasteboard = NSPasteboard.general
             pasteboard.clearContents()
             return pasteboard.setString(text, forType: .string)
         }) {
        self.hint = hint
        self.onDismiss = onDismiss
        self.writeToPasteboard = writeToPasteboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("「\(hint.route.title)」还不能在界面里直接开始")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)

            if let questionLine = hint.questionLine {
                CoachCard {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("已经替你选好这道题")
                            .font(Typography.label)
                            .foregroundStyle(Palette.textSecondary)
                        Text(questionLine)
                            .font(Typography.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("这一版的今日训练页只做了选题与显示，把 ChatGPT 驱动接到这个按钮上是紧接着的下一步。"
                 + "界面与驱动刻意分两步接：出问题时才能一眼看出是界面还是驱动的毛病。")
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("下一步：打开「终端」，进到本工具的源码目录，按顺序运行下面的命令。"
                 + "命令行和这个界面读写的是同一份训练数据——练完的复盘、错题、进度都会回到这一页。")
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(hint.commands.enumerated()), id: \.offset) { _, command in
                        Text(command)
                            .font(Typography.body)
                            .monospaced()
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 点完按钮的那句话。失败用 danger，成功用次一级的文字色——
            // 成功也要说话，不然用户分不清「复制好了」和「按钮坏了」。
            if let copyNotice {
                Text(copyNotice.text)
                    .font(Typography.secondary)
                    .foregroundStyle(copyNotice.isFailure ? Palette.danger : Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                Button("拷贝命令") {
                    copyNotice = hint.copyCommands(using: writeToPasteboard)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: Spacing.md)
                Button("知道了", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .background(Palette.canvas)
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("题库还是空的") {
    TodayView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-today")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in })
}

/// 剪贴板也注入假的：在 Xcode 画布里点一下「拷贝命令」不该把用户真实的剪贴板冲掉。
/// 传 `false` 是因为失败那条提示更长，版式先按它对——短的那条一定放得下。
#Preview("点了开始练习之后") {
    PracticeStartHintSheet(
        hint: PracticeStartHint(route: .planToday,
                                questionLine: "Part 1 · Do you work or are you a student?",
                                commands: ["swift run coach practice p1-study-001"]),
        onDismiss: {},
        writeToPasteboard: { _ in false })
}
