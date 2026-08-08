import Foundation
import XCTest

final class PackagingContractTests: XCTestCase {

    private var root: URL { NotarizeScriptTests.repositoryRoot }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    /// 去掉 Swift 源码里的注释，字符串字面量原样保留。
    ///
    /// `text(at:)` 读的是原文。不先去注释，文件里随便一行
    /// `// 举例：version: "1.0.0"` 就足以让下面那条版本一致性断言绿着通过——
    /// 而它本该盯住的是 `Changelog.releases` 里真实的那一条。
    private func strippingSwiftComments(_ source: String,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) -> String {
        XCTAssertFalse(source.contains("\"\"\""),
                       "这个扫描器不认多行字符串字面量（\"\"\"），再用下去它可能把注释当成字符串留下来，"
                       + "版本一致性那条断言就又变成摆设了。"
                       + "下一步：要么别在这个文件里用多行字符串，要么先把扫描器补上这一种再改源码。",
                       file: file, line: line)

        var output = ""
        let characters = Array(source)
        var index = 0
        var blockCommentDepth = 0        // Swift 的块注释可以嵌套
        var insideStringLiteral = false

        func character(at offset: Int) -> Character? {
            let position = index + offset
            return position < characters.count ? characters[position] : nil
        }

        while index < characters.count {
            let current = characters[index]

            if blockCommentDepth > 0 {
                if current == "/", character(at: 1) == "*" { blockCommentDepth += 1; index += 2; continue }
                if current == "*", character(at: 1) == "/" { blockCommentDepth -= 1; index += 2; continue }
                index += 1
                continue
            }

            if insideStringLiteral {
                if current == "\\" {                     // 转义序列连同被转义的字符一起照抄
                    output.append(current)
                    if let escaped = character(at: 1) { output.append(escaped) }
                    index += 2
                    continue
                }
                if current == "\"" { insideStringLiteral = false }
                output.append(current)
                index += 1
                continue
            }

            if current == "/", character(at: 1) == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if current == "/", character(at: 1) == "*" { blockCommentDepth = 1; index += 2; continue }
            if current == "\"" { insideStringLiteral = true }
            output.append(current)
            index += 1
        }
        return output
    }

