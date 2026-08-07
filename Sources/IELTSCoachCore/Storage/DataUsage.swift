import Foundation

/// 数据目录占了多少地，以及是被什么占的。
public struct DataUsageReport: Equatable, Sendable {
    /// 整个数据目录的大小。**不是几个已知桶的和**——
    /// 将来多出来的任何东西都要算进去，否则用户看到 2 MB、
    /// Finder 显示 900 MB，他会觉得这个数字在骗他。
    public let totalBytes: Int64
    public let stateBytes: Int64
    public let reportBytes: Int64
    public let recordingBytes: Int64
    public let pendingReviewBytes: Int64
    public let fileCount: Int

    public init(totalBytes: Int64, stateBytes: Int64, reportBytes: Int64,
                recordingBytes: Int64, pendingReviewBytes: Int64, fileCount: Int) {
        self.totalBytes = totalBytes
        self.stateBytes = stateBytes
        self.reportBytes = reportBytes
        self.recordingBytes = recordingBytes
        self.pendingReviewBytes = pendingReviewBytes
        self.fileCount = fileCount
    }

    /// 复用 Phase 5 的格式化，不另写一份 —— 两份会给出两个不同的数字。
    public var summaryText: String {
        guard fileCount > 0 else { return "还没有任何数据（0 字节）。" }
        return "共 \(RecordingUsage.humanReadable(bytes: totalBytes))、\(fileCount) 个文件"
            + "（录音 \(RecordingUsage.humanReadable(bytes: recordingBytes))、"
            + "复盘 \(RecordingUsage.humanReadable(bytes: reportBytes))）。"
    }
}

/// 量一下数据目录。
///
/// **刻意不 throws。** 这是给「看一眼占用」用的：目录还没建、某个文件读不到，
/// 都只意味着那一块算 0，不该让整个设置页打不开。
/// 真正读不到训练数据的错误由 `StateStore` 报，那才是要拦的。
public enum DataUsage {
    public static func measure(directory: DataDirectory,
                               fileManager: FileManager = .default) -> DataUsageReport {
        // 总量量的是**整个数据目录**，不是几个已知桶的和：
        // 将来多出来的任何东西都要算进去，否则用户看到 2 MB、Finder 显示 900 MB。
        let whole = walk(directory.root, fileManager: fileManager)
        return DataUsageReport(
            totalBytes: whole.bytes,
            stateBytes: regularFileSize(of: directory.stateFile) ?? 0,
            reportBytes: walk(directory.reportsDirectory, fileManager: fileManager).bytes,
            recordingBytes: walk(directory.recordingsDirectory, fileManager: fileManager).bytes,
            pendingReviewBytes: walk(directory.pendingReviewsDirectory,
                                     fileManager: fileManager).bytes,
            fileCount: whole.count)
    }

    /// 每个桶各量各的目录，**不拿路径字符串比前缀**。
    ///
    /// 实测（macOS 26.5.2）：`FileManager.enumerator(at:)` 吐出来的 URL 是解析过符号链接的，
    /// `/var/folders/…/x/reports/a.json` 会变成 `/private/var/folders/…/x/reports/a.json`，
    /// 而 `DataDirectory` 手里的路径不会（`URL.resolvingSymlinksInPath()` 对 `/var` 这类
    /// 系统 firmlink 也不改写）。用 `hasPrefix` 比路径的话，凡是数据目录落在符号链接下面
    /// （临时目录、`IELTS_SPEAKING_DATA_DIR` 指到 `/tmp/…`）四个桶就全是 0，
    /// 总量却是对的——用户会看到「共 900 MB，其中录音 0、复盘 0」。
    private static func walk(_ url: URL, fileManager: FileManager) -> (bytes: Int64, count: Int) {
        guard let walker = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return (0, 0) }

        var bytes: Int64 = 0
        var count = 0
        for case let child as URL in walker {
            guard let size = regularFileSize(of: child) else { continue }
            bytes += size
            count += 1
        }
        return (bytes, count)
    }

    /// 不是普通文件、或者读不到属性，都算 `nil`（既不计数也不计字节）。
    private static func regularFileSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize else { return nil }
        return Int64(size)
    }
}
