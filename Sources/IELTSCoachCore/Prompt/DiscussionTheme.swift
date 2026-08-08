import Foundation

/// 把一张 cue card 的题干转成**一句话题短语**。
///
/// ## 为什么需要它
///
/// 2026-08-08 用户真机实测：单练 Part 3 时，提示词里那一段长这样——
///
///     Discussion theme for this Part 3 session (topic: Describe a shop/store you enjoy visiting)
///     …
///     Describe a shop/store you enjoy visiting
///
/// 旁边写满了「这不是任务、不许当成 cue card」，ChatGPT 的第一句仍然是
/// 「Can you describe a place you enjoy spending time in?」。用户自己的判断是对的：
/// **那个 `Describe` 摆在那儿本身就在诱导，在它旁边写「别念这句」没用。**
/// 题库里 Part 3 的题干就等于它所属 cue card 的原文（见 `TopicQuestions.part3`），
/// 所以只要还原样往下传，每一场单练 Part 3 都在给模型递一张 Part 2 的任务卡。
///
/// 修法是把题干改写成用户要的形状：`Part 3 theme: a shop or store you enjoy visiting`。
///
/// ## 边界
///
/// 这里只做**纯字符串处理**，不查词典、不猜语义。它做四件事，每一件都对应一个真实的坑：
///
/// 1. 砍掉开头的祈使动词（`Describe` / `Talk about` / `Tell me about`）——诱导源本身；
/// 2. 砍掉 `You should say …` 那条尾巴——它比 `Describe` 更像任务书；
/// 3. `shop/store` 这种斜杠改写成 `shop or store`——用户给的目标形状就是这样，
///    而斜杠读出来是「shop 斜杠 store」；
/// 4. 首字母小写，但**只对确定是虚词的开头**动手（见 `lowercasableOpeners`），
///    免得把 `Describe London in three sentences` 改成 `london`。
///
/// 转不动就原样返回（去掉首尾空白）：题库里 Part 1 的话题是 `Borrowing and lending`
/// 这种名词短语，本来就不需要改写，硬套规则只会把它弄坏。
public enum DiscussionTheme {

    /// cue card 常见的起手祈使动词。**按长度从长到短匹配**，
    /// 否则 `Tell me about a…` 会先被 `Tell` 之外的规则漏过去。
    ///
    /// 只收「这句话是一项任务」的动词。`Explain`、`Compare` 之类不收：
    /// 那是 Part 3 讨论问句的开头，不是 cue card 的任务动词，砍掉会改变意思。
    private static let taskVerbs = ["tell me about", "talk about", "describe"]

    /// 砍掉动词之后可以放心小写的开头词。
    ///
    /// **只小写虚词**是刻意的保守：真实 cue card 在 `Describe` 后面几乎只跟这几个词，
    /// 而白名单之外一律保留原样，最坏的结果只是主题行首字母是大写——
    /// 比把一个专有名词小写掉要好。
    private static let lowercasableOpeners: Set<String> = [
        "a", "an", "the", "some", "someone", "something", "somewhere",
        "your", "one", "two", "any", "this", "that", "an"
    ]

    /// cue card 题干 → 话题短语。
    ///
    /// - Parameter cueCard: 题库里那道题的 `prompt`（Part 3 的题干就是所属 cue card 原文）。
    /// - Returns: 可以直接接在 `Part 3 theme: ` 后面的短语。**输入全是空白时返回空串**，
    ///   由调用方决定怎么兜底（见 `ExaminerPrompt.questionBlock`）——
    ///   这里不编一个假话题出来。
    public static func phrase(fromCueCard cueCard: String) -> String {
        var text = cueCard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = strippingTaskTail(text)
        text = strippingTaskVerb(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = strippingTrailingPeriod(text)
        text = spellingOutSlashes(text)
        return lowercasingFunctionWordOpener(text)
    }

    /// 砍掉 `You should say …` 及其后的一切。
    ///
    /// 这条尾巴比 `Describe` 更像任务书：`You should say what it is, where you saw it,
    /// and explain why you liked it` 逐字念出去，就是一张完整的 Part 2 卡。
    private static func strippingTaskTail(_ text: String) -> String {
        guard let range = text.range(of: "you should say", options: [.caseInsensitive]) else {
            return text
        }
        let head = text[text.startIndex..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 尾巴前面什么都不剩时（题干整句就是 "You should say…"）宁可保留原文，
        // 也不返回空串——空主题比一句啰嗦的主题糟糕得多。
        return head.isEmpty ? text : head
    }

    private static func strippingTaskVerb(_ text: String) -> String {
        let lowered = text.lowercased()
        for verb in taskVerbs where lowered.hasPrefix(verb) {
            let rest = String(text.dropFirst(verb.count))
            // 只在动词后面真的断开时才砍：`Describes`、`Talk aboutish` 不该被误伤。
            guard let first = rest.first else { return text }
            guard first.isWhitespace else { continue }
            return rest
        }
        return text
    }

    private static func strippingTrailingPeriod(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    /// `shop/store` → `shop or store`。
    ///
    /// **只改「字母 / 字母」这一种形状**：`24/7`、`km/h`… 里 `24/7` 有数字，
    /// 改写它会把一个固定说法拆散。两侧带空格的斜杠也不动——那通常是作者刻意排版的。
    private static func spellingOutSlashes(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        for (index, character) in characters.enumerated() {
            guard character == "/",
                  index > 0, index + 1 < characters.count,
                  characters[index - 1].isLetter, characters[index + 1].isLetter else {
                output.append(character)
                continue
            }
            output += " or "
        }
        return output
    }

    private static func lowercasingFunctionWordOpener(_ text: String) -> String {
        guard let firstWord = text.split(separator: " ", maxSplits: 1).first else { return text }
        guard lowercasableOpeners.contains(firstWord.lowercased()) else { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}
