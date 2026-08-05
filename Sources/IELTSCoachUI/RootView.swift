import SwiftUI

public struct RootView: View {
    @State private var app = AppState()
    @State private var selection: SidebarItem? = .today

    public init() {}

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
            default: PlaceholderView(item: current)
            }
        }
    }
}

/// 未实现页面的占位。写明「还没做」与将来会有什么——
/// 空白页会让用户以为程序坏了。
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: item.systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text("「\(item.title)」还没做").font(.title3)
            Text(item.placeholderDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 480)
    }
}

#Preview { RootView() }
