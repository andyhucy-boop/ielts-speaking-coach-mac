import XCTest

@testable import IELTSCoachCore

/// 题库从「一问一题」改成「一话题一题」这次重建模，**以及它必须带着走的数据迁移**。
///
/// ## 为什么迁移不是可选项
///
/// 题号是内容哈希（`QuestionBankImporter.questionID`）。Part 1 从「每个问句一道题」
/// 变成「每个话题一道题」之后，那 281 道 Part 1 与 885 道 Part 3 的 id **全部作废**。
/// 什么都不做的话有两个后果，用户都会当场看到：
///
/// 1. 旧题一道不少地留在库里，新的话题题追加在后面——题库从 1265 道涨到 1424 道；
/// 2. 挂在旧题号上的练习记录、复训链接、学习计划指向不存在的题，
///    训练记录页显示「这道题已经不在题库里了（id：…）」。
///
/// 所以合并那一步要认碎片（`TopicQuestions.supersedes`）、要报告搬家清单
/// （`MergeResult.replacements`），调用方要在同一个写事务里把引用改过去
/// （`QuestionBankMigration.remapQuestionIDs`）。这个文件逐条守这三件事。
final class QuestionBankRemodelTests: XCTestCase {

    // MARK: - 样本：用户题库在重建模之前长什么样

    /// 旧结构：一个话题被拆成三道「题」。id 按当时的规则算（内容哈希，prompt 是问句本身）。
    private func legacyPart1(topic: String, prompt: String,
                             status: String = "new") -> Question {
        Question(id: QuestionBankImporter.questionID(part: 1, topic: topic, prompt: prompt),
                 part: 1, topic: topic, prompt: prompt, source: "上一版", status: status)
    }

    private func legacyPart3(cueCard: String, prompt: String,
                             status: String = "new") -> Question {
        Question(id: QuestionBankImporter.questionID(part: 3, topic: cueCard, prompt: prompt),
                 part: 3, topic: cueCard, prompt: prompt, source: "上一版", status: status)
    }

    // MARK: - 合并：旧碎片被吸收，而且交代得出去向

