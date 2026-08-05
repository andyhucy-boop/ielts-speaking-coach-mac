import ChatGPTBridge
import Foundation
import IELTSCoachCore

enum PracticeCommand {
    /// 目前唯一带取值的 flag。加新 flag 且它也带取值时，要记得把它加进这个集合，
    /// 否则 questionID(in:) 会把它的取值误当成题号（或把题号误当成它的取值）。
    private static let flagsWithValue: Set<String> = ["--goal"]

    /// 题号是「第一个既不是 flag、也不是某个带值 flag 的取值」的参数。
    /// 不能直接取 args.first —— `coach practice --immediate p1-home-001` 这种
    /// flag 写在题号前面的用法很自然，若还是报「没有指定题目」就是错误诊断，
    /// 用户明明给了有效题号却被当成没给。
    private static func questionID(in args: [String]) -> String? {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if flagsWithValue.contains(arg) {
                index += 2   // 跳过 flag 本身与它的取值（例如 --goal "减少 filler"）
                continue
            }
            if arg.hasPrefix("--") {
                index += 1
                continue
            }
            return arg
        }
        return nil
    }

    static func run(_ args: [String]) -> Int32 {
        guard let questionID = questionID(in: args) else {
            print("❌ 没有指定题目。下一步：先 coach questions list 看有哪些题，再 coach practice <题目id>")
            return 2
        }
        let feedbackTiming: FeedbackTiming = args.contains("--immediate") ? .immediate : .deferred
        let prepMode: Part2PrepMode = args.contains("--self-paced") ? .learnerControlled : .countdown
        let goal = valueFor("--goal", in: args) ?? ""

        let directory = DataDirectory.resolve()
        let store = StateStore(directory: directory)

        let question: Question
        do {
            guard let found = try store.load().questions.first(where: { $0.id == questionID }) else {
                print("❌ 题库里没有 id 为「\(questionID)」的题目。")
                print("   下一步：coach questions list 查看可用题目。")
                return 1
            }
            question = found
        } catch {
            print("❌ \(error.localizedDescription)"); return 1
        }

        let access = LiveAXAccess()
        let driver = AXDriver(access: access, locator: AXLocator(access: access))
        let readiness = driver.preflight()
        readiness.messages.forEach { print($0) }
        guard readiness.ok else { return 1 }

        let focusPart = FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
        let setup = SessionSetup(question: question, focusPart: focusPart,
                                 durationMinutes: question.part == 2 ? 4 : 6, goal: goal,
                                 feedbackTiming: feedbackTiming, part2PrepMode: prepMode)

        do {
            print("\n▶︎ 正在把考官提示词发给 ChatGPT…")
            try driver.sendText(ExaminerPrompt.build(setup: setup))

            print("▶︎ 等 ChatGPT 读完考官指令…")
            try driver.waitForAssistantReply(timeout: 60)

            print("▶︎ 正在启动语音…")
            try driver.startVoice()
            print("\n✅ 开练了。跟 ChatGPT 说话就行。")
            print("   练完之后在 ChatGPT 里结束通话即可；也可以回到这里按回车。\n")

            let enter = EnterWaiter()
            waitForSessionEnd(driver: driver, enter: enter)

            if driver.isVoiceActive() {
                print("▶︎ 正在结束语音…")
                try driver.endVoice()
            }

            let requestID = "sync-\(Int(Date().timeIntervalSince1970))"
            // 复盘请求与「取回复盘」共用同一个标记：open 标记是本次复盘在 ChatGPT
            // 回复里必然逐字出现的文本（见 ReviewRequestPrompt），用它而不是裸 requestID
            // 去匹配，可以少踩一层「子串意外命中别的静态文本节点」的坑——裸 requestID
            // 还会出现在同一条消息的 [SYNC_REQUEST_ID:...] 行里，匹配会变弱。
            let marker = ReviewRequestPrompt.marker(requestID: requestID)
            print("▶︎ 正在请 ChatGPT 生成复盘…")
            try driver.sendText(ReviewRequestPrompt.build(requestID: requestID, focusPart: focusPart))

            print("▶︎ 等 ChatGPT 写完…（约 30 秒）")
            Thread.sleep(forTimeInterval: 30)

            // 必须传 expectedMarker：不传会退回「取界面上最长的静态文本」的旧行为，
            // 用户自己粘贴过的长文、更早轮次残留的消息都可能比真复盘更长，
            // 存进档案的「复盘」就会文不对题，而 ReviewParser 只检查字段是否齐全，
            // 很可能不报错。
            let raw = captureReview(driver: driver, expectedMarker: marker.open, enter: enter)
            guard let raw else { return 1 }

            // ⚠️ 必须先落盘再解析。spec 第 5 节的原话是「复盘先落盘再入库，
            // 中途崩溃或误关窗口都不丢数据」。反过来写的话，解析一抛错，
            // 用户练了一整场换来的复盘原文就没了，只能从头再练一次。
            let sessionID = ISO8601DateFormatter().string(from: Date())
            try directory.createIfNeeded()
            let pendingPath = directory.pendingReviewsDirectory.appending(path: "\(requestID).txt")
            try raw.write(to: pendingPath, atomically: true, encoding: .utf8)
            print("▶︎ 复盘原文已存到 \(pendingPath.path)")

            let report: JSONValue
            do {
                report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
            } catch {
                print("\n❌ \(error.localizedDescription)")
                print("   好消息是原文没丢，就在 \(pendingPath.path)")
                print("   下一步：打开这个文件看看 ChatGPT 到底输出了什么；"
                    + "若格式确实不对，回 ChatGPT 里让它按要求重新输出一次，再用 ⌘C 复制。")
                return 1
            }

            try store.mutate { state in
                state = ReviewArchiver.archive(report: report, into: state, sessionID: sessionID,
                                               questionID: question.id,
                                               at: ISO8601DateFormatter().string(from: Date()))
            }
            let state = try store.load()
            print("\n✅ 复盘已存档。")
            print("   错题本 \(state.issues.count) 条，词汇本 \(state.vocabulary.count) 条，"
                + "重训目标 \(state.targets.count) 个")
            return 0
        } catch {
            print("\n❌ \(error.localizedDescription)")
            return 1
        }
    }

    /// 等练习结束。spec 定的是「AX 探测 + 手动按钮双保险」，两条都要接上：
    /// 后台线程读一行 stdin 作为手动兜底，主循环用 VoiceEndPolicy 判断语音是否已结束。
    /// 只做手动那一半的话，Phase 1 造的 VoiceEndPolicy 就成了死代码；
    /// 只做自动那一半的话，AX 万一失灵用户就卡住了。
    private static func waitForSessionEnd(driver: AXDriver, enter: EnterWaiter) {
        enter.arm()

        var state = VoiceEndState()
        while !enter.isPressed {
            state = VoiceEndPolicy.advance(previous: state,
                                           voiceActive: driver.isVoiceActive(),
                                           busy: false)
            if state.shouldFinalize {
                print("▶︎ 检测到语音已结束（\(state.reason)）")
                return   // 没人按回车：让 EnterWaiter 继续挂着，后面用得上就直接复用
            }
            Thread.sleep(forTimeInterval: 0.5)   // 与 requiredInactiveTicks=3 配合约 1.5 秒去抖
        }
        // 走到这里说明是手动结束：把这次按键消费掉，避免残留状态影响后面
        // captureReview 里那次「粘贴好了按回车」的等待——不消费的话，那次等待
        // 会立刻返回，用户根本还没来得及复制粘贴。
        enter.waitForPress()
        print("▶︎ 已手动结束")
    }

    /// **独占 stdin 的读取器。整个流程只能有一个线程在读。**
    ///
    /// 两个线程同时等回车时，内核只会唤醒其中一个，另一个永远阻塞——
    /// 这正是「AX 自动探测到语音结束（手动线程仍挂着）→ 取复盘失败 → 剪贴板兜底
    /// 又调一次 readLine」这条路径上会发生的事，直接违反「禁止无限等待」。
    private final class EnterWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var pressed = false
        private var reading = false

        /// 确保有且只有一个后台线程在读 stdin。已在读或已按下时不再新起线程。
        func arm() {
            lock.lock(); defer { lock.unlock() }
            guard !reading, !pressed else { return }
            reading = true
            Thread.detachNewThread { [self] in
                _ = readLine()
                lock.lock(); pressed = true; reading = false; lock.unlock()
            }
        }

        var isPressed: Bool { lock.lock(); defer { lock.unlock() }; return pressed }

        /// 阻塞直到用户按回车，并消费掉这次按键。
        func waitForPress() {
            arm()
            while !isPressed { Thread.sleep(forTimeInterval: 0.1) }
            lock.lock(); pressed = false; lock.unlock()
        }
    }

    /// 先试 AX 自动读，失败则降级到剪贴板。两条路都失败时给出可执行的下一步。
    /// `expectedMarker` 必须是本次复盘请求的标记（见调用处），不能省略。
    private static func captureReview(driver: AXDriver, expectedMarker: String,
                                      enter: EnterWaiter) -> String? {
        do { return try driver.captureLatestAssistantMessage(expectedMarker: expectedMarker) } catch {
            print("⚠️  \(error.localizedDescription)")
            print("\n请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车。")
            enter.waitForPress()
            do { return try ClipboardFallback.readReview(from: SystemPasteboard()) } catch {
                print("❌ \(error.localizedDescription)")
                return nil
            }
        }
    }

    private static func valueFor(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
