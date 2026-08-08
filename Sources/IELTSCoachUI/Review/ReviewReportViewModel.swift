import Foundation
import IELTSCoachCore

/// 复盘里的一条。
///
/// 三格分别是什么意思**由所属分区说了算**（见 `ReviewSection` 的三个标注）：
/// 「必须纠正的表达」里第二格是改正后的说法，「词汇升级」里第二格是更准确的词，
/// 「逐题高分版」里第二格是学员原来的回答。所以这里只叫 primary / secondary / note，
/// 不给它们起有含义的名字——起了就一定有一节对不上。
public struct ReviewRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let primary: String
    public let secondary: String
    public let note: String

    public init(id: String, primary: String, secondary: String, note: String) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.note = note
    }

    /// 三格全空的一行没有任何可看的东西。
    ///
    /// 这不是假想情况：ChatGPT 偶尔把某一节写成字符串数组（`["I very like it."]`）
    /// 而不是对象数组，那时每个字段都取不到，行里三格全是空字符串——
    /// 界面上就是一块有标题、底下全白的区，看着像渲染坏了。
    var isBlank: Bool {
        [primary, secondary, note].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 复盘里的一节。
public struct ReviewSection: Equatable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    /// 三格各自的中文标注。**必须有**：不标注的话，
    /// `good / rewarding / a rewarding trip` 三行摆在一起，
    /// 谁也看不出哪行是自己说的、哪行是建议。
    public let primaryLabel: String
    public let secondaryLabel: String
    public let noteLabel: String
    public let rows: [ReviewRow]

    public init(title: String, primaryLabel: String, secondaryLabel: String,
                noteLabel: String, rows: [ReviewRow]) {
        self.title = title
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.noteLabel = noteLabel
        self.rows = rows
    }
}

/// 把一份复盘 JSON 拆成界面要显示的分区，以及把会话列表整理成左边那一列。
///
/// 纯逻辑、无 IO——读文件那一段在 `ReviewReportLoader`。
/// 字段名以 `ReviewRequestPrompt`（spec 2.3.8 修复后）为准，一个字都不能改。
public enum ReviewReportViewModel {
    /// 一节的取值规则：标题、复盘里的键、三格取哪三个字段、三格怎么标注。
    private struct Layout {
        let title: String
        let key: String
        let fields: (String, String, String)
        let labels: (String, String, String)
    }

    /// 分区顺序固定，不随 JSON 键序变化——否则同一份复盘每次打开顺序都不一样。
    /// 顺序与 `ReviewRequestPrompt` 里那张键表一致。
    ///
    /// **这张表必须覆盖提示词要的每一个数组键。** 曾经这里只有四行，
    /// `habits`（口语习惯）与 `logic_feedback`（逐题逻辑反馈）ChatGPT 每次都给、
    /// 也原样存进了硬盘，界面却从头到尾一个字都不显示，连「有 N 节没能显示出来」
    /// 那张警告卡都提不到它们（它只遍历这张表）——用户得到的信号是「这就是完整的复盘」。
    /// 「回答前有较长停顿」「没有先直接回应问题」这类最该被看见的行为反馈，一条都不上屏。
    private static let layout: [Layout] = [
        Layout(title: "必须纠正的表达", key: "must_correct",
               fields: ("learner_said", "correction", "why_it_matters"),
               labels: ("你当时说的", "应该说", "为什么要改")),
        Layout(title: "更自然的表达", key: "natural_upgrades",
               fields: ("learner_said", "more_natural", "usage_note"),
               labels: ("你当时说的", "更自然的说法", "什么时候用")),
        Layout(title: "词汇升级", key: "vocabulary",
               fields: ("basic", "better", "collocation"),
               labels: ("你用的词", "更准确的表达", "搭配或例句")),
        // 第二格取 `fix`（提示词里新加的一项）：这一节讲的是习惯，而习惯要的是「下次怎么改」。
        // ChatGPT 没给 `fix` 时这一格空着不画，习惯本身与例证照样上屏。
        Layout(title: "口语习惯", key: "habits",
               fields: ("habit", "fix", "evidence"),
               labels: ("这个习惯", "下次怎么改", "当时的例证")),
        // 第二格是 improvement 而不是 issue：三格里被标绿、最先被读到的那一格，
        // 留给「该怎么办」比留给「哪里不好」有用。
        Layout(title: "逐题逻辑反馈", key: "logic_feedback",
               fields: ("question", "improvement", "issue"),
               labels: ("题目", "改进方向", "当时的问题")),
        Layout(title: "逐题高分版", key: "answer_upgrades",
               fields: ("question", "original_answer", "revised_answer"),
               labels: ("题目", "你当时的回答", "高分版"))
    ]

    /// 整体总结那一块的抬头。`unreadableSections` 用它点名，界面也用它当标题——
    /// 两处各写一份的话，警告卡说的名字会和页面上的标题对不上。
    public static let summaryTitle = "整体总结"

