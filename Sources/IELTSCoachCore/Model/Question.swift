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

    public init(id: String, part: Int, topic: String, prompt: String,
                followups: [String] = [], source: String = "", sourceUrl: String = "",
                importLevel: String = "full-question", status: String = "new") {
        self.id = id; self.part = part; self.topic = topic; self.prompt = prompt
        self.followups = followups; self.source = source; self.sourceUrl = sourceUrl
        self.importLevel = importLevel; self.status = status
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
    }
}

public struct QuestionSource: Codable, Equatable, Sendable {
    public var title: String
    public var sourceUrl: String
    public var importedAt: String
    public var importLevel: String
    public var questionCount: Int
}
