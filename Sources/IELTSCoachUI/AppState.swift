import ChatGPTBridge
import Foundation
import IELTSCoachCore
import Observation

/// 全局状态容器：持有训练数据与环境检查结论，界面只读它。
@MainActor
@Observable
public final class AppState {
    public private(set) var state: CoachState = .empty()
    public private(set) var permission: PermissionState = .unknown
    public private(set) var permissionMessages: [String] = []
    /// 环境检查还没出结论。**初值是 true**：一次都还没查过时，`permission` 里的 `.unknown`
    /// 不是结论而是「不知道」，照它渲染会让用户开机第一眼看到「环境检查没通过」。
    public private(set) var isCheckingPermission = true
    /// 读取训练数据失败时的中文说明。非 nil 时界面必须显示它——
    /// 静默失败会让用户以为自己的练习记录没了。
    public private(set) var loadError: String?
    public var permissionSkipped = false

    private let directory: DataDirectory
    private let store: StateStore
    private let preflight: @Sendable () -> BridgeReadiness
    /// 首次环境检查是否已经发起过。见 `startInitialPermissionCheckIfNeeded()`。
    private var didStartInitialCheck = false

    /// 生产环境真正用的那一份检查：驱动真实的辅助功能接口。
    /// 单元测试一律注入假实现，不接触真实 ChatGPT。
    nonisolated public static let livePreflight: @Sendable () -> BridgeReadiness = {
        let access = LiveAXAccess()
        return AXDriver(access: access, locator: AXLocator(access: access)).preflight()
    }

    public init(directory: DataDirectory = .resolve(),
                preflight: @escaping @Sendable () -> BridgeReadiness = AppState.livePreflight) {
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.preflight = preflight
        // 这里只读本地磁盘（毫秒级）。环境检查**不在**构造函数里做，见下面两个方法的说明。
        reload()
    }

    public func reload() {
        do {
            state = try store.load()
            loadError = nil
        } catch {
            loadError = Self.describeLoadFailure(error, stateFile: directory.stateFile)
        }
    }

    /// 打开界面后的第一次环境检查。**重复调用只会真查一次。**
    ///
    /// 这道闸不能省：调用点是 `RootView` 的 `.task`，而 `.task` 会随视图切换重新触发。
    /// 没有它就是死循环——查完 → 换屏 → 又触发检查 → `isCheckingPermission` 变回 true
    /// → 换回等待屏 → 再查。用户看到的是一个永远转圈的窗口。
    public func startInitialPermissionCheckIfNeeded() async {
        guard !didStartInitialCheck else { return }
        didStartInitialCheck = true
        await recheckPermission()
    }

    /// 重新检查运行环境。用户点「重新检查」时**必须**真的再查一次，所以这里没有闸。
    ///
    /// 检查放在主线程之外跑：`preflight()` 会启动 ChatGPT，并最多轮询 8 秒等它的无障碍树
    /// 醒过来（`LiveAXAccess.wakeAccessibilityTree`）。放在主线程上等于让窗口冻住十秒，
    /// 而 DESIGN-SYSTEM 第 5 节写明「超过 300ms 的操作都要有反馈」。
    /// 期间 `isCheckingPermission` 为 true，界面据此显示「正在检查运行环境…」。
    public func recheckPermission() async {
        isCheckingPermission = true
        let run = preflight
        let readiness = await Task.detached(priority: .userInitiated) { run() }.value
        permission = PermissionStatus.evaluate(readiness: readiness)
        permissionMessages = readiness.messages
        isCheckingPermission = false
    }

    /// 把一次题库导入并进现有题库、落盘，然后刷新内存里的状态。
    ///
    /// 放在这里而不是让视图自己去开 `StateStore`：`store` 与 `directory` 都是私有的，
    /// 而它们私有是有道理的——App 与命令行必须写同一个目录，多一处解析目录就多一处走岔的机会。
    ///
    /// **写盘失败必须抛出来。** 本项目发生过 `try?` 吞掉写盘失败之后照样打印「✅ 已写入」
    /// （铁律 7）；题库导入尤其不能这样——用户会以为题已经在库里了，
    /// 下次打开却一道都没有，而中间那次「成功」的提示让他根本不会怀疑导入这一步。
    @discardableResult
    public func applyImport(_ result: ImportResult) throws -> QuestionBankImportOutcome {
        let total = try store.mutate { state -> Int in
            // merge 按 id 去重、同 id 后者覆盖前者。雅思题库每季度换题，
            // 二次导入是常态而非边缘情况——不能变成两道一模一样的题。
            state.questions = QuestionBankImporter.merge(existing: state.questions,
                                                         incoming: result.questions)
            state.questionSources.append(result.source)
            return state.questions.count
        }
        reload()
        return QuestionBankImportOutcome(importedCount: result.questions.count,
                                         totalCount: total,
                                         warnings: result.warnings)
    }

    /// 读出某次练习的复盘，拆成复盘报告页要显示的分区。
    ///
    /// 放在这里而不是让视图自己拼路径，理由和 `applyImport` 一样：`directory` 是私有的，
    /// 而它私有是有道理的——App 与命令行必须读同一个目录，多一处解析目录就多一处走岔的机会。
    /// `reportPath` 存的是相对数据目录的路径，视图手上没有那个目录，也不该有。
    ///
    /// **失败必须抛出来。** 复盘打不开时给一块空白，用户会以为练了半小时的记录没了；
    /// 实际上原文一直在磁盘上，只是这一页得把路径和下一步告诉他（铁律 6、7）。
    public func loadReview(for session: PracticeSession) throws -> ReviewDocument {
        try ReviewReportLoader.load(session: session, in: directory)
    }

    /// 某次练习的复盘原文在磁盘上的绝对路径。界面用它做「在访达中显示」。
    public func reviewURL(for session: PracticeSession) -> URL {
        ReviewReportLoader.reportURL(for: session, in: directory)
    }

    /// 把读盘失败翻译成用户能照做的一句话。
    ///
    /// **不能直接用 `error.localizedDescription`**：`CoachError` 自带中文的「下一步」，
    /// 但文件权限、目录被占之类的失败抛出来的是系统 NSError，它只说发生了什么，
    /// 不说下一步做什么，措辞也未必是中文（铁律 6）。
    static func describeLoadFailure(_ error: any Error, stateFile: URL) -> String {
        let detail = error.localizedDescription
        if detail.contains("下一步") { return detail }
        return "读不到训练数据：\(detail)（文件：\(stateFile.path)）。"
            + "下一步：确认这个文件存在且可读；若不确定，把它改名备份后重新打开本应用，"
            + "本应用会新建一份空白记录，reports 目录里的历史复盘不受影响。"
    }
}
