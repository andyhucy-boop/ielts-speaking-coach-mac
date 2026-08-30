import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 学习计划页：选周期、定重点 Part、看每日拆分与进度，随时调整并重新生成。
///
/// **这一页最要紧的一条：重新生成不能让人觉得练过的白练。**
/// 所以确认框里第一句就是「已经练过的题仍然算已完成」，而落盘走的是
/// `PlanRegenerator`——「进度怎么搬过去」只有那一处实现，有 Task 4 的全套测试守着。
///
/// **三条不能破的规矩：**
///
/// 1. **可行性判据只有一处**（`PlanScope.blockingReason`，经 `PlanDraftPreviewBuilder` 转手）。
///    这一页绝不自己再判一次「题够不够」——预览说能生成、点下去却报错，
///    是最伤信任的一类界面缺陷。
/// 2. **不能生成时，禁用的按钮旁边必须写清为什么。** 只把按钮灰掉让人猜，
///    等于把用户扔在一页死路上（铁律 6）。
/// 3. **「第几天」按练完的进度走，不按日历，而且必须把这句话写在屏幕上。**
///    不写的话，请假两天回来的人会以为自己落后了——这一页最不该做的就是让人不想练。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
@MainActor
struct PlanView: View {
    let app: AppState
    /// 「打开设置 › 练习偏好」那颗按钮要把设置窗口停到哪一栏。由 `RootView` 传进来，
    /// 与工具栏齿轮、首页「改目标」是同一个对象——三处打开的是同一个窗口。
    let navigator: SettingsNavigator
    /// 打开 ⌘, 那个设置窗口。用系统给的这一个，不要私有 selector。
    @Environment(\.openSettings) private var openSettings

    /// 用户在表单里改过的选择。**nil 表示「还没动过」**，此时按现有计划（或默认值）显示。
    ///
    /// 不在 `onAppear` 里把它初始化成现有计划的取值：那样一来，用户在别处
    /// （命令行、另一个窗口）改了计划，这一页的表单还停在进来那一刻的旧值上。
    @State private var edited: PlanDraft?
    /// 生成 / 删除 / 存偏好之后要显示的那句话——**成功和失败都要显示**。
    ///
    /// 失败时它是 `AppState.mutate` 返回的中文说明（发生了什么 + 下一步）；
    /// 成功时是 `PlanRegenerator` 那段摘要（里面写着「你之前练过的 N 道题仍然算已完成」）。
    /// 不做成一闪而过的提示：用户来不及读，而这两种话都值得读完。
    @State private var notice: String?
    @State private var isConfirmingRegenerate = false
    @State private var isConfirmingDelete = false

    private var model: PlanViewModel { PlanViewModel(state: app.state) }

    /// 表单当前选的是什么。用户动过就用他选的，没动过就取自现有计划。
    private var draft: PlanDraft { edited ?? Self.initialDraft(model) }

