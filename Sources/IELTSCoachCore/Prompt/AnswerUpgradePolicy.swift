import Foundation

/// 回答升级规则。正文逐字移植自上游 desktop/answer-upgrade-policy.mjs。
/// 这段文本直接决定 ChatGPT 的输出行为，除非同步修改上游，否则不得改写措辞。
public enum AnswerUpgradePolicy {
    private static let part1Guidance =
        "Part 1：回答应简短、直接、自然。练习目标通常为2至4句、约20至40词；先回答，再给一个简短原因或具体说明。不要把日常短问答扩写成演讲。"
    private static let part2Guidance =
        "Part 2：官方流程是一分钟准备、最多两分钟陈述。高分建议答案应形成连贯长答；在原回答证据允许时，以约90至120秒、约170至240词为练习目标，覆盖提示点并有清晰时间线或主题线。若真实个人信息不足，宁可略短并指出待补信息，也不能虚构经历。"
    private static let part3Guidance =
        "Part 3：回答应比Part 1更抽象、更充分。练习目标通常为4至7句、约60至120词；形成观点、原因、解释或例子，并可加入对比、条件或让步。篇幅服从问题复杂度，不机械凑词数。"

    private static let partGuidance: [String: String] = [
        "Part 1": part1Guidance,
        "Part 2": part2Guidance,
        "Part 3": part3Guidance,
        // 「Part 2 + Part 3 连着练」这一场里两种题型都出现过，复盘要按各自的标准改各自那几题。
        // **两段原文逐字拼起来，不另写一份**：这三段是从上游 desktop/answer-upgrade-policy.mjs
        // 移植来的，措辞不许改写；另写一份「综合标准」等于凭空发明第四套长度要求。
        //
        // 不走 fallbackRule 是因为那一句只说「先根据问题所属Part选择对应长度」，
        // 三个 Part 各自的目标句数、词数一个都没给——而这一场恰恰知道自己只会出现哪两种。
        FocusPart.part2And3.rawValue: "\(part2Guidance)\n\n\(part3Guidance)"
    ]

    private static let fallbackRule =
        "先根据问题所属Part选择对应长度：Part 1简短直接；Part 2形成最多两分钟的长答；Part 3进行较充分的解释与论证。"

    private static let sharedRules = """
    逐题高分版生成规则：
    1. original_answer必须忠实保留考生原回答；revised_answer必须保留考生已经表达的立场和全部个人事实。
    2. 原回答明显过短或展开不足时，可以主动补充由原观点自然推导出的原因、影响、解释、对比、条件或让步，也可以加入明确属于一般情况或假设情境的例子。
    3. 不得把补充内容伪装成考生亲身事实：不得擅自新增人物、地点、日期、学校、工作、成绩、旅行、家庭关系、具体事件或个人偏好。需要个人细节但证据不足时，使用不冒充个人经历的通用或假设表达；Part 2若因此无法安全达到目标长度，应保持较短。
    4. changes必须用中文明确列出补充了什么；若建议答案包含需要考生按真实情况确认或替换的内容，必须写明“示范补充，请按真实情况调整”。
    5. 提升语法范围时自然混合简单句与复杂句，可使用从句、条件句、让步、比较或分词结构，但不要为了复杂而牺牲口语自然度。
    6. 词汇升级优先选准确搭配、自然短语动词和口语表达。只有高度贴合语境时才加入少量地道或习语表达；不得硬塞俚语、冷僻词、背诵腔或不符合说话者语气的表达。
    7. 长度是练习目标，不是评分门槛。不得仅按词数判断分数，也不得用重复、空话或无关细节凑长度。
    """

    /// `part` 刻意保持 String，不跟着 PracticeSession/ExaminerPrompt 改成 FocusPart：
    /// 这里的合法域和 FocusPart 不是一回事。"full mock" 在 FocusPart 里是正式取值，
    /// 但回答升级规则从来没有为 full mock 单独定过标准，落进 fallbackRule 通用兜底
    /// 才是这里的预期行为（见 AnswerUpgradePolicyTests.testUnknownPartFallsBackToGeneralRule）；
    /// 换成 FocusPart 会让这条「预期的兜底」看起来像遗漏了一个 case。
    /// 另外这段规则文本逐字移植自上游 desktop/answer-upgrade-policy.mjs，
    /// 换参数类型没有必要牵动那段不能改写措辞的文本。
    ///
    /// **「Part 2 + Part 3」那一档的键写成 `FocusPart.part2And3.rawValue` 而不是字面量**：
    /// 参数类型虽然是 String，实际传进来的一直是某个 `FocusPart` 的 raw value
    /// （`ReviewRequestPrompt.build` 那一行）。键与 raw value 各写一份的话，
    /// 改了枚举的 raw value 之后这一档会**静默**落回 fallbackRule——
    /// 复盘照样生成、照样归档，只是那一场的长度标准悄悄换成了通用兜底。
    public static func guidance(part: String) -> String {
        let partRule = partGuidance[part] ?? fallbackRule
        return "\(partRule)\n\n\(sharedRules)"
    }
}
