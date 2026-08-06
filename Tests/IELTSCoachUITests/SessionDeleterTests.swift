import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 可编程的假文件删除器：能指定「哪些路径删起来会失败」。
///
/// **两处刻意贴着 `SystemFileRemover` 的真实行为**，都是复审实测揪出来的空转
/// （改坏实现却一条测试都不红）：
///
/// 1. **按「相对数据目录的路径」记账，不是只看文件名。** 只比 `lastPathComponent`
///    的话，`SessionDeleter` 里的基准目录写错（比如删到 `/tmp` 底下去）测试照样全绿——
///    而真实后果是录音和复盘报告一个都没删掉、全成了孤儿文件，界面还显示删除成功。
///    落在数据目录之外的路径按「不存在」处理，并原样记下**绝对路径**，
///    断言红了一眼能看出跑偏到哪儿去了。
/// 2. **删一个本来就不在的文件要抛错。** 真的 `FileManager.removeItem` 删不存在的文件
///    会抛 `NSFileNoSuchFileError`。假件要是照单全收，实现里那句
///    `guard fileRemover.fileExists(at:)` 被谁删掉都不会有测试红——
///    而用户每删一条「复盘报告早被手工清掉」的记录，都会白挨一句「有 N 个文件没能删除」。
final class FakeFileRemover: FileRemoving, @unchecked Sendable {
    /// 数据目录。假件按「相对它的路径」记账，所以基准目录写错会被逮住。
    private let root: URL
    /// 相对 `root` 的路径，形如 `reports/2026-08-06-001.json`。
    var existing: Set<String> = []
    var failingPaths: Set<String> = []
    private(set) var removed: [String] = []

    init(root: URL) { self.root = root }

    func fileExists(at url: URL) -> Bool { existing.contains(key(for: url)) }

    func remove(at url: URL) throws {
        let path = key(for: url)
        // 顺序照着 FileManager：文件不在，先抛「没这个文件」，轮不到权限。
        guard existing.contains(path) else { throw CocoaError(.fileNoSuchFile) }
        guard !failingPaths.contains(path) else { throw CocoaError(.fileWriteNoPermission) }
        removed.append(path)
        existing.remove(path)
    }

    /// 数据目录里的记成相对路径；目录外的原样记绝对路径——那种路径必然不在
    /// `existing` 里，也就等同于「不存在」。
    private func key(for url: URL) -> String {
        let base = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base + "/") else { return full }
        return String(full.dropFirst(base.count + 1))
    }
}

