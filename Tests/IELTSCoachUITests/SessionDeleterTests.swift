import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 可编程的假文件删除器：能指定「哪些路径删起来会失败」。
final class FakeFileRemover: FileRemoving, @unchecked Sendable {
    var existing: Set<String> = []
    var failingPaths: Set<String> = []
    private(set) var removed: [String] = []

    func fileExists(at url: URL) -> Bool { existing.contains(url.lastPathComponent) }

    func remove(at url: URL) throws {
        if failingPaths.contains(url.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission)
        }
        removed.append(url.lastPathComponent)
        existing.remove(url.lastPathComponent)
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
                                     fileRemover: FakeFileRemover())
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
                                     fileRemover: FakeFileRemover())
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
                                     fileRemover: FakeFileRemover())
        XCTAssertNil(deleter.delete(session("a")))
        XCTAssertEqual(try store.load().currentSession?.id, "b")
    }

    /// **决策 4 的守卫。** 不删录音会留下永远不会被引用的孤儿文件把磁盘吃满，
    /// 而用户完全看不见。
    func testDeletingAlsoRemovesTheRecordingAndTheReport() throws {
        let remover = FakeFileRemover()
        remover.existing = ["2026-08-06-001.json", "a.m4a"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json",
                                        recordingPath: "recordings/a.m4a")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        _ = deleter.delete(session("2026-08-06-001",
                                   reportPath: "reports/2026-08-06-001.json",
                                   recordingPath: "recordings/a.m4a"))

        XCTAssertEqual(Set(remover.removed), ["2026-08-06-001.json", "a.m4a"])
    }

    /// Phase 5 还没交付时，绝大多数记录的 recordingPath 就是空的。
    /// 「有就删、没有就跳过」，不许硬依赖 Phase 5 的任何类型。
    func testAnEmptyRecordingPathIsJustSkipped() throws {
        let remover = FakeFileRemover()
        remover.existing = ["2026-08-06-001.json"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        let notice = deleter.delete(session("2026-08-06-001",
                                            reportPath: "reports/2026-08-06-001.json"))

        XCTAssertNil(notice)
        XCTAssertEqual(remover.removed, ["2026-08-06-001.json"])
    }

    func testAFileThatIsAlreadyGoneIsNotAnError() throws {
        let remover = FakeFileRemover()          // existing 是空的，什么都不在
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

    // MARK: - 失败要说出来

    /// 记录删掉了、文件删不掉（被占用、权限变了），必须如实告诉用户是哪个文件、在哪儿。
    /// 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
    func testAFileThatCouldNotBeDeletedIsReportedWithItsPath() throws {
        let remover = FakeFileRemover()
        remover.existing = ["a.m4a"]
        remover.failingPaths = ["a.m4a"]
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
                                     fileRemover: FakeFileRemover())
        let notice = deleter.delete(session("a"))
        XCTAssertNotNil(notice, "写不进去就必须说出来")
        XCTAssertTrue(try XCTUnwrap(notice).contains("下一步"))
    }
}
