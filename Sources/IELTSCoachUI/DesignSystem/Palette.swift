import SwiftUI

/// 颜色令牌。取值逐字来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 2 节，
/// 那份文件是界面的唯一视觉依据，**这里不许自行调色**。
///
/// 视图里只能引用令牌名，不许出现字面颜色值。这不是洁癖：
/// Phase 7 要加深色模式，那时只改这一个文件；如果颜色散在几十个视图里，
/// 加深色模式就变成了一次全局重写。
///
/// **半透明的两个令牌（`textSecondary`、`sidebarText`）不能随手调淡。**
/// 它们的不透明度是按 4.5:1 的对比度底线定的，`DesignSystemTests` 按合成后的
/// 实际显示效果守着这条线。
public enum Palette {
    // 品牌主色。设计稿里的紫色，用于主按钮、选中态、强调数字
    public static let accent = Color(red: 0.361, green: 0.318, blue: 0.910)      // #5C51E8

    // 侧边栏。设计稿里的深色导航条
    public static let sidebarBackground = Color(red: 0.133, green: 0.118, blue: 0.239)  // #221E3D
    public static let sidebarText = Color.white.opacity(0.72)
    public static let sidebarTextSelected = Color.white

    // 内容区
    public static let canvas = Color(red: 0.957, green: 0.957, blue: 0.969)      // #F4F4F7
    public static let card = Color.white
    public static let cardBorder = Color.black.opacity(0.08)

    // 文字
    public static let textPrimary = Color(red: 0.07, green: 0.07, blue: 0.09)    // #121217
    public static let textSecondary = Color.black.opacity(0.56)
    public static let textOnAccent = Color.white

    // 语义
    //
    // ⚠️ 这三个是**唯一没有照第 2 节原值抄**的地方，依据是该节 2026-08-06 的复审注记与
    // 本计划 Task 7 Step 3：原值达不到同一节那条「不可协商」的 4.5:1，
    // 而 Phase 8 要用 `warning` 显示一段中文正文——那是正文，不是装饰。
    // 调深后观感会比设计稿明显更重，这一条已列进 Task 11 的人工验收，由用户拍板。
    // 重调的唯一前提是仍 ≥ 4.5:1，`testSemanticColorsAreReadableAsText` 拦着。

    // 第 2 节的原值 (0.13, 0.60, 0.35) 对白卡片只有 3.64:1，低于 4.5:1 底线。
    public static let success = Color(red: 0.09, green: 0.50, blue: 0.27)   // 约 5.02:1 / 4.58:1
    // 第 2 节的原值 (0.85, 0.55, 0.10) 对白卡片只有 2.72:1。Phase 8 会用它显示中文正文。
    public static let warning = Color(red: 0.60, green: 0.39, blue: 0.02)   // 约 5.05:1 / 4.60:1
    // danger 原值达标（约 5.14:1），不动。
    public static let danger = Color(red: 0.80, green: 0.20, blue: 0.20)
}
