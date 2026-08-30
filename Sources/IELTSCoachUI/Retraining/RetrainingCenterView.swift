import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 一张正要开始的复训：练哪个目标、这一趟是重答原题还是换题验证、题定下来了没有。
///
/// 每按一次按钮都新造一份（`id` 是新的 `UUID`），这样 `.sheet(item:)` 认得出是新的一趟——
/// 复用同一份的话，用户点第二个目标时弹出来的还是上一个目标的流程。
struct RetrainingFlowLaunch: Identifiable {
    let id = UUID()
    let item: RetrainingItem
    let run: RetrainingRun
    /// 已经定下来的题；nil 表示要在流程里先挑一道。
    let question: Question?
    let originalQuestionID: String
}

/// 复训中心：从复盘留下的目标里挑一个，带着它把原题重答一遍，再换一道题验证。
///
/// **两条不能破的规矩：**
///
/// 1. **待复训列表的顺序直接来自 `RetrainingPolicy.rank`**（经 `RetrainingCenterViewModel.pending`），
///    这一页不许再排一次——那会造出第二套说法，而排序的依据（证据命中高频错题）
///    只有那一处有测试守着。
/// 2. **链断了要说清楚，不能把那一条藏起来。** 来源记录被删、题库换季导致原题找不到，
///    都还留在列表里并显示 `sourceIssue.message`；凭空消失会让用户以为练习记录丢了。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `PrimaryActionCard` / `SectionHeader` /
/// `EmptyStateView`、`Palette` / `Spacing` / `Radius` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
@MainActor
struct RetrainingCenterView: View {
    let app: AppState
    /// 跳到别的页面。导航状态归 `AppState.navigation` 管，由 `RootView` 传进来，
    /// 与 `TodayView`、`HistoryView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void

    /// 规范第 5 节：开启「减弱动态效果」后不做任何过渡。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 用户点开的那一条。**决定哪一条画成紫色主行动卡片**（每页只有一个主行动）。
    /// nil 表示还没点过，那时主行动落在排第一的那条上——它就是最该练的那个。
    @State private var selectedID: String?
    @State private var showRetired = false
    /// 上一次操作的中文说明（失败时必须显示，不许静默）。
    @State private var notice: String?
    @State private var flow: RetrainingFlowLaunch?

