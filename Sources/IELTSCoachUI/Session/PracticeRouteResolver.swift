import Foundation
import IELTSCoachCore

public enum RouteResolution: Equatable, Sendable {
    case ready(SessionSetup)
    /// 中文说明：发生了什么 + 下一步做什么。界面必须把它显示出来。
    case unavailable(String)
}

/// 四条练习路线 → 一场具体的练习。
///
/// **「这条路线能不能显示」与「这条路线练哪道题」用的是同一段代码。**
/// 分成两处写，迟早会出现「卡片显示了、点下去说不行」——用户会以为程序坏了。
public enum PracticeRouteResolver {

    // MARK: - 一场练习的取值

    /// 取值与命令行保持一致（见 `Sources/coach/PracticeCommand.swift`）：
    /// Part 2 是一张 cue card，4 分钟够；其余 6 分钟；「Part 2 + Part 3 连着练」9 分钟。
    /// 题目的 part 落在 1–3 之外（手改坏的 state.json）时按全真模考处理，不崩。
    ///
    /// - Parameter mode: **学习计划的「重点 Part」**。`nil` = 没有计划层面的选择，
    ///   按题目自身的 Part 走。
    ///
    ///   它是「排哪些题」的意思，不是「这一场考几段」，所以要被过滤：
    ///   一份全真模考的计划，每一天仍然练那道题自己的 Part。
    ///   **过滤规则全归 `FocusPart.forSession` 管，这里不再判一次**：
    ///   在这儿另写一遍判断，就等于这条规则有了两份实现，而四条路线各走各的那一份。
    ///
    ///   用户在弹层上当场勾出来的那几个 Part 走的是下面 `chosen:` 那个入口。
    public static func setup(for question: Question, goal: String,
                             defaults: RouteDefaults,
                             mode: FocusPart? = nil,
                             bank: [Question] = []) -> SessionSetup {
        make(question: question, goal: goal, defaults: defaults, bank: bank,
             focusPart: FocusPart.forSession(mode: mode, questionPart: question.part))
    }

    /// **用户当场明确选的考法** → 这一场。与上面那个的区别只有一条，而这一条是
    /// 多选 Part 这个功能的关键：
    ///
    /// - `mode:` 那个入口收的是**学习计划的重点 Part**，它的含义是「排哪些题」，
    ///   所以要被 `FocusPart.forSession` 过滤（一份全真模考的计划，每天仍然练那道题
    ///   自己的 Part，不是每天跑一整场模考）；
    /// - 这个入口收的是**他此刻在弹层上勾出来的那几个 Part**，那就是他对这一场的要求。
    ///   三个全勾就该考一整场模考。走上面那个入口的话会被降级成单 Part——
    ///   勾选框点得动、这一场却和它毫无关系，屏幕上一个字都不会提（铁律 5）。
    ///
    /// 分成两个方法而不是加一个布尔参数：布尔参数漏传的默认值是「按计划语义」，
    /// 那正是会静默降级的一支，而漏传不会有任何编译错误。
    public static func setup(for question: Question, goal: String,
                             defaults: RouteDefaults,
                             chosen: FocusPart,
                             bank: [Question] = []) -> SessionSetup {
        make(question: question, goal: goal, defaults: defaults, bank: bank,
             focusPart: FocusPart.forExplicitSelection(chosen, questionPart: question.part))
    }

    /// - Parameter bank: 配对「这张 cue card 自己那组 Part 3 追问」用的题库
    ///   （`LinkedPart3`）。传空的话，同时含 Part 2 与 Part 3 的那几场会拿不到追问，
    ///   提示词里会如实写明「题库里没找到，全部临场编」——不静默，但也就白白扔掉了真题。
    private static func make(question: Question, goal: String, defaults: RouteDefaults,
                             bank: [Question], focusPart: FocusPart) -> SessionSetup {
        SessionSetup(question: question,
                     focusPart: focusPart,
                     durationMinutes: focusPart.defaultDurationMinutes,
                     goal: goal,
                     feedbackTiming: defaults.feedbackTiming,
                     part2PrepMode: defaults.part2PrepMode,
                     part3Reference: LinkedPart3.reference(for: question, in: bank))
    }

    // MARK: - 解析

    public static func resolve(route: PracticeRoute, state: CoachState,
                               selectedQuestionID: String? = nil,
                               defaults: RouteDefaults = RouteDefaults()) -> RouteResolution {
        switch route {
        case .planToday:   return resolvePlanToday(state, selectedQuestionID, defaults)
        case .freePick:    return resolveFreePick(state, selectedQuestionID, defaults)
        case .continueLast: return resolveContinueLast(state, defaults)
        case .retrain:     return resolveRetrain(state, defaults)
        }
    }

    private static func resolvePlanToday(_ state: CoachState, _ selectedQuestionID: String?,
                                         _ defaults: RouteDefaults) -> RouteResolution {
        guard let plan = state.plan else {
            return .unavailable("还没有学习计划，所以没有「今天的题」。"
                + "下一步：到「学习计划」页选一个 7 / 14 / 30 天的周期，生成一份计划。")
        }
        guard let day = plan.days.first(where: { !$0.isComplete && !$0.questionIds.isEmpty }) else {
            return .unavailable("计划里的题目已经全部练完了。"
                + "下一步：到「学习计划」页重新生成一份计划，或改用「从题库自由选题」。")
        }
        let done = Set(day.completedQuestionIds)
        let pending = day.questionIds.filter { !done.contains($0) }

        // 优先用调用方指定的那道题（用户在今日题目列表里点了哪道就练哪道），
        // 但只认今天还没练的那几道。点一道已经练完的题却当成「按计划练今天」，
        // 计划进度不会前进，用户会以为程序坏了。
        let wanted = selectedQuestionID.flatMap { pending.contains($0) ? $0 : nil } ?? pending.first
        guard let questionID = wanted,
              let question = state.questions.first(where: { $0.id == questionID }) else {
            return .unavailable("今天安排的题目在题库里找不到了（换季重新导入时可能被删掉）。"
                + "下一步：到「学习计划」页重新生成计划，已经练过的进度不会丢。")
        }
        // 计划的「重点 Part」就是用户对这份计划里每一天的明确选择，所以它要跟着进这一场。
        // 不传的话，一份「Part 2 + Part 3 连着练」的计划每天开出来的仍然是普通 Part 2——
        // 计划页显示的考法和真实发生的考法对不上，而屏幕上一个字都不会提（铁律 7）。
        return .ready(setup(for: question, goal: "", defaults: defaults, mode: plan.focusPart,
                            bank: state.questions))
    }

