import Foundation

public struct RetrainingTarget: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var status: String              // "new" | "selected" | "retired"
    public var evidence: [String]
    public var sourceSessionId: String
    public var createdAt: String
}

public struct IssueRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var learnerSaid: String
    public var correction: String
    public var whyItMatters: String
    public var occurrences: Int
    public var sourceSessionIds: [String]
    public var lastSeenAt: String
}

public struct VocabularyRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var basicWord: String
    public var betterExpression: String
    public var collocation: String
    public var priority: String
    public var sourceSessionIds: [String]
}
