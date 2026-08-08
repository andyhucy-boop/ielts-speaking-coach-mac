import Foundation

/// 练习的 Part 选择。用 String raw value 与上游 state.json 保持兼容。
///
/// ## 为什么「Part 2 + Part 3 连着练」是这里的一个 case，而不是另开一个布尔开关
///
/// 用户原话：「你可以加一个功能，是否同时练习 part2 和 part3。」界面上它确实是一个
/// 是 / 否的开关（`PracticeSheet` 里那颗「练完 Part 2 接着练 Part 3」），
/// 但**模型这一层必须是 `FocusPart` 的一个取值**，理由有三条：
///
/// 1. `FocusPart` 就是「这一场按哪套考法跑」的唯一出处：`ExaminerPrompt.partRules`
///    照着它选规则、`ReviewRequestPrompt` 照着它选回答长度标准、`PracticeSession`
///    把它存进训练记录、`PlanScope` 照着它排计划。多一个并行的布尔，就要在这五处
///    分别再穿一遍线，**漏穿一处的表现是「静默地按普通 Part 2 考了一场」**——
///    不报错、界面无异样，正是本项目最忌讳的失败形态。
/// 2. 加 case 会让所有 `switch` 编译不过，逼每一处当场表态；加布尔不会，
///    它带着默认值悄悄编译通过，测试也照样全绿。本仓库已有 `fullMock` 这个先例：
///    组合档本来就属于这个枚举。
/// 3. 存盘只多一个字符串取值，旧数据与旧版本 App 的兼容路径（下面那段）已经现成。
///
/// ## 旧数据 / 旧版本怎么办
///
/// 新增取值只影响「新版本写、旧版本读」这一个方向，而那条路早就铺好了：
/// `TrainingPlan.init(from:)`、`PracticeSession.init(from:)`、`CoachSettings.stringEnum`
/// 全都是「先读字符串，转不出枚举就回落」，认不出 `"Part 2 + Part 3"` 时按 `fullMock`
/// 处理，绝不会因为一个取值让整份训练数据读不出来。
public enum FocusPart: String, Codable, Equatable, Sendable, CaseIterable {
    case part1 = "Part 1"
    case part2 = "Part 2"
    case part3 = "Part 3"
    /// 先 Part 2 的两分钟陈述，紧接着做 Part 3 讨论——真实考试就是这个顺序。
    ///
    /// **raw value 一旦定下就不能再改**：它已经写进用户机器上的 state.json，
    /// 改一个字就等于让那些练习记录的 Part 变成「全真模考」。
    case part2And3 = "Part 2 + Part 3"
    case fullMock = "full mock"

    /// 从题目自身的 Part 推出这一场按哪套考法跑。
    ///
    /// **全工程只留这一份。** 在这之前，`FocusPart(rawValue: "Part \(question.part)") ?? .fullMock`
    /// 这一行在六个文件里各抄了一遍（今日训练页、路线解析器、复训、命令行、两个 MCP 工具）。
    /// 抄六遍的代价不是难看：`part2And3` 加进来之后，谁把其中一处「顺手修好」成也能推出
    /// 组合档，六条路线就会开始给出两种考法，而两边各自的测试都是绿的。
    ///
    /// `part2And3` **永远不会被推出来**，它只可能是用户当场明确选的（见 `forSession`）：
    /// 一道 Part 2 的题默认就该按 Part 2 考，把它悄悄升级成「连着练 Part 3」，
    /// 等于替用户改了这一场的考法而屏幕上没有任何交代。
    public static func inferred(fromQuestionPart part: Int) -> FocusPart {
        // 越界的 part（手改坏的 state.json）落到 full mock，不让脏数据把练习整场卡死。
        FocusPart(rawValue: "Part \(part)") ?? .fullMock
    }

    /// 这一场最终按哪套考法跑：用户明确选的模式优先，选不出来就按题目自身的 Part。
    ///
    /// - Parameter mode: 用户当场明确选的模式（挑题弹层上那颗开关、学习计划的重点 Part、
    ///   或者「继续上次练习」带过来的上一场取值）。`nil` = 没有明确选择。
    ///
    /// **只有 `part2And3` 会真的改变结果，而且只在题目确实是 Part 2 时才生效。**
    /// 其余取值一律回落到 `inferred`，这不是偷懒：
    ///
    /// - `part1` / `part2` / `part3`：这三档的题目筛选已经保证了题目就是那个 Part，
    ///   `inferred` 给出的答案和它们完全一样，多写一条分支只是多一处会漂移的判断；
    /// - `fullMock`：全真模考的计划把三个 Part 的题交错排开，**每一天仍然是练那道题自己的
    ///   Part**（`PlanScope.select` 的既有语义）。这里若返回 `fullMock`，
    ///   用户按计划练的每一天都会变成一整场三 Part 模考——一次行为上的静默突变。
    ///
    /// 题目不是 Part 2 却要求 `part2And3` 时同样回落：一张 Part 1 的话题卡做不出
    /// 「两分钟长陈述 + 延伸讨论」，硬按组合档考只会让考官自己编一张 cue card，
    /// 而用户挑的那道题一次都不会被问到。
    public static func forSession(mode: FocusPart?, questionPart: Int) -> FocusPart {
        let inferred = inferred(fromQuestionPart: questionPart)
        guard let mode else { return inferred }
        switch mode {
        case .part2And3:
            return questionPart == 2 ? .part2And3 : inferred
        case .part1, .part2, .part3, .fullMock:
            return inferred
        }
    }

    /// 这一档默认练多久（分钟）。
    ///
    /// 取值与 `coach practice` 的既有约定一致：Part 2 是一张 cue card，4 分钟够；其余 6 分钟。
    /// `part2And3` = 一场 Part 2（约 4 分钟）接一段 Part 3 讨论（约 5 分钟），所以是 9。
    ///
    /// **`fullMock` 保持 6 分钟不动。** 一整场模考实际要 11–14 分钟，这个 6 是历史取值，
    /// 改它会悄悄改掉每一条既有路线上「今天练多久」的提示，那是另一件事，不在这次改动里做。
    public var defaultDurationMinutes: Int {
        switch self {
        case .part2: return 4
        case .part2And3: return 9
        case .part1, .part3, .fullMock: return 6
        }
    }
}
