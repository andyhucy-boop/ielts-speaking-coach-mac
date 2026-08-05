import ChatGPTBridge
import Foundation
import IELTSCoachCore
import Observation

/// 失败之后「重试」到底该重做什么。
///
/// **这个区分不是锦上添花。** 开练阶段失败时重做的是整条链路，第一步是按「新建会话」；
/// 而收尾阶段失败时若也去按「新建会话」，那条刚练完、复盘还在里面的会话就当场没了——
/// 用户练的半小时连同复盘一起蒸发，且界面上看着像是「重试了一下」。
public enum PracticeRetry: Equatable, Sendable {
    /// 从头再来一遍（新建会话 → 启动语音 → …）。
    case restart
    /// 只重做收尾（结束语音 → 请复盘 → 取回 → 存档），不碰当前会话。
    case wrapUp
    /// 用户手动 ⌘C 之后，从剪贴板取。
    case clipboard
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

    private let bridge: any CoachBridge & Sendable
    private let pasteboard: any PasteboardAccess
    private let directory: DataDirectory
    private let store: StateStore
    private let composerTimeout: TimeInterval
    private let replyTimeout: TimeInterval
    private let copyTimeout: TimeInterval
    private let now: @Sendable () -> Date

    /// 正在进行的这一场。取消或存档完成后置空——**没有它就不该再去驱动 ChatGPT**，
    /// 那时用户很可能已经在用 ChatGPT 做别的事了。
    private var current: SessionSetup?
    /// 本次复盘请求的 id。取复盘、落盘文件名都用它。
    private var currentRequestID: String?

    /// 超时值全部与 `coach practice` 保持一致（那几个数是按实测时序定的，见 spec 2.3.7）。
    /// **要短超时请在测试里显式传参，不要改这里的默认值。**
    public init(bridge: any CoachBridge & Sendable,
                pasteboard: any PasteboardAccess,
                directory: DataDirectory = .resolve(),
                composerTimeout: TimeInterval = 20,
                replyTimeout: TimeInterval = 60,
                copyTimeout: TimeInterval = 10,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.bridge = bridge
        self.pasteboard = pasteboard
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.composerTimeout = composerTimeout
        self.replyTimeout = replyTimeout
        self.copyTimeout = copyTimeout
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
        current = setup
        currentRequestID = nil
        archiveNotice = nil
        retry = nil
        let prompt = ExaminerPrompt.build(setup: setup)
        do {
            try await run(.newChat) { try $0.startNewChat() }
            try await run(.startingVoice) { try $0.startVoice() }
            let timeout = composerTimeout
            try await run(.waitingComposer) { _ = try $0.waitForVoiceComposer(timeout: timeout) }
            try await run(.sendingPrompt) { try $0.sendText(prompt) }
            stage = .practicing
        } catch {
            fail(error, retry: .restart)
            throw error
        }
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
            try archive(raw: raw, setup: setup, requestID: requestID)
        } catch {
            fail(error, retry: .wrapUp)
            throw error
        }
    }

    /// 两条自动路都断了之后，用户照提示按了 ⌘C，再点一下按钮走这里。
    public func captureReviewFromClipboard() async throws {
        guard let setup = current, let requestID = currentRequestID else {
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
            try archive(raw: raw, setup: setup, requestID: requestID)
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
        current = nil
        currentRequestID = nil
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
        var reasons: [String] = []
        do {
            let timeout = copyTimeout
            return try await offMainThrowing { [pasteboard] bridge in
                try bridge.copyLatestAssistantMessage(pasteboard: pasteboard, timeout: timeout)
            }.nonEmptyOrThrow(timeout: timeout)
        } catch {
            reasons.append("复制按钮这条路没走通（\(error.localizedDescription)）")
        }
        stage = .capturingReview
        do {
            return try await offMainThrowing { try $0.captureLatestAssistantMessage(expectedMarker: marker) }
        } catch {
            reasons.append("直接读 ChatGPT 窗口也没读到（\(error.localizedDescription)）")
        }

        stage = .needsManualCopy(
            "自动取复盘的两条路都没走通：\(reasons.joined(separator: "；"))。"
                + "复盘本身没丢——它还完整地在 ChatGPT 窗口里。"
                + "下一步：切到 ChatGPT，选中整段复盘（含首尾那两行 <<<…>>> 标记）按 ⌘C，"
                + "然后回到这里点「我已经复制好了」。")
        retry = .clipboard
        return nil
    }

    // MARK: - 落盘、解析、归档

    /// **顺序不能反：先把原文写到盘上，再解析。**
    ///
    /// 反过来写的话，解析一抛错，用户练了一整场换来的复盘原文就没了，只能从头再练一次。
    /// spec 第 5 节的原话是「复盘先落盘再入库，中途崩溃或误关窗口都不丢数据」。
    private func archive(raw: String, setup: SessionSetup, requestID: String) throws {
        stage = .archiving

        let pendingPath = directory.pendingReviewsDirectory.appending(path: "\(requestID).txt")
        do {
            try directory.createIfNeeded()
            try raw.write(to: pendingPath, atomically: true, encoding: .utf8)
        } catch {
            // 写不下去就必须说出来。**不能 try? 吞掉再往下走**——那样解析失败时
            // 上面那句「原文没丢」就成了假话（铁律 7）。
            throw CoachError.stateUnreadable(
                "复盘取回来了，但没能存到 \(pendingPath.path)（系统说：\(error.localizedDescription)）。"
                    + "下一步：先别关这个窗口，切到 ChatGPT 把复盘全文复制下来自己存一份；"
                    + "然后确认「\(directory.root.path)」这个目录存在且可写。")
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
        } catch {
            throw CoachError.invalidReviewText(
                "复盘取回来了，但不是本工具认得的格式，解析不出来（\(error.localizedDescription)）。"
                    + "好消息是原文一个字都没丢，就在 \(pendingPath.path)。"
                    + "下一步：打开这个文件看看 ChatGPT 到底输出了什么——多半是被截断了（末尾少个 }）；"
                    + "也可以回 ChatGPT 让它按要求重新输出一次，再用「我已经复制好了」这条路重来。")
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        let outcome = try store.mutate { state -> ArchiveOutcome in
            let result = ReviewArchiver.archive(report: report, into: state,
                                                sessionID: requestID,
                                                questionID: setup.question.id,
                                                at: timestamp)
            state = result.state
            return result
        }
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
        retry = nil
        stage = .done
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
