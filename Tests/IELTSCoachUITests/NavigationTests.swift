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

    func testPhase3ImplementsExactlyThreePages() {
        // 本阶段只做今日训练、训练题库、复盘报告三页，其余显示占位。
        // 断言数量而非只断言「至少三个」—— 多标了会让用户点进空页面。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertEqual(Set(implemented), [.today, .questionBank, .reviewReports])
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

    /// 未实现的七页必须说清「还没做」和「将来会有什么」。
    /// 空白页会让用户以为程序坏了——这条与错误信息的标准是同一条（成品标准第 8 条）。
    func testEveryUnimplementedPageSaysWhatWillBeThere() {
        let unimplemented = SidebarItem.allCases.filter { !$0.isImplemented }
        XCTAssertEqual(unimplemented.count, 7)
        for item in unimplemented {
            XCTAssertFalse(item.placeholderDescription.isEmpty,
                           "「\(item.title)」的占位页会是一片空白，用户会以为程序坏了")
            XCTAssertTrue(item.placeholderDescription.contains("将来"),
                          "「\(item.title)」的占位文案没说清将来会有什么："
                          + item.placeholderDescription)
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
