import Foundation

/// 第一次把题库导进来之后，替用户排好第一份学习计划。
///
/// ## 为什么要有这一步
///
/// 引导的最后一步写着「首页已经给你排好今天练什么了，点「开始练习」就行」，
/// 可**导入题库从来不生成计划**——没有计划，「按计划练今天」那张卡片整块不显示，
/// 首页排得出来的唯一路线是「从题库自由选题」。用户每一场都得自己从整份季度题库
/// （几百道题、一张平铺列表）里挑一道，而这正是这个产品声称要替他解决的那件事
///（2026-08-08 复审第 9 条实测）。
///
/// ## 三道闸门，一道都不能少
///
/// - **只在「导入之前题库是空的」时排。** 换季重新导入、以及用户自己在学习计划页
///   删掉计划之后再导一份题库，都不该被这里悄悄塞回一份计划——那是把他明确做过的
///   选择推翻掉，而且一声不吭。
/// - **已经有计划就不动。** 同上，只是更直接：那份计划里有他练过的进度。
/// - **题目不够就不排。** 最短的 7 天计划也要至少 7 道题，
///   否则 `PlanScope.blockingReason` 会拦下来（尾部会出现整天没题可练的空天）。
public enum PlanBootstrap {

    /// 自动排计划时，一天最多排几道题。
    ///
    /// **不是随手定的**：一场练习就是一道题（`SessionSetup` 一场只带一道），
    /// 一天排十几道等于没排。所以在能选的周期里挑**最短**的那一档，
    /// 前提是它平均每天不超过这个数；都超过就退回最长的那一档，把每天的量压到最低。
    public static let maxQuestionsPerDay = 3

    /// 这么多道题该排成几天。排不出来（题目少于最短周期）时返回 nil。
    public static func defaultLength(questionCount: Int) -> Int? {
        // 周期必须 ≤ 题数，否则尾部会出现没题的空天（见 PlanScope.blockingReason）。
        let usable = PlanBuilder.supportedLengths.sorted().filter { $0 <= questionCount }
        guard !usable.isEmpty else { return nil }
        // 向上取整：22 道题排 7 天是「每天 3–4 题」，不是「每天 3 题」。
        let fits = usable.first { (questionCount + $0 - 1) / $0 <= maxQuestionsPerDay }
        return fits ?? usable.last
    }

    /// 这次导入之后要不要自动排一份计划；不排时返回 nil。
    ///
    /// - Parameters:
    ///   - state: **合并完题目之后**的状态。
    ///   - hadQuestionsBefore: 这次导入**之前**题库里有没有题。必须由调用方在同一个
    ///     写事务里取（`StateStore.mutate` 会在锁内重读磁盘，拿事务外那份内存快照会看走眼）。
    public static func planForFirstImport(state: CoachState,
                                          hadQuestionsBefore: Bool,
                                          createdAt: String) -> PlanRegenerationOutcome? {
        guard !hadQuestionsBefore, state.plan == nil else { return nil }
        let selected = PlanScope.select(from: state.questions, focusPart: defaultFocusPart)
        guard let lengthDays = defaultLength(questionCount: selected.count) else { return nil }
        // 生成走 `PlanRegenerator`，不另写一套：它是「生成计划」唯一的实现，
        // 顺带把可行性闸门（PlanScope）和「已练过的题仍算已完成」都带上了。
        //
        // 这里的 `try?` **不是在吞错**：`regenerate` 唯一会抛的是
        // `PlanScope.blockingReason` 那道闸门，而 `defaultLength` 挑出来的周期
        // 一定满足它（`PlanBootstrapTests.testEveryChosenLengthIsActuallyBuildable`
        // 逐个边界跑过）。万一将来那道闸门加了新条件，这里的降级是「这次不自动排」——
        // 用户看到的和从前一模一样（首页给「从题库自由选题」），
        // 而引导文案两种情形都说到了，不会因此变成假话。
        return try? PlanRegenerator.regenerate(state: state, lengthDays: lengthDays,
                                               focusPart: defaultFocusPart, createdAt: createdAt)
    }

    /// 自动排计划用哪个重点 Part。与学习计划页表单的默认值（`PlanDraft`）一致：
    /// 用户还没表达过偏好，全真模考是唯一不替他做取舍的那一档。
    public static let defaultFocusPart: FocusPart = .fullMock

    /// 排好之后要告诉用户的那句话。**必须说出来**：凭空多出一份计划却不吭声，
    /// 用户会以为是上一次用留下的，也不知道去哪儿改。
    ///
    /// 这里不复用 `PlanRegenerationOutcome.summary`：那一句的下一步写的是
    /// 「点「按计划练今天」」，而那是**卡片标题不是按钮**，真正要点的是卡片右下角的
    /// 「开始练习」——指一个点不动的东西比不写还糟（铁律 4）。
    public static func notice(for outcome: PlanRegenerationOutcome) -> String {
        let plan = outcome.plan
        let total = plan.days.flatMap(\.questionIds).count
        let today = plan.days.first { !$0.questionIds.isEmpty }?.questionIds.count ?? 0
        return "顺手替你排了一份 \(plan.lengthDays) 天的学习计划："
            + "\(PlanScope.label(for: plan.focusPart))，共 \(total) 道题，今天先练其中 \(today) 道。"
            + "下一步：回「今日训练」页，「按计划练今天」那张卡片右下角的「开始练习」点下去就能开练；"
            + "想换周期（\(PlanBuilder.supportedLengths.map(String.init).joined(separator: " / ")) 天）"
            + "或者只练某一个 Part，到「学习计划」页重新生成一份，练过的进度不会丢。"
    }
}
