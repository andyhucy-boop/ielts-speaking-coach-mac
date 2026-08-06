import AVFoundation
import XCTest
@testable import IELTSCoachAudio

/// 这些测试**不碰麦克风**：音频是代码里现造的正弦波。
/// 因此它们不需要任何权限，也不需要真的插着耳机去拔。
final class AACSegmentWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-aac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 造一段 440 Hz 正弦波。用真波形而不是静音，是为了让 AAC 编码器
    /// 真的有东西可编——全 0 的输入有可能被压成几乎不占空间的一段，
    /// 那样「文件里到底有没有声音」就测不出来了。
    private func tone(seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(2.0 * .pi * 440.0 * Double(index) / sampleRate)) * 0.25
        }
        return buffer
    }

    private func durationOfFile(at url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    func testWritesAPlayableFile() throws {
        let url = root.appending(path: "a.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 1.0, sampleRate: 48_000))
        let reported = writer.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // AAC 编码会加 priming 帧，长度不会分毫不差，给出容差。
        XCTAssertEqual(reported, 1.0, accuracy: 0.15)
        XCTAssertEqual(try durationOfFile(at: url), 1.0, accuracy: 0.25)
    }

    /// **这是「插拔耳机」在文件层的样子：输入采样率中途变了。**
    /// 变了还能接着往同一个文件里写，用户回听时才是连续的一条，
    /// 而不是两个半截文件。
    func testKeepsWritingIntoTheSameFileWhenTheInputFormatChanges() throws {
        let url = root.appending(path: "b.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.5, sampleRate: 48_000))
        try writer.write(tone(seconds: 0.5, sampleRate: 44_100))   // 换了设备
        let reported = writer.finish()

        XCTAssertEqual(reported, 1.0, accuracy: 0.15, "换设备前后的两段都要在同一个文件里")
        XCTAssertEqual(try durationOfFile(at: url), 1.0, accuracy: 0.25)
    }

    /// m4a 的索引（moov atom）是在文件对象释放时才写出去的。
    /// 不释放的话，播放器要么打不开这个文件，要么显示时长为 0。
    func testFileIsReadableImmediatelyAfterFinish() throws {
        let url = root.appending(path: "c.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.4, sampleRate: 48_000))
        _ = writer.finish()

        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testFinishTwiceReportsTheSameLengthAndDoesNotCorruptTheFile() throws {
        let url = root.appending(path: "d.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.4, sampleRate: 48_000))

        let first = writer.finish()
        let second = writer.finish()
        XCTAssertEqual(first, second)
        XCTAssertNoThrow(try AVAudioFile(forReading: url))
    }

    /// finish 之后再来的音频要安静地丢掉，不能崩。
    /// 真实场景：文件已经收尾了，音频线程上还有一两个缓冲区在路上。
    func testWritingAfterFinishIsHarmless() throws {
        let url = root.appending(path: "e.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.2, sampleRate: 48_000))
        _ = writer.finish()
        XCTAssertNoThrow(try writer.write(tone(seconds: 0.2, sampleRate: 48_000)))
    }

    func testUnwritableLocationFailsWithAnActionableChineseMessage() {
        let url = URL(fileURLWithPath: "/System/definitely-not-writable/x.m4a")
        XCTAssertThrowsError(try AACSegmentWriter(url: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("下一步"), "建不了文件也要告诉用户下一步做什么")
        }
    }
}
