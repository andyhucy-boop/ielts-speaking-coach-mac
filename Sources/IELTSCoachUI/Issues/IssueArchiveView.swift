import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 问题档案页：反复出现的毛病按出现次数排开，每条带上「最近有没有变少」。
///
/// **这一页只回答两件事**：这个毛病在几场练习里犯过，最近有没有变少。
/// 不给任何形式的雅思分数、评级或水平判断（DEFINITION-OF-DONE 第 4 节）——
/// 给一个数字会让人盯着数字，而这一页要人盯的是问题本身。
///
/// **三条不能破的规矩：**
///
/// 1. **排序与筛选原样来自 `IssueArchiveViewModel`**，这一页不许再排一次、再筛一次——
///    那会造出第二套说法，而依据只有视图模型那一处有测试守着。
/// 2. **时间轴查出来的数据问题必须上屏。** 查出问题却不显示，用户拿到的是一个
///    他无法核对的趋势（本项目已经为同一个毛病写过 `ArchiveOutcome.skipped`）。
/// 3. **趋势的颜色只是辅助，文字标签必须始终在。** 只靠颜色区分，
///    对色觉障碍用户等于没有标记。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
@MainActor
struct IssueArchiveView: View {
    let app: AppState
    /// 空状态那颗按钮要把用户送到「今日训练」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `TodayView` / `HistoryView` / `RetrainingCenterView` 的做法一致——
    /// 这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void

    /// 当前选中的筛选档。
    @State private var filter: IssueFilter = .all
    /// 展开着解释的是哪一条。**存 id 不存整行**：列表会随 `app.state` 变，
    /// 存对象会在刷新之后指着一份旧的。
    @State private var expandedID: String?

