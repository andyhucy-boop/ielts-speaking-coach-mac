import Foundation

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
        case .today, .questionBank, .reviewReports: return true
        default: return false
        }
    }

    /// 占位页上「将来会有什么」那一句。
    ///
    /// 放在这里而不是视图里，是为了让「有没有哪一页会摆出一片空白」这件事有测试管得住——
    /// 视图里的 `switch` 写漏一个分支只会安静地返回空字符串，没人看得见。
    /// 已实现的页面不需要占位说明，返回空串。
    public var placeholderDescription: String {
        switch self {
        case .today, .questionBank, .reviewReports: return ""
        case .plan: return "将来在这里选 7/14/30 天周期、定重点 Part，并看每日拆分。"
        case .retraining: return "将来在这里挑一个复盘里的目标，带着它重练，再换题验证。"
        case .history: return "将来在这里按月回看每次练习的题目、复盘和录音。"
        case .issues: return "将来在这里看反复出现的问题，以及它们有没有变少。"
        case .vocabulary: return "将来在这里看积累的词汇，并导出到 Anki。"
        case .upgrade: return "将来在这里看新版本与更新说明。"
        case .feedback: return "将来在这里反馈问题。"
        }
    }
}

/// 根视图当前该显示哪一屏。
public enum RootScreen: Equatable, Sendable {
    /// 环境检查还没出结论。
    case checkingEnvironment
    /// 环境不就绪，挡一道授权引导。
    case permissionGate
    /// 侧边栏 + 内容区的主界面。
    case workspace
}

/// 「什么时候挡、什么时候放行」抽成纯函数，因为这段判断错了用户是直接撞墙的，
/// 而 `View` 里的 `if` 没有任何测试管得住。
public enum RootRouter {
    public static func screen(isCheckingPermission: Bool,
                              permission: PermissionState,
                              permissionSkipped: Bool) -> RootScreen {
        // 用户明确点了「先跳过」就不能再把他挡在外面，包括「又开始检查了」这种理由——
        // 那等于点了跳过却没进去。
        if permissionSkipped { return .workspace }
        // 检查没跑完时 permission 还是初始的 .unknown。照它渲染，用户开机第一眼看到的
        // 会是「环境检查没通过」——一句还没查就下的结论。
        if isCheckingPermission { return .checkingEnvironment }
        return permission == .ready ? .workspace : .permissionGate
    }
}
