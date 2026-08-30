import IELTSCoachCore

/// 「练习偏好」这一栏里的纯文案：四项各自的选项名与那行取舍说明。
///
/// **原来住在 `PlanView` 上**（Phase 8 Task 9 要求 H）。Phase 10 Task 16 把那三项控件
/// 从学习计划页页尾搬进设置窗口时，这些句子跟着控件一起搬——
/// 计划里那句「那三句取舍说明不要删」说的就是这件事：
/// 删掉它们等于让用户面对几个不知道该选哪个的开关。
///
/// 拆成一个 `enum` 而不是留在视图里，理由与 `WeeklyGoalEditor` 完全相同：
/// `View` 测不了，这几句话能测。取值与措辞**逐字**沿用搬家之前那一份。
public enum PracticePreferenceEditor {

    /// 反馈时机的两档。**逐档写全，不用 `default:` 兜底**：
    /// 将来加一档，兜底会把它静默地显示成某个已有选项的名字，编译器一声不吭。
    public static func feedbackTimingTitle(_ timing: FeedbackTiming) -> String {
        switch timing {
        case .deferred: return "全程零反馈"
        case .immediate: return "当场点出"
        }
    }

    public static func part2PrepTitle(_ mode: Part2PrepMode) -> String {
        switch mode {
        case .countdown: return "一分钟倒计时"
        case .learnerControlled: return "自己决定"
        }
    }

    /// **两句话，不是一句。** 第二句是 2026-08-30 合并选题入口之后新出现的行为：
    /// 「从题库自由选题」和「随机抽题练一场」在今日训练页上已经是同一张卡片，
    /// 选哪一条不再改变卡片数量，而是决定**点进去停在哪一档**。
    /// 不说的话，这个设置就在悄悄干一件界面上看不出来的事。
    public static let defaultRouteExplanation =
        "今日训练页会把这条路线排在最前面。"
        + "「从题库自由选题」和「随机抽题练一场」在那一页是同一张卡片，"
        + "选哪一条决定点进去先停在「自己挑」还是「随机抽」。"

    public static let feedbackTimingExplanation =
        "全程零反馈像真考试，但答砸的地方要等到最后才知道；"
        + "当场点出纠正及时，代价是不再是真实考试节奏，单场时间也会拉长。"

    public static let part2PrepExplanation =
        "一分钟倒计时像真考试，练的是压力下组织语言；自己决定适合刚起步时先把内容想清楚。"

    /// 「记录对话逐字稿」下面那一句。**逐字来自 Phase 4**（原先写在训练记录页那个开关下面）。
    ///
    /// 它不是可有可无的：「记录对话」四个字很容易被理解成录音，
    /// 而录音是另一个默认关闭、需要麦克风权限的开关。不写清楚，
    /// 谨慎的用户只会把它关掉，然后训练记录页对他永远是空的。
    public static let transcriptExplanation =
        "开着时，练习中会把考官的问题和你的回答记下来，方便复盘时回看。"
        + "它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网。"

    /// 训练记录页留下的那一行只读现状。**它只说现状 + 去哪儿改，自己不写盘**——
    /// 同一个设置有两个写入口，迟早会出现两个说法不一样的开关（Task 16 决策表第四行）。
    public static func transcriptStatusText(enabled: Bool) -> String {
        "逐字稿记录：\(enabled ? "开" : "关") · 在「设置 › 练习偏好」里更改"
    }
}