    private var model: IssueArchiveViewModel { IssueArchiveViewModel(state: app.state) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                summaryLine
                filterPicker
                warningSection
                listSection
            }
            .coachPageBody()
        }
        .background(Palette.canvas)
    }

    // MARK: - 页头与汇总

    private var header: some View {
        PageHeader(number: 1, label: "ISSUE ARCHIVE", title: "你的问题档案",
                   lede: "这里只说两件事：一个毛病在几场练习里犯过，最近有没有变少。"
                       + "按犯过的场次从多到少排，最上面那条就是眼下最该盯的那个。")
    }

    /// 标题下那一行汇总。
    ///
    /// 抽成纯函数（`summaryText`）而不是在这儿拼字符串，理由和 `HistoryView.speakerText(for:)`
    /// 一样：扫源码只问得出「这儿有个 `Text`」，问不出它到底说了什么。
    private var summaryLine: some View {
        let counts = model.counts
        return Text(Self.summaryText(total: counts.total, new: counts.new,
                                     improving: counts.improving))
            .font(Typography.body)
            // 等宽数字：「共 9 个问题」跳到「共 10 个问题」时整行不许横向抖一下
            // （规范第 6 节最后一条）。
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
    }

    /// 汇总那句话。三个数字全部来自 `IssueArchiveViewModel.counts`，这里不另算一份。
    static func summaryText(total: Int, new: Int, improving: Int) -> String {
        "共 \(total) 个问题 · 其中 \(new) 个是新问题 · \(improving) 个正在变少"
    }

    // MARK: - 筛选

    private var filterPicker: some View {
        Picker("筛选问题", selection: $filter) {
            ForEach(IssueFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .font(Typography.body)
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: 420, alignment: .leading)
    }

    // MARK: - 时间轴查出来的数据问题

    /// **非空时必须显示。** 静默地把有问题的数据算进趋势，
    /// 等于给用户一个他无法核对的结论。
    ///
    /// 用 `Palette.warning` 做左侧标记，正文仍用 `Palette.textPrimary`——
    /// 警告色是给标记用的，拿它写整段中文正文对比度过不了（DESIGN-SYSTEM 第 2 节）。
    @ViewBuilder private var warningSection: some View {
        let warnings = model.dataWarnings
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // 用下标做身份：两条警告的文字理论上可能一样，拿内容当 id 会让
                // ForEach 错乱地复用行。
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    CoachCard {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Typography.body)
                                .foregroundStyle(Palette.warning)
                            Text(warning)
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 列表

    /// 顺序与内容**原样**来自 `IssueArchiveViewModel`。这一页不排、不筛、不藏。
    @ViewBuilder private var listSection: some View {
        let visible = model.rows(filter: filter)
        if model.rows.isEmpty {
            emptyState
        } else if visible.isEmpty {
            filteredEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                // 用下标做身份：state.json 被外部工具改坏时会出现重复的错题 id，
                // 而 ForEach 遇到重复 id 会错乱地复用行。
                ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                    issueCard(row)
                }
            }
        }
    }

    /// 一行 = 一个毛病。点一下展开「这个结论是怎么来的」。
    private func issueCard(_ row: IssueArchiveRow) -> some View {
        Button {
            expandedID = Self.toggling(expandedID, to: row.id)
        } label: {
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("当时说的：\(row.learnerSaid)")
                                .font(Typography.body)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("该说成：\(row.correction)")
                                .font(Typography.body)
                                .foregroundStyle(Palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("为什么要改：\(row.whyItMatters)")
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            // **现在张嘴练什么。** 这一页此前只说「你说错了、该说成什么」，
                            // 一条也没告诉他此刻能做什么，而这一页是他反复回来看的地方。
                            // ChatGPT 这次没给练法时整行不画（提示词明说写不出就给空串，
                            // 不许写「多加练习」这种等于没说的话）。
                            if !row.miniDrill.isEmpty {
                                Text("练一下：\(row.miniDrill)")
                                    .font(Typography.secondary)
                                    .foregroundStyle(Palette.success)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Spacing.sm)
                        // 等宽数字：从 9 跳到 10 时这一列不许横向抖（规范第 6 节最后一条）。
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Text("\(row.occurrences)")
                                .font(Typography.number)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                            Text("次")
                                .font(Typography.label)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        trendBadge(row)
                        if row.isNew {
                            // **图标 + 文字，不能只靠颜色**：只靠颜色区分，
                            // 对色觉障碍用户等于没有标记（DESIGN-SYSTEM 第 4 节）。
                            Label("新问题", systemImage: "sparkles")
                                .font(Typography.label)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: Spacing.sm)
                        Text(row.lastSeenText)
                            .font(Typography.label)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Text("出现在 \(row.sessionCount) 场练习里。\(row.detail)")
                        .font(Typography.secondary)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // 展开之后那段解释里带着「下一步做什么」，是这一页唯一能让用户
                    // 接着动手的地方（铁律 6）。
                    if expandedID == row.id {
                        Text(row.trend.explanation)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityHint("展开看这条趋势是怎么算出来的，以及下一步该做什么")
    }

    /// 趋势标签。**颜色只是辅助，`badge` 那几个字始终在。**
    private func trendBadge(_ row: IssueArchiveRow) -> some View {
        Text(row.trend.badge)
            .font(Typography.label)
            .foregroundStyle(Self.trendColor(row.trend))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: Radius.pill))
            .overlay(RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(Self.trendColor(row.trend), lineWidth: BorderWidth.hairline))
    }

    /// 趋势的语义色。
    ///
    /// **逐档写全，不许 `default:` 兜底**：将来 `IssueTrend` 加一档，兜底会把它静默地
    /// 画成某个已有的颜色，编译器一声不吭；穷尽的 `switch` 会当场逼人补上这一支。
    ///
    /// 抽成纯函数是为了让它真跑得起来——扫源码问不出「`.increasing` 被画成了什么颜色」。
    static func trendColor(_ trend: IssueTrend) -> Color {
        switch trend {
        // 往好的方向走的两档：最近没再出现、出现变少了。
        case .gone, .decreasing: return Palette.success
        case .increasing: return Palette.danger
        case .steady: return Palette.warning
        // 「新问题」与「还看不出趋势」都不是好消息也不是坏消息，
        // 给它们上语义色等于给了一个还没下的结论。
        case .fresh, .notEnoughData: return Palette.textSecondary
        }
    }

    /// 点一下之后展开的是哪一条：点没展开的那条就展开它，再点一次收起来，点另一条就换过去。
    ///
    /// **放成 `static` 纯函数，和 `HistoryView.toggling(_:to:)` 同一个理由**：
    /// 扫源码只问得出「这一行给 `expandedID` 赋了个值」，赋成 nil 也满足——
    /// 而那之后 `if expandedID == row.id` 永远为假，解释永远画不出来。
    static func toggling(_ current: String?, to id: String) -> String? {
        current == id ? nil : id
    }

    // MARK: - 两种空状态

    /// 一个问题都还没有。空状态给足三样：一句现状、一句下一步、一个能直接点的按钮
    /// （DESIGN-SYSTEM 第 4 节）。
    private var emptyState: some View {
        EmptyStateView(
            message: "问题档案还是空的",
            hint: "练一场并让 ChatGPT 生成复盘，反复出现的毛病会自动记到这里，"
                + "按犯过的场次排好，还会标出最近有没有变少。"
                + "下一步：去今日训练开一场。",
            actionTitle: "去今日训练",
            action: { onGo(.today) })
    }

    /// 筛到一条都不剩。**同样不能留白**——摆一片空白的话，用户会以为筛选控件坏了。
    private var filteredEmptyState: some View {
        EmptyStateView(
            message: "当前筛选下没有内容",
            hint: Self.filteredEmptyHint(filter),
            actionTitle: "看全部问题",
            action: { filter = .all })
    }

    /// 筛空时那句话。要说清是**哪一档**筛空了，否则用户不知道自己现在在看什么。
    static func filteredEmptyHint(_ filter: IssueFilter) -> String {
        "「\(filter.title)」这一档现在一条都没有——不是出错了，是确实没有符合的。"
            + "下一步：把上面的筛选换回「\(IssueFilter.all.title)」看看，"
            + "或者先去练一场，新的复盘会把新记下的问题补进来。"
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("一个问题都还没有") {
    IssueArchiveView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-issues")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in })
}
