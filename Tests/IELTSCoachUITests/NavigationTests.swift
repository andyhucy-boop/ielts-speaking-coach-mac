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
        // Phase 4 把「训练记录」加了进来，Phase 6 把「复训中心」加了进来，
        // Phase 7 Task 6 把「问题档案」加了进来，Task 7 把「我的词汇」加了进来，
        // Phase 8 Task 9 把「学习计划」加了进来，Phase 10 Task 17 把「功能升级」加了进来，
        // Task 18 把「问题反馈」加了进来——十项到此全齐。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertEqual(Set(implemented),
                       [.today, .questionBank, .reviewReports, .history, .retraining, .issues,
                        .vocabulary, .plan, .upgrade, .feedback])
    }

    /// 同上，钉住「问题反馈」这一页（Phase 10 Task 18）。
    func testFeedbackPageIsUnlocked() {
        XCTAssertTrue(SidebarItem.feedback.isImplemented, "问题反馈页已实现，必须在侧边栏可点")
    }

    func testEverySidebarItemIsImplementedByTheEndOfPhase10() {
        // Phase 3 起，未实现的页面显示占位。Phase 10 Task 17 / 18 之后，
        // 十项应当全部有内容——PlaceholderView 就此变成死代码。
        let missing = SidebarItem.allCases.filter { !$0.isImplemented }
        XCTAssertTrue(missing.isEmpty,
                      "这几项还是占位：\(missing.map(\.title))。"
                      + "若它们属于前面某个阶段（训练记录归 Phase 4、复训中心归 Phase 6、"
                      + "问题档案与我的词汇归 Phase 7、学习计划归 Phase 8），"
                      + "**不要改这条测试**——去把那个阶段补上，或者停下来报告。")
    }

    /// 问题档案页已经做出来了，侧边栏必须点得进去。
    ///
    /// 上面那条断言的是整个集合，看报错只知道「集合不一样」；这一条把这一页单独钉住，
    /// 谁不小心把它从 `isImplemented` 里划掉，报错会直接说是哪一页。
    func testIssueArchivePageIsUnlocked() {
        XCTAssertTrue(SidebarItem.issues.isImplemented, "问题档案页已实现，必须在侧边栏可点")
    }

    /// 同上，钉住「我的词汇」这一页。
    func testVocabularyPageIsUnlocked() {
        XCTAssertTrue(SidebarItem.vocabulary.isImplemented, "我的词汇页已实现，必须在侧边栏可点")
    }

    /// 同上，钉住「学习计划」这一页（Phase 8 Task 9）。
    func testPlanPageIsUnlocked() {
        XCTAssertTrue(SidebarItem.plan.isImplemented, "学习计划页已实现，必须在侧边栏可点")
    }

    /// 同上，钉住「功能升级」这一页（Phase 10 Task 17）。
    func testUpgradePageIsUnlocked() {
        XCTAssertTrue(SidebarItem.upgrade.isImplemented, "功能升级页已实现，必须在侧边栏可点")
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

    // 占位页那三条测试（「还没做的页面要说清将来会有什么 / 现在能干什么 / 给一颗按钮」
    // 与「已实现的页面不该冒出劝人走开的按钮」）在 Phase 10 Task 18 里删掉了。
    //
    // **不是放宽断言，是被测的东西没有了**：十项全部实现之后
    // `SidebarItem.allCases.filter { !$0.isImplemented }` 恒为空，那三条会退化成
    // 空循环——本项目已经消灭过 15 处这种「对任何实现都亮绿灯」的测试，不该再添三处。
    // `PlaceholderView` 与 `SidebarItem.placeholder*` 三个属性也一并删了。
    //
    // 顶上那条 `testEverySidebarItemIsImplementedByTheEndOfPhase10` 是它们的替代品：
    // 谁把某一页标回「还没做」，那条会直接点名是哪一页；而
    // `RootView.detail` 那个穷尽的 `switch` 让「加了一页却没给内容」变成编译错误。

    // MARK: - 根视图什么时候挡、什么时候放行

    func testChecksEnvironmentBeforeAccusingTheUserOfAnything() {
        // 环境检查还没跑完时，permission 只能是初始的 .unknown。此时若直接按 .unknown
        // 渲染，用户开机第一眼看到的是「环境检查没通过」——一句还没查就下的结论。
        //
        // **已经走过引导的老用户身上这条最要命**：`.unknown` 会算出 `[.environment]`，
        // 于是每次开机的头十秒，屏幕上都是「让它能替你操作 ChatGPT」——
        // 而查完多半一切正常。Phase 10 Task 8 的计划片段漏了这一条。
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: true, permission: .unknown,
                              questionCount: 217, hasCompletedOnboarding: true,
                              onboardingDismissed: false),
            .checkingEnvironment)
    }

    func testBlocksWithTheOnboardingWhenSomethingIsMissing() {
        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            XCTAssertEqual(
                RootRouter.screen(isCheckingPermission: false, permission: state,
                                  questionCount: 217, hasCompletedOnboarding: true,
                                  onboardingDismissed: false),
                .onboarding,
                "\(state) 时不该直接放进主界面——练习点了会失败且没有线索")
        }
    }

    func testGoesToTheWorkspaceWhenEverythingIsReady() {
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: false, permission: .ready,
                              questionCount: 217, hasCompletedOnboarding: true,
                              onboardingDismissed: false),
            .workspace)
    }

    /// 全新安装的人，就算环境一切就绪也要先走一遍引导。
    ///
    /// 少了这一条，「引导」就退化成了从前那道只在环境不就绪时才出现的授权页——
    /// 而环境本来就绪的用户会一头栽进一个空题库的主界面，既没人告诉他题库要自己导，
    /// 也没人问过他要不要录音。
    func testAFreshInstallStillWalksThroughTheOnboardingEvenWhenEverythingIsReady() {
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: false, permission: .ready,
                              questionCount: 217, hasCompletedOnboarding: false,
                              onboardingDismissed: false),
            .onboarding)
    }

    func testFinishingOrSkippingTheOnboardingLetsTheUserIn() {
        // spec 第 7 节规定授权可跳过。收工之后就不能再把他挡在外面，
        // 包括「又开始检查了」这种理由——那等于走完了引导却没进去。
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: false, permission: .needsAccessibility,
                              questionCount: 217, hasCompletedOnboarding: true,
                              onboardingDismissed: true),
            .workspace)
        XCTAssertEqual(
            RootRouter.screen(isCheckingPermission: true, permission: .needsChatGPT,
                              questionCount: 0, hasCompletedOnboarding: false,
                              onboardingDismissed: true),
            .workspace)
    }

    // MARK: - 从「训练记录」带过来的那一场复盘，用户自己切页之后就得作废

    /// **这条是复审 BI-3 的判据。**
    ///
    /// `RootView.requestedReviewSessionID` 原来只写不清：用户从「训练记录」点过一次
    /// 「看这次的复盘」之后，它就永远停在那一场。而复盘页里「用户自己点的那一次」
    /// 是 `@State`，detail 那个 `switch` 换过分支再换回来时会重新初始化成 nil——
    /// 于是此后**每一次**从侧边栏点「复盘报告」，落到的都是那一场旧的，
    /// 而不是那个属性自己承诺的「没点过时落回最近的那一次」。
    /// 用户练完新的一场、点进复盘报告，看到的是几天前那一场：
    /// 内容看着完全正常，但是别人家的——比一片空白更难被发现。
    func testNavigatingOnYourOwnDropsTheSessionCarriedOverFromTheHistoryPage() {
        XCTAssertNil(
            RootRouter.carriedReviewSession("2026-08-01-003",
                                            navigatingFrom: .reviewReports, to: .today),
            "用户自己离开了复盘页，带过来的那一场还留着。下次他再点进复盘报告，"
                + "看到的仍是几天前那一场。")
        XCTAssertNil(
            RootRouter.carriedReviewSession("2026-08-01-003",
                                            navigatingFrom: .today, to: .reviewReports),
            "用户是自己从侧边栏点进「复盘报告」的，这一次要看的是最近那一场，"
                + "不是上回从训练记录跳过去的那一场。")
    }

    /// 反过来也要守住：**切页之外的写回不许清。**
    ///
    /// `RootView` 里那句 `selection = .reviewReports` 是跳转本身，SwiftUI 的
    /// `List(selection:)` 有可能把同一个值再从绑定写回来一次。那一下不是用户切页，
    /// 清掉的话跳过去看到的还是最近那一场——正好把要修的毛病换了个方向再犯一遍。
    func testTheCarriedSessionSurvivesTheListWritingTheSamePageBack() {
        XCTAssertEqual(
            RootRouter.carriedReviewSession("2026-08-01-003",
                                            navigatingFrom: .reviewReports, to: .reviewReports),
            "2026-08-01-003",
            "页面根本没换（同一个值被写回来一次）却把带过来的那一场清掉了，"
                + "用户点「看这次的复盘」跳过去，看到的还是最近那一场。")
    }
}
