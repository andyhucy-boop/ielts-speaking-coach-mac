import Foundation
import IELTSCoachCore

enum InitializeWorkspaceTool {
    private struct Payload: Encodable {
        let dataDirectory: String
        let stateFile: String
        let createdStateFile: Bool
        let schemaVersion: Int
        let learnerName: String
        let questionCount: Int
        let sessionCount: Int
        let issueCount: Int
        let vocabularyCount: Int
        let targetCount: Int
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "initialize_ielts_workspace",
            description: "确保本机的雅思训练数据目录与 state.json 存在，并返回目录位置与各项数量。"
                + "第一次使用这套工具时先调用它。数据全部保存在本机，不联网。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "displayName": .object([
                        "type": .string("string"),
                        "description": .string("学员昵称。只在当前还没有昵称时写入，不会覆盖已有的。可省略。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let displayName = try arguments.optionalString("displayName") ?? ""
            // 这一行必须留在下面 `store.mutate` **之前**：真正建出 state.json 的是 mutate
            // （createIfNeeded 只建目录，不碰 state.json）。挪到 mutate 之后，
            // 第一次调用就会报「文件本来就在」，用户会以为自己之前已经初始化过。
            let existed = FileManager.default.fileExists(atPath: environment.directory.stateFile.path)
            try environment.directory.createIfNeeded()

            // mutate 会把 state 写回磁盘，所以即使什么都不改，state.json 也会被建出来。
            let state = try environment.store.mutate { state -> CoachState in
                if !displayName.isEmpty && state.learner.displayName.isEmpty {
                    state.learner.displayName = displayName
                }
                return state
            }

            return try ToolJSON.text(Payload(
                dataDirectory: environment.directory.root.path,
                stateFile: environment.directory.stateFile.path,
                createdStateFile: !existed,
                schemaVersion: state.schemaVersion,
                learnerName: state.learner.displayName,
                questionCount: state.questions.count,
                sessionCount: state.sessions.count,
                issueCount: state.issues.count,
                vocabularyCount: state.vocabulary.count,
                targetCount: state.targets.count,
                note: state.questions.isEmpty
                    ? "工作区就绪，但题库还是空的。下一步：在 App 的「训练题库」页导入题库文件，"
                        + "或在终端运行 coach questions import <文件>。"
                    : "工作区就绪。下一步：用 set_training_selection 选一道题。"))
        }
    }
}
