import Foundation
import IELTSCoachCore
import XCTest

/// `scripts/install-codex-plugin.sh` 与 `codex/ielts-speaking-mcp.toml` 的测试。
///
/// **跑的是真实脚本，不是脚本逻辑的副本**——副本被改坏不会变红。这一点与
/// `SeedDemoDataScriptTests` / `IconPipelineTests` 的做法一致。
///
/// 为什么这个脚本值得被测试守着：它会往 `~/.codex/config.toml` 里写东西，
/// 而那是用户自己的配置文件，里面可能还配着别的 MCP server。
/// 计划（Phase 9 Task 12）只安排了人工跑一次「不写配置」那条路径；
/// 「加了 --write 会不会覆盖别人的段落」「备份到底有没有生成」这两件事
/// 一旦出错，代价是用户的配置文件，不该只在有人想起来的时候验。
///
/// **测试里绝不拿真实的 `$HOME` 当靶子。** 每个用例都把 `HOME` 指到临时目录，
/// 于是 `~/.codex/config.toml` 与 `~/.local/bin` 都落在临时目录里——
/// 脚本的安全闸失效时，被改坏的是哨兵文件，测试变红，用户的配置无恙。
///
/// **也绝不跑一次 release 编译。** 用 `IELTS_MCP_SOURCE_BIN` 指一个假的可执行文件
/// 顶替编译产物。真实编译产物能不能跑，由 `scripts/mcp-smoke.sh` 与 Task 13 的人工验收负责；
/// 这里验的是「装到哪、配置怎么给」，与编译无关。
final class InstallCodexPluginScriptTests: XCTestCase {

    // MARK: - 默认路径：只打印，不动用户的配置文件

