import Foundation

/// 把**已经在用户机器上**的旧结构题库原地改成「一个话题一道题」，并把历史记录一起搬过去。
///
/// ## 为什么需要它，而不是「让用户再导入一次题库文件」
///
/// 重建模发生在导入那一刻（`QuestionBankImporter.merge` 会认碎片），所以理论上
/// 用户把同一份季度题库 PDF 再选一次就完成了迁移——题库页上那句
/// `QuestionBankViewModel.legacyShapeNotice` 说的正是这件事。
///
/// 但那条路有个前提：**那份文件还在他手上。** 题库是三个月前下载的一份 PDF，
/// 数据目录里只留下了题目本身和一行来源标题。文件删了、换了台电脑、
/// 或者当初是用 CSV 拼的，这条路就走不通，而他的题库会一直停在旧结构上：
/// Part 1 的一个话题被拆成六道「题」，Part 3 的一张 cue card 被拆成十几道，
/// 学习计划把同一张卡排成十几天、每天练一句。
///
/// 所以再给一条不依赖原文件的路：**旧题自己就带着 (part, topic, prompt)**，
/// 按话题重新分组，就能算出和「重新导入那份文件」**完全一样的题号**——
/// 题号只由 `(part, topic)` 决定（`TopicQuestions` 的文档解释了为什么），
/// 所以两条路会收敛到同一个结果，用哪条都不会打架。
///
/// ## 它不做什么
///
/// - **不发明新题**：话题题的参考问句全部来自旧题自己的题干，一句不多、一句不少。
/// - **不吃用户自己加的孤题**：判据与导入那条路完全一致——同一个 `(part, topic)`
///   下要有**两道以上**才算旧结构（`TopicQuestions.legacyShapedCount` 用的也是这一条）。
///   用户用 CSV 加的、一个话题只写了一道的题（真实数据里就有一道 `p1-home-001`，
///   他唯一一场真实练习挂在上面）原样留着，题号一个字符都不变。
/// - **不动 Part 2**：一张 cue card 本来就是一道题。
public enum QuestionBankRemodel {

    // MARK: - 一次迁移的交代

    /// 迁移的结果。**每一个字段都是要说给用户听的**（铁律 7：不许静默失败）。
    public struct Outcome: Equatable, Sendable {
        /// 迁移前后的题库总数。
        public let questionCountBefore: Int
        public let questionCountAfter: Int
        /// 迁移前后还剩多少道「一问一题」的旧结构题目（判据见 `legacyShapedCount`）。
        public let legacyShapedBefore: Int
        public let legacyShapedAfter: Int
        /// 这次造出来的话题题有几道。
        public let topicQuestionCount: Int
        /// 有多少道旧题被并进了它所属的话题题里。
        public let absorbedCount: Int
        /// 因此改写了多少处旧题号引用（练习记录、复训链接、学习计划、正在进行的那一场）。
        public let remappedReferenceCount: Int
        /// 迁移**之前**就已经指不到题的引用。不是这次迁移造成的，但也不许瞒着。
        public let orphansBefore: [String]
        /// 迁移**之后**仍然指不到题的引用。
        public let orphansAfter: [String]
        /// 迁移后彻底消失的题干。**必须是空的。**
        ///
        /// 判据是「这句话在新题库里既不是某道题的题干、也不是任何一道题的参考问句」。
        /// 非空就说明这次迁移真的吃掉了内容——那正是铁律 7 要拦的那种失败。
        public let lostPrompts: [String]

        /// 这次迁移到底动没动东西。
        public var changedAnything: Bool {
            absorbedCount > 0 || remappedReferenceCount > 0
                || questionCountBefore != questionCountAfter
        }

        /// 这次迁移**自己制造**的孤儿引用。非空 = 出了大问题，调用方必须拒绝写盘。
        public var newOrphans: [String] {
            let known = Set(orphansBefore)
            return orphansAfter.filter { !known.contains($0) }
        }

        /// 可以安全落盘吗。两条：没吃掉任何问句，也没制造新的孤儿。
        public var isSafeToApply: Bool { lostPrompts.isEmpty && newOrphans.isEmpty }
    }

    // MARK: - 从旧题库算出该有的话题题

