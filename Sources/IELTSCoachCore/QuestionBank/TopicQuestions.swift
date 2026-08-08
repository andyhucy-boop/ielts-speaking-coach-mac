import Foundation

/// 题库的建模规则：**一个话题就是一道题。**
///
/// ## 为什么不是「一问一题」
///
/// 真实考法（2026-08-08 与考生本人对过，并核对 British Council / Keith Speaking Academy）：
///
/// - **Part 1**：4–5 分钟，考官挑 2–3 个话题，每个话题问 3–4 个，共约 9–12 问。
///   题库里「8-Borrowing/lending」下面那六个问句**不是六道题**，是给考官挑的参考问句。
///   考生答第一问时顺带聊到了第二问的内容，考官就不问第二问了。
/// - **Part 2**：一张 cue card 一道题。这一条本来就是对的。
/// - **Part 3**：由 Part 2 的话题延伸，4–8 问，其中一部分是考官**临场根据上一个回答编的**。
///   所以那一组追问同样是参考，不是题目清单。
///
/// 按「一问一题」建模的后果不只是数字难看：用户练一道 Part 3「追问」时，
/// 屏幕上和考官提示词里都只有那一句孤零零的问句，没有它所属的 cue card 上下文；
/// 学习计划把同一张卡的九个追问排成九天，每天练一句；
/// 「已练过 3/1265」这个进度也毫无意义。
///
/// ## 这个规则长什么样
///
/// 一道话题题的三个字段是**互相约束**的：
/// `prompt == topic`，`followups` 是这个话题下考官可以挑的全部参考问句。
/// `prompt == topic` 不是偷懒——它是「这道题就是这个话题本身」的判据，
/// `isTopicQuestion` 与 `supersedes` 都靠它认人，`id` 也因此只由话题名决定，
/// 于是**同一个话题不管从 PDF 抽、从旧题库合并、还是换季重导，都是同一个 id**。
public enum TopicQuestions {

    /// Part 1：一个话题一道题。`prompts` 是这个话题下的全部参考问句。
    public static func part1(topic: String, prompts: [String],
                             source: String = "", sourceUrl: String = "") -> Question {
        make(part: 1, topic: topic, prompts: prompts, source: source, sourceUrl: sourceUrl)
    }

    /// Part 3：一张 cue card 一道题，挂在它所属 cue card 的题干下。
    ///
    /// **`topic` 用 cue card 的题干而不是「人物 / 地点」那类类别标签**：
    /// Part 3 的问题是从这张卡延伸出来的，脱开这张卡就没法答；
    /// 而类别标签四个值，四张卡的追问会挤成一组，看不出谁跟着谁。
    public static func part3(cueCard: String, prompts: [String],
                             source: String = "", sourceUrl: String = "") -> Question {
        make(part: 3, topic: cueCard, prompts: prompts, source: source, sourceUrl: sourceUrl)
    }

    private static func make(part: Int, topic: String, prompts: [String],
                             source: String, sourceUrl: String) -> Question {
        Question(id: QuestionBankImporter.questionID(part: part, topic: topic, prompt: topic),
                 part: part, topic: topic, prompt: topic,
                 followups: prompts, source: source, sourceUrl: sourceUrl)
    }

    /// 这道题是不是一道话题题（Part 1 的话题 / Part 3 的一组追问）。
    ///
    /// Part 2 永远返回 false：一张 cue card 本来就是一道题，它的 `prompt` 是题干、
    /// `topic` 是类别标签，两者本就不同，不该被当成话题题去吸收别的题。
    public static func isTopicQuestion(_ question: Question) -> Bool {
        (question.part == 1 || question.part == 3)
            && !question.topic.isEmpty
            && question.prompt == question.topic
    }

    /// `candidate` 是不是 `old` 这个碎片所属的那道话题题。
    ///
    /// **判据要窄。** 只有「同 part、同话题，且 `old` 的题干确实是这道话题题的参考问句之一」
    /// 才算——按来源（source）或按「同话题就吸收」去猜的话，用户自己用 CSV 加的一道题
    /// 会被一次无关的 PDF 导入悄悄吃掉，而他挂在那道题上的练习记录会跟着搬家。
    public static func supersedes(_ candidate: Question, _ old: Question) -> Bool {
        guard candidate.id != old.id, isTopicQuestion(candidate) else { return false }
        guard candidate.part == old.part, candidate.topic == old.topic else { return false }
        return candidate.followups.contains(old.prompt)
    }

