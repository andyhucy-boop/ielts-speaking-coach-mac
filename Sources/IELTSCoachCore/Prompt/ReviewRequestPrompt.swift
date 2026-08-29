import Foundation

/// 语音结束后追发的复盘请求。输出格式必须与 ReviewParser 能识别的定界块严格一致。
public enum ReviewRequestPrompt {
    public static func marker(requestID: String) -> (open: String, close: String) {
        ("<<<IELTS_REVIEW_JSON:\(requestID)>>>", "<<<END_IELTS_REVIEW_JSON:\(requestID)>>>")
    }

    /// **上一份复盘格式不对时再问一次**，并且告诉它上次错在哪。
    ///
    /// 原样再发一遍同一份提示词是白发一次：ChatGPT 手上没有任何新信息，
    /// 多半会给出同样形状的输出。上游在同一处的做法是把校验器的具体报错回喂给模型，
    /// 让它自己修——这里照做。
    ///
    /// **那句话必须排在最前面。** 排在一千多字的格式要求后面的话，它会被淹掉；
    /// 而「不要重复上一条回复」正是这一次要它做的唯一一件不同的事。
    ///
    /// - Parameter problem: 解析器给出的诊断（例如「没有返回可识别的标准复盘 JSON」）。
    ///   **原样转给 ChatGPT**，不要翻译成别的说法——它是唯一的新信息。
    public static func retry(requestID: String, focusPart: FocusPart, problem: String) -> String {
        """
        你上一条回复的格式不对：\(problem)

        不要重复上一条回复，也不要为此道歉或解释。现在重新输出一次，
        **只输出被下面两行标记严格包裹的那一个 JSON 对象**，标记前后不要有任何其他文字。
        内容仍然基于刚才那一整场对话，要求与下面完全一致。

        ---

        \(build(requestID: requestID, focusPart: focusPart))
        """
    }

