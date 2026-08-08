import Foundation
import SwiftUI
import XCTest

@testable import IELTSCoachUI

/// 设计规范（`docs/superpowers/DESIGN-SYSTEM.md`）里唯一能自动验证的部分：
/// **间距刻度**与**字体表**。其余（留白是否舒服、卡片好不好看）只能人工验收（Task 11）。
///
/// **对比度不在这里了。** Phase 3 的那几条对比度测试
/// （`testAlphaIsCompositedInsteadOfIgnored`、`testPrimaryTextMeetsAA`、
/// `testSecondaryTextAlsoMeetsAA`、`testTextOnAccentMeetsAA`、`testSidebarTextMeetsAA`、
/// `testSemanticColorsAreReadableAsText`、`testEveryColorTokenIsClassifiedAndTextTokensMeetAA`）
/// 已经**逐条**并进 `AppearanceContrastTests`：那份矩阵对浅色跑的是同样的配对，
/// 外加深色那一半，用的也是会合成 alpha 的算法（`ContrastMath`），
/// 「每个令牌都必须被显式归类」那条完整性守卫也一起搬了过去、并扩到两套外观。
/// **这是收紧，不是放松。**
final class DesignSystemTests: XCTestCase {

    // MARK: - 间距刻度（DESIGN-SYSTEM 第 3 节）

    func testSpacingScaleIsMultiplesOfFour() {
        for value in [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.section] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) 不是 4 的倍数")
        }
    }

    func testRadiusScaleIsOrdered() {
        // 控件比卡片更圆或一样圆，会让按钮看起来像卡片。
        XCTAssertLessThan(Radius.control, Radius.card)
        XCTAssertGreaterThan(Radius.pill, Radius.card)
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
