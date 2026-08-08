import Foundation

/// 「重点 Part」这件事的全部规则：挑哪些题、按什么顺序排、以及这个计划做不做得出来。
public enum PlanScope {

    // MARK: - 选题

    public static func select(from questions: [Question], focusPart: FocusPart) -> [Question] {
        switch focusPart {
        case .part1: return questions.filter { $0.part == 1 }
        case .part2: return questions.filter { $0.part == 2 }
        case .part3: return questions.filter { $0.part == 3 }
        // 「Part 2 + Part 3 连着练」排的就是 Part 2 的那些 cue card，和 `.part2` 挑的是同一批题。
        // **两档的区别不在挑哪些题，而在怎么练那一道题**：这一档每天那道 cue card 做完两分钟
        // 陈述之后，会接着做一段 Part 3 讨论（`ExaminerPrompt` 的 `.part2And3` 规则）。
        // Part 3 那批题在这里刻意不排：它们的题干本来就是 Part 2 cue card 的原文，
        // 排进来会让同一张卡在计划里出现两天。
        case .part2And3: return questions.filter { $0.part == 2 }
        case .fullMock: return interleaveByPart(questions)
        }
    }

    /// 全真模考：按 Part 1 → Part 2 → Part 3 轮转交错，各 Part 内部保持题库原有顺序。
    /// 某个 Part 先用完就跳过它继续轮转。
    ///
    /// 不交错的话，题库的自然顺序（导入器先写完整块 Part 1、再写 Part 2/3）会让
    /// 7 天计划的前几天全是 Part 1、最后几天全是 Part 3——那不叫全真模考。
    ///
    /// part 落在 1–3 之外的脏数据（手改过的 state.json）排在最后，**不丢弃**：
    /// 全真模考的语义是「题库里的全部题目」，悄悄少排几道是静默失败。
    private static func interleaveByPart(_ questions: [Question]) -> [Question] {
        var buckets: [[Question]] = [[], [], []]      // 下标 0/1/2 对应 Part 1/2/3
        var unknown: [Question] = []
        for question in questions {
            if (1...3).contains(question.part) { buckets[question.part - 1].append(question) }
            else { unknown.append(question) }
        }

        var result: [Question] = []
        var cursors = [0, 0, 0]
        var advanced = true
        while advanced {
            advanced = false
            for index in 0..<3 where cursors[index] < buckets[index].count {
                result.append(buckets[index][cursors[index]])
                cursors[index] += 1
                advanced = true
            }
        }
        return result + unknown
    }

    // MARK: - 可行性

    /// 返回 nil 表示这个计划做得出来；否则返回中文说明（发生了什么 + 下一步做什么）。
    ///
    /// **生成前的预览与真正生成时必须用同一个判据**，否则会出现
    /// 「预览说能生成、点下去却报错」——最伤信任的一类界面缺陷。
    /// 所以真正生成路径上的每一道闸门都必须在这里有对应的一条，
    /// 包括 `PlanBuilder.build` 的天数闸门（下面第一条）。
    public static func blockingReason(questionCount: Int, lengthDays: Int,
                                      focusPart: FocusPart) -> String? {
        // 顺序与 PlanBuilder.build 里的 guard 一致：先看天数，再看题目。
        guard PlanBuilder.supportedLengths.contains(lengthDays) else {
            return unsupportedLengthReason(lengthDays: lengthDays)
        }
        guard questionCount > 0 else {
            return "题库里没有\(label(for: focusPart))的题目，生成不了计划。"
                + "下一步：换一个重点 Part，或到「训练题库」页导入含该 Part 的题目。"
        }
        guard questionCount < lengthDays else { return nil }

        // 题数少于天数时 PlanBuilder 会给尾部若干天分 0 题，而空天的 isComplete
        // 永远是 false —— 那样的计划永远显示不出「已完成」，用户会一直以为自己还差一点。
        let advice: String
        if let usable = PlanBuilder.supportedLengths.filter({ $0 <= questionCount }).max() {
            advice = "下一步：把周期改成 \(usable) 天，或先到「训练题库」页导入更多题目。"
        } else {
            advice = "下一步：到「训练题库」页导入更多题目——最短的 7 天计划也需要至少 7 道题。"
        }
        return "\(label(for: focusPart))现在只有 \(questionCount) 道题，分不满 \(lengthDays) 天，"
            + "会有整天没题可练。\(advice)"
    }

    // MARK: - 文案

    /// 天数不在 `PlanBuilder.supportedLengths` 里时的中文说明。
    /// `PlanBuilder.build` 兜底时也用这一份，避免同一件事在两处写出两种说法。
    static func unsupportedLengthReason(lengthDays: Int) -> String {
        let supported = PlanBuilder.supportedLengths.map(String.init).joined(separator: "、")
        return "计划天数只支持 \(supported) 天，现在选的是 \(lengthDays) 天，生成不了计划。"
            + "下一步：把周期改成 \(supported) 天中的一档。"
    }

    /// 重点 Part 的中文说明。界面与 Core 的错误信息共用这一份，避免两处文案漂移。
    public static func label(for focusPart: FocusPart) -> String {
        switch focusPart {
        case .part1: return "Part 1（日常话题问答）"
        case .part2: return "Part 2（个人陈述）"
        case .part3: return "Part 3（深入讨论）"
        // 名字得让人一眼看懂这一档到底会发生什么：先做哪一段、再做哪一段。
        // 只写「Part 2 + Part 3」的话，用户分不清它和「全真模考」差在哪儿。
        case .part2And3: return "Part 2 + Part 3 连着练（先两分钟陈述，再接着讨论）"
        case .fullMock: return "全真模考（Part 1 + 2 + 3）"
        }
    }
}
