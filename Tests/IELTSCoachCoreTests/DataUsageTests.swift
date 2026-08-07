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
        let nowhere = DataDirectory(root: FileManager.default.temporaryDirectory
            .appending(path: "does-not-exist-\(UUID().uuidString)"))
        XCTAssertEqual(DataUsage.measure(directory: nowhere).totalBytes, 0)
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

    func testSummaryTextIsHumanReadableAndNeverEmpty() throws {
        try write(2_048, to: directory.recordingsDirectory.appending(path: "s1.m4a"))
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("KB") || text.contains("MB") || text.contains("字节"),
                      "占用要写成人看得懂的单位：\(text)")
        XCTAssertFalse(text.contains("2048"), "别把原始字节数直接甩给用户：\(text)")
    }

    func testSummaryTextSaysZeroInsteadOfGoingBlank() {
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty, "空目录也要说一句话，空白会让人以为读失败了")
    }

    func testTheSameFormatterAsRecordingUsage() {
        // 两份格式化函数会让同一个文件夹在设置页显示 1.2 GB、
        // 在诊断信息里显示 1.15 GB，而用户会以为其中一个是 bug。
        XCTAssertTrue(DataUsageReport(totalBytes: 2_048, stateBytes: 0, reportBytes: 0,
                                      recordingBytes: 0, pendingReviewBytes: 0, fileCount: 1)
            .summaryText.contains(RecordingUsage.humanReadable(bytes: 2_048)))
    }
}
