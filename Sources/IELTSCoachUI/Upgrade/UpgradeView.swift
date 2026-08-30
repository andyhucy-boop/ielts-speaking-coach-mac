import AppKit
import IELTSCoachCore
import SwiftUI

/// 阶段状态在界面上长什么样。
///
/// **颜色一律取自 `Palette`，图标一律用 SF Symbols**（规范第 4 节明禁 emoji：
/// emoji 在不同系统版本渲染不一致，也不会跟着语义颜色走）。
///
/// 放在这里而不是 `Changelog.swift` 里：那边是一张只讲事实的表，
/// 「已完成用什么颜色」是界面的事。
extension PhaseStatus {
    /// 状态色。三种状态各有各的颜色——共用一个的话，那一列只是把文字重复了一遍。
    var tint: Color {
        switch self {
        case .shipped: return Palette.success
        case .inProgress: return Palette.accent
        case .planned: return Palette.textSecondary
        }
    }

    /// 状态图标。名字打错不会报错，只会渲染成空白，
    /// 所以 `UpgradeViewTests` 里当场问系统认不认这几个名字。
    var symbol: String {
        switch self {
        case .shipped: return "checkmark.circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .planned: return "circle"
        }
    }
}

/// 「功能升级」页：**你手上这份是哪一版、每一版改了什么、十个阶段走到哪儿了。**
///
/// 三块内容全部来自 `Changelog` 那张手工维护的常量表和 `AppMetadata`，
/// 运行时不读 git、也不走 SPM 资源包（理由见 `Changelog` 的类型注释）。
///
/// **在 `swift run IELTSCoachApp` 下跑时，顶上那行版本会显示「未知（开发运行）」**——
/// 那不是 bug：直接跑没有 App bundle，`Bundle.main.infoDictionary` 是 nil。
/// 这一页会为此单独说一句话（`versionNoticeLine`），免得看着像坏了。
@MainActor
public struct UpgradeView: View {
    private let metadata: AppMetadata
    /// 打开发布页。**做成参数而不是直接调 `NSWorkspace`**，理由与
    /// `RecordingSettingsView` 一致：测试不能真去开浏览器；而且它的返回值要接住——
    /// `NSWorkspace.open` 返回 false 时不吭声的话，用户看到的是一颗「点了没反应」的按钮。
    private let openURL: (URL) -> Bool

    /// 哪几条更新记录是展开的。初始值由 `Changelog.defaultExpandedVersions()` 给，
    /// 规则本身（只展开最新那一条）写在那里，有测试拿两条以上的记录问着。
    @State private var expandedVersions: Set<String>

    /// 有没有新版本。**默认值会真的发一次网络请求**（每天最多一次），
    /// 所以预览与测试必须自己传一个假的进来。
    @State private var updates: UpdateCheckViewModel

    /// 打不开发布页时那句话。**不能什么都不做**：点了浏览器没起来，
    /// 用户只会以为程序坏了（禁止静默失败）。
    @State private var openFailure: String?

