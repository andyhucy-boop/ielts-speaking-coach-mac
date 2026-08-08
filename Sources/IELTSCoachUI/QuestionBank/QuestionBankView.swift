import AppKit
import ChatGPTBridge
import IELTSCoachCore
import SwiftUI

/// 训练题库页：看题库里有什么、按 Part 筛、按话题分组，以及导入新题库。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `PrimaryActionCard` / `SectionHeader` /
/// `EmptyStateView`、`Palette` / `Spacing` / `Radius`）。**这里不许出现字面颜色、字号、圆角**——
/// 三个页面各写各的卡片样式，正是界面显得业余的头号原因，而它不会体现在任何一条测试上。
@MainActor
struct QuestionBankView: View {
    let app: AppState

    /// Part 筛选。**0 表示「全部」，不用 `Int?`。**
    /// `Picker` 的 Optional tag 极容易写成不匹配的类型（`.tag(1)` 是 `Int`，
    /// 而 selection 是 `Int?`），一旦对不上，分段控件看着能点、列表却纹丝不动——
    /// 编译器不会说一个字。用 `Int` 就没有这一类失效。
    @State private var partSelection = 0

    /// 上一次导入的交代。非 nil 时弹 `QuestionBankImportResultSheet`。
    ///
    /// **它不能画进下面那个滚动页面里。** 触发导入的按钮（`importCard`）在页面最底下，
    /// 而题库有几十个话题时页面远超一屏：画在页面里，用户选完文件回来，
    /// 交代就落在屏幕外，他看不到任何东西——计划要求逐条摆出来的那些警告尤其。
    /// `QuestionBankViewTests` 扫源码守着这一条。
    @State private var feedback: QuestionBankImportFeedback?

    private var partFilter: Int? { partSelection == 0 ? nil : partSelection }

