import SwiftUI

// 基础组件。规范见 `docs/superpowers/DESIGN-SYSTEM.md` 第 4 节。
//
// 页面必须用这几个组件搭。理由不是「省代码」，而是：各写各的会出现三种不同的
// 卡片样式——圆角差 2pt、边框深浅不一、内边距各不相同。这正是界面显得业余的头号原因，
// 而且它不会体现在任何一条测试上，只会让人觉得「说不上哪儿不对」。
//
// 组件里出现的每一个颜色、字体、圆角、间距都必须来自令牌。组件是最后一道防线：
// 这里破一个例，每个页面就跟着破一次。
//
// 字体走 `Typography`，不写 `Font` 的语义字体、也不在这里单独指定字重——
// 规范第 1 节的字体表里字重是单独一列，写在视图里就等于把那一列交给了视图。

// MARK: - 动效：把「减弱动态效果」焊进构造里

/// 一个尊重系统「减弱动态效果」的 `.animation(_:value:)`。
///
/// **视图请一律用它，不要自己写 `.animation(...)`。** 规范第 5 节那条
/// 「必须尊重减弱动态效果」从前靠每个调用点记得写 `reduceMotion ? nil : …` 这个三元表达式，
/// 而漏写的那一处不会报错、不会变红，只会在开了那个开关的人机器上照样动——
/// 那正是无障碍要求最典型的失守方式。收进修饰符之后，这件事由构造保证。
private struct CoachAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: Double
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeOut(duration: duration), value: value)
    }
}

extension View {
    /// 规范第 5 节的过渡。时长只能从 `Motion` 里取。
    public func coachAnimation<Value: Equatable>(_ duration: Double = Motion.standard,
                                                 value: Value) -> some View {
        modifier(CoachAnimation(duration: duration, value: value))
    }

    /// 中文正文段落的行距。**长段中文必须加**，理由见 `LineHeight`。
    public func coachParagraph(_ height: CGFloat = LineHeight.body) -> some View {
        lineSpacing(height).fixedSize(horizontal: false, vertical: true)
    }

    /// 把一段内容限制在易读的栏宽里，并靠左。
    ///
    /// **凡是连续段落都该套上它。** 不套的话，窗口拉宽时一行会长到上百个字，
    /// 眼睛读完一行找不回下一行的行首（规范第 3 节）。
    public func coachReadingColumn() -> some View {
        frame(maxWidth: Layout.readingMaxWidth, alignment: .leading)
    }
}

extension View {
    /// 页面正文的版式：页面内边距 + 最大宽度 + 居中。
    ///
    /// 给那些外壳形状各异、套不进 `CoachPage` 的页面用（例如「训练记录」是
    /// 左右两栏而不是一条竖列）。**这两件事必须一处定**：改版前十个页面各写一遍
    /// `.padding(Spacing.xl)`，而最大宽度一个页面都没写——于是窗口一拉宽，
    /// 每一页都变成一条一千多点宽的长文。
    public func coachPageBody() -> some View {
        padding(Spacing.xl)
            .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - 页面骨架

/// 一整页的外壳：滚动、页面内边距、最大宽度、内容区底色。
///
/// **改版前这四样是每个页面各写一遍的**，于是「页面内边距 32」这条规范在十个页面里
/// 有十次走样的机会；更要命的是没有任何一页限过最大宽度，窗口拉到 1700pt 时
/// 每张卡片都被拉成 1100pt 宽的长条，按钮被 `Spacer` 顶到一千点开外。
public struct CoachPage<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                content
            }
            .padding(Spacing.xl)
            .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
            // 外面这一层负责把上面那块**居中**：窗口比 contentMaxWidth 宽时，
            // 内容停在中间而不是贴着侧边栏堆在左边。
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.canvas)
    }
}

/// 页头：眉标 + 大标题 + 一句话说明。
///
/// 眉标的写法来自设计稿：`01  TODAY`。编号用两位数且等宽——编号列表里宽度不齐很显眼。
public struct PageHeader: View {
    private let number: Int
    private let label: String
    private let title: String
    private let lede: String?

