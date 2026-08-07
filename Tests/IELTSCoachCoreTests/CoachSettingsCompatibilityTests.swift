import XCTest
@testable import IELTSCoachCore

final class CoachSettingsCompatibilityTests: XCTestCase {

    func testDecodesLegacySettingsWithoutTheNewFields() throws {
        let legacy = #"{"recordingEnabled":true,"recordingConsentAt":"2026-08-01T00:00:00Z"}"#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, "2026-08-01T00:00:00Z")
        XCTAssertEqual(settings.defaultRoute, CoachSettings.defaultRouteFallback)
        XCTAssertEqual(settings.feedbackTiming, .deferred, "ROADMAP 第 5 节：默认全程零反馈")
        XCTAssertEqual(settings.part2PrepMode, .countdown, "ROADMAP 第 5 节：默认一分钟倒计时")
    }

    /// 枚举字段直接 decode 时，遇到不认识的取值会抛错，
    /// 而这个错会一路冒泡到 CoachState，让 StateStore 报「训练数据文件已损坏」。
    /// 为了一个偏好设置丢掉全部练习记录，不成比例。
    func testUnknownEnumValuesFallBackInsteadOfBlowingUpTheWholeFile() throws {
        let weird = """
        {"recordingEnabled":false,"recordingConsentAt":"",
         "feedbackTiming":"someday","part2PrepMode":"whenever"}
        """
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(weird.utf8))
        XCTAssertEqual(settings.feedbackTiming, .deferred)
        XCTAssertEqual(settings.part2PrepMode, .countdown)
    }

    func testRoundTripsTheNewFields() throws {
        let settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     defaultRoute: "retrain", feedbackTiming: .immediate,
                                     part2PrepMode: .learnerControlled)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CoachSettings.self, from: data), settings)
    }

    func testEmptyStateCarriesTheDocumentedDefaults() {
        let settings = CoachState.empty().settings
        XCTAssertEqual(settings.defaultRoute, "planToday")
        XCTAssertEqual(settings.feedbackTiming, .deferred)
        XCTAssertEqual(settings.part2PrepMode, .countdown)
    }

    /// 真实用户硬盘上那份文件长这样：plan 里没有 focusPart、settings 只有两个字段。
    /// 整份 state.json 必须照样读得出来，一个字段都不能丢。
    func testWholeLegacyStateJSONStillDecodes() throws {
        let json = """
        {"schemaVersion":3,"learner":{"displayName":"Andy","createdAt":"2026-01-01T00:00:00Z"},
         "currentSession":null,"sessions":[],"targets":[],"issues":[],"vocabulary":[],
         "plan":{"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z",
                 "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]},
         "questions":[],"questionSources":[],
         "settings":{"recordingEnabled":false,"recordingConsentAt":""},
         "questionCursor":{"part1":0,"part2":0,"part3":0}}
        """
        let state = try JSONDecoder().decode(CoachState.self, from: Data(json.utf8))
        XCTAssertEqual(state.plan?.focusPart, .fullMock)
        XCTAssertEqual(state.plan?.days.first?.completedQuestionIds, ["q1"],
                       "升级不能把已经练过的题变回没练过")
        XCTAssertEqual(state.settings.defaultRoute, CoachSettings.defaultRouteFallback)
        XCTAssertEqual(state.settings.feedbackTiming, .deferred)
    }

    /// **跨阶段回归。** 本任务改写了 `CoachSettings`，最容易犯的错就是把
    /// 前面阶段加的字段顺手删掉——那样编译能过（默认参数顶上了），
    /// 只是用户存过的取值在下一次写盘时被默认值盖掉，没有任何报错。
    ///
    /// 一条测两个字段：Phase 4 的 `transcriptEnabled` 与 Phase 7 的 `weeklyGoal`。
    func testEarlierPhasesFieldsSurviveThisRewrite() throws {
        let json = #"""
        {"recordingEnabled":false,"recordingConsentAt":"",
         "transcriptEnabled":false,"weeklyGoal":3}
        """#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.weeklyGoal, 3, "weeklyGoal 被这次重写弄丢了")
        XCTAssertFalse(settings.transcriptEnabled, "transcriptEnabled 被这次重写弄丢了")

        let roundTripped = try JSONDecoder().decode(
            CoachSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(roundTripped.weeklyGoal, 3, "weeklyGoal 没有被编码回去")
        XCTAssertFalse(roundTripped.transcriptEnabled, "transcriptEnabled 没有被编码回去")
    }

    /// **跨阶段回归。** Phase 5 的录音开关每拨一次就会走一遍
    /// `RecordingConsent.enable` / `disable`。那两个函数若用
    /// `CoachSettings(recordingEnabled:recordingConsentAt:)` 重新构造，
    /// 本任务新加的三项偏好与 Phase 7 的每周目标会被静默重置回默认值。
    func testTogglingTheRecordingSwitchKeepsEveryOtherSetting() {
        let original = CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     transcriptEnabled: false,
                                     weeklyGoal: 3, defaultRoute: "retrain",
                                     feedbackTiming: .immediate,
                                     part2PrepMode: .learnerControlled)

        let on = RecordingConsent.enable(original, at: "2026-08-06T10:00:00Z")
        XCTAssertFalse(on.transcriptEnabled)
        XCTAssertEqual(on.weeklyGoal, 3)
        XCTAssertEqual(on.defaultRoute, "retrain")
        XCTAssertEqual(on.feedbackTiming, .immediate)
        XCTAssertEqual(on.part2PrepMode, .learnerControlled)

        let off = RecordingConsent.disable(on)
        XCTAssertFalse(off.transcriptEnabled)
        XCTAssertEqual(off.weeklyGoal, 3)
        XCTAssertEqual(off.defaultRoute, "retrain")
        XCTAssertEqual(off.feedbackTiming, .immediate)
        XCTAssertEqual(off.part2PrepMode, .learnerControlled)
        XCTAssertFalse(off.recordingEnabled)
        XCTAssertEqual(off.recordingConsentAt, "")
    }
}
