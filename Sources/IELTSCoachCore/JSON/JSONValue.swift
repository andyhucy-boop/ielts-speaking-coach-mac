import Foundation

/// 动态 JSON 值。复盘报告的结构由 ChatGPT 生成，不能用固定 struct 表达。
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
