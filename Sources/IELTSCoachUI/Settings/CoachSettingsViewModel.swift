import Foundation
import IELTSCoachCore
import Observation

/// 设置窗口里除录音之外的三个分区。
///
/// **所有取值都是从 `app.state` 直接读的计算属性，一个都不缓存。**
/// 这不是风格，是「两个窗口不可能不同步」的机制本身：只要这里自己存一份，
/// 「设置窗口改了、主窗口还显示旧值」就从「不会发生」退化成
/// 「只要有人忘了刷新就会发生」——而这种 bug 在本机永远复现不了，
/// 因为你改完总会顺手看一眼那个窗口。
///
/// 录音那一格不在这里：它必须先申请麦克风权限，那套逻辑在 Phase 5 的
/// `RecordingSettingsViewModel` 里，本窗口原样嵌用，不重写。
@MainActor
@Observable
public final class CoachSettingsViewModel {
    /// 写盘失败时的中文说明（发生了什么 + 下一步）。
    /// **非 nil 时界面必须显示。** 静默失败会让用户以为改好了，
    /// 下次打开发现又变回去，而且永远不知道为什么（铁律 7）。
    public private(set) var error: String?
    public private(set) var usage = DataUsageReport(totalBytes: 0, stateBytes: 0, reportBytes: 0,
                                                    recordingBytes: 0, pendingReviewBytes: 0,
                                                    fileCount: 0)

    private let app: AppState
    private let directory: DataDirectory

    public init(app: AppState, directory: DataDirectory = .resolve()) {
        self.app = app
        self.directory = directory
        refreshUsage()
    }

    // MARK: - 读（一律现读，不缓存）

    public var weeklyGoal: Int { app.state.settings.weeklyGoal }
    public var defaultRoute: PracticeRoute {
        PracticeRoutePreference.route(fromSettings: app.state.settings.defaultRoute)
    }
    public var feedbackTiming: FeedbackTiming { app.state.settings.feedbackTiming }
    public var part2PrepMode: Part2PrepMode { app.state.settings.part2PrepMode }
    public var transcriptEnabled: Bool { app.state.settings.transcriptEnabled }
    public var dataDirectoryURL: URL { directory.root }

    /// 「本周已经练了 N 次，离目标还差 M 次」。文案来自 Phase 7 的 `WeeklyGoalEditor`，
    /// 不在这里另写一句——两处迟早会说不一样的话。
    public var weeklyGoalHint: String {
        WeeklyGoalEditor.hint(done: TodayViewModel(state: app.state).weekProgress.done,
                              goal: weeklyGoal)
    }

    // MARK: - 写（一律走 AppState.mutate，改完立刻可见）

    public func setWeeklyGoal(_ raw: Int) {
        let normalized = CoachSettings.normalized(raw)
        apply { $0.settings.weeklyGoal = normalized }
    }

    public func setDefaultRoute(_ route: PracticeRoute) {
        let raw = PracticeRoutePreference.rawValue(for: route)
        apply { $0.settings.defaultRoute = raw }
    }

    public func setFeedbackTiming(_ value: FeedbackTiming) {
        apply { $0.settings.feedbackTiming = value }
    }

    public func setPart2PrepMode(_ value: Part2PrepMode) {
        apply { $0.settings.part2PrepMode = value }
    }

    /// 「记录对话逐字稿」（Phase 4 Task 2 的字段，默认开）。
    /// **这里是它唯一的写入口**——Task 16 会把 `AppState.setTranscriptEnabled` 删掉。
    public func setTranscriptEnabled(_ value: Bool) {
        apply { $0.settings.transcriptEnabled = value }
    }

    public func refreshUsage() {
        usage = DataUsage.measure(directory: directory)
    }

    /// 逐字段赋值，**不整体替换 `settings`**。
    /// `CoachSettings` 被 Phase 5 / 7 / 8 各加过字段，整体替换的写法
    /// 很容易把别人的字段顺手清成默认值，而且一声不吭。
    private func apply(_ change: (inout CoachState) -> Void) {
        if let failure = app.mutate({ change(&$0) }) {
            error = failure
        } else {
            error = nil
        }
    }
}
