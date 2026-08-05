import Foundation

public struct DataDirectory: Equatable, Sendable {
    public static let folderName = "IELTS Speaking Coach"
    public static let environmentKey = "IELTS_SPEAKING_DATA_DIR"

    public let root: URL

    public init(root: URL) { self.root = root }

    public var stateFile: URL { root.appending(path: "state.json") }
    public var reportsDirectory: URL { root.appending(path: "reports") }
    public var pendingReviewsDirectory: URL { root.appending(path: "pending-reviews") }
    public var recordingsDirectory: URL { root.appending(path: "recordings") }

    /// App 与 MCP CLI 必须共用这一个解析函数，否则会写到两个目录去。
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DataDirectory {
        if let override = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return DataDirectory(root: URL(fileURLWithPath: override).standardizedFileURL)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DataDirectory(root: base.appending(path: folderName))
    }

    public func createIfNeeded() throws {
        for url in [root, reportsDirectory, pendingReviewsDirectory, recordingsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