    func testPrintsTheSnippetAndLeavesTheUserConfigUntouched() throws {
        let home = try FakeHome(config: FakeHome.foreignConfig)
        let run = try InstallCodexPluginScript.run(home: home)

        XCTAssertEqual(run.status, 0, "脚本非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        XCTAssertTrue(run.output.contains(InstallCodexPluginScript.sectionHeader),
                      "没有把要粘贴的段落打印出来。输出=\(run.output)")
        XCTAssertTrue(run.output.contains(home.installedBinary.path),
                      "打印出来的 command 必须是安装后的绝对路径。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("下一步"),
                      "输出里必须告诉用户下一步做什么。输出=\(run.output)")

        XCTAssertEqual(home.configContents(), FakeHome.foreignConfig,
                       "不带 --write 却改了用户的 ~/.codex/config.toml——这正是本任务明令禁止的事")
        XCTAssertEqual(home.backupFiles(), [], "不带 --write 时不该产生备份文件")

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: home.installedBinary.path),
                      "可执行文件没被装到 \(home.installedBinary.path)，或者没有执行权限")
    }

    // MARK: - --write：追加、备份，且不碰原有内容

    func testWriteAppendsTheSectionAndBacksUpTheOriginal() throws {
        let home = try FakeHome(config: FakeHome.foreignConfig)
        let run = try InstallCodexPluginScript.run(arguments: ["--write"], home: home)

        XCTAssertEqual(run.status, 0, "脚本非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        let updated = try XCTUnwrap(home.configContents())

        XCTAssertTrue(updated.hasPrefix(FakeHome.foreignConfig),
                      "原有内容被改动了。改后的文件=\(updated)")
        XCTAssertTrue(updated.split(separator: "\n", omittingEmptySubsequences: false)
                          .contains { $0 == InstallCodexPluginScript.sectionHeader[...] },
                      "追加的段落头没有独占一行——原文件末尾没有换行时会和上一行粘在一起，"
                      + "那样整个文件都不是合法 TOML。改后的文件=\(updated)")
        XCTAssertTrue(updated.contains("command = \"\(home.installedBinary.path)\""),
                      "追加进去的 command 不是安装后的绝对路径。改后的文件=\(updated)")

        let backups = home.backupFiles()
        XCTAssertEqual(backups.count, 1, "应当正好留下一个备份，实际=\(backups.map(\.lastPathComponent))")
        let backup = try XCTUnwrap(backups.first)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), FakeHome.foreignConfig,
                       "备份内容与原文件不一致，出事时救不回来")
        XCTAssertTrue(run.output.contains(backup.path),
                      "没有把备份路径打印出来，用户不知道去哪找。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("下一步"), "写完没说下一步做什么。输出=\(run.output)")
    }

    func testWriteCreatesTheConfigFileWhenThereIsNoneYet() throws {
        let home = try FakeHome(config: nil)
        let run = try InstallCodexPluginScript.run(arguments: ["--write"], home: home)

        XCTAssertEqual(run.status, 0, "脚本非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        let created = try XCTUnwrap(home.configContents(),
                                    "~/.codex 整个目录都不存在时，脚本应当把它和 config.toml 建出来")
        XCTAssertTrue(created.contains(InstallCodexPluginScript.sectionHeader),
                      "新建的配置文件里没有那一段。文件=\(created)")
    }

    // MARK: - --write：已经有同名段落时必须拒绝，且一个字都不许改

    func testWriteRefusesWhenTheSectionIsAlreadyThere() throws {
        let existing = """
        \(InstallCodexPluginScript.sectionHeader)
        command = "/somewhere/else/ielts-speaking-mcp"

        """
        let home = try FakeHome(config: existing)
        let run = try InstallCodexPluginScript.run(arguments: ["--write"], home: home)

        XCTAssertEqual(home.configContents(), existing,
                       "已经有同名段落了，脚本还是往里写——用户的 config.toml 会多出一个重复的 TOML 表，"
                       + "Codex 直接读不下去")
        XCTAssertEqual(home.backupFiles(), [], "什么都没改，却留了个备份文件下来")
        XCTAssertFalse(run.output.contains("已把配置追加"),
                       "没写却声称写了，正是铁律 7 禁止的静默失败。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("下一步"),
                      "拒绝的时候没说下一步做什么。输出=\(run.output)")
        XCTAssertTrue(run.output.contains(home.installedBinary.path),
                      "拒绝的时候要告诉用户那一段的 command 应该指向哪。输出=\(run.output)")
    }

    func testWriteIsNotBlockedByACommentThatMerelyMentionsTheSection() throws {
        // 一句提到段落名的中文注释不等于「已经配好了」。若把它也当成已存在，
        // 用户会永远被拒，而且拒绝理由是假的——他的配置里根本没有那一段。
        let existing = """
        # 之前看文档时抄的备注：\(InstallCodexPluginScript.sectionHeader) 那一段还没加

        """
        let home = try FakeHome(config: existing)
        let run = try InstallCodexPluginScript.run(arguments: ["--write"], home: home)

        XCTAssertEqual(run.status, 0, "脚本非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        let updated = try XCTUnwrap(home.configContents())
        XCTAssertTrue(updated.split(separator: "\n", omittingEmptySubsequences: false)
                          .contains { $0 == InstallCodexPluginScript.sectionHeader[...] },
                      "只是注释里提了一句段落名，脚本就当成已经配好了，什么也没写。文件=\(updated)")
    }

    // MARK: - 参数与前置条件：坏消息必须当场说清楚

    func testRejectsAnUnknownArgument() throws {
        let home = try FakeHome(config: FakeHome.foreignConfig)
        let run = try InstallCodexPluginScript.run(arguments: ["--wirte"], home: home)

        XCTAssertNotEqual(run.status, 0,
                          "参数敲错了却以 0 退出：用户以为写进去了，其实只是打印了一遍。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("--write"),
                      "报错里没有给出正确的参数写法。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("下一步"), "报错没说下一步做什么。输出=\(run.output)")
        XCTAssertEqual(home.configContents(), FakeHome.foreignConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.installedBinary.path),
                       "参数都没看懂就先把文件装进去了——校验要在动手之前")
    }

    func testFailsLoudlyWhenThereIsNothingToInstall() throws {
        let home = try FakeHome(config: FakeHome.foreignConfig)
        let missing = home.root.appending(path: "nowhere/ielts-speaking-mcp")
        let run = try InstallCodexPluginScript.run(arguments: [], home: home,
                                                   sourceBinary: missing)

        XCTAssertNotEqual(run.status, 0, "要装的文件根本不存在，脚本却以 0 退出。输出=\(run.output)")
        XCTAssertFalse(run.output.contains("✅"),
                       "装不成还打印成功标记。输出=\(run.output)")
        XCTAssertTrue(run.output.contains(missing.path),
                      "报错里没说是哪个路径找不到。输出=\(run.output)")
        XCTAssertTrue(run.output.contains("下一步"), "报错没说下一步做什么。输出=\(run.output)")
        XCTAssertEqual(home.configContents(), FakeHome.foreignConfig)
    }

    // MARK: - 给人抄的那份配置，必须和脚本写出来的一致

    func testDocumentedTomlAgreesWithWhatTheScriptWrites() throws {
        let document = try String(contentsOf: InstallCodexPluginScript.repositoryRoot
            .appending(path: "codex/ielts-speaking-mcp.toml"), encoding: .utf8)
        let activeLines = document.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }

        // 段落名：脚本打印/追加的那一行，和给人抄的这份文件必须逐字一致。
        // 两处只改一处（Task 13 核实完 Codex 的真实键名之后很可能要改），这条会红。
        let home = try FakeHome(config: nil)
        let printed = try InstallCodexPluginScript.run(home: home)
        let printedHeader = try XCTUnwrap(
            printed.output.split(separator: "\n").map(String.init)
                .first { $0.hasPrefix("[mcp_servers") },
            "脚本打印的内容里找不到段落头。输出=\(printed.output)")
        XCTAssertTrue(activeLines.contains(printedHeader),
                      "codex/ielts-speaking-mcp.toml 里的段落头与脚本写的对不上。"
                      + "脚本=\(printedHeader) 文件里的有效行=\(activeLines)")

        // command 必须是绝对路径。写成裸名字的话，Codex 起 MCP server 时不保证继承
        // 你 shell 里的 PATH，报错还只出现在 Codex 的日志里——这份文件的存在意义就是防这件事。
        let commandLine = try XCTUnwrap(activeLines.first { $0.hasPrefix("command") },
                                        "文件里没有 command 这一行。有效行=\(activeLines)")
        let commandValue = commandLine.split(separator: "\"").dropFirst().first.map(String.init) ?? ""
        XCTAssertTrue(commandValue.hasPrefix("/"),
                      "command 写的不是绝对路径：\(commandLine)")
        XCTAssertTrue(commandValue.hasSuffix("/ielts-speaking-mcp"),
                      "command 指的不是 ielts-speaking-mcp：\(commandLine)")
        XCTAssertTrue(activeLines.contains("args = []"),
                      "文件里没有 args = []。有效行=\(activeLines)")

        // 换数据目录那一段写的必须是可执行文件真正认的那个环境变量名。
        // 写错一个字母，用户按文件照抄之后会以为在拿临时目录做试验，实际动的是真实训练记录。
        XCTAssertTrue(document.contains(DataDirectory.environmentKey),
                      "文件里没有提到 \(DataDirectory.environmentKey)，"
                      + "而它是唯一能把数据目录指到别处的开关")
        XCTAssertTrue(document.contains(DataDirectory.folderName),
                      "文件里没说默认的数据目录叫什么（\(DataDirectory.folderName)）")
    }
}

