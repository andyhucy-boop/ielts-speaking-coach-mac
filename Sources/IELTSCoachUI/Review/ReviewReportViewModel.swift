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
    /// **第四格，可以没有。**
    ///
    /// 加它是为了「必须纠正的表达」那一节的 `mini_drill`（现在张嘴练什么）——
    /// 上游的这一节本来就是四列，本项目当初只移植了前三列，于是错题本里攒了一堆
    /// 「你说错了、应该这么说」，却没有一条告诉他此刻该练什么。
    ///
    /// **做成可选的第四格，而不是把某一格挤掉**：其余六节都只有三格，
    /// 挤掉任何一格都会让一条已经在显示的内容凭空消失。空串时整格不画。
    public let action: String

    public init(id: String, primary: String, secondary: String, note: String,
                action: String = "") {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.note = note
        self.action = action
    }

    /// 三格全空的一行没有任何可看的东西。
    ///
    /// 这不是假想情况：ChatGPT 偶尔把某一节写成字符串数组（`["I very like it."]`）
    /// 而不是对象数组，那时每个字段都取不到，行里三格全是空字符串——
    /// 界面上就是一块有标题、底下全白的区，看着像渲染坏了。
    var isBlank: Bool {
        [primary, secondary, note, action].allSatisfy {
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
    /// 第四格的标注。空串 = 这一节没有第四格（除「必须纠正的表达」外都是）。
    public let actionLabel: String
    public let rows: [ReviewRow]

    public init(title: String, primaryLabel: String, secondaryLabel: String,
                noteLabel: String, actionLabel: String = "", rows: [ReviewRow]) {
        self.title = title
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.noteLabel = noteLabel
        self.actionLabel = actionLabel
        self.rows = rows
    }
}

/// 把一份复盘 JSON 拆成界面要显示的分区，以及把会话列表整理成左边那一列。
///
/// 纯逻辑、无 IO——读文件那一段在 `ReviewReportLoader`。
/// 字段名以 `ReviewRequestPrompt`（spec 2.3.8 修复后）为准，一个字都不能改。
public enum ReviewReportViewModel {
    /// 一节的取值规则：标题、复盘里的键、三格取哪三个字段、三格怎么标注。
    /// 一节的取值规则：标题、复盘里的键、取哪几个字段、每一格怎么标注。
    ///
    /// **`fields` 与 `labels` 改成了等长的数组**（原先是三元组）。理由是各节的格数
    /// 已经不一样了：「亮点」只有两格，「必须纠正的表达」有四格，其余仍是三格。
    /// 继续用三元组的话，那两节只能靠塞空串或者挤掉一格来凑，而挤掉的那一格
    /// 是一条已经在显示的内容凭空消失。
    ///
    /// 代价是数组没有元组那种编译期的元数检查，所以补了一条测试
    /// （`testEverySectionDeclaresAsManyLabelsAsFields`）盯着两者等长、且在 2…4 之间。
    private struct Layout {
        let title: String
        let key: String
        let fields: [String]
        let labels: [String]

        /// 第 n 格的标注；这一节没有第 n 格时是空串（那一格整个不画）。
        func label(_ index: Int) -> String {
            index < labels.count ? labels[index] : ""
        }

        /// 第 n 格从这一条里取到的值；没有这一格、或者 ChatGPT 没给，都是空串。
        func value(_ index: Int, in item: JSONValue) -> String {
            guard index < fields.count else { return "" }
            return item[fields[index]]?.stringValue ?? ""
        }
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
        // **「这几句你说对了」排在最前面。**
        //
        // 这一节是照上游 report-schema.md 第 2 节（What worked）补的：那份规格里
        // 「亮点」就排在所有纠错之前，而本项目当初一节都没移植——整份复盘从第一行到
        // 最后一行全是「哪里不行」。对一个人练、没有老师的考生，这是唯一能告诉他
        // 「哪几个说法可以固定下来接着用」的地方。
        //
        // **它不是打分**：每一条都必须引他真说过的原话（提示词第 8 条钉着这件事），
        // 所以它和「绝不预测分数」那条红线不冲突。
        //
        // 只有两格：没有「第三格」可给，硬凑一格出来只会是空话。
        Layout(title: "这几句你说对了", key: "strengths",
               fields: ["learner_said", "why_it_works"],
               labels: ["你当时说的", "好在哪"]),
        // 四格。第四格 `mini_drill` 是上游这一节本来就有的第四列（Mini drill），
        // 当初漏了没移植：错题本里于是攒了一堆「你说错了、应该这么说」，
        // 却没有一条告诉他此刻该张嘴练什么。
        Layout(title: "必须纠正的表达", key: "must_correct",
               fields: ["learner_said", "correction", "why_it_matters", "mini_drill"],
               labels: ["你当时说的", "应该说", "为什么要改", "30 秒练法"]),
        Layout(title: "更自然的表达", key: "natural_upgrades",
               fields: ["learner_said", "more_natural", "usage_note"],
               labels: ["你当时说的", "更自然的说法", "什么时候用"]),
        Layout(title: "词汇升级", key: "vocabulary",
               fields: ["basic", "better", "collocation"],
               labels: ["你用的词", "更准确的表达", "搭配或例句"]),
        // 第二格取 `fix`（提示词里新加的一项）：这一节讲的是习惯，而习惯要的是「下次怎么改」。
        // ChatGPT 没给 `fix` 时这一格空着不画，习惯本身与例证照样上屏。
        Layout(title: "口语习惯", key: "habits",
               fields: ["habit", "fix", "evidence"],
               labels: ["这个习惯", "下次怎么改", "当时的例证"]),
        // 第二格是 improvement 而不是 issue：三格里被标绿、最先被读到的那一格，
        // 留给「该怎么办」比留给「哪里不好」有用。
        Layout(title: "逐题逻辑反馈", key: "logic_feedback",
               fields: ["question", "improvement", "issue"],
               labels: ["题目", "改进方向", "当时的问题"]),
        // 用户原话（2026-08-20）：「最后的 feedback 我建议你让 AI 还要给我一些内容上的建议，
        // 因为有些时候内容可能比较空洞。」
        //
        // 上面五节全在讲**怎么把同一句话说得更对、更地道、词用得更准**，没有一节回答
        // 「这段话本身有没有东西可说」。而「空洞」正是这位考生自己点名的毛病：
        // 话说得没错、也够长，内容却换一道题也照样能说一遍。
        //
        // **三格取满，一个字段都不多要。** `ReviewRow` 只有三格（`primary`/`secondary`/`note`），
        // 所以提示词那边就只要这三个字段。多要一个 `question` 出来却没格子显示的话，
        // ChatGPT 每次都白写、用户永远看不到，而且 `unreadableSections` 只盯「整节读不出来」、
        // 盯不到「少显示了一格」——那是本项目最忌讳的那种静默丢弃。
        //
        // 第二格照 `logic_feedback` 的规矩留给「该怎么办」：三格里被标绿、最先被读到的那一格，
        // 给「可以补什么」比给「你说得空」有用。
        Layout(title: "内容建议", key: "content_feedback",
               fields: ["thin_spot", "add_this", "example"],
               labels: ["你当时说空了的那句", "可以补什么", "可以这样说"]),
        Layout(title: "逐题高分版", key: "answer_upgrades",
               fields: ["question", "original_answer", "revised_answer"],
               labels: ["题目", "你当时的回答", "高分版"])
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
                                 primaryLabel: entry.label(0),
                                 secondaryLabel: entry.label(1),
                                 noteLabel: entry.label(2),
                                 actionLabel: entry.label(3),
                                 rows: rows)
        }
    }

    /// ChatGPT 对这一场的整体总结（`summary`，一个字符串）。读不出来时是空串。
    ///
    /// **它必须上屏。** 这是整份复盘里唯一一段连贯的话，其余全是逐条清单；
    /// 而且它和 `habits` / `logic_feedback` 一样，此前既不显示也不报缺。
    public static func summary(from report: JSONValue) -> String {
        BandScoreGuard.stripping(rawSummary(from: report))
    }

    /// 硬盘上那份原文里的总结，**一个字都没动过**。
    ///
    /// `summary(from:)` 会把出现雅思分数的那一句挡掉（`BandScoreGuard`），
    /// 而「这一节到底是不是空的」这类判断必须问原文——问挡过之后的那份，
    /// 一份整段都是分数的总结会被判成「ChatGPT 根本没写总结」，
    /// 而实际情况是写了、只是被挡了，两者该说的话完全不同。
    public static func rawSummary(from report: JSONValue) -> String {
        (report["summary"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 这份复盘里出现了雅思分数时要说的那句话；没有就是 nil。
    ///
    /// 提示词里那条「绝不预测分数」此前是**唯一**的防线，全靠 ChatGPT 自觉，
    /// 而它每换一次模型都可能不自觉一次（见 `BandScoreGuard`）。
    public static func scoreNotice(from report: JSONValue) -> String? {
        BandScoreGuard.notice(for: rawSummary(from: report))
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
        // **判据问的是原文（`rawSummary`），不是挡过分数之后那份。**
        // 问后者的话，一段整句都是「大概 6.5 分」的总结会被判成「ChatGPT 没写总结」，
        // 而它其实写了、只是被挡掉了——那两件事该对用户说的话完全不同，
        // 而「被挡了」已经由 `scoreNotice` 单独说过一遍。
        if isPresentAndNonEmpty(report["summary"]) && rawSummary(from: report).isEmpty {
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
        // **id 用 `RetrainingTarget.id`（`targetKey@sourceSessionId`），不是 `targetKey`。**
        //
        // 这一行是「带着这条去复训」那颗按钮的地址：复训中心按
        // `items.contains { $0.id == selectedID }` 找那一条，而它那边的 id 是复合的。
        // 传 `targetKey` 的话，跳过去之后什么都不会被选中，按钮点了像没反应——
        // 而 `targetKey` 跨 session 会重复，本来就不能当唯一键
        //（`RetrainingTarget.id` 的注释里写过这件事）。
        return ReviewRow(id: target.id,
                         primary: label.isEmpty ? target.targetKey : label,
                         secondary: target.status,
                         note: target.evidence.joined(separator: "；"),
                         // 第四格放「怎么算做到了」。没有它的时候，那张卡片下面写的是
                         // 一句所有目标共用的话，说不出这一场到底怎么算做到（见
                         // `RetrainingTarget.successBehavior`）。
                         action: target.successBehavior)
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
                      primary: entry.value(0, in: item),
                      secondary: entry.value(1, in: item),
                      note: entry.value(2, in: item),
                      action: entry.value(3, in: item))
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
