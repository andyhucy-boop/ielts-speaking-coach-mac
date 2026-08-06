import AppKit
import ChatGPTBridge
import IELTSCoachCore
import SwiftUI

/// 复盘报告页：左边列出已经归档复盘的练习（最近的在最上面），右边显示选中那一次的复盘。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// 顶上那块深色的「NEXT SINGLE TARGET」是设计稿里最显眼的一块，也是这个产品真正的价值所在：
/// 复盘给出**一个**具体目标，下次带着它重练（成品标准第 2 节「改进闭环」）。
/// 它必须排在所有分区前面——排到下面去，用户滚不到就看不见。
@MainActor
struct ReviewReportView: View {
    let app: AppState
    /// 空状态那个按钮要把用户送到「今日训练」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `PlaceholderView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void
    /// 从「训练记录」点「看这次的复盘」跳过来时，要看的是哪一场（由 `RootView` 传）。
    /// 平时是 nil，那时这一页照旧落回最近的那一次。
    ///
    /// **它是一次性的**：用户自己再切一次页，`RootView` 就把它清掉
    /// （`RootRouter.carriedReviewSession`），所以这一页收到的非 nil 值一定是刚点过来的那一次，
    /// 不会是几天前那一场的残留。
    var requestedSessionID: String?

    /// 用户点选的那一次。**不是 `selected` 本身**：会话列表会随 `app.state` 变，
    /// 存 id 才不会在刷新之后指着一份旧对象。
    @State private var selectedSessionID: String?
    @State private var document: ReviewDocument?
    /// 读不到或解析不了时那句中文说明（含文件路径）。非 nil 时右半边只显示它。
    @State private var failure: String?
    /// 待处理复盘的收件箱（决策 2）。**nil 表示还没清点完，不是「没有待处理的」**——
    /// 拿 0 顶替的话，「读完了确实没有」和「还没读」长得一模一样，正是本项目最忌讳的静默。
    @State private var inbox: PendingReviewViewModel?
    @State private var isShowingInbox = false

    private var sessions: [PracticeSession] {
        ReviewReportViewModel.archivedSessions(in: app.state)
    }

    /// 没点过时落回最近的那一次，而不是给一块空白。
    ///
    /// 优先级：**用户在这一页自己点的那一次**，压过从「训练记录」带过来的那一次。
    /// 反过来的话，用户从训练记录跳过来之后就再也点不动左边这一列了。
    private var selected: PracticeSession? {
        sessions.first { $0.id == (selectedSessionID ?? requestedSessionID) } ?? sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // 入口摆在这里、**排在下面那个分支之前**，是因为条数为 0 时它也必须在，
            // 一次复盘都还没成功归档的人（恰恰最可能是取复盘一直失败的那位）更是要看得见它。
            HStack(alignment: .top, spacing: Spacing.lg) {
                SectionHeader(number: 5, label: "REVIEW REPORTS",
                              title: SidebarItem.reviewReports.title)
                Spacer(minLength: Spacing.md)
                pendingReviewEntry
            }
            if sessions.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    sessionList.frame(width: 240)
                    reportPane
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        // 换一次会话就重读一次文件。放在 body 里读盘的话，每次重绘都要碰一次磁盘。
        .task(id: selected?.id) { loadSelected() }
        // 同理：清点 pending-reviews 目录也要读盘，只在这一页出现时做一次。
        .task { loadInbox() }
        // 收件箱里补进去的复盘要出现在左边那一列，所以关掉它之后重读一次训练数据。
        .sheet(isPresented: $isShowingInbox, onDismiss: { app.reload() }) { inboxSheet }
    }

    // MARK: - 待处理复盘的入口（决策 2）

    /// 「重新导入待处理的复盘」。
    ///
    /// **标题逐字不能改**：`PracticeRunner` 取复盘失败时那两句话、`PendingReviewStore`
    /// 落盘撞名那句话，写的都是「到「复盘报告」页用「重新导入待处理的复盘」…」。
    /// 名字对不上，用户拿着那句提示会一直找（铁律 4）。
    ///
    /// **刻意不是主行动**：这一页的主角是复盘本身，用次一级的 `.bordered`
    /// （DESIGN-SYSTEM 第 4 节：每页最多一个主行动）。
    private var pendingReviewEntry: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            Button("重新导入待处理的复盘") { isShowingInbox = true }
                .buttonStyle(.bordered)
            Text(pendingCountText)
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// 待处理条数。**0 也要显示出来**，那是「清点过了，确实没有」的意思；
    /// 还没清点完时说的是另一句话，两者不能长得一样。
    private var pendingCountText: String {
        guard let inbox else { return "正在清点待处理的复盘…" }
        return "待处理 \(inbox.rows.count) 份"
    }

