import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// **开练之前那一步：勾这一场练哪几个 Part，再挑题。**
///
/// 用户第一次要的是「可以选择是训练 part one part two 还是 part three」——做成了四选一。
/// 真机用过之后他补了一句：
///
/// > 我发现你这个目前练习好像无法同时选择多个问题啊。
/// > 比如我要多选 Part one 和 Part two，练完这个练那个。
///
/// 于是分段控件换成了三个勾选框，那颗「练完 Part 2 接着练 Part 3」开关一并删掉
///（勾上 Part 2 和 Part 3 就是它）。
///
/// 逻辑（怎么筛、默认勾哪几个、空了说什么、翻译成哪一档考法）在 `PracticePicker` 里，可测；
/// 「这段逻辑真的被画到屏幕上、并且真的连到那张列表和这一场上」只能扫源码
/// （`SourceGuard`，读不到文件会抛错，不会拿空串把断言变成永远绿）。
final class PracticePickerTests: XCTestCase {

    private static let sheet = "Session/PracticeSheet.swift"

    private func question(_ id: String, part: Int, topic: String = "T") -> Question {
        Question(id: id, part: part, topic: topic, prompt: "\(id) prompt")
    }

    private var bank: [Question] {
        [question("a", part: 1), question("b", part: 1),
         question("c", part: 2),
         question("d", part: 3), question("e", part: 3), question("f", part: 3)]
    }

    // MARK: - 筛

    func testEachPartListsOnlyItsOwnQuestions() {
        let picker = PracticePicker(questions: bank)
        XCTAssertEqual(picker.questions(inParts: [1]).map(\.id), ["a", "b"])
        XCTAssertEqual(picker.questions(inParts: [2]).map(\.id), ["c"])
        XCTAssertEqual(picker.questions(inParts: [3]).map(\.id), ["d", "e", "f"])
    }

    /// 一个都不勾就是**全部**，而且顺序原样不动。
    ///
    /// 在这里重排一次的话，改一下勾选又改回来，列表顺序就变了，
    /// 用户刚才看到的那一道再也找不回来。顺序归 `TodayViewModel.pickableQuestions`
    /// 定（先按 Part、再按题库原顺序），这里只筛不排。
    func testNoPartTickedListsEverythingInTheOrderItWasGiven() {
        let picker = PracticePicker(questions: bank)
        XCTAssertEqual(picker.questions(inParts: PracticePicker.unspecified).map(\.id),
                       bank.map(\.id))
        XCTAssertTrue(PracticePicker.unspecified.isEmpty,
                      "「不指定」必须是空集合——`questions(inParts:)` 靠 `min()` 为 nil 认它")
    }

    /// **勾了两个以上时，列表只列开场那一段的题。**
    ///
    /// 一场练习只带一道题（`SessionSetup`），而这道题必须落在某一段上。
    /// 勾了 Part 1 + Part 2 时它落在 Part 1，cue card 由考官自己挑——
    /// 真实考试里 cue card 本来也不是考生选的。这一条和排计划那侧
    /// （`PlanScope.select` 同样只排开场那个 Part）必须一致，否则
    /// 「按计划练今天」和「自由选题」会在同一档考法下给出不同的题。
    func testACombinedSelectionOnlyListsTheOpeningPart() {
        let picker = PracticePicker(questions: bank)
        XCTAssertEqual(picker.questions(inParts: [1, 2]).map(\.id), ["a", "b"],
                       "勾了 1+2 应该只列 Part 1 的题（开场那一段）")
        XCTAssertEqual(picker.questions(inParts: [2, 3]).map(\.id), ["c"])
        XCTAssertEqual(picker.questions(inParts: [1, 2, 3]).map(\.id), ["a", "b"])
    }

    /// 三个勾选框，就是 1 / 2 / 3。
    func testTheThreeCheckboxesAreTheThreeParts() {
        XCTAssertEqual(PracticePicker.selectableParts, [1, 2, 3])
        XCTAssertEqual(PracticePicker.selectableParts.map(PracticePicker.partTitle(forPart:)),
                       ["Part 1", "Part 2", "Part 3"])
    }

    // MARK: - 勾选 → 这一场按哪套考法跑

