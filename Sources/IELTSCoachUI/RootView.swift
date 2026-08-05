import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

public struct RootView: View {
    @State private var app: AppState
    @State private var selection: SidebarItem? = .today

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
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
        }
    }

    /// 侧边栏没选中任何一项时（比如用户按了 ⌘ 点掉选中）落回今日训练，
    /// 而不是给一块空白。
    private var current: SidebarItem { selection ?? .today }

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
            case .today: TodayView(app: app)
            case .questionBank: QuestionBankView(app: app)
            case .reviewReports: ReviewReportView(app: app)
            default: PlaceholderView(item: current, onGo: { selection = $0 })
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
