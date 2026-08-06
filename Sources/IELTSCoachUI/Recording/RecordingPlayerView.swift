import AVFoundation
import Foundation
import IELTSCoachCore
import Observation
import SwiftUI

/// 训练记录页里内嵌的那个播放器：回听这一场自己是怎么说的，也能把这条录音单独删掉。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `Palette` / `Spacing` / `Radius` /
/// `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// ## 这一页有四件事是不能省的
///
/// 1. **这次本来就没录音时（`state == .none`），整段一个像素都不画。** 摆一个灰着的
///    播放器，用户只会以为程序坏了——而实际上他只是没开那个开关。
/// 2. **记录里写着有录音、文件却不在了时，必须明说。** 什么都不显示是静默失败（铁律 7）：
///    用户会以为自己记错了。所以 `.missing` 那一支把话说全，并给一颗
///    「清除这条录音记录」把这个指向去掉。
/// 3. **`AVAudioPlayer` 打不开文件时同样要说出来。** `try?` 之后一言不发的话，
///    用户看到的是一颗按下去没反应的播放键。
/// 4. **删录音要先问一声**，而且那句话要说清删了会失去什么、不会失去什么
///    （`viewModel.deleteConfirmationText`，由 `RecordingPlaybackViewModelTests` 钉着）。
///
/// **刻意不用 AVKit 的 `VideoPlayer`**：那是给视频用的，界面上会出现一块黑框。
@MainActor
public struct RecordingPlayerView: View {
    private let viewModel: RecordingPlaybackViewModel
    /// 这条录音从记录里消失之后要做的事。训练记录页拿它去 `app.reload()`——
    /// 不重读的话，行上那个「这一场有录音」的波形标记会一直留着，
    /// 用户再点一次删除，删的是一条已经不存在的录音。
    private let onRecordingRemoved: () -> Void

    /// 真正在播的那一台。放 `@State` 是因为它是这个视图自己的播放状态，
    /// 与训练数据无关；视图消失时由 `.onDisappear` 停掉。
    @State private var player = RecordingAudioPlayer()
    /// 正在等用户确认删除。非 nil 时确认框开着。
    @State private var isConfirmingDelete = false

    public init(viewModel: RecordingPlaybackViewModel,
                onRecordingRemoved: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onRecordingRemoved = onRecordingRemoved
    }

