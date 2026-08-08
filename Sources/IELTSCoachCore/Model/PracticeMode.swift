import Foundation

/// 考官何时给反馈。用户在开始练习前选择。
public enum FeedbackTiming: String, Codable, Equatable, Sendable, CaseIterable {
    /// 全程零反馈，像真考试。所有反馈憋到最后的结构化复盘。
    case deferred
    /// 每答完一题，考官用中文当场点出最主要的一个问题，然后立刻问下一题。
    case immediate
}

/// Part 2 的一分钟准备怎么处理。用户在开始练习前选择。
public enum Part2PrepMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// 像真考试：宣布一分钟准备并倒计时，时间到自动开始。
    case countdown
    /// 学员自己说准备好了再开始，不限时、不催。
    case learnerControlled = "learner-controlled"
}
