import Foundation
import XCTest

@testable import IELTSCoachUI

/// 铁律 6（界面走设计令牌，视图里不得出现字面颜色、字号、圆角）的**肯定那一半**。
///
/// 之前只有 `DesignSystemTests` 扫 `DesignSystem/` 一个目录，而且只认「点开头」的 `font(.`。
/// 已实测的两个后果：
///
/// - 把 `Components.swift` 的 `.foregroundStyle(Palette.textSecondary)` 换成一个字面灰色 → 全绿；
/// - 把 `.font(Typography.label)` 换成 `.font(Font.caption)` → 全绿（换个拼法就绕过去了）。
///
/// **「一处字面样式都不许有」那条禁令已经搬去 `DesignTokenContractTests`**（Phase 10 Task 13），
/// 并且顺手把 `notYetMigrated` 那个整文件豁免的口子拆了——`RootView.swift` 与
/// `PermissionGateView.swift` 已收编。这里留下的是禁令扫不到的那一半：
/// 每个视图**真的**从令牌取过字体和颜色，以及逐行豁免的账。
///
/// **边界**：扫源码不执行代码，管不了「写对了令牌但摆错了位置」，也不管好不好看——
/// 那部分归人工验收。它管的是「这一处样式还归不归设计系统管」。
final class DesignTokenSweepTests: XCTestCase {

    /// 令牌的定义处。字面取值**只允许**出现在这三个文件里——它们就是那张表本身，
    /// 而表里的取值由 `DesignSystemTests` 逐行钉住。
    ///
    /// `DesignTokenContractTests` 也读这一份，**刻意不各存一份**：
    /// 两份名单迟早会不一致，而不一致的那一天，宽的那一份说了算。
    ///
    /// ## 这份名单就是整个契约里唯一的整文件豁免口子
    ///
    /// 往这里加一行，那个文件**同时**脱离两条守卫：`DesignTokenContractTests` 的
    /// 「除三张表外一处字面样式都不许有」（那边用它做 filter），
    /// 和下面 `testEveryViewActuallyReachesForTheTokens`（这边用它做 exempt）。
    /// 复审实测过这条路走得通：加一行 `"Review/ReviewReportView.swift"`，
    /// 再往那个文件里插一句写死的红色和一句 `.font(.system(size: 13))`，
    /// `swift test` 是 **1623 条全绿**——正是深色下「一行看不见的字」那种失败形态。
    ///
    /// 所以这份名单**自己也被钉住**：`testTheWholeFileExemptionListIsExactlyTheThreeTokenTables`
    /// 断言它恰好是这三项，`testTokenDefinitionFilesAreTheOnlyPlaceLiteralValuesLive`
    /// 要求每一项都在下面那张 marker 表里说得出「凭什么算令牌表」。
    /// 名单要变长，就得同时改这两处——那是一次显式的、复审看得见的动作。
    static let tokenDefinitions = [
        "DesignSystem/Typography.swift",
        "DesignSystem/Palette.swift",
        "DesignSystem/Metrics.swift"
    ]

    /// 每个豁免文件**凭什么算令牌表**：里面必须有这段声明。
    ///
    /// 写成查表而不是 `zip(tokenDefinitions, [...])`。`zip` 以短的一边为准，
    /// 名单第 4 项起就一次都不会被检查——复审实测的那次越狱正是从这个缝里溜过去的
    /// （`ReviewReportView.swift` 当然没有 `public enum Spacing`，但 `zip` 根本没走到它）。
    static let tokenDefinitionMarkers = [
        "DesignSystem/Typography.swift": "public enum Typography",
        "DesignSystem/Palette.swift": "public enum Palette",
        "DesignSystem/Metrics.swift": "public enum Spacing"
    ]

    /// 「一处字面样式都不许有」那条只说「没有字面值」，
    /// 那**把所有样式修饰符统统删光也是零违规**——
    /// 一处字面值都没有，界面却整片退回 SwiftUI 的默认字体和默认前景色。
    /// 「写好的东西没被用上」正是本项目反复栽跟头的那一类，不能只守一半。
    ///
    /// 所以反过来数一遍：**每个自己画 body 的视图，字体和颜色都得真的从令牌取。**
    /// 门槛取「至少一处」——正常重构（把一段文字挪进子组件）碰不到，
    /// 整个文件的样式被删光才会碰到。
    func testEveryViewActuallyReachesForTheTokens() throws {
        let exempt = Set(Self.tokenDefinitions)
        var checked: [String] = []
        for file in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: file)
            guard !exempt.contains(path) else { continue }
            let code = try SourceGuard.code(path)
            // 只看真的画界面的文件。**判据必须带上 `: some View`**：光看「有没有 `var body`」
            // 会把纯逻辑文件也算进来——`OnboardingStep.body` 是一段**给用户看的中文正文**
            // （`String`），它当然不该引用 `Typography` 和 `Palette`，
            // 但会被下面两条断言当成「整页样式被删光了」报出来。
            // 模块里现有的每一个 SwiftUI 视图都写成 `var body: some View {`，
            // 所以这一收紧不放过任何一个真视图（下面那条 `checked.count` 的防空转断言看着）。
            guard code.contains("var body: some View") else { continue }
            checked.append(path)

