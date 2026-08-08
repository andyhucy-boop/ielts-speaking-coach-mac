import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class ToolCatalogTests: XCTestCase {
    private var directory: DataDirectory!
    private var tools: [MCPTool]!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        tools = ToolCatalog.tools(environment: makeEnvironment(directory: directory,
                                                               opener: FakeDashboardOpener()))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    func testExposesExactlyTheSevenToolsNamedInSpec() {
        // spec 第 4.4 节逐字列的就是这七个，顺序也照抄。
        // 多一个、少一个、改一个字，都是把上游协议改掉了。
        XCTAssertEqual(tools.map(\.name), [
            "initialize_ielts_workspace",
            "open_dashboard",
            "set_training_selection",
            "get_training_context",
            "save_session_review",
            "list_practice_history",
            "get_dashboard_data"
        ])
    }

    func testEveryToolHasAChineseDescriptionAndAnObjectSchema() {
        for tool in tools {
            let hasChinese = tool.description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            XCTAssertTrue(hasChinese, "\(tool.name) 的说明必须是中文——面向用户的文案一律中文")
            XCTAssertEqual(tool.inputSchema["type"]?.stringValue, "object",
                           "\(tool.name) 的 inputSchema 必须是 object")
            XCTAssertNotNil(tool.inputSchema["properties"]?.objectValue, "\(tool.name) 缺 properties")
        }
    }

    func testRequiredParametersAreDeclaredForTheToolsThatHaveThem() throws {
        // 先 unwrap 出工具再断言。原来写成 `tool?.inputSchema[...] ?? []`，
        // 工具压根不在目录里时也返回 []，于是「required 是空」这条断言永远成立。
        func required(_ name: String) throws -> [String] {
            let tool = try XCTUnwrap(tools.first { $0.name == name }, "工具目录里没有 \(name)")
            return (tool.inputSchema["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        }
        // schema 里不写 required，模型就会以为参数可省，然后收到一条本可以避免的错误。
        XCTAssertEqual(try required("set_training_selection"), ["questionId"])
        XCTAssertEqual(try required("save_session_review"), ["reviewText"])
        let dashboard = try XCTUnwrap(tools.first { $0.name == "get_dashboard_data" })
        XCTAssertNil(dashboard.inputSchema["required"],
                     "这个工具本来就不吃参数，schema 里不该出现 required 键")
    }

    func testToolNamesAreUnique() {
        XCTAssertEqual(Set(tools.map(\.name)).count, tools.count,
                       "重名的工具后一个永远调不到——tools.first(where:) 只会命中前一个")
    }
}
