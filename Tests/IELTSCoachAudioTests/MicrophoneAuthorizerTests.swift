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
}
