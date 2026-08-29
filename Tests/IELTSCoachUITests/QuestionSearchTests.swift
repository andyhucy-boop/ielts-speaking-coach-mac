import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 按关键词找题。题库 258 道，Part 2 一栏就有 99 条；
/// 在这之前**整个 App 一个文本输入框都没有**，只能一条条往下滑。
@MainActor
final class QuestionSearchTests: XCTestCase {

    private let bank = [
        TopicQuestions.part1(topic: "Borrowing",
                             prompts: ["Do you like to lend things to others?",
                                       "Have you ever borrowed money?"]),
        TopicQuestions.part1(topic: "Hometown", prompts: ["Where is your hometown?"]),
        Question(id: "p2-book", part: 2, topic: "Media",
                 prompt: "Describe a book you recently read.",
                 followups: ["what it is about"])
    ]

    func testItFindsByPrompt() {
        XCTAssertEqual(QuestionSearch.filter(bank, keyword: "book").map(\.id), ["p2-book"])
    }

    func testItFindsByTopic() {
        XCTAssertEqual(QuestionSearch.filter(bank, keyword: "hometown").map(\.topic), ["Hometown"])
    }

    /// **参考问句必须搜得到。** 题库重建模之后 Part 1 的题干就是话题名
    /// （「Borrowing」），而他记得的那句「Do you like to lend things to others?」
    /// 只存在于 `followups` 里——不搜它的话，他印象最深的那句话反而搜不到。
    func testItFindsByAReferenceQuestion() {
        XCTAssertEqual(QuestionSearch.filter(bank, keyword: "lend things").map(\.topic),
                       ["Borrowing"])
    }

    /// 中文没有大小写，英文题干里 `Borrowing` / `borrowing` 都得命中。
    func testItIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(QuestionSearch.filter(bank, keyword: "  BORROWING ").map(\.topic),
                       ["Borrowing"])
    }

    /// 关键词为空时**原样返回，连顺序都不动**：改一下搜索又清空，
    /// 列表顺序变了的话，他刚才看到的那一道就找不回来了。
    func testAnEmptyKeywordChangesNothing() {
        XCTAssertEqual(QuestionSearch.filter(bank, keyword: "   ").map(\.id), bank.map(\.id))
        XCTAssertNil(QuestionSearch.emptyNotice(keyword: "", searchedCount: 3))
    }

    /// 搜不到时要说清「搜的是什么、在多少道里搜的、下一步怎么办」。
    func testTheEmptyNoticeSaysWhatWasSearchedAndWhatToDo() throws {
        XCTAssertTrue(QuestionSearch.filter(bank, keyword: "quantum").isEmpty)
        let notice = try XCTUnwrap(QuestionSearch.emptyNotice(keyword: "quantum",
                                                              searchedCount: 258))
        XCTAssertTrue(notice.contains("quantum"), notice)
        XCTAssertTrue(notice.contains("258"), notice)
        XCTAssertTrue(notice.contains("下一步"), notice)
    }

    /// 提示语要给能照着打的东西。写「搜索」两个字的话，
    /// 一个不知道能搜什么的人不会去用它。
    func testThePlaceholderShowsWhatCanBeSearched() {
        XCTAssertTrue(QuestionSearch.placeholder.contains("例如"), QuestionSearch.placeholder)
    }

    /// **两处都得有这个框**：题库页浏览用，开练弹层挑题用（那里更难受——
    /// 一个很矮的小窗口里平铺滑 99 行）。只加一处的话，另一处的人照样在滑。
    func testBothQuestionListsHaveASearchField() throws {
        for file in ["QuestionBank/QuestionBankView.swift", "Session/PracticeSheet.swift"] {
            let code = try SourceGuard.code(file)
            XCTAssertTrue(code.contains("TextField(QuestionSearch.placeholder, text: $keyword)"),
                          "\(file) 里没有那个搜索框")
            XCTAssertTrue(code.contains("QuestionSearch.filter("),
                          "\(file) 有搜索框却没有真的拿它去筛——打得进字、列表纹丝不动")
        }
    }
}
