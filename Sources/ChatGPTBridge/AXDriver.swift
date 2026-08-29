import Foundation

/// `Sendable` 是必须的，不是顺手加的：界面把每一次 AX 调用甩到主线程之外跑
/// （最长的一步——启动语音——实测约 9 秒，放在主线程上窗口会整整冻住九秒），
/// 而跨并发域传递要求这个类型是 Sendable。
/// 保证由编译器给：下面所有存储属性都是 `let`，且各自的类型都已经是 Sendable。
public final class AXDriver: CoachBridge, Sendable {
    private let access: any AXAccess
    private let locator: AXLocator
    // 下面这五个字段都不标 private：只是为了让 AXDriverTests 能直接断言默认值本身是对的
    // （见 testDefaultTimeoutsMatchRealMeasuredStartupDelay 与
    // testDefaultPacingValuesMatchTheMeasuredOnes），不属于对外公开的 API——
    // `coach` 可执行 target 从不读取它们，只调用 AXDriver/CoachBridge 的方法。
    let shortTimeout: TimeInterval
    let stateTimeout: TimeInterval
    /// 写完提示词后等 Send 按钮出现的时长。**实测：按钮是写完文字之后才出现的**，
    /// 而语音模式下它从第 4 秒起就再没出现过（采样到第 25 秒）——所以既不能不等，
    /// 也不能等太久：等满这段时间就退回模拟回车。
    let sendButtonTimeout: TimeInterval
    /// `waitForAssistantReply` 两次采样之间的间隔。判据是「够长的文本连续三次采样不再增长」，
    /// 间隔太密会把流式输出中间的一次停顿误判成「回复完了」。
    let replySampleInterval: TimeInterval
    /// 按下复制按钮之后，留给 ChatGPT 把内容写进剪贴板的时间。不等就会读到刚被自己清空的
    /// 空剪贴板，把「复制成功」误判成「剪贴板是空的」。
    let clipboardSettleDelay: TimeInterval
    /// 决定 preflight 的提示该让用户勾选谁、该拿什么办法收集诊断信息。见 `HostEnvironment`。
    private let host: HostEnvironment

    /// 后三个节奏参数以前是方法体里的字面量，测试无从缩短，导致 `AXDriverTests` 一个类
    /// 就白等 11 秒（Task 10 的耗时回归）。**它们的默认值全部是实测定的，不许为了让测试
    /// 跑得快去改默认值**——要短就在测试里显式传（`AXDriverTests.driver(_:)` 的做法），
    /// 默认值本身由 `testDefaultPacingValuesMatchTheMeasuredOnes` 钉住。
    public init(access: any AXAccess, locator: AXLocator,
                shortTimeout: TimeInterval = 5.0, stateTimeout: TimeInterval = 25.0,
                sendButtonTimeout: TimeInterval = 2.0,
                replySampleInterval: TimeInterval = 0.5,
                clipboardSettleDelay: TimeInterval = 0.8,
                host: HostEnvironment = .current) {
        self.access = access; self.locator = locator
        self.shortTimeout = shortTimeout; self.stateTimeout = stateTimeout
        self.sendButtonTimeout = sendButtonTimeout
        self.replySampleInterval = replySampleInterval
        self.clipboardSettleDelay = clipboardSettleDelay
        self.host = host
    }

    public func preflight() -> BridgeReadiness {
        var messages: [String] = []
        var ok = true
        if !access.isTargetInstalled() {
            messages.append("❌ 没找到 ChatGPT（新版桌面应用）。"
                + "下一步：从 openai.com/chatgpt/download 安装。注意 ChatGPT Classic 没有 live 语音，不能用。")
            ok = false
        }
        if !access.isAccessibilityTrusted() {
            // 勾选谁必须跟着宿主变（见 HostEnvironment）：.app 里勾的是本应用，
            // 终端里跑才是勾终端。给错对象的用户照做一遍回来重试仍然失败，且毫无线索。
            messages.append("❌ 没有辅助功能权限，无法驱动 ChatGPT。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把\(host.accessibilityGrantee)加进去并勾选，"
                + "然后\(host.retryInstruction)。")
            ok = false
        }
        guard ok else { return BridgeReadiness(ok: false, messages: messages) }

        if !access.isTargetRunning() {
            do { try access.launchTarget() } catch {
                messages.append("❌ 没能启动 ChatGPT：\(error.localizedDescription)。"
                    + "下一步：手动打开 ChatGPT 并进入一个会话，然后重试。")
                return BridgeReadiness(ok: false, messages: messages)
            }
        }
        if !access.wakeAccessibilityTree(timeout: 8.0) {
            messages.append("⚠️ ChatGPT 的无障碍树没能唤醒，可能读不到对话内容。"
                + "下一步：把 ChatGPT 窗口切到前台并打开一个会话，然后\(host.retryInstruction)；"
                + "仍失败请\(host.diagnosticsInstruction)。")
        }
        messages.append("✅ 环境就绪")
        return BridgeReadiness(ok: true, messages: messages)
    }

