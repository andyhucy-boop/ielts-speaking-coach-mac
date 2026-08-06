import Foundation
import XCTest

@testable import IELTSCoachUI

/// 铁律 6（界面走设计令牌，视图里不得出现字面颜色、字号、圆角）的**全模块**守卫。
///
/// 之前只有 `DesignSystemTests` 扫 `DesignSystem/` 一个目录，而且只认「点开头」的 `font(.`。
/// 已实测的两个后果：
///
/// - 把 `Components.swift` 的 `.foregroundStyle(Palette.textSecondary)` 换成一个字面灰色 → 全绿；
/// - 把 `.font(Typography.label)` 换成 `.font(Font.caption)` → 全绿（换个拼法就绕过去了）。
///
/// 现在改成扫整个 `Sources/IELTSCoachUI/`，四类字面值（字体、颜色、圆角/描边、间距）
/// 各自认全同义写法，规则本身由 `SourceGuardTests` 逐条自测。
///
/// **边界**：扫源码不执行代码，管不了「写对了令牌但摆错了位置」，也不管好不好看——
/// 那部分归人工验收。它管的是「这一处样式还归不归设计系统管」。
final class DesignTokenSweepTests: XCTestCase {

    /// 令牌的定义处。字面取值**只允许**出现在这三个文件里——它们就是那张表本身，
    /// 而表里的取值由 `DesignSystemTests` 逐行钉住。
    static let tokenDefinitions = [
        "DesignSystem/Typography.swift",
        "DesignSystem/Palette.swift",
        "DesignSystem/Metrics.swift"
    ]

    /// Task 7 之前的两张占位页，**还没收编进设计系统**。
    ///
    /// 它们用的是系统语义字体加系统语义颜色（`.font(.title3)`、`.foregroundStyle(.secondary)`），
    /// 这是当时刻意的选择，不是遗漏。列在这里是把「还没做」写明白，
    /// 而不是把断言放宽（铁律 8）——下面 `testTheExemptionListCannotQuietlyRot`
    /// 盯着这份名单：哪天这两页改成走令牌了，那条测试会当场变红，逼人把它从名单里划掉。
    ///
    /// **往这份名单里加文件是一次显式的、要过复审的动作。** 不许拿它来消红。
    static let notYetMigrated = [
        "RootView.swift",
        "Onboarding/PermissionGateView.swift"
    ]

