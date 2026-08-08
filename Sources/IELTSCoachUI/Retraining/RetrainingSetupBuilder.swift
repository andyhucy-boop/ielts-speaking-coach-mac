import Foundation
import IELTSCoachCore

/// 把一个复训目标 + 一道题，变成一次**复训会话**的 `SessionSetup`。
///
/// 复训与普通练习的唯一区别就在 `goal`：`ExaminerPrompt` 在 goal 非空时会追加
/// 「本次唯一目标：…」一段，并要求考官不在考试过程中提及它、也不因此改变提问方式。
/// 后半句同样要紧：**目标是给考官看的，不是念给学员听的**——考官一开口说出来，
/// 等于提前把答案给了学员，这场复训就分不出「真会了」和「被提示了」。
///
/// **不要为复训改 `ReviewRequestPrompt`。** 那份指令把八个顶层键与每项内部的字段名
/// 全写死了，`ReviewArchiver` 逐字对着它读；动它一句就可能让 ChatGPT 顺手改动输出形状，
/// 而这种失败不报错、不崩溃，只是悄悄什么都没归档（spec 2.3.8）。
public enum RetrainingSetupBuilder {
    /// 单点目标的文本。
    ///
    /// **label 为空时退回 targetKey**：`RetrainingPolicy.extractTarget` 只强制 id 非空，
    /// label 是允许为空的。goal 一旦是空串，`ExaminerPrompt` 就不会追加目标段落，
    /// 这场「复训」会静默退化成普通练习——不报错、界面照常，只是和复训毫无关系。
    public static func goalText(for target: RetrainingTarget) -> String {
        let label = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty
            ? target.targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
            : label
    }

    public static func makeSetup(target: RetrainingTarget,
                                 question: Question,
                                 feedbackTiming: FeedbackTiming = .deferred,
                                 part2PrepMode: Part2PrepMode = .countdown) -> SessionSetup {
        // 越界的 part（手改坏的 state.json）落到 full mock，不让脏数据把复训整场卡死。
        //
        // **复训刻意不带「Part 2 + Part 3 连着练」这一档。** 复训是回去改一个具体的毛病
        //（`goal`），越短越集中越好；而且这条路线有两个入口——复训中心和今日训练页的
        // `PracticeRouteResolver.resolveRetrain`——两处都按题目自身的 Part 走，
        // 才不会出现「从这个入口进是 9 分钟的 2+3、从那个入口进是 4 分钟的 Part 2」。
        let focusPart = FocusPart.inferred(fromQuestionPart: question.part)
        return SessionSetup(question: question,
                            focusPart: focusPart,
                            // 与 coach practice 的既有取值一致：Part 2 是一段长答，4 分钟；其余 6 分钟。
                            durationMinutes: focusPart.defaultDurationMinutes,
                            goal: goalText(for: target),
                            feedbackTiming: feedbackTiming,
                            part2PrepMode: part2PrepMode)
    }
}