    public func sendText(_ text: String, into target: ComposerTarget) throws {
        let composer: AXNodeSnapshot
        switch target {
        case .voice:
            // **必须重新定位，不能复用 waitForVoiceComposer 那一次的返回值**：
            // 每次 snapshotTree() 都会开启新代次，先前取得的引用会失效。
            // 这里要的是「此刻语音框的最新引用」。
            //
            // **超时用 stateTimeout 而不是 shortTimeout。** 实测语音输入框要等到
            // 第 12 秒左右才出现（spec 2.3.7：语音标志第 9 秒，输入框还要再晚约 3 秒），
            // 而 shortTimeout 是 5 秒——正好卡在它出来之前。
            // 用户报的就是这个：「压根没有等到语音对话中提示框出现的那一刻」。
            composer = try waitForVoiceComposer(timeout: stateTimeout)
        case .any:
            composer = try locator.waitForComposer(timeout: shortTimeout)
        }
        guard access.setValue(text, on: composer.element) else {
            throw BridgeError.actionFailed("写入 ChatGPT 输入框失败。"
                + "下一步：确认 ChatGPT 窗口没有被弹窗挡住，然后重试。")
        }

        // 实测：普通聊天状态下写入文字后会出现 Send 按钮，按它才能发出去（模拟回车无效）；
        // 而语音模式下整个过程都没有 Send 按钮——第 4 秒起就消失，25 秒采样期间再没出现过。
        // 所以两条路都要试，最终一律以「输入框回到空态」为准 —— 走哪条路成功都行，
        // 都失败就报错。press/sendReturnKey 的返回值不单独判断：kAXPressAction 返回 true
        // 不代表 ChatGPT 真收到了（按钮被禁用、焦点跑掉时也可能返回 true），唯一可信的
        // 判据还是下面这条「输入框空了」。
        if let send = try? locator.waitForControl(ChatGPTLabels.sendMessage,
                                                  timeout: sendButtonTimeout) {
            _ = access.press(send.element)
        } else {
            _ = access.sendReturnKey()
        }

        // 操作后验证。这条路径失败被当成成功的后果特别严重：考官提示词没发出去，
        // 语音却正常启动，ChatGPT 就是个普通聊天机器人，用户要练完一整场、
        // 等复盘出来是一团乱麻才发现不对。
        //
        // 判据必须是「输入框空了」，不能是「内容和我写的不一样」——
        // AX 读回的值与写入值不可能逐字节相同（换行与空白会被规范化），
        // 后者一开始就成立，等于没验证。这是本项目第二次栽在
        // 「验证只问现在是不是目标态、没问到底变没变」上。
        //
        // 「空」不是空字符串（spec 2.3.6，本项目第三次栽在判据与实际观测对不上）：
        // 实测空态 value 为「换行 + 该元素自己的 description」（如 "\nMessage ChatGPT"）。
        // 见 AXNodeSnapshot.isEmptyComposer。
        try locator.waitUntil({ nodes in
            guard let composer = ChatGPTLabels.composer(among: nodes) else { return false }
            return composer.isEmptyComposer
        }, timeout: shortTimeout, describing: "提示词发送到 ChatGPT")
    }

