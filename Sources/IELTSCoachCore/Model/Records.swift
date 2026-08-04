import Foundation

public struct RetrainingTarget: Codable, Equatable, Sendable, Identifiable {
    /// ChatGPT 给出的目标标识（如 "logic-explain-example"）。**跨 session 会重复**，
    /// 归并（ReviewArchiver）与匹配（RetrainingPolicy）逻辑依赖它，不要改。
    public var targetKey: String
    public var label: String
    public var status: String              // "new" | "selected" | "retired"
    public var evidence: [String]
    public var sourceSessionId: String
    public var createdAt: String

    /// state.json 里这个字段的键名必须仍是 "id"（与上游 Windows 版兼容），
    /// 即使 Swift 侧把它改叫 targetKey，好把 id 这个名字让给真正唯一的 Identifiable.id。
    enum CodingKeys: String, CodingKey {
        case targetKey = "id"
        case label, status, evidence, sourceSessionId, createdAt
    }

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(targetKey: String, label: String, status: String, evidence: [String],
                sourceSessionId: String, createdAt: String) {
        self.targetKey = targetKey; self.label = label; self.status = status
        self.evidence = evidence; self.sourceSessionId = sourceSessionId; self.createdAt = createdAt
    }

    /// SwiftUI 的 ForEach 用它当唯一键。targetKey 跨 session 重复，直接拿它当 id
    /// 会让列表渲染错乱甚至崩溃；这里拼上 sourceSessionId 保证真正唯一。
    public var id: String { "\(targetKey)@\(sourceSessionId)" }
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

    public init(id: String, basicWord: String, betterExpression: String,
                collocation: String, priority: String, sourceSessionIds: [String]) {
        self.id = id; self.basicWord = basicWord; self.betterExpression = betterExpression
        self.collocation = collocation; self.priority = priority
        self.sourceSessionIds = sourceSessionIds
    }
}
