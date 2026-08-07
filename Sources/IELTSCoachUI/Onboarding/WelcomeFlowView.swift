import AppKit
import ChatGPTBridge
import IELTSCoachCore
import Observation
import SwiftUI

/// 引导走到第几步。
///
/// **它必须活在 `RootView` 手里，不能是 `WelcomeFlowView` 自己的 `@State`。**
/// 「环境」那一步上的「重新检查」会把 `AppState.isCheckingPermission` 拨成 true，
/// 根视图整屏换成「正在检查运行环境…」，`WelcomeFlowView` 连同它的 `@State` 一起被销毁；
/// 查完回来的是全新的一份，于是用户按一下「重新检查」就被扔回第一步「欢迎」。
/// `PermissionGateView.recheckAttempts` 踩的是同一个坑，那里也是把状态提到了上一层。
@MainActor
@Observable
public final class OnboardingFlowModel {
    /// 第一次显示时定下来的步骤。**定下来之后不再跟着输入变。**
    ///
    /// 为什么要冻：`OnboardingFlow.steps` 里「题库已经有题就不问导入」那一条，会在用户
    /// 于引导里真的导入之后翻转——步骤数组当场少一项，后面几步的下标全部往前挪一格，
    /// 用户会看到自己被凭空推到了下一步，而刚导入的那份交代（含逐条警告）还没来得及看。
    ///
    /// `nil` 表示还没显示过，这时视图按当下的输入现算一份（与将要冻的那份完全相同），
    /// 所以第一帧不会是空白。
    public private(set) var frozenSteps: [OnboardingStep]?

    /// 当前走到第几步（下标）。
    public private(set) var index = 0

    public init() {}

    public func freeze(_ steps: [OnboardingStep]) {
        guard frozenSteps == nil else { return }
        frozenSteps = steps
    }

    public func advance() { index += 1 }

    public func goBack() { index = max(0, index - 1) }
}

/// 首次使用引导。
///
/// ## 这一页自己不写任何一句步骤文案
///
/// 标题、正文、主按钮的字全部来自 `OnboardingStep`，这一页只负责摆。视图里再写一套的话，
/// `OnboardingFlowTests` 里那几条「每一步都得有中文标题/正文/主按钮」「环境那步必须说清
/// 跳过之后会怎样」就管不到屏幕上真正显示的东西了。
///
/// ## 三步复用现成的页面，不另写一套
///
/// - **「环境」整块交给 `PermissionGateView`**（Phase 3 Task 2）。那一页上本来就有
///   「打开系统设置」「重新检查」「复制诊断信息」「先跳过」，而且它的引导语会按宿主
///   （`.app` / 命令行）说清该把**谁**加进辅助功能列表——那个坑本项目踩过一次。
///   所以这一步的动作行由它出，流程页**不再画第二套**（同一屏两颗写着几乎一样的字的按钮，
///   用户不知道该点哪个）。
/// - **「题库」整块交给 `QuestionBankImport.importFile(at:)` + `app.applyImport`**，
///   交代那张纸交给 `QuestionBankImportResultSheet`——与「训练题库」页同一条路、同一套话。
/// - **「录音」整块交给 `RecordingSettingsView`**（Phase 5 Task 8）。**绝不许自己写一遍
///   开关逻辑**：自己写会造出 Phase 5 明令禁止的那个状态——开关显示「开」、麦克风权限
///   根本没申请过，于是用户练完一场发现什么都没录，而且完全无从查起。
///
/// ## 版式
///
/// 颜色、字体、间距、圆角全部走令牌（铁律 8）。过渡动画受系统「减弱动态效果」管
/// （DESIGN-SYSTEM 第 5 节，那是硬性要求）。
@MainActor
public struct WelcomeFlowView: View {
    private let app: AppState
    private let model: OnboardingFlowModel
    /// 磁盘上记着「引导看过了」没有。由 `RootView` 从 `OnboardingProgressStore` 读来。
    ///
    /// **不把 store 本身传进视图**：预览会真的去读、去写用户本机的 UserDefaults，
    /// 那和 `PreviewSafetyTests` 拦的「预览别碰真实数据」是同一类副作用。
    private let hasCompletedBefore: Bool
    /// 走完最后一步、或在最后一步点了「先跳过」时调它：记下「引导看过了」并进主界面。
    private let onFinish: () -> Void