    /// 新建一个空会话。Live 语音只能在未发送过消息的会话里启动，
    /// 所以每次练习开始前都要先做这一步，否则 startVoice 会静默失败
    /// （按钮按得下去，但语音起不来）。
    /// 按一颗按钮，**并且确认它真的生效了；没生效就重新找元素再按**。
    ///
    /// ## 为什么必须重按，而不是按一次然后干等
    ///
    /// `AXUIElementPerformAction` 对一个**已经失效的元素**会返回成功、什么都不做
    /// （spec 2.3.1 记过这条：「返回 true 不等于动作生效」）。ChatGPT 是 Chromium，
    /// 「新建会话」按下去之后整个对话区会重挂载一次；我们随后抓的那份树若正好落在
    /// 重绘中途，拿到的元素在按下去那一刻就已经作废了。
    ///
    /// 2026-08-09 用户真机现象：「有时候好有时候又有问题」，失败那次 ChatGPT
    /// **一点反应都没有**，而 App 干等 25 秒后报「语音会话开始仍未发生」。
    /// 重绘落在哪一刻每次都不同，所以时好时坏。
    ///
    /// **本项目的规矩是「等 → 做 → 验」，这里从前只有「等 → 做」。** 补上第三步之后，
    /// 一次落空不再等于整场练习失败：重新抓树（拿到的就是新元素）、重新按一次。
    ///
    /// - Parameters:
    ///   - settled: 怎么算「真的生效了」。**必须是状态判据，不能是按钮返回值。**
    ///   - attempts: 最多按几次。默认 3——重绘窗口是毫秒级的，连撞三次的概率极低；
    ///     无限重试则会在 ChatGPT 真的卡住时变成一场看不见的死循环。
    private func press(_ candidates: [String],
                       until settled: ([AXNodeSnapshot]) -> Bool,
                       attempts: Int = 3,
                       timeout: TimeInterval,
                       failedToPress: String,
                       describing what: String) throws {
        // 每次尝试分到的等待时间。除不尽时宁可多给第一次，不要出现 0 秒的等待。
        let slice = max(timeout / Double(attempts), 0.01)
        var lastPressFailure: BridgeError?

        for attempt in 1...attempts {
            // **每一轮都重新找元素。** 复用上一轮那个正是本 bug 的成因——
            // 它可能已经在重绘里作废了，而作废元素的 press 照样返回 true。
            let button = try locator.waitForControl(candidates, timeout: shortTimeout)
            guard access.press(button.element) else {
                lastPressFailure = .actionFailed(failedToPress)
                continue
            }
            do {
                try locator.waitUntil(settled, timeout: slice, describing: what)
                return
            } catch {
                // 这一轮没等到。还有机会就重新来过；这是最后一轮就把原错误抛出去，
                // 那句话里已经写清了「点击返回成功但 ChatGPT 没有真的响应」。
                if attempt == attempts { throw error }
            }
        }
        // 只有「每一轮 press 都返回 false」才会走到这里。
        throw lastPressFailure ?? .actionFailed(failedToPress)
    }

