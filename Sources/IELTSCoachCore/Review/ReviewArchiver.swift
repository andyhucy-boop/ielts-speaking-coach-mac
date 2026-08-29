import Foundation

/// `archive` 的结果：归档后的新 state，加上「静默丢失」诊断。
public struct ArchiveOutcome: Equatable, Sendable {
    public let state: CoachState
    /// 顶层键存在、且非空，但本次一条都没能归进档案的字段名（目前检查
    /// must_correct、vocabulary 与 priority_target，见 ReviewArchiver.archive 内的判定）。
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

        let targetKept = appendTarget(from: report, into: &updated,
                                      sessionID: sessionID, at: timestamp)
        if isPresentAndNonEmpty(report["priority_target"]) && !targetKept {
            // 「下一次只盯这一个」是这个产品的改进闭环的起点。它存不下来却没人吭声的话，
            // 用户刚在复盘页看过那张深色卡片，转身在复训中心看到的是「还没有待复训的目标」，
            // 而他只会以为是自己漏了哪一步。
            skipped.append("priority_target")
        }

        // **这一场练到的每一道题都要结账**，不只是开场那一道。
        //
        // 随机抽题一场会安排一整组（`PracticeSession.drawnQuestionIds`）。只结开场那一道的话，
        // 训练题库页会把另外几道标成已练（读盘时 `CoachState.reconcilePracticedStatus`
        // 会算回来），而学习计划那边仍然显示没做完——同一道题，两页两个说法，
        // 用户没有任何办法知道哪个是真的。
        for id in practicedQuestionIDs(in: state, sessionID: sessionID, questionID: questionID) {
            advancePlan(in: &updated, questionID: id)
            markPracticed(in: &updated, questionID: id)
        }
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
                // **练法只补不换。** 这条错题上次入库时 ChatGPT 没给练法、这次给了，
                // 就把它补上——那一格是这条错题在错题本里唯一「现在能做什么」的出口，
                // 空着等于这条记录只会指出毛病、不会给出路。
                //
                // 已经有练法时**一个字都不动**，而且这一条放在上面那个 if 外面：
                // 同一场重复归档时也要补得上（那种情形 `sourceSessionIds` 已经含这一场，
                // 上面那块整个跳过），否则补录一次的人永远补不到练法。
                let drill = (entry["mini_drill"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if state.issues[index].miniDrill.isEmpty && !drill.isEmpty {
                    state.issues[index].miniDrill = drill
                }
            } else {
                state.issues.append(IssueRecord(
                    id: "issue-\(state.issues.count + 1)-\(sessionID)",
                    learnerSaid: said,
                    correction: entry["correction"]?.stringValue ?? "",
                    whyItMatters: entry["why_it_matters"]?.stringValue ?? "",
                    occurrences: 1,
                    sourceSessionIds: [sessionID],
                    lastSeenAt: timestamp,
                    miniDrill: (entry["mini_drill"]?.stringValue ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)))
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
                // **缺的字段要回填。**
                //
                // ChatGPT 偶尔会给出只有原词、没有「更好的说法」也没有搭配的条目
                //（提示词要求给全，但没有校验拦它）。那条记录在「我的词汇」页上渲染成
                //「word →（空白）」，导出时每次都被跳过，而跳过的提示写着
                //「等下一次复盘补上」——从前这句话是假的：按 basicWord 命中已有记录之后
                // 只加一次出现次数，缺掉的字段一个都不补，这条残缺卡片会一边被永久跳过、
                // 一边把计数越滚越大（2026-08-08 复审第 11 条实测）。
                //
                // 只填**空的**字段，绝不覆盖已有内容：覆盖等于把用户已经在背的那句话
                // 悄悄换掉，而他不会收到任何提示。
                //
                // **`priority` 不在回填之列**：它落盘时就有默认值（"normal"），永远不是空的，
                // 把它当成「缺字段」去覆盖，等于让后一次复盘悄悄改掉这个词在列表里的排序。
                // 而空白的只有 better / collocation 那两栏——它们正是卡片背面的全部内容，
                // 也是导出被跳过的原因。
                fill(&state.vocabulary[index].betterExpression, with: entry["better"])
                fill(&state.vocabulary[index].collocation, with: entry["collocation"])
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

    /// 把 `field` 填上——**只在它现在是空的、而且新值非空时**。
    ///
    /// 抽成一个函数而不是在上面写三遍 `if`：三处各写一遍时，漏掉其中一个字段
    /// 编译器不会吭声，而漏掉的那个字段会永远停在空白上。
    private static func fill(_ field: inout String, with value: JSONValue?) {
        guard field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let incoming = (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        field = incoming
    }

    // MARK: - 重训目标

    /// 返回「这份复盘的唯一目标最终在不在档案里」。
    ///
    /// **重复入库那一支返回 `true`**：目标本来就在，什么都没丢，那时报警等于对着
    /// 一份归档得好好的复盘喊「有东西没归进去」——狼来了喊多了，真丢的那次就没人信了。
    @discardableResult
    private static func appendTarget(from report: JSONValue, into state: inout CoachState,
                                     sessionID: String, at timestamp: String) -> Bool {
        guard let target = RetrainingPolicy.extractTarget(
            from: report, sessionID: sessionID, createdAt: timestamp) else { return false }
        // 同一 session 重复入库时不追加第二份
        guard !state.targets.contains(where: {
            $0.targetKey == target.targetKey && $0.sourceSessionId == sessionID
        }) else { return true }
        state.targets.append(target)
        return true
    }

    // MARK: - 计划与题目状态

    private static func advancePlan(in state: inout CoachState, questionID: String) {
        guard let plan = state.plan else { return }
        state.plan = PlanBuilder.markCompleted(plan: plan, questionID: questionID)
    }

    /// 这一场到底练了哪些题。
    ///
    /// **从训练记录里读，而不是加一个参数。** `archive` 有五个调用点
    /// （App、命令行两处、MCP、待处理复盘收件箱），其中几处手里根本没有 `SessionSetup`，
    /// 加参数的话它们只能传空——于是同一份复盘从不同入口归档，计划进度不一样。
    /// 训练记录在归档之前就已经写好了（`PracticeRunner.upsertSession`），
    /// 它才是「这一场练了什么」唯一的凭据。
    ///
    /// 记录还没写进去（命令行那条路上有可能）时退回开场那一道，与从前的行为一致。
    private static func practicedQuestionIDs(in state: CoachState, sessionID: String,
                                             questionID: String) -> [String] {
        var ids = [questionID].filter { !$0.isEmpty }
        let recorded = state.sessions.first { $0.id == sessionID }?.allQuestionIds ?? []
        for id in recorded where !ids.contains(id) { ids.append(id) }
        return ids
    }

    private static func markPracticed(in state: inout CoachState, questionID: String) {
        guard let index = state.questions.firstIndex(where: { $0.id == questionID }) else { return }
        state.questions[index].status = "practiced"
    }
}