@MainActor
final class SessionDeleterTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, reportPath: String = "",
                         recordingPath: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: reportPath,
                        recordingPath: recordingPath)
    }

    // MARK: - 确认文案

    func testTheConfirmationSpellsOutEveryFileItWillDelete() {
        let plan = SessionDeletion.plan(for: session("2026-08-06-001",
                                                     reportPath: "reports/2026-08-06-001.json",
                                                     recordingPath: "recordings/a.m4a"))
        XCTAssertEqual(plan.relativePaths,
                       ["reports/2026-08-06-001.json", "recordings/a.m4a"])
        XCTAssertTrue(plan.confirmationText.contains("录音"))
        XCTAssertTrue(plan.confirmationText.contains("复盘"))
        XCTAssertTrue(plan.confirmationText.contains("错题本"),
                      "必须说清什么不会跟着删，否则用户会以为全清了")
        // 铁律 6：这段文案是这个类型**唯一的交付物**，「下一步做什么」不能少。
        // 少了这句，用户面对一个不可撤销的销毁操作，不知道后悔了该点哪儿。
        XCTAssertTrue(plan.confirmationText.contains("下一步"),
                      "确认文案必须说清下一步怎么办（铁律 6）：\(plan.confirmationText)")
    }

    func testASessionWithoutARecordingDoesNotPretendToHaveOne() {
        let plan = SessionDeletion.plan(for: session("2026-08-06-001",
                                                     reportPath: "reports/2026-08-06-001.json"))
        XCTAssertEqual(plan.relativePaths, ["reports/2026-08-06-001.json"])
        XCTAssertFalse(plan.confirmationText.contains("录音"))
    }

    // MARK: - 真的删掉

    func testDeletingRemovesTheRecordFromState() throws {
        try store.mutate { $0.sessions = [self.session("a"), self.session("b")] }
        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover(root: directory.root))
        let notice = deleter.delete(session("a"))

        XCTAssertNil(notice, "一切顺利时不要弹提示")
        XCTAssertEqual(try store.load().sessions.map(\.id), ["b"])
    }

    /// 删掉的正好是「当前这一场」时，`currentSession` 必须跟着清掉。
    /// 留着的话，state 里会挂着一条指向已删记录的会话——今日训练页会照它渲染，
    /// 用户看到的是一场删不掉的练习。
    func testDeletingTheSessionInProgressAlsoClearsCurrentSession() throws {
        try store.mutate {
            $0.sessions = [self.session("a")]
            $0.currentSession = self.session("a")
        }
        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover(root: directory.root))
        XCTAssertNil(deleter.delete(session("a")))
        XCTAssertNil(try store.load().currentSession)
    }

    /// 删的不是当前这一场时，`currentSession` 一个字都不许动——
    /// 顺手清掉会让用户正在练的那一场凭空消失。
    func testDeletingAnotherRecordLeavesTheSessionInProgressAlone() throws {
        try store.mutate {
            $0.sessions = [self.session("a"), self.session("b")]
            $0.currentSession = self.session("b")
        }
        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover(root: directory.root))
        XCTAssertNil(deleter.delete(session("a")))
        XCTAssertEqual(try store.load().currentSession?.id, "b")
    }

    /// **决策 4 的守卫。** 不删录音会留下永远不会被引用的孤儿文件把磁盘吃满，
    /// 而用户完全看不见。
    ///
    /// 假件按「相对数据目录的路径」记账，所以这条同时守着**基准目录**：
    /// 实现要是拿 `DataDirectory.root` 以外的目录去拼路径，删掉的就是别处的文件
    /// （多半哪个都没删掉），这里立刻红。
    func testDeletingAlsoRemovesTheRecordingAndTheReport() throws {
        let remover = FakeFileRemover(root: directory.root)
        remover.existing = ["reports/2026-08-06-001.json", "recordings/a.m4a"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json",
                                        recordingPath: "recordings/a.m4a")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        _ = deleter.delete(session("2026-08-06-001",
                                   reportPath: "reports/2026-08-06-001.json",
                                   recordingPath: "recordings/a.m4a"))

        // 顺序也钉住：先复盘报告再录音，`SessionDeletionPlan.relativePaths` 的注释这么写的。
        XCTAssertEqual(remover.removed,
                       ["reports/2026-08-06-001.json", "recordings/a.m4a"])
    }

    /// Phase 5 还没交付时，绝大多数记录的 recordingPath 就是空的。
    /// 「有就删、没有就跳过」，不许硬依赖 Phase 5 的任何类型。
    func testAnEmptyRecordingPathIsJustSkipped() throws {
        let remover = FakeFileRemover(root: directory.root)
        remover.existing = ["reports/2026-08-06-001.json"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        let notice = deleter.delete(session("2026-08-06-001",
                                            reportPath: "reports/2026-08-06-001.json"))

        XCTAssertNil(notice)
        XCTAssertEqual(remover.removed, ["reports/2026-08-06-001.json"])
    }

    /// 复盘报告早被用户手工清掉、录音随目录拷贝时漏了——这两种情况天天有。
    /// 实现里那句 `guard fileRemover.fileExists(at:)` 就是为它们留的：
    /// 拿掉之后假件会照着 `FileManager` 抛「没这个文件」，这条立刻红。
    func testAFileThatIsAlreadyGoneIsNotAnError() throws {
        let remover = FakeFileRemover(root: directory.root)  // existing 是空的，什么都不在
        try store.mutate {
            $0.sessions = [self.session("a", reportPath: "reports/a.json",
                                        recordingPath: "recordings/a.m4a")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)

        XCTAssertNil(deleter.delete(session("a", reportPath: "reports/a.json",
                                            recordingPath: "recordings/a.m4a")),
                     "文件本来就不在，不该报错")
        XCTAssertEqual(try store.load().sessions.count, 0)
    }

    // MARK: - 假件自己的牙齿

    /// 上面那几条全靠假件「按相对数据目录的路径记账」「删不存在的文件要抛错」这两条。
    /// 哪天有人把它改回只比 `lastPathComponent`、或者对不存在的文件照单全收，
    /// 实现改坏了也不会有测试红——本项目已经这么栽过一次。这条把假件的行为钉死。
    func testTheFakeRemoverActsLikeFileManagerInsteadOfMatchingBareFileNames() throws {
        let remover = FakeFileRemover(root: directory.root)
        remover.existing = ["reports/a.json"]

        // 同名、但不在数据目录里：不算存在，也删不动。基准目录写错就是这个下场。
        let elsewhere = URL(fileURLWithPath: "/tmp/not-the-data-dir").appending(path: "reports/a.json")
        XCTAssertFalse(remover.fileExists(at: elsewhere), "只比文件名的话这里会误判成「存在」")
        XCTAssertThrowsError(try remover.remove(at: elsewhere))

        // 数据目录里的那一个：认得出、删得掉、按相对路径记账。
        let real = directory.root.appending(path: "reports/a.json")
        XCTAssertTrue(remover.fileExists(at: real))
        XCTAssertNoThrow(try remover.remove(at: real))
        XCTAssertEqual(remover.removed, ["reports/a.json"])

        // 再删一次——文件已经没了，照 `FileManager.removeItem` 抛「没这个文件」。
        XCTAssertThrowsError(try remover.remove(at: real)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile,
                           "假件必须模仿 FileManager，否则实现里那句 fileExists 守卫等于没测")
        }
    }

    // MARK: - 失败要说出来

    /// 记录删掉了、文件删不掉（被占用、权限变了），必须如实告诉用户是哪个文件、在哪儿。
    /// 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
    func testAFileThatCouldNotBeDeletedIsReportedWithItsPath() throws {
        let remover = FakeFileRemover(root: directory.root)
        remover.existing = ["recordings/a.m4a"]
        remover.failingPaths = ["recordings/a.m4a"]
        try store.mutate { $0.sessions = [self.session("a", recordingPath: "recordings/a.m4a")] }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)

        let notice = try XCTUnwrap(deleter.delete(session("a", recordingPath: "recordings/a.m4a")))
        XCTAssertTrue(notice.contains("recordings/a.m4a"))
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertEqual(try store.load().sessions.count, 0,
                       "文件删不掉不该拦住记录本身的删除，否则用户就卡住了")
    }

    func testAFailingStateWriteIsReportedInsteadOfSilentlyDoingNothing() throws {
        // 数据目录整个不可写时，删除必须报出来，不能装作删掉了。
        try FileManager.default.removeItem(at: directory.root)
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try store.mutate { $0.sessions = [self.session("a")] }
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: directory.root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: directory.root.path)
        }

        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover(root: directory.root))
        let notice = deleter.delete(session("a"))
        XCTAssertNotNil(notice, "写不进去就必须说出来")
        XCTAssertTrue(try XCTUnwrap(notice).contains("下一步"))
    }
}
