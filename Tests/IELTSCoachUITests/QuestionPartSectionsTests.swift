import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// **挑题列表按 Part 分栏。** 用户原话（真机反馈，他本人是考生）：
///
/// > 你可以把它做成三栏，Part one 一栏，Part one 一堆，然后 part two 一堆，
/// > 然后 part three 一堆。
///
/// 题库现在 258 道（Part 1 60 / Part 2 99 / Part 3 99），此前是一张平铺列表、
/// Part 1 全排在最前面：想练 Part 3 得滑过 159 条。
///
/// 分栏逻辑（怎么分、默认展开哪一栏、折起来的那几栏算不算数、要对用户说什么）
/// 在 `QuestionPartSections` 里，可测；
/// 「这段逻辑真的被画到屏幕上、而且两处挑题列表用的是同一个」只能扫源码
/// （`SourceGuard`，读不到文件会抛错，不会拿空串把断言变成永远绿）。
final class QuestionPartSectionsTests: XCTestCase {

    private static let sheet = "Session/PracticeSheet.swift"
    private static let flow = "Retraining/RetrainingFlowView.swift"
    private static let shell = "Session/QuestionPartSections.swift"

    private func question(_ id: String, part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "\(id) prompt")
    }

    /// 三个 Part 都有题，且**给进去的顺序是乱的**——分栏之后 Part 得排好，
    /// 而栏内必须保持给进去的先后。
    private var bank: [Question] {
        [question("p2-a", part: 2),
         question("p1-a", part: 1),
         question("p3-a", part: 3),
         question("p1-b", part: 1),
         question("p3-b", part: 3)]
    }

    private func sections(_ questions: [Question]) -> [QuestionPartSection<Question>] {
        QuestionPartSections.split(questions) { $0.part }
    }

    // MARK: - 分栏本身

    /// 一栏一个 Part，Part 小的在前。
    func testTheListIsSplitIntoOneSectionPerPartInAscendingOrder() {
        XCTAssertEqual(sections(bank).map(\.part), [1, 2, 3])
        XCTAssertEqual(sections(bank).map { $0.items.count }, [2, 1, 2])
    }

    /// **栏内顺序原样保留。**
    ///
    /// 在这里重排一次的话，展开收起一次列表顺序就变了，用户刚才看到的那一道就找不回来。
    /// 顺序归调用方定（自由选题那边是 `TodayViewModel.pickableQuestions`，
    /// 复训换题那边是 `TransferQuestionPolicy` 那份「换了话题的排前面」）——
    /// 在这里再排一次等于把那两处的排序悄悄推翻。
    ///
    /// **不用下标取栏**：分栏一旦返回空数组（整段被掏空的那种改法），下标会让整个
    /// 测试进程崩掉，而崩掉的进程只会带走后面几百条测试，不会给出一句读得懂的失败原因。
    func testEachSectionKeepsTheOrderItWasGiven() {
        XCTAssertEqual(sections(bank).map { $0.items.map(\.id) },
                       [["p1-a", "p1-b"], ["p2-a"], ["p3-a", "p3-b"]],
                       "分栏之后每一栏里的顺序变了（或者整个分栏根本没分出来）。"
                           + "顺序归调用方定，在这里重排一次的话，"
                           + "展开收起一次列表顺序就变了，用户刚才看到的那一道就找不回来。")
    }

    /// **一道题都不许在分栏时消失。**
    ///
    /// 题库是用户自己导入的，`Question.part` 是个 Int，导进来一条 part 是 0 或 4 的题
    /// 完全可能。写死「只分 1/2/3 三栏」的话，那几条会一声不响地从挑题列表里没掉——
    /// 用户在训练题库页数得到 258 道，在挑题弹层里只看得见 257 道，
    /// 而界面上没有任何异样（铁律 5：禁止静默失败）。
    func testNoQuestionIsSilentlyDroppedEvenWhenItsPartIsNotOneTwoOrThree() {
        let odd = bank + [question("weird-0", part: 0), question("weird-4", part: 4)]
        let split = sections(odd)
        XCTAssertEqual(split.flatMap { $0.items }.count, odd.count,
                       "分栏之后少了题。少掉的那几条在界面上没有任何痕迹，"
                           + "用户只会觉得「我导进去的那道题不见了」。")
        XCTAssertEqual(Set(split.map(\.part)), [0, 1, 2, 3, 4])
        XCTAssertEqual(split.map(\.part), [0, 1, 2, 3, 4], "栏序仍然要按 Part 从小到大")
    }

    func testAnEmptyListProducesNoSections() {
        XCTAssertTrue(sections([]).isEmpty)
    }

    // MARK: - 栏标题

    /// 条数**必须写在栏标题上**：折起来的时候，用户唯一能据以决定「点不点开」的就是这一行。
    func testTheSectionTitleCarriesThePartAndHowManyQuestionsAreInIt() {
        XCTAssertEqual(QuestionPartSections.title(forPart: 1, count: 60), "Part 1 · 60 道")
        XCTAssertEqual(sections(bank).map(\.title),
                       ["Part 1 · 2 道", "Part 2 · 1 道", "Part 3 · 2 道"])
        for section in sections(bank) {
            XCTAssertTrue(section.title.contains("\(section.items.count) 道"),
                          "栏标题上没有条数，折起来之后这一栏是个黑盒：" + section.title)
        }
    }

    // MARK: - 默认展开哪一栏

    /// 用户已经表达过偏好（分段控件停在 Part 3、或学习计划的重点 Part 是 Part 3）时，
    /// **直接展开那一栏**。这正是用户抱怨的那一句：
    /// 「他选了只练 Part 3，就该直接看到 Part 3 那一堆，而不是从 Part 1 开始滑。」
    func testThePreferredPartIsTheOneThatOpens() {
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [1, 2, 3], preferredPart: 3),
            [3])
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [1, 2, 3], preferredPart: 1),
            [1])
    }

    /// **没有偏好时一栏都不展开。**
    ///
    /// 替他展开哪一栏都是替他做了选择，而展开 Part 1 恰好就是他抱怨的那个毛病：
    /// Part 1 那 60 条挡在最前面。这时屏幕上是三行带条数的栏标题，一眼看清、一点直达。
    func testWithoutAPreferenceNothingIsOpenedForTheUser() {
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [1, 2, 3], preferredPart: nil),
            [],
            "没有偏好却替用户展开了一栏——展开的多半是 Part 1，那正是他抱怨的那个毛病")
    }

    /// 偏好指着一个当前根本没有的 Part 时，不许假装展开了它。
    func testAPreferenceForAPartThatIsNotThereOpensNothing() {
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [1, 2], preferredPart: 3), [])
    }

    /// **只有一栏时展开它。**
    ///
    /// 那时分栏没有在替用户做任何选择（分段控件已经停在某一个 Part 上，
    /// 或者复训换题本来就不跨 Part），折起来只是让他多点一下才看得见题。
    func testASingleSectionIsAlwaysOpen() {
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [3], preferredPart: nil), [3])
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [3], preferredPart: 1), [3])
        XCTAssertEqual(
            QuestionPartSections.defaultExpandedParts(inSections: [], preferredPart: 2), [])
    }

    // MARK: - 折起来的那几栏不算数

    /// **挑题那一步只认展开的那几栏。**
    ///
    /// 不然会出现本项目最忌讳的那种事：用户选中一道题、把那一栏折起来、
    /// 再点「开始练习」，练的是屏幕上一道也看不见的题
    ///（和切换 Part 档位时必须清掉旧选择是同一条道理）。
    func testOnlyTheQuestionsInsideOpenSectionsCountAsVisible() {
        let split = sections(bank)
        XCTAssertEqual(
            QuestionPartSections.visibleItems(in: split, expandedParts: [3]).map(\.id),
            ["p3-a", "p3-b"])
        XCTAssertEqual(
            QuestionPartSections.visibleItems(in: split, expandedParts: []).map(\.id), [],
            "一栏都没展开时屏幕上一道题都看不见，这时「看得见的题」必须是空的")
        XCTAssertEqual(
            QuestionPartSections.visibleItems(in: split, expandedParts: [1, 2, 3]).map(\.id),
            ["p1-a", "p1-b", "p2-a", "p3-a", "p3-b"],
            "全展开时得按栏序给全，顺序也得和屏幕上一致")
    }

    // MARK: - 对用户说的那一句

    /// 分成几栏时要说清「发生了什么」和「下一步做什么」（铁律 4），
    /// 而下一步指的那几行栏标题就在这句话下面，是真的可以点的。
    func testTheNoticeSaysWhatHappenedAndWhatToDoNext() throws {
        let line = try XCTUnwrap(QuestionPartSections.notice(for: sections(bank)),
                                 "分成了三栏却什么都不说，用户不知道题去哪儿了")
        XCTAssertTrue(line.contains("5 道"), "没说清一共多少道：" + line)
        XCTAssertTrue(line.contains("3 栏"), "没说清分成了几栏：" + line)
        XCTAssertTrue(line.contains("下一步"), "没说下一步做什么：" + line)
        XCTAssertTrue(line.contains("点开"), "下一步没落到一个具体动作上：" + line)
    }

    /// 只有一栏时不说这句话——那时屏幕上就是一栏题，多一句话是骚扰。
    func testTheNoticeStaysQuietWhenThereIsOnlyOneSection() {
        XCTAssertNil(QuestionPartSections.notice(for: sections([question("a", part: 1)])))
        XCTAssertNil(QuestionPartSections.notice(for: sections([])))
    }

    // MARK: - 这些真的被画到屏幕上了吗

    /// **写好了和摆上屏幕了是两件事**，本项目已经在四五个地方分别栽过这同一跤。
    ///
    /// 实测过的突变：把 `PracticeSheet.questionSections` 的函数体换成 `EmptyView()`——
    /// 上面每一条逻辑断言照样绿，而用户那边挑题弹层里一道题都看不见。
    func testTheSheetActuallyPaintsTheSections() throws {
        let code = try SourceGuard.code(Self.sheet)

        SourceGuard.assertRenders(
            "questionSections", inBodyOf: "private var picker", of: Self.sheet,
            because: "分栏列表只是声明着，没有被摆进挑题那一段——一个像素都不上屏，"
                + "而这不会有任何编译错误。用户看到的是：选完 Part 之后一道题都没有。"
                + "下一步：把 `questionSections` 放回 `picker` 的 VStack 里。")

        SourceGuard.assertRenders(
            "sectionsNotice", inBodyOf: "private var picker", of: Self.sheet,
            because: "分栏那句交代没上屏。用户看到三行折起来的标题，不知道该点哪儿。"
                + "下一步：把 `sectionsNotice` 放回 `picker`。")

        let list = try SourceGuard.memberBody(of: "private var questionSections", in: code)
        for (piece, what) in [
            ("QuestionPartSectionView", "可折叠的栏外壳（和复训换题共用的那一个）"),
            ("section.title", "栏标题上那句「Part 1 · 60 道」"),
            ("expansion(of: section.part)", "这一栏展开与否——绑不上的话点了不会动"),
            ("questionRow(question)", "栏里的每一道题")
        ] {
            XCTAssertTrue(list.contains(piece),
                          "挑题列表里没有\(what)（`\(piece)`）。实际取到的是：\n\(list)")
        }
    }

    /// 复训换题那张列表是同一件事的另一处。**这个项目反复出现「改了一处、另一处照旧」**，
    /// 所以这一条单独钉住它。
    func testTheRetrainingCandidateListPaintsTheSameSections() throws {
        let code = try SourceGuard.code(Self.flow)
        let picker = try SourceGuard.memberBody(of: "private var questionPicker", in: code)
        for (piece, what) in [
            ("sectionsNotice", "分栏那句交代"),
            ("QuestionPartSectionView", "可折叠的栏外壳（和自由选题弹层共用的那一个）"),
            ("section.title", "栏标题上那句「Part 3 · 99 道」"),
            ("expansion(of: section.part)", "这一栏展开与否"),
            ("candidateRow(candidate)", "栏里的每一条候选")
        ] {
            XCTAssertTrue(picker.contains(piece),
                          "复训换题那张列表里没有\(what)（`\(piece)`）。"
                              + "自由选题弹层分了栏、这里照旧平铺的话，"
                              + "同一件事在 App 里就有了两个样子。实际取到的是：\n\(picker)")
        }
    }

    /// **两处必须共用同一个外壳，不许各写一份 `DisclosureGroup`。**
    ///
    /// 各写各的话，两处的折叠交互会长成两个样子（一处有箭头一处没有、字号不同、
    /// 点标题能不能展开也不同），而这不会体现在任何一条测试上——
    /// 正是本项目文档里点名的「界面显得业余的头号原因」。
    func testBothPickersUseTheOneSharedSectionShell() throws {
        for file in [Self.sheet, Self.flow] {
            let code = try SourceGuard.code(file)
            XCTAssertFalse(code.contains("DisclosureGroup("),
                           "\(file) 里自己又写了一个 `DisclosureGroup`。"
                               + "下一步：用共用的 `QuestionPartSectionView`——"
                               + "两处挑题列表的折叠交互必须一模一样。")
        }

        let shell = try SourceGuard.code(Self.shell)
        let body = try SourceGuard.memberBody(of: "public var body", in: shell)
        XCTAssertTrue(body.contains("DisclosureGroup(isExpanded: $isExpanded)"),
                      "栏外壳没有绑到 `isExpanded` 上——点标题不会展开，"
                          + "而「默认展开哪一栏」那一整套逻辑谁也碰不到。实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("Text(title)"),
                      "栏外壳没画标题。折起来之后屏幕上是几条没有名字的横线：\n\(body)")
        XCTAssertTrue(body.contains("content"),
                      "栏外壳没画内容。展开之后底下一道题都没有：\n\(body)")
    }

    // MARK: - 折起来之后，选中的那道题不许还算数

    /// 收起一栏的同时要把那一栏里挑好的题清掉，而「开始练习」也只认展开的那几栏。
    ///
    /// 两头都要钉：只钉按钮那一头的话，`picked` 会留着一个看不见的 id，
    /// 按钮灰着而用户不知道为什么；只钉清除那一头的话，别的路径（切档、题库变了）
    /// 仍然可能留下看不见的选择。
    func testCollapsingASectionDropsASelectionInsideIt() throws {
        for (file, holder) in [(Self.sheet, "visibleCandidates"), (Self.flow, "pickable")] {
            let expansion = try SourceGuard.functionBody(
                named: "expansion", in: try SourceGuard.code(file))
            XCTAssertTrue(expansion.contains("picked = nil"),
                          "\(file)：收起一栏时没有把那一栏里挑好的题清掉。"
                              + "屏幕上看不见的一道题仍然是「已选中」，"
                              + "而用户看不出任何异样。实际取到的是：\n\(expansion)")
            XCTAssertTrue(expansion.contains(holder),
                          "\(file)：清除那一步没有去查那道题到底在不在这一栏，"
                              + "多半会把别的栏里挑好的题一起清掉。实际取到的是：\n\(expansion)")
        }
    }

    /// 「开始练习」按钮灰不灰，得看**屏幕上还看不看得见**那道题，而不是 `picked` 空不空。
    func testTheStartButtonGreysOutWhenThePickedQuestionIsNoLongerOnScreen() throws {
        // 判据搬到了 `readyToStart`（随机抽题那条路线看的是另一样东西），
        // 所以这里钉两段：按钮问的是 `readyToStart`，而 `readyToStart` 问的是
        // `pickedQuestion` 而不是 `picked`。少钉后一段的话，把判据改回 `picked`
        // 这条测试照样全绿。
        let sheetCode = try SourceGuard.code(Self.sheet)
        let sheetActions = try SourceGuard.memberBody(of: "private var actions", in: sheetCode)
        XCTAssertTrue(sheetActions.contains("disabled(!readyToStart)"),
                      "挑题弹层的「开始练习」不再问 `readyToStart` 了。"
                          + "实际取到的是：\n\(sheetActions)")
        let readyToStart = try SourceGuard.memberBody(of: "private var readyToStart", in: sheetCode)
        XCTAssertTrue(readyToStart.contains("pickedQuestion"),
                      "挑题弹层的「开始练习」还在按 `picked == nil` 灰。"
                          + "把挑好那道题所在的栏折起来之后按钮仍然亮着，"
                          + "按下去什么都不会发生——铁律 5 说的静默失败。"
                          + "实际取到的是：\n\(readyToStart)")

        let flowCode = try SourceGuard.code(Self.flow)
        XCTAssertTrue(flowCode.contains("disabled(question == nil && pickedQuestion == nil)"),
                      "复训换题的「开始练习」还在按 `picked == nil` 灰，理由同上。")
        let start = try SourceGuard.functionBody(named: "startPractice", in: flowCode)
        XCTAssertTrue(start.contains("pickedQuestion"),
                      "复训换题开练时是从全量候选里找题的，折起来的栏里那道照样练得起来。"
                          + "实际取到的是：\n\(start)")

        // 而 `pickedQuestion` 自己也得只认展开的那几栏。少了这一句，把它改回
        // `pickable.first { … }` 照样全绿，而「折起来的栏里那道题练不起来」这件事就没人守了。
        let resolved = try SourceGuard.memberBody(of: "private var pickedQuestion", in: flowCode)
        XCTAssertTrue(resolved.contains("visibleCandidates"),
                      "复训换题的 `pickedQuestion` 不是从展开的那几栏里找的，"
                          + "折起来的栏里那道题照样练得起来——屏幕和行为对不上。"
                          + "实际取到的是：\n\(resolved)")
    }

    // MARK: - 默认展开哪一栏，得真的跟着用户的选择走

    /// **这是这个功能唯一可能「装出来」的失效形态。**
    ///
    /// `defaultExpandedParts` 那几条逻辑断言可以全绿，而两处调用方传的是写死的 `nil`——
    /// 那时用户在分段控件上选了 Part 3（或学习计划里把重点 Part 定成了 Part 3），
    /// 打开弹层看到的仍然是三栏全折着，一栏都没替他开。
    /// 用户抱怨的原话正是这一句：「他选了只练 Part 3，就该直接看到 Part 3 那一堆。」
    func testTheSectionThatOpensByDefaultFollowsWhatTheUserAlreadyChose() throws {
        let sheet = try SourceGuard.memberBody(
            of: "private var expandedPartsNow", in: try SourceGuard.code(Self.sheet))
        XCTAssertTrue(sheet.contains("preferredPart: partSelection.min()"),
                      "挑题弹层没有把用户勾的那几个 Part 当成「默认展开哪一栏」的依据。"
                          + "他勾了 Part 3，列表却还是全折着的。"
                          + "下一步：`preferredPart: partSelection.min()`——"
                          + "勾了两个以上时列表只有开场那一段，所以取最小的那个；"
                          + "一个都没勾时 `min()` 是 nil，那时确实没有偏好。实际取到的是：\n\(sheet)")
        XCTAssertFalse(sheet.contains("preferredPart: partSelection.first"),
                       "`Set` 的 `first` 顺序不定，默认展开哪一栏会随运行而变。"
                           + "下一步：用 `min()`。实际取到的是：\n\(sheet)")

        let flowCode = try SourceGuard.code(Self.flow)
        let flow = try SourceGuard.memberBody(of: "private var expandedPartsNow", in: flowCode)
        XCTAssertTrue(flow.contains("preferredPart: referencePart"),
                      "复训换题没有把原题那个 Part 当成「默认展开哪一栏」的依据。"
                          + "换题验证本来就只在同一个 Part 里换，却要用户自己去点开那一栏。"
                          + "实际取到的是：\n\(flow)")

        let reference = try SourceGuard.memberBody(of: "private var referencePart", in: flowCode)
        XCTAssertTrue(reference.contains("originalQuestion") && reference.contains("part"),
                      "`referencePart` 不是从原题（查不到时退回这一趟的题）取的 Part，"
                          + "那它指向哪一栏就没有依据了。实际取到的是：\n\(reference)")
    }
}
