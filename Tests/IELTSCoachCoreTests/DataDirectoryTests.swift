import XCTest
@testable import IELTSCoachCore

final class DataDirectoryTests: XCTestCase {
    func testUsesApplicationSupportByDefault() {
        let directory = DataDirectory.resolve(environment: [:])
        XCTAssertTrue(directory.root.path.hasSuffix("Application Support/IELTS Speaking Coach"))
    }

    func testEnvironmentOverrideWins() {
        let directory = DataDirectory.resolve(
            environment: ["IELTS_SPEAKING_DATA_DIR": "/tmp/ielts-test"])
        XCTAssertEqual(directory.root.path, "/tmp/ielts-test")
    }

    func testWhitespaceOnlyEnvironmentOverrideFallsBackToApplicationSupport() {
        // trim + isEmpty 的回落删掉后没有测试失败：空白字符串会被当成一个合法的
        // 自定义目录（例如 URL(fileURLWithPath: "   ")），而不是回落到默认目录。
        let directory = DataDirectory.resolve(environment: ["IELTS_SPEAKING_DATA_DIR": "   "])
        XCTAssertTrue(directory.root.path.hasSuffix("Application Support/IELTS Speaking Coach"),
                      "空白环境变量没有回落到默认目录，实际：\(directory.root.path)")
    }

    func testDerivedPaths() {
        let directory = DataDirectory.resolve(
            environment: ["IELTS_SPEAKING_DATA_DIR": "/tmp/ielts-test"])
        XCTAssertEqual(directory.stateFile.lastPathComponent, "state.json")
        XCTAssertEqual(directory.reportsDirectory.lastPathComponent, "reports")
        XCTAssertEqual(directory.pendingReviewsDirectory.lastPathComponent, "pending-reviews")
        XCTAssertEqual(directory.recordingsDirectory.lastPathComponent, "recordings")
    }

    // MARK: - 相对路径的那道闸（复审第 4 条的判据）

    private var sandbox: DataDirectory {
        DataDirectory(root: URL(fileURLWithPath: "/tmp/ielts-guard"))
    }
    private var bothFolders: [String] {
        [DataDirectory.reportsFolder, DataDirectory.recordingsFolder]
    }

    /// 这些字符串在真实的 state.json 里出现过（或者用户手改时打得出来），
    /// 每一个拼到数据目录上都会指向不该被删的东西。**一个都不许放行。**
    func testEveryPathThatCouldEscapeTheDataDirectoryIsRefused() {
        let evil = [
            "recordings/../state.json",   // → 全部训练数据一次性消失
            "reports/../state.json",
            "recordings/..",
            "recordings/.",
            "recordings/",                // 空文件名
            "recordings",                 // 整个录音目录被递归删光
            "reports",
            "state.json",                 // 没有子目录前缀
            "/etc/passwd",                // 绝对路径
            "",
            "../state.json",
            "reports/../../outside.txt",
            "recordings/sub/dir.m4a",     // 多层：白名单只认一层
            "pending-reviews/x.json"      // 不在白名单里的子目录
        ]
        for path in evil {
            XCTAssertNil(sandbox.safeURL(forRelativePath: path, in: bothFolders),
                         "「\(path)」被放行了——按一下「删除这一场」就会删掉它指着的东西")
        }
    }

    /// 百分号编码那条路**不是**靠「拒绝」挡住的，是靠「拼完之后还在不在这个目录里」挡住的。
    ///
    /// `recordings/%2E%2E%2Fstate.json` 会被放行，但它落到的是 recordings 里一个
    /// **文件名里带百分号**的文件，不是上一层的 state.json——真正要命的是后者。
    /// 所以这里断言的是那条不变式本身：**放行的路径，父目录必须就是那个子目录。**
    /// 只断言「返回 nil」的话，哪天 URL 的编码行为一变，测试会红在一个不重要的地方，
    /// 而真正的洞（跑到目录外面去）反而没人守。
    func testAnythingThatIsLetThroughStaysInsideTheFolderItNamed() {
        for path in ["recordings/%2E%2E%2Fstate.json", "recordings/..no-such-file",
                     "recordings/a.m4a", "reports/a.json", "reports/....json"] {
            guard let url = sandbox.safeURL(forRelativePath: path, in: bothFolders) else { continue }
            let folder = path.hasPrefix("reports/") ? "reports" : "recordings"
            XCTAssertEqual(url.standardizedFileURL.deletingLastPathComponent().path,
                           "/tmp/ielts-guard/\(folder)",
                           "「\(path)」放行之后落到了 \(url.path)，已经在目录外面了")
        }
    }

    /// 反过来同样要成立：本工具自己写出来的路径一个都不许被误伤。
    /// 误伤的话每删一条记录都留下孤儿文件，而且用户会收到一句莫名其妙的拒绝。
    func testTheShapesThisAppActuallyWritesAreAccepted() throws {
        let report = try XCTUnwrap(
            sandbox.safeURL(forRelativePath: "reports/2026-08-06-001.json", in: bothFolders))
        XCTAssertEqual(report.path, "/tmp/ielts-guard/reports/2026-08-06-001.json")

        let recording = try XCTUnwrap(
            sandbox.safeURL(forRelativePath: "recordings/2026-08-06T10-45-30Z.m4a",
                            in: bothFolders))
        XCTAssertEqual(recording.path, "/tmp/ielts-guard/recordings/2026-08-06T10-45-30Z.m4a")
    }

    /// 白名单是**参数**，不是「反正都在数据目录里就行」：
    /// 只允许 recordings 时，reports 下的路径也得被拒。
    /// （`RecordingStore` 正是这么用它的——录音那条路不该能删复盘报告。）
    func testTheWhitelistIsActuallyHonoured() {
        XCTAssertNil(sandbox.safeURL(forRelativePath: "reports/a.json",
                                     in: [DataDirectory.recordingsFolder]))
        XCTAssertNotNil(sandbox.safeURL(forRelativePath: "recordings/a.m4a",
                                        in: [DataDirectory.recordingsFolder]))
    }

    func testCreateIfNeededMakesAllSubdirectories() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = DataDirectory.resolve(
            environment: ["IELTS_SPEAKING_DATA_DIR": root.path])
        try directory.createIfNeeded()

        for url in [directory.reportsDirectory, directory.pendingReviewsDirectory,
                    directory.recordingsDirectory] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "缺目录：\(url.path)")
        }
    }
}