            XCTAssertGreaterThan(
                SourceGuard.occurrences(of: ".font(Typography.", in: code), 0,
                "\(path) 画着界面，却一处都没用 `Typography` 设字体。这一整页的文字会退回"
                    + "SwiftUI 的默认字号和默认字重，比规范轻一档——一个字面值都找不到，"
                    + "所以上面那条「没有字面样式」照样是绿的。"
                    + "下一步：确认字体是不是被整片删掉了。")
            XCTAssertGreaterThan(
                SourceGuard.occurrences(of: "Palette.", in: code), 0,
                "\(path) 画着界面，却一处都没引用 `Palette`。"
                    + "下一步：确认颜色是不是被整片删掉了——那样这一页会退回系统默认前景色，"
                    + "既不受对比度测试保护，也不会跟着深色模式走。")
        }
        // 防空转：判断条件写坏了、一个文件都没进来的话，上面那圈一次都不跑也是全绿。
        XCTAssertGreaterThanOrEqual(
            checked.count, 5,
            "只检查了 \(checked.count) 个画界面的文件（\(checked.joined(separator: "、"))），"
                + "这条测试很可能在空转。下一步：确认 `var body` 这个判断条件还认得出视图文件。")
    }

    // 「扫描器还有没有牙齿」那一条搬去了 `DesignTokenContractTests`。
    //
    // 它原来是靠 `notYetMigrated` 那两页里「必须还挑得出违规」长着牙的，
    // 而 Task 13 把两页都收编了——留在这里只会变成一圈空数组循环，也就是恒绿。
    // 新的那一条改成往一个真实视图文件里**注入**四类违规各一处，
    // 不再依赖「模块里得有个烂页面」这种会自己消失的前提。
    //
    // 同样搬走的还有「一处字面样式都不许有」那条全模块扫描，以及 `literalCeiling`：
    // 后者是给整文件豁免记账用的，豁免拆了，账也就没有了。

    /// **整文件豁免的名单自己被钉在这里。**
    ///
    /// 上面那份 `tokenDefinitions` 是两条守卫共用的 exempt/filter 名单，
    /// 而在这条断言之前，**没有任何测试拦得住它变长**：
    /// `DesignTokenContractTests` 那条防空转只点名了两个历史文件名，外加一个 40 的下限，
    /// 而实际扫到 58 个——还剩 18 个文件的余量可以偷偷豁免掉。
    /// 复审实测：加一行 `"Review/ReviewReportView.swift"` 再往那页插两处写死的样式，
    /// 1623 条全绿。而那条测试的名字（NoWholeFileEscapeHatch）和 commit message
    /// 都在声称「没有整文件豁免这个口子」。
    ///
    /// 所以这里逐字钉死：**名单要变长，必须先把这条断言改掉**——
    /// 那是一次显式的、复审一眼看得见的动作，而不是往数组里加一行就把守卫关了。
    ///
    /// 第二条（每一项都在 `DesignSystem/` 下）是给「就算真要加第四张表」留的边界：
    /// 令牌表只能住在设计系统目录里，任何一个画界面的文件都不可能满足它。
    func testTheWholeFileExemptionListIsExactlyTheThreeTokenTables() throws {
        XCTAssertEqual(
            Self.tokenDefinitions,
            ["DesignSystem/Typography.swift",
             "DesignSystem/Palette.swift",
             "DesignSystem/Metrics.swift"],
            "整文件豁免名单变成了 \(Self.tokenDefinitions)。这份名单里的文件"
                + "**同时**脱离「一处字面样式都不许有」和「每个视图真的取过令牌」两条守卫——"
                + "往里加一个视图文件，它写死的颜色在深色下就是一行看不见的字，而测试全绿。"
                + "下一步：想加的那个文件如果是视图，改用逐行的"
                + "「\(SourceGuard.exemptionMarker)」注释（那是有人数着的）；"
                + "确实新增了第四张令牌表，就连同 `tokenDefinitionMarkers` 一起改，"
                + "并在复审里说清它为什么必须能写字面取值。")
        for path in Self.tokenDefinitions {
            XCTAssertTrue(
                path.hasPrefix("DesignSystem/"),
                "豁免名单里的「\(path)」不在 DesignSystem/ 目录下。"
                    + "能写字面取值的只有令牌表本身，而令牌表只住在设计系统目录里。"
                    + "下一步：把它挪出名单——画界面的文件一律走令牌。")
        }
    }

    /// 令牌定义文件必须真的在，而且真的在定义令牌。
    ///
    /// 它们是唯一被允许写字面取值的地方，名单一旦指错文件，整条豁免就变成一个洞。
    ///
    /// **逐项查表，不用 `zip`。** 原来写的是
    /// `zip(tokenDefinitions, ["public enum Typography", …])`，而 `zip` 以短的一边为准——
    /// 名单第 4 项及以后一次都不会被检查，这条测试对它们**恒真**。
    /// 复审实测的越狱（往名单里加 `"Review/ReviewReportView.swift"`）正是从这个缝里溜过去的：
    /// 那个文件里当然没有 `public enum Spacing`，但 `zip` 根本没走到它。
    /// 现在名单里出现表外的路径就当场变红。
    func testTokenDefinitionFilesAreTheOnlyPlaceLiteralValuesLive() throws {
        for path in Self.tokenDefinitions {
            guard let marker = Self.tokenDefinitionMarkers[path] else {
                XCTFail("豁免名单里的「\(path)」在 `tokenDefinitionMarkers` 里没有对应条目，"
                        + "也就没人问过它凭什么算令牌表——这一项是被白白豁免掉的。"
                        + "下一步：要么把它从名单里去掉，要么在 marker 表里写上"
                        + "它必须包含的那段令牌声明。")
                continue
            }
            let code = try SourceGuard.code(path)
            XCTAssertTrue(
                code.contains(marker),
                "\(path) 里没有「\(marker)」。豁免名单指着一个不再定义令牌的文件，"
                    + "等于在扫描上开了个洞。下一步：确认令牌是不是搬了家，名单要跟着改。")
        }
        // 反过来也要对得上：marker 表里躺着一条名单上没有的路径，
        // 说明两张表已经错位，而错位时宽的那一张（名单）说了算。
        for path in Self.tokenDefinitionMarkers.keys where !Self.tokenDefinitions.contains(path) {
            XCTFail("`tokenDefinitionMarkers` 里有「\(path)」，但它不在 `tokenDefinitions` 名单上。"
                    + "两张表错位了，这条检查就检查不到真正被豁免的那些文件。"
                    + "下一步：把两张表对齐——名单是唯一的豁免依据，marker 表只是给它作注。")
        }
    }

    // MARK: - 逐行豁免

    /// 单行豁免（`// 设计令牌豁免：<理由>`）是留给「确有正当理由用字面值」那一处的口子。
    /// 口子一开就得有人数着，否则它会从「一处特例」长成「哪儿红就往哪儿贴」。
    ///
    /// **现在全模块是 1 处**，记在案的就是它：
    ///
    /// - `DesignSystem/ContrastMath.swift` 里 `components(_:)` 那一行的 `NSColor(color)`。
    ///   颜色规则是冲着「视图里绕开令牌自己调色」来的，而这个文件不画界面——
    ///   它是量对比度的尺子。要读出一个 SwiftUI `Color` 在 sRGB 下的四个分量，
    ///   除了先转成 `NSColor` 没有别的路；这一处不转，整套「≥ 4.5:1」的守卫就没有输入。
    ///
    /// 要再新增就得同时改这个数字——那是一次显式的、
    /// 会被复审看见的动作，而不是随手加一行注释就把守卫关掉。
    static let exemptionCeiling = 1

    func testLineLevelExemptionsAreCountedAndAlwaysGiveAReason() throws {
        var all: [(path: String, exemption: SourceGuard.Exemption)] = []
        var scanned = 0
        for file in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: file)
            scanned += 1
            for exemption in SourceGuard.exemptions(in: try SourceGuard.read(path)) {
                all.append((path, exemption))
            }
        }
        XCTAssertGreaterThanOrEqual(scanned, 8, "只扫到 \(scanned) 个文件，这条测试很可能在空转")

        for (path, exemption) in all {
            XCTAssertGreaterThanOrEqual(
                exemption.reason.count, SourceGuard.minimumExemptionReasonLength,
                "\(path) 第 \(exemption.line) 行的豁免理由太短：「\(exemption.reason)」。"
                    + "下一步：写清为什么这一处非用字面值不可；写不出来就说明它该改成令牌。")
        }
        XCTAssertLessThanOrEqual(
            all.count, Self.exemptionCeiling,
            "全模块现在有 \(all.count) 处单行豁免，超过了记在案的 \(Self.exemptionCeiling) 处："
                + all.map { "\($0.path):\($0.exemption.line)" }.joined(separator: "、")
                + "。下一步：能改成令牌的改掉；确实改不动的，把 `exemptionCeiling` 加上去，"
                + "在复审里说清每一处的理由。")
    }
}
