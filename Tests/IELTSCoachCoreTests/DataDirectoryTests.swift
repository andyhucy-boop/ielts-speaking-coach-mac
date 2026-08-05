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
