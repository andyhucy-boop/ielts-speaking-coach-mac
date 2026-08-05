import XCTest
import ChatGPTBridge
@testable import IELTSCoachUI

final class PermissionStatusTests: XCTestCase {
    func testReadyWhenPreflightOK() {
        let readiness = BridgeReadiness(ok: true, messages: ["✅ 环境就绪"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .ready)
    }

    func testNeedsAccessibilityWhenMessageMentionsIt() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsAccessibility)
    }

    func testNeedsChatGPTWhenNotInstalled() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testChatGPTTakesPrecedenceWhenBothMissing() {
        // 两样都缺时先引导装 ChatGPT —— 没有目标应用，给了权限也没用
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。",
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testUnknownWhenNotOKButNoRecognizedMessage() {
        // 不能默认当成「就绪」——那会让用户点进去撞一堵墙
        let readiness = BridgeReadiness(ok: false, messages: ["某种没见过的失败"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .unknown)
    }

    func testSystemSettingsURLPointsAtAccessibilityPane() {
        XCTAssertEqual(PermissionStatus.systemSettingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - 把消息的生产者和消费者绑在一起
    //
    // 上面那批测试全用手写字符串，管不住真正会坏的那一环：`evaluate` 认的
    // 「没找到 ChatGPT」「辅助功能」是写死在 AXDriver 里的文案，改了 AXDriver 的措辞，
    // 手写字符串的测试照样全绿，而 evaluate 会对「没装 ChatGPT」这个最常见的首次启动
    // 失败退化成 .unknown。下面这批让 preflight 的真实输出流过 evaluate。
    // 用假 AXAccess，全程不接触真实 ChatGPT（铁律 5）。

    private func realPreflight(installed: Bool, trusted: Bool,
                               host: HostEnvironment = .commandLine) -> BridgeReadiness {
        let access = FakeAXAccess()
        access.installed = installed
        access.trusted = trusted
        return AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                        shortTimeout: 0.2, stateTimeout: 0.2, host: host).preflight()
    }

    /// 两种宿主都跑一遍：措辞按宿主分叉之后，判定结果不允许跟着分叉。
    private let allHosts: [HostEnvironment] = [.commandLine, .app(name: "IELTS Speaking Coach")]

    func testEvaluateUnderstandsRealPreflightWhenChatGPTIsNotInstalled() {
        for host in allHosts {
            let readiness = realPreflight(installed: false, trusted: true, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT,
                           "AXDriver 说的和 evaluate 认的对不上了（宿主：\(host)）："
                           + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenAccessibilityIsDenied() {
        for host in allHosts {
            let readiness = realPreflight(installed: true, trusted: false, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsAccessibility,
                           "AXDriver 说的和 evaluate 认的对不上了（宿主：\(host)）："
                           + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenBothAreMissing() {
        for host in allHosts {
            let readiness = realPreflight(installed: false, trusted: false, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT,
                           "两样都缺时先引导装 ChatGPT（宿主：\(host)）：" + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenEverythingIsReady() {
        for host in allHosts {
            let readiness = realPreflight(installed: true, trusted: true, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .ready,
                           "宿主：\(host)：" + readiness.messages.joined())
        }
    }

    // MARK: - 同一屏上不许出现互相矛盾的「下一步」

    func testAppHostScreenNeverTellsUserToAuthorizeTheTerminal() {
        // 这条守的是复审抓到的原始故障：页面上方的引导语说「把本应用加进列表」，
        // 下方原样展示的 preflight 原文却说「把运行本工具的终端加进去」。
        // 照原文做的用户会去授权终端，回来点「重新检查」仍然失败。
        let host = HostEnvironment.app(name: "IELTS Speaking Coach")
        let readiness = realPreflight(installed: true, trusted: false, host: host)
        let state = PermissionStatus.evaluate(readiness: readiness)
        XCTAssertEqual(state, .needsAccessibility)

        let onScreen = (readiness.messages + [PermissionStatus.guidance(for: state, host: host)]).joined()
        XCTAssertTrue(onScreen.contains("IELTS Speaking Coach"))
        XCTAssertFalse(onScreen.contains("终端"),
                       "页面上任何一句话都不许让 .app 用户去勾终端——照做会白忙一场")
    }

    func testCommandLineHostScreenStillPointsAtTheTerminal() {
        let host = HostEnvironment.commandLine
        let readiness = realPreflight(installed: true, trusted: false, host: host)
        let state = PermissionStatus.evaluate(readiness: readiness)
        let onScreen = (readiness.messages + [PermissionStatus.guidance(for: state, host: host)]).joined()
        XCTAssertTrue(onScreen.contains("终端"))
    }

    // MARK: - 给出的「下一步」必须是用户做得到的事

    func testEveryGuidanceSaysWhatHappenedAndWhatToDoNext() {
        for state in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for host in allHosts {
                let text = PermissionStatus.guidance(for: state, host: host)
                XCTAssertFalse(text.isEmpty, "\(state) 没有引导语")
                if state != .ready {
                    XCTAssertTrue(text.contains("下一步"),
                                  "\(state)（宿主 \(host)）只说了失败没说下一步")
                }
            }
        }
    }

    func testUnknownGuidanceOnlyAsksForThingsAGUIUserCanActuallyDo() {
        for host in allHosts {
            let text = PermissionStatus.guidance(for: .unknown, host: host)
            XCTAssertFalse(text.contains("axprobe"),
                           "build-app.sh 只把 IELTSCoachApp 打进 .app，只装了 .app 的用户没有 axprobe")
            XCTAssertFalse(text.contains("终端"), "Phase 3 的目标是全程不需要打开终端")
            XCTAssertTrue(text.contains("复制诊断信息"), "得给一个界面里真按得到的按钮")
        }
    }

    func testAccessibilityGuidanceNamesWhoToTickAndHowToComeBack() {
        let text = PermissionStatus.guidance(for: .needsAccessibility,
                                             host: .app(name: "IELTS Speaking Coach"))
        XCTAssertTrue(text.contains("隐私与安全性 › 辅助功能"))
        XCTAssertTrue(text.contains("IELTS Speaking Coach"))
        XCTAssertTrue(text.contains("重新检查"))
    }

    // MARK: - 「打开系统设置」不许静默失败（铁律 7）

    func testOpenSettingsAsksTheSystemForTheAccessibilityPane() {
        var requested: URL?
        _ = PermissionStatus.openSettings(host: .commandLine) { url in
            requested = url
            return true
        }
        XCTAssertEqual(requested, PermissionStatus.systemSettingsURL)
    }

    func testOpenSettingsReportsFailureInsteadOfLookingLikeADeadButton() {
        // NSWorkspace.open 的返回值在 AppKit 上是 @discardableResult，丢掉它编译器不会警告，
        // 用户看到的就是「点了没反应」。
        let notice = PermissionStatus.openSettings(host: .app(name: "IELTS Speaking Coach")) { _ in false }
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("没能打开系统设置"), "要说清发生了什么")
        XCTAssertTrue(notice.text.contains("系统设置 › 隐私与安全性 › 辅助功能"),
                      "打不开时必须给出手动路径，否则用户无路可走")
        XCTAssertTrue(notice.text.contains("IELTS Speaking Coach"))
    }

    func testOpenSettingsSuccessIsNotReportedAsFailureButStillSaysWhatToDoThere() {
        // 就算 open 返回 true，也不保证真的落在「辅助功能」那一栏（URL 锚点是否被接受
        // 由系统决定），所以成功提示里也要写清到了那儿该做什么。
        let notice = PermissionStatus.openSettings(host: .commandLine) { _ in true }
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("下一步"))
        XCTAssertTrue(notice.text.contains("辅助功能"))
    }

    // MARK: - 「复制诊断信息」

    func testCopyDiagnosticsPutsThePreflightMessagesOnThePasteboard() {
        var written: String?
        _ = PermissionStatus.copyDiagnostics(state: .unknown,
                                             messages: ["❌ 某种没见过的失败", "⚠️ 另一条"],
                                             host: .app(name: "IELTS Speaking Coach"),
                                             systemVersion: "TEST-OS 1.2.3") { text in
            written = text
            return true
        }
        let text = written ?? ""
        XCTAssertTrue(text.contains("❌ 某种没见过的失败"))
        XCTAssertTrue(text.contains("⚠️ 另一条"))
        XCTAssertTrue(text.contains("TEST-OS 1.2.3"), "系统版本是排查这类问题的第一线索")
        XCTAssertTrue(text.contains("IELTS Speaking Coach"), "得写清是在哪个宿主里跑的")
        XCTAssertTrue(text.contains(PermissionStatus.title(for: .unknown)))
    }

    func testCopyDiagnosticsReportsFailureAndGivesAManualFallback() {
        let notice = PermissionStatus.copyDiagnostics(state: .unknown, messages: ["❌ 某种没见过的失败"],
                                                      host: .commandLine,
                                                      systemVersion: "TEST-OS") { _ in false }
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("没能"), "写剪贴板失败要说出来，不能假装复制成功")
        XCTAssertTrue(notice.text.contains("下一步"))
        XCTAssertTrue(notice.text.contains("⌘C"), "得留一条不靠剪贴板 API 的退路")
    }

    func testCopyDiagnosticsSuccessConfirmsItIsOnThePasteboard() {
        let notice = PermissionStatus.copyDiagnostics(state: .unknown, messages: ["x"],
                                                      host: .commandLine,
                                                      systemVersion: "TEST-OS") { _ in true }
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("已复制"))
    }
}