    /// **三道旧的 Part 1「题」并成一道话题题，题库不是变多而是变少。**
    ///
    /// 不认碎片的话这里会是 4 道（3 道旧的原地不动 + 1 道新的追加在后面）。
    func testATopicQuestionAbsorbsTheOldOneQuestionPerRowFragments() {
        let existing = [
            legacyPart1(topic: "Borrowing/lending", prompt: "Do you like to lend things to others?"),
            legacyPart1(topic: "Borrowing/lending", prompt: "Have you ever borrowed money from others?"),
            legacyPart1(topic: "Borrowing/lending", prompt: "Do you prefer to borrow things or buy them?")
        ]
        let incoming = [TopicQuestions.part1(
            topic: "Borrowing/lending",
            prompts: existing.map(\.prompt), source: "新一版")]

        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.questions.map(\.prompt), ["Borrowing/lending"],
                       "旧碎片没有被吸收，题库反而变多了：\(merged.questions.map(\.prompt))")
        XCTAssertEqual(Set(merged.replacements.keys), Set(existing.map(\.id)),
                       "被吸收的三道旧题必须逐一出现在搬家清单里，否则挂在它们身上的"
                           + "练习记录会变成孤儿，而且没人知道该搬到哪儿去")
        XCTAssertEqual(Set(merged.replacements.values), [incoming[0].id],
                       "三道旧题都该搬到同一道话题题上")
    }

    /// Part 3 那一半：一张 cue card 底下的九道旧「追问题」并成一道。
    func testAPart3GroupAbsorbsTheOldPerFollowupQuestions() {
        let cueCard = "Describe a person who solved a problem in a smart way"
        let existing = [
            legacyPart3(cueCard: cueCard, prompt: "What qualities do such people have?"),
            legacyPart3(cueCard: cueCard, prompt: "Can creativity be taught?")
        ]
        let incoming = [TopicQuestions.part3(cueCard: cueCard,
                                             prompts: existing.map(\.prompt), source: "新一版")]

        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.questions.count, 1)
        XCTAssertEqual(merged.questions[0].followups, existing.map(\.prompt),
                       "那一组追问必须原样留在 followups 里——吸收不是删除")
        XCTAssertEqual(merged.replacements.count, 2)
    }

    /// **反面：吸收的判据必须窄。** 同一个话题下，一道题干不在参考问句里的旧题**不许**被吃掉。
    ///
    /// 这一条对着真实数据：用户库里那道 `p1-home-001`（他自己用 CSV 加的、
    /// 唯一一场真实练习就挂在它上面）话题是 Home。判据要是放宽成「同话题就吸收」，
    /// 一次无关的题库导入会把它连同那场练习一起搬走，而他并没有要求过这件事。
    func testAQuestionWhoseTextIsNotInTheReferenceListIsNotAbsorbed() {
        let mine = Question(id: "p1-home-001", part: 1, topic: "Home",
                            prompt: "What do you like most about your home?",
                            source: "我自己加的", status: "practiced")
        let incoming = [TopicQuestions.part1(
            topic: "Home",
            prompts: ["Do you live in a house or a flat?"], source: "季度题库")]

        let merged = QuestionBankImporter.merge(existing: [mine], incoming: incoming)

        XCTAssertTrue(merged.replacements.isEmpty,
                      "同话题但题干对不上的题被当成碎片吃掉了：\(merged.replacements)")
        XCTAssertEqual(merged.questions.first?.id, "p1-home-001",
                       "用户自己加的题必须原样留在题库里")
        XCTAssertEqual(merged.questions.count, 2, "话题题应当作为新的一道追加进来")
    }

    /// Part 2 不参与吸收：cue card 的 `topic` 是「人物」这类类别标签，
    /// 四张卡共用一个标签。按话题吸收的话，一张卡会把另外三张吃掉。
    func testCueCardsAreNeverTreatedAsFragmentsOfEachOther() {
        let existing = [
            Question(id: "p2-a", part: 2, topic: "人物", prompt: "Describe a person you admire"),
            Question(id: "p2-b", part: 2, topic: "人物", prompt: "Describe a helpful neighbour")
        ]
        // 恶意形状：一道 part 2 的题，prompt 恰好等于 topic，followups 里装着另外两张卡。
        let incoming = [Question(id: "p2-c", part: 2, topic: "人物", prompt: "人物",
                                 followups: existing.map(\.prompt))]

        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)

        XCTAssertTrue(merged.replacements.isEmpty,
                      "Part 2 也去认碎片了，两张 cue card 被吃掉：\(merged.replacements)")
        XCTAssertEqual(merged.questions.count, 3)
    }

    /// 被吸收的碎片里只要有一道练过，「已练」就要升到吸收它的那道话题题上。
    ///
    /// 不升的话，用户练过的那个话题在题库页会重新显示「没练过」——
    /// 「已经练过」那个数字会当场掉下去，而他什么都没做错。
    func testPracticedStatusRidesAlongWhenAFragmentIsAbsorbed() {
        let existing = [
            legacyPart1(topic: "Hometown", prompt: "Where is your hometown?", status: "practiced"),
            legacyPart1(topic: "Hometown", prompt: "Do you like it?")
        ]
        let incoming = [TopicQuestions.part1(topic: "Hometown",
                                             prompts: existing.map(\.prompt), source: "新一版")]

        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.questions.map(\.status), ["practiced"],
                       "练过的记号在合并时丢了：\(merged.questions.map { "\($0.prompt)=\($0.status)" })")
    }

    /// **再导一次同一份题库，题库不增不减、也不再有任何搬家。**
    ///
    /// 换季重新导入是常态。第二次导入还在吸收东西的话，说明这套判据不是幂等的，
    /// 用户每导一次题号都会变一遍，历史记录跟着搬来搬去。
    func testImportingTheSameBankTwiceChangesNothing() {
        let existing = [
            legacyPart1(topic: "Music", prompt: "Do you like music?"),
            legacyPart1(topic: "Music", prompt: "What music did you like as a child?")
        ]
        let incoming = [TopicQuestions.part1(topic: "Music",
                                             prompts: existing.map(\.prompt), source: "新一版")]

        let once = QuestionBankImporter.merge(existing: existing, incoming: incoming)
        let twice = QuestionBankImporter.merge(existing: once.questions, incoming: incoming)

        XCTAssertEqual(twice.questions, once.questions, "第二次导入把题库又改了一遍")
        XCTAssertTrue(twice.replacements.isEmpty,
                      "第二次导入还在搬家：\(twice.replacements)")
    }

    // MARK: - 题号搬家：四处引用一处都不能漏

    private func stateWithOneSession(questionID: String) -> CoachState {
        var state = CoachState.empty()
        state.sessions = [PracticeSession(
            id: "2026-08-08-001", questionId: questionID, focusPart: .part1,
            startedAt: "2026-08-08T08:00:00Z", endedAt: "2026-08-08T08:20:00Z",
            goal: "", transcript: [], reportPath: "reports/2026-08-08-001.json",
            recordingPath: "")]
        return state
    }

    func testAPracticeSessionFollowsItsQuestionToTheNewID() {
        var state = stateWithOneSession(questionID: "old-1")
        let changed = QuestionBankMigration.remapQuestionIDs(
            in: &state, replacements: ["old-1": "new-1"])

        XCTAssertEqual(state.sessions[0].questionId, "new-1",
                       "那场练习还指着已经不存在的题号，训练记录页会显示"
                           + "「这道题已经不在题库里了」")
        XCTAssertEqual(changed, 1)
    }

    /// 复训链接里那个 `originalQuestionId` 同样要搬。
    ///
    /// 不搬的话 `retrainingKind` 会把一场「原题重练」判成「换题验证」
    /// （它比的正是 `questionId == originalQuestionId`），
    /// 复训中心会显示这个目标已经换题验证过了——而其实一次都没有。
    func testTheRetrainingLinkOriginalQuestionAlsoMoves() {
        var state = stateWithOneSession(questionID: "old-1")
        state.sessions[0].retraining = RetrainingLink(
            targetKey: "grammar", sourceSessionId: "2026-08-01-001",
            originalQuestionId: "old-1")

        QuestionBankMigration.remapQuestionIDs(in: &state, replacements: ["old-1": "new-1"])

        XCTAssertEqual(state.sessions[0].retraining?.originalQuestionId, "new-1")
        XCTAssertEqual(state.sessions[0].retrainingKind, .original,
                       "只搬了 questionId 没搬 originalQuestionId：一场原题重练"
                           + "被判成了换题验证，复训中心会谎报「已经验证过」")
    }

    func testTheSessionInFlightAlsoMoves() {
        var state = stateWithOneSession(questionID: "other")
        state.currentSession = state.sessions[0]
        state.currentSession?.questionId = "old-1"

        QuestionBankMigration.remapQuestionIDs(in: &state, replacements: ["old-1": "new-1"])

        XCTAssertEqual(state.currentSession?.questionId, "new-1",
                       "正练到一半时导入题库，这一场会指向不存在的题")
    }

    /// 计划里的题号要搬，**而且同一天里搬到一起的两道要去重**。
    ///
    /// 不去重的话，学习计划那一天会把同一道题列两遍：用户点第一遍练完之后
    /// 第二遍仍然亮着「还没练」，看着像进度没保存。
    func testThePlanMovesAndCollapsesDuplicatesWithinADay() {
        var state = CoachState.empty()
        state.plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-01T00:00:00Z", days: [
            PlanDay(id: 1, questionIds: ["old-1", "old-2", "keep"],
                    completedQuestionIds: ["old-1", "old-2"])
        ])

        QuestionBankMigration.remapQuestionIDs(
            in: &state, replacements: ["old-1": "new-1", "old-2": "new-1"])

        XCTAssertEqual(state.plan?.days[0].questionIds, ["new-1", "keep"],
                       "计划里的旧题号没搬，或者搬完之后同一天里重复了")
        XCTAssertEqual(state.plan?.days[0].completedQuestionIds, ["new-1"])
    }

    /// 搬家清单是空的时候一个字节都不该动（绝大多数导入都是这样）。
    func testNothingMovesWhenThereIsNothingToMove() {
        var state = stateWithOneSession(questionID: "old-1")
        let before = state
        XCTAssertEqual(QuestionBankMigration.remapQuestionIDs(in: &state, replacements: [:]), 0)
        XCTAssertEqual(state, before)
    }

    // MARK: - 从头到尾走一遍：旧题库 + 新题包

    /// **重建模那一刻，用户的历史记录一条都不许变成孤儿。**
    ///
    /// 这是整件事的验收标准：合并 + 搬家做完之后，每一场练习指向的题号
    /// 都必须能在新题库里找得到。
    func testAfterTheRemodelEveryPracticeSessionStillPointsAtAQuestionThatExists() {
        let topic = "Borrowing/lending"
        let prompts = ["Do you like to lend things to others?",
                       "Have you ever borrowed money from others?"]
        var state = CoachState.empty()
        state.questions = prompts.map { legacyPart1(topic: topic, prompt: $0, status: "practiced") }
        state.sessions = state.questions.map { question in
            PracticeSession(id: "session-\(question.id)", questionId: question.id,
                            focusPart: .part1, startedAt: "", endedAt: "", goal: "",
                            transcript: [], reportPath: "", recordingPath: "")
        }
        state.plan = TrainingPlan(lengthDays: 7, createdAt: "", days: [
            PlanDay(id: 1, questionIds: state.questions.map(\.id), completedQuestionIds: [])
        ])

        let incoming = [TopicQuestions.part1(topic: topic, prompts: prompts, source: "新一版")]
        let merged = QuestionBankImporter.merge(existing: state.questions, incoming: incoming)
        state.questions = merged.questions
        QuestionBankMigration.remapQuestionIDs(in: &state, replacements: merged.replacements)

        let live = Set(state.questions.map(\.id))
        let orphans = state.sessions.filter { !live.contains($0.questionId) }
        XCTAssertTrue(orphans.isEmpty,
                      "重建模之后这些练习记录指向了不存在的题："
                          + "\(orphans.map { "\($0.id)→\($0.questionId)" })")
        let plannedOrphans = (state.plan?.days.flatMap(\.questionIds) ?? [])
            .filter { !live.contains($0) }
        XCTAssertTrue(plannedOrphans.isEmpty, "学习计划里剩下了指不到题的题号：\(plannedOrphans)")
        XCTAssertEqual(state.questions.map(\.status), ["practiced"])
    }

    // MARK: - 「你的题库还是旧结构」这个判断

    func testLegacyShapeIsDetectedOnlyWhenATopicReallyHoldsSeveralQuestions() {
        let legacy = [legacyPart1(topic: "Music", prompt: "a?"),
                      legacyPart1(topic: "Music", prompt: "b?")]
        XCTAssertEqual(TopicQuestions.legacyShapedCount(in: legacy), 2)

        let remodelled = [TopicQuestions.part1(topic: "Music", prompts: ["a?", "b?"])]
        XCTAssertEqual(TopicQuestions.legacyShapedCount(in: remodelled), 0,
                       "新结构的题库仍被判成旧结构，那条提示就永远消不掉，等于骚扰")

        // 一个话题只写了一道的（用户自己用 CSV 加的那种）不算旧结构。
        let handWritten = [Question(id: "p1-home-001", part: 1, topic: "Home",
                                    prompt: "What do you like most about your home?")]
        XCTAssertEqual(TopicQuestions.legacyShapedCount(in: handWritten), 0)

        // Part 2 一个类别下本来就有几十张卡，永远不算旧结构。
        let cueCards = [Question(id: "a", part: 2, topic: "人物", prompt: "Describe a person"),
                        Question(id: "b", part: 2, topic: "人物", prompt: "Describe a friend")]
        XCTAssertEqual(TopicQuestions.legacyShapedCount(in: cueCards), 0)
    }

    // MARK: - 话题题的形状本身

    /// `prompt == topic` 是话题题的判据，`supersedes` 与 `isTopicQuestion` 都靠它认人。
    /// 改掉它（比如让 prompt 变成「Let's talk about X」）会让**已经迁移过的题库**
    /// 在下一次导入时认不出自己，于是重新造一批题、再搬一次家。
    func testATopicQuestionUsesItsTopicAsItsPromptAndItsIDFollowsOnlyTheTopic() {
        let question = TopicQuestions.part1(topic: "Borrowing/lending",
                                            prompts: ["a?", "b?"])
        XCTAssertEqual(question.prompt, "Borrowing/lending")
        XCTAssertTrue(TopicQuestions.isTopicQuestion(question))
        XCTAssertEqual(question.id,
                       QuestionBankImporter.questionID(part: 1, topic: "Borrowing/lending",
                                                       prompt: "Borrowing/lending"))
        // 参考问句改了，id **不变**——题库每季度会增删个别问句，
        // 跟着变的话用户练过的那个话题每季度都会变成一道新题。
        XCTAssertEqual(TopicQuestions.part1(topic: "Borrowing/lending", prompts: ["c?"]).id,
                       question.id)
    }
}
