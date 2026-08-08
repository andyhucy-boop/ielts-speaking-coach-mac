import XCTest
@testable import IELTSCoachCore

/// `FocusPart` 是「这一场按哪套考法跑」的唯一出处：`ExaminerPrompt` 照它选规则、
/// `ReviewRequestPrompt` 照它选回答长度标准、`PracticeSession` 把它存进训练记录、
/// `PlanScope` 照它排计划。所以它的三条规则各自都得有测试钉着。
final class FocusPartTests: XCTestCase {

    // MARK: - 取值本身

    /// raw value **写进过用户机器上的 state.json**，改一个字就等于让那些练习记录的 Part
    /// 变成别的东西。所以逐个钉死。
    func testRawValuesAreFrozenBecauseTheyAreAlreadyOnDisk() {
        XCTAssertEqual(FocusPart.part1.rawValue, "Part 1")
        XCTAssertEqual(FocusPart.part2.rawValue, "Part 2")
        XCTAssertEqual(FocusPart.part3.rawValue, "Part 3")
        XCTAssertEqual(FocusPart.part2And3.rawValue, "Part 2 + Part 3")
        XCTAssertEqual(FocusPart.fullMock.rawValue, "full mock")
        // 多选 Part 之后新增的两档。
        XCTAssertEqual(FocusPart.part1And2.rawValue, "Part 1 + Part 2")
        XCTAssertEqual(FocusPart.part1And3.rawValue, "Part 1 + Part 3")
        XCTAssertEqual(FocusPart.allCases.count, 7)
    }

    // MARK: - 建模：一档考法就是一串有序的 Part

    /// 三个 Part 的非空组合恰好七种，**一种都不能少**——少一种就是用户在界面上勾得出来、
    /// 却落不到一档考法上。而且七种互不相同：两档撞成同一个值的话，
    /// 训练记录里两种考法会显示成同一件事。
    func testEveryNonEmptyCombinationOfThePartsIsExactlyOneFocusPart() {
        XCTAssertEqual(Set(FocusPart.allCases.map(\.parts.count)).sorted(), [1, 2, 3])
        XCTAssertEqual(Set(FocusPart.allCases).count, 7, "有两档撞成了同一个值")
        XCTAssertEqual(Set(FocusPart.allCases.map(\.rawValue)).count, 7,
                       "有两档写到磁盘上是同一个字符串")

        for focus in FocusPart.allCases {
            XCTAssertFalse(focus.parts.isEmpty, "\(focus.rawValue) 是一场什么都不考的练习")
            XCTAssertEqual(focus.parts, focus.parts.sorted(),
                           "\(focus.rawValue) 的几段不是按考试顺序排的，提示词会照着它倒过来拼")
            XCTAssertEqual(focus.parts.count, Set(focus.parts).count,
                           "\(focus.rawValue) 里有重复的 Part，那一段会被考两遍")
        }
    }

    /// 空集合造不出一档考法。**返回 nil 而不是挑一个默认值**：
    /// 「一个 Part 都不练」没有任何调用方处理得了，而替他选一个是替他做决定。
    func testAnEmptySelectionIsNotAFocusPartAtAll() {
        XCTAssertNil(FocusPart(parts: []))
    }

    /// 从一组 Part 造出来的那一档，就是 `allCases` 里的那一个。
    /// 两处各写一份映射的话，界面勾出来的和落盘的会是两个不同的值。
    func testBuildingFromPartsLandsOnTheSameValueAsTheNamedOne() {
        XCTAssertEqual(FocusPart(parts: [.two, .three]), .part2And3)
        XCTAssertEqual(FocusPart(parts: [.one, .two]), .part1And2)
        XCTAssertEqual(FocusPart(parts: [.one, .two, .three]), .fullMock)
        // 顺序、重复都不影响结果：它们不携带信息。
        XCTAssertEqual(FocusPart(parts: [.three, .two]), .part2And3)
        XCTAssertEqual(FocusPart(parts: [.two, .two, .three]), .part2And3)
    }

