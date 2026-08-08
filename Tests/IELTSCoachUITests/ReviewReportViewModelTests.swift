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
        let target = try XCTUnwrap(ReviewReportViewModel.priorityTarget(from: value,
                                                                        sessionID: "s1"))
        XCTAssertEqual(target.primary, "补一个原因和例子")
        XCTAssertTrue(target.note.contains("I just like it."))
    }

    // MARK: - 三块此前永远看不到的内容（复审第 2 条）

    /// **整体总结、口语习惯、逐题逻辑反馈。**
    ///
    /// ChatGPT 每次都给（提示词的八个顶层键里就有它们），也原样存进了硬盘上的复盘文件，
    /// 而界面此前一个字都不显示——「回答前有较长停顿」「没有先直接回应问题，
    /// 应该先给答案再补原因和例子」这类最该被看见的行为反馈，一条都不上屏。
    /// 用户得到的信号是「这就是完整的复盘」。
    func testTheThreeBlocksThatUsedToBeInvisibleAreAllRead() throws {
        let value = try report(#"""
        {"summary":"整体流利，但回答偏短。",
         "habits":[{"habit":"回答前有较长停顿","evidence":"多次出现 3 秒以上的空白。",
                    "fix":"想不出来就先说一句通用的开场，别停着"}],
         "logic_feedback":[{"question":"What do you like most about your home?",
                            "issue":"没有先直接回应问题",
                            "improvement":"先一句话给答案，再补原因和例子。"}]}
        """#)

        XCTAssertEqual(ReviewReportViewModel.summary(from: value), "整体流利，但回答偏短。",
                       "整体总结是整份复盘里唯一一段连贯的话，读不出来就等于没有")

        let sections = ReviewReportViewModel.sections(from: value)
        let habits = try XCTUnwrap(sections.first { $0.title == "口语习惯" },
                                   "「口语习惯」这一节根本没被拆出来")
        XCTAssertEqual(habits.rows[0].primary, "回答前有较长停顿")
        XCTAssertEqual(habits.rows[0].secondary, "想不出来就先说一句通用的开场，别停着")
        XCTAssertEqual(habits.rows[0].note, "多次出现 3 秒以上的空白。")

        let logic = try XCTUnwrap(sections.first { $0.title == "逐题逻辑反馈" },
                                  "「逐题逻辑反馈」这一节根本没被拆出来")
        XCTAssertEqual(logic.rows[0].primary, "What do you like most about your home?")
        XCTAssertEqual(logic.rows[0].secondary, "先一句话给答案，再补原因和例子。")
        XCTAssertEqual(logic.rows[0].note, "没有先直接回应问题")
    }

    /// ChatGPT 没给 `fix` 时（旧格式的复盘全都没有），这一节照样要上屏，
    /// 只是「下次怎么改」那一格空着不画。
    func testAHabitWithoutAFixIsStillShown() throws {
        let value = try report(#"""
        {"habits":[{"habit":"回答前有较长停顿","evidence":"多次出现 3 秒以上的空白。"}]}
        """#)
        let habits = try XCTUnwrap(ReviewReportViewModel.sections(from: value)
            .first { $0.title == "口语习惯" })
        XCTAssertEqual(habits.rows.count, 1, "少一个可选字段就整节消失，等于又丢一块内容")
        XCTAssertEqual(habits.rows[0].secondary, "")
    }

    /// **最锋利的一种：一份有实质内容的复盘被打上「这份复盘是空的」。**
    ///
    /// 练得短、语法没硬伤时，复盘里只有这三块内容是完全可能的。那时页面会说
    /// 「这份复盘是空的……多半是那次练习太短，ChatGPT 没什么可点评的。
    /// 下一步：到『今日训练』再练一场」——这对一份有内容的复盘是事实错误，
    /// 还会把用户支去重练一场本不必重练的练习。
    func testAReportThatOnlyHasTheseThreeBlocksIsNotCalledEmpty() throws {
        try write(#"""
        {"summary":"整体流利，但回答偏短。",
         "habits":[{"habit":"回答前有较长停顿","evidence":"多次出现 3 秒以上的空白。"}],
         "logic_feedback":[{"question":"Q","issue":"没有先直接回应问题","improvement":"先给答案"}]}
        """#, to: "soft.json")

        let document = try ReviewReportLoader.load(
            session: session("s1", startedAt: "2026-08-06T10:00:00Z",
                             reportPath: "reports/soft.json"),
            in: directory)

        XCTAssertEqual(document.summary, "整体流利，但回答偏短。")
        XCTAssertEqual(document.sections.map(\.title), ["口语习惯", "逐题逻辑反馈"])
        XCTAssertFalse(document.isEmpty,
                       "一份有整体总结、口语习惯、逐题逻辑反馈的复盘被说成「是空的」，"
                           + "还会把用户支去重练一场本不必重练的练习")
    }

    /// 只有整体总结这一样时也不算空——`isEmpty` 里漏掉 `summary` 那一项就会红。
    ///
    /// 这里直接搭一份 `ReviewDocument`，不走 `ReviewReportLoader`：
    /// `ReviewParser.looksLikeReview` 认的是 must_correct / natural_upgrades /
    /// logic_feedback / priority_target 四个键，只有 summary 的一份 JSON 它压根不收
    /// （那是**另一处**缺陷，会响亮地报「不是本工具认得的格式」并给出路径，不是静默失败，
    /// 也不在本次要修的两条里）。这条测的是 `isEmpty` 的判据本身。
    func testAReportWithOnlyAnOverallSummaryIsNotCalledEmpty() {
        let document = ReviewDocument(path: "/tmp/x.json", priorityTarget: nil,
                                      summary: "整体流利，但回答偏短。",
                                      sections: [], unreadableSections: [])
        XCTAssertFalse(document.isEmpty,
                       "一份写着整体总结的复盘被判成「这份复盘是空的」，"
                           + "页面还会说「多半是那次练习太短」，把用户支去重练一场本不必重练的练习")
    }

    /// 整体总结被写成对象或数组时取不出字符串，那一整段话会凭空消失——
    /// 必须像别的分区一样被点名，而不是悄悄没了。
    func testAnUnreadableOverallSummaryIsReportedInsteadOfVanishing() throws {
        let value = try report(#"{"summary":{"overall":"整体流利，但回答偏短。"}}"#)
        XCTAssertEqual(ReviewReportViewModel.summary(from: value), "")
        XCTAssertEqual(ReviewReportViewModel.unreadableSections(in: value), ["整体总结"],
                       "整段总结读不出来却一个字都不提，用户永远不知道自己少看了什么")
    }

    /// 口语习惯 / 逐题逻辑反馈换了字段名或形状时同样要被点名。
    /// 此前这两节连出现在这份清单里的资格都没有——那张警告卡只遍历分区表，而表里没有它们。
    func testHabitsAndLogicFeedbackCanNowBeReportedAsUnreadable() throws {
        let value = try report(#"""
        {"habits":["回答前有较长停顿"],
         "logic_feedback":{"question":"Q","issue":"没有先直接回应问题"}}
        """#)
        XCTAssertEqual(ReviewReportViewModel.unreadableSections(in: value),
                       ["口语习惯", "逐题逻辑反馈"])
    }

    /// 一份好好的复盘不该被报成「读不出来」。
    func testAWellFormedSummaryIsNotCalledUnreadable() throws {
        let value = try report(#"{"summary":"整体流利。","habits":[]}"#)
        XCTAssertEqual(ReviewReportViewModel.unreadableSections(in: value), [])
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

    /// 六节的完整顺序，与 `ReviewRequestPrompt` 里那张键表一致。
    func testAllSixSectionsComeOutInTheOrderTheSchemaLists() throws {
        let value = try report(#"""
        {"answer_upgrades":[{"question":"a","original_answer":"b","revised_answer":"c"}],
         "logic_feedback":[{"question":"a","improvement":"b","issue":"c"}],
         "habits":[{"habit":"a","evidence":"c"}],
         "vocabulary":[{"basic":"a","better":"b","collocation":"c"}],
         "natural_upgrades":[{"learner_said":"a","more_natural":"b","usage_note":"c"}],
         "must_correct":[{"learner_said":"a","correction":"b","why_it_matters":"c"}]}
        """#)
        XCTAssertEqual(ReviewReportViewModel.sections(from: value).map(\.title),
                       ["必须纠正的表达", "更自然的表达", "词汇升级",
                        "口语习惯", "逐题逻辑反馈", "逐题高分版"])
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
         "habits":[{"habit":"a","fix":"b","evidence":"c"}],
         "logic_feedback":[{"question":"a","improvement":"b","issue":"c"}],
         "answer_upgrades":[{"question":"a","original_answer":"b","revised_answer":"c",
                             "changes":["补了原因"]}]}
        """#)
        let sections = ReviewReportViewModel.sections(from: value)
        // 六节：提示词要的六个数组键，一个都不能少（少一个就是又一块「永远看不到」的内容）。
        XCTAssertEqual(sections.count, 6, "实际拆出来的是：\(sections.map(\.title))")
        for section in sections {
            XCTAssertFalse(section.primaryLabel.isEmpty, "\(section.title) 第一格没有标注")
            XCTAssertFalse(section.secondaryLabel.isEmpty, "\(section.title) 第二格没有标注")
            XCTAssertFalse(section.noteLabel.isEmpty, "\(section.title) 第三格没有标注")
        }
        // 各分区的第二格含义完全不同，标注不能是同一句——
        // 全填一样等于没标，而上面那圈「非空」照样全绿。
        XCTAssertEqual(Set(sections.map(\.secondaryLabel)).count, 6,
                       "分区的第二格标注撞了：\(sections.map(\.secondaryLabel))")
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

    // MARK: - 卡片画得出 ⟺ 目标归得进（复审第 7 条的根因）

    /// **这一条守的是「改进闭环」不断掉。**
    ///
    /// 根因是两套判据不一致：`RetrainingPolicy.extractTarget` 要求 `id` 非空，
    /// 而这一页只要求 `label` 非空、`id` 缺失时兜底成 "target"。于是 ChatGPT 漏给 `id` 的那次，
    /// 用户在复盘页看见那张最显眼的深色卡片「下一次只盯这一个」，`state.targets` 一条不加，
    /// `ArchiveOutcome.skipped` 还是空数组——四个归档出口全都不吭声，
    /// 他转身在复训中心看到的是「还没有待复训的目标。下一步：先完整练一场」。
    ///
    /// 所以这里不逐形状写死结论，而是断言**两边永远同进同退**：
    /// 任何一边单独加一个条件，这条就红。
    func testTheCardOnThisPageAndTheArchiveAgreeOnWhetherThereIsATarget() throws {
        let shapes = [
            #"{"priority_target":{"id":"logic-explain","label":"补一个原因和例子"}}"#,
            #"{"priority_target":{"label":"补一个原因和例子"}}"#,
            #"{"priority_target":{"id":"  ","label":"补一个原因和例子"}}"#,
            #"{"priority_target":{"id":"logic-explain"}}"#,
            #"{"priority_target":{"status":"new"}}"#,
            #"{"priority_target":{}}"#,
            #"{"priority_target":"补一个原因和例子"}"#,
            #"{"priority_target":["补一个原因和例子"]}"#,
            #"{"priority_target":null}"#,
            #"{"must_correct":[]}"#
        ]
        for json in shapes {
            let value = try report(json)
            let card = ReviewReportViewModel.priorityTarget(from: value, sessionID: "s1")
            let archived = RetrainingPolicy.extractTarget(from: value, sessionID: "s1",
                                                          createdAt: "t")
            XCTAssertEqual(card != nil, archived != nil,
                           "复盘页画卡片(\(card != nil))和归档存目标(\(archived != nil))对这份复盘"
                               + "给出了不同的答案：\(json)。"
                               + "画得出卡片却归不进档案，用户会在复训中心被告知"
                               + "「还没有待复训的目标」——一句他刚练完一整场时字面上为假的话；"
                               + "反过来则是档案里多一条页面上从没提过的目标。"
                               + "下一步：两处共用 `RetrainingPolicy.extractTarget` 这一份判据，"
                               + "别在任何一边单独加条件。")
        }
    }

    /// 卡片上那行字必须和复训中心那一行说的是同一个目标——
    /// 只断言「都非 nil」的话，两边显示完全不同的内容也照样绿。
    func testTheCardShowsTheSameTargetTheArchiveWillKeep() throws {
        let value = try report(#"""
        {"priority_target":{"label":"补一个原因和例子","status":"new","evidence":["I just like it."]}}
        """#)
        let card = try XCTUnwrap(ReviewReportViewModel.priorityTarget(from: value,
                                                                      sessionID: "2026-08-08-001"))
        let archived = try XCTUnwrap(RetrainingPolicy.extractTarget(
            from: value, sessionID: "2026-08-08-001", createdAt: "t"))
        XCTAssertEqual(card.primary, archived.label)
        XCTAssertEqual(card.id, archived.targetKey)
        XCTAssertEqual(card.note, archived.evidence.joined(separator: "；"))
    }

    /// label 为空、只有 id 时，卡片退回显示 targetKey，而不是一块没有标题的深色空条。
    /// 做法与复训中心 `RetrainingCenterView.title(for:)` 一致。
    func testACardWithoutALabelFallsBackToTheTargetKeyInsteadOfShowingNothing() throws {
        let card = try XCTUnwrap(ReviewReportViewModel.priorityTarget(
            from: try report(#"{"priority_target":{"id":"logic-explain"}}"#), sessionID: "s1"))
        XCTAssertEqual(card.primary, "logic-explain")
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
