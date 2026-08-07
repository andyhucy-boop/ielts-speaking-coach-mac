import XCTest
@testable import IELTSCoachCore

final class DataUsageTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "usage-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testEmptyDirectoryReportsZeroWithoutBlowingUp() {
        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertEqual(report.fileCount, 0)
    }

    func testMissingDirectoryReportsZeroInsteadOfFailing() {
        // 「看一眼占用」不该因为目录还没建就让整个设置页打不开。
        //
        // 注意这条**走不到** `walk` 里那个 `guard let walker ... else` 分支：实测
        // （macOS 26.5.2）`FileManager.enumerator(at:)` 对不存在的目录也会返回一个非 nil 的
        // enumerator，只是一个都不吐。nil 分支由下面那条注入假 FileManager 的测试覆盖。
        let nowhere = DataDirectory(root: FileManager.default.temporaryDirectory
            .appending(path: "does-not-exist-\(UUID().uuidString)"))
        XCTAssertEqual(DataUsage.measure(directory: nowhere).totalBytes, 0)
    }

    /// `FileManager.enumerator(at:)` 的返回类型是 Optional，而真实 FileManager 在目录不存在时
    /// 给的是空 enumerator 而不是 nil——也就是说 nil 分支只有注入假实现才走得到。
    /// 不覆盖它的话，谁把那句 `else { return (0, 0) }` 改成 `!`，设置页就会在这里崩，
    /// 而整套测试一条都不会红。
    ///
    /// 顺带钉住 `fileManager:` 这个注入口子真的被用上了：如果 `measure` 偷偷用 `.default`，
    /// 下面写进磁盘的那两个文件就会被数出来，断言立刻红。
    func testANilEnumeratorCountsAsZeroInsteadOfCrashing() throws {
        try write(200, to: directory.reportsDirectory.appending(path: "s1.json"))
        try write(400, to: directory.recordingsDirectory.appending(path: "s1.m4a"))

        let report = DataUsage.measure(directory: directory,
                                       fileManager: NilEnumeratorFileManager())
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertEqual(report.fileCount, 0)
        XCTAssertEqual(report.reportBytes, 0)
        XCTAssertEqual(report.recordingBytes, 0)
        XCTAssertEqual(report.pendingReviewBytes, 0)
    }

    func testEachBucketIsCountedSeparatelyAndSumsToTheTotal() throws {
        try write(100, to: directory.stateFile)
        try write(200, to: directory.reportsDirectory.appending(path: "s1.json"))
        try write(400, to: directory.recordingsDirectory.appending(path: "s1.m4a"))
        try write(800, to: directory.pendingReviewsDirectory.appending(path: "p1.txt"))

        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.stateBytes, 100)
        XCTAssertEqual(report.reportBytes, 200)
        XCTAssertEqual(report.recordingBytes, 400)
        XCTAssertEqual(report.pendingReviewBytes, 800)
        XCTAssertEqual(report.totalBytes, 1_500)
        XCTAssertEqual(report.fileCount, 4)
    }

    func testNestedFilesAreCountedToo() throws {
        // reports/ 下将来可能按月分子目录。少算的话，用户看到的占用会比实际小，
        // 而他正是拿这个数字判断「要不要清一清」。
        try write(64, to: directory.reportsDirectory.appending(path: "2026-08/s1.json"))
        XCTAssertEqual(DataUsage.measure(directory: directory).reportBytes, 64)
    }

    func testFilesOutsideTheKnownBucketsStillCountTowardTheTotal() throws {
        // 总量必须是「这个文件夹占了多少地」，不是「我认识的那几类占了多少」。
        // 否则用户看到 2 MB、Finder 显示 900 MB，他会觉得这个数字在骗他。
        try write(4_096, to: directory.root.appending(path: "something-new.bin"))
        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.totalBytes, 4_096)
        XCTAssertEqual(report.reportBytes, 0)
        XCTAssertEqual(report.fileCount, 1)
    }

    /// 这是全套里唯一一条 `measure` → `summaryText` 的端到端检查，所以断言必须钉到具体数字上：
    /// 只查「有没有出现 KB／MB／字节」的话，空状态串「还没有任何数据（0 字节）」里的「字节」
    /// 就能让它恒绿——`measure` 整个坏掉也照样通过。
    func testSummaryTextIsHumanReadableAndNeverEmpty() throws {
        try write(2_048, to: directory.recordingsDirectory.appending(path: "s1.m4a"))
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("共 \(RecordingUsage.humanReadable(bytes: 2_048))"),
                      "总量要写成人看得懂的单位：\(text)")
        XCTAssertTrue(text.contains("录音 \(RecordingUsage.humanReadable(bytes: 2_048))"),
                      "写进 recordings/ 的那 2048 字节要落在「录音」这一栏里：\(text)")
        XCTAssertFalse(text.contains("2048"), "别把原始字节数直接甩给用户：\(text)")
    }

    func testSummaryTextSaysZeroInsteadOfGoingBlank() {
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty, "空目录也要说一句话，空白会让人以为读失败了")
        XCTAssertTrue(text.contains("0 字节"), "得说清楚现在是 0，别让人猜：\(text)")
        // 铁律 6：空状态也要给下一步。这句话会显示在设置的「数据与隐私」和问题反馈的诊断信息里，
        // 只说「还没有任何数据」等于让用户对着一个死胡同发呆。
        XCTAssertTrue(text.contains("下一步"), "空状态要告诉用户怎么让这里长出数据：\(text)")
    }

    func testTheSameFormatterAsRecordingUsage() {
        // 两份格式化函数会让同一个文件夹在设置页显示 1.2 GB、
        // 在诊断信息里显示 1.15 GB，而用户会以为其中一个是 bug。
        XCTAssertTrue(DataUsageReport(totalBytes: 2_048, stateBytes: 0, reportBytes: 0,
                                      recordingBytes: 0, pendingReviewBytes: 0, fileCount: 1)
            .summaryText.contains(RecordingUsage.humanReadable(bytes: 2_048)))
    }
}

/// 只做一件事：把 `enumerator(at:)` 变成 nil。
///
/// 实测（macOS 26.5.2）真实 FileManager 从不返回 nil——不存在的目录、普通文件、
/// 甚至 `https://` URL，给的都是一个非 nil 的空 enumerator。所以那条兜底分支只能用假实现测。
///
/// **为什么重写的是 `__enumerator` 而不是 `enumerator`：** Swift 的 Foundation overlay 把
/// `enumerator(at:includingPropertiesForKeys:options:errorHandler:)` 声明成扩展里的 `@nonobjc`
/// 方法，编译器直接拒绝重写（`overriding non-open instance method outside of its defining
/// module`）。它内部转发给 `open func __enumerator(...)`，重写这一个才拦得住。
/// 万一将来 overlay 改了名字，这里会是编译错误——响的，不会变成一条偷偷失效的测试。
private final class NilEnumeratorFileManager: FileManager {
    override func __enumerator(at url: URL,
                               includingPropertiesForKeys keys: [URLResourceKey]?,
                               options mask: FileManager.DirectoryEnumerationOptions,
                               errorHandler handler: ((URL, any Error) -> Bool)?)
        -> FileManager.DirectoryEnumerator? { nil }
}
