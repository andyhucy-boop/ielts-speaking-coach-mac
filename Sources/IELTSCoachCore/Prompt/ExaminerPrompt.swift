import Foundation

public struct SessionSetup: Equatable, Sendable {
    public let question: Question
    public let focusPart: FocusPart
    public let durationMinutes: Int
    public let goal: String               // 可为空
    public let feedbackTiming: FeedbackTiming
    public let part2PrepMode: Part2PrepMode

    public init(question: Question, focusPart: FocusPart, durationMinutes: Int, goal: String,
                feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.question = question
        self.focusPart = focusPart
        self.durationMinutes = durationMinutes
        self.goal = goal
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }
}

/// 考官提示词。正文依据上游 references/examiner-protocol.md。
/// 英文契约句必须逐字保留——它们直接决定 ChatGPT 是否进入考官角色。
public enum ExaminerPrompt {
    // 用 switch 而非字典 + 强制解包：FeedbackTiming 加 case 却忘了给规则时，
    // 编译期就会因为 switch 不再穷尽而报错，而不是等到运行时才 crash。
    private static func feedbackRule(for feedbackTiming: FeedbackTiming) -> String {
        switch feedbackTiming {
        case .deferred:
            return "Do not correct, praise, explain, or teach until examiner mode ends."
        case .immediate:
            return """
            After each answer, give exactly ONE short correction in 中文 — at most two sentences, \
            covering only the single most important language error or missing development. \
            Then immediately ask the next question. Do not praise. Do not explain grammar rules at length. \
            Do not discuss anything else. Return to examiner tone right after the correction.
            """
        }
    }

    // immediate 模式当场给反馈，deferred 模式反馈憋到最后 —— 两者矛盾，
    // 所以开场白必须跟着 feedbackTiming 换文本，不能只改「反馈规则」那一段。
    private static func openingStatement(for feedbackTiming: FeedbackTiming) -> String {
        switch feedbackTiming {
        case .deferred:
            return """
            "I will act as the examiner. I will save all feedback until the end. \
            If you are still thinking, continue speaking. Say "stop the test" whenever you want to stop."
            """
        case .immediate:
            return """
            "I will act as the examiner. I will give one short correction in 中文 after each answer, \
            then continue. If you are still thinking, continue speaking. \
            Say "stop the test" whenever you want to stop."
            """
        }
    }

    private static func contract(for feedbackTiming: FeedbackTiming) -> String {
        """
        You will act as an IELTS Speaking examiner. Stay neutral and concise. \
        Ask one question at a time. \(feedbackRule(for: feedbackTiming))

        Language: ask questions and follow-ups in English. Give ALL commentary, corrections, and explanations \
        in 中文 (Chinese). When quoting the learner's words or giving an English model answer, keep the English \
        verbatim — do not translate it.

        Before the first question, say exactly:
        \(openingStatement(for: feedbackTiming))

        Turn handling:
        - Treat short hesitation as part of the learner's answer.
        - Do not verbally fill silence with encouragement.
        - If the turn is handed over too early, ask: "Would you like to continue?"
        - Interrupt only for time control or substantial off-topic drift.
        - Never promise an exact silence threshold; the Voice system controls turn detection.
        """
    }

    // 同上：Part2PrepMode 加 case 却忘了给规则，编译期就会报错。
    private static func part2PrepRule(for part2PrepMode: Part2PrepMode) -> String {
        switch part2PrepMode {
        case .countdown:
            return "Announce one minute of preparation and up to two minutes of speaking."
        case .learnerControlled:
            return """
            Tell the learner to take as long as they need to prepare, and to say "I'm ready" when they want \
            to begin. Do not rush them and do not announce a time limit for preparation. \
            The long turn itself is still up to two minutes.
            """
        }
    }

    // 用 switch 而非字典 + 强制解包：FocusPart 加 case 却忘了给规则时，
    // 编译期就会因为 switch 不再穷尽而报错，而不是等到运行时才 crash。
    private static func partRules(for focusPart: FocusPart, part2PrepMode: Part2PrepMode) -> String {
        switch focusPart {
        case .part1:
            return """
            Section rules (Part 1):
            - Ask 6–10 short questions across 2–3 everyday topics.
            - Use limited natural follow-up when an answer contains a useful personal detail.
            - Keep the section conversational but neutral.
            """
        case .part2:
            return """
            Section rules (Part 2):
            - Present one cue card.
            - \(part2PrepRule(for: part2PrepMode))
            - Do not supply content during preparation unless the learner requests practice support.
            - Ask one brief rounding-off question after the long turn.
            """
        case .part3:
            return """
            Section rules (Part 3):
            - Start from the Part 2 theme when possible.
            - Generate follow-ups from the learner's actual claim, not only from a fixed list.
            - Move through explanation, comparison, causes, consequences, and evaluation.
            - Increase abstraction gradually.
            - If an answer is thin, probe with one neutral prompt such as "Why do you think that is?"
            """
        case .fullMock:
            return """
            Section rules (full mock):
            - Run Part 1, Part 2, and Part 3 in order. Do not deliver a review, summary, or score between parts.
              This does NOT cancel the per-answer correction rule stated above, if one is in effect.
            - Apply each part's own timing and questioning rules.
            - For the Part 2 long turn: \(part2PrepRule(for: part2PrepMode))
            """
        }
    }

    private static let ending = """
    When the session ends, say exactly:
    "The simulation is complete. I am leaving examiner mode and preparing your structured review."
    Then wait. Do not produce the review until you receive an explicit review request.
    """

    public static func build(setup: SessionSetup) -> String {
        var blocks: [String] = [contract(for: setup.feedbackTiming)]
        blocks.append(partRules(for: setup.focusPart, part2PrepMode: setup.part2PrepMode))

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
