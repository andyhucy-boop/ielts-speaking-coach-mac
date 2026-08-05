import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 复盘报告页里全部可测的那部分逻辑，三块：
///
/// ① **把一份复盘 JSON 拆成界面要显示的分区**（计划 Task 5 Step 1 那五条）。
/// ② **左边那列会话**：哪几次进得来、按什么顺序排。
/// ③ **从 `reportPath` 把原文读进来**：读不到、解析不了的时候跟用户怎么说。
///
/// 后两块计划里只写在 `ReviewReportView` 的验收要求里（「左侧列出 state.sessions 里带
/// reportPath 的会话（按时间倒序）」「读不到或解析失败时显示中文错误与文件路径」）。
/// 留在 `View` 里就一条测试都写不了，所以照本计划 File Structure 一节的做法拆出来——
/// 那一节的原话是「只有视图模型分离出来，『改成空实现会不会红』这个判据才立得住」。
@MainActor
final class ReviewReportViewModelTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-review-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    // MARK: - 一份复盘拆成分区（计划 Task 5 Step 1）

    func testBuildsMustCorrectSection() throws {
        let value = try report(#"""
        {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
        "why_it_matters":"very 不能修饰动词"}]}
        """#)
        let sections = ReviewReportViewModel.sections(from: value)
        let section = try XCTUnwrap(sections.first { $0.title == "必须纠正的表达" })
        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(section.rows[0].primary, "I very like it.")
        XCTAssertEqual(section.rows[0].secondary, "I really like it.")
        XCTAssertEqual(section.rows[0].note, "very 不能修饰动词")
    }

    func testSkipsSectionsThatAreAbsentOrEmpty() throws {
        let value = try report(#"{"must_correct":[],"vocabulary":[]}"#)
        XCTAssertTrue(ReviewReportViewModel.sections(from: value).isEmpty,
                      "空的分区不该显示成一个空标题")
    }

    func testExtractsPriorityTarget() throws {
        let value = try report(#"""
        {"priority_target":{"id":"logic-explain","label":"补一个原因和例子","evidence":["I just like it."]}}
        """#)
        let target = try XCTUnwrap(ReviewReportViewModel.priorityTarget(from: value))
        XCTAssertEqual(target.primary, "补一个原因和例子")
        XCTAssertTrue(target.note.contains("I just like it."))
    }

    func testSurvivesWrongShapeWithoutCrashing() throws {
        // ChatGPT 曾把 vocabulary 输出成对象而非数组（spec 2.3.8）。
        // 界面绝不能因此崩溃，最多是这一节不显示。
        let value = try report(#"{"vocabulary":{"useful":"x"},"must_correct":"不是数组"}"#)
        XCTAssertNoThrow(ReviewReportViewModel.sections(from: value))
        XCTAssertTrue(ReviewReportViewModel.sections(from: value).isEmpty)
    }

    func testSectionOrderFollowsReportSchema() throws {
        let value = try report(#"""
        {"vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding trip","priority":"high"}],
         "must_correct":[{"learner_said":"a","correction":"b","why_it_matters":"c"}]}
        """#)
        // 顺序固定，不随 JSON 键序变化——否则同一份复盘每次打开顺序都不一样
        XCTAssertEqual(ReviewReportViewModel.sections(from: value).map(\.title),
                       ["必须纠正的表达", "词汇升级"])
    }

    // MARK: - 三格分别是什么意思，必须写出来

    /// 每个分区的三格含义都不一样：「必须纠正的表达」里第二格是改正后的说法，
    /// 「词汇升级」里第二格是更准确的词，「逐题高分版」里第二格是原回答。
    /// 不标注的话，界面上就是三行没头没脑的文字——
    /// `good / rewarding / a rewarding trip` 摆在一起，谁也看不出哪行是自己说的、哪行是建议。
    func testEverySectionSpellsOutWhatItsThreeColumnsMean() throws {
        let value = try report(#"""
        {"must_correct":[{"learner_said":"a","correction":"b","why_it_matters":"c"}],
         "natural_upgrades":[{"learner_said":"a","more_natural":"b","usage_note":"c"}],
         "vocabulary":[{"basic":"a","better":"b","collocation":"c","priority":"high"}],
         "answer_upgrades":[{"question":"a","original_answer":"b","revised_answer":"c",
                             "changes":["补了原因"]}]}
        """#)
        let sections = ReviewReportViewModel.sections(from: value)
        XCTAssertEqual(sections.count, 4)
        for section in sections {
            XCTAssertFalse(section.primaryLabel.isEmpty, "\(section.title) 第一格没有标注")
            XCTAssertFalse(section.secondaryLabel.isEmpty, "\(section.title) 第二格没有标注")
            XCTAssertFalse(section.noteLabel.isEmpty, "\(section.title) 第三格没有标注")
        }
        // 四个分区的第二格含义完全不同，标注不能是同一句——
        // 全填一样等于没标，而上面那圈「非空」照样全绿。
        XCTAssertEqual(Set(sections.map(\.secondaryLabel)).count, 4,
                       "四个分区的第二格标注撞了：\(sections.map(\.secondaryLabel))")
    }

    // MARK: - 键在、却一条都读不出来时不许悄悄消失

    /// ChatGPT 偶尔把某一节写成字符串数组（`["I very like it."]`）而不是对象数组。
    /// 字段一个都取不到时，行里三格全是空字符串——界面上就是一块有标题、底下全白的区。
    ///
    /// 这与 `ArchiveOutcome.skipped` 守的是同一件事：**归档 0 条不等于没错题**，
    /// 更可能是字段名对不上，而这种失败不报错、不崩溃，只是悄悄什么都不做。
    func testSectionsThatArePresentButUnreadableAreReportedInsteadOfVanishing() throws {
        let value = try report(#"{"must_correct":["I very like it."],"vocabulary":{"useful":"x"}}"#)
        XCTAssertTrue(ReviewReportViewModel.sections(from: value).isEmpty,
                      "三格全空的行不该画成一块空白")
        XCTAssertEqual(ReviewReportViewModel.unreadableSections(in: value),
                       ["必须纠正的表达", "词汇升级"],
                       "复盘里有内容却一条都没读出来，必须说出来")
    }

    func testNothingIsCalledUnreadableWhenTheReportIsFine() throws {
        let value = try report(#"""
        {"must_correct":[{"learner_said":"a","correction":"b","why_it_matters":"c"}],
         "vocabulary":[]}
        """#)
        XCTAssertEqual(ReviewReportViewModel.unreadableSections(in: value), [],
                       "读得好好的却报「读不出来」，用户会以为复盘坏了")
    }

    // MARK: - 左边那列会话

    func testOnlySessionsWithAnArchivedReportAreListedAndNewestComesFirst() {
        var state = CoachState.empty()
        state.sessions = [
            session("older", startedAt: "2026-08-01T09:00:00Z", reportPath: "reports/older.json"),
            session("no-report", startedAt: "2026-08-03T09:00:00Z", reportPath: ""),
            session("newer", startedAt: "2026-08-02T09:00:00Z", reportPath: "reports/newer.json")
        ]
        // 没有复盘的那次不能进来——点开只会是一句错误信息；
        // 顺序必须是最近的在最上面，否则用户每次都要滚到底才找得到刚练完的那次。
        XCTAssertEqual(ReviewReportViewModel.archivedSessions(in: state).map(\.id),
                       ["newer", "older"])
    }

    func testNoSessionsAtAllIsNotACrash() {
        XCTAssertTrue(ReviewReportViewModel.archivedSessions(in: .empty()).isEmpty)
    }

    // MARK: - 把复盘原文从磁盘读进来

    func testLoadsAReportStoredRelativeToTheDataDirectory() throws {
        try write(Self.sampleReport, to: "2026-08-06-001.json")

        let document = try ReviewReportLoader.load(
            session: session("s1", startedAt: "2026-08-06T10:00:00Z",
                             reportPath: "reports/2026-08-06-001.json"),
            in: directory)

        // reportPath 存的是**相对数据目录**的路径（见 PracticeSession 的注释）。
        // 直接拿它当路径打开，换台电脑就全打不开了。
        XCTAssertEqual(document.path,
                       directory.root.appending(path: "reports/2026-08-06-001.json").path)
        XCTAssertEqual(document.sections.map(\.title), ["必须纠正的表达"])
        XCTAssertEqual(document.priorityTarget?.primary, "补一个原因和例子")
        XCTAssertFalse(document.isEmpty)
    }

    func testAnAbsoluteReportPathIsOpenedAsIsInsteadOfBeingGluedOntoTheDataDirectory() throws {
        // 约定是相对路径，但万一哪一版写进去的是绝对路径（Phase 10 Task 4 专门审计这件事），
        // 拼在数据目录后面会得到一个必然不存在的路径，报错还指着一个看着眼熟其实不存在的地方。
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-review-abs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(Self.sampleReport.utf8).write(to: outside)

        let document = try ReviewReportLoader.load(
            session: session("s1", startedAt: "2026-08-06T10:00:00Z", reportPath: outside.path),
            in: directory)

        XCTAssertEqual(document.path, outside.path)
        XCTAssertEqual(document.sections.map(\.title), ["必须纠正的表达"])
    }

    func testAMissingReportFileNamesTheFileAndSaysWhatToDoNext() {
        let missing = session("s1", startedAt: "2026-08-06T10:00:00Z",
                              reportPath: "reports/gone.json")
        XCTAssertThrowsError(try ReviewReportLoader.load(session: missing, in: directory)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains(directory.root.appending(path: "reports/gone.json").path),
                          "得指名是哪个文件不见了，否则用户无从下手：" + message)
            XCTAssertTrue(message.contains("下一步"), "只说打不开不说下一步不算合格：" + message)
        }
    }

    func testAnUnparsableReportKeepsPointingAtTheOriginalFileInsteadOfADeadEnd() throws {
        try write("这不是 JSON，是 ChatGPT 的一段闲聊。", to: "broken.json")
        let broken = session("s1", startedAt: "2026-08-06T10:00:00Z",
                             reportPath: "reports/broken.json")

        XCTAssertThrowsError(try ReviewReportLoader.load(session: broken, in: directory)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains(directory.root.appending(path: "reports/broken.json").path),
                          "解析失败必须给出文件路径，用户才能自己去看原文：" + message)
            XCTAssertTrue(message.contains("下一步"), "只说解析失败不说下一步不算合格：" + message)
            // ReviewParser 那句「下一步：点『补生成复盘报告』」是给练习当场用的，
            // 这一页上没有那个按钮。照搬会把用户支到一个不存在的地方（铁律 6）。
            XCTAssertFalse(message.contains("补生成复盘报告"),
                           "把练习当场的处置办法照搬到这一页，用户找不到那个按钮：" + message)
        }
    }

    func testAReportWithNothingInItIsFlaggedInsteadOfRenderingABlankPane() throws {
        try write(#"{"must_correct":[]}"#, to: "empty.json")
        let document = try ReviewReportLoader.load(
            session: session("s1", startedAt: "2026-08-06T10:00:00Z",
                             reportPath: "reports/empty.json"),
            in: directory)
        // 一块全白的右半边会让用户以为程序坏了，界面得据此说一句话。
        XCTAssertTrue(document.isEmpty)
    }

    func testAppStateReadsTheReportFromTheSameDataDirectoryItLoadsTheStateFrom() throws {
        try write(Self.sampleReport, to: "2026-08-06-002.json")
        let app = AppState(directory: directory,
                           preflight: { BridgeReadiness(ok: true, messages: []) })

        let document = try app.loadReview(for: session(
            "s1", startedAt: "2026-08-06T10:00:00Z", reportPath: "reports/2026-08-06-002.json"))

        // 走错目录的话这里读不到文件——而界面拿不到 directory（它是私有的，
        // App 与命令行必须写同一个目录），只能经 AppState 这一道。
        XCTAssertEqual(document.sections.map(\.title), ["必须纠正的表达"])
    }

    // MARK: - 小工具

    private static let sampleReport = #"""
    {"summary":"整体流利，但回答偏短。",
     "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                      "why_it_matters":"very 不能修饰动词"}],
     "priority_target":{"id":"logic-explain","label":"补一个原因和例子","status":"new",
                        "evidence":["I just like it."]}}
    """#

    private func write(_ text: String, to fileName: String) throws {
        try Data(text.utf8).write(to: directory.reportsDirectory.appending(path: fileName))
    }

    private func session(_ id: String, startedAt: String, reportPath: String,
                         questionId: String = "q1") -> PracticeSession {
        PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                        startedAt: startedAt, endedAt: startedAt, goal: "",
                        transcript: [], reportPath: reportPath, recordingPath: "")
    }
}