    /// 录音那一步内嵌的那份视图模型。**惰性造**：造它会去问系统麦克风权限的当前状态，
    /// 而用户多半停在第一步「欢迎」上，没必要一进来就问。
    @State private var recording: RecordingSettingsViewModel?
    /// 上一次导入题库的交代。非 nil 时弹 `QuestionBankImportResultSheet`。
    @State private var importFeedback: QuestionBankImportFeedback?

    /// 开了系统「减弱动态效果」就不做过渡（DESIGN-SYSTEM 第 5 节）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(app: AppState, model: OnboardingFlowModel,
                hasCompletedBefore: Bool, onFinish: @escaping () -> Void) {
        self.app = app
        self.model = model
        self.hasCompletedBefore = hasCompletedBefore
        self.onFinish = onFinish
    }

    // MARK: - 走到哪一步了

    /// 这一趟要走的几步。冻过就用冻的那份，没冻过就按当下的输入现算一份。
    private var steps: [OnboardingStep] {
        model.frozenSteps ?? OnboardingFlow.steps(permission: app.permission,
                                                  questionCount: app.state.questions.count,
                                                  hasCompletedBefore: hasCompletedBefore)
    }

    /// 当前下标。**夹在合法范围里**：步骤数组理论上可能比 `model.index` 短，
    /// 越界会直接崩掉整个 App，而这一屏正是用户见到的第一屏。
    private var index: Int { min(max(model.index, 0), max(steps.count - 1, 0)) }

    private var step: OnboardingStep? { steps.indices.contains(index) ? steps[index] : nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let step = step {
                progressLine
                ScrollView { stepContent(step) }
                footer(step)
            } else {
                nothingToConfirm
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.canvas)
        .font(Typography.body)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.index)
        .onAppear { model.freeze(steps) }
        // 「重新检查」查到就绪之后自动往前走一步：用户刚在系统设置里勾完开关回来，
        // 让他再点一次「下一步」是在问一个已经有答案的问题。
        .onChange(of: app.permission) { _, updated in
            guard step == .environment, updated == .ready else { return }
            advance()
        }
        .sheet(item: $importFeedback) { feedback in
            QuestionBankImportResultSheet(feedback: feedback) { importFeedback = nil }
        }
    }

    // MARK: - 第几步 / 共几步

    /// 数字一律等宽（DESIGN-SYSTEM 第 1 节最后一行）：3 跳到 4 时这一行不该横向抖一下。
    private var progressLine: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("第 \(index + 1) 步 / 共 \(steps.count) 步")
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            ProgressView(value: Double(index + 1), total: Double(max(steps.count, 1)))
                .tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 这一步显示什么

    @ViewBuilder private func stepContent(_ step: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(step.title)
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(step.body)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            switch step {
            case .environment: environmentStep
            case .questionBank: questionBankStep
            case .recordingChoice: recordingStep
            case .welcome, .ready: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 环境**不就绪**时才摆权限页。
    ///
    /// 就绪时摆它是在说假话：那一页最后一行写死着「「先跳过」后可以先浏览题库和历史复盘；
    /// 在上面的问题解决之前，自动驱动 ChatGPT 的练习没法进行」——而这时根本没有
    /// 「上面的问题」。同一屏上还会同时出现「环境就绪」和「先跳过」，用户读不出该信哪句。
    ///
    /// **这一步在就绪时仍然要显示**（用户有权知道这个 App 拿辅助功能去干什么，
    /// `OnboardingFlowTests.testFreshInstallStillExplainsThePermissionEvenWhenAlreadyGranted`
    /// 钉着这件事），只是退化成一句「已经拿到了」。
    private var showsPermissionGate: Bool { app.permission != .ready }

    /// 「环境」这一步的内容与动作。不就绪时整块来自 Phase 3 的授权页。
    ///
    /// `onSkip` 接的是流程页的「往前一步」，不是「从此不再提」：跳过之后如果权限仍缺，
    /// **下次启动还会再问一次**——没有辅助功能权限，这个产品的核心自动化就是残的，
    /// 每次开机温和地提醒一次（且一键可跳过）比默默残废好。
    @ViewBuilder private var environmentStep: some View {
        if showsPermissionGate {
            PermissionGateView(state: app.permission,
                               messages: app.permissionMessages,
                               recheckAttempts: app.recheckAttempts,
                               onRecheck: { Task { await app.recheckPermission() } },
                               onSkip: { advance() })
        } else {
            permissionReadyCard
        }
    }

    private var permissionReadyCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这台电脑已经给过辅助功能授权了", systemImage: "checkmark.circle")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.success)
                Text("所以上面那段「先跳过」这次用不上，这一步不用做什么。"
                     + "下一步：直接往下走。哪天这个授权没了（换了机器、或者系统升级把它重置了），"
                     + "本应用下次打开会再问你一次。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「题库」这一步：导入的结果由 `QuestionBankImportResultSheet` 弹出来交代
    /// （与「训练题库」页同一张纸），所以这里只补一句「不导会怎样」。
    ///
    /// **不许写成「跳过也能先用自带的样例题练」**：本工程没有任何一处会把样例题灌进
    /// `state.json`，跳过之后题库就是空的，首页四条练习路线一条都走不通
    /// （`TodayView.emptyBank`）。承诺一件不会发生的事，比不承诺更糟。
    private var questionBankStep: some View {
        CoachCard {
            Text("导入是可选的。现在跳过的话题库就是空的，首页会告诉你「题库还是空的」"
                 + "并带你去导入——那时再导完全一样。"
                 + "同一道题会被新的覆盖，不会变成两道，所以以后换季重新导入也是安全的。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「录音」这一步：整块内嵌 Phase 5 的录音设置页。
    ///
    /// 那一页自己管着「问权限 → 只有 granted 才写盘 → 写盘走 `RecordingConsent.enable` →
    /// 没拿到就把开关弹回「关」并显示引导」这一整条，引导页一个字节都不该另写。
    @ViewBuilder private var recordingStep: some View {
        if let recording = recording {
            RecordingSettingsView(viewModel: recording)
                // 每次进到这一步都重读一遍磁盘：占用与权限都可能在别处变过。
                .onAppear { recording.refresh() }
        } else {
            // 造之前的那一帧。空白会让人以为这一步坏了（DESIGN-SYSTEM 第 4 节）。
            Text("正在读取录音设置…下一步：稍等一下，读完开关就会出现在这里。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .task { recording = app.makeRecordingSettingsViewModel() }
        }
    }

    /// 一步都算不出来时的兜底。正常路径走不到这儿（`RootRouter` 只在
    /// `OnboardingFlow.shouldPresent` 为真时才显示本页），但一片空白会让用户以为程序坏了，
    /// 而且他会被永久困在这一屏——所以照空状态那三样给：现状、下一步、一个能点的按钮。
    private var nothingToConfirm: some View {
        EmptyStateView(
            message: "没有需要你确认的设置",
            hint: "运行环境和题库都已经就绪，直接开始用就行。",
            actionTitle: "开始使用",
            action: onFinish)
    }

    // MARK: - 底下那一行按钮

    /// **摆着权限页的那一步，动作行由权限页出，这里不画。**
    /// 它那一页上「打开系统设置」「重新检查」「复制诊断信息」「先跳过」四颗齐全，
    /// 流程页再画一颗「打开系统设置」和一颗「先跳过」，就是同一屏上两组同名按钮。
    ///
    /// 权限页不摆的时候（环境本来就绪，见 `showsPermissionGate`），动作行回到流程页手上。
    private func ownsActionRow(_ step: OnboardingStep) -> Bool {
        step != .environment || !showsPermissionGate
    }

    @ViewBuilder private func footer(_ step: OnboardingStep) -> some View {
        if index > 0 || ownsActionRow(step) {
            HStack(spacing: Spacing.sm) {
                if index > 0 {
                    Button("上一步") { model.goBack() }
                }
                Spacer(minLength: Spacing.sm)
                if ownsActionRow(step) {
                    Button(primaryTitle(step)) { primaryAction(step) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        // 回车即走。引导是一路按下去的东西，不该逼用户去够鼠标。
                        .keyboardShortcut(.defaultAction)
                    // **哪一步有「先跳过」由 `step.canSkip` 说了算，不写死。**
                    // 「环境」排除在外：不就绪时这一整行归权限页画（它自带一颗「先跳过」），
                    // 就绪时主按钮本身就是往前走，再来一颗就是两颗一模一样的按钮。
                    if step.canSkip && step != .environment {
                        Button(forwardTitle(step)) { advance() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 主按钮上写什么。
    ///
    /// 除「环境」之外都逐字来自 `OnboardingStep.primaryActionTitle`。
    /// 「环境」这一步只在**已经就绪**时才由流程页画主按钮，那时再写「打开系统设置」
    /// 就是让用户去办一件已经办完的事——它这时的主行动就是往下走。
    private func primaryTitle(_ step: OnboardingStep) -> String {
        step == .environment ? forwardTitle(step) : step.primaryActionTitle
    }

    /// 「主按钮按下去不会前进」的那几步，还需要一颗往前走的按钮。它写「先跳过」还是「下一步」，
    /// 看这一步到底还有没有事没办：
    ///
    /// - 「题库」：还没导进来写「先跳过」；刚导完写「下一步」——用户刚导完一份题库，
    ///   屏幕却让他「跳过」，会让人怀疑刚才那一下到底算不算数。题库里有题 = 他在这一步
    ///   真导进来了（这一步只在开始引导时题库为空才会出现）。
    /// - 「环境」：走到这里说明权限已经拿到了，没什么可跳的，写「下一步」。
    private func forwardTitle(_ step: OnboardingStep) -> String {
        switch step {
        case .questionBank: return app.state.questions.isEmpty ? "先跳过" : "下一步"
        default: return "下一步"
        }
    }

    // MARK: - 按下去之后

    private func primaryAction(_ step: OnboardingStep) {
        switch step {
        case .welcome, .recordingChoice: advance()
        case .questionBank: importQuestionBank()
        case .ready: finish()
        // 环境不就绪时这一支根本走不到——那时「打开系统设置」那一下由
        // `PermissionGateView` 里的 `PermissionStatus.openSettings(host:using:)` 干，
        // 而且它会把成功和失败都说出来。就绪时主按钮就是往下走。
        case .environment: advance()
        }
    }

    /// 往前一步；已经是最后一步就收工。
    private func advance() {
        guard index + 1 < steps.count else { finish(); return }
        model.advance()
    }

    private func finish() { onFinish() }

    /// 选一个题库文件导进来。
    ///
    /// 认格式、取文字、解析这三步**不在这里各写一遍**，走的是「训练题库」页同一个
    /// `QuestionBankImport.importFile(at:)`（含 PDF）；落盘走 `app.applyImport`，
    /// 与那一页同一个数据目录。各写一份的话，引导里导进去的题会落在别处，
    /// 用户走完引导到首页一看，题库还是空的。
    private func importQuestionBank() {
        let panel = NSOpenPanel()
        panel.title = "选择题库文件"
        panel.message = "支持这 \(QuestionBankImport.supportedExtensions.count) 种题库文件："
            + "\(QuestionBankImport.supportedFormatList)。"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = QuestionBankImport.allowedContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try QuestionBankImport.importFile(at: url)
            importFeedback = QuestionBankImportFeedback(outcome: try app.applyImport(result))
        } catch {
            // 导入失败必须说出来。静默吞掉的话，用户选完文件回来屏幕纹丝不动，
            // 只会以为这颗按钮坏了（铁律 7）。
            importFeedback = QuestionBankImportFeedback(
                failureMessage: QuestionBankImport.describeFailure(
                    error, fileName: url.lastPathComponent))
        }
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("首次使用引导") {
    WelcomeFlowView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-onboarding")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        model: OnboardingFlowModel(),
        hasCompletedBefore: false,
        onFinish: {})
}