    func testAllPackagingScriptsAreExecutable() {
        for script in ["build-app.sh", "verify-signature-stability.sh",
                       "package-app.sh", "notarize.sh", "make-icon.sh",
                       "verify-portability.sh"] {
            let path = root.appending(path: "scripts/\(script)").path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path),
                          "scripts/\(script) 没有可执行位——别人 clone 下来会直接跑不了")
        }
    }

    func testEntitlementsContainTheMicrophoneAndNothingElseUnjustified() throws {
        let entitlements = try text(at: "packaging/IELTSCoach.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"),
                      "缺了麦克风 entitlement，Hardened Runtime 下录音会被系统直接拒掉")

        // 下面这几条是「Hardened Runtime 报错时最容易被顺手粘上来」的。
        // 每一条都会实打实削弱 Hardened Runtime，而本项目一条都不需要
        // （实测 otool -L 显示只链接系统库；沙盒会让辅助功能驱动整个失效）。
        for forbidden in ["com.apple.security.app-sandbox",
                          "com.apple.security.cs.disable-library-validation",
                          "com.apple.security.cs.allow-unsigned-executable-memory",
                          "com.apple.security.cs.disable-executable-page-protection",
                          "com.apple.security.cs.allow-dyld-environment-variables"] {
            XCTAssertFalse(entitlements.contains(forbidden),
                           "多了一条不该有的 entitlement：\(forbidden)。"
                           + "若它真的必要，先在计划里写明为什么，再改这条测试。")
        }
    }

    func testDesignatedRequirementBaselineIsRecordedAndNotAdHoc() throws {
        let baseline = try text(at: "packaging/expected-designated-requirement.txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(baseline.hasPrefix("designated =>"),
                      "基线文件格式不对，应当就是 codesign -d -r- 输出的那一行：\(baseline)")
        XCTAssertTrue(baseline.contains("identifier \"com.ielts.speakingcoach\""),
                      "基线里的 bundle id 变了。辅助功能授权绑的就是它，任何阶段都不得更改。")
        XCTAssertTrue(baseline.contains("certificate leaf"),
                      "基线里没有证书条件，说明用的不是固定证书。")
        XCTAssertFalse(baseline.lowercased().contains("cdhash"),
                       "基线是 cdhash 形式，说明用了 ad-hoc 签名——"
                       + "cdhash 每次编译都变，用户的辅助功能授权会反复失效。")
    }

    func testProjectStillHasNoThirdPartyDependencies() throws {
        // 关于页的致谢里写着「第三方依赖：没有」。加了依赖却不改那句话，
        // 就变成了一句假话，而且没人会注意到。
        let manifest = try text(at: "Package.swift")
        XCTAssertFalse(manifest.contains(".package("),
                       "工程新增了第三方依赖。下一步：要么撤掉它，"
                       + "要么把它加进 AboutViewModel.acknowledgements 并改掉「没有第三方依赖」那句话。")
    }

    func testChangelogNewestVersionMatchesWhatTheBuildScriptStamps() throws {
        // 关于页显示 1.0.1、更新记录最新一条写着 1.0.0 —— 这种不一致
        // 恰好出现在用户最想搞清楚「我手上这份到底是哪一版」的时候。
        //
        // 断的是**最新那一条**，不是「全文里出现过」。早先写成
        // `changelog.contains("version: \"\(version)\"")`，两种情形都是全绿的：
        // 表顶上多出一条 1.1.0 而脚本还停在 1.0.0（也就是这条测试要防的那件事本身），
        // 以及全表都是 2.0.0、只有一行注释里写着 1.0.0。

        // 脚本这边：只认顶格的赋值。`# APP_VERSION="9.9.9"` 这种注释不算数，
        // 而 shell 以最后一次赋值为准，所以多于一处就没法判断哪个才是打进 .app 的。
        let script = try text(at: "scripts/build-app.sh")
        let assignments = try NSRegularExpression(pattern: #"(?m)^APP_VERSION="([^"]*)""#)
            .matches(in: script, range: NSRange(script.startIndex..., in: script))
        XCTAssertEqual(assignments.count, 1,
                       "build-app.sh 里顶格的 APP_VERSION=\"…\" 赋值有 \(assignments.count) 处，"
                       + "而 shell 以最后一次赋值为准，这条测试无从判断哪一个才是打进 .app 的版本。"
                       + "下一步：把 build-app.sh 收敛成只有一处 APP_VERSION=\"…\"。")
        let stamped = try XCTUnwrap(
            assignments.first
                .flatMap { Range($0.range(at: 1), in: script) }
                .map { String(script[$0]) },
            "build-app.sh 里找不到顶格的 APP_VERSION=\"…\" 赋值。"
            + "下一步：Info.plist 的 CFBundleShortVersionString 就是从它来的，把它加回去。")
        XCTAssertFalse(stamped.isEmpty,
                       "build-app.sh 里的 APP_VERSION 是空串，打出来的 .app 会没有版本号。"
                       + "下一步：填上真实版本号。")

        // 表这边：PackagingTests 刻意不依赖 IELTSCoachUI（原因写在 Package.swift 里），
        // 所以只能读文本。「最新那一条 = 数组里的第一条」这个前提由
        // ChangelogTests.testVersionsAreUniqueAndNewestFirst 守着。
        let changelog = strippingSwiftComments(
            try text(at: "Sources/IELTSCoachUI/Upgrade/Changelog.swift"))
        let table = try XCTUnwrap(
            changelog.range(of: "static let releases"),
            "Changelog.swift 里找不到 releases 这张表——它改名或者被删了。"
            + "下一步：把表加回来，或者同步改这条测试指向新名字。")
        let newestMatch = try XCTUnwrap(
            changelog.range(of: #"version:\s*"([^"]*)""#,
                            options: .regularExpression,
                            range: table.upperBound..<changelog.endIndex),
            "Changelog.releases 里一条 version: \"…\" 都没有，这张表是空的。"
            + "下一步：至少补一条当前版本的记录，否则「功能升级」页等于还是占位页。")
        let newest = String(changelog[newestMatch])
            .replacingOccurrences(of: #"^version:\s*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")

        XCTAssertEqual(newest, stamped,
                       "更新记录最新一条写的是 \(newest)，而 build-app.sh 打进 .app 的是 \(stamped)——"
                       + "用户在关于页看到的版本号，和在「功能升级」页读到的最新一条对不上。"
                       + "下一步：要么把 build-app.sh 的 APP_VERSION 改成 \(newest)，"
                       + "要么在 Changelog.releases 顶上补一条 \(stamped) 的记录。")
    }

    func testOpenInstructionsCoverGatekeeperAndTheDataDirectory() throws {
        // 这份说明是随包发出去的，收件人只有它。少一条他就卡住了。
        let instructions = try text(at: "packaging/open-instructions.txt")
        XCTAssertTrue(instructions.contains("仍要打开"), "没写怎么绕过 Gatekeeper")
        XCTAssertTrue(instructions.contains("辅助功能"), "没写要授予什么权限")
        XCTAssertTrue(instructions.contains("Application Support/IELTS Speaking Coach"),
                      "没写数据存在哪儿——换电脑和备份都靠它")
    }
}
