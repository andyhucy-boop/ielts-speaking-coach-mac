import Foundation

/// `coach prompt` 背后的那一点逻辑：把命令行给的一个 Part 记号，变成一份能直接打印的
/// 考官提示词。
///
/// ## 为什么要有这个命令
///
/// 提示词是这个工具唯一真正的产品——考官的每一句话都由它决定。而在这之前，
/// 想看一眼它长什么样只有两条路：真的驱动一次 ChatGPT（铁律 3 禁止），
/// 或者临时写一段探针代码跑完就删。结果是每次改提示词都靠脑补验证，
/// 2026-08-08 那次翻车（单练 Part 3 第一句问出 Part 1 的题）本来一眼就能看出来。
///
/// 所以它是排障工具，不是测试脚手架：用户自己也可以跑 `coach prompt --part 3`，
/// 把这一份完整读一遍，再决定要不要相信它。
///
/// ## 为什么逻辑放在 Core 而不是 `Sources/coach`
///
/// `coach` 是可执行 target，**没有测试 target**（见 `CoachCLIGuidanceTests` 的说明）。
/// 记号解析、示例题、时长这些东西留在那边就一行都测不到。命令行那边只留
/// 「读参数 → 调这里 → print」这一层皮。
public enum PromptPreview {

    /// 命令行上 `--part` 接受的写法 → `FocusPart`。
    ///
    /// 认得的写法刻意放宽：`3`、`part3`、`Part 3`、`2+3`、`mock` 都算。
    /// **认不出来必须返回 nil**，不许猜一个默认值糊弄过去——
    /// 用户想看 Part 3 却拿到一份 Part 1 的提示词，比直接报错糟糕得多。
    public static func focusPart(forToken token: String) -> FocusPart? {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "1", "part1": return .part1
        case "2", "part2": return .part2
        case "3", "part3": return .part3
        case "2+3", "23", "part2+3", "part2and3", "2and3": return .part2And3
        case "mock", "fullmock", "full", "4": return .fullMock
        default: return nil
        }
    }

    /// 用户在 `--part` 后面可以写什么。错误信息要把它逐字念出来（铁律 4：下一步得说得出口）。
    public static let acceptedPartTokens = ["1", "2", "3", "2+3", "mock"]

    /// 没给 `--question` 时用的示例题。
    ///
    /// **不是随便编的。** 三道题都照题库真实的建模长（见 `TopicQuestions`）：
    /// Part 1 / Part 3 是「一话题一题」，`prompt == topic`，`followups` 是参考问句池；
    /// Part 2 是一张 cue card，`followups` 是 `You should say` 的提示点。
    ///
    /// Part 3 那道刻意用了用户翻车当天那张卡的原文 `Describe a shop/store you enjoy visiting`：
    /// 它同时带着诱导性的 `Describe` 开头**和**一个斜杠，
    /// 所以 `coach prompt --part 3` 打出来的那一行主题，正好就是这次改动要验的东西。
    public static func sampleQuestion(for focusPart: FocusPart) -> Question {
        switch focusPart {
        case .part1:
            return TopicQuestions.part1(
                topic: "Borrowing and lending",
                prompts: ["Do you like to lend things to others?",
                          "Have you ever borrowed money from others?",
                          "How do you feel when someone does not return what they borrowed?",
                          "Would you lend your car to a friend?"])
        case .part2, .part2And3, .fullMock:
            return Question(
                id: "sample-p2-shop", part: 2, topic: "Places",
                prompt: "Describe a shop or store you enjoy visiting",
                followups: ["Where it is", "What it sells", "How often you go there",
                            "And explain why you enjoy visiting it"])
        case .part3:
            return TopicQuestions.part3(
                cueCard: "Describe a shop/store you enjoy visiting",
                prompts: ["How have shopping habits changed in your country in recent years?",
                          "Why do some people prefer small local shops to large chain stores?",
                          "What effect does online shopping have on small towns?",
                          "Do you think shops will still exist in fifty years? Why?"])
        }
    }

    /// 组装一份可以直接交给 `ExaminerPrompt.build` 的 setup。
    ///
    /// - Parameter question: `--question <id>` 从题库取到的题；`nil` 用示例题。
    ///
    /// 时长走 `FocusPart.defaultDurationMinutes`——**不能在这里另写一份数字**，
    /// 否则命令行打出来的提示词和真练时发出去的那一份会在时长上悄悄不一样，
    /// 而这个命令存在的全部意义就是「看到的就是发出去的」。
    public static func setup(focusPart: FocusPart, question: Question? = nil, goal: String = "",
                             feedbackTiming: FeedbackTiming = .deferred,
                             part2PrepMode: Part2PrepMode = .countdown) -> SessionSetup {
        SessionSetup(question: question ?? sampleQuestion(for: focusPart),
                     focusPart: focusPart,
                     durationMinutes: focusPart.defaultDurationMinutes,
                     goal: goal,
                     feedbackTiming: feedbackTiming,
                     part2PrepMode: part2PrepMode)
    }
}
