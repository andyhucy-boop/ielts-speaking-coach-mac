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
    /// `PracticeRoute.rawValue` 的默认值。**`PracticeRoute` 定义在 `IELTSCoachUI` 里，
    /// 而 Core 不允许依赖 UI**，所以这里只能存字符串。两边的对齐由
    /// `Tests/IELTSCoachUITests/PracticeRoutePreferenceTests.swift` 里的一条测试守住。
    public static let defaultRouteFallback = "planToday"

    public var recordingEnabled: Bool
    public var recordingConsentAt: String
    /// 「记录对话逐字稿」。ROADMAP 第 5 节：开 / 关，**默认开**。
    ///
    /// 与录音开关的区别，别把两者混为一谈：
    /// 逐字稿只多采集 AX 树，没有隐私成本、不需要任何系统权限，且是复盘质量与
    /// 训练记录的共同基础；录音要麦克风权限、要磁盘，所以默认关、且需要明确同意。
    public var transcriptEnabled: Bool
    /// 每周训练目标次数。ROADMAP 第 5 节：用户可配置，默认 5 次。**Phase 7 Task 1 加的。**
    public var weeklyGoal: Int
    /// 用户偏好的练习路线，存的是 `PracticeRoute.rawValue`。
    /// ROADMAP 第 5 节：默认「按计划练今天」。**Phase 8 Task 2 加的。**
    public var defaultRoute: String
    /// 考官何时给反馈。ROADMAP 第 5 节：默认全程零反馈。**Phase 8 Task 2 加的。**
    public var feedbackTiming: FeedbackTiming
    /// Part 2 的一分钟准备怎么处理。ROADMAP 第 5 节：默认倒计时。**Phase 8 Task 2 加的。**
    public var part2PrepMode: Part2PrepMode

    public static let defaultTranscriptEnabled = true

    public static let defaultWeeklyGoal = 5
    /// 上限 21 = 一天三场。给上限是为了让界面上的 Stepper 有边界，
    /// 也挡住手滑输入的 999——「本周 3/999 次」这种显示毫无意义。
    public static let weeklyGoalRange = 1...21

    /// 越界或缺失一律回落到默认值，而不是抛错——
    /// 一个坏掉的目标数字不该让用户整份训练数据读不出来。
    public static func normalized(_ raw: Int?) -> Int {
        guard let raw, weeklyGoalRange.contains(raw) else { return defaultWeeklyGoal }
        return raw
    }

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    // transcriptEnabled / weeklyGoal 都给默认值，既有调用点（CoachState.empty、各处测试）不用改。
    // **transcriptEnabled 保持在 weeklyGoal 前面，与 Phase 4 定下的位置一致**——
    // 换位置会打断 Phase 4 已有的调用点；两个都有默认值，只传 weeklyGoal: 照样能编译。
    // Phase 8 的三项练习偏好一律**追加在末尾**，同样只为了不动前面阶段已有的调用点。
    public init(recordingEnabled: Bool, recordingConsentAt: String,
                transcriptEnabled: Bool = CoachSettings.defaultTranscriptEnabled,
                weeklyGoal: Int = CoachSettings.defaultWeeklyGoal,
                defaultRoute: String = CoachSettings.defaultRouteFallback,
                feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.recordingEnabled = recordingEnabled
        self.recordingConsentAt = recordingConsentAt
        self.transcriptEnabled = transcriptEnabled
        self.weeklyGoal = CoachSettings.normalized(weeklyGoal)
        self.defaultRoute = defaultRoute
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }

    enum CodingKeys: String, CodingKey {
        case recordingEnabled, recordingConsentAt, transcriptEnabled, weeklyGoal
        case defaultRoute, feedbackTiming, part2PrepMode
    }

    /// 先读字符串再转枚举，转不出来就用默认值。
    /// 直接 decode 枚举的话，遇到不认识的取值会抛 `dataCorrupted`，而这个错会一路
    /// 冒泡到 `CoachState`，让 `StateStore` 报「训练数据文件已损坏」——
    /// 为了一个偏好设置丢掉全部练习记录，不成比例。
    /// **注意 `decodeIfPresent` 只挡「键不存在」，挡不住「键在但值不认识」**，
    /// 所以这一层不能省。
    private static func stringEnum<T: RawRepresentable>(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, fallback: T
    ) -> T where T.RawValue == String {
        let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        return raw.flatMap(T.init(rawValue:)) ?? fallback
    }

    /// 手写解码：transcriptEnabled 是 Phase 4、weeklyGoal 是 Phase 7 才加的字段，
    /// 老的 state.json 里没有它们。
    /// 合成的解码器遇到缺键会直接抛错，等于「升级一次版本，全部训练数据读不出来」。
    /// 与 `CoachState.init(from:)` 的容错策略一致。
    ///
    /// 编码仍由 Swift 合成——只手写 Decodable 那一半时，Encodable 的合成不受影响。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? false
        recordingConsentAt = try container.decodeIfPresent(String.self, forKey: .recordingConsentAt) ?? ""
        // ↓ Phase 4 Task 2 的那一行，原样保留。删了它，用户关掉的逐字稿开关
        //   会在下一次写盘时被默认值悄悄盖回「开」，而且没有任何报错。
        transcriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .transcriptEnabled)
            ?? CoachSettings.defaultTranscriptEnabled
        weeklyGoal = CoachSettings.normalized(
            try container.decodeIfPresent(Int.self, forKey: .weeklyGoal))
        // ↓ Phase 8 Task 2 的三行。老的 state.json 里没有这三个键，缺了必须照样读得出来。
        defaultRoute = try container.decodeIfPresent(String.self, forKey: .defaultRoute)
            ?? CoachSettings.defaultRouteFallback
        feedbackTiming = CoachSettings.stringEnum(container, .feedbackTiming, fallback: .deferred)
        part2PrepMode = CoachSettings.stringEnum(container, .part2PrepMode, fallback: .countdown)
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

    /// 按练习记录把题库的「已练」标记算回来。**纯函数，读盘时跑一次。**
    ///
    /// 两件事：
    ///
    /// 1. **给已经踩过坑的用户的自动迁移。** 换季重新导入曾经把每道练过的题的
    ///    `status` 抹回 `"new"`（复审第 10 条），而那个标记「丢了就再也回不来」。
    ///    数据其实是够的——每条练习记录都存着 `questionId`，所以这里能算回来，
    ///    用户不需要做任何事，也不需要一次性的迁移脚本。做法与
    ///    `IssueRecord.occurrences` 那处自愈一致。
    /// 2. **一道恒久的守卫。** 以后再有谁在合并、重排、生成计划的路上顺手重置
    ///    `status`，下一次读盘就会把它纠回来，用户看不到进度倒退。
    ///
    /// **只升不降。** 没有练习记录的题一个字都不动：训练记录允许被单条删除
    /// （确认框逐字承诺「已经归进错题本和词汇本的内容不会跟着删」），
    /// 删掉一条记录不该连带把题库上那道题的进度也抹掉。
    ///
    /// 只认 `sessions`，不认 `currentSession`：正在练、还没归档的那一场随时可能被放弃。
    public static func reconcilePracticedStatus(questions: [Question],
                                                sessions: [PracticeSession]) -> [Question] {
        // **走 `allQuestionIds` 而不是 `questionId`。** 随机抽题一场会安排一整组题
        // （`PracticeSession.drawnQuestionIds`），只认开场那一道的话，同一场里另外几道
        // 会永远停在「新题」，于是「只抽没练过的」一遍遍把它们再抽出来，
        // 而训练题库页那个「已练 N / 258」也永远少数它们——两样都不会报错。
        // **每道题记「最近一次被练到是什么时候」**，而不只是「练没练过」。
        //
        // 只记一个 id 集合的话，用户手动把一道题标回「没练过」之后，
        // 下一次读盘就会照着旧的练习记录把它又算成已练——
        // 那颗按钮点得动、却什么都改不了（本项目最忌讳的静默失败）。
        var lastPracticed: [String: String] = [:]
        for session in sessions {
            for id in session.allQuestionIds
            where session.startedAt > (lastPracticed[id] ?? "") {
                lastPracticed[id] = session.startedAt
            }
        }
        guard !lastPracticed.isEmpty else { return questions }
        return questions.map { question in
            guard question.status != "practiced",
                  let practicedAt = lastPracticed[question.id] else { return question }
            // **他说过不算数之后又练了一次的，照常升回来。**
            // 时间戳都是本工具写的 ISO8601（统一格式、全是 Z 时区），字典序即时间序。
            guard practicedAt > question.practiceResetAt else { return question }
            var upgraded = question
            upgraded.status = "practiced"
            return upgraded
        }
    }

    /// 把一道题**标回「没练过」**，让它重新参与随机抽题与计划排题。
    ///
    /// 记下这一刻（`Question.practiceResetAt`）而不只是改 `status`：
    /// 只改状态的话，下一次读盘 `reconcilePracticedStatus` 会照着旧的练习记录
    /// 把它又算成已练。**练习记录一个字都不动**——那一场确实发生过。
    ///
    /// - Returns: 真的改了返回 true；这道题本来就不是「已练」时返回 false（调用方据此说话）。
    @discardableResult
    public static func markUnpracticed(questionID: String, in state: inout CoachState,
                                       at timestamp: String) -> Bool {
        guard let index = state.questions.firstIndex(where: { $0.id == questionID }),
              state.questions[index].status == "practiced" else { return false }
        state.questions[index].status = "new"
        state.questions[index].practiceResetAt = timestamp
        return true
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
        // ↓ 读盘这一刻把被抹掉的「已练」标记算回来（见 reconcilePracticedStatus）。
        //   放在最后，因为它同时要用 questions 和 sessions。
        questions = Self.reconcilePracticedStatus(questions: questions, sessions: sessions)
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
