import Foundation

/// 语音结束后追发的复盘请求。输出格式必须与 ReviewParser 能识别的定界块严格一致。
public enum ReviewRequestPrompt {
    public static func marker(requestID: String) -> (open: String, close: String) {
        ("<<<IELTS_REVIEW_JSON:\(requestID)>>>", "<<<END_IELTS_REVIEW_JSON:\(requestID)>>>")
    }

    public static func build(requestID: String, focusPart: FocusPart) -> String {
        let (open, close) = marker(requestID: requestID)
        return """
        [SYNC_REQUEST_ID:\(requestID)]

        考官模式结束。现在基于刚才的完整对话生成结构化复盘。

        \(AnswerUpgradePolicy.guidance(part: focusPart.rawValue))

        输出要求：
        1. 只输出一个 JSON 对象，用下面两行标记严格包裹，标记前后不要有任何其他文字。
        2. JSON 必须是一个对象，含且仅含这些顶层键：summary、must_correct、natural_upgrades、\
        vocabulary、habits、logic_feedback、answer_upgrades、priority_target。
        3. 每个键的结构必须严格如下，字段名一个字都不能改：
           - summary：字符串
           - must_correct：数组，每项 {"learner_said": 学员原话, "correction": 改正后的说法, \
        "why_it_matters": 为什么重要}
           - natural_upgrades：数组，每项 {"learner_said": 学员原话, "more_natural": 更地道的说法, \
        "usage_note": 用法说明}
           - vocabulary：**数组**（不是对象），每项 {"basic": 学员用的词, "better": 更准确的表达, \
        "collocation": 搭配或例句, "priority": "high"/"medium"/"low"}
           - habits：数组，每项 {"habit": 习惯描述, "evidence": 例证}
           - logic_feedback：数组，每项 {"question": 题目, "issue": 问题, "improvement": 改进方向}
           - answer_upgrades：数组，每项 {"question": 题目, "original_answer": 原回答, \
        "revised_answer": 高分版, "changes": 中文说明的数组}
           - priority_target：对象 {"id": 短标识, "label": 目标描述, "status": "new", \
        "evidence": 学员原话的数组}
        4. **vocabulary 必须是数组，不是对象**——曾经实测 ChatGPT 把它输出成 \
        {"useful_replacements": ..., "pronunciation": ...} 这样的对象，导致这次练习完全没能归档。
        5. priority_target 只给一个。
        6. 只在有音频证据时给发音反馈；仅凭文本时该项写 "Not assessed from text"。
        7. 复盘的所有说明、点评、解释一律用中文；引用学员原话与给出的英文范例保持英文原文，不要翻译。

        \(open)
        {在这里输出 JSON}
        \(close)
        """
    }
}
