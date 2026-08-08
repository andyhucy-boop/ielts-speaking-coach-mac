import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

public struct RootView: View {
    /// **由 App 层建、由 App 层下发**（Phase 10 Task 16）。
    ///
    /// 从前是这一层自己 `@State private var app = AppState()`，那时进程里只有一个窗口，
    /// 也就只有一份状态。现在设置窗口是另一个 Scene，两边必须是**同一个实例**——
    /// 各建各的话，「在设置窗口把每周目标改成 9、主窗口那格当场变成 N/9」
    /// 就只能靠事后刷新去补，而漏一处就是一个在本机永远复现不了的 bug。
    let app: AppState
    /// 设置窗口停在哪一栏。工具栏那颗齿轮先 `open(.goals)` 再 `openSettings()`，
    /// 于是窗口弹出来时已经在「训练目标」那一栏了。
    let navigator: SettingsNavigator
    /// 打开 ⌘, 那个设置窗口。**用系统给的这一个，不要私有 selector。**
    @Environment(\.openSettings) private var openSettings
    /// 从「训练记录」点「看这次的复盘」带过来的那一场。
    ///
    /// **选中哪一页归 `app.navigation` 管，这一个仍留在这里**：它是「复盘报告」这一页
    /// 内部的一次性参数，不是全局导航状态；而选中页之所以搬进 `AppState`，
    /// 是因为今日训练页要跳到复训中心，回调传不到那儿（见 `NavigationState` 的说明）。
    ///
    /// 不带这个的话，
    /// 用户点某一场的复盘，跳过去看到的是最近那一场——内容看着完全正常，
    /// 但是别人家的，比一片空白更难被发现。
    ///
    /// **它是一次性的：用户自己再切一次页就作废**（见 `go(to:)`）。
    /// 只写不清的话方向会反过来犯同一个错——见 `RootRouter.carriedReviewSession` 的说明。
    @State private var requestedReviewSessionID: String?

    /// 收到一条打不开的 `ieltscoach://` 链接时要显示的那句话。
    ///
    /// **不能什么都不做。** macOS 把窗口拉到前台是系统干的，链接认不认得出来它不管；
    /// 认不出来又不吭声的话，用户看到的是「窗口跳出来了、页面纹丝不动」，
    /// 只会以为程序坏了（铁律：禁止静默失败）。
    @State private var deepLinkNotice: String?

    /// 开了系统「减弱动态效果」就不做过渡（DESIGN-SYSTEM 第 5 节，那是硬性要求）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 首次使用引导走到第几步。
    ///
    /// **它必须在这一层，不能在 `WelcomeFlowView` 自己手里**：引导里「重新检查」那一下
    /// 会把整屏换成「正在检查运行环境…」，引导页连同它的 `@State` 一起被销毁重建，
    /// 用户会被扔回第一步（理由与 `PermissionGateView.recheckAttempts` 完全相同）。
    @State private var onboarding = OnboardingFlowModel()

    /// 「引导看过没有」记在哪儿。**存本机 UserDefaults，不进数据目录**——
    /// 换了机器，辅助功能授权是本机 TCC 的，必须重给一次，引导应该再出现
    /// （理由写在 `OnboardingProgressStore` 上）。
    private let onboardingStore: any OnboardingProgressStore

    /// 生产入口。**`AppState` 与 `SettingsNavigator` 都由 App 层建好传进来**，
    /// 这一层不再自己 new——那两份状态要和设置窗口共用同一个实例（见 `app` 的说明）。
    ///
    /// 预览与测试同样走这一个：不带参数的 `AppState()` 用的是生产默认值，
    /// `AppState.livePreflight` 会 `NSWorkspace.open` 真的把 ChatGPT 启起来（铁律 5），
    /// `DataDirectory.resolve()` 又会在用户真实的「应用程序支持」目录里建目录和 `.state.lock`。
    /// `PreviewSafetyTests` 扫源码守着这件事。
    public init(app: AppState, navigator: SettingsNavigator) {
        self.init(app: app, navigator: navigator, onboardingStore: UserDefaultsOnboardingStore())
    }

