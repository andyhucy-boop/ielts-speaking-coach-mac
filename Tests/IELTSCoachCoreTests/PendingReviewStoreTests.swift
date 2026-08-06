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

    func testANameWhoseImportedTwinExistsIsNeverHandedOutAgain() throws {
        // 复盘解析失败的那一场压根不会进 state.sessions，下一次 SessionID.next 取
        // 「当天已有编号的最大值 +1」，算出来还是同一个编号。此时 `<id>.txt` 确实
        // 已经不在了（被改名成 `<id>.txt.imported`），只看 `<id>.txt` 在不在，
        // 就会把这个已经用过的名字再发一次。
        _ = try PendingReviewStore.write(rawText: "第一次的复盘", sessionID: "s1",
                                         directory: directory)
        let first = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        let marked = try PendingReviewStore.markImported(first)

        let second = try PendingReviewStore.write(rawText: "第二次的复盘", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt",
                       "s1.txt 这个名字已经被 s1.txt.imported 占掉了，不能再发一次")
        XCTAssertEqual(try String(contentsOf: marked, encoding: .utf8), "第一次的复盘",
                       "已经入库的那份原文一个字都不能被动")

        // write 交出来的路径，必须保证它的 .imported 孪生名也是空的。否则归档做完了、
        // markImported 却因为目标已存在而失败，文件留在待处理列表里，用户再点一次
        // 导入就再归档一次，IssueRecord.occurrences 会一次次累加。
        let secondEntry = try XCTUnwrap(
            try PendingReviewStore.list(directory: directory)
                .first { $0.fileName == second.lastPathComponent })
        XCTAssertNoThrow(try PendingReviewStore.markImported(secondEntry),
                         "落盘时发的名字必须是连 .imported 孪生名一起空着的")
    }

    func testTextIdenticalToAnAlreadyImportedFileStillGetsItsOwnPendingFile() throws {
        // 「内容相同就复用」这条捷径不能跨过 .imported：那份已经入库，不在待处理列表里，
        // 把它的路径交回去，调用方会以为自己落盘成功了，用户却在收件箱里看不到这一份。
        _ = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                         directory: directory)
        let first = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        _ = try PendingReviewStore.markImported(first)

        let second = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt")
        XCTAssertEqual(try PendingReviewStore.list(directory: directory).map(\.fileName),
                       ["s1-2.txt"], "新落盘的这一份必须能在待处理列表里看见")
    }

    func testAPendingFileIsNotReusedWhenItsImportedTwinIsAlreadyThere() throws {
        // 磁盘上同时躺着 s1.txt 和 s1.txt.imported——用户手工往 pending-reviews 里
        // 放过文件，或者旧版本留下的。内容一模一样也不能把 s1.txt 交回去：
        // 它的 .imported 名字已经被占，归档做完后 markImported 会失败。
        _ = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                         directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.copyItem(
            at: entry.url,
            to: entry.url.deletingLastPathComponent()
                .appendingPathComponent(entry.fileName + PendingReviewStore.importedSuffix))

        let again = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                 directory: directory)
        XCTAssertEqual(again.lastPathComponent, "s1-2.txt")
        let againEntry = try XCTUnwrap(
            try PendingReviewStore.list(directory: directory)
                .first { $0.fileName == again.lastPathComponent })
        XCTAssertNoThrow(try PendingReviewStore.markImported(againEntry))
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

    func testMarkingImportedOntoAnOccupiedNameExplainsItselfInChinese() throws {
        // 手工往 pending-reviews 里放文件是允许的（`coach reimport` 就是这么用的），
        // 所以「`<id>.txt` 和 `<id>.txt.imported` 同时存在」没法从源头彻底杜绝。
        // 撞上了要说人话：归档发生在标记之前，此刻档案已经写完了，
        // 用户再点一次导入就再归档一次，IssueRecord.occurrences 会重复累加。
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.copyItem(
            at: entry.url,
            to: entry.url.deletingLastPathComponent()
                .appendingPathComponent(entry.fileName + PendingReviewStore.importedSuffix))

        XCTAssertThrowsError(try PendingReviewStore.markImported(entry)) { error in
            XCTAssertTrue(error is CoachError,
                          "不能把 Foundation 的英文原始错误直接摆到界面上：\(error)")
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("下一步"), "要说清下一步做什么：\(message)")
            XCTAssertTrue(message.contains("s1.txt"), "要说清是哪个文件：\(message)")
            XCTAssertTrue(message.contains("导入"), "要提醒别再导一次，否则出现次数会重复累加：\(message)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.url.path),
                      "标记失败也不能把原文弄丢")
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
