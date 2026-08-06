import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

public struct RootView: View {
    @State private var app: AppState
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

    /// 生产入口：真实数据目录 + 真实的环境检查。
    public init() { self.init(app: AppState()) }

    /// 注入用，**预览必须走这一个**。
    ///
    /// 不带参数的 `AppState()` 用的是生产默认值：`AppState.livePreflight` 会
    /// `NSWorkspace.open` 真的把 ChatGPT 启起来（铁律 5），`DataDirectory.resolve()`
    /// 又会在用户真实的「应用程序支持」目录里建目录和 `.state.lock`。
    /// 也就是说，在预览里直接写无参的 `RootView()`，会让「打开画布看一眼布局」这件事
    /// 产生真实副作用。`PreviewSafetyTests` 扫源码守着这件事。
    init(app: AppState) { _app = State(initialValue: app) }

    public var body: some View {
        // 外面这层 ZStack 不是为了排版：`.task` 必须挂在一个身份稳定的容器上。
        // 直接挂在下面的分支上，切屏会被当成新视图重新触发检查。
        // （`Group` 不行——它会把修饰符透传给每个子视图。）
        ZStack {
            switch RootRouter.screen(isCheckingPermission: app.isCheckingPermission,
                                     permission: app.permission,
                                     permissionSkipped: app.permissionSkipped) {
            case .checkingEnvironment:
                checkingEnvironment
            case .permissionGate:
                PermissionGateView(state: app.permission,
                                   messages: app.permissionMessages,
                                   recheckAttempts: app.recheckAttempts,
                                   onRecheck: { Task { await app.recheckPermission() } },
                                   onSkip: { app.permissionSkipped = true })
            case .workspace:
                workspace
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task { await app.startInitialPermissionCheckIfNeeded() }
    }

    /// 检查最长可能花十秒（要等 ChatGPT 的无障碍树醒过来）。这段时间里界面必须一直在说话，
    /// 否则用户对着一个不动的窗口只会以为死机了（DESIGN-SYSTEM 第 5 节）。
    private var checkingEnvironment: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在检查运行环境…").font(.title3)
            Text("在确认 ChatGPT 桌面应用是否已安装、辅助功能权限是否已授权。"
                 + "下一步：稍等几秒，检查完会自动进入；最长约十秒。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
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
        }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("读不到训练数据").font(.title3).bold()
                Text(loadError).font(.body).textSelection(.enabled)
                Button("重试") { app.reload() }.buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
        } else {
            switch current {
            case .today: TodayView(app: app, onGo: { go(to: $0) })
            case .questionBank: QuestionBankView(app: app)
            case .reviewReports: ReviewReportView(app: app, onGo: { go(to: $0) },
                                                  requestedSessionID: requestedReviewSessionID)
                // 带过来的那一场换了，就得是一份全新的复盘页。
                // 复盘页里「用户自己点的那一次」是 `@State`，不换身份的话，
                // 万一 SwiftUI 把上一次进来时的选择留着，用户点「看这次的复盘」
                // 看到的还是他上回在这一页点开的那一场。
                .id(requestedReviewSessionID)
            case .history: HistoryView(app: app, onGo: { go(to: $0) },
                                       onOpenReview: { session in
                                           // 这一条不走 `go(to:)`：它就是要带着这一场过去。
                                           requestedReviewSessionID = session.id
                                           app.navigation.selection = .reviewReports
                                       })
            case .retraining: RetrainingCenterView(app: app, onGo: { go(to: $0) })
            default: PlaceholderView(item: current, onGo: { go(to: $0) })
            }
        }
    }
}

/// 未实现页面的占位。按 DESIGN-SYSTEM 第 4 节「空状态（必须有，不能留白）」给足三样：
/// **一句现状**（「还没做」）、**一句下一步**（现在真做得到的事，见 `placeholderDescription`）、
/// **一个能直接点的按钮**（跳到那件事所在的页面）。
///
/// 只有前两样也不够：光写一句「可以先去今日训练」，用户读完还得自己回去翻侧边栏。
struct PlaceholderView: View {
    let item: SidebarItem
    /// 点了按钮之后把侧边栏选中项换到哪一页。由 `RootView` 提供——
    /// 占位页自己不持有导航状态。
    let onGo: (SidebarItem) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text("「\(item.title)」还没做").font(.title3)
            Text(item.placeholderDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let target = item.placeholderFallback {
                Button(item.placeholderActionTitle) { onGo(target) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
    }
}

/// 预览一律走注入：假的环境检查（不碰真的 ChatGPT）+ 临时目录（不碰用户真实的训练数据）。
/// 见 `RootView.init(app:)` 的说明。
#Preview {
    RootView(app: AppState(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview")),
        preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) }))
}
