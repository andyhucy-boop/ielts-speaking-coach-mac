import ChatGPTBridge
import Foundation
import IELTSCoachAudio
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
    /// 用户点「重新检查」并且**已经查完**的次数。0 表示还没点过。
    ///
    /// 界面靠它给「重新检查」这颗按钮一个反馈：重查结论和上一次一样时，
    /// `permission` 和 `permissionMessages` 都不变，页面不会有任何一个像素变化，
    /// 用户分不清是「查过了还是不行」还是「按钮坏了」（见 `PermissionStatus.recheckNotice`）。
    ///
    /// **这个计数必须放在 AppState，不能放在权限页自己的 `@State` 里**：重查期间
    /// `isCheckingPermission` 会把整页换成「正在检查运行环境…」，权限页连同它的
    /// `@State` 一起被销毁，查完回来的是全新的一份——那句反馈会永远显示不出来。
    public private(set) var recheckAttempts = 0
    /// 读取训练数据失败时的中文说明。非 nil 时界面必须显示它——
    /// 静默失败会让用户以为自己的练习记录没了。
    public private(set) var loadError: String?
    /// 改设置失败时的中文说明。**非 nil 时界面必须显示，且不许关闭面板**——
    /// 静默失败会让用户以为目标改好了，下次打开发现又变回去，
    /// 而且他永远不知道为什么。
    public private(set) var settingsError: String?
    public var permissionSkipped = false

    /// 侧边栏选中项与跨页跳转意图。
    ///
    /// **放在这里而不是 `RootView` 的 `@State` 里**：跨页跳转的发起方不止侧边栏——
    /// 今日训练页上「复训一个旧问题」那张卡片要跳到复训中心，而回调传不到那儿。
    /// 两份选中状态一定会走岔：导航状态变了、屏幕照另一份渲染，
    /// 用户点下去一个像素都不动，会以为按钮坏了。
    public let navigation = NavigationState()

    private let directory: DataDirectory
    private let store: StateStore
    private let preflight: @Sendable () -> BridgeReadiness
    private let makeBridge: @Sendable () -> any CoachBridge & Sendable
    private let makeTranscriptSampler: @Sendable () -> any TranscriptSampling
    /// 造这一场的录音器。**每场一台**：`PracticeRecordingCoordinator` 手上是
    /// 开练那一刻的开关快照与权限快照，复用同一台等于永远用第一场的那一份。
    private let makeRecording: @Sendable (RecordingStore, CoachSettings) -> any PracticeRecording
    /// 首次环境检查是否已经发起过。见 `startInitialPermissionCheckIfNeeded()`。
    private var didStartInitialCheck = false

    /// 生产环境真正用的那一份检查：驱动真实的辅助功能接口。
    /// 单元测试一律注入假实现，不接触真实 ChatGPT。
    nonisolated public static let livePreflight: @Sendable () -> BridgeReadiness = {
        let access = LiveAXAccess()
        return AXDriver(access: access, locator: AXLocator(access: access)).preflight()
    }

    /// 生产环境真正用的那一台驱动器。**构造它本身没有副作用**——不打开 ChatGPT、不碰磁盘，
    /// 只有被调用的方法才会动真格；`livePreflight` 那一份则是一按下去就会启动 ChatGPT。
    /// 单元测试与预览一律注入假 Bridge，不接触真实 ChatGPT（铁律 5）。
    nonisolated public static let liveBridge: @Sendable () -> any CoachBridge & Sendable = {
        let access = LiveAXAccess()
        return AXDriver(access: access, locator: AXLocator(access: access))
    }

    /// 生产环境真正用的那一台逐字稿采样器。**构造它本身没有副作用**——
    /// `LiveAXAccess.init` 是空的，不启动 ChatGPT、不碰磁盘，只有 `sample()` 被调用时
    /// 才会去读无障碍树。与 `liveBridge` 同理，单元测试与预览一律注入假采样器（铁律 5）。
    ///
    /// **它与 `liveBridge` 各自持有一份 `LiveAXAccess` 是有意的**：
    /// `LiveAXAccess.snapshotTree()` 每次调用都会清空 rawID 映射并把代次 +1，
    /// 让驱动器和采样器共用一份的话，采样器每 2.5 秒一次的遍历会把驱动器
    /// 手上正等着按的那个元素引用作废（症状是「按钮明明在，按下去没反应」）。
    nonisolated public static let liveTranscriptSampler: @Sendable () -> any TranscriptSampling = {
        AXTranscriptSampler(access: LiveAXAccess())
    }

    /// 生产环境真正用的那一台录音器。**构造它本身没有副作用**——不开麦克风、不建文件，
    /// `begin()` 不被调用就什么都不发生（与 `liveBridge` 同理，铁律 5）。
    ///
    /// **麦克风权限在每次开练那一刻查一次**（`currentStatus()` 只读系统状态，不弹窗）：
    /// 用户可能刚在系统设置里把权限给上，若要重启 App 才认，他会以为是这个应用坏了。
    ///
    /// 开关关着时协调器连采集器都不造，直接返回 `.skippedByUser`
    /// （见 `PracticeRecordingCoordinator.begin`），所以这里不必先判一次开关——
    /// 「录不录」的规则只留在 `RecordingConsent` 一处，两处各判一次迟早会走岔。
    ///
    /// **为什么权限查询是参数而不是写死的：** Phase 5 计划的 Global Constraints 写明
    /// 「单元测试里绝不允许碰真硬件，不许构造 `SystemMicrophoneAuthorizer`」——
    /// `swift test` 跑的是没有 bundle id、没有 Info.plist 的命令行进程。
    /// 把它做成带默认值的参数，测试就能把**这一份生产代码**原样跑一遍
    /// （只换掉那个查询），而不是另测一个长得像的替身：换成替身的话，
    /// 谁把这里改成一个什么都不录的空实现，测试也不会红。
    nonisolated public static func liveRecording(
        authorizer: @escaping @Sendable () -> any MicrophoneAuthorizing = { SystemMicrophoneAuthorizer() }
    ) -> @Sendable (RecordingStore, CoachSettings) -> any PracticeRecording {
        { store, settings in
            PracticeRecordingCoordinator(store: store,
                                         settings: settings,
                                         permission: authorizer().currentStatus())
        }
    }

    public init(directory: DataDirectory = .resolve(),
                preflight: @escaping @Sendable () -> BridgeReadiness = AppState.livePreflight,
                makeBridge: @escaping @Sendable () -> any CoachBridge & Sendable = AppState.liveBridge,
                makeTranscriptSampler: @escaping @Sendable () -> any TranscriptSampling
                    = AppState.liveTranscriptSampler,
                makeRecording: @escaping @Sendable (RecordingStore, CoachSettings)
                    -> any PracticeRecording = AppState.liveRecording()) {
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.preflight = preflight
        self.makeBridge = makeBridge
        self.makeTranscriptSampler = makeTranscriptSampler
        self.makeRecording = makeRecording
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
        await runPermissionCheck()
    }

    /// 重新检查运行环境。用户点「重新检查」时**必须**真的再查一次，所以这里没有闸。
    ///
    /// 与首次检查只差一件事：**这一次是用户按出来的，所以要计数。**
    /// 首次检查不能算进去——开机第一眼就看到「已重新检查，仍未通过」，
    /// 是在回答一个用户还没问的问题。
    public func recheckPermission() async {
        await runPermissionCheck()
        // 加在查完之后：这个数字的含义是「已经查完几次」。查到一半就先说「已重新检查」是句假话，
        // 而这期间界面显示的本来就是「正在检查运行环境…」那一屏。
        recheckAttempts += 1
    }

    /// 真正跑一次环境检查。首次检查与重查共用这一份，避免两条路各写各的之后走岔。
    ///
    /// 检查放在主线程之外跑：`preflight()` 会启动 ChatGPT，并最多轮询 8 秒等它的无障碍树
    /// 醒过来（`LiveAXAccess.wakeAccessibilityTree`）。放在主线程上等于让窗口冻住十秒，
    /// 而 DESIGN-SYSTEM 第 5 节写明「超过 300ms 的操作都要有反馈」。
    ///
    /// **`isCheckingPermission = true` 这一行是那十秒里界面唯一的反馈来源**：
    /// `RootRouter` 靠它切到「正在检查运行环境…」。删掉它，重查期间路由一路返回
    /// `.permissionGate`，用户点完按钮对着一动不动的授权页干等最多十秒
    /// （`AppStateTests.testRecheckSaysItIsCheckingWhileThePreflightIsStillRunning` 钉着这件事）。
    private func runPermissionCheck() async {
        isCheckingPermission = true
        let run = preflight
        let readiness = await Task.detached(priority: .userInitiated) { run() }.value
        permission = PermissionStatus.evaluate(readiness: readiness)
        permissionMessages = readiness.messages
        isCheckingPermission = false
    }

    /// 改训练数据。成功返回 nil；失败返回中文说明（发生了什么 + 下一步）。
    ///
    /// **调用方必须把返回的消息显示出来。** 写盘失败却什么都不说，
    /// 用户会以为改动生效了，下次打开才发现全没了——那正是禁止静默失败要防的事（铁律 7）。
    /// 刻意不加 `@discardableResult`：忽略返回值时编译器会警告。
    ///
    /// 学习计划页的每一次写盘都走这里：生成 / 重新生成 / 删除计划、三项练习偏好。
    /// 让视图自己开 `StateStore` 的话，App 与命令行就会有两处解析数据目录的地方，
    /// 而多一处就多一处走岔的机会（与 `applyImport`、`makePracticeRunner` 同一个理由）。
    ///
    /// **走 `store.mutate` 而不是改内存里那份 `state`**：`store.mutate` 在锁内重新从磁盘
    /// 读一遍再写回去，而 `coach practice` 写的是同一个文件。只改内存的话，
    /// 命令行那边同期写进去的东西会被整份盖掉。
    public func mutate(_ body: (inout CoachState) throws -> Void) -> String? {
        do {
            try store.mutate { try body(&$0) }
            // 改完必须重读：不重读的话页面显示的还是改之前那份，
            // 用户会以为按钮没反应，再点一次。
            reload()
            return nil
        } catch {
            return Self.describeMutationFailure(error, stateFile: directory.stateFile)
        }
    }

    /// 把写盘失败翻译成用户能照做的一句话。
    ///
    /// **不能直接用 `error.localizedDescription`**，理由与 `describeLoadFailure` 完全相同：
    /// `CoachError` 自带中文的「下一步」，但目录被占、权限不足之类的失败抛出来的是系统
    /// NSError，它只说发生了什么，不说下一步做什么，措辞也未必是中文（铁律 6）。
    ///
    /// 错误自带「下一步」时**原样交出去**：再包一层的话，用户会读到两个互相矛盾的
    /// 「下一步」，而真正该做的那一步被埋在中间。
    static func describeMutationFailure(_ error: any Error, stateFile: URL) -> String {
        let detail = error.localizedDescription
        if detail.contains("下一步") { return detail }
        return "这次改动没能保存：\(detail)（文件：\(stateFile.path)）。"
            + "下一步：确认这个文件所在的目录存在且可写"
            + "（默认在「资源库 › Application Support › IELTS Speaking Coach」），然后再试一次；"
            + "在此之前训练数据保持原样，练习记录与复盘都没有受影响。"
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

    /// 「记录对话逐字稿」开关（ROADMAP 第 5 节，默认开）。
    ///
    /// 写盘失败必须让用户看见——静默失败会让用户以为已经关掉了，实际还在记录。
    /// 这属于本项目最不能接受的那种失败：界面显示的状态和真实行为对不上。
    public func setTranscriptEnabled(_ enabled: Bool) {
        do {
            try store.mutate { $0.settings.transcriptEnabled = enabled }
            reload()
        } catch {
            loadError = "没能保存「记录对话逐字稿」这个设置：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重试；在此之前这个开关仍按原来的设置生效。"
        }
    }

    /// 改每周训练目标。越界的取值按 `CoachSettings.normalized` 归一，不抛错。
    ///
    /// **归一必须在这里做一次，不能只靠读回来时那一次。** `CoachSettings.init(from:)`
    /// 解码时确实还会归一一遍，所以少了这一句，界面上看不出任何异样；
    /// 但磁盘上那份 state.json 会留着 `"weeklyGoal": 99`，而它是 App 与命令行共用的
    /// 同一个文件——把一个越界值写进共享数据，等于给下一个读它的人埋一颗雷。
    ///
    /// - Returns: 是否写盘成功。界面据此决定要不要关闭设置面板。
    @discardableResult
    public func setWeeklyGoal(_ goal: Int) -> Bool {
        let normalized = CoachSettings.normalized(goal)
        do {
            try store.mutate { $0.settings.weeklyGoal = normalized }
            settingsError = nil
            reload()          // 立刻把新目标反映到首页的「本周 N/M」上
            return true
        } catch {
            settingsError = "每周训练目标没能存下来：\(error.localizedDescription)"
                + " 下一步：确认数据目录可写"
                + "（默认在「资源库 › Application Support › IELTS Speaking Coach」），"
                + "然后再试一次；在此之前仍按原来的目标计数。"
            return false
        }
    }

    /// 删掉一条训练记录，连带清掉它的复盘报告与录音（决策 4）。
    ///
    /// **永不抛错**：返回 nil 表示一切顺利，返回字符串是给用户看的中文说明
    /// （记录删掉了但有文件没删成，见 `SessionDeleter.delete`）。
    ///
    /// 放在这里而不是让视图自己 new 一台 `SessionDeleter`，理由和 `applyImport`、
    /// `loadReview` 一样：`directory` 与 `store` 都是私有的，而它们私有是有道理的——
    /// App 与命令行必须读写同一个目录，多一处解析目录就多一处走岔的机会。
    @discardableResult
    public func deleteSession(_ session: PracticeSession) -> String? {
        let failure = SessionDeleter(directory: directory, store: store).delete(session)
        // 删完必须重读：不重读的话那一行还留在界面上，用户会再点一次删除，
        // 而这一次删的是一条已经不存在的记录。
        reload()
        return failure
    }

    /// 造一台练习驱动器：**与本 AppState 同一个数据目录**，桥接注入进来的那个 Bridge。
    ///
    /// 放在这里而不是让视图自己 new 一个，理由和 `applyImport`、`loadReview` 一样：
    /// `directory` 是私有的，而它私有是有道理的——App 与命令行必须读写同一个目录，
    /// 多一处解析目录就多一处走岔的机会。练完存下来的复盘要是落在另一个目录里，
    /// 用户回到「复盘报告」页会看到空的，而磁盘上其实存着。
    ///
    /// 每次开练都造一台新的：`PracticeRunner` 带着「这一场是哪道题」的状态，
    /// 复用同一台会让上一场的残留状态影响下一场。
    ///
    /// **「记录对话逐字稿」这个开关就在这里生效**：开着才造采样器，关着传 nil
    /// （`PracticeRunner` 收到 nil 就安静地什么都不做，不报错、不留提示——
    /// 那是用户自己的选择，不该渲染成警告）。开关在**开练这一刻**读一次，
    /// 而不是练到一半跟着变：一场练习记一半逐字稿，比记全或不记都难解释。
    ///
    /// **录音同理，也是在这里接上的**：录音器每场造一台，拿到的是开练这一刻的
    /// 开关快照与麦克风权限快照。「用户开没开、系统给没给」的判断全在录音器里做
    /// （`RecordingConsent`），这里不重复判一遍——两处各判一次，迟早会走岔。
    ///
    /// 这一步曾经漏掉过两次：Phase 4 的十三个任务没有一个认领「把采样器接到 App 上」，
    /// 于是 `AXTranscriptSampler` 在整个 App 里从来没有被造出来过，真机上练一场
    /// 逐字稿一定是空的，而界面上看不出任何异样；Phase 5 的十一个任务同样没有一个认领
    /// 「把录音器接到 App 上」，后果是真机上练一场一秒都不会被录下来，
    /// 而全套测试照样全绿。守着这两件事的是 `AppStateTests` 里
    /// 「采样器必须真的接到练习上」与「录音也必须真的接到练习上」那两组。
    public func makePracticeRunner() -> PracticeRunner {
        // **开练前先从磁盘重读一次设置。** 录音开关是在系统「设置」窗口（⌘,）里拨的，
        // 那个窗口有它自己的 StateStore，不经过本 AppState；只信内存里这一份的话，
        // 用户刚打开录音、转身开练，交给录音器的还是启动 App 那一刻的旧值——
        // 设置窗口里开关明明开着，练完却一个录音都没有，而且不会有任何报错。
        // 读的是本地一个小 JSON，毫秒级；读失败时 `reload()` 会把中文说明放进 `loadError`，
        // 沿用上一次读到的设置继续，不静默（铁律 7）。
        reload()
        let settings = state.settings
        return PracticeRunner(bridge: makeBridge(),
                              pasteboard: SystemPasteboard(),
                              directory: directory,
                              transcript: settings.transcriptEnabled ? makeTranscriptSampler() : nil,
                              recording: makeRecording(RecordingStore(directory: directory),
                                                       settings))
    }

    /// 造一台复训编排器：把 `launcher` 那一场挂到**本 AppState 这个数据目录**的复训台账上。
    ///
    /// 放在这里而不是让视图自己 new 一个，理由和 `makePracticeRunner` 一样：`store` 是私有的，
    /// 而它私有是有道理的——App 与命令行必须写同一个目录。台账要是写进另一个 state.json，
    /// 用户练完回到复训中心会看到进度纹丝不动，而且不会有任何报错。
    ///
    /// 每开一场复训造一台新的：它带着「这一场挂上了没有」（`linkedSessionID`）与
    /// 「哪一步没走通」（`failure`）的状态，复用同一台会让上一场的提示留在这一场的屏幕上。
    ///
    /// **`mutate` 走 `store.mutate` 而不是改内存里那份 `state`**：`store.mutate` 在锁内
    /// 重新从磁盘读一遍再写回去，而 `coach practice` 写的是同一个文件。只改内存的话，
    /// 命令行那边同期写进去的东西会被整份盖掉。
    public func makeRetrainingCoordinator(
        launcher: any PracticeSessionLauncher) -> RetrainingCoordinator {
        RetrainingCoordinator(launcher: launcher,
                              mutate: { [store] body in try store.mutate { body(&$0) } })
    }

    /// 改一个复训目标的状态（选中 / 退休 / 重新放回待复训）。
    ///
    /// - Returns: nil 表示改成了；非 nil 是**必须显示给用户看**的中文说明。
    ///   静默返回成功，用户会看到列表纹丝不动却没有任何解释（铁律 7）。
    @discardableResult
    public func setRetrainingStatus(_ status: RetrainingStatus, of targetID: String) -> String? {
        do {
            var changed = false
            try store.mutate { changed = RetrainingLedger.setStatus(status, of: targetID, in: &$0) }
            // 改完必须重读：不重读的话这一页显示的还是改之前那份，
            // 用户会再点一次，而这一次改的是一个已经改过的目标。
            reload()
            guard changed else {
                return "训练数据里已经找不到这个复训目标（\(targetID)），所以它的状态没有改动。"
                    + "下一步：多半是它来源的那一场练习记录已被删除，或另一个进程改过训练数据；"
                    + "回到「今日训练」再进来一次，看它还在不在列表里。"
            }
            return nil
        } catch {
            return "没能保存这个复训目标的状态：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重试；在此之前它仍按原来的状态显示。"
        }
    }

    /// 读出某次练习的**复盘原文**（不拆分区），给复训第一步装配证据用。
    ///
    /// 与 `loadReview(for:)` 的区别只在返回什么：那一个交给复盘报告页，已经拆好了分区；
    /// 这一个交给 `RetrainingEvidenceBuilder` 与 `RetrainingOutcome.judge`，它们要的是原始 JSON。
    ///
    /// **读不到就返回 nil，不要编一份空的顶上。** 这不是静默失败：拿到 nil 的
    /// `RetrainingEvidenceBuilder` 会给出一句中文说明（「复盘报告读不到，屏幕上只剩……
    /// 下一步：到「复盘报告」页确认那份报告还在不在」），那才是用户需要的东西；
    /// 而 `RetrainingOutcome.judge` 拿到 nil 会判成 `.noReport`（「不知道」），
    /// **不会**把读不到当成好消息。
    ///
    /// 解析走 `ReviewParser` 而不是裸 `JSONValue.decode`：ChatGPT 的复盘常带 ``` 围栏与前后废话，
    /// 归档时用的就是 `ReviewParser`。两边用不同的解析器，会出现「复盘报告页显示得好好的，
    /// 复训第一步却说读不到」。
    public func loadReviewJSON(for session: PracticeSession) -> JSONValue? {
        guard !session.reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let url = ReviewReportLoader.reportURL(for: session, in: directory)
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
              let value = try? ReviewParser.parse(raw) else { return nil }
        return value
    }

    /// 造一份「重新导入待处理的复盘」的视图模型：**与本 AppState 同一个数据目录**。
    ///
    /// 放在这里而不是让视图自己 new 一个，理由和 `makePracticeRunner`、`loadReview` 一样：
    /// `directory` 与 `store` 都是私有的，而它们私有是有道理的——App 与命令行必须读写
    /// 同一个目录，多一处解析目录就多一处走岔的机会。补进去的复盘要是落在另一个目录里，
    /// 用户回到「复盘报告」页只会看到什么都没变，而且不会有任何报错。
    ///
    /// 每次打开收件箱都造一份新的：它带着「上一次操作说了什么」（`notice`）的状态，
    /// 复用同一份会让上次的提示留在这次的屏幕上。
    public func makePendingReviewViewModel() -> PendingReviewViewModel {
        PendingReviewViewModel(directory: directory, store: store)
    }

    /// 造一份「这一场的录音」的视图模型：**与本 AppState 同一个数据目录**。
    ///
    /// 放在这里而不是让视图自己 new 一个，理由和 `makePendingReviewViewModel`、
    /// `loadReview` 一样：`directory` 与 `store` 都是私有的，而它们私有是有道理的——
    /// App 与命令行必须读写同一个目录，多一处解析目录就多一处走岔的机会。
    /// 播放器要是去另一个目录里找那条 `recordings/*.m4a`，训练记录页上每一场都会
    /// 显示「录音文件找不到了」，而文件其实好端端地躺在磁盘上。
    ///
    /// 每点开一场造一份新的：它带着这一场的 `sessionID` 与「上一次操作说了什么」
    /// （`notice`）的状态，复用同一份会让上一场的提示留在这一场的屏幕上。
    ///
    /// **它写盘不经过本 AppState**（`RecordingPlaybackViewModel` 自己拿着 `StateStore`），
    /// 所以删完录音之后界面必须自己 `reload()` 一次——`RecordingPlayerView` 的
    /// `onRecordingRemoved` 就是干这个的。不重读的话，行上那个波形标记会一直留着。
    public func makeRecordingPlaybackViewModel(
        for session: PracticeSession) -> RecordingPlaybackViewModel {
        RecordingPlaybackViewModel(sessionID: session.id,
                                   relativePath: session.recordingPath,
                                   store: store,
                                   recordings: RecordingStore(directory: directory))
    }

    /// 读出某次练习的复盘，拆成复盘报告页要显示的分区。
    ///
    /// 放在这里而不是让视图自己拼路径，理由和 `applyImport` 一样：`directory` 是私有的，
    /// 而它私有是有道理的——App 与命令行必须读同一个目录，多一处解析目录就多一处走岔的机会。
    /// `reportPath` 存的是相对数据目录的路径，视图手上没有那个目录，也不该有。
    ///
    /// **失败必须抛出来。** 复盘打不开时给一块空白，用户会以为练了半小时的记录没了；
    /// 实际上原文一直在磁盘上，只是这一页得把路径和下一步告诉他（铁律 6、7）。
    ///
    /// 界面要的绝对路径已经在 `ReviewDocument.path` 里（`load` 顺手带出来的），
    /// **不要再补一个 `reviewURL(for:)` 之类的方法**：那等于让同一条路径有两个来源，
    /// 「在访达中显示原文」打开的文件就可能和它旁边那行字写的路径不是同一个。
    public func loadReview(for session: PracticeSession) throws -> ReviewDocument {
        try ReviewReportLoader.load(session: session, in: directory)
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
