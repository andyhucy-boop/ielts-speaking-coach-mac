import Foundation
import IELTSCoachCore
import SwiftUI

/// 一趟复训的三步流程：回看证据 → 重答原题 → 撤掉提示，开口说。
///
/// **这一页的成败判据只有一条：开口之后屏幕上不许再出现任何范答。**
/// 原话、原答、高分版全归第一步；第二步一按下去它们就没了，只剩题目和这一次的唯一目标。
/// 对着高分版念一遍不叫复训——那样练完，用户和这个工具都会以为他改掉了那个毛病。
///
/// **「显不显示」不在这里判，全部问 `RetrainingStep`。** 材料分成三段
///（`evidenceBody` / `modelAnswerCard` / `transcriptBody`），每段在 `content` 里由一句
/// `if step.showsXxx` 把着门，各自只有那一个调用点。这不是形式主义：
/// 复审实测过，把「第二步各画各的」那种写法里塞一句 `textCard(…evidence.modelAnswer)`，
/// 941 条测试一条不红，而真机上高分版就画在开口前那一屏上。
/// 现在两头都有守卫——`RetrainingStepTests` 钉住那几个属性答得对不对，
/// `RetrainingFlowViewTests` 钉住这三句 `if` 还在、以及三段之外谁都不许碰证据字段。
///
/// **换题验证（`run == .transfer`）从第二步开始**：正因为不给回看，才知道是不是真会了，
/// 还是只记住了那个答案（DEFINITION-OF-DONE 第 2 节）。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `PrimaryActionCard` 不在这里用——
/// sheet 的主行动是底部那颗按钮；`Palette` / `Spacing` / `Radius` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
///
/// **为什么不直接把 `PracticeSheet` 嵌进第三步**（计划原文是这么建议的）：
/// 它那颗「我练完了」写死了调 `runner.finishPractice()`，绕过 `RetrainingCoordinator.finish`。
/// 绕过去的后果正是 Task 9 存在的理由——这一场练完、复盘也存了，
/// 却一个字都没挂进复训台账：进度纹丝不动，而界面上看不出任何异样。
/// 所以第三步这里自己画，但显示的东西与 `PracticeSheet` 一致：
/// 阶段文案、正在录音、已记录几条对话、以及那颗「我练完了」。
@MainActor
struct RetrainingFlowView: View {
    let app: AppState
    let item: RetrainingItem
    /// 目标来源那一场练的是哪道题。**由调用方给，这里不回查**：来源记录允许被单条删除，
    /// 删掉之后就再也查不到了，而「原题重练还是换题验证」必须永远能判定。
    /// 空串表示确实查不到（含义见 `RetrainingCenterView.originalQuestionID(of:)`）。
    let originalQuestionID: String
    let onClose: () -> Void
    /// 跳到别的页面（例如题库空时的「去训练题库」）。由复训中心页提供，
    /// 它会顺手把这张 sheet 关掉——导航状态不归这张 sheet 管。
    let onGo: (SidebarItem) -> Void

    /// 规范第 5 节：开启「减弱动态效果」后不做任何过渡。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 这一趟练的是原题还是换的题。**是 `@State` 不是 `let`**：
    /// 练完之后在结果卡片上点「换这道题再练一趟」，就地转成换题验证的一趟。
    @State private var run: RetrainingRun
    @State private var step: RetrainingStep
    /// 这一趟要练的题。nil 表示还没挑（换题验证从复训中心进来时就是 nil）。
    @State private var question: Question?
    @State private var picked: String?
    /// 第一步要看的材料。**在 `onAppear` 里读一次**，不在 `body` 里现读——
    /// 那是一次磁盘 IO，放在 `body` 里等于每重绘一次读一遍文件。
    @State private var evidence: RetrainingEvidence?
    /// 这一趟的驱动器与编排器。开练那一刻才造，**每趟一台**：
    /// 复用同一台会把这一趟的复盘挂到上一趟那条记录上。
    @State private var runner: PracticeRunner?
    @State private var coordinator: RetrainingCoordinator?
    /// 练完并且真的走到底之后的判定。非 nil 时整页换成结果卡片。
    @State private var outcome: RetrainingOutcome?
    /// 上一次操作的中文说明（失败时必须显示，不许静默）。
    @State private var notice: String?
    /// 候选题按 Part 分栏之后，哪几栏是展开的。**`nil` = 用户还没动过折叠，按默认来**
    /// （`QuestionPartSections.defaultExpandedParts`）。理由与 `PracticeSheet` 那一处相同。
    @State private var expandedParts: Set<Int>?

