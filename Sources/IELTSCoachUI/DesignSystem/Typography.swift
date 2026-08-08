import SwiftUI

/// 字体令牌。取值逐字来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 1 节那张字体表，
/// 一个令牌对应表里的一行。
///
/// **字重必须写出来，不许省。** 这是这个文件存在的全部理由：
/// SwiftUI 的语义字体只有一部分自带字重（`.headline` 是 semibold），
/// 其余（`.caption`、`.title`、`.largeTitle`…）默认都是 regular。
/// 表里给 `.caption` 标的是 medium、给数字标的是 semibold——
/// 在视图里写 `.font(.caption)` 编得过、跑得动、看着也「差不多」，
/// 只是比规范轻一档；而 `.caption` 的标签本来就压在 56% 黑上，
/// 再轻一档正是那种「说不上哪儿不对」。已经掉过一次（`SectionHeader` 的编号 + 英文标签）。
///
/// 所以字体和颜色一样收进令牌：视图只挑档位，字重由这张表说了算。
/// `DesignSystemTests` 两头守着——一头逐行比对这里的取值与第 1 节的表，
/// 一头扫 `DesignSystem/` 的源码，不许视图自己拼字体或单独指定字重。
public enum Typography {
    /// 页面大标题。表：`.largeTitle` / 约 26 / `.bold`
    public static let pageTitle = Font.largeTitle.weight(.bold)

    /// 区块标题。表：`.title2` / 约 17 / `.semibold`
    public static let sectionTitle = Font.title2.weight(.semibold)

    /// 卡片标题。表：`.headline` / 约 13 / `.semibold`
    ///
    /// `.headline` 本来就自带 semibold，这里仍然显式写出来：
    /// 「表里有字重的档位一律显式写」比「记住哪几个自带」可靠。
    public static let cardTitle = Font.headline.weight(.semibold)

    /// 正文。表：`.body` / 约 13 / `.regular`
    public static let body = Font.body.weight(.regular)

    /// 次要说明。表：`.callout` / 约 12 / `.regular`
    public static let secondary = Font.callout.weight(.regular)

    /// 小标签（区块标题上那行编号 + 英文标签）。表：`.caption` / 约 11 / `.medium`
    public static let label = Font.caption.weight(.medium)

    /// 按钮文字。**表里没有按钮这一行**，取与卡片标题同一档（`.headline` / `.semibold`）。
    ///
    /// 值和 `cardTitle` 一样，单独起个名字是为了以后想调按钮时不必连卡片标题一起动。
    public static let action = Font.headline.weight(.semibold)

    /// 统计数字、时长。表：`.title` + `.monospacedDigit()` / 约 22 / `.semibold`
    ///
    /// **等宽数字是表里写死的，不是可选项**：否则「本周 3/5 次」跳到「10/5 次」时整行会抖。
    /// 它跟字重一起焊在令牌里，省得每个用到数字的页面各记一次。
    public static let number = Font.title.weight(.semibold).monospacedDigit()
}
