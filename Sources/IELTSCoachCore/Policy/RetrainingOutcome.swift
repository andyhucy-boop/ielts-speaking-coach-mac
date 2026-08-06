import Foundation

/// 一场复训之后，这个目标有没有被新复盘再次点名。
///
/// **这不是「改没改掉」的结论。** ChatGPT 完全可能换一个 id 说同一件事，也可能这一次
/// 碰巧没抓到。所以这里只报告一个可观测的事实，措辞上不许升级成结论（见计划的「决定 4」）。
public enum RetrainingOutcome: String, Equatable, Sendable, CaseIterable {
    /// 还没有可判断的复盘（没练完、复盘没取回、或取回的东西不成形）。
    case noReport
    /// 新复盘又把同一个目标点了出来。
    case namedAgain
    /// 新复盘没有再点它。
    case notNamedAgain

    public static func judge(report: JSONValue?, targetKey: String) -> RetrainingOutcome {
        // 不成形的东西一律算「不知道」。把没认出来的输入当成好消息，
        // 会让用户拿着一个假结论以为自己练成了。
        guard let report, report.objectValue != nil else { return .noReport }

        guard let target = report["priority_target"], target.objectValue != nil else {
            return .notNamedAgain
        }
        let id = (target["id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return .notNamedAgain }

        return id == targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
            ? .namedAgain : .notNamedAgain
    }
}