    /// 新建一个空会话。
    ///
    /// **这一步刻意没有「按完验一眼」。** 不是漏了，是 AX 树上找不到一个诚实的判据：
    /// 新会话与「本来就停在一个空会话上」长得一模一样——输入框空着、对话区没有消息、
    /// 按钮一颗不少。拿这些当判据就落进本项目反复栽过的那个坑：
    /// **验证只问「现在是不是目标态」，没问「到底变没变」**，于是它在没生效时照样通过。
    /// 编一个假验证比不验更糟：不验至少诚实，假验证会让下一个人以为这里守住了。
    ///
    /// 真正兜住这一步的是下一步：Live 语音只能在没发过消息的会话里启动（spec 2.3.5），
    /// 所以「新建会话」没生效时 `startVoice` 起不来——而它现在会重按三次再报错。
    public func startNewChat() throws {
        let button = try locator.waitForControl(ChatGPTLabels.newChat, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下「新建会话」失败。"
                + "下一步：在 ChatGPT 里手动开一个新对话，然后重新运行本命令。")
        }
    }

    /// 等语音模式的输入框出现。**不能用通用的 composer(among:) 查找**——实测第 9~11 秒
    /// 这个窗口里，`Voice chat active` 已经出现，但输入框描述仍是普通聊天态的
    /// "Message ChatGPT"，大约 3 秒后才变成语音态的 "Work with ChatGPT"。通用查找见到
    /// 任意输入框就返回，会在这个窗口里命中普通框，把考官提示词发进错误的地方。
    @discardableResult
    public func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot {
        guard let found = locator.waitForNode(matching: { ChatGPTLabels.voiceComposer(among: $0) },
                                              timeout: timeout) else {
            throw BridgeError.elementNotFound(
                "语音已经启动，但等了 \(Int(timeout)) 秒仍没等到语音模式的输入框出现。"
                + "下一步：看一眼 ChatGPT 窗口是不是真的进了语音界面；"
                + "若已经进了但输入框迟迟不出现，可能是这一版 ChatGPT 改了界面，请把这条错误告诉开发者。")
        }
        return found
    }

    public func startVoice() throws {
        // 前置校验，防的是「验证没区分『变成了』和『本来就是』」这个陷阱：
        // 语音已经在跑时按「启动」，ChatGPT 多半什么都不做，而下面的
        // waitUntil(isVoiceActive) 会立刻通过——我们以为启动成功了，实际上用户是
        // 接着上一场没结束的通话在练，本次的考官提示词（可能是不同的 Part、
        // 不同的反馈模式）完全没生效，而 App 显示一切正常。
        guard !isVoiceActive() else {
            throw BridgeError.stateNotReached(
                "ChatGPT 里已经有一场语音通话在进行中，不能再开一场。"
                + "下一步：先在 ChatGPT 窗口里结束当前通话，再重新开始练习。")
        }
        // kAXPressAction 返回成功不等于动作生效（spec 2.3.1），必须验证状态真的变了。
        //
        // 实测：点下语音按钮后约 9 秒 Voice chat active 才出现（逐秒采样 25 秒得到）。
        // 原默认 8 秒正好卡在它起来的前一秒，是首次真机联调失败的直接原因。
        // 25 秒留足余量——慢网络或冷启动会更久。
        //
        // 这 25 秒现在由 `press(_:until:…)` 分给三次尝试：一次落空不再等于整场失败，
        // 而是重新抓树、重新按（见那个函数的文档）。
        try press(ChatGPTLabels.startVoice,
                  until: { ChatGPTLabels.isVoiceActive($0) },
                  timeout: stateTimeout,
                  failedToPress: "按下语音按钮失败。"
                      + "下一步：确认 ChatGPT 窗口在前台，然后重试。",
                  describing: "语音会话开始")
    }

    public func isVoiceActive() -> Bool { ChatGPTLabels.isVoiceActive(access.snapshotTree()) }

    public func assistantReplyCount() -> Int {
        ChatGPTLabels.assistantReplyCount(among: access.snapshotTree())
    }

    /// 等 ChatGPT 把上一条消息回复完。
    ///
    /// 判据：界面上出现了一段足够长的新文本，且在连续几次采样间**不再增长**
    /// （流式输出结束）。用户实测确认必须等它回复完再进语音，否则语音会话
    /// 可能不带考官设定就开始了 —— 这一点从 AX 树上看不出来。
    ///
    /// ## `afterReplyCount`：屏幕上原本就有东西时，光看「不再变长」是假的
    ///
    /// 这个判据只在**新建会话之后**成立，因为那时屏幕上本来就没东西。
    /// 收尾链路上完全不是这样：整场语音的逐字稿都还在屏幕上，加上刚发出去的那条
    /// 一千多字的复盘请求本身——两样都在、都不再变化，于是判据在 ChatGPT
    /// **一个字都没答之前**就满足了，约 1.5 秒后就返回，接着去按复制按钮，
    /// 复制到的是考官最后一句话。
    ///
    /// 传入发送**之前**的助手回复条数（`assistantReplyCount()`），就要求「先真的多出一条」。
    /// 复制按钮要等消息输出完才渲染，所以「条数变多」本身就已经含着「那条写完了」。
    /// 传 nil 时行为与从前逐字一致（新建会话之后那一次仍然走老路）。
    public func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int = 60,
                                      afterReplyCount baseline: Int? = nil) throws {
        var previousLongest = 0
        var stableTicks = 0
        var sawNewReply = baseline == nil
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // **一次快照同时算两件事。** 分两次抓树的话，两个判据看的是不同时刻的界面，
            // 而这一步正处在流式输出中途，两帧之间差别很大。
            let nodes = access.snapshotTree()
            if let baseline, ChatGPTLabels.assistantReplyCount(among: nodes) > baseline {
                sawNewReply = true
            }
            let longest = nodes
                .filter { $0.role == "AXStaticText" }
                .map(\.value.count).max() ?? 0
            if sawNewReply && longest >= minimumLength && longest == previousLongest {
                stableTicks += 1
                if stableTicks >= 3 { return }
            } else {
                stableTicks = 0
            }
            previousLongest = longest
            Thread.sleep(forTimeInterval: replySampleInterval)
        }
        // **两种超时说的是两件事**，下一步也不一样：一条新回复都没出现，多半是那条消息
        // 根本没发出去或者发去了别的会话；出现了但一直在长，那是它还在写。
        let reason = sawNewReply
            ? "ChatGPT 还在输出，一直没停下来。"
            : "ChatGPT 一条新回复都没有出现——那条消息可能根本没发出去，或者发进了别的会话。"
        throw BridgeError.stateNotReached(
            "等了 \(Int(timeout)) 秒，\(reason)"
            + "下一步：切到 ChatGPT 窗口看看它是不是还在输出；"
            + "如果它已经回复完了，说明本工具的判断有误，请把这条错误告诉开发者。")
    }

    public func endVoice() throws {
        // 同样是前置校验：没有通话在跑时「结束通话」若被当成成功，
        // 会掩盖「我们对语音状态的判断本来就错了」这件事。
        guard isVoiceActive() else {
            throw BridgeError.stateNotReached(
                "ChatGPT 里没有正在进行的语音通话，无从结束。"
                + "下一步：看一眼 ChatGPT 窗口确认通话是否已经结束；若已结束，直接继续取复盘即可。")
        }
        let button = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下结束语音按钮失败。"
                + "下一步：切到 ChatGPT 窗口手动结束通话。")
        }
        try locator.waitUntil({ !ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话结束")
    }

    /// 读回复盘。`expectedMarker` 给出时**必须**命中它——
    /// 只挑「最长的文本」是个假阳性温床：用户自己粘贴过的长文、更早轮次残留在树上的消息、
    /// 设置面板里的长段说明，都可能比真复盘更长。取错的后果是存进档案的「复盘」根本不是复盘，
    /// 而解析器只检查有没有那几个字段，很可能不报错。
    public func captureLatestAssistantMessage(expectedMarker: String? = nil) throws -> String {
        let allTexts = access.snapshotTree()
            .filter { $0.role == "AXStaticText" }
            .map(\.value)

        if let marker = expectedMarker {
            let matching = allTexts.filter { $0.contains(marker) }
            guard let best = matching.max(by: { $0.count < $1.count }) else {
                throw BridgeError.elementNotFound(
                    "在 ChatGPT 窗口里没找到带本次标记的复盘，它可能还没输出完、或者没按要求的格式输出。"
                    + "下一步：等它输出完再重试；若已经输出完但格式不对，"
                    + "在 ChatGPT 里选中整段复盘按 ⌘C，然后按提示继续。")
            }
            return best
        }

        // 未给标记时退回旧行为（原有的 ≥40 字符取最长），保持既有测试不变
        let texts = allTexts.filter { $0.count >= 40 }
        guard let longest = texts.max(by: { $0.count < $1.count }) else {
            // ⚠️ 这句话从前写的是「用 coach practice --from-clipboard 继续」——
            // **那个 flag 从来就不存在**（`PracticeCommand.flagsWithValue` 只认 --goal，
            // 而 --from-clipboard 会被 `questionID(in:)` 当成题号忽略掉）。
            // 用户照做只会得到「题库里没有 id 为「--from-clipboard」的题目」。
            // 真正接得住这一步的是调用方的手动兜底（`ManualReviewCapture`），
            // 所以这里只说「按提示继续」，与同文件里另外两处一致。
            throw BridgeError.elementNotFound(
                "没能从 ChatGPT 窗口读到足够长的文字，复盘可能还没生成完。"
                + "下一步：等 ChatGPT 输出完再重试；若已经输出完，请在 ChatGPT 里选中复盘全文按 ⌘C，"
                + "然后按提示继续。")
        }
        return longest
    }

    /// 用 ChatGPT 自己的复制按钮取回最新一条回复，然后从剪贴板读。
    ///
    /// 为什么不直接读 AX 文本：实测复盘在 AX 树里被切成大量碎片节点，
    /// 连定界标记都被拆成三段，「找一个包含完整标记的节点」永远找不到。
    /// 拼接碎片依赖节点顺序与拼接规则，ChatGPT 一改版就崩；
    /// 用它自己的复制功能则由应用保证内容完整，且与内容有没有滚出屏幕无关（见 spec 2.3.9）。
    public func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                           timeout: TimeInterval) throws -> String {
        guard let button = locator.waitForNode(matching: {
            ChatGPTLabels.matchLastControl(ChatGPTLabels.copyAssistantMessage, among: $0)
        }, timeout: timeout) else {
            throw BridgeError.elementNotFound(
                "没找到 ChatGPT 回复下方的复制按钮。"
                + "下一步：把鼠标移到那条回复上，看看下面有没有出现一排小图标；"
                + "若有但本工具找不到，可能是这一版 ChatGPT 改了界面，请把这条错误告诉开发者。"
                + "你也可以直接选中整段复盘按 ⌘C，然后按提示继续。")
        }

        // 按钮之前先清空剪贴板：万一按钮按下去了但 ChatGPT 没真的写剪贴板（界面改版、
        // 复制功能悄悄失效……），读到的会是清空前的旧内容——那正是本项目反复栽过的
        // 「静默拿到错误数据」。清空之后，同样的失败会变成明确的「剪贴板是空的」报错，
        // 而不是拿一份看起来正常、实际是上一次复盘的旧内容去解析、归档。
        pasteboard.clear()

        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下复制按钮失败。"
                + "下一步：手动选中整段复盘按 ⌘C，然后按提示继续。")
        }
        Thread.sleep(forTimeInterval: clipboardSettleDelay)   // 给剪贴板写入留时间
        return try ClipboardFallback.readReview(from: pasteboard)
    }
}
