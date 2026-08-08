import XCTest

@testable import IELTSCoachCore

/// **在用户自己的机器上把旧结构题库改成新结构，而不丢任何东西。**
///
/// `QuestionBankRemodelTests` 守的是「导入一份新题库时会发生什么」；这一份守的是另一条路：
/// 用户手上**没有**那份题库文件了（三个月前下载的 PDF、换过电脑、当初是用 CSV 拼的），
/// 只剩数据目录里那 1265 道旧题。那条路不通的话，他的题库会一直停在旧结构上。
///
/// 这组测试的判据全部对着真实数据（2026-08-08 从
/// `~/Library/Application Support/IELTS Speaking Coach/state.json` 读出来的形状）：
/// 1265 道题 = Part 1 281 道 + Part 2 99 道 + Part 3 885 道，
/// 外加一道他自己用 CSV 加的 `p1-home-001`（唯一一场真实练习就挂在它上面）。
final class QuestionBankRemodelMigrationTests: XCTestCase {

    // MARK: - 样本

    private func legacy(part: Int, topic: String, prompt: String,
                        status: String = "new", source: String = "季度题库") -> Question {
        Question(id: QuestionBankImporter.questionID(part: part, topic: topic, prompt: prompt),
                 part: part, topic: topic, prompt: prompt, source: source, status: status)
    }

    private func session(_ id: String, questionID: String) -> PracticeSession {
        PracticeSession(id: id, questionId: questionID, focusPart: .part1,
                        startedAt: "2026-08-08T08:00:00Z", endedAt: "2026-08-08T08:20:00Z",
                        goal: "", transcript: [], reportPath: "reports/\(id).json",
                        recordingPath: "")
    }

    // MARK: - 分组

    /// 一个话题下的六个问句并成一道题，六句一句不少地成为参考问句。
    ///
    /// 用户原话：「8-Borrowing/lending 下面那六个问句，「8 Borrowing/lending」应该是一道题。」
    func testTheOldOneQuestionPerRowBankIsRegroupedByTopic() {
        var state = CoachState.empty()
        let prompts = ["Do you like to lend things to others?",
                       "Have you ever borrowed money from others?",
                       "Do you prefer to borrow things or buy them?"]
        state.questions = prompts.map { legacy(part: 1, topic: "Borrowing/lending", prompt: $0) }

        let outcome = QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(state.questions.count, 1,
                       "三道旧「题」没有并成一道：\(state.questions.map(\.prompt))")
        XCTAssertEqual(state.questions[0].prompt, "Borrowing/lending")
        XCTAssertEqual(state.questions[0].followups, prompts,
                       "参考问句丢了或者被重排了——顺序是题库里的原顺序，用户看得见")
        XCTAssertEqual(outcome.absorbedCount, 3)
        XCTAssertEqual(outcome.topicQuestionCount, 1)
        XCTAssertTrue(outcome.lostPrompts.isEmpty, "有问句消失了：\(outcome.lostPrompts)")
    }

    /// **反面：只有一道题的话题不算旧结构，一个字符都不许动。**
    ///
    /// 这一条对着用户真实数据里那道 `p1-home-001`：他自己用 CSV 加的，
    /// 话题 Home 下就它一道，而他**唯一一场真实练习**挂在它上面。
    /// 判据一放宽，那道题会被改名换号，那场练习跟着搬家——而他从没要求过这件事。
    func testAHandAddedQuestionThatIsAloneUnderItsTopicIsLeftExactlyAsItWas() {
        var state = CoachState.empty()
        let mine = Question(id: "p1-home-001", part: 1, topic: "Home",
                            prompt: "What do you like most about your home?",
                            source: "s", status: "practiced")
        state.questions = [mine,
                           legacy(part: 1, topic: "Study and work", prompt: "Do you work?"),
                           legacy(part: 1, topic: "Study and work", prompt: "Do you like it?")]
        state.sessions = [session("2026-08-08-001", questionID: "p1-home-001")]

        let outcome = QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(state.questions.first { $0.id == "p1-home-001" }, mine,
                       "用户自己加的那道题被改了。它的 id、题干、来源、已练标记都不该动")
        XCTAssertEqual(state.sessions[0].questionId, "p1-home-001",
                       "他唯一一场真实练习被搬到了别的题号上")
        XCTAssertTrue(outcome.orphansAfter.isEmpty)
        // 另一个话题照常合并，证明这条测试不是因为整个迁移没跑起来才绿的。
        XCTAssertEqual(outcome.absorbedCount, 2)
    }

