import XCTest

final class PackagingContractTests: XCTestCase {

    private var root: URL { NotarizeScriptTests.repositoryRoot }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    func testAllPackagingScriptsAreExecutable() {
        // Task 10 会往这个列表里补 verify-portability.sh。
        for script in ["build-app.sh", "verify-signature-stability.sh",
                       "package-app.sh", "notarize.sh", "make-icon.sh"] {
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
        let script = try text(at: "scripts/build-app.sh")
        let match = try XCTUnwrap(
            script.range(of: #"APP_VERSION="[^"]+""#, options: .regularExpression),
            "build-app.sh 里找不到 APP_VERSION")
        let version = script[match]
            .replacingOccurrences(of: "APP_VERSION=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")

        let changelog = try text(at: "Sources/IELTSCoachUI/Upgrade/Changelog.swift")
        XCTAssertTrue(changelog.contains("version: \"\(version)\""),
                      "更新记录里没有 \(version) 这一版。"
                      + "下一步：要么在 Changelog.releases 顶上补一条，要么改回 build-app.sh 里的 APP_VERSION。")
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
