import Foundation
import IELTSCoachCore

enum ListPracticeHistoryTool {
    private struct Row: Encodable {
        let sessionId: String
        let questionId: String
        let questionPrompt: String
        let topic: String
        let part: Int
        let questionMissing: Bool
        let focusPart: String
        let startedAt: String
        let endedAt: String
        let goal: String
        let hasReport: Bool
        let reportPath: String
        let hasRecording: Bool
        let transcriptTurns: Int
        /// startedAt 与场次 id 里都读不出时间。这种行排在最后，位置不代表它有多新。
        /// 不逐条标出来的话，模型与用户都会把它当成「最早的一场」。
        let startTimeUnreadable: Bool
    }

    private struct Payload: Encodable {
        let total: Int
        let returned: Int
        /// 读不出练习时间、因此排不进时间轴的场次数（按全量算，不只是这次返回的几条）。
        /// 非 0 时 note 里必须解释——排序不可信却一个字不提就是静默失败。
        let undatedSessionCount: Int
        let sessions: [Row]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "list_practice_history",
            description: "列出已经存档的练习记录，从新到旧。每条含题目、Part、时间、是否已有复盘。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(200),
                        "description": .string("最多返回几条，默认 20。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let limit = try arguments.optionalInt("limit", in: 1...200, default: 20,
                hint: "limit 传 1–200 之间的整数；省略则返回最近 20 条。")
            let state = try environment.store.load()

            // 排序规则不在这里另写一份。这里原本写的是 `sorted { $0.startedAt > $1.startedAt }`，
            // 它比 Core 那份弱：startedAt 空着、时间只剩在 id 里的记录是真实存在的数据，
            // 于是用户刚练完的那场被排到最后、传了 limit 就直接从列表里消失，
            // 而同一份 state 交给 get_dashboard_data（走 TrainingStats，有兜底）
            // 又把它算进「本周训练」——两个工具对同一份数据给出互相矛盾的答案。
            let ordering = PracticeSessionOrder.newestFirst(state.sessions)
            let undated = Set(ordering.undatedIDs)
            let rows = ordering.ordered.prefix(limit).map { session -> Row in
                let question = state.questions.first { $0.id == session.questionId }
                return Row(
                    sessionId: session.id,
                    questionId: session.questionId,
                    questionPrompt: question?.prompt ?? "",
                    topic: question?.topic ?? "",
                    part: question?.part ?? 0,
                    // 换季重新导入题库后旧记录可能指向已经不存在的题。
                    // 显示成空白会让用户以为记录坏了，必须明确标出来。
                    questionMissing: question == nil,
                    focusPart: session.focusPart.rawValue,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    goal: session.goal,
                    hasReport: !session.reportPath.isEmpty,
                    reportPath: session.reportPath,
                    hasRecording: !session.recordingPath.isEmpty,
                    // 逐字稿是 Phase 4 的事，现在恒为 0，如实返回。
                    transcriptTurns: session.transcript.count,
                    startTimeUnreadable: undated.contains(session.id))
            }

            var note = state.sessions.isEmpty
                ? "还没有任何练习记录。下一步：用 set_training_selection 选题、"
                    + "get_training_context 取考官提示词，练完把复盘交给 save_session_review。"
                : "按练习开始时间从新到旧排列（startedAt 空着时退回按场次 id 里的日期算）。"
                    + "下一步：想看某一场的完整复盘，"
                    + "打开对应的 reportPath 文件，或用 open_dashboard 打开复盘报告页。"
            if !ordering.undatedIDs.isEmpty {
                // 顺序对这几条是不可信的，不说等于给了一个用户无法核对的列表（铁律 6、7）。
                let sample = ordering.undatedIDs.prefix(3).joined(separator: "、")
                note += "另有 \(ordering.undatedIDs.count) 场练习读不出练习时间"
                    + "（startedAt 空着或写坏了，场次 id 也不以 YYYY-MM-DD 开头），"
                    + "它们排在列表最后、行内 startTimeUnreadable 为 true，"
                    + "传了 limit 时可能根本没出现在这次返回里。"
                    + "下一步：打开数据目录里的 state.json，在 sessions 里找到这几个 id：\(sample)，"
                    + "把 startedAt 补成练习当天的时间戳（形如 2026-08-05T10:00:00Z），"
                    + "补上它们就会回到正确的位置。"
            }

            return try ToolJSON.text(Payload(
                total: state.sessions.count,
                returned: rows.count,
                undatedSessionCount: ordering.undatedIDs.count,
                sessions: Array(rows),
                note: note))
        }
    }
}
