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
}
