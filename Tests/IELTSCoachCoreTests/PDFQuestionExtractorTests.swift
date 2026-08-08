import XCTest

@testable import IELTSCoachCore

/// 题库 PDF 的解析规则。
///
/// **测试数据全部照抄真实 PDF 里的片段**（2026-08-06 用 PDFKit 抽出全文后逐段看过），
/// 不是自己编一份好解析的——理想排版的样本会让解析器看着全绿、喂真文件时全崩。
final class PDFQuestionExtractorTests: XCTestCase {

    // MARK: - 目录必须被丢掉

    func testTableOfContentsIsDropped() throws {
        // 目录行的特征是点号引导。第二条目录项自己还折了行——
        // 只看「以数字结尾」会漏掉 "teacher) ......... 19" 这种。
        //
        // ⚠️ 计划给的原始样本里**没有**下面那两行带点号的分区标题，而那正是这条规则真正的
        // 用武之地：目录里的「Part1 必考题.......6」「Part2 & 3 保留题.......19」本身就是
        // 分区标题的形状。不丢掉它们，解析器在目录里就进了正文状态，
        // 整份目录会被当成题目提出来——实测真实 PDF：Part 2 从 99 张变成 198 张。
        // 而只用计划那份样本时，把「丢弃点号行」整条删掉，测试照样全绿（目录条目
        // 会被「还没进任何分区」这条兜住），也就是说那条规则一条测试都没守着。
        let text = """
        5-8 月雅思口语题库
        Part1 必考题.....................................................................................6
        Websites .................................................................................. 17
        1- Describe one of your friends who learned a skill from someone (not a
        teacher) ......................................................................................... 19
        Part2 & 3 保留题............................................................................19
        1- Describe a person who solved a problem in a smart way ....................... 20
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "题库", sourceUrl: "")
        XCTAssertEqual(result.questions.count, 1, "目录里的条目不能被当成题目")
        XCTAssertEqual(result.questions[0].topic, "Study and work")
    }

    // MARK: - 分区标题带字符间空格

    func testSectionHeadersWithInterCharacterSpacingAreRecognised() throws {
        // PDF 抽出来是「Part1 必 考 题」，汉字之间有空格。
        // 按原样匹配一个都对不上，必须先去掉全部空白再比。
        let text = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        Part2 & 3 保 留 题
        人物
        1-Describe a person who solved a problem in a smart way
        You should say
        Who this person is
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        XCTAssertEqual(result.questions.filter { $0.part == 1 }.count, 1)
        XCTAssertEqual(result.questions.filter { $0.part == 2 }.count, 1,
                       "没认出 Part2 分区标题的话，cue card 会被算进 Part 1")
    }

    // MARK: - 折行合并（本任务最核心的一条）

    func testWrappedCueCardTitleIsJoined() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Describe one of your friends who learned a skill from someone
        (not a teacher)
        You should say
        Who he/she is
        And explain whether it would be easier to learn from a teacher
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let part2 = result.questions.filter { $0.part == 2 }
        XCTAssertEqual(part2.count, 1, "折行的续行不能变成第二道题")
        XCTAssertTrue(part2[0].prompt.hasSuffix("(not a teacher)"),
                      "题干被截断了：\(part2[0].prompt)")
    }

    func testWrappedFollowupQuestionIsJoined() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Describe a person who solved a problem in a smart way
        You should say
        Who this person is
        Part3
        What are the main differences between learning from a formal teacher and
        learning from someone like a friend or family member?
        Is it necessary to continue learning after finishing formal education?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let part3 = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(part3.count, 2, "折行的追问应合成一条，不是两条")
        XCTAssertTrue(part3[0].prompt.contains("formal teacher and learning from someone"),
                      "折行处没有合并：\(part3[0].prompt)")
    }

    // MARK: - 折行合并：两处「续行以大写字母开头」
    //
    // 下面两条是 Step 5 拿真实 PDF 跑出来之后补的，片段是原文照抄（raw 第 681–683、780–783 行）。
    // 「续行一律以小写字母或标点开头」这条判据对 1276 道题里的 1269 道成立，剩下 7 道栽在这两种形状上，
    // 提出来的是「Olympics?」「Why?」这种没有上下文、根本没法拿来练的碎片。

    /// 上一行以冠词或 `as` 收尾时，续行哪怕以大写专有名词开头也仍是续行。
    ///
    /// 英语句子不可能停在 the / a / an / and / or / as / than 上。
    /// **这七个词是刻意选窄的**：`like` / `with` / `about` / `of` / `for` / `to` 都能合法收尾
    /// （「What it is like」「Who you were with」「What it is made of」全是 cue card 的提示点），
    /// 把它们算进来会把整张 cue card 的四条提示点粘成一条。
    func testACapitalisedContinuationAfterAnArticleIsStillJoined() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Describe a successful sportsperson you admire
        You should say
        Who this person is
        Part3
        Why are some sports more popular than others?
        What are the benefits of hosting major international sporting events like the
        Olympics?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let part3 = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(part3.count, 2, "「Olympics?」是上一行的后半截，不是第三道题")
        XCTAssertTrue(part3[1].prompt.hasSuffix("like the Olympics?"),
                      "题干断在冠词上了：\(part3[1].prompt)")
    }

    /// 光秃秃的「Why?」不可能是一道独立的题——它没有任何上下文，练的时候没法答。
    /// 它是上一问折行掉下来的尾巴。
    func testABareWhyTailIsJoinedToTheQuestionItBelongsTo() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Describe a person you know who runs a family business
        You should say
        What the business is
        Part3
        Do you think it's better to work for a large company or a small family business?
        Why?
        How can the government support small and family businesses?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let part3 = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(part3.count, 2, "「Why?」不是一道题，是上一问的尾巴")
        XCTAssertTrue(part3[0].prompt.hasSuffix("family business? Why?"),
                      "尾巴没接回去：\(part3[0].prompt)")
    }

    /// 上面两条的反面：cue card 的提示点大量以介词收尾（真实文件里满是
    /// 「What it was about」「Who you watched it with」），它们各自是完整的一条，
    /// **一条都不许被粘起来**。合并规则一旦放宽到「以介词结尾就接下一行」，
    /// 99 张 cue card 的提示点会成片消失。
    func testCueCardBulletsEndingInAStrandedPrepositionAreNotGluedTogether() throws {
        let text = """
        Part2 & 3 保 留 题
        事件
        1-Describe a film you watched that disappointed you
        You should say
        What it was about
        Why you decided to watch it
        Who you watched it with
        And explain why it disappointed you
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let cue = try XCTUnwrap(result.questions.first { $0.part == 2 })
        XCTAssertEqual(cue.followups, [
            "What it was about",
            "Why you decided to watch it",
            "Who you watched it with",
            "And explain why it disappointed you"
        ])
    }