    /// Part 2 一张 cue card 本来就是一道题，永远不参与合并。
    ///
    /// 它的 `topic` 是「人物」这类类别标签，四张卡共用一个标签——
    /// 按话题合并的话，一张卡会把另外三张吃掉。
    func testCueCardsAreNeverMerged() {
        var state = CoachState.empty()
        state.questions = [
            Question(id: "p2-a", part: 2, topic: "人物", prompt: "Describe a person you admire"),
            Question(id: "p2-b", part: 2, topic: "人物", prompt: "Describe a helpful neighbour"),
            Question(id: "p2-c", part: 2, topic: "人物", prompt: "Describe a famous athlete")
        ]
        let before = state.questions

        let outcome = QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(state.questions, before, "Part 2 被合并了：\(state.questions.map(\.prompt))")
        XCTAssertFalse(outcome.changedAnything)
    }

    // MARK: - 历史记录跟着搬家

    /// 四处引用（练习记录、复训链接、正在进行的一场、学习计划）一处都不能留在旧题号上。
    func testEveryPlaceThatPointsAtAQuestionFollowsItToItsNewID() {
        var state = CoachState.empty()
        let a = legacy(part: 3, topic: "Describe a long journey you had",
                       prompt: "Why do people travel?")
        let b = legacy(part: 3, topic: "Describe a long journey you had",
                       prompt: "Is travelling good for children?")
        state.questions = [a, b]
        var practised = session("2026-08-01-001", questionID: a.id)
        practised.retraining = RetrainingLink(targetKey: "grammar",
                                              sourceSessionId: "2026-07-30-001",
                                              originalQuestionId: b.id)
        state.sessions = [practised]
        state.currentSession = session("2026-08-08-001", questionID: b.id)
        state.plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-01T00:00:00Z",
                                  days: [PlanDay(id: 1, questionIds: [a.id, b.id],
                                                 completedQuestionIds: [a.id])])

        let outcome = QuestionBankRemodel.apply(to: &state)

