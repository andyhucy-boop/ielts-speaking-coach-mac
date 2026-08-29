import XCTest
@testable import IELTSCoachCore

final class ReviewArchiverTests: XCTestCase {
    private let report = try! JSONValue.decode(from: """
    {"summary":"ok",
     "must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                      "why_it_matters":"very 不能修饰动词"}],
     "vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding experience",
                    "priority":"high"}],
     "answer_upgrades":[],
     "priority_target":{"id":"logic-explain-example","label":"补一个原因和例子",
                        "status":"new","evidence":["I just like it."]}}
    """)

    private func baseState() -> CoachState {
        var state = CoachState.empty()
        state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "P")]
        state.plan = try! PlanBuilder.build(questions: state.questions, lengthDays: 7,
                                            createdAt: "2026-08-04T00:00:00Z")
        return state
    }

    func testAddsNewIssue() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "2026-08-04-001", questionID: "q1",
                                           at: "2026-08-04T10:00:00Z").state
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].learnerSaid, "I very like it.")
        XCTAssertEqual(state.issues[0].occurrences, 1)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["2026-08-04-001"])
    }

    func testIncrementsOccurrenceForRepeatedIssue() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].occurrences, 2)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1", "s2"])
        XCTAssertEqual(state.issues[0].lastSeenAt, "t2")
    }

    /// **同一场练习的复盘归档两次，「出现次数」不许变成 2。**
    ///
    /// 这条路走得到：`markImported` 改名失败（`.imported` 那个名字被占）时归档已经做完、
    /// 文件却还在待处理列表里；用户手工去掉 `.imported` 后缀重来；界面那条路和
    /// `coach reimport` 各导一次。`occurrences` 是「这个毛病在变多还是变少」的全部依据，
    /// 虚高的后果不是显示错一个数——是用户以为老毛病越来越严重，而他其实正在变好。
    func testArchivingTheSameSessionTwiceDoesNotInflateOccurrences() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.issues[0].occurrences, 1, "同一场归档两次，出现次数被加了两遍")
        // 「最后一次见到」同样要幂等：s1 这一场发生在什么时候是固定的，
        // 第二次归档只是补录，不该把它说成刚刚才犯过。
        XCTAssertEqual(state.issues[0].lastSeenAt, "t1",
                       "重复归档同一场，把「最后一次见到」改成了补录的时刻")
    }

    /// 归档过一次之后，**新的一场**里再犯同一个错，该加的还是要加——
    /// 幂等不等于从此不再计数。没有这条的话，把 `occurrences += 1` 整段删掉
    /// （永远停在 1）也能让上面那条绿。
    func testANewSessionStillIncrementsOccurrences() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t3").state
        XCTAssertEqual(state.issues[0].occurrences, 2)
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1", "s2"])
        XCTAssertEqual(state.issues[0].lastSeenAt, "t3")
    }

    /// 幂等的完整含义：同一份复盘归档第二次，整个 state 一个字节都不该变。
    /// 只盯着 `occurrences` 的话，别的字段偷偷变了照样看不出来。
    func testArchivingTheSameReviewTwiceIsAWholeStateNoOp() {
        let once = ReviewArchiver.archive(report: report, into: baseState(),
                                          sessionID: "s1", questionID: "q1", at: "t1").state
        let twice = ReviewArchiver.archive(report: report, into: once,
                                           sessionID: "s1", questionID: "q1", at: "t2").state
        XCTAssertEqual(once, twice, "同一份复盘归档第二次改动了训练档案")
    }

    func testDoesNotDuplicateSessionIDWhenArchivedTwice() {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        // 这条断言不能省：只查 sourceSessionIds 的话，即使归并逻辑退化成
        // 「每次都新增一条错题记录」，issues[0] 依然是第一条、依然只含 s1，测试照样绿。
        XCTAssertEqual(state.issues.count, 1, "同一 session 重复入库不应新增错题记录")
        XCTAssertEqual(state.issues[0].sourceSessionIds, ["s1"])
        // 同理：词汇按 basicWord 去重、重训目标按 targetKey+sourceSessionId 去重，各自的
        // 守卫删掉后没有任何测试失败——只查内容不查数量的话，即使每次都新增一条重复记录，
        // vocabulary[0]/targets[0] 依然是第一条、内容不变，测试照样绿。
        XCTAssertEqual(state.vocabulary.count, 1, "同一 session 重复入库不应新增词汇记录")
        XCTAssertEqual(state.targets.count, 1, "同一 session 重复入库不应新增重训目标记录")
    }

    func testAddsVocabulary() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.vocabulary[0].basicWord, "good")
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding")
        XCTAssertEqual(state.vocabulary[0].priority, "high")
    }

    // MARK: - 残缺词条的回填（复审第 11 条）

    /// 第一次复盘只给了原词，第二次给全了——**缺的字段必须补上**。
    ///
    /// 补不上的话，这条记录会永远渲染成「good →（空白）」，每次导出都被跳过，
    /// 而跳过的提示写着「等下一次复盘补上」——那句话就是假的。
    func testASecondReviewFillsInTheFieldsThatWereMissingTheFirstTime() throws {
        let partial = try JSONValue.decode(from: """
        {"summary":"ok","must_correct":[],"answer_upgrades":[],
         "vocabulary":[{"basic":"good"}]}
        """)
        var state = ReviewArchiver.archive(report: partial, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.vocabulary[0].betterExpression, "", "前提：第一次确实是残缺的")

        state = ReviewArchiver.archive(report: report, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.vocabulary.count, 1, "同一个词不该变成两条")
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding",
                       "「更好的说法」没有回填，这条卡片会被永久跳过")
        XCTAssertEqual(state.vocabulary[0].collocation, "a rewarding experience",
                       "搭配没有回填")
        XCTAssertEqual(state.vocabulary[0].sourceSessionIds, ["s1", "s2"])
        // priority 刻意不回填：它落盘时就有默认值 "normal"，从来不是空的，
        // 按「缺字段」去覆盖等于让后一次复盘悄悄改掉这个词在列表里的排序。
        XCTAssertEqual(state.vocabulary[0].priority, "normal",
                       "优先级不该被后来的复盘改掉——那会悄悄重排用户的背词顺序")
    }

    /// 回填**只填空的**。已经有内容的字段绝不许被后来的复盘悄悄换掉——
    /// 用户已经在背那句话了，换掉它而不吭声比不补更糟。
    func testBackfillNeverOverwritesSomethingTheUserAlreadyHas() throws {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        let different = try JSONValue.decode(from: """
        {"summary":"ok","must_correct":[],"answer_upgrades":[],
         "vocabulary":[{"basic":"good","better":"某个完全不同的说法",
                        "collocation":"另一个搭配","priority":"low"}]}
        """)
        state = ReviewArchiver.archive(report: different, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding")
        XCTAssertEqual(state.vocabulary[0].collocation, "a rewarding experience")
        XCTAssertEqual(state.vocabulary[0].priority, "high")
        XCTAssertEqual(state.vocabulary[0].sourceSessionIds, ["s1", "s2"],
                       "内容不改，但「在几场里出现过」还是要照记")
    }

    /// 第二次也没给的话，不许把空的写进去搅乱已有内容（等价于上一条的反向边界）。
    func testAnEmptyIncomingFieldLeavesTheExistingOneAlone() throws {
        var state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        let blank = try JSONValue.decode(from: """
        {"summary":"ok","must_correct":[],"answer_upgrades":[],
         "vocabulary":[{"basic":"good","better":"   ","collocation":""}]}
        """)
        state = ReviewArchiver.archive(report: blank, into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.vocabulary[0].betterExpression, "rewarding")
        XCTAssertEqual(state.vocabulary[0].collocation, "a rewarding experience")
    }

    func testAppendsRetrainingTarget() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.targets[0].targetKey, "logic-explain-example")
        XCTAssertEqual(state.targets[0].sourceSessionId, "s1")
    }

    func testAdvancesPlanProgress() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.plan?.days[0].completedQuestionIds, ["q1"])
    }

    func testMarksQuestionPracticed() {
        let state = ReviewArchiver.archive(report: report, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t").state
        XCTAssertEqual(state.questions[0].status, "practiced")
    }

    func testHandlesReportWithNoIssuesOrVocabulary() {
        let sparse = try! JSONValue.decode(from: #"{"must_correct":[],"priority_target":{"id":"t1"}}"#)
        let outcome = ReviewArchiver.archive(report: sparse, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.state.issues.isEmpty)
        XCTAssertTrue(outcome.state.vocabulary.isEmpty)
        XCTAssertEqual(outcome.state.targets.count, 1)
        // must_correct 是空数组、vocabulary 键根本不存在：两者都不算「存在且非空但没归进去」，
        // 不应该报警——报警是留给「有内容却没归进去」这种真正可疑的情况。
        XCTAssertTrue(outcome.skipped.isEmpty)
    }

    // MARK: - skipped：归档 0 条时必须报警（spec 2.3.8 的直接现场）

    /// 真机实测到的故障现场：ChatGPT 把 must_correct 的字段名写成了
    /// issue/examples/fix，而不是 ReviewArchiver 读的 learner_said/correction/why_it_matters。
    /// 数组本身非空，但一条都识别不出来——这正是「归档 0 条不等于没错题」的典型样本。
    func testSkippedReportsMustCorrectWhenFieldNamesDoNotMatch() {
        let mismatched = try! JSONValue.decode(from: """
        {"summary":"ok",
         "must_correct":[{"issue":"filler words","examples":["um","like"],"fix":"pause instead"}],
         "priority_target":{"id":"t1"}}
        """)
        let outcome = ReviewArchiver.archive(report: mismatched, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.contains("must_correct"))
        XCTAssertTrue(outcome.state.issues.isEmpty, "字段名对不上时不应该凭空造出一条空白错题记录")
    }

    /// 同一类故障的 vocabulary 版本：真机实测里 ChatGPT 把 vocabulary 整体输出成了
    /// 一个对象（{"useful_replacements":...,"pronunciation":...}）而不是数组。
    func testSkippedReportsVocabularyWhenShapeIsWrong() {
        let wrongShape = try! JSONValue.decode(from: """
        {"summary":"ok",
         "vocabulary":{"useful_replacements":["rewarding"],"pronunciation":"n/a"},
         "priority_target":{"id":"t1"}}
        """)
        let outcome = ReviewArchiver.archive(report: wrongShape, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.contains("vocabulary"))
        XCTAssertTrue(outcome.state.vocabulary.isEmpty)
    }

    /// 反面对照：字段名正确时不应该报 skipped。
    func testSkippedIsEmptyWhenFieldNamesMatch() {
        let outcome = ReviewArchiver.archive(report: report, into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertTrue(outcome.skipped.isEmpty)
        XCTAssertEqual(outcome.state.issues.count, 1)
        XCTAssertEqual(outcome.state.vocabulary.count, 1)
    }

    // MARK: - 「下一次唯一目标」不许被静默丢掉（复审第 7 条）

    /// ChatGPT 漏给 `priority_target.id`（提示词要求给全，但没有任何校验拦得住）时，
    /// **目标照样要进档案**。
    ///
    /// 丢掉的后果不是少一条记录：复盘报告页照常画那张最显眼的深色卡片
    /// 「下一次只盯这一个」，而用户转身打开复训中心看到的是
    /// 「还没有待复训的目标。下一步：先完整练一场」——一句在他刚练完一整场的前提下
    /// 字面上为假的话。这条链是这个产品自称的核心价值（改进闭环）。
    func testATargetWithoutAnIDIsStillArchived() {
        let noID = try! JSONValue.decode(from: """
        {"summary":"ok",
         "priority_target":{"label":"补一个原因和例子","status":"new","evidence":["I just like it."]}}
        """)
        let outcome = ReviewArchiver.archive(report: noID, into: baseState(),
                                             sessionID: "2026-08-08-001", questionID: "q1",
                                             at: "t")
        XCTAssertEqual(outcome.state.targets.count, 1, "复盘给了目标，档案里一条都没有")
        XCTAssertEqual(outcome.state.targets.first?.label, "补一个原因和例子")
        XCTAssertEqual(outcome.state.targets.first?.targetKey, "target-2026-08-08-001")
        XCTAssertFalse(outcome.skipped.contains("priority_target"),
                       "目标已经好好归进去了，还报警等于狼来了——真丢的那次就没人信了")
    }

    /// 兜底 key 之后幂等仍然成立：同一场归档两次不会变成两条目标。
    func testTheFallbackKeyKeepsArchivingIdempotent() {
        let noID = try! JSONValue.decode(from:
            #"{"priority_target":{"label":"补一个原因和例子"}}"#)
        var state = ReviewArchiver.archive(report: noID, into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        state = ReviewArchiver.archive(report: noID, into: state,
                                       sessionID: "s1", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.targets.count, 1, "同一场归档两次多出了一条重复目标")
    }

    /// 真的存不下来时（`priority_target` 有内容、但既不是对象、也说不出要盯什么），
    /// **必须记进「跳过了什么」那份清单**——四个归档出口（应用内、两个命令行、ChatGPT 侧）
    /// 全靠它说话。清单为空时它们只会写「重训目标 N 个」，数字和上一场一模一样。
    func testSkippedReportsThePriorityTargetWhenItCannotBeStored() {
        for json in [#"{"priority_target":"补一个原因和例子"}"#,
                     #"{"priority_target":["补一个原因和例子"]}"#,
                     #"{"priority_target":{"status":"new"}}"#] {
            let outcome = ReviewArchiver.archive(report: try! JSONValue.decode(from: json),
                                                 into: baseState(),
                                                 sessionID: "s1", questionID: "q1", at: "t")
            XCTAssertTrue(outcome.state.targets.isEmpty, json)
            XCTAssertTrue(outcome.skipped.contains("priority_target"),
                          "目标存不下来，四个归档出口却一个字都不说：\(json)")
        }
    }

    /// 反面对照两条，缺一不可：
    /// 键根本不存在时不报警（否则每份没给目标的复盘都会挨一句莫名其妙的警告），
    /// 重复归档同一场时也不报警（目标本来就在，什么都没丢）。
    func testThePriorityTargetIsNotReportedWhenThereIsNothingToLose() {
        let noTarget = try! JSONValue.decode(from: #"{"must_correct":[]}"#)
        XCTAssertFalse(ReviewArchiver.archive(report: noTarget, into: baseState(),
                                              sessionID: "s1", questionID: "q1", at: "t")
            .skipped.contains("priority_target"),
                       "复盘压根没给目标，却报「有东西没归进去」")

        let once = ReviewArchiver.archive(report: report, into: baseState(),
                                          sessionID: "s1", questionID: "q1", at: "t1").state
        XCTAssertFalse(ReviewArchiver.archive(report: report, into: once,
                                              sessionID: "s1", questionID: "q1", at: "t2")
            .skipped.contains("priority_target"),
                       "同一场重复归档，目标本来就在档案里，不该报成「没归进去」")
    }

    // MARK: - 从上游补回来的两个字段（2026-08-20）

    /// 上游 report-schema 第 3 节那张表本来就是四列，第四列 Mini drill 当初漏了没移植：
    /// 错题本于是攒了一堆「你说错了、应该这么说」，一条也没告诉他此刻该张嘴练什么。
    func testTheMiniDrillLandsInTheIssueArchive() throws {
        let json = #"""
        {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                          "why_it_matters":"very 不能修饰动词",
                          "mini_drill":"把这句用 really 说三遍"}]}
        """#
        let outcome = ReviewArchiver.archive(report: try JSONValue.decode(from: json),
                                             into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(outcome.state.issues.first?.miniDrill, "把这句用 really 说三遍")
    }

    /// **练法只补不换。** 这条错题上次入库时 ChatGPT 没给练法、这次给了，就补上——
    /// 那一格是这条错题在错题本里唯一「现在能做什么」的出口。
    /// 已经有练法时一个字都不动（换来换去只是噪音）。
    func testAMissingDrillIsFilledInLaterButAnExistingOneIsNeverOverwritten() throws {
        func report(drill: String) throws -> JSONValue {
            try JSONValue.decode(from: #"""
            {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
                              "why_it_matters":"very 不能修饰动词","mini_drill":"\#(drill)"}]}
            """#)
        }
        var state = ReviewArchiver.archive(report: try report(drill: ""), into: baseState(),
                                           sessionID: "s1", questionID: "q1", at: "t1").state
        XCTAssertEqual(state.issues.first?.miniDrill, "")

        state = ReviewArchiver.archive(report: try report(drill: "说三遍"), into: state,
                                       sessionID: "s2", questionID: "q1", at: "t2").state
        XCTAssertEqual(state.issues.first?.miniDrill, "说三遍", "空着的练法没有被补上")

        state = ReviewArchiver.archive(report: try report(drill: "换一个练法"), into: state,
                                       sessionID: "s3", questionID: "q1", at: "t3").state
        XCTAssertEqual(state.issues.first?.miniDrill, "说三遍", "已经有的练法被后来的覆盖了")
    }

    /// 「下次只盯这一个」必须带一句他自己能当场自查的达标线，否则那张深色卡片
    /// 下面写的只能是一句所有目标共用的空话。
    func testTheSuccessBehaviourIsKeptWithTheTarget() throws {
        let json = #"""
        {"priority_target":{"id":"logic-explain","label":"补一个原因和例子","status":"new",
                            "success_behavior":"每个回答里都出现一次 This is mainly because",
                            "evidence":["I just like it."]}}
        """#
        let outcome = ReviewArchiver.archive(report: try JSONValue.decode(from: json),
                                             into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(outcome.state.targets.first?.successBehavior,
                       "每个回答里都出现一次 This is mainly because")
    }

    /// **缺了达标线不许把整个目标丢掉。** 目标是改进闭环的起点，
    /// 为了一个新加的字段把它扔了，比没有这个字段更糟。
    func testATargetWithoutASuccessBehaviourIsStillKept() throws {
        let json = #"{"priority_target":{"id":"logic-explain","label":"补一个原因和例子"}}"#
        let outcome = ReviewArchiver.archive(report: try JSONValue.decode(from: json),
                                             into: baseState(),
                                             sessionID: "s1", questionID: "q1", at: "t")
        XCTAssertEqual(outcome.state.targets.count, 1)
        XCTAssertEqual(outcome.state.targets.first?.successBehavior, "")
    }

    /// 这两个字段上线之前存下来的档案仍然要读得出来。手写解码器用 `decode` 而不是
    /// `decodeIfPresent` 的话，那个 `keyNotFound` 会一路冒泡到 `StateStore`，
    /// 把用户全部练习记录说成「已损坏」——为了一个新加的字段。
    func testArchivesWrittenBeforeTheseFieldsExistedStillLoad() throws {
        let old = #"""
        {"schemaVersion":3,
         "issues":[{"id":"i1","learnerSaid":"a","correction":"b","whyItMatters":"c",
                    "occurrences":1,"sourceSessionIds":["s1"],"lastSeenAt":"t"}],
         "targets":[{"id":"t1","label":"l","status":"new","evidence":[],
                     "sourceSessionId":"s1","createdAt":"t"}]}
        """#
        let state = try JSONDecoder().decode(CoachState.self, from: Data(old.utf8))
        XCTAssertEqual(state.issues.first?.miniDrill, "")
        XCTAssertEqual(state.targets.first?.successBehavior, "")
    }
}
