import ChatGPTBridge
import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import Observation

/// 失败之后「重试」到底该重做什么。
///
/// **这个区分不是锦上添花。** 开练阶段失败时重做的是整条链路，第一步是按「新建会话」；
/// 而收尾阶段失败时若也去按「新建会话」，那条刚练完、复盘还在里面的会话就当场没了——
/// 用户练的半小时连同复盘一起蒸发，且界面上看着像是「重试了一下」。
///
/// `CaseIterable` 不是给产品代码用的，是给守卫用的：
/// 「文案里指名的那颗按钮，界面上真的有吗」这条断言需要一份**完整**的按钮清单，
/// 而手写的清单会漏掉将来新加的那一种重试——漏掉的那一种就又没人看着了。
public enum PracticeRetry: Equatable, Sendable, CaseIterable {
    /// 从头再来一遍（新建会话 → 启动语音 → …）。
    case restart
    /// 只重做收尾（结束语音 → 请复盘 → 取回 → 存档），不碰当前会话。
    case wrapUp
    /// 用户手动 ⌘C 之后，从剪贴板取。
    case clipboard

    /// 重试那颗按钮上写的字。
    ///
    /// **放在这里是因为运行器写的「下一步」要指名道姓地提到这颗按钮**，而按钮是界面画的。
    /// 两边各写一份的话，改了界面上的字，错误信息里指的就成了一颗界面上不存在的按钮——
    /// 用户照着找，找不到（铁律 6）。
    public var buttonTitle: String {
        switch self {
        case .restart: return "从头再试一次"
        case .wrapUp: return "重新取复盘"
        case .clipboard: return "我已经复制好了"
        }
    }
}

/// 用户中途放弃这一场时，还在主线程外面跑着的那条链路用它退场。
///
/// **它不是错误，一个字都不许画到屏幕上。** 界面这时已经被 `cancel()` 放到
/// `.abandoned` 那张交代卡片上了；再画一句「这一步没成功」是对用户撒谎——
/// 那一步不是没成功，是他自己叫停的。
struct PracticeAbandoned: Error {}

/// 把一场练习包成可观察的状态流。
///
/// **只依赖 `CoachBridge`，不依赖 `AXDriver`。** 因此整条流转可以用假 Bridge 完整测试，
/// 全程不碰真实 ChatGPT——这正是 Phase 2 花力气做 `AXAccess` 接缝换来的红利。
///
/// 所有阻塞调用（AX 轮询，最长的一步约 9 秒）都甩到主线程之外跑，
/// 阶段变化则在主线程上更新。放在主线程上做的话，窗口会整整冻住十几秒，
/// 而那时界面写着「正在启动语音…」却一个像素都不会重绘——比不写还糟。
@MainActor
@Observable
public final class PracticeRunner {
    public private(set) var stage: PracticeStage = .idle
    /// 失败或需要手动复制时，「重试」按钮该重做什么。其余时候是 nil。
    public private(set) var retry: PracticeRetry?
    /// 存档之后要交代的话：三处档案各进了多少条、原文存在哪儿、有没有字段没读进去。
    ///
    /// **归档 0 条不等于没内容**（见 `ArchiveOutcome.skipped`），所以这句话必须显示出来，
    /// 不能只画一个「✅ 完成」。
    public private(set) var archiveNotice: String?

    /// 这一场存进 `state.sessions` 之后那条记录的 id。还没练完时是 nil。
    ///
    /// 复训要靠它把「这一场」和「哪个目标」挂上钩（Phase 6 前置依赖 P3），
    /// 首页的「本周练了几次」也数这些记录（Phase 7）。
    public private(set) var finishedSessionID: String?
    /// 逐字稿不完整时的中文说明。**非 nil 时界面必须显示它。**
    ///
    /// 它不是错误：采样失败绝不中断练习（ROADMAP 3.2）。但也绝不静默——
    /// 悄悄丢掉几分钟对话、逐字稿看起来一切正常，才是本项目最忌讳的失败形态。
    public private(set) var transcriptNotice: String?
    /// 目前已经记下几条对话。**练习进行中就要能看到它在涨**，所以是算出来的，
    /// 不是练完才填一次的快照——`TranscriptCollector` 每采一次样就更新一次 `turns`。
    public var transcriptTurnCount: Int { collector.turns.count }

    /// 这一场到底在不在录。界面据此显示「● 正在录音」。
    ///
    /// **录不了的时候必须是 false。** 显示成「正在录音」却什么都没录，
    /// 是本项目最不能接受的那种失败（计划「这个阶段有一件事任何自动化都绕不过去」第 2 条）。
    public private(set) var isRecording = false
    /// 录音相关的中文说明。**非 nil 时界面必须显示。**
    ///
    /// 它不是错误：录音是增强，不是必需，起不来也照常练完（与逐字稿同一条原则，ROADMAP 3.2）。
    /// 但也绝不静默——用户以为在录、实际没录，或者录音中途断过，不说就是骗人。
    public private(set) var recordingNotice: String?
    /// 这次录音的相对路径（例如 `recordings/2026-08-06T10-45-30Z.m4a`），
    /// 归档时写进 `PracticeSession.recordingPath`，训练记录页靠它挂播放器。
    ///
    /// **一秒都没录到时是空串**：那时候 `RecordingSession` 已经把空文件删了，
    /// 再往训练记录里写一个指向已删文件的路径，只会画出一个点了没声音的播放器。
    public private(set) var recordingRelativePath = ""

    private let bridge: any CoachBridge & Sendable
    private let pasteboard: any PasteboardAccess
    /// 这一场的录音。传 nil 表示这台运行器根本不管录音（Xcode 预览、以及所有
    /// 不关心录音的既有测试）——此时安静地什么都不做，不报错、不留提示。
    ///
    /// **只依赖 `PracticeRecording` 这个 protocol，不依赖任何 AVFoundation 类型**，
    /// 所以整条接线可以用假实现测完，全程不碰真麦克风（铁律 5）。
    private let recording: (any PracticeRecording)?
    private let directory: DataDirectory
    private let store: StateStore
    private let collector: TranscriptCollector
    private let composerTimeout: TimeInterval
    private let replyTimeout: TimeInterval
    private let copyTimeout: TimeInterval
    /// 逐字稿采样的节拍。实测每 2~3 秒一次足够跟上流式输出，
    /// 又不会把 CPU 耗在反复遍历几百个 AX 节点上。
    private let samplingInterval: TimeInterval
    private let now: @Sendable () -> Date

