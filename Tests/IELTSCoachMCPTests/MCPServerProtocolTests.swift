import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

/// 协议层测试。**刻意不用真的 tool**——用两个假的，把「协议怎么回话」
/// 和「工具做什么」分开测。协议层崩了，客户端只会看到「服务器没响应」，
/// 拿不到任何线索。
final class MCPServerProtocolTests: XCTestCase {
    private static let initializeLine = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#

    private func makeServer(initialized: Bool = true) -> MCPServer {
        let echo = MCPTool(
            name: "echo",
            description: "把 message 原样返回，测试用。",
            inputSchema: .object(["type": .string("object")]),
            run: { arguments in .success(arguments["message"]?.stringValue ?? "(没有 message)") })

        let explode = MCPTool.throwing(
            name: "explode",
            description: "总是抛错，测试用。",
            inputSchema: .object(["type": .string("object")])) { _ in
                throw NSError(domain: "test", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "假装炸了"])
            }

        let server = MCPServer(tools: [echo, explode])
        if initialized { _ = server.handle(line: Self.initializeLine) }
        return server
    }

    /// 发一行、收一行、解析成 JSONValue。顺手把「响应必须是单独一行」也验了——
    /// 响应里混进换行会把 NDJSON 分帧撕成两半，客户端从此对不上号。
    private func respond(_ server: MCPServer, to line: String,
                         file: StaticString = #filePath, testLine: UInt = #line) throws -> JSONValue {
        let raw = try XCTUnwrap(server.handle(line: line),
                                "这条请求应当有响应，实际什么都没返回", file: file, line: testLine)
        XCTAssertFalse(raw.contains("\n"), "响应必须是单独一行，实际是：\(raw)", file: file, line: testLine)
        return try JSONValue.decode(from: raw)
    }

    // MARK: - 畸形输入

    func testMalformedJSONBecomesParseErrorInsteadOfCrashing() throws {
        let response = try respond(makeServer(), to: "{ 这不是 JSON")
        XCTAssertEqual(response["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32700)
        XCTAssertEqual(response["id"], JSONValue.null, "连 id 都没解析出来，只能回 null")
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("下一步"),
                      "错误信息必须说清下一步做什么")
    }

    func testServerKeepsWorkingAfterMalformedInput() throws {
        let server = makeServer()
        _ = server.handle(line: "{ 坏消息")
        let response = try respond(server, to: #"{"jsonrpc":"2.0","id":9,"method":"tools/list"}"#)
        XCTAssertNotNil(response["result"]?["tools"]?.arrayValue,
                        "一条坏消息不能让后面所有请求都废掉")
    }

    func testTopLevelValueMustBeAnObject() throws {
        let response = try respond(makeServer(), to: #""就一个字符串""#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testBatchRequestsAreRejectedWithAnExplanation() throws {
        // MCP 2025-06-18 已经移除批量请求。收到数组要明确说不支持，
        // 不能默默丢掉——默默丢掉的话客户端会一直等那条永远不来的响应。
        let response = try respond(makeServer(), to: #"[{"jsonrpc":"2.0","id":1,"method":"tools/list"}]"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("批量"))
    }

    func testBlankLinesAreIgnored() {
        let server = makeServer()
        XCTAssertNil(server.handle(line: ""))
        XCTAssertNil(server.handle(line: "   "))
    }

    func testTrailingCarriageReturnIsTolerated() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":4,"method":"ping"}"# + "\r")
        XCTAssertNotNil(response["result"])
    }

    // MARK: - 请求形状

    func testWrongJSONRPCVersionIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"1.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testMissingMethodIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":2}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testNonStringNonIntegerIDIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testIntegerIDComesBackAsAnIntegerNotAFloat() throws {
        let raw = try XCTUnwrap(makeServer().handle(line: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#))
        // 客户端把 id 反序列化成整数；回 7.0 会让它当场解析失败，
        // 症状是「服务器有响应，客户端说协议错误」，是最难查的一类故障。
        XCTAssertTrue(raw.contains("\"id\":7"), "id 必须原样回整数 7，实际响应：\(raw)")
        XCTAssertFalse(raw.contains("7.0"), "实际响应：\(raw)")
    }

    func testStringIDComesBackAsAString() throws {
        let raw = try XCTUnwrap(makeServer().handle(line: #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#))
        XCTAssertTrue(raw.contains(#""id":"abc""#), "实际响应：\(raw)")
    }

    // MARK: - 通知

    func testNotificationsNeverGetAResponse() {
        let server = makeServer()
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        // 不认识的通知也不能回。JSON-RPC 规定通知没有响应，
        // 回一条错误会让客户端收到对不上号的消息。
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#))
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"完全不认识的通知"}"#))
    }

    // MARK: - 握手

    func testRequestsBeforeInitializeAreRejectedWithInstructions() throws {
        let response = try respond(makeServer(initialized: false),
                                   to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("initialize"))
    }

    func testInitializeAdvertisesToolsCapabilityAndServerInfo() throws {
        let response = try respond(makeServer(initialized: false), to: Self.initializeLine)
        XCTAssertEqual(response["result"]?["protocolVersion"]?.stringValue, "2025-06-18")
        XCTAssertNotNil(response["result"]?["capabilities"]?["tools"]?.objectValue)
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"]?.stringValue, "ielts-speaking-mcp")
        XCTAssertFalse((response["result"]?["serverInfo"]?["version"]?.stringValue ?? "").isEmpty)
    }

    func testUnknownProtocolVersionFallsBackToOneWeActuallySupport() throws {
        let response = try respond(makeServer(initialized: false),
                                   to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01","capabilities":{}}}"#)
        let version = try XCTUnwrap(response["result"]?["protocolVersion"]?.stringValue)
        XCTAssertTrue(MCPServer.supportedProtocolVersions.contains(version))
        XCTAssertNotEqual(version, "1999-01-01", "不能鹦鹉学舌地回一个我们并不支持的版本")
    }

    // MARK: - tools/list 与 tools/call

    func testToolsListReturnsNameDescriptionAndSchemaForEveryTool() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try XCTUnwrap(response["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools.compactMap { $0["name"]?.stringValue }, ["echo", "explode"])
        for tool in tools {
            XCTAssertFalse((tool["description"]?.stringValue ?? "").isEmpty)
            XCTAssertEqual(tool["inputSchema"]?["type"]?.stringValue, "object")
        }
    }

    func testUnknownMethodIsMethodNotFoundAndNamesTheMethod() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32601)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("resources/list"))
    }

    func testToolsCallWithoutParamsIsInvalidParams() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testToolsCallWithoutNameIsInvalidParams() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"arguments":{}}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testUnknownToolNameIsInvalidParamsAndListsTheRealOnes() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
        let message = response["error"]?["message"]?.stringValue ?? ""
        XCTAssertTrue(message.contains("nope"))
        XCTAssertTrue(message.contains("echo"), "报错时要把真实存在的工具名列出来")
    }

    func testArgumentsMayBeOmitted() throws {
        // MCP 允许省略 arguments。省略时报错的话，所有无参工具都调不动。
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo"}}"#)
        XCTAssertEqual(response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue,
                       "(没有 message)")
        XCTAssertEqual(response["result"]?["isError"], JSONValue.bool(false))
    }

    func testArgumentsMustBeAnObjectWhenPresent() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo","arguments":[1,2]}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testToolResultIsWrappedAsMCPTextContent() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo","arguments":{"message":"你好"}}}"#)
        let content = try XCTUnwrap(response["result"]?["content"]?.arrayValue)
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"]?.stringValue, "text")
        XCTAssertEqual(content[0]["text"]?.stringValue, "你好")
    }

    func testToolFailureIsAResultWithIsErrorNotAProtocolError() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"explode","arguments":{}}}"#)
        XCTAssertNil(response["error"],
                     "工具自身失败必须走 result.isError；变成协议错误的话，模型看不到失败原因，也就无从自我纠正")
        XCTAssertEqual(response["result"]?["isError"], JSONValue.bool(true))
        let text = try XCTUnwrap(response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("假装炸了"), "原始错误信息不能被吞掉")
        XCTAssertTrue(text.contains("下一步"))
    }

    func testServerStillWorksAfterAToolThrows() throws {
        let server = makeServer()
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"explode","arguments":{}}}"#)
        let response = try respond(server, to: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        XCTAssertNotNil(response["result"])
    }
}
