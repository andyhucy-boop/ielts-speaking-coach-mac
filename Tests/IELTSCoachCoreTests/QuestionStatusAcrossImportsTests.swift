import XCTest
@testable import IELTSCoachCore

/// 换季重新导入题库，不许把每道练过的题的「已练」标记清空（复审第 10 条）。
///
/// **雅思题库每季度换题，重新导入是这个产品的日常，不是边缘情况**，
/// 引导页还亲口保证过「同一道题会被新的覆盖，不会变成两道，所以以后换季重新导入也是安全的」。
///
/// 修之前：`merge` 同 id 时整条用新的覆盖旧的，而新导入的每道题 `status` 都是 `"new"`，
/// 于是内容一个字没改的那些题，「已练」标记全部退回「没练过」——题库页顶上
/// 「已经练过」的数字掉下去、每道题右边的勾消失、终端列表里的 ✓ 消失、
/// ChatGPT 侧读到的已练数跟着变小。全程没有提示、没有报错。
/// 项目自己在计划生成器的注释里写着「顺手把 status 重置成 new……会让用户一次点击丢掉全部历史」。
final class QuestionStatusAcrossImportsTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func csv(topic: String, extraRow: String = "") -> String {
        """
        id,part,topic,prompt,followups
        \(extraRow)ignored-1,1,\(topic),Do you work or are you a student?,
        """
    }

    // MARK: - 合并这一步不许把标记抹掉

    /// **第 10 条的最小复现。** 同一道题（同 id）再导一次，「已练」必须还在。
    func testReimportingTheSameQuestionKeepsItMarkedAsPracticed() {
        let existing = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?",
                                 status: "practiced")]
        let incoming = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?")]

        let merged = QuestionBankImporter.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.first?.status, "practiced",
                       "换季重新导入把「已练」标记抹回「没练过」了，而且不可恢复")
    }

    /// 题目内容更新了（题干改了个字、topic 换了写法）也一样：新的内容要进来，
    /// 「练过没有」是用户的进度，不属于题库内容，不许被题库文件覆盖。
    func testUpdatedWordingOverwritesTheContentButNotThePracticedMark() {
        let existing = [Question(id: "q1", part: 1, topic: "旧话题", prompt: "旧题干",
                                 status: "practiced")]
        let incoming = [Question(id: "q1", part: 1, topic: "新话题", prompt: "新题干",
                                 followups: ["f1"], source: "2026 秋季")]

        let merged = try? XCTUnwrap(QuestionBankImporter.merge(existing: existing,
                                                               incoming: incoming).first)
        XCTAssertEqual(merged?.topic, "新话题", "题库内容该更新的还得更新")
        XCTAssertEqual(merged?.prompt, "新题干")
        XCTAssertEqual(merged?.followups, ["f1"])
        XCTAssertEqual(merged?.source, "2026 秋季")
        XCTAssertEqual(merged?.status, "practiced", "进度不是题库内容，不许被覆盖")
    }

    /// 反过来不许倒灌：导入文件里写着 `practiced` 的题，如果本机确实练过就保持，
    /// 但**没练过的题不该因为别人的文件被标成练过**——那是假的正反馈。
    func testAPracticedFlagInsideTheImportedFileDoesNotFakeProgress() {
        let existing = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?")]
        let incoming = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?",
                                 status: "practiced")]

        XCTAssertEqual(QuestionBankImporter.merge(existing: existing, incoming: incoming).first?.status,
                       "new", "本机没练过的题被导入文件标成练过了")
    }

    /// 新题就是新题，不许被这道闸误标成练过。
    func testABrandNewQuestionIsStillNew() {
        let merged = QuestionBankImporter.merge(
            existing: [], incoming: [Question(id: "q9", part: 2, topic: "T", prompt: "P")])
        XCTAssertEqual(merged.first?.status, "new")
    }

    // MARK: - 走真实的导入路：两季题库

    /// 复审用的就是这个场景：上一季练过的题，这一季的包里原样还在。
    /// 走真实的 `importCSV` → `merge` → `StateStore` 写盘 → 重新读盘这一整条路。
    func testASeasonalReimportThroughTheRealPathKeepsThePracticedCount() throws {
        let store = StateStore(directory: directory)

        // 上一季导入，然后练了这道题（`ReviewArchiver` 就是这么标的）。
        let lastSeason = try QuestionBankImporter.importCSV(csv(topic: "Work"),
                                                           sourceTitle: "2026 夏季")
        try store.mutate { state in
            state.questions = QuestionBankImporter.merge(existing: state.questions,
                                                         incoming: lastSeason.questions)
            state.questions[0].status = "practiced"
            state.sessions = [PracticeSession(
                id: "2026-08-06-001", questionId: state.questions[0].id, focusPart: .part1,
                startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                goal: "", transcript: [], reportPath: "reports/2026-08-06-001.json",
                recordingPath: "")]
        }

        // 换季：新包里多了一道题，那道练过的原样还在。
        let thisSeason = try QuestionBankImporter.importCSV(
            csv(topic: "Work", extraRow: "ignored-0,2,Weather,Describe a rainy day.,\n"),
            sourceTitle: "2026 秋季")
        try store.mutate { state in
            state.questions = QuestionBankImporter.merge(existing: state.questions,
                                                         incoming: thisSeason.questions)
        }

        let reloaded = try StateStore(directory: directory).load()
        XCTAssertEqual(reloaded.questions.count, 2, "换季导入之后题目数对不上")
        XCTAssertEqual(reloaded.questions.filter { $0.status == "practiced" }.count, 1,
                       "题库页顶上「已经练过」的数字掉下去了——这正是第 10 条")
        XCTAssertEqual(
            reloaded.questions.first { $0.status == "practiced" }?.prompt,
            "Do you work or are you a student?",
            "标记留在了错的那道题上")

        // **磁盘上的字节也得是对的，不能只靠读盘时那一道自愈。**
        // 只断言 `load()` 的话，合并那一步把标记抹掉照样全绿——自愈会替它兜住，
        // 而自愈兜不住下面那种情况（用户把那条练习记录删了）。
        let raw = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"practiced\""),
                      "state.json 里那道题被写成了 new：合并这一步把标记抹掉了，"
                          + "只是读盘时又被算了回来")
    }

    /// **自愈兜不住的那一种，也是这条缺陷真正不可逆的地方。**
    ///
    /// 「训练记录」页允许逐条删除（确认框还逐字承诺「已经归进错题本和词汇本的内容不会跟着删」）。
    /// 一旦合并那一步把「已练」抹掉、用户之后又删掉了那条练习记录，
    /// 读盘时就再也没有东西能把它算回来——**只能重新练一遍**。
    /// 所以合并那一步本身必须是对的，自愈只是给已经踩过坑的人的补救。
    func testTheMarkSurvivesAnImportEvenWhenNoSessionCanProveItAnymore() {
        // 用户在「训练记录」页把那条旧记录删掉了（这一页就是这么用的，确认框还逐字承诺
        // 「已经归进错题本和词汇本的内容不会跟着删」）。于是读盘时的自愈无从算起。
        let afterImport = QuestionBankImporter.merge(
            existing: [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?",
                                status: "practiced")],
            incoming: [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?")])

        XCTAssertEqual(
            CoachState.reconcilePracticedStatus(questions: afterImport, sessions: []).first?.status,
            "practiced",
            "合并那一步把标记抹掉了，而证明它练过的那条记录已经被删——"
                + "读盘时的自愈救不回来，用户只能把这道题重新练一遍")
    }

    // MARK: - 已经丢掉的标记，开 App 就自动修回来

    /// **给已经踩过这个坑的用户的自动迁移。**
    ///
    /// 第 10 条最疼的一句是「这个标记丢了就再也回不来：应用里没有任何地方能从
    /// 练习记录把它算回去（数据其实是够的）」。数据确实是够的——每条练习记录都存着
    /// `questionId`。所以读盘这一刻按练习记录重算一次，用户什么都不用做。
    /// 做法与 `IssueRecord.occurrences` 那处自愈完全一致。
    func testAPracticedMarkThatWasAlreadyWipedComesBackOnLoad() throws {
        let store = StateStore(directory: directory)
        try store.mutate { state in
            // 已经被旧版本抹成 new 的题库 + 证明练过的那条练习记录。
            state.questions = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?"),
                               Question(id: "q2", part: 2, topic: "Weather", prompt: "Rainy day?")]
            state.sessions = [PracticeSession(
                id: "2026-08-06-001", questionId: "q1", focusPart: .part1,
                startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                goal: "", transcript: [], reportPath: "reports/2026-08-06-001.json",
                recordingPath: "")]
        }

        let reloaded = try StateStore(directory: directory).load()
        XCTAssertEqual(reloaded.questions.first { $0.id == "q1" }?.status, "practiced",
                       "练过的题在读盘时没有被算回来，用户只能重新练一遍")
        XCTAssertEqual(reloaded.questions.first { $0.id == "q2" }?.status, "new",
                       "没练过的题被算成练过了——假的正反馈比不显示更糟")
    }

    /// 正在练、还没归档的那一场不算数：`currentSession` 不是练习记录，
    /// 中途放弃的话那道题从来没被练完过。
    func testASessionStillInProgressDoesNotCountAsPracticed() throws {
        let inProgress = PracticeSession(
            id: "2026-08-06-001", questionId: "q1", focusPart: .part1,
            startedAt: "2026-08-06T10:00:00Z", endedAt: "", goal: "", transcript: [],
            reportPath: "", recordingPath: "")
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?")]
            state.currentSession = inProgress
        }
        XCTAssertEqual(try StateStore(directory: directory).load().questions.first?.status, "new")
    }

    /// 重算是纯函数，单独钉一条：它只往「练过」这一个方向走，绝不反向。
    func testTheReconciliationOnlyEverUpgradesAndNeverDowngrades() {
        let questions = [Question(id: "q1", part: 1, topic: "", prompt: "", status: "practiced"),
                         Question(id: "q2", part: 1, topic: "", prompt: "")]
        let reconciled = CoachState.reconcilePracticedStatus(
            questions: questions, sessions: [])   // 一条练习记录都没有
        XCTAssertEqual(reconciled.map(\.status), ["practiced", "new"],
                       "没有练习记录时不许把已有的「已练」标记抹掉——"
                           + "训练记录允许单条删除，删掉记录不该连带把题库的进度也删了")
    }
}
