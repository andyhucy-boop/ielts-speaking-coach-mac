import Foundation
import IELTSCoachCore
import Observation

public struct PendingReviewRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let entry: PendingReviewEntry
    /// 文件名里的那个编号，原样显示给用户看——包括 `2026-08-06-001-2` 这种
    /// 「同一场的第二份原文」。**它不一定是一个真实存在的会话编号**，见下。
    public let sessionID: String
    /// 这份原文真正属于训练记录里的哪一场；回查不到时是 nil。
    ///
    /// **归档、写报告、回填 `reportPath` 都必须用它，不能用 `sessionID`。**
    /// `PracticeRunner` 重试取复盘、拿到的原文和上一次不一样时，
    /// `PendingReviewStore.write` 会把第二份落成 `<id>-2.txt`，于是文件名里的编号
    /// 比真正的会话编号多一截。拿它去归档的话：`sourceSessionIds` 里会多出一个
    /// 根本不存在的编号、`reportPath` 回填不上（复盘报告页永远看不到这一场）、
    /// `reports/<id>-2.json` 成了没人引用的文件。
    /// 列表这一侧本来就是去掉 `-N` 后缀回查会话的（所以行上显示的题目是对的），
    /// 两侧必须用同一个答案，否则同一行上的两句话自相矛盾。
    public let linkedSessionID: String?
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
                // 回查到哪一场，就把那一场的编号交出去——**归档那一侧用的正是它**，
                // 这样「行上显示的是哪一场」和「归到哪一场名下」不可能说两套话。
                linkedSessionID: session?.id,
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
/// 1. **导入成功后必须打 `.imported` 标记。** 不打的话，一份已经入库的复盘会一直赖在
///    收件箱里，用户分不清哪些还没处理、哪些早就处理完了。
///    （数字本身不会因此失真：`ReviewArchiver.mergeIssues` 按 sessionID 去重，
///    同一场归档多少次，`occurrences` 都一样——那道保险在归档那一层，不在这里。）
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
            //
            // **只取诊断、丢掉 `ReviewParser` 自带的那句「下一步」**（`diagnosisOnly`）。
            // 它在 Core 里，命令行也在用，那句「点「补生成复盘报告」让 ChatGPT 重新输出一次」
            // 在终端那边是对的，可**图形界面里没有这颗按钮**。原样透传的话，
            // 用户会连读到两句「下一步」，第一句指着一颗全 App 都找不到的按钮，
            // 然后一直找（铁律 4：下一步必须是真做得到的一步）。
            // `PracticeRunner` 与 `ReviewReportLoader` 早就各自这么退让过，这一页此前漏了。
            notice = "「\(row.sessionID)」还是解析不了：\(PracticeRunner.diagnosisOnly(error))。"
                + "下一步：点「查看原文」看看 ChatGPT 到底输出了什么；"
                + "若确实不是标准格式，回 ChatGPT 里让它按要求重新输出一次，"
                + "复制之后新练一场时会自动落盘。这个文件原样留着，没有被改动。"
            return
        }

        // 归到哪一场名下：能回查到就用那一场真正的编号，**不是文件名里那个**。
        // `<id>-2.txt`（同一场的第二份原文）拿文件名当编号的话，
        // 会在 `sourceSessionIds` 里留下一个不存在的编号、`reportPath` 回填不上、
        // 还多写一个没人引用的 `reports/<id>-2.json`（见 `PendingReviewRow.linkedSessionID`）。
        let archiveID = row.linkedSessionID ?? row.sessionID
        let timestamp = ISO8601DateFormatter().string(from: now())
        let reportRelativePath = "reports/\(archiveID).json"

        let outcome: ArchiveOutcome
        let linkedToASession: Bool
        do {
            try directory.createIfNeeded()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(archiveID).json"),
                       options: .atomic)

            (outcome, linkedToASession) = try store.mutate { state -> (ArchiveOutcome, Bool) in
                let questionID = state.sessions.first { $0.id == archiveID }?.questionId ?? ""
                let result = ReviewArchiver.archive(report: report, into: state,
                                                    sessionID: archiveID,
                                                    questionID: questionID, at: timestamp)
                state = result.state
                guard let index = state.sessions.firstIndex(where: { $0.id == archiveID }) else {
                    return (result, false)
                }
                state.sessions[index].reportPath = reportRelativePath
                return (result, true)
            }
        } catch {
            // 这一支里档案纹丝不动（`StateStore.mutate` 写不成功就不落盘），所以「再点一次」是对的。
            notice = "「\(row.sessionID)」解析成功了，但入库时出错：\(error.localizedDescription) "
                + "下一步：确认数据目录可写后再点一次「重新导入」；原文没有被改动，不会丢。"
            refresh()
            return
        }

        // 打标记必须在归档成功之后。归档失败还打了标记，用户就再也点不到它了。
        //
        // **从这里往后，任何失败都不许再说「再点一次「重新导入」」。** 归档已经做完了，
        // 再导一次什么也补不上，只会在打标记那一步再失败一次——真正要做的是把撞上的
        // 那个文件名腾出来（`PendingReviewStore.markImported` 抛出的那句话说的就是这件事）。
        do {
            try PendingReviewStore.markImported(row.entry)
        } catch {
            // `markImported` 抛出来的那句话自己就说清了「归档已经做完」和
            // 「先别再点一次导入」，原样交给用户；**后面一个字都不许追加相反的指示**。
            var message = error.localizedDescription
            if !outcome.skipped.isEmpty {
                // 少说一句「字段名可能对不上」就是静默（铁律 7），但也不能借着这句
                // 把「重来一次」偷渡回来——重来一次正是上一句明令禁止的事。
                message += " 另外，这份复盘里的 \(outcome.skipped.joined(separator: "、")) "
                    + "一条都没能归进档案，多半是 ChatGPT 用的字段名和本工具读的对不上；"
                    + "这一条不是再导一次能解决的，先按上面那句把文件名的事处理掉。"
            }
            notice = message
            refresh()
            return
        }

        notice = successNotice(row: row, archiveID: archiveID, reportPath: reportRelativePath,
                               linkedToASession: linkedToASession, skipped: outcome.skipped)
        refresh()
    }

    /// 入库成功之后那句交代。
    ///
    /// **「下一步」不许承诺一件兑现不了的事**（铁律 6）：复盘报告页左边那一列只收
    /// `reportPath` 非空的会话（`ReviewReportViewModel.archivedSessions`），
    /// 而 `reportPath` 只有在训练记录里真的有这一场时才回填得上。查不到那一场
    /// （`sync-*` 那类老编号、或者那次练习压根没能存进记录）却仍旧说「到复盘列表里就能看到它了」，
    /// 用户去那一页永远看不到，只会以为是自己点错了；`reports/<id>.json` 也就成了
    /// 一个没人知道的文件。同一行在列表里刚说完「查不到这份复盘属于哪一场练习」，
    /// 成功文案不能转头当它查得到。
    private func successNotice(row: PendingReviewRow, archiveID: String, reportPath: String,
                               linkedToASession: Bool, skipped: [String]) -> String {
        var message = archiveID == row.sessionID
            ? "「\(row.sessionID)」已经重新入库。"
            : "「\(row.sessionID)」已经重新入库，算在同一场练习「\(archiveID)」名下。"

        if !skipped.isEmpty {
            // 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
            // 静默的 0 是本项目已知最危险的失败形态。
            message += "不过复盘里的 \(skipped.joined(separator: "、")) 一条都没能归进档案，"
                + "这通常意味着 ChatGPT 用的字段名和本工具读的对不上。"
        }

        if linkedToASession {
            message += "下一步：关掉这张表，「复盘报告」页左边那一列里就能看到这一场了。"
        } else {
            message += "但训练记录里查不到编号「\(row.sessionID)」这一场"
                + "（多半是那次练习当时没能存进记录），所以「复盘报告」页左边那一列不会出现它——"
                + "那一列只收记得下复盘位置的练习。"
                + "下一步：这份复盘的完整内容已经存成 \(reportPath)，"
                + "到数据目录里打开它就能看；错题和词汇不受影响，已经照常进了档案。"
        }

        if !skipped.isEmpty {
            message += "另外，原文已经改名成 \(row.entry.fileName)\(PendingReviewStore.importedSuffix) "
                + "留在 pending-reviews 目录里，可以打开对照着看；"
                + "等本工具认得这种字段名之后想重来的话，把 .imported 后缀去掉，"
                + "它就会重新出现在这个列表里。"
        }
        return message
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
