import AppKit
import ChatGPTBridge
import IELTSCoachCore
import Observation
import SwiftUI

/// 「问题反馈」页背后的那份数据与那三个动作。
///
/// ## 为什么这一页要有一个模型，而不是把逻辑全塞进 `View`
///
/// 计划 Task 18 的 Step 5 只给了一张验收表，没给测试步骤。而这一页上真正会出错的三件事
/// （写剪贴板失败、打开访达失败、诊断文本里带了不该带的东西）在 `View` 里全都测不到——
/// `swift test` 不画界面。关于页（Task 6/7）为同一个原因把逻辑收在 `AboutPageModel` 里，
/// 这里照做，好让 `FeedbackViewTests` 能真的把这三件事各跑一遍。
///
/// ## 这一页绝不做的两件事
///
/// **一、不自动发送任何东西。** 没有提交按钮、没有邮件、没有网络请求，
/// 连一个「去提 issue」的外链都没有——放了就等于替用户决定了这段话发去哪儿。
/// `Tests/PackagingTests/FeedbackPrivacyContractTests` 扫这个目录的源码守着。
///
/// **二、诊断信息里不放任何练习内容。** 逐字稿、错题原句、词汇、姓名由 Task 5 的
/// `DiagnosticsReport` 守着；本页新增的「最近一次错误」只记阶段、代号与时间，
/// 一个字的错误原文都不记（见 `LastErrorLog`）。
@MainActor
@Observable
public final class FeedbackPageModel {
    /// 按钮点完之后的一句反馈。**成功也要说话**：只在失败时才出声的话，
    /// 用户分不清「成功了」和「点了没反应」。
    public private(set) var notice: ActionNotice?
    /// 数据目录占了多少地。**懒得测**：`DataUsage.measure` 要走一遍整个目录，
    /// 放在 `body` 里算会让每次重绘都扫一次磁盘。进页面时测一次，点「重新检查环境」再测一次。
    public private(set) var usage: DataUsageReport?

    private let app: AppState
    private let log: LastErrorLog
    private let directory: DataDirectory
    private let metadata: AppMetadata
    private let systemVersion: String
    private let reveal: (URL) -> Bool
    private let writeToPasteboard: (String) -> Bool

    public init(app: AppState,
                log: LastErrorLog = .shared,
                directory: DataDirectory = .resolve(),
                metadata: AppMetadata = .current,
                systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                reveal: @escaping (URL) -> Bool = AboutPageModel.revealInFinder,
                writeToPasteboard: @escaping (String) -> Bool = AboutPageModel.copyToPasteboard) {
        self.app = app
        self.log = log
        self.directory = directory
        self.metadata = metadata
        self.systemVersion = systemVersion
        self.reveal = reveal
        self.writeToPasteboard = writeToPasteboard
    }

    /// 数据目录的绝对路径。界面上要显示它——用户得知道「打开数据目录」会把他带到哪儿。
    public var dataDirectoryPath: String { directory.root.path }

    /// 最近一次错误。**只有阶段、代号、时间。**
    public var lastError: DiagnosticsError? { log.last }

    /// 还没出过错时页面上那两句话。**不能留白**：一片空白会让用户以为这一块坏了。
    public static let noErrorYet = "最近没有出错。"
    public static let noErrorNextStep =
        "下一步：出问题的时候再回到这一页，把上面这段复制出去。"

    /// 这一页的产品承诺，逐字。
    public static let promise =
        "这一页不会把任何东西发到任何地方。复制之后要粘给谁、发不发，全由你决定。"

    /// 这段文字里到底有什么、没有什么。
    public static let privacyNote =
        "这段文字里只有版本、系统、数据目录与错误代号，没有你说过的英语、没有题目、没有姓名。"

    /// 要复制出去的那段话。
    ///
    /// **走统一的 `DiagnosticsReport.text(_:)`，不自己再拼一份。**
    /// 自己拼的话，Task 5 那些「不许带练习内容」的测试就管不到它了。
    ///
    /// 读盘失败时要专门说一句：那时 `app.state` 是启动时那份（或空的），
    /// 里面「题库 0 题 · 练习记录 0 次」会被收到这段话的人当成真实数字。
    public var diagnosticsText: String {
        var text = DiagnosticsReport.text(DiagnosticsInput(
            metadata: metadata,
            dataDirectory: directory.root,
            systemVersion: systemVersion,
            permission: app.permission,
            state: app.state,
            // 与关于页同一份审计（连磁盘上那几个文件在不在也查），
            // 两处用不同的重载会给出两个不同的数字，而它们叫同一个名字。
            portabilityFindingCount: DataPortabilityAudit.audit(state: app.state,
                                                                directory: directory).count,
            usage: usage,
            // **查完之前传 `nil`，不是传那个空数组**：空数组的含义是
            // 「查过了却一条输出都没有」，那不正常；而查完之前它只是「还没查」。
            // 两者混成一件事的话，这段要转发给别人的文字会从一个假线索起头
            // （关于页此前就是这么写的，2026-08-08 复审修）。
            environmentMessages: app.hasCheckedEnvironment ? app.permissionMessages : nil,
            lastError: log.last))
        if let loadError = app.loadError {
            text += "\n注：读不到训练数据，所以上面「数据量」与「数据可搬迁检查」两行是占位值，"
                + "不是真实数字。读盘失败的原文是：\(loadError)"
        }
        return text
    }

    /// 量一次数据目录。进页面时调一次，点「重新检查环境」之后再调一次。
    public func refreshUsage() {
        usage = DataUsage.measure(directory: directory)
    }

