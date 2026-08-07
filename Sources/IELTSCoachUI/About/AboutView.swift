import AppKit
import ChatGPTBridge
import IELTSCoachCore
import Observation
import SwiftUI

/// 关于窗口的 id。菜单项与场景注册靠它对上，写错一个字母就是「点了没反应」，
/// 所以只在这里写一次。
public enum AboutWindow {
    public static let id = "about"
}

/// 苹果菜单里的「关于 …」。
///
/// **关于页在苹果菜单里，不在侧边栏。** 侧边栏固定十项（产品设计稿定死的，
/// Phase 3 的 `testSidebarHasAllTenItems` 守着），而苹果菜单是 Mac 应用放这一页的标准位置。
public struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("关于 IELTS Speaking Coach") { openWindow(id: AboutWindow.id) }
    }
}

/// 关于页自己的那份数据。
///
/// ## 为什么它不共享主窗口的 `AppState`
///
/// 关于页是独立窗口（`Window(id: AboutWindow.id)`），拿不到主窗口那份 `AppState`，
/// 所以它自己读一次 `state.json`。这是只读页，重复读一次的代价可以忽略；
/// 换成到处传 `AppState` 反而会把主窗口的生命周期和一个偶尔打开的小窗绑死。
/// 设置窗口（⌘,）已经是同样的分工（见 `RecordingSettingsScene`）。
///
/// ## 为什么打开这一页不自动检查环境
///
/// `preflight()` 会 `NSWorkspace.open` 把 ChatGPT 拉到前台，并最多轮询八秒等它的
/// 无障碍树醒过来（实测约九秒）。用户点开「关于」多半只是想看一眼版本号或者
/// 拷一份诊断信息，界面却把他手上的事打断了——所以这一页把检查留给「重新检查」那颗按钮。
///
/// 代价是「辅助功能」那一行在查之前没有结论，而 `PermissionState` 只有四档，
/// 直接拿 `.unknown` 去渲染会写成「检查未通过」——**那是一句没查就下的结论**。
/// 所以 `rows` 里把这一行换成「还没检查」，并给出下一步。诊断文本同理（见 `diagnosticsText`）。
@MainActor
@Observable
public final class AboutPageModel {
    /// 这一页显示的六行事实。**永远有六行**：读不到训练数据不影响版本、签名、数据目录，
    /// 而这一页恰恰是出问题时才会被打开的那一页。
    public var rows: [AboutRow] {
        AboutViewModel.rows(metadata: metadata,
                            dataDirectory: directory.root,
                            permission: permission ?? .unknown,
                            portabilityFindings: findings)
            .map(honest)
    }

    /// 环境检查的结论。**`nil` 表示这一页还没查过**，不是「查过了不通过」。
    public private(set) var permission: PermissionState?
    /// 检查结果原文。`AboutViewModel` 那条 hint 写着「点「重新检查」看原始消息」，
    /// 所以查到的原文必须留下来给界面显示，也要跟着诊断信息一起发出去。
    public private(set) var permissionMessages: [String] = []
    /// 正在跑检查。那九秒里界面必须一直在说话（DESIGN-SYSTEM 第 5 节）。
    public private(set) var isChecking = false
    /// 读 `state.json` 失败时的中文说明（发生了什么 + 下一步）。非 nil 时界面必须显示它。
    public private(set) var loadError: String?
    /// 按钮点完之后的一句反馈。**成功也要说话**：只在失败时才出声的话，
    /// 用户分不清「成功了」和「点了没反应」。
    public private(set) var notice: ActionNotice?

    public let metadata: AppMetadata
    /// 数据目录的绝对路径。界面上要显示它，读盘失败那一块尤其要——
    /// 用户得知道去哪儿找那个文件。
    public var dataDirectoryPath: String { directory.root.path }

    private let directory: DataDirectory
    private let store: StateStore
    private let systemVersion: String
    private let preflight: @Sendable () -> BridgeReadiness
    private let reveal: (URL) -> Bool
    private let writeToPasteboard: (String) -> Bool

    /// 读出来的训练数据。**读失败时是 nil，不是 `.empty()`**：
    /// 拿空白顶上，诊断信息里会写着「题库 0 题 · 练习记录 0 次」，
    /// 而收到这段文字的人会照着一个凭空的数字去找方向。
    private var state: CoachState?
    private var findings: [PortabilityFinding] = []

