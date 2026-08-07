import AppKit
import Foundation
import XCTest

@testable import IELTSCoachUI

/// 「功能升级」页。
///
/// ## 为什么这一页要单独有一组测试
///
/// 计划 Task 17 的 Step 4 只给了一张验收表（「必须做到 / 判据」），没有测试步骤，
/// 而 `ChangelogTests` 守的全是**数据层**：表里有几条记录、有没有空话。
/// 本项目已经实测过五次「算好了却一个像素都不上屏，全套测试照样绿」，
/// 关于页那一组（`AboutViewTests`）就是为同一个原因补的。
///
/// 所以这里分两类：
///
/// 一、**真跑起来的断言**：版本对不上时那句提示、默认展开哪一条、三种状态的颜色。
///    这几件事都被抽成了纯函数/纯属性，改成空实现当场变红。
/// 二、**扫源码**：`swift test` 不画界面，所以退一步问「这段渲染还在不在渲染树里」。
///    拦得住整段被删、接线被换掉；拦不住排版好不好看——那部分归 Task 19 的人工验收。
@MainActor
final class UpgradeViewTests: XCTestCase {

    private static let view = "Upgrade/UpgradeView.swift"
    private static let data = "Upgrade/Changelog.swift"

    /// `UpgradeView` 那个 `body` 的大括号内容。
    private func upgradeViewBody() throws -> String {
        let type = try SourceGuard.memberBody(of: "public struct UpgradeView",
                                              in: try SourceGuard.code(Self.view))
        return try SourceGuard.memberBody(of: "public var body", in: type)
    }

    // MARK: - 一、顶上那行版本：来自 AppMetadata，永远不许写死

    /// 写死的版本号在每一次发版之后都是错的，而且错得毫无迹象——
    /// 而这一页存在的全部意义就是回答「我手上这份到底是哪一版」。
    func testTheHeaderSaysWhichBuildYouAreRunningAndNeverHardCodesIt() throws {
        let code = try SourceGuard.code(Self.view)
        let header = try SourceGuard.memberBody(of: "private var header", in: code)

        XCTAssertTrue(header.contains("metadata.versionLine"),
                      "顶上那行版本不再取自 `AppMetadata.versionLine` 了：\(header.flattened)")
        for piece in ["metadata.buildDate", "metadata.buildCommit"] {
            XCTAssertTrue(header.contains(piece),
                          "顶上少了 `\(piece)`。验收表要求版本旁边还有一行构建时间与提交号——"
                              + "没有它，两份同样标着 1.0.0 的 App 就分不出谁是谁。")
        }
        for version in Changelog.releases.map(\.version) {
            XCTAssertFalse(code.contains(version),
                           "这一页里写死了版本号「\(version)」。下一版发出去它就是错的，"
                               + "而且不会有任何迹象。下一步：一律走 `AppMetadata`。")
        }
        XCTAssertTrue(try upgradeViewBody().contains("header"),
                      "`header` 只是声明着，没有被摆进 `UpgradeView.body`，一个像素都不会上屏。")
    }

    // MARK: - 二、版本对不上时那句提示