    private var model: RetrainingCenterViewModel { RetrainingCenterViewModel(state: app.state) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    header
                    noticeCard
                    pendingSection
                    retiredSection
                }
                .coachPageBody()
            }
            .background(Palette.canvas)
            .onAppear { adoptPendingTarget(using: proxy) }
        }
        // 重读放在 onDismiss 上：一趟复训会改 state.json（训练记录、复训台账、错题本），
        // 不重读的话这一页显示的还是开练之前那份，用户会以为刚才那一趟没算数。
        // 挂在 onDismiss 上是为了让「不是从按钮走的那些关闭方式」也照样重读。
        .sheet(item: $flow, onDismiss: { app.reload() }) { launch in
            RetrainingFlowView(app: app,
                               item: launch.item,
                               run: launch.run,
                               question: launch.question,
                               originalQuestionID: launch.originalQuestionID,
                               onClose: { flow = nil },
                               onGo: { destination in
                                   flow = nil
                                   onGo(destination)
                               })
        }
    }

    // MARK: - 顶部

    private var header: some View {
        PageHeader(number: 4, label: "RETRAINING", title: "一次只解决一个问题",
                   lede: "从复盘留下的目标里挑一个，回看当时到底说了什么，带着它把原题重答一遍；"
                       + "然后换一道题再练一次——分清是真会了，还是只记住了那个答案。")
    }

    @ViewBuilder private var noticeCard: some View {
        if let notice {
            NoticeCard(.warning, notice)
        }
    }

    // MARK: - 待复训

    @ViewBuilder private var pendingSection: some View {
        // 顺序**原样**来自 `RetrainingCenterViewModel.pending`。这里不排、不筛、不藏。
        let items = model.pending
        VStack(alignment: .leading, spacing: Spacing.md) {
            if items.isEmpty {
                emptyState
            } else {
                // 用下标做身份：targetKey 跨 session 会重复，理论上两条能算出同一个 id，
                // 而 ForEach 遇到重复 id 会错乱地复用行。
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    pendingRow(item, isPrimary: item.id == primaryID(among: items))
                        .id(item.id)
                }
            }
        }
        .coachAnimation(Motion.standard, value: selectedID)
    }

    private var emptyState: some View {
        EmptyStateView(message: "复训中心还是空的",
                       hint: model.emptyStateMessage,
                       actionTitle: "去今日训练",
                       action: { onGo(.today) })
    }

    /// 一条待复训目标。
    ///
    /// 选中的那一条会从白卡变成整块紫色主行动卡（多出按钮，高度不一样），
    /// 原来那张紫卡同一帧变回白卡。**两处高度同时变**，硬切的话中间和下面所有行整块瞬移，
    /// 用户点的是 A，眼睛却要重新找 A 跑到哪去了。
    @ViewBuilder
    private func pendingRow(_ item: RetrainingItem, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isPrimary {
                primaryTargetCard(item)
            } else {
                secondaryTargetCard(item)
            }
            // 已经重答过原题的，额外给一条次一级的路。**这才是本阶段真正的交付物**：
            // 只重练原题，分不清是真会了还是只记住了那个答案。
            if item.progress.stage != .notStarted {
                HStack(spacing: Spacing.sm) {
                    Button("换一道题验证") { openTransfer(item) }
                        .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 这一页唯一的主行动（规范第 4 节：每页最多一个）。
    /// 十条一起用紫色大卡片，等于一条主行动都没有。
    private func primaryTargetCard(_ item: RetrainingItem) -> some View {
        PrimaryActionCard(title: title(of: item),
                          subtitle: item.statusLabel,
                          actionTitle: mainActionTitle(of: item),
                          action: { openMainAction(item) }) {
            // 这里刻意不设颜色：容器已经把前景色定成了紫底上的白字，
            // 再指定一次会变成深色字压在紫底上，直接读不清。
            targetDetail(item)
        }
    }

    private func secondaryTargetCard(_ item: RetrainingItem) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title(of: item))
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                // 等宽数字：「已换题验证 1 次」跳到「10 次」时整行不许横向抖一下
                // （规范第 6 节最后一条）。
                Text(item.statusLabel)
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                targetDetail(item)
                // 按钮**跟在内容后面**，不靠 `Spacer` 顶到最右边。
                // 卡片有一千点宽，顶到右边的话，标题和要点的东西隔着大半个屏幕。
                HStack(spacing: Spacing.sm) {
                    mainActionButton(item)
                    Spacer(minLength: 0)
                }
                .padding(.top, Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = item.id }
    }

    /// 一条待复训目标的正文：原话、来源日期、原题，以及链断了的话那句说明。
    ///
    /// **不设前景色**：它同时被紫色主行动卡片和白色普通卡片用，颜色由容器定。
    private func targetDetail(_ item: RetrainingItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let quote = firstQuote(of: item) {
                Text("当时说的：\(quote)")
                    .font(Typography.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("来自 \(dateText(item.target.createdAt)) 那次复盘")
                .font(Typography.label)
                .monospacedDigit()
            if let question = item.originalQuestion {
                Text("原题：Part \(question.part) · \(promptText(question))")
                    .font(Typography.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 链断了要原样说清楚，**不许把这一条从列表里藏掉**。
            if let issue = item.sourceIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(Typography.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 主行动那颗按钮。写成两个分支而不是一个三元表达式，是为了让两句按钮文字
    /// 都以字面量留在源码里——`RenderReachabilitySweepTests` 要靠这份字面清单
    /// 回答「文案里指名让用户点的东西，界面上真有吗」。
    @ViewBuilder
    private func mainActionButton(_ item: RetrainingItem) -> some View {
        if item.canRetryOriginal {
            Button("带着本题进入复训") { openMainAction(item) }
                .buttonStyle(.bordered)
        } else {
            Button("挑一道题带着这个目标练") { openMainAction(item) }
                .buttonStyle(.bordered)
        }
    }

    private func mainActionTitle(of item: RetrainingItem) -> String {
        item.canRetryOriginal ? "带着本题进入复训" : "挑一道题带着这个目标练"
    }

    // MARK: - 已经不用再练的

    /// 退休的目标仍然列出来（折叠着）。**退休不等于删除**：
    /// 凭空消失会让用户以为自己按错了什么，而这一步本来就是他自己点的。
    @ViewBuilder private var retiredSection: some View {
        let items = model.retired
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Button { toggleRetired() } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: showRetired ? "chevron.down" : "chevron.right")
                        Text("已经不用再练的目标（\(items.count)）")
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                }
                .buttonStyle(.plain)

                if showRetired {
                    Text("这些是你自己标为「不用再练」的目标，不是系统替你判定改掉了。"
                         + "下一步：想再练的话，点它右边的「重新放回待复训」。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        retiredRow(item)
                    }
                }
            }
        }
    }

    private func retiredRow(_ item: RetrainingItem) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title(of: item))
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(item.statusLabel)
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Button("重新放回待复训") { restore(item) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 动作

    /// 哪一条画成主行动卡片：用户点过的那一条，没点过就是排第一的那条
    /// （顺序来自 `RetrainingPolicy.rank`，排第一的就是最该练的那个）。
    private func primaryID(among items: [RetrainingItem]) -> String? {
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return selectedID }
        return items.first?.id
    }

    /// 从别的页面（今日训练的「复训一个旧问题」）跳过来时，预先选中那一条并滚过去。
    ///
    /// **只生效一次**——`consumePendingRetrainingTarget()` 自己会清空。不清的话，
    /// 用户在这一页点开别的目标，每次重绘都会被弹回最初那一个，他会以为界面点不动。
    private func adoptPendingTarget(using proxy: ScrollViewProxy) {
        guard let targetID = app.navigation.consumePendingRetrainingTarget() else { return }
        selectedID = targetID
        if reduceMotion {
            proxy.scrollTo(targetID, anchor: .top)
        } else {
            // 时长必须写出来：不写跑的是系统默认 0.35s，比 `Motion.deliberate` 还长一档，
            // 和侧边栏、卡片悬停的节奏对不上，连着用会觉得这里「粘手」。
            withAnimation(.easeOut(duration: Motion.standard)) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func toggleRetired() {
        if reduceMotion {
            showRetired.toggle()
        } else {
            withAnimation(.easeOut(duration: Motion.standard)) { showRetired.toggle() }
        }
    }

    /// 「带着本题进入复训」／「挑一道题带着这个目标练」。
    ///
    /// 原题查得到就走三步流程的第一步（回看证据）；查不到就只能带着目标自己挑一道题，
    /// 那一趟按换题验证记——`RetrainingSourceIssue` 那句话已经把原因摆在同一屏上了。
    private func openMainAction(_ item: RetrainingItem) {
        selectedID = item.id
        notice = nil
        guard let question = item.originalQuestion else {
            openTransfer(item)
            return
        }
        flow = RetrainingFlowLaunch(item: item, run: .original, question: question,
                                    originalQuestionID: originalQuestionID(of: item))
    }

    private func openTransfer(_ item: RetrainingItem) {
        selectedID = item.id
        notice = nil
        flow = RetrainingFlowLaunch(item: item, run: .transfer, question: nil,
                                    originalQuestionID: originalQuestionID(of: item))
    }

    private func restore(_ item: RetrainingItem) {
        // 失败时返回的是一句中文说明，必须显示出来——静默的话用户会看到列表纹丝不动
        // 而没有任何解释，只会再点一次。
        notice = app.setRetrainingStatus(.new, of: item.target.id)
    }

    /// 目标来源那一场练的是哪道题。**存进 `RetrainingLink` 的就是它**，
    /// 「这一场算原题重练还是换题验证」全靠它判。
    ///
    /// 题库里查不到那道题（换季导入了新题库）时仍能从来源记录里读出题目 id——那条链只断了后半截。
    ///
    /// **来源记录本身被删掉时返回空串。** 那时是真的无从得知，而空串会让接下来练的
    /// 任何一道题都被判成换题验证（计划 Task 10 给这条路径定的就是 `run = .transfer`）。
    /// 代价说清楚：万一用户恰好挑中了当初那道题，这一趟会被记成「已换题验证」而其实是原题重练。
    /// 同一屏上那句 `RetrainingSourceIssue.sessionMissing.message` 已经写明「找不回当时练的是哪道题」，
    /// 用户不会是在毫不知情的情况下拿到这个数字。
    private func originalQuestionID(of item: RetrainingItem) -> String {
        if let question = item.originalQuestion { return question.id }
        return app.state.sessions.first { $0.id == item.target.sourceSessionId }?.questionId ?? ""
    }

    // MARK: - 文案小工具

    /// label 为空时退回 targetKey：`RetrainingPolicy.extractTarget` 只强制 id 非空，
    /// label 允许为空，而一行没有标题的记录用户根本不知道那是什么。
    private func title(of item: RetrainingItem) -> String {
        let label = item.target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? item.target.targetKey : label
    }

    /// 第一条证据原话。全是空白的那种就当没有——摆一行「当时说的：」后面什么都没有更糟。
    private func firstQuote(of item: RetrainingItem) -> String? {
        let quote = item.target.evidence.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return quote.isEmpty ? nil : quote
    }

    private func promptText(_ question: Question) -> String {
        question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt
    }

    private static let timestampParser = ISO8601DateFormatter()

    private static let dateDisplay: DateFormatter = {
        let formatter = DateFormatter()
        // 不写死格式，跟随用户在系统里设的地区。
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// 认不出来的时间戳原样显示，**不显示成空白**——空白会让人以为这一行坏了。
    private func dateText(_ iso: String) -> String {
        guard let date = Self.timestampParser.date(from: iso) else { return iso }
        return Self.dateDisplay.string(from: date)
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("还没有待复训的目标") {
    RetrainingCenterView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-retraining")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in })
}

// 三步流程页（`RetrainingFlowView`）刻意不做预览：它一开练就会造出真的
// `PracticeRunner`，而打开画布就会执行预览体（铁律 5）。那一页的验收归 Task 11 的真机走查。
