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

    /// 这一页做出来了没有。**Phase 10 Task 18 之后十项全是 `true`。**
    ///
    /// 从前未实现的页面显示的是 `PlaceholderView`（一句「还没做」+ 一句下一步 + 一颗按钮），
    /// 「问题反馈」是最后一项，占位页连同 `SidebarItem.placeholderDescription` /
    /// `placeholderFallback` / `placeholderActionTitle` 一起在本任务里删掉了——
    /// 全都返回空值的属性和只会跑空循环的测试，比没有更糟：它们看着像在守什么。
    ///
    /// **这个 `switch` 是穷尽的，不写 `default`。** 将来真要往侧边栏加第十一项，
    /// 编译器会在这里、在 `title`、在 `systemImage`、在 `RootView.detail` 四处同时报错，
    /// 而不是默默给出一个 `false` 再摆一页空白。
    public var isImplemented: Bool {
        switch self {
        case .today, .questionBank, .plan, .retraining, .reviewReports,
             .upgrade, .feedback, .history, .issues, .vocabulary: return true
        }
    }
}

/// 侧边栏的分组。
///
/// **十项平铺是这条侧边栏最大的问题。** 一列十个同样粗细、同样间距的条目，
/// 用户找「问题档案」时只能从上到下读一遍——列表没有形状，就没有肌肉记忆。
/// 分完组之后每组三四项，落点由「在第几组」加「组里第几个」两级定位。
///
/// 分组只影响**怎么摆**，不影响有哪些页面：`items` 拼起来必须恰好是
/// `SidebarItem.allCases`，`NavigationTests` 逐项对着这条。
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case practice, review, library

    public var id: String { rawValue }

    /// 组标题。**用中文，不用英文缩写**：侧边栏是这个 App 里最常被扫的一列，
    /// 组标题要一眼认出来，不该让人先翻译一次。
    public var title: String {
        switch self {
        case .practice: return "练习"
        case .review: return "复盘"
        case .library: return "资料与设置"
        }
    }

    /// 这一组里有哪几页，顺序就是屏幕上的顺序。
    ///
    /// **顺序不是随手排的**：每一组的第一项是这一组里最常去的那一页
    /// （今日训练 / 复盘报告 / 我的词汇）。
    public var items: [SidebarItem] {
        switch self {
        case .practice: return [.today, .questionBank, .plan, .retraining]
        case .review: return [.reviewReports, .history, .issues]
        case .library: return [.vocabulary, .upgrade, .feedback]
        }
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
        case .upgrade: self = .upgrade
        case .feedback: self = .feedback
        }
    }
}
