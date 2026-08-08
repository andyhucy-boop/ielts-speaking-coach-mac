import XCTest
@testable import IELTSCoachCore

final class ExaminerPromptTests: XCTestCase {
    private let question = Question(id: "p2-skill-001", part: 2, topic: "Skills",
                                    prompt: "Describe a useful skill you learned",
                                    followups: ["How you learned it", "Why it is useful"])

    private func setup(focusPart: FocusPart = .part2,
                        feedbackTiming: FeedbackTiming = .deferred,
                        part2PrepMode: Part2PrepMode = .countdown) -> SessionSetup {
        SessionSetup(question: question, focusPart: focusPart, durationMinutes: 4, goal: "",
                     feedbackTiming: feedbackTiming, part2PrepMode: part2PrepMode)
    }

    func testIncludesQuestionAndFollowups() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("Describe a useful skill you learned"))
        XCTAssertTrue(text.contains("How you learned it"))
    }

    func testCarriesExaminerContractVerbatim() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("I will act as the examiner."))
        // 停止口令按 brief 第 3 节要求由中文改英文（testStopCommandIsEnglish 覆盖两种模式）。
        XCTAssertTrue(text.contains("stop the test"))
    }

    func testPart2AnnouncesPreparationAndSpeakingTime() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("one minute of preparation"))
        XCTAssertTrue(text.contains("up to two minutes"))
    }

    /// Part 1 走的是「短问题」那一套，不是 cue card 那一套。
    ///
    /// 原先这里钉的是 "6–10 short questions"。那个总数与同一段里的
    /// 「2–3 个话题 × 每话题 3–4 问」对不上（那是 6–12），而真实考法是 4–5 分钟约 9–12 问，
    /// 所以数字改成了 9–12。**这条测试要拦的东西没变**：Part 1 不能出现准备时间。
    /// 具体的节奏数字由 `testPart1PacingFollowsTheRealExam` 单独钉。
    func testPart1UsesShortQuestionRule() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p1-home-001", part: 1, topic: "Home", prompt: "Tell me about your home"),
            focusPart: .part1, durationMinutes: 5, goal: ""))
        XCTAssertTrue(text.contains("about 9–12 questions in total"))
        XCTAssertFalse(text.contains("one minute of preparation"))
    }

    func testIncludesSingleGoalWhenProvided() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: "减少 filler words"))
        XCTAssertTrue(text.contains("减少 filler words"))
    }

    func testOmitsGoalSectionWhenEmpty() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertFalse(text.contains("本次唯一目标"))
    }

    func testForbidsFeedbackDuringExam() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."))
    }

    func testReviewRequestEmbedsRequestIDInBothMarkers() {
        let text = ReviewRequestPrompt.build(requestID: "sync-123", focusPart: .part2)
        XCTAssertTrue(text.contains("<<<IELTS_REVIEW_JSON:sync-123>>>"))
        XCTAssertTrue(text.contains("<<<END_IELTS_REVIEW_JSON:sync-123>>>"))
        XCTAssertTrue(text.contains("SYNC_REQUEST_ID:sync-123"))
    }

    func testReviewRequestCarriesAnswerUpgradePolicy() {
        let text = ReviewRequestPrompt.build(requestID: "sync-123", focusPart: .part2)
        XCTAssertTrue(text.contains("90至120秒"))
        XCTAssertTrue(text.contains("逐题高分版生成规则"))
    }

    func testBuildCoversEveryFocusPartCase() {
        // partRules 是手写的 [FocusPart: String] 字典，删掉 assertionFailure 之后
        // build() 里改成了强制解包；这条测试逐 case 跑一遍，保证字典没有漏掉某个
        // FocusPart case（否则会在这里而不是生产环境里炸出来）。
        for part in FocusPart.allCases {
            let text = ExaminerPrompt.build(setup: SessionSetup(
                question: question, focusPart: part, durationMinutes: 4, goal: ""))
            XCTAssertTrue(text.contains("Section rules"), "缺少 \(part) 的 section rules")
        }
    }

    func testReviewRequestOutputIsParseableEndToEnd() throws {
        // 用一份符合指令要求的假回复，验证 ReviewParser 能吃下自己发出的格式
        let (open, close) = ReviewRequestPrompt.marker(requestID: "sync-9")
        let fake = """
        \(open)
        {"summary":"ok","must_correct":[],"answer_upgrades":[{"question":"Q",\
        "original_answer":"a","revised_answer":"b","changes":[]}],"priority_target":{"id":"t"}}
        \(close)
        """
        XCTAssertEqual(try ReviewParser.parse(fake, requireAnswerUpgrades: true)["summary"],
                       .string("ok"))
    }

    func testDeferredTimingForbidsMidSessionFeedback() {
        let text = ExaminerPrompt.build(setup: setup(feedbackTiming: .deferred))
        XCTAssertTrue(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."))
        XCTAssertFalse(text.contains("After each answer"))
    }

    func testImmediateTimingAsksForOneShortChineseCorrection() {
        let text = ExaminerPrompt.build(setup: setup(feedbackTiming: .immediate))
        XCTAssertTrue(text.contains("After each answer"))
        XCTAssertTrue(text.contains("at most two sentences"))
        XCTAssertFalse(text.contains("Do not correct, praise, explain, or teach until examiner mode ends."),
                       "immediate 模式不能同时出现「全程不反馈」的指令，两者自相矛盾")
        XCTAssertFalse(text.contains("I will save all feedback until the end"),
                       "immediate 模式的开场白不能说「反馈留到最后」")
    }

    func testCountdownPrepAnnouncesOneMinute() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .part2, part2PrepMode: .countdown))
        XCTAssertTrue(text.contains("Announce one minute of preparation"))
    }

    func testLearnerControlledPrepDoesNotRush() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .part2, part2PrepMode: .learnerControlled))
        XCTAssertTrue(text.contains("say \"I'm ready\""))
        XCTAssertFalse(text.contains("Announce one minute of preparation"))
    }

    func testStopCommandIsEnglish() {
        for timing in FeedbackTiming.allCases {
            let text = ExaminerPrompt.build(setup: setup(feedbackTiming: timing))
            XCTAssertTrue(text.contains("stop the test"), "停止口令应为英文：\(timing)")
            XCTAssertFalse(text.contains("结束训练"), "不应再出现中文停止口令：\(timing)")
        }
    }

    func testAllModesRequireChineseCommentary() {
        for timing in FeedbackTiming.allCases {
            for prep in Part2PrepMode.allCases {
                let text = ExaminerPrompt.build(
                    setup: setup(focusPart: .part2, feedbackTiming: timing, part2PrepMode: prep))
                XCTAssertTrue(text.contains("in 中文"), "缺少中文点评要求：\(timing)/\(prep)")
            }
        }
    }

    func testReviewRequestRequiresChineseCommentary() {
        let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: .part2)
        XCTAssertTrue(text.contains("一律用中文"))
    }

    /// **DEFINITION-OF-DONE 第 4 节第一条：不预测雅思分数。**
    ///
    /// 这条红线此前在复盘这条路上没有任何守卫：七条输出要求里一条都没禁止 ChatGPT 打分。
    /// 之所以一直没透出来，纯粹是因为 `summary` 压根没被显示——
    /// 而「把 summary 显示出来」正是复审第 2 条要修的事，两件事必须同时做完。
    /// 界面这一侧拦不住：`summary` 是 ChatGPT 写的，扫源码扫不到它。
    /// 唯一能拦的地方就是这份提示词。
    func testReviewRequestForbidsAnyBandScoreOrLevelJudgement() {
        for part in FocusPart.allCases {
            let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: part)
            XCTAssertTrue(text.contains("不要给任何形式的雅思分数、评级或水平判断"),
                          "\(part) 的复盘请求里没有禁止打分这一条。"
                              + "「你大概 6.5 分」既不准也有害，会让学员盯着数字"
                              + "而不是盯着具体哪句话该怎么改（DEFINITION-OF-DONE 第 4 节）。")
            XCTAssertTrue(text.contains("summary 里同样一个字都不许出现"),
                          "禁令没有点名 summary。整体总结是唯一一段连贯的话，"
                              + "也是最容易顺手写上一句「大概 6.5」的地方——"
                              + "而它现在会原样显示在复盘报告页上。")
        }
    }

    /// 提示词要 ChatGPT 输出的每一个顶层键，界面上都得有人显示。
    /// 这条钉的是那张键表本身没有被悄悄缩水——它是「复盘里有哪些内容」的唯一出处，
    /// 而 `ReviewReportViewModel` 的分区表照着它写。
    func testReviewRequestStillAsksForTheHabitsAndLogicFeedbackBlocks() {
        let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: .part2)
        for key in ["summary", "must_correct", "natural_upgrades", "vocabulary",
                    "habits", "logic_feedback", "answer_upgrades", "priority_target"] {
            XCTAssertTrue(text.contains(key), "复盘请求里不再要 \(key) 这一项了")
        }
        XCTAssertTrue(text.contains(#""fix": 下次怎么改"#),
                      "口语习惯少了「下次怎么改」这一格。只说「你有这个毛病」而不说怎么改，"
                          + "正是本项目铁律 4 要拦的那种话。")
    }

    func testFullMockThreadsPart2PrepMode() {
        let countdown = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, part2PrepMode: .countdown))
        XCTAssertTrue(countdown.contains("Announce one minute of preparation"),
                      "全真模考里有 Part 2，准备时间模式必须传进去")

        let learnerLed = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, part2PrepMode: .learnerControlled))
        XCTAssertTrue(learnerLed.contains("say \"I'm ready\""))
        XCTAssertFalse(learnerLed.contains("Announce one minute of preparation"),
                       "用户选了自己决定，不该再出现倒计时指令")
    }

    func testFullMockDoesNotCancelImmediateCorrections() {
        let text = ExaminerPrompt.build(
            setup: setup(focusPart: .fullMock, feedbackTiming: .immediate))
        XCTAssertTrue(text.contains("After each answer"))
        XCTAssertTrue(text.contains("does NOT cancel"),
                      "必须明确「不在各 Part 之间总结」不等于「整场不给反馈」，否则会静默覆盖当场点评")
        XCTAssertFalse(text.contains("without pausing for feedback between them"),
                       "这句歧义表述应已被替换")
    }

    // MARK: - 参考问句不是问卷（题库重建模之后新增）

    /// **Part 1 的 `followups` 是一池参考问句，不是清单。**
    ///
    /// 题库改成「一话题一题」之后，一道 Part 1 题底下挂着这个话题的全部问句
    /// （真实题库里五到七句）。原先那句 "Follow-up points to cover" 会让 ChatGPT
    /// 把七句一句不落地问完——而真实考试里 Part 1 一个话题只问 3–4 个，
    /// 考生答第一句时顺带聊到了第二句的内容，考官就跳过它。
    /// 一句不落地问完就不是雅思口语了，是问卷。
    func testPart1ReferenceQuestionsAreOfferedAsAPoolNotAChecklist() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p1-borrow", part: 1, topic: "Borrowing/lending",
                               prompt: "Borrowing/lending",
                               followups: ["Do you like to lend things to others?",
                                           "Have you ever borrowed money from others?"]),
            focusPart: .part1, durationMinutes: 5, goal: ""))

        XCTAssertFalse(text.contains("Follow-up points to cover"),
                       "Part 1 的参考问句仍被当成「要覆盖的要点」，考官会把整个话题问穿")
        XCTAssertTrue(text.contains("pick only 3–4 of them"),
                      "没有告诉考官只挑 3–4 个：\n\(text)")
        XCTAssertTrue(text.contains("Do NOT ask them all"),
                      "没有明说不许全问一遍：\n\(text)")
        XCTAssertTrue(text.contains("Do you like to lend things to others?"),
                      "参考问句本身得给出去，否则考官只拿到一个话题名")
    }

    /// Part 3 那一半：那一组追问同样是池子，而且要明说大部分追问要临场从考生的
    /// 回答里生成——真实考试里 Part 3 有一部分问题就是考官现编的。
    func testPart3ReferenceQuestionsAreAPoolAndImprovisationIsRequired() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p3-x", part: 3, topic: "Describe a person you admire",
                               prompt: "Describe a person you admire",
                               followups: ["Why do people admire celebrities?"]),
            focusPart: .part3, durationMinutes: 5, goal: ""))

        XCTAssertFalse(text.contains("Follow-up points to cover"),
                       "Part 3 的参考问句仍被当成「要覆盖的要点」")
        XCTAssertTrue(text.contains("not a script"), "没有说清那是池子不是脚本：\n\(text)")
        // 钉整句而不是 "improvise" 这四个字：Part 3 的 section rules 里也有一句
        // 「部分问题必须临场编」，只钉词根的话，把这行抬头删掉测试照样是绿的。
        XCTAssertTrue(text.contains("Improvise most follow-ups from what the learner actually claims"),
                      "参考问句那一栏没有要求临场追问：\n\(text)")
    }

    /// **反面：Part 2 那一栏还是「要覆盖的提示点」，一个字都不许改。**
    ///
    /// cue card 上 `You should say` 的四条提示点，考生本来就该逐条覆盖，
    /// 那是 Part 2 的评分点。把它也改成「挑几条说说」会让长独白垮掉。
    func testPart2CueCardBulletsAreStillPointsToCover() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        XCTAssertTrue(text.contains("Follow-up points to cover"),
                      "cue card 的提示点被改成了「参考问句」，Part 2 的长独白会失去骨架")
        XCTAssertFalse(text.contains("pick only 3–4 of them"))
    }

    // MARK: - 临场发挥：考官自己决定问什么
    //
    // 下面这一组钉的是「提示词里确实写了这些话」。
    // **它们证明不了 ChatGPT 照做了**——提示词在 ChatGPT 那边执行，我们这侧只能写清楚。
    // 「考官真的跳过了已答到的问题」只能人工验，判据见
    // docs/examiner-improvisation-acceptance-checklist.md。

    private func part1Text(followups: [String] = []) -> String {
        ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p1-borrow", part: 1, topic: "Borrowing/lending",
                               prompt: "Borrowing/lending", followups: followups),
            focusPart: .part1, durationMinutes: 5, goal: ""))
    }

    private func part3Text(followups: [String] = []) -> String {
        ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p3-admire", part: 3, topic: "Describe a person you admire",
                               prompt: "Describe a person you admire", followups: followups),
            focusPart: .part3, durationMinutes: 5, goal: ""))
    }

    /// **Part 1 的节奏：2–3 个话题，每话题 3–4 问，约 9–12 问。**
    ///
    /// 真实考试 4–5 分钟。把一个话题下列出的六七个问句全问一遍，
    /// 时间上根本不是 Part 1，内容上也不是——那是问卷。
    func testPart1PacingFollowsTheRealExam() {
        let text = part1Text()
        XCTAssertTrue(text.contains("about 4–5 minutes"), "没给出 Part 1 的真实时长：\n\(text)")
        XCTAssertTrue(text.contains("2–3 everyday topics"), "没说要覆盖 2–3 个话题：\n\(text)")
        XCTAssertTrue(text.contains("3–4 questions on each topic"),
                      "没说每个话题只问 3–4 个：\n\(text)")
        XCTAssertTrue(text.contains("Start with the supplied topic"),
                      "没说从给定话题起手——不然今天挑的这道题可能一次都不会被问到：\n\(text)")
        XCTAssertTrue(text.contains("Never work through a whole list of questions."),
                      "没有明说不许把一张单子问穿：\n\(text)")
    }

    /// **Part 3 的节奏：一共 4–8 问，且要往抽象层面走。**
    ///
    /// 「往抽象走」这一条原先钉的是 `more abstract, general level`，那是接在 Part 2 后面
    /// 那一支的措辞。单练 Part 3 这一支现在把要求提前到了第一问（见
    /// `testPart3AloneMakesTheVeryFirstQuestionAbstract`），措辞跟着变了，
    /// 但这条测试要拦的东西没变：**单练 Part 3 也必须往抽象层面走，不能停在个人层面。**
    func testPart3PacingFollowsTheRealExam() {
        // 特意不给 followups：抬头那一栏就不会出现，
        // 于是这条断言只可能命中 section rules 本身。
        let text = part3Text()
        XCTAssertTrue(text.contains("Ask 4–8 questions in total."), "没说共问 4–8 个：\n\(text)")
        XCTAssertTrue(text.contains("Increase abstraction gradually."),
                      "没要求逐步往抽象层面走：\n\(text)")
        XCTAssertTrue(text.contains("abstract, general, society-level"),
                      "单练 Part 3 没要求讨论走到抽象、社会层面：\n\(text)")
    }

    /// **参考问句是素材，不是清单。** Part 1 与 Part 3 都要有这句。
    func testPart1AndPart3TreatReferenceQuestionsAsRawMaterial() {
        for (name, text) in [("Part 1", part1Text()), ("Part 3", part3Text())] {
            XCTAssertTrue(text.contains("raw material, not a checklist"),
                          "\(name) 没说参考问句是素材而不是清单，考官会照单念题：\n\(text)")
        }
    }

    /// **下一句问什么，取决于考生上一句说了什么；已经答到的就跳过。**
    ///
    /// 这是用户本人举的那个例子：问他愿不愿意借东西给别人，他答的时候聊到了钱，
    /// 那「你跟人借过钱吗」这句就不必再问。
    func testPart1AndPart3PickTheNextQuestionFromTheLastAnswer() {
        for (name, text) in [("Part 1", part1Text()), ("Part 3", part3Text())] {
            XCTAssertTrue(text.contains("Choose each next question from what the learner has just said"),
                          "\(name) 没有要求根据上一个回答决定下一问：\n\(text)")
            XCTAssertTrue(text.contains("drop that question rather than asking it anyway"),
                          "\(name) 没有要求跳过考生已经答到的问句——"
                              + "这正是用户举的那个例子（聊到了钱就不必再问借钱）：\n\(text)")
        }
    }

    /// **考官可以自己编追问，但不许跑出当前话题。**
    ///
    /// 后半句同样重要：只说「可以自由发挥」而不划范围，一场 Part 1 会被聊成闲谈。
    func testPart1AndPart3AllowImprovisedFollowUpsInsideTheTopic() {
        for (name, text) in [("Part 1", part1Text()), ("Part 3", part3Text())] {
            XCTAssertTrue(text.contains("invent a follow-up of your own"),
                          "\(name) 没有允许考官自己编追问：\n\(text)")
            XCTAssertTrue(text.contains("stays inside the topic you are on"),
                          "\(name) 允许了自由发挥却没划范围，考试会跑题：\n\(text)")
        }
    }

    /// **Part 3 更进一步：有一部分问题必须是现编的，不能全从单子上拿。**
    func testPart3RequiresSomeQuestionsToBeImprovisedFromScratch() {
        let text = part3Text()
        XCTAssertTrue(text.contains("must be improvised on the spot from the learner's previous answer"),
                      "Part 3 没有要求一部分问题临场生成——真实考试里这部分就是考官现编的：\n\(text)")
    }

    /// **反面：Part 2 一个字都不许沾临场发挥那一套。**
    ///
    /// Part 2 是一张 cue card 加两分钟独白，那里根本没有「下一问」。
    /// 把「根据回答决定下一句问什么」塞进去，等于请考官在长独白中途插嘴。
    func testPart2DoesNotGetTheImprovisationRules() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2, durationMinutes: 4, goal: ""))
        for line in ["raw material, not a checklist",
                     "Choose each next question from what the learner has just said",
                     "invent a follow-up of your own"] {
            XCTAssertFalse(text.contains(line),
                           "Part 2 混进了 Part 1/3 的临场发挥规则「\(line)」，"
                               + "考官会在两分钟长独白中途插话")
        }
    }

    /// **全真模考必须把三个 Part 的规则正文都带上。**
    ///
    /// 原先 full mock 只写了一句「Apply each part's own timing and questioning rules」，
    /// 而那三套规则的正文压根没进提示词——ChatGPT 手里什么都没有，无从 apply 起。
    /// 于是全真模考里的 Part 1 会照单念题，Part 3 不会现编，两条都静默失效。
    func testFullMockCarriesTheRealPacingRulesForEveryPart() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .fullMock))
        XCTAssertTrue(text.contains("belongs to one of the three parts"),
                      "全真模考只给了一道题，却没说另外两个 Part 的材料要考官自己找：\n\(text)")
        XCTAssertTrue(text.contains("3–4 questions on each topic"),
                      "全真模考里没带上 Part 1 的节奏规则：\n\(text)")
        XCTAssertTrue(text.contains("Ask 4–8 questions in total."),
                      "全真模考里没带上 Part 3 的题量规则：\n\(text)")
        XCTAssertTrue(text.contains("Choose each next question from what the learner has just said"),
                      "全真模考里没带上「根据上一个回答决定下一问」：\n\(text)")
        XCTAssertTrue(text.contains("must be improvised on the spot from the learner's previous answer"),
                      "全真模考里没带上 Part 3 的临场发挥要求：\n\(text)")
    }

    // MARK: - 临场发挥不许把既有红线一起放开

    /// **红线一：一次只问一个问题。**
    ///
    /// 「你可以自己编追问」离「那我一口气抛三个问题」只有一步。
    /// 四种 Part × 两种反馈时机都得带上这句。
    func testEveryModeStillAsksOneQuestionAtATime() {
        for part in FocusPart.allCases {
            for timing in FeedbackTiming.allCases {
                let text = ExaminerPrompt.build(setup: setup(focusPart: part, feedbackTiming: timing))
                XCTAssertTrue(text.contains("Ask one question at a time."),
                              "\(part)/\(timing) 少了「一次只问一个问题」")
            }
        }
    }

    /// **红线二：本项目铁律——不许出现任何形式的雅思分数预测。**
    ///
    /// 这条此前只守在复盘那一侧（`testReviewRequestForbidsAnyBandScoreOrLevelJudgement`）。
    /// 考试当场这一侧是空的：提示词里一个字都没禁止打分，而 immediate 模式每答一句
    /// 就要 ChatGPT 开口点评，「这段大概 6.5」是它最顺手的一句话。
    /// 界面这一侧拦不住——考官说的话直接进语音，源码里扫不到它。
    func testNoModeEverAllowsABandScore() {
        for part in FocusPart.allCases {
            for timing in FeedbackTiming.allCases {
                for prep in Part2PrepMode.allCases {
                    let text = ExaminerPrompt.build(
                        setup: setup(focusPart: part, feedbackTiming: timing, part2PrepMode: prep))
                    XCTAssertTrue(text.contains("Never give an IELTS band score"),
                                  "\(part)/\(timing)/\(prep) 没有禁止考官打分（本项目铁律第 8 条）")
                    XCTAssertTrue(text.contains("not if the learner asks for one"),
                                  "\(part)/\(timing)/\(prep) 的禁令留了口子："
                                      + "学员一句「我大概几分」就能把它绕过去")
                }
            }
        }
    }

    // MARK: - 单练 Part 3 就只考 Part 3（2026-08-08 用户真机实测的那一次翻车）
    //
    // 他选了 Part 3，ChatGPT 的第一句回复是：
    //     "Alright. Let's begin. Describe a book you recently read. You should say what the book
    //      was, what it was about, why you chose it, and explain how you felt about it."
    // ——一张 Part 2 cue card。当时 `part3Rules` 的第一句是
    // "Start from the Part 2 theme when possible."，被读成了「先把 Part 2 做出来」。

    /// 一道真实形状的 Part 3 题：题干**就等于**它所属 cue card 的原文
    /// （题库的建模规则，见 `TopicQuestions.part3`），所以它天生长得像一个 Part 2 任务。
    private let part3AsInTheRealBank = Question(
        id: "p3-law", part: 3, topic: "Describe a law on environmental protection",
        prompt: "Describe a law on environmental protection",
        followups: ["Should governments do more to protect the environment?"])

    private func part3OnlyText(feedbackTiming: FeedbackTiming = .deferred) -> String {
        ExaminerPrompt.build(setup: SessionSetup(
            question: part3AsInTheRealBank, focusPart: .part3, durationMinutes: 6, goal: "",
            feedbackTiming: feedbackTiming))
    }

    /// **这一场只有 Part 3，规则里必须把这句话说死。**
    ///
    /// 把 `part3OnlyFraming` 从提示词里删掉，这条就红。
    func testPart3AloneDeclaresThatThereIsNoPart2InThisSession() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("This session contains ONLY Part 3."),
                      "没有明说这一场只有 Part 3。ChatGPT 知道「Part 3 接在 Part 2 后面」，"
                          + "不明说不许补的话，它会顺手先出一张 cue card：\n\(text)")
        XCTAssertFalse(text.contains("Start from the Part 2 theme"),
                       "单练 Part 3 的提示词里还留着「从 Part 2 的话题起手」——"
                           + "这正是实测中被读成「先做一张 cue card」的那一句：\n\(text)")
    }

    /// **那张卡的题目是话题背景，不是要考生做的任务。**
    func testPart3AloneCallsTheCueCardTextABackgroundThemeNotATask() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("not a task for the learner"),
                      "没说清题干只是话题背景。题库里 Part 3 的题干就是 cue card 原文，"
                          + "不点破的话它看起来就是一道「Describe a…」的任务：\n\(text)")
        XCTAssertTrue(text.contains("Do not present it as a cue card"),
                      "没有明说不许把它当成 cue card 出出去：\n\(text)")
    }

    /// **第一句就得是一个 Part 3 层面的讨论问题**，不是准备时间、不是长独白。
    func testPart3AloneOpensWithADiscussionQuestionAndGivesNoPreparationTime() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("your very first utterance is an abstract Part 3 "
                                    + "discussion question"),
                      "没说清第一句该是什么。只说「不许做 X」而不说「那该做什么」，"
                          + "模型仍然可能停在原地或者自己发明一套开场：\n\(text)")
        XCTAssertFalse(text.contains("one minute of preparation"),
                       "单练 Part 3 不该出现准备时间——那是 Part 2 的流程：\n\(text)")
        XCTAssertFalse(text.contains("Present one cue card."),
                       "单练 Part 3 的提示词里混进了 Part 2 的「出一张 cue card」：\n\(text)")
    }

    /// **题目那一段的措辞也要跟着改。**
    ///
    /// 规则段说「不许出 cue card」，题目段却写着「Today's question (Part 3): Describe a law…」，
    /// 那是一份自相矛盾的提示词——模型照哪一半做都不奇怪。
    ///
    /// 第二轮又改了一次：抬头改对了，题干原文却还留在下面（见
    /// `testPart3AloneNeverShowsTheRawDescribeSentence`），实测第一句依然是 Part 1 的问法。
    func testPart3QuestionBlockIsLabelledAsADiscussionThemeInsteadOfTodaysQuestion() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("Part 3 theme: a law on environmental protection"),
                      "题目那一段没有写成用户要的那一行「Part 3 theme: <话题短语>」：\n\(text)")
        XCTAssertTrue(text.contains("it is NOT a task, NOT a cue card"),
                      "题目块没有当场否掉「这是一道任务」这个读法：\n\(text)")
        XCTAssertFalse(text.contains("Today's question (Part 3"),
                       "题目块还是「今天的题目（Part 3）：Describe a law…」，"
                           + "一句 Describe 摆在「今天的题目」底下，本身就在诱导它当成 Part 2 任务：\n\(text)")
    }

    /// **一道 Part 3 的题，无论这一场是哪一档考法，题干都不许原样摆出来。**
    ///
    /// 那个 `Describe` 的诱导性跟考法无关，只跟题本身有关：题库里 Part 3 的题干就是
    /// 它所属 cue card 的原文（`TopicQuestions.part3`）。判据写成「这一场是不是单练
    /// Part 3」的话，同一道题被排进全真模考、或者从 MCP 那边被指成组合档时，
    /// `Today's question (Part 3): Describe a law…` 又会回到提示词里——
    /// 而那正是用户真机上翻车的那一行。
    func testAPart3QuestionIsNeverPrintedRawNoMatterWhichModeRunsIt() {
        for focus in [FocusPart.part3, .part1And3, .fullMock] {
            let text = ExaminerPrompt.build(setup: SessionSetup(
                question: part3AsInTheRealBank, focusPart: focus, durationMinutes: 6, goal: ""))
            XCTAssertTrue(text.contains("Part 3 theme: a law on environmental protection"),
                          "\(focus.rawValue) 里那道 Part 3 题没有被改写成话题短语：\n\(text)")
            XCTAssertFalse(text.contains("Today's question (Part 3"),
                           "\(focus.rawValue) 把 Part 3 的题干原样摆成了「今天的题目」——"
                               + "一句 Describe 摆在那儿本身就在诱导考官出 cue card：\n\(text)")
            XCTAssertFalse(text.contains("\nDescribe a law on environmental protection"),
                           "\(focus.rawValue) 的提示词里还留着那张卡的原句：\n\(text)")
        }
    }

    /// 组合档里那道 Part 3 的题只够一段用，别的几段必须交代清楚由考官自选。
    /// 不说的话，考官要么在 Part 1 里把这个抽象话题问一遍，要么整场只做 Part 3。
    func testACombinedSessionAnchoredOnAPart3QuestionSaysWhoSuppliesTheOtherParts() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: part3AsInTheRealBank, focusPart: .part1And3, durationMinutes: 10, goal: ""))
        XCTAssertTrue(text.contains("This session also runs Part 1"),
                      "没交代这一场还有 Part 1：\n\(text)")
        XCTAssertTrue(text.contains("choose your own"),
                      "没说清 Part 1 的材料由谁出：\n\(text)")
    }

    /// 两种反馈时机下都得成立——`.immediate` 那一支的开场白不一样，
    /// 别让「只在默认设置下才不出 cue card」溜过去。
    func testPart3AloneHoldsUnderEveryFeedbackTiming() {
        for timing in FeedbackTiming.allCases {
            let text = part3OnlyText(feedbackTiming: timing)
            XCTAssertTrue(text.contains("This session contains ONLY Part 3."), "\(timing)")
            XCTAssertFalse(text.contains("Present one cue card."), "\(timing)")
        }
    }

    // MARK: - 「Part 2 + Part 3 连着练」

    private func part2And3Text(part2PrepMode: Part2PrepMode = .countdown) -> String {
        ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2And3, durationMinutes: 9, goal: "",
            part2PrepMode: part2PrepMode))
    }

    /// **先 Part 2，再 Part 3，中间不停。** 真实考试就是这个顺序，这一档保留它。
    func testPart2And3RunsTheLongTurnFirstAndThenTheDiscussion() {
        let text = part2And3Text()
        XCTAssertTrue(text.contains("Section rules (Part 2 + Part 3, run back to back)"),
                      "这一档没有自己的 section rules：\n\(text)")
        XCTAssertTrue(
            text.contains("a Part 2 long turn followed immediately by a Part 3 discussion"),
            "没说清先做哪一段、再做哪一段：\n\(text)")
        XCTAssertTrue(text.contains("There is no Part 1 in it."),
                      "没排除 Part 1——这一档不是全真模考：\n\(text)")
        XCTAssertTrue(text.contains("mark the change of gear in one short sentence"),
                      "两段之间没有过渡指令，考官会把 Part 3 的第一问接得像还在追问 cue card：\n\(text)")
        XCTAssertTrue(text.contains("does NOT cancel"),
                      "「两段之间不做总结」必须写明它不等于「整场不给反馈」，"
                          + "否则会静默覆盖用户选的当场点评：\n\(text)")
    }

    /// 两段的规则正文都要原样装进去——只写一句「各按各的规则来」等于什么都没给
    /// （全真模考当年就栽在这上面）。
    func testPart2And3CarriesBothSectionsRulesVerbatim() {
        let text = part2And3Text()
        XCTAssertTrue(text.contains("Section rules (Part 2)"), "缺 Part 2 的规则正文：\n\(text)")
        XCTAssertTrue(text.contains("Present one cue card."), "缺「出一张 cue card」：\n\(text)")
        XCTAssertTrue(text.contains("up to two minutes"), "缺两分钟长独白：\n\(text)")
        XCTAssertTrue(text.contains("Section rules (Part 3)"), "缺 Part 3 的规则正文：\n\(text)")
        XCTAssertTrue(text.contains("Ask 4–8 questions in total."), "缺 Part 3 的题量：\n\(text)")
        XCTAssertTrue(text.contains("Start from the Part 2 theme you have just finished"),
                      "这一档里 Part 3 确实接在 Part 2 之后，起手规则就该这么写：\n\(text)")
    }

    // MARK: - 连着练时，那张卡自己那一组 Part 3 追问
    //
    // 用户原话：「我练 Part two 的时候，顺带也把对应的 Part three 问题一起给练了。」
    // 注意「对应的」三个字：真实考试里 Part 3 就是紧接着**这张卡**问下来的。
    //
    // 上一轮这里判断错了：给这一档写死了一句「Part 3 那一半没有参考问句，全部临场编」，
    // 前提是「题库里一张 cue card 底下只有 You should say 提示点」。
    // 题库重建模之后这个前提已经不成立——每张卡都有一条对应的 Part 3 题（`LinkedPart3`）。

    /// 那张卡自己的 Part 3 追问必须**原样进提示词**。
    ///
    /// 把 `part3ReferenceBlock` 里那几行 followups 去掉、或者把 `part3Reference`
    /// 在 `build` 里忽略掉，这条就红。
    func testPart2And3CarriesTheCueCardsOwnPart3QuestionsIntoThePrompt() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .part2And3, durationMinutes: 9, goal: "",
            part3Reference: pairedPart3))

        for reference in pairedPart3.followups {
            XCTAssertTrue(text.contains("- \(reference)"),
                          "题库里这张卡自己的 Part 3 追问「\(reference)」没进提示词——"
                              + "考官只能凭空编，而题库里现成的真题被扔掉了：\n\(text)")
        }
        XCTAssertTrue(text.contains("the question bank attaches to THIS cue card"),
                      "没说清这几问是**这张卡**的，考官会以为它们是随便一组讨论题：\n\(text)")
        XCTAssertFalse(text.contains("You are given no reference questions for the Part 3 half"),
                       "那句「Part 3 那一半没有参考问句」还在，和刚发下去的那一组直接打架：\n\(text)")
    }

    /// **配不上时不许沉默**（铁律：禁止静默失败）。
    ///
    /// 题库里没有这张卡对应的 Part 3 题（用户自己用 CSV 加的卡、或者导入残缺）时，
    /// 提示词里既没有问句、也没有「你得自己编」这句话的话，考官最顺手的做法是
    /// 把 cue card 的四条提示点当成讨论题再问一遍——那还是 Part 2。
    func testPart2And3SaysSoOutLoudWhenNoPairedPart3QuestionsExist() {
        let text = part2And3Text()      // part3Reference 是 nil
        XCTAssertTrue(text.contains("No Part 3 reference questions were found for this cue card"),
                      "配不上却一个字都不说：\n\(text)")
        XCTAssertTrue(text.contains("Improvise every Part 3 question yourself"),
                      "只说了「没有」，没说「那你该怎么办」：\n\(text)")
    }

    /// 全真模考里同样要带上——那一场里 Part 2 和 Part 3 都在。
    func testAFullMockAnchoredOnACueCardAlsoGetsThatCardsPart3Questions() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: question, focusPart: .fullMock, durationMinutes: 6, goal: "",
            part3Reference: pairedPart3))
        XCTAssertTrue(text.contains("- \(pairedPart3.followups[0])"),
                      "全真模考没把这张卡自己的 Part 3 追问带上：\n\(text)")
    }

    /// **这一场没有 Part 3 时，一个讨论题都不许发下去。**
    ///
    /// 发了的话，单练 Part 2 的考官手里会多出一组抽象讨论题——
    /// 它最可能拿来当那句「收尾一问」，于是两分钟独白后面接上一道 Part 3 的题。
    func testASessionWithoutPart3NeverGetsThoseQuestions() {
        for focus in [FocusPart.part1, .part2, .part1And2] {
            let text = ExaminerPrompt.build(setup: SessionSetup(
                question: question, focusPart: focus, durationMinutes: 4, goal: "",
                part3Reference: pairedPart3))
            XCTAssertFalse(text.contains(pairedPart3.followups[0]),
                           "\(focus.rawValue) 这一场没有 Part 3，却发了 Part 3 的讨论题：\n\(text)")
            XCTAssertFalse(text.contains("No Part 3 reference questions were found"),
                           "\(focus.rawValue) 这一场没有 Part 3，却在解释「配不上 Part 3 追问」：\n\(text)")
        }
    }

    /// 一道**真实形状**的配对 Part 3 题：题干与 topic 都等于那张 cue card 的原文
    /// （`TopicQuestions.part3`），底下挂着那一组真实追问。
    private var pairedPart3: Question {
        TopicQuestions.part3(
            cueCard: question.prompt,
            prompts: ["What kinds of skills are people often interested in learning?",
                      "Is it necessary to continue learning after finishing formal education?"])
    }

    /// **这一档不许带上「这一场只有 Part 3」那段话**——它这一场恰恰是有 Part 2 的。
    /// 两段规则同时出现的话，提示词自相矛盾。
    func testPart2And3DoesNotInheritThePart3OnlyFraming() {
        for (name, text) in [("Part 2 + Part 3", part2And3Text()),
                             ("全真模考", ExaminerPrompt.build(setup: setup(focusPart: .fullMock)))] {
            XCTAssertFalse(text.contains("This session contains ONLY Part 3."),
                           "\(name) 里混进了「这一场只有 Part 3」，"
                               + "而它明明要出 cue card——提示词自相矛盾：\n\(text)")
        }
    }

    /// 题目块把那道题说成 cue card，并且交代 Part 3 要留在同一个话题上。
    func testPart2And3QuestionBlockPresentsTheCueCardAndPinsThePart3Theme() {
        let text = part2And3Text()
        XCTAssertTrue(text.contains("Today's Part 2 cue card"),
                      "题目块没说这是一张 cue card：\n\(text)")
        XCTAssertTrue(text.contains("keep the Part 3 discussion on the same theme"),
                      "没要求 Part 3 留在同一个话题上，这一档就退化成「两道无关的题」：\n\(text)")
        XCTAssertTrue(text.contains("Follow-up points to cover"),
                      "cue card 的提示点被改写了。Part 2 的提示点是考生该逐条覆盖的，"
                          + "不是「挑几条说说」的参考问句：\n\(text)")
    }

    /// 用户在设置里选的「Part 2 的一分钟怎么处理」要穿到这一档里——
    /// 这一档里真的有一段 Part 2，漏穿的话那项偏好在这条路线上静默失效。
    func testPart2And3ThreadsPart2PrepMode() {
        XCTAssertTrue(part2And3Text(part2PrepMode: .countdown)
            .contains("Announce one minute of preparation"))
        let learnerLed = part2And3Text(part2PrepMode: .learnerControlled)
        XCTAssertTrue(learnerLed.contains("say \"I'm ready\""))
        XCTAssertFalse(learnerLed.contains("Announce one minute of preparation"),
                       "用户选了自己决定，不该再出现倒计时指令")
    }

    /// 复盘那一侧也要认得这一档：一场里出现了两种题型，两套长度标准都得给。
    /// 落回通用兜底的话，那句话里三个 Part 的目标句数、词数一个都没有。
    func testReviewRequestForPart2And3CarriesBothLengthStandards() {
        let text = ReviewRequestPrompt.build(requestID: "sync-1", focusPart: .part2And3)
        XCTAssertTrue(text.contains("最多两分钟陈述"), "缺 Part 2 的长度标准：\n\(text)")
        XCTAssertTrue(text.contains("比Part 1更抽象"), "缺 Part 3 的长度标准：\n\(text)")
        XCTAssertFalse(text.contains("先根据问题所属Part选择对应长度"),
                       "落回了通用兜底——这一场明明知道自己只会出现哪两种题型：\n\(text)")
    }

    // MARK: - 三个 Part 各自「不做什么」
    //
    // 原先三段规则只写了「做什么」。Part 3 这次就是栽在这上面：规则把该做的写得很细，
    // 而模型顺手把它以为缺的那一半（Part 2）补上了。

    /// 每个 Part 都得有一段自己的禁令。**逐 Part 分开写**：
    /// 「不许出 cue card」对 Part 1 / Part 3 是铁律，对 Part 2 恰恰相反。
    func testEveryPartSpellsOutWhatItMustNotDo() {
        let cases: [(String, String, String)] = [
            ("Part 1", part1Text(), "Never do these in Part 1:"),
            ("Part 2", ExaminerPrompt.build(setup: setup(focusPart: .part2)),
             "Never do these in Part 2:"),
            ("Part 3", part3OnlyText(), "Never do these in the Part 3 discussion:")
        ]
        for (name, text, heading) in cases {
            XCTAssertTrue(text.contains(heading),
                          "\(name) 只写了「做什么」，没写「不做什么」。"
                              + "本项目已经因为这一点翻过一次车（Part 3 被补出了一张 cue card）：\n\(text)")
        }
    }

    /// **Part 1 不做什么**：不出 cue card、不给准备时间、不要长独白、不谈抽象议题。
    func testPart1IsForbiddenFromCueCardsPreparationAndAbstractDiscussion() {
        let text = part1Text()
        for line in ["- Never present a cue card, and never set a \"Describe …\" task.",
                     "- Never give preparation time.",
                     "- Never ask for a long turn, a one-to-two-minute answer, or a speech.",
                     "- Never open an abstract, general or society-level discussion — "
                        + "that is Part 3, not Part 1."] {
            XCTAssertTrue(text.contains(line), "Part 1 少了这条禁令「\(line)」：\n\(text)")
        }
    }

    /// **Part 2 不做什么**：不许省掉 cue card、不许在两分钟里插嘴、不许把独白聊成对话、
    /// 不许当场展开 Part 3 的抽象讨论。
    func testPart2IsForbiddenFromInterruptingOrTurningIntoADiscussion() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .part2))
        for line in ["- Never skip the cue card: the learner must be given the task and its bullet points.",
                     "- Never interrupt the long turn to correct, teach, praise, or ask another question.",
                     "- Never turn the long turn into a back-and-forth conversation.",
                     "- Never start the abstract Part 3 discussion while the long turn is still running."] {
            XCTAssertTrue(text.contains(line), "Part 2 少了这条禁令「\(line)」：\n\(text)")
        }
    }

    /// **Part 3 不做什么**：不出 cue card、不给准备时间、不要长独白、不许停在 Part 1 的层面。
    ///
    /// 这一段在**三种**带 Part 3 的考法里都得在：单练、连着练、全真模考。
    /// 少了其中任何一处，那条路线上的 Part 3 就又可能被做成一张卡。
    func testPart3IsForbiddenFromCueCardsAndLongTurnsInEveryModeThatContainsIt() {
        let modes: [(String, FocusPart)] = [("单练 Part 3", .part3),
                                            ("Part 2 + Part 3", .part2And3),
                                            ("全真模考", .fullMock)]
        for (name, focus) in modes {
            let text = ExaminerPrompt.build(setup: setup(focusPart: focus))
            for line in ["- Never present a cue card, and never turn the discussion theme "
                            + "into a \"Describe …\" task.",
                         "- Never ask for a one-to-two-minute long turn.",
                         "- Never stay at Part 1 level — personal habits and simple preferences "
                            + "alone are not Part 3."] {
                XCTAssertTrue(text.contains(line),
                              "\(name) 的 Part 3 少了这条禁令「\(line)」：\n\(text)")
            }
        }
    }

    /// **禁令必须挂在各自的 Part 名下。**
    ///
    /// 三段禁令会同时出现在全真模考的提示词里（「不许出 cue card」与「必须出 cue card」
    /// 就在同一份文本里）。它们不打架的唯一依据，是每段开头那句「在 Part N 里不要…」。
    /// 把限定语去掉之后这条会红。
    func testTheNeverListsAreScopedToTheirOwnPartSoTheyCanCoexist() {
        let text = ExaminerPrompt.build(setup: setup(focusPart: .fullMock))
        for heading in ["Never do these in Part 1:", "Never do these in Part 2:",
                        "Never do these in the Part 3 discussion:"] {
            XCTAssertTrue(text.contains(heading),
                          "全真模考里缺了「\(heading)」这段限定过的禁令。"
                              + "没有 Part 名限定的话，「不许出 cue card」会和 Part 2 的"
                              + "「必须出 cue card」在同一份提示词里直接冲突：\n\(text)")
        }
        XCTAssertTrue(text.contains("Present one cue card."),
                      "全真模考里 Part 2 该出的那张 cue card 被禁令误伤了：\n\(text)")
    }

    // MARK: - 「这个 Part 到底是什么」——提示词此前最大的缺口
    //
    // 用户（考生本人）的原话：
    //   「我觉得如果你直接说 part three 的话，他可能自己也不知道雅思 part three 有哪些东西。
    //     你最好给他加点提示词，解释一下 part three 具体是什么。」
    // 在这之前，三段 section rules 只写了「做什么 / 不做什么」，一个字都没解释这个 Part 本身。

    /// **三个 Part 都要有一段「这是什么」。**
    ///
    /// 把 `part1Primer` / `part2Primer` / `part3Primer` 里任意一段从规则里摘掉，这条就红。
    func testEveryPartExplainsWhatThatPartActuallyIs() {
        let cases: [(String, String, String)] = [
            ("Part 1", part1Text(), "What Part 1 is:"),
            ("Part 2", ExaminerPrompt.build(setup: setup(focusPart: .part2)), "What Part 2 is:"),
            ("Part 3", part3OnlyText(), "What Part 3 is:")
        ]
        for (name, text, heading) in cases {
            XCTAssertTrue(text.contains(heading),
                          "\(name) 只有规则，没有一句话解释这个 Part 是什么。"
                              + "规则只能修剪一个已经存在的概念——模型脑子里那个概念长歪了，"
                              + "再多的 Never 也是在歪的东西上修剪：\n\(text)")
        }
    }

    /// **Part 3 那段说明必须点明「往上抽象一层、不谈考生个人经历」。**
    ///
    /// 这是 Part 3 与 Part 1 / Part 2 的唯一分界线。少了它，那段说明就只是复述规则。
    func testPart3PrimerSaysItGoesUpALevelAndIsNotAboutTheLearnersOwnLife() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("move it UP one level"),
                      "没说 Part 3 是把 Part 2 的话题往上抽象一层：\n\(text)")
        for expected in ["society", "causes and", "advantages and disadvantages"] {
            XCTAssertTrue(text.contains(expected),
                          "Part 3 的说明里没提到「\(expected)」这一维度：\n\(text)")
        }
        XCTAssertTrue(
            text.contains("personal habits and personal preferences "
                          + "belong to Part 1 and Part 2"),
            "没说清个人经历 / 个人习惯属于 Part 1、Part 2 而不是 Part 3——"
                + "这正是实测里第一句问偏的那条线：\n\(text)")
    }

    /// **反例必须标出「这是 Part 几的问法」，而不只是「不许这样」。**
    ///
    /// 只写「不许问个人经历题」是一句抽象的话；标明它属于哪个 Part，
    /// 模型才知道错在哪一个维度（层级不对，不是措辞不对），也才举得一反三。
    func testPart3PrimerLabelsEachCounterExampleWithThePartItBelongsTo() {
        let text = part3OnlyText()

        // 正例：真题形状，覆盖变化、原因/比较、影响这几类。
        for good in ["What makes an environmental law effective or ineffective?",
                     "How have shopping habits changed in your country over the last twenty years?",
                     "Why do some people prefer small local shops to large chain stores?"] {
            XCTAssertTrue(text.contains("✅ \"\(good)\""),
                          "Part 3 的说明里缺了这个正例「\(good)」：\n\(text)")
        }

        // 反例：三句都标明了出处，其中最后一句是用户真机里 ChatGPT 实际问出来的那一句。
        let labelled: [(String, String)] = [
            ("Describe a shop you like.", "PART 2"),
            ("Do you enjoy shopping?", "PART 1"),
            ("Do you often go to the shops near your home?", "PART 1"),
            ("Can you describe a place you enjoy spending time in?", "PART 1 / PART 2")
        ]
        for (bad, label) in labelled {
            guard let range = text.range(of: "❌ \"\(bad)\"") else {
                return XCTFail("Part 3 的说明里缺了这个反例「\(bad)」：\n\(text)")
            }
            let explanation = String(text[range.upperBound...].prefix(160))
            XCTAssertTrue(explanation.contains("that is a \(label)"),
                          "反例「\(bad)」没有标明它是 \(label) 的问法，"
                              + "模型只知道「不许这样」，不知道错在哪一层：\(explanation)")
        }
    }

    /// Part 1 / Part 2 的说明也要给正反例，反例同样标出处。短即可，但不能没有。
    func testPart1AndPart2PrimersAlsoGiveLabelledCounterExamples() {
        let part1 = part1Text()
        XCTAssertTrue(part1.contains("✅ \"Do you work, or are you a student?\""),
                      "Part 1 的说明缺正例：\n\(part1)")
        XCTAssertTrue(part1.contains("that is a PART 2 question"),
                      "Part 1 的说明里没有一个被标成 Part 2 问法的反例：\n\(part1)")
        XCTAssertTrue(part1.contains("that is a PART 3 question"),
                      "Part 1 的说明里没有一个被标成 Part 3 问法的反例：\n\(part1)")

        let part2 = ExaminerPrompt.build(setup: setup(focusPart: .part2))
        XCTAssertTrue(part2.contains("that is a PART 1 question"),
                      "Part 2 的说明里没有一个被标成 Part 1 问法的反例：\n\(part2)")
        XCTAssertTrue(part2.contains("that is a PART 3 question"),
                      "Part 2 的说明里没有一个被标成 Part 3 问法的反例：\n\(part2)")
    }

    /// **说明要跟着 Part 走。** 全真模考里三段都在；单练某一档时不该混进别的 Part 的说明——
    /// 单练 Part 3 的提示词里出现「What Part 2 is: … 给一张 cue card」，
    /// 正是上一次翻车的成因。
    func testPrimersAreScopedToThePartsThatActuallyRunInThisSession() {
        let part3Only = part3OnlyText()
        XCTAssertFalse(part3Only.contains("What Part 2 is:"),
                       "单练 Part 3 的提示词里混进了「Part 2 是什么」的说明：\n\(part3Only)")
        XCTAssertFalse(part3Only.contains("What Part 1 is:"),
                       "单练 Part 3 的提示词里混进了「Part 1 是什么」的说明：\n\(part3Only)")

        let mock = ExaminerPrompt.build(setup: setup(focusPart: .fullMock))
        for heading in ["What Part 1 is:", "What Part 2 is:", "What Part 3 is:"] {
            XCTAssertEqual(mock.components(separatedBy: heading).count - 1, 1,
                           "全真模考里「\(heading)」出现的次数不是 1 次。"
                               + "重复一遍等于让模型读两次同一段，缺一段等于那个 Part 没被解释。")
        }

        let both = part2And3Text()
        XCTAssertTrue(both.contains("What Part 2 is:") && both.contains("What Part 3 is:"),
                      "「Part 2 + Part 3」缺了其中一段说明：\n\(both)")
        XCTAssertFalse(both.contains("What Part 1 is:"),
                       "「Part 2 + Part 3」里混进了 Part 1 的说明——这一档没有 Part 1：\n\(both)")
    }

    // MARK: - 提问前自检
    //
    // 用户与 ChatGPT 一起给出的第三条修法：每次提问前默检——是否为英语、是否围绕主题、
    // 是否不是 Part 1/2 的问法、是否基于上一个回答；不符合就重写再问。

    /// **三个 Part 都要有自检段，且措辞各不相同。**
    func testEveryPartChecksItsQuestionBeforeAskingIt() {
        let cases: [(String, String, String)] = [
            ("Part 1", part1Text(), "Check before you speak (Part 1):"),
            ("Part 2", ExaminerPrompt.build(setup: setup(focusPart: .part2)),
             "Check before you speak (Part 2):"),
            ("Part 3", part3OnlyText(), "Check before you speak (Part 3):")
        ]
        for (name, text, heading) in cases {
            XCTAssertTrue(text.contains(heading),
                          "\(name) 没有提问前自检。禁令是读的时候生效的，自检是每次开口前生效的——"
                              + "长对话里模型早就滑离了开头那些约束：\n\(text)")
        }
    }

    /// **Part 3 的自检要逐条写死那四项，还要说清不合格就重写再问。**
    func testPart3SelfCheckSpellsOutAllFourChecksAndTheRewriteRule() {
        let text = part3OnlyText()
        for check in ["1. Is it in English?",
                      "2. Is it about the discussion theme of this session?",
                      "3. Is it a Part 3 question",
                      "4. Does it build on what the learner has just said?"] {
            XCTAssertTrue(text.contains(check), "Part 3 的自检缺了「\(check)」：\n\(text)")
        }
        XCTAssertTrue(text.contains("NOT a Part 1 question")
                        && text.contains("NOT a Part 2 \"Describe …\" task"),
                      "自检第三条没有反过来点名 Part 1 / Part 2 的问法，"
                          + "等于把最要紧的那一项写空了：\n\(text)")
        XCTAssertTrue(text.contains("Never say a question that fails one of these checks."),
                      "没说不合格就不许问出口：\n\(text)")
        XCTAssertTrue(text.contains("Fix it first, then ask."),
                      "没说不合格该怎么办（重写再问）：\n\(text)")
    }

    /// 第一问没有「上一个回答」可依据——不点破的话，自检第四条会在开场那一刻就自相矛盾。
    func testPart1AndPart3SelfChecksExemptTheVeryFirstQuestionFromTheFollowOnCheck() {
        for (name, text) in [("Part 1", part1Text()), ("Part 3", part3OnlyText())] {
            XCTAssertTrue(text.contains("does not apply to your very first question"),
                          "\(name) 的自检没有豁免第一问——开场那一刻第四条无从满足，"
                              + "一条自相矛盾的自检会被整段忽略：\n\(text)")
        }
    }

    /// 自检也要跟着 Part 走，别把 Part 2 的自检塞进单练 Part 3。
    func testSelfChecksAreScopedToThePartsThatActuallyRun() {
        let text = part3OnlyText()
        XCTAssertFalse(text.contains("Check before you speak (Part 2):"),
                       "单练 Part 3 里混进了 Part 2 的自检：\n\(text)")
        let mock = ExaminerPrompt.build(setup: setup(focusPart: .fullMock))
        for heading in ["Check before you speak (Part 1):", "Check before you speak (Part 2):",
                        "Check before you speak (Part 3):"] {
            XCTAssertTrue(mock.contains(heading), "全真模考缺了「\(heading)」：\n\(mock)")
        }
    }

    // MARK: - 主题行不再以 Describe 开头

    /// **单练 Part 3 时，那张卡的原句一个字都不许出现在提示词里。**
    ///
    /// 上一轮已经在题目块旁边写满了「这不是任务、不许当成 cue card」，
    /// 而实测第一句仍然是 `Can you describe a place you enjoy spending time in?`。
    /// 用户的判断：**`Describe` 摆在那儿本身就在诱导，旁边写「别念这句」没用。**
    ///
    /// 把 `DiscussionTheme.phrase` 换成 `{ $0 }`（原样返回），这条就红。
    func testPart3AloneNeverShowsTheRawDescribeSentence() {
        let text = part3OnlyText()
        XCTAssertFalse(text.contains("Describe a law on environmental protection"),
                       "题干原句还在提示词里。它就是一张 Part 2 的任务卡，"
                           + "写多少句否定都盖不住：\n\(text)")
        XCTAssertTrue(text.contains("Part 3 theme: a law on environmental protection"),
                      "话题本身必须还在，否则考官不知道讨论什么：\n\(text)")
    }

    /// 用户给的目标形状，逐字：`Part 3 theme: a shop or store you enjoy visiting`
    ///（原题干是 `Describe a shop/store you enjoy visiting`）。
    func testPart3ThemeLineMatchesTheShapeTheLearnerAskedFor() {
        let text = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p3-shop", part: 3,
                               topic: "Describe a shop/store you enjoy visiting",
                               prompt: "Describe a shop/store you enjoy visiting"),
            focusPart: .part3, durationMinutes: 6, goal: ""))
        XCTAssertTrue(text.contains("Part 3 theme: a shop or store you enjoy visiting"),
                      "主题行不是用户要的那一行：\n\(text)")
    }

    /// 题干空掉时退回话题名；两者都空时**明说主题没给出来并交代怎么办**，
    /// 不许留一行 `Part 3 theme:` 后面什么都没有（禁止静默失败）。
    func testPart3ThemeFallsBackToTheTopicAndThenSaysSoWhenNothingIsSupplied() {
        let onlyTopic = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p3-blank", part: 3, topic: "Shopping habits", prompt: "   "),
            focusPart: .part3, durationMinutes: 6, goal: ""))
        XCTAssertTrue(onlyTopic.contains("Part 3 theme: Shopping habits"),
                      "题干空掉时没有退回话题名：\n\(onlyTopic)")

        let nothing = ExaminerPrompt.build(setup: SessionSetup(
            question: Question(id: "p3-empty", part: 3, topic: "", prompt: ""),
            focusPart: .part3, durationMinutes: 6, goal: ""))
        XCTAssertFalse(nothing.contains("Part 3 theme: \n"),
                       "主题行空着就发出去了——考官会自己编一个话题，"
                           + "而用户挑的那道题一次都不会被问到：\n\(nothing)")
        XCTAssertTrue(nothing.contains("none was supplied"),
                      "主题缺失时没有明说缺失：\n\(nothing)")
        XCTAssertTrue(nothing.contains("ask the learner in English which"),
                      "主题缺失时没有交代考官下一步该怎么办：\n\(nothing)")
    }

    /// **「Part 2 + Part 3」与全真模考不能被这条改动误伤**：
    /// 那两档里那道题真的是一张 cue card，题干必须原样递过去。
    func testModesThatReallyRunPart2StillGetTheCueCardVerbatim() {
        for (name, text) in [("Part 2", ExaminerPrompt.build(setup: setup(focusPart: .part2))),
                             ("Part 2 + Part 3", part2And3Text()),
                             ("全真模考", ExaminerPrompt.build(setup: setup(focusPart: .fullMock)))] {
            XCTAssertTrue(text.contains("Describe a useful skill you learned"),
                          "\(name) 的 cue card 题干被改写了——那一档考生真的要照着它做长陈述：\n\(text)")
        }
    }

    // MARK: - Part 3 第一问必须是抽象讨论

    /// 单练 Part 3：起手规则不能只说「问它」，必须说「问到什么层级」。
    ///
    /// 原先写的是 "open with a question about it"，实测第一句就是
    /// `Can you describe a place you enjoy spending time in?`——完全合规，也完全不是 Part 3。
    func testPart3AloneMakesTheVeryFirstQuestionAbstract() {
        let text = part3OnlyText()
        XCTAssertTrue(text.contains("Your very first question must already be an abstract, "
                                    + "general, society-level"),
                      "起手规则没要求第一问就已经是抽象讨论：\n\(text)")
        XCTAssertTrue(text.contains("Do NOT warm up with a "
                                    + "personal question about the learner's own experience"),
                      "没禁止用一个个人经历问题「热身」——实测翻车的正是这一步：\n\(text)")
        XCTAssertFalse(text.contains("open with a question about it"),
                       "还留着那句只说「问它」不说层级的旧规则：\n\(text)")
    }

    /// 接在 Part 2 后面的那一支同样要说死：不然它会被做成「再追问一遍刚才那件事」，
    /// 那是 Part 2 的尾巴，不是 Part 3 的开头。
    func testPart3AfterPart2AlsoRequiresTheFirstQuestionToBeAboveThePersonalLevel() {
        for (name, text) in [("Part 2 + Part 3", part2And3Text()),
                             ("全真模考", ExaminerPrompt.build(setup: setup(focusPart: .fullMock)))] {
            XCTAssertTrue(
                text.contains("Your very first Part 3 question must already be above the "
                              + "personal level"),
                "\(name) 没要求 Part 3 的第一问已经高于个人层面：\n\(text)")
        }
    }

    /// **红线三：本次的复训目标不许提前告诉考生。**
    ///
    /// 说破了就不是考试了——学员会照着目标演，复盘拿到的不是他平时的样子。
    func testGoalIsKeptFromTheLearnerDuringTheExam() {
        for part in FocusPart.allCases {
            let text = ExaminerPrompt.build(setup: SessionSetup(
                question: question, focusPart: part, durationMinutes: 4, goal: "减少 filler words"))
            XCTAssertTrue(text.contains("考试过程中不要提及这个目标"),
                          "\(part) 把本次目标交给了考官却没说不许提——"
                              + "学员会照着目标演，复盘就失真了")
        }
    }
}
