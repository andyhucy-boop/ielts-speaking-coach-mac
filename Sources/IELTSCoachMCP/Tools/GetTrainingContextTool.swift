import Foundation
import IELTSCoachCore

enum GetTrainingContextTool {
    private struct QuestionPayload: Encodable {
        let id: String
        let part: Int
        let topic: String
        let prompt: String
        let followups: [String]
    }

    private struct TargetPayload: Encodable {
        let id: String
        let label: String
        let status: String
        let evidence: [String]
    }

    private struct IssuePayload: Encodable {
        let learnerSaid: String
        let correction: String
        let occurrences: Int
    }

    private struct Payload: Encodable {
        let sessionId: String
        let question: QuestionPayload
        let focusPart: String
        let durationMinutes: Int
        let goal: String
        let feedbackTiming: String
        let part2PrepMode: String
        let examinerPrompt: String
        let reviewRequestId: String
        let reviewRequestPrompt: String
        let activeTargets: [TargetPayload]
        let recurringIssues: [IssuePayload]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let timings = FeedbackTiming.allCases.map(\.rawValue)
        let prepModes = Part2PrepMode.allCases.map(\.rawValue)

        return MCPTool.throwing(
            name: "get_training_context",
            description: "取当前选定题目的完整练习上下文：考官提示词、复盘请求指令、"
                + "待复训目标与反复出现的错题。调用前先用 set_training_selection 选题。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "durationMinutes": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(60),
                        "description": .string("这一场大约练多少分钟。省略时 Part 2 用 4 分钟、其余用 6 分钟。")
                    ]),
                    "feedbackTiming": .object([
                        "type": .string("string"),
                        "enum": .array(timings.map { JSONValue.string($0) }),
                        "description": .string("deferred＝全程零反馈、像真考试（默认）；immediate＝每答完一题当场用中文点一句。")
                    ]),
                    "part2PrepMode": .object([
                        "type": .string("string"),
                        "enum": .array(prepModes.map { JSONValue.string($0) }),
                        "description": .string("countdown＝一分钟准备倒计时（默认）；learner-controlled＝学员说准备好了再开始。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let state = try environment.store.load()
            guard let session = state.currentSession else {
                throw ToolInputError(message:
                    "还没有选定题目，没有可用的练习上下文。下一步：先调用 set_training_selection 选一道题。")
            }
            guard let question = state.questions.first(where: { $0.id == session.questionId }) else {
                throw ToolInputError(message:
                    "选中的题目「\(session.questionId)」已经不在题库里了（通常是换季重新导入过题库）。"
                    + "下一步：调用 set_training_selection 重新选一道题。")
            }

            // 默认时长跟着**这一场的考法**走，不是跟着题目的 part 走。
            // 两者在大多数情况下一样，但 `set_training_selection` 允许显式指定 focusPart：
            // 一道 Part 2 的题被选成「Part 2 + Part 3 连着练」时，按题目算出来的 4 分钟
            // 会写进提示词的「Target session length」，考官为了对上时间会把 Part 3 砍掉。
            let duration = try arguments.optionalInt("durationMinutes", in: 1...60,
                default: session.focusPart.defaultDurationMinutes,
                // 各档的默认时长逐个念出来，不写死一句会过时的概括：
                // 多选 Part 之后有七档，只提其中两档的话，另外几档的数字就是错的。
                hint: "durationMinutes 传 1–60 之间的整数分钟；省略则按这一场的 focusPart 取默认值（"
                    + FocusPart.allCases
                        .map { "\($0.rawValue) 用 \($0.defaultDurationMinutes) 分钟" }
                        .joined(separator: "、")
                    + "）。")
            let timingRaw = try arguments.optionalChoice("feedbackTiming", allowed: timings,
                default: FeedbackTiming.deferred.rawValue,
                hint: "feedbackTiming 只能是 deferred 或 immediate。")
            let prepRaw = try arguments.optionalChoice("part2PrepMode", allowed: prepModes,
                default: Part2PrepMode.countdown.rawValue,
                hint: "part2PrepMode 只能是 countdown 或 learner-controlled。")

            // 提示词一个字都不在这里拼：英文契约句直接决定 ChatGPT 是否进入考官角色，
            // 只能有 ExaminerPrompt 那一份（spec 2.3.x 全靠它）。
            let setup = SessionSetup(
                question: question, focusPart: session.focusPart, durationMinutes: duration,
                goal: session.goal,
                feedbackTiming: FeedbackTiming(rawValue: timingRaw) ?? .deferred,
                part2PrepMode: Part2PrepMode(rawValue: prepRaw) ?? .countdown,
                // 这一场同时有 Part 2 和 Part 3 时，把那张 cue card 自己那组 Part 3 追问
                // 一起发下去（`LinkedPart3`）。不传的话，从 MCP 这条路开的连练场次
                // 会拿不到题库里现成的真题，而 App 那条路拿得到——同一件事两种结果。
                part3Reference: LinkedPart3.reference(for: question, in: state.questions))

            // 标记由 sessionId 派生，所以同一场练习问几次上下文都是同一个值——
            // 换一个就意味着复盘里的标记和这边对不上号。
            let requestID = "sync-\(session.id)"

            return try ToolJSON.text(Payload(
                sessionId: session.id,
                question: QuestionPayload(id: question.id, part: question.part, topic: question.topic,
                                          prompt: question.prompt, followups: question.followups),
                focusPart: session.focusPart.rawValue,
                durationMinutes: duration,
                goal: session.goal,
                feedbackTiming: timingRaw,
                part2PrepMode: prepRaw,
                examinerPrompt: ExaminerPrompt.build(setup: setup),
                reviewRequestId: requestID,
                reviewRequestPrompt: ReviewRequestPrompt.build(requestID: requestID,
                                                              focusPart: session.focusPart),
                activeTargets: RetrainingPolicy.rank(targets: state.targets, issues: state.issues)
                    .prefix(3)
                    .map { TargetPayload(id: $0.targetKey, label: $0.label, status: $0.status,
                                         evidence: $0.evidence) },
                recurringIssues: IssueRanking.top(state.issues, limit: 3)
                    .map { IssuePayload(learnerSaid: $0.learnerSaid, correction: $0.correction,
                                        occurrences: $0.occurrences) },
                note: "下一步：把 examinerPrompt 原样发给已经进入 Live 语音的 ChatGPT；"
                    + "练完再发 reviewRequestPrompt，然后把 ChatGPT 输出的整段复盘交给 save_session_review。"))
        }
    }
}