    private var model: QuestionBankViewModel {
        QuestionBankViewModel(questions: app.state.questions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header
                if model.counts.total == 0 {
                    emptyBank
                } else {
                    legacyShapeCard
                    bank
                    importCard
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .sheet(item: $feedback) { result in
            QuestionBankImportResultSheet(feedback: result) { feedback = nil }
        }
    }

    // MARK: - 顶部：这个题库现在是什么样

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 2, label: "QUESTION BANK", title: SidebarItem.questionBank.title)
            CoachCard {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    statistic(model.counts.total, caption: "题库总题数")
                    statistic(model.counts.practiced, caption: "已经练过")
                    statistic(model.counts.total - model.counts.practiced, caption: "还没练过")
                }
            }
        }
    }

    /// 统计数字一律等宽（规范第 1 节最后一行）。否则 9 跳到 10 时整行会横向抖一下，
    /// 那种抖动没人说得出哪里不对，但会让整个界面显得廉价。
    private func statistic(_ value: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(value)")
                .font(Typography.number)
                .foregroundStyle(Palette.textPrimary)
            Text(caption)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - 题库还是旧结构时的提醒

    /// 题库仍是「一问一题」时摆在列表上方的一句话。已经是新结构就整块不显示。
    ///
    /// **摆在列表上方而不是页面底部。** 它要解释的正是下面那张列表为什么长成那样
    /// （一个话题下面挂着六道几乎一样的「题」），放在几十个话题之后等于没写。
    /// 文案本身在 `QuestionBankViewModel.legacyShapeNotice` 里，那边可测；
    /// 这里只负责把它摆上屏幕。
    @ViewBuilder
    private var legacyShapeCard: some View {
        if let notice = model.legacyShapeNotice {
            CoachCard {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "rectangle.stack.badge.person.crop")
                        .foregroundStyle(Palette.accent)
                    Text(notice)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 题库列表

    private var bank: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("按 Part 筛选题目", selection: $partSelection) {
                Text("全部").tag(0)
                Text("Part 1").tag(1)
                Text("Part 2").tag(2)
                Text("Part 3").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("按 Part 筛选题目")

            let groups = model.groupedByTopic(part: partFilter)
            if groups.isEmpty {
                noQuestionsInThisPart
            } else {
                ForEach(groups, id: \.topic) { group in
                    topicCard(topic: group.topic, questions: group.questions)
                }
            }
        }
    }

    private func topicCard(topic: String, questions: [Question]) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    // 话题可能是空的（CSV 里 topic 那列留白）。留一片空白会让人以为渲染坏了。
                    Text(topic.isEmpty ? "未标注话题" : topic)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    Text("\(questions.count) 题")
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // 用下标而不是 `\.id` 做 ForEach 的身份：题库正常情况下 id 唯一
                    // （`QuestionBankImporter.merge` 按 id 去重），但用户手工编辑过 state.json
                    // 之后未必如此，而 ForEach 遇到重复 id 会错乱地复用行——
                    // 显示出来是「同一道题出现两次、另一道消失」，极难查。
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        if index > 0 { Divider() }
                        questionRow(question)
                    }
                }
            }
        }
    }

    private func questionRow(_ question: Question) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text("Part \(question.part)")
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                if !question.followups.isEmpty {
                    Text("附 \(question.followups.count) 条追问")
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            Spacer(minLength: Spacing.sm)
            statusBadge(for: question)
        }
    }

    /// 状态只用 SF Symbols，不用 emoji（规范第 4 节）——emoji 跨系统版本渲染不一致，
    /// 也无法跟随语义颜色。
    @ViewBuilder
    private func statusBadge(for question: Question) -> some View {
        if question.status == "practiced" {
            Label("已练", systemImage: "checkmark.circle")
                .font(Typography.label)
                .foregroundStyle(Palette.success)
        } else {
            Label("没练过", systemImage: "circle")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - 两种空状态

    /// 题库整个是空的。这时页面上唯一该做的事就是导入，所以主行动就落在这儿
    /// （规范第 4 节：每页最多一个主行动），下面那张紫色的 `importCard` 此时不显示。
    private var emptyBank: some View {
        EmptyStateView(
            message: "题库还是空的",
            hint: "先导入你的雅思口语题库，才能开始练习。支持这 "
                + "\(QuestionBankImport.supportedExtensions.count) 种文件："
                + "\(QuestionBankImport.supportedFormatList)。",
            actionTitle: "导入题库…",
            action: chooseFile)
    }

    /// 题库有题，但当前这个 Part 一道都没有。
    ///
    /// 这里刻意**不用** `EmptyStateView`：它的按钮是 `borderedProminent`（紫色实心），
    /// 而此刻页面下方还有一张紫色的 `importCard`，两个同样醒目的紫色块会让人不知道该点哪个
    /// （规范第 4 节）。所以退成次一级的 `bordered`，但「说明现状 + 说明下一步 + 一个能直接点的按钮」
    /// 三样一个不少。
    private var noQuestionsInThisPart: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Part \(partSelection) 下还没有题目")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("题库里共有 \(model.counts.total) 道题，但没有一道属于 Part \(partSelection)。"
                     + "下一步：切回「全部」看看现有的题，或导入一份包含 Part \(partSelection) 的题库文件。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                Button("看全部题目") { partSelection = 0 }
                    .buttonStyle(.bordered)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - 导入

    private var importCard: some View {
        PrimaryActionCard(
            title: "再导入一份题库",
            subtitle: "支持 \(QuestionBankImport.supportedExtensionList)。"
                + "同一道题会被新的覆盖，不会变成两道——换季重新导入是安全的。",
            actionTitle: "导入题库…",
            action: chooseFile)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择题库文件"
        panel.message = "支持这 \(QuestionBankImport.supportedExtensions.count) 种题库文件："
            + "\(QuestionBankImport.supportedFormatList)。"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // 面板放行的类型与 `parse` 认的格式来自同一个 `QuestionBankImport.Format`。
        // 各写一份的话，面板放行了、解析却不认，用户会选完文件才被拒，白跑一趟。
        panel.allowedContentTypes = QuestionBankImport.allowedContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runImport(from: url)
    }

    /// 认格式、取文字、解析这三步**不在这里各写一遍**，全部收在
    /// `QuestionBankImport.importFile(at:)` 里——`View` 写不了单元测试，三步散在这儿时，
    /// 取文字那一步一旦被改回按 UTF-8 读文件，真实 PDF 就再也导不进来，
    /// 而三步各自的测试全都照绿。收口之后那条线由 `QuestionBankPDFImportTests` 守着，
    /// 「这一页确实调的是它」由 `QuestionBankViewTests` 扫源码守着。
    private func runImport(from url: URL) {
        do {
            let result = try QuestionBankImport.importFile(at: url)
            feedback = QuestionBankImportFeedback(outcome: try app.applyImport(result))
        } catch {
            feedback = QuestionBankImportFeedback(
                failureMessage: QuestionBankImport.describeFailure(
                    error, fileName: url.lastPathComponent))
        }
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("空题库") {
    QuestionBankView(app: AppState(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview-bank")),
        preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }))
}
