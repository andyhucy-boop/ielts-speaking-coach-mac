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

    // 下面两条是配对的：note 有两条分支，各测一条。
    // 只断言「下一步」是不够的——两条分支都含这三个字，那样的断言对分支零约束力。

    func testEmptyBankNoteSendsTheUserToImportQuestions() throws {
        let payload = try harness.callToolJSON("initialize_ielts_workspace")

        XCTAssertEqual(payload["questionCount"]?.intValue, 0, "前提没成立：这条测的是空题库分支")
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("题库还是空的"), "题库为空时得先说清现状，不能只报一个 0：\(note)")
        XCTAssertTrue(note.contains("下一步"), "题库为空时必须给出路：\(note)")
        XCTAssertTrue(note.contains("导入"), "空题库的出路是导入题库，note 里必须写出来：\(note)")
        XCTAssertFalse(note.contains("set_training_selection"),
                       "题库为 0 时把用户指去选题，他只会撞上一个空列表：\(note)")
    }

    func testNonEmptyBankNoteSendsTheUserToSelectAQuestion() throws {
        try directory.createIfNeeded()
        try StateStore(directory: directory).mutate { state in
            state.questions.append(Question(id: "q1", part: 1, topic: "Home", prompt: "Where do you live?"))
        }

        let payload = try harness.callToolJSON("initialize_ielts_workspace")

        XCTAssertEqual(payload["questionCount"]?.intValue, 1, "前提没成立：这条测的是题库非空分支")
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("set_training_selection"),
                      "题库里已经有题了，下一步就该是选题：\(note)")
        XCTAssertTrue(note.contains("下一步"), "有题库也要说清下一步：\(note)")
        XCTAssertFalse(note.contains("题库还是空的"),
                       "题库不空却说空，用户会跑去重新导入一遍：\(note)")
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
