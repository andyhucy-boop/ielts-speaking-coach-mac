import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachMCP

/// **列题库**。在这之前这个 MCP 服务一个题号都吐不出来，
/// 而 `set_training_selection` 的 questionId 是必填——两句「下一步」互相指着对方，
/// 模型只能反过来叫用户打开 App 自己抄一串题号过来。
final class ListQuestionBankToolTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        opener = FakeDashboardOpener()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func seed(_ questions: [Question]) throws {
        try StateStore(directory: directory).mutate { $0.questions = questions }
    }

    /// **走一遍真实的协议层**（`ServerHarness`），不是直接调 `tool.run`：
    /// 直接调会漏掉 tools/call 的参数校验，而那部分同样会在真机上出事。
    private func call(_ arguments: [String: JSONValue]) throws -> String {
        let harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                                  opener: opener))
        return try harness.callTool("list_question_bank", arguments).text
    }

    /// 参数被协议层判错时，`callTool` 返回的是 isError。
    private func callExpectingError(_ arguments: [String: JSONValue]) throws -> Bool {
        let harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                                  opener: opener))
        return try harness.callTool("list_question_bank", arguments).isError
    }

    private var bank: [Question] {
        [TopicQuestions.part1(topic: "Borrowing",
                              prompts: ["Do you like to lend things to others?"]),
         TopicQuestions.part1(topic: "Hometown", prompts: ["Where is your hometown?"]),
         Question(id: "p2-book", part: 2, topic: "Media",
                  prompt: "Describe a book you recently read.", status: "practiced")]
    }

    func testItReturnsQuestionIdsThatSetTrainingSelectionCanUse() throws {
        try seed(bank)
        let text = try call([:])
        XCTAssertTrue(text.contains("p2-book"), text)
        XCTAssertTrue(text.contains("set_training_selection"),
                      "没说清拿到题号之后该做什么（铁律 6）：\(text)")
    }

    func testItFiltersByPart() throws {
        try seed(bank)
        let text = try call(["part": .number(2)])
        XCTAssertTrue(text.contains("p2-book"))
        XCTAssertFalse(text.contains("Hometown"), text)
    }

    /// 关键词要能搜到**参考问句**：Part 1 的题干就是话题名（「Borrowing」），
    /// 他记得的那句话只存在于 followups 里。
    func testItSearchesReferenceQuestionsToo() throws {
        try seed(bank)
        let text = try call(["search": .string("lend things")])
        XCTAssertTrue(text.contains("Borrowing"), text)
        XCTAssertFalse(text.contains("Hometown"), text)
    }

    func testItCanShowOnlyTheUnpracticedOnes() throws {
        try seed(bank)
        let text = try call(["onlyUnpracticed": .bool(true)])
        XCTAssertFalse(text.contains("p2-book"), "已经练过的还是被列出来了：\(text)")
        XCTAssertTrue(text.contains("Borrowing"))
    }

    /// **截断了必须说出来。** 不说的话，模型会把这几条当成题库的全部，
    /// 然后对用户说「你的题库里只有这些」。
    func testItSaysSoWhenTheListWasTruncated() throws {
        try seed((1...30).map { TopicQuestions.part1(topic: "T\($0)", prompts: ["q"]) })
        let text = try call(["limit": .number(5)])
        XCTAssertTrue(text.contains("\"matched\":30") || text.contains("\"matched\" : 30"), text)
        XCTAssertTrue(text.contains("没有返回"), "截断了却一个字不提：\(text)")
    }

    /// 题库空、和「条件没匹配上」是两件事，下一步完全不同。
    func testAnEmptyBankAndAnEmptyResultSayDifferentThings() throws {
        try seed([])
        XCTAssertTrue(try call([:]).contains("训练题库"), "题库空时没告诉他去导入")

        try seed(bank)
        let noMatch = try call(["search": .string("quantum")])
        XCTAssertTrue(noMatch.contains("改短"), "搜不到时没给下一步：\(noMatch)")
    }

    /// 布尔参数传错类型时**报错，不当成 false**：静静当成 false 的话，
    /// 调用方以为自己开了开关、拿到的却是关着的行为。
    func testABooleanPassedAsAStringIsRejected() throws {
        try seed(bank)
        XCTAssertTrue(try callExpectingError(["onlyUnpracticed": .string("true")]),
                      "布尔参数传成字符串却被静静当成 false 了")
    }
}
