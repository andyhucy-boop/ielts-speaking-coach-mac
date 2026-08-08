import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// **命令行 `coach questions import` 与界面上那颗「导入题库…」必须是同一条路。**
///
/// ## 这不是理论问题，已经咬过一次
///
/// 两边从前各写各的：界面有一个 `Format` 枚举（显式拒绝不认识的扩展名），
/// 命令行是 `switch ext { case "json": …; default: CSV }`。后果实测过两条：
///
/// 1. **Task 8 给界面加了 PDF，命令行整整落后了一个格式**——同一个人用两条路导同一份
///    季度题库，一条成功、一条把 PDF 当成 CSV 解析。上一次就是因为「命令行不支持 PDF」
///    才发现这个缺口。
/// 2. `coach questions import 讲义.docx` 会走进 CSV 解析器，抛出一句
///    「题库表头缺少必需列「id」」——用户手上那份根本不是 CSV，
///    这句话把他指向一个不存在的问题（铁律 6：下一步必须是他真的做得到的那件事）。
///
/// 修法是把「认格式 → 读文件 → 分派解析」整段搬进 `IELTSCoachCore.QuestionBankFile`，
/// 两条路都只调它。这组测试守着「两边真的还在调同一个函数」——
/// 光有一个共用函数没用，谁在命令行里再写一遍 switch，行为就又分家了，
/// 而两边各自的测试都会照绿。
///
/// 边界：`coach` 是可执行 target，没有测试 target，所以这里扫的是它的源码
/// （`SourceGuard.repositoryCode`，读不到会抛错，不会拿空串把断言变成永远绿）。
final class QuestionBankImportParityTests: XCTestCase {

    private static let cli = "Sources/coach/QuestionsCommand.swift"

    private static let csv = """
        id,part,topic,prompt
        p1-1,1,Home,Do you live in a house or a flat?
        """
    private static let json = #"""
        {"title":"季度题库","part1":[{"raw":"Home","questions":["Do you live in a house or a flat?"]}]}
        """#
    private static let pdf = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        """

    private static func sample(for format: QuestionBankFormat) -> String {
        switch format {
        case .csv: return csv
        case .json: return json
        case .pdf: return pdf
        }
    }

    // MARK: - 行为：同一份文件，两边解析出来的东西必须一模一样

    /// 界面这一侧的门面 `QuestionBankImport.parse` 与 Core 那一份 `QuestionBankFile.parse`
    /// 对每一种格式都得给出**同一批题**。
    ///
    /// 命令行调的正是后者（下面那条源码断言钉着这件事），所以这一条 + 那一条合起来
    /// 就是「两条路结果相同」。
    func testBothSidesParseEveryFormatIntoExactlyTheSameQuestions() throws {
        XCTAssertFalse(QuestionBankFormat.allCases.isEmpty,
                       "一种格式都没有的话，下面这个循环一次都不跑，这条测试等于空转")
        for format in QuestionBankFormat.allCases {
            let fileName = "季度题库.\(format.fileExtension)"
            let text = Self.sample(for: format)
            let viaUI = try QuestionBankImport.parse(fileName: fileName, text: text)
            let viaCore = try QuestionBankFile.parse(fileName: fileName, text: text)
            XCTAssertFalse(viaCore.questions.isEmpty,
                           "样本 .\(format.fileExtension) 一道题都没解析出来，这一轮比的是两个空数组")
            XCTAssertEqual(viaUI.questions, viaCore.questions,
                           "界面与命令行对 .\(format.fileExtension) 解析出的题目不一样")
            XCTAssertEqual(viaUI.warnings, viaCore.warnings)
        }
    }

    /// 不认识的扩展名，两边都必须**拒绝**，而不是一边默默当成 CSV。
    func testAnUnknownExtensionIsRejectedOnBothSidesWithTheSameSentence() {
        for parse in [QuestionBankImport.parse(fileName:text:),
                      QuestionBankFile.parse(fileName:text:)] {
            XCTAssertThrowsError(try parse("讲义.docx", Self.csv)) { error in
                let message = error.localizedDescription
                XCTAssertTrue(message.contains("讲义.docx"), message)
                XCTAssertTrue(message.contains("下一步"), message)
                XCTAssertFalse(message.contains("表头"),
                               "这句话在说 CSV 表头——说明它其实被当成 CSV 解析了，"
                                   + "而用户手上那份根本不是 CSV：" + message)
            }
        }
    }

    // MARK: - 接线：命令行真的还在调那一条路吗

