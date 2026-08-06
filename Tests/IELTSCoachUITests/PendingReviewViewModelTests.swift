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
/// 1. **导入成功后必须打 `.imported` 标记。** `ReviewArchiver` 对「同一 session 重复归档」
///    只在 `sourceSessionIds` 上去重，`IssueRecord.occurrences` 会跟着重复调用继续累加。
///    不打标记的话，用户手一抖点两次，「这句话说错了几次」就悄悄失真了。
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
    }

    /// **本任务最重要的一条。** 不打 .imported 标记的话，用户手一抖点两次，
    /// `IssueRecord.occurrences` 就悄悄多加了一次，「这句话说错了几次」永久失真。
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
