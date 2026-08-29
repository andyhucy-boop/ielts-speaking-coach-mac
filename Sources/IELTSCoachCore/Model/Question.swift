import Foundation

public struct Question: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var part: Int                    // 1 / 2 / 3
    public var topic: String
    public var prompt: String
    public var followups: [String]
    public var source: String
    public var sourceUrl: String
    public var importLevel: String          // "full-question" | "topic-outline"
    public var status: String               // "new" | "practiced"

    /// 用户**手动把这道题标回「没练过」**的时刻（ISO8601）。没标过时是空串。
    ///
    /// ## 为什么需要它
    ///
    /// 「已练」这个标记此前是**只升不降、永久不可逆**的：随机抽了 5 道题、
    /// 只认真答了 2 道就点了「我练完了」，5 道全部永久打勾，以后再也抽不到。
    ///
    /// 而光把 `status` 改回 `"new"` 是没用的：`CoachState.reconcilePracticedStatus`
    /// 每次读盘都按练习记录把标记算回来，下一次开 App 就又变成「已练」了。
    /// 所以要记的不是「现在是什么状态」，而是**「他在哪一刻说过这道题不算数」**——
    /// 那之后再练一次，标记照常升回来。
    ///
    /// 这样两条规矩同时成立：自动算回来的那道保护还在（换季重导不会抹掉进度），
    /// 而他明确说过不算数的那几道也不会被算回来。
    public var practiceResetAt: String

    public init(id: String, part: Int, topic: String, prompt: String,
                followups: [String] = [], source: String = "", sourceUrl: String = "",
                importLevel: String = "full-question", status: String = "new",
                practiceResetAt: String = "") {
        self.id = id; self.part = part; self.topic = topic; self.prompt = prompt
        self.followups = followups; self.source = source; self.sourceUrl = sourceUrl
        self.importLevel = importLevel; self.status = status
        self.practiceResetAt = practiceResetAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        part = try c.decode(Int.self, forKey: .part)
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        prompt = try c.decode(String.self, forKey: .prompt)
        followups = try c.decodeIfPresent([String].self, forKey: .followups) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        importLevel = try c.decodeIfPresent(String.self, forKey: .importLevel) ?? "full-question"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "new"
        practiceResetAt = try c.decodeIfPresent(String.self, forKey: .practiceResetAt) ?? ""
    }
}

public struct QuestionSource: Codable, Equatable, Sendable {
    public var title: String
    public var sourceUrl: String
    public var importedAt: String
    public var importLevel: String
    public var questionCount: Int

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(title: String, sourceUrl: String, importedAt: String,
                importLevel: String, questionCount: Int) {
        self.title = title; self.sourceUrl = sourceUrl; self.importedAt = importedAt
        self.importLevel = importLevel; self.questionCount = questionCount
    }
}
