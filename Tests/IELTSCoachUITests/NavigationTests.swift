import AppKit
import XCTest
@testable import IELTSCoachUI

final class NavigationTests: XCTestCase {
    func testSidebarHasAllTenItems() {
        XCTAssertEqual(SidebarItem.allCases.count, 10)
    }

    func testEveryItemHasChineseTitleAndIcon() {
        for item in SidebarItem.allCases {
            XCTAssertFalse(item.title.isEmpty, "\(item) 缺标题")
            XCTAssertFalse(item.systemImage.isEmpty, "\(item) 缺图标")
        }
    }

    func testImplementedPagesMatchWhatIsActuallyBuilt() {
        // 断言集合相等而不是「至少包含」——多标一项会让用户点进一个空页面，
        // 而空页面会让人以为程序坏了。
        // Phase 4 把「训练记录」加了进来。后续阶段各自往里加自己的那一项，
        // 不要把别人加的删掉：Phase 6 加 .retraining，Phase 7 加 .issues 与 .vocabulary，
        // Phase 8 加 .plan，Phase 10 加 .upgrade 与 .feedback。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertEqual(Set(implemented), [.today, .questionBank, .reviewReports, .history])
    }

    func testHistoryHasAMeaningfulTitleAndIcon() {
        XCTAssertEqual(SidebarItem.history.title, "训练记录")
        XCTAssertFalse(SidebarItem.history.systemImage.isEmpty)
    }

    func testTitlesAreUnique() {
        let titles = SidebarItem.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "侧边栏有重名条目")
    }

    /// 图标名打错了不会报错，只会渲染成空白——侧边栏少一个图标，肉眼未必立刻看得出来，
    /// 而 DESIGN-SYSTEM 第 4 节要求「只用 SF Symbols」。这里当场问系统认不认这个名字。
    func testEveryIconIsARealSFSymbol() {
        for item in SidebarItem.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil),
                "系统不认识 SF Symbol「\(item.systemImage)」（\(item.title)），这一项会显示成空白")
        }
    }

    /// 还没做的那几页必须说清「还没做」「将来会有什么」和**现在该干什么**。
    /// 空白页会让用户以为程序坏了——这条与错误信息的标准是同一条（成品标准第 8 条）。
    ///
    /// 「下一步」这一句不是可选的：只说「将来会有」等于把用户扔在一页死路上。
    /// 铁律 6 把「发生了什么 + 下一步做什么」明确扩展到了空状态与界面提示。
    func testEveryUnimplementedPageSaysWhatWillBeThereAndWhatToDoNow() {
        let unimplemented = SidebarItem.allCases.filter { !$0.isImplemented }
        // Phase 4 交付「训练记录」之后从 7 降到 6。**这个数字只许降，不许升**——
        // 升上去意味着有人把一页已经做出来的又标回了「还没做」。
        XCTAssertEqual(unimplemented.count, 6)
        for item in unimplemented {
            XCTAssertFalse(item.placeholderDescription.isEmpty,
                           "「\(item.title)」的占位页会是一片空白，用户会以为程序坏了")
            XCTAssertTrue(item.placeholderDescription.contains("将来"),
                          "「\(item.title)」的占位文案没说清将来会有什么："
                          + item.placeholderDescription)
            XCTAssertTrue(item.placeholderDescription.contains("下一步"),
                          "「\(item.title)」的占位文案只说了「将来」，没说用户现在能做什么："
                          + item.placeholderDescription)
        }
    }

    /// DESIGN-SYSTEM 第 4 节「空状态（必须有，不能留白）」要三样东西：
    /// 一句现状、一句下一步、**一个能直接点的按钮**。上面那条测试守前两样，这条守第三样。
    ///
    /// 按钮的落点必须是一页**真做出来了**的页面：把用户从一个「还没做」送到另一个「还没做」，
    /// 比不给按钮更气人。
    func testEveryUnimplementedPageHasAButtonThatLeadsSomewhereThatExists() throws {
        for item in SidebarItem.allCases.filter({ !$0.isImplemented }) {
            let target = try XCTUnwrap(
                item.placeholderFallback,
                "「\(item.title)」的占位页上没有任何能点的东西，用户读完只能自己乱翻侧边栏")
            XCTAssertTrue(
                target.isImplemented,
                "「\(item.title)」的按钮把用户送到同样还没做的「\(target.title)」，等于原地打转")
            XCTAssertTrue(
                item.placeholderActionTitle.contains(target.title),
                "「\(item.title)」的按钮文字没说清点下去会到哪一页：" + item.placeholderActionTitle)
            XCTAssertTrue(
                item.placeholderDescription.contains(target.title),
                "「\(item.title)」的「下一步」那句话和按钮指的不是同一页，用户不知道该信哪个："
                    + item.placeholderDescription)
        }
    }

    /// 已经做出来的页面不该冒出一个「先去别处」的按钮——那是在告诉用户这页也没做。
    func testImplementedPagesCarryNoPlaceholderAction() {
        for item in SidebarItem.allCases.filter(\.isImplemented) {
            XCTAssertNil(item.placeholderFallback, "「\(item.title)」已经做出来了，不该再劝用户走开")
            XCTAssertTrue(item.placeholderActionTitle.isEmpty, "同上：\(item.placeholderActionTitle)")
        }
    }

    // MARK: - 根视图什么时候挡、什么时候放行

    func testChecksEnvironmentBeforeAccusingTheUserOfAnything() {
        // 环境检查还没跑完时，permission 只能是初始的 .unknown。此时若直接按 .unknown
        // 渲染，用户开机第一眼看到的是「环境检查没通过」——一句还没查就下的结论。
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: true, permission: .unknown,
                              permissionSkipped: false),
            .checkingEnvironment)
    }

    func testBlocksWithTheGateWhenSomethingIsMissing() {
        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            XCTAssertEqual(
                RootRouter.screen(isCheckingPermission: false, permission: state,
                                  permissionSkipped: false),
                .permissionGate,
                "\(state) 时不该直接放进主界面——练习点了会失败且没有线索")
        }
    }

    func testGoesToTheWorkspaceWhenEverythingIsReady() {
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: false, permission: .ready,
                              permissionSkipped: false),
            .workspace)
    }

    func testSkippingTheGateLetsTheUserIn() {
        // spec 第 7 节规定授权可跳过。跳过之后就不能再把他挡在外面，
        // 包括「又开始检查了」这种理由——那等于点了「先跳过」却没进去。
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: false, permission: .needsAccessibility,
                              permissionSkipped: true),
            .workspace)
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: true, permission: .needsChatGPT,
                              permissionSkipped: true),
            .workspace)
    }
}
