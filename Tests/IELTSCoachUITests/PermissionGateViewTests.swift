import Foundation
import XCTest

@testable import IELTSCoachUI

/// 权限页与根视图上那几件**逻辑写对了、但可能根本没被画到屏幕上**的事。
///
/// 这一页的每一句话都有纯函数守着（`PermissionStatusTests`），但那些函数是不是真的
/// 被调用、返回值是不是真的摆进了 `body`，没有任何一条测试问过——本项目在
/// `PracticeSheet`、`QuestionBankImportResultSheet` 上已经因为这件事栽过两次：
/// 渲染那一段整段删掉，全套测试照样全绿。
///
/// 边界与 `TodayViewTests` 一样：扫源码不执行代码，拦得住「整段被删」「写好了没摆上」，
/// 拦不住「代码还在但跑不到」；排版好不好看归人工验收。
final class PermissionGateViewTests: XCTestCase {
    static let viewPath = "Onboarding/PermissionGateView.swift"
    static let rootPath = "RootView.swift"
    /// Phase 10 Task 8 之后，摆出权限页的不再是根视图，而是首次使用引导的「环境」那一步。
    /// 根视图只负责决定「这一屏显不显示引导」。
    static let flowPath = "Onboarding/WelcomeFlowView.swift"

    // MARK: - 最上面那行标题

    /// `title(for:)` 里四档文案钉得再死，这一行调用删掉，用户照样一个字都看不到——
    /// 而且那时页面最上面是一片空白，最像「程序坏了」的一种样子。
    func testTheHeadlineIsActuallyRenderedOnThePage() {
        SourceGuard.assertRenders("PermissionStatus.title(for: state)",
                                  inBodyOf: "public var body", of: Self.viewPath,
                                  because: "权限页最上面那行标题没有被画出来。"
                                      + "下一步：把 `Text(PermissionStatus.title(for: state))` "
                                      + "放回 body 的第一行；换了写法就同步改这条测试。")
        SourceGuard.assertRenders("PermissionStatus.guidance(for: state",
                                  inBodyOf: "public var body", of: Self.viewPath,
                                  because: "「发生了什么 + 下一步做什么」那段引导语没有被画出来，"
                                      + "用户只剩一个标题和几颗按钮。")
    }

    // MARK: - 「重新检查」按下去的反馈

    /// 这颗是这一页上按得最多的键：去系统设置勾完开关回来，第一件事就是按它。
    /// 重查结论和上次一样时，`state` 和 `messages` 都不变——那句反馈是屏幕上唯一会变的东西，
    /// 它没被画出来，等于这颗按钮又回到「点了没反应」。
    func testTheRecheckFeedbackIsRenderedAndFedByTheRealCounter() {
        SourceGuard.assertRenders("PermissionStatus.recheckNotice(",
                                  inBodyOf: "public var body", of: Self.viewPath,
                                  because: "「已重新检查，仍未通过：…」那句反馈没有被画出来。"
                                      + "下一步：把 `PermissionStatus.recheckNotice(...)` 的返回值"
                                      + "放回 body 里显示。")
        SourceGuard.assertRenders("completedAttempts: recheckAttempts",
                                  inBodyOf: "public var body", of: Self.viewPath,
                                  because: "重查反馈没有接在真实的次数上，那它要么永远不显示、"
                                      + "要么一直挂着。下一步：把 `recheckAttempts` 传进去。")

        // 摆出权限页的那一头得把 AppState 的计数真的递下来。**必须是 `app.recheckAttempts`**：
        // 视图自己的 @State 在重查期间会随页面一起被销毁（那十秒里显示的是等待屏），
        // 查完回来是全新的一份，那句反馈永远显示不出来。
        SourceGuard.assertRenders("recheckAttempts: app.recheckAttempts", in: Self.flowPath,
                                  because: "引导的「环境」那一步没把重查次数递给权限页。"
                                      + "下一步：`PermissionGateView(... recheckAttempts: "
                                      + "app.recheckAttempts ...)`。")
        SourceGuard.assertRenders("await app.recheckPermission()", in: Self.flowPath,
                                  because: "「重新检查」这颗按钮没有接在 AppState 上，按了不会真去查。")
    }

    // MARK: - 那十秒里界面一直在说话

    /// `AppState.isCheckingPermission` 的值再对，路由不读它也白搭：
    /// 写死成 `false` 的话，重查那十秒里用户对着一动不动的授权页干等（问题 3 的另一半）。
    func testTheWaitingScreenIsWiredToTheRealFlag() {
        SourceGuard.assertRenders("isCheckingPermission: app.isCheckingPermission",
                                  inBodyOf: "public var body", of: Self.rootPath,
                                  because: "路由没有读 `app.isCheckingPermission`。"
                                      + "下一步：确认它不是被写死成了某个常量——"
                                      + "写死成 false，重查的十秒里界面一个像素都不会变。")
        // 声明一次、用一次、`switch` 里对上一次。只问「出现过吗」的话，
        // 把 `case .checkingEnvironment: checkingEnvironment` 那句删掉照样绿。
        SourceGuard.assertRenders("checkingEnvironment", in: Self.rootPath, atLeast: 3,
                                  because: "等待屏要么没有声明、要么没被摆进 switch 的那一支。"
                                      + "下一步：确认 `.checkingEnvironment` 这一支画的确实是它。")
        SourceGuard.assertRenders("正在检查运行环境", in: Self.rootPath,
                                  because: "等待屏上那句话没了，用户看到的是一个不动的窗口"
                                      + "（DESIGN-SYSTEM 第 5 节：超过 300ms 的操作都要有反馈）。")
        SourceGuard.assertRenders("ProgressView()", inBodyOf: "private var checkingEnvironment",
                                  of: Self.rootPath,
                                  because: "等待屏上没有转圈的指示器，只有一段静止的文字，"
                                      + "十秒里看不出它到底还在不在动。")
    }
}
