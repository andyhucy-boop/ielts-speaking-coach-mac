import AppKit
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
/// **算对比度只认 `Palette.light` / `Palette.dark` 这两套静态取值。**
/// `Palette.accent` 那一组是随系统外观解析的动态颜色，拿它去算对比度，
/// 算到的是「跑测试那一刻恰好是什么外观」——开发者的机器是浅色，
/// 于是「深色的对比度测试」实际测的是浅色，永远绿。
///
/// **但「动态令牌解析到哪一套」本身必须验，而且只能在显式指定的外观下验。**
/// 那是本任务的核心产出：视图一行没改，颜色跟着系统外观走。
/// `testDynamicTokensResolveToTheAppearanceTheyAreDrawnIn` 用
/// `NSAppearance.performAsCurrentDrawingAppearance` 把外观钉死再解析，
/// 所以它不受跑测试那台机器的外观影响。
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
        "sidebarHighlight": \.sidebarHighlight,
        "canvas": \.canvas,
        "card": \.card,
        "surfaceSubtle": \.surfaceSubtle,
        "accentSoft": \.accentSoft,
        "cardBorder": \.cardBorder,
        "cardBorderStrong": \.cardBorderStrong,
        "textPrimary": \.textPrimary,
        "textSecondary": \.textSecondary,
        "textOnAccent": \.textOnAccent,
        "success": \.success,
        "warning": \.warning,
        "danger": \.danger
    ] }

    /// 名字 → 视图真正引用的那个**动态**令牌。
    ///
    /// 上面那张 `accessors` 给的是两套静态取值，够算对比度，但拿不到 `Palette.accent`
    /// 这一层——而视图引用的恰恰是这一层。两张表都对着源码校验（见完整性那条测试），
    /// 所以「加了 `PaletteTokens` 属性却忘了加动态别名」也会红。
    private static var dynamicTokens: [String: Color] { [
        "accent": Palette.accent,
        "sidebarBackground": Palette.sidebarBackground,
        "sidebarText": Palette.sidebarText,
        "sidebarTextSelected": Palette.sidebarTextSelected,
        "sidebarHighlight": Palette.sidebarHighlight,
        "canvas": Palette.canvas,
        "card": Palette.card,
        "surfaceSubtle": Palette.surfaceSubtle,
        "accentSoft": Palette.accentSoft,
        "cardBorder": Palette.cardBorder,
        "cardBorderStrong": Palette.cardBorderStrong,
        "textPrimary": Palette.textPrimary,
        "textSecondary": Palette.textSecondary,
        "textOnAccent": Palette.textOnAccent,
        "success": Palette.success,
        "warning": Palette.warning,
        "danger": Palette.danger
    ] }

    /// `Palette` 这个 enum 里不是颜色令牌的那两个 `public static let`。
    /// 它们是整套静态取值（`PaletteTokens`），是对比度矩阵的输入，不是拿来画界面的颜色。
    /// 写死在这里是一次显式判断：以后再多一个非颜色的 `public static let`，
    /// 下面那条完整性断言会当场红，逼人来这儿说清它是什么。
    private static let nonColorMembersOfPalette: Set<String> = ["light", "dark"]

    /// 会被当成文字画出来的令牌 → 它会压在哪些底色上。每一对、每套外观都得过 4.5:1。
    ///
    /// `accent` 也在这里：`PrimaryActionCard` 的按钮是白底紫字（`Components.swift`），
    /// 所以它既是底色也是文字色。
    ///
    /// **下面的 `textPairs(for:)` 是从这张表算出来的，不是另抄一份。**
    /// 抄两份的话，新加的配对写进一边、忘了另一边，是这类表的通病。
    private static let textTokensOnBackgrounds: [String: [String]] = [
        "textPrimary": ["canvas", "card", "surfaceSubtle", "accentSoft"],
        "textSecondary": ["canvas", "card", "surfaceSubtle", "accentSoft"],
        "textOnAccent": ["accent"],
        // 侧边栏那一行在「选中 / 鼠标悬停」时底色会换成 `sidebarHighlight`，
        // 两种底色上都得读得清——只验一种的话，另一种就是没人看过的那一半。
        "sidebarText": ["sidebarBackground", "sidebarHighlight"],
        "sidebarTextSelected": ["sidebarBackground", "sidebarHighlight"],
        // 语义色**刻意不列 `accentSoft`**：那是主色调的浅底，
        // 橙字压紫底是不该出现的配色，工程里也没有这么用的地方。
        // 归到这里只为了「不好过就少列一个」——那正是铁律 10 禁止的（见下面那条完整性守卫）。
        "success": ["canvas", "card", "surfaceSubtle"],
        "warning": ["canvas", "card", "surfaceSubtle"],
        "danger": ["canvas", "card", "surfaceSubtle"],
        // `accent` 既当底色也当文字色：`CoachBadge(kind: .accent)` 是主色字压在 `accentSoft` 上。
        "accent": ["canvas", "card", "surfaceSubtle", "accentSoft"]
    ]

    /// 从不当文字用的令牌。列在这里是一次显式的判断，不是「忘了检查」——
    /// `cardBorder` 是发丝边框（DESIGN-SYSTEM 第 4 节），按文字标准量它必然不达标，
    /// 但它本来就不是给人读的。
    private static let nonTextTokens: Set<String> = [
        "canvas", "card", "surfaceSubtle", "accentSoft",
        "sidebarBackground", "sidebarHighlight",
        // 两道边框都不是给人读的：`cardBorder` 是发丝分层线，
        // `cardBorderStrong` 是悬停/选中时那一档。按文字标准量它们必然不达标。
        "cardBorder", "cardBorderStrong"
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
        "surfaceSubtle": "卡片里的浅色嵌块", "accentSoft": "主色浅底",
        "sidebarBackground": "侧边栏底色", "sidebarHighlight": "侧边栏选中/悬停底",
        "accent": "主色"
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
                pairs.count, 26,
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
        XCTAssertGreaterThanOrEqual(backgrounds.count, 7,
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
    /// Phase 3 实测过、2026-08-08 复审又实测过一次：往 `Palette` 里加一个
    /// `subtle = Color.black.opacity(0.28)`（对白卡约 2.3:1）并在 `EmptyStateView` 上用它
    /// —— 全套 1621 条一条不红。铁律 8 只要求「视图走令牌」，而这个新令牌确实是令牌，
    /// 于是扫描放行；对比度那几条又只认名字写死的那几个。「灰上加灰」就这么从正门走进来了。
    ///
    /// **所以这条必须同时盯住两面**，少一面就是留了那个洞：
    ///   · `PaletteTokens` 里的 `public let` —— 对比度矩阵的输入；
    ///   · `enum Palette` 里的 `public static let` —— **视图真正引用的那一面**。
    ///     只盯前者的话，上面那个 `subtle` 加在后者上，前者的名单纹丝不动。
    ///
    /// 两面还必须**互相相等**：这样「加了 `PaletteTokens` 属性却忘了加动态别名」
    /// （那个属性在深色下永远拿不到）与「只加了动态别名」（那个颜色没有任何对比度断言管得着）
    /// 都会红。归成文字色的当场量两套外观的对比度。
    func testEveryPaletteTokenIsClassifiedInBothAppearances() throws {
        let code = try SourceGuard.code("DesignSystem/Palette.swift")
        let body = try SourceGuard.memberBody(of: "public struct PaletteTokens", in: code)
        let declared = Set(Self.declaredPropertyNames(in: body))

        XCTAssertGreaterThanOrEqual(declared.count, 17,
                                    "只解析到 \(declared.count) 个颜色令牌，疑似空转。"
                                        + "下一步：确认 `PaletteTokens` 里还是 `public let` 声明。")

        // 视图引用的那一面。`dynamic(_:)` 是 private func，不会被这条正则算进来。
        let staticMembers = Set(try SourceGuard.declaredTokenNames(inEnum: "Palette", of: code))
        XCTAssertGreaterThanOrEqual(
            staticMembers.count, 19,
            "只解析到 \(staticMembers.count) 个 `Palette` 成员，疑似空转。"
                + "下一步：确认 `Palette` 里还是 `public static let` 声明。")
        XCTAssertTrue(
            Self.nonColorMembersOfPalette.isSubset(of: staticMembers),
            "`Palette` 里少了 \(Self.nonColorMembersOfPalette.subtracting(staticMembers).sorted())"
                + "——那是对比度矩阵的输入。下一步：确认这两套静态取值还在，"
                + "不要把矩阵的输入换成动态颜色（动态颜色会按跑测试那一刻的外观解析，永远绿）。")
        let colorMembers = staticMembers.subtracting(Self.nonColorMembersOfPalette)
        let onlyOnPalette = colorMembers.subtracting(declared).sorted()
        let onlyOnTokens = declared.subtracting(colorMembers).sorted()
        XCTAssertEqual(
            colorMembers, declared,
            "`Palette` 里的颜色令牌和 `PaletteTokens` 里声明的对不上。"
                + "只在 `Palette` 上的 \(onlyOnPalette)：没有任何对比度断言管得着它，"
                + "而且这样加进来的多半是写死的静态色，深色下根本不跟随外观。"
                + "只在 `PaletteTokens` 上的 \(onlyOnTokens)：视图根本引用不到。"
                + "下一步：两边都补齐——`PaletteTokens` 里加 `public let` 并给两套取值各一个值，"
                + "`Palette` 里加 `public static let x = dynamic(\\.x)`。")

        XCTAssertEqual(
            declared, Set(Self.dynamicTokens.keys),
            "这个测试文件里的 `dynamicTokens` 映射和 `PaletteTokens` 的声明对不上，"
                + "漏掉的那个令牌没人验过它跟不跟随外观。下一步：同步 `dynamicTokens`。")
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

    // MARK: - 动态令牌真的跟着系统外观走

    /// 把一个动态令牌按指定外观解析出来。
    ///
    /// 这是**唯一**能验到 `Palette.dynamic(_:)` 那个闭包的办法：上面所有测试拿的都是
    /// `Palette.tokens(for:)` 的静态取值，一次都不经过动态解析这条路。
    /// 不在测试里显式指定外观的话，`NSColor(…).usingColorSpace(.sRGB)` 解析到的是
    /// 「跑测试那台机器此刻是什么外观」——开发者的机器是浅色，深色那一半永远绿。
    private func resolve(_ token: Color, as appearance: Appearance) -> ContrastMath.Components {
        let missing = ContrastMath.Components(red: .nan, green: .nan, blue: .nan, alpha: .nan)
        let name: NSAppearance.Name = appearance == .dark ? .darkAqua : .aqua
        guard let nsAppearance = NSAppearance(named: name) else {
            XCTFail("取不到 \(name.rawValue) 外观，这条测试没法验任何东西。"
                        + "下一步：确认跑测试的是 macOS，且 AppKit 可用。")
            return missing
        }
        var resolved = missing
        nsAppearance.performAsCurrentDrawingAppearance {
            resolved = ContrastMath.components(token)
        }
        return resolved
    }

    /// **这条守的是本任务的核心产出：视图一行没改，颜色却跟着系统外观走。**
    ///
    /// 少了它，`dynamic(_:)` 里的映射写反（浅色系统显示深色盘）或者永远返回 `light`
    /// （等于深色模式在真机上压根不存在）都是全绿的——两种都实测过。
    /// 上面那些矩阵拦不住，因为它们一次都不碰动态解析这条路。
    ///
    /// 顺带钉住半透明令牌的 alpha 不会在动态包装里丢掉：丢了的话
    /// `textSecondary` 会从 70% 白变成实心白，深色下的层次全平掉。
    func testDynamicTokensResolveToTheAppearanceTheyAreDrawnIn() {
        var checked = 0
        for appearance in Appearance.allCases {
            let expected = Palette.tokens(for: appearance)
            for (name, token) in Self.dynamicTokens.sorted(by: { $0.key < $1.key }) {
                guard let path = Self.accessors[name] else {
                    XCTFail("`\(name)` 不在 accessors 里，取不到该比对的静态值")
                    continue
                }
                let actual = resolve(token, as: appearance)
                let want = ContrastMath.components(expected[keyPath: path])
                let hint = "`Palette.\(name)` 在 \(appearance.rawValue) 外观下解析成了别的值。"
                    + "下一步：检查 `Palette.dynamic(_:)` 里 `isDark` 到 `Appearance` 的映射"
                    + "有没有写反，以及 `\(name)` 是不是漏写成了不跟随外观的静态色。"
                XCTAssertEqual(actual.red, want.red, accuracy: 0.002, "红通道：" + hint)
                XCTAssertEqual(actual.green, want.green, accuracy: 0.002, "绿通道：" + hint)
                XCTAssertEqual(actual.blue, want.blue, accuracy: 0.002, "蓝通道：" + hint)
                XCTAssertEqual(actual.alpha, want.alpha, accuracy: 0.002, "不透明度：" + hint)
                checked += 1
            }
        }
        // 防空转：映射表被清空、或 guard 每次都走了 continue，上面那圈一次都不跑也是全绿。
        XCTAssertGreaterThanOrEqual(
            checked, 34,
            "只验了 \(checked) 个令牌×外观的组合（应为 17×2），这条测试很可能在空转。"
                + "下一步：确认 `dynamicTokens` 与 `accessors` 还对得上号。")
    }

    /// 同一个令牌，在两套外观下必须解析成**不同**的颜色。
    ///
    /// 这是上面那句话的最小版本，故意**不经过 `dynamicTokens` / `accessors` 这两张手写表**：
    /// 上面那条循环再严，它的覆盖面也系在这两张表上；表本身出了错（比如被谁改窄了），
    /// 「深色下真的换了一套颜色」这个最核心的结论就跟着一起失守。
    /// 这条只认死了 `Palette.canvas` 一个令牌，任何时候都还在。
    func testTheSameTokenResolvesDifferentlyInTheTwoAppearances() {
        let light = resolve(Palette.canvas, as: .light)
        let dark = resolve(Palette.canvas, as: .dark)
        XCTAssertGreaterThan(
            light.red - dark.red, 0.5,
            "`Palette.canvas` 在深色外观下没有解析成深色（浅色 \(light.red)、深色 \(dark.red)）。"
                + "下一步：确认动态令牌确实按绘制时的外观解析，而不是被固定成了一套。")
    }

    // MARK: - 玻璃只许当浮层，不许当底

    /// **液态玻璃不许铺在整片侧边栏底上。**
    ///
    /// 2026-08-30 试过，实测否掉了：`Glass.tint(_:)` 是给材质**上色**，
    /// 不是按不透明度把颜色压上去——传一个 alpha 0.92 的深紫进去，
    /// 渲染出来仍然是浅色（从实机截图上采样到 rgb(219,219,220)）。
    /// 于是这条深色侧边栏在浅色壁纸下整片变浅，白字糊成一片；
    /// 而在开发者自己的深色壁纸上，这件事完全看不出来。
    ///
    /// 玻璃跟着背后的东西走，而侧边栏背后是用户的壁纸。所以它只能当浮层
    /// （选中那颗药丸、面板上那几颗按钮），不能当承载文字的底。
    ///
    /// 这条守的是「别再试一次」：源码里那句 `.background(Palette.sidebarBackground)`
    /// 一旦被换成 `coachGlass`，这里当场变红。
    func testTheSidebarSurfaceItselfIsOpaqueAndOnlyThePillIsGlass() throws {
        let code = try SourceGuard.code("Sidebar/SidebarView.swift")
        let body = try SourceGuard.memberBody(of: "var body: some View", in: code)
        XCTAssertTrue(
            body.contains(".background(Palette.sidebarBackground)"),
            "侧边栏底不再是不透明的 `Palette.sidebarBackground`。玻璃跟着背后的东西走，"
                + "而这一片背后是用户的壁纸——浅色壁纸下整条侧边栏会变浅，白字糊成一片，"
                + "而开发者自己的深色壁纸上完全看不出来（2026-08-30 实测采样确认）。"
                + "下一步：玻璃只给浮层用（选中那颗药丸、面板上那几颗按钮）。"
                + "实际取到的是：\n\(body)")
        XCTAssertFalse(
            body.contains("coachGlass"),
            "整片侧边栏底又用上玻璃了，理由同上。实际取到的是：\n\(body)")
        // 反过来也要有牙齿：玻璃必须真的用在**某处**，否则这条就只是在禁止一件没人做的事。
        //
        // 用在哪儿变过一次：起初给了侧边栏选中的那颗药丸，后来撤了——
        // 玻璃要么在要么不在，做不出淡入淡出，而那颗药丸需要跟着悬停平滑地亮起来
        // （见 `SidebarView.pill`）。现在留在两处真正的浮层上：
        // 主行动卡片的按钮、复盘页目标横幅的按钮，两处都浮在有颜色的面板上。
        let glassUsers = ["DesignSystem/Components.swift", "Review/ReviewReportView.swift"]
        var found = 0
        for path in glassUsers where try SourceGuard.code(path).contains(".coachGlass(") {
            found += 1
        }
        XCTAssertEqual(
            found, glassUsers.count,
            "液态玻璃已经不在那两处浮层上了（\(glassUsers)）。"
                + "这条测试禁止把玻璃铺在承载文字的底上，但如果玻璃哪儿都不用了，"
                + "它就只是在禁止一件没人做的事——那种守卫是恒绿的。"
                + "下一步：确认 `coachGlass` 还用在主行动卡片和复盘页目标横幅的按钮上。")
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

        // `alpha(_:)` 也是一把量具，而且是 `testEveryBackgroundTokenIsOpaque` 唯一的输入。
        // 把它写死成 `{ 1.0 }`（「全都不透明」）之后那条守卫就只剩形状——实测全绿。
        // `testComponentsKeepAlphaSeparateFromTheColorItself` 盖不住它：那条测的是
        // `components(_:)`，不经过 `alpha(_:)`。
        XCTAssertEqual(
            ContrastMath.alpha(Color.black.opacity(0.56)), 0.56, accuracy: 0.01,
            "`alpha(_:)` 没有读出真正的不透明度。下一步：让它回到 `components(color).alpha`，"
                + "否则 `testEveryBackgroundTokenIsOpaque` 就只剩形状——半透明底色会一路放行。")
        XCTAssertEqual(
            ContrastMath.alpha(.black), 1.0, accuracy: 0.001,
            "`alpha(_:)` 把不透明色也读错了。下一步：确认它读的是 sRGB 的 alpha 分量。")
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
