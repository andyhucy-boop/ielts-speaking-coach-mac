import Foundation

/// 录音目录的占用情况。
public struct RecordingUsage: Equatable, Sendable {
    public let count: Int
    public let bytes: Int64

    public init(count: Int, bytes: Int64) { self.count = count; self.bytes = bytes }

    /// 超过这个值就在提示里追加「怎么清理」。
    /// 1 GB 按 64 kbps 单声道算大约是 37 小时的练习，正常用一年也到不了；
    /// 到了就说明该清了。
    public static let noticeThreshold: Int64 = 1_073_741_824

    /// 刻意不用 ByteCountFormatter：它的输出随系统语言与版本变化，
    /// 断言会在别人的机器上莫名其妙地红。自己算，结果确定。
    public static func humanReadable(bytes: Int64) -> String {
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024
        let value = Double(bytes)
        if value < mb { return String(format: "%.1f KB", value / kb) }
        if value < gb { return String(format: "%.1f MB", value / mb) }
        return String(format: "%.2f GB", value / gb)
    }

    public var summaryText: String {
        guard count > 0 else {
            return "还没有录音。开启「保存我的回答录音」之后，你练习时说的话会存在这里。"
        }
        var text = "录音 \(count) 个，共占用 \(Self.humanReadable(bytes: bytes))。"
        if bytes >= Self.noticeThreshold {
            text += "下一步：到「训练记录」页把不再需要的录音逐条删掉。"
        }
        return text
    }
}

public enum RecordingStoreError: Error, Equatable, LocalizedError {
    case unsafePath(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let m), .deleteFailed(let m): return m
        }
    }
}

/// `recordings/` 目录的全部操作：命名、列举、占用、删除、孤儿检测。
/// 只依赖 Foundation（FileManager 属于 Foundation），因此留在 Core 里。
public struct RecordingStore: Sendable {
    public static let fileExtension = "m4a"
    public static let relativePrefix = DataDirectory.recordingsFolder + "/"

    public let directory: DataDirectory

    public init(directory: DataDirectory) { self.directory = directory }

    /// 用「练习开始的时刻」命名，不用 PracticeSession.id。
    ///
    /// 会话 id 是练完归档时才分配的，而录音在那之前十几分钟就已经在写了。
    /// 若坚持用会话 id 命名，录音就得先写成临时名、事后改名，而「改名那一步失败」
    /// 会让一整场练习的录音凭空消失——正是成品标准第 7 条最不能接受的形态。
    /// 按开始时刻命名，文件从第一秒起就在它最终该在的位置上。
    public static func fileName(startedAt: Date, taken: Set<String>) -> String {
        let formatter = DateFormatter()
        // 三行都不能省：locale 不定死会在中文/佛历等区域设置下出别的年份，
        // timeZone 不定死会让同一场练习在不同机器上叫不同名字。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"

        let stamp = formatter.string(from: startedAt)
        var candidate = "\(stamp).\(fileExtension)"
        var suffix = 2
        // 同一秒里重开一场时不能覆盖上一场——覆盖掉的是已经录好的内容。
        while taken.contains(candidate) {
            candidate = "\(stamp)-\(suffix).\(fileExtension)"
            suffix += 1
        }
        return candidate
    }

    public func relativePath(fileName: String) -> String { Self.relativePrefix + fileName }

    /// 把 state.json 里存的相对路径变成真实 URL，并挡掉危险路径。
    ///
    /// **不挡的代价：** recordingPath 是可以被手工改坏的字符串，
    /// 一个 "recordings/../state.json" 就能让「删掉这条录音」删掉用户的全部训练数据。
    ///
    /// 真正的判据在 `DataDirectory.safeURL(forRelativePath:in:)` —— **只有一份实现**。
    /// 这里留下的是分支不同的两句话：「不在 recordings 目录下」和「文件名不合法」
    /// 对用户是两回事，混成一句话他不知道该改哪儿。
    public func url(forRelativePath path: String) throws -> URL {
        guard path.hasPrefix(Self.relativePrefix) else {
            throw RecordingStoreError.unsafePath(
                "录音路径「\(path)」不在 recordings 目录下，已拒绝操作，什么都没动。"
                + "下一步：这条训练记录的录音路径可能被改坏了；"
                + "打开数据目录里的 state.json，检查这一条的 recordingPath 字段。")
        }
        guard let url = directory.safeURL(forRelativePath: path,
                                          in: [DataDirectory.recordingsFolder]) else {
            throw RecordingStoreError.unsafePath(
                "录音路径「\(path)」不是一个合法的文件名，已拒绝操作，什么都没动。"
                + "下一步：打开数据目录里的 state.json，检查这一条的 recordingPath 字段。")
        }
        return url
    }

    public func fileExists(relativePath: String) -> Bool {
        guard let url = try? url(forRelativePath: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func existingFileNames() throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.recordingsDirectory.path) else { return [] }
        return try manager.contentsOfDirectory(atPath: directory.recordingsDirectory.path)
            .filter { $0.hasSuffix(".\(Self.fileExtension)") }
            .sorted()
    }

    /// 删除一条录音。文件本来就不在时不报错——用户要的是「这条录音没了」，
    /// 文件早就没了同样满足；报错只会让人以为没删掉然后反复去点。
    public func delete(relativePath: String) throws {
        let url = try url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RecordingStoreError.deleteFailed(
                "删不掉录音文件 \(url.path)：\(error.localizedDescription)。"
                + "下一步：确认这个文件没有正在被播放或被别的程序打开，然后再点一次删除。")
        }
    }

    public func usage() throws -> RecordingUsage {
        let names = try existingFileNames()
        var total: Int64 = 0
        for name in names {
            let url = directory.recordingsDirectory.appending(path: name)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += Int64(size ?? 0)
        }
        return RecordingUsage(count: names.count, bytes: total)
    }

    /// 磁盘上有、但没有任何训练记录指向它的录音。多半是练习中途崩溃留下的。
    /// **不主动删**——用户的录音只有用户能决定删不删，但必须让他知道它们占着地方。
    public func orphanFileNames(referencedPaths: [String]) throws -> [String] {
        let referenced = Set(referencedPaths.compactMap { path -> String? in
            guard path.hasPrefix(Self.relativePrefix) else { return nil }
            return String(path.dropFirst(Self.relativePrefix.count))
        })
        return try existingFileNames().filter { !referenced.contains($0) }
    }
}
