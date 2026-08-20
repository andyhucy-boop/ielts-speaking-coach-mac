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

    /// 这一段**每多一份材料**再加多久（分钟）。
    ///
    /// 三个数字各有各的来源，不能统一成一个：
    ///
    /// - Part 1 多一个话题只是多问 3–4 个短问题，加 2 分钟；
    /// - Part 2 多一张卡是**再来一遍**「一分钟准备 + 两分钟独白 + 收尾一问」，加满 4 分钟；
    /// - Part 3 多一个讨论主题是再来一轮 4–8 问的讨论，加 4 分钟。
    ///
    /// 一份材料时 `firstItemMinutes` 与 `FocusPart` 那三档冻住的历史时长完全对得上
    /// （5 + 4 + 5 = 14，正是全真模考的 14 分钟），所以随机抽 1/1/1 与勾三个 Part
    /// 得到的是同一个数字——两条路给出两个时长的话，用户没有任何办法知道哪个是真的。
    public var additionalItemMinutes: Int {
        switch self {
        case .one: return 2
        case .two: return 4
        case .three: return 4
        }
    }
}
