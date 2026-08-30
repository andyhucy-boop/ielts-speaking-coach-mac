import SwiftUI

/// 字体令牌。取值逐字来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 1 节那张字体表，
/// 一个令牌对应表里的一行。
///
/// **字重必须写出来，不许省。** 这是这个文件存在的头号理由：
/// SwiftUI 的语义字体只有一部分自带字重（`.headline` 是 semibold），
/// 其余（`.caption`、`.title`、`.largeTitle`…）默认都是 regular。
/// 表里给 `.caption` 标的是 medium、给数字标的是 semibold——
/// 在视图里写 `.font(.caption)` 编得过、跑得动、看着也「差不多」，
/// 只是比规范轻一档；而 `.caption` 的标签本来就压在 56% 黑上，
/// 再轻一档正是那种「说不上哪儿不对」。已经掉过一次（`SectionHeader` 的编号 + 英文标签）。
///
/// **一律用语义字体，不写 `.system(size:)`。** 固定磅值会让系统「辅助功能 › 文字大小」
/// 那一档失效，而规范第 6 节的验收清单里有「系统文字调到最大时界面不截断」这一条。
/// 想要更大的字就往上挑一档语义字体（`.body` → `.title3`），不要自己写死磅值。
///
/// ## 2026-08-30 改版：把「全是 13 磅」拆开
///
/// 改版前 `cardTitle`（`.headline`，13）与 `body`（`.body`，13）**是同一个字号**，
/// 只差一档字重；`secondary` 12、`label` 11 又紧挨着它们。于是整页从标题到脚注
/// 落在 11–13 磅这一条窄缝里，层级只能靠颜色深浅去分——这正是界面显得平、显得糊的头号原因。
///
/// 改法是把标题那一档整体抬高一级（`cardTitle` 13 → 15），并补上两头：
/// `lede`（15 regular，长文与例句）撑开阅读区，`overline`（10 semibold，区块编号）
/// 收紧眉标。改完的层级是 26 / 17 / 15 / 13 / 12 / 11 / 10，每一档之间都看得出差别。
public enum Typography {

    // MARK: - 标题

    /// 页面大标题。表：`.largeTitle` / 约 26 / `.bold`
    public static let pageTitle = Font.largeTitle.weight(.bold)

    /// 区块标题。表：`.title2` / 约 17 / `.semibold`
    public static let sectionTitle = Font.title2.weight(.semibold)

    /// 卡片标题。表：`.title3` / 约 15 / `.semibold`
    ///
    /// **改版前是 `.headline`（13）**，与正文同号，两者只差一档字重——
    /// 卡片标题和卡片正文在屏幕上分不开，一整页因此糊成一片。
    public static let cardTitle = Font.title3.weight(.semibold)

    /// 密排列表里那一行的标题。表：`.headline` / 约 13 / `.semibold`
    ///
    /// 题库、训练记录这种一屏几十行的地方用它：这些行的标题不该和卡片标题一样大，
    /// 否则一屏只装得下五六行。`cardTitle` 让位之后，这一档接手了原来那个位置。
    public static let rowTitle = Font.headline.weight(.semibold)

    /// 区块眉标（`01 PRACTICE ROUTES` 那一行）。表：`.caption2` / 约 10 / `.semibold`
    ///
    /// 比 `label` 更小、更重、配更宽的字距（`Tracking.overline`）。
    /// 眉标是**标记**不是**内容**：它该小到一眼看过去不与标题争，
    /// 又重到不会被当成一句没读完的说明。
    public static let overline = Font.caption2.weight(.semibold)

    // MARK: - 正文

    /// 正文。表：`.body` / 约 13 / `.regular`
    public static let body = Font.body.weight(.regular)

    /// 引导语与例句。表：`.title3` / 约 15 / `.regular`
    ///
    /// 两处用它：页面标题下那句话，以及复盘报告里的英文原句与改写句。
    /// 后者是这个 App 里**唯一需要逐字读的英文**，和周围的中文说明同号会读得很吃力。
    ///
    /// 取值与 `cardTitle` 同档不同重，是刻意的：同一档字号里，
    /// 「标题」和「要读的正文」靠字重分，不靠字号分。
    public static let lede = Font.title3.weight(.regular)

    /// 次要说明。表：`.callout` / 约 12 / `.regular`
    public static let secondary = Font.callout.weight(.regular)

    /// 小标签。表：`.caption` / 约 11 / `.medium`
    public static let label = Font.caption.weight(.medium)

    // MARK: - 控件

    /// 侧边栏一项。表：`.body` / 约 13 / `.medium`
    ///
    /// **选中与否都用这一档。** 选中时换成 semibold 是很自然的手势，
    /// 但那会让这一行的宽度当场变一下——十项里有一项在抖，整条侧边栏就显得廉价。
    /// 选中靠底色与文字色区分（`Palette.sidebarTextSelected`），不靠字重。
    public static let navItem = Font.body.weight(.medium)

    /// 按钮文字。**表里没有按钮这一行**，取与密排行标题同一档（`.headline` / `.semibold`）。
    ///
    /// 值和 `rowTitle` 一样，单独起个名字是为了以后想调按钮时不必连列表一起动。
    public static let action = Font.headline.weight(.semibold)

    // MARK: - 数字

    /// 统计数字、时长。表：`.title` + `.monospacedDigit()` / 约 22 / `.semibold`
    ///
    /// **等宽数字是表里写死的，不是可选项**：否则「本周 3/5 次」跳到「10/5 次」时整行会抖。
    /// 它跟字重一起焊在令牌里，省得每个用到数字的页面各记一次。
    public static let number = Font.title.weight(.semibold).monospacedDigit()

    /// 一屏里最大的那个数字。表：`.largeTitle` + `.monospacedDigit()` / 约 26 / `.bold`
    ///
    /// 只给「本周训练 3/5」这种**这一页真正要看的那一个**数字用。
    /// 四格全用它就等于一个都没突出——那是 `number` 的位置。
    public static let numberHero = Font.largeTitle.weight(.bold).monospacedDigit()
}
