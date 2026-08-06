import IELTSCoachAudio
import IELTSCoachCore
import SwiftUI

/// 组装真实依赖。视图模型本身不知道 `DataDirectory` 从哪来，因此可测。
///
/// **这一页有它自己的 `StateStore`，不经过 `AppState`。** 设置窗口（⌘,）是独立场景，
/// 拿不到主窗口那份状态；反过来，用户在这里拨了开关之后，主窗口那份 `AppState` 里
/// 的设置就是旧的——所以 `AppState.makePracticeRunner()` 在开练前会先 `reload()` 一次
/// （Task 7b 接线规则第 2 条）。两处的分工写在这儿，免得以后有人「顺手」把这一页
/// 接回 `AppState` 时把那次 reload 一起删掉。
@MainActor
public struct RecordingSettingsScene: View {
    @State private var viewModel: RecordingSettingsViewModel

    public init(directory: DataDirectory = .resolve()) {
        _viewModel = State(wrappedValue: RecordingSettingsViewModel(
            store: StateStore(directory: directory),
            recordings: RecordingStore(directory: directory),
            // 只查状态、不弹窗：构造它和调 `currentStatus()` 都不会打扰用户，
            // 真正会弹系统对话框的只有 `requestAccess()`，那由用户拨开关才触发。
            authorizer: SystemMicrophoneAuthorizer()))
    }

    public var body: some View {
        RecordingSettingsView(viewModel: viewModel)
            // 每次打开设置窗口都重读一遍磁盘：占用是练习时长出来的，
            // 停在打开 App 那一刻的数字等于在骗人。
            .onAppear { viewModel.refresh() }
            // 这两句是这一页的底子，不是装饰：设置窗口默认吃系统窗口底色和 SwiftUI 默认字体，
            // 而这一页里的 `CoachCard` 是白底——白卡片压在白窗口上会糊成一片，
            // 分层就全靠那道发丝边框了。底色统一到内容区的 `Palette.canvas`，
            // 正文档位统一到字体表里的 `.body`，与主窗口各页一致。
            .background(Palette.canvas)
            .font(Typography.body)
    }
}

/// 预览注入临时目录，不碰用户真实的训练数据（见 `PreviewSafetyTests`）。
#Preview("录音设置") {
    RecordingSettingsScene(
        directory: DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-coach-preview-recording-settings")))
}
