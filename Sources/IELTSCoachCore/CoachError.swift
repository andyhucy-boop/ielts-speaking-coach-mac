import Foundation

/// 所有面向用户的错误。message 必须是中文，且同时说明发生了什么与下一步做什么。
public enum CoachError: Error, Equatable, LocalizedError {
    case invalidReviewText(String)
    case reviewNotFound(String)
    case reviewIncomplete(String)
    case stateUnreadable(String)
    case questionBankInvalid(String)
    case planImpossible(String)
    case invalidSessionID(String)

    /// **这是不是「ChatGPT 那份复盘的格式不对」**——也就是那种「告诉它哪里不对、
    /// 让它重出一份」多半就能救回来的失败。
    ///
    /// 三个取值都由 `ReviewParser` 抛出，说的是同一类事：原文取回来了、也已经落盘，
    /// 只是读不成本工具认得的形状。**存盘失败（`stateUnreadable`）不在里面**：
    /// 那是磁盘的问题，再问 ChatGPT 一百遍也没用，而重问会让用户白等一分钟。
    ///
    /// 用穷尽的 `switch` 而不是 `if case`：将来加了新的错误取值，
    /// 这里会当场编译不过、逼人表态，而不是安静地被归进「不重问」那一支。
    public var isReviewFormatProblem: Bool {
        switch self {
        case .invalidReviewText, .reviewNotFound, .reviewIncomplete:
            return true
        case .stateUnreadable, .questionBankInvalid, .planImpossible, .invalidSessionID:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidReviewText(let m), .reviewNotFound(let m), .reviewIncomplete(let m),
             .stateUnreadable(let m), .questionBankInvalid(let m), .planImpossible(let m),
             .invalidSessionID(let m):
            return m
        }
    }
}
