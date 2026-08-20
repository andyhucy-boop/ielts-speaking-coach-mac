import Foundation
import IELTSCoachCore

/// 「随机抽题」那张弹层上全部可测的逻辑：每个 Part 现在有多少可抽、
/// 三个数字加起来是一场什么样的练习、抽之前要提醒什么、抽完之后要交代什么。
///
/// 拆出来是因为 `View` 几乎没法单元测试，而这些全是纯函数。
/// 判据一律是「把这里改成空实现，`RandomDrawViewModelTests` 会不会红」。
public struct RandomDrawViewModel: Sendable {

    /// 打开时三个数字的默认值：**Part 1 两个话题、Part 2 一张卡、Part 3 一组讨论。**
    ///
    /// 不是 1/1/1，也不是 0/0/0：
    ///
    /// - 真实考试 Part 1 就是 2–3 个话题（`ExaminerPrompt.part1Rules` 里那句
    ///   "Cover 2–3 everyday topics" 是同一个出处），只抽一个话题的 Part 1 短得不像一场考试；
    /// - 全 0 会让用户一打开就面对一个「点了没反应」的抽题按钮，
    ///   而这一页的默认值本来就该是一场立刻能练的完整考试。
    ///
    /// 这套默认值抽出来恰好是 14 分钟，与「勾满三个 Part」的全真模考等长——
    /// 一段 Part 1 本来就装 2–3 个话题，多给一个只是把那 4–5 分钟填满
    /// （见 `ExamPart.minutes(forItems:)`）。
    public static let defaultCounts = RandomDraw.Counts(one: 2, two: 1, three: 1)

    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    // MARK: - 现在有多少可抽

    public func total(inPart part: ExamPart) -> Int {
        RandomDraw.available(in: questions, part: part, excludingPracticed: false)
    }

    public func fresh(inPart part: ExamPart) -> Int {
        RandomDraw.available(in: questions, part: part, excludingPracticed: true)
    }

    /// 步进器最大能调到几。
    ///
    /// **卡在「这个 Part 一共有多少道」上，而不是「没练过的有多少道」。**
    /// 卡在后者的话，用户勾上「只抽没练过的」那一刻，他刚设好的数字会被悄悄改小——
    /// 而他并没有动那个数字。要的比没练过的多是允许的，抽之前会有一句提醒
    /// （`warnings`），抽完还会有一句交代（`shortfallNotices`）。
    public func maximum(inPart part: ExamPart) -> Int {
        min(total(inPart: part), RandomDraw.Counts.maximumPerPart)
    }

    /// 步进器下面那一行：这个 Part 共几道、没练过几道。
    ///
    /// **两个数都要有。** 只写总数的话，勾上「只抽没练过的」之后用户不知道还剩多少；
    /// 只写没练过的话，他不知道题库到底有多大。
    public func availabilityLine(forPart part: ExamPart) -> String {
        "共 \(total(inPart: part)) 道，没练过 \(fresh(inPart: part)) 道"
    }

    /// 把一组数量夹到「现在真的抽得到」的范围里。
    ///
    /// **只用在打开弹层那一刻，夹的是默认值。** 题库里 Part 2 一道都没有时，
    /// 默认值 1 会让步进器停在一个它根本调不到的数上（`Stepper` 的范围是 `0...0`），
    /// 屏幕上写着 1、抽出来是 0，而没有任何解释。
    ///
    /// **不用在切换「只抽没练过的」的时候**：那时改的是用户自己设过的数字，
    /// 悄悄改小等于替他做决定；那种情况归 `warnings` 提醒（见 `maximum(inPart:)`）。
    public func clampedToAvailable(_ counts: RandomDraw.Counts) -> RandomDraw.Counts {
        var clamped = counts
        for part in ExamPart.allCases {
            clamped[part] = min(counts[part], maximum(inPart: part))
        }
        return clamped
    }

    // MARK: - 抽之前

    /// 三个数字加起来是一场什么练习。**一道都没要时返回 nil**（那时说的是另一句话）。
    public func summary(forCounts counts: RandomDraw.Counts) -> String? {
        guard let focusPart = counts.focusPart else { return nil }
        let parts = focusPart.parts
            .map { "\($0.englishName) \(counts[$0]) 道" }
            .joined(separator: " · ")
        let order = focusPart.isCombined
            ? "，按 \(focusPart.parts.map(\.englishName).joined(separator: " → ")) 的顺序连着练"
            : ""
        return "这一场抽 \(parts)\(order)，大约 \(estimatedMinutes(forCounts: counts)) 分钟。"
    }

