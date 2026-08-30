import CoreGraphics

/// 间距令牌。取值逐字来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 3 节，统一 4 的倍数。
///
/// **页面内边距统一 `xl`（32），卡片内边距 `lg`（24）。**
/// 设计稿里的留白很足，那是它显得高级的主要原因——不要为了多塞内容压缩留白。
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let section: CGFloat = 40   // 大区块之间
}

/// 圆角令牌。同上，逐字来自第 3 节。
public enum Radius {
    /// 页面级的大面板（首屏那张主行动卡、复盘页顶上那条目标横幅）。
    ///
    /// 大块面用 12 会显得「方」——圆角要跟着面积走，同一个半径贴在 1000pt 宽的面板上
    /// 和贴在 200pt 宽的小卡上，看着不是一回事。
    public static let panel: CGFloat = 16
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}

/// 描边宽度。规范第 4 节要求卡片用「发丝边框」分层，不用投影。
///
/// 单独立个令牌而不是在视图里写 `lineWidth: 1`，理由和颜色一样：
/// 边框粗细一旦散落到各个视图里，就再没有「统一改一次」的机会了。
public enum BorderWidth {
    public static let hairline: CGFloat = 1
    /// 选中、悬停、以及需要点名的那一块用的粗边。
    ///
    /// **上限就是 2。** 再粗一档就从「这一块被选中了」变成「这一块被框起来了」，
    /// 而规范第 4 节的分层手段是边框与留白，不是画框。
    public static let emphasis: CGFloat = 2
}

/// 字距。规范第 4 节：区块标题的编号与英文标签「字距略宽」。
public enum Tracking {
    /// 小标签。`.caption`（约 11pt）下约合 11%，看得出是标签而不至于散架。
    public static let label: CGFloat = 1.2
    /// 区块眉标（`01 PRACTICE ROUTES`）。它比 `label` 更小（`.caption2`，约 10pt）
    /// 也更重，所以字距要再放宽一档，否则那几个大写字母会挤成一坨。
    public static let overline: CGFloat = 1.6
}

/// 行距（在语义字体自带行高之上**额外**加的那几点）。
///
/// 这个令牌是给中文正文加的。SwiftUI 默认行距是按拉丁文字设计的，
/// 中文方块字在同样的行距下会显得「贴在一起」——一段五行的中文说明读起来像一堵墙。
/// 规范第 1 节因此多了一列「行距」。
///
/// **不是所有文字都要加行距。** 标题只有一行，加了只会让它和下一行的间距失控；
/// 所以 `tight` 是 0，写出来是为了让「这一处刻意不加」这件事在代码里看得见。
public enum LineHeight {
    /// 标题、单行标签：不额外加。
    public static let tight: CGFloat = 0
    /// 中文正文段落。13pt 上加 5pt，约合 1.4 倍行高。
    public static let body: CGFloat = 5
    /// 需要逐字读的长段（复盘报告的总结、考官提示词预览）。约合 1.55 倍。
    public static let relaxed: CGFloat = 8
}

/// 版面尺寸。
///
/// **`readingMaxWidth` 是这次改版里效果最大的一个令牌。** 改版前整个 App 一处宽度限制都没有：
/// 窗口拉到 1728pt 时，复盘报告的中文段落就是一行 1100pt、上百个字——
/// 眼睛读完一行找不回下一行的行首。卡片同理：标题在最左边、按钮被 `Spacer` 顶到最右边，
/// 中间空出 900pt，看着像布局坏了。
///
/// 两档而不是一档：正文要窄（读），列表与网格可以宽（扫）。
public enum Layout {
    /// 连续中文/英文段落的最大宽度。约 60–75 个西文字符、35–45 个汉字一行。
    public static let readingMaxWidth: CGFloat = 720
    /// 页面内容整体的最大宽度（列表、网格、卡片列）。
    public static let contentMaxWidth: CGFloat = 1040
    /// 侧边栏宽度。十项中文标题里最长的是「复盘报告」四个字加图标，220 够且不空。
    public static let sidebarWidth: CGFloat = 220
    /// 主行动卡片左边那道主色竖条的宽度。
    public static let railWidth: CGFloat = 4
    public static let minWindowWidth: CGFloat = 960
    public static let minWindowHeight: CGFloat = 640
}

/// 动效时长（秒）。规范第 5 节：微交互 150–250ms，且**必须尊重「减弱动态效果」**。
///
/// 只存时长、不存 `Animation` 值，是为了让 `DesignSystemTests` 能逐个把它们钉住——
/// 这三个数字散到视图里的话，会出现「这一处 0.15、那一处 0.4」的节奏不齐，
/// 而那种不齐没人指得出来，只会觉得整个界面「手感不一致」。
///
/// **视图不要自己写 `.animation(...)`，用 `View.coachAnimation(_:value:)`**
/// （在 `Components.swift`）：那个修饰符自己读「减弱动态效果」，
/// 于是这条无障碍要求由构造保证，而不是靠每个调用点记得写那个三元表达式。
public enum Motion {
    /// 悬停、按下这类跟手的反馈。
    public static let quick: Double = 0.16
    /// 展开、切换、内容替换。规范第 5 节那一档的中值。
    public static let standard: Double = 0.22
    /// 整屏过渡。**上限就是它**，第 5 节的红线是 250ms 级的微交互，
    /// 这一档已经是给「换了一整屏」留的余量。
    public static let deliberate: Double = 0.32
}
