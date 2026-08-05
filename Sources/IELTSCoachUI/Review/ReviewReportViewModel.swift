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
        Layout(title: "逐题高分版", key: "answer_upgrades",
               fields: ("question", "original_answer", "revised_answer"),
               labels: ("题目", "你当时的回答", "高分版"))
    ]

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

    /// 复盘里存在、且非空，却一条都没能读出来的分区名。
    ///
    /// 与 `ArchiveOutcome.skipped` 守的是同一件事：**读出 0 条不等于复盘里没有**，
    /// 更可能是 ChatGPT 换了字段名或整个形状（数组写成了对象）。
    /// 这种失败不报错、不崩溃，只是悄悄什么都不显示——本项目已知最危险的失败形态。
    public static func unreadableSections(in report: JSONValue) -> [String] {
        layout.compactMap { entry in
            guard isPresentAndNonEmpty(report[entry.key]) else { return nil }
            return rows(for: entry, in: report).isEmpty ? entry.title : nil
        }
    }

    public static func priorityTarget(from report: JSONValue) -> ReviewRow? {
        guard let target = report["priority_target"], target.objectValue != nil,
              let label = target["label"]?.stringValue, !label.isEmpty else { return nil }
        let evidence = (target["evidence"]?.arrayValue ?? []).compactMap(\.stringValue)
        return ReviewRow(id: target["id"]?.stringValue ?? "target",
                         primary: label,
                         secondary: target["status"]?.stringValue ?? "new",
                         note: evidence.joined(separator: "；"))
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
