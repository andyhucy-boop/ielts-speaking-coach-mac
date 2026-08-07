import Foundation
import IELTSCoachCore

enum SaveSessionReviewTool {
    private struct Payload: Encodable {
        let sessionId: String
        let questionId: String
        let reportPath: String          // 相对路径，与 PracticeSession.reportPath 一致
        let reportFile: String          // 绝对路径，方便用户直接打开
        let pendingReviewPath: String
        let issuesAdded: Int
        let vocabularyAdded: Int
        let issueTotal: Int
        let vocabularyTotal: Int
        let targetTotal: Int
        let skipped: [String]
        let warning: String?
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "save_session_review",
            description: "把 ChatGPT 输出的整段复盘存档：原文先落盘，再解析，然后并入错题本、"
                + "词汇本、重训目标，并推进计划进度。传整段原文（含 <<<IELTS_REVIEW_JSON…>>> 首尾标记）即可。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "reviewText": .object([
                        "type": .string("string"),
                        "description": .string("ChatGPT 输出的整段复盘原文，含首尾标记。不要自己改写或截断。")
                    ]),
                    "sessionId": .object([
                        "type": .string("string"),
                        "description": .string("这一场的会话编号。省略时用当前选题的编号，没有选题就自动生成。")
                    ]),
                    "questionId": .object([
                        "type": .string("string"),
                        "description": .string("这一场练的题号。省略时用当前选题的题号；"
                            + "传了就必须和这一场在案的题号一致，对不上会被拒绝而不是二选一。")
                    ])
                ]),
                "required": .array([.string("reviewText")]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let rawText = try arguments.requiredString("reviewText", trimmed: false,
                hint: "把 ChatGPT 输出的整段复盘（含 <<<IELTS_REVIEW_JSON…>>> 首尾标记）原样传进来。")

            let state = try environment.store.load()
            let sessionID: String
            if let given = try arguments.optionalString("sessionId") {
                // ⚠️ 这一句是第二道防线，**当前不可观测**：`PendingReviewStore.write`
                // 内部也调 `SessionID.validated`，而落盘是本工具里第一个用到 sessionID
                // 的地方，所以把这一句删掉，`testRejectsSessionIdThatCouldEscapeTheDataDirectory`
                // 照样是绿的（实测过：只有连 Core 那道一起去掉，测试才变红，
                // 并真的在数据目录外面写出了 escaped.txt）。
                // 留着的理由是别的：一旦以后有人把落盘挪到解析之后、或在落盘之前
                // 先拼出 reports/<id>.json，Core 那道校验就赶不上了，而这里赶得上。
                sessionID = try SessionID.validated(given)
            } else if let current = state.currentSession {
                sessionID = current.id
            } else {
                sessionID = SessionID.next(existing: state.sessions, now: environment.now(),
                                           timeZone: environment.timeZone)
            }
            // 显式传的题号与这一场已经在案的题号对不上时，直接停下来问清楚。
            // 让任何一方「赢」都会造出三份互相矛盾的记录：`ReviewArchiver` 照显式题号
            // 推进计划、把它标成 practiced，而这条练习记录（focusPart、goal 都是照
            // 原来那道题定的）写着另一道题，返回负载报的又是第三种说法。Task 9 的
            // `list_practice_history` 照 `state.sessions` 显示，用户看到的历史与题库状态
            // 永远对不上，全程没有任何提示——正是铁律 7 说的静默失败。
            // 检查刻意放在所有落盘之前：错的是参数不是复盘内容，模型手里还拿着原文，
            // 改好参数原样再传一次即可，不该先在 pending-reviews 里留下一份让人事后收拾。
            let explicitQuestionID = try arguments.optionalString("questionId")
            let recordInFlight = state.currentSession.flatMap { $0.id == sessionID ? $0 : nil }
                ?? state.sessions.first { $0.id == sessionID }
            if let explicitQuestionID, let recorded = recordInFlight?.questionId,
               !recorded.isEmpty, recorded != explicitQuestionID {
                throw ToolInputError(message:
                    "参数「questionId」传的是「\(explicitQuestionID)」，"
                    + "但这一场（\(sessionID)）在案的题号是「\(recorded)」，两者对不上，"
                    + "没法确定这场练的到底是哪道题，所以什么都没存，复盘原文也还没落盘。"
                    + "下一步：这场练的确实是「\(explicitQuestionID)」的话，"
                    + "先用 set_training_selection 把它选上，再把整段复盘原样传一次；"
                    + "练的是「\(recorded)」的话，把 questionId 整个省掉再传一次即可。")
            }
            let questionID = explicitQuestionID ?? state.currentSession?.questionId ?? ""

            // ⚠️ 顺序不能改：先落盘，再解析。
            // 反过来写的话，解析一抛错，用户练了一整场换来的复盘原文就没了
            //（成品标准第 7 条；coach practice 里也是这个顺序）。
            let pendingURL = try PendingReviewStore.write(rawText: rawText, sessionID: sessionID,
                                                          directory: environment.directory)

            let report: JSONValue
            do {
                report = try ReviewParser.parse(rawText, requireAnswerUpgrades: false)
            } catch {
                throw ToolInputError(message:
                    "\(error.localizedDescription)\n"
                    + "好消息是原文没丢，已经存在 \(pendingURL.path)。"
                    + "下一步：打开这个文件看看 ChatGPT 到底输出了什么；"
                    + "让它按 get_training_context 给的 reviewRequestPrompt 重新输出一次后再调一次本工具；"
                    + "也可以在 App 的「复盘报告」页点「重新导入待处理的复盘」，"
                    + "或在终端运行 coach reimport 把已落盘的复盘补入库。")
            }

            let timestamp = environment.timestamp
            let reportRelativePath = "reports/\(sessionID).json"
            let reportURL = environment.directory.reportsDirectory.appending(path: "\(sessionID).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report).write(to: reportURL, options: .atomic)

            let payload = try environment.store.mutate { state -> Payload in
                let issuesBefore = state.issues.count
                let vocabularyBefore = state.vocabulary.count

                let outcome = ReviewArchiver.archive(report: report, into: state,
                                                     sessionID: sessionID, questionID: questionID,
                                                     at: timestamp)
                state = outcome.state

                // 这一场的记录：优先接着 currentSession，其次接着已有的同号记录，
                // 都没有就新建一条。三条路都要走通——用户可能压根没调过 set_training_selection。
                var session = state.currentSession.flatMap { $0.id == sessionID ? $0 : nil }
                    ?? state.sessions.first { $0.id == sessionID }
                    ?? PracticeSession(id: sessionID, questionId: questionID,
                                       focusPart: focusPart(forQuestion: questionID, in: state),
                                       startedAt: timestamp, endedAt: "", goal: "",
                                       transcript: [], reportPath: "", recordingPath: "")
                session.endedAt = timestamp
                session.reportPath = reportRelativePath
                // 只在记录里还没有题号时才补：同一场存第二次时 questionID 可能是空的
                //（这次没传 questionId，currentSession 又已经在第一次存完时清掉了），
                // 无条件赋值会把第一次记好的题号抹成空。
                // 「显式题号与在案题号不一致」那种情况上面已经拦掉了，
                // 所以走到这里两者要么相等、要么在案的那个本来就是空的。
                if session.questionId.isEmpty { session.questionId = questionID }

                if let index = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                    state.sessions[index] = session          // 重存不产生第二条记录
                } else {
                    state.sessions.append(session)
                }
                if state.currentSession?.id == sessionID { state.currentSession = nil }

                let warning = outcome.skipped.isEmpty ? nil :
                    "复盘里有 \(outcome.skipped.joined(separator: "、"))，但一条都没能归进档案。"
                    + "这通常意味着 ChatGPT 用的字段名和本工具读的对不上——归档 0 条不等于没错题。"
                    + "下一步：原文完整保存在 \(pendingURL.path)，"
                    + "让 ChatGPT 按 reviewRequestPrompt 里写死的字段名重新输出一次；"
                    + "也可以在 App 的「复盘报告」页点「重新导入待处理的复盘」，"
                    + "或在终端运行 coach reimport 重新入库，这场练习不会白费。"

                return Payload(
                    sessionId: sessionID,
                    questionId: session.questionId,
                    reportPath: reportRelativePath,
                    reportFile: reportURL.path,
                    pendingReviewPath: pendingURL.path,
                    issuesAdded: state.issues.count - issuesBefore,
                    vocabularyAdded: state.vocabulary.count - vocabularyBefore,
                    issueTotal: state.issues.count,
                    vocabularyTotal: state.vocabulary.count,
                    targetTotal: state.targets.count,
                    skipped: outcome.skipped,
                    warning: warning,
                    note: "已存档。下一步：用 get_dashboard_data 看看这次之后的整体情况，"
                        + "或用 open_dashboard 打开复盘报告页。")
            }
            return try ToolJSON.text(payload)
        }
    }

    /// 新建记录时用得上：题目还在题库里就按它的 part，找不到就按全真模考处理。
    private static func focusPart(forQuestion questionID: String, in state: CoachState) -> FocusPart {
        guard let question = state.questions.first(where: { $0.id == questionID }) else { return .fullMock }
        return FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
    }
}
