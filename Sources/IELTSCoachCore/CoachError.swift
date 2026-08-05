import Foundation

/// 所有面向用户的错误。message 必须是中文，且同时说明发生了什么与下一步做什么。
public enum CoachError: Error, Equatable, LocalizedError {
    case invalidReviewText(String)
    case reviewNotFound(String)
    case reviewIncomplete(String)
    case stateUnreadable(String)
    case questionBankInvalid(String)
    case planImpossible(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReviewText(let m), .reviewNotFound(let m), .reviewIncomplete(let m),
             .stateUnreadable(let m), .questionBankInvalid(let m), .planImpossible(let m):
            return m
        }
    }
}
