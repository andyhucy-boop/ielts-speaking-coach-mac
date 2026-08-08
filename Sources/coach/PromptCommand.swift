import Foundation
import IELTSCoachCore

/// `coach prompt` —— 把发给 ChatGPT 的那份考官提示词原样打印出来，**不碰 ChatGPT**。
///
/// 逻辑全在 `PromptPreview`（Core，有测试）。这里只做三件事：读参数、取题、print。
enum PromptCommand {
    static func run(_ args: [String]) -> Int32 {
        let partToken = valueFor("--part", in: args) ?? "3"
        guard let focusPart = PromptPreview.focusPart(forToken: partToken) else {
            print("❌ 认不出 --part 的取值「\(partToken)」，没有打印任何提示词。")
            print("   下一步：改成这几个之一 —— "
                + PromptPreview.acceptedPartTokens.joined(separator: " / ")
                + "，例如 coach prompt --part 3")
            return 2
        }

        let feedbackTiming: FeedbackTiming = args.contains("--immediate") ? .immediate : .deferred
        let prepMode: Part2PrepMode = args.contains("--self-paced") ? .learnerControlled : .countdown
        let goal = valueFor("--goal", in: args) ?? ""

        var question: Question?
        // 题库整份带着走，不只带那一道题：同时含 Part 2 与 Part 3 的那几档要靠它
        // 配出「这张 cue card 自己那组 Part 3 追问」（`LinkedPart3`）。
        // 只取一道题的话，`coach prompt` 打出来的永远是「配不上」那句兜底，
        // 而真练时是配得上的——这个命令存在的意义（看到的就是发出去的）当场作废。
        var bank: [Question] = []
        if let questionID = valueFor("--question", in: args) {
            let store = StateStore(directory: DataDirectory.resolve())
            do {
                let loaded = try store.load().questions
                bank = loaded
                guard let found = loaded.first(where: { $0.id == questionID })
                else {
                    print("❌ 题库里没有 id 为「\(questionID)」的题目，没有打印任何提示词。")
                    print("   下一步：coach questions list 查看可用题目；"
                        + "或者去掉 --question，用内置示例题看这一档的提示词长什么样。")
                    return 1
                }
                question = found
            } catch {
                print("❌ 读不出题库：\(error.localizedDescription)")
                print("   下一步：去掉 --question 就能用内置示例题打印提示词，不需要题库；"
                    + "要用自己的题，先运行 coach doctor 看数据目录是不是好的。")
                return 1
            }
        }

        let setup = PromptPreview.setup(focusPart: focusPart, question: question, bank: bank,
                                        goal: goal,
                                        feedbackTiming: feedbackTiming, part2PrepMode: prepMode)
        // 题目来源要写清楚：拿示例题打印出来的提示词，和用户自己那道题的提示词并不完全一样
        // （题干、参考问句都不同）。不说明的话，他会以为自己在看真练时的那一份。
        let origin = question == nil ? "内置示例题" : "题库里的 \(setup.question.id)"
        print("# \(focusPart.rawValue) 的考官提示词（题目：\(origin)；"
            + "反馈：\(feedbackTiming == .immediate ? "当场点评" : "留到最后")；"
            + "时长：\(setup.durationMinutes) 分钟）")
        print("# 这就是练习开始时发给 ChatGPT 的原文，一个字都没改。")
        print("")
        print(ExaminerPrompt.build(setup: setup))
        return 0
    }

    private static func valueFor(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
