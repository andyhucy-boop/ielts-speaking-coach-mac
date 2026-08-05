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

    // MARK: - 字体表（DESIGN-SYSTEM 第 1 节）

    /// 设计系统里的字体必须走令牌，不许在视图里直接写语义字体或单独指定字重。
    ///
    /// **这条守的是第 1 节字体表的「字重」那一列。** 字重是这张表里最容易掉的一格：
    /// `Font.caption` 的默认字重是 regular（不像 `.headline` 自带 semibold），
    /// 少写一句字重编译照过、跑起来也不报错，只是渲染出来比规范轻一档——
    /// 而 `.caption` 的标签本来就压在 56% 黑上，再轻一档正是那种「说不上哪儿不对」。
    /// 已经掉过一次：`SectionHeader` 的编号 + 英文标签曾经只有语义字体没有字重。
    ///
    /// 字重没法从渲染结果上断言（`swift test` 不画界面），所以退一步扫源码：
    /// 只要视图不自己拼字体，字重就只能来自 `Typography`，而 `Typography` 有下面两条测试钉着。
    /// 扫源码这一招在本项目有先例（`PreviewSafetyTests`、Phase 10 Task 18）。
    ///
    /// **只扫 `DesignSystem/` 这一个目录。** Task 7 之前的占位页（`RootView` 等）按铁律 8
    /// 用的是系统语义字体加系统语义颜色，它们由 Task 4–6 重写时再一起收编。
    func testDesignSystemTakesFontsFromTypographyTokens() throws {
        let files = try Self.swiftFiles(in: Self.designSystemDirectory)
        XCTAssertFalse(
            files.isEmpty,
            "一个设计系统源文件都没扫到，这条测试等于空转。下一步：确认目录还在——"
                + Self.designSystemDirectory.path)

        // 在视图里拼字体的三种写法。三种都会绕开 Typography，也就绕开了字体表的字重那一列。
        let forbidden = [
            ("font(.", "直接写了语义字体"),
            ("fontWeight(", "在视图里单独指定字重"),
            (".bold()", "在视图里单独加粗")
        ]
        var tokenUses = 0
        for file in files {
            let source = Self.strippingLineComments(try String(contentsOf: file, encoding: .utf8))
            tokenUses += Self.occurrences(of: ".font(Typography.", in: source)
            for (pattern, what) in forbidden {
                XCTAssertFalse(
                    source.contains(pattern),
                    "\(file.lastPathComponent) 里\(what)（「\(pattern)」）。"
                        + "这样字重就由这一处视图说了算，DESIGN-SYSTEM 第 1 节字体表管不到它。"
                        + "下一步：换成 Typography 里对应的那一档；表里没有的档位，"
                        + "先往 Typography 里加一个令牌再用。")
            }
        }
        // 防空转：把组件里的字体全删光，上面那圈断言同样会全绿。
        XCTAssertGreaterThanOrEqual(
            tokenUses, 5,
            "设计系统里几乎没有用 Typography 令牌设字体（只找到 \(tokenUses) 处），"
                + "这条测试很可能在空转。下一步：确认组件是不是真的还在设字体。")
    }

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

    /// 被扫的目录：设计系统三件套。
    static var designSystemDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources/IELTSCoachUI/DesignSystem")
    }

    /// 与 `PreviewSafetyTests` 共用一份遍历逻辑，别再抄一遍。
    static func swiftFiles(in directory: URL) throws -> [URL] {
        try PreviewSafetyTests.swiftFiles(in: directory)
    }

    /// 去掉 `//` 之后的内容。文档注释里出现「反例长什么样」是很自然的写法，
    /// 不去掉的话这条测试会被自己的注释绊倒。
    ///
    /// 注意：这个处理看不懂字符串字面量里的 `//`（例如 URL）。设计系统这三个文件里没有，
    /// 真要写就先把这里改成正经的词法扫描。
    static func strippingLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.range(of: "//").map { String(line[line.startIndex..<$0.lowerBound]) } ?? String(line)
        }.joined(separator: "\n")
    }

    static func occurrences(of needle: String, in source: String) -> Int {
        var count = 0
        var cursor = source.startIndex
        while let found = source.range(of: needle, range: cursor..<source.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }
}