    /// 按 `(part, topic)` 把旧题重新分组，算出这些组各自应该长成的那一道话题题。
    ///
    /// 只处理 Part 1 与 Part 3，且**同一组里要有两道以上**——判据与
    /// `TopicQuestions.legacyShapedCount`、与导入那条路上的 `supersedes` 完全一致。
    /// 三处判据必须是同一条，否则「题库页说你还是旧结构」「迁移说没什么可迁的」
    /// 会同时出现在屏幕上。
    public static func topicQuestions(from questions: [Question]) -> [Question] {
        var order: [String] = []
        var buckets: [String: [Question]] = [:]
        for question in questions
        where (question.part == 1 || question.part == 3) && !question.topic.isEmpty {
            let key = "\(question.part)|\(question.topic)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(question)
        }

        var result: [Question] = []
        for key in order {
            guard let bucket = buckets[key], bucket.count >= 2, let first = bucket.first else {
                continue
            }
            // 已经是话题题的，贡献它的参考问句；还是碎片的，贡献它自己的题干。
            // **这一条是「重跑一次不会把话题名本身塞成参考问句」的关键**：
            // 拿话题题的 prompt（它等于话题名）当问句的话，第二次迁移会在
            // followups 里凭空多出一行「Borrowing/lending」。
            var prompts: [String] = []
            var seen: Set<String> = []
            for question in bucket {
                let contributed = TopicQuestions.isTopicQuestion(question)
                    ? question.followups : [question.prompt]
                for prompt in contributed
                where !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && seen.insert(prompt).inserted {
                    prompts.append(prompt)
                }
            }
            guard !prompts.isEmpty else { continue }

            let source = bucket.first { !$0.source.isEmpty }?.source ?? ""
            let sourceUrl = bucket.first { !$0.sourceUrl.isEmpty }?.sourceUrl ?? ""
            var made = first.part == 1
                ? TopicQuestions.part1(topic: first.topic, prompts: prompts,
                                       source: source, sourceUrl: sourceUrl)
                : TopicQuestions.part3(cueCard: first.topic, prompts: prompts,
                                       source: source, sourceUrl: sourceUrl)
            made.importLevel = first.importLevel
            result.append(made)
        }
        return result
    }

    // MARK: - 真正迁移

    /// 原地迁移。**合并与搬家都不在这里另写一遍**——用的正是导入那条路上的
    /// `QuestionBankImporter.merge` 与 `QuestionBankMigration.remapQuestionIDs`。
    ///
    /// 各写一份的话，「导入一次」和「跑一次迁移」会给出两种题号，
    /// 用户先跑迁移再导入题库时，历史记录要搬第二次家。
    ///
    /// **重跑安全**：第二次跑的时候每个话题下都只剩一道题，`topicQuestions` 返回空，
    /// 什么都不会发生（`changedAnything` 为 false）。
    @discardableResult
    public static func apply(to state: inout CoachState) -> Outcome {
        let before = state.questions
        let orphansBefore = orphanedReferences(in: state)
        let incoming = topicQuestions(from: before)

        guard !incoming.isEmpty else {
            return Outcome(questionCountBefore: before.count, questionCountAfter: before.count,
                           legacyShapedBefore: TopicQuestions.legacyShapedCount(in: before),
                           legacyShapedAfter: TopicQuestions.legacyShapedCount(in: before),
                           topicQuestionCount: 0, absorbedCount: 0, remappedReferenceCount: 0,
                           orphansBefore: orphansBefore, orphansAfter: orphansBefore,
                           lostPrompts: [])
        }

        let merged = QuestionBankImporter.merge(existing: before, incoming: incoming)
        state.questions = merged.questions
        let remapped = QuestionBankMigration.remapQuestionIDs(in: &state,
                                                             replacements: merged.replacements)

        let lost = lostPrompts(before: before, after: state.questions)

        return Outcome(questionCountBefore: before.count,
                       questionCountAfter: state.questions.count,
                       legacyShapedBefore: TopicQuestions.legacyShapedCount(in: before),
                       legacyShapedAfter: TopicQuestions.legacyShapedCount(in: state.questions),
                       topicQuestionCount: incoming.count,
                       absorbedCount: merged.replacements.count,
                       remappedReferenceCount: remapped,
                       orphansBefore: orphansBefore,
                       orphansAfter: orphanedReferences(in: state),
                       lostPrompts: lost)
    }

    // MARK: - 不许静默丢东西

