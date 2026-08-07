import Foundation
import IELTSCoachCore

/// 侧边栏十项，与产品设计稿一致。
public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case today, questionBank, plan, retraining, reviewReports
    case upgrade, feedback, history, issues, vocabulary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今日训练"
        case .questionBank: return "训练题库"
        case .plan: return "学习计划"
        case .retraining: return "复训中心"
        case .reviewReports: return "复盘报告"
        case .upgrade: return "功能升级"
        case .feedback: return "问题反馈"
        case .history: return "训练记录"
        case .issues: return "问题档案"
        case .vocabulary: return "我的词汇"
        }
    }

    /// 只用 SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
    /// 名字打错不会报错，只会渲染成空白，所以 `NavigationTests` 里当场问系统认不认。
    public var systemImage: String {
        switch self {
        case .today: return "house"
        case .questionBank: return "list.bullet.rectangle"
        case .plan: return "calendar"
        case .retraining: return "arrow.triangle.2.circlepath"
        case .reviewReports: return "doc.text"
        case .upgrade: return "arrow.up.circle"
        case .feedback: return "bubble.left"
        case .history: return "clock"
        case .issues: return "exclamationmark.triangle"
        case .vocabulary: return "textformat.abc"
        }
    }

    /// 本阶段是否已实现。未实现的显示占位页，写明「这一页还没做」和它将来会有什么，
    /// 而不是空白——空白会让用户以为坏了。
    public var isImplemented: Bool {
        switch self {
        // Phase 4 加了 .history，Phase 6 加了 .retraining，Phase 7 Task 6 加了 .issues、
        // Task 7 加了 .vocabulary，Phase 8 Task 9 加了 .plan，Phase 10 Task 17 加了 .upgrade。
        // 后续阶段各自往这里加自己的那一项，不要删别人的。
        case .today, .questionBank, .reviewReports, .history, .retraining, .issues,
             .vocabulary, .plan, .upgrade: return true
        default: return false
        }
    }

    /// 占位页上的说明：**将来会有什么 + 现在该干什么**。
    ///
    /// 两句缺一不可。只写「将来会有」等于把用户扔在一页死路上——铁律 6 的
    /// 「发生了什么 + 下一步做什么」不只管错误信息，空状态与界面提示同样算数
    /// （DESIGN-SYSTEM 第 4 节「空状态（必须有，不能留白）」）。
    ///
    /// 「下一步」那句里必须点名 `placeholderFallback` 那一页，好跟下面的按钮对上；
    /// 两边指向不同的页面，用户不知道该信哪个。`NavigationTests` 守着这件事。
    ///
    /// 放在这里而不是视图里，是为了让「有没有哪一页会摆出一片空白」这件事有测试管得住——
    /// 视图里的 `switch` 写漏一个分支只会安静地返回空字符串，没人看得见。
    /// 已实现的页面不需要占位说明，返回空串。
    public var placeholderDescription: String {
        switch self {
        case .today, .questionBank, .reviewReports, .history, .retraining, .issues,
             .vocabulary, .plan, .upgrade: return ""
        case .feedback:
            return "将来在这里一键复制诊断信息（版本、系统、环境检查结果），你自己决定粘给谁。"
                + "下一步：这一页没做完不影响练习，可以直接到「今日训练」继续练；"
                + "现在就想报问题，先把现象和当时的报错原文原样记下来。"
        }
    }

    /// 占位页上那个按钮点下去要去的页面——**现在就做得到的那件事在哪一页**。
    ///
    /// DESIGN-SYSTEM 第 4 节要求空状态给三样东西：一句现状、一句下一步、一个能点的按钮。
    /// 光有前两样，用户读完还得自己回去翻侧边栏。
    ///
    /// 落点必须是一页**真做出来了**的页面（`isImplemented == true`）：
    /// 把人从一个「还没做」送到另一个「还没做」，比不给按钮更气人。
    /// 已实现的页面返回 nil——那儿不该冒出一个劝用户走开的按钮。
    public var placeholderFallback: SidebarItem? {
        switch self {
        case .today, .questionBank, .reviewReports, .history, .retraining, .issues,
             .vocabulary, .plan, .upgrade: return nil
        case .feedback: return .today
        }
    }

    /// 占位页那个按钮上的字。由 `placeholderFallback` 推出来，不单独维护一份——
    /// 按钮写着「去复盘报告」却跳到今日训练，是照着两个 `switch` 手写时的经典翻车。
    public var placeholderActionTitle: String {
        guard let target = placeholderFallback else { return "" }
        return "去「\(target.title)」"
    }
}

