import Foundation

/// 「重点 Part」这件事的全部规则：挑哪些题、按什么顺序排、以及这个计划做不做得出来。
public enum PlanScope {

    // MARK: - 选题

    /// - 全真模考（三个 Part 全选）：把三个 Part 的题**交错**排开，每一天仍然练那道题
    ///   自己的 Part（`FocusPart.forSession` 那一侧保证）。
    /// - 其余组合档（1+2、1+3、2+3）：只排**开场那个 Part** 的题。
    ///
    ///   这一条原先是 `part2And3` 的专属规则，理由是题库里 Part 3 的题干就是它所属
    ///   cue card 的原文（`TopicQuestions.part3`），两批一起排会让同一张卡在计划里占掉两天。
    ///   推广到全部组合档之后规则更整齐，也和 `FocusPart.forSession` 对得上：
    ///   那边只在「题目正是这一档的第一段」时才让组合档生效，
    ///   这里要是排了别的 Part 的题，那些天会被静默降级成单 Part——
    ///   计划页写着「连着练」，实际每天只考一段。
    /// - 单 Part：就是那个 Part 的题。
    public static func select(from questions: [Question], focusPart: FocusPart) -> [Question] {
        if focusPart == .fullMock { return interleaveByPart(questions) }
        let opening = focusPart.openingPart.rawValue
        return questions.filter { $0.part == opening }
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

    /// 一个 Part 自己那句话。组合档的名字由它们拼出来，**不另写一份**：
    /// 两处各写各的话，「Part 2（个人陈述）」和「Part 2 + Part 3 连着练（先两分钟陈述…）」
    /// 迟早会用两种说法称呼同一段考试。
    private static func phrase(for part: ExamPart) -> String {
        switch part {
        case .one: return "日常话题问答"
        case .two: return "两分钟陈述"
        case .three: return "深入讨论"
        }
    }

    /// 重点 Part 的中文说明。界面与 Core 的错误信息共用这一份，避免两处文案漂移。
    ///
    /// 名字得让人一眼看懂这一档到底会发生什么：先做哪一段、再做哪一段。
    /// 只写「Part 2 + Part 3」的话，用户分不清它和「全真模考」差在哪儿。
    public static func label(for focusPart: FocusPart) -> String {
        if focusPart == .fullMock { return "全真模考（Part 1 + 2 + 3）" }
        let names = focusPart.parts.map(\.englishName).joined(separator: " + ")
        guard focusPart.isCombined else {
            // 单 Part 沿用原来那三句，一个字都没动——它们出现在学习计划页、
            // 生成失败的报错、以及开练弹层那句默认档位说明里。
            switch focusPart.openingPart {
            case .one: return "Part 1（日常话题问答）"
            case .two: return "Part 2（个人陈述）"
            case .three: return "Part 3（深入讨论）"
            }
        }
        let steps = focusPart.parts.map(phrase(for:)).joined(separator: "，再接着")
        return "\(names) 连着练（先\(steps)）"
    }
}
