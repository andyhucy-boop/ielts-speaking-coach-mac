import XCTest
@testable import IELTSCoachCore

final class RecordingStoreTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: RecordingStore!

    /// 2026-08-06T10:45:30Z 的 Unix 时间戳。
    ///
    /// **计划里写的是 1_785_931_530，那个数是错的**——它对应的是 2026-08-05T12:05:30Z，
    /// 跟它自己注释里写的「= 2026-08-06T10:45:30Z」差了近一天。按错的数写，
    /// 一个完全正确的实现也会红。这里改的是测试的输入常量，不是断言：
    /// 期望的文件名一个字都没动，约束力不变。
    private let startInstant = Date(timeIntervalSince1970: 1_786_013_130)

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    /// 造一个占位录音文件。内容是什么无所谓，这一层只管路径与字节数。
    @discardableResult
    private func makeFile(_ name: String, bytes: Int) throws -> URL {
        let url = directory.recordingsDirectory.appending(path: name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: - 命名

    /// 按练习开始的时刻命名，UTC，文件名安全（不含冒号——冒号在 Finder 里会被显示成斜杠）。
    func testFileNameIsTheStartInstantInUTC() {
        let name = RecordingStore.fileName(startedAt: startInstant, taken: [])
        XCTAssertEqual(name, "2026-08-06T10-45-30Z.m4a")
        XCTAssertFalse(name.contains(":"), "冒号在 Finder 里会显示成斜杠，别用")
    }

    /// 同一秒里开了两场（重开、崩溃后立刻重来）不能互相覆盖——
    /// 覆盖掉的是上一场已经录好的内容。
    func testFileNameAvoidsOverwritingAnExistingRecording() {
        let taken: Set<String> = ["2026-08-06T10-45-30Z.m4a"]
        XCTAssertEqual(
            RecordingStore.fileName(startedAt: startInstant, taken: taken),
            "2026-08-06T10-45-30Z-2.m4a")

        let takenTwice = taken.union(["2026-08-06T10-45-30Z-2.m4a"])
        XCTAssertEqual(
            RecordingStore.fileName(startedAt: startInstant, taken: takenTwice),
            "2026-08-06T10-45-30Z-3.m4a")
    }

    // MARK: - 路径安全

    /// state.json 里的 recordingPath 是可以被手工改坏的。
    /// 一个 "recordings/../state.json" 就能让「删掉这条录音」删掉全部训练数据。
    func testRefusesPathsThatEscapeTheRecordingsDirectory() {
        for evil in ["recordings/../state.json", "recordings/..", "recordings/a/b.m4a"] {
            XCTAssertThrowsError(try store.url(forRelativePath: evil), "\(evil) 应当被拒绝") { error in
                XCTAssertTrue("\(error)".contains("下一步"), "拒绝也要告诉用户下一步做什么")
            }
        }
    }

    func testRefusesPathsOutsideTheRecordingsPrefix() {
        for evil in ["state.json", "/etc/passwd", "reports/x.json", ""] {
            XCTAssertThrowsError(try store.url(forRelativePath: evil), "\(evil) 应当被拒绝")
        }
    }

    func testAcceptsANormalRecordingPath() throws {
        let url = try store.url(forRelativePath: "recordings/2026-08-06T10-45-30Z.m4a")
        XCTAssertEqual(url.lastPathComponent, "2026-08-06T10-45-30Z.m4a")
        // 比的是 path 不是 URL 本身。**计划里写的是直接比两个 URL，那样任何正确实现都过不了**：
        // deletingLastPathComponent() 一定会带出一个结尾斜杠（file://…/recordings/），
        // 而 recordingsDirectory 没有（file://…/recordings），URL 的相等是按字符串算的，
        // standardizedFileURL 也不会把这个斜杠去掉。比 path 一样严——父目录只要不是
        // recordings（比如实现里多塞了一层子目录）照样红。
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       directory.recordingsDirectory.standardizedFileURL.path)
    }

    // MARK: - 删除

    func testDeleteRemovesOnlyTheTargetFile() throws {
        try makeFile("a.m4a", bytes: 10)
        try makeFile("b.m4a", bytes: 10)

        try store.delete(relativePath: "recordings/a.m4a")

        XCTAssertFalse(store.fileExists(relativePath: "recordings/a.m4a"))
        XCTAssertTrue(store.fileExists(relativePath: "recordings/b.m4a"))
    }

    /// 用户要的是「这条录音没了」。文件早就没了同样满足这个要求，
    /// 这时候报错只会让人以为没删掉，然后反复去点。
    func testDeleteIsFineWhenTheFileIsAlreadyGone() {
        XCTAssertNoThrow(try store.delete(relativePath: "recordings/never-existed.m4a"))
    }

    // MARK: - 占用

    func testUsageCountsOnlyRecordingsAndSumsTheirSize() throws {
        try makeFile("a.m4a", bytes: 10)
        try makeFile("b.m4a", bytes: 20)
        try makeFile("notes.txt", bytes: 5_000)   // 不是录音，不该数进去

        let usage = try store.usage()
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.bytes, 30)
    }

    func testUsageOnAnEmptyDirectory() throws {
        let usage = try store.usage()
        XCTAssertEqual(usage.count, 0)
        XCTAssertEqual(usage.bytes, 0)
    }

    /// 刻意不用 ByteCountFormatter：它的输出随系统语言和版本变化，
    /// 断言会在别人的机器上莫名其妙地红。
    func testHumanReadableSizesAreStable() {
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 512), "0.5 KB")
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 36_175_872), "34.5 MB")
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 2_147_483_648), "2.00 GB")
    }

    func testEmptyUsageTellsTheUserWhatWouldShowUpHere() {
        let text = RecordingUsage(count: 0, bytes: 0).summaryText
        XCTAssertTrue(text.contains("还没有录音"))
    }

    /// 占用不大时不啰嗦；大到该清理时必须给出怎么清。
    func testLargeUsageTellsTheUserHowToCleanUp() {
        let small = RecordingUsage(count: 3, bytes: 30_000_000).summaryText
        XCTAssertTrue(small.contains("3 个"))
        XCTAssertFalse(small.contains("下一步"), "占用不大时不该催人清理")

        let large = RecordingUsage(count: 900, bytes: RecordingUsage.noticeThreshold).summaryText
        XCTAssertTrue(large.contains("下一步"))
    }

    // MARK: - 孤儿

    /// 练习中途崩溃会在磁盘上留下没有任何训练记录指向的录音。
    /// **不主动删**——用户的录音只有用户能决定删不删，但必须让他知道它们占着地方。
    func testOrphansAreRecordingsNoSessionPointsAt() throws {
        try makeFile("kept.m4a", bytes: 10)
        try makeFile("orphan.m4a", bytes: 10)

        let orphans = try store.orphanFileNames(
            referencedPaths: ["recordings/kept.m4a", "", "recordings/already-deleted.m4a"])
        XCTAssertEqual(orphans, ["orphan.m4a"])
    }
}
