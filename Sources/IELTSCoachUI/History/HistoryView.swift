import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 训练记录页：按月列出练过的每一场，点开一场看那一场的逐字稿全文。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// 页头右上那个「记录对话逐字稿」开关是逐字稿功能唯一的关闭入口（ROADMAP 第 5 节）。
/// 它摆在这一页而不是设置页，是因为这一页就是它的产物——用户在这儿看到记录为空，
/// 抬头就能看见是不是自己把它关了。
///
/// **这一页刻意不做搜索、筛选、导出。** 那些都不在 ROADMAP Phase 4 的交付清单里。
@MainActor
struct HistoryView: View {
    let app: AppState
    /// 空状态那颗按钮要把用户送到「今日训练」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `TodayView` / `ReviewReportView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void
    /// 「看这次的复盘」：跳到复盘报告页**并选中这一场**。同上，落地由 `RootView` 接。
    let onOpenReview: (PracticeSession) -> Void

    /// 展开着逐字稿的是哪一场。**存 id 不存整条记录**：列表会随 `app.state` 变，
    /// 存对象会在刷新之后指着一份旧的。
    @State private var expandedSessionID: String?
    /// 正在等用户确认删除的那一行。非 nil 时确认框开着。
    @State private var pendingDeletion: HistoryRow?
    /// 删除只完成了一半时那段中文说明。**不做成一闪而过的提示**——用户来不及读，
    /// 而这段话里带着「哪几个文件没删掉、在哪儿」，是他自己去清理的唯一线索。
    @State private var deletionFailure: String?
    /// 展开着的那一场的录音播放器。**跟着 `expandedSessionID` 一起换**。
    ///
    /// 放 `@State` 而不是每次画界面现造一份：那份视图模型带着「上一次操作说了什么」
    /// （`notice`）的状态，每次重绘现造的话，「录音已删除。这次练习的题目、逐字稿和复盘
    /// 都还在。」这句话会在下一次重绘时消失，用户根本来不及读。
    @State private var playback: RecordingPlaybackViewModel?

