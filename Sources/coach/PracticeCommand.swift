import ChatGPTBridge
import Foundation
import IELTSCoachCore

enum PracticeCommand {
    static func run(_ args: [String]) -> Int32 {
        guard let questionID = args.first, !questionID.hasPrefix("--") else {
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

            print("▶︎ 正在启动语音…")
            try driver.startVoice()
            print("\n✅ 开练了。跟 ChatGPT 说话就行。")
            print("   练完之后在 ChatGPT 里结束通话即可；也可以回到这里按回车。\n")

            waitForSessionEnd(driver: driver)

            if driver.isVoiceActive() {
                print("▶︎ 正在结束语音…")
                try driver.endVoice()
            }

            let requestID = "sync-\(Int(Date().timeIntervalSince1970))"
            // 复盘请求与「取回复盘」共用同一个标记：open 标记是本次复盘在 ChatGPT
            // 回复里必然逐字出现的文本（见 ReviewRequestPrompt），用它而不是裸 requestID
            // 去匹配，可以少踩一层「子串意外命中别的静态文本节点」的坑。
            let marker = ReviewRequestPrompt.marker(requestID: requestID)
            print("▶︎ 正在请 ChatGPT 生成复盘…")
            try driver.sendText(ReviewRequestPrompt.build(requestID: requestID, focusPart: focusPart))

            print("▶︎ 等 ChatGPT 写完…（约 30 秒）")
            Thread.sleep(forTimeInterval: 30)

            // 必须传 expectedMarker：不传会退回「取界面上最长的静态文本」的旧行为，
            // 用户自己粘贴过的长文、更早轮次残留的消息都可能比真复盘更长，
            // 存进档案的「复盘」就会文不对题，而 ReviewParser 只检查字段是否齐全，
            // 很可能不报错——参见 brief 里「两个必须做对的点」之二。
            let raw = captureReview(driver: driver, expectedMarker: marker.open)
            guard let raw else { return 1 }

            let report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
            let sessionID = ISO8601DateFormatter().string(from: Date())
            try directory.createIfNeeded()
            try raw.write(to: directory.pendingReviewsDirectory.appending(path: "\(requestID).txt"),
                          atomically: true, encoding: .utf8)

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
    private static func waitForSessionEnd(driver: AXDriver) {
        let manualStop = ManualStopFlag()
        Thread.detachNewThread {
            _ = readLine()
            manualStop.set()
        }

        var state = VoiceEndState()
        while !manualStop.isSet {
            state = VoiceEndPolicy.advance(previous: state,
                                           voiceActive: driver.isVoiceActive(),
                                           busy: false)
            if state.shouldFinalize {
                print("▶︎ 检测到语音已结束（\(state.reason)）")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)   // 与 requiredInactiveTicks=3 配合约 1.5 秒去抖
        }
        print("▶︎ 已手动结束")
    }

    /// 跨线程的一次性标志。用类而非局部 var，因为要被后台线程写。
    private final class ManualStopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    /// 先试 AX 自动读，失败则降级到剪贴板。两条路都失败时给出可执行的下一步。
    /// `expectedMarker` 必须是本次复盘请求的标记（见调用处），不能省略。
    private static func captureReview(driver: AXDriver, expectedMarker: String) -> String? {
        do { return try driver.captureLatestAssistantMessage(expectedMarker: expectedMarker) } catch {
            print("⚠️  \(error.localizedDescription)")
            print("\n请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车。")
            _ = readLine()
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