    public init(number: Int, label: String, title: String, lede: String? = nil) {
        self.number = number
        self.label = label
        self.title = title
        self.lede = lede
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Overline(number: number, label: label)
            Text(title)
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
            if let lede {
                Text(lede)
                    .font(Typography.lede)
                    .foregroundStyle(Palette.textSecondary)
                    .coachParagraph()
                    .coachReadingColumn()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 眉标那一行：`01  PRACTICE ROUTES`。
///
/// 编号用主色、标签用次要文字色：这一行是**两样东西**——第几块、这块叫什么。
/// 全用同一个灰的话它就成了一串没人读的字母。
public struct Overline: View {
    private let number: Int
    private let label: String

    public init(number: Int, label: String) {
        self.number = number
        self.label = label
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(String(format: "%02d", number))
                .font(Typography.overline)
                .monospacedDigit()
                .foregroundStyle(Palette.accent)
            Text(label)
                .font(Typography.overline)
                .foregroundStyle(Palette.textSecondary)
        }
        .tracking(Tracking.overline)
    }
}

/// 区块标题。设计稿的写法：小号编号 + 全大写英文标签 + 中文标题。
///
/// ```
/// 01  PRACTICE ROUTES
/// 今天练什么？
/// ```
public struct SectionHeader: View {
    private let number: Int
    private let label: String
    private let title: String

    public init(number: Int, label: String, title: String) {
        self.number = number
        self.label = label
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Overline(number: number, label: label)
            Text(title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 卡片

/// 卡片。圆角 `Radius.card`、发丝边框、**不加投影**。
///
/// 设计稿里的卡片靠边框和留白分层，不靠阴影。滥用投影是让界面显脏的常见原因。
public struct CoachCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline))
            .foregroundStyle(Palette.textPrimary)
    }
}

/// 整块都能点的卡片。
///
/// **这是这次改版里最要紧的一条交互修正。** 改版前每张卡片的动作是右下角那颗小按钮，
/// 而卡片宽 1000pt——标题在最左边，要点的东西在一千点开外，中间是一大片什么也没有的白。
/// 卡片本来就长得像一个可点的东西，用户的第一下多半点在卡片上，然后什么也不发生。
///
/// 整块可点之后，那颗按钮从「唯一的入口」降级成「这里可以点」的说明，
/// 位置也就不再要紧；右边那个箭头是给「这一块点得动」的第二个提示。
public struct CoachActionCard<Content: View>: View {
    private let actionLabel: String
    private let action: () -> Void
    private let content: Content
    @State private var isHovering = false

    public init(actionLabel: String, action: @escaping () -> Void,
                @ViewBuilder content: () -> Content) {
        self.actionLabel = actionLabel
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.md) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(isHovering ? Palette.accent : Palette.textSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Palette.surfaceSubtle : Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(isHovering ? Palette.cardBorderStrong : Palette.cardBorder,
                                  lineWidth: BorderWidth.hairline))
            .foregroundStyle(Palette.textPrimary)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .onHover { isHovering = $0 }
        .coachAnimation(Motion.quick, value: isHovering)
        .accessibilityLabel(actionLabel)
    }
}

/// 主行动卡片。主色填充、白字，用于「今天想怎么练？」那一块。
///
/// **每个页面最多一个。** 两个同样醒目的主色大块会让人不知道该点哪个。
///
/// 和 `CoachActionCard` 一样**整块可点**。
///
/// 改版前它是一片 1000×130 的实心高饱和色块：宽度不设限，标题贴在最左、按钮被顶到最右，
/// 中间空出九百多点。现在宽度收在 `Layout.contentMaxWidth` 里，动作按钮也回到了内容旁边。
public struct PrimaryActionCard<Detail: View>: View {
    private let title: String
    private let subtitle: String
    private let actionTitle: String
    private let action: () -> Void
    private let detail: Detail
    @State private var isHovering = false

    public init(title: String, subtitle: String, actionTitle: String,
                action: @escaping () -> Void,
                @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.detail = detail()
    }

    public var body: some View {
        Button(action: action) {
            inner
            .background(Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.panel)
                    .strokeBorder(isHovering ? Palette.textOnAccent : Palette.accent,
                                  lineWidth: BorderWidth.emphasis))
            .foregroundStyle(Palette.textOnAccent)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.panel))
        .onHover { isHovering = $0 }
        .coachAnimation(Motion.quick, value: isHovering)
        .accessibilityLabel("\(title)。\(actionTitle)")
    }

    private var inner: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(Typography.cardTitle)
                    // 副标题同样用满不透明度的白。在主色底上把白字调淡是很自然的手势，
                    // 但白色降到 80% 后对比度就掉到 4.1:1，跌破底线——层级靠字号区分，不靠调淡。
                    Text(subtitle).font(Typography.secondary)
                }
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 白底主色字这一对的对比度有测试守着（5.5:1）。
            // 主色底上再放一个主色按钮会糊成一片，所以这里翻面。
            HStack(spacing: Spacing.xs) {
                Text(actionTitle).font(Typography.action)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control))
            .fixedSize()
        }
        .padding(Spacing.lg)
    }
}