    /// 「复制诊断信息」。**只把文字放进剪贴板，一个字节都不往外发**——
    /// 送到哪儿去是用户自己粘贴时才决定的事。
    public func copyDiagnostics() {
        guard writeToPasteboard(diagnosticsText) else {
            notice = ActionNotice(
                text: "没能把诊断信息写进剪贴板（多半是别的程序正占着它）。"
                    + "下一步：直接在上面那段文字里选中，按 ⌘C 复制。",
                isFailure: true)
            return
        }
        notice = ActionNotice(
            text: "已复制。这段文字现在在你的剪贴板里，粘给谁、发不发由你决定。",
            isFailure: false)
    }

    /// 「重新检查环境」：再跑一次 preflight，并把数据目录占用重新量一次。
    ///
    /// **注意这一下会把整个窗口换成「正在检查运行环境…」约九秒**：
    /// `AppState.isCheckingPermission` 是 `RootRouter` 切屏的依据，而检查要启动 ChatGPT
    /// 并等它的无障碍树醒过来（实测约九秒）。查完回到这一页时，页面是全新的一份，
    /// 上一次点按钮留下的那句反馈不会跟过来——那九秒里屏幕上一直有进度提示，
    /// 所以用户不会以为死机，只是别指望在这里再看到「已复制」。
    public func recheckEnvironment() async {
        await app.recheckPermission()
        refreshUsage()
    }

    /// 「打开数据目录」。
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
}

/// 「问题反馈」页本体：**把环境凑成一段话，一键复制。发给谁由你决定。**
///
/// 布局遵 DESIGN-SYSTEM：页面内边距 `Spacing.xl`、卡片用 `CoachCard`、
/// 区块用 `SectionHeader`、图标一律 SF Symbols（不用 emoji）、颜色字号圆角一律走令牌。
///
/// 整页只有一个主行动（「复制诊断信息」），另外两颗按钮在视觉上明确次一级。
@MainActor
public struct FeedbackView: View {
    @State private var model: FeedbackPageModel
    /// 「重新检查环境」正在跑。**读 `app` 而不是自己记一个**：
    /// 检查是 `AppState` 在跑的，两份状态一定会走岔。
    private let app: AppState

    /// 生产入口。`RootView` 走的就是这一个。
    public init(app: AppState,
                log: LastErrorLog = .shared,
                directory: DataDirectory = .resolve()) {
        self.init(model: FeedbackPageModel(app: app, log: log, directory: directory), app: app)
    }

    /// 注入用的那一个（测试与预览）。**预览必须走它**：上面那个默认会在用户真实的
    /// 「应用程序支持」目录里量文件（见 `PreviewSafetyTests` 说的同一类问题）。
    init(model: FeedbackPageModel, app: AppState) {
        _model = State(wrappedValue: model)
        self.app = app
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                SectionHeader(number: 1, label: "DIAGNOSTICS", title: "要复制的就是下面这段")
                diagnosticsCard
                actions
                if let notice = model.notice { noticeLine(notice) }
                privacyNote
                SectionHeader(number: 2, label: "LAST ERROR", title: "最近一次出错")
                lastErrorCard
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .font(Typography.body)
        // 进页面量一次数据目录。放在 `body` 里算的话，每次重绘都会扫一遍磁盘。
        .task { model.refreshUsage() }
    }

    /// 顶上那块。**第二行那句话是这一页的产品承诺，逐字**：
    /// 用户点进「问题反馈」时最先想知道的就是「这玩意儿会不会把我的东西发出去」。
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("问题反馈")
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(FeedbackPageModel.promise)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 诊断信息全文。**必须可选中**：剪贴板被别的程序占住时，
    /// 「自己选中按 ⌘C」是那句失败提示给出的下一步，选不中就等于那句话指向空气。
    private var diagnosticsCard: some View {
        CoachCard {
            Text(model.diagnosticsText)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 三颗按钮。主行动只有一个（「复制诊断信息」），另外两颗明确次一级。
    ///
    /// 检查那九秒里「重新检查环境」被 `.disabled` 挡住，防止连点排队。
    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Button("复制诊断信息") { model.copyDiagnostics() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                Button("重新检查环境") { Task { await model.recheckEnvironment() } }
                    .disabled(app.isCheckingPermission)
                Button("打开数据目录") { model.revealDataDirectory() }
            }
            Text("数据目录：\(model.dataDirectoryPath)")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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

    /// 这段文字里有什么、没有什么。**摆在按钮旁边而不是页尾**：
    /// 用户是在按下「复制」之前需要知道这件事的。
    private var privacyNote: some View {
        Label(FeedbackPageModel.privacyNote, systemImage: "lock.shield")
            .font(Typography.secondary)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 最近一次错误。**没出过错时也要写字**，不能是一块空白
    /// （DESIGN-SYSTEM 第 4 节：空白会让用户以为程序坏了）。
    private var lastErrorCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let error = model.lastError {
                    Text(error.summary)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("只记了「什么时候、在做什么、错误代号」三样。"
                         + "错误原文一个字都没记——原文里可能夹着复盘片段，而那里全是你说过的英语。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(FeedbackPageModel.noErrorYet)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Text(FeedbackPageModel.noErrorNextStep)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 预览注入临时目录与假 preflight，不碰用户真实的训练数据、也不启动 ChatGPT
/// （见 `PreviewSafetyTests`）。
#Preview("问题反馈") {
    let directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ielts-coach-preview-feedback"))
    let app = AppState(directory: directory,
                       preflight: { BridgeReadiness(ok: true, messages: ["✅ 环境就绪（预览用的假结果）"]) })
    return FeedbackView(model: FeedbackPageModel(app: app,
                                                 log: LastErrorLog(),
                                                 directory: directory,
                                                 reveal: { _ in true },
                                                 writeToPasteboard: { _ in true }),
                        app: app)
}