    /// 生产环境真正去打开访达的那一下。
    ///
    /// **先判「这儿真的是一个文件夹」再打开**：`NSWorkspace.activateFileViewerSelecting`
    /// 没有返回值，目录不在时它只是静静地什么都不做——那正是铁律 7 说的静默失败。
    /// 这里把「打不开」变成一个 false，调用方才有话可说。
    ///
    /// 只判 `fileExists` 不够：数据目录该在的位置被一个**同名文件**占住时
    /// （`createIfNeeded` 会因此抛错，本项目的测试里就是这么造故障的），
    /// `fileExists` 照样是 true，于是界面会说一句「已在访达中打开数据目录」——
    /// 而访达里弹出来的是一个文件。用户接下来会照着这句话去那个「目录」里找 reports/，
    /// 永远找不到，也不知道真正卡住他的是那个同名文件。
    nonisolated public static func revealInFinder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// 生产环境真正去写剪贴板的那一下。**返回值必须消费**——
    /// `setString` 会失败（别的进程正占着剪贴板），丢掉它用户会粘出上一次复制的东西。
    nonisolated public static func copyToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    public init(directory: DataDirectory = .resolve(),
                metadata: AppMetadata = .current,
                systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                preflight: @escaping @Sendable () -> BridgeReadiness = AppState.livePreflight,
                reveal: @escaping (URL) -> Bool = AboutPageModel.revealInFinder,
                writeToPasteboard: @escaping (String) -> Bool = AboutPageModel.copyToPasteboard) {
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.metadata = metadata
        self.systemVersion = systemVersion
        self.preflight = preflight
        self.reveal = reveal
        self.writeToPasteboard = writeToPasteboard
        // 只读本地磁盘（毫秒级）。环境检查**不在**这里做，理由见类型注释。
        reload()
    }

    /// 重读 `state.json` 并重跑一次可搬迁审计。「重试」按钮与「重新检查」都走这一份。
    public func reload() {
        do {
            let loaded = try store.load()
            state = loaded
            findings = DataPortabilityAudit.audit(state: loaded, directory: directory)
            loadError = nil
        } catch {
            state = nil
            findings = []
            loadError = AppState.describeLoadFailure(error, stateFile: directory.stateFile)
        }
    }

    /// 「重新检查」：再跑一次 preflight，并把磁盘重读一遍（可搬迁审计也跟着重跑）。
    ///
    /// 检查放在主线程之外：它要启动 ChatGPT 并最多轮询八秒。放在主线程上等于让窗口冻住十秒。
    /// 期间 `isChecking` 为 true，界面靠它显示「正在检查…」。
    public func recheck() async {
        guard !isChecking else { return }
        isChecking = true
        let run = preflight
        let readiness = await Task.detached(priority: .userInitiated) { run() }.value
        permission = PermissionStatus.evaluate(readiness: readiness)
        permissionMessages = readiness.messages
        // 环境和数据一起刷新：用户按这颗按钮是想看「现在到底怎么样」，
        // 只换半边的话，可搬迁那一行显示的还是打开窗口那一刻的旧结论。
        reload()
        isChecking = false
    }

    /// 「在访达中显示」。
    ///
    /// 全新安装、还没练过一场时这个目录可能压根不存在，所以先建出来再交给访达；
    /// **建不出来（位置被同名文件占了、盘满、只读卷）必须说话**，
    /// 不许 `try?` 吞掉之后再说一句「已打开」（铁律 7）。
    public func revealDataDirectory() {
        var creationFailure: String?
        do {
            try directory.createIfNeeded()
        } catch {
            creationFailure = error.localizedDescription
        }
        guard reveal(directory.root) else {
            let cause = creationFailure.map { "建这个文件夹时系统报的是：\($0)。" }
                ?? "这个位置现在打不开。"
            notice = ActionNotice(
                text: "没能在访达里打开数据目录：\(dataDirectoryPath)。\(cause)"
                    + "下一步：确认这个位置可写（磁盘没满、外接盘还连着、同名的位置上不是一个文件）；"
                    + "把上面那行路径拷进访达的「前往」-「前往文件夹」也能直接打开它。",
                isFailure: true)
            return
        }
        notice = ActionNotice(text: "已在访达中打开数据目录。", isFailure: false)
    }

