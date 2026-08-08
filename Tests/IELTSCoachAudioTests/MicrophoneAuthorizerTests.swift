import AVFoundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachAudio

final class MicrophoneAuthorizerTests: XCTestCase {
    /// 只测纯映射。**绝不能在这里调 currentStatus() 或 requestAccess()**：
    /// 前者的返回值取决于跑测试这台机器授过什么权（今天绿明天红），
    /// 后者会弹系统对话框把测试挂死。
    func testMapsEveryKnownAuthorizationStatus() {
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.authorized), .granted)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.notDetermined), .notDetermined)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.denied), .denied)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.restricted), .restricted)
    }

    /// 未来的系统若加了新的授权状态，必须按「录不了」处理。
    ///
    /// 这条分支的错法只有一种但后果最重：默认成 `.granted` 的话，App 会以为自己在录，
    /// 用户练完却什么都没有，界面上还没有任何线索——正是「禁止静默失败」要挡的事。
    /// `AVAuthorizationStatus` 是 Objective-C 枚举，用一个系统还没用过的 rawValue
    /// 就能真的走进 `@unknown default`。
    func testUnknownFutureAuthorizationStatusIsTreatedAsDenied() throws {
        let future = try XCTUnwrap(AVAuthorizationStatus(rawValue: 99),
                                   "构造不出未知状态，这条分支就测不到了")
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(future), .denied)
    }

    // MARK: - 「被拒过就别再弹窗」

    /// 数弹窗被调了几次。用 class 是因为要在闭包里改。
    private final class PromptSpy {
        private(set) var calls = 0
        let answer: Bool
        init(answer: Bool) { self.answer = answer }
        func prompt() -> Bool {
            calls += 1
            return answer
        }
    }

    /// 这是本阶段唯一一处「会让用户干等」的地方，所以直接盯着真正在跑的那条判断。
    ///
    /// macOS 一个 App 一辈子只为麦克风弹一次系统对话框。用户点过「不允许」之后再调
    /// `AVCaptureDevice.requestAccess` 不会弹窗，只会立刻返回拒绝——界面上什么都不发生，
    /// 用户只能对着一个永远不出现的对话框干等。所以非 `.notDetermined` 时必须原样返回，
    /// 一次弹窗都不许发起。
    func testAlreadyAnsweredStatesNeverPromptAgain() async {
        for current in [MicrophonePermissionState.denied, .restricted, .granted] {
            let spy = PromptSpy(answer: true)
            let result = await SystemMicrophoneAuthorizer.resolveAccessRequest(
                current: current, prompt: { spy.prompt() })
            XCTAssertEqual(result, current, "\(current) 应当原样返回，而不是被弹窗结果覆盖")
            XCTAssertEqual(spy.calls, 0,
                           "\(current) 状态下还去弹窗，用户会对着一个永远不出现的对话框干等")
        }
    }

    func testNotDeterminedPromptsExactlyOnceAndTakesTheAnswer() async {
        let allowed = PromptSpy(answer: true)
        let grantedResult = await SystemMicrophoneAuthorizer.resolveAccessRequest(
            current: .notDetermined, prompt: { allowed.prompt() })
        XCTAssertEqual(grantedResult, .granted)
        XCTAssertEqual(allowed.calls, 1, "还没问过就该弹一次窗，否则永远拿不到权限")

        let refused = PromptSpy(answer: false)
        let deniedResult = await SystemMicrophoneAuthorizer.resolveAccessRequest(
            current: .notDetermined, prompt: { refused.prompt() })
        XCTAssertEqual(deniedResult, .denied)
        XCTAssertEqual(refused.calls, 1)
    }
}
