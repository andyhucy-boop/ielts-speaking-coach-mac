import Foundation

public struct DataDirectory: Equatable, Sendable {
    public static let folderName = "IELTS Speaking Coach"
    public static let environmentKey = "IELTS_SPEAKING_DATA_DIR"

    public let root: URL

    public init(root: URL) { self.root = root }

    /// state.json 里的相对路径只可能落在这两个子目录里。
    /// 拿字符串常量而不是各处手写，是因为**这两个名字同时是路径校验的白名单**
    /// （见 `safeURL(forRelativePath:in:)`），写错一处就等于开了一个洞。
    public static let reportsFolder = "reports"
    public static let recordingsFolder = "recordings"

    public var stateFile: URL { root.appending(path: "state.json") }
    public var reportsDirectory: URL { root.appending(path: Self.reportsFolder) }
    public var pendingReviewsDirectory: URL { root.appending(path: "pending-reviews") }
    public var recordingsDirectory: URL { root.appending(path: Self.recordingsFolder) }

    /// 把 state.json 里存的相对路径变成数据目录里的真实 URL。
    /// **只认「<允许的子目录>/<纯文件名>」这一种形状**，其余一律返回 nil。
    ///
    /// **不挡的代价（复审第 4 条，用真实文件系统实测过）：** `reportPath` 与
    /// `recordingPath` 都是可以被手工改坏的字符串，而本工具自己的错误提示会引导用户
    /// 去手改 state.json。改坏之后按一下「删除这一场」：
    ///
    /// - 写成 `recordings/../state.json` → **全部练习记录、错题本、词汇本、复训目标、
    ///   题库、设置一次性消失**；
    /// - 写成 `recordings` → 整个录音目录被递归删光；
    /// - 带 `..` → 删到数据目录**外面**去。
    ///
    /// 而且全程没有声音：删除是「成功」的，界面照常显示删掉了这一场。
    ///
    /// 三道闸缺一不可：
    /// 1. 必须带白名单里的子目录前缀（挡住 `state.json`、`/etc/passwd` 这种）；
    /// 2. 剩下那一截必须是纯文件名（挡住 `../`、多层子目录、空名字）；
    /// 3. 拼完之后**再核一次**父目录就是那个子目录本身——URL 会把百分号编码解回来，
    ///    只靠前两道有可能被 `%2F` 之类绕过去。
    public func safeURL(forRelativePath path: String, in subdirectories: [String]) -> URL? {
        for folder in subdirectories where path.hasPrefix(folder + "/") {
            let name = String(path.dropFirst(folder.count + 1))
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
            let parent = root.appending(path: folder)
            let candidate = parent.appending(path: name)
            guard candidate.standardizedFileURL.deletingLastPathComponent().path
                    == parent.standardizedFileURL.path else { return nil }
            return candidate
        }
        return nil
    }

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