    private var model: HistoryViewModel { HistoryViewModel(state: app.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if let deletionFailure { deletionFailureCard(deletionFailure) }
            if model.isEmpty {
                emptyState
            } else {
                monthList
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .confirmationDialog(pendingDeletion.map(deletionTitle) ?? "",
                            isPresented: isConfirmingDeletion,
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { row in
            // 默认焦点不给这一颗：`.cancel` 那颗才是回车/ESC 落点。
            Button("删除这一场", role: .destructive) { destroy(row) }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { row in
            // **原样显示 `SessionDeletionPlan.confirmationText`**，不要自己另写一句：
            // 那段话逐条列明了会删掉哪些文件、以及错题本词汇本不会跟着删，
            // 而它的每一句都有 `SessionDeleterTests` 钉着。
            Text(SessionDeletion.plan(for: row.session).confirmationText)
        }
    }

    // MARK: - 页头与「记录对话逐字稿」开关

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            SectionHeader(number: 2, label: "TRAINING HISTORY", title: SidebarItem.history.title)
            transcriptToggle
        }
    }

    /// 开关**两头都要接**：读 `settings.transcriptEnabled`，写 `app.setTranscriptEnabled(_:)`。
    ///
    /// 下面那行小字不是可有可无的。「记录对话」四个字很容易被理解成录音，
    /// 而录音是另一个默认关闭、需要麦克风权限的开关。不写清楚，谨慎的用户只会把它关掉，
    /// 然后这一页对他永远是空的。
    private var transcriptToggle: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            Toggle("记录对话逐字稿", isOn: Binding(
                get: { app.state.settings.transcriptEnabled },
                set: { app.setTranscriptEnabled($0) }))
                .toggleStyle(.switch)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("开着时，练习中会把考官的问题和你的回答记下来，方便复盘时回看。"
                 + "它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .trailing)
        }
    }

    // MARK: - 按月分组的列表

    private var monthList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(model.months) { month in
                    monthSection(month)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func monthSection(_ month: HistoryMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(month.title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(month.rows.count) 场")
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(month.rows) { row in
                rowCard(row)
            }
        }
    }

    /// 一行 = 一场练习。五项缺一不可（ROADMAP Phase 4 交付清单里写死的）：
    /// 日期、Part、题目、对话条数、复盘状态。
    ///
    /// 删除那颗按钮是行的**兄弟**而不是塞在行里面：SwiftUI 里按钮套按钮的点击区
    /// 会互相吃掉，用户点删除会变成展开逐字稿。
    private func rowCard(_ row: HistoryRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button {
                    expandedSessionID = Self.toggling(expandedSessionID, to: row.id)
                    // 播放器跟着展开状态换。收起来时置 nil：留着的话，正在播的那条
                    // 录音会在一个看不见的视图里继续响（`.onDisappear` 会停掉它）。
                    playback = expandedSessionID == row.id
                        ? app.makeRecordingPlaybackViewModel(for: row.session) : nil
                } label: {
                    CoachCard {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                                Text(row.dateText)
                                    .font(Typography.cardTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                Text(row.partText)
                                    .font(Typography.label)
                                    .foregroundStyle(Palette.textSecondary)
                                Spacer(minLength: Spacing.sm)
                                recordingBadge(row)
                                // 等宽数字：条数从 9 跳到 12 时整行不该跟着抖。
                                Text(row.turnCountText)
                                    .font(Typography.label)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textSecondary)
                                Text(row.reviewStatusText)
                                    .font(Typography.label)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            // 题目已经不在题库里时标成警示色，**但这一行照常显示**——
                            // 藏起来会让用户以为这几场练习记录丢了（成品标准第 12 条）。
                            Text(row.questionText)
                                .font(Typography.body)
                                .foregroundStyle(row.questionIsMissing
                                                 ? Palette.warning : Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: Radius.card))
                .accessibilityHint("点开看这一场的逐字稿")

                deleteButton(row)
            }
            if expandedSessionID == row.id {
                // **播放器摆在逐字稿上方**：先听自己当时是怎么说的，再对照文字。
                // 反过来的话，一屏逐字稿会把播放器顶到看不见的地方。
                recordingPlayer
                transcriptPane(row)
            }
        }
    }

    /// 「这一场有录音」的标记。只认 `recordingPath` 非空，**不管文件在不在**——
    /// 文件不在了这件事由展开之后的播放器说清楚（它会明说「找不到了」并给出下一步），
    /// 在列表这一层去逐条摸磁盘，每滚一屏都要几十次 IO。
    @ViewBuilder
    private func recordingBadge(_ row: HistoryRow) -> some View {
        if row.hasRecording {
            // SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
            Image(systemName: "waveform")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                .help("这一场有录音，点开可以回听")
                .accessibilityLabel("这一场有录音")
        }
    }

    /// 展开之后那条内嵌播放器。
    ///
    /// `.id(...)` 不能省：换一场时视图在同一个位置上，不换 id 的话 SwiftUI 会复用
    /// 同一个 `RecordingPlayerView`，里面那台 `AVAudioPlayer`（`@State`）还是上一场的。
    ///
    /// 删完之后 `app.reload()` 一次：播放器写盘不经过 `AppState`，不重读的话
    /// 行上那个波形标记会一直留着，用户会再点一次删除。
    @ViewBuilder
    private var recordingPlayer: some View {
        if let playback {
            RecordingPlayerView(viewModel: playback, onRecordingRemoved: { app.reload() })
                .id(playback.sessionID)
        }
    }

    /// 行尾的删除入口。图标按钮，鼠标悬停有说明；点了先弹确认框，不直接删。
    private func deleteButton(_ row: HistoryRow) -> some View {
        Button {
            pendingDeletion = row
        } label: {
            Image(systemName: "trash")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .padding(Spacing.sm)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        .help("删除这条训练记录")
        .accessibilityLabel("删除这条训练记录")
    }

    /// 点了一行之后，展开着的应该是哪一场：点没展开的那一行就展开它，
    /// 再点一次同一行就收起来，点另一行就换过去（同时只展开一场，否则整页会滚不动）。
    ///
    /// **放成 `static` 纯函数，和 `speakerText(for:)` 同一个理由**：扫源码只问得出
    /// 「这一行给 `expandedSessionID` 赋了个值」，赋成 nil 也满足。复审实测把这里
    /// 改成 `expandedSessionID = nil`，656 条全绿——而那之后 `if expandedSessionID == row.id`
    /// 永远为假，逐字稿面板永远画不出来，这一页的头号功能整条死掉，
    /// 底下那一串扫描（transcriptPane / turn.text / 复盘按钮）全在扫一段渲染不到的代码。
    static func toggling(_ current: String?, to id: String) -> String? {
        current == id ? nil : id
    }

    // MARK: - 展开之后：这一场的逐字稿全文

    private func transcriptPane(_ row: HistoryRow) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if row.session.transcript.isEmpty {
                    // 空白会让用户以为这一页坏了。说清两种可能，再说下一步。
                    Text("这一场没有逐字稿。可能是练习时「记录对话逐字稿」是关着的，"
                         + "也可能是这一场发生在这个功能上线之前。"
                         + "下一步：确认上面的开关是开的，下次练习就会记下来。")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // 用下标而不是内容做身份：同一场里两句一模一样的话是常有的
                    //（「Sorry?」「Yes.」），拿内容当 id 会让 ForEach 错乱地复用行。
                    ForEach(Array(row.session.transcript.enumerated()), id: \.offset) { _, turn in
                        turnView(turn)
                    }
                }
                if row.hasReport {
                    Button("看这次的复盘") { onOpenReview(row.session) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// 逐字稿里的一条。考官靠左、自己靠右，底色也不同——
    /// 一整页不分左右的文字块，复盘时根本读不下去。
    private func turnView(_ turn: PracticeSession.TranscriptTurn) -> some View {
        let speaker = TranscriptSpeaker(rawValue: turn.role)
        let isLearner = speaker == .learner
        let isCertain = speaker == .learner || speaker == .examiner
        return VStack(alignment: isLearner ? .trailing : .leading, spacing: Spacing.xs) {
            Text(Self.speakerText(for: turn.role))
                .font(Typography.label)
                // 判不出是谁说的那些标成警示色：这一条读的时候要留个心眼。
                .foregroundStyle(isCertain ? Palette.textSecondary : Palette.warning)
            Text(turn.text)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(isLearner ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: isLearner ? .trailing : .leading)
        .padding(Spacing.sm)
        .background(isLearner ? Palette.canvas : Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline))
    }

    /// 这一条是谁说的。
    ///
    /// **判不出来时不许猜**（spec 2.3.9）：正在流式输出的消息还没有复制按钮，
    /// 采样时判不出归属就记成 `unknown`。猜错的后果是用户把考官说的话当成自己说的，
    /// 而这种错误没有任何信号提示——他会照着一句自己根本没说过的话去改。
    ///
    /// 放成 `static` 而不是内联在 `turnView` 里，是为了让这件事有一条真跑起来的测试
    /// 管得住；扫源码问不出「`system` 这种没见过的取值会被显示成什么」。
    static func speakerText(for role: String) -> String {
        switch TranscriptSpeaker(rawValue: role) {
        case .examiner: return "考官"
        case .learner: return "我"
        case .unknown, .none: return "说不准是谁说的"
        }
    }

    // MARK: - 删除

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } })
    }

