import Foundation
import IELTSCoachCore

/// MCP over stdio 的协议层。**只做一件事：吃一行、吐一行。**
/// 真正读写 stdin/stdout 的代码在可执行文件里，这样协议逻辑百分之百可测。
///
/// 分帧是 NDJSON（每条消息一行、行内无裸换行），不是 LSP 那种 Content-Length 头。
public final class MCPServer {
    /// 从新到旧。客户端要的版本在列表里就原样回，不在就回列表第一个——
    /// 鹦鹉学舌地回一个自己并不支持的版本，比明确降级更糟。
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverName = "ielts-speaking-mcp"
    public static let serverVersion = "0.9.0"

    private let tools: [MCPTool]
    private var initialized = false

    public init(tools: [MCPTool]) { self.tools = tools }

    /// 返回要写回 stdout 的一行；通知与空行返回 nil（通知不许有响应）。
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let message = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.parseError,
                message: "收到的这一行不是合法 JSON，无法解析。"
                    + "下一步：按 MCP stdio 规范每行发送一条完整的 JSON-RPC 消息（消息内部不能有裸换行）。"))
        }

        if message.arrayValue != nil {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "本服务器不接受批量请求（JSON-RPC batch），MCP 2025-06-18 已移除该特性。"
                    + "下一步：把每条请求单独发一行。"))
        }
        guard message.objectValue != nil else {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "JSON-RPC 消息的顶层必须是对象。下一步：改发形如 "
                    + #"{"jsonrpc":"2.0","id":1,"method":"tools/list"} 的对象。"#))
        }

        let method = message["method"]?.stringValue

        switch parseID(message["id"]) {
        case .notification:
            // 通知没有响应，哪怕它是畸形的。回一条会让客户端收到对不上号的消息。
            if method == "notifications/initialized" { initialized = true }
            return nil
        case .invalid:
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "请求的 id 必须是字符串或整数。下一步：改用 \"id\": 1 或 \"id\": \"abc\" 这样的形式。"))
        case .value(let id):
            return encode(dispatch(id: id, method: method, message: message))
        }
    }

    // MARK: - 分发

    private func dispatch(id: JSONRPCID, method: String?, message: JSONValue) -> JSONRPCResponse {
        guard message["jsonrpc"]?.stringValue == "2.0" else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "缺少 jsonrpc 字段或它不是 \"2.0\"。下一步：每条消息都带上 \"jsonrpc\": \"2.0\"。")
        }
        guard let method, !method.isEmpty else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "缺少 method 字段。下一步：带上 method，例如 \"method\": \"tools/list\"。")
        }

        if method == "initialize" {
            initialized = true
            return .success(id: id, result: initializeResult(params: message["params"]))
        }

        guard initialized else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "还没完成 initialize 握手，不能调用「\(method)」。"
                    + "下一步：先发一条 initialize 请求，再发其他请求。")
        }

        switch method {
        case "ping":
            return .success(id: id, result: .object([:]))
        case "tools/list":
            return .success(id: id, result: toolsListResult())
        case "tools/call":
            return callTool(id: id, params: message["params"])
        default:
            return .failure(id: id, code: JSONRPCErrorCode.methodNotFound,
                message: "不支持的方法「\(method)」。"
                    + "下一步：本服务器只实现 initialize、ping、tools/list、tools/call 四个方法；"
                    + "所有能力都通过 tools/call 使用。")
        }
    }

    private func initializeResult(params: JSONValue?) -> JSONValue {
        let requested = params?["protocolVersion"]?.stringValue ?? ""
        let version = Self.supportedProtocolVersions.contains(requested)
            ? requested : Self.supportedProtocolVersions[0]
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": .object([
                "name": .string(Self.serverName),
                "version": .string(Self.serverVersion)
            ]),
            "instructions": .string(
                "本机的雅思口语训练工具。先调用 initialize_ielts_workspace 建好工作区，"
                + "再用 set_training_selection 选题、get_training_context 取考官提示词；"
                + "练完把 ChatGPT 输出的整段复盘交给 save_session_review。"
                + "所有数据都在本机，不联网。")
        ])
    }

    private func toolsListResult() -> JSONValue {
        .object(["tools": .array(tools.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        })])
    }

    private func callTool(id: JSONRPCID, params: JSONValue?) -> JSONRPCResponse {
        guard let params, params.objectValue != nil else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 缺少 params 对象。"
                    + "下一步：传 {\"name\": \"工具名\", \"arguments\": {…}}。")
        }
        guard let name = params["name"]?.stringValue, !name.isEmpty else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 的 params 里缺少 name。"
                    + "下一步：先调用 tools/list 看可用工具，再把工具名填进 name。")
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "没有名为「\(name)」的工具。"
                    + "下一步：可用的工具是 \(tools.map(\.name).joined(separator: "、"))。")
        }
        let arguments = params["arguments"] ?? .object([:])
        guard arguments.objectValue != nil else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 的 arguments 必须是 JSON 对象。"
                    + "下一步：不传参数时可以整个省略 arguments，或传 {}。")
        }

        let outcome = tool.run(arguments)
        return .success(id: id, result: .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(outcome.text)
            ])]),
            "isError": .bool(outcome.isError)
        ]))
    }

    // MARK: - id

    private enum IDParse {
        case notification            // 没有 id
        case invalid                 // 有 id，但既不是字符串也不是整数
        case value(JSONRPCID)
    }

    private func parseID(_ raw: JSONValue?) -> IDParse {
        guard let raw else { return .notification }
        if let text = raw.stringValue { return .value(.string(text)) }
        if let number = raw.intValue { return .value(.number(number)) }
        return .invalid              // 含 "id": null —— MCP 明确禁止 null id
    }

    // MARK: - 编码

    private func encode(_ response: JSONRPCResponse) -> String {
        let encoder = JSONEncoder()
        // 不能用 .prettyPrinted：NDJSON 要求一条消息一行。
        // .sortedKeys 让输出确定，测试才好断言。
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(response),
              let text = String(data: data, encoding: .utf8) else {
            // 连响应都编不出来时也必须回一条合法的 JSON-RPC 错误。
            // 什么都不回 = 客户端一直等下去（禁止无限等待）。
            return #"{"error":{"code":-32603,"message":"服务器无法编码本次响应。下一步：把这条消息连同复现步骤反馈给开发者。"},"id":null,"jsonrpc":"2.0"}"#
        }
        return text
    }
}