        let newID = state.questions[0].id
        XCTAssertEqual(state.sessions[0].questionId, newID)
        XCTAssertEqual(state.sessions[0].retraining?.originalQuestionId, newID)
        XCTAssertEqual(state.currentSession?.questionId, newID)
        // 同一天里的两道旧题搬到同一道新题上，必须去重——否则计划里那天会列同一道题两遍。
        XCTAssertEqual(state.plan?.days[0].questionIds, [newID])
        XCTAssertEqual(state.plan?.days[0].completedQuestionIds, [newID])
        XCTAssertEqual(outcome.remappedReferenceCount, 6,
                       "改写的引用处数不对，说明有一处没搬或者搬重了")
        XCTAssertTrue(outcome.orphansAfter.isEmpty,
                      "迁移之后还有指不到题的引用：\(outcome.orphansAfter)")
    }

    /// **孤儿体检的清单不能漏掉任何一处。**
    ///
    /// 这条是上一条的地基：`orphanedReferences` 少查一处，那一处的孤儿就永远不会被报出来，
    /// 而上面那条 `orphansAfter.isEmpty` 会因此变成一句好听的空话。
    func testTheOrphanCheckLooksAtAllFourPlacesThatCanPointAtAQuestion() {
        var state = CoachState.empty()
        state.questions = []          // 题库整个是空的，所以下面每一处都是孤儿
        var practised = session("s1", questionID: "from-session")
        practised.retraining = RetrainingLink(targetKey: "k", sourceSessionId: "s0",
                                              originalQuestionId: "from-retraining")
        state.sessions = [practised]
        state.currentSession = session("s2", questionID: "from-current")
        state.plan = TrainingPlan(lengthDays: 7, createdAt: "",
                                  days: [PlanDay(id: 1, questionIds: ["from-plan"],
                                                 completedQuestionIds: ["from-plan-done"])])

        XCTAssertEqual(Set(QuestionBankRemodel.orphanedReferences(in: state)),
                       ["from-session", "from-retraining", "from-current",
                        "from-plan", "from-plan-done"],
                       "有一处指向题目的地方没被查到——那一处的孤儿会永远沉默")
    }

    /// 迁移**之前**就有的孤儿要如实报出来，但不许算到这次迁移头上。
    func testPreExistingOrphansAreReportedWithoutBeingBlamedOnTheMigration() {
        var state = CoachState.empty()
        state.questions = [legacy(part: 1, topic: "Music", prompt: "a?"),
                           legacy(part: 1, topic: "Music", prompt: "b?")]
        state.sessions = [session("s1", questionID: "一道早就被删掉的题")]

        let outcome = QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(outcome.orphansBefore, ["一道早就被删掉的题"])
        XCTAssertEqual(outcome.orphansAfter, ["一道早就被删掉的题"])
        XCTAssertTrue(outcome.newOrphans.isEmpty,
                      "把迁移之前就有的孤儿算成了这次迁移造出来的：\(outcome.newOrphans)")
        XCTAssertTrue(outcome.isSafeToApply)
    }

    // MARK: - 重跑

    /// **跑第二遍，磁盘上的数据一个字节都不该变。**
    ///
    /// 迁移会被重跑：用户跑完一次不放心再跑一次、或者先跑迁移再导入题库。
    /// 第二遍还在改东西的话，题号会再变一次，历史记录跟着搬第二次家。
    func testRunningItASecondTimeChangesNothing() {
        var state = CoachState.empty()
        state.questions = [legacy(part: 1, topic: "Music", prompt: "Do you like music?"),
                           legacy(part: 1, topic: "Music", prompt: "What did you like as a child?"),
                           legacy(part: 3, topic: "Describe a song", prompt: "Why do people sing?"),
                           legacy(part: 3, topic: "Describe a song", prompt: "Is music education needed?")]
        state.sessions = [session("s1", questionID: state.questions[0].id)]

        QuestionBankRemodel.apply(to: &state)
        let afterFirst = state
        let second = QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(state, afterFirst, "第二次迁移又把数据改了一遍")
        XCTAssertFalse(second.changedAnything)
        XCTAssertEqual(second.absorbedCount, 0)
        XCTAssertEqual(second.remappedReferenceCount, 0)
    }

    /// **重跑时话题名本身不许混进参考问句。**
    ///
    /// 话题题的题干**就等于**话题名（`TopicQuestions` 的判据）。第二次分组时若还把
    /// 「题干」当成一条问句收进来，`followups` 里会凭空多出一行「Music」——
    /// 一条考官会真的照着念出口的假问题，而题数、id 全都没变，肉眼极难发现。
    func testTheTopicNameItselfNeverLeaksIntoTheReferencePromptsOnARerun() {
        var state = CoachState.empty()
        state.questions = [legacy(part: 1, topic: "Music", prompt: "a?"),
                           legacy(part: 1, topic: "Music", prompt: "b?")]
        QuestionBankRemodel.apply(to: &state)

        // 再塞一道同话题的碎片进来（用户后来又用 CSV 补了一道），逼第二次分组真的跑起来。
        state.questions.append(legacy(part: 1, topic: "Music", prompt: "c?"))
        QuestionBankRemodel.apply(to: &state)

        XCTAssertEqual(state.questions.count, 1)
        XCTAssertEqual(state.questions[0].followups, ["a?", "b?", "c?"],
                       "参考问句里混进了话题名本身（或者顺序乱了）：\(state.questions[0].followups)")
    }

    // MARK: - 不许静默丢东西

    /// 每一句旧题干，迁移之后要么还是某道题的题干，要么成了某道题的参考问句。
    ///
    /// 这条断言的**牙齿**在于它扫的是迁移前的全部题目，而不是「被合并的那些」：
    /// 合并逻辑要是哪天开始丢弃它认不出的碎片，这里会立刻报出那几句话的原文。
    func testNotOneSinglePromptDisappears() {
        var state = CoachState.empty()
        state.questions =
            (1...6).map { legacy(part: 1, topic: "Borrowing/lending", prompt: "q\($0)?") }
            + (1...9).map { legacy(part: 3, topic: "Describe a smart person", prompt: "p\($0)?") }
            + [Question(id: "p2-x", part: 2, topic: "人物", prompt: "Describe a person")]
        let allPrompts = state.questions.map(\.prompt)

        let outcome = QuestionBankRemodel.apply(to: &state)

        var surviving: Set<String> = []
        for question in state.questions {
            surviving.insert(question.prompt)
            for followup in question.followups { surviving.insert(followup) }
        }
        for prompt in allPrompts {
            XCTAssertTrue(surviving.contains(prompt),
                          "「\(prompt)」在迁移之后既不是任何一道题的题干，也不是任何一条参考问句——"
                              + "它被静默丢掉了")
        }
        XCTAssertTrue(outcome.lostPrompts.isEmpty)
        XCTAssertTrue(outcome.isSafeToApply)
    }

    /// **上面那条断言的地基：那个「丢东西」的探测器真的探得出来。**
    ///
    /// 今天的合并逻辑只有在确认旧题的题干已经进了新题的参考问句之后才会删掉它
    /// （`TopicQuestions.supersedes`），所以 `lostPrompts` 在今天恒为空——
    /// 只断言「它是空的」等于什么都没测（铁律 1：把被测逻辑改成空实现，那条测试会不会红？
    /// 答案会是「不会」）。
    ///
    /// 所以这里直接喂它一份**真的丢了东西**的前后对照：
    /// 一道题在新题库里既不是谁的题干、也不是谁的参考问句。探得出来，
    /// 上面那条「迁移没丢东西」才算数；探不出来（比如有人把它改成 `return []`），
    /// 这条会红。
    func testTheLostPromptDetectorReallyDetectsALoss() {
        let before = [legacy(part: 1, topic: "Music", prompt: "a?"),
                      legacy(part: 1, topic: "Music", prompt: "b?"),
                      legacy(part: 1, topic: "Music", prompt: "被吃掉的那一句?")]
        // 一份「合并判据被放宽」之后可能出现的结果：第三句谁都没留住。
        let after = [TopicQuestions.part1(topic: "Music", prompts: ["a?", "b?"])]

        XCTAssertEqual(QuestionBankRemodel.lostPrompts(before: before, after: after),
                       ["被吃掉的那一句?"],
                       "探测器没认出被吃掉的那一句——「迁移没丢东西」这条保证也就成了空话")

        // 反面：题干变成了参考问句**不算丢**，那正是这次重建模在做的事。
        XCTAssertTrue(
            QuestionBankRemodel.lostPrompts(
                before: before,
                after: [TopicQuestions.part1(topic: "Music",
                                             prompts: ["a?", "b?", "被吃掉的那一句?"])]).isEmpty,
            "把题干收成参考问句被误报成了「丢了」——那样每次正常迁移都会被拦下来")
    }

    /// 迁移**不发明内容**：参考问句全部来自旧题自己的题干，一句不多。
    ///
    /// 少了这条，上面那条「一句都没丢」可以被一个「把所有问句复制给每一道题」的
    /// 荒唐实现凑绿。
    func testItInventsNothing() {
        var state = CoachState.empty()
        state.questions = [legacy(part: 1, topic: "Music", prompt: "a?"),
                           legacy(part: 1, topic: "Music", prompt: "b?"),
                           legacy(part: 1, topic: "Sport", prompt: "c?"),
                           legacy(part: 1, topic: "Sport", prompt: "d?")]
        let known = Set(state.questions.map(\.prompt) + state.questions.map(\.topic))

        QuestionBankRemodel.apply(to: &state)

        for question in state.questions {
            XCTAssertTrue(known.contains(question.prompt), "凭空多出一道题：\(question.prompt)")
            for followup in question.followups {
                XCTAssertTrue(known.contains(followup), "凭空多出一条参考问句：\(followup)")
            }
        }
        XCTAssertEqual(state.questions.map(\.followups), [["a?", "b?"], ["c?", "d?"]],
                       "两个话题的问句串到一起去了：\(state.questions.map(\.followups))")
    }

    // MARK: - 两条路必须收敛

    /// **原地迁移与「把同一份题库再导入一次」必须落在同一批题号上。**
    ///
    /// 这是整件事能同时提供两条路的前提。收敛不了的话，用户先跑迁移、后来又导入一次
    /// 季度题库，历史记录会搬第二次家——而他做的两件事在他看来都是「整理题库」。
    ///
    /// 2026-08-08 拿他真实那 1265 道题实测过一遍：两条路产出的 258 道题
    /// **id 与参考问句逐条相同**。这条测试把那次实测固化下来。
    func testRemodellingInPlaceLandsOnExactlyTheSameQuestionsAsReimportingTheBank() {
        let prompts = ["Do you like to lend things?", "Have you borrowed money?"]
        let legacyBank = prompts.map { legacy(part: 1, topic: "Borrowing/lending", prompt: $0) }

        var remodelled = CoachState.empty()
        remodelled.questions = legacyBank
        QuestionBankRemodel.apply(to: &remodelled)

        // 另一条路：一份「重新导入的季度题库」，形状就是导入器产出的话题题。
        let reimportedBank = QuestionBankImporter.merge(
            existing: legacyBank,
            incoming: [TopicQuestions.part1(topic: "Borrowing/lending", prompts: prompts,
                                            source: "季度题库")]).questions

        XCTAssertEqual(remodelled.questions.map(\.id), reimportedBank.map(\.id),
                       "两条路给出了不同的题号，用户走完一条再走另一条会被搬第二次家")
        XCTAssertEqual(remodelled.questions.map(\.followups), reimportedBank.map(\.followups))
    }

    // MARK: - 交代

    /// 报告要同时说清「发生了什么」和「下一步做什么」（铁律 6），而且不许只报好消息。
    func testTheReportSaysWhatHappenedAndWhatToDoNext() {
        var state = CoachState.empty()
        state.questions = [legacy(part: 1, topic: "Music", prompt: "a?"),
                           legacy(part: 1, topic: "Music", prompt: "b?")]
        state.sessions = [session("s1", questionID: "一道早就被删掉的题")]

        let report = QuestionBankRemodel.report(QuestionBankRemodel.apply(to: &state))

        XCTAssertTrue(report.contains("下一步"), "报告没写下一步：\(report)")
        XCTAssertTrue(report.contains("2") && report.contains("1"),
                      "报告没给出题数变化：\(report)")
        XCTAssertTrue(report.contains("一道早就被删掉的题"),
                      "还有一处引用指不到题，报告却只字不提——这正是「静默失败」：\(report)")
    }

    /// 已经是新结构时，报告不能装作干了活。
    func testTheReportOfANoOpDoesNotPretendItDidSomething() {
        var state = CoachState.empty()
        state.questions = [TopicQuestions.part1(topic: "Music", prompts: ["a?", "b?"])]

        let outcome = QuestionBankRemodel.apply(to: &state)
        let report = QuestionBankRemodel.report(outcome)

        XCTAssertFalse(outcome.changedAnything)
        XCTAssertTrue(report.contains("一个字都没有改"), report)
        XCTAssertTrue(report.contains("下一步"), report)
    }
}

