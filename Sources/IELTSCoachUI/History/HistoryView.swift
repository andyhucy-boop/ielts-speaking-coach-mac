import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 训练记录页：按月列出练过的每一场，点开一场看那一场的逐字稿全文。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// 页头右上从前摆着「记录对话逐字稿」那个开关（Phase 4）。**Phase 10 Task 16 把它撤了。**
/// 它决定的是**每一场练习**要不要采集逐字稿，不是训练记录页的属性；
/// 而设置窗口的「练习偏好」里也有同一个开关，两处并存就是「同一个设置两个家」——
/// 两个家改的还是同一个字段，谁后写盘谁说了算，用户看到的是随机结果。
/// 这里只留一行只读现状 + 一颗「打开设置 › 练习偏好」按钮。
///
/// **这一页刻意不做搜索、筛选、导出。** 那些都不在 ROADMAP Phase 4 的交付清单里。
@MainActor
struct HistoryView: View {
    let app: AppState
    /// 空状态那颗按钮要把用户送到「今日训练」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `TodayView` / `ReviewReportView` 的做法一致——这一页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void
    /// 「打开设置 › 练习偏好」那颗按钮要把设置窗口停到哪一栏。
    let navigator: SettingsNavigator
    /// 「看这次的复盘」：跳到复盘报告页**并选中这一场**。同上，落地由 `RootView` 接。
    let onOpenReview: (PracticeSession) -> Void
    /// 打开 ⌘, 那个设置窗口。用系统给的这一个，不要私有 selector。
    @Environment(\.openSettings) private var openSettings

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
        .coachPageBody()
        .frame(maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - 页头与「逐字稿记录开着没有」那一行

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            PageHeader(number: 2, label: "TRAINING HISTORY", title: SidebarItem.history.title)
            transcriptStatus
        }
    }

    /// **只读现状 + 去哪儿改。这一页自己一个字都不写盘。**
    ///
    /// 这一行仍然要有：这一页就是逐字稿的产物，看到记录里没有对话时，
    /// 抬头能看见是不是自己把它关了——这是 Phase 4 把开关放在这儿的本意，保留下来了。
    /// 变的只是「改」这个动作：它现在只在设置窗口的「练习偏好」里做。
    ///
    /// 那句解释（「它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网」）跟着开关
    /// 一起搬去了设置窗口（`PracticePreferenceEditor.transcriptExplanation`），
    /// **不在两边各留一份**——两份说明迟早会说不一样的话。
    private var transcriptStatus: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            Text(PracticePreferenceEditor.transcriptStatusText(
                enabled: app.state.settings.transcriptEnabled))
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开设置 › 练习偏好") {
                navigator.open(.practice)
                openSettings()
            }
            .buttonStyle(.bordered)
            .font(Typography.action)
        }
        .frame(maxWidth: 320, alignment: .trailing)
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
                                // 时长排在条数前面：它是首页那句「有 N 场超过 2 小时…
                                // 到训练记录页核对这几场」唯一能兑现的字段。
                                Text(row.durationText)
                                    .font(Typography.label)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textSecondary)
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
                    Text("这一场没有逐字稿。可能是练习时逐字稿记录是关着的，"
                         + "也可能是这一场发生在这个功能上线之前。"
                         + "下一步：到「设置」（⌘,）里把「记录对话逐字稿」打开，下次练习就会记下来。")
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
        // 返回 nil 表示一切顺利；非 nil 是一段中文说明，三种情况都可能：
        // 记录删了但有文件没删掉、记录本身就没写进去、路径不合法所以整趟都没做。
        deletionFailure = app.deleteSession(row.session)
    }

    /// 删除没有按预期完成。**必须留在屏幕上**——这段话里有哪几个文件没删掉、在哪儿，
    /// 用一闪而过的提示的话，用户来不及读，那些孤儿文件就永远躺在磁盘上了（铁律 7）。
    ///
    /// **抬头刻意不写「只做完了一半」**：三条失败路径里有两条（写盘失败、路径不合法）
    /// 是一个字节都没动，抬头说「做完了一半」对它们是假话，而用户第一眼读的就是抬头。
    /// 具体做没做、做了多少，由 `message` 那一段逐字说清。
    private func deletionFailureCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这次删除没有正常完成", systemImage: "exclamationmark.triangle")
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
        navigator: SettingsNavigator(),
        onOpenReview: { _ in })
}
