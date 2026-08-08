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
    /// 新建一个空会话，见 `AXDriver.startNewChat`。**每次练习前都要先调用它**——
    /// Live 语音只能在还没发送过任何消息的会话里启动。
    func startNewChat() throws
    /// 把文字写进输入框并发出去。
    ///
    /// **`target` 没有默认值是刻意的：调用方必须想清楚这段文字该进哪个框。**
    ///
    /// 2026-08-08 真机发现的缺陷就出在这里：此前 `sendText` 只会「找一个输入框」，
    /// 而 `ChatGPTLabels.composer(among:)` 取的是树里排在前面的那个。语音起来之后，
    /// 普通聊天的输入框仍然在树里且往往排在前面，于是考官提示词被打进了那个
    /// **属于文字会话的框**——用户看到的是「新建对话 → 点语音 → 又新建了一个对话 →
    /// 提示词发进了那个文字会话」，而语音那边一个字都没收到。
    ///
    /// 项目里本来就有 `waitForVoiceComposer`，注释还写明了这个坑，只是没人接上。
    /// 给个默认值等于把这个坑原样留着——所以不给。
    func sendText(_ text: String, into target: ComposerTarget) throws
    func startVoice() throws
    /// 等语音模式的输入框出现，见 `AXDriver.waitForVoiceComposer`。
    @discardableResult
    func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot
    func isVoiceActive() -> Bool
    func endVoice() throws
    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String
    /// 等 ChatGPT 把上一条消息回复完，见 `AXDriver.waitForAssistantReply`。
    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int) throws
    /// 按 ChatGPT 自己的复制按钮取回最新一条回复，见 `AXDriver.copyLatestAssistantMessage`。
    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess, timeout: TimeInterval) throws -> String
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
