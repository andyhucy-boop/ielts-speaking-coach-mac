import AppKit
import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// ⌘, 打开的那一个窗口。**全 App 的设置只有这一个家。**
///
/// Phase 10 之前它们散在四处：录音在这个窗口、每周目标在首页齿轮弹出的面板、
/// 三项练习偏好在学习计划页页尾、「记录对话逐字稿」在训练记录页页头。
/// Task 16 把它们收进这里的四个分区，旧入口一律改成「打开这个窗口并停在某一栏」的深链接。
///
/// ## 三条不能破的规矩
///
/// 1. **每一处取值都现读 `CoachSettingsViewModel`（它又现读 `app.state`），中间不许有 `@State` 副本。**
///    有副本的话，写盘失败时控件会停在用户刚拨到的位置——界面说改好了、磁盘上没变，
///    正是铁律 7 点名的那种静默失败。没有副本，控件自己就会弹回落盘的事实。
/// 2. **分区、标题、图标、那句「这一栏管什么」全部来自 `SettingsSection`**，
///    这里不另写一套。写两套的话，加一个分区就得改两处，而漏改的那一处不会报错。
/// 3. **录音那一格原样嵌 Phase 5 的 `RecordingSettingsView`，一行都不重写。**
///    它那套「权限没拿到时开关必须停在关」的逻辑是踩过坑换来的；
///    在这里重写一遍就会造出 Phase 5 明令禁止的状态：开关显示「开」、麦克风权限根本没申请过，
///    用户练完发现什么都没录，且无从查起。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `Palette` / `Spacing` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
@MainActor
public struct SettingsWindowView: View {
    private let app: AppState
    /// 停在哪一栏。**只存这一个**，任何设置的值都不在这里（见 `SettingsNavigator`）。
    private let navigator: SettingsNavigator

    /// 除录音之外三个分区的取值与写盘。
    @State private var settings: CoachSettingsViewModel
    /// 录音那一格。它持有自己的 `StateStore`，所以造它时挂了 `onChange`
    /// （在 `AppState.makeRecordingSettingsViewModel()` 里），写完盘会让主窗口那份状态重读。
    @State private var recording: RecordingSettingsViewModel
    /// 「在访达中显示」点失败时的说明。放 `@State` 是可以的：这颗按钮不换屏。
    @State private var revealNotice: String?

    /// 真正去访达里显示数据目录的那一下。返回是否成功。
    ///
    /// 做成参数而不是直接调 `NSWorkspace`，理由与 `RecordingSettingsView` 一致：
    /// 目录还没建出来时 `activateFileViewerSelecting` 会一声不响地什么都不做，
    /// 用户看到的就是一颗「点了没反应」的按钮（铁律 7）。
    private let revealFolder: (URL) -> Bool

    public init(app: AppState,
                navigator: SettingsNavigator,
                directory: DataDirectory = .resolve(),
                revealFolder: @escaping (URL) -> Bool = { url in
                    guard FileManager.default.fileExists(atPath: url.path) else { return false }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return true
                }) {
        self.app = app
        self.navigator = navigator
        self.revealFolder = revealFolder
        _settings = State(wrappedValue: CoachSettingsViewModel(app: app, directory: directory))
        _recording = State(wrappedValue: app.makeRecordingSettingsViewModel())
    }

