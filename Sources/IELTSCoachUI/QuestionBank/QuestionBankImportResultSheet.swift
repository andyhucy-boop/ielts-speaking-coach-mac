import SwiftUI

/// 一次导入之后弹出来的那张交代。
///
/// **为什么是弹出来而不是画在页面上：** 触发导入的按钮在训练题库页的最底下，
/// 而题库有几十个话题时页面远超一屏（窗口 minHeight 600）。结果画在页面里，
/// 真实路径就成了「用户滚到底 → 点导入 → 选完文件 → 面板关闭 →
/// 结果出现在屏幕外的页面顶端」，用户看不到任何交代。
/// 弹出来则与滚动位置无关，空题库首次导入、题库已有内容再导入，两条路径一视同仁。
///
/// **警告要逐条摆出来。** 只显示「导入了 N 题 ✅」是这一页最容易犯的错：
/// 那些警告是在告诉用户「你的 CSV 第 7 行缺 id，那道题没进来」——比总数有用得多，
/// 而且不看就再也不会知道。所以正文这一段是可滚动的：一份坏掉的 CSV 可能有几十条警告，
/// 挤不下时必须能翻，不能截断。
///
/// 颜色、字体、间距、圆角全部走令牌（铁律 8）。
struct QuestionBankImportResultSheet: View {
    let feedback: QuestionBankImportFeedback
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(feedback.title, systemImage: symbolName)
                .font(Typography.cardTitle)
                .foregroundStyle(tint)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(feedback.message)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)

                    if !feedback.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            // 用下标做身份：两行 CSV 出一模一样的毛病时警告文本会重复，
                            // 而 ForEach 遇到重复 id 会错乱地复用行。
                            ForEach(Array(feedback.warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(Typography.secondary)
                                    .foregroundStyle(Palette.warning)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer(minLength: Spacing.md)
                Button("知道了", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    // 回车即关。读完警告要按的就这一个键，不该逼用户去够鼠标。
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 240, idealHeight: 360, maxHeight: 560)
        .background(Palette.card)
    }

    /// 图标只用 SF Symbols，不用 emoji（规范第 4 节）。
    private var symbolName: String {
        switch feedback.tone {
        case .done: return "checkmark.circle"
        case .nothing: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    /// 「一道题都没进来」用警告色而不是成功色——用户扫一眼绿色对勾就会走开，
    /// 而真正的原因全在下面那几条警告里（铁律 7）。
    private var tint: Color {
        switch feedback.tone {
        case .done: return Palette.success
        case .nothing: return Palette.warning
        case .failed: return Palette.danger
        }
    }
}

#Preview("导入完成，但有警告") {
    QuestionBankImportResultSheet(
        feedback: QuestionBankImportFeedback(outcome: QuestionBankImportOutcome(
            importedCount: 38, totalCount: 41,
            warnings: ["跳过第 7 行：缺少 id。下一步：给这道题一个唯一编号。",
                       "跳过第 12 行：part 不是 1/2/3。下一步：把它改成 1、2 或 3。"])),
        dismiss: {})
}

#Preview("一道题都没进来") {
    QuestionBankImportResultSheet(
        feedback: QuestionBankImportFeedback(outcome: QuestionBankImportOutcome(
            importedCount: 0, totalCount: 41,
            warnings: ["跳过第 2 行：缺少 id。下一步：给这道题一个唯一编号。"])),
        dismiss: {})
}