    /// **开发运行时这一页不能显得像坏了。**
    ///
    /// `swift run IELTSCoachApp` 没有 App bundle，`AppMetadata` 每个字段都是
    /// 「未知（开发运行）」。这时顶上写着「未知（开发运行）」、下面的更新记录写着 1.0.0，
    /// 不加解释就是一页自相矛盾的界面。
    func testADevelopmentBuildGetsAnExplanationInsteadOfLookingBroken() throws {
        let notice = try XCTUnwrap(
            Changelog.versionNotice(runningShortVersion: AppMetadata.unknownValue),
            "从源码直接跑时，顶上是「\(AppMetadata.unknownValue)」、更新记录里是"
                + "\(Changelog.current.version)，这一页却一句解释都没有——看着就像坏了。")

        XCTAssertTrue(notice.contains(AppMetadata.unknownValue),
                      "没说清「你现在跑的是什么」：\(notice)")
        XCTAssertTrue(notice.contains(Changelog.current.version),
                      "没说清「更新记录里最新的是哪一版」：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "只说了现状，没说下一步做什么（铁律 6）：\(notice)")
        XCTAssertTrue(notice.contains("build-app.sh"),
                      "没告诉用户怎么才能得到带完整版本信息的 App：\(notice)")
    }

    /// 版本对得上就不该冒出这一行。
    /// 一直挂着的提示等于没有提示——真出事那次也不会有人多看一眼。
    func testAMatchingVersionGetsNoNoticeAtAll() {
        XCTAssertNil(
            Changelog.versionNotice(runningShortVersion: Changelog.current.version),
            "版本明明对得上，页面上还挂着一行「对不上」的提示。")
    }

    /// 手上是一份真打出来的 `.app`，只是更新记录还没补上这一版。
    /// **这时不能照抄开发版本那句话**——那是一句假话，而且会让用户去跑一个他不需要跑的脚本。
    func testAVersionTheChangelogDoesNotKnowStillSaysWhatToDoNext() throws {
        let notice = try XCTUnwrap(
            Changelog.versionNotice(runningShortVersion: "9.9.9"),
            "顶上写着 9.9.9、更新记录里最新的是 \(Changelog.current.version)，却一声不吭。")

        XCTAssertTrue(notice.contains("9.9.9"), "没说清用户手上这份是哪一版：\(notice)")
        XCTAssertTrue(notice.contains(Changelog.current.version),
                      "没说清更新记录停在哪一版：\(notice)")
        XCTAssertTrue(notice.contains("下一步"), "没说下一步做什么（铁律 6）：\(notice)")
        XCTAssertFalse(notice.contains("开发版本"),
                       "这是一份真打出来的 App，却被说成「从源码直接运行的开发版本」——"
                           + "照着这句话去跑打包脚本只会白忙一场：\(notice)")
    }

    /// 那句提示得真的画在页面上。模型层算得对不等于用户看得见（本项目已实测过五次）。
    func testTheVersionNoticeIsActuallyPainted() throws {
        let code = try SourceGuard.code(Self.view)
        let line = try SourceGuard.memberBody(of: "private var versionNoticeLine", in: code)

        XCTAssertTrue(line.contains("Changelog.versionNotice"),
                      "这一行不再问 `Changelog.versionNotice` 了：\(line.flattened)")
        XCTAssertTrue(line.contains("metadata.shortVersion"),
                      "问的不是用户此刻真正跑着的那个版本号：\(line.flattened)")
        XCTAssertTrue(try upgradeViewBody().contains("versionNoticeLine"),
                      "`versionNoticeLine` 没有被摆进 `UpgradeView.body`——"
                          + "开发运行时这一页会显示一个自相矛盾的版本号，而一句解释都没有。")
    }

    // MARK: - 三、更新记录

    func testEveryReleaseIsPaintedWithItsVersionDateHeadlineAndChanges() throws {
        let code = try SourceGuard.code(Self.view)
        let card = try SourceGuard.memberBody(of: "private func releaseCard", in: code)

        for piece in ["release.version", "release.date", "release.headline", "release.changes"] {
            XCTAssertTrue(card.contains(piece),
                          "更新记录里不画 `\(piece)` 了。`Changelog` 把内容写全了却不上屏，"
                              + "等于静默失败（铁律 7），而且不会有任何编译错误。")
        }

        let section = try SourceGuard.memberBody(of: "private var releasesSection", in: code)
        XCTAssertTrue(section.contains("Changelog.releases"),
                      "这一页不再遍历 `Changelog.releases` 了，画出来的将是一张固定的死表。")
        XCTAssertTrue(try upgradeViewBody().contains("releasesSection"),
                      "`releasesSection` 没有被摆进 `UpgradeView.body`，更新记录一个字都不上屏。")
    }

    /// 验收表：**最新一版默认展开。**
    ///
    /// 全都收起来的话，用户点进这一页只看得到一行版本号——那正是它作为占位页时的样子。
    func testOnlyTheNewestReleaseIsExpandedByDefault() throws {
        let newer = ReleaseNote(version: "2.0.0", date: "2026-09-01",
                                headline: "新的那一版", changes: ["改了一件事"])
        let older = ReleaseNote(version: "1.0.0", date: "2026-08-06",
                                headline: "旧的那一版", changes: ["改了另一件事"])

        XCTAssertEqual(Changelog.defaultExpandedVersions(of: [newer, older]), ["2.0.0"],
                       "默认展开的不是最新那一条。全收起来 = 用户点进来什么都看不到；"
                           + "全展开 = 一页翻不完的历史，最新那一条反而找不着。")
        XCTAssertEqual(Changelog.defaultExpandedVersions(of: []), [],
                       "一条记录都没有时，凭空展开了一个不存在的版本")

        let code = try SourceGuard.code(Self.view)
        XCTAssertTrue(code.contains("Changelog.defaultExpandedVersions"),
                      "这一页没有用 `defaultExpandedVersions` 定初始展开状态——"
                          + "那条规则算得再对也没接上界面。")
        let card = try SourceGuard.memberBody(of: "private func releaseCard", in: code)
        XCTAssertTrue(card.contains("isExpanded"),
                      "更新记录不再是可展开的了，「最新一版默认展开」这条验收无从谈起：\(card.flattened)")
    }

    // MARK: - 四、十个阶段

    func testTheTenPhasesArePaintedWithWhatTheyGaveYouAndWhereTheyStand() throws {
        let code = try SourceGuard.code(Self.view)
        let row = try SourceGuard.memberBody(of: "private func phaseRow", in: code)

        for piece in ["phase.label", "phase.title", "phase.summary", "phase.status.title"] {
            XCTAssertTrue(row.contains(piece),
                          "阶段那一栏里不画 `\(piece)` 了。少了 `summary` 就只剩一串阶段名，"
                              + "对用户等于没写；少了 `status.title` 则看不出走到哪儿了。")
        }

        let section = try SourceGuard.memberBody(of: "private var phasesSection", in: code)
        XCTAssertTrue(section.contains("Changelog.phases"),
                      "这一页不再遍历 `Changelog.phases` 了：\(section.flattened)")
        XCTAssertTrue(try upgradeViewBody().contains("phasesSection"),
                      "`phasesSection` 没有被摆进 `UpgradeView.body`，十个阶段一个都不上屏。")
    }

    /// 三种状态各有各的颜色，且都来自 `Palette`。
    ///
    /// 验收表点名了这三个令牌。三种状态共用一个颜色的话，那一列就只是重复了一遍文字；
    /// 而在视图里随手调一个灰，深色下就是一行看不见的字（Task 12 的教训）。
    func testEachPhaseStatusGetsItsOwnTokenColour() {
        XCTAssertEqual(PhaseStatus.shipped.tint, Palette.success, "已完成不再用 `Palette.success`")
        XCTAssertEqual(PhaseStatus.inProgress.tint, Palette.accent, "进行中不再用 `Palette.accent`")
        XCTAssertEqual(PhaseStatus.planned.tint, Palette.textSecondary,
                       "还没开始不再用 `Palette.textSecondary`")

        let tints = [PhaseStatus.shipped.tint,
                     PhaseStatus.inProgress.tint,
                     PhaseStatus.planned.tint]
        XCTAssertEqual(Set(tints.map { String(describing: $0) }).count, 3,
                       "三种状态用了同一个颜色，那一列等于白画")
    }

    /// 状态图标只用 SF Symbols（规范第 4 节明禁 emoji），而且名字得是系统认识的——
    /// 打错一个字母不会报错，只会渲染成空白。
    func testEveryStatusIconIsARealSFSymbol() {
        for status in [PhaseStatus.shipped, .inProgress, .planned] {
            XCTAssertFalse(status.symbol.isEmpty, "\(status) 没有图标")
            XCTAssertNotNil(
                NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil),
                "系统不认识 SF Symbol「\(status.symbol)」（\(status.title)），这一项会显示成空白")
        }
    }