/// 根视图当前该显示哪一屏。
public enum RootScreen: Equatable, Sendable {
    /// 环境检查还没出结论。
    case checkingEnvironment
    /// 首次使用引导（`WelcomeFlowView`）。**原名 `permissionGate`**：
    /// 那时挡在前面的只有讲权限的 `PermissionGateView`，现在它是引导里的一步
    /// （「让它能替你操作 ChatGPT」），挡在前面的是整条引导。
    case onboarding
    /// 侧边栏 + 内容区的主界面。
    case workspace
}

/// 「什么时候挡、什么时候放行」抽成纯函数，因为这段判断错了用户是直接撞墙的，
/// 而 `View` 里的 `if` 没有任何测试管得住。
public enum RootRouter {
    /// - Parameters:
    ///   - questionCount: 题库里有多少道题。只影响引导**内容**（题库已经有题就不问导入），
    ///     不影响弹不弹——但仍要传进来，好让这一处和 `OnboardingFlow.steps` 永远同一份输入。
    ///   - hasCompletedOnboarding: 磁盘上记着的「引导看过没有」（`OnboardingProgressStore`）。
    ///   - onboardingDismissed: 这次启动里引导已经收工了（`AppState.onboardingDismissed`）。
    public static func screen(isCheckingPermission: Bool,
                              permission: PermissionState,
                              questionCount: Int,
                              hasCompletedOnboarding: Bool,
                              onboardingDismissed: Bool) -> RootScreen {
        // 引导这次已经收工了就不能再把他挡在外面，包括「又开始检查了」这种理由——
        // 那等于走完了引导却没进去。也包括「权限还是缺的」：在最后一步点了「先跳过」
        // 之后立刻又弹回同一屏，是这条流程最容易犯、也最让人恼火的错。
        if onboardingDismissed { return .workspace }
        // 检查没跑完时 permission 还是初始的 .unknown。照它渲染，**已经走过引导的老用户**
        // 开机第一眼会看到「让它能替你操作 ChatGPT」那一步——一句还没查就下的结论。
        // （这一条计划里的 RootView 代码片段漏掉了，见 Task 8 的实施记录。）
        if isCheckingPermission { return .checkingEnvironment }
        return OnboardingFlow.shouldPresent(permission: permission,
                                            questionCount: questionCount,
                                            hasCompletedBefore: hasCompletedOnboarding)
            ? .onboarding : .workspace
    }

    /// 用户自己切了一页之后，「从『训练记录』点『看这次的复盘』带过来的那一场」还留不留。
    ///
    /// **换了一页就必须清掉。** 不清的话这个值只写不清：用户点过一次之后它永远停在那一场，
    /// 而复盘页里「用户自己点的那一次」是 `@State`，detail 那个 `switch` 换过分支再换回来时
    /// 会重新初始化成 nil——于是此后每一次从侧边栏点「复盘报告」，落到的都是那一场旧的，
    /// 而不是那个属性承诺的「没点过时落回最近的那一次」。用户练完新的一场点进复盘报告，
    /// 看到的是几天前那一场：内容看着完全正常，但是别人家的，比一片空白更难被发现。
    ///
    /// **页面没换就保持原样。** `RootView` 里那句 `selection = .reviewReports` 是跳转本身，
    /// SwiftUI 的 `List(selection:)` 有可能把同一个值再从绑定写回来一次；
    /// 那一下不是用户切页，跟着清掉的话跳过去看到的还是最近那一场——
    /// 等于把要修的毛病换个方向再犯一遍。
    ///
    /// 抽成纯函数是因为这段判断错了用户是直接看到别人家复盘的，
    /// 而 `View` 里的一句赋值没有任何测试管得住（`NavigationTests` 钉着这两条）。
    public static func carriedReviewSession(_ carried: String?,
                                           navigatingFrom current: SidebarItem?,
                                           to next: SidebarItem?) -> String? {
        next == current ? carried : nil
    }
}

extension SidebarItem {
    /// 深链接路由 → 侧边栏页面。switch 是穷尽的，
    /// 将来 CoachRoute 加了 case 而这里忘了映射，编译期就会红。
    public init(route: CoachRoute) {
        switch route {
        case .dashboard, .today: self = .today
        case .questions: self = .questionBank
        case .plan: self = .plan
        case .retraining: self = .retraining
        case .reviews: self = .reviewReports
        case .history: self = .history
        case .issues: self = .issues
        case .vocabulary: self = .vocabulary
        }
    }
}
