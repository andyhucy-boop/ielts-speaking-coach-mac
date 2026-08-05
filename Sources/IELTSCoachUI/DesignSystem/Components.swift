import SwiftUI

// 基础组件。规范见 `docs/superpowers/DESIGN-SYSTEM.md` 第 4 节。
//
// 三个页面必须用这几个组件搭。理由不是「省代码」，而是：各写各的会出现三种不同的
// 卡片样式——圆角差 2pt、边框深浅不一、内边距各不相同。这正是界面显得业余的头号原因，
// 而且它不会体现在任何一条测试上，只会让人觉得「说不上哪儿不对」。
//
// 组件里出现的每一个颜色、字号、圆角、间距都必须来自令牌。组件是最后一道防线：
// 这里破一个例，三个页面就跟着破三次。

/// 卡片。白底、圆角 `Radius.card`、发丝边框、**不加投影**。
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

/// 主行动卡片。紫色填充、白字，用于「今天想怎么练？」那块。
///
/// **每个页面最多一个。** 两个同样醒目的紫色大块会让人不知道该点哪个，
/// 所以这个组件刻意做成「一块 + 一个动作」，而不是能随处套用的容器——
/// 想放第二个次级动作，用 `CoachCard`。
///
/// `detail` 用来放这次行动的具体内容（例如今天要练的两道题）。它不参与点击，
/// 真正的动作只有右下那一个按钮。
///
/// 按钮做成白底紫字而不是系统的醒目按钮样式：紫底上再放一个紫色按钮会糊成一片，
/// 而白底紫字这一对的对比度有测试守着（`testTextOnAccentMeetsAA`，5.5:1）。
public struct PrimaryActionCard<Detail: View>: View {
    private let title: String
    private let subtitle: String
    private let actionTitle: String
    private let action: () -> Void
    private let detail: Detail

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
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.title2).fontWeight(.semibold)
                // 副标题同样用满不透明度的白。在紫底上把白字调淡是很自然的手势，
                // 但白色降到 80% 后对比度就掉到 4.1:1，跌破底线——层级靠字号区分，不靠调淡。
                Text(subtitle).font(.callout)
            }
            detail
            HStack {
                Spacer(minLength: Spacing.md)
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Palette.card,
                                    in: RoundedRectangle(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Palette.accent)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .foregroundStyle(Palette.textOnAccent)
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

/// 区块标题。设计稿的写法：小号编号 + 全大写英文标签 + 中文标题。
///
/// ```
/// 01  PRACTICE ROUTES
/// 今天练什么？
/// ```
///
/// 编号用两位数（`01` 而不是 `1`），且用等宽数字——编号列表里宽度不齐会很显眼。
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
            HStack(spacing: Spacing.sm) {
                Text(String(format: "%02d", number)).monospacedDigit()
                Text(label)
            }
            .font(.caption)
            .tracking(Tracking.label)
            .foregroundStyle(Palette.textSecondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 空状态。**三样缺一不可：一句说明现状、一句说明下一步、一个能直接点的按钮。**
///
/// 三个参数都不是可选的，就是为了让「只写一句『暂无数据』」这种写法编不过去。
/// 空白页会让用户以为程序坏了——这与本项目对错误文案的硬性要求（说清「发生了什么 +
/// 下一步做什么」）是同一条规矩，只是换了个场合。
///
/// 只写前两样也不够：光说「可以先去导入题库」，用户读完还得自己回去翻侧边栏找入口。
public struct EmptyStateView: View {
    private let message: String
    private let hint: String
    private let actionTitle: String
    private let action: () -> Void

    public init(message: String, hint: String, actionTitle: String,
                action: @escaping () -> Void) {
        self.message = message
        self.hint = hint
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(message)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            Text(hint)
                .font(.callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview("卡片与区块标题") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        SectionHeader(number: 1, label: "PRACTICE ROUTES", title: "今天练什么？")
        PrimaryActionCard(title: "按计划练今天",
                          subtitle: "按学习计划安排的今日题目",
                          actionTitle: "开始练习") {} detail: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Part 1 · Describe your hometown").font(.body)
                Text("Part 2 · A skill you learned recently").font(.body)
            }
        }
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("本周训练").font(.headline)
                Text("3/5 次").font(.title).monospacedDigit()
                Text("还差两次达成本周目标。").font(.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
    .padding(Spacing.xl)
    .background(Palette.canvas)
}

#Preview("空状态") {
    EmptyStateView(message: "题库还是空的",
                   hint: "先导入你的雅思口语题库，才能开始练习。",
                   actionTitle: "导入题库…") {}
        .background(Palette.canvas)
}
