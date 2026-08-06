import Foundation
import IELTSCoachCore

/// 删一条训练记录会连带删掉哪些文件。**纯计算，不碰磁盘**，所以能测。
public struct SessionDeletionPlan: Equatable, Sendable {
    public let sessionID: String
    /// 相对数据目录的路径，顺序固定：先复盘报告，再录音。
    public let relativePaths: [String]
    /// 给用户看的确认文案。**必须逐条列明会删掉什么、也说清什么不会删。**
    public let confirmationText: String
}

public enum SessionDeletion {
    /// **为什么这句话里只点名「取消」，不点名那颗销毁按钮**：
    /// `RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists` 要求
    /// 文案里「点『X』」的 X 必须是界面上真存在的按钮（铁律 4）。承载删除确认的
    /// `HistoryView` 还没建（本计划 Task 9），那颗销毁按钮此刻并不存在——
    /// 指着一颗不存在的按钮，比不写还糟，用户会一直找。
    /// 页面建好、确认框里真的有了那颗按钮之后，这句话可以改成同时点名两颗。
    public static func plan(for session: PracticeSession) -> SessionDeletionPlan {
        var paths: [String] = []
        var pieces: [String] = ["这一场的训练记录和逐字稿"]
        if !session.reportPath.isEmpty {
            paths.append(session.reportPath)
            pieces.append("它的复盘报告")
        }
        // Phase 5 还没交付时，recordingPath 基本都是空的——「有就删、没有就跳过」，
        // 不硬依赖 Phase 5 的任何类型（决策 4）。
        if !session.recordingPath.isEmpty {
            paths.append(session.recordingPath)
            pieces.append("它的录音文件")
        }
        return SessionDeletionPlan(
            sessionID: session.id,
            relativePaths: paths,
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
    /// 顺序刻意是「先删记录，再删文件」：文件删不掉不该拦住记录本身的删除，
    /// 否则用户会卡在一条删不掉的记录上，而他真正想做的只是让它从列表里消失。
    @discardableResult
    public func delete(_ session: PracticeSession) -> String? {
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
        for relativePath in SessionDeletion.plan(for: session).relativePaths {
            let url = directory.root.appending(path: relativePath)
            // 文件本来就不在（用户手工删过、拷目录时漏了）不是错误
            guard fileRemover.fileExists(at: url) else { continue }
            do { try fileRemover.remove(at: url) } catch { failed.append(relativePath) }
        }

        guard !failed.isEmpty else { return nil }
        // 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
        return "训练记录已经删掉了，但有 \(failed.count) 个文件没能删除："
            + failed.joined(separator: "、") + "。"
            + "下一步：到数据目录里手动删掉它们（默认在「资源库 › Application Support › "
            + "IELTS Speaking Coach」）；留着不影响使用，只是白占磁盘。"
    }
}
