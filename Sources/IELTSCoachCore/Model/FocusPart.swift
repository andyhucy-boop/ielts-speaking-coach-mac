import Foundation

/// 这一场练习**按哪几个 Part 跑**，以及按什么顺序。
///
/// ## 为什么它从枚举变成了「一串有序的 Part」
///
/// 用户原话（2026-08-08 真机反馈）：
///
/// > 我发现你这个目前练习好像无法同时选择多个问题啊。
/// > 比如我要多选 Part one 和 Part two，练完这个练那个。
///
/// 在这之前这里是个五取值的枚举（`part1` / `part2` / `part3` / `part2And3` / `fullMock`），
/// 也就是说组合档是**一个一个手写进枚举**的。要支持任意组合（1、2、3、1+2、1+3、2+3、
/// 1+2+3）有两条路：
///
/// 1. **继续加 case。** 三个 Part 的非空组合恰好七种，加两个 case 就齐了，
///    而且所有 `switch` 会当场编译不过、逼每一处表态——听起来很稳。
///    但代价在**下游**：`ExaminerPrompt` 要为七个 case 各写一遍「把这几段规则拼起来」，
///    `PlanScope`、`AnswerUpgradePolicy`、`PracticePicker` 同样各写七遍。
///    同一段文本抄七遍，改的时候必然只改被测试盯着的那几遍，
///    而漏掉的那一档**照样能跑完一整场**，只是少了半套规则——屏幕上一个字都不会提。
///    这正是本项目最忌讳的失败形态。
/// 2. **把「有序的 Part 列表」本身变成模型**（这里选的）。规则只写一遍、挂在 `ExamPart`
///    上，一场练习就是这些规则按 `parts` 的顺序拼起来。加组合不需要加规则。
///
/// 穷尽性检查没有丢：它搬到了 `ExamPart`（永远只有三个取值）。任何「每个 Part
/// 各来一份」的东西漏写一个 Part，仍然是编译错误。
///
/// ## raw value 已经落盘，一个字都不能改
///
/// 这五个字符串写在用户机器上的 `state.json` 里（`sessions[].focusPart`、`plan.focusPart`）：
///
/// - `"Part 1"` / `"Part 2"` / `"Part 3"`
/// - `"Part 2 + Part 3"`
/// - `"full mock"` ← 三个 Part 全选的写法**仍然是这个**，不是 `"Part 1 + Part 2 + Part 3"`
///
/// 最后一条是这次建模最要紧的一个约束：`[1, 2, 3]` 与 `fullMock` 是**同一个取值**，
/// 所以它必须编码回 `"full mock"`。写成 `"Part 1 + Part 2 + Part 3"` 的话，
/// 旧版本 App（以及回退 / 跨机同步）读到的是一个不认识的字符串，会当成……
/// 恰好也是 full mock（那边的兜底就是它），于是**不报错、不崩、行为也对**——
/// 但用户的历史记录里同一件事会有两种写法，「按考法筛选训练记录」从此对不齐。
///
/// 两个新增取值（`"Part 1 + Part 2"`、`"Part 1 + Part 3"`）只影响
/// 「新版本写、旧版本读」这一个方向，而那条路早就铺好了：`TrainingPlan.init(from:)`、
/// `PracticeSession.init(from:)` 都是「先读字符串，转不出来就回落到 full mock」，
/// 绝不会因为一个取值让整份训练数据读不出来。
public struct FocusPart: RawRepresentable, Codable, Hashable, Sendable, CaseIterable {

    /// 这一场要跑的 Part，**升序、去重、非空**。三条不变量由所有构造入口共同保证：
    /// 顺序就是真实考试的顺序，提示词直接照着它拼；空列表是「一场什么都不考的练习」，
    /// 没有任何调用方处理得了它。
    public let parts: [ExamPart]

    // MARK: - 构造

    /// 从一组 Part 造一档考法。**空集合返回 nil**——把空当成「全选」或者「Part 1」
    /// 都是替用户做决定，而他刚刚做的动作是「一个都没勾」。
    public init?(parts: [ExamPart]) {
        let canonical = Array(Set(parts)).sorted()
        guard !canonical.isEmpty else { return nil }
        self.parts = canonical
    }

    /// 单个 Part。这一条永远成功，所以不是 failable。
    public init(_ part: ExamPart) { parts = [part] }