    /// **七种组合一个不少，而且顺序永远是 Part 1 → 2 → 3。**
    ///
    /// 这就是用户要的那个功能本身。少一种组合，界面上勾得出来、考法却落回别的档，
    /// 而屏幕上一个字都不会提。
    func testEveryCombinationOfTicksBecomesItsOwnFocusPart() {
        let cases: [(Set<Int>, FocusPart)] = [
            ([1], .part1), ([2], .part2), ([3], .part3),
            ([1, 2], .part1And2), ([1, 3], .part1And3), ([2, 3], .part2And3),
            ([1, 2, 3], .fullMock)
        ]
        for (ticks, expected) in cases {
            XCTAssertEqual(PracticePicker.mode(forParts: ticks), expected,
                           "勾了 \(ticks.sorted()) 没有变成 \(expected.rawValue)")
        }
        XCTAssertEqual(Set(cases.map(\.1)), Set(FocusPart.allCases),
                       "有一档考法在界面上勾不出来")
    }

    /// **一个都不勾 = 不指定**，不是「全都要」。
    ///
    /// 把「都不勾」读成「跑一整场三 Part 模考」是替用户做一个他没做的决定——
    /// 他刚刚的动作恰恰是「一个都没勾」。
    func testTickingNothingMeansUnspecifiedRatherThanEverything() {
        XCTAssertNil(PracticePicker.mode(forParts: PracticePicker.unspecified),
                     "一个都没勾却带出了一档考法，这一场会被改成他没选过的样子")
        XCTAssertNotEqual(PracticePicker.mode(forParts: PracticePicker.unspecified), .fullMock)
    }

    /// 越界的勾（不该出现，但真出现了也不能把它算成一个 Part）。
    func testAnOutOfRangeTickIsNotSilentlyTreatedAsAPart() {
        XCTAssertNil(PracticePicker.mode(forParts: [9]),
                     "Part 9 被当成了某个真实的 Part")
        XCTAssertEqual(PracticePicker.mode(forParts: [2, 9]), .part2,
                       "脏勾选把这一场拧成了别的考法")
    }

    // MARK: - 每一档底下有多少题

    /// 三个勾选框只有三个词。不把题数摆出来的话，用户勾了 Part 2 才发现是空的，
    /// 再取消——一次白跑。
    func testTheCountsLineSaysHowManyQuestionsSitBehindEachPart() {
        let line = PracticePicker(questions: bank).countsLine
        for expected in ["共 6 道", "Part 1 2 道", "Part 2 1 道", "Part 3 3 道"] {
            XCTAssertTrue(line.contains(expected), "「\(expected)」没出现在：\(line)")
        }
    }

    /// 列表上方那一句要把**这一场会怎么考**说清楚，三种勾选状态各一句。
    func testTheSelectionSummarySaysWhatWillActuallyHappen() {
        let picker = PracticePicker(questions: bank)

        let none = picker.selectionSummary(forParts: PracticePicker.unspecified)
        XCTAssertTrue(none.contains("6 道"), none)
        XCTAssertTrue(none.contains("你挑的那道题决定"),
                      "没说清都不勾时练哪个 Part 由谁决定：" + none)

        let single = picker.selectionSummary(forParts: [3])
        XCTAssertTrue(single.contains("只练 Part 3"), single)
        XCTAssertTrue(single.contains("3 道"), single)

        // 勾了两个却只看到一段的题，是最容易被误读成「那一勾没生效」的一幕，
        // 所以这一句必须同时说清顺序、列的是哪一段、另一段的题从哪儿来。
        let combined = picker.selectionSummary(forParts: [2, 3])
        XCTAssertTrue(combined.contains("Part 2 → Part 3"),
                      "没说清连着练的顺序：" + combined)
        XCTAssertTrue(combined.contains("1 道"),
                      "没说清列出来的是开场那一段的几道题：" + combined)
        XCTAssertTrue(combined.contains("考官"),
                      "没交代 Part 3 的题目从哪儿来，用户会以为它被漏掉了：" + combined)
    }

    // MARK: - 这次勾选下一道题都没有

