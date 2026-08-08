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

    /// 每个 Part 的**「这是什么」**——先教会它这个 Part 到底是个什么东西，再谈规则。
    ///
    /// ## 为什么规则写得再细都不够
    ///
    /// 2026-08-08 用户（考生本人）的原话：
    ///
    /// > 我觉得如果你直接说 part three 的话，他可能自己也不知道雅思 part three 有哪些东西。
    /// > 你最好给他加点提示词，解释一下 part three 具体是什么。
    ///
    /// 在这之前，三段 section rules 把「做什么」和「不做什么」都写满了，唯独没有一句话
    /// 说明这个 Part 本身是什么。规则是**约束**，约束只能修剪一个已经存在的概念；
    /// 模型脑子里那个「Part 3」如果本来就长歪了，再多的 `Never …` 也只是在歪的东西上修剪。
    /// 实测的表现就是：选了单练 Part 3，第一句问的是
    /// 「Can you describe a place you enjoy spending time in?」——
    /// 这句话既没出 cue card、也没给准备时间，把当时所有禁令逐条对一遍全是合规的，
    /// 但它根本不是 Part 3。
    ///
    /// ## 为什么要给正反例，而且反例要标出「这是 Part 几的问法」
    ///
    /// 「不许问个人经历题」是一句抽象的话，模型对它的理解不一定和考纲一致。
    /// 一组真题形状的例句能把这条线画在具体的位置上。反例只写「不许这样」是浪费——
    /// 标明它属于哪个 Part，模型才知道**错在哪一个维度**（层级不对，而不是措辞不对），
    /// 也才能自己举一反三到没被列出来的句式。
    private static let part1Primer = """
    What Part 1 is:
    Part 1 is the opening interview, about 4–5 minutes. You ask short questions about the learner's \
    own everyday life — home, hometown, work or study, food, weather, hobbies, daily routine, \
    simple likes and dislikes. Answers are two to four sentences. Nothing is set up as a task, and \
    nothing goes up to the level of society in general.

    Examples of real Part 1 questions:
    - ✅ "Do you work, or are you a student?" (the learner's own situation)
    - ✅ "How often do you cook at home?" (personal habit)
    - ✅ "Do you prefer to shop online or in shops?" (simple personal preference)
    - ❌ "Describe a meal you really enjoyed." — that is a PART 2 question: it sets a task and asks \
    for a long prepared turn.
    - ❌ "How have eating habits changed in your country over the last twenty years?" — that is a \
    PART 3 question: it is about society and trends, not about this learner's own life.
    """

    private static let part2Primer = """
    What Part 2 is:
    Part 2 is the long turn, about 3–4 minutes in total. You give the learner ONE cue card — a \
    "Describe …" task with its bullet points — then preparation time, and then the learner speaks \
    alone for up to two minutes while you stay silent. One card, one monologue, one short \
    rounding-off question at the end. The task itself is supplied to you below; you do not invent \
    a different one.

    Examples:
    - ✅ "Describe a shop or store you enjoy visiting. You should say where it is, what it sells, \
    how often you go there, and explain why you enjoy visiting it." (a task, plus bullet points, \
    for a two-minute turn)
    - ❌ "Do you enjoy shopping?" — that is a PART 1 question: short and personal, it cannot fill \
    two minutes.
    - ❌ "What are the advantages and disadvantages of online shopping for small towns?" — that is \
    a PART 3 question: an abstract discussion question, not a long turn.
    """

    /// **这一段是这次改动的重点。** Part 3 是唯一一个「模型自以为知道、其实做成了别的东西」的 Part。
    ///
    /// 反例里那句 `Can you describe a place you enjoy spending time in?` 是从用户真机记录里
    /// 原样抄回来的——把翻车现场当反例写进提示词，比任何转述都准。
    private static let part3Primer = """
    What Part 3 is:
    Part 3 is a two-way discussion, about 4–5 minutes. You take the topic of the Part 2 card and \
    move it UP one level: away from this one learner, and out to people in general — society, \
    different groups and generations, how things have changed and where they are going, causes and \
    effects, advantages and disadvantages, comparisons, and whether something is a good thing. \
    The learner is expected to give opinions and reasons, not to tell you their own story. \
    Questions about the learner's personal experience, personal habits and personal preferences \
    belong to Part 1 and Part 2 — they are NOT Part 3.

    Examples of real Part 3 questions:
    - ✅ "What makes an environmental law effective or ineffective?" (evaluation)
    - ✅ "How have shopping habits changed in your country over the last twenty years?" \
    (change over time)
    - ✅ "Why do some people prefer small local shops to large chain stores?" (causes, comparison)
    - ✅ "What effect does online shopping have on small towns?" (consequences, society level)
    - ✅ "Do you think governments or individuals should be responsible for this? Why?" \
    (opinion with reasons, groups rather than one person)
    - ❌ "Describe a shop you like." — that is a PART 2 question: it sets a task and asks for a \
    long personal turn.
    - ❌ "Do you enjoy shopping?" — that is a PART 1 question: this learner's own preference.
    - ❌ "Do you often go to the shops near your home?" — that is a PART 1 question: this \
    learner's own routine.
    - ❌ "Can you describe a place you enjoy spending time in?" — that is a PART 1 / PART 2 \
    question: it asks the learner to describe their own experience. Never open Part 3 with it.
    """

    /// 提问前的默检。**每个 Part 一份，措辞不能共用。**
    ///
    /// 用户与 ChatGPT 一起给出的第三条修法就是这个：「每次提问前默检——是否为英语、
    /// 是否围绕主题、是否非 Part 1/2 的问法、是否基于上一个回答；不符合就重写再问。」
    ///
    /// 为什么值得单独写一段，而不是并进 `Never …` 清单：禁令是**读的时候**生效的，
    /// 自检是**每次开口之前**生效的。一段长对话里，模型早就滑离了开头那些约束，
    /// 一条「每次开口前重新对一遍」的指令会把约束重新拉回当前这一轮。
    ///
    /// 第三条按 Part 各自反过来写：Part 3 要防的是滑回 Part 1/2，
    /// Part 1 要防的是滑到 Part 2/3 去，Part 2 只有两句话要说（卡本身，和收尾那一问）。
    private static let part1SelfCheck = """
    Check before you speak (Part 1):
    Before you ask any question in this section, run these four checks silently, and rewrite the \
    question before you say it if it fails even one:
    1. Is it in English?
    2. Is it about the everyday topic you are currently on?
    3. Is it a Part 1 question — short, and about this learner's own life — rather than a Part 2 \
    "Describe …" long-turn task or an abstract Part 3 discussion question?
    4. Does it follow from what the learner has just said? (This one does not apply to your very \
    first question; the other three always do.)
    Never say a question that fails one of these checks. Fix it first, then ask.
    """

    private static let part2SelfCheck = """
    Check before you speak (Part 2):
    Before you read the cue card out, check silently that it is in English, that it is the task \
    supplied to you below rather than one you invented, and that you are giving its bullet points \
    with it. Before you ask the rounding-off question at the end, check silently that it is in \
    English, short, on the same topic, and that it is not the start of an abstract Part 3 \
    discussion. Fix it first, then speak.
    """

    private static let part3SelfCheck = """
    Check before you speak (Part 3):
    Before you ask any question in this discussion, run these four checks silently, and rewrite \
    the question before you say it if it fails even one:
    1. Is it in English?
    2. Is it about the discussion theme of this session?
    3. Is it a Part 3 question — abstract, about people in general, society, groups, trends, \
    causes, consequences, comparisons, advantages and disadvantages — and NOT a Part 1 question \
    about this learner's own habits or preferences, and NOT a Part 2 "Describe …" task?
    4. Does it build on what the learner has just said? (This one does not apply to your very \
    first question; the other three always do, and check 3 matters most of all on that first one.)
    Never say a question that fails one of these checks. Fix it first, then ask.
    """

    /// 每个 Part 的**「不做什么」**。
    ///
    /// ## 为什么「只写做什么」不够
    ///
    /// 2026-08-08 用户真机实测：他选了单练 Part 3，而 `part3Rules` 的第一句当时是
    /// `Start from the Part 2 theme when possible.`——ChatGPT 把这句读成了
    /// 「那就先把 Part 2 做出来」，第一句回复原样是一张 cue card：
    /// 「Describe a book you recently read. You should say …」。
    ///
    /// 三段规则当时把「这个 Part 要做的事」写得很细，却一个字都没说**不许做什么**。
    /// 一个尽职的模型手里拿着「Part 3 由 Part 2 延伸而来」这条背景知识时，
    /// 顺手把缺的那一半补上是最自然的行为——除非明说不许。
    ///
    /// 所以三个 Part 各自都要有一段禁令，且**必须逐 Part 分开写**：
    /// 「不许出 cue card」对 Part 1 / Part 3 是铁律，对 Part 2 恰恰相反。
    /// 每段禁令都用 Part 名开头限定作用域，这样它们在全真模考、
    /// 以及「Part 2 + Part 3 连着练」里同时出现也不会互相打架。
    private static let part1Nevers = """
    Never do these in Part 1:
    - Never present a cue card, and never set a "Describe …" task.
    - Never give preparation time.
    - Never ask for a long turn, a one-to-two-minute answer, or a speech.
    - Never open an abstract, general or society-level discussion — that is Part 3, not Part 1.
    """

    private static let part2Nevers = """
    Never do these in Part 2:
    - Never skip the cue card: the learner must be given the task and its bullet points.
    - Never interrupt the long turn to correct, teach, praise, or ask another question.
    - Never turn the long turn into a back-and-forth conversation.
    - Never start the abstract Part 3 discussion while the long turn is still running.
    """

    private static let part3Nevers = """
    Never do these in the Part 3 discussion:
    - Never present a cue card, and never turn the discussion theme into a "Describe …" task.
    - Never give preparation time.
    - Never ask for a one-to-two-minute long turn.
    - Never stay at Part 1 level — personal habits and simple preferences alone are not Part 3.
    """

    /// 单练 Part 3 时，规则正文**之前**要先说清这一场的边界。
    ///
    /// 放在最前面而不是塞进 section rules 的某一条里：ChatGPT 的第一句回复就已经出错了，
    /// 拦它的话必须排在它读到的所有 Part 3 细则之前。
    ///
    /// 「那张卡的题目是话题背景，不是要考生做的任务」这句是整段的重点——
    /// 题库里 Part 3 的题干就是它所属 cue card 的原文（见 `TopicQuestions.part3`），
    /// 一句 `Describe a law on environmental protection` 摆在那儿，
    /// 本身就在诱导模型把它当成 Part 2 的任务。
    private static let part3OnlyFraming = """
    This session contains ONLY Part 3. There is no Part 1 and no Part 2 in it.
    The topic supplied below is the background theme of the discussion, not a task for the learner: \
    it is the cue card that this set of Part 3 questions belongs to, and it is there only so that \
    you know what the discussion is about.
    Do not present it as a cue card, do not read it out as an instruction, and do not give any \
    preparation time. After the opening statement, your very first utterance is an abstract Part 3 \
    discussion question about that theme — about people in general, society, groups, trends, \
    causes, consequences, comparisons, or advantages and disadvantages. It must not be a question \
    about the learner's own experience, own habits or own preferences, and it must not ask them to \
    describe anything.
    """

    /// 各 Part 的规则单独拆出来，是因为**全真模考与「Part 2 + Part 3」要把它们原样装进去**。
    /// 原先 full mock 只写了一句 "Apply each part's own timing and questioning rules."——
    /// 而那三套规则的正文根本没进提示词，ChatGPT 无从「apply」起。
    private static let part1Rules = """
    \(part1Primer)

    Section rules (Part 1):
    - This section runs about 4–5 minutes.
    - Cover 2–3 everyday topics, and ask only 3–4 questions on each topic — about 9–12 questions in total.
    - Start with the supplied topic, then move on to other everyday topics of your choice.
    \(improvisationRules)
    - Never work through a whole list of questions.
    - Keep the section conversational but neutral.

    \(part1Nevers)

    \(part1SelfCheck)
    """

    private static func part2Rules(part2PrepMode: Part2PrepMode) -> String {
        """
        \(part2Primer)

        Section rules (Part 2):
        - Present one cue card.
        - \(part2PrepRule(for: part2PrepMode))
        - Do not supply content during preparation unless the learner requests practice support.
        - Ask one brief rounding-off question after the long turn.

        \(part2Nevers)

        \(part2SelfCheck)
        """
    }

    /// Part 3 的规则正文。
    ///
    /// - Parameter afterPart2: 这一场的 Part 3 前面**真的**刚做完一段 Part 2 吗
    ///   （全真模考、「Part 2 + Part 3 连着练」是 true；单练 Part 3 是 false）。
    ///
    /// 这个参数存在的唯一理由，就是那句起手规则不能两种场合共用一句话：
    /// 在有 Part 2 的场合它是「接着刚才那张卡继续」，在单练 Part 3 的场合，
    /// 同一句话会被读成「那就先把 Part 2 补出来」——实测就是这么翻车的。
    /// - Note: 起手那一条**两种场合都要求「第一问已经是抽象讨论」**。
    ///   在这之前，单练那一支写的是 "open with a question about it"——只说了「问它」，
    ///   没说「问到什么层级」，而模型手里那个「关于购物的问题」最顺手的一句就是
    ///   `Can you describe a place you enjoy spending time in?`（用户实测的原句）。
    ///   接在 Part 2 后面那一支同样要说死：那里的「先从刚才的话题起手」很容易被做成
    ///   「再追问一遍他刚才讲的那件事」，那还是 Part 2 的尾巴，不是 Part 3 的开头。
    private static func part3Rules(afterPart2: Bool) -> String {
        let opening = afterPart2
            ? "- Start from the Part 2 theme you have just finished, then move the discussion to "
                + "a more abstract, general level. Your very first Part 3 question must already be "
                + "above the personal level — ask about people in general, about society, about "
                + "causes or consequences — not one more question about what the learner personally "
                + "did or likes."
            : "- The discussion theme has already been chosen for you and is supplied below. "
                + "Your very first question must already be an abstract, general, society-level "
                + "question about that theme — about people in general, groups, trends, causes, "
                + "consequences, comparisons, advantages and disadvantages. Do NOT warm up with a "
                + "personal question about the learner's own experience of the theme, and do NOT "
                + "ask them to describe anything."
        return """
        \(part3Primer)

        Section rules (Part 3):
        - Ask 4–8 questions in total.
        \(opening)
        \(improvisationRules)
        - Some of your questions must be improvised on the spot from the learner's previous answer, \
        not taken from the reference list at all.
        - Move through explanation, comparison, causes, consequences, and evaluation.
        - Increase abstraction gradually.
        - If an answer is thin, probe with one neutral prompt such as "Why do you think that is?"

        \(part3Nevers)

        \(part3SelfCheck)
        """
    }

    // 用 switch 而非字典 + 强制解包：FocusPart 加 case 却忘了给规则时，
    // 编译期就会因为 switch 不再穷尽而报错，而不是等到运行时才 crash。
    private static func partRules(for focusPart: FocusPart, part2PrepMode: Part2PrepMode) -> String {
        switch focusPart {
        case .part1:
            return part1Rules
        case .part2:
            return part2Rules(part2PrepMode: part2PrepMode)
        case .part3:
            return """
            \(part3OnlyFraming)

            \(part3Rules(afterPart2: false))
            """
        case .part2And3:
            return """
            Section rules (Part 2 + Part 3, run back to back):
            - This session is a Part 2 long turn followed immediately by a Part 3 discussion, \
            exactly as they follow each other in the real exam. There is no Part 1 in it.
            - Do not deliver a review, summary, or score between the two parts.
              This does NOT cancel the per-answer correction rule stated above, if one is in effect.
            - The question supplied below is the Part 2 cue card. The Part 3 discussion that \
            follows must stay on that same theme.
            - When the Part 2 rounding-off question is done, mark the change of gear in one short \
            sentence (for example "Now let's talk more generally about …"), then begin Part 3.
            - You are given no reference questions for the Part 3 half of this session: improvise \
            every one of them from the cue card theme and from what the learner said in the long turn.
            - Each part keeps its own pacing and questioning rules, spelled out here:

            \(part2Rules(part2PrepMode: part2PrepMode))

            \(part3Rules(afterPart2: true))
            """
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

            \(part3Rules(afterPart2: true))
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

    /// 题目那一段。**三种考法各写一段，不能共用一句话。**
    ///
    /// ## 单练 Part 3 那一支为什么连题干本身都不原样往下传
    ///
    /// 原先无论哪一档都是 `Today's question (Part N, topic: T):` 加题干原文。
    /// 第一轮修的是抬头，改成了「这是讨论话题，不是任务」，但题干原文还留在下面，
    /// 于是单练 Part 3 时提示词长这样：
    ///
    ///     Discussion theme for this Part 3 session (topic: Describe a shop/store you enjoy visiting)
    ///     …it is NOT a task, NOT a cue card…
    ///     Describe a shop/store you enjoy visiting
    ///
    /// 用户实测的第一句仍然是 `Can you describe a place you enjoy spending time in?`。
    /// 他的判断是对的：**那个 `Describe` 摆在那儿本身就在诱导，旁边写「别念这句」没用。**
    /// 题库里 Part 3 的题干就等于它所属 cue card 的原文（见 `TopicQuestions.part3`），
    /// 所以这一档必须先把题干改写成话题短语（`DiscussionTheme.phrase`）再往下传——
    /// 让提示词里根本不出现那张卡的原句，而不是出现之后再否定它。
    private static func questionBlock(for setup: SessionSetup) -> String {
        switch setup.focusPart {
        case .part3:
            return """
            Part 3 theme: \(part3Theme(for: setup.question))

            That line is the background theme this set of discussion questions belongs to; \
            it is NOT a task, NOT a cue card, and the learner is NOT being asked to describe it. \
            Do not read it out as an instruction. Your first question is an abstract Part 3 \
            discussion question about it.
            """
        case .part2And3:
            return """
            Today's Part 2 cue card (topic: \(setup.question.topic)). \
            Present this one as the Part 2 task, then keep the Part 3 discussion on the same theme:
            \(setup.question.prompt)
            """
        case .part1, .part2, .fullMock:
            return """
            Today's question (Part \(setup.question.part), topic: \(setup.question.topic)):
            \(setup.question.prompt)
            """
        }
    }

    /// 单练 Part 3 时那一行主题短语。
    ///
    /// 三级兜底，每一级都对应一种真会出现的脏数据：题干改写不动就退回话题名，
    /// 话题名也空就**明说主题没给出来，并告诉考官这时候该怎么办**——
    /// 不能留一行 `Part 3 theme:` 后面什么都没有（铁律：禁止静默失败。
    /// 一份主题为空的提示词发出去，考官会自己编一个话题，而用户挑的那道题一次都不会被问到）。
    private static func part3Theme(for question: Question) -> String {
        let fromPrompt = DiscussionTheme.phrase(fromCueCard: question.prompt)
        if !fromPrompt.isEmpty { return fromPrompt }
        let fromTopic = DiscussionTheme.phrase(fromCueCard: question.topic)
        if !fromTopic.isEmpty { return fromTopic }
        return "(none was supplied — before your first question, ask the learner in English which "
            + "topic they would like to discuss, then run a normal Part 3 discussion on it)"
    }

    public static func build(setup: SessionSetup) -> String {
        var blocks: [String] = [contract(for: setup.feedbackTiming)]
        blocks.append(partRules(for: setup.focusPart, part2PrepMode: setup.part2PrepMode))

        var block = questionBlock(for: setup)
        if !setup.question.followups.isEmpty {
            block += "\n\n\(followupHeading(forPart: setup.question.part))\n"
                + setup.question.followups.map { "- \($0)" }.joined(separator: "\n")
        }
        blocks.append(block)

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