    public static func sections(from report: JSONValue) -> [ReviewSection] {
        layout.compactMap { entry in
            let rows = self.rows(for: entry, in: report)
            // 一条都读不出来时不画这一节。**但也不能就这么算了**——
            // 键在、内容也在却读不出来，是 `unreadableSections` 负责说出来的事。
            guard !rows.isEmpty else { return nil }
            return ReviewSection(title: entry.title,
                                 primaryLabel: entry.labels.0,
                                 secondaryLabel: entry.labels.1,
                                 noteLabel: entry.labels.2,
                                 rows: rows)
        }
    }

    /// ChatGPT 对这一场的整体总结（`summary`，一个字符串）。读不出来时是空串。
    ///
    /// **它必须上屏。** 这是整份复盘里唯一一段连贯的话，其余全是逐条清单；
    /// 而且它和 `habits` / `logic_feedback` 一样，此前既不显示也不报缺。
    public static func summary(from report: JSONValue) -> String {
        (report["summary"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 复盘里存在、且非空，却一条都没能读出来的分区名。
    ///
    /// 与 `ArchiveOutcome.skipped` 守的是同一件事：**读出 0 条不等于复盘里没有**，
    /// 更可能是 ChatGPT 换了字段名或整个形状（数组写成了对象）。
    /// 这种失败不报错、不崩溃，只是悄悄什么都不显示——本项目已知最危险的失败形态。
    public static func unreadableSections(in report: JSONValue) -> [String] {
        // 整体总结先算：`summary` 被写成对象或数组（`{"overall":"…"}`）时取不出字符串，
        // 那一整段话会凭空消失，而下面那圈只看数组键的检查一个字都提不到它。
        var titles: [String] = []
        if isPresentAndNonEmpty(report["summary"]) && summary(from: report).isEmpty {
            titles.append(summaryTitle)
        }
        titles += layout.compactMap { entry in
            guard isPresentAndNonEmpty(report[entry.key]) else { return nil }
            return rows(for: entry, in: report).isEmpty ? entry.title : nil
        }
        return titles
    }

    /// 那张深色的「下一次唯一目标」卡片要画的内容。没有目标时返回 nil。
    ///
    /// **判据整个交给 `RetrainingPolicy.extractTarget`，这里一个条件都不许自己加。**
    /// 曾经这里只要求 `label` 非空、归档那边只要求 `id` 非空，于是 ChatGPT 漏给 `id` 的那次，
    /// 卡片照画、`state.targets` 一条不加、`ArchiveOutcome.skipped` 还是空数组——
    /// 四个归档出口全都不吭声，用户在复训中心被告知「还没有待复训的目标」。
    /// 现在这两处共用同一份判据：**画得出卡片 ⟺ 归得进档案**。
    ///
    /// `createdAt` 传空串：它只写进档案里那条记录，卡片一个字都不显示它，
    /// 而这里要的只是「有没有目标、目标是什么」这份判断。
    public static func priorityTarget(from report: JSONValue, sessionID: String) -> ReviewRow? {
        guard let target = RetrainingPolicy.extractTarget(
            from: report, sessionID: sessionID, createdAt: "") else { return nil }
        // label 为空时退回 targetKey，与复训中心 `RetrainingCenterView.title(for:)` 的做法一致：
        // 一块没有标题的深色卡片，用户根本不知道要盯的是什么。
        let label = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewRow(id: target.targetKey,
                         primary: label.isEmpty ? target.targetKey : label,
                         secondary: target.status,
                         note: target.evidence.joined(separator: "；"))
    }

    /// 左边那一列：已经存下复盘原文的练习，最近的排在最上面。
    ///
    /// **没有 `reportPath` 的不能进来**——点开只会是一句「找不到复盘原文」，
    /// 用户会以为自己的记录坏了，而实际上那次练习本来就没归档复盘。
    /// **顺序必须是倒序**：练完立刻来看是最常见的用法，正序会让他每次都滚到底。
    public static func archivedSessions(in state: CoachState) -> [PracticeSession] {
        state.sessions
            .filter { !$0.reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - 私有

    private static func rows(for entry: Layout, in report: JSONValue) -> [ReviewRow] {
        // arrayValue 在形状不对时返回 nil（ChatGPT 曾把 vocabulary 输出成对象），
        // 此时这一节没有行而不是崩溃。
        guard let items = report[entry.key]?.arrayValue else { return [] }
        return items.enumerated().map { index, item in
            ReviewRow(id: "\(entry.key)-\(index)",
                      primary: item[entry.fields.0]?.stringValue ?? "",
                      secondary: item[entry.fields.1]?.stringValue ?? "",
                      note: item[entry.fields.2]?.stringValue ?? "")
        }.filter { !$0.isBlank }
    }

    /// 「这个键在复盘里存在且非空」的判定。**刻意不要求特定形状**——
    /// 实测故障里 vocabulary 曾被输出成一个非空对象而不是数组，若这里只认「非空数组」，
    /// 那次故障反而不会被报出来（`arrayValue` 直接是 nil，看起来像「键不存在」），
    /// 恰好漏掉最该报警的那一种。判定与 `ReviewArchiver` 里那份保持一致。
    private static func isPresentAndNonEmpty(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null: return false
        case .array(let items): return !items.isEmpty
        case .object(let dict): return !dict.isEmpty
        case .string(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bool, .number: return true
        }
    }
}
