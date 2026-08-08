import XCTest
@testable import IELTSCoachCore

final class RecordingConsentTests: XCTestCase {
    private let t1 = "2026-08-06T10:00:00Z"
    private let t2 = "2026-08-20T21:30:00Z"

    // MARK: - 默认关

    /// 产品决策：录音默认关闭（ROADMAP 第 5 节、spec 第 7 节）。
    /// 涉及麦克风权限与磁盘占用的东西，必须用户明确开启才做。
    func testRecordingIsOffOnAFreshInstall() {
        let settings = CoachState.empty().settings
        XCTAssertFalse(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, "")
        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted),
                       .disabledByUser)
    }

    // MARK: - 同意时间戳

    func testEnableRecordsWhenTheUserAgreed() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        XCTAssertTrue(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, t1)
    }

    /// 同意是一次性的事实，不该因为界面重绘、重复点击而被刷新成「刚刚同意」。
    func testEnablingAgainKeepsTheOriginalConsentTime() {
        let once = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let twice = RecordingConsent.enable(once, at: t2)
        XCTAssertEqual(twice.recordingConsentAt, t1)
    }

    /// 关掉开关等于撤回同意。留着旧时间戳的话，state.json 里会存着一条
    /// 「用户其实已经反悔」的同意记录——这是隐私相关的记录，不能含糊。
    func testDisableClearsTheConsentTime() {
        let enabled = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let disabled = RecordingConsent.disable(enabled)
        XCTAssertFalse(disabled.recordingEnabled)
        XCTAssertEqual(disabled.recordingConsentAt, "")
    }

    func testTurningItBackOnRecordsTheNewTimeNotTheOldOne() {
        let first = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let off = RecordingConsent.disable(first)
        let again = RecordingConsent.enable(off, at: t2)
        XCTAssertEqual(again.recordingConsentAt, t2)
    }

    /// 计划里 `enable` / `disable` 的注释花了整整一段警告「绝不能重新构造 CoachSettings」，
    /// 但计划给的九条测试没有一条能抓住这个 bug：它们全都从 `CoachState.empty().settings`
    /// 出发，而那里的 `transcriptEnabled` 恰好等于 `CoachSettings` 的默认值 true——
    /// 重新构造之后它照样是 true，测试照样全绿。
    ///
    /// 所以这里必须先把 `transcriptEnabled` 拨到**与默认值相反**的一侧再拨录音开关。
    /// 一旦有人把实现写成 `CoachSettings(recordingEnabled:recordingConsentAt:)`，
    /// 这条会立刻变红；不这么写的话，用户每拨一次录音开关就会丢一批别的设置，
    /// 而且不报错、不崩溃，只是设置自己变回去了。
    func testTogglingRecordingLeavesEveryOtherSettingAlone() {
        var settings = CoachState.empty().settings
        settings.transcriptEnabled = false   // 刻意与默认值 true 相反

        let enabled = RecordingConsent.enable(settings, at: t1)
        XCTAssertFalse(enabled.transcriptEnabled, "打开录音开关不该动逐字稿开关")

        let disabled = RecordingConsent.disable(enabled)
        XCTAssertFalse(disabled.transcriptEnabled, "关掉录音开关不该动逐字稿开关")
    }

    // MARK: - 能不能录

    /// 开关是用户的意愿，权限是系统的许可。**开关关着时连问都不用问权限。**
    ///
    /// 计划里这条测试只传了 `.granted`，那样测不出顺序：先看权限还是先看开关，
    /// `.granted` 都会走到「看开关」那一步，结果一样是 `.disabledByUser`，
    /// 把两个 guard 对调也不会变红。真正能分辨顺序的是**权限拿不到、开关也没开**——
    /// 正确的顺序安安静静地返回 `.disabledByUser`（用户压根没要这个功能），
    /// 反过来的顺序会朝他弹一句「去系统设置里开麦克风」，为一个他从没打开过的开关报警。
    func testTheSwitchBeatsThePermission() {
        var settings = CoachState.empty().settings
        settings.recordingEnabled = false

        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted),
                       .disabledByUser)

        for permission in [MicrophonePermissionState.denied, .notDetermined, .restricted] {
            XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: permission),
                           .disabledByUser,
                           "开关关着时不该拿权限的事去烦用户（permission=\(permission)）")
        }
    }

    func testBlockedWithAnActionableMessageWhenPermissionIsMissing() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        guard case .blocked(let message) = RecordingConsent.readiness(settings: settings,
                                                                     permission: .denied) else {
            return XCTFail("开关开着但没权限时必须是 blocked，且要带一条能照着做的说明")
        }
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertTrue(message.contains("系统设置"))
    }

    /// 有人手工改过 state.json、或将来某个迁移写漏了，就会出现
    /// 「开关是开的、同意时间是空的」这种自相矛盾的状态。
    /// 这时候必须停下来问用户，而不是当成已经同意默默开录。
    func testEnabledWithoutAConsentTimeIsRefusedRatherThanAssumed() {
        var settings = CoachState.empty().settings
        settings.recordingEnabled = true
        settings.recordingConsentAt = ""
        guard case .blocked(let message) = RecordingConsent.readiness(settings: settings,
                                                                     permission: .granted) else {
            return XCTFail("没有同意记录就不能录")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testReadyWhenTheSwitchIsOnAndThePermissionIsGranted() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted), .ready)
    }
}
