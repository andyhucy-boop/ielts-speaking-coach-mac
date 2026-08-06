import XCTest
@testable import IELTSCoachCore

final class PendingReviewStoreTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-pending-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 落盘

    func testWritesTheRawTextAndCreatesTheDirectoryOnItsOwn() throws {
        // 刻意没有先 createIfNeeded：落盘这一步发生在最危险的时刻，
        // 不能因为目录还不存在就把用户的复盘丢了。
        let url = try PendingReviewStore.write(rawText: "复盘原文", sessionID: "2026-08-06-001",
                                               directory: directory)
        XCTAssertEqual(url.lastPathComponent, "2026-08-06-001.txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "复盘原文")
    }

    func testWritingTheSameTextTwiceReusesTheSameFile() throws {
        let first = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                 directory: directory)
        let second = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(first, second, "重试一次不该多出一个一模一样的文件")
        let files = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(files.count, 1)
    }

    func testDifferentTextNeverOverwritesWhatIsAlreadyThere() throws {
        let first = try PendingReviewStore.write(rawText: "第一次的复盘", sessionID: "s1",
                                                 directory: directory)
        let second = try PendingReviewStore.write(rawText: "第二次的复盘", sessionID: "s1",
                                                  directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "第一次的复盘",
                       "先落盘的那份一个字都不能被覆盖")
    }

    func testRejectsSessionIDsThatEscapeTheDataDirectory() {
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "x", sessionID: "../escaped",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
        let escaped = directory.root.deletingLastPathComponent().appending(path: "escaped.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testGivesUpWithAnActionableErrorInsteadOfLoopingForever() throws {
        // 同一个 sessionID 塞满 100 个不同内容之后必须报错退出，不能无限试下去
        //（禁止无限等待）。这条同时保证了实现里那个循环有出口。
        for index in 0..<100 {
            _ = try PendingReviewStore.write(rawText: "内容 \(index)", sessionID: "s1",
                                             directory: directory)
        }
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "第 101 份", sessionID: "s1",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
    }

    // MARK: - 清点

    func testListingAnAbsentDirectoryIsEmptyNotAnError() throws {
        // 全新安装、从没练过：目录还不存在。这不是错误，界面该显示空状态。
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty)
    }

    func testListsOnlyTxtFilesNewestFirst() throws {
        let old = try PendingReviewStore.write(rawText: "旧的", sessionID: "2026-08-05-001",
                                               directory: directory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: old.path)
        _ = try PendingReviewStore.write(rawText: "新的", sessionID: "2026-08-06-001",
                                         directory: directory)
        // 已经入库过的那份不该再出现在列表里
        let done = try PendingReviewStore.write(rawText: "已入库", sessionID: "2026-08-04-001",
                                                directory: directory)
        try FileManager.default.moveItem(
            at: done,
            to: done.deletingLastPathComponent()
                .appendingPathComponent(done.lastPathComponent + PendingReviewStore.importedSuffix))

        let entries = try PendingReviewStore.list(directory: directory)
        XCTAssertEqual(entries.map(\.sessionID), ["2026-08-06-001", "2026-08-05-001"])
        XCTAssertEqual(entries[0].byteCount, Data("新的".utf8).count)
    }

    func testTheSessionIDComesFromTheFileNameWithoutExtension() throws {
        _ = try PendingReviewStore.write(rawText: "x", sessionID: "sync-1785940167",
                                         directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        XCTAssertEqual(entry.sessionID, "sync-1785940167")
        XCTAssertEqual(entry.fileName, "sync-1785940167.txt")
    }

    func testReadingGivesBackExactlyWhatWasWritten() throws {
        let text = "<<<IELTS_REVIEW_JSON:x>>>{\"must_correct\":[]}<<<END_IELTS_REVIEW_JSON:x>>>"
        _ = try PendingReviewStore.write(rawText: text, sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        XCTAssertEqual(try PendingReviewStore.read(entry), text)
    }

    // MARK: - 标记与删除

    func testMarkingAsImportedKeepsTheFileButHidesItFromTheList() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        let marked = try PendingReviewStore.markImported(entry)

        XCTAssertEqual(marked.lastPathComponent, "s1.txt.imported")
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty,
                      "入库过的不该再出现在待处理列表里，否则会被反复导入")
        XCTAssertEqual(try String(contentsOf: marked, encoding: .utf8), "原文",
                       "原文一个字都不能改——用户可能想回头看当时 ChatGPT 写了什么")
    }

    func testDeletingReallyRemovesTheFile() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try PendingReviewStore.delete(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.url.path))
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty)
    }

    func testReadingAFileThatIsGoneSaysSoInsteadOfReturningEmpty() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.removeItem(at: entry.url)

        XCTAssertThrowsError(try PendingReviewStore.read(entry)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"),
                          "读不到就要说清楚，返回空字符串等于假装它是一份空复盘")
        }
    }
}