    /// 「复制诊断信息」。**只把文字放进剪贴板，一个字节都不往外发**——
    /// 送到哪儿去是用户自己粘贴时才决定的事。
    public func copyDiagnostics() {
        guard writeToPasteboard(diagnosticsText) else {
            notice = ActionNotice(
                text: "没能把诊断信息写进剪贴板（多半是别的程序正占着它）。"
                    + "下一步：把这一页上的内容直接选中按 ⌘C；"
                    + "版本、签名、数据目录这几行都能选中复制。",
                isFailure: true)
            return
        }
        notice = ActionNotice(text: "诊断信息已复制到剪贴板，粘贴给开发者即可。", isFailure: false)
    }

    /// 复制出去的那段文字。
    ///
    /// **凡是这一页没拿到的东西，都要在文字里说明白。** `DiagnosticsReport` 收的是一份
    /// `CoachState` 与一个 `PermissionState`，两者在「读盘失败」「还没检查」时都只有占位值；
    /// 不加说明就等于把凭空的 0 和一句没查过的结论一起发给了别人。
    public var diagnosticsText: String {
        var text = DiagnosticsReport.text(DiagnosticsInput(
            metadata: metadata,
            dataDirectory: directory.root,
            systemVersion: systemVersion,
            permission: permission ?? .unknown,
            state: state ?? .empty(),
            portabilityFindingCount: findings.count))
        if permission == nil {
            text += "\n注：本页打开后还没做过环境检查（打开关于页不会自动检查，那会把 ChatGPT "
                + "拉到前台），所以上面「辅助功能」那一行不是结论。"
                + "下一步：在关于页点「重新检查」，查完再复制一次。"
        }
        if !permissionMessages.isEmpty {
            text += "\n检查结果原文：\n"
                + permissionMessages.map { "- \($0)" }.joined(separator: "\n")
        }
        if let loadError {
            text += "\n注：读不到训练数据，所以上面「数据量」与「数据可搬迁检查」两行是占位值，"
                + "不是真实数字。读盘失败的原文是：\(loadError)"
        }
        return text
    }

    /// 把「还没查」「正在查」「查不成」三种情况说成它们本来的样子。
    ///
    /// `AboutViewModel.rows` 只认四档权限状态和一份findings清单，
    /// 而这一页有它答不上来的时刻——照它的输出原样显示就会变成说假话。
    private func honest(_ row: AboutRow) -> AboutRow {
        switch row.id {
        case "permission" where isChecking:
            return AboutRow(id: row.id, label: row.label, value: "正在检查…",
                            hint: "正在启动 ChatGPT 并等它的界面醒过来，实测约需九秒。"
                                + "下一步：等这一行给出结论，其间不用做别的。")
        case "permission" where permission == nil:
            return AboutRow(id: row.id, label: row.label, value: "还没检查",
                            hint: "打开这一页不会自动检查——检查要启动 ChatGPT，会打断你手上的事。"
                                + "下一步：点「重新检查」查一次，结论会显示在这一行。")
        case "portability" where loadError != nil:
            return AboutRow(id: row.id, label: row.label, value: "这次没查成",
                            hint: "这项检查要读训练数据，而这次没读出来（原因见上面那块说明）。"
                                + "下一步：先按那段说明把文件修好，再点「重试」。")
        default:
            return row
        }
    }
}

/// 关于页本体。
///
/// 布局遵 DESIGN-SYSTEM：页面内边距 `Spacing.xl`、卡片用 `CoachCard`、
/// 区块用 `SectionHeader`、图标一律 SF Symbols（不用 emoji）。
///
/// **在 `swift run IELTSCoachApp` 下跑时，版本那几行会显示「未知（开发运行）」**——
/// 那不是 bug：直接跑没有 App bundle，`Bundle.main.infoDictionary` 是 nil
/// （`AppMetadata` 每个字段都有兜底就是为了这一刻）。要看真实版本号得先
/// `./scripts/build-app.sh` 再打开 `.app`。
@MainActor
public struct AboutView: View {
    @State private var model: AboutPageModel

    /// 生产用的那一个：自己解析数据目录、自己读一次磁盘。
    public init() {
        _model = State(wrappedValue: AboutPageModel())
    }

