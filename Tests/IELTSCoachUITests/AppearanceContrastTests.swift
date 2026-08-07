import Foundation
import SwiftUI
import XCTest

@testable import IELTSCoachUI

/// 两套外观的对比度矩阵。
///
/// **为什么是矩阵而不是挑几条断言：** 任何一组只在浅色下被检查过的前景/背景配对，
/// 都是深色下的一个洞。深色下最典型的失败不是「难看」，是「那行字直接看不见了」，
/// 而写这行字的人多半用浅色开发，永远撞不上。
///
/// **这里只认 `Palette.light` / `Palette.dark` 这两套静态取值。**
/// `Palette.accent` 那一组是随系统外观解析的动态颜色，拿它去算对比度，
/// 算到的是「跑测试那一刻恰好是什么外观」——开发者的机器是浅色，
/// 于是「深色的对比度测试」实际测的是浅色，永远绿。
final class AppearanceContrastTests: XCTestCase {

    private struct Pair {
        let name: String
        let foreground: Color
        let background: Color
    }

    // MARK: - 唯一一份配对表

    /// 每个令牌 → 取值。**这份映射存在的唯一理由是 Swift 取不到属性的名字**，
    /// 而下面那条完整性测试要按名字把「`PaletteTokens` 里声明了什么」
    /// 和「这里检查了什么」对起来。它自己会被对着源码校验（多一个、少一个、改了名都红）。
    /// 写成计算属性而不是 `static let`：`KeyPath` 在 Swift 6 的并发检查下不算 `Sendable`，
    /// 存成全局常量编不过。计算属性没有存储，也就没有共享可变状态。
    private static var accessors: [String: KeyPath<PaletteTokens, Color>] { [
        "accent": \.accent,
        "sidebarBackground": \.sidebarBackground,
        "sidebarText": \.sidebarText,
        "sidebarTextSelected": \.sidebarTextSelected,
        "canvas": \.canvas,
        "card": \.card,
        "cardBorder": \.cardBorder,
        "textPrimary": \.textPrimary,
        "textSecondary": \.textSecondary,
        "textOnAccent": \.textOnAccent,
        "success": \.success,
        "warning": \.warning,
        "danger": \.danger
    ] }

    /// 会被当成文字画出来的令牌 → 它会压在哪些底色上。每一对、每套外观都得过 4.5:1。
    ///
    /// `accent` 也在这里：`PrimaryActionCard` 的按钮是白底紫字（`Components.swift`），
    /// 所以它既是底色也是文字色。
    ///
    /// **下面的 `textPairs(for:)` 是从这张表算出来的，不是另抄一份。**
    /// 抄两份的话，新加的配对写进一边、忘了另一边，是这类表的通病。
    private static let textTokensOnBackgrounds: [String: [String]] = [
        "textPrimary": ["canvas", "card"],
        "textSecondary": ["canvas", "card"],
        "textOnAccent": ["accent"],
        "sidebarText": ["sidebarBackground"],
        "sidebarTextSelected": ["sidebarBackground"],
        "success": ["canvas", "card"],
        "warning": ["canvas", "card"],
        "danger": ["canvas", "card"],
        "accent": ["canvas", "card"]
    ]

    /// 从不当文字用的令牌。列在这里是一次显式的判断，不是「忘了检查」——
    /// `cardBorder` 是发丝边框（DESIGN-SYSTEM 第 4 节），按文字标准量它必然不达标，
    /// 但它本来就不是给人读的。
    private static let nonTextTokens: Set<String> = [
        "canvas", "card", "sidebarBackground", "cardBorder"
    ]

    /// 失败信息里的中文名。看到「深色的『警告文字 vs 卡片』只有 3.9:1」，
    /// 比看到「dark warning/card 3.9」更容易知道屏幕上哪一处会读不清。
    private static let foregroundNames = [
        "textPrimary": "正文", "textSecondary": "次要文字",
        "textOnAccent": "主色块上的文字", "sidebarText": "侧边栏文字",
        "sidebarTextSelected": "侧边栏选中文字", "success": "成功文字",
        "warning": "警告文字", "danger": "危险文字", "accent": "主色文字"
    ]
    private static let backgroundNames = [
        "canvas": "内容区底色", "card": "卡片",
        "sidebarBackground": "侧边栏底色", "accent": "主色"
    ]

