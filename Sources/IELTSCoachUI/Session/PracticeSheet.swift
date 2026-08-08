import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 练习进行中的界面。**Task 9 的交付物就是这张 sheet**：点一下「开始练习」之后，
/// 新建会话、启动语音、发考官提示词、练完取复盘、存档，全在这里发生，不需要打开终端
/// （成品标准第 2 条）。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// 最要紧的一条：**这张 sheet 必须一直在说话**。整条链路里最长的一步是启动语音，
/// 实测约 9 秒（spec 2.3.7）；中间界面一动不动的话，用户会以为程序卡死然后去强退，
/// 而那时 ChatGPT 那边的语音通话已经开起来了（DESIGN-SYSTEM 第 5 节）。
@MainActor
struct PracticeSheet: View {
    let runner: PracticeRunner
    let route: PracticeRoute
    /// 已经替用户定下来的这一场。nil 表示要先挑一道题（自由选题，
    /// 或者那条路线原来指着的题在题库里已经没有了）。
    let preselected: SessionSetup?
    /// 挑题用的候选。
    let candidates: [Question]
    /// 打开时 Part 筛选默认停在哪一档（0 = 全部）。由调用方按学习计划的「重点 Part」算出来，
    /// 规则在 `PracticePicker.defaultPart(forPlanFocus:)`，那边有测试守着。
    let defaultPart: Int
    /// 学习计划的「重点 Part」，只用来解释上面那个默认值是从哪儿来的（可以是 nil）。
    let planFocusPart: FocusPart?
    /// 把选中的题变成一场练习的设置。逻辑在 `TodayViewModel` 里，那边有测试守着。
    let makeSetup: (Question) -> SessionSetup
    let onClose: () -> Void

    /// 这一场最终定下来的设置。nil 时显示挑题列表。
    @State private var running: SessionSetup?
    @State private var picked: String?
    /// 当前的 Part 筛选。**0 表示「全部」，不用 `Int?`**——理由见
    /// `PracticePicker.allParts` 的说明（Optional tag 对不上时控件看着能点、列表纹丝不动）。
    ///
    /// 初值来自 `defaultPart`，所以它跟着学习计划的重点 Part 走；
    /// 用户在这里切档**不会**回写学习计划。
    @State private var partSelection: Int

    init(runner: PracticeRunner, route: PracticeRoute, preselected: SessionSetup?,
         candidates: [Question], defaultPart: Int = PracticePicker.allParts,
         planFocusPart: FocusPart? = nil,
         makeSetup: @escaping (Question) -> SessionSetup, onClose: @escaping () -> Void) {
        self.runner = runner
        self.route = route
        self.preselected = preselected
        self.candidates = candidates
        self.defaultPart = defaultPart
        self.planFocusPart = planFocusPart
        self.makeSetup = makeSetup
        self.onClose = onClose
        _partSelection = State(initialValue: defaultPart)
    }

    private var partPicker: PracticePicker { PracticePicker(questions: candidates) }

    /// 当前这一档筛出来的题。**挑好的那道不在这一档里时要把选择清掉**——
    /// 否则用户选了 Part 1 的一道题、切到 Part 2、再点「开始练习」，
    /// 练的是屏幕上一道也看不见的题。
    private var visibleCandidates: [Question] {
        partPicker.questions(inPart: partSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if let running {
                practiceBody(for: running)
            } else {
                picker
            }
            Divider()
            actions
        }
        .padding(Spacing.xl)
        .frame(width: 620)
        .background(Palette.canvas)
        .task {
            // 题已经定下来的路线直接开练：多让用户按一次「确认」只是白按一下，
            // 而成品标准第 1 条数的就是点击次数。
            guard running == nil, let preselected else { return }
            await begin(preselected)
        }
    }

