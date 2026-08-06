import AppKit
import IELTSCoachCore
import SwiftUI

/// 设置窗口（⌘,）里的「录音」那一页。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `SectionHeader`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// ## 这一页有三件事是不能省的
///
/// 1. **开关的取值只从 `viewModel.enabled` 来，本视图不另存一份 `@State`。**
///    另存一份的后果是界面显示成「开」而 `state.json` 里是关的——用户练完发现没录音，
///    而界面从头到尾都在告诉他录着呢。这正是本任务最要紧的那条测试
///    （`testTheSwitchStaysOffWhenThePermissionIsRefused`）守的东西，
///    在视图里再存一份就等于把它绕过去。
/// 2. **权限被拒 / 被限制时必须给一条能点的出路。** macOS 一个 App 一辈子只为麦克风弹一次
///    系统对话框，拒过之后再点开关什么都不会发生——没有这颗「打开系统设置」，
///    用户就只能对着一个永远不出现的弹窗干等。
/// 3. **只录自己、不录 ChatGPT** 这句话必须写在页面上。那是产品取舍
///    （`DEFINITION-OF-DONE.md` 第 4 节），用户有权知道自己的录音里没有考官的声音。
///
/// `openURL` / `revealFolder` 做成参数而不是直接调 `NSWorkspace`，理由与
/// `PermissionGateView` 一致：这两下都可能失败（URL scheme 系统不认、文件夹还没建出来），
/// 而 `NSWorkspace.open` 的返回值丢掉不会有任何编译警告，用户看到的就是一颗「点了没反应」
/// 的按钮——铁律 7 里说的静默失败。抽成参数之后，失败路径至少写得出、也说得清下一步。
@MainActor
public struct RecordingSettingsView: View {
    private let viewModel: RecordingSettingsViewModel
    /// 真正去打开系统设置的那一下。返回是否成功。
    private let openURL: (URL) -> Bool
    /// 真正去 Finder 里显示录音文件夹的那一下。文件夹不在时返回 false。
    private let revealFolder: (URL) -> Bool

    /// 点「打开系统设置」「打开录音文件夹」之后的反馈，只在失败时有话说。
    /// 放 `@State` 是可以的：这两颗按钮不换屏，视图不会被销毁重建。
    @State private var actionNotice: String?

    public init(viewModel: RecordingSettingsViewModel,
                openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
                revealFolder: @escaping (URL) -> Bool = { url in
                    // 文件夹不在就别装作打开了：Finder 会一声不响地什么都不做。
                    guard FileManager.default.fileExists(atPath: url.path) else { return false }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return true
                }) {
        self.viewModel = viewModel
        self.openURL = openURL
        self.revealFolder = revealFolder
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                recordingSection
                usageSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.xl)
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Palette.canvas)
    }

    // MARK: - 01 录音开关

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 区块标题与开关标题刻意不同字：同一句话连着出现两遍会让人以为是重复渲染。
            SectionHeader(number: 1, label: "RECORDING", title: "练习录音")
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    toggle
                    Text("默认关闭。打开之后，练习时你说的话会存成一个 m4a 文件，"
                         + "只存在这台电脑上，不上传任何地方，可以随时逐条删掉。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // 产品取舍（成品标准第 4 节），用户有权知道。
                    Text("本工具只录你自己的麦克风，不录 ChatGPT 的声音。"
                         + "考官问了什么，看训练记录里的逐字稿。")
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.consentText)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let notice = viewModel.notice { noticeCard(notice) }
            if let actionNotice { noticeCard(actionNotice) }
            if needsSystemSettings { systemSettingsCard }
        }
    }

    /// 开关两头都要接：读 `viewModel.enabled`，写 `viewModel.setEnabled(_:)`。
    /// **中间不许有第二份状态**（理由见类型上的说明）。
    private var toggle: some View {
        Toggle("保存我的回答录音", isOn: Binding(
            get: { viewModel.enabled },
            set: { turnOn in Task { await viewModel.setEnabled(turnOn) } }))
            .toggleStyle(.switch)
            .font(Typography.cardTitle)
            .foregroundStyle(Palette.textPrimary)
            // 正在等系统权限对话框时禁用，避免连点弹出好几次请求。
            .disabled(viewModel.isWorking)
    }

    /// 权限被拒或被系统策略限制时，界面上必须有一条能点的出路。
    private var needsSystemSettings: Bool {
        viewModel.permission == .denied || viewModel.permission == .restricted
    }

    private var systemSettingsCard: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("麦克风权限不在本应用手里", systemImage: "mic.slash")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.warning)
                Text(viewModel.permission.guidance ?? "")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // `.restricted` 时这颗按钮也留着：那一栏里用户自己看得到是谁把它锁上的，
                // 比只读一句「你改不了」强。
                Button("打开系统设置") { openSystemSettings() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 02 磁盘占用

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(number: 2, label: "DISK USAGE", title: "录音占了多少地方")
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // 等宽数字：占用从 9 个跳到 12 个时，整行不该跟着抖。
                    Text(viewModel.usage.summaryText)
                        .font(Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let orphanNotice = viewModel.orphanNotice {
                        Text(orphanNotice)
                            .font(Typography.body)
                            .monospacedDigit()
                            .foregroundStyle(Palette.warning)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("打开录音文件夹") { openRecordingsFolder() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 两颗按钮真正干活的那一下

    private func openSystemSettings() {
        guard let url = URL(string: MicrophonePermissionState.systemSettingsURLString),
              openURL(url) else {
            actionNotice = "没能替你打开系统设置（这台电脑不认这个设置页链接）。"
                + "下一步：自己打开「系统设置 › 隐私与安全性 › 麦克风」，"
                + "把「IELTS Speaking Coach」那一项打开，再回到这里拨一次上面的开关。"
            return
        }
        actionNotice = nil
    }

    private func openRecordingsFolder() {
        guard revealFolder(viewModel.recordingsFolderURL) else {
            actionNotice = "还没有录音文件夹（\(viewModel.recordingsFolderURL.path)），"
                + "所以没什么可打开的——第一次真的录到东西时它才会建出来。"
                + "下一步：把上面的开关打开、练一场，再回来看。"
            return
        }
        actionNotice = nil
    }

    private func noticeCard(_ message: String) -> some View {
        CoachCard {
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                // 文字可选中：这几段话里带着路径和权限项的名字，用户要能复制走。
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
