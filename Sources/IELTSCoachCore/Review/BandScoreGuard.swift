import Foundation

/// **运行期挡住雅思分数。**
///
/// ## 为什么提示词里写了还不够
///
/// 「绝不预测分数」是本项目的一条红线（DEFINITION-OF-DONE 第 4 节），而在这之前
/// 它**只写在复盘请求的提示词里**——全靠 ChatGPT 自觉，而它每换一次模型都可能不自觉一次。
/// 真写了一句「整体大概 6.5」的话，那句话会原样存档、原样显示在复盘页最上面那张卡片上，
/// 而那张卡片是用户打开复盘第一眼看到的东西。
///
/// 上游的原则说得很直接：不能再把全部规则只寄托在一个提示词上。它的实时桥真的在
/// 收到回复时逐项校验。这里做的是同一件事的最小版本：**收到之后再挡一道。**
///
/// ## 两条刻意的克制
///
/// 1. **不扫中文单字「分」。** 复盘里到处是「分析」「部分」「十分」「区分」「分钟」，
///    扫单字会让每一份复盘都误报，而一个天天误报的警告等于没有警告。
///    这里只认**带数字的形态**（`6.5 分`、`band 7`、`雅思 6.5`、`7 分水平`）。
/// 2. **绝不因此丢掉整份复盘。** 他练了半小时才换来这一份，
///    为了一句多余的话把它整份拒收是不成比例的。做法是：照常归档、照常显示其余内容，
///    只把**出现分数的那一句**挡在总结之外，并明说挡掉了什么（铁律：禁止静默）。
public enum BandScoreGuard {

    /// 命中的那些片段（去重、保序）。空数组 = 这份复盘里没有分数。
    public static func matches(in text: String) -> [String] {
        var found: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let hit = Range(match.range, in: text) else { continue }
                let fragment = String(text[hit]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !fragment.isEmpty && !found.contains(fragment) { found.append(fragment) }
            }
        }
        return found
    }

    /// 把**出现分数的那几句**去掉，其余原样留下。没有命中时返回原文（连空白都不动）。
    ///
    /// 按句子切而不是只删那几个字：只删「6.5」的话，剩下的是
    /// 「整体大概 ，建议…」——比留着更糟，用户会以为复盘本身坏了。
    public static func stripping(_ text: String) -> String {
        guard !matches(in: text).isEmpty else { return text }
        let kept = sentences(in: text).filter { matches(in: $0).isEmpty }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 要对用户说的那句话。没有命中时返回 nil。
    ///
    /// 三样一个不少：发生了什么、挡掉的原文是什么（让他自己判断）、为什么要挡。
    /// **必须把原文摆出来**——只说「挡掉了一句话」而不说是哪句，
    /// 等于让他怀疑复盘里还有别的东西被悄悄动过。
    public static func notice(for text: String) -> String? {
        let hits = matches(in: text)
        guard !hits.isEmpty else { return nil }
        return "这份复盘里出现了雅思分数（\(hits.joined(separator: "、"))），"
            + "带这句话的那一段已经挡在上面那段总结之外，其余内容一个字没动，复盘原文也完整存着。"
            + "挡它的理由：这个数字既不准也有害，会让你盯着数字而不是盯着具体哪句话该怎么改。"
            + "下一步：照常看下面各节；想核对原话的话，这一页最下面有复盘原文的路径。"
    }

    // MARK: - 私有

    /// **只认带数字的形态。** 每一条都对应一种真会被写出来的说法。
    private static let patterns = [
        // band 6.5 / Band score 7 / band: 6
        #"band\s*(score)?\s*[:：]?\s*\d(\.\d)?"#,
        // 6.5 分 / 7分。**排除「分钟」「分析」这一类**——它们在复盘里到处都是。
        #"\d(\.\d)?\s*分(?![钟析别配开数量之支])"#,
        // 雅思 6.5 / IELTS 7
        #"(雅思|ielts)\s*\d(\.\d)?"#,
        // 7 分水平 / 6.5 的水平
        #"\d(\.\d)?\s*(分)?\s*(的)?水平"#,
        // **光秃秃的一个 6.5**（「整体大概 6.5，建议多练」——实测最常见的写法之一）。
        //
        // 只认 4.0–9.5 且小数位是 .0 或 .5：雅思分数只有这个形状。
        // 复盘里别的数字（「2 到 4 句」「90 至 120 词」「3 分钟」）都不是小数，撞不上。
        //
        // **刻意不认光秃秃的整数**（「大概 7」）：那和「大概 7 个例子」分不开，
        // 而这里误报一次的代价是把一句正常的话从总结里挡掉。
        // 代价是漏掉「大概 7」这一种写法——漏一条，好过天天误报到没人再看这条警告。
        #"(?<![\d.])[4-9]\.[05](?![\d])"#,
    ]

    /// 按中英文句末标点与换行切句，**标点跟着前一句走**（否则拼回去会少标点）。
    private static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if "。！？!?\n".contains(character) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
