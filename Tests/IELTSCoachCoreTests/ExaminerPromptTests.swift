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
    func testPart3PacingFollowsTheRealExam() {
        // 特意不给 followups：抬头那一栏就不会出现，
        // 于是这条断言只可能命中 section rules 本身。
        let text = part3Text()
        XCTAssertTrue(text.contains("Ask 4–8 questions in total."), "没说共问 4–8 个：\n\(text)")
        XCTAssertTrue(text.contains("more abstract, general level"),
                      "没要求从 Part 2 的话题往抽象层面延伸：\n\(text)")
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
