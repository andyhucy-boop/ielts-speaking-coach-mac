import XCTest
@testable import IELTSCoachCore

final class WeeklyGoalTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 纯逻辑

    func testDefaultIsFive() {
        // ROADMAP 第 5 节：每周训练目标默认 5 次
        XCTAssertEqual(CoachSettings.defaultWeeklyGoal, 5)
        XCTAssertEqual(CoachState.empty().settings.weeklyGoal, 5)
    }

    func testNormalizedAcceptsValuesInRange() {
        XCTAssertEqual(CoachSettings.normalized(1), 1)
        XCTAssertEqual(CoachSettings.normalized(7), 7)
        XCTAssertEqual(CoachSettings.normalized(21), 21)
    }

    func testNormalizedFallsBackForOutOfRangeOrMissing() {
        // 0 会让「本周 3/0 次」变成没有意义的显示；999 是手滑输入。
        // 一个坏掉的目标数字不该让整份训练数据读不出来，所以是回落而不是抛错。
        XCTAssertEqual(CoachSettings.normalized(0), 5)
        XCTAssertEqual(CoachSettings.normalized(-3), 5)
        XCTAssertEqual(CoachSettings.normalized(999), 5)
        XCTAssertEqual(CoachSettings.normalized(nil), 5)
    }

    func testMemberwiseInitNormalizes() {
        XCTAssertEqual(CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     weeklyGoal: 0).weeklyGoal, 5)
    }

    /// **跨阶段回归（2026-08-06 复审补入）。** 本任务整体替换了 `CoachSettings`，
    /// 最容易犯的错就是把 Phase 4 加的 `transcriptEnabled` 顺手删掉——
    /// 那样编译能过（新参数都带默认值），只是用户关掉的逐字稿开关会在下一次
    /// 写盘时被默认值悄悄盖回「开」，没有任何报错。
    ///
    /// **Phase 4 尚未交付时，把这条整条注释掉并在报告里写明，不要删。**
    func testTranscriptSwitchFromPhase4SurvivesThisRewrite() throws {
        let json = #"{"recordingEnabled":false,"recordingConsentAt":"","transcriptEnabled":false}"#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.transcriptEnabled, "transcriptEnabled 被这次重写弄丢了")

        let roundTripped = try JSONDecoder().decode(
            CoachSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertFalse(roundTripped.transcriptEnabled, "transcriptEnabled 没有被编码回去")
    }

    // MARK: - 落盘与读回

    func testWeeklyGoalPersistsThroughStateStore() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = 3 }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 3)
    }

    func testOldStateFileWithoutWeeklyGoalGetsDefaultAndKeepsOtherSettings() throws {
        // weeklyGoal 是 Phase 7 才加的字段。用合成解码器会因为缺键直接抛错，
        // 等于「升级一次版本，用户全部训练数据读不出来」。
        let json = #"""
        {"schemaVersion":3,
         "settings":{"recordingEnabled":true,"recordingConsentAt":"2026-01-01T00:00:00Z"}}
        """#
        try json.write(to: directory.stateFile, atomically: true, encoding: .utf8)

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.settings.weeklyGoal, 5)
        XCTAssertTrue(state.settings.recordingEnabled, "加新字段不能把已有设置读丢")
        XCTAssertEqual(state.settings.recordingConsentAt, "2026-01-01T00:00:00Z")
    }

    func testOutOfRangeWeeklyGoalOnDiskIsNormalizedOnLoad() throws {
        let json = #"""
        {"schemaVersion":3,
         "settings":{"recordingEnabled":false,"recordingConsentAt":"","weeklyGoal":0}}
        """#
        try json.write(to: directory.stateFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 5)
    }

    func testSettingWeeklyGoalThroughTheStoreClampsAndPersists() throws {
        // 这就是 AppState.setWeeklyGoal 做的事：先归一，再写盘。
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = CoachSettings.normalized(99) }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 5)

        try store.mutate { $0.settings.weeklyGoal = CoachSettings.normalized(7) }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 7)
    }

    func testWeeklyGoalIsWrittenIntoStateFile() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = 4 }
        let text = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(text.contains("\"weeklyGoal\""), "新字段必须真的写进 state.json")
    }
}
