import Foundation
import IELTSCoachCore

/// 删一条训练记录会连带删掉哪些文件。**纯计算，不碰磁盘**，所以能测。
public struct SessionDeletionPlan: Equatable, Sendable {
    /// 一个会被删掉的文件，连同它在 state.json 里的字段名。
    ///
    /// **字段名必须带着走**：路径被改坏时那句拒绝的话要点名让用户去改哪一行，
    /// 只说「有个路径不对」他得在整份 state.json 里翻。
    public struct Entry: Equatable, Sendable {
        public let field: String            // "reportPath" | "recordingPath"
        public let relativePath: String
    }

    public let sessionID: String
    /// 顺序固定：先复盘报告，再录音。
    public let entries: [Entry]
    /// 给用户看的确认文案。**必须逐条列明会删掉什么、也说清什么不会删。**
    public let confirmationText: String

    /// 相对数据目录的路径，顺序同 `entries`。
    public var relativePaths: [String] { entries.map(\.relativePath) }
}

public enum SessionDeletion {
    /// **为什么这句话里只点名「取消」，不点名那颗销毁按钮**：
    /// `RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists` 要求
    /// 文案里「点『X』」的 X 必须是界面上真存在的按钮（铁律 4）。承载删除确认的
    /// `HistoryView` 还没建（本计划 Task 9），那颗销毁按钮此刻并不存在——
    /// 指着一颗不存在的按钮，比不写还糟，用户会一直找。
    /// 页面建好、确认框里真的有了那颗按钮之后，这句话可以改成同时点名两颗。
    public static func plan(for session: PracticeSession) -> SessionDeletionPlan {
        var entries: [SessionDeletionPlan.Entry] = []
        var pieces: [String] = ["这一场的训练记录和逐字稿"]
        if !session.reportPath.isEmpty {
            entries.append(.init(field: "reportPath", relativePath: session.reportPath))
            // **把真实路径也摆出来。** 这是一次不可撤销的销毁，而路径是可以被手工改坏的
            // （本工具自己的错误提示就在引导用户去改 state.json）。只说「它的复盘报告」，
            // 用户按下去之前没有任何机会发现这条记录指向的其实是别的东西。
            pieces.append("它的复盘报告（\(session.reportPath)）")
        }
        // Phase 5 还没交付时，recordingPath 基本都是空的——「有就删、没有就跳过」，
        // 不硬依赖 Phase 5 的任何类型（决策 4）。
        if !session.recordingPath.isEmpty {
            entries.append(.init(field: "recordingPath", relativePath: session.recordingPath))
            pieces.append("它的录音文件（\(session.recordingPath)）")
        }
        return SessionDeletionPlan(
            sessionID: session.id,
            entries: entries,
            confirmationText: "删掉之后，\(pieces.joined(separator: "、"))都会从磁盘上消失，无法恢复。"
                + "已经归进错题本和词汇本的内容不会跟着删——那些是跨场累积的，"
                + "只删这一场不会让它们对不上。"
                + "下一步：想留着就点「取消」；确认之后立刻生效，不进废纸篓，也没有撤销。")
    }
}

/// 文件删除的接缝。**唯一目的是可测性**——有了它，「删不掉时要如实报告」
/// 这条路径才能在不真的把文件锁住的情况下被测到。
public protocol FileRemoving: Sendable {
    func fileExists(at url: URL) -> Bool
    func remove(at url: URL) throws
}

public struct SystemFileRemover: FileRemoving {
    public init() {}
    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    public func remove(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// 删一条训练记录。
@MainActor
public final class SessionDeleter {
    private let directory: DataDirectory
    private let store: StateStore
    private let fileRemover: any FileRemoving

    public init(directory: DataDirectory, store: StateStore,
                fileRemover: any FileRemoving = SystemFileRemover()) {
        self.directory = directory
        self.store = store
        self.fileRemover = fileRemover
    }

    /// 删除。**永不抛错**：返回 nil 表示一切顺利，返回字符串是给用户看的中文说明。
    ///
    /// 顺序刻意是「先校验路径，再删记录，最后删文件」：
    ///
    /// - **校验必须在最前面**（复审第 4 条）。路径被改坏时这一趟一个字节都不许动，
    ///   连记录本身也不删——记录是用户找到那条坏路径的唯一线索，
    ///   先把它删掉就等于让他修无可修。
    /// - 校验通过之后，文件删不掉不该拦住记录本身的删除，
    ///   否则用户会卡在一条删不掉的记录上，而他真正想做的只是让它从列表里消失。
    @discardableResult
    public func delete(_ session: PracticeSession) -> String? {
        let plan = SessionDeletion.plan(for: session)
        var targets: [(relativePath: String, url: URL)] = []
        var unsafe: [SessionDeletionPlan.Entry] = []
        for entry in plan.entries {
            // 白名单只有这两个子目录：state.json 里的路径本来就只可能落在这里。
            if let url = directory.safeURL(
                forRelativePath: entry.relativePath,
                in: [DataDirectory.reportsFolder, DataDirectory.recordingsFolder]) {
                targets.append((entry.relativePath, url))
            } else {
                unsafe.append(entry)
            }
        }
        if let refusal = Self.refusal(for: unsafe, sessionID: session.id) { return refusal }

        do {
            try store.mutate { state in
                state.sessions.removeAll { $0.id == session.id }
                if state.currentSession?.id == session.id { state.currentSession = nil }
            }
        } catch {
            return "没能删掉这条训练记录：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重试。这一条仍然在列表里，什么都没被改动。"
        }

        var failed: [String] = []
        for target in targets {
            // 文件本来就不在（用户手工删过、拷目录时漏了）不是错误
            guard fileRemover.fileExists(at: target.url) else { continue }
            do { try fileRemover.remove(at: target.url) } catch { failed.append(target.relativePath) }
        }

        guard !failed.isEmpty else { return nil }
        // 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
        return "训练记录已经删掉了，但有 \(failed.count) 个文件没能删除："
            + failed.joined(separator: "、") + "。"
            + "下一步：到数据目录里手动删掉它们（默认在「资源库 › Application Support › "
            + "IELTS Speaking Coach」）；留着不影响使用，只是白占磁盘。"
    }

    /// 路径不合法时给用户的那段话。全都合法时返回 nil。
    ///
    /// 四件事一句都不能少：**哪一条**、**哪个字段**、**那个字符串长什么样**、
    /// **这一趟什么都没动**。少了最后一句，用户看到那一行还在列表里，
    /// 只会以为删除按钮坏了，然后一直点。
    private static func refusal(for unsafe: [SessionDeletionPlan.Entry],
                                sessionID: String) -> String? {
        guard !unsafe.isEmpty else { return nil }
        let listed = unsafe.map { "\($0.field) =「\($0.relativePath)」" }.joined(separator: "、")
        return "没有删除：这一条训练记录里有 \(unsafe.count) 个文件路径不在数据目录的 "
            + "reports/ 或 recordings/ 下——\(listed)。"
            + "照这样的路径删下去，删掉的可能是你的训练数据文件本身或者整个录音目录，"
            + "所以这一趟什么都没有动：训练记录、复盘报告、录音文件全都原样还在，"
            + "那一条也还留在列表里。"
            + "下一步：打开数据目录里的 state.json（默认在「资源库 › Application Support › "
            + "IELTS Speaking Coach」），找到 id 为 \(sessionID) 的这条记录，"
            + "把上面这个字段改成 reports/文件名 或 recordings/文件名 的形状"
            + "（这一场本来就没有对应文件的话，写成空字符串 \"\" 即可），"
            + "存盘后重新打开 App 再删一次。"
    }
}
