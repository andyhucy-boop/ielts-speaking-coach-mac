import Foundation

public struct SessionSetup: Equatable, Sendable {
    public let question: Question
    public let focusPart: FocusPart
    public let durationMinutes: Int
    public let goal: String               // 可为空

    public init(question: Question, focusPart: FocusPart, durationMinutes: Int, goal: String) {
        self.question = question
        self.focusPart = focusPart
        self.durationMinutes = durationMinutes
        self.goal = goal
    }
}

/// 考官提示词。正文依据上游 references/examiner-protocol.md。
/// 英文契约句必须逐字保留——它们直接决定 ChatGPT 是否进入考官角色。
public enum ExaminerPrompt {
    private static let contract = """
    You will act as an IELTS Speaking examiner. Stay neutral and concise. \
    Ask one question at a time. Do not correct, praise, explain, or teach until examiner mode ends.

    Before the first question, say exactly:
    "I will act as the examiner. I will save all feedback until the end. \
    If you are still thinking, continue speaking. Say 结束训练 whenever you want to stop."

    Turn handling:
    - Treat short hesitation as part of the learner's answer.
    - Do not verbally fill silence with encouragement.
    - If the turn is handed over too early, ask: "Would you like to continue?"
    - Interrupt only for time control or substantial off-topic drift.
    - Never promise an exact silence threshold; the Voice system controls turn detection.
    """

    private static let partRules: [FocusPart: String] = [
        .part1: """
        Section rules (Part 1):
        - Ask 6–10 short questions across 2–3 everyday topics.
        - Use limited natural follow-up when an answer contains a useful personal detail.
        - Keep the section conversational but neutral.
        """,
        .part2: """
        Section rules (Part 2):
        - Present one cue card.
        - Announce one minute of preparation and up to two minutes of speaking.
        - Do not supply content during preparation unless the learner requests practice support.
        - Ask one brief rounding-off question after the long turn.
        """,
        .part3: """
        Section rules (Part 3):
        - Start from the Part 2 theme when possible.
        - Generate follow-ups from the learner's actual claim, not only from a fixed list.
        - Move through explanation, comparison, causes, consequences, and evaluation.
        - Increase abstraction gradually.
        - If an answer is thin, probe with one neutral prompt such as "Why do you think that is?"
        """,
        .fullMock: """
        Section rules (full mock):
        - Run Part 1, Part 2, and Part 3 in order without pausing for feedback between them.
        - Apply each part's own timing and questioning rules.
        """
    ]

    private static let ending = """
    When the session ends, say exactly:
    "The simulation is complete. I am leaving examiner mode and preparing your structured review."
    Then wait. Do not produce the review until you receive an explicit review request.
    """

    public static func build(setup: SessionSetup) -> String {
        var blocks: [String] = [contract]

        // focusPart 现在是 FocusPart 枚举，穷尽后不存在未知值：partRules 覆盖了
        // FocusPart 的全部 case（ExaminerPromptTests 里有一条测试逐 case 验证），
        // 不再需要运行时兜底或 assertionFailure。
        blocks.append(partRules[setup.focusPart]!)

        var questionBlock = """
        Today's question (Part \(setup.question.part), topic: \(setup.question.topic)):
        \(setup.question.prompt)
        """
        if !setup.question.followups.isEmpty {
            questionBlock += "\n\nFollow-up points to cover:\n"
                + setup.question.followups.map { "- \($0)" }.joined(separator: "\n")
        }
        blocks.append(questionBlock)

        blocks.append("Target session length: about \(setup.durationMinutes) minutes.")

        let goal = setup.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty {
            blocks.append("""
            本次唯一目标：\(goal)
            考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
            """)
        }

        blocks.append(ending)
        return blocks.joined(separator: "\n\n---\n\n")
    }
}