    private static func resolveFreePick(_ state: CoachState, _ selectedQuestionID: String?,
                                        _ defaults: RouteDefaults) -> RouteResolution {
        guard !state.questions.isEmpty else {
            return .unavailable("题库还是空的。下一步：到「训练题库」页导入你的题库文件。")
        }
        guard let id = selectedQuestionID else {
            return .unavailable("还没选题。下一步：先在题目列表里点一道题，再点开始。")
        }
        guard let question = state.questions.first(where: { $0.id == id }) else {
            return .unavailable("题库里没有 id 为「\(id)」的题目。下一步：回题目列表重新选一道。")
        }
        return .ready(setup(for: question, goal: "", defaults: defaults, bank: state.questions))
    }

    private static func resolveContinueLast(_ state: CoachState,
                                            _ defaults: RouteDefaults) -> RouteResolution {
        // startedAt 是 ISO8601 字符串，同一格式下字典序即时间序。
        guard let last = state.sessions.max(by: { $0.startedAt < $1.startedAt }) else {
            return .unavailable("还没有练习记录，没有「上次」可以继续。"
                + "下一步：改用「按计划练今天」或「从题库自由选题」。")
        }
        guard let question = state.questions.first(where: { $0.id == last.questionId }) else {
            return .unavailable("上次练的那道题已经不在题库里了（换季重新导入时可能被删掉）。"
                + "下一步：改用「从题库自由选题」挑一道新的；那次练习的复盘仍然在「复盘报告」页里。")
        }
        // 上次的单点目标一并带上：「继续上次」的意思就是接着上次那件事再练一遍。
        // 上次的**考法**同理，而且要**原样还原**，所以走 `chosen:` 而不是 `mode:`：
        // 上一场是「Part 2 + Part 3 连着练」或者用户勾出来的一整场模考时，
        // `mode:` 那条路会把它降级成单 Part，而卡片上写的是「接着上次那道题再练」。
        return .ready(setup(for: question, goal: last.goal, defaults: defaults,
                            chosen: last.focusPart, bank: state.questions))
    }

    private static func resolveRetrain(_ state: CoachState,
                                       _ defaults: RouteDefaults) -> RouteResolution {
        // rank 已经排除了 status == "retired" 的目标，并把证据命中高频错题的排前面。
        guard let target = RetrainingPolicy.rank(targets: state.targets,
                                                 issues: state.issues).first else {
            return .unavailable("还没有待复训的目标。"
                + "下一步：先练一场并取回复盘，复盘会给出下一次的单点目标。")
        }
        // 空目标带进 ExaminerPrompt，「本次唯一目标」那一整段会被整块跳过，
        // 于是这场「复训」和普通练习一模一样——不报错、不崩溃，只是白练一场。
        // 静默地什么都没发生，是本项目已知最危险的失败形态（spec 2.3.8）。
        //
        // **跨阶段决策 6（2026-08-06）：不拒绝，回落成 targetKey 照常开练。**
        // 用户是来练英语的，因为一个内部字段是空的就不让他练，代价不成比例。
        // 直接复用 Phase 6 的那一份，**不要在这里再写一遍判断**——
        // 同一件事两份实现，迟早会出现「从复训中心进」和「从今日训练页进」不一样。
        let label = RetrainingSetupBuilder.goalText(for: target)
        guard let session = state.sessions.first(where: { $0.id == target.sourceSessionId }) else {
            return .unavailable("找不到这个目标是哪一次练习提出来的（那条训练记录可能被删过）。"
                + "下一步：改用「从题库自由选题」挑一道题，把目标手动写进去。")
        }
        guard let question = state.questions.first(where: { $0.id == session.questionId }) else {
            return .unavailable("这个目标对应的原题已经不在题库里了。"
                + "下一步：改用「从题库自由选题」挑一道同 Part 的题，把目标手动写进去再练一次。")
        }
        return .ready(setup(for: question, goal: label, defaults: defaults, bank: state.questions))
    }

    // MARK: - 可用路线

    /// 只返回**真的能开练**的路线，默认路线排在最前面。
    ///
    /// 「自由选题」是唯一的例外：它天生要先选题才能解析出题目，
    /// 所以它的条件就是「题库非空」。
    public static func availableRoutes(state: CoachState, preferring preferred: PracticeRoute,
                                       defaults: RouteDefaults = RouteDefaults()) -> [PracticeRoute] {
        var usable = PracticeRoute.allCases.filter { route in
            if route == .freePick { return !state.questions.isEmpty }
            if case .ready = resolve(route: route, state: state, defaults: defaults) { return true }
            return false
        }
        // 用户选的默认路线提到最前面，其余保持 PracticeRoute.allCases 的固定顺序。
        // 顺序固定很重要：每次打开卡片位置都在变，用户会点错。
        if let index = usable.firstIndex(of: preferred) {
            usable.remove(at: index)
            usable.insert(preferred, at: 0)
        }
        return usable
    }
}
