import XCTest

/// 守打包脚本的契约。不依赖任何产品代码。
final class NotarizeScriptTests: XCTestCase {

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)     // Tests/PackagingTests/NotarizeScriptTests.swift
            .deletingLastPathComponent()     // Tests/PackagingTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // 仓库根
    }

    private struct Result { let status: Int32; let output: String }

    /// 用干净的环境跑脚本。
    /// 不继承开发机上可能已经设好的 IELTS_* 变量——否则这些测试在
    /// 「配好了证书的机器」和「没配的机器」上会得出不同结论，那种测试等于没有。
    private func run(_ script: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.repositoryRoot.appending(path: script).path] + arguments
        process.currentDirectoryURL = Self.repositoryRoot
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // 必须先读完再 wait，否则管道写满会死锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(data: data, encoding: .utf8) ?? "")
    }

    func testDryRunSucceedsWithoutAnyDeveloperIDAtAll() throws {
        // 本期不买 Developer ID。dry-run 必须在这台什么都没配的机器上跑得通，
        // 否则这个「预留」就是一段没人验证过的死文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertEqual(result.status, 0, "dry-run 应该退出 0：\n\(result.output)")
    }

    func testDefaultModeIsDryRunSoItNeverDoesAnythingByAccident() throws {
        let result = try run("scripts/notarize.sh", [])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("一条都没有执行"),
                      "不带参数时必须是 dry-run，且要说清什么都没做：\n\(result.output)")
    }

    func testDryRunSpellsOutEveryStepOfTheProcedure() throws {
        // 这五步就是「将来怎么做」的全部内容。少一步，将来那天就要现查文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        for needle in ["codesign", "--options runtime", "--entitlements",
                       "ditto -c -k", "notarytool submit", "stapler staple", "spctl"] {
            XCTAssertTrue(result.output.contains(needle),
                          "公证流程里缺了「\(needle)」：\n\(result.output)")
        }
    }

    func testDryRunWarnsThatSwitchingCertificateBreaksTheAccessibilityGrant() throws {
        // 这是换证书那天最容易被忘、后果又最烦人的一件事。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("辅助功能"),
                      "没警告辅助功能授权会失效：\n\(result.output)")
        XCTAssertTrue(result.output.contains("expected-designated-requirement.txt"),
                      "没提醒要同步更新签名基线，那会让 build-app.sh 从此一直报错：\n\(result.output)")
    }

    func testEveryMissingPreconditionComesWithANextStep() throws {
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("下一步"),
                      "缺东西时必须说下一步做什么：\n\(result.output)")
        XCTAssertTrue(result.output.contains("Developer ID"),
                      "至少要点名缺的是 Developer ID：\n\(result.output)")
    }

    func testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping() throws {
        // 静默跳过是本项目最危险的失败形态：以为公证了，其实什么都没发生。
        let result = try run("scripts/notarize.sh", ["--execute"])
        XCTAssertNotEqual(result.status, 0,
                          "没有凭据却退出 0，等于静默跳过公证：\n\(result.output)")
        XCTAssertTrue(result.output.contains("不执行公证"),
                      "要说清它没做什么：\n\(result.output)")
    }

    /// 计划之外补的一条（见任务报告）。计划里 --help 用的是 `sed -n '3,20p'`，
    /// 那个行号范围会把 APP_NAME/BUNDLE_ID/ROOT/APP/ZIP/ENTITLEMENTS 六行 shell 赋值
    /// 一起打进帮助里。帮助是给人看的，混进代码就不是帮助了；
    /// 而且行号范围这种东西一改脚本就会悄悄错位，必须有测试钉住。
    func testHelpPrintsTheUsageWithoutLeakingShellCode() throws {
        let result = try run("scripts/notarize.sh", ["--help"])
        XCTAssertEqual(result.status, 0, "--help 应该退出 0：\n\(result.output)")
        XCTAssertTrue(result.output.contains("./scripts/notarize.sh --execute"),
                      "--help 没写清怎么真的执行公证：\n\(result.output)")
        XCTAssertTrue(result.output.contains("本期不购买 Developer ID"),
                      "--help 没说清本期这个脚本处于什么状态：\n\(result.output)")
        XCTAssertFalse(result.output.contains("APP_NAME="),
                       "--help 把脚本里的变量赋值也打出来了，行号范围错位了：\n\(result.output)")
    }

    func testUnknownArgumentIsRejectedRatherThanIgnored() throws {
        // 参数打错被忽略，用户会以为自己 --execute 了。
        let result = try run("scripts/notarize.sh", ["--yolo"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("下一步"))
    }
}
