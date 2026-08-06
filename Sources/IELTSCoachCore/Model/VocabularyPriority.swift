import Foundation

/// 词汇优先级。`VocabularyRecord.priority` 存的是 ChatGPT 给的原始字符串，
/// 写法不受控（见过 "high" / "medium" / "normal" / 空）。归一到三档再用。
public enum VocabularyPriority: String, CaseIterable, Equatable, Sendable {
    case high, normal, low

    /// 任何没见过的写法都当普通。**不要在这里抛错或新增档次**——
    /// 一个拼错的优先级不该让整页词汇显示不出来。
    public static func normalize(_ raw: String) -> VocabularyPriority {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "h", "1": return .high
        case "low", "l", "3": return .low
        default: return .normal
        }
    }

    /// 中文档次名。用「记不记」的说法而不是「高/中/低」——
    /// 用户要的是「先背哪个」，不是一个抽象等级。
    public var title: String {
        switch self {
        case .high: return "优先记"
        case .normal: return "有空再记"
        case .low: return "先放着"
        }
    }

    public var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    /// Anki 的层级标签写法。
    public var ankiTag: String { "ielts-speaking::\(rawValue)" }
}
