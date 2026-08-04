import Foundation

/// 把一份已解析的复盘并入训练档案。纯函数：吃进旧 state，吐出新 state，不做任何 IO。
public enum ReviewArchiver {
    public static func archive(report: JSONValue, into state: CoachState,
                               sessionID: String, questionID: String, at timestamp: String) -> CoachState {
        var updated = state
        mergeIssues(from: report, into: &updated, sessionID: sessionID, at: timestamp)
        mergeVocabulary(from: report, into: &updated, sessionID: sessionID)
        appendTarget(from: report, into: &updated, sessionID: sessionID, at: timestamp)
        advancePlan(in: &updated, questionID: questionID)
        markPracticed(in: &updated, questionID: questionID)
        return updated
    }

    // MARK: - 错题：按 learner_said 归并并累加出现次数

    private static func mergeIssues(from report: JSONValue, into state: inout CoachState,
                                    sessionID: String, at timestamp: String) {
        for entry in report["must_correct"]?.arrayValue ?? [] {
            let said = (entry["learner_said"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty else { continue }

            if let index = state.issues.firstIndex(where: {
                $0.learnerSaid.trimmingCharacters(in: .whitespacesAndNewlines) == said
            }) {
                state.issues[index].occurrences += 1
                if !state.issues[index].sourceSessionIds.contains(sessionID) {
                    state.issues[index].sourceSessionIds.append(sessionID)
                }
                state.issues[index].lastSeenAt = timestamp
            } else {
                state.issues.append(IssueRecord(
                    id: "issue-\(state.issues.count + 1)-\(sessionID)",
                    learnerSaid: said,
                    correction: entry["correction"]?.stringValue ?? "",
                    whyItMatters: entry["why_it_matters"]?.stringValue ?? "",
                    occurrences: 1,
                    sourceSessionIds: [sessionID],
                    lastSeenAt: timestamp))
            }
        }
    }

    // MARK: - 词汇：按 basic 去重

    private static func mergeVocabulary(from report: JSONValue, into state: inout CoachState,
                                        sessionID: String) {
        for entry in report["vocabulary"]?.arrayValue ?? [] {
            let basic = (entry["basic"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !basic.isEmpty else { continue }

            if let index = state.vocabulary.firstIndex(where: { $0.basicWord == basic }) {
                if !state.vocabulary[index].sourceSessionIds.contains(sessionID) {
                    state.vocabulary[index].sourceSessionIds.append(sessionID)
                }
            } else {
                state.vocabulary.append(VocabularyRecord(
                    id: "vocab-\(state.vocabulary.count + 1)-\(sessionID)",
                    basicWord: basic,
                    betterExpression: entry["better"]?.stringValue ?? "",
                    collocation: entry["collocation"]?.stringValue ?? "",
                    priority: entry["priority"]?.stringValue ?? "normal",
                    sourceSessionIds: [sessionID]))
            }
        }
    }

    // MARK: - 重训目标

    private static func appendTarget(from report: JSONValue, into state: inout CoachState,
                                     sessionID: String, at timestamp: String) {
        guard let target = RetrainingPolicy.extractTarget(
            from: report, sessionID: sessionID, createdAt: timestamp) else { return }
        // 同一 session 重复入库时不追加第二份
        guard !state.targets.contains(where: {
            $0.id == target.id && $0.sourceSessionId == sessionID
        }) else { return }
        state.targets.append(target)
    }

    // MARK: - 计划与题目状态

    private static func advancePlan(in state: inout CoachState, questionID: String) {
        guard let plan = state.plan else { return }
        state.plan = PlanBuilder.markCompleted(plan: plan, questionID: questionID)
    }

    private static func markPracticed(in state: inout CoachState, questionID: String) {
        guard let index = state.questions.firstIndex(where: { $0.id == questionID }) else { return }
        state.questions[index].status = "practiced"
    }
}
