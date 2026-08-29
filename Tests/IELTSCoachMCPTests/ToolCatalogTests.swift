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

    /// spec 第 4.4 节逐字列的那七个，**一个都不许少，相对顺序也不许乱**。
    /// 少一个、改一个字，都是把上游协议改掉了。
    static let specTools = [
        "initialize_ielts_workspace",
        "open_dashboard",
        "set_training_selection",
        "get_training_context",
        "save_session_review",
        "list_practice_history",
        "get_dashboard_data"
    ]

    func testStillExposesTheSevenSpecToolsInTheirSpecOrder() {
        XCTAssertEqual(tools.map(\.name).filter(Self.specTools.contains), Self.specTools)
    }

    /// **spec 之外的工具必须是一件明确决定过的事，不能是顺手加的。**
    ///
    /// 这条从前写的是「恰好这七个」。放宽成「七个都在 + 额外的逐个点名」，
    /// 是因为 spec 4.4 那张表本身就比上游少：上游的 `mcp/server.mjs` 有
    /// `list_question_bank`，而本项目当初没移植——后果是这个服务**一个题号都吐不出来**，
    /// `set_training_selection` 的 questionId 又是必填，
    /// 于是模型只能反过来叫用户打开 App 自己抄一串题号过来。
    ///
    /// 加进来是**向上游靠拢**，不是自己发明协议。名单写死在这里，
    /// 下一个人再加一个就会当场变红、必须在这里说明理由。
    func testAnyToolBeyondTheSpecIsOneWeDeliberatelyAdded() {
        let extras = tools.map(\.name).filter { !Self.specTools.contains($0) }
        XCTAssertEqual(extras, ["list_question_bank"],
                       "出现了没记在案的工具：\(extras)。"
                           + "下一步：要么去掉它，要么在这条测试里写清为什么加。")
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
