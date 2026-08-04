import Foundation

public enum RetrainingPolicy {
    /// 从复盘的 priority_target 中取出唯一推荐目标。
    /// 注意：这只是「推荐」，不得据此强制学员下次必须练它（见 report-schema.md 第 9 节）。
    public static func extractTarget(from report: JSONValue, sessionID: String,
                                     createdAt: String) -> RetrainingTarget? {
        guard let target = report["priority_target"], target.objectValue != nil else { return nil }
        let id = (target["id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        return RetrainingTarget(
            id: id,
            label: target["label"]?.stringValue ?? "",
            status: (target["status"]?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? "new",
            evidence: (target["evidence"]?.arrayValue ?? []).compactMap(\.stringValue),
            sourceSessionId: sessionID,
            createdAt: createdAt)
    }

    /// 排序：证据命中高频错题的目标排前面。已退休的目标不参与。
    public static func rank(targets: [RetrainingTarget], issues: [IssueRecord]) -> [RetrainingTarget] {
        func weight(_ target: RetrainingTarget) -> Int {
            target.evidence.reduce(0) { total, quote in
                let normalized = quote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return total }
                return total + issues
                    .filter { $0.learnerSaid.trimmingCharacters(in: .whitespacesAndNewlines) == normalized }
                    .reduce(0) { $0 + $1.occurrences }
            }
        }
        return targets
            .filter { $0.status != "retired" }
            .enumerated()
            .sorted {
                let left = weight($0.element), right = weight($1.element)
                return left == right ? $0.offset < $1.offset : left > right   // 权重相同保持原顺序
            }
            .map(\.element)
    }
}