    /// 确认框的标题要说清是**哪一场**：日期 + 题目。
    /// 只说「确定删除吗」的话，用户在一列长得差不多的记录里根本不敢按。
    private func deletionTitle(_ row: HistoryRow) -> String {
        "删掉 \(row.dateText) 那一场（\(row.partText)·\(row.questionText)）？"
    }

    private func destroy(_ row: HistoryRow) {
        pendingDeletion = nil
        // 整条记录都要删掉了，展开着的播放器也得跟着收——留着的话它指着一条
        // 已经不存在的记录，点「删除录音」会去删一个刚被连带删掉的文件。
        if expandedSessionID == row.id { expandedSessionID = nil; playback = nil }
        // 返回 nil 表示一切顺利；非 nil 是「记录删了，但有文件没删掉」的中文说明。
        deletionFailure = app.deleteSession(row.session)
    }

    /// 删除只完成了一半。**必须留在屏幕上**——这段话里有哪几个文件没删掉、在哪儿，
    /// 用一闪而过的提示的话，用户来不及读，那些孤儿文件就永远躺在磁盘上了（铁律 7）。
    private func deletionFailureCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这次删除只做完了一半", systemImage: "exclamationmark.triangle")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.warning)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("知道了") { deletionFailure = nil }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 一场都还没练过

    /// 空状态给足三样：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    private var emptyState: some View {
        EmptyStateView(
            message: "还没有训练记录。",
            hint: "练完第一场之后，这里会按月列出你练过的每一道题、每一次对话。",
            actionTitle: "去今日训练",
            action: { onGo(.today) })
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("一场都还没练过") {
    HistoryView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-history")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in },
        onOpenReview: { _ in })
}
