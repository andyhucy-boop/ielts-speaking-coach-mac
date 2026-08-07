import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 「每周训练目标」这块设置里的纯文案与取值范围。
/// 拆出来是为了能测——`View` 测不了，这几句话能测。
public enum WeeklyGoalEditor {
    /// 与落盘时的归一范围保持同一个来源。两处写死两个范围的话，
    /// Stepper 让你选 30、存下去却变成 5，用户会以为设置没生效。
    public static let range = CoachSettings.weeklyGoalRange

    public static func label(for goal: Int) -> String { "每周练 \(goal) 次" }

    /// 面板上那句「现在什么情况 + 下一步做什么」（铁律 6）。
    ///
    /// **已达标那一支不许说「还差」**：达标了还被告知「还差 -1 次」，
    /// 是这类文案最常见也最伤人的错法。
    public static func hint(done: Int, goal: Int) -> String {
        if done >= goal {
            return "本周已经练了 \(done) 次，达到目标了。"
                + "下一步：想继续练就继续，这个目标只是下限，不是上限。"
        }
        return "本周已经练了 \(done) 次，离目标还差 \(goal - done) 次。"
            + "下一步：目标定得能坚持下来，比定得高有用——定不下来的目标只会让人不想打开这个 App。"
    }
}

/// 改每周训练目标的小面板。由 `RootView` 工具栏的齿轮按钮与首页「本周训练」格里的
/// 「改目标」按钮共用同一个 binding 打开。
///
/// **这颗齿轮不挂 ⌘,。** `Sources/IELTSCoachApp/main.swift` 里已经有
/// `Settings { RecordingSettingsScene() }`，那个场景自带「设置…」菜单项与 ⌘,。
/// 两处绑同一个快捷键 SwiftUI 不报错，只会随机胜出一个——用户按 ⌘,
/// 时而弹录音设置、时而弹每周目标，而 Phase 5 有三处中文提示写着
/// 「到「录音设置」（⌘,）…」，那条指路会时灵时不灵
/// （`WeeklyGoalEntryPointTests.testTheGearButtonDoesNotStealTheSettingsShortcutFromPhase5` 钉着这件事）。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard`、`Palette` / `Spacing` / `Typography`）。
/// **这里不许出现字面颜色、字号、圆角。**
@MainActor
public struct WeeklyGoalSheet: View {
    let app: AppState
    @Binding var isPresented: Bool
    /// 面板里正在编辑的取值。打开时用 `app.state.settings.weeklyGoal` 初始化，
    /// 点「保存」才写盘——半路改一半就关掉不该留下痕迹。
    @State private var draft: Int

    public init(app: AppState, isPresented: Binding<Bool>) {
        self.app = app
        self._isPresented = isPresented
        self._draft = State(initialValue: app.state.settings.weeklyGoal)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            goalCard
            // 上一次没存成的话，这条必须一直摆着，而且面板不许关（见 `save()`）。
            if let failure = app.settingsError { failureCard(failure) }
            actions
        }
        .padding(Spacing.xl)
        .frame(minWidth: 420, alignment: .leading)
        .background(Palette.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("每周训练目标")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("这个数字只用来算首页那一格的本周进度，改它不会动到任何已经练过的记录。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Stepper 的可选范围来自 `WeeklyGoalEditor.range`，而它就是落盘时的归一范围本身——
    /// 界面能选、存下去却不认，是最难查的那类不一致。
    private var goalCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Stepper(value: $draft, in: WeeklyGoalEditor.range) {
                    // 等宽数字：从 9 跳到 10 时这一行不许横向抖（规范第 6 节最后一条）。
                    Text(WeeklyGoalEditor.label(for: draft))
                        .font(Typography.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
                Text(WeeklyGoalEditor.hint(done: weeklyDone, goal: draft))
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 本周已经练了几次。取自 `TodayViewModel`，与首页那一格同一个来源——
    /// 面板里另算一份的话，两处会给出两个不同的「本周练了几次」。
    private var weeklyDone: Int { TodayViewModel(state: app.state).weekProgress.done }

    /// 写盘失败时的全文。**可选中**：里面带着系统给的原始报错，用户要能复制走。
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

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: Spacing.md)
            // 「取消」直接关掉，一个字都不写盘。
            Button("取消") { isPresented = false }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// **存不下来就不关面板。** 关掉等于告诉用户「改好了」，
    /// 而他下次打开会发现目标又变回去了，且永远不知道为什么（铁律 7）。
    private func save() {
        guard app.setWeeklyGoal(draft) else { return }
        isPresented = false
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("每周训练目标") {
    WeeklyGoalSheet(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-weekly-goal")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        isPresented: .constant(true))
}
