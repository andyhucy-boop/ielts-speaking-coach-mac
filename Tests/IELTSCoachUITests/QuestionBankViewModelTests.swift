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

    /// PDF 那一路吃的是「PDFKit 抽出来的纯文本」，所以样本就是真实 PDF 里的片段
    /// （分区标题带字符间空格，照抄 2026-08-06 的实测结果）。
    private static let pdf = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        """

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
        // 故意喂一份**合法的 CSV 正文**，只是文件名是 .docx。
        // 若实现照搬命令行那套「不是 json 就当 csv」，这里会安静地导入成功——
        // 那正是这条测试要拦住的。
        //
        // 这里原本用的是 .pdf。**Task 8 把 PDF 变成了支持的格式**，再拿它当反例就不成立了；
        // 换成 .docx（用户第二可能拿来试的东西）而不是放宽断言。
        XCTAssertThrowsError(try QuestionBankImport.parse(fileName: "季度题库.docx", text: Self.csv)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("下一步"), "只说不支持不说下一步不算合格：" + message)
            XCTAssertTrue(message.contains("csv") || message.contains("CSV"),
                          "得告诉用户到底认哪几种格式：" + message)
            XCTAssertTrue(message.contains("季度题库.docx"), "得指名是哪个文件：" + message)
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

    /// 每一种格式都必须真的解析得出题目来。
    ///
    /// **有牙齿的是那句 `XCTFail`。** 加一种格式而不给样本，这条当场红——
    /// 也就逼着加格式的人回答「`parse` 真的认它吗」。之前这个问题没人问：
    /// 面板的清单、`parse` 的分派、拒绝文案是三份互不相干的字面量，
    /// 改其中一份另外两份不会有任何反应。
    func testEveryFormatTheFilePanelLetsThroughIsActuallyParsed() throws {
        let samples: [QuestionBankImport.Format: String] = [
            .csv: Self.csv, .json: Self.json, .pdf: Self.pdf
        ]

        XCTAssertFalse(QuestionBankImport.Format.allCases.isEmpty,
                       "一种格式都不认时 allowedContentTypes 会是空数组，"
                           + "而空数组的意思是 NSOpenPanel 放行一切文件类型；这条测试也就空转了")

        for format in QuestionBankImport.Format.allCases {
            guard let sample = samples[format] else {
                XCTFail("文件面板放行 .\(format.fileExtension)，但这条测试没有对应的样本，"
                        + "也就从没人验证过 parse 真的认它。"
                        + "下一步：给这条测试补一份 .\(format.fileExtension) 的样本，"
                        + "确认 parse 解析得出题目，而不是选完文件才把用户拒掉。")
                continue
            }
            let result = try QuestionBankImport.parse(
                fileName: "季度题库.\(format.fileExtension)", text: sample)
            XCTAssertFalse(result.questions.isEmpty,
                           "面板放行 .\(format.fileExtension)，parse 却一道题都没解析出来")
        }
    }

    /// 每种格式配给文件面板的类型，必须真的对应它的扩展名。
    ///
    /// 原先这里是 `supportedExtensions.compactMap { UTType(filenameExtension: $0) }`：
    /// 查不到 UTType 的项会被**静默丢掉**（铁律 7），全丢掉时 `allowedContentTypes`
    /// 退化成空数组——而空数组对 `NSOpenPanel` 的意思是「放行一切文件类型」。
    func testEachFormatsFilePanelTypeReallyMatchesItsExtension() {
        for format in QuestionBankImport.Format.allCases {
            XCTAssertEqual(format.contentType.preferredFilenameExtension, format.fileExtension,
                           "格式 .\(format.fileExtension) 配的是 \(format.contentType.identifier)，"
                               + "面板里能选到的会是别的文件")
        }
        XCTAssertEqual(QuestionBankImport.allowedContentTypes.count,
                       QuestionBankImport.Format.allCases.count,
                       "有格式在配文件面板类型的路上被丢掉了——丢光时空数组等于放行一切文件")
        XCTAssertFalse(QuestionBankImport.allowedContentTypes.isEmpty,
                       "allowedContentTypes 为空时 NSOpenPanel 放行一切文件类型")
    }

    /// 拒绝文案里列的格式，必须就是文件面板放行的那几种。
    ///
    /// 这一条守的是「同一份清单被抄了三遍」：`supportedExtensions`（面板用）、
    /// `parse` 的分派、以及这句拒绝文案，一度是三处各写各的字面量，只是恰好一致。
    /// 把清单改成 `["csv", "json", "pdf"]`，面板就会放行 PDF、`parse` 抛错、
    /// 而这句话还在说「只认 .csv 和 .json 两种」——全部 272 条测试无一变红。
    func testTheRejectionMessageListsTheSameFormatsTheFilePanelLetsThrough() {
        XCTAssertThrowsError(try QuestionBankImport.parse(fileName: "季度题库.docx", text: Self.csv)) { error in
            let message = error.localizedDescription
            for ext in QuestionBankImport.supportedExtensions {
                XCTAssertTrue(message.contains(".\(ext)"),
                              "文件面板放行 .\(ext)，拒绝文案却没提它，用户不知道该另存成什么：" + message)
            }
            // 连「几种」这个数也必须是数出来的。写死成「两种」的话，
            // 加一种格式之后这句话就开始骗人，而没有任何东西会红。
            XCTAssertTrue(message.contains("这 \(QuestionBankImport.supportedExtensions.count) 种"),
                          "格式的种数是写死在文案里的，加一种格式它就会开始骗人：" + message)
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

    // MARK: - 导入之后弹给用户看的那张交代
    //
    // 这张交代必须弹出来（`.sheet`），不能画在滚动页面里——理由见 `QuestionBankViewTests`。
    // 这里测的是弹出来之后**里面写什么**：语气对不对、警告有没有被吞掉。

    func testFeedbackOfAnEmptyImportIsNotDressedUpAsSuccess() {
        let feedback = QuestionBankImportFeedback(outcome: QuestionBankImportOutcome(
            importedCount: 0, totalCount: 41,
            warnings: ["跳过第 7 行：缺少 id。下一步：给这道题一个唯一编号。"]))
        XCTAssertEqual(feedback.tone, .nothing,
                       "一道题都没进来时给绿色对勾，用户扫一眼就走开了，"
                           + "而真正的原因全在下面那几条警告里")
        XCTAssertFalse(feedback.title.contains("完成"), feedback.title)
    }

    func testFeedbackCarriesEveryWarningThroughInOrder() {
        let warnings = ["第 3 行没有题干。", "第 7 行缺少 id。", "第 9 行的 part 不是 1/2/3。"]
        let feedback = QuestionBankImportFeedback(outcome: QuestionBankImportOutcome(
            importedCount: 3, totalCount: 41, warnings: warnings))
        XCTAssertEqual(feedback.warnings, warnings,
                       "警告要逐条摆出来、一条不吞（计划 Task 4 Step 3）——"
                           + "它们比「导入了 N 题」有用得多，而且不看就再也不会知道")
        XCTAssertEqual(feedback.tone, .done)
        XCTAssertTrue(feedback.message.contains("下一步"), feedback.message)
    }

    func testFailureFeedbackKeepsTheWholeMessage() {
        let text = "读不到「季度题库.csv」的内容。下一步：另存为 UTF-8 之后再导入一次。"
        let feedback = QuestionBankImportFeedback(failureMessage: text)
        XCTAssertEqual(feedback.tone, .failed)
        XCTAssertEqual(feedback.message, text, "失败原因被改写或截断，用户就照着做不了了")
    }

    // MARK: - 题库重建模：那两句必须说出来的话

    /// 题库还是「一问一题」时，页面上必须主动说一句，并指向这一页真有的那颗按钮。
    ///
    /// **不说的话，用户永远停在旧结构上。** 重建模发生在导入那一刻，不是打开 App
    /// 自动改数据（那是把他没要求过的事做了，还没法撤销）。代价就是他得再导一次，
    /// 而他不会知道要这么做。
    func testTheBankPageSaysSoWhileTheBankIsStillOneQuestionPerRow() throws {
        let legacy = QuestionBankViewModel(questions: [
            q("a", 1, "Music"), q("b", 1, "Music"), q("c", 2, "人物")
        ])
        let notice = try XCTUnwrap(legacy.legacyShapeNotice,
                                   "题库还是旧结构，页面上却一句话都没有")
        XCTAssertTrue(notice.contains("2 道"), "得说清有多少道是旧结构的：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "铁律 4：必须说下一步做什么：\(notice)")
        XCTAssertTrue(notice.contains("导入题库…"),
                      "下一步指的按钮必须是这一页上真有的那颗（叫「导入题库…」）：\(notice)")
    }

    /// 反面：已经是新结构了就闭嘴。一直挂着的提示等于没有提示。
    func testTheBankPageStaysQuietOnceTheBankIsRemodelled() {
        let remodelled = QuestionBankViewModel(questions: [
            TopicQuestions.part1(topic: "Music", prompts: ["a?", "b?"]),
            q("c", 2, "人物")
        ])
        XCTAssertNil(remodelled.legacyShapeNotice)
    }

    /// 一次导入吸收掉旧题时，交代里必须同时说清**题库为什么变小**与**历史记录去哪了**。
    ///
    /// 用户导入前 1265 道、导入后 258 道。少掉一千多道没有一句解释的话，
    /// 他只会认为导入把题库弄坏了——而实际上一个问句都没丢。
    func testTheImportSummaryExplainsWhyTheBankSuddenlyGotSmaller() throws {
        let outcome = QuestionBankImportOutcome(
            importedCount: 257, totalCount: 258, warnings: [],
            absorbedCount: 1165, remappedReferenceCount: 3)
        let summary = outcome.summary

        XCTAssertTrue(summary.contains("1165 道"), "没说吸收了多少道：\(summary)")
        XCTAssertTrue(summary.contains("一句没丢"), "没说清问句其实都还在：\(summary)")
        XCTAssertTrue(summary.contains("3 处"), "没说历史记录搬了多少处：\(summary)")
        XCTAssertTrue(summary.contains("下一步"), "\(summary)")
    }

    /// 有警告时那句交代也不许被挤掉——题库总数变化比某几行解析失败更要紧，
    /// 而且它自带的「下一步」不能变成两个互相矛盾的下一步。
    func testTheRemodelExplanationSurvivesEvenWhenThereAreWarnings() {
        let outcome = QuestionBankImportOutcome(
            importedCount: 257, totalCount: 258, warnings: ["某一行没进来"],
            absorbedCount: 1165, remappedReferenceCount: 0)
        let summary = outcome.summary

        XCTAssertTrue(summary.contains("1165 道"), "有警告时那句交代被挤掉了：\(summary)")
        XCTAssertTrue(summary.contains("1 条警告"), "\(summary)")
        XCTAssertEqual(summary.components(separatedBy: "下一步").count - 1, 1,
                       "出现了两个「下一步」，用户不知道该照哪个做：\(summary)")
    }

    /// 反面：没吸收任何旧题的普通导入（绝大多数），一个字都不该多说。
    func testAnOrdinaryImportSaysNothingAboutRemodelling() {
        let outcome = QuestionBankImportOutcome(importedCount: 10, totalCount: 10, warnings: [])
        XCTAssertNil(outcome.remodelNotice)
        XCTAssertEqual(outcome.summary,
                       "已导入 10 道题，题库现共 10 道题。下一步：到「今日训练」页开始练习。")
    }
}
