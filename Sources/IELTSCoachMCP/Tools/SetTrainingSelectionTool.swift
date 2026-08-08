import Foundation
import IELTSCoachCore

enum SetTrainingSelectionTool {
    private struct Payload: Encodable {
        let sessionId: String
        let questionId: String
        let part: Int
        let topic: String
        let prompt: String
        let focusPart: String
        let goal: String
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let parts = FocusPart.allCases.map(\.rawValue)
        return MCPTool.throwing(
            name: "set_training_selection",
            description: "选定下一场练习的题目、Part 与单点目标，写进 state.json 的 currentSession。"
                + "App 与命令行都会读到同一份选择。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "questionId": .object([
                        "type": .string("string"),
                        "description": .string("题库里的题号，例如 p1-2f3k9x。用 get_dashboard_data 或 App 的「训练题库」页可以看到。")
                    ]),
                    "focusPart": .object([
                        "type": .string("string"),
                        "enum": .array(parts.map { JSONValue.string($0) }),
                        "description": .string("练哪一部分。省略时按题目自身的 part 推断。")
                    ]),
                    "goal": .object([
                        "type": .string("string"),
                        "description": .string("本次唯一的单点目标，例如「回答后补一个原因和例子」。可留空。")
                    ])
                ]),
                "required": .array([.string("questionId")]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let questionID = try arguments.requiredString("questionId",
                hint: "先调用 get_dashboard_data 或在 App 的「训练题库」页找到题号，再传进来。")
            let goal = try arguments.optionalString("goal") ?? ""

            // 整个「查题 + 写选择」放在同一次 mutate 里：查不到题就抛错，
            // mutate 的写入发生在 body 之后，因此磁盘上不会留下半个选择。
            let payload = try environment.store.mutate { state -> Payload in
                guard let question = state.questions.first(where: { $0.id == questionID }) else {
                    throw ToolInputError(message:
                        "题库里没有题号「\(questionID)」（当前共 \(state.questions.count) 题）。"
                        + "下一步：调用 get_dashboard_data 看看现在有哪些题，"
                        + "或先在 App 的「训练题库」页导入题库。")
                }
                let inferred = FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
                let focusRaw = try arguments.optionalChoice("focusPart", allowed: parts,
                    default: inferred.rawValue,
                    hint: "focusPart 只能是 \(parts.joined(separator: "、"))。")
                let focusPart = FocusPart(rawValue: focusRaw) ?? inferred

                let sessionID = SessionID.next(existing: state.sessions, now: environment.now(),
                                               timeZone: environment.timeZone)
                state.currentSession = PracticeSession(
                    id: sessionID, questionId: question.id, focusPart: focusPart,
                    startedAt: environment.timestamp, endedAt: "", goal: goal,
                    transcript: [], reportPath: "", recordingPath: "")

                return Payload(sessionId: sessionID, questionId: question.id, part: question.part,
                               topic: question.topic, prompt: question.prompt,
                               focusPart: focusPart.rawValue, goal: goal,
                               note: "已选定。下一步：调用 get_training_context 取考官提示词。")
            }
            return try ToolJSON.text(payload)
        }
    }
}
