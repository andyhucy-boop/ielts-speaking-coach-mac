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
    /// **「在几场练习里犯过这个毛病」**，恒等于 `sourceSessionIds.count`。
    ///
    /// 不是「一共说错了几次」：那个数没有可去重的键，同一场复盘补录一次就永久虚高，
    /// 而这个数字正是「老毛病在变多还是变少」的全部依据——虚高比不显示更糟。
    /// 维护它的是 `ReviewArchiver.mergeIssues`（按 sessionID 去重）。
    public var occurrences: Int
    public var sourceSessionIds: [String]
    public var lastSeenAt: String

    public init(id: String, learnerSaid: String, correction: String, whyItMatters: String,
                occurrences: Int, sourceSessionIds: [String], lastSeenAt: String) {
        self.id = id; self.learnerSaid = learnerSaid; self.correction = correction
        self.whyItMatters = whyItMatters; self.occurrences = occurrences
        self.sourceSessionIds = sourceSessionIds; self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case id, learnerSaid, correction, whyItMatters, occurrences, sourceSessionIds, lastSeenAt
    }

    /// 手写解码：**老档案里虚高的 `occurrences` 在读盘这一刻就修回来**，
    /// 用户不需要做任何事，也不需要一次性的迁移脚本。
    ///
    /// 修好之前的 `ReviewArchiver` 每次命中都 `+= 1`、只在 `sourceSessionIds` 上去重，
    /// 所以同一场复盘被归档两次（`markImported` 改名失败后重来、手工去掉 `.imported`
    /// 后缀、界面与 `coach reimport` 各导一次）会让这个数字比真实场次多，
    /// 而 `sourceSessionIds` 是干净的——恒等式 `occurrences == sourceSessionIds.count`
    /// 因此能唯一地把它算回来。
    ///
    /// `sourceSessionIds` 为空时**不动**：那种档案（手工编辑过、或上游写出来的）
    /// 算回来会变成 0，等于把一条真实存在的错题说成「一次都没犯过」，
    /// 比留着一个偏大的数更糟。
    ///
    /// 编码仍由 Swift 合成——只手写 Decodable 那一半时不影响 Encodable 的合成
    /// （与 `CoachSettings` 一致）。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        learnerSaid = try c.decode(String.self, forKey: .learnerSaid)
        correction = try c.decode(String.self, forKey: .correction)
        whyItMatters = try c.decode(String.self, forKey: .whyItMatters)
        sourceSessionIds = try c.decode([String].self, forKey: .sourceSessionIds)
        lastSeenAt = try c.decode(String.self, forKey: .lastSeenAt)

        let stored = try c.decode(Int.self, forKey: .occurrences)
        occurrences = sourceSessionIds.isEmpty ? stored : sourceSessionIds.count
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
