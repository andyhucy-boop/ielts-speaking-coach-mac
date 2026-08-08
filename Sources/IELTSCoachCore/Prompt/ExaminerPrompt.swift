import Foundation

public struct SessionSetup: Equatable, Sendable {
    public let question: Question
    public let focusPart: FocusPart
    public let durationMinutes: Int
    public let goal: String               // 可为空
    public let feedbackTiming: FeedbackTiming
    public let part2PrepMode: Part2PrepMode

    public init(question: Question, focusPart: FocusPart, durationMinutes: Int, goal: String,
                feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.question = question
        self.focusPart = focusPart
        self.durationMinutes = durationMinutes
        self.goal = goal
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }
}

/// 考官提示词。正文依据上游 references/examiner-protocol.md。
/// 英文契约句必须逐字保留——它们直接决定 ChatGPT 是否进入考官角色。
public enum ExaminerPrompt {
    // 用 switch 而非字典 + 强制解包：FeedbackTiming 加 case 却忘了给规则时，
    // 编译期就会因为 switch 不再穷尽而报错，而不是等到运行时才 crash。
    private static func feedbackRule(for feedbackTiming: FeedbackTiming) -> String {
        switch feedbackTiming {
        case .deferred:
            return "Do not correct, praise, explain, or teach until examiner mode ends."
        case .immediate:
            return """
            After each answer, give exactly ONE short correction in 中文 — at most two sentences, \
            covering only the single most important language error or missing development. \
            Then immediately ask the next question. Do not praise. Do not explain grammar rules at length. \
            Do not discuss anything else. Return to examiner tone right after the correction.
            """
        }
    }

    // immediate 模式当场给反馈，deferred 模式反馈憋到最后 —— 两者矛盾，
    // 所以开场白必须跟着 feedbackTiming 换文本，不能只改「反馈规则」那一段。
    private static func openingStatement(for feedbackTiming: FeedbackTiming) -> String {
        switch feedbackTiming {
        case .deferred:
            return """
            "I will act as the examiner. I will save all feedback until the end. \
            If you are still thinking, continue speaking. Say "stop the test" whenever you want to stop."
            """
        case .immediate:
            return """
            "I will act as the examiner. I will give one short correction in 中文 after each answer, \
            then continue. If you are still thinking, continue speaking. \
            Say "stop the test" whenever you want to stop."
            """
        }
    }

    /// **本项目铁律：不许出现任何形式的雅思分数预测。**
    ///
    /// 这条红线此前只守在复盘那一侧（`ReviewRequestPrompt`）。考试当场这一侧一直是空的：
    /// 提示词从头到尾没有一个字禁止 ChatGPT 打分，而 immediate 模式每答一句就要它开口点评，
    /// 「这段大概 6.5」是它最顺手的一句话。学员一旦拿到数字就会盯着数字，
    /// 而不是盯着具体哪句话该怎么改。
    ///
    /// 放在 `contract` 里而不是某个 Part 的规则里：四种 `FocusPart`、两种 `FeedbackTiming`
    /// 都必须带上它，漏一种就等于没有。
    private static let noScoreRule = """
    Never give an IELTS band score, a band range, a level, or any numeric or letter rating of the \
    learner's English — not during the test, not at the end, and not if the learner asks for one. \
    If the learner asks for a score, say you will not give one, and continue the test.
    """

    private static func contract(for feedbackTiming: FeedbackTiming) -> String {
        """
        You will act as an IELTS Speaking examiner. Stay neutral and concise. \
        Ask one question at a time. \(feedbackRule(for: feedbackTiming))

        \(noScoreRule)

        Language: ask questions and follow-ups in English. Give ALL commentary, corrections, and explanations \
        in 中文 (Chinese). When quoting the learner's words or giving an English model answer, keep the English \
        verbatim — do not translate it.

        Before the first question, say exactly:
        \(openingStatement(for: feedbackTiming))

        Turn handling:
        - Treat short hesitation as part of the learner's answer.
        - Do not verbally fill silence with encouragement.
        - If the turn is handed over too early, ask: "Would you like to continue?"
        - Interrupt only for time control or substantial off-topic drift.
        - Never promise an exact silence threshold; the Voice system controls turn detection.
        """
    }

    // 同上：Part2PrepMode 加 case 却忘了给规则，编译期就会报错。
    private static func part2PrepRule(for part2PrepMode: Part2PrepMode) -> String {
        switch part2PrepMode {
        case .countdown:
            return "Announce one minute of preparation and up to two minutes of speaking."
        case .learnerControlled:
            return """
            Tell the learner to take as long as they need to prepare, and to say "I'm ready" when they want \
            to begin. Do not rush them and do not announce a time limit for preparation. \
            The long turn itself is still up to two minutes.
            """
        }
    }

    /// Part 1 与 Part 3 共用的「临场发挥」内核：**下一句问什么，取决于考生上一句说了什么。**
    ///
    /// 真实考官手里那张纸是素材，不是台本。用户本人举的例子：问他
    /// 「Do you like to lend things to others?」，他答的时候顺带聊到了钱，
    /// 那「Have you ever borrowed money from others?」这句就不必再问了。
    /// 照单念题的机器考官不会跳这一句——它会把六句问穿，那是问卷不是口语考试。
    ///
    /// **只给 Part 1 与 Part 3 用。** Part 2 是一张 cue card 加两分钟独白，
    /// 那里根本没有「下一问」；把这段塞过去只会让考官在长独白中途插嘴，
    /// 而 cue card 上的四条提示点考生本来就该逐条覆盖（见 `followupHeading`）。
    private static let improvisationRules = """
    - Any reference questions you are given are raw material, not a checklist: pick from them, \
    reorder them, and leave the rest unasked.
    - Choose each next question from what the learner has just said. When an answer already covers \
    the ground of a later reference question, drop that question rather than asking it anyway.
    - You may invent a follow-up of your own instead of using a reference question, as long as it \
    stays inside the topic you are on.
    """