    /// 注入引导进度用，**预览必须走这一个**：不然打开画布会往真实的偏好设置里
    /// 写一句「引导看过了」。
    init(app: AppState,
         navigator: SettingsNavigator,
         onboardingStore: any OnboardingProgressStore = UserDefaultsOnboardingStore()) {
        self.app = app
        self.navigator = navigator
        self.onboardingStore = onboardingStore
    }

    public var body: some View {
        // 横幅摆在最外面、三屏之上：它要能在「正在检查运行环境…」和授权引导页上照样显示。
        // 摆进 `workspace` 的话，用户卡在授权引导页时 handler 跑了、消息也存下了，
        // 屏幕上却一个字都没有——静默失败换了个地方发生（铁律 7）。
        //
        // 用 `VStack` 把它顶在上面而不是 `.overlay`：这句话是要读的，
        // 浮在上面会盖住下面那一屏的第一行内容。
        //
        // 横幅不在时那个 `if let` 是一个空视图，SwiftUI 不给它算 spacing，
        // 所以这一档间距只在真有横幅时出现。
        VStack(spacing: Spacing.md) {
            if let notice = deepLinkNotice { deepLinkBanner(notice) }
            // 这层 ZStack 不是为了排版：`.task` 必须挂在一个身份稳定的容器上。
            // 直接挂在下面的分支上，切屏会被当成新视图重新触发检查。
            // （`Group` 不行——它会把修饰符透传给每个子视图。）
            ZStack {
                switch RootRouter.screen(
                    isCheckingPermission: app.isCheckingPermission,
                    permission: app.permission,
                    questionCount: app.state.questions.count,
                    hasCompletedOnboarding: hasCompletedOnboarding,
                    onboardingDismissed: app.onboardingDismissed) {
                case .checkingEnvironment:
                    checkingEnvironment
                case .onboarding:
                    // 授权那一步在引导里面（`WelcomeFlowView` 复用 `PermissionGateView`），
                    // 所以这一层不再单独摆一道授权页——两处各摆一道的话，
                    // 用户在引导里跳过之后会撞上第二道说着同一件事的墙。
                    WelcomeFlowView(app: app,
                                    model: onboarding,
                                    hasCompletedBefore: hasCompletedOnboarding,
                                    onFinish: finishOnboarding)
                case .workspace:
                    workspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: deepLinkNotice)
        .task { await app.startInitialPermissionCheckIfNeeded() }
        // **必须挂在这一层，不能挂在 `workspace` 上。** `workspace` 是
        // `RootRouter.screen` 的一条分支：`AppState.isCheckingPermission` 初值是 `true`，
        // 启动那一瞬间在屏幕上的是「正在检查运行环境…」（最长约十秒），`workspace` 不在视图树里。
        // 而 App 没在跑时，Codex 调 `open_dashboard` 会先把 App 拉起来，链接正好投在这十秒中间——
        // `.onOpenURL` 不是队列，投递时没有 handler 就直接丢了：窗口跳到前台、页面纹丝不动、
        // 一句报错都没有（铁律 7）。环境检查没过、用户长期停在授权引导页时更是每一条都蒸发。
        // `DeepLinkTests` 里那条「不许挂回 workspace」的断言守着这件事。
        .onOpenURL { url in
            switch DeepLinkResolver.resolve(url) {
            case .open(let item):
                // **走 `go(to:)`，不直接写 `app.navigation.selection`。**
                // 计划里写的是后者，那是它成文时的形态；现在切页还要顺手作废
                // 「从训练记录带过来的那一场」（见 `go(to:)` 与 `RootRouter.carriedReviewSession`）。
                // 绕过它的话，深链接连着切两次页（复盘报告 → 训练记录 → 复盘报告）之后，
                // 用户看到的会是几天前那一场旧复盘——内容看着完全正常，但是别人家的。
                go(to: item)
                deepLinkNotice = nil
            case .rejected(let message):
                // 不能什么都不做——用户点了链接、窗口跳出来却毫无反应，
                // 只会以为程序坏了（禁止静默失败）。
                deepLinkNotice = message
            }
        }
    }

    /// 磁盘上记着的「引导看过没有」。版本号涨了就当成没看过——
    /// 不留这个口子的话，改了引导也没人看得到（见 `OnboardingFlow.currentVersion`）。
    private var hasCompletedOnboarding: Bool {
        onboardingStore.completedVersion() >= OnboardingFlow.currentVersion
    }

    /// 引导收工：记一笔「看过了」，再放行到主界面。
    ///
    /// **两件事都要做，缺一不可。** 只记不放行，`OnboardingFlow.steps` 会因为权限仍缺
    /// 立刻算出 `[.environment]`，引导当场又弹回用户脸上；只放行不记，下次开机
    /// 从「欢迎」重头再来一遍。
    private func finishOnboarding() {
        onboardingStore.markCompleted(version: OnboardingFlow.currentVersion)
        app.onboardingDismissed = true
    }

    /// 检查最长可能花十秒（要等 ChatGPT 的无障碍树醒过来）。这段时间里界面必须一直在说话，
    /// 否则用户对着一个不动的窗口只会以为死机了（DESIGN-SYSTEM 第 5 节）。
    private var checkingEnvironment: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("正在检查运行环境…")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("在确认 ChatGPT 桌面应用是否已安装、辅助功能权限是否已授权。"
                 + "下一步：稍等几秒，检查完会自动进入；最长约十秒。")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
    }

    private var workspace: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: sidebarSelection) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        // 打开的是**设置窗口本体**，并停在「训练目标」那一栏。
                        // 从前这里弹的是一张自己的小面板（`WeeklyGoalSheet`），
                        // 于是同一个设置有了两份界面；Task 16 把面板整个删掉，
                        // 只留这条深链接：一个窗口、一份状态、两条到达路径。
                        Button { navigator.open(.goals); openSettings() } label: {
                            Label("每周训练目标", systemImage: "gearshape")
                        }
                        // **不挂 ⌘,。** 那个快捷键归 `Sources/IELTSCoachApp/main.swift` 里的
                        // `Settings { SettingsWindowView(…) }` 场景——两处绑同一个快捷键，
                        // SwiftUI 不报错，只会随机胜出一个，用户按 ⌘, 时而弹这个、时而弹那个。
                        .help("到设置里改每周训练目标")
                    }
                }
        }
    }

    /// 打不开的链接给一条横幅，把那句话原原本本摆在窗口顶上。
    ///
    /// **由 `body` 直接摆出来，不在 `workspace` 里面**：环境检查那十秒、以及权限没过时的
    /// 授权引导页，`workspace` 整个不在视图树上，摆在里面的话那期间收到的坏链接一句提示都看不到。
    ///
    /// 不截断（`fixedSize`）：这句话的后半截才是「下一步做什么」，截掉就只剩抱怨。
    private func deepLinkBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { deepLinkNotice = nil } label: {
                Image(systemName: "xmark").foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭这条提示")
            .help("关闭这条提示")
        }
        .padding(Spacing.md)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(Palette.warning, lineWidth: BorderWidth.hairline))
        .padding(.horizontal, Spacing.xl)
        // 只补上边：下边那一档由 `body` 里那个 `VStack(spacing: Spacing.md)` 给，
        // 两处都写就会变成 32pt 的空当。
        .padding(.top, Spacing.md)
    }

    /// 侧边栏的选中项。**不能直接把导航状态交出去**：写进来的那一头还要顺手
    /// 把「从训练记录带过来的那一场」作废掉（见 `go(to:)`）。
    ///
    /// 对外仍是 `SidebarItem?`，因为 `List(selection:)` 只收可选值——用户按 ⌘ 点掉选中时
    /// 它会写回 nil。而 `NavigationState.selection` 是非可选的，理由见 `go(to:)`。
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { app.navigation.selection }, set: { go(to: $0) })
    }

    /// 换一页。**凡是用户自己发起的切页都要走这里**——侧边栏，以及各页面里那些
    /// 「去今日训练」「看复盘报告」按钮（它们走 `onGo`）。
    ///
    /// 唯一的例外是「训练记录 › 看这次的复盘」那条跳转：它要带着那一场过去，
    /// 所以自己写 `requestedReviewSessionID` 与 `selection`，见 `detail` 里的 `onOpenReview`。
    private func go(to item: SidebarItem?) {
        // 先算再改：这个判断要拿「还没换页时的选中项」作依据。
        requestedReviewSessionID = RootRouter.carriedReviewSession(
            requestedReviewSessionID, navigatingFrom: app.navigation.selection, to: item)
        // 用户按 ⌘ 点掉选中时列表会写回 nil。**那一下不换页**：
        // 导航状态不收 nil，否则每个读它的地方都得再判一次「没选中时算哪一页」，
        // 而那正是从前 `selection ?? .today` 在做的事——把它收在这一处。
        if let item { app.navigation.selection = item }
    }

    /// 当前这一页。选中项归 `app.navigation` 管，这一页只是读它。
    private var current: SidebarItem { app.navigation.selection }

    @ViewBuilder private var detail: some View {
        if let loadError = app.loadError {
            // 读不到数据时不进任何一页：那些页面全靠 state 渲染，进去只会是一堆空列表，
            // 用户会以为练习记录没了。
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("读不到训练数据")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(loadError)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                Button("重试") { app.reload() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        } else {
            switch current {
            case .today: TodayView(app: app, onGo: { go(to: $0) }, navigator: navigator)
            case .questionBank: QuestionBankView(app: app)
            case .reviewReports: ReviewReportView(app: app, onGo: { go(to: $0) },
                                                  requestedSessionID: requestedReviewSessionID)
                // 带过来的那一场换了，就得是一份全新的复盘页。
                // 复盘页里「用户自己点的那一次」是 `@State`，不换身份的话，
                // 万一 SwiftUI 把上一次进来时的选择留着，用户点「看这次的复盘」
                // 看到的还是他上回在这一页点开的那一场。
                .id(requestedReviewSessionID)
            case .history: HistoryView(app: app, onGo: { go(to: $0) },
                                       navigator: navigator,
                                       onOpenReview: { session in
                                           // 这一条不走 `go(to:)`：它就是要带着这一场过去。
                                           requestedReviewSessionID = session.id
                                           app.navigation.selection = .reviewReports
                                       })
            case .plan: PlanView(app: app, navigator: navigator)
            case .retraining: RetrainingCenterView(app: app, onGo: { go(to: $0) })
            case .issues: IssueArchiveView(app: app, onGo: { go(to: $0) })
            case .vocabulary: VocabularyView(app: app, onGo: { go(to: $0) })
                // 这一页不读 `app`：它显示的是「你手上这份 App 是哪一版、改了什么」，
                // 全部来自 `AppMetadata` 与 `Changelog` 那张常量表。
            case .upgrade: UpgradeView()
                // 这一页要读 `app`：诊断信息里有环境检查的结论与原文、训练数据的**数量**
                // （只有数量，没有内容）。数据目录由它自己解析（与关于页同一条路径）。
            case .feedback: FeedbackView(app: app)
            }
            // **这个 `switch` 是穷尽的，没有 `default:`。** 十项全部有了内容之后，
            // `PlaceholderView` 连同 `SidebarItem.placeholder*` 一起删掉了。
            // 将来万一真要动侧边栏，编译器会在这里当场报错，而不是默默显示一个空页面。
        }
    }
}

// `PlaceholderView` 在 Phase 10 Task 18 里删掉了：十项侧边栏全部有了内容，
// 它成了永远走不到的死代码。上面那个 `switch` 因此变成穷尽的——
// 将来真要往侧边栏加一项，编译器会当场报错，而不是默默摆出一页空白。

/// 预览一律走注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）
/// + 只活在内存里的引导进度（不往真实偏好设置里写「引导看过了」）。
/// 见 `RootView.init(app:navigator:onboardingStore:)` 的说明。
#Preview {
    RootView(app: AppState(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview")),
        preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }),
             navigator: SettingsNavigator(),
             onboardingStore: InMemoryOnboardingStore(
                completedVersion: OnboardingFlow.currentVersion))
}
