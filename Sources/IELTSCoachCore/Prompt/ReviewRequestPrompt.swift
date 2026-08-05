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
        2. JSON 必须包含这些键：summary、must_correct、natural_upgrades、vocabulary、\
        habits、logic_feedback、answer_upgrades、priority_target。
        3. answer_upgrades 是数组，每项含 question、original_answer、revised_answer、changes。
        4. priority_target 只给一个，含 id、label、status、evidence。
        5. 只在有音频证据时给发音反馈；仅凭文本时该项写 "Not assessed from text"。
        6. 复盘的所有说明、点评、解释一律用中文；引用学员原话与给出的英文范例保持英文原文，不要翻译。

        \(open)
        {在这里输出 JSON}
        \(close)
        """
    }
}
