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

    // MARK: - 颜色表的完整性

    /// 每个颜色令牌 → 它本身。**这份映射存在的唯一理由是 Swift 取不到 enum 静态成员的名字**，
    /// 而下面那条测试要按名字把「源码里声明了什么」和「测试里检查了什么」对起来。
    ///
    /// 它自己会被对着 `Palette.swift` 校验（少一个、多一个、改了名都红），
    /// 所以它不是又一份会悄悄过期的手写清单。
    private static let colorTokens: [String: Color] = [
        "accent": Palette.accent,
        "sidebarBackground": Palette.sidebarBackground,
        "sidebarText": Palette.sidebarText,
        "sidebarTextSelected": Palette.sidebarTextSelected,
        "canvas": Palette.canvas,
        "card": Palette.card,
        "cardBorder": Palette.cardBorder,
        "textPrimary": Palette.textPrimary,
        "textSecondary": Palette.textSecondary,
        "textOnAccent": Palette.textOnAccent,
        "success": Palette.success,
        "warning": Palette.warning,
        "danger": Palette.danger
    ]

    /// 会被当成文字画出来的令牌 → 它会压在哪些底色上。每一对都得过 4.5:1。
    ///
    /// `accent` 也在这里：`PrimaryActionCard` 的按钮就是白底紫字（`Components.swift`），
    /// 所以它既是底色也是文字色。
    private static let textTokensOnBackgrounds: [String: [String]] = [
        "textPrimary": ["canvas", "card"],
        "textSecondary": ["canvas", "card"],
        "textOnAccent": ["accent"],
        "sidebarText": ["sidebarBackground"],
        "sidebarTextSelected": ["sidebarBackground"],
        "success": ["canvas", "card"],
        "warning": ["canvas", "card"],
        "danger": ["canvas", "card"],
        "accent": ["card"]
    ]

    /// 从不当文字用的令牌。列在这里是一次显式的判断，不是「忘了检查」——
    /// `cardBorder` 是 8% 黑的发丝边框（第 4 节），按文字标准量它必然不达标，
    /// 但它本来就不是给人读的。
    private static let nonTextTokens: Set<String> = [
        "canvas", "card", "sidebarBackground", "cardBorder"
    ]

    /// **上面那些对比度断言是一份手写清单，这条守的是它的完整性。**
    ///
    /// 实测：往 `Palette` 里加一个 `subtle = Color.black.opacity(0.28)`（约 2.3:1）
    /// 并在 `EmptyStateView` 上用它 —— 全套 429 条一条不红。铁律 6 只要求「视图走令牌」，
    /// 而这个新令牌确实是令牌，于是扫描放行；对比度那几条又只认名字写死的那几个。
    /// 「灰上加灰」就这么从正门走进来了。
    ///
    /// 所以：`Palette.swift` 里声明的每一个令牌，都必须在这里被显式归类，
    /// 归成文字色的就当场量对比度。新增一个令牌 → 名单对不上 → 红，逼人做这个判断。
    func testEveryColorTokenIsClassifiedAndTextTokensMeetAA() throws {
        let declared = Set(try SourceGuard.declaredTokenNames(
            inEnum: "Palette", of: try SourceGuard.code("DesignSystem/Palette.swift")))
        XCTAssertGreaterThanOrEqual(declared.count, 13,
                                    "只解析到 \(declared.count) 个颜色令牌，疑似空转")

        XCTAssertEqual(
            declared, Set(Self.colorTokens.keys),
            "`Palette.swift` 里声明的令牌和这个测试文件里的映射对不上（多出来或少掉的那个"
                + "现在没有任何对比度断言管得着）。下一步：同步 `colorTokens`。")
        XCTAssertEqual(
            declared, Set(Self.textTokensOnBackgrounds.keys).union(Self.nonTextTokens),
            "有令牌既没被归成文字色、也没被归成非文字色。下一步：想清楚它会不会被人读——"
                + "会读就写进 `textTokensOnBackgrounds` 并指明压在哪个底色上，"
                + "不会读就写进 `nonTextTokens`。不许因为「不好过」就归到后者（铁律 8）。")
        XCTAssertTrue(
            Set(Self.textTokensOnBackgrounds.keys).isDisjoint(with: Self.nonTextTokens),
            "同一个令牌既归了文字色又归了非文字色，归类失去意义")

        var pairs = 0
        for (name, backgrounds) in Self.textTokensOnBackgrounds {
            guard let foreground = Self.colorTokens[name] else {
                XCTFail("`\(name)` 不在 colorTokens 里，量不了对比度")
                continue
            }
            for background in backgrounds {
                guard let base = Self.colorTokens[background] else {
                    XCTFail("`\(name)` 声称压在 `\(background)` 上，但那不是个颜色令牌")
                    continue
                }
                pairs += 1
                XCTAssertGreaterThanOrEqual(
                    contrast(foreground, on: base), 4.5,
                    "`\(name)` 压在 `\(background)` 上只有 "
                        + String(format: "%.2f", contrast(foreground, on: base))
                        + ":1，低于第 2 节那条不可协商的 4.5:1。")
            }
        }
        XCTAssertGreaterThanOrEqual(pairs, 13, "只量了 \(pairs) 对，这条测试很可能在空转")
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

        // 第 4 节：区块标题的编号与英文标签「字距略宽」。规范没给数值，取值定在令牌里，
        // 所以更要钉住：调到 20 的话那行英文标签会散成一串孤零零的字母，而这里不钉就没人管。
        XCTAssertEqual(Tracking.label, 1.2, "Tracking.label 与 Metrics.swift 里定的取值对不上")

        // 刻度必须是严格递增的，否则「xs 比 md 大」这种手误照样能逐条对齐地写进去。
        let scale = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.section]
        XCTAssertEqual(scale, scale.sorted(), "间距刻度不是递增的：\(scale)")
    }

    // MARK: - 表的完整性：手写清单漏掉新加的那一行

    /// **上面那两张手写的表，本身也需要一个守卫。**
    ///
    /// 手写清单的通病是「新加的那一行没人写进来」。实测：往 `Metrics.swift` 里加一个
    /// `Radius.sheet = 3`、并在 `CoachCard` 上用它，全套 429 条一条不红——卡片圆角
    /// 从 12 变成 3，看上去就是一张便宜的方框，而没有任何一条测试有话说。
    ///
    /// 所以反过来对一遍：`Metrics.swift` 里声明的每一个令牌，都必须在上面那条测试的
    /// 函数体里被 `XCTAssertEqual` 钉住。enum 的名单也是从源码里读的，
    /// 这样新加一整个 `public enum` 也漏不掉。
    func testEveryMetricsTokenIsPinnedByThatTable() throws {
        let metrics = try SourceGuard.code("DesignSystem/Metrics.swift")
        let pinning = try SourceGuard.functionBody(
            named: "testSpacingAndRadiusTokensMatchTheSpecTable",
            in: try SourceGuard.testCode("DesignSystemTests.swift"))

        var checked = 0
        for enumName in SourceGuard.declaredEnumNames(in: metrics) {
            let tokens = try SourceGuard.declaredTokenNames(inEnum: enumName, of: metrics)
            XCTAssertFalse(tokens.isEmpty, "\(enumName) 里一个令牌都没解析到，这一圈在空转")
            for token in tokens {
                checked += 1
                XCTAssertTrue(
                    pinning.contains("XCTAssertEqual(\(enumName).\(token),"),
                    "`\(enumName).\(token)` 没有被 testSpacingAndRadiusTokensMatchTheSpecTable 钉住，"
                        + "它现在可以被改成任何值而不会有任何一条测试变红。"
                        + "下一步：在那条测试里加一行 `XCTAssertEqual(\(enumName).\(token), <取值>)`，"
                        + "取值以 DESIGN-SYSTEM 第 3/4 节为准；规范里没有的档位，先写进规范。")
            }
        }
        XCTAssertGreaterThanOrEqual(
            checked, 11,
            "只对到 \(checked) 个令牌，这条测试很可能在空转。"
                + "下一步：确认 Metrics.swift 的解析（public enum / public static let）还认得出来。")
    }

    /// 同上，管字体表。新加一档 `Typography.caption2` 而没人钉它的话，
    /// 那一档的字重就退回 SwiftUI 的默认值，而这正是本项目已经掉过一次的坑。
    func testEveryTypographyTokenIsPinnedByThatTable() throws {
        let typography = try SourceGuard.code("DesignSystem/Typography.swift")
        let pinning = try SourceGuard.functionBody(
            named: "testTypographyTokensMatchTheSpecTable",
            in: try SourceGuard.testCode("DesignSystemTests.swift"))

        let tokens = try SourceGuard.declaredTokenNames(inEnum: "Typography", of: typography)
        XCTAssertGreaterThanOrEqual(tokens.count, 8, "只解析到 \(tokens.count) 个字体令牌，疑似空转")
        for token in tokens {
            XCTAssertTrue(
                pinning.contains("XCTAssertEqual(Typography.\(token),"),
                "`Typography.\(token)` 没有被 testTypographyTokensMatchTheSpecTable 钉住，"
                    + "它的字号和字重现在可以随便改。"
                    + "下一步：在那条测试里补一行，右边写第 1 节字体表里对应那一行的"
                    + "「语义字体 + 字重」。")
        }
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
