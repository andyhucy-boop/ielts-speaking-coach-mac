import XCTest
@testable import IELTSCoachCore

final class MicrophonePermissionStateTests: XCTestCase {
    /// 这是本阶段最容易写错的一条规则。
    ///
    /// macOS 一个 App 一辈子只会为麦克风弹一次系统对话框：用户点过「不允许」之后
    /// 再调 requestAccess 会立刻返回拒绝，对话框根本不出现。若代码把 .denied 也
    /// 当成「可以再弹一次」，用户点了开关之后就会对着一个永远不来的弹窗干等——
    /// 这正是「禁止无限等待」要防的事。
    func testOnlyNotDeterminedCanPrompt() {
        XCTAssertTrue(MicrophonePermissionState.notDetermined.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.denied.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.restricted.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.granted.canPrompt)
    }

    func testGrantedHasNothingToSay() {
        XCTAssertNil(MicrophonePermissionState.granted.guidance)
    }

    /// 每一条引导都必须同时说清「发生了什么」和「下一步做什么」。
    func testEveryBlockedStateExplainsWhatHappenedAndWhatToDoNext() {
        for state in MicrophonePermissionState.allCases where state != .granted {
            let guidance = state.guidance
            XCTAssertNotNil(guidance, "\(state) 没有给用户任何说明")
            XCTAssertTrue(guidance?.contains("下一步") == true,
                          "\(state) 的说明没写下一步做什么：\(guidance ?? "nil")")
        }
    }

    /// 被拒之后唯一的出路是系统设置，所以文案里必须点名它，
    /// 否则用户只会知道「不行」，不知道去哪儿改。
    func testDeniedPointsAtSystemSettings() {
        let guidance = MicrophonePermissionState.denied.guidance ?? ""
        XCTAssertTrue(guidance.contains("系统设置"))
        XCTAssertTrue(guidance.contains("麦克风"))
    }

    func testSystemSettingsURLIsTheMicrophonePane() {
        XCTAssertEqual(MicrophonePermissionState.systemSettingsURLString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertNotNil(URL(string: MicrophonePermissionState.systemSettingsURLString))
    }
}
