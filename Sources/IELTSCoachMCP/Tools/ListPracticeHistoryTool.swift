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
    }

    private struct Payload: Encodable {
        let total: Int
        let returned: Int
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

            // startedAt 全项目统一是 ISO8601 UTC 字符串，同格式下字符串倒序即时间倒序。
            let ordered = state.sessions.sorted { $0.startedAt > $1.startedAt }
            let rows = ordered.prefix(limit).map { session -> Row in
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
                    transcriptTurns: session.transcript.count)
            }

            return try ToolJSON.text(Payload(
                total: state.sessions.count,
                returned: rows.count,
                sessions: Array(rows),
                note: state.sessions.isEmpty
                    ? "还没有任何练习记录。下一步：用 set_training_selection 选题、"
                        + "get_training_context 取考官提示词，练完把复盘交给 save_session_review。"
                    : "按开始时间从新到旧排列。下一步：想看某一场的完整复盘，"
                        + "打开对应的 reportPath 文件，或用 open_dashboard 打开复盘报告页。"))
        }
    }
}