    /// 旧题库里哪些题干在新题库里彻底找不到了（去重、保序）。**正常情况下必须是空的。**
    ///
    /// 判据：一句话在新题库里既不是任何一道题的**题干**、也不是任何一道题的**参考问句**，
    /// 那它就是被这次迁移吃掉了。
    ///
    /// ## 为什么它是独立一个函数，而不是写在 `apply` 里
    ///
    /// 今天的合并逻辑（`QuestionBankImporter.merge`）**只有在确认某道旧题的题干
    /// 已经在新题的参考问句里之后**才会把它从题库里去掉（`TopicQuestions.supersedes`）,
    /// 所以这个检查在今天永远返回空——「断言它是空的」因此测不出任何东西。
    ///
    /// 它防的是**将来**：谁把合并判据放宽（比如改成「同话题就吸收」），
    /// 用户自己加的题会被悄悄吃掉，而题数、界面、报告全都看不出异样。
    /// 独立出来之后，这个探测器本身可以被喂一份「真的丢了东西」的前后对照来验，
    /// 于是它有没有约束力这件事本身就是被测出来的
    ///（`testTheLostPromptDetectorReallyDetectsALoss`），而不是靠一句永远为真的断言。
    public static func lostPrompts(before: [Question], after: [Question]) -> [String] {
        var surviving: Set<String> = []
        for question in after {
            surviving.insert(question.prompt)
            for followup in question.followups { surviving.insert(followup) }
        }
        var lost: [String] = []
        var reported: Set<String> = []
        for question in before
        where !surviving.contains(question.prompt) && reported.insert(question.prompt).inserted {
            lost.append(question.prompt)
        }
        return lost
    }

    // MARK: - 引用体检

    /// 这份数据里所有指向题目的地方（去重、保序）。
    ///
    /// 四处与 `QuestionBankMigration.remapQuestionIDs` 一一对应，一处都不能漏——
    /// 少查一处，那一处的孤儿就永远不会被报出来。
    public static func referencedQuestionIDs(in state: CoachState) -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        func add(_ id: String) {
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        for session in state.sessions {
            add(session.questionId)
            if let link = session.retraining { add(link.originalQuestionId) }
        }
        if let current = state.currentSession {
            add(current.questionId)
            if let link = current.retraining { add(link.originalQuestionId) }
        }
        for day in state.plan?.days ?? [] {
            for id in day.questionIds { add(id) }
            for id in day.completedQuestionIds { add(id) }
        }
        return ids
    }

    /// 上面那些引用里，题库中已经找不到的那些。
    public static func orphanedReferences(in state: CoachState) -> [String] {
        let live = Set(state.questions.map(\.id))
        return referencedQuestionIDs(in: state).filter { !live.contains($0) }
    }

    // MARK: - 说给用户听

    /// 迁移之后那段交代。铁律 6：同时说清「发生了什么」和「下一步做什么」，
    /// 且提到的页面在 App 里真实存在（「训练题库」「学习计划」都是侧边栏上的页）。
    public static func report(_ outcome: Outcome) -> String {
        guard outcome.changedAnything else {
            return "题库已经是「一个话题一道题」的新结构了，这次迁移一个字都没有改"
                + "（共 \(outcome.questionCountAfter) 道题）。"
                + "下一步：直接到「今日训练」页开练；这条命令可以随时重跑，重跑也不会改坏任何东西。"
        }
        var lines: [String] = []
        lines.append("题库从 \(outcome.questionCountBefore) 道变成 \(outcome.questionCountAfter) 道："
            + "\(outcome.absorbedCount) 道旧结构的「一问一题」并进了它们所属的话题，"
            + "凑成 \(outcome.topicQuestionCount) 道话题题。"
            + "原来的问句一句没丢，成了那道题下面的参考问句"
            + "（练习时考官从中挑几个问，不会全问一遍）。")
        if outcome.remappedReferenceCount > 0 {
            lines.append("你练过的记录已经跟着指到新的题上：一共改写了 "
                + "\(outcome.remappedReferenceCount) 处题号（练习记录、复训链接、学习计划都算在内）。")
        } else {
            lines.append("没有任何练习记录、复训链接或学习计划指向被合并的那些题，所以题号一处也不用改写。")
        }
        if !outcome.orphansAfter.isEmpty {
            lines.append("注意：还有 \(outcome.orphansAfter.count) 处引用在题库里找不到对应的题"
                + "（\(outcome.orphansAfter.prefix(5).joined(separator: "、"))"
                + "\(outcome.orphansAfter.count > 5 ? " 等" : "")）。"
                + "这些在迁移之前就已经是这样了，不是这次改出来的。"
                + "下一步：到「训练记录」页看看这几场，它们的复盘报告仍在，只是对不回题库里的题。")
        }
        lines.append("下一步：到「训练题库」页按 Part 筛一遍，看看新的分组；"
            + "题数变了，学习计划可以到「学习计划」页重新生成一份，练过的进度不会丢。")
        return lines.joined(separator: "\n")
    }
}
