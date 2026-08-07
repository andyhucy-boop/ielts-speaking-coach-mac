import AppKit
import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI
import UniformTypeIdentifiers

/// 导出/复制之后要告诉用户的那句话。
///
/// **三档，不是两档。** 「存下去了」和「没存下去」之间还有第三种真实情况：
/// 文件确实写成功了，可里面一张卡片都没有（筛选筛空了，或者那几条词都缺字段）。
/// 只分成功/失败的话，这一种必然会被报成成功——而用户要到 Anki 里才发现导进去的是空气。
struct VocabularyExportNotice: Equatable {
    enum Kind: String, CaseIterable, Equatable {
        /// 真的写出去了，而且里面有卡片。
        case done
        /// 写出去了，但一张卡片都没有。
        case nothingExported
        /// 根本没写成。
        case failed
    }

    let kind: Kind
    /// 一句话说清发生了什么，以及（失败时）下一步做什么。
    let title: String
    /// `ExportDocument.skipped` 的每一条。**必须逐条上屏**——
    /// 静默少导出几条，用户在 Anki 里根本不会发现。
    let details: [String]
}

/// 我的词汇页：复盘推荐的词按「先背哪个」排开，能筛，能导出到 Anki。
///
/// **四条不能破的规矩：**
///
/// 1. **排序与筛选原样来自 `VocabularyViewModel`**，这一页不许再排一次、再筛一次——
///    那会造出第二套说法，而依据只有视图模型那一处有测试守着。
/// 2. **导出必须跟随当前筛选。** 用户筛到「优先记」再点导出却拿到全部词汇，
///    是典型的「界面骗人」，而他要到 Anki 里才会发现。
/// 3. **导出前后都要说清这个文件怎么用。** 导出一个文件却不说怎么用，等于没做这个功能。
/// 4. **`ExportDocument.skipped` 每一条都要上屏，剪贴板写失败也要说。**
///    只显示「导出成功」是本项目明令禁止的静默失败（铁律 7）。
///
/// 版式全部走设计令牌与组件（`CoachCard` / `SectionHeader` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
@MainActor
struct VocabularyView: View {
    let app: AppState
    /// 空状态那颗按钮要把用户送到「今日训练」。导航状态在 `RootView` 手上，所以由它传进来，
    /// 与 `TodayView` / `HistoryView` / `IssueArchiveView` 的做法一致。
    let onGo: (SidebarItem) -> Void
    /// 真正去写剪贴板的那一下。抽成闭包是为了让「写失败时到底会不会告诉用户」
    /// 这件事有测试管得住（`View` 本身无法单元测试）——做法与 `PermissionGateView` 一致。
    let writeToPasteboard: (String) -> Bool

    /// 当前选中的筛选档。
    @State private var filter: VocabularyFilter = .all
    /// 用户刚在菜单里选的导出格式。非 nil 时保存面板正开着。
    @State private var savingFormat: VocabularyExportFormat?
    /// 上一次选的格式。`savingFormat` 会在面板关掉的那一瞬间被清空，而 `onCompletion`
    /// 未必在那之前跑完——拿它拼「存好之后那句话」才不会取到 nil。
    @State private var lastChosenFormat: VocabularyExportFormat = .ankiTSV
    /// 导出/复制之后那句反馈。nil 表示还没点过。
    @State private var notice: VocabularyExportNotice?

    init(app: AppState, onGo: @escaping (SidebarItem) -> Void,
         writeToPasteboard: @escaping (String) -> Bool = { text in
             let pasteboard = NSPasteboard.general
             pasteboard.clearContents()
             return pasteboard.setString(text, forType: .string)
         }) {
        self.app = app
        self.onGo = onGo
        self.writeToPasteboard = writeToPasteboard
    }

    private var model: VocabularyViewModel { VocabularyViewModel(state: app.state) }

