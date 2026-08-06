import ChatGPTBridge
import Foundation
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

    private let bridge: any CoachBridge & Sendable
    private let pasteboard: any PasteboardAccess
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

    /// 超时值全部与 `coach practice` 保持一致（那几个数是按实测时序定的，见 spec 2.3.7）。
    /// **要短超时请在测试里显式传参，不要改这里的默认值。**
    ///
    /// - Parameter transcript: 逐字稿采样器。传 nil 表示用户在设置里关掉了
    ///   「记录对话逐字稿」，此时安静地什么都不做。**刻意不挂在 `CoachBridge` 上**，
    ///   理由见 `TranscriptSampling` 的注释。
    public init(bridge: any CoachBridge & Sendable,
                pasteboard: any PasteboardAccess,
                directory: DataDirectory = .resolve(),
                transcript: (any TranscriptSampling)? = nil,
                composerTimeout: TimeInterval = 20,
                replyTimeout: TimeInterval = 60,
                copyTimeout: TimeInterval = 10,
                samplingInterval: TimeInterval = 2.5,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.bridge = bridge
        self.pasteboard = pasteboard
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
        current = setup
        currentRequestID = nil
        currentSessionID = nil
        finishedSessionID = nil
        transcriptNotice = nil
        startedAt = now()
        archiveNotice = nil
        retry = nil
        let prompt = ExaminerPrompt.build(setup: setup)
        do {
            try await run(.newChat) { try $0.startNewChat() }
            try await run(.startingVoice) { try $0.startVoice() }
            let timeout = composerTimeout
            try await run(.waitingComposer) { _ = try $0.waitForVoiceComposer(timeout: timeout) }
            try await run(.sendingPrompt) { try $0.sendText(prompt) }
            beginCollectingTranscript()
            stage = .practicing
        } catch {
            stopSampling()
            fail(error, retry: .restart)
            throw error
        }
    }

    /// 逐字稿从**考官提示词已经发出去之后**才开始收集。
    ///
    /// 早一步的话，那条两千字符的考官提示词就不会被当成背景板，而是被当成对话内容
    /// 采进逐字稿里——而它恰恰是屏幕上最长的一段文字。
    private func beginCollectingTranscript() {
        collector.begin()
        samplingTask = Task { [weak self, samplingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(samplingInterval))
                if Task.isCancelled { return }
                self?.collector.tick()
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
        upsertSession(id: sessionID, setup: setup, reportPath: nil)
        finishedSessionID = sessionID

        do {
            // 用户自己在 ChatGPT 里挂断时语音已经结束了。这时再按一次「结束通话」，
            // `AXDriver.endVoice` 会直接抛错（它刻意不把「本来就没在通话」当成成功），
            // 整场练习的复盘就取不回来了。
            let voiceStillOn = await offMain { $0.isVoiceActive() }
            if voiceStillOn {
                try await run(.endingVoice) { try $0.endVoice() }
            }

            let requestID = "gui-\(Int(now().timeIntervalSince1970))"
            currentRequestID = requestID
            let marker = ReviewRequestPrompt.marker(requestID: requestID)
            let request = ReviewRequestPrompt.build(requestID: requestID, focusPart: setup.focusPart)
            try await run(.requestingReview) { try $0.sendText(request) }
            let replyTimeout = replyTimeout
            try await run(.requestingReview) {
                try $0.waitForAssistantReply(timeout: replyTimeout, minimumLength: 60)
            }

            guard let raw = await captureReview(marker: marker.open) else {
                return   // 已经转到 .needsManualCopy，等用户手动 ⌘C
            }
            try archive(raw: raw, setup: setup, sessionID: sessionID, retryOnFailure: .wrapUp)
        } catch {
            fail(error, retry: .wrapUp)
            throw error
        }
    }

    /// 两条自动路都断了之后，用户照提示按了 ⌘C，再点一下按钮走这里。
    public func captureReviewFromClipboard() async throws {
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
            try archive(raw: raw, setup: setup, sessionID: sessionID, retryOnFailure: .clipboard)
        } catch {
            // 剪贴板里没有东西 / 内容太短，都还能再复制一次——**别把路堵死成失败态**。
            stage = .needsManualCopy(Self.describeFailure(error, at: .capturingReview))
            retry = .clipboard
        }
    }

    /// 用户中途放弃这一场。
    ///
    /// 已经发出去的那一步收不回来（AX 调用是阻塞的、不可中断），所以这里只保证两件事：
    /// 界面立刻回到空闲态，以及**之后不会再有任何一次 ChatGPT 操作**——
    /// 用户放弃之后多半已经在用 ChatGPT 做别的事了，这时再冒出来按一下「结束通话」很吓人。
    public func cancel() {
        // 不停掉的话，那个 Task 会一直转下去——一边空转，一边把用户放弃之后
        // 在 ChatGPT 里做的别的事采进这一场的逐字稿里。
        stopSampling()
        collector.abandon(reason: "你中途取消了这次练习。")
        current = nil
        currentRequestID = nil
        currentSessionID = nil
        archiveNotice = nil
        retry = nil
        stage = .idle
    }

    // MARK: - 取复盘：三级降级

    /// ① 按 ChatGPT 自己的复制按钮（主路径：复盘在 AX 树里被切成大量碎片，逐节点找完整标记
    ///    永远找不到，见 spec 2.3.9）→ ② 带标记直接读 AX 树 → ③ 请用户手动 ⌘C。
    ///
    /// 返回 nil 表示前两级都没走通、已经转入 `.needsManualCopy`。**不抛错**：
    /// 复盘这时完整地留在 ChatGPT 窗口里，一次 ⌘C 就能救回来，判成失败等于让用户白练一场。
    private func captureReview(marker: String) async -> String? {
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
        do {
            return try await offMainThrowing { try $0.captureLatestAssistantMessage(expectedMarker: marker) }
        } catch {
            reasons.append("直接读 ChatGPT 窗口也没读到（\(error.localizedDescription)）")
        }

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
                    + "（多半是被截断了，末尾少个 }），或者回 ChatGPT 让它按要求重新输出一次，"
                    + "再到「复盘报告」页用「重新导入待处理的复盘」把这份原文补进来。")
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
        upsertSession(id: sessionID, setup: setup, reportPath: "reports/\(sessionID).json")
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
    private func upsertSession(id: String, setup: SessionSetup, reportPath: String?) {
        let formatter = ISO8601DateFormatter()
        do {
            try store.mutate { state in
                var session = state.sessions.first { $0.id == id }
                    ?? PracticeSession(id: id, questionId: setup.question.id,
                                       focusPart: setup.focusPart,
                                       startedAt: formatter.string(from: self.startedAt ?? self.now()),
                                       endedAt: "", goal: setup.goal,
                                       transcript: [], reportPath: "", recordingPath: "")
                session.endedAt = formatter.string(from: self.now())
                session.transcript = self.collector.turns
                if let reportPath { session.reportPath = reportPath }
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

    // MARK: - 跑一步

    /// 把一步阻塞调用甩到主线程之外跑，并在跑之前把阶段更新到界面上。
    ///
    /// 阶段先设、再 await：反过来的话，界面在这一步跑完之前显示的还是上一步，
    /// 最长的那一步（启动语音，实测约 9 秒）就成了一段没有任何提示的空白等待。
    private func run(_ stage: PracticeStage,
                     _ body: @escaping @Sendable (any CoachBridge & Sendable) throws -> Void) async throws {
        self.stage = stage
        try await offMainThrowing(body)
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

    private func fail(_ error: any Error, retry: PracticeRetry) {
        let failedAt = stage
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
