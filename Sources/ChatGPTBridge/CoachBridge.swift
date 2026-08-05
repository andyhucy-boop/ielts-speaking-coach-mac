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
    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String
    /// 等 ChatGPT 把上一条消息回复完，见 `AXDriver.waitForAssistantReply`。
    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int) throws
}

extension CoachBridge {
    /// 协议里的方法要求本身不能带默认参数值（会破坏见证表派发），
    /// 用扩展补一个「省略 expectedMarker」的重载，行为等价于 `expectedMarker: nil`。
    public func captureLatestAssistantMessage() throws -> String {
        try captureLatestAssistantMessage(expectedMarker: nil)
    }

    /// 同理：省略 `minimumLength` 的重载，默认 60 字符，与 `AXDriver` 的默认值保持一致。
    public func waitForAssistantReply(timeout: TimeInterval) throws {
        try waitForAssistantReply(timeout: timeout, minimumLength: 60)
    }
}