    /// 扫全模块。收编过的每一个界面文件，四类字面样式一处都不许有。
    func testEveryMigratedViewTakesItsStyleFromDesignTokens() throws {
        let exempt = Set(Self.tokenDefinitions + Self.notYetMigrated)
        var scanned = 0
        for file in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: file)
            guard !exempt.contains(path) else { continue }
            scanned += 1
            SourceGuard.assertUsesDesignTokens(in: path)
        }
        // 防空转：目录挪了、过滤条件写反了，上面那圈一个文件都没扫也是全绿。
        XCTAssertGreaterThanOrEqual(
            scanned, 8,
            "只扫到 \(scanned) 个界面文件，这条测试很可能在空转。"
                + "下一步：确认 \(SourceGuard.uiSourceRelativeRoot) 还在，且豁免名单没有失控地变长。")
    }

    /// 上一条只说「没有字面值」，那**把所有样式修饰符统统删光也是零违规**——
    /// 一处字面值都没有，界面却整片退回 SwiftUI 的默认字体和默认前景色。
    /// 「写好的东西没被用上」正是本项目反复栽跟头的那一类，不能只守一半。
    ///
    /// 所以反过来数一遍：**每个自己画 body 的视图，字体和颜色都得真的从令牌取。**
    /// 门槛取「至少一处」——正常重构（把一段文字挪进子组件）碰不到，
    /// 整个文件的样式被删光才会碰到。
    func testEveryViewActuallyReachesForTheTokens() throws {
        let exempt = Set(Self.tokenDefinitions + Self.notYetMigrated)
        var checked: [String] = []
        for file in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: file)
            guard !exempt.contains(path) else { continue }
            let code = try SourceGuard.code(path)
            guard code.contains("var body") else { continue }   // 只看真的画界面的文件
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

    /// **这条是上一条的牙齿。**
    ///
    /// 上一条只断言「没扫到违规」。把 `SourceGuard` 里的正则全改成匹配不到的东西，
    /// 它照样全绿——守门员被掏空了，比分牌还显示 0 失球。
    ///
    /// 所以这里反过来断言：那两张还没收编的占位页里，扫描器**必须**真的挑得出违规，
    /// 而且四类规则里的字体和颜色都得挑得出来（那两页确实两样都有）。
    /// 扫描器一旦被弱化，这条当场变红。
    func testTheScannerStillHasTeethOnRealSourceFiles() throws {
        for path in Self.notYetMigrated {
            let found = try SourceGuard.designTokenViolations(inFileAt: path)
            XCTAssertFalse(
                found.isEmpty,
                "\(path) 里一处违规都没扫到。两种可能：这一页已经改成走令牌了"
                    + "（那就把它从 notYetMigrated 里划掉），或者扫描规则被弱化了"
                    + "（那全模块那条扫描已经是空转）。下一步：两种都得看一眼。")
            let rules = Set(found.map(\.rule))
            XCTAssertTrue(rules.contains(where: { $0.contains("字体") }),
                          "\(path) 里没扫到字体类违规，字体规则可能已经失效：\(rules)")
            XCTAssertTrue(rules.contains(where: { $0.contains("色") }),
                          "\(path) 里没扫到颜色类违规，颜色规则可能已经失效：\(rules)")
        }
    }

    /// **这份「还没做」的名单只能变短，不能变长。**
    ///
    /// 上一条只问「这两页里还挑不挑得出违规」，那它们再烂十倍也是绿的。
    /// 而整个文件被豁免还有个副作用：这两页往后新写的每一行也一并不受管——
    /// 于是「还没收编」会悄悄变成「越欠越多」。
    ///
    /// 所以给每一页记一个上限：**只许降，不许升**。真要收编就把数字改小，
    /// 收编完就把它从 `notYetMigrated` 里划掉（那时上面那条会红，逼你动手）。
    ///
    /// 数字是**今天的实测值**，不留余量。留余量等于把那几个名额提前送人。
    static let literalCeiling = [
        "RootView.swift": 17,
        "Onboarding/PermissionGateView.swift": 16
    ]

    func testTheUnmigratedPagesCannotGetAnyWorse() throws {
        XCTAssertEqual(Set(Self.literalCeiling.keys), Set(Self.notYetMigrated),
                       "上限表和豁免名单对不上，有页面落在两边之外")
        for (path, ceiling) in Self.literalCeiling {
            let found = try SourceGuard.designTokenViolations(inFileAt: path)
            XCTAssertLessThanOrEqual(
                found.count, ceiling,
                "\(path) 的字面样式从 \(ceiling) 处涨到了 \(found.count) 处。"
                    + "这一页整体豁免着，新写的样式也跟着不受管，欠账只会越滚越大。"
                    + "下一步：新加的这几处改成走令牌；确实收编不动的话，"
                    + "在复审里说清理由再调这个数字。")
        }
    }

    /// 令牌定义文件必须真的在，而且真的在定义令牌。
    ///
    /// 它们是唯一被允许写字面取值的地方，名单一旦指错文件，整条豁免就变成一个洞。
    func testTokenDefinitionFilesAreTheOnlyPlaceLiteralValuesLive() throws {
        for (path, marker) in zip(Self.tokenDefinitions,
                                  ["public enum Typography", "public enum Palette",
                                   "public enum Spacing"]) {
            let code = try SourceGuard.code(path)
            XCTAssertTrue(
                code.contains(marker),
                "\(path) 里没有「\(marker)」。豁免名单指着一个不再定义令牌的文件，"
                    + "等于在扫描上开了个洞。下一步：确认令牌是不是搬了家，名单要跟着改。")
        }
    }

    // MARK: - 逐行豁免

    /// 单行豁免（`// 设计令牌豁免：<理由>`）是留给「确有正当理由用字面值」那一处的口子。
    /// 口子一开就得有人数着，否则它会从「一处特例」长成「哪儿红就往哪儿贴」。
    ///
    /// **现在全模块是 0 处。** 要新增就得同时改这个数字——那是一次显式的、
    /// 会被复审看见的动作，而不是随手加一行注释就把守卫关掉。
    static let exemptionCeiling = 0

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
