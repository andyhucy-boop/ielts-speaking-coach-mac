import Foundation

/// 雅思口语考试的一个 Part。**这是这次改动引入的原子。**
///
/// ## 为什么要有它
///
/// 在这之前，「这一场按哪套考法跑」由 `FocusPart` 一个枚举表达，而它的取值里
/// 已经混进了 `part2And3`（两段）和 `fullMock`（三段）这样的**组合**。
/// 用户要求任意组合（1、2、3、1+2、1+3、2+3、1+2+3）之后，继续加 case 的写法会让
/// 每一处 `switch` 都要为组合再写一遍「Part 2 的规则 + Part 3 的规则」——
/// 同一段文本在七个分支里各抄一遍，改一处漏一处，而漏掉的那一档**照样能跑**，
/// 只是那一场少了半套规则，屏幕上一个字都不会提。
///
/// 拆出这个原子之后，「每个 Part 是什么、要做什么、不许做什么、提问前检查什么、
/// 复盘按什么长度改」都只写一遍，挂在这三个取值上；一场练习则是**一串有序的 Part**
/// （`FocusPart.parts`），提示词按顺序把各段拼起来。加组合不再需要加规则。
///
/// ## 穷尽性搬到了这里
///
/// 原先 `FocusPart` 用 `switch` 而不是字典，就是为了「加 case 却忘了给规则时编译期报错」。
/// 那条保护没有丢，只是搬了家：现在 `switch` 的是 `ExamPart`（永远只有三个取值），
/// 任何「每个 Part 各来一份」的东西漏写一个 Part 仍然编译不过。
public enum ExamPart: Int, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case one = 1
    case two = 2
    case three = 3

    /// 按考试顺序比大小。提示词、计划、界面都要求「Part 1 在 Part 2 前面」，
    /// 排序规则只写这一份，别处一律用它。
    public static func < (lhs: ExamPart, rhs: ExamPart) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 从 `Question.part` 那个 Int 认人。**越界返回 nil，不许猜。**
    ///
    /// 手改坏的 state.json 里 `part` 可能是 0、9、-1。在这里挑一个默认值糊弄过去的话，
    /// 一道坏数据的题会被当成某个 Part 正常考完，而用户永远不知道它坏过。
    public init?(questionPart: Int) { self.init(rawValue: questionPart) }

    /// 提示词里的写法。**逐字固定**：考官提示词里所有 "Part 1" / "Part 2" / "Part 3"
    /// 都从这里出，两处各写各的话，禁令段的限定语（"Never do these in Part 1:"）
    /// 会和规则段的标题对不上。
    public var englishName: String { "Part \(rawValue)" }

    // MARK: - 时长

    /// 这一段**第一份材料**要多久（分钟）。取值对着真实考试：
    /// Part 1 约 4–5 分钟，Part 2 一张卡约 4 分钟，Part 3 约 4–5 分钟。
    ///
    /// 从 `FocusPart` 搬过来的（那边原是个 private switch）。搬家的理由是随机抽题
    /// 要按「这一段抽了几份材料」算时长，而那件事和「这一场跑哪几段」不是一回事——
    /// 在两个地方各写一份数字，改的时候必然只改一处。
    public var firstItemMinutes: Int {
        switch self {
        case .one: return 5
        case .two: return 4
        case .three: return 5
        }
    }

    /// 这一段供了 `count` 份材料时大概要多久（分钟）。0 份是 0 分钟。
    ///
    /// **三段的算法不一样，而且不能统一**——因为「多一份材料」在三段里根本不是同一件事：
    ///
    /// - **Part 1 是按整段计时的。** 真实考试里这一段就是 4–5 分钟，里面装 2–3 个话题
    ///   （`ExaminerPrompt.part1Rules` 里那句 "Cover 2–3 everyday topics" 是同一个出处）。
    ///   多给一个话题只是把这 5 分钟填满，不是再来一段，所以 1 个和 2 个都是 5 分钟；
    ///   超过 3 个才真的开始变长。
    /// - **Part 2 是按张数计时的。** 每张卡都是完整的一轮「一分钟准备 + 两分钟独白 +
    ///   收尾一问」，抽 3 张就是老老实实的 12 分钟。
    /// - **Part 3 介于两者之间。** 第一组讨论就是那 4–5 分钟的一整段；再多一组是
    ///   另起一个话题重来一轮 4–8 问，加 4 分钟。
    ///
    /// 一份材料时三段相加 = 5 + 4 + 5 = 14，正是 `FocusPart.fullMock` 冻住的那个数字，
    /// 所以「随机抽 1/1/1」与「勾满三个 Part」得到的是同一个时长——
    /// 两条路给出两个数字的话，用户没有任何办法知道哪个是真的。
    public func minutes(forItems count: Int) -> Int {
        guard count > 0 else { return 0 }
        switch self {
        case .one: return max(firstItemMinutes, 2 * count)
        case .two: return firstItemMinutes * count
        case .three: return firstItemMinutes + (count - 1) * 4
        }
    }
}