    public var body: some View {
        // 这次本来就没录音、而且没有话要对用户说时，**整段不渲染**（连标题都不要）。
        if case .none = viewModel.state, viewModel.notice == nil {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            stateBlock
            if let notice = viewModel.notice { noticeCard(notice) }
        }
        // 不停的话，切到别的记录、甚至切到别的页面，上一条录音还在响。
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var stateBlock: some View {
        switch viewModel.state {
        case .none:
            // 删完之后走到这里：播放器该消失，但上面那句「录音已删除」还得留着。
            EmptyView()
        case .missing(let message):
            missingCard(message)
        case .ready(let url):
            playerCard(url)
        }
    }

    // MARK: - 文件在，能播

    private func playerCard(_ url: URL) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这一场的录音", systemImage: "waveform")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                if let failure = player.failure {
                    // 打不开也要说清是怎么回事、下一步做什么，不许 `try?` 之后一言不发。
                    Text(failure)
                        .font(Typography.body)
                        .foregroundStyle(Palette.warning)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    transport
                }
                deleteRow
            }
        }
        // 第一次显示、以及换到另一条录音时都要重新装载。
        .onAppear { player.load(url) }
        .onChange(of: url) { _, newURL in player.load(newURL) }
    }

    /// 播放键 + 可拖动的进度条 + `当前时间 / 总时长`。
    private var transport: some View {
        HStack(spacing: Spacing.md) {
            Button {
                player.toggle()
            } label: {
                // SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.accent)
                    .padding(Spacing.xs)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control))
            .help(player.isPlaying ? "暂停" : "播放")
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            // 上限取 `max(duration, 1)`：长度读不出来（0）时 `0...0` 是个空区间，
            // 滑块会画不出来。这个 1 不是版式取值，与设计令牌无关。
            Slider(value: progress, in: 0...max(player.duration, 1))
                .tint(Palette.accent)
                .accessibilityLabel("播放进度")

            // 等宽数字：秒数每跳一下，整行都不该跟着抖（DESIGN-SYSTEM 第 1 节）。
            Text("\(Self.timeText(player.currentTime)) / \(Self.timeText(player.duration))")
                .font(Typography.secondary)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// 进度条两头都要接：读播放位置，拖动时真的跳过去。
    /// 只接读的那一头，用户拖完会看到滑块自己弹回去。
    private var progress: Binding<Double> {
        Binding(get: { player.currentTime }, set: { player.seek(to: $0) })
    }

    /// `mm:ss`。
    ///
    /// **放成 `static` 纯函数**，理由与 `HistoryView.speakerText(for:)` 一致：
    /// 扫源码只问得出「这儿画了一个时间」，问不出 65 秒会不会显示成「1:5」，
    /// 也问不出长度读不出来时会不会画出一个 `nan:nan`。
    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - 删除

    private var deleteRow: some View {
        HStack {
            Spacer(minLength: Spacing.sm)
            Button("删除录音", role: .destructive) { isConfirmingDelete = true }
                .buttonStyle(.bordered)
        }
        .confirmationDialog("删掉这一场的录音？", isPresented: $isConfirmingDelete,
                            titleVisibility: .visible) {
            // 默认焦点不给这一颗：`.cancel` 那颗才是回车/ESC 落点。
            Button("删除录音", role: .destructive) { destroy() }
            Button("取消", role: .cancel) { isConfirmingDelete = false }
        } message: {
            // **原样显示 `deleteConfirmationText`**，不要自己另写一句：
            // 那段话说清了删了会失去什么、不会失去什么，且有测试钉着。
            Text(viewModel.deleteConfirmationText)
        }
    }

    /// 删之前先把播放停掉：正在播的文件被删掉之后，`AVAudioPlayer` 会继续播它
    /// 已经读进内存的那一段，用户会看着「已删除」听着自己的声音。
    private func destroy() {
        player.stop()
        viewModel.delete()
        onRecordingRemoved()
    }

    // MARK: - 记录里有、文件不在了

    private func missingCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("这一场的录音找不到了", systemImage: "waveform.slash")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.warning)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    // 这段话里带着文件路径，要能选中复制，用户得拿它去访达里找。
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("清除这条录音记录") {
                    viewModel.clearReferenceOnly()
                    onRecordingRemoved()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func noticeCard(_ message: String) -> some View {
        CoachCard {
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 播一条本地 `.m4a`。**全工程只有这里会构造 `AVAudioPlayer`。**
///
/// 单独抽成一个 `@Observable` 类而不是一堆 `@State`，是为了让「打不开怎么办」
/// 有个明确的落点：`failure` 非 nil 时界面必须显示它。
/// 摊在视图里的话，`try?` 一下就把失败吞了，用户看到的是一颗按下去没反应的播放键。
@MainActor
@Observable
final class RecordingAudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// 文件打不开时的中文说明。非 nil 时界面必须显示。
    private(set) var failure: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var ticker: Timer?

    /// 装载一条录音。同一条重复调用是空操作——`onAppear` 会随视图重绘多次触发，
    /// 每次都重新装载的话，播到一半会自己跳回开头。
    func load(_ url: URL) {
        guard loadedURL != url else { return }
        stop()
        do {
            let opened = try AVAudioPlayer(contentsOf: url)
            opened.prepareToPlay()
            player = opened
            loadedURL = url
            duration = opened.duration
            currentTime = 0
            failure = nil
        } catch {
            player = nil
            loadedURL = nil
            duration = 0
            currentTime = 0
            failure = "这个录音文件打不开，可能已损坏（\(url.lastPathComponent)："
                + "\(error.localizedDescription)）。"
                + "下一步：点「删除录音」把它清掉，下次练习会重新录。"
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard player.play() else {
            // 播不动也要说话：静默失败会让用户以为这颗键坏了。
            failure = "这条录音播不出来（系统拒绝了播放请求，可能是音频设备正被别的程序独占）。"
                + "下一步：先关掉正在用麦克风或扬声器的其他程序，再点一次播放键；"
                + "还是不行的话，到「录音设置」（⌘,）点「打开录音文件夹」，在访达里直接播这个文件。"
            isPlaying = false
            return
        }
        isPlaying = true
        startTicking()
    }

    /// 拖动进度条。
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// 停掉并回到开头。视图消失、删录音之前都要调。
    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
    }

    /// 心跳：把播放位置同步到界面，并在播完时把播放键弹回去。
    ///
    /// 0.2 秒一次——再快看不出差别，再慢进度条会一跳一跳。
    /// 只在播放时跑，暂停/停止时立刻停掉，不让它在后台空转。
    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncTime() }
        }
    }

    private func syncTime() {
        guard let player else { return }
        currentTime = player.currentTime
        guard !player.isPlaying else { return }
        // 播完了。回到开头，下一次点播放从头再听一遍。
        stop()
    }
}
