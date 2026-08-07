import Foundation

public enum IssueRanking {
    /// 按出现次数从多到少取前 limit 条。次数相同的保持原有顺序——
    /// Swift 的 `sorted` 不保证稳定，不用下标兜住的话，同次数的条目每次
    /// 运行顺序都可能不一样，界面上看就是「列表自己在跳」。
    public static func top(_ issues: [IssueRecord], limit: Int) -> [IssueRecord] {
        guard limit > 0 else { return [] }
        return issues.enumerated()
            .sorted {
                $0.element.occurrences == $1.element.occurrences
                    ? $0.offset < $1.offset
                    : $0.element.occurrences > $1.element.occurrences
            }
            .prefix(limit)
            .map(\.element)
    }
}
