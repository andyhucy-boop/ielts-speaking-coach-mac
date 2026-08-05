import Foundation

public enum BridgeError: Error, Equatable, LocalizedError {
    case targetNotInstalled(String)
    case accessibilityDenied(String)
    case treeNotAwake(String)
    case elementNotFound(String)
    case stateNotReached(String)
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .targetNotInstalled(let m), .accessibilityDenied(let m), .treeNotAwake(let m),
             .elementNotFound(let m), .stateNotReached(let m), .actionFailed(let m):
            return m
        }
    }
}

public struct BridgeReadiness: Equatable, Sendable {
    public let ok: Bool
    public let messages: [String]
    public init(ok: Bool, messages: [String]) { self.ok = ok; self.messages = messages }
}

/// App 层只依赖这个 protocol，不感知内部用的是 AX 还是剪贴板。
public protocol CoachBridge {
    func preflight() -> BridgeReadiness
    func sendText(_ text: String) throws
    func startVoice() throws
    func isVoiceActive() -> Bool
    func endVoice() throws
    func captureLatestAssistantMessage() throws -> String
}