    /// 从落盘的字符串认人。**认不出来返回 nil**，由调用方决定回落到什么——
    /// 在这里猜一个默认值的话，一份手改坏的 state.json 会被当成正常数据继续用。
    ///
    /// 认得三种写法：`"full mock"`（历史取值）、`"Part 1 + Part 2 + Part 3"`（同一个东西，
    /// 只是写法不同，读进来之后会被规范化成前者）、以及任意 `Part N` 用 `+` 连起来。
    ///
    /// **顺序和重复容忍，大小写不容忍。** 分界线在这里：
    ///
    /// - 顺序（`"Part 3 + Part 2"`）和重复（`"Part 2 + Part 2"`）不携带任何信息，
    ///   两种写法说的是同一件事，规范化掉不会丢东西；
    /// - 大小写不同（`"part 1"`）是**手改坏了**。本项目对手改坏的字段一贯的处理是
    ///   回落到默认值而不是猜（`PracticeSessionCodableTests` 那条钉着这个约定）：
    ///   猜错一次的代价是那条练习记录被静默改成另一档考法，而屏幕上一个字都没有。
    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == Self.fullMockRawValue { self.init(parts: ExamPart.allCases); return }

        var found: [ExamPart] = []
        for piece in trimmed.split(separator: "+") {
            let token = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.hasPrefix("Part ") else { return nil }
            let number = token.dropFirst("Part ".count).trimmingCharacters(in: .whitespaces)
            guard let value = Int(number), let part = ExamPart(questionPart: value) else { return nil }
            found.append(part)
        }
        self.init(parts: found)
    }

    // MARK: - 落盘

    /// **`"full mock"` 这个历史写法必须保住**（理由见类型文档）。
    private static let fullMockRawValue = "full mock"

    public var rawValue: String {
        parts.count == ExamPart.allCases.count
            ? Self.fullMockRawValue
            : parts.map(\.englishName).joined(separator: " + ")
    }

    /// 编码成一个字符串，与从前那个 String 枚举**逐字节一致**——
    /// 换成对象或者数组的话，旧版本 App 读到的不是「不认识的取值」而是「类型不对」，
    /// 那条容错路径挡不住它，整份 state.json 会报损坏。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 解码。认不出来**抛错**，与从前那个 String 枚举的行为一致：
    /// 各个模型（`TrainingPlan` / `PracticeSession`）自己那层「先读字符串再转」的容错
    /// 是唯一的兜底出处，在这里再兜一次会让那层容错永远测不出来。
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = FocusPart(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "认不出的 focusPart 取值「\(raw)」"))
        }
        self = parsed
    }

    // MARK: - 七种取值

    public static let part1 = FocusPart(.one)
    public static let part2 = FocusPart(.two)
    public static let part3 = FocusPart(.three)
    /// 先日常问答，再两分钟陈述。
    public static let part1And2 = FocusPart(parts: [.one, .two])!
    /// 日常问答之后直接进抽象讨论，跳过 cue card。
    public static let part1And3 = FocusPart(parts: [.one, .three])!
    /// 先 Part 2 的两分钟陈述，紧接着做 Part 3 讨论——真实考试就是这个顺序。
    public static let part2And3 = FocusPart(parts: [.two, .three])!
    /// 三个 Part 全跑。**raw value 仍然是 `"full mock"`**，不是三个 Part 拼起来。
    public static let fullMock = FocusPart(parts: ExamPart.allCases)!

    /// 单 Part 在前、两 Part 组合在中、全真模考在最后。
    /// **顺序是用户看得见的**（学习计划页那组单选按钮、MCP 工具的 enum 清单），
    /// 每次改动都会让界面上的选项换位置，所以定死在这里。
    public static let allCases: [FocusPart] =
        [.part1, .part2, .part3, .part1And2, .part1And3, .part2And3, .fullMock]

    // MARK: - 查询

    /// 这一场里有没有这个 Part。
    public func includes(_ part: ExamPart) -> Bool { parts.contains(part) }

    /// 这一场是不是不止一段。
    public var isCombined: Bool { parts.count > 1 }

    /// 这一场从哪个 Part 开始。`parts` 非空，所以永远有值。
    public var openingPart: ExamPart { parts[0] }

    // MARK: - 从题目自身的 Part 推

    /// 从题目自身的 Part 推出这一场按哪套考法跑。
    ///
    /// **全工程只留这一份。** 在这之前，`FocusPart(rawValue: "Part \(question.part)") ?? .fullMock`
    /// 这一行在六个文件里各抄了一遍（今日训练页、路线解析器、复训、命令行、两个 MCP 工具）。
    ///
    /// 组合档**永远不会被推出来**，它只可能是用户当场明确选的（见 `forExplicitSelection`）
    /// 或者学习计划里定下的（见 `forSession`）：一道 Part 2 的题默认就该按 Part 2 考，
    /// 把它悄悄升级成「连着练 Part 3」，等于替用户改了这一场的考法而屏幕上没有任何交代。
    public static func inferred(fromQuestionPart part: Int) -> FocusPart {
        // 越界的 part（手改坏的 state.json）落到 full mock，不让脏数据把练习整场卡死。
        guard let examPart = ExamPart(questionPart: part) else { return .fullMock }
        return FocusPart(examPart)
    }

    /// **学习计划的「重点 Part」**在某一天变成这一场的考法。
    ///
    /// - Parameter mode: 计划里定下的重点 Part，或者「继续上次练习」带过来的上一场取值。
    ///   `nil` = 没有明确选择。
    ///
    /// 这里的规则刻意保守，三条都不是偷懒：
    ///
    /// - `part1` / `part2` / `part3`：这三档的题目筛选已经保证了题目就是那个 Part，
    ///   `inferred` 给出的答案和它们完全一样；
    /// - **`fullMock` 一律回落到 `inferred`。** 「全真模考」作为计划的重点 Part，
    ///   意思是「把三个 Part 的题交错排开」（`PlanScope.select`），
    ///   **每一天仍然是练那道题自己的 Part**。这里若返回 `fullMock`，
    ///   用户按计划练的每一天都会变成一整场三 Part 模考——一次行为上的静默突变。
    ///   要真的考一场模考，走的是用户当场三个 Part 全勾（`forExplicitSelection`）；
    /// - 其余组合档（1+2、1+3、2+3）**只在题目正是这一档的第一段时生效**。
    ///   一张 Part 1 的话题卡做不出「两分钟长陈述 + 延伸讨论」，硬按 2+3 考只会让考官
    ///   自己编一张 cue card，而用户挑的那道题一次都不会被问到。
    public static func forSession(mode: FocusPart?, questionPart: Int) -> FocusPart {
        let inferred = inferred(fromQuestionPart: questionPart)
        guard let mode, mode.isCombined, mode != .fullMock else { return inferred }
        guard let anchor = ExamPart(questionPart: questionPart),
              mode.openingPart == anchor else { return inferred }
        return mode
    }

    /// **用户在开练弹层上当场勾出来的那几个 Part**，直接就是这一场的考法。
    ///
    /// 与 `forSession` 的区别只有一条，而这一条是整个多选功能的关键：
    /// 计划里的重点 Part 是「排哪些题」，所以要被过滤；弹层上那几个勾是
    /// **他此刻对这一场的明确要求**，勾了 1、2、3 就该考一整场模考，不能被降级成
    /// 「练那道题自己的 Part」——那样的话，勾选框拨得动、这一场却和它毫无关系，
    /// 屏幕上一个字都不会提（铁律 5）。
    ///
    /// 唯一的回落是「挑中的那道题根本不属于勾选的任何一个 Part」：
    /// 那时按它自己的 Part 考，因为一份提示词里那道题必须落在某一段上，
    /// 落不上就等于用户挑的题一次都不会被问到。界面上这种情况已经被挡掉了
    /// （切档会清空选择），这里是最后一道防线。
    public static func forExplicitSelection(_ selection: FocusPart,
                                            questionPart: Int) -> FocusPart {
        guard let anchor = ExamPart(questionPart: questionPart),
              selection.includes(anchor) else { return inferred(fromQuestionPart: questionPart) }
        return selection
    }

    // MARK: - 时长

    /// 这几档的时长是历史取值，沿用它们只是为了不顺手改掉用户已经看惯的数字。
    ///
    /// **`fullMock` 不在这张表里，它按各段相加（14 分钟）。**
    ///
    /// 它原本也冻在 6 分钟，而多选功能上线后新增的组合档是 9、9、10——
    /// 勾三个 Part 反而比勾两个短。这不只是数字难看：它会写进提示词的
    /// `Target session length`，考官为了对上 6 分钟会把三段压缩，
    /// 或者干脆砍掉 Part 3——正是这一轮刚修完的那类跑偏的另一种形态。
    /// 真实考试 11–14 分钟，相加得到的 14 正落在里面。
    ///
    /// 单 Part 那三档保持原样：它们各自没有内部矛盾，而且是用户看了最久的三个数字。
    /// `part2And3` 的 9 同样保留（相加也是 9，本来就一致）。
    private static let frozenDurations: [String: Int] = [
        part1.rawValue: 6, part2.rawValue: 4, part3.rawValue: 6,
        part2And3.rawValue: 9
    ]

    /// 新增组合按各段时长相加。取值对着真实考试：Part 1 约 4–5 分钟，
    /// Part 2 一张卡约 4 分钟，Part 3 约 4–5 分钟。
    private static func minutes(for part: ExamPart) -> Int {
        switch part {
        case .one: return 5
        case .two: return 4
        case .three: return 5
        }
    }

    /// 这一档默认练多久（分钟）。
    ///
    /// 先查那五个冻住的历史取值，查不到才按各段相加。**这个顺序不能反**：
    /// 反过来的话 `part2And3` 会从 9 变成 9（碰巧一样）、而 `fullMock` 会从 6 变成 14，
    /// 于是一次建模改动顺带改掉了用户看得见的一个数字。
    public var defaultDurationMinutes: Int {
        if let frozen = Self.frozenDurations[rawValue] { return frozen }
        return parts.map(Self.minutes(for:)).reduce(0, +)
    }
}
