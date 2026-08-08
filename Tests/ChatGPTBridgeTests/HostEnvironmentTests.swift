import XCTest
@testable import ChatGPTBridge

/// 守的是「命令行时代的假设漏进图形界面」这一类问题。
///
/// 辅助功能（TCC）授权的对象是**发起 AX 调用的进程被系统归属到的那个应用**：
/// 从终端跑 `coach` / `axprobe`，归属的是终端；双击 `.app` 跑，归属的是本应用。
/// preflight 的提示只写死一种，另一种宿主的用户照着做会白忙一场——授权了错误的对象，
/// 回来重试仍然失败，且界面上没有任何线索说明为什么。
final class HostEnvironmentTests: XCTestCase {

    // MARK: - 宿主识别

    /// 在临时目录里造一个真的 `.app` 包（Contents/Info.plist），用 `Bundle` 读它。
    /// 不用假 Bundle：`detect` 要验证的就是「对着真实的 bundle 布局能不能认出来」。
    private func makeAppBundle(name: String?) throws -> Bundle {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HostEnvironmentTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("IELTS Speaking Coach.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var info: [String: Any] = ["CFBundleIdentifier": "com.ielts.speakingcoach"]
        if let name { info["CFBundleName"] = name }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(Bundle(url: app))
    }

    func testDetectsAppBundleAsAppHostAndTakesItsDisplayName() throws {
        let bundle = try makeAppBundle(name: "IELTS Speaking Coach")
        XCTAssertEqual(HostEnvironment.detect(bundle: bundle), .app(name: "IELTS Speaking Coach"))
    }

    func testAppBundleWithoutNameStillCountsAsAppHost() throws {
        // 名字读不到时也绝不能退回「命令行」——那会让 .app 用户看到「去勾选终端」
        let bundle = try makeAppBundle(name: nil)
        XCTAssertEqual(HostEnvironment.detect(bundle: bundle), .app(name: "本应用"))
    }

    func testDetectsPlainExecutableDirectoryAsCommandLine() throws {
        // 命令行可执行文件（`swift run coach`、`.build/release/axprobe`）的 Bundle.main
        // 是可执行文件所在的**目录**，不是 .app 包
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HostEnvironmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let bundle = try XCTUnwrap(Bundle(url: dir))
        XCTAssertEqual(HostEnvironment.detect(bundle: bundle), .commandLine)
    }

    // MARK: - preflight 的提示必须跟着宿主变

    private func preflight(host: HostEnvironment,
                           trusted: Bool = true,
                           wakeSucceeds: Bool = true) -> BridgeReadiness {
        let access = FakeAXAccess()
        access.trusted = trusted
        access.wakeSucceeds = wakeSucceeds
        return AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                        shortTimeout: 0.2, stateTimeout: 0.2, host: host).preflight()
    }

    func testAppHostIsToldToAuthorizeTheAppItselfNotTheTerminal() {
        let text = preflight(host: .app(name: "IELTS Speaking Coach"), trusted: false)
            .messages.joined()
        XCTAssertTrue(text.contains("IELTS Speaking Coach"),
                      "在 .app 里跑时，辅助功能列表里要勾的是本应用，提示必须点名它")
        XCTAssertFalse(text.contains("终端"),
                       "让 .app 用户去勾终端，他照做一遍回来重试仍然失败，且没有任何线索说明为什么")
    }

    func testCommandLineHostIsStillToldToAuthorizeTheTerminal() {
        let text = preflight(host: .commandLine, trusted: false).messages.joined()
        XCTAssertTrue(text.contains("终端"),
                      "从终端跑时，TCC 授权归属的是终端本身，勾别的没用")
        XCTAssertTrue(text.contains("重新运行本命令"))
    }

    func testAppHostIsNeverAskedToRunAxprobeBecauseTheAppBundleHasNoSuchCommand() {
        // scripts/build-app.sh 只把 IELTSCoachApp 拷进 Contents/MacOS，
        // 只装了 .app 的用户手上根本没有 axprobe 这个命令
        let text = preflight(host: .app(name: "IELTS Speaking Coach"), wakeSucceeds: false)
            .messages.joined()
        XCTAssertTrue(text.contains("⚠️"), "唤醒失败本身仍要报出来")
        XCTAssertFalse(text.contains("axprobe"),
                       ".app 里没有 axprobe，让用户去终端跑它等于给了一个他做不到的下一步")
        XCTAssertTrue(text.contains("复制诊断信息"), "要给的是他在界面里真做得到的动作")
    }

    func testCommandLineHostIsStillPointedAtAxprobeWhenTreeWontWake() {
        let text = preflight(host: .commandLine, wakeSucceeds: false).messages.joined()
        XCTAssertTrue(text.contains("axprobe dump"))
    }
}
