import XCTest
@testable import IELTSCoachCore

final class TranscriptSettingsTests: XCTestCase {
    func testDefaultIsOn() {
        // ROADMAP 第 5 节：逐字稿默认开、录音默认关。
        // 前者只多采集 AX 树（无隐私与权限成本，且是复盘质量的基础），
        // 后者涉及麦克风权限与磁盘占用，须用户明确同意。
        XCTAssertTrue(CoachSettings.defaultTranscriptEnabled)
        XCTAssertTrue(CoachState.empty().settings.transcriptEnabled)
        XCTAssertFalse(CoachState.empty().settings.recordingEnabled, "录音默认必须仍然是关的")
    }

    func testTheThirdParameterIsOptionalSoExistingCallSitesKeepCompiling() {
        let settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "")
        XCTAssertTrue(settings.transcriptEnabled)
    }

    /// **这条守的是「升级一次版本，用户的设置被默认值悄悄盖掉」。**
    /// 老的 state.json 里没有 transcriptEnabled 这个键，合成的解码器遇到缺键会直接抛错，
    /// 等于「升级一次，全部训练数据读不出来」。必须容错，且缺键时回落到**开**。
    func testOldStateFileWithoutTheKeyStillDefaultsToOn() throws {
        let old = #"{"schemaVersion":3,"settings":{"recordingEnabled":true,"recordingConsentAt":"t"}}"#
        let state = try JSONDecoder().decode(CoachState.self, from: Data(old.utf8))
        XCTAssertTrue(state.settings.transcriptEnabled, "缺这个键时必须默认开，不是默认关")
        XCTAssertTrue(state.settings.recordingEnabled, "同一份设置里别的字段不能被带歪")
    }

    func testTheStoredValueSurvivesARoundTrip() throws {
        var state = CoachState.empty()
        state.settings.transcriptEnabled = false
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(CoachState.self, from: data)
        XCTAssertFalse(restored.settings.transcriptEnabled,
                       "用户关掉之后必须真的关着，下次打开不能又变回开")
    }

    func testItReallyReachesTheDiskThroughStateStore() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        let directory = DataDirectory(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: directory)

        try store.mutate { $0.settings.transcriptEnabled = false }
        XCTAssertFalse(try store.load().settings.transcriptEnabled)

        let onDisk = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("transcriptEnabled"),
                      "字段必须真的写进 state.json，否则换台机器拷目录就丢了")
    }
}
