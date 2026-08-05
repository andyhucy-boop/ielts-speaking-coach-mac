import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class QuestionBankViewModelTests: XCTestCase {
    private func q(_ id: String, _ part: Int, _ topic: String, status: String = "new") -> Question {
        Question(id: id, part: part, topic: topic, prompt: "P-\(id)", status: status)
    }

    // MARK: - 筛选与分组

    func testFilterByPart() {
        let vm = QuestionBankViewModel(questions: [q("a", 1, "Home"), q("b", 2, "Skills"), q("c", 1, "Work")])
        XCTAssertEqual(vm.filtered(part: 1).map(\.id), ["a", "c"])
        XCTAssertEqual(vm.filtered(part: nil).count, 3)
    }

    func testGroupsByTopicSortedByName() {
        let vm = QuestionBankViewModel(questions: [
            q("a", 1, "Work"), q("b", 1, "Home"), q("c", 1, "Work")
        ])
        let groups = vm.groupedByTopic(part: 1)
        XCTAssertEqual(groups.map(\.topic), ["Home", "Work"])
        XCTAssertEqual(groups.last?.questions.map(\.id), ["a", "c"])
    }

    func testGroupingRespectsPartFilter() {
        let vm = QuestionBankViewModel(questions: [q("a", 1, "Home"), q("b", 2, "Home")])
        XCTAssertEqual(vm.groupedByTopic(part: 2).flatMap(\.questions).map(\.id), ["b"])
    }

    func testCountsPracticed() {
        let vm = QuestionBankViewModel(questions: [
            q("a", 1, "Home", status: "practiced"), q("b", 1, "Home"), q("c", 2, "Skills", status: "practiced")
        ])
        XCTAssertEqual(vm.counts.total, 3)
        XCTAssertEqual(vm.counts.practiced, 2)
    }

    func testEmptyBankProducesEmptyGroupsNotCrash() {
        let vm = QuestionBankViewModel(questions: [])
        XCTAssertTrue(vm.groupedByTopic(part: nil).isEmpty)
        XCTAssertEqual(vm.counts.total, 0)
    }

    // MARK: - 按扩展名分派到哪个导入器
    //
    // 计划 Step 3 只写了「按扩展名调 importCSV/importJSON」这一句。这段分派看着一行就能写完，
    // 但它有一个不能靠肉眼守住的坑：命令行那份实现（`Sources/coach/QuestionsCommand.swift`）
    // 是「不是 .json 就当 CSV」，那在终端里尚可（路径是用户自己敲的），
    // 放到界面上就不行——Task 8 马上要把 PDF 加进文件面板，一份 PDF 被当成 CSV 解析
    // 会把二进制垃圾灌进题库，而且不报任何错。所以这里必须显式拒绝不认识的扩展名。

    private static let csv = """
        id,part,topic,prompt
        p1-1,1,Home,Do you live in a house or a flat?
        """

    private static let json = #"""
        {"title":"季度题库","part1":[{"raw":"Home","questions":["Do you live in a house or a flat?"]}]}
        """#

    func testCSVGoesToTheCSVImporterAndTakesItsTitleFromTheFileName() throws {
        let result = try QuestionBankImport.parse(fileName: "季度题库.csv", text: Self.csv)
        XCTAssertEqual(result.questions.map(\.id), ["p1-1"])
        XCTAssertEqual(result.source.title, "季度题库",
                       "题库来源要用文件名（去掉扩展名），否则「训练记录」里看不出题是从哪份文件来的")
    }

    func testJSONGoesToTheJSONImporter() throws {
        let result = try QuestionBankImport.parse(fileName: "bank.json", text: Self.json)
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertEqual(result.questions.first?.topic, "Home")
    }

    func testExtensionMatchIsCaseInsensitive() throws {
        // 从 Excel 导出的文件名常常是大写的 .CSV。大小写不敏感这件事没测过就会掉。
        let result = try QuestionBankImport.parse(fileName: "季度题库.CSV", text: Self.csv)
        XCTAssertEqual(result.questions.map(\.id), ["p1-1"])
    }

    func testUnsupportedExtensionIsRejectedInsteadOfBeingTreatedAsCSV() {
        // 故意喂一份**合法的 CSV 正文**，只是文件名是 .pdf。
        // 若实现照搬命令行那套「不是 json 就当 csv」，这里会安静地导入成功——
        // 那正是这条测试要拦住的。
        XCTAssertThrowsError(try QuestionBankImport.parse(fileName: "季度题库.pdf", text: Self.csv)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("下一步"), "只说不支持不说下一步不算合格：" + message)
            XCTAssertTrue(message.contains("csv") || message.contains("CSV"),
                          "得告诉用户到底认哪几种格式：" + message)
            XCTAssertTrue(message.contains("季度题库.pdf"), "得指名是哪个文件：" + message)
        }
    }

    func testFileWithoutExtensionIsRejectedWithAReadableMessage() {
        XCTAssertThrowsError(try QuestionBankImport.parse(fileName: "题库", text: Self.csv)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("下一步"), message)
            // 「扩展名是「.」」这种话读起来像 bug。没扩展名要说人话。
            XCTAssertFalse(message.contains("「.」"), "没有扩展名时的措辞读起来像程序出错：" + message)
        }
    }

    // MARK: - 导入完成后给用户看的那句话
    //
    // 铁律 6：面向用户的文案要同时说清「发生了什么」和「下一步做什么」。
    // 导入完成是最容易只说前半句的地方（「导入了 3 题 ✅」），而用户此刻最需要知道的恰恰是
    // 「那 5 条警告是什么意思、要不要管」。

    func testSummarySaysHowManyCameInAndHowManyThereAreNow() {
        let outcome = QuestionBankImportOutcome(importedCount: 3, totalCount: 41, warnings: [])
        XCTAssertTrue(outcome.summary.contains("3"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("41"),
                      "只说这次导入了几题不够，用户想知道题库现在共有多少：" + outcome.summary)
        XCTAssertTrue(outcome.summary.contains("下一步"), outcome.summary)
    }

    func testSummaryOfAnEmptyImportDoesNotReadLikeSuccess() {
        // 一道题都没进来却显示「已导入 0 道题」，用户会以为是自己题库本来就空。
        let outcome = QuestionBankImportOutcome(
            importedCount: 0, totalCount: 41,
            warnings: ["跳过一行：缺少 id。下一步：给每道题一个唯一编号。"])
        XCTAssertFalse(outcome.summary.contains("已导入 0"),
                       "0 道题不能报成一次成功的导入：" + outcome.summary)
        XCTAssertTrue(outcome.summary.contains("下一步"), outcome.summary)
        XCTAssertTrue(outcome.summary.contains("41"),
                      "得说清题库没被改动、现在还有多少题：" + outcome.summary)
    }

    func testSummaryTellsHowManyWarningsThereAre() {
        // 41 里没有 2，"3" 也不含 2 —— 断言里的「2 条警告」只能来自 warnings.count。
        let outcome = QuestionBankImportOutcome(importedCount: 3, totalCount: 41,
                                                warnings: ["甲", "乙"])
        XCTAssertTrue(outcome.summary.contains("2 条警告"),
                      "有几条警告要说清，否则用户不知道下面那堆红字是什么：" + outcome.summary)
    }

    // MARK: - 失败文案
    //
    // 铁律 6 的另一半：系统抛出来的 NSError 只说发生了什么，措辞也未必是中文。
    // 直接把 localizedDescription 摆给用户，等于把他扔在半路。
    // `AppState.describeLoadFailure` 已经为读状态做过一次同样的事。

    func testSystemErrorsGetAChineseNextStepAppended() {
        let system = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                             userInfo: [NSLocalizedDescriptionKey: "The volume is out of space."])
        let text = QuestionBankImport.describeFailure(system, fileName: "季度题库.csv")
        XCTAssertTrue(text.contains("下一步"), "系统给的报错不带下一步，必须由我们补上：" + text)
        XCTAssertTrue(text.contains("季度题库.csv"), "得指名是哪个文件：" + text)
        XCTAssertTrue(text.contains("The volume is out of space."),
                      "系统原文不能丢，否则没法排查到底是什么毛病：" + text)
    }

    func testMessagesThatAlreadyHaveANextStepArePassedThroughUnchanged() {
        // CoachError 的文案本来就是按铁律 6 写的，再包一层只会变成两句「下一步」。
        let original = "题库表头缺少必需列「id」。下一步：确保第一行是 id,part,topic,prompt,followups。"
        XCTAssertEqual(
            QuestionBankImport.describeFailure(CoachError.questionBankInvalid(original),
                                               fileName: "季度题库.csv"),
            original)
    }
}