    /// 命令行必须调 `QuestionBankFile.importFile(at:pdfText:)`，
    /// 并且**不许**自己再写一遍「哪个扩展名走哪个导入器」。
    ///
    /// 实测过的退化形态就是那段 `switch ext`：它编得过、跑得动、单元测试全绿，
    /// 只是比界面少认一种格式。
    func testTheCommandLineGoesThroughTheOneSharedEntryPoint() throws {
        let code = try SourceGuard.repositoryCode(Self.cli)

        XCTAssertTrue(
            code.contains("QuestionBankFile.importFile(at:"),
            "命令行没有走 `QuestionBankFile.importFile(at:)`——认格式、读文件、分派解析"
                + "三步又变成了两份实现，而两份实现迟早会差一种格式（Task 8 就差过一次）。"
                + "下一步：把 `coach questions import` 改回只调它。")

        for reimplementation in ["QuestionBankImporter.importCSV",
                                 "QuestionBankImporter.importJSON",
                                 "PDFQuestionExtractor.extract"] {
            XCTAssertFalse(
                code.contains(reimplementation),
                "命令行又在自己挑导入器了（\(reimplementation)）。哪个扩展名走哪个导入器"
                    + "只能有一处说了算，否则界面加一种格式、命令行不知道。"
                    + "下一步：交回 `QuestionBankFile`。")
        }

        XCTAssertFalse(
            code.contains(#"case "json""#) || code.contains(#"ext == "pdf""#),
            "命令行里又出现了按扩展名分支的写法。下一步：格式判定只留 `QuestionBankFile` 一处。")
    }

    /// 命令行的用法提示里列的格式，必须是**数出来的**，不是手抄的。
    ///
    /// 手抄的那份（原文是「支持 .pdf / .csv / .json 三种」）在加第四种格式的那天
    /// 就开始骗人，而没有任何东西会红。
    func testTheCommandLineDerivesItsFormatListInsteadOfHardcodingIt() throws {
        let code = try SourceGuard.repositoryCode(Self.cli)
        XCTAssertTrue(
            code.contains("QuestionBankFile.supportedExtensionList"),
            "命令行的提示文案没有从 `QuestionBankFile` 取格式清单。"
                + "下一步：用 `supportedExtensionList` / `supportedExtensions.count` 拼这句话。")
        XCTAssertFalse(
            code.contains(".pdf / .csv / .json") || code.contains("三种。"),
            "命令行又把格式清单手抄进文案里了——加一种格式它就开始骗人。"
                + "下一步：改成从 `QuestionBankFile` 推出来。")
    }

    /// 失败信息也要共用一份。
    ///
    /// 系统 `NSError`（磁盘满、文件被占）只说发生了什么、不说下一步，措辞还未必是中文。
    /// 界面那一侧早就把这件事做掉了；命令行从前是 `print("❌ \(error.localizedDescription)")`，
    /// 于是同一次失败在两条路上给出两种说法，其中一种没有「下一步」。
    func testTheCommandLineTranslatesFailuresTheSameWayTheAppDoes() throws {
        let code = try SourceGuard.repositoryCode(Self.cli)
        XCTAssertTrue(
            code.contains("QuestionBankFile.describeFailure("),
            "命令行的导入失败没有走 `describeFailure`。系统 NSError 的原文只说发生了什么，"
                + "不说下一步（铁律 6）。下一步：`print(QuestionBankFile.describeFailure(error, "
                + "fileName: …))`。")

        // 前提：那个翻译真的会补上「下一步」。它要是变成原样透传，上面那条就成了摆设。
        let systemError = NSError(domain: NSCocoaErrorDomain, code: 640,
                                  userInfo: [NSLocalizedDescriptionKey: "The disk is full."])
        XCTAssertTrue(
            QuestionBankFile.describeFailure(systemError, fileName: "题库.csv").contains("下一步"),
            "`describeFailure` 不再补「下一步」了，上面那条接线断言也就失去了意义")
    }

    /// 界面那一侧同样不许把这段逻辑抄回去。
    ///
    /// 门面留着是为了不动几十处调用点，但它只能**转发**——
    /// 谁在里面重新实现一遍，两边就又分家了。
    func testTheAppSideIsOnlyAThinFacadeOverTheSharedPath() throws {
        let code = try SourceGuard.code("QuestionBank/QuestionBankViewModel.swift")
        XCTAssertTrue(code.contains("QuestionBankFile."),
                      "界面这一侧不再转发给 `QuestionBankFile` 了：两条导入路径又分家了。")
        XCTAssertFalse(code.contains("QuestionBankImporter.importCSV"),
                       "界面这一侧又自己挑导入器了。下一步：交回 `QuestionBankFile`。")
        XCTAssertFalse(code.contains("pathExtension.lowercased()"),
                       "界面这一侧又自己认了一遍扩展名。下一步：交回 "
                           + "`QuestionBankFile.format(ofFileName:)`。")
    }

    /// 命令行也得能跑一次原地重建模——不然那 1265 道旧题的用户只有「重新导入」一条路，
    /// 而那条路要求他手上还留着三个月前那份 PDF。
    ///
    /// 三件事一件不能少：默认只干跑、写盘前先备份、备份没成就不往下走。
    func testTheRemodelCommandIsDryRunFirstAndBacksUpBeforeItWrites() throws {
        let code = try SourceGuard.repositoryCode(Self.cli)

        XCTAssertTrue(code.contains(#"case "remodel""#),
                      "`coach questions remodel` 没了。题库文件已经丢了的用户就没有迁移的路了。")
        XCTAssertTrue(code.contains("--apply"),
                      "重建模没有「真改」的显式开关——手滑敲错一个子命令就把题库重排了。"
                          + "下一步：默认干跑，加 `--apply` 才写盘。")
        XCTAssertTrue(code.contains("DataBackup.copy("),
                      "写盘前不备份。这条命令动的是用户唯一一份训练数据。"
                          + "下一步：`DataBackup.copy` 成功之后再 `store.mutate`。")

        // 备份必须排在写盘**之前**。顺序反了的话，备份下来的是已经改过的那一份，
        // 那就等于没有备份——而两句代码都在，扫「有没有调用」的断言照样绿。
        let backupAt = try XCTUnwrap(code.range(of: "DataBackup.copy("))
        let mutateAt = try XCTUnwrap(code.range(of: "store.mutate {"))
        XCTAssertLessThan(backupAt.lowerBound, mutateAt.lowerBound,
                          "备份写在了写盘后面——备份下来的是改过之后的数据，等于没备份。")

        XCTAssertTrue(code.contains("lostPrompts") && code.contains("newOrphans"),
                      "命令行没有检查「有没有问句被吃掉 / 有没有制造孤儿」就写盘了。"
                          + "下一步：两项非空时打印出来并拒绝写盘（铁律 7）。")
    }
}
