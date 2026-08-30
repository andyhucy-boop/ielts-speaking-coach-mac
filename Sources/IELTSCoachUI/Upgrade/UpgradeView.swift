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

    /// 哪几条更新记录是展开的。初始值由 `Changelog.defaultExpandedVersions()` 给，
    /// 规则本身（只展开最新那一条）写在那里，有测试拿两条以上的记录问着。
    @State private var expandedVersions: Set<String>

    public init(metadata: AppMetadata = .current) {
        self.metadata = metadata
        _expandedVersions = State(initialValue: Changelog.defaultExpandedVersions())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                versionNoticeLine
                SectionHeader(number: 1, label: "RELEASE NOTES", title: "每一版改了什么")
                releasesSection
                SectionHeader(number: 2, label: "PHASES", title: "十个阶段走到哪儿了")
                phasesSection
            }
            .coachPageBody()
        }
        .background(Palette.canvas)
        .font(Typography.body)
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
    UpgradeView(metadata: AppMetadata(
        displayName: "IELTS Speaking Coach",
        bundleIdentifier: "com.ielts.speakingcoach",
        shortVersion: Changelog.current.version,
        buildNumber: "1",
        buildCommit: "a1b2c3d",
        buildDate: "2026-08-06T09:00:00Z",
        signingIdentity: "IELTS Coach Dev",
        channel: .selfSigned))
}
