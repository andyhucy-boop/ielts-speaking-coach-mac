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

    /// **写盘失败不许被一句「录音已删除」盖过去（铁律 7）。**
    ///
    /// 文件删掉了、训练记录却没更新上时，那条 `recordingPath` 还指着一个已经不存在的文件。
    /// 此时报「录音已删除。这次练习的题目、逐字稿和复盘都还在」是两重的谎：
    /// 记录压根没更新，界面上还画着一颗按下去会哑掉的播放键。
    /// 用户下次打开训练记录看到的是「录音文件找不到了」，而他刚刚被告知一切正常。
    func testAFailedRecordUpdateIsNotPaintedOverWithSuccess() throws {
        try makeRecordingFile("a.m4a")
        // state.json 变成读不出来的东西：`store.mutate` 必然抛错，而 recordings 目录完好，
        // 音频文件照样删得掉——这正是「文件没了、记录还指着它」那一半失败。
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
        viewModel.delete()

        let notice = try XCTUnwrap(viewModel.notice, "写盘失败却一声不吭")
        XCTAssertFalse(notice.contains("录音已删除"),
                       "训练记录没更新上，却告诉用户「录音已删除，其他都还在」——"
                           + "这正是铁律 7 点名禁止的形态：写盘失败被吞掉之后照样报成功。"
                           + "实际说的是：" + notice)
        XCTAssertTrue(notice.contains("训练记录没能更新"),
                      "没说清是「文件删了、记录没更新」，用户不知道自己现在处在什么状态："
                          + notice)
        XCTAssertTrue(notice.contains("下一步"), "只说失败不说下一步不算合格：" + notice)

        // **界面画的东西必须和磁盘现状对得上。** 文件已经没了，还停在 `.ready` 的话，
        // 训练记录页上摆着一颗能按的播放键，按下去只会得到「这个录音文件打不开」。
        guard case .missing(let message) = viewModel.state else {
            return XCTFail("音频文件已经删掉了，播放器却还停在 \(viewModel.state)——"
                           + "界面上那颗播放键按下去必然是哑的")
        }
        XCTAssertTrue(message.contains("找不到"), message)
    }

    /// 「清除这条录音记录」这一颗按下去写盘失败时，同样必须说出来，且状态不能假装清干净了。
    ///
    /// 没有这一条的话，`clearReferenceOnly()` 里那个 catch 分支整个删掉、
    /// 或者改成无条件 `state = .none`，都不会有人红：按钮按一下卡片就消失了，
    /// 用户以为清掉了，下次打开训练记录「找不到了」原样回来。
    func testAFailedClearSaysSoInsteadOfPretendingTheReferenceIsGone() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))
        let cleared = viewModel.clearReferenceOnly()

        XCTAssertFalse(cleared, "记录根本没更新成功，却回报说清干净了")
        let notice = try XCTUnwrap(viewModel.notice, "清不掉却一声不吭")
        XCTAssertTrue(notice.contains("训练记录没能更新"), notice)
        XCTAssertTrue(notice.contains("下一步"), "只说失败不说下一步不算合格：" + notice)
        guard case .missing = viewModel.state else {
            return XCTFail("记录里那条指向还在，界面却当作已经清干净了（\(viewModel.state)）——"
                           + "用户下次打开会发现「找不到了」原样回来")
        }
    }

    /// 顺利清掉时要回报成功，否则 `delete()` 永远不敢说「已删除」。
    func testASuccessfulClearReportsSuccess() throws {
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/gone.m4a")] }
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))

        XCTAssertTrue(viewModel.clearReferenceOnly(), "记录明明更新成功了却回报失败")
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
