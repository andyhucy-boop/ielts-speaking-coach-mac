import Foundation
import IELTSCoachCore

/// 一次工具调用的结果。`isError` 为真时 MCP 客户端仍然收到一条正常的 result，
/// 只是内容标着「这次失败了」——模型能读到失败原因并自我纠正。
/// 这与协议错误是两回事，别混：协议错误的文本模型看不到。
public struct ToolOutcome: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text; self.isError = isError
    }

    public static func success(_ text: String) -> ToolOutcome { ToolOutcome(text: text, isError: false) }
    public static func failure(_ message: String) -> ToolOutcome { ToolOutcome(text: message, isError: true) }
}

// MARK: - 工具
//
// 工具的输入与错误类型不在这里：`ToolInputError` 与 `ToolArguments` 在
// ToolArguments.swift，`DashboardOpenError` 与 `DashboardOpening` 在 MCPEnvironment.swift。
// 下面的 `throwing` 会捕获它们，把中文文案原样透给模型。

public struct MCPTool {
    public let name: String
    /// 面向用户与模型的中文说明。必须说清「这个工具干什么」，
    /// 需要前置条件的还要说清「先调哪个」。
    public let description: String
    public let inputSchema: JSONValue
    public let run: (JSONValue) -> ToolOutcome

    public init(name: String, description: String, inputSchema: JSONValue,
                run: @escaping (JSONValue) -> ToolOutcome) {
        self.name = name; self.description = description
        self.inputSchema = inputSchema; self.run = run
    }

    /// 把会抛错的实现包成绝不抛错的 `run`。
    /// **任何异常都不许穿透到协议层**——协议层挂了整条 stdio 就断了，
    /// 客户端只会看到「服务器没响应」，一点线索都没有。
    public static func throwing(name: String, description: String, inputSchema: JSONValue,
                                body: @escaping (ToolArguments) throws -> String) -> MCPTool {
        MCPTool(name: name, description: description, inputSchema: inputSchema) { arguments in
            do {
                return .success(try body(ToolArguments(arguments)))
            } catch let error as ToolInputError {
                return .failure(error.message)
            } catch let error as DashboardOpenError {
                return .failure(error.message)
            } catch let error as CoachError {
                // CoachError 的文案本来就是中文且带「下一步」，原样透出即可
                return .failure(error.errorDescription ?? "\(error)")
            } catch {
                return .failure("工具「\(name)」执行失败：\(error.localizedDescription)。"
                    + "下一步：把这条消息连同刚才的调用参数一起反馈给开发者。")
            }
        }
    }
}

enum ToolJSON {
    /// 工具的返回负载统一用 Codable struct 编码：
    /// 字段是 Int 就编成 `5`，不会变成 `5.0`，也不用手工拼 JSON。
    static func text<Payload: Encodable>(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolInputError(message: "工具的返回内容无法编码成文本。"
                + "下一步：把这条消息连同刚才的调用参数一起反馈给开发者。")
        }
        return text
    }
}
