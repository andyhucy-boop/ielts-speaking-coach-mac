import ChatGPTBridge
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 固定时钟。**写在类外面**：`PendingReviewViewModel.init` 收的是
/// `@Sendable () -> Date`（与 `PracticeRunner` / `TranscriptCollector` 一致，
/// 刻意保持，不为了迁就测试去改产品代码），而 `@Sendable` 闭包不继承 actor 隔离。
/// 放在 `@MainActor` 的测试类里（哪怕是 `static let`）会报
/// `main actor-isolated static property … can not be referenced from a Sendable closure`——
/// 实测过；写成实例属性则是另一条 `capture of 'self' with non-Sendable type …`。
/// `TranscriptCollectorTests` 踩过同一个坑，那边的解法是把时钟单拎出去，这里同理。
private let fixedNow = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!

/// 「重新导入待处理的复盘」的逻辑层。
///
/// 存在的理由（跨阶段决策 2）：复盘自动取回失败时，原文确实落在 `pending-reviews/` 里没丢，
/// 但把它补进库的唯一途径原本是终端里跑 `coach reimport`。成品标准第 2 条是
/// 「全程不需要打开终端」，而**出错恰恰是最需要它成立的时候**。
///
/// 这一层必须做对的两件事，也是下面两节分别守的：
///
/// 1. **导入成功后必须打 `.imported` 标记。** 不打的话，一份已经入库的复盘会一直赖在
///    收件箱里，用户分不清哪些还没处理、哪些早就处理完了。
///    （数字本身不靠这道标记兜底：`ReviewArchiver.mergeIssues` 按 sessionID 去重，
///    见本文件的 `testFollowingTheRetryInstructionDoesNotInflateOccurrences`。）
/// 2. **失败时一个字都不许动那个文件。** 它是用户练了半小时换来的东西。
@MainActor
final class PendingReviewViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        // 有一条测试会把数据目录改成只读来制造入库失败，删之前先还回来，
        // 否则临时目录会一直堆在磁盘上。
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: directory.root.path)
        try? FileManager.default.removeItem(at: directory.root)
    }

    private static let goodReview = #"""
    <<<IELTS_REVIEW_JSON:sync-1>>>
    {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
    "why_it_matters":"very 不能修饰动词"}],
    "vocabulary":[{"basic":"good","better":"decent","collocation":"a decent meal","priority":"high"}]}
    <<<END_IELTS_REVIEW_JSON:sync-1>>>
    """#

    private func model() -> PendingReviewViewModel {
        PendingReviewViewModel(directory: directory, store: store, timeZone: utc,
                               now: { fixedNow })
    }

    /// 可编程的剪贴板。**绝不碰真实剪贴板**：测试里读它会把用户当时复制的东西弄没。
    private final class StubPasteboard: PasteboardAccess, @unchecked Sendable {
        var contents: String?
        func readString() -> String? { contents }
        func clear() { contents = nil }
    }

    private func model(clipboard: String?) -> (PendingReviewViewModel, StubPasteboard) {
        let board = StubPasteboard()
        board.contents = clipboard
        return (PendingReviewViewModel(directory: directory, store: store, timeZone: utc,
                                       now: { fixedNow }, pasteboard: board), board)
    }

    // MARK: - 从剪贴板补录（2026-08-20：把一句一直说不到的「下一步」变成真的）

    /// 在这之前，工具会对用户说「回 ChatGPT 让它重新输出一次，复制之后……」，
    /// 而 App 里**没有任何地方**能把复制回来的那份收进这一场：
    /// 「重新导入待处理的复盘」读的是盘上那份**坏的**原文，再导一百遍还是同一份。
    func testAReviewPastedBackFromChatGPTGetsArchivedIntoThatSession() throws {
        try seedSession("2026-08-06-001")
        // 盘上先有一份坏的原文（自动取复盘失败时留下的那种）。
        _ = try PendingReviewStore.write(rawText: "这是坏的那一份，解析不了。",
                                         sessionID: "2026-08-06-001", directory: directory)

        let (model, _) = model(clipboard: Self.goodReview)
        model.importFromClipboard(into: "2026-08-06-001")

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.first?.reportPath, "reports/2026-08-06-001.json",
                       "补录的这一份没有挂到那一场上：\(model.notice ?? "（没有说明）")")
        XCTAssertEqual(saved.issues.count, 1, "错题没有归进档案")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001.json").path))
    }

    /// **坏的那一份原样留着。** 它是用户练了半小时换来的东西，
    /// 而且出问题时它是唯一能拿去对照的证据。
    func testPastingANewReviewNeverOverwritesTheOldRawText() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: "这是坏的那一份，解析不了。",
                                         sessionID: "2026-08-06-001", directory: directory)

        let (model, _) = model(clipboard: Self.goodReview)
        model.importFromClipboard(into: "2026-08-06-001")

        let names = try pendingFileNames()
        XCTAssertEqual(names.count, 2, "补录之后原文文件数不对：\(names)")
        XCTAssertTrue(names.contains { $0.hasPrefix("2026-08-06-001.txt") },
                      "坏的那一份被动过了：\(names)")
    }

    /// 剪贴板里多半是别的东西（刚复制的一个词、一条链接）。
    /// **每按一次就往数据目录里丢一个文件的话，那个目录很快就没法看了。**
    func testAShortClipboardIsRefusedBeforeAnythingIsWrittenToDisk() throws {
        try seedSession("2026-08-06-001")
        let (model, _) = model(clipboard: "borrow")
        model.importFromClipboard(into: "2026-08-06-001")

        XCTAssertEqual(try pendingFileNames(), [], "没看一眼就往盘上写了")
        let notice = try XCTUnwrap(model.notice)
        XCTAssertTrue(notice.contains("下一步"), notice)
        XCTAssertTrue(notice.contains("标记"), "没告诉他要连开头结尾那两行标记一起复制：\(notice)")
    }

    /// 剪贴板是空的时候同样得说话，而不是按下去什么都不发生。
    func testAnEmptyClipboardStillSaysSomething() throws {
        try seedSession("2026-08-06-001")
        let (model, _) = model(clipboard: nil)
        model.importFromClipboard(into: "2026-08-06-001")
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(try pendingFileNames(), [])
    }

    /// 判「这看着像不像一份复盘」用的是 `ClipboardFallback.minimumLength` 那**同一个**数
    /// （自动取复盘那条路上也是它）。各定一个数的话，同一段文字在一处被收下、
    /// 在另一处被拒绝，而用户没有任何办法知道为什么。这里从行为上钉那条线在哪儿。
    func testTheLengthCutoffIsTheSameOneUsedWhenCopyingAutomatically() throws {
        try seedSession("2026-08-06-001")

        let justUnder = String(repeating: "x", count: ClipboardFallback.minimumLength - 1)
        let (tooShort, _) = model(clipboard: justUnder)
        tooShort.importFromClipboard(into: "2026-08-06-001")
        XCTAssertEqual(try pendingFileNames(), [], "刚好差一个字符也该被挡在盘外")

        let justOver = String(repeating: "x", count: ClipboardFallback.minimumLength)
        let (longEnough, _) = model(clipboard: justOver)
        longEnough.importFromClipboard(into: "2026-08-06-001")
        XCTAssertEqual(try pendingFileNames().count, 1,
                       "到了长度线还被挡在外面——那条线两处对不上了")
    }

    private func seedSession(_ id: String, questionId: String = "q1") throws {
        try store.mutate { state in
            state.questions = [Question(id: questionId, part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?")]
            state.sessions = [PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                                              startedAt: "2026-08-06T10:00:00Z",
                                              endedAt: "2026-08-06T10:20:00Z", goal: "",
                                              transcript: [], reportPath: "", recordingPath: "")]
        }
    }

    private func pendingFileNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
            .sorted()
    }

    // MARK: - 列表

    func testAnEmptyInboxIsEmptyNotAnError() {
        let model = self.model()
        model.refresh()
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.notice)
    }

    func testARowShowsTimeQuestionAndSize() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()

        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(row.sessionID, "2026-08-06-001")
        XCTAssertEqual(row.questionText, "Do you live in a house or a flat?")
        XCTAssertFalse(row.timeText.isEmpty)
        XCTAssertTrue(row.sizeText.contains("KB") || row.sizeText.contains("字节"))
    }

    /// 那一场根本没能写进训练记录时，题目无从查起。**明说，不要留空。**
    func testAnUnknownQuestionIsSpelledOut() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "sync-1785940167",
                                         directory: directory)
        let model = self.model()
        model.refresh()

        let row = try XCTUnwrap(model.rows.first)
        XCTAssertTrue(row.questionText.contains("查不到"))
        XCTAssertFalse(row.questionText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testTheRawTextCanBeReadForInspection() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(model.rawText(of: row), Self.goodReview)
    }

    // MARK: - 重新导入

    func testReimportingArchivesTheReviewAndLinksTheReport() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let saved = try store.load()
        XCTAssertEqual(saved.issues.count, 1, "错题必须真的归进去")
        XCTAssertEqual(saved.vocabulary.count, 1)
        XCTAssertEqual(saved.sessions.first?.reportPath, "reports/2026-08-06-001.json")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001.json").path))
        XCTAssertTrue(model.isEmpty, "导入成功之后这一条就该从待处理列表里消失")

        // 这一句「下一步」是**能兑现的**：`reportPath` 回填上了，所以这一场真的会出现在
        // 复盘报告页左边那一列（`archivedSessions` 只收 `reportPath` 非空的会话）。
        // 与 `testReimportingASessionMissingFromTheRecordsSaysWhereTheReviewWent` 里那条
        // 「不许说这句话」配成一对：两个分支说同一句话的话，那边会红。
        XCTAssertFalse(ReviewReportViewModel.archivedSessions(in: saved).isEmpty)
        let notice = try XCTUnwrap(model.notice, "导入成功也要说话，不能让用户猜（铁律 7）")
        XCTAssertTrue(notice.contains("就能看到这一场了"),
                      "成功之后没告诉用户去哪儿看这份复盘：\(notice)")
    }

    /// **训练记录里查不到这一场时，不许承诺一件兑现不了的事**（铁律 6）。
    ///
    /// `sync-*` 这种编号是当年命令行时代的产物，它压根不在 `state.sessions` 里，
    /// `reportPath` 也就无处回填；而复盘报告页左边那一列只收 `reportPath` 非空的会话
    /// （`ReviewReportViewModel.archivedSessions`）。此时仍然说「到复盘列表里就能看到它了」，
    /// 用户去那一页永远看不到，只会以为是自己点错了——而且 `reports/<id>.json` 成了
    /// 没人引用的文件，他连这份复盘存在哪儿都不知道。
    ///
    /// 同一份数据在列表那一侧已经老老实实说了「查不到这份复盘属于哪一场练习」
    /// （`testAnUnknownQuestionIsSpelledOut`），成功文案不能转头当它查得到。
    func testReimportingASessionMissingFromTheRecordsSaysWhereTheReviewWent() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "sync-1785940167",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let saved = try store.load()
        XCTAssertEqual(saved.issues.count, 1, "查不到那一场，错题该归进去的还是要归进去")
        XCTAssertTrue(ReviewReportViewModel.archivedSessions(in: saved).isEmpty,
                      "这一场不在训练记录里，复盘报告页那一列不可能显示它——"
                          + "这正是文案不许承诺它的原因")

        let notice = try XCTUnwrap(model.notice)
        XCTAssertFalse(notice.contains("就能看到这一场"),
                       "文案把用户支到一个永远看不到这份复盘的页面去了：\(notice)")
        XCTAssertTrue(notice.contains("查不到"),
                      "没说清「为什么复盘列表里不会有它」：\(notice)")
        XCTAssertTrue(notice.contains("reports/sync-1785940167.json"),
                      "没告诉用户这份复盘到底存在哪儿，那个文件就成了没人知道的孤儿：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "没说下一步做什么：\(notice)")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "sync-1785940167.json").path),
                      "文案里报了这个路径，那儿就必须真的有东西（铁律 7）")
    }

    /// **同一场的第二份原文（`<id>-2.txt`）要并回那一场，不许造出一个不存在的会话编号。**
    ///
    /// 这条路走得到：`PracticeRunner` 重试取复盘、拿到的原文和上一次不一样时，
    /// `PendingReviewStore.write` 就会落成 `<id>-2.txt`（内容相同才复用同一个文件名）。
    ///
    /// 列表那一侧本来就是去掉 `-N` 后缀回查会话的（所以行上显示的题目是对的）。
    /// 归档这一侧要是直接拿文件名当编号，同一个 `PendingReviewRow` 上两句话就自相矛盾了：
    /// `sourceSessionIds` 里多出一个根本不存在的编号、`reportPath` 回填不上、
    /// `reports/<id>-2.json` 成了没人引用的孤儿文件，而成功文案还在说「就能看到这一场了」。
    func testASecondCopyOfTheSameSessionIsArchivedUnderThatSession() throws {
        try seedSession("2026-08-06-001")
        // 第一份和第二份内容不同，`write` 才会换名字（内容相同时它复用同一个文件名）。
        _ = try PendingReviewStore.write(rawText: "第一份原文（内容不一样，所以下一份会换名字）",
                                         sessionID: "2026-08-06-001", directory: directory)
        let second = try PendingReviewStore.write(rawText: Self.goodReview,
                                                  sessionID: "2026-08-06-001", directory: directory)
        XCTAssertEqual(second.lastPathComponent, "2026-08-06-001-2.txt",
                       "这条测试的前提没成立：第二份原文没有落成 `<id>-2.txt`")

        let model = self.model()
        model.refresh()
        let row = try XCTUnwrap(model.rows.first { $0.sessionID == "2026-08-06-001-2" })
        XCTAssertEqual(row.questionText, "Do you live in a house or a flat?",
                       "列表那一侧已经把它认成这一场了，归档那一侧必须跟着一致")
        model.reimport(row)

        let saved = try store.load()
        XCTAssertEqual(saved.issues.first?.sourceSessionIds, ["2026-08-06-001"],
                       "错题记在了一个不存在的会话编号名下")
        XCTAssertEqual(saved.sessions.first?.reportPath, "reports/2026-08-06-001.json",
                       "复盘没能挂回那一场，复盘报告页永远看不到它")
        XCTAssertFalse(ReviewReportViewModel.archivedSessions(in: saved).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001.json").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001-2.json").path),
                       "多写了一个没人引用的 reports/<id>-2.json")
    }

    /// 导进去的那一份必须从收件箱里消失，否则用户永远分不清哪些还没处理。
    /// 原文本身要留着（改名不删除）——他可能想回头看当时 ChatGPT 到底写了什么。
    func testAnImportedFileIsMarkedSoItCannotBeImportedTwice() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        XCTAssertEqual(try store.load().issues.first?.occurrences, 1)
        model.refresh()
        XCTAssertTrue(model.rows.isEmpty)

        XCTAssertEqual(try pendingFileNames(), ["2026-08-06-001.txt.imported"],
                       "原文要留着（用户可能想回头看），但不能再被扫到")
    }

    func testAReviewThatStillCannotBeParsedLeavesTheFileAlone() throws {
        _ = try PendingReviewStore.write(rawText: "这不是一份复盘", sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let notice = try XCTUnwrap(model.notice)
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertFalse(model.rows.isEmpty, "导不进去的那条要留在列表里，让用户能看原文、能删")
        XCTAssertEqual(try pendingFileNames(), ["s1.txt"], "解析失败时一个字都不许动那个文件")
    }

    /// **「点『补生成复盘报告』」那条老毛病的第三处。**
    ///
    /// `ReviewParser` 在 `IELTSCoachCore` 里，`coach` 命令行也在用它，它那句
    /// 「下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次」在终端那边是对的，
    /// 但**图形界面里没有这颗按钮**。`PracticeRunner`（`diagnosisOnly`）和
    /// `ReviewReportLoader` 都各自把它砍掉过，唯独这一页原样透传了
    /// `error.localizedDescription`——用户会连读到两句「下一步」，
    /// 第一句指着一颗全 App 都找不到的按钮，然后一直找。
    ///
    /// 这一条同时守两头：**幽灵按钮不许出现**，而**诊断不许一起砍掉**——
    /// 只剩一句「解析不了」的话，用户分不出是输出被截断了还是压根没按格式写。
    func testAParseFailureNeverSendsTheUserAfterAButtonThatDoesNotExist() throws {
        _ = try PendingReviewStore.write(rawText: "这不是一份复盘", sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))
        let notice = try XCTUnwrap(model.notice)

        let controls = try SourceGuard.literalControlTitles()
        let named = SourceGuard.clickTargets(in: notice)
        XCTAssertFalse(named.isEmpty,
                       "这句话里一处「点『…』」都没有，这条检查等于空转：\(notice)")
        for target in named where !controls.contains(target) {
            XCTFail("这句话让用户去点「\(target)」，而界面上没有这个控件（铁律 4）。"
                        + "界面上真有的是：\(controls.sorted().joined(separator: "、"))。"
                        + "下一步：把 `ReviewParser` 自带的「下一步」砍掉"
                        + "（`PracticeRunner.diagnosisOnly(_:)`），只留诊断，"
                        + "「下一步」由这一页自己写——这一页有的是「查看原文」。"
                        + "原话：\(notice)")
        }

        XCTAssertTrue(notice.contains("没有返回可识别的标准复盘JSON"),
                      "诊断被一起砍掉了。只说「解析不了」的话，用户分不出是 ChatGPT 的输出被截断了"
                          + "还是压根没按格式写，也就无从判断该重新输出还是自己把结尾补上：\(notice)")
    }

    /// **归档抛错时，那个文件同样一个字都不许动。**
    ///
    /// 计划的突变清单里第二行（把 `markImported` 挪到 `store.mutate` 之前）本来没有测试接得住——
    /// 两步都成功时谁先谁后看不出区别。这条把入库那一步弄失败（数据目录改成只读：
    /// `state.json` 读得到、写不进去），于是先后顺序变成可观测的：
    /// 先打标记的话，归档明明没成功，这份原文却已经从待处理列表里消失，用户再也点不到它，
    /// 而档案里什么都没有——练了半小时的东西就这么没了。
    func testAnArchiveFailureLeavesTheFileForAnotherTry() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        let row = try XCTUnwrap(model.rows.first)

        // 只读：`Data.write` 建不了 `.state.json.<uuid>.tmp`，而读 state.json 不受影响，
        // 所以失败点精确落在「入库」这一步，不会顺带让列表也读不出来。
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: directory.root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: directory.root.path)
        }

        model.reimport(row)

        let notice = try XCTUnwrap(model.notice, "入库失败必须说话，不许静默（铁律 7）")
        XCTAssertTrue(notice.contains("入库"), "这句话没说清失败在哪一步：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "这句话没说下一步做什么：\(notice)")
        XCTAssertEqual(try pendingFileNames(), ["2026-08-06-001.txt"],
                       "归档失败了却把原文标记成已入库，用户就再也点不到这一条了")
        XCTAssertEqual(try store.load().issues.count, 0, "入库失败了，档案里不该有东西")
    }

    /// **归档成功、只有「打标记」这一步失败**时，那句话绝对不许教用户再点一次导入。
    ///
    /// 这两种失败的「下一步」正好相反，混成一句话就会出人命：
    ///
    /// - 入库失败 → 档案纹丝不动，要再点一次「重新导入」；
    /// - `markImported` 失败 → **归档已经做完了**，再导一次什么也补不上，
    ///   只会在打标记那一步再失败一次；真正要做的是把撞上的那个文件名腾出来。
    ///
    /// `PendingReviewStore.markImported` 为此专门写了「先别再点一次导入」。
    /// 把它当成 `error.localizedDescription` 拼进一句「下一步：…再点一次「重新导入」」里，
    /// 用户读到的最后一句话，教他做的恰恰是前一句明令禁止的事——而且照做也修不好，
    /// 他会在原地打转，那份复盘永远从收件箱里下不去。
    func testAMarkFailureNeverTellsThemToImportAgain() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        // 手工把 `.imported` 那个名字占掉：`markImported` 只改名不删除，目标已存在就抛错。
        // 必须**在 write 之后**造，否则 `write` 会绕开撞名、直接落成 `<id>-2.txt`。
        // 用户手工往 pending-reviews 里放文件是允许的（`coach reimport` 就是这么用的），
        // 所以这种撞名没法从源头杜绝——`PendingReviewStoreTests` 里也是这么造的。
        try "占住这个名字".write(to: directory.pendingReviewsDirectory
            .appending(path: "2026-08-06-001.txt.imported"), atomically: true, encoding: .utf8)

        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        XCTAssertEqual(try store.load().issues.first?.occurrences, 1,
                       "归档这一步是成功的——这条测试的前提")

        let notice = try XCTUnwrap(model.notice, "打标记失败必须说话，不许静默（铁律 7）")
        XCTAssertTrue(notice.contains("先别再点一次导入"),
                      "这句话没把「别再导一次」说出来。用户会在同一个地方反复失败，"
                          + "而真正要做的（把撞上的文件名腾出来）没人告诉他：\(notice)")
        XCTAssertFalse(notice.contains("再点一次「重新导入」"),
                       "这句话末尾教用户去做前半句明令禁止的事——「出现次数」会当场失真：\(notice)")
        XCTAssertFalse(notice.contains("解析成功了，但入库时出错"),
                       "入库是成功的，失败的是打标记。说反了，用户会以为档案里什么都没有，"
                           + "于是照着去重导一次：\(notice)")
        XCTAssertEqual(try pendingFileNames(),
                       ["2026-08-06-001.txt", "2026-08-06-001.txt.imported"],
                       "改名失败了，两个文件应该原样都在")
    }

    /// **成功文案里那句「把 .imported 后缀去掉，它就会重新出现在这个列表里」，
    /// 照着做一遍必须是安全的。**
    ///
    /// 这条走的是「混合 skip」：must_correct 归进去了、vocabulary 因为形状不对一条没进，
    /// 于是文案会附上那句「等本工具认得这种字段名之后想重来的话……」。
    /// 用户照做时，已经归进档案的那条错题会被再归一次——`ReviewArchiver.mergeIssues`
    /// 从前每次命中都 `+= 1`，「这句话说错了几次」就当场虚高，而虚高比不显示更糟：
    /// 用户会以为老毛病越来越严重，其实他可能正在变好。
    ///
    /// 现在 `mergeIssues` 按 sessionID 去重（幂等），这句指示才兑现得了。
    /// 哪天幂等被改回去，这条会红——那句话届时就是在教用户毁掉自己的数据。
    func testFollowingTheRetryInstructionDoesNotInflateOccurrences() throws {
        // vocabulary 是个对象而不是数组（真机实测过的形状），所以它会进 skipped；
        // must_correct 是好的，照常归档——「混合 skip」的前提就在这里。
        let mixed = #"""
        <<<IELTS_REVIEW_JSON:x>>>
        {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
        "why_it_matters":"very 不能修饰动词"}],
        "vocabulary":{"useful_replacements":["decent"],"pronunciation":"n/a"}}
        <<<END_IELTS_REVIEW_JSON:x>>>
        """#
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: mixed, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        XCTAssertEqual(try store.load().issues.first?.occurrences, 1, "这条测试的前提：第一次归档成功")
        let firstNotice = try XCTUnwrap(model.notice)
        XCTAssertTrue(firstNotice.contains("把 .imported 后缀去掉"),
                      "这条测试要验的正是这句指示，它没出现就说明前提没成立：\(firstNotice)")

        // 照着那句话做：把 .imported 后缀去掉。
        let pendingDirectory = directory.pendingReviewsDirectory
        try FileManager.default.moveItem(
            at: pendingDirectory.appending(path: "2026-08-06-001.txt.imported"),
            to: pendingDirectory.appending(path: "2026-08-06-001.txt"))
        model.refresh()
        let reappeared = try XCTUnwrap(model.rows.first,
                                       "文案说它会重新出现在这个列表里，结果没有——这句话就是假的")
        model.reimport(reappeared)

        let saved = try store.load()
        XCTAssertEqual(saved.issues.count, 1, "重来一次多造了一条一模一样的错题记录")
        XCTAssertEqual(saved.issues.first?.occurrences, 1,
                       "照着成功文案里那句话做了一遍，「出现次数」就多了一次——"
                           + "用户会以为老毛病在变严重，而他其实可能正在变好")
        // **必须直接读盘上的原始数字。** `store.load()` 会经过
        // `IssueRecord.init(from:)` 的读时修复，虚高的数字在那一步就被算回来了——
        // 只查 `load()` 的话，归档那一层的幂等被改回去也照样绿（实测过）。
        // 两道防线要各自被独立地钉住。
        XCTAssertEqual(try occurrencesWrittenToDisk(), 1,
                       "落到 state.json 里的就是个虚高的数字，只是被读时修复盖住了")
    }

    /// 绕过 `StateStore.load()`（连同它的读时修复），直接看 state.json 里写的是几。
    private func occurrencesWrittenToDisk() throws -> Int {
        let data = try Data(contentsOf: directory.stateFile)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let issues = try XCTUnwrap(root["issues"] as? [[String: Any]])
        return try XCTUnwrap(issues.first?["occurrences"] as? Int)
    }

    /// 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
    /// **静默的 0 是本项目已知最危险的失败形态。**
    func testArchivingNothingIsReportedLoudly() throws {
        let wrongFieldNames = #"""
        <<<IELTS_REVIEW_JSON:x>>>
        {"must_correct":[{"issue":"very like","examples":["I very like it."],"fix":"really like"}]}
        <<<END_IELTS_REVIEW_JSON:x>>>
        """#
        _ = try PendingReviewStore.write(rawText: wrongFieldNames, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let notice = try XCTUnwrap(model.notice)
        XCTAssertTrue(notice.contains("must_correct"))
        XCTAssertTrue(notice.contains("一条都没"))
        XCTAssertTrue(notice.contains("下一步"))
    }

    // MARK: - 删除

    func testDeletingRemovesTheFileForGood() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.delete(try XCTUnwrap(model.rows.first))

        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(try pendingFileNames().isEmpty)
    }
}
