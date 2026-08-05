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
}