    /// 注入用的那一个（测试与预览）。**预览必须走它**：不带参数的那一个会在用户真实的
    /// 「应用程序支持」目录里建目录（见 `PreviewSafetyTests`）。
    public init(model: AboutPageModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if let error = model.loadError { loadErrorCard(error) }
                SectionHeader(number: 1, label: "THIS BUILD", title: "这份 App 是哪一份")
                factsCard
                actions
                if let notice = model.notice { noticeLine(notice) }
                if !model.permissionMessages.isEmpty { checkOutputCard }
                acknowledgementsSection
                licenseSection
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .font(Typography.body)
        // 窗口用 `.windowResizability(.contentSize)`，尺寸由这里的 ideal 值决定；
        // 外面套着 `ScrollView`，所以系统文字调到最大档时内容会滚动，不会被截断。
        .frame(minWidth: 560, idealWidth: 720, maxWidth: 900,
               minHeight: 460, idealHeight: 660, maxHeight: 900)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "graduationcap")
                    .imageScale(.large)
                    .foregroundStyle(Palette.accent)
                Text(model.metadata.displayName)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text(model.metadata.versionLine)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var factsCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.rows) { row in rowLine(row) }
            }
        }
    }

    /// 一行事实：标签、内容、补充说明。
    ///
    /// **`hint` 为空时不画那一行**：空白行会让人以为那儿本该有话却没显示出来。
    @ViewBuilder private func rowLine(_ row: AboutRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(row.label)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            Text(row.value)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !row.hint.isEmpty {
                Text(row.hint)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 三颗按钮。主行动只有一个（「重新检查」），另外两个明确次一级。
    ///
    /// 「重新检查」在查的时候被 `.disabled` 挡住，防止连点排队；
    /// 那九秒里下面那行字是界面唯一的反馈（DESIGN-SYSTEM 第 5 节：超过 300ms 就要有反馈）。
    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Button("重新检查") { Task { await model.recheck() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .disabled(model.isChecking)
                Button("在访达中显示") { model.revealDataDirectory() }
                Button("复制诊断信息") { model.copyDiagnostics() }
            }
            if model.isChecking {
                Label("正在检查运行环境…这一步要启动 ChatGPT 并等它的界面醒过来，约需九秒。",
                      systemImage: "hourglass")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func noticeLine(_ notice: ActionNotice) -> some View {
        Label(notice.text,
              systemImage: notice.isFailure ? "exclamationmark.triangle" : "checkmark.circle")
            .font(Typography.secondary)
            .foregroundStyle(notice.isFailure ? Palette.danger : Palette.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 读不到训练数据时的那一块：错误全文 + 数据目录路径 + 一颗能点的「重试」。
    ///
    /// **不能只留一片空白**：这一页正是出问题时才会被打开的那一页，
    /// 而版本、签名、辅助功能几行照样是准的——所以只挡这一块，不挡整页。
    @ViewBuilder private func loadErrorCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("读不到你的训练数据", systemImage: "exclamationmark.triangle")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.danger)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("数据目录：\(model.dataDirectoryPath)")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("下面的版本、标识、签名、辅助功能几行不受影响，照样是准的。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                Button("重试") { model.reload() }
            }
        }
    }

    /// 检查结果原文。「辅助功能」那一行在 `.unknown` 时写着「点「重新检查」看原始消息」，
    /// 这一块就是那句话指的地方——不画出来，那条「下一步」就指向空气。
    private var checkOutputCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("检查结果原文")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                ForEach(model.permissionMessages, id: \.self) { message in
                    Text(message)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var acknowledgementsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 2, label: "CREDITS", title: "致谢")
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(AboutViewModel.acknowledgements) { item in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(item.name)
                                .font(Typography.cardTitle)
                                .foregroundStyle(Palette.textPrimary)
                                .textSelection(.enabled)
                            Text(item.role)
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.license)
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            // 没有链接的两条（SF Pro、第三方依赖）不画空链接：
                            // 一个点不开的链接比不给更让人困惑。
                            if !item.url.isEmpty, let url = URL(string: item.url) {
                                Link(item.url, destination: url)
                                    .font(Typography.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 许可区。**全文原样显示，且必须能选中复制。**
    ///
    /// 工程里有逐字沿用自上游（MIT）的文本，MIT 唯一的条件是把版权声明与许可声明的
    /// 原文随副本一起交付——交出去的是 `.app`，里面没有源码树，
    /// 这一页就是那份原文唯一的容身之处（见 `AboutViewModel.licenseNotice` 的说明）。
    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 3, label: "LICENSE", title: "许可与声明")
            CoachCard {
                Text(AboutViewModel.licenseNotice)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 预览注入临时目录与假 preflight，不碰用户真实的训练数据、也不启动 ChatGPT
/// （见 `PreviewSafetyTests`）。
#Preview("关于") {
    AboutView(model: AboutPageModel(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview-about")),
        preflight: { BridgeReadiness(ok: true, messages: ["环境就绪"]) }))
}
