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
        // **只断言「有下一步」是空转的**（2026-08-07 复审实测）：把 `DeepLinkResolver`
        // 里那道 scheme 闸整个删掉，这条测试照样绿——因为 `CoachRoute.parse` 内部也查 scheme，
        // `https://history` 会掉进第二个 guard，而那句话同样含「下一步」。
        // 于是这条分支独有的文案完全没人守，删掉闸门后 `https://vocabulary` 还会得到一句
        // 撒谎的提示（「页面名『vocabulary』不认识」——可 vocabulary 明明是合法页面）。
        // 钉住 scheme 本身就能把两句话分开：页面名那句里不会出现 `ieltscoach://`。
        XCTAssertTrue(message.contains("\(CoachRoute.scheme)://"),
                      "拒绝别的 scheme 时必须把「本应用只认 \(CoachRoute.scheme)://」说出来。"
                          + "只说「页面名不认识」的话，用户改页面名改一整天也打不开。"
                          + "实际收到的是：\(message)")
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

    // MARK: - 接线：解析器写好了、App 不接，等于没写

    /// **这一节不在计划的 Step 1 里，是 2026-08-07 复审实测之后补的。**
    ///
    /// 实测：把 `RootView.swift` 里整个 `.onOpenURL { … }` 闭包删掉，`swift test` 1477 条全绿。
    /// 也就是说上面那七条只测了纯函数 `DeepLinkResolver.resolve`，
    /// 没有任何东西证明它被接到了 App 上——而 `open_dashboard` 恰恰死在这一段。
    /// 这正是本项目反复栽的那一类（写好了没接上），而它一行编译错误都不会有。
    ///
    /// **而且「挂在哪一层」本身就是缺陷。** `.onOpenURL` 原先挂在 `private var workspace` 上，
    /// 那是 `RootRouter.screen` 的一条分支：`AppState.isCheckingPermission` 初值是 `true`，
    /// 启动瞬间那一屏是「正在检查运行环境…」（最长约十秒），`workspace` 整个不在视图树里。
    /// App 没在跑时 Codex 调 `open_dashboard` 会先把 App 拉起来，链接正好投递在这十秒中间——
    /// `.onOpenURL` 还没注册，而它不是队列，投递时没有 handler 就丢了。
    /// 用户看到的是「窗口跳到前台、页面纹丝不动、没有任何报错」（铁律 7 禁止静默失败）。
    /// 更常驻的一条：环境检查没过时用户长期停在授权引导页，那期间每一条链接都这么无声蒸发。
    ///
    /// 所以这里钉的是**层级**，不只是「文件里出现过 `.onOpenURL` 吗」：收链接的那一段
    /// 和显示提示的那条横幅都必须挂在 `body`（三屏共用的那个容器）上，不许回到 `workspace` 里面。
    ///
    /// 边界：扫源码不执行代码，拦不住「代码还在但跑不到」；拦得住的正是已经发生过的
    /// 「整段接线被拿掉」和「接线挂错了层」。
    func testTheAppReceivesDeepLinksOnEveryScreenNotOnlyInsideTheWorkspace() throws {
        let root = try SourceGuard.code("RootView.swift")
        let bodyCode = try SourceGuard.memberBody(of: "public var body: some View", in: root)
        let workspaceCode = try SourceGuard.memberBody(of: "private var workspace", in: root)

        XCTAssertEqual(SourceGuard.occurrences(of: ".onOpenURL", in: root), 1,
                       "`RootView` 里 `.onOpenURL` 不是恰好一处。多处会互相盖掉，"
                           + "一处都没有则 `ieltscoach://` 根本没人接。"
                           + "下一步：只在 `body` 那一段挂一次。")
        XCTAssertTrue(bodyCode.contains(".onOpenURL"),
                      "`.onOpenURL` 没有挂在 `body` 这一层。挂在 `workspace` 那条分支上的话，"
                          + "启动那十秒的「正在检查运行环境…」和授权引导页期间它根本没注册，"
                          + "而 `onOpenURL` 不是队列——那时投递过来的链接直接丢了，"
                          + "用户看到窗口跳出来、页面纹丝不动、没有任何报错。"
                          + "下一步：把它挪到最外层那个容器（和 `.task` 同一层）。")
        XCTAssertFalse(workspaceCode.contains(".onOpenURL"),
                       "`.onOpenURL` 又回到了 `workspace` 里面。`workspace` 是条件渲染的分支，"
                           + "环境检查没过时整屏都不在视图树上，那期间的链接会无声蒸发。"
                           + "下一步：只留 `body` 那一处。")

        // 收到了还得真的换页 / 真的报错，两条支路都要钉——
        // 少了 `go(to:)` 那一支，链接白收；少了 `deepLinkNotice` 那一支，坏链接静默失败。
        let handler = try SourceGuard.memberBody(of: ".onOpenURL", in: root)
        XCTAssertTrue(handler.contains("DeepLinkResolver.resolve("),
                      "收下 URL 之后没有交给 `DeepLinkResolver.resolve`，"
                          + "上面那七条测的东西跟 App 没有半点关系。实际取到的是：\n\(handler)")
        XCTAssertTrue(handler.contains("go(to:"),
                      "解析成功之后没有走 `go(to:)` 换页。用户点链接窗口会跳到前台，"
                          + "停的还是原来那一页。实际取到的是：\n\(handler)")
        XCTAssertTrue(handler.contains("deepLinkNotice = message"),
                      "链接被拒绝时没有把那句中文交给横幅，等于静默失败（铁律 7）。"
                          + "实际取到的是：\n\(handler)")

        // 横幅本体有 `RenderReachabilitySweepTests` 兜着（把 `deepLinkBanner(notice)` 换成
        // `EmptyView()` 它当场报「走不到」），但它只问「从 body 走得到吗」，
        // 不问「在哪一屏能看见」。摆在 `workspace` 里的话，用户停在授权引导页时
        // 那句话永远显示不出来——handler 跑了、消息也存下了，屏幕上一个字都没有。
        XCTAssertTrue(bodyCode.contains("deepLinkBanner("),
                      "打不开的链接那条横幅没有挂在 `body` 这一层。摆在 `workspace` 里面的话，"
                          + "环境检查没过、用户停在授权引导页时，那句「下一步做什么」永远不上屏。"
                          + "下一步：把横幅和 `.onOpenURL` 挂在同一层。")
        XCTAssertFalse(workspaceCode.contains("deepLinkBanner("),
                       "横幅又回到了 `workspace` 里面，理由同上。下一步：只留 `body` 那一处。")
    }

    /// 横幅的出现/消失要尊重系统「减弱动态效果」（DESIGN-SYSTEM 第 5 节，硬性要求）。
    ///
    /// 这是本任务新加的一条 `reduceMotion` 分支，而它同样零覆盖：把
    /// `reduceMotion ? nil :` 那一段换成写死的动画，全套测试一条不红。
    /// 本项目已有两处同样的守法（`RetrainingFlowViewTests` / `RetrainingCenterViewTests` 的 `if reduceMotion`）。
    func testTheDeepLinkBannerRespectsReduceMotion() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(root.contains("@Environment(\\.accessibilityReduceMotion)"),
                      "`RootView` 没有读「减弱动态效果」，开着这个开关的用户照样会看到横幅滑进滑出"
                          + "（规范第 5 节）。下一步：加上这个 `@Environment` 并在动画处分支。")
        let bodyCode = try SourceGuard.memberBody(of: "public var body: some View", in: root)
        XCTAssertTrue(bodyCode.contains("reduceMotion ? nil :"),
                      "横幅的动画没有按「减弱动态效果」分支——开着开关的用户仍会看到过渡。"
                          + "实际取到的是：\n\(bodyCode)")
        XCTAssertTrue(bodyCode.contains("value: deepLinkNotice"),
                      "那条 `.animation` 没有绑在 `deepLinkNotice` 上，"
                          + "等于横幅进出根本不受这段分支管。实际取到的是：\n\(bodyCode)")
    }
}
