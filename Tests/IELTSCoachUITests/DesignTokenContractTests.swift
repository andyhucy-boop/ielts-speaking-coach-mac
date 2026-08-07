import Foundation
import XCTest

@testable import IELTSCoachUI

/// 守「视图里不得出现字面颜色、字面字号、字面圆角」——Phase 3 就写进 Global Constraints、
/// 一直只靠人看的那一条（Phase 10 Task 13）。
///
/// ## 为什么现在才较真
///
/// 深色模式（Task 12）把它从风格问题变成了功能问题：一个写死的
/// `Color(red: 0.07, green: 0.07, blue: 0.09)` 在浅色下是漂亮的深灰正文，
/// 在深色下是**一行看不见的字**；而写它的人用浅色开发，永远不会撞上。
/// `.foregroundStyle(.secondary)` 也一样不行——它确实跟随外观，但取值不在
/// `AppearanceContrastTests` 那张矩阵里，没有任何人验证过它压在
/// `Palette.canvas` / `Palette.card` 这两套底色上够不够 4.5:1。
/// 「所有颜色必须走令牌」的意义正是「每一个都被验过」。
///
/// ## 与 `DesignTokenSweepTests` 的分工
///
/// 扫描规则本身在 `SourceGuard`（认同义写法，逐条由 `SourceGuardTests` 自测），
/// 两边共用同一份实现，**不各写一套**。
///
/// - 这一份问的是**否定**的那一半：全模块除三个令牌定义文件外，一处字面样式都不许有，
///   而且**没有整文件豁免这个口子**。Task 13 之前是有的（`notYetMigrated` 挂着
///   `RootView.swift` 与 `PermissionGateView.swift` 两页），那两页因此连新写的行也不受管。
/// - `DesignTokenSweepTests` 问的是**肯定**的那一半（每个视图真的从令牌取过字体和颜色）
///   与逐行豁免的账。
///
/// ## 它拦不住什么
///
/// 扫源码不执行代码。令牌挑错了档（该 `sectionTitle` 写成了 `label`）拦不住，
/// 排版好不好看也拦不住——那部分归 Task 13 Step 5 的人工验收。
final class DesignTokenContractTests: XCTestCase {

    /// 唯一允许出现字面取值的地方：那三张表本身。
    ///
    /// **刻意复用 `DesignTokenSweepTests.tokenDefinitions` 而不是再抄一份**——
    /// 两份名单迟早会不一致，而不一致的那一天，宽的那一份说了算。
    ///
    /// 这份名单就是下面 `scannedPaths()` 的 filter，也就是**整文件豁免的口子本身**。
    /// 拦住它变长的不是这个文件里的任何一条断言，而是
    /// `DesignTokenSweepTests.testTheWholeFileExemptionListIsExactlyTheThreeTokenTables`
    /// ——那条逐字钉死了这三项。改名单必须先改那条断言。
    private var tokenDefinitions: Set<String> { Set(DesignTokenSweepTests.tokenDefinitions) }

    /// Task 13 收编的两页。它们曾经被整文件豁免，是这条契约最该盯住的两个名字。
    ///
    /// **注意这只是两个名字，不是「没有整文件豁免」的证明。** 复审实测过：
    /// 往 `tokenDefinitions` 加一行 `"Review/ReviewReportView.swift"` 再往那页插两处
    /// 写死的样式，这两个名字都还在扫描范围里、文件数也远在下限之上，于是全绿。
    /// 名单不许变长这件事由上面那条钉子管，这里只管这两页没有被重新豁免回去。
    private static let previouslyExempt = ["RootView.swift", "Onboarding/PermissionGateView.swift"]

    /// 这一趟真正扫过的文件（模块内相对路径）。
    private func scannedPaths() throws -> [String] {
        try SourceGuard.swiftFiles()
            .map { try SourceGuard.relativePath(of: $0) }
            .filter { !tokenDefinitions.contains($0) }
    }

    /// 防空转：路径写错、过滤条件写反时，下面那条禁令会一个文件都扫不到，
    /// 然后**全绿**——那是最坏的一种绿，它对任何实现都亮。
    ///
    /// 除了数个数，还点名要求那两页在扫描范围里：它们是曾经被整文件豁免的两页，
    /// 谁把这两个名字重新塞回豁免名单，这一条当场变红。
    ///
    /// **它只认这两个名字。** 换个文件名豁免它拦不住，40 这个下限也拦不住
    /// （实际扫到 58 个，还有十几个文件的余量）。「名单只能是那三张令牌表」
    /// 由 `DesignTokenSweepTests.testTheWholeFileExemptionListIsExactlyTheThreeTokenTables` 钉住。
    func testThereAreActuallyFilesToScanAndNoWholeFileEscapeHatch() throws {
        let scanned = try scannedPaths()
        XCTAssertGreaterThanOrEqual(
            scanned.count, 40,
            "只扫到 \(scanned.count) 个界面文件，这条契约很可能在空转。"
                + "下一步：确认 \(SourceGuard.uiSourceRelativeRoot) 还在，"
                + "且过滤条件没有把绝大多数文件挡在外面。")
        for path in Self.previouslyExempt {
            XCTAssertTrue(
                scanned.contains(path),
                "\(path) 不在扫描范围里。Task 13 拆掉的就是「整个文件豁免」这个口子——"
                    + "这一页曾经因此连新写的样式也不受管。"
                    + "下一步：把它放回扫描范围；确实要破例，就用逐行的"
                    + "「\(SourceGuard.exemptionMarker)」注释并写清理由，那是有人数着的。")
        }
    }

    /// 契约本体：全模块除三张表之外，四类字面样式一处都不许有。
    func testNoViewOutsideTheTokenTablesHardcodesStyle() throws {
        for path in try scannedPaths() {
            SourceGuard.assertUsesDesignTokens(in: path)
        }
    }

    /// **这条是上一条的牙齿。**
    ///
    /// 上一条只断言「没扫到违规」。把 `SourceGuard` 里的正则全改成匹配不到的东西，
    /// 它照样全绿——守门员被掏空了，比分牌还显示 0 失球。
    /// Task 13 之前这颗牙齿是靠「那两页里必须还挑得出违规」长着的，
    /// 而两页一收编，那颗牙就掉了（空数组循环 = 恒绿）。
    ///
    /// 所以改成往**一个真实的视图文件**里注入四类违规各一处，断言四类都被挑出来。
    /// 不用人造字符串：`SourceGuardTests` 已经拿人造串逐条测过规则本身，
    /// 这里要证的是「这条契约用的那条路径，在真实源码上真的会报」。
    func testTheScannerStillHasTeethOnARealViewFile() throws {
        let path = "Today/TodayView.swift"
        let pristine = try SourceGuard.read(path)
        XCTAssertEqual(
            SourceGuard.designTokenViolations(inRawSource: pristine).count, 0,
            "\(path) 本身就有违规，下面的注入实验分不清是谁报的")

        let injected = pristine + """

        // 下面四行是这条测试临时拼上去的，不在磁盘上。
        .font(.system(size: 13))
        .foregroundStyle(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(12)
        """
        let rules = Set(SourceGuard.designTokenViolations(inRawSource: injected).map(\.rule))
        for keyword in ["字体", "色", "圆角", "内边距"] {
            XCTAssertTrue(
                rules.contains(where: { $0.contains(keyword) }),
                "往真实视图里注入了「\(keyword)」类违规，扫描器却没报出来：\(rules)。"
                    + "下一步：这条契约现在是空转的——先修 `SourceGuard` 里对应的那条规则，"
                    + "再回头看全模块那条扫描是不是也一直在放水。")
        }
    }
}