    public var body: some View {
        TabView(selection: sectionSelection) {
            ForEach(SettingsSection.allCases) { section in
                sectionBody(section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
        // 窗口最小尺寸按四个分区里最高的那一个定（练习偏好有四张卡片），
        // 免得默认尺寸下最后一张被截掉。
        .frame(minWidth: 640, minHeight: 600)
        .background(Palette.canvas)
        .font(Typography.body)
        // 占用是练习时长出来的。停在打开 App 那一刻的数字等于在骗人。
        .onAppear { settings.refreshUsage() }
    }

    /// 当前停在哪一栏。**读写都走 `navigator`**：首页齿轮先 `open(.goals)` 再 `openSettings()`，
    /// 窗口打开时就已经在那一栏了。这里自己存一份的话，深链接会永远落在默认那一栏。
    private var sectionSelection: Binding<SettingsSection> {
        Binding(get: { navigator.section }, set: { navigator.open($0) })
    }

    /// 一栏的内容。**四个分支一个都不能少**，少一个那一栏就是个空白页。
    @ViewBuilder
    private func sectionBody(_ section: SettingsSection) -> some View {
        switch section {
        case .recording: recordingSection
        case .goals: pane(section, content: goalsSection)
        case .practice: pane(section, content: practiceSection)
        case .data: pane(section, content: dataSection)
        }
    }

    /// 三个自绘分区共用的外壳：这一栏管什么 + 上一次写盘失败的话摆在最上面 + 内容。
    ///
    /// **内容用 `some View` 参数而不是 `@ViewBuilder` 闭包**：带闭包的泛型函数
    /// 在可达性扫描眼里根本不是一个视图成员（`SourceGuard.viewMemberPatterns` 认不出
    /// `func pane<Content: View>(…)`），于是只被它调用的 `failureCard`
    /// 会被判成「写好了没上屏」。这里换成参数，整条链子重新连上。
    /// 那三句渲染本身仍由 `SettingsWindowViewTests` 单独钉着——
    /// 扫描只问「成员走不走得到」，问不出「传进来的东西画没画出来」。
    private func pane(_ section: SettingsSection, content: some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                summary(section)
                if let failure = settings.error { failureCard(failure) }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.xl)
        }
        .background(Palette.canvas)
    }

    /// 分区抬头。标题与那句「这一栏管什么」都来自 `SettingsSection`，这里不另写一份。
    private func summary(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(section.title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(section.summary)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 录音（原样嵌 Phase 5 那一页）

    /// **不套 `pane`**：`RecordingSettingsView` 自带滚动、内边距与底色，
    /// 再包一层会变成双层滚动条和 64pt 的空当。
    ///
    /// `.onAppear` 里那次 `refresh()` 不能省：用户在系统设置里撤掉麦克风权限之后，
    /// **只有重读一遍权限状态**，那颗开关才会从「开」回到「关」。
    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            summary(.recording)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)
            RecordingSettingsView(viewModel: recording)
                .onAppear { recording.refresh() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas)
    }

    // MARK: - 训练目标

    private var goalsSection: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Stepper(value: goalBinding, in: WeeklyGoalEditor.range) {
                    // 等宽数字：从「每周练 9 次」按到「每周练 10 次」时这一行不许横向抖
                    //（DESIGN-SYSTEM 第 6 节最后一条），而这里正是用户会反复来回按的地方。
                    Text(WeeklyGoalEditor.label(for: settings.weeklyGoal))
                        .font(Typography.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
                Text(settings.weeklyGoalHint)
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 范围就是落盘时的归一范围本身（`WeeklyGoalEditor.range`）。
    /// 界面能选、存下去却不认，是最难查的那类不一致。
    private var goalBinding: Binding<Int> {
        Binding(get: { settings.weeklyGoal }, set: { settings.setWeeklyGoal($0) })
    }

    // MARK: - 练习偏好（改动即时落盘）

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            routePreference
            feedbackPreference
            prepPreference
            transcriptPreference
        }
    }

    private var routePreference: some View {
        preferenceCard(
            title: "默认练习路线",
            explanation: PracticePreferenceEditor.defaultRouteExplanation,
            control: Picker("默认练习路线", selection: routeBinding) {
                ForEach(PracticeRoute.allCases) { route in
                    Text(route.title).tag(route)
                }
            }
                .pickerStyle(.radioGroup)
                .labelsHidden())
    }

    private var feedbackPreference: some View {
        preferenceCard(
            title: "反馈时机",
            explanation: PracticePreferenceEditor.feedbackTimingExplanation,
            control: Picker("反馈时机", selection: feedbackBinding) {
                ForEach(FeedbackTiming.allCases, id: \.self) { timing in
                    Text(PracticePreferenceEditor.feedbackTimingTitle(timing)).tag(timing)
                }
            }
                .pickerStyle(.radioGroup)
                .labelsHidden())
    }

    private var prepPreference: some View {
        preferenceCard(
            title: "Part 2 准备时间",
            explanation: PracticePreferenceEditor.part2PrepExplanation,
            control: Picker("Part 2 准备时间", selection: prepBinding) {
                ForEach(Part2PrepMode.allCases, id: \.self) { mode in
                    Text(PracticePreferenceEditor.part2PrepTitle(mode)).tag(mode)
                }
            }
                .pickerStyle(.radioGroup)
                .labelsHidden())
    }

    /// 「记录对话逐字稿」。Phase 4 把它放在训练记录页页头，Task 16 收到这里——
    /// 它决定的是**每一场练习**要不要采集逐字稿，不是训练记录页的属性。
    private var transcriptPreference: some View {
        preferenceCard(
            title: "逐字稿",
            explanation: PracticePreferenceEditor.transcriptExplanation,
            control: Toggle("记录对话逐字稿", isOn: transcriptBinding)
                .toggleStyle(.switch))
    }

    /// 四项偏好长得一样，所以摆版只写一处。
    ///
    /// **那行小字不是装饰**：两个选项哪个更合适取决于用户现在想练什么，
    /// 不写清代价的话他只能靠猜，而猜错要练完一整场才发现。
    ///
    /// 控件用 `some View` 参数而不是 `@ViewBuilder` 闭包，理由与 `pane` 相同：
    /// 带闭包的泛型函数在可达性扫描眼里不是一个视图成员。
    private func preferenceCard(title: String, explanation: String,
                                control: some View) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                control
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                Text(explanation)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 四项偏好的绑定（读现值、写视图模型，中间没有第二份状态）

    /// 默认练习路线。**存与读都走 `PracticeRoutePreference`**（在视图模型里）：
    /// Core 存的是字符串，两边靠一个约定好的名字对齐，没有任何类型能替我们检查它。
    private var routeBinding: Binding<PracticeRoute> {
        Binding(get: { settings.defaultRoute }, set: { settings.setDefaultRoute($0) })
    }

    private var feedbackBinding: Binding<FeedbackTiming> {
        Binding(get: { settings.feedbackTiming }, set: { settings.setFeedbackTiming($0) })
    }

    private var prepBinding: Binding<Part2PrepMode> {
        Binding(get: { settings.part2PrepMode }, set: { settings.setPart2PrepMode($0) })
    }

    private var transcriptBinding: Binding<Bool> {
        Binding(get: { settings.transcriptEnabled }, set: { settings.setTranscriptEnabled($0) })
    }

    // MARK: - 数据与隐私

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            dataLocationCard
            if let revealNotice { noticeCard(revealNotice) }
            privacyCard
        }
    }

    private var dataLocationCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("数据目录")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                // 完整路径，**可选中**：用户要能直接复制走（备份、换机器、贴给别人问）。
                Text(settings.dataDirectoryURL.path)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // 等宽数字：占用从 9 个文件跳到 12 个时，整行不该跟着抖。
                Text(settings.usage.summaryText)
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("在访达中显示") { reveal() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var privacyCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("换电脑时把这个文件夹整个拷过去就能接着用；备份就是拷贝它。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("你的练习内容只在这台电脑上，本工具不上传任何东西。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 目录还没建出来时访达会一声不响地什么都不做，所以这一路必须说话（铁律 7）。
    private func reveal() {
        guard revealFolder(settings.dataDirectoryURL) else {
            revealNotice = "没能在访达里打开这个文件夹（\(settings.dataDirectoryURL.path)）——"
                + "它多半还没建出来，第一次真的存下东西时才会建。"
                + "下一步：先练一场，或到「训练题库」页导入一份题库，再回来点这颗按钮。"
            return
        }
        revealNotice = nil
    }

    // MARK: - 两张说明卡片

    /// 写盘失败时的全文。**可选中**：里面带着系统给的原始报错，用户要能复制走。
    ///
    /// **不许把它藏起来。** 静默失败会让用户以为改好了，下次打开发现又变回去，
    /// 而且永远不知道为什么（铁律 7）。控件那一头不用管：所有取值都是现读磁盘的，
    /// 没存进去的话它自己就弹回原样了。
    private func failureCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这次没能存下来", systemImage: "exclamationmark.triangle")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.danger)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func noticeCard(_ message: String) -> some View {
        CoachCard {
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）
/// + 一个不会真去开访达的 `revealFolder`。见 `PreviewSafetyTests` 的说明。
#Preview("设置") {
    let directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ielts-coach-preview-settings"))
    return SettingsWindowView(
        app: AppState(
            directory: directory,
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        navigator: SettingsNavigator(),
        directory: directory,
        revealFolder: { _ in true })
}