    /// 空档不许给白板：说明现状 + 说明下一步，而下一步指的那几个勾选框就在这句话上面。
    func testAnEmptySelectionExplainsItselfAndPointsAtAControlThatExists() throws {
        let onlyPart1 = PracticePicker(questions: [question("a", part: 1)])
        let notice = try XCTUnwrap(onlyPart1.emptyNotice(forParts: [2]),
                                   "Part 2 一道题都没有，却什么都不说——用户看到的是一片空白")
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("Part 2"),
                      "没指出是哪个勾造成的空列表：" + notice)

        // 有题的那一档、以及「一个都不勾」都不该出现这段话。
        XCTAssertNil(onlyPart1.emptyNotice(forParts: [1]))
        XCTAssertNil(onlyPart1.emptyNotice(forParts: PracticePicker.unspecified))
    }

    /// 题库整个是空的时候，说法要换一句——那时取消勾选也没有题，
    /// 让他去改勾等于把他指向一件做了也没用的事。
    func testAnEmptyBankSaysSomethingDifferentFromAnEmptyPart() throws {
        let notice = try XCTUnwrap(PracticePicker(questions: []).emptyNotice(forParts: [1]))
        XCTAssertTrue(notice.contains("训练题库"), notice)
        XCTAssertFalse(notice.contains("把上面"),
                       "题库空的时候还劝人去改勾选，改完同样一道题都没有：" + notice)
    }

    /// **题库空着、又一个 Part 都没勾** —— 刚装好的用户正好落在这一格。
    ///
    /// 2026-08-09 复审实测：这一格返回 nil，于是 `PracticeSheet` 走 else 分支，
    /// `sectionsNotice`（0 栏时为 nil）和 `questionSections`（0 栏）都画不出东西，
    /// 屏幕上是一段说明文字底下一片空白，没有任何交代。
    ///
    /// 走到这一格不需要任何异常操作：`defaultParts(forPlanFocus: nil)` 就是
    /// 「一个都不勾」，而还没建过学习计划、还没导过题库的人两个条件同时成立。
    func testAnEmptyBankWithNothingTickedStillExplainsItself() throws {
        let notice = try XCTUnwrap(
            PracticePicker(questions: []).emptyNotice(forParts: PracticePicker.unspecified),
            "题库空着又一个 Part 都没勾时什么都不说——用户看到的是一片空白（铁律：空状态必须有说明）")
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("训练题库"),
                      "没告诉他去哪儿导题库：" + notice)
        XCTAssertFalse(notice.contains("把上面"),
                       "一个都没勾的时候劝他「把上面某个勾去掉」，那个勾根本不存在：" + notice)
    }

    // MARK: - 默认勾哪几个：与学习计划的「重点 Part」的关系

    /// 默认勾选跟着学习计划的「重点 Part」走。
    ///
    /// **这是这两处 Part 选择「不打架」的做法**：计划里选了 Part 2 + Part 3，
    /// 开练弹层默认就把这两个勾上；两者因此像同一件事的两个层次。
    func testTheDefaultTicksFollowThePlansFocusPart() {
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .part1), [1])
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .part2), [2])
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .part3), [3])
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .part1And2), [1, 2])
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .part2And3), [2, 3],
                       "计划里选了「连着练」，弹层却没把两个都勾上——"
                           + "他会以为那个选择根本没生效")
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: .fullMock), [1, 2, 3],
                       "计划里选的是全真模考，默认就该是那一场")
        XCTAssertEqual(PracticePicker.defaultParts(forPlanFocus: nil),
                       PracticePicker.unspecified,
                       "还没有学习计划时不该凭空替他勾上哪个 Part")
    }

    /// 每一档考法都要能从「默认勾选」原样再翻译回它自己。
    ///
    /// 这条守的是一个真会发生的漂移：`defaultParts` 与 `mode(forParts:)` 各写一份映射，
    /// 其中一处漏了一档，用户按计划打开弹层看到的勾是对的、
    /// 点下去练的却是另一档考法——两处都各自「测得很好看」。
    func testTheDefaultTicksTranslateBackIntoExactlyThatFocusPart() {
        for focus in FocusPart.allCases {
            XCTAssertEqual(PracticePicker.mode(forParts:
                            PracticePicker.defaultParts(forPlanFocus: focus)), focus,
                           "\(focus.rawValue) 默认勾出来的那几个 Part 翻译回去不是它自己")
        }
    }

    /// 默认勾选是从计划带过来的时候必须解释它是从哪儿来的，否则用户会以为题库里别的 Part 没了。
    ///
    /// 而且要说清**在这儿改勾不会改学习计划**——一次临时选择偷偷改掉一份长期计划，
    /// 是最让人不信任的那种行为。
    func testWhenTheDefaultComesFromThePlanItSaysSoAndSaysItIsNotSticky() throws {
        let notice = try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2))
        XCTAssertTrue(notice.contains("学习计划"), notice)
        XCTAssertTrue(notice.contains(PlanScope.label(for: .part2)),
                      "没说清默认勾的是哪一档：" + notice)
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("学习计划不会跟着改"),
                      "没说清在这儿改勾会不会改掉计划，用户不敢动：" + notice)

        XCTAssertNil(PracticePicker.planFocusNotice(for: nil),
                     "没有计划时默认一个都不勾，没有什么要解释的，多一句话是骚扰")
    }

    /// 计划选的是组合档时，那句说明必须交代**列表只列开场那一段**。
    ///
    /// 不说的话，用户看到一列 Part 2 的题，会以为计划里那个「连着练」没生效。
    func testThePlanNoticeExplainsWhyOnlyOnePartIsListedForACombinedPlan() throws {
        let notice = try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2And3))
        XCTAssertTrue(notice.contains("开场"),
                      "没说清列表列的是哪一段的题：" + notice)
        XCTAssertTrue(notice.contains("Part 2"), notice)
        XCTAssertTrue(notice.contains("下一步"), notice)

        XCTAssertFalse(try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2))
            .contains("开场"),
                       "单 Part 的说明里不该提「开场那一段」——那一档只有一段")
    }

    // MARK: - 这些真的被画到弹层上了吗

    /// **写好了和摆上屏幕了是两件事**，本项目已经在四个地方分别栽过这同一跤。
    ///
    /// 实测过的突变：把 `partSection` 里那个 `ForEach` 换成 `EmptyView()`——
    /// `PracticePicker` 的全部逻辑测试照样绿，而用户那边「勾这一场练哪几个 Part」
    /// 这个功能整个不存在。
    func testTheThreeCheckboxesAreActuallyOnTheSheetAndBoundToTheSelection() throws {
        let code = try SourceGuard.code(Self.sheet)

        // 勾选框标题走 `partTitle`，而它的绑定必须是 `partBinding(for:)`——
        // 三个勾各绑一个独立的 Bool 的话，`partSelection` 那个集合永远是空的。
        XCTAssertTrue(
            code.contains("Toggle(PracticePicker.partTitle(forPart: part), "
                          + "isOn: partBinding(for: part))"),
            "挑题弹层上没有那三个绑到 `partBinding(for:)` 的勾选框。"
                + "用户要的第一件事（多选 Part）整个不存在，"
                + "而 `PracticePicker` 的逻辑测试全都照绿。"
                + "下一步：把 `PracticeSheet.partSection` 里那三颗 Toggle 放回去。")

        XCTAssertTrue(code.contains("ForEach(PracticePicker.selectableParts"),
                      "勾选框不是照 `selectableParts` 画的，界面上有几个 Part 就成了另写一份。"
                          + "下一步：`ForEach(PracticePicker.selectableParts, id: \\.self)`。")

        SourceGuard.assertRenders(
            "partSection", inBodyOf: "private var picker", of: Self.sheet,
            because: "`partSection` 只是声明着，没有被摆进挑题那一段——一个像素都不上屏。"
                + "下一步：把它放回 `picker` 的 VStack 里。")

        for piece in ["countsLine", "selectionSummary", "planFocusNotice"] {
            SourceGuard.assertRenders(
                piece, inBodyOf: "private var partSection", of: Self.sheet,
                because: "`\(piece)` 没画在勾选框旁边。三个格子只剩三个词，"
                    + "用户勾之前不知道每一档底下有没有题、默认这几个勾是从哪儿来的。"
                    + "下一步：把它放回 `partSection`。")
        }
    }

    /// **筛完的结果得真的用在列表上。**
    ///
    /// 这是这个功能唯一可能「装出来」的失效形态：控件在、文案在、`visibleCandidates`
    /// 也算得好好的，而列表那一行还是 `ForEach(candidates)`——勾选框点起来毫无反应，
    /// 而上面每一条断言都是绿的。
    func testTheListRendersTheFilteredQuestionsNotTheWholeBank() throws {
        let code = try SourceGuard.code(Self.sheet)

        let visible = try SourceGuard.memberBody(of: "private var visibleCandidates", in: code)
        XCTAssertTrue(visible.contains("questions(inParts: partSelection)"),
                      "列表不是按当前勾选筛的，那几个勾会变成点了没反应的装饰品。"
                          + "下一步：`partPicker.questions(inParts: partSelection)`。"
                          + "实际取到的是：\n\(visible)")

        let sections = try SourceGuard.memberBody(of: "private var sectionsByPart", in: code)
        XCTAssertTrue(sections.contains("QuestionPartSections.split(visibleCandidates)"),
                      "分栏不是从筛过的结果分出来的。下一步："
                          + "`QuestionPartSections.split(visibleCandidates) { $0.part }`。"
                          + "实际取到的是：\n\(sections)")
        XCTAssertFalse(sections.contains("split(candidates)"),
                       "分栏还是从全库分的：\n\(sections)")

        let list = try SourceGuard.memberBody(of: "private var questionSections", in: code)
        XCTAssertTrue(list.contains("ForEach(sectionsByPart)"),
                      "挑题列表没有遍历分好的那几栏。下一步：`ForEach(sectionsByPart)`。"
                          + "实际取到的是：\n\(list)")
        XCTAssertFalse(list.contains("ForEach(candidates)"),
                       "挑题列表还在画全库。下一步：改成 `ForEach(sectionsByPart)`。")
    }

    /// 改完勾选之后，上一次勾选下挑好的那道题必须失效。
    ///
    /// 不清掉的话：选了 Part 1 的一道题 → 改勾成 Part 2 → 点「开始练习」，
    /// 练的是屏幕上一道也看不见的题。这是真会发生的一次「静默做错事」。
    func testChangingTheTicksDropsASelectionThatIsNoLongerVisible() throws {
        let code = try SourceGuard.code(Self.sheet)
        let binding = try SourceGuard.functionBody(named: "partBinding", in: code)
        XCTAssertTrue(binding.contains("self.picked = nil"),
                      "改勾选时没有清掉已经看不见的那道题。"
                          + "点「开始练习」会练到一道屏幕上看不见的题。"
                          + "下一步：在 `partBinding(for:)` 的 setter 里，"
                          + "把不在当前列表里的选择清掉。实际取到的是：\n\(binding)")
        XCTAssertTrue(binding.contains("expandedParts = nil"),
                      "改勾选之后展开状态没有重算，刚勾上的那一栏还折着。"
                          + "实际取到的是：\n\(binding)")

        let start = try SourceGuard.functionBody(named: "startPicked", in: code)
        XCTAssertTrue(start.contains("pickedQuestion"),
                      "「开始练习」是从全库里找那道题的——改勾之后残留的 id 照样找得到，"
                          + "于是练的是屏幕上看不见的那道题。"
                          + "下一步：只认 `pickedQuestion`。实际取到的是：\n\(start)")
        XCTAssertFalse(start.contains("candidates.first"),
                       "`startPicked` 还在全库里找题：\n\(start)")

        // 而 `pickedQuestion` 只认**展开的那几栏里**的题：那条链断在这一环的话，
        // 上面那句 `pickedQuestion` 照样绿，而折起来的栏里那道题仍然练得起来。
        let resolved = try SourceGuard.memberBody(of: "private var pickedQuestion", in: code)
        XCTAssertTrue(resolved.contains("visibleInExpandedSections"),
                      "`pickedQuestion` 不是从展开的那几栏里找的。改勾或者折起一栏之后，"
                          + "残留的那个 id 照样找得到题，练的是屏幕上一道也看不见的题。"
                          + "下一步：只在 `visibleInExpandedSections` 里找。实际取到的是：\n\(resolved)")
    }

    /// **那几个勾真的连到这一场的考法上。**
    ///
    /// 这是这个功能第二种可能「装出来」的失效形态：`PracticePicker` 那几条逻辑测试全绿，
    /// 而 `startPicked()` 拿写死的 `nil` 去开练（勾了不算数，屏幕上毫无异样）。
    func testTheTicksReachTheSessionThroughTheExplicitEntryPoint() throws {
        let code = try SourceGuard.code(Self.sheet)
        let start = try SourceGuard.functionBody(named: "startPicked", in: code)
        XCTAssertTrue(start.contains("PracticePicker.mode(forParts: partSelection)"),
                      "「开始练习」没有把那几个勾带进这一场。勾点得动、"
                          + "练的却仍是那道题自己的 Part，而界面上看不出任何异样。"
                          + "下一步：`makeSetup(question, PracticePicker.mode(forParts: partSelection))`。"
                          + "实际取到的是：\n\(start)")

        // 今日训练页得把这个参数继续往解析器传，而且必须走 `chosen:` 那个入口：
        // 走 `mode:` 的话，三个全勾会被 `FocusPart.forSession` 静默降级成单 Part。
        let today = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(today.contains("makeSetup: { question, mode in"),
                      "今日训练页的 `makeSetup` 没有接收用户当场勾的那几个 Part。")
        XCTAssertTrue(today.contains("chosen: mode"),
                      "今日训练页把勾选当成了学习计划的重点 Part（`mode:`）往下传，"
                          + "而那条路会过滤掉组合档——三个全勾会被静默降级成单 Part。"
                          + "下一步：`PracticeRouteResolver.setup(for:goal:defaults:chosen:bank:)`。")
        XCTAssertTrue(today.contains("bank: app.state.questions"),
                      "今日训练页没有把题库传下去，连着练那一场配不到"
                          + "「这张 cue card 自己那组 Part 3 追问」（`LinkedPart3`），"
                          + "题库里现成的真题被白白扔掉。"
                          + "下一步：`bank: app.state.questions`。")
    }

    /// 弹层默认勾的那几个必须真的是调用方按学习计划算出来的。
    ///
    /// 少了这一条，`defaultParts(forPlanFocus:)` 可以测得很好看，
    /// 而今日训练页压根没把它传进来（弹层永远一个都不勾）。
    func testTodayPageFeedsThePlansFocusPartIntoTheSheet() throws {
        let today = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(
            today.contains("PracticePicker.defaultParts(") && today.contains("planFocusPart:"),
            "今日训练页没有把学习计划的重点 Part 传给挑题弹层。"
                + "于是计划里选了 Part 2，开练弹层却一个都不勾——两处 Part 选择看起来"
                + "各说各话。下一步：`defaultParts: PracticePicker.defaultParts(forPlanFocus: "
                + "app.state.plan?.focusPart)`，并把 `planFocusPart` 一起传下去。")
    }

    /// 学习计划页得说清「重点 Part」和开练时那几个勾各管什么。
    ///
    /// App 里现在有两处能选 Part。不说清的话，用户会以为它们是同一个设置的两份界面，
    /// 然后开始怀疑「我在这儿选了 Part 2，为什么那边还能选 Part 1」。
    @MainActor
    func testThePlanPageExplainsHowItsFocusPartRelatesToThePracticeSheet() throws {
        let note = PlanView.focusScopeNote
        XCTAssertTrue(note.contains("这份计划"), note)
        XCTAssertTrue(note.contains("开始练习"),
                      "没指出那几个 Part 勾选框从哪儿去：" + note)
        XCTAssertTrue(note.contains("不会动这份计划"),
                      "没说清在弹层里改勾会不会改掉计划：" + note)
        // 组合档在弹层上是「勾两个、只列开场那一段的题」，这一点必须在这儿说清；
        // 否则用户在计划里选了它，到弹层看到一列 Part 2 的题，会以为选择没生效。
        XCTAssertTrue(note.contains("连着练") && note.contains("开场"),
                      "没说清两个 Part 连着练时那张弹层长什么样：" + note)

        SourceGuard.assertRenders(
            "focusScopeNote", inBodyOf: "private var focusPicker", of: "Plan/PlanView.swift",
            because: "这句说明只是声明着，没有画在「重点 Part」那组单选按钮下面。"
                + "下一步：把它放回 `focusPicker`。")
    }
}