/// 动用户数据之前那一份备份。
///
/// 这几条守的是「备份没做成时绝不往下走」和「绝不覆盖上一份备份」——
/// 后者是这类命令最坏的失手方式：用户以为自己有两道保险，其实只有一道。
final class DataBackupTests: XCTestCase {

    private func makeDataDirectory() throws -> (DataDirectory, URL) {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-backup-tests-\(UUID().uuidString)")
        let directory = DataDirectory(root: parent.appending(path: "IELTS Speaking Coach"))
        try directory.createIfNeeded()
        try "{}".write(to: directory.stateFile, atomically: true, encoding: .utf8)
        try "录音".write(to: directory.recordingsDirectory.appending(path: "a.m4a"),
                        atomically: true, encoding: .utf8)
        try "复盘".write(to: directory.reportsDirectory.appending(path: "r.json"),
                        atomically: true, encoding: .utf8)
        return (directory, parent)
    }

    /// **整份复制，不是只复制 state.json。**
    ///
    /// state.json 里存的是相对路径（`reports/…`、`recordings/…`）。只备份它的话，
    /// 回滚出来的是一份看着完整、点开却处处「文件找不到」的数据。
    func testTheBackupContainsTheWholeTreeNotJustTheStateFile() throws {
        let (directory, parent) = try makeDataDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let backup = try DataBackup.copy(directory, into: parent)

        for relative in ["state.json", "recordings/a.m4a", "reports/r.json"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: backup.appending(path: relative).path),
                "备份里少了 \(relative)——回滚之后这一项就永久没了")
        }
    }

    /// 同一秒内跑第二次，**不许覆盖第一份备份**。
    func testASecondBackupInTheSameSecondNeverOverwritesTheFirst() throws {
        let (directory, parent) = try makeDataDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let moment = Date(timeIntervalSince1970: 1_786_000_000)

        let first = try DataBackup.copy(directory, into: parent, at: moment)
        try "改过了".write(to: directory.stateFile, atomically: true, encoding: .utf8)
        let second = try DataBackup.copy(directory, into: parent, at: moment)

        XCTAssertNotEqual(first.path, second.path, "第二份备份盖掉了第一份")
        XCTAssertEqual(try String(contentsOf: first.appending(path: "state.json"),
                                  encoding: .utf8), "{}",
                       "第一份备份的内容被后一次运行改掉了")
    }

    /// 备份文件夹的名字要和用户已有的那份手工备份同一个命名法，否则它们不会排在一起。
    func testTheBackupFolderIsNamedLikeTheOneTheUserAlreadyHas() {
        let name = DataBackup.folderName(
            at: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: TimeZone(secondsFromGMT: 8 * 3600) ?? .gmt)
        XCTAssertTrue(name.hasPrefix("ielts-coach-backup-"), name)
        XCTAssertEqual(name.count, "ielts-coach-backup-20260808-161115".count,
                       "时间戳的形状和用户那份对不上：\(name)")
    }

    /// 目录不存在时必须抛错，**不能返回一个空备份然后让后面那一步照常改数据**。
    func testItRefusesWhenThereIsNothingToBackUp() {
        let missing = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-backup-missing-\(UUID().uuidString)"))
        XCTAssertThrowsError(
            try DataBackup.copy(missing, into: URL(fileURLWithPath: NSTemporaryDirectory()))
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("下一步"),
                          error.localizedDescription)
        }
    }
}
