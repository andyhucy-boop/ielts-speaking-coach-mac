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

        let focusPart = FocusPart.inferred(fromQuestionPart: question.part)
        let setup = SessionSetup(question: question, focusPart: focusPart,
                                 durationMinutes: focusPart.defaultDurationMinutes, goal: goal,
                                 feedbackTiming: feedbackTiming, part2PrepMode: prepMode)

        do {
            // 用户真机联调两次失败后纠正的顺序：Live 语音只能在还没发送过任何消息的
            // 会话里启动。先按 New chat 保证这个前提成立，再开语音、等语音模式的
            // 输入框出现，最后才把考官提示词写进去——反过来做（先发提示词）会让
            // 这个会话直接失去启动 Live 的资格，这一点从 AX 树上完全看不出来。
            print("\n▶︎ 正在新建会话（Live 语音只能在全新会话里启动）…")
            try driver.startNewChat()

            print("▶︎ 正在启动语音…")
            try driver.startVoice()

            print("▶︎ 等语音模式的输入框出现…")
            try driver.waitForVoiceComposer(timeout: 20)

            print("▶︎ 正在把考官提示词发给 ChatGPT…")
            try driver.sendText(ExaminerPrompt.build(setup: setup), into: .voice)
            print("\n✅ 开练了。跟 ChatGPT 说话就行。")
            print("   练完之后在 ChatGPT 里结束通话即可；也可以回到这里按回车。\n")

            let enter = ConsoleEnterWaiter()
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
            try driver.sendText(ReviewRequestPrompt.build(requestID: requestID, focusPart: focusPart),
                                into: .any)

            print("▶︎ 等 ChatGPT 写完复盘…")
            try driver.waitForAssistantReply(timeout: 60)

            // 必须传 expectedMarker：不传会退回「取界面上最长的静态文本」的旧行为，
            // 用户自己粘贴过的长文、更早轮次残留的消息都可能比真复盘更长，
            // 存进档案的「复盘」就会文不对题，而 ReviewParser 只检查字段是否齐全，
            // 很可能不报错。
            let raw = captureReview(driver: driver, expectedMarker: marker.open, enter: enter)
            guard let raw else { return 1 }

            // ⚠️ 必须先落盘再解析。spec 第 5 节的原话是「复盘先落盘再入库，
            // 中途崩溃或误关窗口都不丢数据」。反过来写的话，解析一抛错，
            // 用户练了一整场换来的复盘原文就没了，只能从头再练一次。
            // 决策 1：会话编号统一成 YYYY-MM-DD-NNN。旧的 ISO8601 编号仍然读得进来
            //（SessionID.validated 白名单里留了冒号），但新产生的一律用新形状——
            // 否则界面练的和命令行练的会是两种编号，统计与 MCP 都要各走一条路。
            let existingSessions = (try? store.load())?.sessions ?? []
            let sessionID = SessionID.next(existing: existingSessions, now: Date(),
                                           timeZone: .current)
            try directory.createIfNeeded()
            // 文件名用会话编号而不是 requestID：coach reimport 与界面里的
            // 「重新导入待处理的复盘」都从文件名取 sessionID，用同一个值才能保证
            // 「当场归档」和「事后补导」落进档案的编号一致。
            let pendingPath = try PendingReviewStore.write(rawText: raw, sessionID: sessionID,
                                                           directory: directory)
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

            // 解析后的复盘写成 reports/<会话编号>.json，训练记录里的 reportPath 指向它。
            // 存的是解析后的复盘本身，不是带定界标记的原文——原文归 pending-reviews/。
            let reportFile = directory.reportsDirectory.appending(path: "\(sessionID).json")
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                try encoder.encode(report).write(to: reportFile, options: .atomic)
            } catch {
                // 不许 try? 吞掉再往下走：吞掉之后训练记录里的 reportPath 会指向一个
                // 根本不存在的文件，界面上的「复盘报告」页点开是一场空，而这里却打了个 ✅。
                print("\n❌ 复盘解析出来了，但没能写成报告文件 \(reportFile.path)"
                    + "（系统说：\(error.localizedDescription)）。")
                print("   好消息是复盘原文一个字都没丢，就在 \(pendingPath.path)；"
                    + "但这一场还没有归进档案，也还没有记进训练记录。")
                print("   下一步：确认「\(directory.root.path)」这个目录存在且可写，"
                    + "然后运行 coach reimport，把这份原文里的错题和词汇补进档案。")
                // ⚠️ 这句限定不能省。coach reimport 只调 ReviewArchiver.archive 归错题与词汇，
                // 它不写 reports/<id>.json，也不往 state.sessions 里加任何东西
                //（见 ReimportCommand，以及 CoachCLIGuidanceTests 里守着这条前提的那条测试）。
                // 只说「运行 coach reimport 重新入库」的话，用户照着做完，「训练记录」和
                // 「复盘报告」两页里这一场依然永远不存在，而他不会知道为什么——
                // 那正是 PendingReviewViewModel.successNotice 的注释里禁止的
                // 「下一步承诺一件兑现不了的事」。
                print("   要先说清楚：coach reimport 只补错题和词汇。"
                    + "「训练记录」和「复盘报告」这两页里补不回这一场——"
                    + "要那两页也有这一场，只能重新练一次。")
                return 1
            }

            let outcome = try store.mutate { state -> ArchiveOutcome in
                let result = ReviewArchiver.archive(report: report, into: state, sessionID: sessionID,
                                                    questionID: question.id,
                                                    at: ISO8601DateFormatter().string(from: Date()))
                state = result.state

                // Phase 4：命令行也要留下训练记录，否则界面上的「训练记录」页
                // 看不到用命令行练的那些场次。字段与 PracticeRunner 落的那条保持一致，
                // 也同样是按 id upsert 而不是无脑 append——同一个编号重存不该多出一条。
                //
                // ⚠️ startedAt 用的是归档这一刻，不是真正的开始时刻。命令行没有记录开始
                // 时间的地方，而为此改造 PracticeCommand 的结构不值得（界面才是主路径）。
                // 这个近似只影响「本周开口时长」这类统计对命令行场次的精度，别当成准的。
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let session = PracticeSession(
                    id: sessionID, questionId: question.id, focusPart: focusPart,
                    startedAt: timestamp, endedAt: timestamp, goal: goal,
                    transcript: [],                       // 命令行不采逐字稿
                    reportPath: "reports/\(sessionID).json", recordingPath: "")
                if let index = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                    state.sessions[index] = session
                } else {
                    state.sessions.append(session)
                }
                return result
            }
            let state = try store.load()
            print("\n✅ 复盘已存档。")
            print("   错题本 \(state.issues.count) 条，词汇本 \(state.vocabulary.count) 条，"
                + "重训目标 \(state.targets.count) 个")
            if !outcome.skipped.isEmpty {
                print("\n⚠️  复盘里有 \(outcome.skipped.joined(separator: "、"))，但一条都没能归进档案。")
                print("   这通常意味着 ChatGPT 用的字段名和本工具读的对不上。")
                print("   下一步：复盘原文已完整保存在上面那个路径；"
                    + "修好之后可以用 coach reimport 把它重新入库，这次练习不会白费。")
            }
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
    private static func waitForSessionEnd(driver: AXDriver, enter: ConsoleEnterWaiter) {
        enter.arm()

        var state = VoiceEndState()
        while !enter.isPressed {
            state = VoiceEndPolicy.advance(previous: state,
                                           voiceActive: driver.isVoiceActive(),
                                           busy: false)
            if state.shouldFinalize {
                print("▶︎ 检测到语音已结束（\(state.reason)）")
                // 没人按回车：让读取线程继续挂着，后面用得上就直接复用。
                // ⚠️ 这条路上**不消费**按键标志，所以用户此刻顺手按的那一下会粘在这儿；
                // 后面手动兜底那一步必须用 `waitForFreshPress()` 把它丢掉再等新的
                //（复审第 13 条：不丢的话那一步会 0 秒穿过去，整场复盘一个字不留）。
                return
            }
            Thread.sleep(forTimeInterval: 0.5)   // 与 requiredInactiveTicks=3 配合约 1.5 秒去抖
        }
        // 走到这里说明是手动结束：把这次按键消费掉，避免残留状态影响后面
        // captureReview 里那次「粘贴好了按回车」的等待——不消费的话，那次等待
        // 会立刻返回，用户根本还没来得及复制粘贴。
        enter.waitForPress()
        print("▶︎ 已手动结束")
    }

    // `EnterWaiter` 已经搬进 `ChatGPTBridge.ConsoleEnterWaiter`。
    // 搬家的唯一理由是可测性：`coach` 是可执行 target，没有测试 target，
    // 这段等待逻辑留在这里就一行都测不到——而它出过一个真缺陷
    //（粘滞的按键标志让手动兜底 0 秒穿过去，复审第 13 条）。

    /// 取复盘：三级降级，每级失败都打印一句「为什么换下一条路」，让用户知道发生了什么，
    /// 而不是默默换路。`expectedMarker` 必须是本次复盘请求的标记（见调用处），不能省略。
    ///
    /// ① 按 ChatGPT 自己的复制按钮 + 读剪贴板——主路径。复盘在 AX 树里被切成大量碎片
    ///    节点（连定界标记本身都被拆成三段），逐节点匹配「包含完整标记」的旧路径（②）
    ///    永远找不到；复制按钮由应用自身保证内容完整，且与内容有没有滚出屏幕无关
    ///    （见 spec 2.3.9）。
    /// ② AX 直接读（带标记）——万一复制按钮本身找不到（ChatGPT 又改了界面），还留一条
    ///    路试试，不至于直接落到最麻烦的手动兜底。
    /// ③ 提示用户手动 ⌘C——最终兜底，两条自动路径都失败时才用。
    private static func captureReview(driver: AXDriver, expectedMarker: String,
                                      enter: ConsoleEnterWaiter) -> String? {
        do {
            return try driver.copyLatestAssistantMessage(pasteboard: SystemPasteboard(), timeout: 10)
        } catch {
            print("⚠️  复制按钮这条路没走通，改试直接读 AX 树：\(error.localizedDescription)")
        }

        do {
            return try driver.captureLatestAssistantMessage(expectedMarker: expectedMarker)
        } catch {
            print("⚠️  直接读 AX 树也没读到，改成手动兜底：\(error.localizedDescription)")
        }

        // 提示、等一次**新的**回车、读剪贴板、失败重试，全在 `ManualReviewCapture` 里，
        // 它有测试（`ManualReviewCaptureTests`）。这里只负责接上真实的剪贴板与终端输出。
        return ManualReviewCapture.read(pasteboard: SystemPasteboard(), enter: enter) { print($0) }
    }

    private static func valueFor(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
