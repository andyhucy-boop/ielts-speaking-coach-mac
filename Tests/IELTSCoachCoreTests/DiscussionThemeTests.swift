import XCTest
@testable import IELTSCoachCore

/// `DiscussionTheme.phrase` —— 把 cue card 的题干改写成一句话题短语。
///
/// 这是纯字符串处理，所以每一条断言都能钉死具体的输入输出。
/// 它守的那件事在提示词那一侧（`ExaminerPromptTests` 的
/// `testPart3AloneNeverShowsTheRawDescribeSentence`）：**单练 Part 3 时，
/// 那张 Part 2 卡的原句一个字都不许出现在提示词里。**
final class DiscussionThemeTests: XCTestCase {

    // MARK: - 用户给的那两个真实例子

    /// 用户实测当天那张卡，以及他自己写出来的目标形状。
    func testTurnsTheLearnersOwnExampleIntoTheShapeHeAskedFor() {
        XCTAssertEqual(
            DiscussionTheme.phrase(fromCueCard: "Describe a shop/store you enjoy visiting"),
            "a shop or store you enjoy visiting")
    }

    /// 题库里 Part 3 那一组题真实的题干形状。
    func testStripsTheLeadingDescribeFromARealBankPrompt() {
        XCTAssertEqual(
            DiscussionTheme.phrase(fromCueCard: "Describe a law on environmental protection"),
            "a law on environmental protection")
    }

    // MARK: - 砍动词

    func testStripsEveryTaskVerbCueCardsActuallyUse() {
        let cases = [
            "Describe an important decision you made": "an important decision you made",
            "Talk about the best holiday you have had": "the best holiday you have had",
            "Tell me about someone you admire": "someone you admire"
        ]
        for (input, expected) in cases {
            XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: input), expected, "输入：\(input)")
        }
    }

    /// 大小写不该影响砍动词——PDF 抽出来的题干什么写法都有。
    func testMatchesTheTaskVerbCaseInsensitively() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "DESCRIBE a place you often visit"),
                       "a place you often visit")
    }

    /// **动词后面必须真的断开才算。** 否则 `Describes` 这种词会被砍成 `s`，
    /// 主题行直接变成一个字母。
    func testDoesNotStripAWordThatMerelyStartsWithATaskVerb() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describes of daily life in the city"),
                       "Describes of daily life in the city")
    }

    // MARK: - 砍 You should say 那条尾巴

    /// 这条尾巴比 `Describe` 更像任务书，逐字念出去就是一张完整的卡。
    func testCutsOffTheYouShouldSayTail() {
        XCTAssertEqual(
            DiscussionTheme.phrase(fromCueCard:
                "Describe a book you recently read. You should say what the book was, "
                + "what it was about, and explain how you felt about it."),
            "a book you recently read")
    }

    /// 尾巴前面什么都不剩时保留原文——空主题比一句啰嗦的主题糟糕得多。
    func testKeepsTheTextWhenCuttingTheTailWouldLeaveNothing() {
        let input = "You should say what it is and why you like it"
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: input), input)
    }

    // MARK: - 斜杠

    /// `shop/store` 读出来是「shop 斜杠 store」，改写成 `or`。
    func testSpellsOutASlashBetweenTwoWords() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe a film/movie you enjoyed"),
                       "a film or movie you enjoyed")
    }

    /// **数字两边的斜杠不动。** `24/7` 是一个固定说法，拆开就不是那个意思了。
    func testLeavesSlashesAloneWhenTheyAreNotBetweenTwoLetters() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe a shop that is open 24/7"),
                       "a shop that is open 24/7")
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe a job / a career you want"),
                       "a job / a career you want")
    }

    // MARK: - 首字母

    func testLowercasesTheOpenerOnlyWhenItIsAFunctionWord() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe An unusual meal you had"),
                       "an unusual meal you had")
        // 白名单之外一律保留原样：把专有名词小写掉，比留一个大写首字母糟糕。
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe London in three sentences"),
                       "London in three sentences")
    }

    // MARK: - 兜底

    /// **不以任务动词开头就原样返回。** 题库里 Part 1 的话题是
    /// `Borrowing and lending` 这种名词短语，本来就不需要改写。
    func testLeavesATopicPhraseUntouched() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Borrowing and lending"),
                       "Borrowing and lending")
    }

    func testTrimsSurroundingWhitespaceAndOneTrailingPeriod() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "  Describe a rule at your school.  "),
                       "a rule at your school")
    }

    /// **空输入返回空串，不编一个假话题出来。** 兜底由调用方负责
    ///（`ExaminerPrompt.part3Theme` 会退回话题名，再退到「明说没给主题」）。
    func testReturnsAnEmptyStringForBlankInputInsteadOfInventingATheme() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: ""), "")
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "   \n  "), "")
    }

    /// 题干整句就是一个动词时也不许返回空串。
    func testKeepsTheTextWhenItIsNothingButTheTaskVerb() {
        XCTAssertEqual(DiscussionTheme.phrase(fromCueCard: "Describe"), "Describe")
    }
}
