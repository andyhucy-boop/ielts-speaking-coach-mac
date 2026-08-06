import Foundation
import IELTSCoachCore
import Observation

public struct PendingReviewRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let entry: PendingReviewEntry
    public let sessionID: String
    public let timeText: String
    /// 这份复盘属于哪道题。查不到时是一句中文说明，**不会是空字符串**。
    public let questionText: String
    public let sizeText: String
}

/// 把「文件清单」和「训练记录」拼成界面要显示的行。**纯函数，所以能测。**
public enum PendingReviewRowBuilder {
    public static func rows(entries: [PendingReviewEntry], state: CoachState,
                            timeZone: TimeZone) -> [PendingReviewRow] {
        let sessions = Dictionary(state.sessions.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let questions = Dictionary(state.questions.map { ($0.id, $0) },
                                   uniquingKeysWith: { first, _ in first })

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return entries.map { entry in
            // 文件名可能是 "2026-08-06-001-2.txt"（同一场的第二份原文），
            // 先按完整编号找，找不到再去掉 "-N" 后缀找一次。
            let session = sessions[entry.sessionID] ?? sessions[trimmedCopySuffix(entry.sessionID)]
            let questionText: String
            if let session, let question = questions[session.questionId] {
                questionText = question.prompt
            } else if let session {
                questionText = "这一场练的题目已经不在题库里了（id：\(session.questionId)）。"
            } else {
                questionText = "查不到这份复盘属于哪一场练习"
                    + "（编号「\(entry.sessionID)」不在训练记录里，多半是那次练习没能存进去）。"
            }

            return PendingReviewRow(
                id: entry.id, entry: entry, sessionID: entry.sessionID,
                timeText: formatter.string(from: entry.modifiedAt),
                questionText: questionText,
                sizeText: sizeText(entry.byteCount))
        }
    }

    private static func trimmedCopySuffix(_ sessionID: String) -> String {
        guard let dash = sessionID.lastIndex(of: "-"),
              Int(sessionID[sessionID.index(after: dash)...]) != nil else { return sessionID }
        return String(sessionID[..<dash])
    }

    static func sizeText(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) 字节"
                     : String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
}

/// 「重新导入待处理的复盘」。
///
/// **为什么它必须存在**（决策 2）：复盘自动取回失败时，原文确实落在 `pending-reviews/`
/// 里没丢，但把它补进库的唯一途径原本是终端里跑 `coach reimport`。成品标准第 2 条是
/// 「全程不需要打开终端」，而**出错恰恰是最需要它成立的时候**。
///
/// 两件必须做对的事：
///
/// 1. **导入成功后必须打 `.imported` 标记。** `ReviewArchiver` 对「同一 session 重复归档」
///    只在 `sourceSessionIds` 上去重，`IssueRecord.occurrences` 会跟着重复调用继续累加。
///    不打标记的话，用户手一抖点两次，「这句话说错了几次」就悄悄失真了。
/// 2. **失败时一个字都不许动那个文件。** 解析不了、归档失败，都要让它原样留在待处理列表里——
///    它是用户练了半小时换来的东西，删了就再也没有第二份。
@MainActor
@Observable
public final class PendingReviewViewModel {
    private let directory: DataDirectory
    private let store: StateStore
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    public private(set) var rows: [PendingReviewRow] = []
    /// 给用户看的中文说明（成功或失败）。**非 nil 时界面必须显示它。**
    public private(set) var notice: String?

    public init(directory: DataDirectory, store: StateStore,
                timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.store = store
        self.timeZone = timeZone
        self.now = now
    }

    public var isEmpty: Bool { rows.isEmpty }

    public func refresh() {
        do {
            let entries = try PendingReviewStore.list(directory: directory)
            let state = try store.load()
            rows = PendingReviewRowBuilder.rows(entries: entries, state: state, timeZone: timeZone)
        } catch {
            rows = []
            notice = "没能列出待处理的复盘：\(error.localizedDescription) "
                + "下一步：确认数据目录能读（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后点「刷新」重试。"
        }
    }

    /// 用户读完那句说明之后把它收起来。
    ///
    /// **不在 `refresh()` 里顺手清掉**：`reimport` 的最后一步就是 `refresh()`，
    /// 那样刚写好的「已经重新入库」「字段名对不上」会被自己的刷新抹掉，
    /// 用户点完按钮只看到列表少了一行，不知道到底成没成。
    public func clearNotice() { notice = nil }

    public func rawText(of row: PendingReviewRow) -> String? {
        do { return try PendingReviewStore.read(row.entry) } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    public func reimport(_ row: PendingReviewRow) {
        let raw: String
        do { raw = try PendingReviewStore.read(row.entry) } catch {
            notice = error.localizedDescription
            return
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
        } catch {
            // 解析失败时**一个字都不许动那个文件**——它是用户练了半小时换来的东西。
            notice = "「\(row.sessionID)」还是解析不了：\(error.localizedDescription) "
                + "下一步：点「查看原文」看看 ChatGPT 到底输出了什么；"
                + "若确实不是标准格式，回 ChatGPT 里让它按要求重新输出一次，"
                + "复制之后新练一场时会自动落盘。这个文件原样留着，没有被改动。"
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        let reportRelativePath = "reports/\(row.sessionID).json"
        do {
            try directory.createIfNeeded()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(row.sessionID).json"),
                       options: .atomic)

            let outcome = try store.mutate { state -> ArchiveOutcome in
                let questionID = state.sessions.first { $0.id == row.sessionID }?.questionId ?? ""
                let result = ReviewArchiver.archive(report: report, into: state,
                                                    sessionID: row.sessionID,
                                                    questionID: questionID, at: timestamp)
                state = result.state
                if let index = state.sessions.firstIndex(where: { $0.id == row.sessionID }) {
                    state.sessions[index].reportPath = reportRelativePath
                }
                return result
            }

            // 打标记必须在归档成功之后。归档失败还打了标记，用户就再也点不到它了。
            try PendingReviewStore.markImported(row.entry)

            if outcome.skipped.isEmpty {
                notice = "「\(row.sessionID)」已经重新入库。"
                    + "下一步：到上面的复盘列表里就能看到它了。"
            } else {
                // 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
                // 静默的 0 是本项目已知最危险的失败形态。
                notice = "「\(row.sessionID)」入库了，但复盘里的 "
                    + outcome.skipped.joined(separator: "、")
                    + " 一条都没能归进档案。这通常意味着 ChatGPT 用的字段名和本工具读的对不上。"
                    + "下一步：原文已经改名成 \(row.entry.fileName)\(PendingReviewStore.importedSuffix) "
                    + "留在 pending-reviews 目录里，可以打开对照着看；"
                    + "若想重来，把 .imported 后缀去掉它就会重新出现在这个列表里。"
            }
        } catch {
            notice = "「\(row.sessionID)」解析成功了，但入库时出错：\(error.localizedDescription) "
                + "下一步：确认数据目录可写后再点一次「重新导入」；原文没有被改动，不会丢。"
        }
        refresh()
    }

    public func delete(_ row: PendingReviewRow) {
        do {
            try PendingReviewStore.delete(row.entry)
            notice = "已经删掉「\(row.entry.fileName)」。下一步：无需其他操作。"
        } catch {
            notice = "没能删掉「\(row.entry.fileName)」：\(error.localizedDescription) "
                + "下一步：到数据目录的 pending-reviews 里手动删除。"
        }
        refresh()
    }
}
