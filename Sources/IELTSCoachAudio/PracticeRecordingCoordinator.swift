import AVFoundation
import Foundation
import IELTSCoachCore

/// 一次练习开始时，录音到底有没有跑起来。
public enum RecordingBeginOutcome: Equatable, Sendable {
    case started(relativePath: String)
    /// 用户没开开关。**这是默认状态，不是故障**——界面不该为它报警，
    /// 也不该显示「正在录音」。
    case skippedByUser
    /// 想录但录不了。message 是中文，写明了发生了什么与下一步做什么。
    /// **界面必须显示它**：用户以为在录，实际没录，不说就是骗人。
    case failed(String)
}

/// 给 `PracticeRunner` 用的接口：开练时调一次 `begin`，收尾时调一次 `finish`。
/// 做成 protocol 是为了让 `PracticeRunner` 的测试可以用假实现，
/// 不必真去开麦克风。
public protocol PracticeRecording: AnyObject {
    func begin(startedAt: Date) -> RecordingBeginOutcome
    /// 结束录音。**无论练习成功还是失败都必须调用**——练到一半出错时，
    /// 已经录下的部分不能跟着一起丢。没在录时返回 nil，且必须无害。
    func finish() -> RecordingOutcome?
}

public final class PracticeRecordingCoordinator: PracticeRecording, @unchecked Sendable {
    public typealias EngineFactory = @Sendable () -> AudioCaptureEngine
    public typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter

    private let store: RecordingStore
    /// 练习开始那一刻的开关快照。中途去设置里改开关不影响正在进行的这一场——
    /// 文件已经在写了，半路停下来只会得到一条莫名其妙截断的录音。
    private let settings: CoachSettings
    private let permission: MicrophonePermissionState
    private let engineFactory: EngineFactory
    private let writerFactory: WriterFactory

    private let lock = NSLock()
    private var session: RecordingSession?

    public init(store: RecordingStore,
                settings: CoachSettings,
                permission: MicrophonePermissionState,
                engineFactory: @escaping EngineFactory = { AVAudioEngineCapture() },
                writerFactory: @escaping WriterFactory = { try AACSegmentWriter(url: $0) }) {
        self.store = store
        self.settings = settings
        self.permission = permission
        self.engineFactory = engineFactory
        self.writerFactory = writerFactory
    }

    public func begin(startedAt: Date) -> RecordingBeginOutcome {
        // 顺序有意义：先看用户的意愿，再看系统的许可。开关关着时连采集器都不造——
        // 造了就会在系统的「最近使用麦克风」里留下记录，而用户根本没开这个功能。
        switch RecordingConsent.readiness(settings: settings, permission: permission) {
        case .disabledByUser:
            return .skippedByUser
        case .blocked(let message):
            return .failed(message)
        case .ready:
            break
        }

        // 记下这次挑中的文件名：起不来的时候要回头把它收拾掉，理由见 `discardEmptyFile`。
        var reserved: (url: URL, relativePath: String)?
        do {
            try store.directory.createIfNeeded()
            let taken = Set(try store.existingFileNames())
            let name = RecordingStore.fileName(startedAt: startedAt, taken: taken)
            let relative = store.relativePath(fileName: name)
            let url = try store.url(forRelativePath: relative)
            reserved = (url, relative)

            let made = RecordingSession(engine: engineFactory(),
                                        writerFactory: writerFactory,
                                        fileURL: url,
                                        relativePath: relative)
            try made.start()
            lock.lock(); session = made; lock.unlock()
            return .started(relativePath: relative)
        } catch {
            var message = "这次练习没能开始录音：\(error.localizedDescription)"
                + "\n练习本身不受影响，可以照常练完。"
                + "下一步：练完之后到「录音设置」（⌘,）检查麦克风权限与磁盘空间。"
            if let reserved, let leftover = discardEmptyFile(at: reserved.url,
                                                            relativePath: reserved.relativePath) {
                message += "\n" + leftover
            }
            return .failed(message)
        }
    }

    public func finish() -> RecordingOutcome? {
        lock.lock()
        let current = session
        session = nil
        lock.unlock()
        return current?.finish()
    }

    // MARK: - 私有

    /// 收拾起不来的那一次留下的空文件。返回值非 nil 时是要接在失败说明后面的一段话。
    ///
    /// **为什么这件事在这里做：** 写入器一建出来，文件就已经在磁盘上了；
    /// `RecordingSession.start()` 抛错时只把它**关掉**（不关，m4a 的索引写不出去、
    /// 文件对象一直吊着），**关掉不等于删掉**。而删空文件的逻辑长在 `finish()` 里，
    /// `start()` 抛错的这条路上没人会去调 `finish()`——`begin()` 直接返回 `.failed` 了。
    /// 留着它的代价不是几个字节：`RecordingStore.usage()` 会把它算进录音占用，
    /// `orphanFileNames`（明写「不主动删」）会把它当成孤儿报出来，于是一次都没录成的用户
    /// 会在「录音设置」里看到「有 1 个孤儿录音占着地方」。
    ///
    /// **只动这一次刚挑出来的那个文件名。** 它是按「没被别人占用」挑出来的
    /// （`RecordingStore.fileName(startedAt:taken:)`），因此绝不会是上一场已经录好的录音。
    ///
    /// 删不掉时不装作没事：那个文件确实还占着地方，用户过会儿就会在占用统计和孤儿列表里
    /// 看到它，这里不说清楚，那两处就成了没头没尾的报警。
    private func discardEmptyFile(at url: URL, relativePath: String) -> String? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        do {
            try manager.removeItem(at: url)
            return nil
        } catch {
            return "另外，这次建出来的空录音文件 \(relativePath) 没能删掉："
                + "\(error.localizedDescription)。"
                + "它会被算进录音占用，也会在「录音设置」里被当成孤儿录音报出来。"
                + "下一步：到「录音设置」（⌘,）点「打开录音文件夹」，手工把它删掉。"
        }
    }
}