    /// 按要的份数算的时长。**与 `RandomDraw.Result.estimatedMinutes` 是同一套算法**——
    /// 抽之前说 14 分钟、抽完变成 9 分钟（因为少抽了几道）是正常的，
    /// 而抽之前和抽完对同一组题给出两个数字就不正常了。
    public func estimatedMinutes(forCounts counts: RandomDraw.Counts) -> Int {
        ExamPart.allCases.reduce(0) { $0 + $1.minutes(forItems: counts[$1]) }
    }

    /// 一道都没要时说什么。要了就返回 nil。
    ///
    /// 三样一个不少：现状、下一步、下一步指向的控件真实存在（那三个步进器就在这句话上面）。
    public func emptyNotice(forCounts counts: RandomDraw.Counts) -> String? {
        guard counts.total == 0 else { return nil }
        guard !questions.isEmpty else {
            return "题库还是空的，一道题都抽不出来。"
                + "下一步：关掉这个窗口，到「训练题库」页导入你的题库文件。"
        }
        return "三个 Part 的数量都是 0，抽出来会是一场什么都不考的练习。"
            + "下一步：把上面任意一个 Part 的数量调到 1 以上。"
    }

    /// 抽之前的提醒：要的比现在能抽的多。**必须抽之前就说**——
    /// 等抽完再说的话，用户已经看着一组比他要的少的题，得先弄明白少了什么才知道怎么办。
    public func warnings(forCounts counts: RandomDraw.Counts,
                         excludingPracticed: Bool) -> [String] {
        counts.parts.compactMap { part in
            let have = RandomDraw.available(in: questions, part: part,
                                            excludingPracticed: excludingPracticed)
            guard have < counts[part] else { return nil }
            let reason = excludingPracticed && total(inPart: part) >= counts[part]
                ? "没练过的只剩 \(have) 道。下一步：把数量调小，或者把「只抽没练过的」取消勾选。"
                : "题库里 \(part.englishName) 一共就 \(have) 道。"
                    + "下一步：把数量调小，或到「训练题库」页导入更多题。"
            return "\(part.englishName) 你要 \(counts[part]) 道，但\(reason)"
        }
    }

    // MARK: - 抽完之后

    /// 抽出来这一组是什么。
    public static func resultSummary(for result: RandomDraw.Result) -> String {
        guard let focusPart = result.focusPart else {
            return "一道题都没抽到。下一步：把数量调大，或者把「只抽没练过的」取消勾选，再抽一次。"
        }
        let parts = focusPart.parts
            .map { "\($0.englishName) \(result.count(inPart: $0)) 道" }
            .joined(separator: " · ")
        return "抽到了 \(parts)，这一场大约 \(result.estimatedMinutes) 分钟。"
    }

    /// 抽不够时的交代。**两种原因说两句不同的话**：题库本来不够只能去导题，
    /// 而「没练过的不够」把开关关掉就有了——分不清的话，用户手边那个一按就解决的开关
    /// 他不会想到去按。
    public static func shortfallNotices(for result: RandomDraw.Result) -> [String] {
        result.shortfalls.map { shortfall in
            let head = "\(shortfall.part.englishName) 要 \(shortfall.asked) 道，"
                + "只抽到 \(shortfall.got) 道："
            return shortfall.causedByExcludingPracticed
                ? head + "没练过的不够了。"
                    + "下一步：把「只抽没练过的」取消勾选再抽一次，或者把数量调小。"
                : head + "题库里 \(shortfall.part.englishName) 一共就这么多。"
                    + "下一步：把数量调小，或到「训练题库」页导入更多题。"
        }
    }

    /// 抽到的这一组里，某一道要显示成什么。
    ///
    /// Part 3 显示的是**改写过的讨论主题**，不是题干原文：题库里 Part 3 的题干就是
    /// 它所属 cue card 的原文，原样显示的话，屏幕上会是一句
    /// 「Describe a shop you enjoy visiting」，而这一场其实是抽象讨论——
    /// 提示词那边已经为这件事改过一轮（`ExaminerPrompt.part3ThemeBlock`），
    /// 界面不能还在显示那句会误导人的原话。
    public static func label(for question: Question) -> String {
        guard question.part == 3 else {
            return question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt
        }
        let theme = DiscussionTheme.phrase(fromCueCard: question.prompt)
        return theme.isEmpty ? question.topic : theme
    }
}
