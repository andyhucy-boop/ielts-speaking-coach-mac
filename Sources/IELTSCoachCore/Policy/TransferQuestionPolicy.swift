import Foundation

public struct TransferCandidate: Equatable, Sendable, Identifiable {
    public let question: Question
    /// 与原题同一个话题。仍然可以练，但界面必须标出来——同话题换题的验证力度打折。
    public let sameTopicAsOriginal: Bool

    public init(question: Question, sameTopicAsOriginal: Bool) {
        self.question = question
        self.sameTopicAsOriginal = sameTopicAsOriginal
    }

    public var id: String { question.id }
}

/// 「同一目标换一道题再练」的候选题挑选。
///
/// **这是整个 Phase 6 的价值所在**（DEFINITION-OF-DONE 第 2 节）：
/// 只重练原题，分不清是真会了还是只记住了那个答案。
public enum TransferQuestionPolicy {
    /// 规则顺序即优先级：
    /// 1. 排除原题本身
    /// 2. 排除已经为**这个目标**练过的题
    /// 3. 只在同一个 Part 内换（Part 1 要短、Part 3 要展开，标准不同）
    /// 4. 话题与原题不同的排前面；同话题的保留但打标
    /// 5. 其余保持题库原有顺序，保证界面每次打开顺序一样
    public static func candidates(for target: RetrainingTarget,
                                  originalQuestion: Question,
                                  questions: [Question],
                                  sessions: [PracticeSession]) -> [TransferCandidate] {
        // 按 targetID 匹配，不是按 targetKey：别的目标练过这道题不该影响这个目标。
        let alreadyUsed = Set(
            sessions.filter { $0.retraining?.targetID == target.id }.map(\.questionId))
        let originalTopic = normalized(originalQuestion.topic)

        return questions.enumerated()
            .filter { $0.element.part == originalQuestion.part }
            .filter { $0.element.id != originalQuestion.id }
            .filter { !alreadyUsed.contains($0.element.id) }
            .map { entry in
                (offset: entry.offset,
                 candidate: TransferCandidate(
                    question: entry.element,
                    sameTopicAsOriginal: normalized(entry.element.topic) == originalTopic))
            }
            .sorted { left, right in
                if left.candidate.sameTopicAsOriginal != right.candidate.sameTopicAsOriginal {
                    return !left.candidate.sameTopicAsOriginal   // 换话题的排前面
                }
                return left.offset < right.offset               // 同档保持题库原有顺序
            }
            .map(\.candidate)
    }

    /// 话题比对要忽略大小写与前后空白：题库来自 CSV/JSON/PDF 三条导入路径，
    /// 同一个话题写成 "Home" / "home" / " Home " 都很常见，
    /// 按字面比会把同话题误判成换了话题，让验证形同虚设。
    private static func normalized(_ topic: String) -> String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
