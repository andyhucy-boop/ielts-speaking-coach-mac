import Foundation

public struct PracticeSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String                  // "YYYY-MM-DD-NNN"
    public var questionId: String
    public var focusPart: FocusPart
    public var startedAt: String
    public var endedAt: String
    public var goal: String                // 本次的单点目标，可为空
    public var transcript: [TranscriptTurn]
    public var reportPath: String          // reports/<id>.json，未完成时为空
    public var recordingPath: String       // 未录音时为空

    /// 非 nil 表示这是一场复训会话（Phase 6）。普通练习为 nil。
    /// Optional 属性由 Swift 合成的解码器走 decodeIfPresent，
    /// 因此不带这个键的历史记录仍然能正常读出来——不要改成非 Optional。
    public var retraining: RetrainingLink?

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(id: String, questionId: String, focusPart: FocusPart, startedAt: String,
                endedAt: String, goal: String, transcript: [TranscriptTurn],
                reportPath: String, recordingPath: String,
                retraining: RetrainingLink? = nil) {
        self.id = id; self.questionId = questionId; self.focusPart = focusPart
        self.startedAt = startedAt; self.endedAt = endedAt; self.goal = goal
        self.transcript = transcript; self.reportPath = reportPath
        self.recordingPath = recordingPath; self.retraining = retraining
    }

    public struct TranscriptTurn: Codable, Equatable, Sendable {
        public var role: String            // "user" | "assistant"
        public var text: String
        public var capturedAt: String

        // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
        public init(role: String, text: String, capturedAt: String) {
            self.role = role; self.text = text; self.capturedAt = capturedAt
        }
    }
}
