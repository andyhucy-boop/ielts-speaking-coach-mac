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
public struct VocabularyRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let basicWord: String
    public let betterExpression: String
    public let collocation: String
    public let priority: VocabularyPriority
    /// 这个词在几场不同的练习里被推荐过。
    public let sessionCount: Int

    public init(id: String, basicWord: String, betterExpression: String, collocation: String,
                priority: VocabularyPriority, sessionCount: Int) {
        self.id = id; self.basicWord = basicWord; self.betterExpression = betterExpression
        self.collocation = collocation; self.priority = priority; self.sessionCount = sessionCount
    }
}

/// 我的词汇页的视图模型：把 `state.vocabulary` 排好序、归一优先级，
/// 变成界面直接能画的一串行；导出走同一份顺序。
public struct VocabularyViewModel: Sendable {
    public let rows: [VocabularyRow]
    /// 导出要用原始记录（`VocabularyExporter` 吃的是 `VocabularyRecord`）。
    private let recordsByID: [String: VocabularyRecord]

    public init(state: CoachState) {
        // ⚠️ 不用 Dictionary(uniqueKeysWithValues:)：重复 id 会 fatalError 闪退整个 App。
        // 本项目在 QuestionBankImporter.merge 与 IssueArchiveViewModel 里已经为同一个坑
        // 写过两次注释。
        var index: [String: VocabularyRecord] = [:]
        for record in state.vocabulary { index[record.id] = record }
        recordsByID = index

        rows = state.vocabulary
            .map { record in
                VocabularyRow(id: record.id,
                              basicWord: record.basicWord,
                              betterExpression: record.betterExpression,
                              collocation: record.collocation,
                              priority: VocabularyPriority.normalize(record.priority),
                              sessionCount: Set(record.sourceSessionIds).count)
            }
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
        let selected = rows(filter: filter).compactMap { recordsByID[$0.id] }
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
