import AppKit
import SwiftUI

/// 两套外观。**深色不是浅色的反色**，是另一套单独定过对比度的取值
/// （DESIGN-SYSTEM 第 2 节）。
public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
}

/// 一整套颜色令牌的**静态**取值。
///
/// 为什么要有这个类型：`Palette.accent` 那一组是随系统外观解析的动态颜色，
/// 拿它去算对比度，算到的是「跑测试那一刻恰好是什么外观」——
/// 开发者的机器是浅色，于是「深色的对比度测试」实际测的是浅色，永远绿。
public struct PaletteTokens: Equatable, Sendable {
    public let accent: Color
    public let sidebarBackground: Color
    public let sidebarText: Color
    public let sidebarTextSelected: Color
    public let canvas: Color
    public let card: Color
    public let cardBorder: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textOnAccent: Color
    public let success: Color
    public let warning: Color
    public let danger: Color

    public init(accent: Color, sidebarBackground: Color, sidebarText: Color,
                sidebarTextSelected: Color, canvas: Color, card: Color, cardBorder: Color,
                textPrimary: Color, textSecondary: Color, textOnAccent: Color,
                success: Color, warning: Color, danger: Color) {
        self.accent = accent
        self.sidebarBackground = sidebarBackground
        self.sidebarText = sidebarText
        self.sidebarTextSelected = sidebarTextSelected
        self.canvas = canvas
        self.card = card
        self.cardBorder = cardBorder
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textOnAccent = textOnAccent
        self.success = success
        self.warning = warning
        self.danger = danger
    }
}

/// 颜色令牌。取值来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 2 节，
/// 那份文件是界面的唯一视觉依据，**这里不许自行调色**。
///
/// 视图里只能引用令牌名，不许出现字面颜色值。这不是洁癖：
/// 深色模式就是靠这条规矩只改这一个文件做成的；如果颜色散在几十个视图里，
/// 加深色模式就变成了一次全局重写。
///
/// **半透明的几个令牌（`textSecondary`、`sidebarText`）不能随手调淡。**
/// 它们的不透明度是按 4.5:1 的对比度底线定的，`AppearanceContrastTests`
/// 按合成后的实际显示效果、对两套外观各守一遍这条线。
public enum Palette {

    /// 浅色。取值来自设计稿（DESIGN-SYSTEM 第 2 节），
    /// 只有 success 与 warning 被按对比度底线调深过——
    /// 原值分别只有 3.64:1 与 2.72:1，低于第 2 节那条不可协商的 4.5:1。
    public static let light = PaletteTokens(
        accent: Color(red: 0.361, green: 0.318, blue: 0.910),            // #5C51E8
        sidebarBackground: Color(red: 0.133, green: 0.118, blue: 0.239), // #221E3D
        sidebarText: Color.white.opacity(0.72),                          // 对侧边栏底 8.8:1
        sidebarTextSelected: .white,                                     // 15.9:1
        canvas: Color(red: 0.957, green: 0.957, blue: 0.969),            // #F4F4F7
        card: .white,
        cardBorder: Color.black.opacity(0.08),
        textPrimary: Color(red: 0.07, green: 0.07, blue: 0.09),          // 对卡片 18.7:1
        textSecondary: Color.black.opacity(0.56),                        // 对卡片 4.94:1
        textOnAccent: .white,                                            // 对主色 5.5:1
        success: Color(red: 0.09, green: 0.50, blue: 0.27),              // 对卡片 5.0:1
        warning: Color(red: 0.60, green: 0.39, blue: 0.02),              // 对卡片 5.0:1
        danger: Color(red: 0.80, green: 0.20, blue: 0.20))               // 对卡片 5.1:1

    /// 深色。**每一个值都是降饱和的色调变体，不是反色。**
    /// 两处刻意的不对称，都是为了守住 4.5:1：
    ///   · 主色调亮并降饱和（#A6A1E0），否则「强调数字」这种主色文字在深色卡片上只有 3:1；
    ///   · 主色块上的文字因此翻成近黑——白字压在调亮后的主色上只有 2.7:1。
    ///     一个令牌不可能同时满足「主色当文字用」和「白字压在主色上」，必须让一边翻面。
    public static let dark = PaletteTokens(
        accent: Color(red: 0.651, green: 0.631, blue: 0.878),            // 对卡片 6.9:1
        sidebarBackground: Color(red: 0.106, green: 0.094, blue: 0.188),
        sidebarText: Color.white.opacity(0.78),                          // 对侧边栏底 10.8:1
        sidebarTextSelected: .white,                                     // 17.2:1
        canvas: Color(red: 0.078, green: 0.078, blue: 0.102),
        card: Color(red: 0.118, green: 0.118, blue: 0.149),              // 比底色亮，卡片才不是个洞
        cardBorder: Color.white.opacity(0.14),
        textPrimary: Color(red: 0.929, green: 0.929, blue: 0.949),       // 对卡片 14.2:1
        textSecondary: Color.white.opacity(0.70),                        // 对卡片 8.7:1
        textOnAccent: Color(red: 0.078, green: 0.078, blue: 0.102),      // 对主色 7.7:1
        success: Color(red: 0.42, green: 0.79, blue: 0.56),              // 对卡片 8.2:1
        warning: Color(red: 0.95, green: 0.74, blue: 0.35),              // 对卡片 9.6:1
        danger: Color(red: 0.98, green: 0.53, blue: 0.51))               // 对卡片 7.0:1

    public static func tokens(for appearance: Appearance) -> PaletteTokens {
        switch appearance {
        case .light: return light
        case .dark: return dark
        }
    }

    // MARK: - 视图用的动态令牌
    //
    // 名字与类型跟 Phase 3 完全一样，所以既有视图一行都不用改。
    // 差别只在于：它们现在会跟着系统外观自己解析。

    public static let accent = dynamic(\.accent)
    public static let sidebarBackground = dynamic(\.sidebarBackground)
    public static let sidebarText = dynamic(\.sidebarText)
    public static let sidebarTextSelected = dynamic(\.sidebarTextSelected)
    public static let canvas = dynamic(\.canvas)
    public static let card = dynamic(\.card)
    public static let cardBorder = dynamic(\.cardBorder)
    public static let textPrimary = dynamic(\.textPrimary)
    public static let textSecondary = dynamic(\.textSecondary)
    public static let textOnAccent = dynamic(\.textOnAccent)
    public static let success = dynamic(\.success)
    public static let warning = dynamic(\.warning)
    public static let danger = dynamic(\.danger)

    /// 用 AppKit 的动态颜色，而不是 `@Environment(\.colorScheme)`。
    /// 理由：环境值只有 `View` 拿得到，而令牌是静态属性，被 `Components.swift`
    /// 里的组件直接引用。动态 NSColor 由绘制时的外观解析，不需要每个组件
    /// 都去读一次环境，也就不会漏掉任何一处。
    private static func dynamic(_ keyPath: KeyPath<PaletteTokens, Color>) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(tokens(for: isDark ? .dark : .light)[keyPath: keyPath])
        })
    }
}