extension PrimaryActionCard where Detail == EmptyView {
    /// 不需要额外内容时的简写。
    public init(title: String, subtitle: String, actionTitle: String,
                action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, actionTitle: actionTitle,
                  action: action, detail: { EmptyView() })
    }
}

// MARK: - 小件

/// 标记用的小胶囊：`Part 1`、`没练过`、`6 条`。
///
/// 一屏几十行的列表（题库、训练记录）靠它把「这是什么」从行标题里拆出来。
/// 改版前这些信息是一行小灰字跟在标题后面，扫一眼分不出哪个是题目、哪个是状态。
public struct CoachBadge: View {
    public enum Kind: Sendable { case neutral, accent, success, warning, danger }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(Typography.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.control))
    }

    private var foreground: Color {
        switch kind {
        case .neutral: return Palette.textSecondary
        case .accent: return Palette.accent
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }

    /// 语义色目前共用 `surfaceSubtle` 作底。
    /// **不给它们各配一块浅色底**：那需要 success/warning/danger 各一个浅底令牌，
    /// 每个都得单独验两套外观的对比度，而这里要的只是「把这几个字圈出来」。
    private var background: Color {
        kind == .accent ? Palette.accentSoft : Palette.surfaceSubtle
    }
}

/// 一句提示。图标 + 文字（+ 可选的按钮），按语气分四种颜色。
///
/// **改版前这块在六个地方各手搓了一遍**，图标、间距、边框各不相同。
/// 它承载的又恰恰是本项目最要紧的那类文字——「发生了什么 + 下一步做什么」。
public struct NoticeCard<Actions: View>: View {
    public enum Kind: Sendable { case info, success, warning, danger }

    private let kind: Kind
    private let text: String
    private let actions: Actions

    public init(_ kind: Kind, _ text: String, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.text = text
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .coachParagraph()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(tint, lineWidth: BorderWidth.hairline))
    }

    private var tint: Color {
        switch kind {
        case .info: return Palette.accent
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .danger: return "xmark.octagon"
        }
    }
}

extension NoticeCard where Actions == EmptyView {
    public init(_ kind: Kind, _ text: String) {
        self.init(kind, text, actions: { EmptyView() })
    }
}

/// 空状态。**三样缺一不可：一句说明现状、一句说明下一步、一个能直接点的按钮。**
///
/// 三个参数都不是可选的，就是为了让「只写一句『暂无数据』」这种写法编不过去。
/// 空白页会让用户以为程序坏了——这与本项目对错误文案的硬性要求（说清「发生了什么 +
/// 下一步做什么」）是同一条规矩，只是换了个场合。
public struct EmptyStateView: View {
    private let symbol: String
    private let message: String
    private let hint: String
    private let actionTitle: String
    private let action: () -> Void

    public init(symbol: String = "tray", message: String, hint: String,
                actionTitle: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.message = message
        self.hint = hint
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textSecondary)
            VStack(spacing: Spacing.xs) {
                Text(message)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(hint)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .coachParagraph()
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
        }
        .padding(Spacing.section)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline))
    }
}

#Preview("卡片与区块标题") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            PageHeader(number: 1, label: "TODAY", title: "今日训练",
                       lede: "早上好。今天是 Sunday, 30 August 2026。")
            SectionHeader(number: 2, label: "PRACTICE ROUTES", title: "今天练什么？")
            PrimaryActionCard(title: "按计划练今天",
                              subtitle: "按学习计划安排的今日题目",
                              actionTitle: "开始练习") {} detail: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Part 1 · Describe your hometown").font(Typography.body)
                    Text("Part 2 · A skill you learned recently").font(Typography.body)
                }
            }
            CoachActionCard(actionLabel: "随机抽题练一场", action: {}) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("随机抽题练一场").font(Typography.cardTitle)
                    Text("自己定每个 Part 抽几道").font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            HStack(spacing: Spacing.sm) {
                CoachBadge("Part 1")
                CoachBadge("没练过", kind: .accent)
                CoachBadge("已归档", kind: .success)
            }
            NoticeCard(.warning, "这个目标来自的那次练习记录已经不在了。下一步：仍然可以带着它自己挑一道题练。")
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("本周训练").font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text("3/5 次").font(Typography.numberHero)
                    Text("还差两次达成本周目标。").font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(Spacing.xl)
    }
    .background(Palette.canvas)
}

#Preview("空状态") {
    EmptyStateView(symbol: "tray",
                   message: "题库还是空的",
                   hint: "先导入你的雅思口语题库，才能开始练习。",
                   actionTitle: "导入题库…") {}
        .padding(Spacing.xl)
        .background(Palette.canvas)
}