    @ViewBuilder private var inboxSheet: some View {
        if let inbox {
            PendingReviewInboxView(model: inbox, onClose: { isShowingInbox = false })
        } else {
            // 清点还没做完就被点开了（正常情况下碰不到：清点是毫秒级的本地读盘）。
            // 这里不能给一块空白，更不能假装「没有待处理的复盘」。
            VStack(spacing: Spacing.sm) {
                ProgressView()
                Text("正在清点待处理的复盘…下一步：等一下再点开；"
                     + "一直停在这里的话，多半是数据目录读不了，关掉这张表看看页面上的提示。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("关闭") { isShowingInbox = false }
                    .buttonStyle(.bordered)
            }
            .padding(Spacing.xl)
            .frame(minWidth: 360, alignment: .leading)
            .background(Palette.canvas)
        }
    }

    /// 清点待处理的复盘。**走 `AppState`**：数据目录在它手上，视图自己解析一次的话，
    /// 补进去的复盘可能落到另一个目录里，而用户看不到任何报错。
    private func loadInbox() {
        let model = app.makePendingReviewViewModel()
        model.refresh()
        inbox = model
    }

    // MARK: - 左边：哪几次练习有复盘

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("已归档 \(sessions.count) 次")
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PracticeSession) -> some View {
        let isSelected = selected?.id == session.id
        return Button {
            selectedSessionID = session.id
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(dateText(session.startedAt))
                    .font(Typography.cardTitle)
                Text(questionText(session))
                    .font(Typography.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(session.focusPart.rawValue)
                    .font(Typography.label)
            }
            // 选中态用紫底白字：白字压在 `Palette.accent` 上的对比度有测试守着
            // （`DesignSystemTests.testTextOnAccentMeetsAA`）。**副标题不许调淡**——
            // 白色降到 80% 就跌破 4.5:1，层级靠字号区分，不靠调淡。
            .foregroundStyle(isSelected ? Palette.textOnAccent : Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(isSelected ? Palette.accent : Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 右边：这一次的复盘

    @ViewBuilder private var reportPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let failure {
                    failureCard(failure)
                } else if let document {
                    if let target = document.priorityTarget { priorityCard(target) }
                    if !document.unreadableSections.isEmpty {
                        unreadableCard(document.unreadableSections)
                    }
                    ForEach(document.sections) { section in
                        sectionCard(section)
                    }
                    if document.isEmpty { emptyReportCard() }
                    originalFileFooter(document.path)
                } else {
                    // 读一份几 KB 的 JSON 是毫秒级的事，但「还没读」和「读完是空的」
                    // 不能长得一样——后者要说话，前者不能让人以为程序卡住了。
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("正在打开这一次的复盘…")
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 设计稿里那块深色的 NEXT SINGLE TARGET。
    ///
    /// 深色只有一个取值（`Palette.sidebarBackground`），白字压在它上面的对比度
    /// 已由 `DesignSystemTests.testSidebarTextMeetsAA` 守着，所以这里直接借用它，
    /// 而不是自己调一个新的深色——视图里出现字面颜色值是铁律 8 明令禁止的。
    private func priorityCard(_ target: ReviewRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("NEXT SINGLE TARGET")
                .font(Typography.label)
                .tracking(Tracking.label)
                .foregroundStyle(Palette.sidebarText)
            Text(target.primary)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.sidebarTextSelected)
                .textSelection(.enabled)
            if !target.note.isEmpty {
                Text("你当时说的：\(target.note)")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.sidebarText)
                    .textSelection(.enabled)
            }
            Text("下一步：下次练习时只盯这一个，别的先放着——一次改一样才看得出有没有改掉。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.sidebarText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Palette.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private func sectionCard(_ section: ReviewSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(section.title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(section.rows.count) 条")
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // 用下标而不是 `\.id` 做身份：id 由「键名 + 序号」拼出来，正常情况下唯一，
                    // 但复盘是 ChatGPT 生成的，不值得为这一点赌 ForEach 不错乱地复用行。
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        rowView(row, in: section)
                    }
                }
            }
        }
    }

    private func rowView(_ row: ReviewRow, in section: ReviewSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            field(label: section.primaryLabel, text: row.primary)
            // 第二格是「改成什么」，是这一行真正要看的东西，用语义色标出来。
            // `Palette.success` 对白卡片约 5.0:1，够当正文读（DESIGN-SYSTEM 第 2 节）。
            field(label: section.secondaryLabel, text: row.secondary, highlighted: true)
            field(label: section.noteLabel, text: row.note)
        }
    }

    @ViewBuilder
    private func field(label: String, text: String, highlighted: Bool = false) -> some View {
        // 某一格空着时整格不画，而不是留一行悬空的标注。
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                Text(text)
                    .font(highlighted ? Typography.cardTitle : Typography.body)
                    .foregroundStyle(highlighted ? Palette.success : Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 复盘里有内容、却一条都没读出来。**这一句必须说**——
    /// 悄悄少显示一节，用户永远不会知道自己少看了什么（同 `ArchiveOutcome.skipped`）。
    private func unreadableCard(_ titles: [String]) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("有 \(titles.count) 节没能显示出来", systemImage: "exclamationmark.triangle")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.warning)
                Text("「\(titles.joined(separator: "」「"))」在这份复盘里有内容，"
                     + "但一条都没能读出来，多半是 ChatGPT 这次用的字段名和本工具读的对不上。"
                     + "下一步：点下面的「在访达中显示原文」打开原文自己看一眼，内容一个字都没丢。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    private func emptyReportCard() -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这份复盘是空的", systemImage: "doc.text.magnifyingglass")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.warning)
                Text("文件读到了、格式也对，但里面没有任何一条可显示的内容——"
                     + "多半是那次练习太短，ChatGPT 没什么可点评的。"
                     + "下一步：到「今日训练」再练一场，说满三五分钟再结束。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    private func failureCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这一次的复盘打不开", systemImage: "xmark.octagon")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.danger)
                // 这句话里带着文件的完整路径（见 `ReviewReportLoader`），
                // 允许选中复制——用户要拿它去访达里找那个文件。
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("再试一次", action: loadSelected)
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    /// 原文在哪儿，以及一个直接打开它的按钮。
    /// 「让用户能自己去看原文」是这一页的硬要求——本工具读不出来的东西，他自己读得出来。
    private func originalFileFooter(_ path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("复盘原文：\(path)")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("在访达中显示原文") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - 一次复盘都还没有

    /// 空状态给足三样：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    ///
    /// 分两种说法：一次都没练过，和练过但没有一次存下复盘。
    /// 后者是真出过事的情况（当场取复盘失败），把「原文没丢、在哪儿」说清楚很重要——
    /// 用户最怕的是练了半小时的东西不见了。
    private var emptyState: some View {
        let practiced = app.state.sessions.count
        return EmptyStateView(
            message: practiced == 0 ? "还没有复盘可看" : "练过 \(practiced) 次，但没有一次存下复盘",
            hint: practiced == 0
                ? "练完一场之后，这一页会显示必须纠正的表达、更自然的说法、词汇升级，"
                    + "以及下一次要盯的那一个目标。下一步：到「今日训练」挑一道题开练。"
                : "这几次练习的档案里没有记下复盘文件的位置，多半是当时没能把复盘取回来。"
                    + "已经取回来的原文不会丢，都留在数据目录里。"
                    + "下一步：到「今日训练」再练一场，练完复盘会自动存档并出现在这一页。",
            actionTitle: "去今日训练",
            action: { onGo(.today) })
    }

    // MARK: - 读盘与文案

    private func loadSelected() {
        guard let session = selected else {
            document = nil
            failure = nil
            return
        }
        do {
            document = try app.loadReview(for: session)
            failure = nil
        } catch {
            // 打不开也要留下痕迹：错误信息里带着文件路径与下一步（铁律 7）。
            document = nil
            failure = error.localizedDescription
        }
    }

    private static let timestampParser = ISO8601DateFormatter()

    private static let dateDisplay: DateFormatter = {
        let formatter = DateFormatter()
        // 不写死格式，跟随用户在系统里设的地区——中文环境下自然是「2026年8月6日 上午10:00」。
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// 认不出来的时间戳原样显示，**不显示成空白**——空白会让人以为这一行坏了。
    private func dateText(_ iso: String) -> String {
        guard let date = Self.timestampParser.date(from: iso) else { return iso }
        return Self.dateDisplay.string(from: date)
    }

    private func questionText(_ session: PracticeSession) -> String {
        if let question = app.state.questions.first(where: { $0.id == session.questionId }) {
            return question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt
        }
        return session.questionId.isEmpty
            ? "（这次练习没有记下题目）"
            : "（题库里已经没有这道题了：\(session.questionId)）"
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("一次复盘都还没有") {
    ReviewReportView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-review")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in })
}