    /// **三个 Part 全选写到磁盘上仍然是 `"full mock"`。**
    ///
    /// 这是这次建模最要紧的一条兼容约束。写成 `"Part 1 + Part 2 + Part 3"` 的话，
    /// 旧版本 App 会把它当成不认识的取值回落到 full mock——行为碰巧也对，
    /// 所以不报错、不崩，但用户的历史记录里同一件事从此有两种写法。
    func testAllThreePartsStillSerialiseAsTheHistoricFullMockString() throws {
        XCTAssertEqual(FocusPart(parts: ExamPart.allCases)?.rawValue, "full mock")
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-09T00:00:00Z", days: [],
                                focusPart: .fullMock)
        let text = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        XCTAssertTrue(text.contains("\"full mock\""), text)
        XCTAssertFalse(text.contains("Part 1 + Part 2 + Part 3"), text)
    }

    // MARK: - 旧数据 / 迁移路径

    /// 磁盘上已有的五个字符串，**这一版必须原样读得出来**。
    /// 读不出来的后果不是崩，是那条练习记录的考法被悄悄换成别的一档。
    func testEveryStringAlreadyOnDiskStillReadsBackAsTheSameThing() {
        let onDisk: [String: FocusPart] = [
            "Part 1": .part1, "Part 2": .part2, "Part 3": .part3,
            "Part 2 + Part 3": .part2And3, "full mock": .fullMock
        ]
        for (raw, expected) in onDisk {
            XCTAssertEqual(FocusPart(rawValue: raw), expected, "磁盘上的「\(raw)」读不回原样")
        }
    }

    /// 顺序反了、写全了三段、多空格——这些都表达同一件事，读得出来并规范化。
    ///
    /// 「三段写全」这条是真实的迁移入口：将来若有人手写或从别处导入
    /// `"Part 1 + Part 2 + Part 3"`，它必须等于全真模考，而不是一个第八档。
    func testFormatVariantsThatMeanTheSameThingAreNormalised() {
        XCTAssertEqual(FocusPart(rawValue: "Part 3 + Part 2"), .part2And3)
        XCTAssertEqual(FocusPart(rawValue: "Part 1 + Part 2 + Part 3"), .fullMock)
        XCTAssertEqual(FocusPart(rawValue: "Part 1+Part 2"), .part1And2)
        XCTAssertEqual(FocusPart(rawValue: "  Part 2 + Part 3  "), .part2And3)
        // 规范化之后写回磁盘的仍然是那一份冻住的写法。
        XCTAssertEqual(FocusPart(rawValue: "Part 1 + Part 2 + Part 3")?.rawValue, "full mock")
        XCTAssertEqual(FocusPart(rawValue: "Part 3 + Part 2")?.rawValue, "Part 2 + Part 3")
    }

    /// 认不出来的一律 nil，交给各模型自己那层容错回落。**不许在这里猜。**
    ///
    /// 大小写打错（`"part 1"`）算认不出来：猜错一次的代价是那条练习记录被静默改成
    /// 另一档考法，而屏幕上一个字都没有（`PracticeSessionCodableTests` 钉着这个约定）。
    func testUnrecognisedStringsReturnNilInsteadOfAGuess() {
        for raw in ["", "   ", "part 1", "PART 2", "Part 4", "Part 0", "Part",
                    "Part 1 + Part 4", "Part one", "mock", "Full Mock"] {
            XCTAssertNil(FocusPart(rawValue: raw), "「\(raw)」被猜成了某一档考法")
        }
    }

    /// 两个新增取值存下去还能原样读回来，而且**旧版本读到它不会把整份数据搞坏**——
    /// 那条路早就铺好了（先读字符串、转不出来回落到 full mock）。
    func testTheTwoNewValuesSurviveARoundTripAndDegradeGracefully() throws {
        for focus in [FocusPart.part1And2, .part1And3] {
            let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-09T00:00:00Z", days: [],
                                    focusPart: focus)
            let data = try JSONEncoder().encode(plan)
            XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data).focusPart, focus)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(focus.rawValue))
        }

        // 「旧版本读到新取值」这条路：模型那层看到认不出的字符串，回落到 full mock，
        // 而不是让整份训练数据打不开。
        let session = """
        {"id":"2026-08-09-001","questionId":"p1-x","focusPart":"Part 1 + Part 9",
         "startedAt":"2026-08-09T10:00:00Z","endedAt":"","goal":"","transcript":[],
         "reportPath":"","recordingPath":""}
        """
        XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self,
                                                from: Data(session.utf8)).focusPart, .fullMock)
    }

    // MARK: - 从题目自身的 Part 推

    func testInferenceFollowsTheQuestionsOwnPart() {
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 1), .part1)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 2), .part2)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 3), .part3)
    }

    /// 越界的 part（手改坏的 state.json）落到 full mock，不崩、不拒绝开练。
    func testOutOfRangePartFallsBackToFullMockInsteadOfCrashing() {
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 9), .fullMock)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: 0), .fullMock)
        XCTAssertEqual(FocusPart.inferred(fromQuestionPart: -1), .fullMock)
    }

    /// **「Part 2 + Part 3 连着练」永远不会被推出来。**
    ///
    /// 它只可能是用户当场明确选的。一道 Part 2 的题默认就该按 Part 2 考——
    /// 悄悄升级成「连着练」等于替用户改了这一场的考法，而屏幕上没有任何交代。
    func testTheCombinedModeIsNeverInferredOnItsOwn() {
        for part in [1, 2, 3, 9] {
            XCTAssertNotEqual(FocusPart.inferred(fromQuestionPart: part), .part2And3,
                              "part \(part) 被自动推成了「Part 2 + Part 3 连着练」")
        }
    }

    // MARK: - 用户明确选的模式怎么落地

    /// 没有明确选择时，一律按题目自身的 Part。
    func testWithoutAModeItIsExactlyTheInferredPart() {
        for part in [1, 2, 3, 9] {
            XCTAssertEqual(FocusPart.forSession(mode: nil, questionPart: part),
                           FocusPart.inferred(fromQuestionPart: part))
        }
    }

    /// **只有 Part 2 的题能进「连着练」这一档。**
    ///
    /// 一张 Part 1 的话题卡做不出「两分钟长陈述 + 延伸讨论」，硬按组合档考的话，
    /// 考官只能自己编一张 cue card，而用户挑的那道题一次都不会被问到。
    func testTheCombinedModeOnlyTakesEffectOnAPart2Question() {
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 2), .part2And3)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 1), .part1)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 3), .part3)
        XCTAssertEqual(FocusPart.forSession(mode: .part2And3, questionPart: 9), .fullMock)
    }

    /// **`fullMock` 当模式传进来时不许把这一场变成一整场模考。**
    ///
    /// 「全真模考」作为学习计划的重点 Part，含义是「把三个 Part 的题交错排开」
    /// （`PlanScope.select`），每一天仍然是练那道题自己的 Part。
    /// 这里若返回 `.fullMock`，用户按计划练的每一天都会突然变成一整场三 Part 模考——
    /// 一次没有任何界面提示的行为突变。
    func testAFullMockPlanStillPracticesEachDaysOwnPart() {
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 1), .part1)
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 2), .part2)
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 3), .part3)
    }

    /// 单 Part 的模式与推断结果一致，不会把一道题拧成别的 Part。
    ///
    /// 这条挡的是「模式一律照抄」那种写法：那样的话，学习计划的重点 Part 是 Part 2、
    /// 而某一天排进来一道 Part 1 的题时，这一场会按 Part 2 的规则考一道 Part 1 的题。
    func testASinglePartModeNeverOverridesTheQuestionsOwnPart() {
        for mode in [FocusPart.part1, .part2, .part3] {
            for part in [1, 2, 3] {
                XCTAssertEqual(FocusPart.forSession(mode: mode, questionPart: part),
                               FocusPart.inferred(fromQuestionPart: part),
                               "mode \(mode) + part \(part) 把题目拧成了别的 Part")
            }
        }
    }

    // MARK: - 用户当场勾出来的那几个 Part

    /// **勾了什么就考什么。** 这是多选 Part 这个功能的落点：
    /// 走 `forSession` 那条（计划语义）的话，三个全勾会被静默降级成单 Part——
    /// 勾选框点得动、这一场却和它毫无关系。
    func testAnExplicitSelectionIsTakenLiterally() {
        XCTAssertEqual(FocusPart.forExplicitSelection(.fullMock, questionPart: 2), .fullMock,
                       "三个全勾却没考成一整场模考")
        XCTAssertEqual(FocusPart.forExplicitSelection(.part1And2, questionPart: 1), .part1And2)
        XCTAssertEqual(FocusPart.forExplicitSelection(.part2And3, questionPart: 2), .part2And3)
        XCTAssertEqual(FocusPart.forExplicitSelection(.part3, questionPart: 3), .part3)
    }

    /// **这正是两个入口必须分开的理由。** 同一档考法从计划那条路进来会被过滤，
    /// 从「用户当场勾的」这条路进来不会。混用哪一条都会有人吃亏：
    /// 混成计划语义 → 多选功能静默失效；混成明确语义 → 全真模考的计划每天变成一整场模考。
    func testTheExplicitEntryPointDiffersFromThePlanOneExactlyWhereItMatters() {
        XCTAssertEqual(FocusPart.forSession(mode: .fullMock, questionPart: 2), .part2,
                       "计划语义那条不该把这一天变成一整场模考")
        XCTAssertNotEqual(FocusPart.forSession(mode: .fullMock, questionPart: 2),
                          FocusPart.forExplicitSelection(.fullMock, questionPart: 2))
    }

    /// 挑中的题不属于勾选的任何一段时回落到它自己的 Part。
    ///
    /// 一份提示词里那道题必须落在某一段上，落不上就等于用户挑的题一次都不会被问到。
    func testAnExplicitSelectionFallsBackWhenTheQuestionBelongsToNoneOfThem() {
        XCTAssertEqual(FocusPart.forExplicitSelection(.part2And3, questionPart: 1), .part1)
        XCTAssertEqual(FocusPart.forExplicitSelection(.part1, questionPart: 3), .part3)
        XCTAssertEqual(FocusPart.forExplicitSelection(.part1And2, questionPart: 9), .fullMock,
                       "越界的 part 该走 inferred 那条兜底")
    }

    /// 新增的两档组合从计划那条路进来时，规则与 `part2And3` 完全一样：
    /// 只在题目正是开场那一段时生效。
    func testTheNewCombinationsFollowTheSamePlanSideRuleAsPart2And3() {
        XCTAssertEqual(FocusPart.forSession(mode: .part1And2, questionPart: 1), .part1And2)
        XCTAssertEqual(FocusPart.forSession(mode: .part1And2, questionPart: 2), .part2,
                       "一道 Part 2 的题开不出「先 Part 1 再 Part 2」这一场")
        XCTAssertEqual(FocusPart.forSession(mode: .part1And3, questionPart: 1), .part1And3)
        XCTAssertEqual(FocusPart.forSession(mode: .part1And3, questionPart: 3), .part3)
    }

    // MARK: - 时长

    func testDurationsMatchTheRealExamShape() {
        XCTAssertEqual(FocusPart.part1.defaultDurationMinutes, 6)
        XCTAssertEqual(FocusPart.part2.defaultDurationMinutes, 4)
        XCTAssertEqual(FocusPart.part3.defaultDurationMinutes, 6)
        XCTAssertEqual(FocusPart.fullMock.defaultDurationMinutes, 6)
    }

    /// **连着练必须比单练 Part 2 长。** 它是一段两分钟陈述加一整段讨论；
    /// 沿用 Part 2 的 4 分钟的话，提示词里写着「这一场约 4 分钟」，
    /// 而实际要考两段——考官会为了对上时间把 Part 3 砍成一两问。
    func testTheCombinedModeIsLongerThanPart2Alone() {
        XCTAssertEqual(FocusPart.part2And3.defaultDurationMinutes, 9)
        XCTAssertGreaterThan(FocusPart.part2And3.defaultDurationMinutes,
                             FocusPart.part2.defaultDurationMinutes)
    }

    /// 新增的两档也得比它们各自的单段长——沿用单段时长的话，提示词里写着
    /// 「这一场约 N 分钟」而实际要考两段，考官会为了对上时间把后一段砍成一两问。
    ///
    /// 每一档都必须有一个正数：查表查不到就按各段相加，没有「返回 0 分钟」这条路。
    func testEveryCombinationGetsAPositiveDurationLongerThanItsOwnParts() {
        for focus in FocusPart.allCases {
            XCTAssertGreaterThan(focus.defaultDurationMinutes, 0,
                                 "\(focus.rawValue) 没有时长，提示词里会写「约 0 分钟」")
        }
        XCTAssertEqual(FocusPart.part1And2.defaultDurationMinutes, 9)
        XCTAssertEqual(FocusPart.part1And3.defaultDurationMinutes, 10)
        for combined in [FocusPart.part1And2, .part1And3, .part2And3] {
            for part in combined.parts {
                XCTAssertGreaterThan(combined.defaultDurationMinutes,
                                     FocusPart(part).defaultDurationMinutes,
                                     "\(combined.rawValue) 不比单练 \(part.englishName) 长")
            }
        }
    }

    // MARK: - 旧数据 / 旧版本

    /// 新增取值只影响「新版本写、旧版本读」这一个方向，而那条路早就铺好了：
    /// 认不出来的 focusPart 按 full mock 处理，绝不因为一个取值让整份数据读不出来。
    func testAnOlderAppReadingTheNewValueFallsBackInsteadOfBricking() throws {
        let session = """
        {"id":"2026-08-08-001","questionId":"p2-x","focusPart":"Part 2 + Part 3",
         "startedAt":"2026-08-08T10:00:00Z","endedAt":"","goal":"","transcript":[],
         "reportPath":"","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self,
                                               from: Data(session.utf8))
        XCTAssertEqual(decoded.focusPart, .part2And3, "本版本必须原样读出这个取值")

        let plan = """
        {"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 2 + Part 3","days":[]}
        """
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: Data(plan.utf8)).focusPart,
                       .part2And3)
    }

    /// 存下去还能原样读回来——存的时候写成别的字符串，训练记录页那一列就会变。
    func testTheNewValueSurvivesARoundTrip() throws {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-08T00:00:00Z", days: [],
                                focusPart: .part2And3)
        let data = try JSONEncoder().encode(plan)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Part 2 + Part 3"))
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data).focusPart, .part2And3)
    }
}