    /// 「复制到剪贴板」复制哪一种格式。
    ///
    /// 选 AnkiConnect 那一份是因为剪贴板这条路的用途就是喂给脚本（用户已经有一个
    /// AnkiConnect 脚本）；要拿去 Anki 手动导入的人本来就该存成文件。
    /// 这件事必须在界面上写明（见 `clipboardHint`）——按钮上只写「复制到剪贴板」
    /// 而不说复制的是什么，用户粘出来才发现不是他要的那种。
    static let clipboardFormat: VocabularyExportFormat = .ankiConnectJSON

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                summaryLine
                filterPicker
                exportSection
                howToUseSection
                noticeSection
                listSection
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .fileExporter(isPresented: savePanelIsShowing,
                      document: savingDocument,
                      contentType: Self.contentType(for: savingFormat ?? lastChosenFormat),
                      defaultFilename: savingFileName) { result in
            switch result {
            case .success(let url):
                // 重新算一份文档而不是捕获旧的：这中间用户动不了筛选（面板是模态的），
                // 两者内容一致，但重算不会拿到一份过期的快照。
                notice = Self.savedNotice(fileName: url.lastPathComponent,
                                          document: exportDocument(for: lastChosenFormat),
                                          format: lastChosenFormat)
            case .failure(let error):
                // 存不下去必须说清楚。`try?` 吞掉写盘失败然后显示「已导出」这种事，
                // 本项目发生过一次，不许再有（铁律 7）。
                notice = Self.failureNotice(error)
            }
        }
    }

    // MARK: - 页头与汇总

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(number: 1, label: "VOCABULARY", title: "我的词汇")
            Text("复盘里推荐过的词都在这儿，按「先背哪个」排好。"
                 + "筛完可以直接导出成 Anki 卡片——导出的就是你眼下看到的这些。")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 标题下那一行汇总。
    ///
    /// 抽成纯函数（`summaryText`）而不是在这儿拼字符串，理由和 `IssueArchiveView` 一样：
    /// 扫源码只问得出「这儿有个 `Text`」，问不出它到底说了什么。
    private var summaryLine: some View {
        let counts = model.counts
        return Text(Self.summaryText(total: counts.total, high: counts.high))
            .font(Typography.body)
            // 等宽数字：「共 9 个词」跳到「共 10 个词」时整行不许横向抖一下
            // （规范第 6 节最后一条）。
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
    }

    /// 汇总那句话。两个数字都来自 `VocabularyViewModel.counts`，这里不另算一份。
    /// 档次名取 `VocabularyPriority.high.title`，不手抄——改了档次名这句话会跟着改。
    static func summaryText(total: Int, high: Int) -> String {
        "共 \(total) 个词 · 其中 \(high) 个要\(VocabularyPriority.high.title)"
    }

    // MARK: - 筛选

    private var filterPicker: some View {
        Picker("筛选词汇", selection: $filter) {
            ForEach(VocabularyFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .font(Typography.body)
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: 420, alignment: .leading)
    }

    // MARK: - 导出（本任务的核心交付）

    /// 导出**当前筛选**下的词汇。内容与顺序原样来自 `VocabularyViewModel`。
    private func exportDocument(for format: VocabularyExportFormat) -> ExportDocument {
        model.exportDocument(format: format, filter: filter)
    }

    /// 保存面板开着没有。`savingFormat` 为 nil 就是关着。
    private var savePanelIsShowing: Binding<Bool> {
        Binding(get: { savingFormat != nil },
                set: { showing in if !showing { savingFormat = nil } })
    }

    /// 交给保存面板的那份文档。没选格式时是 nil（面板也不会开）。
    private var savingDocument: ExportTextDocument? {
        guard let savingFormat else { return nil }
        return ExportTextDocument(text: exportDocument(for: savingFormat).text,
                                  contentType: Self.contentType(for: savingFormat))
    }

    /// 保存面板里预填的文件名，来自 `ExportDocument.suggestedFileName`（带日期）。
    private var savingFileName: String? {
        savingFormat.map { exportDocument(for: $0).suggestedFileName }
    }

    /// 每种格式存成什么文件类型。
    ///
    /// **逐种写全，不许 `default:` 兜底**：将来加一种格式，兜底会把它静默地存成
    /// 某个已有的类型，编译器一声不吭。抽成纯函数是为了让它真跑得起来——
    /// 扫源码问不出「AnkiConnect 那一份到底存成了什么类型」。
    static func contentType(for format: VocabularyExportFormat) -> UTType {
        switch format {
        case .ankiTSV: return .plainText
        case .ankiConnectJSON: return .json
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Menu("导出…") {
                    ForEach(VocabularyExportFormat.allCases) { format in
                        Button(format.title) {
                            lastChosenFormat = format
                            savingFormat = format
                        }
                    }
                }
                .fixedSize()
                .disabled(model.rows.isEmpty)

                Button("复制到剪贴板") {
                    let document = exportDocument(for: Self.clipboardFormat)
                    // 写剪贴板是有可能失败的，`setString` 的返回值不能吞。
                    notice = Self.clipboardNotice(didWrite: writeToPasteboard(document.text),
                                                  document: document,
                                                  format: Self.clipboardFormat)
                }
                .disabled(model.rows.isEmpty)

                Spacer(minLength: 0)
            }

            // 灰掉的按钮必须说清为什么灰。一颗点了什么都不发生的按钮比一颗写明原因的
            // 灰按钮更让人困惑（DESIGN-SYSTEM 第 4 节的空状态同理）。
            Text(model.rows.isEmpty ? Self.disabledHint : Self.clipboardHint)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 词汇本为空时，两颗按钮为什么是灰的。
    static let disabledHint = "词汇本还是空的，现在没有任何东西可以导出，所以上面两个按钮是灰的。"
        + "下一步：去今日训练开一场，练完让 ChatGPT 生成复盘，推荐词汇会自动记到这里。"

    /// 有词的时候那句说明：**说清剪贴板里会是哪一种格式**。
    static let clipboardHint = "导出和复制都只包含你眼下筛选出来的这些词，顺序也和上面一致。"
        + "「复制到剪贴板」放进去的是 AnkiConnect 请求（.json）那一份，方便直接喂给脚本；"
        + "要拿去 Anki 里手动导入的话，用上面的导出菜单选第一种格式。"

    /// 导出的文件怎么用。**在用户点导出之前就摆在这儿**——
    /// 导出一个文件却不说怎么用，等于没做这个功能。
    private var howToUseSection: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("导出的文件怎么用")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                ForEach(VocabularyExportFormat.allCases) { format in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(format.title)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                        Text(format.howToUse)
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 导出之后那句反馈

    /// 存好之后那句话。
    ///
    /// **0 张卡片不算成功。** 文件确实写下去了，可里面什么都没有——
    /// 报成「已导出」的话，用户会拿着一个空文件去 Anki 里找不存在的问题。
    static func savedNotice(fileName: String, document: ExportDocument,
                            format: VocabularyExportFormat) -> VocabularyExportNotice {
        guard document.exportedCount > 0 else {
            return VocabularyExportNotice(
                kind: .nothingExported,
                title: "文件已经存到「\(fileName)」，但里面一张卡片都没有。",
                details: document.skipped)
        }
        return VocabularyExportNotice(
            kind: .done,
            title: "已经把 \(document.exportedCount) 张卡片存到「\(fileName)」。" + format.howToUse,
            details: document.skipped)
    }

    /// 存不下去时那句话。要带上系统给的原因，再给一步用户真做得到的动作。
    static func failureNotice(_ error: any Error) -> VocabularyExportNotice {
        VocabularyExportNotice(
            kind: .failed,
            title: "文件没能存下来：\(error.localizedDescription)。"
                + "下一步：换一个你有写入权限的位置再试一次。",
            details: [])
    }

    /// 点了「复制到剪贴板」之后那句话。
    ///
    /// 抽成纯函数是因为「写剪贴板失败了却显示已复制」正是本项目禁止的静默失败：
    /// `NSPasteboard.setString` 是有返回值的，吞掉它，用户会去 Anki 里粘一份空白。
    static func clipboardNotice(didWrite: Bool, document: ExportDocument,
                                format: VocabularyExportFormat) -> VocabularyExportNotice {
        guard didWrite else {
            return VocabularyExportNotice(
                kind: .failed,
                title: "剪贴板没能写进去，内容一个字都没有复制成功。"
                    + "下一步：改用上面的导出菜单把它存成文件，或者过几秒再点一次这颗按钮。",
                details: [])
        }
        guard document.exportedCount > 0 else {
            return VocabularyExportNotice(
                kind: .nothingExported,
                title: "剪贴板里现在是一份没有任何卡片的内容，粘到哪儿都不会有词。",
                details: document.skipped)
        }
        return VocabularyExportNotice(
            kind: .done,
            title: "已经把 \(document.exportedCount) 张卡片复制到剪贴板。" + format.howToUse,
            details: document.skipped)
    }

    /// 三档反馈的语义色。**逐档写全，不许 `default:` 兜底**——
    /// 将来加一档，兜底会把它静默地画成某个已有的颜色，编译器一声不吭。
    static func noticeColor(_ kind: VocabularyExportNotice.Kind) -> Color {
        switch kind {
        case .done: return Palette.success
        case .nothingExported: return Palette.warning
        case .failed: return Palette.danger
        }
    }

    /// 三档反馈的图标。只用 SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
    /// **颜色只是辅助**：图标和 `title` 那句话始终在，色觉障碍用户照样读得到发生了什么。
    static func noticeIcon(_ kind: VocabularyExportNotice.Kind) -> String {
        switch kind {
        case .done: return "checkmark.circle"
        case .nothingExported: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    /// 导出/复制之后那段反馈。**`details` 里每一条都要画出来**——
    /// 只显示「导出成功」而把跳过的几条吞掉，用户拿到的是一份比他以为的少几张卡的牌组。
    @ViewBuilder private var noticeSection: some View {
        if let notice {
            CoachCard {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: Self.noticeIcon(notice.kind))
                        .font(Typography.body)
                        .foregroundStyle(Self.noticeColor(notice.kind))
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(notice.title)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        // 用下标做身份：两条说明的文字理论上可能一样，拿内容当 id 会让
                        // ForEach 错乱地复用行。
                        ForEach(Array(notice.details.enumerated()), id: \.offset) { _, detail in
                            Text(detail)
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 列表

    /// 顺序与内容**原样**来自 `VocabularyViewModel`。这一页不排、不筛、不藏。
    @ViewBuilder private var listSection: some View {
        let visible = model.rows(filter: filter)
        if model.rows.isEmpty {
            emptyState
        } else if visible.isEmpty {
            filteredEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                // 用下标做身份：state.json 被外部工具改坏时会出现重复的词汇 id，
                // 而 ForEach 遇到重复 id 会错乱地复用行。
                ForEach(Array(visible.enumerated()), id: \.offset) { _, row in
                    vocabularyCard(row)
                }
            }
        }
    }

    /// 一行 = 一个词。「原来的说法 → 更好的说法」之间用 SF Symbol 的箭头给出方向感，
    /// 不用 emoji（DESIGN-SYSTEM 第 4 节）。
    private func vocabularyCard(_ row: VocabularyRow) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(row.basicWord)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                    Image(systemName: "arrow.right")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text(row.betterExpression)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.accent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: Spacing.sm)

                    // 优先级 pill。**文字始终在**，不靠颜色区分档次——
                    // 只靠颜色对色觉障碍用户等于没有标记。
                    Text(row.priority.title)
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Palette.canvas,
                                    in: RoundedRectangle(cornerRadius: Radius.pill))
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill)
                            .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline))
                }

                Text("搭配：\(row.collocation)")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // 等宽数字：从 9 跳到 10 时这一行不许横向抖（规范第 6 节最后一条）。
                Text("出现在 \(row.sessionCount) 场练习里")
                    .font(Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - 两种空状态

    /// 一个词都还没有。空状态给足三样：一句现状、一句下一步、一个能直接点的按钮
    /// （DESIGN-SYSTEM 第 4 节）。
    private var emptyState: some View {
        EmptyStateView(
            message: "词汇本还是空的",
            hint: "练一场并让 ChatGPT 生成复盘，推荐词汇会自动记到这里，"
                + "按「先背哪个」排好，还能一键导出成 Anki 卡片。"
                + "下一步：去今日训练开一场。",
            actionTitle: "去今日训练",
            action: { onGo(.today) })
    }

    /// 筛到一条都不剩。**同样不能留白**——摆一片空白的话，用户会以为筛选控件坏了。
    private var filteredEmptyState: some View {
        EmptyStateView(
            message: "当前筛选下没有词",
            hint: Self.filteredEmptyHint(filter),
            actionTitle: "看全部词汇",
            action: { filter = .all })
    }

    /// 筛空时那句话。要说清是**哪一档**筛空了，否则用户不知道自己现在在看什么。
    static func filteredEmptyHint(_ filter: VocabularyFilter) -> String {
        "「\(filter.title)」这一档现在一个词都没有——不是出错了，是确实没有符合的。"
            + "下一步：把上面的筛选换成「\(VocabularyFilter.all.title)」看看，"
            + "或者先去练一场，新的复盘会把新推荐的词补进来。"
    }
}

/// 预览一律注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 与 `PreviewSafetyTests` 的说明。
#Preview("一个词都还没有") {
    VocabularyView(
        app: AppState(
            directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "ielts-coach-preview-vocabulary")),
            preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
        onGo: { _ in },
        // 预览里不碰真剪贴板：画布一开就可能把用户正在复制的东西冲掉。
        writeToPasteboard: { _ in true })
}
