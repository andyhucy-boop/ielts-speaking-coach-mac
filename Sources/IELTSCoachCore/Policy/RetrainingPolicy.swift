import Foundation

public enum RetrainingPolicy {
    /// 从复盘的 priority_target 中取出唯一推荐目标。
    /// 注意：这只是「推荐」，不得据此强制学员下次必须练它（见 report-schema.md 第 9 节）。
    ///
    /// **这是「这份复盘到底有没有给出下一次的唯一目标」全项目唯一的判据。**
    /// 复盘报告页那块深色卡片（`ReviewReportViewModel.priorityTarget`）也走这一份，
    /// 不许在别处另写一套：曾经界面只要求 `label` 非空、这里却要求 `id` 非空，
    /// 于是 ChatGPT 漏给 `id` 的那一次，用户在复盘页看见「下一次的唯一目标」，
    /// 转身打开复训中心却被告知「还没有待复训的目标。下一步：先完整练一场」——
    /// 一句在他刚练完一整场的前提下字面上为假的话。
    ///
    /// `id` 缺失或只有空白时**用会话编号兜底**，不丢。ChatGPT 生成的 `id` 本来就只是个短标识，
    /// 而 `targetKey` 只需要在「同一场练习内」稳定（`ReviewArchiver.appendTarget` 按
    /// targetKey + sourceSessionId 去重），会话编号完全够用，且重复归档同一场仍然幂等。
    public static func extractTarget(from report: JSONValue, sessionID: String,
                                     createdAt: String) -> RetrainingTarget? {
        guard let target = report["priority_target"], target.objectValue != nil else { return nil }
        let id = (target["id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (target["label"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 两样都没有才算「这份复盘没给目标」——那时连要盯什么都说不出来，兜底也造不出内容。
        guard !id.isEmpty || !label.isEmpty else { return nil }

        return RetrainingTarget(
            targetKey: id.isEmpty ? fallbackTargetKey(sessionID: sessionID) : id,
            label: target["label"]?.stringValue ?? "",
            status: (target["status"]?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? "new",
            evidence: (target["evidence"]?.arrayValue ?? []).compactMap(\.stringValue),
            sourceSessionId: sessionID,
            createdAt: createdAt,
            // 「怎么算做到了」。**它不参与上面那道 guard**：没给达标线不等于没给目标，
            // 因为一条这个字段而把整个目标丢掉，等于把改进闭环的起点扔了。
            successBehavior: (target["success_behavior"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `id` 缺失时兜底生成的 targetKey。**必须只由 sessionID 决定**——
    /// 掺进时间戳或随机数的话，同一场复盘归档两次就会变成两条目标，
    /// `ReviewArchiver` 那条「同一场重复入库不新增」的幂等当场破掉。
    public static func fallbackTargetKey(sessionID: String) -> String {
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.isEmpty ? "target" : "target-\(session)"
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