    /// 各 Part 的规则单独拆出来，是因为**全真模考要把它们原样装进去**。
    /// 原先 full mock 只写了一句 "Apply each part's own timing and questioning rules."——
    /// 而那三套规则的正文根本没进提示词，ChatGPT 无从「apply」起。
    private static let part1Rules = """
    Section rules (Part 1):
    - This section runs about 4–5 minutes.
    - Cover 2–3 everyday topics, and ask only 3–4 questions on each topic — about 9–12 questions in total.
    - Start with the supplied topic, then move on to other everyday topics of your choice.
    \(improvisationRules)
    - Never work through a whole list of questions.
    - Keep the section conversational but neutral.
    """

    private static func part2Rules(part2PrepMode: Part2PrepMode) -> String {
        """
        Section rules (Part 2):
        - Present one cue card.
        - \(part2PrepRule(for: part2PrepMode))
        - Do not supply content during preparation unless the learner requests practice support.
        - Ask one brief rounding-off question after the long turn.
        """
    }

    private static let part3Rules = """
    Section rules (Part 3):
    - Ask 4–8 questions in total.
    - Start from the Part 2 theme, then move the discussion to a more abstract, general level.
    \(improvisationRules)
    - Some of your questions must be improvised on the spot from the learner's previous answer, \
    not taken from the reference list at all.
    - Move through explanation, comparison, causes, consequences, and evaluation.
    - Increase abstraction gradually.
    - If an answer is thin, probe with one neutral prompt such as "Why do you think that is?"
    """

    // 用 switch 而非字典 + 强制解包：FocusPart 加 case 却忘了给规则时，
    // 编译期就会因为 switch 不再穷尽而报错，而不是等到运行时才 crash。
    private static func partRules(for focusPart: FocusPart, part2PrepMode: Part2PrepMode) -> String {
        switch focusPart {
        case .part1:
            return part1Rules
        case .part2:
            return part2Rules(part2PrepMode: part2PrepMode)
        case .part3:
            return part3Rules
        case .fullMock:
            return """
            Section rules (full mock):
            - Run Part 1, Part 2, and Part 3 in order. Do not deliver a review, summary, or score between parts.
              This does NOT cancel the per-answer correction rule stated above, if one is in effect.
            - The question supplied below belongs to one of the three parts. Choose your own material \
            for the other two, staying on a related theme.
            - Each part keeps its own pacing and questioning rules, spelled out here:

            \(part1Rules)

            \(part2Rules(part2PrepMode: part2PrepMode))

            \(part3Rules)
            """
        }
    }

    private static let ending = """
    When the session ends, say exactly:
    "The simulation is complete. I am leaving examiner mode and preparing your structured review."
    Then wait. Do not produce the review until you receive an explicit review request.
    """

    /// `followups` 这一段该怎么向考官介绍。**三个 Part 的含义完全不同，不能共用一句话。**
    ///
    /// 题库改成「一话题一题」之后，Part 1 与 Part 3 的 `followups` 装的是**参考问句池**：
    /// 真实考试里 Part 1 一个话题只问 3–4 个，Part 3 有一部分问题是考官根据考生
    /// 上一个回答临场编的。原先那句 "Follow-up points to cover" 会让 ChatGPT
    /// 把一个话题下的六个问句一句不落地问完——那不是雅思口语，那是问卷。
    ///
    /// Part 2 不一样：那是 cue card 上 `You should say` 的提示点，考生本来就该逐条覆盖。
    private static func followupHeading(forPart part: Int) -> String {
        switch part {
        case 1:
            return """
            Reference questions for this topic — pick only 3–4 of them, and skip any whose \
            content the learner has already covered. Do NOT ask them all:
            """
        case 3:
            // 问句数量归 `part3Rules` 管，这里不再重复写一遍——两处各写一个数字，
            // 改的时候必然只改一处，提示词就会自相矛盾。
            return """
            Reference questions for this discussion — treat them as a pool, not a script. \
            Improvise most follow-ups from what the learner actually claims, and leave the rest unasked:
            """
        default:
            return "Follow-up points to cover:"
        }
    }

    public static func build(setup: SessionSetup) -> String {
        var blocks: [String] = [contract(for: setup.feedbackTiming)]
        blocks.append(partRules(for: setup.focusPart, part2PrepMode: setup.part2PrepMode))

        var questionBlock = """
        Today's question (Part \(setup.question.part), topic: \(setup.question.topic)):
        \(setup.question.prompt)
        """
        if !setup.question.followups.isEmpty {
            questionBlock += "\n\n\(followupHeading(forPart: setup.question.part))\n"
                + setup.question.followups.map { "- \($0)" }.joined(separator: "\n")
        }
        blocks.append(questionBlock)

        blocks.append("Target session length: about \(setup.durationMinutes) minutes.")

        let goal = setup.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            blocks.append("""
            本次唯一目标：\(goal)
            考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
            """)
        }

        blocks.append(ending)
        return blocks.joined(separator: "\n\n---\n\n")
    }
}