    private func begin(_ setup: SessionSetup) async {
        running = setup
        // 失败不靠抛出来的错处理：`runner` 已经把它翻译成中文放进 `stage` 了，
        // 下面的 `stageBlock` 会原样显示。这里再吞一次只是不让它冒泡到 Task 里。
        try? await runner.start(setup: setup)
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(route.title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(route.subtitle)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - 还没定题：挑一道

    private var picker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if candidates.isEmpty {
                // 走不到这里（题库空时今日训练页整页都是导入引导），但真走到了也不能给白板。
                Text("题库里没有可以练的题目。下一步：关掉这个窗口，到「训练题库」导入你的题库文件。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("先选这一场练哪个 Part，再挑一道题。挑好之后本工具会自动打开 ChatGPT、进语音、"
                     + "并把这道题的考官提示词发过去——你什么都不用输。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                partSection
                if let notice = partPicker.emptyNotice(forPart: partSelection) {
                    emptyPartNotice(notice)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(visibleCandidates) { question in
                                questionRow(question)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
        }
    }

    /// **这一段就是用户要的那个「先选 Part」。**
    ///
    /// 三个 Part 是三种完全不同的题型，一次练习只可能是其中一种；从前这里是一张
    /// 258 道题（重建模之前 1265 道）的平铺列表，想练 Part 2 得滚过 60 个 Part 1 话题。
    ///
    /// 每一格的题数摆在下面那一行（`countsLine`）而不是格子里：四格挤在一行里，
    /// 写成「Part 1（60）」会被截断，而截断之后用户既看不清 Part 也看不清数。
    private var partSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Picker("这一场练哪个 Part", selection: $partSelection) {
                ForEach(PracticePicker.partOptions, id: \.self) { part in
                    Text(PracticePicker.segmentTitle(forPart: part)).tag(part)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("这一场练哪个 Part")
            // 切档之后，上一档里挑好的那道题必须失效：不清掉的话，用户选了 Part 1 的一道、
            // 切到 Part 2、再点「开始练习」，练的是屏幕上一道也看不见的题。
            .onChange(of: partSelection) { _, _ in
                if let picked, !visibleCandidates.contains(where: { $0.id == picked }) {
                    self.picked = nil
                }
            }

            Text(partPicker.countsLine)
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(partPicker.selectionSummary(forPart: partSelection))
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = PracticePicker.planFocusNotice(for: planFocusPart) {
                Text(notice)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 这一档一道题都没有。**不给白板**：说清现状、说清下一步，
    /// 而下一步指的那排分段按钮就在这句话上面，真实存在。
    private func emptyPartNotice(_ notice: String) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "tray")
                    .foregroundStyle(Palette.textSecondary)
                Text(notice)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func questionRow(_ question: Question) -> some View {
        Button {
            picked = question.id
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: picked == question.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(picked == question.id ? Palette.accent : Palette.textSecondary)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Part \(question.part) · \(question.topic)")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text(question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(picked == question.id ? Palette.accent : Palette.cardBorder,
                              lineWidth: BorderWidth.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 练起来之后：这一步在干什么

    @ViewBuilder
    private func practiceBody(for setup: SessionSetup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("这一场练的是")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text("\(setup.focusPart.rawValue) · \(setup.question.prompt)")
                        .font(Typography.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !setup.goal.isEmpty {
                        Text("本次目标：\(setup.goal)")
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            stageBlock
            recordingBlock
            transcriptBlock
            checklist
            if let notice = runner.archiveNotice {
                CoachCard {
                    Text(notice)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 当前这一步在干什么。**任何时候都得有内容**——空白等于「程序卡住了」。
    private var stageBlock: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if runner.stage.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: stageIcon)
                    .foregroundStyle(stageTint)
            }
            Text(runner.stage.userFacingText)
                .font(Typography.body)
                .foregroundStyle(stageTint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 录音这一路的交代。两半各守一件不能含糊的事：
    ///
    /// - **正在录音的指示**：麦克风开着却一点表示都没有，用户不知道自己什么时候在被录。
    ///   **静止的，不做呼吸闪烁**：一个一直在动的红点是这个界面上最容易让人分心的东西，
    ///   而用户这时候正要开口说英语（DESIGN-SYSTEM 第 5 节禁止循环装饰动画）。
    /// - **那句提示**：用户以为在录、实际没录（没权限、麦克风被别的程序占着），
    ///   或者中途插拔耳机断过一下。**不显示就是骗人**——练完点开回听才发现什么都没有。
    ///   用 `CoachCard` 装、文字可选中，方便用户把这句话复制去查。
    ///
    /// **开关关着时这里什么都不画**：那是默认状态，不是故障，为它摆一句提示会天天骚扰用户。
    /// `isRecording` 与 `recordingNotice` 那时都是 false / nil，两半自然都不出现。
    ///
    /// 两半都不抢「我练完了」那颗按钮的视觉主位：一行小字加一张说明卡，
    /// 主行动仍然只有底下那一颗（DESIGN-SYSTEM 第 4 节）。
    @ViewBuilder
    private var recordingBlock: some View {
        if runner.isRecording {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "record.circle")
                    .foregroundStyle(Palette.danger)
                Text("正在录音")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.danger)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在录音，这次练习你说的话会存在本机")
        }
        if let notice = runner.recordingNotice {
            CoachCard {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.bubble")
                        .foregroundStyle(Palette.warning)
                    Text(notice)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 逐字稿这一路的交代：练习中显示已经记下几条，练完/失败后如实说明缺了什么。
    ///
    /// **不画成红色的错误。** 逐字稿是增强，不是必需（ROADMAP 3.2）：采样失败不中断练习，
    /// 复盘和训练记录都照常。用 `Palette.warning` 而不是 `Palette.danger`，
    /// 是不想让用户以为这一场白练了。
    ///
    /// 但也**绝不省略**：悄悄丢掉几分钟对话、逐字稿看起来一切正常，
    /// 才是本项目最忌讳的失败形态。
    @ViewBuilder
    private var transcriptBlock: some View {
        if runner.transcriptTurnCount > 0 {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Palette.textSecondary)
                // 等宽数字：这个数字每采一次样就可能变，不等宽的话整行会跟着抖
                // （DESIGN-SYSTEM 第 6 节最后一条）。
                Text("已记录 \(runner.transcriptTurnCount) 条对话")
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        if let notice = runner.transcriptNotice {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(Palette.warning)
                Text(notice)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.warning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var stageIcon: String {
        switch runner.stage {
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        case .needsManualCopy: return "doc.on.clipboard"
        case .practicing: return "waveform"
        // 放弃不是故障，是用户自己的选择：给一个中性的「停」，不给三角警告。
        case .abandoned: return "stop.circle"
        default: return "circle"
        }
    }

    private var stageTint: Color {
        switch runner.stage {
        case .done: return Palette.success
        case .failed: return Palette.danger
        case .needsManualCopy: return Palette.warning
        default: return Palette.textPrimary
        }
    }

    /// 走到第几步了。失败与放弃时不画（`PracticeStage.showsChecklist`）：
    /// 这两种收场的 `order` 都是 -1，一格都不会打勾，画出来只是一列灰圈，
    /// 反而把那段真正要读的话（错误信息 / 放弃之后的交代）挤下去。
    @ViewBuilder
    private var checklist: some View {
        if !runner.stage.showsChecklist {
            EmptyView()
        } else {
            let steps = runner.stage.order > PracticeStage.practicing.order
                ? Self.wrapUpSteps : Self.startupSteps
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(steps, id: \.stepName) { step in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: runner.stage.order > step.order
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(runner.stage.order > step.order
                                             ? Palette.success : Palette.textSecondary)
                        Text(step.stepName)
                            .font(Typography.label)
                            .foregroundStyle(runner.stage.order >= step.order
                                             ? Palette.textPrimary : Palette.textSecondary)
                    }
                }
            }
        }
    }

    private static let startupSteps: [PracticeStage] =
        [.newChat, .startingVoice, .waitingComposer, .sendingPrompt]
    private static let wrapUpSteps: [PracticeStage] =
        [.endingVoice, .requestingReview, .capturingReview, .archiving]

    // MARK: - 按钮：每个状态都得有一条出口

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: Spacing.md)
            switch runner.stage {
            case .practicing:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我练完了") {
                    Task { try? await runner.finishPractice() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)

            case .needsManualCopy:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我已经复制好了") {
                    Task { try? await runner.captureReviewFromClipboard() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)

            case .failed:
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                if let retry = runner.retry {
                    Button(retry.buttonTitle) { redo(retry) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .keyboardShortcut(.defaultAction)
                }

            case .done:
                Button("完成", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)

            case .abandoned:
                // **放弃之后停在这里，不在同一帧关窗**（见 `abandon()`）。
                // 上面那段交代（逐字稿去哪儿了、录音留在哪儿、ChatGPT 那通语音要不要
                // 自己挂）和那张录音警告卡片，得有一帧画得出来才算数。
                // 这里只留「关掉」一颗：这个状态下再没有别的事可做了。
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)

            case .idle:
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                if running == nil {
                    Button("开始练习") { startPicked() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .disabled(picked == nil)
                        .keyboardShortcut(.defaultAction)
                }

            default:
                // 正在自动跑的那几步。只留取消——这时候点别的都没有意义。
                Button("取消") { abandon() }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// 「重试」到底重做什么，由 `runner.retry` 说了算。
    ///
    /// **不能一律重跑 `start`**：收尾阶段失败时重跑 start 的第一步是按「新建会话」，
    /// 那条刚练完、复盘还在里面的会话当场就没了。
    ///
    /// 按钮上写什么字用的是 `PracticeRetry.buttonTitle`，**不在这里另写一份**：
    /// 运行器的错误信息里会指名道姓提到这颗按钮，两处各写一份的话，
    /// 改了这边的字，那边指的就成了一颗界面上不存在的按钮。
    private func redo(_ retry: PracticeRetry) {
        switch retry {
        case .restart:
            // `running` 在 `begin` 里就已经设上了，走到这儿必然非 nil；
            // 兜一个 `preselected` 只是不让这颗按钮有任何一条「按下去什么都不发生」的可能。
            guard let setup = running ?? preselected else { return }
            Task { await begin(setup) }
        case .wrapUp:
            Task { try? await runner.finishPractice() }
        case .clipboard:
            Task { try? await runner.captureReviewFromClipboard() }
        }
    }

    /// 只认**当前这一档里看得见**的那道题。用 `candidates` 全库去找的话，
    /// 切档之后残留的那个 id 仍然找得到题——用户会练到一道屏幕上一道也看不见的题。
    private func startPicked() {
        guard let picked,
              let question = visibleCandidates.first(where: { $0.id == picked }) else { return }
        Task { await begin(makeSetup(question)) }
    }

    /// 「放弃这一场」/「取消」。
    ///
    /// **这里不关窗口，一帧都不许提前关。** `runner.cancel()` 恰好在这一刻做三件事：
    /// 关掉录音（可能因此生成一条「中途插拔耳机断过」「写盘失败，已录到的部分存在某处」
    /// 的警告）、把已经采到的逐字稿定案、写出那段「这一场已经放弃了…」的交代。
    /// 在同一帧调 `onClose()` 的话，这三样一个像素都画不出来——
    /// 真发生过的录音故障，唯一的出口被同一次点击关掉了（复审第 6 条）。
    ///
    /// 关窗口归 `.abandoned` 那条分支里的「关掉」，由用户看完再点。
    private func abandon() {
        runner.cancel()
    }
}

#if DEBUG
/// 预览专用的空壳 Bridge：**一次也不碰真实 ChatGPT**（铁律 5）。
///
/// 打开画布就会执行预览体，而 `PracticeSheet` 在题已经定下来时会自动开练——
/// 用真 Bridge 的话，看一眼布局就会在用户账号里新建会话、拨一通语音。
/// 所以预览一律传这个空壳，且 `preselected` 传 nil，停在挑题那一步。
/// 每个方法都抛错而不是假装成功：万一哪天预览真的走到开练那一步，
/// 看到的会是一句「这是预览」，而不是一条看着正常、其实什么都没发生的流程。
private struct InertBridge: CoachBridge, Sendable {
    private var refuse: BridgeError {
        .actionFailed("这是 Xcode 预览，不驱动真实的 ChatGPT。下一步：要真练一场，请运行 App。")
    }
    func preflight() -> BridgeReadiness {
        BridgeReadiness(ok: false, messages: ["这是 Xcode 预览，不驱动真实的 ChatGPT。"])
    }
    func startNewChat() throws { throw refuse }
    func sendText(_ text: String, into target: ComposerTarget) throws { throw refuse }
    func startVoice() throws { throw refuse }
    func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot { throw refuse }
    func isVoiceActive() -> Bool { false }
    func endVoice() throws { throw refuse }
    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String { throw refuse }
    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int) throws { throw refuse }
    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                    timeout: TimeInterval) throws -> String { throw refuse }
}

/// 同理：预览里点任何东西都不该动用户真实的剪贴板。
private struct InertPasteboard: PasteboardAccess {
    func readString() -> String? { nil }
    func clear() {}
}

#Preview("挑一道题") {
    PracticeSheet(
        runner: PracticeRunner(bridge: InertBridge(), pasteboard: InertPasteboard()),
        route: .freePick,
        preselected: nil,
        candidates: [
            Question(id: "p1-home-001", part: 1, topic: "Home",
                     prompt: "Do you live in a house or a flat?"),
            Question(id: "p2-skill-001", part: 2, topic: "Skills",
                     prompt: "Describe a skill you learned recently.")
        ],
        defaultPart: PracticePicker.allParts,
        planFocusPart: nil,
        makeSetup: { question in
            SessionSetup(question: question, focusPart: .part1, durationMinutes: 6, goal: "")
        },
        onClose: {})
}
#endif
