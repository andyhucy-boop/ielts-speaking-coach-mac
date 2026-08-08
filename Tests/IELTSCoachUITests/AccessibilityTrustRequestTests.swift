import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 守住「让本应用出现在系统设置的辅助功能列表里」这条线。
///
/// 2026-08-08 真机第一次使用就撞上：App 打包好了、打开了、界面停在授权页，
/// 而用户在「系统设置 › 隐私与安全性 › 辅助功能」里**根本搜不到这个应用**。
/// 根因是全项目只调 `AXIsProcessTrusted()`（被动查询），
/// 从来没调过带 prompt 的 `AXIsProcessTrustedWithOptions`——而后者才是
/// 把应用登记进那份列表的唯一办法。
///
/// 1859 条测试全绿，产品的第一步却走不通。这是真机验收才发现得了的那一类，
/// 所以这里补的守卫也只能守住「代码里接上了」，守不住「系统真的弹窗了」。
@MainActor
final class AccessibilityTrustRequestTests: XCTestCase {

    func testRequestingPermissionActuallyAsksTheSystemAndThenRechecks() async throws {
        let access = FakeAXAccess()
        access.trusted = false
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = DataDirectory(root: root)

        // 计数得跨线程：preflight 被甩到 Task.detached 上跑（那一步在真机上要等十秒）。
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func bump() { lock.lock(); value += 1; lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        }
        let preflightCalls = Counter()

        let app = AppState(
            directory: directory,
            requestTrust: { access.requestAccessibilityTrust() },
            preflight: {
                preflightCalls.bump()
                return BridgeReadiness(ok: access.isAccessibilityTrusted(), messages: [])
            })

        await app.requestAccessibilityPermission()

        XCTAssertEqual(access.trustRequests, 1,
                       "点了「申请辅助功能权限」却没有真的去问系统——那颗按钮就是个摆设，"
                       + "而本应用永远不会出现在系统设置的列表里")
        XCTAssertGreaterThanOrEqual(preflightCalls.count, 1,
                                    "申请完必须立刻重查一次：用户在弹窗里点了「允许」之后，"
                                    + "界面得当场变成「环境就绪」，而不是让他自己再点一次「重新检查」")
    }

    func testTheButtonOnScreenIsWiredToThatMethodAndNotToSomethingElse() throws {
        // 视图模型侧接对了，不代表屏幕上那颗按钮接到了它——这个项目已经因为
        // 「逻辑对但没接上」栽过好几次，所以这里扫源码。
        let gate = try SourceGuard.read("Onboarding/PermissionGateView.swift")
        XCTAssertTrue(gate.contains(#"Button("申请辅助功能权限")"#),
                      "授权页上没有「申请辅助功能权限」这颗按钮")
        XCTAssertTrue(gate.contains("onRequestPermission()"),
                      "那颗按钮没有接上 onRequestPermission")

        let flow = try SourceGuard.read("Onboarding/WelcomeFlowView.swift")
        XCTAssertTrue(flow.contains("app.requestAccessibilityPermission()"),
                      "引导页没有把 onRequestPermission 接到 AppState.requestAccessibilityPermission——"
                      + "接到别的方法上的话，按钮点下去不会向系统申请任何东西")
    }
}
