import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import IELTSCoachUI

/// 设计规范（`docs/superpowers/DESIGN-SYSTEM.md`）里唯一能自动验证的部分：
/// **对比度**和**间距刻度**。其余（留白是否舒服、卡片好不好看）只能人工验收（Task 11）。
///
/// 对比度值得测，是因为它恰恰是「说不上哪儿不对」的那类问题：
/// 灰上加灰不会让人指出「这里只有 2.8:1」，只会让人觉得界面有点糊、有点廉价。
final class DesignSystemTests: XCTestCase {

    // MARK: - 量对比度的尺子

    /// WCAG 相对亮度。**不看 alpha**——调用方负责先合成。
    private func luminance(red: Double, green: Double, blue: Double) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        // 取不出分量时返回全 NaN。**不要改成「取不出就当黑色」**——那会让对比度
        // 变得非常好看，而 NaN 会让任何 XCTAssertGreaterThanOrEqual 当场失败，这正是想要的。
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else {
            return (.nan, .nan, .nan, .nan)
        }
        return (Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    /// 前景压在背景上之后的对比度。背景必须是不透明令牌。
    ///
    /// **这三行合成就是这个函数存在的意义。** 删掉它们，
    /// 所有半透明令牌（textSecondary、sidebarText、cardBorder）都会「永远达标」，
    /// 下面几条断言全部退化成空转。
    private func contrast(_ foreground: Color, on background: Color) -> Double {
        let fg = components(foreground)
        let bg = components(background)
        let r = fg.r * fg.a + bg.r * (1 - fg.a)
        let g = fg.g * fg.a + bg.g * (1 - fg.a)
        let b = fg.b * fg.a + bg.b * (1 - fg.a)
        let front = luminance(red: r, green: g, blue: b)
        let back = luminance(red: bg.r, green: bg.g, blue: bg.b)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }

    // MARK: - 先守住尺子本身

    /// 半透明前景必须被合成，而不是被当成不透明色。
    /// 56% 黑压在白底上观感等同 #747474，约 4.94:1；忽略 alpha 会算成 21:1。
    ///
    /// 这条守的是下面所有断言的有效性：尺子量不准的话，
    /// 「textSecondary 必须 ≥ 4.5:1」会变成一条永远绿的空转测试，而且没人会去看它。
    func testAlphaIsCompositedInsteadOfIgnored() {
        let ratio = contrast(Color.black.opacity(0.56), on: .white)
        XCTAssertEqual(ratio, 4.94, accuracy: 0.2)
        XCTAssertLessThan(ratio, 6.0, "把半透明前景当成不透明色算了")
        // 两个已知值，钉住这把尺子的刻度本身（不透明色不受合成影响）
        XCTAssertEqual(contrast(.black, on: .white), 21, accuracy: 0.01)
        XCTAssertEqual(contrast(.white, on: .white), 1, accuracy: 0.01)
    }

    // MARK: - 对比度底线（DESIGN-SYSTEM 第 2 节，不可协商）

    func testPrimaryTextMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.textPrimary, on: Palette.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(Palette.textPrimary, on: Palette.card), 4.5)
    }

    func testSecondaryTextAlsoMeetsAA() {
        // 次要文字仍然是要读的，不能降到 3:1。
        // 灰上加灰是让界面显廉价的头号原因。
        XCTAssertGreaterThanOrEqual(contrast(Palette.textSecondary, on: Palette.card), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(Palette.textSecondary, on: Palette.canvas), 4.5)
    }

    func testTextOnAccentMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.textOnAccent, on: Palette.accent), 4.5)
    }

    func testSidebarTextMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.sidebarText, on: Palette.sidebarBackground), 4.5)
        XCTAssertGreaterThanOrEqual(
            contrast(Palette.sidebarTextSelected, on: Palette.sidebarBackground), 4.5)
    }

    /// 语义色也要读得清。Phase 8 会用 `Palette.warning` 显示一段中文正文，
    /// 那是正文不是装饰——设计稿的原值只有 2.72:1，进不了这条线。
    func testSemanticColorsAreReadableAsText() {
        for (name, color) in [("success", Palette.success),
                              ("warning", Palette.warning),
                              ("danger", Palette.danger)] {
            XCTAssertGreaterThanOrEqual(contrast(color, on: Palette.card), 4.5, "\(name) 对卡片")
            XCTAssertGreaterThanOrEqual(contrast(color, on: Palette.canvas), 4.5, "\(name) 对内容区底色")
        }
    }

    // MARK: - 间距刻度（DESIGN-SYSTEM 第 3 节）

    func testSpacingScaleIsMultiplesOfFour() {
        for value in [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.section] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) 不是 4 的倍数")
        }
    }

    /// 逐个钉住取值。**上面那条「是 4 的倍数」远远不够**：实测把 `Spacing.lg` 从 24 改成 8、
    /// 把 `Radius.card` 从 12 改成 40，整套测试一条都不红——8 和 40 都是 4 的倍数，
    /// 而 `Radius` 压根没被那条覆盖。
    ///
    /// 后果是整个界面的观感一起走样：卡片内边距从 24 掉到 8，那份「留白很足」的高级感
    /// （第 3 节明写「不要为了多塞内容压缩留白」）当场没了；圆角 40 则把卡片变成药丸。
    /// 这类改动一个字的编译错误都不会有，也不会有任何一条测试拦着，只会让人觉得
    /// 「说不上哪儿不对」——正是本项目最怕的那种缺陷。
    ///
    /// 令牌值和第 3 节的代码块逐字对齐；要改就先改那份规范，再改这里。
    func testSpacingAndRadiusTokensMatchTheSpecTable() {
        XCTAssertEqual(Spacing.xs, 4, "Spacing.xs 与第 3 节对不上")
        XCTAssertEqual(Spacing.sm, 8, "Spacing.sm 与第 3 节对不上")
        XCTAssertEqual(Spacing.md, 16, "Spacing.md 与第 3 节对不上")
        XCTAssertEqual(Spacing.lg, 24, "Spacing.lg 与第 3 节对不上（卡片内边距就是它）")
        XCTAssertEqual(Spacing.xl, 32, "Spacing.xl 与第 3 节对不上（页面内边距就是它）")
        XCTAssertEqual(Spacing.section, 40, "Spacing.section 与第 3 节对不上")

        XCTAssertEqual(Radius.card, 12, "Radius.card 与第 3 节对不上")
        XCTAssertEqual(Radius.control, 8, "Radius.control 与第 3 节对不上")
        XCTAssertEqual(Radius.pill, 999, "Radius.pill 与第 3 节对不上")

        // 第 4 节：卡片用「发丝边框」分层，不用投影。粗一档就从分层变成描边。
        XCTAssertEqual(BorderWidth.hairline, 1, "BorderWidth.hairline 与第 4 节对不上")

        // 刻度必须是严格递增的，否则「xs 比 md 大」这种手误照样能逐条对齐地写进去。
        let scale = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.section]
        XCTAssertEqual(scale, scale.sorted(), "间距刻度不是递增的：\(scale)")
    }

    // MARK: - 字体表（DESIGN-SYSTEM 第 1 节）

    /// 「视图不许自己拼字体」这条已经搬去 `DesignTokenSweepTests`，并且扩到了整个
    /// `Sources/IELTSCoachUI/`、认全同义写法（`.font(`、`Font.`、`.weight(`）。
    ///
    /// 原来那一版只扫 `DesignSystem/` 一个目录，而且只认「点开头」的 `font(.`——
    /// **实测把 `.font(Typography.label)` 换成 `.font(Font.caption)` 就溜过去了。**
    /// 扫描规则现在收在 `SourceGuard` 里，且它自己有一整组自测
    /// （`SourceGuardTests`）证明每种同义写法都拦得住。

    /// 字体表逐行钉住。左边是令牌，右边是第 1 节表里那一行的「SwiftUI 语义字体 + 字重」。
    ///
    /// 表里「数字」那一行还要求 `.monospacedDigit()`：本周 3/5 次跳到 10/5 次时整行不能抖。
    func testTypographyTokensMatchTheSpecTable() {
        XCTAssertEqual(Typography.pageTitle, Font.largeTitle.weight(.bold))
        XCTAssertEqual(Typography.sectionTitle, Font.title2.weight(.semibold))
        XCTAssertEqual(Typography.cardTitle, Font.headline.weight(.semibold))
        XCTAssertEqual(Typography.body, Font.body.weight(.regular))
        XCTAssertEqual(Typography.secondary, Font.callout.weight(.regular))
        XCTAssertEqual(Typography.label, Font.caption.weight(.medium))
        XCTAssertEqual(Typography.number, Font.title.weight(.semibold).monospacedDigit())
        // 表里没有「按钮」这一行，`action` 是加的，取与卡片标题同一档。
        XCTAssertEqual(Typography.action, Font.headline.weight(.semibold))
    }

    /// 每个令牌都必须真的带上字重，不能是光秃秃的语义字体。
    ///
    /// **这条才是上面那条的牙齿。** 只写 `Font.caption` 也能编过、也能跑，
    /// 只是字重悄悄退回 SwiftUI 的默认值（`.caption` 默认 regular，比表里的 medium 轻一档），
    /// 而这种差别没人能靠眼睛在截图上指出来。`SectionHeader` 就是这么掉过一次的。
    func testTypographyTokensDoNotFallBackToBareSemanticFonts() {
        XCTAssertNotEqual(Typography.pageTitle, Font.largeTitle, "pageTitle 没带字重")
        XCTAssertNotEqual(Typography.sectionTitle, Font.title2, "sectionTitle 没带字重")
        XCTAssertNotEqual(Typography.cardTitle, Font.headline, "cardTitle 没带字重")
        XCTAssertNotEqual(Typography.body, Font.body, "body 没带字重")
        XCTAssertNotEqual(Typography.secondary, Font.callout, "secondary 没带字重")
        XCTAssertNotEqual(Typography.label, Font.caption, "label 没带字重")
        XCTAssertNotEqual(Typography.number, Font.title, "number 没带字重")
        XCTAssertNotEqual(Typography.number, Font.title.weight(.semibold), "number 没带等宽数字")
    }

    // MARK: - 扫源码用的小工具

    // 原来这里自己带着一份「遍历目录 / 去注释 / 数次数」的实现，`QuestionBankViewTests`、
    // `TodayViewTests`、`PracticeSheetTests` 都跨类引用它。那份实现现在收进了
    // `Support/SourceGuard.swift`：一处实现、一组自测，而且读不到源码时会抛错而不是给空串。
}