    // MARK: - 五、接线：侧边栏点得进来

    /// `isImplemented` 标了 `.upgrade`，`RootView` 却没接上视图的话，
    /// 用户点进来看到的还是那句「「功能升级」还没做」——而 `NavigationTests`
    /// 那条确切集合断言只看得到前半截。
    func testTheSidebarActuallyOpensThisPage() throws {
        XCTAssertTrue(SidebarItem.upgrade.isImplemented,
                      "「功能升级」已经做出来了，侧边栏必须点得进去")

        let branches = try SourceGuard.switchBranches(over: "current",
                                                      in: try SourceGuard.code("RootView.swift"))
        let branch = try XCTUnwrap(
            branches.first { $0.cases.contains("upgrade") },
            "`RootView` 的 detail switch 里没有 `.upgrade` 这一支，它会掉进 `default` 的占位页——"
                + "而侧边栏已经把这一项标成做好了。扫到的分支是："
                + branches.map(\.label).joined(separator: "、"))
        XCTAssertTrue(branch.body.contains("UpgradeView("),
                      "`.upgrade` 那一支画的不是 `UpgradeView`：\(branch.body.flattened)")
    }

    // MARK: - 六、这一页自己不许承诺未来功能，样式全部走令牌

    /// 数据层由 `ChangelogTests.testNoEmptyPromises` 守着，视图里也不许自己加一句。
    func testThePageMakesNoPromisesOfItsOwn() throws {
        for path in [Self.view, Self.data] {
            let raw = try SourceGuard.read(path)
            for word in ["即将", "敬请期待", "稍后补充", "待定"] {
                XCTAssertFalse(raw.contains(word),
                               "\(path) 里出现了「\(word)」。一个自用工具的更新记录写这种话没有任何"
                                   + "信息量，而且它会一直留在那儿——因为没人记得回来删。")
            }
        }
    }

    func testTheUpgradePageUsesSFSymbolsAndNoEmojiAndTakesEveryStyleFromTheTokens() throws {
        let raw = try SourceGuard.read(Self.view)
        XCTAssertGreaterThan(SourceGuard.occurrences(of: "Image(systemName:", in: raw)
                                + SourceGuard.occurrences(of: "systemImage:", in: raw), 0,
                             "这一页一个 SF Symbol 都没有，多半是图标被换成了别的东西")

        for path in [Self.view, Self.data] {
            let source = try SourceGuard.read(path)
            let emoji = source.unicodeScalars.filter { scalar in
                (0x1F300...0x1FAFF).contains(scalar.value) || (0x2600...0x27BF).contains(scalar.value)
            }
            XCTAssertTrue(emoji.isEmpty,
                          "\(path) 里出现了 emoji（\(String(String.UnicodeScalarView(emoji)))）。"
                              + "下一步：换成 SF Symbols（`Image(systemName:)`）。")
        }

        // 全模块那一趟（`DesignTokenContractTests`）也扫得到这一页，
        // 这里再点名一次，是为了这一页红的时候报错直接指到它。
        SourceGuard.assertUsesDesignTokens(in: Self.view)
    }
}

private extension String {
    /// 报错里贴原文用：压成一行，太长就截断——报错本身不该刷屏。
    var flattened: String {
        let flat = split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= 120 ? flat : String(flat.prefix(120)) + "…"
    }
}
