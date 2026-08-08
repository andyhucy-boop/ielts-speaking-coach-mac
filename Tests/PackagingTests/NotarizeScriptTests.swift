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
    ///
    /// `fakeToolsAt` 会被塞到 PATH 最前面，用来把 codesign/security/xcrun/swift 这些
    /// 外部命令换成假的。--execute 越过前置条件之后的那段路径只能这么测：
    /// 真跑它要么需要一张 Developer ID 证书（本期没有），要么会真的编译、真的提交公证。
    private func run(_ script: String,
                     _ arguments: [String],
                     environment extra: [String: String] = [:],
                     fakeToolsAt fakeBin: URL? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.repositoryRoot.appending(path: script).path] + arguments
        process.currentDirectoryURL = Self.repositoryRoot
        let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        var environment = ["PATH": fakeBin.map { "\($0.path):\(systemPath)" } ?? systemPath,
                           "HOME": NSHomeDirectory()]
        environment.merge(extra) { _, new in new }
        process.environment = environment
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

    // MARK: - 切片

    /// 取出 [起始行, 结束行) 之间的那一段。找不到就返回 nil，让调用方报出完整输出。
    private func section(of output: String,
                         from startMarker: String,
                         to endMarker: String) -> [String]? {
        let lines = output.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains(startMarker) }),
              let end = lines[start...].firstIndex(where: { $0.contains(endMarker) }),
              start < end
        else { return nil }
        return Array(lines[(start + 1)..<end])
    }

    // MARK: - dry-run

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

    func testDryRunSpellsOutEveryStepInTheOrderTheyMustBeRun() throws {
        // 这几步就是「将来怎么做」的全部内容。少一步，将来那天就要现查文档。
        // 顺序也在断言之内：更新签名基线必须排在重签之前——反过来的话，
        // build-app.sh 的基线闸门会把重签那一步当场 exit 1 挡掉，整个流程走不下去。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        guard let steps = section(of: result.output, from: "公证流程（", to: "──── 完成之后")
        else {
            return XCTFail("找不到「公证流程」那一段，或它没有收尾：\n\(result.output)")
        }
        let procedure = steps.joined(separator: "\n")

        var previousIndex: String.Index?
        var previousNeedle = ""
        for needle in ["expected-designated-requirement.txt",   // 1. 先换基线
                       "codesign", "--options runtime", "--entitlements",  // 2. 重签
                       "ditto -c -k",                            // 3. 压缩
                       "notarytool submit",                      // 4. 提交公证
                       "stapler staple",                         // 5. 钉票据
                       "spctl"] {                                // 6. 系统判定
            guard let range = procedure.range(of: needle) else {
                return XCTFail("公证流程里缺了「\(needle)」：\n\(procedure)")
            }
            if let previousIndex {
                XCTAssertLessThan(previousIndex, range.lowerBound,
                                  "「\(previousNeedle)」必须排在「\(needle)」前面：\n\(procedure)")
            }
            previousIndex = range.lowerBound
            previousNeedle = needle
        }
    }

    func testDryRunWarnsUpFrontThatSwitchingCertificateBreaksTheAccessibilityGrant() throws {
        // 这是换证书那天最容易被忘、后果又最烦人的一件事，
        // 计划要求「脚本必须在动手前把这段话打出来」——所以位置也在断言之内。
        //
        // 只断言「输出里出现过『辅助功能』」是没用的：收尾提示里也有这四个字，
        // 把整段警告删掉照样绿。这里认的是这段警告独有的句子。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        let output = result.output

        for sentence in ["换成 Developer ID 证书会改变签名的「指定要求」",
                         "系统会把重签后的 App 当成另一个程序",
                         "本机已授予的辅助功能授权会失效",
                         "只发生一次"] {
            XCTAssertTrue(output.contains(sentence),
                          "换证书的那段警告缺了「\(sentence)」：\n\(output)")
        }

        guard let warning = output.range(of: "换成 Developer ID 证书会改变签名的「指定要求」"),
              let preconditions = output.range(of: "前置条件（")
        else { return XCTFail("输出结构不对：\n\(output)") }
        XCTAssertLessThan(warning.lowerBound, preconditions.lowerBound,
                          "这段警告必须在动手前就打出来，不能排在前置条件后面：\n\(output)")
    }

    func testEveryPreconditionSaysWhatHappenedAndWhatToDoNext() throws {
        // 这一条守的是 5 个 check 调用和 check() 本身的输出，不是别处那些顺带出现的
        // 「下一步」。判据：把 check() 换成只置 MISSING、一个字都不打印，它必须变红。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        guard let block = section(of: result.output, from: "前置条件（", to: "公证流程（") else {
            return XCTFail("找不到前置条件那一段：\n\(result.output)")
        }

        func isItemHeader(_ line: String) -> Bool {
            line.hasPrefix("✅") || line.hasPrefix("⚠️")
        }
        let headerIndexes = block.indices.filter { isItemHeader(block[$0]) }

        // 每一条都要在，缺一条就意味着将来那天会撞上一个没人提醒过的前置条件。
        for item in ["IELTS_DEVELOPER_ID",          // 证书名
                     "钥匙串",                        // 证书真的能用来签名
                     "notarytool",                  // 工具在不在
                     "IELTS_NOTARY_PROFILE",        // 公证凭据
                     ".app"] {                      // 有没有打好的包
            XCTAssertTrue(headerIndexes.contains { block[$0].contains(item) },
                          "前置条件里没有「\(item)」这一条：\n\(block.joined(separator: "\n"))")
        }
        XCTAssertEqual(headerIndexes.count, 5,
                       "前置条件应当正好 5 条：\n\(block.joined(separator: "\n"))")

        // 这台机器上没有 Developer ID，前两条必然是 ⚠️——所以下面这段一定会被执行到。
        let missing = headerIndexes.filter { block[$0].hasPrefix("⚠️") }
        XCTAssertGreaterThanOrEqual(missing.count, 2,
                                    "没配证书的机器上，证书那两条必须报 ⚠️：\n\(block.joined(separator: "\n"))")

        for index in missing {
            let next = headerIndexes.first { $0 > index } ?? block.count
            let detail = block[(index + 1)..<next].joined(separator: "\n")
            XCTAssertTrue(detail.contains("发生了什么："),
                          "「\(block[index])」没说发生了什么：\n\(detail)")
            XCTAssertTrue(detail.contains("下一步："),
                          "「\(block[index])」没说下一步做什么：\n\(detail)")
        }
    }

    // MARK: - --execute

    func testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping() throws {
        // 静默跳过是本项目最危险的失败形态：以为公证了，其实什么都没发生。
        let result = try run("scripts/notarize.sh", ["--execute"])
        XCTAssertNotEqual(result.status, 0,
                          "没有凭据却退出 0，等于静默跳过公证：\n\(result.output)")
        XCTAssertTrue(result.output.contains("不执行公证"),
                      "要说清它没做什么：\n\(result.output)")
    }

    /// 假的 Developer ID 工具链。
    /// - Parameter designatedRequirement: 假 codesign 在 `-d -r-` 时吐出的「指定要求」。
    private func makeFakeToolchain(designatedRequirement: String) throws -> (bin: URL, log: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "notarize-fakes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let log = directory.appending(path: "calls.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)

        func install(_ name: String, _ body: String) throws {
            let path = directory.appending(path: name)
            try("#!/bin/bash\nprintf '%s %s\\n' \"\(name)\" \"$*\" >> \"$FAKE_LOG\"\n" + body)
                .write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: path.path)
        }

        // 签名时静默成功；被问「指定要求」时吐出预设的那一行。
        try install("codesign", """
        for argument in "$@"; do
            if [[ "$argument" == "-r-" ]]; then
                printf 'Executable=/fake/probe.app/Contents/MacOS/IELTSCoachApp\\n'
                printf '%s\\n' "$FAKE_DESIGNATED"
                exit 0
            fi
        done
        exit 0
        """)
        try install("security", """
        printf '  1) 0000000000000000000000000000000000000000 "%s"\\n' "$FAKE_IDENTITY"
        printf '     1 valid identities found\\n'
        exit 0
        """)
        try install("xcrun", """
        if [[ "${1:-}" == "--find" ]]; then printf '/fake/bin/%s\\n' "${2:-}"; exit 0; fi
        printf '假 xcrun 被调用了：测试里不许真的提交公证\\n'
        exit 96
        """)
        // 这几个是护栏：万一将来有人把闸门去掉，测试也不该真的编译、真的压包、真的判定。
        try install("swift", "printf '假 swift 被调用了：走到真正的编译这一步了\\n'\nexit 97")
        try install("ditto", "printf '假 ditto 被调用了\\n'\nexit 95")
        try install("spctl", "printf '假 spctl 被调用了\\n'\nexit 94")

        return (directory, log)
    }

    private static let fakeIdentity = "Developer ID Application: 测试用 (TEAM123456)"

    /// `--execute` 需要「已有打好的 .app」。开发机上通常已经有一个，那就用它；
    /// 没有就临时造一个空壳，用完删掉——绝不动别人真打出来的那个。
    private func ensureBuiltAppExists() throws -> URL {
        let app = Self.repositoryRoot.appending(path: ".build/IELTS Speaking Coach.app")
        if !FileManager.default.fileExists(atPath: app.path) {
            try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"),
                                                    withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        }
        return app
    }

    private func recordedBaseline() throws -> String {
        try String(contentsOf: Self.repositoryRoot
            .appending(path: "packaging/expected-designated-requirement.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testExecuteRefusesToResignBeforeTheSignatureBaselineIsRotated() throws {
        // Task 9 的立论是「把将来要怎么做写成可以直接跑的东西」。可执行的那一半
        // 一旦顺序是反的就永远跑不通：build-app.sh 会拿签名的「指定要求」跟
        // packaging/expected-designated-requirement.txt 逐字比对，换证书必然让它变，
        // 于是重签那一步被 exit 1 挡掉，后面几步永远到不了。
        // 所以脚本必须在动手之前自己发现这件事，并且把要写进基线的那一行算给你。
        _ = try ensureBuiltAppExists()
        let newRequirement = "designated => identifier \"com.ielts.speakingcoach\" and anchor apple generic and certificate leaf[subject.OU] = \"TEAM123456\""
        let fake = try makeFakeToolchain(designatedRequirement: newRequirement)

        let result = try run("scripts/notarize.sh", ["--execute"],
                             environment: ["IELTS_DEVELOPER_ID": Self.fakeIdentity,
                                           "IELTS_NOTARY_PROFILE": "ielts-notary",
                                           "FAKE_LOG": fake.log.path,
                                           "FAKE_DESIGNATED": newRequirement,
                                           "FAKE_IDENTITY": Self.fakeIdentity],
                             fakeToolsAt: fake.bin)

        XCTAssertNotEqual(result.status, 0,
                          "基线还指向旧证书却继续往下走，等于把必然失败的一步留给用户撞：\n\(result.output)")
        XCTAssertTrue(result.output.contains(try recordedBaseline()),
                      "没把现在的基线打出来，用户不知道差在哪：\n\(result.output)")
        XCTAssertTrue(result.output.contains(newRequirement),
                      "没把换证书之后的新值算出来打给用户：\n\(result.output)")
        XCTAssertTrue(result.output.contains("packaging/expected-designated-requirement.txt"),
                      "没说要改哪个文件：\n\(result.output)")
        XCTAssertTrue(result.output.contains("下一步"),
                      "只说了失败没说怎么办：\n\(result.output)")
        XCTAssertTrue(result.output.contains("辅助功能"),
                      "没提醒辅助功能授权要重做一次：\n\(result.output)")

        // 最要紧的一条：拦下的时候，一件事都不许已经做过。
        let calls = try String(contentsOf: fake.log, encoding: .utf8)
        XCTAssertFalse(calls.contains("swift "),
                       "已经走到 build-app.sh 的编译了，说明闸门没拦住：\n\(calls)")
        XCTAssertFalse(calls.contains("ditto "), "已经压包了：\n\(calls)")
        XCTAssertFalse(calls.contains("notarytool submit"), "已经提交公证了：\n\(calls)")
    }

    func testExecuteProceedsOnceTheBaselineAlreadyMatchesTheNewCertificate() throws {
        // 上一条只证明它会拦。这一条证明它拦的是「基线不一致」而不是「一律拦」——
        // 少了它，把闸门写成无条件 exit 1 也能全绿。
        _ = try ensureBuiltAppExists()
        let baseline = try recordedBaseline()
        let fake = try makeFakeToolchain(designatedRequirement: baseline)

        let result = try run("scripts/notarize.sh", ["--execute"],
                             environment: ["IELTS_DEVELOPER_ID": Self.fakeIdentity,
                                           "IELTS_NOTARY_PROFILE": "ielts-notary",
                                           "FAKE_LOG": fake.log.path,
                                           "FAKE_DESIGNATED": baseline,
                                           "FAKE_IDENTITY": Self.fakeIdentity],
                             fakeToolsAt: fake.bin)

        XCTAssertFalse(result.output.contains("先更新签名基线"),
                       "基线明明一致却被拦下了：\n\(result.output)")
        let calls = try String(contentsOf: fake.log, encoding: .utf8)
        XCTAssertTrue(calls.contains("swift "),
                      "基线一致时应当继续往下走到重签这一步：\n\(result.output)\n---\n\(calls)")
        // 假 swift 故意退非零：build-app.sh 失败必须原样传上来，不许被吞掉当成公证成功。
        XCTAssertNotEqual(result.status, 0,
                          "重签失败却退出 0，等于静默跳过公证：\n\(result.output)")
        XCTAssertFalse(result.output.contains("✅ 公证完成"),
                       "重签都没成就报公证完成：\n\(result.output)")
    }

    // MARK: - 参数

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
                       "--help 把脚本里的变量赋值也打出来了，范围错位了：\n\(result.output)")
    }

    func testUnknownArgumentIsRejectedRatherThanIgnored() throws {
        // 参数打错被忽略，用户会以为自己 --execute 了。
        let result = try run("scripts/notarize.sh", ["--yolo"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("下一步"))
    }
}