    // MARK: - Part 2 的提示点与 Part 3 的归属

    func testCueCardBulletsGoToFollowupsAndPart3BecomesOwnQuestions() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Describe a person who solved a problem in a smart way
        You should say
        Who this person is
        What the problem was
        How he/she solved it
        And explain why you think he/she did it in a smart way
        Part3
        What are the qualities of a person who can solve problems in smart ways?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        let cue = try XCTUnwrap(result.questions.first { $0.part == 2 })
        XCTAssertEqual(cue.followups.count, 4, "You should say 下面四条提示点都要进 followups")
        XCTAssertEqual(cue.topic, "人物", "中文类别标签就是 Part 2 的话题")

        let part3 = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(part3.count, 1)
        XCTAssertTrue(part3[0].topic.contains("solved a problem"),
                      "Part 3 追问要能看出它跟着哪张 cue card，否则练的时候不知道上下文")
    }

    // MARK: - 噪声

    /// ⚠️ 这条断言原本写的是「题数等于 3」加「没有哪道题的 prompt 恰好是 `/` 或 `6`」，
    /// 那两条把 `/` 这一半漏空了：把「丢掉 `/`」整条规则删掉，`/` 并不会变成一道独立的题，
    /// 而是被折行合并器当成续行粘到上一句尾巴上，产出是
    /// 「Do you work or are you a student? /」——题数仍是 3，也没有哪道 prompt 恰好等于 `/`，
    /// 两条断言双双照绿。名字和注释都写着「分支分隔符 /」，实际只守住了页码那一半。
    ///
    /// 所以改成逐条比对完整的 prompt 列表：粘到句尾也好、单独成题也好，一律红。
    func testPageNumbersAndBranchSeparatorAreNotQuestions() throws {
        let text = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        /
        What work do you do?
        6
        Do you like your job?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        XCTAssertEqual(result.questions.map(\.prompt), [
            "Do you work or are you a student?",
            "What work do you do?",
            "Do you like your job?"
        ], "页码与分支分隔符 / 都不是题目，也不许被当成续行粘到上一道题的尾巴上")
    }

    // MARK: - 一道题都没提出来必须报警

    func testWarnsWhenNothingExtracted() throws {
        let result = try PDFQuestionExtractor.extract(
            plainText: "完全无关的一段文字", sourceTitle: "t", sourceUrl: "")
        XCTAssertTrue(result.questions.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty, "一道题都没提出来必须报警，不能静默返回空")
        XCTAssertTrue(result.warnings.joined().contains("下一步"), "警告必须说明下一步做什么")
    }

    // MARK: - 丢掉的东西必须有交代
    //
    // ⚠️ 下面两条是**实现写完之后补的**，不是先红后绿——它们覆盖的是计划没要求、
    // 我自己加的两条防线（铁律 7：禁止静默失败）。补测试是为了让这两条防线本身有约束力：
    // 把 warnings 清空，两条当场红。补的时间点如实写在这里，不假装是先写的。

    /// Part 2/3 区里的编号项若不是以 Describe / Talk about 开头，本实现认不出它是哪种题。
    /// **认不出可以，不吭声不行**——用户手里那份题库缺了几道题，他得知道去哪儿找。
    func testANumberedItemThatIsNotACueCardIsReportedInsteadOfSilentlyDropped() throws {
        let text = """
        Part2 & 3 保 留 题
        人物
        1-Tell me about a person who changed your life
        You should say
        Who this person is
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        XCTAssertTrue(result.questions.isEmpty)
        let joined = result.warnings.joined()
        XCTAssertTrue(joined.contains("Tell me about a person who changed your life"),
                      "认不出的那一条得指名道姓，否则用户没法去核对：" + joined)
        XCTAssertTrue(joined.contains("下一步"), joined)
    }

    /// 分区标题与第一道题之间、cue card 题干与 `You should say` 之间掉出来的行，同理。
    func testLinesThatFallOutsideAnyQuestionAreReported() throws {
        let text = """
        Part 1 T opics
        Part1 必 考 题
        This line arrives before any topic heading
        1-Study and work
        Do you work or are you a student?
        """
        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "t", sourceUrl: "")
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertTrue(result.warnings.joined().contains("1 行"),
                      "掉在题目之外的行数要说出来：\(result.warnings)")
        XCTAssertTrue(result.warnings.joined().contains("下一步"), "\(result.warnings)")
    }

    // MARK: - id 不随位置漂移
    //
    // ⚠️ 这条原先叫 `testIDsAreContentBasedSoInsertionDoesNotShiftThem`（「id 必须基于内容」），
    // 名不副实：它只问了「插入新话题之后 id 变没变」，而**常量 id 也满足这一条**。
    // 复审把 `QuestionBankImporter.questionID` 改成 `_ = (topic, prompt); return "p\(part)"`
    // （完全不看内容），全量测试 0 失败；拿真实那份 81 页 PDF 实测，1264 道题只剩 3 个不同的 id，
    // 经 `merge` 去重后题库塌成 3 道。
    //
    // 「内容不同 → id 必须不同」那一半现在由 `QuestionIDTests` 守（part / topic / prompt
    // 三个维度各自单独变、加上 merge 之后还剩几道题）。这里保留的是另一半：位置无关。
    // 名字按它真正测的东西改过了。

    func testInsertingANewTopicAboveDoesNotShiftTheIDsBelow() throws {
        let onlyHome = """
        Part 1 T opics
        Part1 必 考 题
        1-Accommodation
        Do you live in a house or a flat?
        """
        // 前面插入一个新话题后，原有题目的 id 不能变——
        // 否则换季重新导入会让历史练习记录全部指错题。
        let withNewTopicFirst = """
        Part 1 T opics
        Part1 必 考 题
        1-Brand new topic
        A brand new question?
        2-Accommodation
        Do you live in a house or a flat?
        """
        let first = try PDFQuestionExtractor.extract(
            plainText: onlyHome, sourceTitle: "t", sourceUrl: "")
        let second = try PDFQuestionExtractor.extract(
            plainText: withNewTopicFirst, sourceTitle: "t", sourceUrl: "")

        let originalID = try XCTUnwrap(first.questions.first?.id)
        let afterInsert = try XCTUnwrap(
            second.questions.first { $0.topic == "Accommodation" }?.id)
        XCTAssertEqual(originalID, afterInsert)
    }
}
