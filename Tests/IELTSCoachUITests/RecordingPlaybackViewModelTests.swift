import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class RecordingPlaybackViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private var recordings: RecordingStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
        recordings = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, recordingPath: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T10:45:30Z", endedAt: "2026-08-06T11:00:00Z",
                        goal: "补一个原因和例子",
                        transcript: [PracticeSession.TranscriptTurn(
                            role: "assistant", text: "Do you live in a house or a flat?",
                            capturedAt: "2026-08-06T10:46:00Z")],
                        reportPath: "reports/2026-08-06-001.json",
                        recordingPath: recordingPath)
    }

    @discardableResult
    private func makeRecordingFile(_ name: String) throws -> URL {
        let url = directory.recordingsDirectory.appending(path: name)
        try Data(repeating: 0x41, count: 128).write(to: url)
        return url
    }

    private func makeViewModel(_ practice: PracticeSession) -> RecordingPlaybackViewModel {
        RecordingPlaybackViewModel(sessionID: practice.id, relativePath: practice.recordingPath,
                                   store: store, recordings: recordings)
    }

    // MARK: - 三种状态

    /// 这次练习本来就没录音（开关关着）。不该显示播放器，也不该报警。
    func testNoRecordingPathMeansNoPlayerAndNoNoise() {
        let viewModel = makeViewModel(session("s1", recordingPath: ""))
        XCTAssertEqual(viewModel.state, .none)
        XCTAssertNil(viewModel.notice)
    }

    func testReadyWhenTheFileIsThere() throws {
        try makeRecordingFile("a.m4a")
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
        guard case .ready(let url) = viewModel.state else { return XCTFail("文件在就该能播") }
        XCTAssertEqual(url.lastPathComponent, "a.m4a")
    }

    /// **记录里有录音、文件却不在了，必须明说。**
    /// 什么都不显示的话，用户会以为自己记错了，或者以为程序坏了。
    func testAMissingFileIsSaidOutLoudInsteadOfSilentlyShowingNothing() throws {
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))
        guard case .missing(let message) = viewModel.state else {
            return XCTFail("文件不在了不能装作这次本来就没录音")
        }
        XCTAssertTrue(message.contains("找不到"))
        XCTAssertTrue(message.contains("下一步"))
    }

    /// 路径被改坏时同样要说出来，而且**绝不能照着这个路径去删东西**。
    func testAnUnsafePathIsReportedAndNothingOutsideRecordingsIsTouched() throws {
        try Data("重要的训练数据".utf8).write(to: directory.stateFile)
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/../state.json"))

        guard case .missing = viewModel.state else { return XCTFail("路径不合法也要说出来") }
        viewModel.delete()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path),
                      "绝不能顺着一个被改坏的路径删到 recordings 外面去")
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("下一步"))
    }

    // MARK: - 删除

    func testDeleteRemovesTheFileAndClearsThePathOnThatSession() throws {
        try makeRecordingFile("a.m4a")
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/a.m4a")] }

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
        viewModel.delete()

        XCTAssertEqual(viewModel.state, .none)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.recordingsDirectory.appending(path: "a.m4a").path))
        XCTAssertEqual(try store.load().sessions.first?.recordingPath, "")
    }

    /// 删录音只删录音。题目、逐字稿、复盘一个都不能动——
    /// 那是用户练了半小时的成果，跟一条音频完全是两回事。
    func testDeletingARecordingKeepsTheTranscriptAndTheReport() throws {
        try makeRecordingFile("a.m4a")
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/a.m4a")] }

        makeViewModel(session("s1", recordingPath: "recordings/a.m4a")).delete()

        let saved = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(saved.transcript.count, 1)
        XCTAssertEqual(saved.reportPath, "reports/2026-08-06-001.json")
        XCTAssertEqual(saved.goal, "补一个原因和例子")
    }

    func testDeletingOneRecordingLeavesTheOthersAlone() throws {
        try makeRecordingFile("a.m4a")
        try makeRecordingFile("b.m4a")
        try store.mutate {
            $0.sessions = [session("s1", recordingPath: "recordings/a.m4a"),
                           session("s2", recordingPath: "recordings/b.m4a")]
        }

        makeViewModel(session("s1", recordingPath: "recordings/a.m4a")).delete()

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.first(where: { $0.id == "s2" })?.recordingPath,
                       "recordings/b.m4a")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.recordingsDirectory.appending(path: "b.m4a").path))
    }

    /// 文件早就没了也要能把记录里的指向清掉，否则这条会永远显示「找不到」。
    func testClearingAStaleReferenceWorksWithoutTheFile() throws {
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/gone.m4a")] }

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))
        viewModel.clearReferenceOnly()

        XCTAssertEqual(viewModel.state, .none)
        XCTAssertEqual(try store.load().sessions.first?.recordingPath, "")
    }

    /// 删之前必须问一声，而且要说清删了会失去什么、不会失去什么。
    func testTheDeleteConfirmationSaysWhatIsLostAndWhatIsKept() {
        let text = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
            .deleteConfirmationText
        XCTAssertTrue(text.contains("听不到"))
        XCTAssertTrue(text.contains("复盘"))
        XCTAssertTrue(text.contains("下一步"))
    }
}