    public init(metadata: AppMetadata = .current,
                updates: UpdateCheckViewModel? = nil,
                openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.metadata = metadata
        self.openURL = openURL
        _expandedVersions = State(initialValue: Changelog.defaultExpandedVersions())
        _updates = State(initialValue: updates ?? .live)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                versionNoticeLine
                updateCard
                SectionHeader(number: 1, label: "RELEASE NOTES", title: "每一版改了什么")
                releasesSection
                SectionHeader(number: 2, label: "PHASES", title: "十个阶段走到哪儿了")
                phasesSection
            }
            .coachPageBody()
        }
        .background(Palette.canvas)
        .font(Typography.body)
        // 打开这一页时自动查一次（每天最多一次，见 `UpdateCheckSchedule`）。
        // **不能每次打开都查**：GitHub 对匿名请求每小时只给 60 次，
        // 打满之后返回 403——于是这个功能在最需要它的时候恰好是坏的。
        .task { await updates.checkIfDue(localVersion: metadata.shortVersion) }
    }

    // MARK: - 有没有新版本

    /// **只检测，不自动装。**
    ///
    /// 这块告诉你有没有新版本、并把发布页打开；它不会自己下载，更不会自己替换 App。
    /// 自动装要么得引入 Sparkle 那一套（还要一对签名密钥），要么就是让程序去下载并执行
    /// 一个来自网络的二进制——后者在本项目是明令不做的一类操作。
    /// 换包是十秒钟的事，而「App 会自己改自己」值得用户自己点一下头。
    private var updateCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Text("检查有没有新版本")
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    if updates.isChecking {
                        // 超过 300ms 的操作都要有反馈（规范第 5 节）。
                        ProgressView().controlSize(.small)
                        Text("正在问 GitHub…")
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                // 还没查过时这里是 nil，界面上只有一颗按钮——
                // 「还没查」和「查过、没有新版本」不能长得一样。
                if let message = updates.message {
                    Text(message)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .coachParagraph()
                        .coachReadingColumn()
                }

                HStack(spacing: Spacing.sm) {
                    Button("检查更新") {
                        Task { await updates.check(localVersion: metadata.shortVersion) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(updates.isChecking)

                    // 查失败时**也**给这颗按钮：那时用户最需要的就是自己去看一眼。
                    //
                    // 两支分开写，不写成 `.buttonStyle(x ? .a : .b)`：那两个样式不是同一个类型，
                    // 三元表达式编不过。顺带也让两句按钮文字都以字面量留在源码里，
                    // `RenderReachabilitySweepTests` 要靠那份清单核对文案里指名的控件。
                    if updates.hasUpdate {
                        Button("去 GitHub 看这一版") { openReleasePage() }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                    } else {
                        Button("打开发布页") { openReleasePage() }
                            .buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                }

                if let openFailure {
                    NoticeCard(.warning, openFailure)
                }
            }
        }
    }

    /// 打开发布页。**返回值要接住**——`NSWorkspace.open` 返回 false 时不吭声的话，
    /// 用户看到的是一颗点了没反应的按钮。
    private func openReleasePage() {
        openFailure = openURL(updates.pageURL) ? nil
            : "打不开浏览器。下一步：自己在浏览器里打开 \(updates.pageURL.absoluteString)"
    }

    /// 顶上那块：这一页存在的全部意义就是回答「我手上这份到底是哪一版」。
    ///
    /// **版本号一个字都不许写死。** 写死的话下一版发出去它就是错的，而且毫无迹象。
    /// 构建时间与提交号也要有：两份同样标着 1.0.0 的 App，靠它们才分得出谁是谁。
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("功能升级")
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("当前版本 \(metadata.versionLine)")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
            Text("构建时间 \(metadata.buildDate) · 提交 \(metadata.buildCommit)")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 顶上那行版本和更新记录最新一条对不上时的那句解释。
    ///
    /// 对得上时 `versionNotice` 返回 nil，这里就一个像素都不画——
    /// 一直挂着的提示等于没有提示。
    @ViewBuilder private var versionNoticeLine: some View {
        if let notice = Changelog.versionNotice(runningShortVersion: metadata.shortVersion) {
            Label(notice, systemImage: "info.circle")
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var releasesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Changelog.releases) { release in releaseCard(release) }
        }
    }

    /// 一条更新记录：版本号、日期、一句话概括，展开后是逐条改动。
    ///
    /// 收起来的时候仍然看得见概括那一句——**折叠的是细节，不是信息本身**。
    private func releaseCard(_ release: ReleaseNote) -> some View {
        CoachCard {
            DisclosureGroup(isExpanded: expansion(of: release.version)) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(release.changes, id: \.self) { change in changeLine(change) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Spacing.sm)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(release.version)
                            .font(Typography.cardTitle)
                            .foregroundStyle(Palette.textPrimary)
                        Text(release.date)
                            .font(Typography.label)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(release.headline)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Palette.accent)
        }
    }

    private func changeLine(_ change: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "circle.fill")
                .imageScale(.small)
                .foregroundStyle(Palette.accent)
            Text(change)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phasesSection: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Changelog.phases) { phase in phaseRow(phase) }
            }
        }
    }

    /// 一个阶段：编号、标题、状态，以及**它给你带来了什么**。
    ///
    /// `summary` 不能省：只列一串阶段名，对使用这个 App 的人等于没写。
    private func phaseRow(_ phase: PhaseMilestone) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("Phase \(phase.label)")
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                Text(phase.title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.sm)
                Label(phase.status.title, systemImage: phase.status.symbol)
                    .font(Typography.label)
                    .foregroundStyle(phase.status.tint)
            }
            Text(phase.summary)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 某一条更新记录展开与否。`DisclosureGroup` 要的是 `Binding<Bool>`，
    /// 而这一页记的是「哪几条展开着」，所以在这里转一道。
    private func expansion(of version: String) -> Binding<Bool> {
        Binding(get: { expandedVersions.contains(version) },
                set: { isExpanded in
                    if isExpanded {
                        expandedVersions.insert(version)
                    } else {
                        expandedVersions.remove(version)
                    }
                })
    }
}

/// 预览注入一份假的 `AppMetadata`：不带参数的那一个读 `Bundle.main`，
/// 在画布里拿到的是 Xcode 自己的版本信息，看不出这一页真实的样子。
///
/// 版本号取自 `Changelog.current`，**不写字面值**：这一页里任何一处写死的版本号，
/// 下一版发出去就是错的（`UpgradeViewTests` 连预览一起扫）。
#Preview("功能升级") {
    // **必须传一个假的进来。** 默认的 `UpdateCheckViewModel()` 用的是
    // `LiveReleaseFetcher`，打开画布就会真去 GitHub 发一次请求（铁律 5：
    // 预览不许碰真实的外部世界）。`PreviewSafetyTests` 扫源码守着这一条。
    UpgradeView(metadata: AppMetadata(
        displayName: "IELTS Speaking Coach",
        bundleIdentifier: "com.ielts.speakingcoach",
        shortVersion: Changelog.current.version,
        buildNumber: "1",
        buildCommit: "a1b2c3d",
        buildDate: "2026-08-06T09:00:00Z",
        signingIdentity: "IELTS Coach Dev",
        channel: .selfSigned),
        updates: UpdateCheckViewModel(fetcher: FixedReleaseFetcher.upToDate,
                                      store: InMemoryUpdateCheckStore()),
        openURL: { _ in true })
}
