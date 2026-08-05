import Foundation

public struct LearnerProfile: Codable, Equatable, Sendable {
    public var displayName: String
    public var createdAt: String

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(displayName: String, createdAt: String) {
        self.displayName = displayName; self.createdAt = createdAt
    }
}

public struct CoachSettings: Codable, Equatable, Sendable {
    public var recordingEnabled: Bool
    public var recordingConsentAt: String

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(recordingEnabled: Bool, recordingConsentAt: String) {
        self.recordingEnabled = recordingEnabled; self.recordingConsentAt = recordingConsentAt
    }
}

public struct QuestionCursor: Codable, Equatable, Sendable {
    public var part1: Int
    public var part2: Int
    public var part3: Int

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(part1: Int, part2: Int, part3: Int) {
        self.part1 = part1; self.part2 = part2; self.part3 = part3
    }
}

/// state.json 的顶层模型。字段名与上游逐字一致，全部 camelCase。
public struct CoachState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var learner: LearnerProfile
    public var currentSession: PracticeSession?
    public var sessions: [PracticeSession]
    public var targets: [RetrainingTarget]
    public var issues: [IssueRecord]
    public var vocabulary: [VocabularyRecord]
    public var plan: TrainingPlan?
    public var questions: [Question]
    public var questionSources: [QuestionSource]
    public var settings: CoachSettings
    public var questionCursor: QuestionCursor

    /// 同时手写 init(from:) 和 encode(to:) 之后，Swift 不再自动合成 CodingKeys
    /// （只有还需要合成 Encodable 或 Decodable 中至少一个时才会合成），必须显式声明。
    enum CodingKeys: String, CodingKey {
        case schemaVersion, learner, currentSession, sessions, targets, issues,
             vocabulary, plan, questions, questionSources, settings, questionCursor
    }

    public static func empty(displayName: String = "",
                             createdAt: String = ISO8601DateFormatter().string(from: Date())) -> CoachState {
        CoachState(
            schemaVersion: 3,
            learner: LearnerProfile(displayName: displayName, createdAt: createdAt),
            currentSession: nil, sessions: [], targets: [], issues: [], vocabulary: [],
            plan: nil, questions: [], questionSources: [],
            settings: CoachSettings(recordingEnabled: false, recordingConsentAt: ""),
            questionCursor: QuestionCursor(part1: 0, part2: 0, part3: 0)
        )
    }

    /// 容忍缺字段的解码，等价于上游 ensureWorkspace 的补齐逻辑。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 3
        if schemaVersion < 2 { schemaVersion = 3 }
        learner = try c.decodeIfPresent(LearnerProfile.self, forKey: .learner)
            ?? LearnerProfile(displayName: "", createdAt: ISO8601DateFormatter().string(from: Date()))
        currentSession = try c.decodeIfPresent(PracticeSession.self, forKey: .currentSession)
        sessions = try c.decodeIfPresent([PracticeSession].self, forKey: .sessions) ?? []
        targets = try c.decodeIfPresent([RetrainingTarget].self, forKey: .targets) ?? []
        issues = try c.decodeIfPresent([IssueRecord].self, forKey: .issues) ?? []
        vocabulary = try c.decodeIfPresent([VocabularyRecord].self, forKey: .vocabulary) ?? []
        plan = try c.decodeIfPresent(TrainingPlan.self, forKey: .plan)
        questions = try c.decodeIfPresent([Question].self, forKey: .questions) ?? []
        questionSources = try c.decodeIfPresent([QuestionSource].self, forKey: .questionSources) ?? []
        settings = try c.decodeIfPresent(CoachSettings.self, forKey: .settings)
            ?? CoachSettings(recordingEnabled: false, recordingConsentAt: "")
        questionCursor = try c.decodeIfPresent(QuestionCursor.self, forKey: .questionCursor)
            ?? QuestionCursor(part1: 0, part2: 0, part3: 0)
    }

    public init(schemaVersion: Int, learner: LearnerProfile, currentSession: PracticeSession?,
                sessions: [PracticeSession], targets: [RetrainingTarget], issues: [IssueRecord],
                vocabulary: [VocabularyRecord], plan: TrainingPlan?, questions: [Question],
                questionSources: [QuestionSource], settings: CoachSettings,
                questionCursor: QuestionCursor) {
        self.schemaVersion = schemaVersion; self.learner = learner
        self.currentSession = currentSession; self.sessions = sessions
        self.targets = targets; self.issues = issues; self.vocabulary = vocabulary
        self.plan = plan; self.questions = questions; self.questionSources = questionSources
        self.settings = settings; self.questionCursor = questionCursor
    }

    /// 手写 encode(to:)：Swift 对 Optional 属性默认走 encodeIfPresent，
    /// nil 时会整体省略字段而不是写 null，与上游 state.json 「字段总是存在」的形状不符。
    /// 这里显式用 encode(_:forKey:) 而非 encodeIfPresent，保证 currentSession / plan
    /// 在 nil 时仍编码为 "currentSession": null，而不是消失。
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(learner, forKey: .learner)
        try c.encode(currentSession, forKey: .currentSession)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(targets, forKey: .targets)
        try c.encode(issues, forKey: .issues)
        try c.encode(vocabulary, forKey: .vocabulary)
        try c.encode(plan, forKey: .plan)
        try c.encode(questions, forKey: .questions)
        try c.encode(questionSources, forKey: .questionSources)
        try c.encode(settings, forKey: .settings)
        try c.encode(questionCursor, forKey: .questionCursor)
    }
}
