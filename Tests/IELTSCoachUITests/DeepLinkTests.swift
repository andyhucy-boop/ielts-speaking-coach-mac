import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class DeepLinkTests: XCTestCase {
    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testDashboardOpensTheTodayPage() throws {
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://dashboard")), .open(.today))
    }

    func testEveryRouteLandsOnSomePage() throws {
        // 路由表在 Core、页面枚举在 UI，两边靠这条测试对齐。
        // 少映射一个，用户点开链接就会停在原地，而且没有任何提示。
        for route in CoachRoute.allCases {
            let resolution = DeepLinkResolver.resolve(route.url)
            guard case .open = resolution else {
                return XCTFail("\(route.rawValue) 没有对应的页面：\(resolution)")
            }
        }
    }

    func testRoutesMapToTheExpectedPages() throws {
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://questions")), .open(.questionBank))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://reviews")), .open(.reviewReports))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://history")), .open(.history))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://vocabulary")), .open(.vocabulary))
    }

    /// **计划里那四条只钉了九条路由中的四条**（questions / reviews / history / vocabulary），
    /// 剩下的 today / plan / retraining / issues 没有任何一条测试管得着：
    /// 把 `issues` 映射到「我的词汇」，上面 `testEveryRouteLandsOnSomePage` 照样绿
    /// （它只问「有没有落点」），下面 `testUnimplementedPagesStillOpen…` 也照样绿
    /// （它拿的是同一份 `SidebarItem(route:)` 去比，是同义反复）。
    /// 而映射错了的后果，是用户从 Codex 点「打开问题档案」跳到了词汇本——
    /// 页面正常渲染，看不出哪里不对，只是走错了门。
    ///
    /// 所以这里把九条逐条钉死，并当场确认这张表覆盖了 `CoachRoute` 的每一个 case：
    /// 将来 Core 加了新路由而这张表忘了补，这条测试会红，而不是安静地少守一条。
    func testEveryRouteIsPinnedToOneSpecificPage() throws {
        let expected: [CoachRoute: SidebarItem] = [
            .dashboard: .today,
            .today: .today,
            .questions: .questionBank,
            .plan: .plan,
            .retraining: .retraining,
            .reviews: .reviewReports,
            .history: .history,
            .issues: .issues,
            .vocabulary: .vocabulary
        ]
        XCTAssertEqual(Set(expected.keys), Set(CoachRoute.allCases),
                       "这张对照表和 CoachRoute 的 case 对不上，有路由没人钉。"
                           + "下一步：把新加的路由补进表里，并想清楚它该落在哪一页。")
        for (route, page) in expected {
            XCTAssertEqual(DeepLinkResolver.resolve(route.url), .open(page),
                           "\(route.rawValue) 应当打开「\(page.title)」")
        }
    }

    func testUnknownPageIsRejectedWithAnActionableChineseMessage() throws {
        guard case .rejected(let message) = DeepLinkResolver.resolve(try url("ieltscoach://nope")) else {
            return XCTFail("不认识的页面必须被拒绝，而不是默默跳到首页")
        }
        XCTAssertTrue(message.contains("nope"))
        XCTAssertTrue(message.contains("dashboard"), "要把可用的页面名列出来")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testOtherSchemesAreRejected() throws {
        guard case .rejected(let message) = DeepLinkResolver.resolve(try url("https://history")) else {
            return XCTFail("只认 ieltscoach:// —— 别的 scheme 一律拒绝")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testUnimplementedPagesStillOpenBecauseThePlaceholderExplainsItself() throws {
        // 还没做完的页面也要能跳过去：看到的是占位页，而占位页写明了
        // 「还没做、将来会有什么」——这比点了链接毫无反应强得多。
        //
        // ⚠️ 2026-08-06 跨阶段复审：初稿这里写的是
        //     XCTAssertFalse(SidebarItem.history.isImplemented)
        // 那条断言在 Phase 4（训练记录页）交付之后必然变红，而且红得毫无道理——
        // 它其实是在断言「某个页面还没做」，那不是深链接该管的事。
        // 现在改成断言真正要保证的东西：**没做完的页面也解析得出来，不会被拒绝。**
        for route in CoachRoute.allCases {
            let item = SidebarItem(route: route)
            XCTAssertEqual(DeepLinkResolver.resolve(route.url), .open(item),
                           "\(route.rawValue) 无论做没做完都必须能跳过去")
        }
    }
}
