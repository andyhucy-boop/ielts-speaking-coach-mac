import Foundation
import IELTSCoachCore

/// 一份已经读进来、也拆好分区的复盘。
public struct ReviewDocument: Equatable, Sendable {
    /// 复盘原文的绝对路径。**要显示给用户**——他随时可以自己去看 ChatGPT 当时写了什么。
    public let path: String
    public let priorityTarget: ReviewRow?
    /// ChatGPT 对这一场的整体总结。空串表示这份复盘没给（或没能读出来，那时它会出现在
    /// `unreadableSections` 里）。
    public let summary: String
    public let sections: [ReviewSection]
    /// 复盘里有内容、却一条都没读出来的分区名（见 `ReviewReportViewModel.unreadableSections`）。
    public let unreadableSections: [String]
    /// ChatGPT 在总结里写了雅思分数时要说的那句话（`BandScoreGuard`）；没写就是 nil。
    /// **不是错误**：其余内容照常显示、原文照常存着，只有带分数的那一句被挡在总结之外。
    public let scoreNotice: String?

    public init(path: String, priorityTarget: ReviewRow?, summary: String,
                sections: [ReviewSection], unreadableSections: [String],
                scoreNotice: String? = nil) {
        self.path = path
        self.priorityTarget = priorityTarget
        self.summary = summary
        self.sections = sections
        self.unreadableSections = unreadableSections
        self.scoreNotice = scoreNotice
    }

    /// 解析成功了，但一个字都没有可显示的。界面必须据此说一句话——
    /// 右半边全白会让用户以为程序坏了。
    ///
    /// **`summary` 必须算进来。** 漏掉它的后果不是少显示一块，是**说一句假话**：
    /// 一份只有整体总结（练得短、语法没硬伤时完全可能）的复盘会被打上
    /// 「这份复盘是空的……多半是那次练习太短」，把用户支去重练一场本不必重练的练习。
    public var isEmpty: Bool {
        summary.isEmpty && priorityTarget == nil && sections.isEmpty && unreadableSections.isEmpty
    }
}

/// 把 `PracticeSession.reportPath` 指的那份复盘原文读进来并解析。
///
/// 与 `ReviewReportViewModel` 分开，是因为这一段要碰磁盘：
/// 文件不见了、读不动、解析不了，各要跟用户说一句不同的话，而且每一句都得带上文件路径。
public enum ReviewReportLoader {
    /// `reportPath` 解析成的绝对路径。
    ///
    /// 约定是**相对数据目录**（`reports/<id>.json`，见 `PracticeSession` 的注释；
    /// Phase 10 Task 4 会专门审计这条约定有没有被破坏）。相对路径是「把数据目录整个拷到
    /// 另一台电脑就能接着用」（成品标准第 10 条）的前提。
    ///
    /// **绝对路径也照样打开**：万一哪一版写进去的是绝对路径，硬拼在数据目录后面
    /// 会得到一个必然不存在的路径，报错还指着一个看着眼熟其实根本不存在的地方，
    /// 用户会以为是自己把文件弄丢了。
    public static func reportURL(for session: PracticeSession, in directory: DataDirectory) -> URL {
        let trimmed = session.reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed).standardizedFileURL }
        return directory.root.appending(path: trimmed).standardizedFileURL
    }

    public static func load(session: PracticeSession,
                            in directory: DataDirectory) throws -> ReviewDocument {
        let trimmed = session.reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 列表里本来就不该出现这种会话（`archivedSessions` 会滤掉），
            // 但真走到这儿也要说人话，不能扔一个空白页。
            throw CoachError.reviewNotFound(
                "这次练习（\(session.id)）的档案里没有记下复盘文件，也就没有可显示的复盘。"
                    + "下一步：到「今日训练」再练一场，练完复盘会自动存档并出现在这一页。")
        }

        let url = reportURL(for: session, in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoachError.reviewNotFound(
                "找不到这次练习的复盘原文：\(url.path)。"
                    + "下一步：确认这个文件还在——移动过数据目录、或手工整理过 reports 目录都会让它对不上；"
                    + "确实找不回来的话，到「今日训练」重练一场即可，其余记录不受影响。")
        }

        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CoachError.invalidReviewText(
                "读不到复盘原文：\(url.path)（系统说：\(error.localizedDescription)）。"
                    + "下一步：确认这个文件没有被别的程序占用、当前账号对它有读取权限，"
                    + "然后回到这一页重新点开这次练习。")
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw)
        } catch {
            // **不透传 `ReviewParser` 那句话。** 它的「下一步」是「点『补生成复盘报告』
            // 让 ChatGPT 重新输出一次」——那是练习当场的处置办法，这一页上没有那个按钮，
            // 照搬会把用户支到一个不存在的地方（铁律 6）。
            throw CoachError.invalidReviewText(
                "这份复盘原文不是本工具认得的格式，解析不出来：\(url.path)。原文一个字都没丢。"
                    + "下一步：打开这个文件看看 ChatGPT 当时到底写了什么——多半是内容被截断了"
                    + "（末尾少了一个 }）；补回去再存一次就能显示，补不回来就到「今日训练」重练一场。")
        }

        return ReviewDocument(
            path: url.path,
            // sessionID 只在 ChatGPT 漏给 `priority_target.id` 时用来兜底生成一个稳定的
            // targetKey——与 `ReviewArchiver` 归档这一场时用的是同一个编号、同一份判据，
            // 所以这一页画得出卡片就一定归得进档案。
            priorityTarget: ReviewReportViewModel.priorityTarget(from: report,
                                                                 sessionID: session.id),
            summary: ReviewReportViewModel.summary(from: report),
            sections: ReviewReportViewModel.sections(from: report),
            unreadableSections: ReviewReportViewModel.unreadableSections(in: report),
            scoreNotice: ReviewReportViewModel.scoreNotice(from: report))
    }
}
