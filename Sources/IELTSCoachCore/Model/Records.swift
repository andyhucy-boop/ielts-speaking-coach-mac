import Foundation

public struct RetrainingTarget: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var status: String              // "new" | "selected" | "retired"
    public var evidence: [String]
    public var sourceSessionId: String
    public var createdAt: String

    public init(id: String, label: String, status: String, evidence: [String],
                sourceSessionId: String, createdAt: String) {
        self.id = id; self.label = label; self.status = status
        self.evidence = evidence; self.sourceSessionId = sourceSessionId; self.createdAt = createdAt
    }
}

public struct IssueRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var learnerSaid: String
    public var correction: String
    public var whyItMatters: String
    public var occurrences: Int
    public var sourceSessionIds: [String]
    public var lastSeenAt: String

    public init(id: String, learnerSaid: String, correction: String, whyItMatters: String,
                occurrences: Int, sourceSessionIds: [String], lastSeenAt: String) {
        self.id = id; self.learnerSaid = learnerSaid; self.correction = correction
        self.whyItMatters = whyItMatters; self.occurrences = occurrences
        self.sourceSessionIds = sourceSessionIds; self.lastSeenAt = lastSeenAt
    }
}

public struct VocabularyRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var basicWord: String
    public var betterExpression: String
    public var collocation: String
    public var priority: String
    public var sourceSessionIds: [String]
}