    /// 题库里还剩多少道「一问一题」的旧结构题目。0 表示题库已经是新结构了。
    ///
    /// 判据是**同一个 (part, topic) 下有两道以上的题**，而不是「`prompt != topic`」：
    /// 后者会把用户自己用 CSV 加的、一个话题只写了一道的题也算成旧结构，
    /// 于是界面上那条「你的题库还是旧结构」的提示永远消不掉，等于骚扰。
    public static func legacyShapedCount(in questions: [Question]) -> Int {
        var buckets: [String: Int] = [:]
        for question in questions where question.part == 1 || question.part == 3 {
            buckets["\(question.part)|\(question.topic)", default: 0] += 1
        }
        return buckets.values.filter { $0 >= 2 }.reduce(0, +)
    }
}

/// 题号搬家：题库重建模之后，把指向旧题号的历史记录搬到新题号上。
///
/// **这不是可选项。** 题号是内容哈希，「一问一题」变「一话题一题」会让 Part 1 与 Part 3
/// 每一道题的 id 都换掉。不搬的话，用户那场练习在训练记录页显示的是
/// 「这道题已经不在题库里了（id：p1-…）」，复训中心里那条目标点进去也找不到原题——
/// 数据其实都在，只是再也对不上号了。
public enum QuestionBankMigration {

    /// 把 `state` 里所有指向题号的地方按 `replacements`（旧 id → 新 id）改写。
    ///
    /// 覆盖四处，一处都不能漏：
    /// - `sessions[].questionId`：训练记录、复盘报告、历史列表全靠它找题；
    /// - `sessions[].retraining.originalQuestionId`：少了它，`retrainingKind` 会把一场
    ///   「原题重练」判成「换题验证」，复训中心会显示已经验证过了，而其实没有；
    /// - `currentSession`：正练到一半时导入题库并非不可能；
    /// - `plan.days[].questionIds` / `completedQuestionIds`：不改的话计划里那些天会指向
    ///   不存在的题，今日训练页那张卡片直接空掉。
    ///
    /// - Returns: 一共改了多少处引用。调用方要把这个数字说给用户听（铁律 7）。
    @discardableResult
    public static func remapQuestionIDs(in state: inout CoachState,
                                        replacements: [String: String]) -> Int {
        guard !replacements.isEmpty else { return 0 }
        var changed = 0

        func remap(_ id: inout String) {
            guard let replacement = replacements[id] else { return }
            id = replacement
            changed += 1
        }

        func remap(_ session: inout PracticeSession) {
            remap(&session.questionId)
            if var link = session.retraining {
                remap(&link.originalQuestionId)
                session.retraining = link
            }
        }

        for index in state.sessions.indices { remap(&state.sessions[index]) }
        if var current = state.currentSession {
            remap(&current)
            state.currentSession = current
        }
        if var plan = state.plan {
            for dayIndex in plan.days.indices {
                for slot in plan.days[dayIndex].questionIds.indices {
                    remap(&plan.days[dayIndex].questionIds[slot])
                }
                for slot in plan.days[dayIndex].completedQuestionIds.indices {
                    remap(&plan.days[dayIndex].completedQuestionIds[slot])
                }
                // 同一天里的两道旧碎片会搬到同一道话题题上。**必须去重**：
                // 学习计划页那一天会把同一道题列两遍，用户点第一遍练完之后
                // 第二遍仍然亮着「还没练」，看着像进度没保存。
                plan.days[dayIndex].questionIds =
                    deduplicated(plan.days[dayIndex].questionIds)
                plan.days[dayIndex].completedQuestionIds =
                    deduplicated(plan.days[dayIndex].completedQuestionIds)
            }
            state.plan = plan
        }
        return changed
    }

    /// 保序去重。用 `Set` 一把过会打乱顺序，而计划里那几天的题序是用户看得见的。
    private static func deduplicated(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
