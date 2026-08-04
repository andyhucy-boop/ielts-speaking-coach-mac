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
