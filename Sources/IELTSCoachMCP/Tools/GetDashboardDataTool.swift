import Foundation
import IELTSCoachCore

enum GetDashboardDataTool {
    /// 「值可能没有，但键必须在」。
    ///
    /// Swift 合成的 `Encodable` 对 Optional 属性走的是 `encodeIfPresent`：
    /// 值为 nil 时**整个键会从 JSON 里消失**，而不是编成 `null`
    /// （`CoachState.encode(to:)` 手写的那一段就是为了同一件事）。
    /// 键消失意味着「还没有学习计划」与「这个工具忘了返回计划」在负载上长得一模一样，
    /// 模型没有任何办法区分。用它把 nil 如实编成 `null`，键的集合就永远稳定。
    private struct AlwaysPresent<Wrapped: Encodable>: Encodable {
        let value: Wrapped?
        init(_ value: Wrapped?) { self.value = value }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            if let value { try container.encode(value) } else { try container.encodeNil() }
        }
    }

    private struct QuestionBrief: Encodable {
        let id: String
        let part: Int
        let topic: String
        let prompt: String
    }

    private struct IssueBrief: Encodable {
        let learnerSaid: String
        let correction: String
        let occurrences: Int
        let lastSeenAt: String
    }

    private struct TargetBrief: Encodable {
        let id: String
        let label: String
        let status: String
        let evidence: [String]
    }

    private struct PlanBrief: Encodable {
        let lengthDays: Int
        let completedDays: Int
        /// 计划全部做完时为 null——键不许消失，理由见 AlwaysPresent。
        let currentDay: AlwaysPresent<Int>
    }

    private struct Payload: Encodable {
        let learnerName: String
        let dataDirectory: String
        let questionTotal: Int
        let questionPracticed: Int
        let sessionTotal: Int
        let weekDone: Int
        let weekGoal: Int
        /// 读不出练习时间、因此没算进 weekDone 的场次数。非 0 时 note 里必须解释。
        let undatedSessionCount: Int
        let issueTotal: Int
        let vocabularyTotal: Int
        /// 还没有计划时为 null——键不许消失，理由见 AlwaysPresent。
        let plan: AlwaysPresent<PlanBrief>
        let todayQuestions: [QuestionBrief]
        let topIssues: [IssueBrief]
        let nextTargets: [TargetBrief]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "get_dashboard_data",
            description: "取训练总览：题库与练习数量、本周进度、计划走到第几天、"
                + "今天该练的题、反复出现的错题、下次的复训目标。不需要参数。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ) { _ in
            let state = try environment.store.load()
            // 统计逻辑一行都不在这里——全在 Core 的 DashboardSummary，
            // Phase 7 的首页会用同一套。这里只做「调一次 + 编码 + 写一句下一步」。
            let summary = DashboardSummary.build(state: state, now: environment.now())

            let todayQuestions = (summary.plan?.todayQuestionIds ?? []).compactMap { id in
                state.questions.first { $0.id == id }
            }.map { QuestionBrief(id: $0.id, part: $0.part, topic: $0.topic, prompt: $0.prompt) }

            var note: String
            if summary.questionTotal == 0 {
                note = "题库还是空的，现在还没法开练。下一步：在 App 的「训练题库」页导入题库文件，"
                    + "或在终端运行 coach questions import <文件>。"
            } else if summary.plan == nil {
                note = "还没有学习计划。下一步：可以直接用 set_training_selection 挑一道题开练。"
            } else {
                note = "下一步：用 set_training_selection 选定 todayQuestions 里的一道题，"
                    + "再用 get_training_context 取考官提示词。"
            }
            // 本周次数可能算少了。少了就必须说，且要说下一步怎么补（铁律 6、7）。
            note += summary.warnings.joined()

            return try ToolJSON.text(Payload(
                learnerName: state.learner.displayName,
                dataDirectory: environment.directory.root.path,
                questionTotal: summary.questionTotal,
                questionPracticed: summary.questionPracticed,
                sessionTotal: summary.sessionTotal,
                weekDone: summary.weekDone,
                weekGoal: summary.weekGoal,
                undatedSessionCount: summary.undatedSessionCount,
                issueTotal: summary.issueTotal,
                vocabularyTotal: summary.vocabularyTotal,
                plan: AlwaysPresent(summary.plan.map {
                    PlanBrief(lengthDays: $0.lengthDays, completedDays: $0.completedDays,
                              currentDay: AlwaysPresent($0.currentDay))
                }),
                todayQuestions: todayQuestions,
                topIssues: summary.topIssues.map {
                    IssueBrief(learnerSaid: $0.learnerSaid, correction: $0.correction,
                               occurrences: $0.occurrences, lastSeenAt: $0.lastSeenAt)
                },
                nextTargets: summary.nextTargets.map {
                    TargetBrief(id: $0.targetKey, label: $0.label, status: $0.status,
                                evidence: $0.evidence)
                },
                note: note))
        }
    }
}
