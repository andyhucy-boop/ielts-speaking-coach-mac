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
    /// 命令行会再导一遍，用户会在收件箱里反复看到同一份已经处理完的复盘。
    ///
    /// 它**不是**「出现次数不会虚高」的那道保险——那道保险在 `ReviewArchiver.mergeIssues`
    /// 里，按 sessionID 去重，同一场归档多少次结果都一样。这里只是让收件箱干净。
    /// 两道防线不能互相顶替：标记这一步自己就会失败（改名撞名，见 `markImported`）。
    public static let importedSuffix = ".imported"

    /// 同名文件已存在时的行为：
    /// - 内容完全相同 → 直接复用，重试不会堆出一堆一样的文件
    /// - 内容不同 → 改用 `<id>-2.txt`、`<id>-3.txt`…，**绝不覆盖已经落盘的内容**
    /// - 名字被 `<id>.txt.imported` 占着 → 一样要换名，见下
    ///
    /// **交出去的路径，必须保证它的 `.imported` 孪生名也是空的。** `markImported`
    /// 只改名不删除，而复盘解析失败的那一场压根不会进 `state.sessions`，
    /// 下一次 `SessionID.next` 取「当天已有编号的最大值 +1」会算出同一个编号。
    /// 此时 `<id>.txt` 确实不在了，光看它在不在就会把这个用过的名字再发一次；
    /// 等归档做完、`markImported` 撞上已存在的 `<id>.txt.imported` 抛错，文件就
    /// 留在了待处理列表里——用户对着一份其实已经入库的复盘反复点「重新导入」，
    /// 每次都失败在同一个地方，而两份不同的原文挤在同一个编号下也再分不开。
    @discardableResult
    public static func write(rawText: String, sessionID: String,
                             directory: DataDirectory) throws -> URL {
        let safeID = try SessionID.validated(sessionID)
        try directory.createIfNeeded()

        let fileManager = FileManager.default
        var candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID).txt")
        var suffix = 2
        while true {
            let markedTwinExists = fileManager.fileExists(atPath: importedTwin(of: candidate).path)
            guard fileManager.fileExists(atPath: candidate.path) || markedTwinExists else { break }
            // 「内容相同就复用」这条捷径不能跨过已入库的那一份：它不在待处理列表里，
            // 把它的路径交回去，调用方会以为落盘成功了，用户却在收件箱里看不到这一份。
            if !markedTwinExists,
               let existing = try? String(contentsOf: candidate, encoding: .utf8),
               existing == rawText {
                return candidate
            }
            guard suffix <= 100 else {
                throw CoachError.stateUnreadable(
                    "同一个会话编号「\(safeID)」下已经占用了 100 个文件名"
                    + "（含已经标记为入库的），不再继续新建文件。"
                    + "下一步：到 \(directory.pendingReviewsDirectory.path) 清理掉不需要的文件，"
                    + "或在「复盘报告」页用「重新导入待处理的复盘」把它们处理掉。")
            }
            candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID)-\(suffix).txt")
            suffix += 1
        }

        try rawText.write(to: candidate, atomically: true, encoding: .utf8)
        return candidate
    }

    /// `<name>.txt` 对应的已入库标记文件 `<name>.txt.imported`。
    private static func importedTwin(of url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + importedSuffix)
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
    ///
    /// 失败了要说人话。`write` 已经保证自己发出去的名字连 `.imported` 孪生名一起空着，
    /// 但用户手工往 `pending-reviews/` 里放文件是允许的（`coach reimport` 就是这么用的），
    /// 所以撞名这件事没法从源头彻底杜绝。而这一步失败的后果比一般的改名失败重：
    /// 归档发生在标记之前，此刻档案已经写完，文件却还留在待处理列表里，
    /// 用户会以为整件事没成、照着「再点一次」去做，然后在同一个地方再失败一次。
    /// （档案本身不会因此失真——`ReviewArchiver.mergeIssues` 按 sessionID 去重，
    /// 同一场归多少次都一样——但重导解决不了这个问题，得先把名字腾出来。）
    /// 提示里必须把「别再导一次」和「去挪名字」都说出来
    /// （`coach reimport` 同一情形下的警告也是这么写的）。
    @discardableResult
    public static func markImported(_ entry: PendingReviewEntry) throws -> URL {
        let target = importedTwin(of: entry.url)
        do {
            try FileManager.default.moveItem(at: entry.url, to: target)
        } catch {
            throw CoachError.stateUnreadable(
                "「\(entry.fileName)」的内容已经归进档案，但要把它标记为已入库（改名成"
                + "「\(target.lastPathComponent)」）时失败了：\(error.localizedDescription) "
                + "最常见的原因是这个名字已经被占。"
                + "下一步：先别再点一次导入——归档已经做完了，再导一次只会卡在同一个名字上；"
                + "到 \(entry.url.deletingLastPathComponent().path) 把这个编号下不需要的那份"
                + "删掉或改个别的名字，再回来刷新列表。")
        }
        return target
    }

    public static func delete(_ entry: PendingReviewEntry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }
}
