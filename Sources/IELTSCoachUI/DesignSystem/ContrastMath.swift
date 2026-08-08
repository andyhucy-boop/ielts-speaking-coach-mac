import AppKit
import SwiftUI

/// WCAG 对比度。**唯一存在的理由是它会合成 alpha。**
///
/// 直接拿 `NSColor(color).redComponent` 去算，`Color.black.opacity(0.56)`
/// 的分量是纯黑（透明度在 alpha 上），算出来是 21:1，而它在屏幕上只有 4.94:1。
/// 忽略 alpha 的对比度测试对每一个半透明令牌都是空转的。
public enum ContrastMath {

    public struct Components: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    /// 取不出分量时返回全 NaN。
    /// **不要改成「取不出就当黑色」**——那会让对比度变得非常好看，
    /// 而 NaN 会让任何 `XCTAssertGreaterThanOrEqual` 当场失败，这正是想要的。
    ///
    /// 下面那行带着一条单行豁免：全模块扫描（`DesignTokenSweepTests`）禁止直接构造
    /// 平台颜色，那条规则是冲着「视图里绕开令牌自己调色」来的。这个文件不画界面，
    /// 它是量对比度的尺子；要读出一个 SwiftUI `Color` 在 sRGB 下的四个分量，
    /// 除了先转成 `NSColor` 没有别的路。这一处不转，整套「≥ 4.5:1」的守卫就没有输入。
    public static func components(_ color: Color) -> Components {
        // 设计令牌豁免：这是量对比度的尺子，不画界面；读 sRGB 分量只能先转 NSColor
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return Components(red: .nan, green: .nan, blue: .nan, alpha: .nan)
        }
        return Components(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                          blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }

    public static func alpha(_ color: Color) -> Double { components(color).alpha }

    /// WCAG 相对亮度。忽略 alpha —— 调用方负责先合成。
    public static func luminance(_ color: Color) -> Double {
        let components = components(color)
        return luminance(red: components.red, green: components.green, blue: components.blue)
    }

    /// 前景压在背景上之后的对比度。背景必须是不透明令牌
    /// （`AppearanceContrastTests.testEveryBackgroundTokenIsOpaque` 守着这条约定）。
    public static func ratio(_ foreground: Color, over background: Color) -> Double {
        let fg = components(foreground)
        let bg = components(background)
        // 这三行就是这个类型存在的意义。删掉它们，所有半透明令牌都会「永远达标」。
        let red = fg.red * fg.alpha + bg.red * (1 - fg.alpha)
        let green = fg.green * fg.alpha + bg.green * (1 - fg.alpha)
        let blue = fg.blue * fg.alpha + bg.blue * (1 - fg.alpha)

        let front = luminance(red: red, green: green, blue: blue)
        let back = luminance(red: bg.red, green: bg.green, blue: bg.blue)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }

    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
