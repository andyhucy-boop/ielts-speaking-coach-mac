import Foundation

/// `pending-reviews/` 里的一份待入库复盘原文。
public struct PendingReviewEntry: Equatable, Sendable, Identifiable {
    public let fileName: String
    /// 文件名去掉扩展名，即当初落盘时用的会话编号。
    public let sessionID: String
    public let modifiedAt: Date
    public let byteCount: Int
    public let url: URL

    public var id: String { fileName }

    public init(fileName: String, sessionID: String, modifiedAt: Date,
                byteCount: Int, url: URL) {
        self.fileName = fileName; self.sessionID = sessionID
        self.modifiedAt = modifiedAt; self.byteCount = byteCount; self.url = url
    }
}

/// 复盘原文的落盘与清点。
///
/// **`write` 必须在解析之前调用。** spec 第 5 节：「复盘先落盘再入库，中途崩溃或
/// 误关窗口都不丢数据」。反过来写的话，解析一抛错，用户练了一整场换来的原文就没了，
/// 只能从头再练一次。
public enum PendingReviewStore {
    /// 成功入库后给文件追加的后缀。**与 `coach reimport` 的约定必须一致**
    /// （见 `Sources/coach/ReimportCommand.swift`），否则界面里导入过的文件，
    /// 命令行会再导一遍，而 `IssueRecord.occurrences` 会跟着重复累加、悄悄失真。
    public static let importedSuffix = ".imported"

    /// 同名文件已存在时的行为：
    /// - 内容完全相同 → 直接复用，重试不会堆出一堆一样的文件
    /// - 内容不同 → 改用 `<id>-2.txt`、`<id>-3.txt`…，**绝不覆盖已经落盘的内容**
    @discardableResult
    public static func write(rawText: String, sessionID: String,
                             directory: DataDirectory) throws -> URL {
        let safeID = try SessionID.validated(sessionID)
        try directory.createIfNeeded()

        var candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID).txt")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if let existing = try? String(contentsOf: candidate, encoding: .utf8),
               existing == rawText {
                return candidate
            }
            guard suffix <= 100 else {
                throw CoachError.stateUnreadable(
                    "同一个会话编号「\(safeID)」下已经有 100 份内容不同的复盘原文，不再继续新建文件。"
                    + "下一步：到 \(directory.pendingReviewsDirectory.path) 清理掉不需要的文件，"
                    + "或在「复盘报告」页用「重新导入待处理的复盘」把它们处理掉。")
            }
            candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID)-\(suffix).txt")
            suffix += 1
        }

        try rawText.write(to: candidate, atomically: true, encoding: .utf8)
        return candidate
    }

    /// 列出还没入库的复盘原文，新的在前。
    ///
    /// 只认 `.txt`：打过 `.imported` 标记的文件扫不到，但原文一字不改地留在磁盘上。
    /// **目录不存在不是错误**（全新安装、从没练过），返回空数组即可——
    /// 界面该显示的是空状态，不是一句报错。
    public static func list(directory: DataDirectory) throws -> [PendingReviewEntry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.pendingReviewsDirectory.path) else {
            return []
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directory.pendingReviewsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])

        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { url in
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey])
                return PendingReviewEntry(
                    fileName: url.lastPathComponent,
                    sessionID: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    byteCount: values?.fileSize ?? 0,
                    url: url)
            }
            // 时间相同时按文件名倒序，保证顺序稳定——列表每次刷新都跳来跳去很难用
            .sorted { ($0.modifiedAt, $0.fileName) > ($1.modifiedAt, $1.fileName) }
    }

    public static func read(_ entry: PendingReviewEntry) throws -> String {
        do {
            return try String(contentsOf: entry.url, encoding: .utf8)
        } catch {
            throw CoachError.reviewNotFound(
                "读不到待处理的复盘原文「\(entry.fileName)」：\(error.localizedDescription) "
                + "下一步：确认这个文件还在数据目录的 pending-reviews 里；"
                + "若已经被手工删掉了，在列表里把这一条也删掉即可，其余记录不受影响。")
        }
    }

    /// 标记为已入库：**不删除，只改名**。
    @discardableResult
    public static func markImported(_ entry: PendingReviewEntry) throws -> URL {
        let target = entry.url.deletingLastPathComponent()
            .appendingPathComponent(entry.fileName + importedSuffix)
        try FileManager.default.moveItem(at: entry.url, to: target)
        return target
    }

    public static func delete(_ entry: PendingReviewEntry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }
}