    init(app: AppState, item: RetrainingItem, run: RetrainingRun, question: Question?,
         originalQuestionID: String,
         onClose: @escaping () -> Void, onGo: @escaping (SidebarItem) -> Void) {
        self.app = app
        self.item = item
        self.originalQuestionID = originalQuestionID
        self.onClose = onClose
        self.onGo = onGo
        _run = State(initialValue: run)
        _step = State(initialValue: run.firstStep)
        _question = State(initialValue: question)
        _picked = State(initialValue: question?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            stepBar
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            noticeCard
            Divider()
            actions
        }
        .padding(Spacing.xl)
        .frame(width: 660, height: 620)
        .background(Palette.canvas)
        .onAppear { loadEvidenceIfNeeded() }
    }

    // MARK: - 顶部：走到第几步了

    private var stepBar: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            ForEach(RetrainingStep.allCases) { candidate in
                stepChip(candidate)
            }
            Spacer(minLength: 0)
        }
    }

    /// 三步进度指示里的一格。
    ///
    /// 换题验证那一趟第一格显示成「已跳过」而不是干脆不画：少一格会让人以为自己漏了一步，
    /// 而这一步是**故意**不给的（不给回看，才知道是不是真会了）。
    private func stepChip(_ candidate: RetrainingStep) -> some View {
        let skipped = run == .transfer && candidate == .evidence
        let isCurrent = candidate == step && !skipped
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: stepIcon(candidate, skipped: skipped))
                // 等宽数字：三格并排时数字宽度不齐会很显眼（规范第 1 节最后一行）。
                Text("\(candidate.stepNumber)").monospacedDigit()
                Text(candidate.title)
            }
            .font(isCurrent ? Typography.cardTitle : Typography.label)
            .foregroundStyle(isCurrent ? Palette.accent : Palette.textSecondary)
            if skipped {
                Text("换题验证跳过这一步")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stepIcon(_ candidate: RetrainingStep, skipped: Bool) -> String {
        if skipped { return "minus.circle" }
        if candidate.stepNumber < step.stepNumber { return "checkmark.circle.fill" }
        return candidate == step ? "largecircle.fill.circle" : "circle"
    }

    // MARK: - 正文

    /// 正文。**「这一步给不给看」全部问 `RetrainingStep`，这里不自己判。**
    ///
    /// 三段材料各一句 `if`，条件是那几个有测试守着的属性。写成「每一步各画各的」
    ///（`switch step` 之后第二步一段、第三步一段）的话，谁往第二步那一段里塞一句
    /// `textCard(…evidence.modelAnswer)` 都编得过、跑得通、没有一条测试会红——
    /// 而那之后用户就是对着高分版念一遍。这条路复审已经实测走通过一次。
    @ViewBuilder private var content: some View {
        if outcome != nil {
            resultBody
        } else {
            explanationCard
            if step.showsGoal { goalLine }
            if step.showsEvidence { evidenceBody }
            if step.showsModelAnswer { modelAnswerCard }
            if step.showsEvidence { transcriptBody }
            if step == .rehearsal { rehearsalBody }
            if step == .speaking { speakingBody }
        }
    }

    /// 每一步都要把 `step.explanation` 摆出来：它同时说清这一步在干什么、下一步做什么。
    private var explanationCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("第 \(step.stepNumber) 步 · \(step.title)")
                    .font(Typography.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(step.explanation)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「本次唯一目标」那一行。**三步都在**（`RetrainingStep.showsGoal` 恒为真）：
    /// 目标是行为指令，不是答案；撤掉它，复训就和随便再练一遍没区别了。
    ///
    /// 文字取自 `RetrainingSetupBuilder.goalText`，与真正发给考官的那一段是同一个来源——
    /// 各写一份的话，屏幕上写的和提示词里发的就可能不是同一句。
    private var goalLine: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("本次唯一目标")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                Text(RetrainingSetupBuilder.goalText(for: item.target))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 第一步：回看证据（`step.showsEvidence` / `step.showsModelAnswer` 把门）

    /// 当时说的原话、完整原答、复盘说要改什么。
    ///
    /// **高分版不在这一段里**：它单独成段（`modelAnswerCard`），由 `showsModelAnswer` 单独把门。
    /// 分开是为了让「哪一样归哪个开关管」在源码上就是一一对应的——
    /// 挤在一段里的话，那个开关就没有自己的上屏通道，等于没人用它。
    @ViewBuilder private var evidenceBody: some View {
        if let evidence {
            // 材料不齐时那句中文说明要原样摆出来。少一块内容不要紧，
            // 少了还不说才要命——用户会以为这一页坏了。
            if let missing = evidence.missingNote { warningCard(missing) }
            if !evidence.quotes.isEmpty {
                listCard(title: "当时说的原话", lines: evidence.quotes)
            }
            if !evidence.originalAnswer.isEmpty {
                textCard(title: "当时的完整原答", text: evidence.originalAnswer)
            }
            if !evidence.changes.isEmpty {
                listCard(title: "复盘说改了什么", lines: evidence.changes)
            }
        } else {
            hintCard("正在读取那一场的复盘和逐字稿。"
                     + "下一步：稍等一下就会显示；若这句话一直停着，"
                     + "关掉这个窗口，从复训中心再进来一次。")
        }
    }

    /// 复盘给的高分版。**整页只有这一段会画它**，而且画不画由
    /// `RetrainingStep.showsModelAnswer` 说了算——只有第一步返回真
    ///（`RetrainingStepTests.testModelAnswerIsOnlyVisibleWhileReviewingEvidence`）。
    @ViewBuilder private var modelAnswerCard: some View {
        if let evidence, !evidence.modelAnswer.isEmpty {
            textCard(title: "复盘给的高分版", text: evidence.modelAnswer)
        }
    }

    /// 逐字稿里认得出是学员自己说的那几句。**同样是证据，同样只有第一步能看**：
    /// 照着自己上次那份念，和照着高分版念是同一件事。
    @ViewBuilder private var transcriptBody: some View {
        if let evidence {
            if evidence.learnerTurns.isEmpty {
                // 那个开关现在在 ⌘, 设置窗口的「练习偏好」那一栏
                // （`SettingsWindowView.transcriptPreference`，Phase 10 Task 16 从训练记录页
                // 页头收进去的）。**指错地方比不写下一步更糟**：用户会一直翻。
                // `RenderReachabilitySweepTests` 那条「控件得真在文案说的那一页上」钉着这一句。
                hintCard("这一场的逐字稿里没有认得出是你说的话。"
                         + "下一步：上面的原话与原答照样可用；想让以后每一场都留下逐字稿，"
                         + "到「设置」（⌘,）里确认「记录对话逐字稿」是开着的。")
            } else {
                listCard(title: "逐字稿里你说过的话",
                         lines: evidence.learnerTurns.map(\.text))
            }
        }
    }

    // MARK: - 第二步：提示已经撤掉，只剩题目和目标

    /// **这一段里一个证据字段都不许出现。** `RetrainingFlowViewTests` 那条结构性守卫
    /// 扫的就是「从这里顺着调用关系走得到的每一个成员」。
    @ViewBuilder private var rehearsalBody: some View {
        if let question {
            questionCard(question)
        } else {
            questionPicker
        }
    }

    /// 题目全文（含追问）。**这一步只有它和目标**——范答一个字都不在这一屏上。
    private func questionCard(_ question: Question) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("这一趟练的是 · Part \(question.part) · \(question.topic)")
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                Text(question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(question.followups.enumerated()), id: \.offset) { _, followup in
                    Text("· \(followup)")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var questionPicker: some View {
        if pickable.isEmpty {
            EmptyStateView(message: emptyCandidatesMessage,
                           hint: emptyCandidatesHint,
                           actionTitle: "去训练题库",
                           action: { onGo(.questionBank) })
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("挑一道题带着这个目标练")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                // 平常这里只有一栏（换题验证不跨 Part，`TransferQuestionPolicy` 就是这么筛的），
                // 那时 `notice` 是 nil、那一栏默认展开，看起来和从前一模一样。
                // 会分成几栏的是「原题查不到、退回整个题库」那一路——那一路此前是
                // 一张 258 条的平铺列表，Part 1 全排在最前面。
                sectionsNotice
                ForEach(candidateSections) { section in
                    QuestionPartSectionView(title: section.title,
                                            isExpanded: expansion(of: section.part)) {
                        ForEach(section.items) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
            }
        }
    }

    /// 分栏这件事本身的那一句交代。只有一栏时什么都不画。
    @ViewBuilder private var sectionsNotice: some View {
        if let line = QuestionPartSections.notice(for: candidateSections) {
            Text(line)
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 一条候选题。
    ///
    /// **同话题的那几条必须标出来**：同话题太接近原题，验证力度打折。
    /// 不给用会让题库小的用户当场卡死，所以留着，但要让他知道自己选的是什么。
    private func candidateRow(_ candidate: TransferCandidate) -> some View {
        let isPicked = picked == candidate.question.id
        return Button {
            picked = candidate.question.id
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: isPicked ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isPicked ? Palette.accent : Palette.textSecondary)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Part \(candidate.question.part) · \(candidate.question.topic)")
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                    Text(candidate.question.prompt.isEmpty
                         ? "（这道题没有题干）" : candidate.question.prompt)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if candidate.sameTopicAsOriginal {
                        Label("和原题同一个话题，验证力度打折", systemImage: "exclamationmark.triangle")
                            .font(Typography.label)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Spacer(minLength: Spacing.sm)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(isPicked ? Palette.accent : Palette.cardBorder,
                              lineWidth: BorderWidth.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 第三步：练习进行中

    /// 同 `rehearsalBody`：**这一段里一个证据字段都不许出现**。
    @ViewBuilder private var speakingBody: some View {
        if let runner {
            stageCard(runner)
            if let archived = runner.archiveNotice { hintCard(archived) }
            if let transcript = runner.transcriptNotice { warningCard(transcript) }
            if let recording = runner.recordingNotice { warningCard(recording) }
        } else {
            warningCard("这一趟还没有真的开练，所以这里没有进度可显示。"
                        + "下一步：回到第二步点「开始练习」；"
                        + "若按钮点了没反应，关掉这个窗口从复训中心再进来一次。")
        }
        // 挂不上台账必须让用户看见。静默过去的话，他会以为这一场计入了复训进度，
        // 而台账里其实什么都没有——本项目已知最危险的失败形态。
        if let failure = coordinator?.failure { warningCard(failure) }
    }

    /// 这一步在干什么。**任何时候都得有内容**——空白等于「程序卡住了」。
    /// 整条链路里最长的一步是启动语音，实测约 9 秒（规范第 5 节）。
    private func stageCard(_ runner: PracticeRunner) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    if runner.stage.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "waveform").foregroundStyle(Palette.textSecondary)
                    }
                    Text(runner.stage.userFacingText)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if runner.isRecording {
                    // 静止的，不做呼吸闪烁：用户这时候正要开口说英语。
                    Label("正在录音", systemImage: "record.circle")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.danger)
                }
                if runner.transcriptTurnCount > 0 {
                    Text("已记录 \(runner.transcriptTurnCount) 条对话")
                        .font(Typography.secondary)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: - 练完之后

    @ViewBuilder private var resultBody: some View {
        if let outcome {
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(RetrainingOutcomeText.headline(for: outcome))
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(RetrainingOutcomeText.detail(for: outcome))
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // **原文显示，不折叠、不省略。** 这句话是用户唯一能知道「哪一步没走通」的地方。
        if let failure = coordinator?.failure { warningCard(failure) }
        transferSection
    }

    /// 换题验证那一段。**这是整个 Phase 6 的价值所在**：
    /// 同一道题第二次答得好，可能只是记住了上次那份高分版。
    @ViewBuilder private var transferSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("换一道题验证")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("同一道题再答一遍，分不清是真会了还是只记住了那个答案。"
                 + "下一步：从下面挑一道题，带着同一个目标再练一趟。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if pickable.isEmpty {
                EmptyStateView(message: emptyCandidatesMessage,
                               hint: emptyCandidatesHint,
                               actionTitle: "去训练题库",
                               action: { onGo(.questionBank) })
            } else {
                ForEach(Array(pickable.prefix(5))) { candidate in
                    transferRow(candidate)
                }
            }
        }
    }

    private func transferRow(_ candidate: TransferCandidate) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Part \(candidate.question.part) · \(candidate.question.topic)")
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                    Text(candidate.question.prompt.isEmpty
                         ? "（这道题没有题干）" : candidate.question.prompt)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if candidate.sameTopicAsOriginal {
                        Label("和原题同一个话题，验证力度打折", systemImage: "exclamationmark.triangle")
                            .font(Typography.label)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Button("换这道题再练一趟") { startTransfer(with: candidate) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 小零件

    private func listCard(title: String, lines: [String]) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                // 用下标做身份：同一句话可能重复出现，按内容做身份时 ForEach 会错乱地复用行。
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text("· \(line)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func textCard(title: String, text: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func warningCard(_ text: String) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                Text(text)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func hintCard(_ text: String) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Palette.textSecondary)
                Text(text)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var noticeCard: some View {
        if let notice { warningCard(notice) }
    }

    // MARK: - 按钮：每个状态都得有一条出口

    @ViewBuilder private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: Spacing.md)
            if outcome != nil {
                // **这个动作只能由用户点，系统不许自动做**：一次没被点名不等于改掉了。
                Button("这个问题我不用再练了") { retire() }
                    .buttonStyle(.bordered)
                Button("完成") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)
            } else {
                stepActions
            }
        }
    }

    /// 开口前那两步的按钮。**「这一步能按哪颗」同样问 `RetrainingStep`**，
    /// 不按「按钮画在 `switch` 的哪一支里」定——按钮的位置随时会被挪，
    /// 而「哪一步还看得见证据」「哪一步才能开口」是这一页的规矩。
    @ViewBuilder private var stepActions: some View {
        if step == .speaking {
            speakingActions
        } else {
            Button("关掉") { onClose() }
                .buttonStyle(.bordered)
            // 第一步那颗：按下去，证据和高分版一起收走。
            if step.showsEvidence {
                Button("重答这道题") { advance(to: .rehearsal) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)
            }
            // 一道题都挑不出来时不摆这颗永远按不动的按钮：那时页面上的
            // `EmptyStateView` 已经给了唯一能做的事（去导入题库）。
            if step.canStartPractice, question != nil || !pickable.isEmpty {
                Button("开始练习") { startPractice() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    // 灰着的条件用 `pickedQuestion` 而不是 `picked`：把挑好那道题所在的栏
                    // 折起来之后它就不在屏幕上了，按钮还亮着的话，按下去什么都不会发生。
                    .disabled(question == nil && pickedQuestion == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var speakingActions: some View {
        if let runner {
            switch runner.stage {
            case .practicing:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我练完了") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)

            case .abandoned:
                // **放弃之后停在这里，不在同一帧关窗**（见 `abandon()`）：
                // `stageCard` 上那段交代和下面那张录音警告卡片，得有一帧画得出来才算数。
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)

            case .needsManualCopy:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我已经复制好了") { captureFromClipboard() }
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
                Button("完成") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)

            default:
                // 正在自动跑的那几步。只留取消——这时候点别的都没有意义。
                Button("取消") { abandon() }
                    .buttonStyle(.bordered)
            }
        } else {
            Button("关掉") { onClose() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - 动作

    /// 换一步。规范第 5 节：开着「减弱动态效果」时不做过渡。
    private func advance(to next: RetrainingStep) {
        if reduceMotion {
            step = next
        } else {
            withAnimation(.easeOut) { step = next }
        }
    }

    private func loadEvidenceIfNeeded() {
        // 换题验证那一趟根本不看证据，读它只是白读一次磁盘。
        guard evidence == nil, run == .original else { return }
        let source = app.state.sessions.first { $0.id == item.target.sourceSessionId }
        // 复盘读不到就传 nil，**不要编一份空的顶上**：
        // `RetrainingEvidenceBuilder` 会给出一句中文说明，那才是用户需要的东西。
        evidence = RetrainingEvidenceBuilder.build(
            target: item.target,
            report: source.flatMap { app.loadReviewJSON(for: $0) },
            transcript: source?.transcript ?? [])
    }

    /// 开练。**每趟造一台新的驱动器与编排器**，理由见 `runner` 的说明。
    private func startPractice() {
        let chosen = question ?? pickedQuestion
        guard let chosen else { return }
        question = chosen
        notice = nil
        let launcher = app.makePracticeRunner()
        runner = launcher
        let wiring = app.makeRetrainingCoordinator(launcher: launcher)
        coordinator = wiring
        advance(to: .speaking)
        Task {
            await wiring.start(target: item.target, question: chosen,
                               originalQuestionID: originalQuestionID)
        }
    }

    /// 从头再跑一遍这一趟。**沿用同一台驱动器**：换一台的话它手上「这一场的记录编号」
    /// 就没了，重试会在训练记录里多留一条空记录。
    private func relaunch() {
        guard let question, let coordinator else { return }
        Task {
            await coordinator.start(target: item.target, question: question,
                                    originalQuestionID: originalQuestionID)
        }
    }

    private func finish() {
        guard let coordinator, let runner else { return }
        Task {
            await coordinator.finish(target: item.target, originalQuestionID: originalQuestionID)
            settleAfterWrapUp(runner)
        }
    }

    private func captureFromClipboard() {
        guard let runner else { return }
        Task {
            // 抛出来的详情驱动自己已经放进 `stage` 了，上面那张阶段卡片会原样显示，
            // 而且它会停在 `.needsManualCopy` 让用户再复制一次——不是把路堵死。
            try? await runner.captureReviewFromClipboard()
            settleAfterWrapUp(runner)
        }
    }

    private func redo(_ retry: PracticeRetry) {
        switch retry {
        case .restart: relaunch()
        case .wrapUp: finish()
        case .clipboard: captureFromClipboard()
        }
    }

    /// 收尾之后决定还留不留在第三步。
    ///
    /// **只有真的走完（`.done`）才给结论。** 停在 `.needsManualCopy` 时复盘整份还留在
    /// ChatGPT 窗口里，用户复制一次就能救回来；这时候摆一张「这一次没有再被点名」的结果卡片，
    /// 依据是一份根本还没取回来的复盘——那正是本项目最忌讳的假结论。停在 `.failed` 时同理，
    /// 而且第三步上还有那颗重试按钮，把用户拽走等于把路堵死。
    private func settleAfterWrapUp(_ runner: PracticeRunner) {
        // 台账和复盘都写在磁盘上。不重读的话，下面判的是开练之前那一份。
        app.reload()
        guard runner.stage == .done else { return }
        let archived = runner.finishedSessionID.flatMap { id in
            app.state.sessions.first { $0.id == id }
        }
        outcome = RetrainingOutcome.judge(report: archived.flatMap { app.loadReviewJSON(for: $0) },
                                          targetKey: item.target.targetKey)
    }

    /// 换一道题，就地再跑一趟。**驱动器与编排器一起换掉**：
    /// 上一趟那台手上还留着上一场的记录编号与阶段，复用会把这一趟的复盘挂到上一场上去。
    private func startTransfer(with candidate: TransferCandidate) {
        run = .transfer
        question = candidate.question
        picked = candidate.question.id
        outcome = nil
        runner = nil
        coordinator = nil
        notice = nil
        advance(to: .rehearsal)
    }

    /// 「放弃这一场」/「取消」。
    ///
    /// **这里不关窗口，一帧都不许提前关**，理由与 `PracticeSheet.abandon()` 逐字相同：
    /// `cancel()` 就在这一刻收掉录音（可能因此生成一条本该被看见的录音警告）、
    /// 给出「逐字稿去哪儿了、录音留在哪儿、ChatGPT 那通语音要不要自己挂」那段交代。
    /// 同一帧 `onClose()` 会把它们连同那条警告一起抹掉。
    ///
    /// 关窗口归 `.abandoned` 那条分支里的「关掉」，由用户看完再点。
    /// 驱动器还没造出来（`runner == nil`）时这颗按钮画不出来，走不到这里。
    private func abandon() {
        runner?.cancel()
    }

    /// 「这个问题我不用再练了」。**系统永远不会替用户做这个决定**（计划的「决定 4」）：
    /// 一次没被点名不等于改掉了。
    private func retire() {
        if let failure = app.setRetrainingStatus(.retired, of: item.target.id) {
            notice = failure
        } else {
            onClose()
        }
    }

    // MARK: - 候选题

    /// 这一趟能挑的题。
    ///
    /// 有原题时交给 `TransferQuestionPolicy`：不跨 Part、排掉这个目标已经练过的、
    /// 换了话题的排前面。原题查不到（来源记录被删、或换季导入了新题库）时，
    /// 退回**这一趟刚练的那道题**作参照——同样保证不跨 Part，也仍然排掉已经练过的。
    /// 两样都没有时才把整个题库摆出来；那时列表旁边那句 `sourceIssue` 已经说明了为什么。
    private var pickable: [TransferCandidate] {
        if let reference = item.originalQuestion ?? question {
            return TransferQuestionPolicy.candidates(for: item.target,
                                                     originalQuestion: reference,
                                                     questions: app.state.questions,
                                                     sessions: app.state.sessions)
        }
        return app.state.questions.map {
            TransferCandidate(question: $0, sameTopicAsOriginal: false)
        }
    }

    /// 候选题按 Part 分栏。分栏规则与自由选题弹层共用 `QuestionPartSections`，
    /// 那边有测试守着；两处各写一份的话，同一件事会长成两个样子。
    private var candidateSections: [QuestionPartSection<TransferCandidate>] {
        QuestionPartSections.split(pickable) { $0.question.part }
    }

    /// 默认展开哪一栏时的「用户偏好」。换题验证的偏好就是**原题那个 Part**——
    /// 这一趟本来就只该在同一个 Part 里换（`TransferQuestionPolicy`）。
    /// 原题和这一趟的题都查不到时（`pickable` 那条退回整个题库的路）没有偏好，传 nil。
    private var referencePart: Int? { (item.originalQuestion ?? question)?.part }

    private var expandedPartsNow: Set<Int> {
        expandedParts ?? QuestionPartSections.defaultExpandedParts(
            inSections: candidateSections.map(\.part), preferredPart: referencePart)
    }

    /// 此刻屏幕上真的看得见的那些候选：展开的那几栏里的。**开练只认这一份。**
    private var visibleCandidates: [TransferCandidate] {
        QuestionPartSections.visibleItems(in: candidateSections, expandedParts: expandedPartsNow)
    }

    /// 用户挑中的那道题。**折起来的栏里那道不算数**——
    /// 选中一道、把那一栏折起来、再点「开始练习」的话，
    /// 练的会是屏幕上一道也看不见的题。
    private var pickedQuestion: Question? {
        guard let picked else { return nil }
        return visibleCandidates.first { $0.question.id == picked }?.question
    }

    /// 某一栏展开与否。收起一栏的同时把那一栏里挑好的题清掉，
    /// 否则屏幕上看不见的一道题仍然是「已选中」，而「开始练习」照样亮着。
    private func expansion(of part: Int) -> Binding<Bool> {
        Binding(get: { expandedPartsNow.contains(part) },
                set: { isExpanded in
                    var next = expandedPartsNow
                    if isExpanded {
                        next.insert(part)
                    } else {
                        next.remove(part)
                        if let picked, pickable.contains(where: {
                            $0.question.id == picked && $0.question.part == part
                        }) {
                            self.picked = nil
                        }
                    }
                    expandedParts = next
                })
    }

    private var emptyCandidatesMessage: String {
        guard let part = (item.originalQuestion ?? question)?.part else {
            return "题库里没有可以练的题目"
        }
        return "题库里没有第二道 Part \(part) 的题可以换"
    }

    private var emptyCandidatesHint: String {
        "换题验证只在同一个 Part 内换——Part 1 要短、Part 3 要展开，"
            + "同一个目标在两者里的达成标准根本不一样。"
            + "下一步：到「训练题库」导入更多题目，回到这里就能换一道再练一趟。"
    }
}
