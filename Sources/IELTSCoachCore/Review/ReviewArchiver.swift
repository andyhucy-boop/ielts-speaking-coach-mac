import Foundation

/// `archive` 的结果：归档后的新 state，加上「静默丢失」诊断。
public struct ArchiveOutcome: Equatable, Sendable {
    public let state: CoachState
    /// 顶层键存在、且非空，但本次一条都没能归进档案的字段名（目前只检查
    /// must_correct 与 vocabulary，见 ReviewArchiver.archive 内的判定）。
    ///
    /// **归档 0 条不等于没错题**——更可能是 ChatGPT 用的字段名（或整个结构的形状，
    /// 比如把数组写成了对象）与我们读的对不上，而这种失败不报错、不崩溃，
    /// 只是悄悄什么都不做。静默的 0 是本项目已知最危险的失败形态：用户练了一整场、
    /// 复盘也写得完整，档案却纹丝不动，且没有任何信号提示哪里错了。
    public let skipped: [String]

    public init(state: CoachState, skipped: [String]) { self.state = state; self.skipped = skipped }
}

/// 把一份已解析的复盘并入训练档案。纯函数：吃进旧 state，吐出新 state，不做任何 IO。
public enum ReviewArchiver {
    public static func archive(report: JSONValue, into state: CoachState,
                               sessionID: String, questionID: String, at timestamp: String) -> ArchiveOutcome {
        var updated = state
        var skipped: [String] = []

        let issuesMerged = mergeIssues(from: report, into: &updated, sessionID: sessionID, at: timestamp)
        if isPresentAndNonEmpty(report["must_correct"]) && issuesMerged == 0 {
            skipped.append("must_correct")
        }

        let vocabularyMerged = mergeVocabulary(from: report, into: &updated, sessionID: sessionID)
        if isPresentAndNonEmpty(report["vocabulary"]) && vocabularyMerged == 0 {
            skipped.append("vocabulary")
        }

        appendTarget(from: report, into: &updated, sessionID: sessionID, at: timestamp)
        advancePlan(in: &updated, questionID: questionID)
        markPracticed(in: &updated, questionID: questionID)
        return ArchiveOutcome(state: updated, skipped: skipped)
    }

    /// 「该键在复盘里存在且非空」的判定。刻意不要求特定形状（数组 vs 对象）——
    /// 实测故障里 vocabulary 曾被 ChatGPT 输出成一个非空对象而不是数组，
    /// 若这里只认「非空数组」，那次故障反而不会被判定为 skipped（因为 arrayValue
    /// 直接是 nil，看起来像「键不存在」），恰好漏掉了最该报警的那种情况。
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

    // MARK: - 错题：按 learner_said 归并并累加出现次数

    /// 返回本次实际归并（新增或命中已有记录）的条数。
    ///
    /// **幂等：去重键是 `sessionID`。** 同一场练习的复盘归档多少次，
    /// `occurrences` / `sourceSessionIds` / `lastSeenAt` 都保持第一次的结果。
    /// 这条路走得到：`markImported` 改名失败时归档已经做完、文件却还留在待处理列表里；
    /// 用户手工去掉 `.imported` 后缀重来；界面那条路和 `coach reimport` 各导一次。
    /// 靠「打标记」防重是不够的——标记那一步本身就会失败。
    ///
    /// 于是 `occurrences` 的含义被钉死为**「在几场练习里犯过这个毛病」**，
    /// 恒等于 `sourceSessionIds.count`（同一份复盘里两条一模一样的 `learner_said`
    /// 只算一场）。要问的问题本来就是「这个毛病在变多还是变少」，
    /// 而能可靠回答它的只有场次；「一共说错了几次」没有可去重的键，
    /// 重导一次就永久虚高，比不显示更糟。
    /// 老档案里已经虚高的数字由 `IssueRecord.init(from:)` 在读盘时按这个恒等式修回来。
    @discardableResult
    private static func mergeIssues(from report: JSONValue, into state: inout CoachState,
                                    sessionID: String, at timestamp: String) -> Int {
        var merged = 0
        for entry in report["must_correct"]?.arrayValue ?? [] {
            let said = (entry["learner_said"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty else { continue }
            merged += 1

            if let index = state.issues.firstIndex(where: {
                $0.learnerSaid.trimmingCharacters(in: .whitespacesAndNewlines) == said
            }) {
                // 这一场已经记过这条错题了 → 一个字段都不许再动。
                // `lastSeenAt` 也在里面：s1 那一场发生在什么时候是固定的，
                // 补录一次不该把它说成刚刚才犯过（更糟的是把一个更晚的 s2 覆盖回去）。
                if !state.issues[index].sourceSessionIds.contains(sessionID) {
                    state.issues[index].occurrences += 1
                    state.issues[index].sourceSessionIds.append(sessionID)
                    state.issues[index].lastSeenAt = timestamp
                }
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
        return merged
    }

    // MARK: - 词汇：按 basic 去重

    /// 返回本次实际归并（新增或命中已有记录）的条数。
    @discardableResult
    private static func mergeVocabulary(from report: JSONValue, into state: inout CoachState,
                                        sessionID: String) -> Int {
        var merged = 0
        for entry in report["vocabulary"]?.arrayValue ?? [] {
            let basic = (entry["basic"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !basic.isEmpty else { continue }
            merged += 1

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
        return merged
    }

    // MARK: - 重训目标

    private static func appendTarget(from report: JSONValue, into state: inout CoachState,
                                     sessionID: String, at timestamp: String) {
        guard let target = RetrainingPolicy.extractTarget(
            from: report, sessionID: sessionID, createdAt: timestamp) else { return }
        // 同一 session 重复入库时不追加第二份
        guard !state.targets.contains(where: {
            $0.targetKey == target.targetKey && $0.sourceSessionId == sessionID
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
