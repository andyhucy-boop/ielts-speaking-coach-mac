import Foundation

public struct PracticeSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String                  // "YYYY-MM-DD-NNN"
    public var questionId: String
    public var focusPart: String           // "Part 1" | "Part 2" | "Part 3" | "full mock"
    public var startedAt: String
    public var endedAt: String
    public var goal: String                // 本次的单点目标，可为空
    public var transcript: [TranscriptTurn]
    public var reportPath: String          // reports/<id>.json，未完成时为空
    public var recordingPath: String       // 未录音时为空

    public struct TranscriptTurn: Codable, Equatable, Sendable {
        public var role: String            // "user" | "assistant"
        public var text: String
        public var capturedAt: String
    }
}
