import SwiftUI

/// 侧边栏。
///
/// ## 为什么要自己画，而不是用系统的 `List`
///
/// 设计稿里的侧边栏是深紫色的，`Palette` 里也一直躺着四个为它定好、
/// 而且逐项验过对比度的令牌（`sidebarBackground` / `sidebarText` /
/// `sidebarTextSelected` / `sidebarHighlight`）。**但屏幕上那条侧边栏一个都没用过**——
/// 从 Phase 3 起它就是一个系统默认样式的 `List`，令牌只在复盘页一个装饰性标题上出现过。
/// 也就是说：这个 App 最显眼的那一块，一直没有被设计过。
///
/// 自己画之后拿回三样东西：分组（十项平铺没有形状）、悬停反馈（桌面应用没有悬停
/// 会显得是死的）、以及那套深色配色。
struct SidebarView: View {
    let selection: SidebarItem
    let onSelect: (SidebarItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                brand
                ForEach(SidebarSection.allCases) { section in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(section.title)
                            .font(Typography.overline)
                            .tracking(Tracking.overline)
                            .foregroundStyle(Palette.sidebarText)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.xs)
                        ForEach(section.items) { item in
                            SidebarRow(item: item,
                                       isSelected: item == selection,
                                       onSelect: { onSelect(item) })
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        // **底色是不透明的。玻璃用在上面那颗选中药丸上，不用在这一整片底上。**
        //
        // 试过整片用玻璃，实测否掉了（2026-08-30）：`Glass.tint(_:)` 是给材质上色，
        // **不是**按不透明度把颜色压上去——传一个 alpha 0.92 的深紫进去，
        // 渲染出来仍然是浅色（实测采样到 rgb(219,219,220)）。
        // 于是这条深色侧边栏在浅色壁纸下整片变浅，白字糊成一片。
        //
        // 换句话说：玻璃跟着背后的东西走，而这条侧边栏背后是用户的壁纸。
        // 想让它保持深色，就只能自己铺一层不透明的底——那也就不是玻璃了。
        .background(Palette.sidebarBackground)
    }

    /// 顶上那块。**不是装饰**：`NavigationSplitView` 的侧边栏顶部要给窗口的红绿灯按钮
    /// 让出位置，这块留白如果什么都不放，看着就是「侧边栏第一项被挤下去了」。
    private var brand: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("IELTS Speaking")
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.sidebarTextSelected)
            Text("口语陪练")
                .font(Typography.label)
                .foregroundStyle(Palette.sidebarText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.lg)
    }
}

/// 侧边栏的一行。
///
/// **选中标记有两样：左边那道主色竖条 + 底色。** 只靠底色的话，深色底上
/// 「选中」和「鼠标正悬在上面」会长得一模一样；只靠竖条的话，那是纯粹的颜色信息
/// （规范：不许只用颜色传达状态）。
private struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            surface(label)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .coachAnimation(Motion.quick, value: isHovering)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .help(item.title)
    }

    private var label: some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Radius.pill)
                .fill(isSelected ? Palette.accent : Palette.sidebarHighlight)
                .frame(width: Layout.railWidth)
                .opacity(isSelected ? 1 : 0)
            Image(systemName: item.systemImage)
                .frame(width: Spacing.md)
            Text(item.title)
            Spacer(minLength: 0)
        }
        .font(Typography.navItem)
        .foregroundStyle(isSelected ? Palette.sidebarTextSelected : Palette.sidebarText)
        .padding(.vertical, Spacing.sm)
        .padding(.trailing, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    /// 选中/悬停那颗药丸用**液态玻璃**；其余的行**什么底都不画**。
    ///
    /// 两件事各修掉一个坑：
    ///
    /// - **不画底**：从前这里给未选中的行也铺了一块 `Palette.sidebarBackground`。
    ///   侧边栏不透明时那是隐形的（底色一样），一旦换了底就当场现形成十个贴纸。
    ///   这类 bug 只有在换底之后才看得见，而它在换底之前一直躺在那儿。
    /// - **玻璃只给这颗药丸**：它浮在一片我们自己铺好的深色底上，玻璃采样到的就是那片深色，
    ///   所以文字的落脚点仍然可控。整片侧边栏用玻璃试过，实测否掉了——见 `body` 里的说明。
    @ViewBuilder
    private func surface(_ content: some View) -> some View {
        if isSelected || isHovering {
            content.coachGlass(tint: Palette.sidebarHighlight,
                               fallback: Palette.sidebarHighlight,
                               interactive: true,
                               in: RoundedRectangle(cornerRadius: Radius.control))
        } else {
            content
        }
    }
}

#Preview {
    SidebarView(selection: .today, onSelect: { _ in })
        .frame(width: Layout.sidebarWidth, height: Layout.minWindowHeight)
}