    public static func build(requestID: String, focusPart: FocusPart) -> String {
        let (open, close) = marker(requestID: requestID)
        return """
        [SYNC_REQUEST_ID:\(requestID)]

        考官模式结束。现在基于刚才的完整对话生成结构化复盘。

        \(AnswerUpgradePolicy.guidance(part: focusPart.rawValue))

        输出要求：
        1. 只输出一个 JSON 对象，用下面两行标记严格包裹，标记前后不要有任何其他文字。
        2. JSON 必须是一个对象，含且仅含这些顶层键：summary、strengths、must_correct、\
        natural_upgrades、vocabulary、habits、logic_feedback、content_feedback、\
        answer_upgrades、priority_target。
        3. 每个键的结构必须严格如下，字段名一个字都不能改：
           - summary：字符串
           - strengths：数组，最多 3 项，每项 {"learner_said": 他说得好的那句原话, \
        "why_it_works": 这句好在哪}
           - must_correct：数组，每项 {"learner_said": 学员原话, "correction": 改正后的说法, \
        "why_it_matters": 为什么重要, "mini_drill": 一个 30 秒就能练一遍的开口练法}
           - natural_upgrades：数组，每项 {"learner_said": 学员原话, "more_natural": 更地道的说法, \
        "usage_note": 用法说明}
           - vocabulary：**数组**（不是对象），每项 {"basic": 学员用的词, "better": 更准确的表达, \
        "collocation": 搭配或例句, "priority": "high"/"medium"/"low"}
           - habits：数组，每项 {"habit": 习惯描述, "evidence": 例证, "fix": 下次怎么改}
           - logic_feedback：数组，每项 {"question": 题目, "issue": 问题, "improvement": 改进方向}
           - content_feedback：数组，最多 3 项，每项 {"thin_spot": 他说空了的那句原话, \
        "add_this": 可以补哪一类内容, "example": 一句可以直接说的英文示范}
           - answer_upgrades：数组，每项 {"question": 题目, "original_answer": 原回答, \
        "revised_answer": 高分版, "changes": 中文说明的数组}
           - priority_target：对象 {"id": 短标识, "label": 目标描述, "status": "new", \
        "evidence": 学员原话的数组, "success_behavior": 下次怎么算做到了（一句可自查的具体行为）}
        4. **vocabulary 必须是数组，不是对象**——曾经实测 ChatGPT 把它输出成 \
        {"useful_replacements": ..., "pronunciation": ...} 这样的对象，导致这次练习完全没能归档。
        5. **content_feedback 讲的是「内容」，不是「英文」。** 它要回答的是：他这段话说得空不空。\
        判据是内容有没有落到实处——有没有具体的人、事、地点、时间、数字、对比、亲身细节；\
        有没有给出理由；有没有举例；观点是不是含糊到换一道题也能照说一遍。\
        thin_spot 直接引用他当时那句说空了的原话（英文原文，不要翻译），别写成泛泛的评语；\
        add_this 说的是「补哪一类内容」（例如「补一个具体场合」「补一条相反的看法再反驳它」），\
        不是「说得再多一点」；example 给一句他可以直接开口说的英文。\
        **不许替他编个人经历**：不得凭空添人物、地点、日期、学校、工作、旅行、家庭关系或具体事件；\
        需要个人细节而证据不足时，example 用不冒充亲身经历的通用或假设说法，\
        并在 add_this 里写明「示范补充，请按真实情况调整」。\
        最多给 3 项，最空的排最前面。这一场内容确实没有明显空洞时给空数组，不要硬凑。\
        与 logic_feedback 分工固定：logic_feedback 管条理（有没有先正面回答、顺序乱不乱），\
        content_feedback 管内容本身（有没有东西可说）。两项不要写重复的话。
        6. **只用逐字稿里真的出现过的话。** 不许把没说过的句子写成他的原话，
        也不许凭「他大概会这么说」编一条来凑数。语音转写把中国考生的话听岔一个词是常态，
        所以：**拿不准那句到底是不是他说的，就在该项的原话后面加一句「（待核实）」**，
        并且**不要**拿这种拿不准的句子当 priority_target 的证据。
        听岔的一句话被写成 must_correct，会让他去改一个自己根本没犯的毛病，
        而那条错误会永久进错题本、还可能当场变成他下一场唯一要盯的目标。
        7. **must_correct 只收真的错**（语法、用词、搭配确实不对）。
        「这样说更自然」「换个词更准」一律放 natural_upgrades 或 vocabulary，
        **不许混进 must_correct**——混进来的会被当成他犯过的错记进错题本、参与复训排序。
        8. **strengths 必须引他真说过的原话**，最多 3 条，每条一句话说清好在哪。
        这一场确实没什么可夸的就给空数组，**不要硬夸**——空洞的表扬比不表扬更糟。
        它不是打分，是告诉他哪几个说法可以固定下来接着用。
        9. **mini_drill 是「现在张嘴练什么」，不是「记住这条规则」。**
        写成一个 30 秒之内能练一遍的动作，例如「把刚才那句用 I've been 开头说三遍」。
        写不出具体动作时给空字符串，不要写「多加练习」这种等于没说的话。
        10. priority_target 只给一个，且 success_behavior 必须是**他自己能当场自查**的行为，
        例如「每个回答里都出现一次 This is mainly because」，
        不能是「提高词汇量」这种没法判断做没做到的空目标。
        11. 复盘的所有说明、点评、解释一律用中文；引用学员原话与给出的英文范例保持英文原文，不要翻译。
        12. **不要给任何形式的雅思分数、评级或水平判断**：不要写 band、不要写「大概 6.5」\
        「相当于 7 分水平」，也不要按词数、流利度推断分数。summary 里同样一个字都不许出现——\
        它要说的是「哪里已经稳了、哪里还不稳」，不是打一个分。\
        这个数字既不准也有害，会让学员盯着数字而不是盯着具体哪句话该怎么改。

        \(open)
        {在这里输出 JSON}
        \(close)
        """
    }
}
