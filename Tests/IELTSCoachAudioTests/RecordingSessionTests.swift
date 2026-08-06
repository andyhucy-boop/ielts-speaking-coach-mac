import AVFoundation
import XCTest
@testable import IELTSCoachAudio

/// 可以拨的假时钟。中断记录的是「什么时候断的」，拿真实时间断言不了。
/// 只被测试线程碰，所以 `@unchecked Sendable` 在这里成立。
private final class TestClock: @unchecked Sendable {
    private(set) var now: Date
    init(_ start: Date) { now = start }
    func advance(_ seconds: TimeInterval) { now += seconds }
    func read() -> Date { now }
}

final class RecordingSessionTests: XCTestCase {
    private let relativePath = "recordings/2026-08-06T10-45-30Z.m4a"
    /// 2026-08-06T10:45:30Z，与 relativePath 里的文件名对得上。
    ///
    /// **计划里写的是 1_785_931_530，那个数是错的**——它对应 2026-08-05T12:05:30Z，
    /// 跟它自己的注释差了近一天（Task 3 的 `RecordingStoreTests` 已经记过同一处）。
    /// 本任务的 relativePath 是显式传进去的，用错的数也不会红，但没有理由把一个
    /// 已知错误的常量再抄一遍。
    private let startInstant = Date(timeIntervalSince1970: 1_786_013_130)
    private var root: URL!
    private var fileURL: URL!
    private var engine: FakeCaptureEngine!
    private var writer: FakeSegmentWriter!
    private var clock: TestClock!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "2026-08-06T10-45-30Z.m4a")
        engine = FakeCaptureEngine()
        writer = FakeSegmentWriter()
        clock = TestClock(startInstant)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession() -> RecordingSession {
        let writer = self.writer!
        let clock = self.clock!
        return RecordingSession(
            engine: engine,
            // 真实的写入器会在这里建出文件，假的也要建——
            // 否则「0 秒录音要把空文件删掉」那条根本测不到。
            writerFactory: { url in
                FileManager.default.createFile(atPath: url.path, contents: Data())
                return writer
            },
            fileURL: fileURL,
            relativePath: relativePath,
            clock: { clock.read() })
    }

    // MARK: - 正常路径

    func testBuffersReachTheWriter() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        engine.deliver(makePCMBuffer())
        XCTAssertEqual(writer.writtenCount, 2)
    }

    func testFinishReturnsThePathAndDuration() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, relativePath)
        XCTAssertEqual(outcome.duration, 12)
        XCTAssertNil(outcome.warning, "一切正常时不该拿警告去打扰用户")
        XCTAssertTrue(outcome.interruptions.isEmpty)
        XCTAssertEqual(writer.finishCount, 1)
        // 计划外补的一条断言：录到东西的文件**必须留在磁盘上**。
        // 少了它，「收尾时无条件删文件」这种改法能让上面每一条都绿着通过，
        // 而用户点开回听时文件已经没了。
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "录到了东西却把文件删了，用户练完什么都拿不到")
    }

    // MARK: - 插拔耳机（本阶段的核心风险）

    /// 换了输入设备之后必须重新启动采集。
    /// 不重启的话，后面用户说的每一句都录不到，而且不会抛任何错误——
    /// 用户练完点开回听，只有前三分钟。
    func testUnpluggingHeadphonesRestartsCaptureAndKeepsTheSameFile() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer(sampleRate: 48_000))

        engine.unplugHeadphones()
        engine.deliver(makePCMBuffer(sampleRate: 44_100))   // 新设备的采样率变了

        XCTAssertEqual(engine.startCount, 2, "换设备后必须重新启动采集")
        XCTAssertEqual(writer.writtenCount, 2, "换设备之后送来的音频也要写进去")
        XCTAssertEqual(writer.finishCount, 0, "能接回来就不该关文件——换设备不该换文件")
    }

    /// 接回来了也**必须**告诉用户：切换的那一两秒确实没录到。
    /// 「悄悄少了一段」同样是静默失败——用户回听时会以为自己当时没说话。
    func testRecoveredInterruptionIsStillReportedToTheUser() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        engine.unplugHeadphones()
        engine.deliver(makePCMBuffer())

        let outcome = session.finish()
        XCTAssertEqual(outcome.interruptions.count, 1)
        XCTAssertTrue(outcome.interruptions[0].recovered)
        let warning = try XCTUnwrap(outcome.warning, "中断过却什么都不说，用户永远不知道少了一段")
        XCTAssertTrue(warning.contains("耳机"), "要说人话，用户能对上号的是「插拔耳机」")
        XCTAssertTrue(warning.contains("下一步"))
        XCTAssertEqual(outcome.relativePath, relativePath, "接上了就还是同一条录音")
    }

    /// 拔出来再插回去是两次设备变化，真机验收（Task 11 Step 5）走的就是这条路。
    /// 三段音频必须都在**同一个文件**里，用户听到的才是连续的一条，
    /// 而不是三个半截文件。
    func testTwoDeviceSwitchesStillProduceOneContinuousRecording() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer(sampleRate: 48_000))

        engine.unplugHeadphones()                             // 拔掉
        engine.deliver(makePCMBuffer(sampleRate: 44_100))

        engine.unplugHeadphones()                             // 插回去
        engine.deliver(makePCMBuffer(sampleRate: 48_000))

        XCTAssertEqual(engine.startCount, 3, "每一次设备变化都要重新启动采集")
        XCTAssertEqual(writer.writtenCount, 3, "三段音频一段都不能少")
        XCTAssertEqual(writer.finishCount, 0, "中途一次都不该关文件")

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, relativePath, "两次切换之后仍然只有一条录音")
        XCTAssertEqual(outcome.interruptions.count, 2, "两次切换要各记一条，不能只记第一条")
        XCTAssertTrue(outcome.interruptions.allSatisfy(\.recovered))
        XCTAssertEqual(writer.finishCount, 1)
    }

    /// 每一次中断都要记下**它自己发生的那一刻**。
    /// 时钟是注入的就是为了这个：拿 `Date()` 现取的话，两次中断会记成几乎同一时刻，
    /// 用户想对着录音找那两个断点时就对不上了。
    func testEachInterruptionRecordsTheMomentItHappened() throws {
        let session = makeSession()
        try session.start()

        clock.advance(30)
        engine.unplugHeadphones()
        clock.advance(45)
        engine.unplugHeadphones()

        let outcome = session.finish()
        XCTAssertEqual(outcome.interruptions.map(\.at),
                       [startInstant.addingTimeInterval(30), startInstant.addingTimeInterval(75)])
    }

    /// 接不回来时，**已经录到的部分必须当场落盘**。
    /// 练了半小时换来的录音，不能跟着一个错误一起蒸发。
    func testFailedRecoveryClosesTheFileSoAudioSoFarSurvives() throws {
        engine.failStartAtCall = 2      // 第一次 start 成功，重启时失败
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        engine.unplugHeadphones()

        XCTAssertEqual(writer.finishCount, 1,
                       "接不回来就要立刻把文件关好，而不是等着跟错误一起丢掉")

        let outcome = session.finish()
        XCTAssertEqual(writer.finishCount, 1, "文件不能被关第二次")
        XCTAssertEqual(outcome.relativePath, relativePath, "录到一半也是录音，路径必须给出来")
        XCTAssertEqual(outcome.duration, 12)
        XCTAssertEqual(outcome.interruptions.count, 1)
        XCTAssertFalse(outcome.interruptions[0].recovered)
        let warning = try XCTUnwrap(outcome.warning)
        XCTAssertTrue(warning.contains("下一步"))
        // 计划外补的一条断言：路径给了，文件就得真的在。
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "报了一条路径却没有文件，用户点开回听会以为程序坏了")
    }

    /// 接不回来、文件已经关掉之后，再插拔耳机**不能**把采集重新拉起来。
    ///
    /// 拉起来的后果不是崩溃，是骗人：写入器已经关了，后面采到的音频全部落空，
    /// 界面上却会多出一句「已经自动接上继续录」。
    func testNothingRestartsAfterAFailedRecovery() throws {
        engine.failStartAtCall = 2
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        engine.unplugHeadphones()          // 接不回来，文件关掉

        engine.unplugHeadphones()          // 设备还在抖，又变了一次

        XCTAssertEqual(engine.startCount, 2, "文件都关了还去重启采集，录到的东西没人收")
        XCTAssertEqual(writer.finishCount, 1, "文件不能被关第二次")

        let outcome = session.finish()
        XCTAssertEqual(outcome.interruptions.count, 1, "已经收尾了就不该再记新的中断")
        XCTAssertFalse(try XCTUnwrap(outcome.warning).contains("已经自动接上"),
                       "文件已经关了，绝不能告诉用户「已自动接上继续录」")
    }

    // MARK: - 其他失败

    func testWriteFailureStopsRecordingButKeepsWhatWasWritten() throws {
        let session = makeSession()
        try session.start()
        writer.failOnWrite = true
        engine.deliver(makePCMBuffer())

        XCTAssertEqual(writer.finishCount, 1, "写失败也要先把文件关好再说")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1, "写不进去了就别再采了")

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, relativePath)
        XCTAssertTrue(try XCTUnwrap(outcome.warning).contains("下一步"))
    }

    /// 写失败之后，音频线程上还在路上的缓冲区不能再往已经关掉的文件里塞，
    /// 也不能让同一条警告在界面上叠成一堵墙。
    func testWriteFailureIsReportedOnceEvenWhenMoreAudioKeepsArriving() throws {
        let session = makeSession()
        try session.start()
        writer.failOnWrite = true
        engine.deliver(makePCMBuffer())

        writer.failOnWrite = false         // 后面的缓冲区就算能写也不许写了
        engine.deliverAfterStop(makePCMBuffer())
        engine.deliverAfterStop(makePCMBuffer())

        XCTAssertEqual(writer.writtenCount, 0, "文件已经关了，后面的音频不能再往里写")
        XCTAssertEqual(writer.finishCount, 1, "文件不能被关第二次")

        let warning = try XCTUnwrap(session.finish().warning)
        XCTAssertEqual(warning.components(separatedBy: "录音在中途写不下去了").count - 1, 1,
                       "同一次写失败只说一遍，不要在界面上刷屏")
    }

    /// 计划里这条的理由写的是「否则 recordings 里会留一个孤儿」，那句不准确：
    /// 关文件不会删文件，0 字节的空文件照样留着（谁来收拾见实现里的注释）。
    /// 这条真正守的是「句柄不能吊着」——不关的话 m4a 索引写不出去。
    func testStartFailureDoesNotLeaveAnOpenFile() {
        engine.failStartAtCall = 1
        let session = makeSession()
        XCTAssertThrowsError(try session.start())
        XCTAssertEqual(writer.finishCount, 1, "采集起不来时要把刚建出来的文件关掉")
    }

    /// 一秒都没录到时不能给出一个「看起来有录音」的路径——
    /// 那会让训练记录页显示一个点了没声音的播放器，用户只会以为程序坏了。
    func testSilentRecordingReportsItInsteadOfHandingBackAnEmptyFile() throws {
        writer.secondsToReport = 0
        let session = makeSession()
        try session.start()

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, "")
        XCTAssertTrue(try XCTUnwrap(outcome.warning).contains("下一步"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "0 秒的空文件不该留在 recordings 里占位置")
    }

    func testFinishIsIdempotent() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        let first = session.finish()
        let second = session.finish()
        XCTAssertEqual(first, second)
        XCTAssertEqual(writer.finishCount, 1, "重复调用 finish 不能把文件关两次")
    }

    /// 收尾之后音频线程上还有一两个缓冲区在路上（真实场景，不是假设）。
    /// 它们必须被安静丢掉：文件已经关了，再写进去要么崩，要么写坏索引。
    func testBuffersArrivingAfterFinishAreDroppedNotWritten() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        let outcome = session.finish()
        engine.deliverAfterStop(makePCMBuffer())    // 收尾之后才到的

        XCTAssertEqual(writer.writtenCount, 1, "文件已经关了，后到的音频不能再写进去")
        XCTAssertEqual(writer.finishCount, 1)
        XCTAssertEqual(session.finish(), outcome, "后到的音频不该改变已经给出的结果")
    }

    /// 收尾之后再插拔耳机（用户练完顺手把耳机拔了）不能把采集重新拉起来。
    ///
    /// 真实链路上拦住它的是「收尾时把自己从采集器上摘下来」那一行：
    /// `AVAudioEngineCapture` 的通知观察者活到 deinit 为止，练完之后系统照样会发
    /// 设备变化通知，摘不干净就会调到一个已经收尾的 session 上。
    func testUnpluggingAfterFinishDoesNotRestartCapture() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        let outcome = session.finish()

        XCTAssertNil(engine.onConfigurationChange, "收尾时必须把自己从采集器上摘下来")
        engine.unplugHeadphones()

        XCTAssertEqual(engine.startCount, 1, "已经收尾了还去重启采集，等于凭空打开麦克风")
        XCTAssertEqual(session.finish(), outcome, "收尾之后的设备变化不该改变结果")
    }
}
