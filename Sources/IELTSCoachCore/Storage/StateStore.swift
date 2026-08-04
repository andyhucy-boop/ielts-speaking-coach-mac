import Foundation

/// state.json 的读写。用 flock 保证跨进程互斥，用临时文件 + rename 保证写入原子性。
public final class StateStore: @unchecked Sendable {
    private let directory: DataDirectory
    private let lockFile: URL

    public init(directory: DataDirectory) {
        self.directory = directory
        self.lockFile = directory.root.appending(path: ".state.lock")
    }

    public func load() throws -> CoachState {
        try withLock(exclusive: false) { try readUnlocked() }
    }

    /// 加锁完成「读 → 改 → 写」，避免两个进程互相覆盖。
    @discardableResult
    public func mutate<T>(_ body: (inout CoachState) throws -> T) throws -> T {
        try withLock(exclusive: true) {
            var state = try readUnlocked()
            let result = try body(&state)
            try writeUnlocked(state)
            return result
        }
    }

    // MARK: - 私有

    private func readUnlocked() throws -> CoachState {
        guard FileManager.default.fileExists(atPath: directory.stateFile.path) else {
            return CoachState.empty()
        }
        let data = try Data(contentsOf: directory.stateFile)
        if data.isEmpty { return CoachState.empty() }
        do {
            return try JSONDecoder().decode(CoachState.self, from: data)
        } catch {
            throw CoachError.stateUnreadable(
                "训练数据文件已损坏，无法读取：\(directory.stateFile.path)。"
                + "下一步：把该文件改名备份后重新启动，App 会新建一份空白记录；"
                + "reports 目录里的历史复盘不受影响。")
        }
    }

    private func writeUnlocked(_ state: CoachState) throws {
        try directory.createIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)

        let temporary = directory.root.appending(path: ".state.json.\(UUID().uuidString).tmp")
        // replaceItemAt 成功时临时文件已被移走，这里的清理是 no-op；
        // 失败时（磁盘满、权限等）则确保不在用户数据目录里留下孤儿 .tmp 文件。
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        // rename 是同一卷内的原子操作，读者永远看不到半截文件。
        // temporary 与 stateFile 同为 directory.root 的直接子项，必然同卷，原子性成立。
        _ = try FileManager.default.replaceItemAt(directory.stateFile, withItemAt: temporary)
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        try directory.createIfNeeded()
        if !FileManager.default.fileExists(atPath: lockFile.path) {
            FileManager.default.createFile(atPath: lockFile.path, contents: nil)
        }
        let descriptor = open(lockFile.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw CoachError.stateUnreadable(
                "无法为训练数据加锁：\(lockFile.path)。下一步：确认该目录可写后重试。")
        }
        defer { close(descriptor) }

        // 刻意使用阻塞的 flock（不加 LOCK_NB）。审查裁定：临界区是 KB 级 JSON 的
        // 毫秒级读改写，持锁进程崩溃时 OS 会自动释放，不存在真死锁；
        // spec 第 6 节「禁止无限等待」针对的是 AX 树、外部应用那类无界等待，
        // 本地磁盘 I/O 是有界的。不要改成 LOCK_NB + 超时重试。
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw CoachError.stateUnreadable(
                "训练数据正被另一个进程占用，且等待失败。下一步：关闭其他正在运行的实例后重试。")
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }
}