    /// 正在进行的这一场。取消或存档完成后置空——**没有它就不该再去驱动 ChatGPT**，
    /// 那时用户很可能已经在用 ChatGPT 做别的事了。
    private var current: SessionSetup?
    /// 本次复盘请求的 id。只用来在 ChatGPT 的回复里认出这一次的定界标记。
    private var currentRequestID: String?
    /// 这一场的会话编号。**落盘文件名（`pending-reviews/<id>.txt`、`reports/<id>.json`）
    /// 与 `state.sessions` 里的记录用的都是它**，所以收尾失败后重试时要沿用同一个，
    /// 不能每重试一次就再要一个新编号——那会给同一场练习留下好几条训练记录。
    private var currentSessionID: String?
    /// 这一场的开始时刻。训练记录要按它排序、按月分组。
    private var startedAt: Date?
    private var samplingTask: Task<Void, Never>?

    /// 「这一场」的代次。`start()` 与 `cancel()` 各把它 +1。
    ///
    /// **它是「取消真的取消得掉」这件事的全部依据。** AX 调用是阻塞、不可中断的：
    /// 已经甩到主线程外面的那一步收不回来，但它跑完之后接着要做的每一步，
    /// 都得先拿自己出发时的代次和它比一次——对不上就当场退场（`PracticeAbandoned`）。
    ///
    /// **为什么不是一个 `isCancelled` 布尔量**：布尔量会被下一次 `start()` 清掉，
    /// 而那一刻上一条链路可能还挂在某个 AX 调用里；清掉之后它会当作没事继续往下跑，
    /// 接着去驱动用户那时候正在用的 ChatGPT。代次只增不减，谁也复活不了旧链路。
    private var generation = 0
    /// 收尾链路（`finishPractice` / `captureReviewFromClipboard`）是不是正跑着。
    ///
    /// **「我练完了」挂着回车快捷键**（`.keyboardShortcut(.defaultAction)`），
    /// 练完那一刻双击、或者急着结束连按两下回车都非常容易。没有这道守卫的话，
    /// 两条收尾链路会同时跑起来：复盘请求被打进 ChatGPT 两遍（用户回去会看到同一段
    /// 一千多字的提示词贴了两次、它也答了两次），而且两条链路会同时驱动同一台
    /// AX 驱动器——那是一次真实的数据竞争，实测会段错误，这一场的复盘跟着没。
    private var isWrappingUp = false
    /// ChatGPT 那边的语音通话有没有可能还开着。
    ///
    /// 只用来决定放弃时那句交代要不要提「你得自己去挂断」。宁可多说一次也不能漏：
    /// 漏了的话，用户的麦克风在 ChatGPT 那边一直开着，而他毫不知情。
    private var voiceMayBeLive = false

    /// 超时值全部与 `coach practice` 保持一致（那几个数是按实测时序定的，见 spec 2.3.7）。
    /// **要短超时请在测试里显式传参，不要改这里的默认值。**
    ///
    /// - Parameter transcript: 逐字稿采样器。传 nil 表示用户在设置里关掉了
    ///   「记录对话逐字稿」，此时安静地什么都不做。**刻意不挂在 `CoachBridge` 上**，
    ///   理由见 `TranscriptSampling` 的注释。
    /// - Parameter recording: 这一场的录音。**默认 nil，所以既有调用点一处都不用改**；
    ///   收到 nil 就当这台运行器不管录音。开关与麦克风权限的判定归
    ///   `PracticeRecordingCoordinator`，这里只负责按四条接线规则调用它。
    public init(bridge: any CoachBridge & Sendable,
                pasteboard: any PasteboardAccess,
                directory: DataDirectory = .resolve(),
                transcript: (any TranscriptSampling)? = nil,
                composerTimeout: TimeInterval = 20,
                replyTimeout: TimeInterval = 60,
                copyTimeout: TimeInterval = 10,
                samplingInterval: TimeInterval = 2.5,
                recording: (any PracticeRecording)? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.bridge = bridge
        self.pasteboard = pasteboard
        self.recording = recording
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.collector = TranscriptCollector(sampler: transcript, now: now)
        self.composerTimeout = composerTimeout
        self.replyTimeout = replyTimeout
        self.copyTimeout = copyTimeout
        self.samplingInterval = samplingInterval
        self.now = now
    }

    // MARK: - 开练

    /// 严格按 spec 2.3.5 的顺序：新建会话 → 启动语音 → 等语音输入框 → 发考官提示词。
    ///
    /// **顺序不能改。** Live 语音只能在一条还没发过任何消息的会话里启动，
    /// 先发消息就再也点不动 Live 了——这一点从 AX 树上完全看不出来，是真机上栽过的坑。
    ///
    /// 任何一步失败都停在 `.failed` 并把错误抛出去，**绝不继续往下走**：
    /// 继续走的后果是用户对着一个根本没收到考官提示词的 ChatGPT 练完整整一场。
    public func start(setup: SessionSetup) async throws {
        // 重开一场之前先把上一场的节拍停掉。走到这儿时上一场多半已经停了，
        // 但「上一场还在采样、这一场又开一个」的后果是两个 Task 同时往同一个
        // 拼接器里灌，且旧的那个永远没人取消——宁可多停一次。
        stopSampling()
        // 开新的一场就是新的一代：上一条还挂在某个 AX 调用里的链路从此再也走不动。
        generation += 1
        let ticket = generation
        current = setup
        currentRequestID = nil
        currentSessionID = nil
        finishedSessionID = nil
        transcriptNotice = nil
        startedAt = now()
        archiveNotice = nil
        recordingNotice = nil
        recordingRelativePath = ""
        isRecording = false
        voiceMayBeLive = false
        retry = nil
        let prompt = ExaminerPrompt.build(setup: setup)
        do {
            try await run(.newChat, ticket: ticket) { try $0.startNewChat() }
            // **在这一步之前就立起来**：`startVoice()` 是阻塞调用，抛错也可能是
            // 「按下去了但没等到确认」，那时 ChatGPT 那边的通话已经拨出去了。
            voiceMayBeLive = true
            try await run(.startingVoice, ticket: ticket) { try $0.startVoice() }
            let timeout = composerTimeout
            try await run(.waitingComposer, ticket: ticket) {
                _ = try $0.waitForVoiceComposer(timeout: timeout)
            }
            try await run(.sendingPrompt, ticket: ticket) { try $0.sendText(prompt, into: .voice) }
            // **开练这一刻就在盘上占好位置。**
            //
            // 在这之前，一场练习在用户按下「我练完了」之前**磁盘上一个字都没有**：
            // 练到一半 App 崩了、Mac 重启、误按退出，这半小时就等于没发生过——
            // 不进「本周 N/5」、学习计划不前进、题目不打「已练」，
            // 那段录音变成一个没人认领的孤儿文件。
            //
            // 上游文档里那句话很直白：不要等复盘生成完才保存训练记录。
            //
            // 写的是 `state.currentSession` 而不是 `sessions`：这一场还没结束，
            // 混进正式记录里会让「本周练了几次」把一场没练完的也算进去。
            // 下次开 App 时由「今日训练」页把它捡起来（`UnfinishedSession`）。
            beginSessionRecord(setup: setup)
            beginCollectingTranscript()
            beginRecording()
            stage = .practicing
        } catch {
            // **放弃优先于失败。** 代次对不上就说明用户在开练途中按了取消：
            // 抛出来的既可能是守卫的 `PracticeAbandoned`，也可能是那一步自己的真错误
            //（他按取消的时候那一步本来就正要失败）。两种都一样处理——
            // `cancel()` 已经把采样停了、录音收了、那张交代卡片也画好了，
            // **这里一个字都不能再改**：改了会把它盖成一句「这一步没成功」
            // 外加一颗「从头再试一次」，而那颗按钮按下去的第一步是新建会话——
            // 用户刚放弃，它又替他开一场。
            //
            // 更要紧的是绝不能继续往下走：往下一步是把考官提示词发给用户此刻
            // 多半正在用的 ChatGPT，再往下一步 `beginRecording()` 会把麦克风
            // **重新打开一遍**，而那之后再没有任何人会去调 `finish()`——
            // 系统状态栏那个橙点会一直亮到用户退出整个应用为止。
            guard ticket == generation else { return }
            stopSampling()
            // 已经录下的部分不能跟着这次失败一起丢：走到这儿时录音多半还没开始，
            // 但「开始录了之后才失败」这条路存在（`beginRecording` 之后再抛错的将来改动），
            // 而漏掉它的代价是一整场录音停在缓冲区里，用户什么都拿不到。
            finalizeRecording()
            fail(error, retry: .restart)
            throw error
        }
    }