    /// 所有承载文字的前景/背景配对。
    /// **背景一律用不透明令牌**——`ContrastMath` 只合成前景的 alpha，
    /// 背景是半透明时算出来的数跟屏幕上的观感没关系
    /// （`testEveryBackgroundTokenIsOpaque` 守着这条约定）。
    private func textPairs(for appearance: Appearance) -> [Pair] {
        let tokens = Palette.tokens(for: appearance)
        return Self.textTokensOnBackgrounds.keys.sorted().flatMap { foreground -> [Pair] in
            (Self.textTokensOnBackgrounds[foreground] ?? []).sorted().compactMap { background in
                guard let foregroundPath = Self.accessors[foreground],
                      let backgroundPath = Self.accessors[background] else { return nil }
                let name = (Self.foregroundNames[foreground] ?? foreground)
                    + " vs " + (Self.backgroundNames[background] ?? background)
                return Pair(name: name,
                            foreground: tokens[keyPath: foregroundPath],
                            background: tokens[keyPath: backgroundPath])
            }
        }
    }

    // MARK: - 底线（DESIGN-SYSTEM 第 2 节，不可协商）

    func testEveryTextPairMeetsAAInBothAppearances() {
        for appearance in Appearance.allCases {
            let pairs = textPairs(for: appearance)
            // 防空转：配对表被清空、key path 对不上号的话，下面那圈一次都不跑也是全绿。
            XCTAssertGreaterThanOrEqual(
                pairs.count, 15,
                "\(appearance.rawValue) 只算出 \(pairs.count) 对配对，这条测试很可能在空转。"
                    + "下一步：确认 `textTokensOnBackgrounds` 与 `accessors` 还对得上号。")
            for pair in pairs {
                let ratio = ContrastMath.ratio(pair.foreground, over: pair.background)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(appearance.rawValue) 的「\(pair.name)」只有 "
                        + String(format: "%.2f", ratio)
                        + ":1，低于 4.5:1（DESIGN-SYSTEM 第 2 节，不可协商）。"
                        + "下一步：把这个令牌在这套外观下调深/调亮一档，不要改这条 4.5。")
            }
        }
    }

    func testEveryBackgroundTokenIsOpaque() {
        // ContrastMath 只合成前景的 alpha。背景一旦半透明，
        // 上面那条矩阵算出来的就只是个好看的数字，跟屏幕上看到的没关系。
        let backgrounds = Set(Self.textTokensOnBackgrounds.values.joined())
        XCTAssertGreaterThanOrEqual(backgrounds.count, 4,
                                    "只取到 \(backgrounds.count) 个底色，这条测试很可能在空转")
        for appearance in Appearance.allCases {
            let tokens = Palette.tokens(for: appearance)
            for name in backgrounds.sorted() {
                guard let path = Self.accessors[name] else {
                    XCTFail("`\(name)` 不在 accessors 里，取不到取值")
                    continue
                }
                XCTAssertEqual(
                    ContrastMath.alpha(tokens[keyPath: path]), 1.0, accuracy: 0.001,
                    "\(appearance.rawValue) 的 \(name) 不是不透明的。"
                        + "下一步：把它改成不透明取值，否则所有压在它上面的对比度都算不准。")
            }
        }
    }

    // MARK: - 完整性：新加一个令牌，不许没人管

    /// **上面那张配对表是手写的，这条守的是它的完整性。**
    ///
    /// Phase 3 实测过：往 `Palette` 里加一个 `subtle = Color.black.opacity(0.28)`（约 2.3:1）
    /// 并在 `EmptyStateView` 上用它 —— 全套一条不红。铁律 8 只要求「视图走令牌」，
    /// 而这个新令牌确实是令牌，于是扫描放行；对比度那几条又只认名字写死的那几个。
    /// 「灰上加灰」就这么从正门走进来了。
    ///
    /// 所以：`PaletteTokens` 里声明的每一个令牌，都必须在这里被显式归类，
    /// 归成文字色的就当场量两套外观的对比度。新增一个令牌 → 名单对不上 → 红，逼人做这个判断。
    func testEveryPaletteTokenIsClassifiedInBothAppearances() throws {
        let code = try SourceGuard.code("DesignSystem/Palette.swift")
        let body = try SourceGuard.memberBody(of: "public struct PaletteTokens", in: code)
        let declared = Set(Self.declaredPropertyNames(in: body))

        XCTAssertGreaterThanOrEqual(declared.count, 13,
                                    "只解析到 \(declared.count) 个颜色令牌，疑似空转。"
                                        + "下一步：确认 `PaletteTokens` 里还是 `public let` 声明。")
        XCTAssertEqual(
            declared, Set(Self.accessors.keys),
            "`PaletteTokens` 里声明的令牌和这个测试文件里的映射对不上（多出来或少掉的那个"
                + "现在没有任何对比度断言管得着）。下一步：同步 `accessors`。")
        XCTAssertEqual(
            declared, Set(Self.textTokensOnBackgrounds.keys).union(Self.nonTextTokens),
            "有令牌既没被归成文字色、也没被归成非文字色。下一步：想清楚它会不会被人读——"
                + "会读就写进 `textTokensOnBackgrounds` 并指明压在哪个底色上，"
                + "不会读就写进 `nonTextTokens`。不许因为「不好过」就归到后者（铁律 10）。")
        XCTAssertTrue(
            Set(Self.textTokensOnBackgrounds.keys).isDisjoint(with: Self.nonTextTokens),
            "同一个令牌既归了文字色又归了非文字色，归类失去意义")
    }

    private static func declaredPropertyNames(in body: String) -> [String] {
        // 只认属性声明。`init` 的参数写的是 `accent: Color`，没有 `public let`，不会被算进来。
        let text = body as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"public\s+let\s+([A-Za-z_][A-Za-z0-9_]*)"#) else { return [] }
        return regex.matches(in: body, range: NSRange(location: 0, length: text.length))
            .compactMap { $0.numberOfRanges > 1 ? text.substring(with: $0.range(at: 1)) : nil }
    }

    // MARK: - 深色是真的深色，不是浅色的别名

    func testDarkIsActuallyDark() {
        // 少了这一条，「深色模式」可以是一个把浅色原样返回的空实现，
        // 而上面那条矩阵会照样全绿——那正是本项目消灭过 15 次的空转。
        XCTAssertLessThan(
            ContrastMath.luminance(Palette.tokens(for: .dark).canvas),
            ContrastMath.luminance(Palette.tokens(for: .light).canvas) / 4,
            "深色的内容区底色并不比浅色暗，深色模式没有真做出来。"
                + "下一步：确认 `Palette.dark` 是另一套取值，而不是指回 `light`。")
        XCTAssertGreaterThan(
            ContrastMath.luminance(Palette.tokens(for: .dark).textPrimary),
            ContrastMath.luminance(Palette.tokens(for: .dark).canvas),
            "深色下正文比背景还暗。下一步：把 `dark.textPrimary` 调成浅色文字。")
    }

    func testCardsStandOutFromTheCanvasInBothAppearances() {
        // 卡片靠「比背景亮一点」分层（DESIGN-SYSTEM 第 4 节：不加投影）。
        // 深色下把卡片做得比背景暗，每张卡片会变成一个洞。
        for appearance in Appearance.allCases {
            let tokens = Palette.tokens(for: appearance)
            XCTAssertGreaterThan(
                ContrastMath.luminance(tokens.card),
                ContrastMath.luminance(tokens.canvas),
                "\(appearance.rawValue) 的卡片没有比内容区底色亮，卡片会变成一个洞。"
                    + "下一步：把 `card` 调得比 `canvas` 亮一档。")
        }
    }

    func testTheDarkPaletteIsNotJustTheLightOneInverted() {
        // DESIGN-SYSTEM 第 2 节：不要用反色实现深色模式，要用降饱和的色调变体。
        // 反色的判据：深色主色 ≈ 1 − 浅色主色（逐通道）。
        let light = ContrastMath.components(Palette.tokens(for: .light).accent)
        let dark = ContrastMath.components(Palette.tokens(for: .dark).accent)
        let inverted = abs((1 - light.red) - dark.red) < 0.02
            && abs((1 - light.green) - dark.green) < 0.02
            && abs((1 - light.blue) - dark.blue) < 0.02
        XCTAssertFalse(inverted,
                       "深色主色是浅色主色的反色，规范明确禁止这种做法。"
                           + "下一步：改用降饱和、调亮的同色相变体，并重新量对比度。")
    }

    // MARK: - 尺子本身

    func testAlphaIsCompositedInsteadOfIgnored() {
        // 56% 黑压在白底上，观感等同 #747474，比值约 4.94:1。
        // 忽略 alpha 的实现会把它当成纯黑，算出 21:1 ——
        // 那样每个半透明令牌都「永远达标」，整条矩阵成了摆设。
        let ratio = ContrastMath.ratio(Color.black.opacity(0.56), over: .white)
        XCTAssertEqual(ratio, 4.94, accuracy: 0.2)
        XCTAssertLessThan(ratio, 6.0, "把半透明前景当成不透明色算了")
        // 两个已知值，钉住这把尺子的刻度本身（不透明色不受合成影响）
        XCTAssertEqual(ContrastMath.ratio(.black, over: .white), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastMath.ratio(.white, over: .white), 1, accuracy: 0.01)
    }

    func testComponentsKeepAlphaSeparateFromTheColorItself() {
        // 这一条把「为什么忽略 alpha 会错」摆在明面上：
        // 56% 黑的三个分量就是纯黑，透明度全在 alpha 上。
        // 拿分量直接算亮度，算的是纯黑——21:1，而屏幕上是 4.94:1。
        let components = ContrastMath.components(Color.black.opacity(0.56))
        XCTAssertEqual(components.red, 0, accuracy: 0.001)
        XCTAssertEqual(components.green, 0, accuracy: 0.001)
        XCTAssertEqual(components.blue, 0, accuracy: 0.001)
        XCTAssertEqual(components.alpha, 0.56, accuracy: 0.01)
    }
}