// MARK: - 跑真实脚本的小工具

enum InstallCodexPluginScript {
    /// 脚本写进配置文件的段落头。测试与脚本各写一份，对不上就说明有一边改漏了。
    static let sectionHeader = "[mcp_servers.ielts_speaking]"

    struct Run {
        var status: Int32
        var stdout: String
        var stderr: String
        /// 断言一律看这个：错误走 stderr 还是 stdout 不该影响「用户到底看见了什么」。
        var output: String { stdout + stderr }
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachMCPTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
    }

    static var scriptURL: URL { repositoryRoot.appending(path: "scripts/install-codex-plugin.sh") }

    /// 直接执行脚本本身（不是 `bash 脚本`），这样「忘了 chmod +x」也会让测试变红。
    static func run(arguments: [String] = [], home: FakeHome,
                    sourceBinary: URL? = nil) throws -> Run {
        let source = try sourceBinary ?? home.makeStubBinary()

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.currentDirectoryURL = home.root

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.root.path
        environment["IELTS_MCP_SOURCE_BIN"] = source.path
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Run(status: -1, stdout: "",
                       stderr: "启动 \(scriptURL.path) 失败：\(error)。"
                       + "下一步：确认脚本存在且有执行权限（chmod +x scripts/install-codex-plugin.sh）。")
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus,
                   stdout: String(decoding: outData, as: UTF8.self),
                   stderr: String(decoding: errData, as: UTF8.self))
    }
}

/// 一个假的家目录：`~/.codex/config.toml` 与 `~/.local/bin` 都落在这里。
struct FakeHome {
    /// 「用户原本就配着别的 MCP server」——脚本一个字都不许动它。
    static let foreignConfig = """
    # 我自己的 Codex 配置
    [mcp_servers.some_other_server]
    command = "/usr/local/bin/other-mcp"
    """   // 刻意不以换行结尾：追加时前面不补一个换行的话，两段会粘成一行

    let root: URL

    var configFile: URL { root.appending(path: ".codex/config.toml") }
    var installedBinary: URL { root.appending(path: ".local/bin/ielts-speaking-mcp") }

    init(config: String?) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "install-codex-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let config {
            try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try config.write(to: configFile, atomically: true, encoding: .utf8)
        }
    }

    func configContents() -> String? {
        try? String(contentsOf: configFile, encoding: .utf8)
    }

    func backupFiles() -> [URL] {
        let directory = configFile.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("config.toml.bak") }.sorted()
            .map { directory.appending(path: $0) }
    }

    /// 顶替 release 编译产物的假可执行文件。**它一行都不碰 ChatGPT，也不做任何事。**
    func makeStubBinary() throws -> URL {
        let url = root.appending(path: "stub/ielts-speaking-mcp")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
