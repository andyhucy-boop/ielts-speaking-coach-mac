import Foundation
import IELTSCoachCore

/// JSON-RPC 2.0 的请求 id。**必须区分整数与字符串并原样回**：
/// 客户端（Codex 是 Rust 写的）把整数 id 反序列化成 i64，回 `7.0` 会让它
/// 直接解析失败，而症状是「服务器有响应，客户端报协议错误」——最难查的一类。
public enum JSONRPCID: Equatable, Sendable, Encodable {
    case number(Int)
    case string(String)
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

struct JSONRPCErrorObject: Encodable {
    let code: Int
    let message: String
}

/// `result` 与 `error` 二选一。两个都是 Optional，Swift 合成的 encode 走
/// encodeIfPresent，nil 的那个自然不会出现在 JSON 里。
struct JSONRPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    var result: JSONValue?
    var error: JSONRPCErrorObject?

    static func success(id: JSONRPCID, result: JSONValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }

    static func failure(id: JSONRPCID, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCErrorObject(code: code, message: message))
    }
}
