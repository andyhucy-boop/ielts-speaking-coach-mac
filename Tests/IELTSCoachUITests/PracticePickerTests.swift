import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// **开练之前那一步：先选 Part 1 / 2 / 3，再挑题。**
///
/// 用户原话：「首先应该可以选择是训练 part one part two 还是 part three，
/// 这样方便区分开来选。」在这之前，「从题库自由选题」弹出来的是一张平铺的全库列表
/// （重建模之后 258 道，重建模之前 1265 道），想练 Part 2 得滚过 60 个 Part 1 话题。
///
/// 逻辑（怎么筛、默认停在哪一档、空了说什么）在 `PracticePicker` 里，可测；
/// 「这段逻辑真的被画到屏幕上、并且真的连到那张列表上」只能扫源码
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
        XCTAssertEqual(picker.questions(inPart: 1).map(\.id), ["a", "b"])
        XCTAssertEqual(picker.questions(inPart: 2).map(\.id), ["c"])
        XCTAssertEqual(picker.questions(inPart: 3).map(\.id), ["d", "e", "f"])
    }

    /// 「全部」这一档必须是**全部**，而且顺序原样不动。
    ///
    /// 在这里重排一次的话，切一下 Part 又切回来，列表顺序就变了，
    /// 用户刚才看到的那一道再也找不回来。顺序归 `TodayViewModel.pickableQuestions`
    /// 定（先按 Part、再按题库原顺序），这里只筛不排。
    func testAllPartsKeepsEveryQuestionInTheOrderItWasGiven() {
        let picker = PracticePicker(questions: bank)
        XCTAssertEqual(picker.questions(inPart: PracticePicker.allParts).map(\.id),
                       bank.map(\.id))
    }

    /// 「全部」用 0 而不是 `Int?`。Optional tag 一旦和 selection 的类型对不上，
    /// 分段控件看着能点、列表却纹丝不动，而编译器不会说一个字
    /// （`QuestionBankView.partSelection` 那一处也是同一个理由）。
    func testTheFourSegmentsAreAllPlusThreeParts() {
        XCTAssertEqual(PracticePicker.partOptions, [0, 1, 2, 3])
        XCTAssertEqual(PracticePicker.allParts, 0)
        XCTAssertEqual(PracticePicker.partOptions.map(PracticePicker.segmentTitle(forPart:)),
                       ["全部", "Part 1", "Part 2", "Part 3"])
    }

    // MARK: - 每一档底下有多少题

    /// 分段控件本身只有四个词。不把题数摆出来的话，用户点进 Part 2 才发现是空的，
    /// 再点回来——一次白跑。
    func testTheCountsLineSaysHowManyQuestionsSitBehindEachSegment() {
        let line = PracticePicker(questions: bank).countsLine
        for expected in ["共 6 道", "Part 1 2 道", "Part 2 1 道", "Part 3 3 道"] {
            XCTAssertTrue(line.contains(expected), "「\(expected)」没出现在：\(line)")
        }
    }

    func testTheSelectionSummaryCountsWhatIsActuallyListed() {
        let picker = PracticePicker(questions: bank)
        XCTAssertTrue(picker.selectionSummary(forPart: 3).contains("3 道"),
                      picker.selectionSummary(forPart: 3))
        XCTAssertTrue(picker.selectionSummary(forPart: PracticePicker.allParts).contains("6 道"),
                      picker.selectionSummary(forPart: PracticePicker.allParts))
    }

    // MARK: - 这一档一道题都没有

    /// 空档不许给白板：说明现状 + 说明下一步，而下一步指的那排按钮就在这句话上面。
    func testAnEmptyPartExplainsItselfAndPointsAtAControlThatExists() throws {
        let onlyPart1 = PracticePicker(questions: [question("a", part: 1)])
        let notice = try XCTUnwrap(onlyPart1.emptyNotice(forPart: 2),
                                   "Part 2 一道题都没有，却什么都不说——用户看到的是一片空白")
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("全部"),
                      "没告诉用户可以切回「全部」，而那正是这张弹层上唯一能立刻做的事：" + notice)

        // 「全部」这一档和有题的那些档都不该出现这段话。
        XCTAssertNil(onlyPart1.emptyNotice(forPart: 1))
        XCTAssertNil(onlyPart1.emptyNotice(forPart: PracticePicker.allParts))
    }

    /// 题库整个是空的时候，说法要换一句——那时切回「全部」也没有题，
    /// 让他去切等于把他指向一件做了也没用的事。
    func testAnEmptyBankSaysSomethingDifferentFromAnEmptyPart() throws {
        let notice = try XCTUnwrap(PracticePicker(questions: []).emptyNotice(forPart: 1))
        XCTAssertTrue(notice.contains("训练题库"), notice)
        XCTAssertFalse(notice.contains("切回「全部」"),
                       "题库空的时候还劝人切回「全部」，那儿同样一道题都没有：" + notice)
    }

    // MARK: - 默认停在哪一档：与学习计划的「重点 Part」的关系

    /// 默认档位跟着学习计划的「重点 Part」走。
    ///
    /// **这是这两处 Part 选择「不打架」的做法**：计划里选了 Part 2，开练弹层默认就停在
    /// Part 2；两者因此像同一件事的两个层次，而不是两套互相矛盾的设置。
    func testTheDefaultSegmentFollowsThePlansFocusPart() {
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: .part1), 1)
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: .part2), 2)
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: .part3), 3)
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: .fullMock),
                       PracticePicker.allParts,
                       "全真模考的意思就是三个 Part 都练，默认不该被钉在某一个上")
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: nil), PracticePicker.allParts,
                       "还没有学习计划时不该凭空挑一个 Part")
    }

    /// 默认档位不是「全部」时必须解释它是从哪儿来的，否则用户会以为题库里别的 Part 没了。
    ///
    /// 而且要说清**在这儿切档不会改学习计划**——一次临时选择偷偷改掉一份长期计划，
    /// 是最让人不信任的那种行为。
    func testWhenTheDefaultComesFromThePlanItSaysSoAndSaysItIsNotStickyy() throws {
        let notice = try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2))
        XCTAssertTrue(notice.contains("学习计划"), notice)
        XCTAssertTrue(notice.contains(PlanScope.label(for: .part2)),
                      "没说清默认停在哪一档：" + notice)
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("学习计划不会跟着改"),
                      "没说清在这儿切档会不会改掉计划，用户不敢切：" + notice)

        XCTAssertNil(PracticePicker.planFocusNotice(for: .fullMock),
                     "全真模考时默认就是「全部」，没有什么要解释的，多一句话是骚扰")
        XCTAssertNil(PracticePicker.planFocusNotice(for: nil))
    }

    // MARK: - 这些真的被画到弹层上了吗

    /// **写好了和摆上屏幕了是两件事**，本项目已经在四个地方分别栽过这同一跤。
    ///
    /// 实测过的突变：把 `partSection` 里那个 `Picker` 换成 `EmptyView()`——
    /// `PracticePicker` 的全部逻辑测试照样绿，而用户那边「先选 Part」这个功能整个不存在。
    func testThePartPickerIsActuallyOnTheSheetAndBoundToTheSelection() throws {
        let code = try SourceGuard.code(Self.sheet)

        XCTAssertTrue(
            code.contains("Picker(") && code.contains("selection: $partSelection"),
            "挑题弹层上没有绑到 `$partSelection` 的分段控件。用户要的第一件事"
                + "（先选练哪个 Part）整个不存在，而 `PracticePicker` 的逻辑测试全都照绿。"
                + "下一步：把 `PracticeSheet.partSection` 里那个 Picker 放回去。")

        SourceGuard.assertRenders(
            "partSection", inBodyOf: "private var picker", of: Self.sheet,
            because: "`partSection` 只是声明着，没有被摆进挑题那一段——一个像素都不上屏。"
                + "下一步：把它放回 `picker` 的 VStack 里。")

        for piece in ["countsLine", "selectionSummary", "planFocusNotice"] {
            SourceGuard.assertRenders(
                piece, inBodyOf: "private var partSection", of: Self.sheet,
                because: "`\(piece)` 没画在分段控件旁边。四个格子只剩四个词，"
                    + "用户点之前不知道每一档底下有没有题、默认这一档是从哪儿来的。"
                    + "下一步：把它放回 `partSection`。")
        }
    }

    /// **筛完的结果得真的用在列表上。**
    ///
    /// 这是这个功能唯一可能「装出来」的失效形态：控件在、文案在、`visibleCandidates`
    /// 也算得好好的，而列表那一行还是 `ForEach(candidates)`——分段控件点起来毫无反应，
    /// 而上面每一条断言都是绿的。
    func testTheListRendersTheFilteredQuestionsNotTheWholeBank() throws {
        let picker = try SourceGuard.memberBody(of: "private var picker",
                                                in: SourceGuard.code(Self.sheet))
        XCTAssertTrue(picker.contains("ForEach(visibleCandidates)"),
                      "挑题列表画的不是筛过的结果。分段控件会变成一个点了没反应的装饰品。"
                          + "下一步：`ForEach(visibleCandidates)`。实际取到的是：\n\(picker)")
        XCTAssertFalse(picker.contains("ForEach(candidates)"),
                       "挑题列表还在画全库。下一步：改成 `ForEach(visibleCandidates)`。")
    }

    /// 切档之后，上一档里挑好的那道题必须失效。
    ///
    /// 不清掉的话：选了 Part 1 的一道题 → 切到 Part 2 → 点「开始练习」，
    /// 练的是屏幕上一道也看不见的题。这是真会发生的一次「静默做错事」。
    func testSwitchingPartsDropsASelectionThatIsNoLongerVisible() throws {
        let code = try SourceGuard.code(Self.sheet)
        let section = try SourceGuard.memberBody(of: "private var partSection", in: code)
        XCTAssertTrue(section.contains("onChange(of: partSelection)"),
                      "切档时没有任何反应。上一档里挑好的那道题会留着，"
                          + "点「开始练习」练到一道屏幕上看不见的题。"
                          + "下一步：在 `partSection` 上挂 `.onChange(of: partSelection)`，"
                          + "把不在当前档里的选择清掉。")

        let start = try SourceGuard.functionBody(named: "startPicked", in: code)
        XCTAssertTrue(start.contains("visibleCandidates"),
                      "「开始练习」是从全库里找那道题的——切档之后残留的 id 照样找得到，"
                          + "于是练的是屏幕上看不见的那道题。"
                          + "下一步：只在 `visibleCandidates` 里找。实际取到的是：\n\(start)")
        XCTAssertFalse(start.contains("candidates.first"),
                       "`startPicked` 还在全库里找题：\n\(start)")
    }

    /// 弹层的默认档位必须真的是调用方按学习计划算出来的那一个。
    ///
    /// 少了这一条，`defaultPart(forPlanFocus:)` 可以测得很好看，
    /// 而今日训练页压根没把它传进来（弹层永远停在「全部」）。
    func testTodayPageFeedsThePlansFocusPartIntoTheSheet() throws {
        let today = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(
            today.contains("PracticePicker.defaultPart(") && today.contains("planFocusPart:"),
            "今日训练页没有把学习计划的重点 Part 传给挑题弹层。"
                + "于是计划里选了 Part 2，开练弹层却停在「全部」——两处 Part 选择看起来"
                + "各说各话。下一步：`defaultPart: PracticePicker.defaultPart(forPlanFocus: "
                + "app.state.plan?.focusPart)`，并把 `planFocusPart` 一起传下去。")
    }

    /// 学习计划页得说清「重点 Part」和开练时那排按钮各管什么。
    ///
    /// App 里现在有两处能选 Part。不说清的话，用户会以为它们是同一个设置的两份界面，
    /// 然后开始怀疑「我在这儿选了 Part 2，为什么那边还能选 Part 1」。
    @MainActor
    func testThePlanPageExplainsHowItsFocusPartRelatesToThePracticeSheet() throws {
        let note = PlanView.focusScopeNote
        XCTAssertTrue(note.contains("这份计划"), note)
        XCTAssertTrue(note.contains("开始练习"),
                      "没指出那排 Part 按钮从哪儿去：" + note)
        XCTAssertTrue(note.contains("不会动这份计划"),
                      "没说清在弹层里切档会不会改掉计划：" + note)

        SourceGuard.assertRenders(
            "focusScopeNote", inBodyOf: "private var focusPicker", of: "Plan/PlanView.swift",
            because: "这句说明只是声明着，没有画在「重点 Part」那组单选按钮下面。"
                + "下一步：把它放回 `focusPicker`。")
    }
}
