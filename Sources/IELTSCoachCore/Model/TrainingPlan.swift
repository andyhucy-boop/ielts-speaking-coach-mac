import Foundation

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var lengthDays: Int             // 7 | 14 | 30
    public var createdAt: String
    public var days: [PlanDay]
    /// 这个计划的重点 Part。计划页要显示它，重新生成时以它为默认值。
    public var focusPart: FocusPart

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    // focusPart 带默认值，是为了不打断 PlanBuilder.build 与 Phase 0–2 已有的调用点。
    public init(lengthDays: Int, createdAt: String, days: [PlanDay],
                focusPart: FocusPart = .fullMock) {
        self.lengthDays = lengthDays; self.createdAt = createdAt
        self.days = days; self.focusPart = focusPart
    }

    enum CodingKeys: String, CodingKey {
        case lengthDays, createdAt, days, focusPart
    }

    /// 手写解码，只为一件事：**旧版本写的 plan 里没有 focusPart，缺了也必须读得出来。**
    /// CoachState 用 decodeIfPresent 读 plan，而 decodeIfPresent 只在「键不存在」时返回 nil；
    /// 键存在但内部缺字段照样抛错，那个错会一路冒泡，让 StateStore 报
    /// 「训练数据文件已损坏」——为了一个新加的字段，把用户全部练习记录挡在门外。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lengthDays = try c.decode(Int.self, forKey: .lengthDays)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
        focusPart = try c.decodeIfPresent(FocusPart.self, forKey: .focusPart) ?? .fullMock
    }

    public var isComplete: Bool { days.allSatisfy(\.isComplete) }
}

public struct PlanDay: Codable, Equatable, Sendable, Identifiable {
    public var id: Int                     // 第几天，从 1 开始
    public var questionIds: [String]
    public var completedQuestionIds: [String]

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    public init(id: Int, questionIds: [String], completedQuestionIds: [String]) {
        self.id = id; self.questionIds = questionIds; self.completedQuestionIds = completedQuestionIds
    }

    /// 上游规则：当天全部题目都完成，这一天才算完成。
    public var isComplete: Bool {
        !questionIds.isEmpty && Set(questionIds).isSubset(of: Set(completedQuestionIds))
    }
}
