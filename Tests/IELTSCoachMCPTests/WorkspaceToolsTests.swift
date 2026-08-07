import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class WorkspaceToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        opener = FakeDashboardOpener()
        harness = ServerHarness(environment: makeEnvironment(directory: directory, opener: opener))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - initialize_ielts_workspace

    func testCreatesTheDataDirectoryAndStateFile() throws {
        // 刻意没有预先 createIfNeeded：这个工具的职责就是「让工作区存在」。
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.stateFile.path))

        let payload = try harness.callToolJSON("initialize_ielts_workspace")

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path))
        XCTAssertEqual(payload["createdStateFile"], JSONValue.bool(true))
        XCTAssertEqual(payload["dataDirectory"]?.stringValue, directory.root.path)
        XCTAssertEqual(payload["schemaVersion"]?.intValue, 3)
        XCTAssertEqual(payload["questionCount"]?.intValue, 0)
    }

    func testSecondCallReportsThatItDidNotCreateAnything() throws {
        _ = try harness.callToolJSON("initialize_ielts_workspace")
        let payload = try harness.callToolJSON("initialize_ielts_workspace")
        XCTAssertEqual(payload["createdStateFile"], JSONValue.bool(false),
                       "第二次调用不能还说自己新建了文件——用户会以为记录被重置了")
    }

    func testWritesDisplayNameOnlyWhenThereIsNoneYet() throws {
        _ = try harness.callToolJSON("initialize_ielts_workspace", ["displayName": .string("Andy")])
        XCTAssertEqual(try StateStore(directory: directory).load().learner.displayName, "Andy")

        _ = try harness.callToolJSON("initialize_ielts_workspace", ["displayName": .string("别人")])
        XCTAssertEqual(try StateStore(directory: directory).load().learner.displayName, "Andy",
                       "已有昵称不能被后来的调用覆盖")
    }

    func testEmptyBankNoteTellsTheUserWhatToDoNext() throws {
        let payload = try harness.callToolJSON("initialize_ielts_workspace")
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("下一步"), "题库为空时必须给出路，而不是只报一个 0")
    }

    // MARK: - open_dashboard

    func testOpensTheDashboardURLByDefault() throws {
        let payload = try harness.callToolJSON("open_dashboard")
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["ieltscoach://dashboard"])
        XCTAssertEqual(payload["opened"]?.stringValue, "ieltscoach://dashboard")
    }

    func testOpensTheRequestedSection() throws {
        _ = try harness.callToolJSON("open_dashboard", ["section": .string("history")])
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["ieltscoach://history"])
    }

    func testUnknownSectionIsRejectedWithoutOpeningAnything() throws {
        let result = try harness.callTool("open_dashboard", ["section": .string("nope")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("dashboard"), "报错时要把可用的页面列出来")
        XCTAssertTrue(result.text.contains("下一步"))
        XCTAssertTrue(opener.opened.isEmpty, "参数不合法时一个窗口都不该被打开")
    }

    func testOpenFailureIsExplainedInPlainChinese() throws {
        opener.errorToThrow = DashboardOpenError(message:
            "系统没能打开 ieltscoach://dashboard。下一步：先手动打开一次 App。")
        let result = try harness.callTool("open_dashboard")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步：先手动打开一次 App。"),
                      "唤起失败的原文必须原样透出，不能被包成一句笼统的「执行失败」")
    }

    // MARK: - 目录

    func testCatalogOnlyContainsNamesFromSpec() {
        // spec 4.4 钉死了 7 个名字。这条先兜住「不许自己发明工具名」，
        // Task 9 再收紧成「恰好这 7 个、顺序也一致」。
        let specNames: Set<String> = [
            "initialize_ielts_workspace", "open_dashboard", "set_training_selection",
            "get_training_context", "save_session_review", "list_practice_history",
            "get_dashboard_data"
        ]
        let names = ToolCatalog.tools(environment:
            makeEnvironment(directory: directory, opener: opener)).map(\.name)
        XCTAssertEqual(Set(names).subtracting(specNames), [], "出现了 spec 4.4 之外的工具名")
        XCTAssertTrue(names.contains("initialize_ielts_workspace"))
        XCTAssertTrue(names.contains("open_dashboard"))
    }
}
