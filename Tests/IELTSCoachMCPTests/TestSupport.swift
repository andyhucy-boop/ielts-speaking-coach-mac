import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachMCP

/// 每个测试一个独立的临时数据目录。
/// **绝不能让测试写到 DataDirectory.resolve() 的真实目录**——那是用户的训练记录。
func makeTemporaryDirectory() -> DataDirectory {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ielts-mcp-\(UUID().uuidString)")
    return DataDirectory(root: root)
}

/// 记录被请求打开的 URL，永远不真的打开任何东西。
/// 真机上唤起 App 是 Task 13 的人工验收，单元测试里一次都不许发生。
final class FakeDashboardOpener: DashboardOpening {
    private(set) var opened: [URL] = []
    var errorToThrow: (any Error)?

    func open(_ url: URL) throws {
        if let errorToThrow { throw errorToThrow }
        opened.append(url)
    }
}

/// 固定时间的运行环境，测试里一律用它，免得断言随「今天几号」变化。
func makeEnvironment(directory: DataDirectory, opener: FakeDashboardOpener,
                     nowISO: String = "2026-08-06T12:00:00Z") -> MCPEnvironment {
    let now = ISO8601DateFormatter().date(from: nowISO)!
    return MCPEnvironment(directory: directory, opener: opener, now: { now },
                          timeZone: TimeZone(identifier: "UTC")!)
}

/// 让每个 tool 测试都**走一遍真实的协议层**再落到工具上。
/// 直接调 `tool.run` 会漏掉 tools/call 的参数校验，那部分同样会在真机上出事。
///
/// `init(environment:)` 那个 convenience init 要等 Task 6 建出 `ToolCatalog` 之后再补
/// （见 Phase 9 计划 Task 5 Step 3 的备注）。
final class ServerHarness {
    let server: MCPServer
    private var nextID = 100

    init(tools: [MCPTool]) {
        server = MCPServer(tools: tools)
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#)
    }

    enum HarnessError: Error { case noResponse, unexpectedProtocolError(String) }

    /// 返回工具的文本负载与 isError。落到协议错误上会直接让测试失败并打印原文——
    /// 那说明测试自己把参数传错了，不该被当成「工具返回了错误」。
    @discardableResult
    func callTool(_ name: String, _ arguments: [String: JSONValue] = [:],
                  file: StaticString = #filePath, line: UInt = #line)
        throws -> (text: String, isError: Bool) {
        nextID += 1
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(nextID)),
            "method": .string("tools/call"),
            "params": .object(["name": .string(name), "arguments": .object(arguments)])
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let requestLine = String(data: try encoder.encode(request), encoding: .utf8)!

        guard let responseLine = server.handle(line: requestLine) else {
            XCTFail("调用 \(name) 没有得到任何响应", file: file, line: line)
            throw HarnessError.noResponse
        }
        let response = try JSONValue.decode(from: responseLine)
        if let error = response["error"] {
            let message = error["message"]?.stringValue ?? "\(error)"
            XCTFail("调用 \(name) 落到了协议错误上：\(message)", file: file, line: line)
            throw HarnessError.unexpectedProtocolError(message)
        }
        let text = response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        let isError = response["result"]?["isError"] == .bool(true)
        return (text, isError)
    }

    /// 工具成功时返回的是一段 JSON 文本，这里解析开好做断言。
    func callToolJSON(_ name: String, _ arguments: [String: JSONValue] = [:],
                      file: StaticString = #filePath, line: UInt = #line) throws -> JSONValue {
        let result = try callTool(name, arguments, file: file, line: line)
        XCTAssertFalse(result.isError, "\(name) 本应成功，实际返回：\(result.text)", file: file, line: line)
        return try JSONValue.decode(from: result.text)
    }
}
