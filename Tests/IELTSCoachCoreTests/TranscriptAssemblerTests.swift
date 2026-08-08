import XCTest
@testable import IELTSCoachCore

final class TranscriptAssemblerTests: XCTestCase {
    private let t1 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
    private let t2 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:03Z")!
    private let t3 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:06Z")!

    private func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }
    private func unknown(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .unknown, text: text)
    }

    // MARK: - 情况一：片段递增（流式输出）

    /// 同一条消息越来越长，最后只能留一条，且是最长的那个版本。
    func testAGrowingMessageKeepsOnlyItsLongestVersion() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live")], at: t1)
        assembler.ingest([examiner("Do you live in a house")], at: t2)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)

        XCTAssertEqual(assembler.turns.count, 1, "同一条消息的十几个版本必须收敛成一条")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
        XCTAssertEqual(assembler.turns[0].role, "assistant")
    }

    /// capturedAt 记的是这条消息**第一次出现**的时刻，不是最后一次采到它的时刻。
    /// 记成最后一次的话，一条说了三十秒的长回答会显示成它说完的那一刻。
    func testCapturedAtIsWhenTheMessageFirstAppeared() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live")], at: t1)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)

        let expected = ISO8601DateFormatter().string(from: t1)
        XCTAssertEqual(assembler.turns[0].capturedAt, expected)
    }

    // MARK: - 情况二：片段乱序到达

    /// 采样是在后台按节拍跑的，一次慢一点的采样完全可能在更晚的那次之后才并进来。
    /// 迟到的旧版本**不许把已经拼好的内容缩回去**。
    func testALateArrivingEarlierSampleDoesNotShrinkWhatWeAlreadyHave() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)
        assembler.ingest([examiner("Do you live")], at: t1)   // 迟到的早期采样

        XCTAssertEqual(assembler.turns.count, 1, "迟到的旧片段不能变成第二条")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// 迟到的旧采样带着更早的时间戳，capturedAt 要跟着往前修正。
    func testALateArrivingEarlierSampleCorrectsTheTimestampBackwards() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)
        assembler.ingest([examiner("Do you live")], at: t1)

        XCTAssertEqual(assembler.turns[0].capturedAt, ISO8601DateFormatter().string(from: t1))
    }

    // MARK: - 情况三：完全重复的片段

    /// 界面十秒没动，采样了五次，读到的是一模一样的东西。不能堆出五条。
    func testIdenticalFragmentsNeverPileUp() {
        var assembler = TranscriptAssembler()
        for _ in 0..<5 {
            assembler.ingest([examiner("Do you live in a house or a flat?"),
                              learner("I live in a flat with my parents.")], at: t1)
        }
        XCTAssertEqual(assembler.turns.count, 2)
        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Do you live in a house or a flat?",
                        "I live in a flat with my parents."])
    }

    /// 空白与换行的差异不算差异——AX 读回来的文本会带各种换行与缩进。
    func testWhitespaceOnlyDifferencesAreNotTreatedAsNewMessages() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house?")], at: t1)
        assembler.ingest([examiner("  Do you   live in a\n house?  ")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1)
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house?")
    }

    // MARK: - 情况四：消息边界（两条不同消息恰好前缀相同）

    /// **本任务最关键的一条。** 考官先问一句，没听清时又把同一句重问一遍并追加追问——
    /// 后一条以前一条为**严格前缀**。它们在**同一次采样**里同时出现，
    /// 就是两条不同的消息，绝不能合并成一条。
    /// 合并的后果是逐字稿里少了一个考官问过的问题，直接违反成品标准第 5 条。
    ///
    /// **测试数据与计划原稿不同，是实现者刻意改的**（Step 5 突变验证中发现）：
    /// 计划原稿用的是「Do you live in a house?」与「Do you live in a house or a flat?」，
    /// 并称后者以前者为前缀——**其实不是**，前者结尾的 `?` 在后者的对应位置是空格，
    /// `hasPrefix` 返回 false。两条字符串根本进不了 `canMerge` 的合并分支，
    /// 于是这条测试和下面那条无论 R1 在不在都是绿的（已实测）。
    /// 换成真正构成前缀的一对，两条测试才真的在守 R1。
    func testTwoMessagesThatSharePrefixStayTwoMessages() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?"),
                          examiner("Do you live in a house or a flat? Tell me a bit more.")],
                         at: t1)

        XCTAssertEqual(assembler.turns.count, 2, "同一次采样里的两个片段永远是两条消息")
        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Do you live in a house or a flat?",
                        "Do you live in a house or a flat? Tell me a bit more."])
    }

    /// 边界稳定：再采几次，仍然是两条，不会因为反复并入而互相吞掉。
    ///
    /// **这里必须连文本一起断言，只数条数是不够的**（实现者在 Step 5 突变验证中实测发现）：
    /// 把 `matchIndex` 的 `for index in cursor..<slots.count` 改成 `0..<slots.count`（即废掉 R1），
    /// 第二次采样时后一条会倒回去并进前一条的槽位，结果是**两条槽位装着同一句话**——
    /// 条数仍然是 2，只数条数的断言全绿，而短的那个问题已经从逐字稿里消失了，
    /// 正是成品标准第 5 条要挡的事故。
    ///
    /// 计划原稿的数据构不成前缀（见上一条测试的说明），这里同样换成真正的前缀对。
    /// 单次采样的场景其实咬不住这个突变——`matchIndex` 开头的
    /// `guard cursor < slots.count` 会先一步返回 nil；**跨采样才是 R1 真正的战场**。
    func testThePrefixBoundaryHoldsAcrossRepeatedSamples() {
        var assembler = TranscriptAssembler()
        for timestamp in [t1, t2, t3] {
            assembler.ingest([examiner("Do you live in a house or a flat?"),
                              examiner("Do you live in a house or a flat? Tell me a bit more.")],
                             at: timestamp)
        }
        XCTAssertEqual(assembler.turns.count, 2)
        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Do you live in a house or a flat?",
                        "Do you live in a house or a flat? Tell me a bit more."],
                       "短的那条不能被长的那条覆盖掉——那等于逐字稿里少了一个考官问过的问题")
    }

    /// **实现者按复审意见补的一条（计划里没有）。**
    ///
    /// `canMerge` 最后那行文本判据（两段文本必须互为前缀）原本没有任何测试守着：
    /// 把它整行改成 `return true`（只剩说话人判断），原有 21 条测试全绿（复审已实测）。
    ///
    /// 而这一行正是 R2 成立的前提——`merge` 敢拿「更长的那条」整句换掉短的那条，
    /// 靠的就是「两者必有一个是另一个的前缀，所以更长就等于内容更全」。
    /// 判据一没，两条毫不相干的消息只要说话人兼容就会并进同一个槽位，
    /// 长的那条把短的那条整句盖掉：逐字稿里凭空少一条考官问过的问题，
    /// 而且没有任何信号——正是成品标准第 5 条要挡的事故。
    ///
    /// 场景必须是**跨采样、且这一次没读到前面那条**才咬得住：
    /// 同一次采样里两条都在时，R1 的游标已经走过前一个槽位，
    /// 文本判据在不在都不影响结果（实现者实测确认）。
    ///
    /// 不断言两条的先后顺序：顺序归 R4 管，由
    /// `testAMessageThatMatchesNothingIsAppendedAtTheEnd` 那几条守着。
    /// 本条只守 `canMerge` 的文本判据，两件事分开测，坏了才看得出是哪件坏了。
    func testTwoUnrelatedMessagesFromTheSameSpeakerNeverMergeIntoOneTurn() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Where do you live?")], at: t1)
        // 界面正好在重绘，这一次只读到了考官新问的那一句
        assembler.ingest([examiner("What do you do in your free time?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 2, "毫不相干的两句话不能并进同一个槽位")
        XCTAssertEqual(Set(assembler.turns.map(\.text)),
                       ["Where do you live?", "What do you do in your free time?"],
                       "两句话都必须在——长的那条不能把短的那条整句盖掉")
    }

    // MARK: - 情况五：说话人切换

    func testExaminerAndLearnerNeverMergeIntoOneTurn() {
        var assembler = TranscriptAssembler()
        // 学员复述了考官的问题开头——文本兼容，但说话人不同，绝不能并成一条
        assembler.ingest([examiner("Do you live in a house or a flat?"),
                          learner("Do you live")], at: t1)

        XCTAssertEqual(assembler.turns.count, 2)
        XCTAssertEqual(assembler.turns.map(\.role), ["assistant", "user"])
    }

    /// **实现者补充的一条（计划里没有）。**
    ///
    /// 上面那条测试其实咬不住 `canMerge` 里的说话人判断：两个片段来自**同一次**采样，
    /// R1 的游标已经走过第一个槽位，第二个片段无论说话人是谁都只能新开槽位。
    /// 把 `guard speakerOK else { return false }` 整行删掉，上面那条照样绿
    /// （已在 Step 5 突变验证里实测确认）。
    ///
    /// 这一条让说话人判断真的被守住：**跨采样**时，同样的文字从另一个说话人嘴里出来，
    /// 必须是两条，不能并进考官那一条里去。
    /// 合并的后果正是 `TranscriptSpeaker` 注释里点名的那种最坏情况——
    /// 复训时「回看自己说过的话」显示成考官说的话，且没有任何信号提示。
    ///
    /// 不断言两条的先后顺序：顺序归 R4 管，由
    /// `testAMessageThatMatchesNothingIsAppendedAtTheEnd` 那几条守着。
    /// 本条只守 `canMerge` 的说话人判断，两件事分开测。
    func testTheSameSentenceFromTheOtherSpeakerNeverMergesIntoAnExistingTurn() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.ingest([learner("Do you live in a house or a flat?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 2, "说话人不同就是两条，哪怕一字不差")
        XCTAssertEqual(Set(assembler.turns.map(\.role)), ["assistant", "user"])
    }

    /// 正在流式输出的那条消息，界面上还没出现复制按钮，采样时判不出是谁说的。
    /// 等它说完、按钮出现了，同一条消息就要**升级**成已知说话人，
    /// 而不是变成第二条 role 不同的记录。
    func testAnUnattributedFragmentIsUpgradedWhenTheSpeakerBecomesKnown() {
        var assembler = TranscriptAssembler()
        assembler.ingest([unknown("Do you live in a")], at: t1)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1, "判出说话人不能让同一条消息变成两条")
        XCTAssertEqual(assembler.turns[0].role, "assistant")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// 反过来不行：已经判定是考官说的，后面一次采样判不出来，不能把它降级回 unknown。
    func testAKnownSpeakerIsNeverDowngradedBackToUnknown() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.ingest([unknown("Do you live in a house or a flat?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1)
        XCTAssertEqual(assembler.turns[0].role, "assistant")
    }

    // MARK: - 情况六：采样中途失败（不得中断练习）

    /// 采样失败只记账，已经拼好的内容一个字都不许丢，
    /// 而且**必须在练完之后如实告诉用户**——静默地少几分钟对话是本项目最忌讳的失败形态。
    func testSamplingFailuresAreRecordedWithoutLosingAnything() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.noteSamplingFailure("没能读到 ChatGPT 的界面内容")
        assembler.noteSamplingFailure("ChatGPT 窗口被切走了")
        assembler.ingest([learner("I live in a flat.")], at: t3)

        XCTAssertEqual(assembler.turns.count, 2, "失败前后采到的内容都要在")
        XCTAssertEqual(assembler.samplingFailureCount, 2)
        XCTAssertEqual(assembler.lastSamplingFailure, "ChatGPT 窗口被切走了")
    }

    func testTheCompletenessNoteSaysWhatHappenedAndWhatToDoNext() throws {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.noteSamplingFailure("没能读到 ChatGPT 的界面内容")

        let note = try XCTUnwrap(assembler.completenessNote, "有失败就必须有说明")
        XCTAssertTrue(note.contains("1 次"), "要说清失败了几次")
        XCTAssertTrue(note.contains("没能读到 ChatGPT 的界面内容"), "要带上最后一次的原因")
        XCTAssertTrue(note.contains("下一步"), "必须告诉用户下一步做什么")
        XCTAssertTrue(note.contains("练习本身"), "必须说明练习和复盘没受影响，别让用户白担心")
    }

    func testNoNoiseWhenEverythingWentFine() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?"),
                          learner("I live in a flat.")], at: t1)
        XCTAssertNil(assembler.completenessNote, "一切正常时不要弹一句没用的提示")
    }

    func testUnattributedTurnsAreAlsoReportedAsIncomplete() throws {
        var assembler = TranscriptAssembler()
        assembler.ingest([unknown("Do you live in a house or a flat?")], at: t1)

        let note = try XCTUnwrap(assembler.completenessNote)
        XCTAssertTrue(note.contains("没能判断"), "判不出谁说的也要如实说，不能装作正常")
        XCTAssertEqual(assembler.unknownSpeakerCount, 1)
        XCTAssertEqual(assembler.turns[0].role, "unknown")
    }

    // MARK: - 背景板：练习开始那一刻屏幕上已经有的东西

    /// 考官提示词是一条两千字符的用户消息，会以几十个碎片一直挂在树上；
    /// 侧边栏会话名、按钮说明也一样。它们不属于本次对话。
    func testWhatWasAlreadyOnScreenIsNotPartOfTheTranscript() {
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([learner("You will act as an IELTS Speaking examiner."),
                                unknown("New chat"),
                                learner("Today's question (Part 1, topic: Home):")])
        assembler.ingest([learner("You will act as an IELTS Speaking examiner."),
                          unknown("New chat"),
                          learner("Today's question (Part 1, topic: Home):"),
                          examiner("Do you live in a house or a flat?")], at: t1)

        XCTAssertEqual(assembler.turns.count, 1, "背景板不算对话")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// **成品标准第 5 条的守卫，也是本任务最容易想不到的一条。**
    ///
    /// 今天要练的题干**本身就写在考官提示词里**，考官问出口时说的就是那句话。
    /// 如果按「内容出现过就滤掉」来过滤背景板，这个问题会从逐字稿里凭空消失——
    /// 而它恰恰是整场练习的第一个问题。
    ///
    /// 靠的是 R1：游标已经走过背景板那几个槽位，后面同样的文字只能新开槽位。
    /// 这里刻意用 unknown 说话人，因为万一说话人判别整个失效，这条防线也必须还在。
    ///
    /// **采样分两次、让考官那句话流式长出来，是实现者刻意加的**（Step 5 突变验证中发现）：
    /// 只采一次的话，`matchIndex` 开头的 `guard cursor < slots.count` 会先一步返回 nil，
    /// 于是把 `for index in cursor..<slots.count` 改成 `0..<slots.count`（废掉 R1）
    /// 这条测试照样绿——计划原稿点名它守 R1，其实没咬住。
    /// 采第二次时游标停在最后一个槽位之前，倒回去找才会把这句话并进背景板槽位里，
    /// 逐字稿里就只剩半句题干。
    func testTheExaminerAskingTheQuestionThatWasAlsoInThePromptStillShowsUp() {
        let question = "Describe a place you like to visit."
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([unknown("Today's question (Part 2, topic: Places):"),
                                unknown(question)])
        // 考官刚开口，题干才念出半句（流式输出）
        assembler.ingest([unknown("Today's question (Part 2, topic: Places):"),
                          unknown(question),
                          unknown("Describe a place")], at: t1)
        // 这句念完了
        assembler.ingest([unknown("Today's question (Part 2, topic: Places):"),
                          unknown(question),
                          unknown(question)], at: t2)

        XCTAssertEqual(assembler.turns.count, 1,
                       "考官把题干问出口时，必须作为一条新对话出现在逐字稿里")
        XCTAssertEqual(assembler.turns[0].text, question,
                       "这句话必须长全，不能被背景板槽位吃掉、只在逐字稿里留下半句")
    }

    func testBaselineFragmentsThatKeepGrowingStayHidden() {
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([learner("You will act as an IELTS")])
        assembler.ingest([learner("You will act as an IELTS Speaking examiner.")], at: t1)

        XCTAssertTrue(assembler.turns.isEmpty, "背景板长长了还是背景板")
    }

    // MARK: - 杂项

    func testBlankFragmentsAreDropped() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("   "), examiner("\n\n"), examiner("Hello?")], at: t1)
        XCTAssertEqual(assembler.turns.map(\.text), ["Hello?"])
    }

    /// R4：匹配不上就新开槽位，**插在游标当前位置**，而不是一律追加到末尾。
    ///
    /// 采样漏掉过中间那条（界面正好在重绘），下一次又读到了——
    /// 它必须回到它本来的位置。
    ///
    /// **测试数据与计划原稿不同，是实现者按复审意见改的。**
    /// 计划原稿第二次采样读到的新消息（"Question two?"）本来就在最末尾，
    /// 「插在游标当前位置」和「追加到末尾」得到的结果一模一样——
    /// 把 `let insertion = min(cursor, slots.count)` 改成 `let insertion = slots.count`
    /// （即退化成一律追加）原稿照样绿（复审已实测）。名字写着守 R4，其实没咬住。
    /// 改成「漏掉的是中间那条」，游标停在中间，两种实现才分得开。
    func testANewMessageArrivingBetweenTwoKnownOnesKeepsTheOrder() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?"), learner("Answer one.")], at: t1)
        // 这一次读全了：考官问完之后还补了一句，上一次采样正好没读到
        assembler.ingest([examiner("Question one?"),
                          examiner("Take your time."),
                          learner("Answer one.")], at: t2)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Take your time.", "Answer one."],
                       "补读到的那条要回到它本来的位置，不能被追加到最后")
    }

    /// R4 情形二：这一次采样**一条已有消息都没对上**，读到的是刚冒出来的最新那条。
    ///
    /// 这是真实常态而不是边缘情况：ChatGPT 的对话区随内容变长而滚动，
    /// 早先的消息滚出可视区后 AX 树里就读不到了，一次采样只读到最新一条太正常了。
    func testAMessageThatMatchesNothingIsAppendedAtTheEnd() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?"), learner("Answer one.")], at: t1)
        // 对话区滚动了，这一次只读到考官新问的那一句
        assembler.ingest([examiner("Question two?")], at: t2)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Question two?"],
                       "逐字稿的顺序就是这场练习的顺序：新问的那句绝不能跑到最前面")
    }

    /// R4 情形二续：连着几次都只读到最新那条，顺序仍然是练习本来的顺序。
    ///
    /// 一场练习里对话区一直在往下滚，「只读到尾巴」会连着发生很多次。
    /// 只测一次的话，「每次都插到最前面」会把整份逐字稿倒过来而测不出来。
    func testConsecutiveTailOnlySamplesKeepAppendingInOrder() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?")], at: t1)
        assembler.ingest([learner("Answer one.")], at: t2)
        assembler.ingest([examiner("Question two?")], at: t3)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Question two?"],
                       "逐字稿是追加式的：后说的话永远排在先说的话后面")
    }

    /// R4 情形三：这一次只读到对话中间的一段，中间那段里还夹着一条没见过的消息。
    ///
    /// 界面往下滚之后，开头那条已经读不到了；这一次读到的是「中间一段」，
    /// 新消息要落在这一段内部它本来的位置，既不许跑到最前面，也不许被甩到最后面。
    func testANewMessageInsideAMidConversationSampleLandsWhereItBelongs() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?"),
                          learner("Answer one."),
                          examiner("Question two?")], at: t1)
        // 开头那条滚出可视区了，这一次读到的是中间一段，里面多出一句没见过的
        assembler.ingest([learner("Answer one."),
                          examiner("Take your time."),
                          examiner("Question two?")], at: t2)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Take your time.", "Question two?"],
                       "夹在中间读到的新消息要落在它本来的位置")
    }

    /// R4 情形四：界面往回滚了，这一次读到的是**更早**的内容。
    ///
    /// 真实来路：考官问出第一句时正好赶上一次采样失败（R5 只记账不抛错），
    /// 等采样恢复，那句已经滚出可视区，逐字稿里只剩学员的回答和后面的问题。
    /// 学员往回滚去重看题目，这一次采样就读到了那句从没记下来的提问——
    /// 它必须回到它本来的位置（学员回答**之前**），不能因为「刚读到」就当成最新的追加到末尾。
    func testScrollingBackRevealsAnEarlierMessageThatGoesBeforeWhatWeAlreadyHave() {
        var assembler = TranscriptAssembler()
        // 采样失败的那几秒里考官问的话没记下来，逐字稿是从学员的回答开始的
        assembler.ingest([learner("Answer one."), examiner("Question two?")], at: t2)
        // 往回滚，读到了那句一直没记下来的提问
        assembler.ingest([examiner("Question one?"), learner("Answer one.")], at: t3)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Question two?"],
                       "往回滚补读到的更早内容要插在它后面那条之前，不能追加到末尾")
    }

    /// 背景板里的 unknown **不算**「没能判断是谁说的」。
    ///
    /// 真实采样里背景板几乎全是 unknown（考官提示词、侧边栏会话名、按钮说明，
    /// 它们下面都没有那个用来判别说话人的复制按钮）。这些东西根本不进逐字稿，
    /// 把它们数进来的后果是「狼来了」：每一场练完都被告知逐字稿可能不完整，
    /// 用户看几次发现没事就再也不看这句提示了，等真出问题时它已经失效了。
    func testBaselineNoiseIsNotCountedAsUnattributedTurns() {
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([unknown("New chat"),
                                unknown("Today's question (Part 1, topic: Home):"),
                                unknown("Send message")])
        assembler.ingest([unknown("New chat"),
                          unknown("Today's question (Part 1, topic: Home):"),
                          unknown("Send message"),
                          examiner("Do you live in a house or a flat?")], at: t1)

        XCTAssertEqual(assembler.unknownSpeakerCount, 0,
                       "背景板不进逐字稿，也就谈不上「没能判断是谁说的」")
        XCTAssertNil(assembler.completenessNote,
                     "一切正常时不许因为背景板全是 unknown 就报一句假警")
    }
}
