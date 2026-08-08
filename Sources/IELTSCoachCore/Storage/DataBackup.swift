import Foundation

/// 动用户训练数据之前先整份复制一遍。
///
/// ## 为什么整份复制，而不是只备份 state.json
///
/// state.json 里存的是**相对路径**（`reports/2026-08-08-001.json`、
/// `recordings/…m4a`）。只备份 state.json 的话，回滚之后那些路径指向的文件
/// 可能已经不在了——回滚出来的是一份看着完整、点开却处处「文件找不到」的数据。
/// 4 MB 级的目录，整份复制的代价可以忽略。
///
/// ## 为什么不做「自动回滚」
///
/// 回滚意味着删掉用户当前的数据目录。**这个工具不做这种事**：把备份放在哪儿、
/// 什么时候用它，由用户自己决定，命令只负责如实报出那条路径。
public enum DataBackup {

    /// 备份文件夹的名字：`ielts-coach-backup-20260808-161115`。
    ///
    /// **和用户已有的那份手工备份同一个命名法**，这样它们会排在一起、一眼能看出先后。
    /// 时间戳用本机时区：这条路径是给人看的，UTC 会让他对不上「我刚才几点跑的」。
    public static func folderName(at date: Date,
                                  timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "ielts-coach-backup-\(formatter.string(from: date))"
    }

    /// 把整个数据目录复制到 `parent` 下的一个新文件夹里，返回那个文件夹的 URL。
    ///
    /// **绝不覆盖已有的备份。** 同一秒内跑第二次时改用 `-2`、`-3`……
    /// 覆盖掉上一份备份是这类命令最坏的失手方式：用户以为自己有两道保险，其实只有一道。
    ///
    /// 复制失败一律抛错（铁律 7）：备份没成，后面那一步就不该发生。
    @discardableResult
    public static func copy(_ directory: DataDirectory, into parent: URL,
                            at date: Date = Date(),
                            fileManager: FileManager = .default) throws -> URL {
        guard fileManager.fileExists(atPath: directory.root.path) else {
            throw CoachError.stateUnreadable(
                "要备份的训练数据目录不存在：\(directory.root.path)。"
                    + "下一步：确认这台电脑上确实用过本工具；没有数据就没有什么要迁移的。")
        }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let base = folderName(at: date)
        var destination = parent.appending(path: base)
        var attempt = 2
        while fileManager.fileExists(atPath: destination.path) {
            guard attempt <= 100 else {
                throw CoachError.stateUnreadable(
                    "\(parent.path) 下已经有 100 份同一秒的备份了，再建一份没有意义。"
                        + "下一步：先把旧的备份挪走或删掉，再重新运行。")
            }
            destination = parent.appending(path: "\(base)-\(attempt)")
            attempt += 1
        }

        do {
            try fileManager.copyItem(at: directory.root, to: destination)
        } catch {
            throw CoachError.stateUnreadable(
                "备份训练数据失败：\(error.localizedDescription)。"
                    + "因为备份没做成，**数据一个字节都没有被改动**。"
                    + "下一步：确认 \(parent.path) 可写、磁盘还有剩余空间，然后重新运行。")
        }
        return destination
    }
}
