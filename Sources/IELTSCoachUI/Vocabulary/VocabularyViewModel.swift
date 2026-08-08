import Foundation
import IELTSCoachCore

/// 我的词汇页顶上的四档筛选。
///
/// 三个档次的名字**不在这里另写一份**，直接取 `VocabularyPriority.title`——
/// 手抄一份的话，档次名改了之后筛选控件上还是旧说法，而两处都「看着正常」。
public enum VocabularyFilter: String, CaseIterable, Identifiable, Sendable {
    case all, high, normal, low

    public var id: String { rawValue }

    public var priority: VocabularyPriority? {
        switch self {
        case .all: return nil
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        }
    }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .high, .normal, .low: return priority?.title ?? "全部"
        }
    }
}

/// 列表里的一行。**界面要显示的每一样东西都在这儿算好**，视图不再自己拼——
/// 视图里拼出来的东西没有任何测试管得住。
///
/// **这一行背后那条原始记录直接挂在这儿（`record`），导出取的就是它。**
/// 从前是先建一张「id → 记录」的表、导出时再拿行的 `id` 回头查：
/// `state.json` 被外部工具改坏、或上游写入过重复 id 时，那张表每个 id 只留得下最后一条，
/// 于是屏幕上是「aaa」「bbb」两行、导出的却是两份「bbb」——少一个词、多一张重复卡，
/// `skipped` 里还一个字都没有。用户要到 Anki 里才会发现。
/// 现在一行只能由一条记录造出来，「屏幕上的」和「导出的」在类型上就不可能是两回事。
public struct VocabularyRow: Equatable, Identifiable, Sendable {
    /// 这一行背后那条原始记录。`VocabularyExporter` 吃的就是它。
    public let record: VocabularyRecord
    /// 归一后的优先级。`record.priority` 是 ChatGPT 给的原始字符串，写法不受控。
    public let priority: VocabularyPriority
    /// 这个词在几场不同的练习里被推荐过。
    public let sessionCount: Int

    /// 下面四样一律**转发**给 `record`，不另存一份——
    /// 存两份就有走岔的余地，而走岔的表现正是「屏幕上和导出的不是一回事」。
    public var id: String { record.id }
    public var basicWord: String { record.basicWord }
    public var betterExpression: String { record.betterExpression }
    public var collocation: String { record.collocation }

    public init(record: VocabularyRecord) {
        self.record = record
        self.priority = VocabularyPriority.normalize(record.priority)
        self.sessionCount = Set(record.sourceSessionIds).count
    }
}

/// 我的词汇页的视图模型：把 `state.vocabulary` 排好序、归一优先级，
/// 变成界面直接能画的一串行；导出走同一份顺序。
public struct VocabularyViewModel: Sendable {
    public let rows: [VocabularyRow]

    public init(state: CoachState) {
        // ⚠️ 这里**不建任何「id → 记录」的索引**。重复 id 时索引每个 id 只留得下一条，
        // 而导出一旦拿行的 id 回头查它，导出的内容就和屏幕上显示的不是一回事了
        // （见 `VocabularyRow` 的说明）。记录直接挂在行上，导出从行上取。
        rows = state.vocabulary
            .map(VocabularyRow.init(record:))
            .sorted { left, right in
                if left.priority.sortRank != right.priority.sortRank {
                    return left.priority.sortRank < right.priority.sortRank
                }
                // 反复被推荐的词更该先记
                if left.sessionCount != right.sessionCount {
                    return left.sessionCount > right.sessionCount
                }
                if left.basicWord != right.basicWord { return left.basicWord < right.basicWord }
                return left.id < right.id      // 让排序完全确定
            }
    }

    public func rows(filter: VocabularyFilter) -> [VocabularyRow] {
        guard let priority = filter.priority else { return rows }
        return rows.filter { $0.priority == priority }
    }

    public var counts: (total: Int, high: Int) {
        (rows.count, rows.filter { $0.priority == .high }.count)
    }

    /// 导出**当前筛选**下的词汇，顺序与界面显示一致。
    ///
    /// 用户筛到「优先记」再点导出却拿到全部词汇，是典型的界面骗人——
    /// 而他要到 Anki 里才会发现。
    public func exportDocument(format: VocabularyExportFormat,
                               filter: VocabularyFilter,
                               exportedAt: Date = Date(),
                               calendar: Calendar = .current) -> ExportDocument {
        // **直接从行上取记录，不许拿 `id` 回头查表**——查表在重复 id 时会把
        // 屏幕上的两行换成同一条记录的两份，而且一声不吭。
        let selected = rows(filter: filter).map(\.record)
        let document = VocabularyExporter.export(selected, format: format,
                                                 exportedAt: exportedAt, calendar: calendar)
        guard selected.isEmpty, !rows.isEmpty else { return document }

        // 词汇本不空、只是当前筛选下一条都没有。沿用 Exporter 那句
        // 「词汇本还是空的」会把用户支去找一个不存在的问题。
        return ExportDocument(
            text: document.text,
            suggestedFileName: document.suggestedFileName,
            exportedCount: 0,
            skipped: ["当前筛选（\(filter.title)）下一条词都没有，导出的文件里没有任何卡片。"
                      + "下一步：把筛选换成「全部」再导出一次。"])
    }
}