    /// 按当前选择，这份计划会长什么样、做不做得出来。
    ///
    /// **每次选择变化都重算**（计算属性，不缓存）：缓存下来忘了更新的话，
    /// 用户换了重点 Part 而预览还写着上一档的题数，而那正是他用来决定要不要点生成的依据。
    private var preview: PlanDraftPreview {
        PlanDraftPreviewBuilder.preview(state: app.state, draft: draft)
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    header
                    if let notice { noticeCard(notice) }
                    // 还没有计划时先给空状态：一句现状、一句下一步、一个能直接点的按钮。
                    if !model.hasPlan { emptyState(scroller) }
                    planSummary
                    dayList
                    form
                    deleteSection
                    preferences
                }
                .coachPageBody()
            }
            .background(Palette.canvas)
            .onAppear { scrollToToday(scroller) }
        }
        .confirmationDialog(Self.regenerateConfirmationTitle,
                            isPresented: $isConfirmingRegenerate,
                            titleVisibility: .visible) {
            // 默认焦点不给这一颗：`.cancel` 那颗才是回车/ESC 的落点。
            Button("重新生成") { generate() }
            Button("取消", role: .cancel) { isConfirmingRegenerate = false }
        } message: {
            Text(Self.regenerateConfirmationMessage)
        }
        .confirmationDialog(Self.deleteConfirmationTitle,
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) { deletePlan() }
            Button("取消", role: .cancel) { isConfirmingDelete = false }
        } message: {
            Text(Self.deleteConfirmationMessage)
        }
    }

    // MARK: - 页头

    private var header: some View {
        PageHeader(number: 1, label: "STUDY PLAN", title: SidebarItem.plan.title,
                   lede: "选一个周期和重点 Part，这一页会把题库拆成每天几道；"
                       + "练完一道，进度就往前走一格。")
    }

    /// 生成 / 删除 / 存偏好之后的那句话。**成功与失败共用这一张卡片**：
    /// 两条路各画一份的话，其中一条迟早会被漏掉，而漏掉的那条多半是失败那条（铁律 7）。
    private func noticeCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    // 里面可能带着文件路径与原始报错，用户要能复制出来。
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("知道了") { notice = nil }
                    .buttonStyle(.bordered)
                    .font(Typography.action)
            }
        }
    }

    // MARK: - 还没有计划时

    /// 空状态三样缺一不可：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    ///
    /// 那颗按钮直接把页面滚到下面的生成表单：这一页可能很长，
    /// 光写一句「在下面」等于让用户自己找。
    private func emptyState(_ scroller: ScrollViewProxy) -> some View {
        EmptyStateView(
            message: "你还没有学习计划",
            hint: "有计划之后，「今日训练」页会直接告诉你今天练哪几道题，不用每次自己想。"
                + "下一步：在下面的表单里选好周期和重点 Part，再生成一份。",
            actionTitle: "去下面选周期和重点 Part",
            action: { scroller.scrollTo(Self.formAnchor, anchor: .top) })
    }

    // MARK: - 计划概览

    /// **三种情况都得说话，一种都不许留白。** 全部练完、还在练、以及一道题都没排
    /// （题数少于天数的老计划会长这样）——留白会让用户以为程序坏了。
    @ViewBuilder private var planSummary: some View {
        if let days = model.lengthDays, let focus = model.focusPart {
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(Self.planTitleText(lengthDays: days, focusPart: focus))
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    progressRow
                    if model.isFinished {
                        Text(Self.finishedText)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let today = model.todayNumber {
                        Text(Self.todayNote(dayNumber: today))
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(Self.emptyPlanNote)
                            .font(Typography.body)
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// 进度按**题目**算（`PlanViewModel.progress`），这一页不另数一份——
    /// 数两遍迟早会出现「概览说 3 题、下面列表里勾了 5 道」。
    private var progressRow: some View {
        let progress = model.progress
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Self.progressText(done: progress.done, total: progress.total))
                .font(Typography.number)
                // 等宽数字：从 9 跳到 10 时整行不许横向抖（规范第 6 节最后一条）。
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
            ProgressView(value: Self.progressFraction(done: progress.done,
                                                      total: progress.total))
                .tint(Palette.accent)
                .frame(maxWidth: 420)
        }
    }

    // MARK: - 每日拆分

    @ViewBuilder private var dayList: some View {
        let rows = model.dayRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(number: 2, label: "DAILY BREAKDOWN", title: "每日安排")
                ForEach(rows) { row in dayCard(row) }
            }
        }
    }

    /// 一张卡片 = 一天。今天那一天用 `Palette.accent` 标出来，并且**默认滚动到它**
    /// （见 `scrollToToday`）——30 天的计划打开来停在第 1 天的话，每次都得自己滚到底。
    private func dayCard(_ row: PlanDayRow) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(Self.dayTitle(row.id))
                        .font(Typography.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(Self.dayTitleColor(isToday: row.isToday))
                    if row.isToday {
                        // **图标 + 文字，不只靠颜色**：只靠颜色区分，
                        // 对色觉障碍用户等于没有标记（DESIGN-SYSTEM 第 4 节）。
                        Label("今天练这几道", systemImage: "arrow.right.circle")
                            .font(Typography.label)
                            .foregroundStyle(Palette.accent)
                    }
                    Spacer(minLength: Spacing.sm)
                    Text(Self.dayCountText(total: row.items.count))
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                    Text(Self.dayStatusText(isComplete: row.isComplete))
                        .font(Typography.label)
                        .foregroundStyle(row.isComplete ? Palette.success : Palette.textSecondary)
                }
                ForEach(row.items) { item in questionRow(item) }
            }
        }
        .id(Self.dayAnchor(row.id))
    }

    /// 一行 = 一道题。
    ///
    /// **题目已经不在题库里的那一行照常显示**（`isMissing`），只是换成警示色并把
    /// `prompt` 里那段中文说明摆出来。藏起来或者留一行空白，用户会以为界面坏了
    /// （与训练记录页对已删题目的做法一致）。
    private func questionRow(_ item: PlanQuestionRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(Typography.body)
                .foregroundStyle(item.isCompleted ? Palette.success : Palette.textSecondary)
                .accessibilityLabel(item.isCompleted ? "已练过" : "还没练")
            Text(Self.partBadgeText(part: item.part))
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: Radius.pill))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !item.topic.isEmpty {
                    Text(item.topic)
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(item.prompt)
                    .font(Typography.body)
                    .foregroundStyle(item.isMissing ? Palette.warning : Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 生成 / 调整表单

    private var form: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(model.hasPlan ? "调整这份计划" : "生成一份计划")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                lengthPicker
                focusPicker
                previewLine
                generateButton
            }
        }
        .id(Self.formAnchor)
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("练几天")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            Picker("计划周期", selection: lengthBinding) {
                // 选项来自 `PlanBuilder.supportedLengths`，不手抄一份：
                // 手抄的话，Core 那边加一档，界面上不会出现，而 Core 的测试照样绿。
                ForEach(PlanBuilder.supportedLengths, id: \.self) { days in
                    Text(Self.lengthTitle(days)).tag(days)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(Typography.body)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var focusPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("重点练哪一部分")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            Picker("重点 Part", selection: focusBinding) {
                // 文字用 `PlanScope.label(for:)`：与 Core 报错里的说法共用一份，
                // 两处各写各的会出现「界面叫 Part 2、报错叫个人陈述」。
                ForEach(FocusPart.allCases, id: \.self) { part in
                    Text(PlanScope.label(for: part)).tag(part)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(Typography.body)
            .foregroundStyle(Palette.textPrimary)
            Text(Self.focusScopeNote)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「重点 Part」与开练时那几个 Part 勾选框的关系。
    ///
    /// **这句话必须有。** App 里现在有两处能选 Part：这里，和「今日训练」页点
    /// 「开始练习」之后那张弹层上的勾选框（`PracticeSheet.partSection`）。
    /// 不说清各管什么，用户会以为它们是同一个设置的两份界面，然后开始怀疑
    /// 「我在这儿选了 Part 2，为什么那边还能选 Part 1」。
    ///
    /// 两者的实际关系写在 `PracticePicker` 的文档里：这里决定**排计划时挑哪些题**，
    /// 那里决定**这一次练哪几段、列出哪些题**；那张弹层默认勾的就是这里选的这一项，
    /// 但在那儿改不会回写这里。文案里提到的「开始练习」是真按钮
    ///（`TodayView.actionTitle`），弹层上那几个勾选框也真的存在。
    static let focusScopeNote = "这一项只决定这份计划每天排哪些题。"
        + "到「今日训练」页点「开始练习」之后，那张窗口上还有 Part 1 / Part 2 / Part 3 "
        + "三个勾选框，可以临时改这一场练哪几个 Part——默认勾的就是这里选的这一项，"
        + "在那儿改不会动这份计划。"
        // 组合档在那张窗口上是「勾两个」，而列表只列开场那一段的题。
        // 不说清的话，用户在这儿选了 Part 2 + Part 3，到那边看到一列 Part 2 的题，
        // 会以为这个选择根本没生效。
        + "选了两个 Part 连着练时，那边会同时勾上这两个，"
        + "题目列的是开场那一段的，后面那一段考官顺着同一个话题接着考。"

    /// 能生成时说清会得到什么；不能生成时把**阻断原因全文**摆出来。
    ///
    /// 「只把按钮灰掉」是这一页最容易犯的错：用户看得见按钮、按不动，又没有任何解释，
    /// 只能一档一档去试（计划要求 B 明写这段文字必须在按钮旁边）。
    @ViewBuilder private var previewLine: some View {
        let preview = self.preview
        if preview.canBuild {
            Text(Self.previewText(preview, draft: draft))
                .font(Typography.body)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(Typography.body)
                    .foregroundStyle(Palette.warning)
                // 正文仍用 `textPrimary`：警告色是给标记用的，
                // 拿它写整段中文正文对比度过不了（DESIGN-SYSTEM 第 2 节）。
                Text(preview.blockingReason)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    /// 这一页**唯一**的主行动（DESIGN-SYSTEM 第 4 节：每页最多一个）。
    /// 删除计划那颗刻意做成次一级。
    private var generateButton: some View {
        HStack(spacing: Spacing.md) {
            Button(Self.generateButtonTitle(hasPlan: model.hasPlan)) { requestGenerate() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .font(Typography.action)
                .disabled(!preview.canBuild)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 删除计划（次一级）

    @ViewBuilder private var deleteSection: some View {
        if model.hasPlan {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // **不用 `.borderedProminent`**：整页只能有一个主行动，那一个是「生成计划」。
                // 两个同样醒目的按钮会让人不知道该点哪个。
                Button("删除计划", role: .destructive) { isConfirmingDelete = true }
                    .buttonStyle(.bordered)
                    .font(Typography.action)
                Text("练习记录、复盘和题目的已练标记都不会跟着删掉。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 练习偏好搬去设置窗口了，这里只留一条路

    /// 三项练习偏好（默认路线、反馈时机、Part 2 准备时间）从前就摆在这一页页尾。
    ///
    /// **Phase 10 Task 16 把它们搬进了设置窗口。** 理由：它们影响的是**每一场练习**，
    /// 不只是计划；当初落在这儿，只是因为那时还没有设置窗口。
    /// 留在两处的话，「练习偏好」就有两个家，而两个家迟早会显示两个不一样的取值。
    ///
    /// **这里不能什么都不留**：用户从前在这一页改这几项，突然一片空白只会让他以为功能没了。
    /// 一行说明 + 一颗能直接点的按钮（DESIGN-SYSTEM 第 4 节对空状态的三样要求同理）。
    private var preferences: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 3, label: "PRACTICE PREFERENCES", title: "练习偏好")
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("默认练习路线、反馈时机、Part 2 准备时间都在设置里改。"
                         + "它们影响的是每一场练习，不只是这份计划，所以收在同一个地方。")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开设置 › 练习偏好") {
                        navigator.open(.practice)
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .font(Typography.action)
                }
            }
        }
    }

    // MARK: - 绑定

    private var lengthBinding: Binding<Int> {
        Binding(get: { draft.lengthDays },
                set: { edited = PlanDraft(lengthDays: $0, focusPart: draft.focusPart) })
    }

    private var focusBinding: Binding<FocusPart> {
        Binding(get: { draft.focusPart },
                set: { edited = PlanDraft(lengthDays: draft.lengthDays, focusPart: $0) })
    }

    // 三项偏好的绑定跟着控件一起搬去了 `SettingsWindowView`（Phase 10 Task 16）。
    // **别在这儿加回来**：`SettingsHomeContractTests` 会当场变红——
    // 同一个设置有两个写入口，谁后写盘谁说了算，用户看到的是随机结果。

    // MARK: - 动作

    /// 已经有计划时先问一声再重排；第一次生成不问——那时没有任何东西会被覆盖，
    /// 多一次确认只是多一次点击。
    private func requestGenerate() {
        if model.hasPlan { isConfirmingRegenerate = true } else { generate() }
    }

    /// 生成并落盘。**三条出口都得说话**：生成不出来、写盘失败、成功，
    /// 一条都不许安静地什么都不发生（铁律 7）。
    private func generate() {
        isConfirmingRegenerate = false
        do {
            let outcome = try PlanRegenerator.regenerate(
                state: app.state, lengthDays: draft.lengthDays, focusPart: draft.focusPart,
                createdAt: ISO8601DateFormatter().string(from: Date()))
            if let failure = app.mutate({ PlanRegenerator.apply(outcome, to: &$0) }) {
                notice = failure
            } else {
                notice = outcome.summary
            }
        } catch {
            notice = Self.generationFailureText(error)
        }
    }

    private func deletePlan() {
        isConfirmingDelete = false
        notice = app.mutate(Self.clearPlan) ?? Self.deletedNotice
    }

    /// 删掉计划。**只清 `plan` 一个字段**（与 `PlanRegenerator.apply` 同一条规矩）：
    /// 顺手清掉 `sessions`、把题目状态重置成 new 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史——而确认框里逐字承诺过「练习记录、复盘和题目的
    /// 已练标记都还在」。
    ///
    /// 抽成纯函数是为了让这句承诺真跑得起来：扫源码只问得出「这儿有句 `$0.plan = nil`」，
    /// 问不出它后面有没有再跟一句别的（实测：加一句 `$0.sessions = []`，41 条一条不红）。
    static func clearPlan(_ state: inout CoachState) {
        state.plan = nil
    }

    /// 打开这一页时滚到「今天」那一天。30 天的计划停在第 1 天的话，每次都得自己滚到底。
    private func scrollToToday(_ scroller: ScrollViewProxy) {
        guard let today = model.todayNumber else { return }
        // 让这一帧先布局完再滚：`onAppear` 时列表还没量出高度，直接滚会落在错的位置。
        // 不加动画——DESIGN-SYSTEM 第 5 节要求尊重「减弱动态效果」，而这一下本来也不需要动效。
        Task { @MainActor in scroller.scrollTo(Self.dayAnchor(today), anchor: .top) }
    }

    // MARK: - 文案与取值（抽成纯函数，好让它们真跑得起来）

    /// 表单一进来选中的是什么：有计划就取现有计划的，没有就用 `PlanDraft()` 的默认值。
    ///
    /// 周期要先过一遍 `supportedLengths`：手改过的 state.json 里可能是 10 天这种
    /// 界面上根本没有的档位，直接拿它当初值的话，分段控件一档都不会高亮，
    /// 用户看到的是一个没有选中项的控件。
    static func initialDraft(_ model: PlanViewModel) -> PlanDraft {
        let fallback = PlanDraft()
        guard let days = model.lengthDays, let focus = model.focusPart else { return fallback }
        return PlanDraft(
            lengthDays: PlanBuilder.supportedLengths.contains(days) ? days : fallback.lengthDays,
            focusPart: focus)
    }

    static func generateButtonTitle(hasPlan: Bool) -> String {
        hasPlan ? "重新生成计划" : "生成计划"
    }

    static func lengthTitle(_ days: Int) -> String { "\(days) 天" }

    /// 生成之前那句话：题数、天数、每天几道，全部来自 `PlanDraftPreview`，这里不另算一份。
    static func previewText(_ preview: PlanDraftPreview, draft: PlanDraft) -> String {
        "\(PlanScope.label(for: draft.focusPart))现在 \(preview.questionCount) 题，"
            + "分 \(draft.lengthDays) 天，\(preview.perDayText)"
    }

    static func planTitleText(lengthDays: Int, focusPart: FocusPart) -> String {
        "\(lengthDays) 天计划 · \(PlanScope.label(for: focusPart))"
    }

    static func progressText(done: Int, total: Int) -> String {
        "已完成 \(done) / \(total) 题"
    }

    /// 进度条的取值。**总题数为 0 时返回 0，不许直接相除**——
    /// 那会得到 NaN，而 `ProgressView` 画 NaN 会崩。
    static func progressFraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    /// 「今天是第几天」以及**它为什么不按日历走**。
    ///
    /// 后面那半句不是啰嗦：计划里没有日期字段，进度只随「练完一题」前进。
    /// 不写的话，请假两天回来的人看到「第 3 天」会以为自己落后了，
    /// 而被界面指责只会让人不想练（计划的范围边界第一行）。
    static func todayNote(dayNumber: Int) -> String {
        "今天是第 \(dayNumber) 天。这里的「第几天」按练完的进度走，不按日历。"
            + "中间停几天回来，它还在原地等你。"
    }

    static let finishedText = "这份计划已经全部练完了。"
        + "下一步：重新生成一份，或换个重点 Part 再来一轮。"

    /// 计划在、题一道都没排。题数少于天数的老计划会长这样，手改过的 state.json 也会。
    static let emptyPlanNote = "这份计划里一道题都没排上（题库里的题少于计划天数时会这样）。"
        + "下一步：在下面把周期改短一点重新生成，或先到「训练题库」页导入更多题目。"

    static func dayTitle(_ day: Int) -> String { "第 \(day) 天" }

    /// 「今天」那一天的日期用强调色（计划要求 F）。
    ///
    /// 抽成纯函数而不是在视图里写个三元表达式，与 `IssueArchiveView.trendColor` 同一个理由：
    /// 扫源码问不出「isToday 那一天到底被画成了什么颜色」，而同一段代码里还有一句
    /// 「今天练这几道」的标签也用着 `Palette.accent`——只问「这儿有没有 accent」的话，
    /// 把日期的高亮整个删掉照样是绿的（实测过一次）。
    static func dayTitleColor(isToday: Bool) -> Color {
        isToday ? Palette.accent : Palette.textPrimary
    }

    static func dayCountText(total: Int) -> String { "共 \(total) 题" }

    static func dayStatusText(isComplete: Bool) -> String { isComplete ? "已练完" : "还没练完" }

    /// Part 徽标。题目已经不在题库里时 `part` 是 0——**不能因此显示成空白或「Part 0」**，
    /// 那是个不存在的东西，用户会以为界面坏了。
    static func partBadgeText(part: Int) -> String {
        (1...3).contains(part) ? "Part \(part)" : "题目已失效"
    }

    /// 滚动锚点。天与表单必须各用各的，否则「去下面生成」会跳到列表上。
    static func dayAnchor(_ day: Int) -> String { "plan-day-\(day)" }

    static let formAnchor = "plan-form"

    // MARK: - 两个确认框（文案逐字来自计划 Task 9 要求 C 与 G）

    static let regenerateConfirmationTitle = "重新生成计划？"

    /// 这段话要回答用户按下按钮前唯一关心的问题：**我练过的那些会不会白练。**
    static let regenerateConfirmationMessage =
        "已经练过的题仍然算已完成，练习记录、复盘、错题本、词汇本都不受影响。\n"
        + "下一步：确认后会按你选的周期和重点 Part，重排今后的每日安排。"

    static let deleteConfirmationTitle = "删除计划？"

    static let deleteConfirmationMessage =
        "删掉之后「今日训练」页的「按计划练今天」会消失，但练习记录、复盘和题目的已练标记都还在。\n"
        + "下一步：随时可以回到这一页重新生成一份计划。"

    static let deletedNotice = "计划已经删掉了。练习记录、复盘和题目的已练标记都还在。"
        + "下一步：想重新排一份的话，在下面选好周期和重点 Part 再生成。"

    /// 生成失败时给用户看的话。
    ///
    /// `PlanRegenerator` 抛的是 `CoachError`，它自带中文的「下一步」，原样交出去即可；
    /// 万一冒出别的错误（系统 NSError 只说发生了什么、措辞未必是中文），
    /// 由这里补上「下一步」——否则用户被扔在半路（铁律 6）。
    static func generationFailureText(_ error: any Error) -> String {
        let detail = error.localizedDescription
        if detail.contains("下一步") { return detail }
        return "这份计划没能生成：\(detail) "
            + "下一步：换一个周期或重点 Part 再试一次；现有的计划与练习记录都没有变。"
    }

    // 三项偏好的选项名与取舍说明搬去了 `PracticePreferenceEditor`（Phase 10 Task 16），
    // 跟着控件一起走。留一份在这儿的话，两处迟早会说不一样的话。
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("还没有计划") {
    PlanView(app: AppState(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview-plan")),
        preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
             navigator: SettingsNavigator())
}