    /// 录音**在考官提示词发出去之后**才开始。
    ///
    /// 早一步的话，录进去的是用户等 ChatGPT 启动语音的那 9 秒沉默（spec 2.3.7）——
    /// 那段时间他还没开口，也不该开口。
    ///
    /// **起不来绝不能把练习也拖垮。** 录音是增强，不是必需（与逐字稿同一条原则，
    /// ROADMAP 3.2）：一个没给麦克风权限的用户本来只是听不了回放，
    /// 若因此连练都练不了，那就是拿一个可选功能把主功能废掉了。
    private func beginRecording() {
        // 用这一场的开始时刻命名，而不是「此刻」：训练记录里那条会话记的也是它，
        // 两处一致，人肉对照文件与记录时才不会差出九秒。
        switch recording?.begin(startedAt: startedAt ?? now()) {
        case .started(let path):
            isRecording = true
            recordingRelativePath = path
        case .failed(let message):
            // 想录却录不了，必须让用户看见：他以为在录，实际没录，不说就是骗人。
            isRecording = false
            recordingNotice = message
        case .skippedByUser, .none:
            // 开关关着是默认状态，不是故障，什么都不说——为它报警会天天骚扰用户。
            isRecording = false
        }
    }

    /// 收尾录音。可以被重复调用：没在录时 `PracticeRecording.finish()` 返回 nil。
    ///
    /// **每一条会走到头的路径都要调它**（练完、开练失败、中途取消），漏掉任何一条，
    /// 那条路上的录音就停在缓冲区里，用户练了半小时什么都拿不到。
    private func finalizeRecording() {
        guard let outcome = recording?.finish() else {
            isRecording = false
            return
        }
        isRecording = false
        // 一秒都没录到时这里是空串，训练记录就不会挂上一个指向已删文件的播放器。
        recordingRelativePath = outcome.relativePath
        if let warning = outcome.warning {
            // 拼接而不是覆盖：开录时那条「这次没录上」与收尾时这条「中途断过」
            // 是两件事，都发生过的话用户两件都得知道。
            recordingNotice = [recordingNotice, warning].compactMap { $0 }.joined(separator: "\n")
        }
    }

    /// 逐字稿从**考官提示词已经发出去之后**才开始收集。
    ///
    /// 早一步的话，那条两千字符的考官提示词就不会被当成背景板，而是被当成对话内容
    /// 采进逐字稿里——而它恰恰是屏幕上最长的一段文字。
    /// 开练这一刻在 `state.currentSession` 上占好位置。
    ///
    /// 编号在这里就分配好，`finishPractice` 会沿用它（那边本来就是
    /// `currentSessionID ?? SessionID.next(...)`）——所以一场练习自始至终只有一个编号。
    ///
    /// **写不进去不算失败，但要说出来。** 这是一道保险，不是练习本身：
    /// 因为它开不了练是本末倒置。但一声不响地不保险，就等于用户以为有保险而其实没有。
    private func beginSessionRecord(setup: SessionSetup) {
        let formatter = ISO8601DateFormatter()
        do {
            let sessionID = try store.mutate { state -> String in
                let id = SessionID.next(existing: state.sessions, now: self.now(),
                                        timeZone: .current)
                state.currentSession = PracticeSession(
                    id: id, questionId: setup.question.id, focusPart: setup.focusPart,
                    startedAt: formatter.string(from: self.startedAt ?? self.now()),
                    endedAt: "", goal: setup.goal, transcript: [],
                    reportPath: "", recordingPath: "",
                    drawnQuestionIds: self.drawnQuestionIds(in: setup))
                return id
            }
            currentSessionID = sessionID
        } catch {
            transcriptNotice = "这一场没能在开练时先记下来：\(error.localizedDescription) "
                + "练习本身不受影响，照常练；只是万一中途崩溃或误关窗口，这一场救不回来。"
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」）。"
        }
    }

    /// 把已经采到的逐字稿存进 `state.currentSession`。
    ///
    /// **每采一次存一次。** 上游是「逐字稿一变就在 450 毫秒后存一次」，本工具的采样
    /// 本来就是定时的（默认 2.5 秒一次），跟着它走即可，不必再加一层节流。
    ///
    /// 写盘失败**一个字都不说**：这一路每 2.5 秒跑一次，说了会刷屏，
    /// 而真正要紧的那次失败（开练时占不上位置）在 `beginSessionRecord` 里已经说过了。
    private func checkpointTranscript() {
        guard let sessionID = currentSessionID else { return }
        let turns = collector.turns
        guard !turns.isEmpty else { return }
        try? store.mutate { state in
            guard var session = state.currentSession, session.id == sessionID else { return }
            session.transcript = turns
            state.currentSession = session
        }
    }

