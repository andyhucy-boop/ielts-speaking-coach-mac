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
    /// 不断言两条的先后顺序：R4 规定「匹配不上就插在游标当前位置」，
    /// 这里游标停在 0，所以后来的那条排在前面。这是 R4 的直接后果，
    /// 而顺序不是本条测试要守的东西，钉死它只会把无关行为焊进测试。
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

    func testANewMessageArrivingBetweenTwoKnownOnesKeepsTheOrder() {
        // 采样漏掉过中间那条（界面正好在重绘），下一次又读到了。
        // 它必须回到它本来的位置，不能被追加到最后。
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?"), learner("Answer one.")], at: t1)
        assembler.ingest([examiner("Question one?"),
                          learner("Answer one."),
                          examiner("Question two?")], at: t2)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Question two?"])
    }
}
