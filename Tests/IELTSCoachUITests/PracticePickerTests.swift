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

    // MARK: - 「练完 Part 2 接着练 Part 3」
    //
    // 用户原话：「你可以加一个功能，是否同时练习 part2 和 part3。」
    // 他要的是一个是 / 否，所以界面上是一颗开关，而不是分段控件上的第五格。

    /// 开关只在 Part 2 那一档出现，**也只在那一档生效**。
    ///
    /// 两者必须同进同退：显示条件比生效条件宽的话，会出现「开关亮着、这一场却不是连着练」；
    /// 反过来则是「开关看不见、这一场却被改成了连着练」。两种都是屏幕与行为对不上。
    func testTheLinkToggleOnlyShowsAndOnlyTakesEffectOnThePart2Segment() {
        for part in [PracticePicker.allParts, 1, 3] {
            XCTAssertFalse(PracticePicker.showsLinkPart3(forPart: part),
                           "Part \(part) 这一档不该出现「连着练」开关")
            XCTAssertNil(PracticePicker.mode(forPart: part, linksPart3: true),
                         "Part \(part) 这一档开关开着也不该改变考法——"
                             + "那一档里挑到的题根本不是一张 cue card")
        }
        XCTAssertTrue(PracticePicker.showsLinkPart3(forPart: 2))
        XCTAssertEqual(PracticePicker.mode(forPart: 2, linksPart3: true), .part2And3)
        XCTAssertNil(PracticePicker.mode(forPart: 2, linksPart3: false),
                     "开关关着时就是一场普通 Part 2，不能带任何模式出去")
    }

    /// 开关的默认状态跟着学习计划的「重点 Part」走，与档位默认值同一个道理。
    func testTheToggleDefaultsOnOnlyWhenThePlanAsksForTheCombinedMode() {
        XCTAssertTrue(PracticePicker.defaultLinksPart3(forPlanFocus: .part2And3))
        for other: FocusPart? in [.part1, .part2, .part3, .fullMock, nil] {
            XCTAssertFalse(PracticePicker.defaultLinksPart3(forPlanFocus: other),
                           "\(String(describing: other)) 不该把开关默认打开")
        }
        XCTAssertEqual(PracticePicker.defaultPart(forPlanFocus: .part2And3), 2,
                       "「连着练」排的就是 Part 2 那批 cue card，档位该停在 Part 2")
    }

    /// 计划选了「连着练」时，那句说明必须把**开关也被打开了**这件事说出来。
    ///
    /// 不说的话，用户看到档位停在「Part 2」，会以为计划里那个选择根本没生效。
    func testThePlanNoticeMentionsTheToggleWhenThePlanAsksForTheCombinedMode() throws {
        let notice = try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2And3))
        XCTAssertTrue(notice.contains(PracticePicker.linkPart3Title),
                      "没说清下面那颗开关已经替他打开了：" + notice)
        XCTAssertTrue(notice.contains("下一步"), notice)

        XCTAssertFalse(try XCTUnwrap(PracticePicker.planFocusNotice(for: .part2))
            .contains(PracticePicker.linkPart3Title),
                       "普通 Part 2 的说明里不该提那颗开关——它默认是关着的，提了就是骗人")
    }

    /// 开关旁边那句解释要说清「打开会怎样、关着会怎样」。
    /// 只写一个开关标题的话，用户不知道打开之后这一场会长多少、会不会变成模考。
    func testTheToggleExplainsWhatHappensBothWays() {
        let hint = PracticePicker.linkPart3Hint
        XCTAssertTrue(hint.contains("Part 3 讨论"), hint)
        XCTAssertTrue(hint.contains("只做 Part 2"), "没说清关着的时候是什么样：" + hint)
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
    ///
    /// 列表现在是按 Part 折叠分栏的（`QuestionPartSections`），所以这一条查的是那条链
    /// 的两头：分栏是从 `visibleCandidates` 分出来的，列表画的是分出来的那几栏。
    /// 中间任何一环换回全库，这里都会红。
    func testTheListRendersTheFilteredQuestionsNotTheWholeBank() throws {
        let code = try SourceGuard.code(Self.sheet)

        let sections = try SourceGuard.memberBody(of: "private var sectionsByPart", in: code)
        XCTAssertTrue(sections.contains("QuestionPartSections.split(visibleCandidates)"),
                      "分栏不是从筛过的结果分出来的。分段控件会变成一个点了没反应的装饰品。"
                          + "下一步：`QuestionPartSections.split(visibleCandidates) { $0.part }`。"
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
        XCTAssertTrue(start.contains("pickedQuestion"),
                      "「开始练习」是从全库里找那道题的——切档之后残留的 id 照样找得到，"
                          + "于是练的是屏幕上看不见的那道题。"
                          + "下一步：只认 `pickedQuestion`。实际取到的是：\n\(start)")
        XCTAssertFalse(start.contains("candidates.first"),
                       "`startPicked` 还在全库里找题：\n\(start)")

        // 而 `pickedQuestion` 只认**展开的那几栏里**的题：那条链断在这一环的话，
        // 上面那句 `pickedQuestion` 照样绿，而折起来的栏里那道题仍然练得起来。
        let resolved = try SourceGuard.memberBody(of: "private var pickedQuestion", in: code)
        XCTAssertTrue(resolved.contains("visibleInExpandedSections"),
                      "`pickedQuestion` 不是从展开的那几栏里找的。切档或者折起一栏之后，"
                          + "残留的那个 id 照样找得到题，练的是屏幕上一道也看不见的题。"
                          + "下一步：只在 `visibleInExpandedSections` 里找。实际取到的是：\n\(resolved)")
    }

    /// **那颗开关真的在弹层上，而且真的连到这一场的考法上。**
    ///
    /// 这是这个功能唯一可能「装出来」的失效形态：`PracticePicker` 那几条逻辑测试全绿，
    /// 而弹层上要么根本没有开关（用户选不到这个模式），要么开关拨得动、
    /// `startPicked()` 却拿写死的 `nil` 去开练（拨了不算数，屏幕上毫无异样）。
    func testTheLinkToggleIsOnTheSheetAndItsValueReachesTheSession() throws {
        let code = try SourceGuard.code(Self.sheet)

        // 开关标题在视图里写成字面量，而不是引用常量：`SourceGuard` 那条
        // 「文案里让人点的控件必须真的存在」靠扫 `Toggle("…")` 的字面量建清单。
        XCTAssertTrue(code.contains("Toggle(\"\(PracticePicker.linkPart3Title)\", isOn: $linkPart3)"),
                      "挑题弹层上没有那颗绑到 `$linkPart3` 的开关，或者标题和 "
                          + "`PracticePicker.linkPart3Title`（「\(PracticePicker.linkPart3Title)」）"
                          + "对不上。用户原话要的就是「是否同时练习 part2 和 part3」这个选择。"
                          + "下一步：把 `linkPart3Section` 里那颗 Toggle 放回去，标题逐字一致。")

        SourceGuard.assertRenders(
            "linkPart3Section", inBodyOf: "private var partSection", of: Self.sheet,
            because: "`linkPart3Section` 只是声明着，没有摆在那排 Part 按钮下面——"
                + "一个像素都不上屏，用户永远选不到「连着练」。"
                + "下一步：把它放回 `partSection`。")

        SourceGuard.assertRenders(
            "showsLinkPart3", inBodyOf: "private var linkPart3Section", of: Self.sheet,
            because: "那颗开关没有按档位收起来。「全部」那一档里挑到一道 Part 1 的题时，"
                + "开关会亮着而这一场跟它毫无关系——屏幕和行为对不上。"
                + "下一步：`if PracticePicker.showsLinkPart3(forPart: partSelection)`。")

        let start = try SourceGuard.functionBody(named: "startPicked", in: code)
        XCTAssertTrue(start.contains("PracticePicker.mode(forPart: partSelection, linksPart3: linkPart3)"),
                      "「开始练习」没有把那颗开关的状态带进这一场。开关拨得动、"
                          + "练的却仍是普通 Part 2，而界面上看不出任何异样。"
                          + "下一步：`makeSetup(question, PracticePicker.mode(...))`。"
                          + "实际取到的是：\n\(start)")

        // 今日训练页得把这个参数继续往解析器传，否则它到 `makeSetup` 就断了。
        let today = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(today.contains("makeSetup: { question, mode in") && today.contains("mode: mode"),
                      "今日训练页的 `makeSetup` 把用户选的考法丢了。"
                          + "下一步：`PracticeRouteResolver.setup(for: question, goal: \"\", "
                          + "defaults: defaults, mode: mode)`。")
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
        // 「连着练」在弹层上不是第五格按钮而是一颗开关，这一点必须在这儿说清；
        // 否则用户在计划里选了它，到弹层看到档位停在「Part 2」，会以为选择没生效。
        XCTAssertTrue(note.contains(PracticePicker.linkPart3Title),
                      "没说清「Part 2 + Part 3 连着练」在开练弹层上长什么样：" + note)

        SourceGuard.assertRenders(
            "focusScopeNote", inBodyOf: "private var focusPicker", of: "Plan/PlanView.swift",
            because: "这句说明只是声明着，没有画在「重点 Part」那组单选按钮下面。"
                + "下一步：把它放回 `focusPicker`。")
    }
}