    private func beginCollectingTranscript() {
        collector.begin()
        samplingTask = Task { [weak self, samplingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(samplingInterval))
                if Task.isCancelled { return }
                self?.collector.tick()
                // 采完就存。不存的话，`currentSession` 里永远是一份空逐字稿，
                // 崩溃之后捡起来的是一条什么都没有的记录——比没有更让人困惑。
                self?.checkpointTranscript()
            }
        }
    }

    private func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    // MARK: - 练完

    /// 结束语音（若还开着）→ 发复盘请求 → 等 ChatGPT 写完 → 取复盘 →
    /// **先落盘再解析** → 归档 → `.done`。
    ///
    /// 「先落盘再解析」不能省：练了半小时换来的复盘，不能因为解析出错就没了（成品标准第 7 条）。
    public func finishPractice() async throws {
        // **重入守卫，早于一切。** 连点两下「我练完了」（那颗按钮挂着回车快捷键，
        // 练完那一刻很容易连按）会开出两条收尾链路：复盘请求打进 ChatGPT 两遍，
        // 两条链路还会同时驱动同一台 AX 驱动器——实测那是一次真实的数据竞争，会段错误。
        //
        // 第二下**安静地什么都不做**，这不是静默失败：第一下正跑着，界面上那行阶段说明
        // 和那列进度清单一直在说它走到哪儿了，用户看得见事情在推进。
        guard !isWrappingUp else { return }
        isWrappingUp = true
        defer { isWrappingUp = false }
        let ticket = generation

        // **第一件事，早于结束语音、早于发复盘请求。** 用户点「我练完了」的那一刻
        // 就已经不说话了，早一点关文件，后面结束语音、请 ChatGPT 写复盘、
        // 等它写完那几十秒就不会被录进去。
        finalizeRecording()

        guard let setup = current else {
            let message = "现在没有正在进行的练习，也就没有复盘可以取回"
                + "（这一场可能已经存过档，或者刚才被取消了）。"
                + "下一步：关掉这个窗口，回到「今日训练」重新开始一场；"
                + "若刚才那一场的复盘还留在 ChatGPT 窗口里，先把它复制下来自己留一份。"
            stage = .failed(message)
            retry = nil
            throw CoachError.reviewNotFound(message)
        }

        // **第一件事。** 晚一步的话，复盘那一大坨 JSON 会被采进逐字稿里。
        stopSampling()
        collector.finish()
        transcriptNotice = collector.notice

        // 收尾失败后重试时沿用同一个编号：每次都要一个新的话，一场练习会留下好几条记录。
        let sessionID = currentSessionID
            ?? SessionID.next(existing: (try? store.load())?.sessions ?? [],
                              now: now(), timeZone: .current)
        currentSessionID = sessionID

        // **取复盘之前就把这一场记下来。** 后面任何一步失败，用户练的这一场
        // 和已经采到的逐字稿都还在（成品标准第 7 条）。
        upsertSession(id: sessionID, setup: setup, reportPath: nil,
                      recordingPath: recordingRelativePath)
        finishedSessionID = sessionID

        do {
            try ensureStillRunning(ticket)
            // 用户自己在 ChatGPT 里挂断时语音已经结束了。这时再按一次「结束通话」，
            // `AXDriver.endVoice` 会直接抛错（它刻意不把「本来就没在通话」当成成功），
            // 整场练习的复盘就取不回来了。
            let voiceStillOn = await offMain { $0.isVoiceActive() }
            try ensureStillRunning(ticket)
            if voiceStillOn {
                try await run(.endingVoice, ticket: ticket) { try $0.endVoice() }
            }
            // 走到这里语音一定是关的：要么本来就没开，要么刚刚成功挂断。
            // 放弃时那句「你得自己去挂断」从此不必再说。
            voiceMayBeLive = false

            let requestID = "gui-\(Int(now().timeIntervalSince1970))"
            currentRequestID = requestID
            let marker = ReviewRequestPrompt.marker(requestID: requestID)
            let request = ReviewRequestPrompt.build(requestID: requestID, focusPart: setup.focusPart)
            // **发之前先数一次已经写完的助手回复。** 这就是等回复的基线。
            //
            // 没有它的时候，「等 ChatGPT 写完复盘」的判据只有「屏幕上最长那段文字不再变长」——
            // 而此刻屏幕上摆着整场语音的逐字稿，加上下一行刚发出去的那条一千多字的请求本身，
            // 两样都在、都不动，于是判据在 ChatGPT 一个字都没答之前就成立，
            // 约一秒半后就往下走去按复制按钮，复制到的是**考官最后一句话**。
            // （那句话短于 200 字符时会被 `ClipboardFallback` 拦下、落到手动 ⌘C；
            // 长于 200 字符时就真的被当成复盘归档了。两条都是坏结果。）
            let repliesBefore = await offMain { $0.assistantReplyCount() }
            try ensureStillRunning(ticket)
            // 复盘请求发在 endVoice 之后，那时语音框已经不在了，用 .any。
            try await run(.requestingReview, ticket: ticket) { try $0.sendText(request, into: .any) }
            let replyTimeout = replyTimeout
            try await run(.requestingReview, ticket: ticket) {
                try $0.waitForAssistantReply(timeout: replyTimeout, minimumLength: 60,
                                             afterReplyCount: repliesBefore)
            }

            guard let raw = try await captureReview(marker: marker.open, ticket: ticket) else {
                return   // 已经转到 .needsManualCopy，等用户手动 ⌘C
            }
            try ensureStillRunning(ticket)
            do {
                try archive(raw: raw, setup: setup, sessionID: sessionID, retryOnFailure: .wrapUp)
            } catch let error as CoachError where error.isReviewFormatProblem {
                // **格式不对就自动再问一次，并告诉它上次错在哪。**
                //
                // 此前这里直接失败，屏幕上摆出一颗「重新取复盘」等用户去点——而点下去
                // 发的是**一模一样**的提示词，ChatGPT 手上没有任何新信息，
                // 多半再给一份同样形状的输出，等于白点一次。
                //
                // 只重问一次。第二次还不行说明不是一次偶然的截断，接着自动重发只会
                // 一遍遍往那条对话里贴一千多字，而用户在旁边干等。
                try await reaskForReview(setup: setup, sessionID: sessionID,
                                         requestID: requestID, focusPart: setup.focusPart,
                                         problem: Self.diagnosisOnly(error), ticket: ticket)
            }
        } catch {
            // 代次对不上 = 用户在等复盘那一分钟里按了「放弃这一场」（「取消」按钮
            // 在这一步上挂得最久）。**什么都不做就是全部要做的事**：不发复盘请求、
            // 不动剪贴板、不归档，也不改屏幕。归档下去的后果是他明确放弃的这一场，
            // 最后在「训练记录」里显示成一场正常完成、带完整复盘报告的练习。
            guard ticket == generation else { return }
            fail(error, retry: .wrapUp)
            throw error
        }
    }

    /// 第一份复盘格式不对时，**告诉 ChatGPT 哪里不对，让它重出一份**。
    ///
    /// 三件事和第一次问不一样，一件都不能省：
    ///
    /// 1. 发的是 `ReviewRequestPrompt.retry(...)`，开头写明上次错在哪、并明令
    ///    「不要重复上一条回复」——原样再发一遍同一份提示词是白发一次。
    /// 2. 阶段是 `.reaskingReview` 而不是 `.requestingReview`：用户得知道刚才那次
    ///    失败了、而工具正在替他救这一场，不然他看到的是同一句话又转了一遍圈。
    /// 3. 基线重新取一次。上一条（格式不对的那份）此刻已经写完并计进条数里了，
    ///    拿第一次那个旧基线的话，判据一进来就成立，又会去复制那份坏的。
    ///
    /// 这一次再失败就**照常抛出去**，由外层 `catch` 摆出「重新取复盘」那颗按钮。
    /// 那时那句提示说的是实话：两次自动尝试都没成，确实该由人来看一眼了。
    private func reaskForReview(setup: SessionSetup, sessionID: String, requestID: String,
                                focusPart: FocusPart, problem: String, ticket: Int) async throws {
        let retryPrompt = ReviewRequestPrompt.retry(requestID: requestID,
                                                    focusPart: focusPart, problem: problem)
        let repliesBefore = await offMain { $0.assistantReplyCount() }
        try ensureStillRunning(ticket)
        try await run(.reaskingReview, ticket: ticket) { try $0.sendText(retryPrompt, into: .any) }
        let replyTimeout = replyTimeout
        try await run(.reaskingReview, ticket: ticket) {
            try $0.waitForAssistantReply(timeout: replyTimeout, minimumLength: 60,
                                         afterReplyCount: repliesBefore)
        }
        let marker = ReviewRequestPrompt.marker(requestID: requestID)
        guard let raw = try await captureReview(marker: marker.open, ticket: ticket) else {
            return   // 已经转到 .needsManualCopy，等用户手动 ⌘C
        }
        try ensureStillRunning(ticket)
        try archive(raw: raw, setup: setup, sessionID: sessionID, retryOnFailure: .wrapUp)
    }

    /// 两条自动路都断了之后，用户照提示按了 ⌘C，再点一下按钮走这里。
    public func captureReviewFromClipboard() async throws {
        // 与 `finishPractice()` 共用同一道重入守卫：这颗按钮同样挂着回车快捷键，
        // 连点两下会读两次剪贴板、归档两次，同一场练习留下两份档案。
        guard !isWrappingUp else { return }
        isWrappingUp = true
        defer { isWrappingUp = false }
        let ticket = generation

        guard let setup = current, let sessionID = currentSessionID else {
            let message = "现在没有正在等待取回的复盘。"
                + "下一步：关掉这个窗口，回到「今日训练」重新开始一场。"
            stage = .failed(message)
            retry = nil
            throw CoachError.reviewNotFound(message)
        }
        stage = .capturingReview
        do {
            let raw = try await offMainThrowing { [pasteboard] _ in
                try ClipboardFallback.readReview(from: pasteboard)
            }
            try ensureStillRunning(ticket)
            try archive(raw: raw, setup: setup, sessionID: sessionID, retryOnFailure: .clipboard)
        } catch {
            // 读剪贴板那一下里用户按了「放弃这一场」。归档下去的话，他明确放弃的这一场
            // 会带着完整复盘报告出现在「训练记录」里；改屏幕则会盖掉那张交代卡片。
            guard ticket == generation else { return }
            // 剪贴板里没有东西 / 内容太短，都还能再复制一次——**别把路堵死成失败态**。
            stage = .needsManualCopy(Self.describeFailure(error, at: .capturingReview))
            retry = .clipboard
        }
    }

    /// 用户中途放弃这一场。
    ///
    /// 用户按这颗按钮时想要的是一件很具体的事：**立刻停下，别再动我的 ChatGPT，
    /// 也别动我的剪贴板。** 所以这里保证三条：
    ///
    /// 1. 已经甩到主线程外面的那一步收不回来（AX 调用是阻塞、不可中断的），
    ///    但**它之后一次 ChatGPT 操作、一次剪贴板操作都不会再有**——
    ///    靠的是把代次 +1，那条链路每一步之前都要拿出发时的代次比一次。
    /// 2. 麦克风当场关掉，而且**再也不会被这条链路重新打开**（同上）。
    /// 3. 界面停在 `.abandoned` 那张交代卡片上，**不是空闲态**：
    ///    放弃这一刻有三件事必须让用户知道，见下面 `describeCancellation`。
    ///
    /// **不去替用户挂断 ChatGPT 那通语音**：那恰恰是他刚叫停的那件事。
    /// 该做的是如实告诉他通话还开着、请他自己挂——见那句交代。
    public func cancel() {
        // **第一件事。** 代次一变，还挂在 AX 调用里的那条链路就再也走不动了。
        generation += 1
        // 不停掉的话，那个 Task 会一直转下去——一边空转，一边把用户放弃之后
        // 在 ChatGPT 里做的别的事采进这一场的逐字稿里。
        stopSampling()
        // 逐字稿要在 `collector.abandon` 之前数：那之后它就该被当成丢掉的了，
        // 而「丢掉了多少」正是要对用户交代的东西。
        let collected = collector.turns.count
        // 放弃这一场也要把录音关掉：不关的话麦克风会一直开着（系统状态栏上那个
        // 橙点会一直亮），已经录下的那几分钟也停在缓冲区里没人写盘。
        // **注意它可能刚生成一条录音警告**（中途插拔耳机断过、写盘失败），
        // 所以界面绝不许在同一帧把窗口关掉——那句话会一帧都没画出来就没了。
        finalizeRecording()
        collector.abandon(reason: "你中途取消了这次练习。")
        // **把盘上那个占位清掉。** 他是明确按了「放弃这一场」的，
        // 下次开 App 再问他一次「上一场没正常结束，要不要留着」是把已经做过的决定
        // 再问一遍；而那条记录里的逐字稿去哪儿了，下面那段交代已经说过了。
        try? store.mutate { state in
            if state.currentSession?.id == self.currentSessionID { state.currentSession = nil }
        }
        // **这一句此前整条取消路径上都没有。** 收集器把「这一场没有正常走完、
        // 中间有几次没读到界面」那段说明生成出来了，却没有任何人把它交给界面，
        // 于是采样失败连同「已经记下几条」一起悄悄没了——正是本项目最忌讳的失败形态。
        transcriptNotice = collector.notice
        current = nil
        currentRequestID = nil
        currentSessionID = nil
        archiveNotice = nil
        retry = nil
        stage = .abandoned(describeCancellation(discardedTurns: collected))
    }

    /// 放弃这一场之后，屏幕上那段交代。
    ///
    /// **三件事一件都不能省**，它们各自对应一次真实的损失：
    ///
    /// - ChatGPT 那通语音本工具不会去挂（挂了就成了「你叫停之后它还在动你的 ChatGPT」），
    ///   不说的话用户的麦克风在 ChatGPT 那边一直开着，而他毫不知情；
    /// - 已经采到的逐字稿到底存了还是丢了——按下去的按钮写着「放弃这一场」，
    ///   多半就是想丢，但**丢没丢得让他知道**；
    /// - 已经录下的那一段留在磁盘上、不属于任何一场训练记录，得告诉他去哪儿找。
    private func describeCancellation(discardedTurns: Int) -> String {
        var lines = ["这一场已经放弃了。本工具不会再操作 ChatGPT，也不会再动你的剪贴板。"]
        if voiceMayBeLive {
            lines.append("ChatGPT 那边的语音通话不会被自动挂断——你按的就是别再动它。"
                + "下一步：切到 ChatGPT 自己把那通语音挂掉，麦克风才会真的停。")
        }
        if let sessionID = finishedSessionID {
            // 收尾走到一半才放弃：这一场早在取复盘之前就落盘了（那是刻意的，
            // 见 `finishPractice`），删掉它反而是又一次数据损失。如实说它在哪儿。
            lines.append("这一场已经记进「训练记录」了，编号 \(sessionID)，"
                + "只是没有复盘报告；已经记下的 \(discardedTurns) 条对话和这次的录音都挂在它上面。")
        } else if discardedTurns > 0 {
            lines.append("这一场不会进「训练记录」：已经记下的 \(discardedTurns) 条对话"
                + "跟着一起丢掉了，没有保留。")
        }
        if finishedSessionID == nil, !recordingRelativePath.isEmpty {
            lines.append("已经录下的那一段留在 \(recordingRelativePath)，"
                + "没有任何一场训练记录指向它。"
                + "下一步：到「录音设置」（⌘,）点「打开录音文件夹」就能找到它。")
        }
        lines.append("下一步：点「关掉」回到主界面。")
        return lines.joined(separator: "\n")
    }

    // MARK: - 取复盘：三级降级

    /// ① 按 ChatGPT 自己的复制按钮（主路径：复盘在 AX 树里被切成大量碎片，逐节点找完整标记
    ///    永远找不到，见 spec 2.3.9）→ ② 带标记直接读 AX 树 → ③ 请用户手动 ⌘C。
    ///
    /// 返回 nil 表示前两级都没走通、已经转入 `.needsManualCopy`。**不抛错**：
    /// 复盘这时完整地留在 ChatGPT 窗口里，一次 ⌘C 就能救回来，判成失败等于让用户白练一场。
    ///
    /// **抛 `PracticeAbandoned` 是唯一的例外**：第一级那一下会把用户的剪贴板
    /// 先清空再写上复盘内容。放弃之后再走这一步，用户刚复制的那段文字/账号/链接就没了，
    /// 而全程一个字的提示都没有。所以每一级之前都先验一次代次。
    private func captureReview(marker: String, ticket: Int) async throws -> String? {
        try ensureStillRunning(ticket)
        // **阶段先设、再 await**（同 `run(_:_:)`）。第一级最长要等 `copyTimeout` 秒，
        // 设在它后面的话，这段时间界面上写的还是上一步那句「正在请 ChatGPT 写复盘…
        // 可能要一分钟左右」——用户会以为还在等 ChatGPT 写字。
        // 顺带：设在后面时 happy path 上 `.capturingReview` 根本不会出现，
        // 进度清单里「取回复盘」那一格永远不会作为当前步骤亮起。
        stage = .capturingReview

        var reasons: [String] = []
        do {
            let timeout = copyTimeout
            return try await offMainThrowing { [pasteboard] bridge in
                try bridge.copyLatestAssistantMessage(pasteboard: pasteboard, timeout: timeout)
            }.nonEmptyOrThrow(timeout: timeout)
        } catch {
            reasons.append("复制按钮这条路没走通（\(error.localizedDescription)）")
        }
        try ensureStillRunning(ticket)
        do {
            return try await offMainThrowing { try $0.captureLatestAssistantMessage(expectedMarker: marker) }
        } catch {
            reasons.append("直接读 ChatGPT 窗口也没读到（\(error.localizedDescription)）")
        }
        try ensureStillRunning(ticket)

        stage = .needsManualCopy(
            "自动取复盘的两条路都没走通：\(reasons.joined(separator: "；"))。"
                + "复盘本身没丢——它还完整地在 ChatGPT 窗口里。"
                + "下一步：切到 ChatGPT，选中整段复盘（含首尾那两行 <<<…>>> 标记）按 ⌘C，"
                + "然后回到这里点「\(PracticeRetry.clipboard.buttonTitle)」。")
        retry = .clipboard
        return nil
    }

    // MARK: - 落盘、解析、归档

    /// **顺序不能反：先把原文写到盘上，再解析。**
    ///
    /// 反过来写的话，解析一抛错，用户练了一整场换来的复盘原文就没了，只能从头再练一次。
    /// spec 第 5 节的原话是「复盘先落盘再入库，中途崩溃或误关窗口都不丢数据」。
    ///
    /// `retryOnFailure` 是**调用方失败时会摆出来的那颗按钮**，因为这里写的「下一步」要指名道姓
    /// 提到它。两条调用路径摆出来的按钮不一样（收尾那条是「重新取复盘」，手动复制那条是
    /// 「我已经复制好了」），写死一个的话，其中一条路上的用户会照着提示去找一颗不存在的按钮。
    private func archive(raw: String, setup: SessionSetup, sessionID: String,
                         retryOnFailure: PracticeRetry) throws {
        stage = .archiving

        let pendingPath: URL
        do {
            pendingPath = try PendingReviewStore.write(rawText: raw, sessionID: sessionID,
                                                       directory: directory)
        } catch {
            // 写不下去就必须说出来。**不能 try? 吞掉再往下走**——那样解析失败时
            // 上面那句「原文没丢」就成了假话（铁律 7）。
            throw CoachError.stateUnreadable(
                "复盘取回来了，但没能存进 \(directory.pendingReviewsDirectory.path)"
                    + "（系统说：\(error.localizedDescription)）。"
                    + "下一步：先别关这个窗口，切到 ChatGPT 把复盘全文复制下来自己存一份；"
                    + "然后确认「\(directory.root.path)」这个目录存在且可写。")
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
        } catch {
            // 这里**只取诊断、丢掉它自带的「下一步」**，理由见 `diagnosisOnly(_:)`：
            // `ReviewParser` 那句「下一步：点「补生成复盘报告」…」说的是命令行时代的操作。
            //
            // 也**不许把用户推回终端**（不提 `coach reimport`）：界面里已经有
            //「重新导入待处理的复盘」这条路，出错恰恰是「全程不用终端」最该成立的时候。
            throw CoachError.invalidReviewText(
                "复盘取回来了，但不是本工具认得的格式，解析不出来（\(Self.diagnosisOnly(error))）。"
                    + "好消息是原文一个字都没丢，就在 \(pendingPath.path)，"
                    + "这一场也已经记进训练记录了。"
                    + "下一步：先点「\(retryOnFailure.buttonTitle)」再取一次；"
                    + "还是不行的话，打开上面那个文件看看 ChatGPT 到底输出了什么"
                    + "（多半是被截断了，末尾少个 }）；"
                    + "或者回 ChatGPT 让它按要求重新输出一次，把那一整段复制下来，"
                    + "再到「复盘报告」页点「从剪贴板补录这一场的复盘」。")
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        let outcome = try store.mutate { state -> ArchiveOutcome in
            let result = ReviewArchiver.archive(report: report, into: state,
                                                sessionID: sessionID,
                                                questionID: setup.question.id,
                                                at: timestamp)
            state = result.state
            return result
        }
        try writeReport(report, sessionID: sessionID)
        upsertSession(id: sessionID, setup: setup, reportPath: "reports/\(sessionID).json",
                      recordingPath: recordingRelativePath)
        let state = try store.load()

        var notice = "错题本 \(state.issues.count) 条，词汇本 \(state.vocabulary.count) 条，"
            + "重训目标 \(state.targets.count) 个。复盘原文存在 \(pendingPath.path)。"
        if !outcome.skipped.isEmpty {
            // 静默的 0 是本项目已知最危险的失败形态：复盘写得完整、档案却纹丝不动。
            notice += "\n⚠️ 复盘里有 \(outcome.skipped.joined(separator: "、"))，但一条都没能归进档案，"
                + "多半是 ChatGPT 用的字段名和本工具读的对不上。"
                + "下一步：原文已经完整保存在上面那个路径，可以打开对照着看；"
                + "这次练习的计划进度和题目状态已经正常更新，另外请把这个情况告诉开发者。"
        }
        archiveNotice = notice

        current = nil
        currentRequestID = nil
        currentSessionID = nil
        retry = nil
        stage = .done
    }

    /// 把解析后的复盘写成 `reports/<id>.json`。
    ///
    /// 存的是解析后的复盘本身，不是带定界标记的原文——原文归 `pending-reviews/`。
    /// 复盘报告页读的就是这个文件。
    private func writeReport(_ report: JSONValue, sessionID: String) throws {
        try directory.createIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        do {
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(sessionID).json"),
                       options: .atomic)
        } catch {
            throw CoachError.stateUnreadable(
                "复盘解析出来了，但没能写成报告文件 reports/\(sessionID).json"
                    + "（系统说：\(error.localizedDescription)）。"
                    + "好消息是原文和这一场的训练记录都还在。"
                    + "下一步：确认「\(directory.root.path)」这个目录存在且可写，"
                    + "然后到「复盘报告」页用「重新导入待处理的复盘」重试一次。")
        }
    }

    /// 把这一场写进 `state.sessions`。**按 id upsert，不是无脑 append**——
    /// 同一个编号重存不该产生第二条记录（Phase 9 的 `save_session_review` 也按同样规则做）。
    ///
    /// 会被调用两次：取复盘**之前**一次（那时还没有报告路径），归档成功之后再一次
    /// （补上 `reportPath`）。中间任何一步失败，第一次写下的东西都不回滚。
    ///
    /// `reportPath` 与 `recordingPath` 都是**非 nil 才写**：nil 的含义是「这一次没有新值」，
    /// 不是「把已有的清空」。空串同样当成「没有」——一秒都没录到时录音文件已经被删了，
    /// 写一个指向已删文件的路径，训练记录页会据此画出一个点了没声音的播放器。
    private func upsertSession(id: String, setup: SessionSetup, reportPath: String?,
                               recordingPath: String?) {
        let formatter = ISO8601DateFormatter()
        do {
            try store.mutate { state in
                var session = state.sessions.first { $0.id == id }
                    ?? PracticeSession(id: id, questionId: setup.question.id,
                                       focusPart: setup.focusPart,
                                       startedAt: formatter.string(from: self.startedAt ?? self.now()),
                                       endedAt: "", goal: setup.goal,
                                       transcript: [], reportPath: "", recordingPath: "",
                                       drawnQuestionIds: self.drawnQuestionIds(in: setup))
                session.endedAt = formatter.string(from: self.now())
                session.transcript = self.collector.turns
                if let reportPath { session.reportPath = reportPath }
                if let recordingPath, !recordingPath.isEmpty {
                    session.recordingPath = recordingPath
                }
                if let index = state.sessions.firstIndex(where: { $0.id == id }) {
                    state.sessions[index] = session
                } else {
                    state.sessions.append(session)
                }
                if state.currentSession?.id == id { state.currentSession = nil }
            }
        } catch {
            // 训练记录写不进去是真事故（这一场就真的没了），必须让用户看见（铁律 7）。
            transcriptNotice = "这一场没能存进训练记录：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重新练一场；"
                + "复盘原文若已取回，仍然保存在 pending-reviews 目录里。"
        }
    }

    /// 随机抽题那一场安排到的整组题号；普通练习是 nil。
    ///
    /// **必须记下来**：这一组 id 是「这几道题练过了」唯一的凭据
    /// （`CoachState.reconcilePracticedStatus`）。只记开场那一道的话，
    /// 同一场里另外几道会永远停在「新题」，于是「只抽没练过的」一遍遍把它们再抽出来，
    /// 训练题库页那个「已练 N / 258」也永远少数它们——两样都不报错。
    private func drawnQuestionIds(in setup: SessionSetup) -> [String]? {
        setup.drawnQuestions.isEmpty ? nil : setup.drawnQuestions.map(\.id)
    }

    // MARK: - 跑一步

    /// 把一步阻塞调用甩到主线程之外跑，并在跑之前把阶段更新到界面上。
    ///
    /// 阶段先设、再 await：反过来的话，界面在这一步跑完之前显示的还是上一步，
    /// 最长的那一步（启动语音，实测约 9 秒）就成了一段没有任何提示的空白等待。
    ///
    /// **前后各验一次代次**，两次都不能省：
    ///
    /// - 前面那次挡住「上一步跑着的时候用户按了取消，这一步还照发不误」；
    /// - 后面那次挡住「这一步跑着的时候用户按了取消，回来之后还接着往下走」。
    ///   收尾链路上最长的一步（等 ChatGPT 写复盘）默认要等 60 秒，
    ///   而「取消」按钮恰恰在这一步上挂得最久——少了后面那次验，
    ///   用户按完取消的一分钟里，ChatGPT 还会收到复盘请求、剪贴板还会被覆盖。
    private func run(_ stage: PracticeStage, ticket: Int,
                     _ body: @escaping @Sendable (any CoachBridge & Sendable) throws -> Void) async throws {
        try ensureStillRunning(ticket)
        self.stage = stage
        try await offMainThrowing(body)
        try ensureStillRunning(ticket)
    }

    /// 这一条链路还是「当前这一场」吗？不是就抛 `PracticeAbandoned` 让它退场。
    private func ensureStillRunning(_ ticket: Int) throws {
        guard ticket == generation else { throw PracticeAbandoned() }
    }

    private func offMain<T: Sendable>(
        _ body: @escaping @Sendable (any CoachBridge & Sendable) -> T) async -> T {
        let bridge = self.bridge
        return await Task.detached(priority: .userInitiated) { body(bridge) }.value
    }

    private func offMainThrowing<T: Sendable>(
        _ body: @escaping @Sendable (any CoachBridge & Sendable) throws -> T) async throws -> T {
        let bridge = self.bridge
        return try await Task.detached(priority: .userInitiated) { try body(bridge) }.value
    }

    /// 一场练习里所有失败的唯一出口。
    ///
    /// **「问题反馈」页的「最近一次错误」就在这里记一笔**（Phase 10 Task 18）：
    /// 只记阶段与错误代号，`error` 的消息一个字都不进去——它里面完全可能夹着复盘原文，
    /// 而复盘原文里全是用户说过的英语（见 `LastErrorLog`）。
    /// 屏幕上那句给用户看的话仍然是完整的 `describeFailure`，两者互不影响。
    private func fail(_ error: any Error, retry: PracticeRetry) {
        let failedAt = stage
        LastErrorLog.shared.record(error, at: failedAt.diagnosticsStage)
        stage = .failed(Self.describeFailure(error, at: failedAt))
        self.retry = retry
    }

    /// 取一个错误里「发生了什么」那半句，**把它自带的「下一步」丢掉**。
    ///
    /// 用在「我要把别人的错误嵌进我自己的一句话里，而我随后会写我自己的下一步」这种场合。
    ///
    /// 为什么非丢不可：`ReviewParser` 在 `IELTSCoachCore` 里，`coach` 命令行也在用它，
    /// 它那句「下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次」在命令行那边是对的，
    /// 但**这颗按钮在图形界面里根本不存在**（`grep 'Button(' Sources/IELTSCoachUI/` 一个都没有）。
    /// 原样转述过来，用户会照着去找一颗找不到的按钮（铁律 4：下一步必须是真做得到的一步）。
    ///
    /// **不改 Core 的文案**：命令行那边照它做是对的，改了反而把两边一起弄坏。
    /// 该退让的是界面这一侧——同样的做法 `ReviewReportLoader` 已经用过一次。
    ///
    /// 只砍「下一步」及其之后，前半句诊断（「没有返回可识别的标准复盘JSON」之类）留着：
    /// 那是用户判断该怎么处理的依据，砍掉就只剩一句「解析不出来」。
    static func diagnosisOnly(_ error: any Error) -> String {
        let detail = error.localizedDescription
        guard let cut = detail.range(of: "下一步") else { return detail }
        let head = detail[..<cut.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: " 　\n。；;，,"))
        // 整句话就是一句「下一步：…」时，砍完会什么都不剩。那时宁可原样保留，
        // 也不能返回空串——空串会让上层那句话变成「解析不出来（）」，用户一头雾水。
        return head.isEmpty ? detail : head
    }

    /// 把一个错误翻译成用户照着做得下去的一句话。
    ///
    /// **不能直接用 `error.localizedDescription`**：`BridgeError` 与 `CoachError` 自带中文的
    /// 「下一步」，但磁盘、权限之类的失败抛出来的是系统 NSError——它只说发生了什么，
    /// 不说下一步做什么，措辞也未必是中文（铁律 6）。做法与 `AppState.describeLoadFailure` 一致。
    static func describeFailure(_ error: any Error, at stage: PracticeStage) -> String {
        let detail = error.localizedDescription
        let head = "「\(stage.stepName)」这一步没成功：\(detail)"
        if detail.contains("下一步") { return head }
        return head + "。下一步：切到 ChatGPT 看一眼窗口是不是停在对话界面、没有弹窗挡住，"
            + "然后回到这里重试；若一直失败，把这段话记下来告诉开发者。"
    }
}

private extension String {
    /// 复制按钮那条路返回空串时当成失败，好让第二条路还有机会跑。
    ///
    /// 真实的 `AXDriver.copyLatestAssistantMessage` 会经 `ClipboardFallback` 挡掉空内容，
    /// 这里再兜一层是因为：拿一份空复盘去落盘、解析、归档，最后得到的是一句
    /// 「解析失败」加一个空文件——用户完全看不出真正的毛病是复制按钮没起作用。
    func nonEmptyOrThrow(timeout: TimeInterval) throws -> String {
        guard !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError.elementNotFound(
                "按了复制按钮，但等了 \(Int(timeout)) 秒剪贴板里还是空的。"
                    + "下一步：这多半是 ChatGPT 改了界面，本工具会自动改试另一条路。")
        }
        return self
    }
}
