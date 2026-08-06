import Foundation

/// `AVAudioEngineCapture` 的串行工作台：装 tap、拆 tap、开引擎、停引擎，
/// 以及采集器内部那两位可变状态（`tapped` / `observer`），全部排在这一条队列上。
///
/// 它同时解决两个问题，两个都是实打实会发生的，不是洁癖：
///
/// ## 一、不能在 tap 回调里同步停引擎
///
/// `AudioCaptureEngine.stop()` 的契约明写「可能在 onBuffer 回调里被调用」——
/// 磁盘写满时 `AACSegmentWriter.write` 抛错，`RecordingSession.append` 当场收摊，
/// 那句 `engine.stop()` 就在 tap 回调里。而 `AVAudioEngine.stop()` 与
/// `removeTap(onBus:)` 会等当前这条 tap 回调返回（`RecordingSession` 的注释里
/// 也是这么写的，它不握锁去 stop 正是为了这个）。就地做就是「在 tap 回调里等
/// tap 回调结束」：麦克风一直开着，用户连「我练完了」都点不动。
///
/// 所以 `performOffTheTapThread` 在身处 tap 回调时把活挪到队列上异步做，
/// 别的线程上仍然是「做完再返回」——用户点「我练完了」时，`finish()` 里的
/// `engine.stop()` 返回时麦克风必须是真的关了。
///
/// ## 二、`stop()` 与 `start()` 真的会撞上
///
/// 设备变化的通知走主线程（观察者注册在 `queue: .main`，所以
/// `RecordingSession.handleConfigurationChange` 里的 stop/start 在主线程跑），
/// 写盘失败后的收摊走音频线程。`RecordingSession` 只保证「finish() 会等设备变化
/// 处理完」，**不保证**这两条线互不相撞。撞上之后 `tapped` 会被撕裂：轻则
/// `removeTap` 被调两次，重则 tap 已经装上而 `tapped` 还是 false——此后 `stop()`
/// 直接返回，练习结束了输入节点上还挂着一个 tap，麦克风灯不灭。
///
/// ## 使用者必须守住的那一条
///
/// **tap 回调不得阻塞在这条队列上。** 队列上的活会等 tap 回调返回，tap 回调再回头
/// 等队列，就是死锁。`performOffTheTapThread` 已经替 `stop()` 守住了；
/// `perform` 是同步的，调用方要先用 `isInsideTapCallback` 判断（`start()` 就是这么做的）。
final class CaptureWorkQueue: Sendable {
    private let queue = DispatchQueue(label: "com.ielts-speaking-coach.audio-capture")
    /// 每个实例一把自己的钥匙：同时活着两个采集器时，谁的 tap 回调是谁的。
    private let markKey: String

    init() {
        markKey = "IELTSCoachAudio.insideTapCallback.\(UUID().uuidString)"
    }

    /// 当前**这条线程**是不是正在跑一条 tap 回调。
    ///
    /// 刻意用线程局部存储而不是一个实例上的开关：音频线程正在跑 tap 回调，
    /// 不代表界面线程也在。做成全局开关的话，用户点「我练完了」时 `stop()` 会
    /// 误以为自己身处 tap 回调而改成异步，`finish()` 返回时麦克风还开着。
    var isInsideTapCallback: Bool {
        Thread.current.threadDictionary[markKey] != nil
    }

    /// 把活做完再返回。
    ///
    /// **不得在 tap 回调里调用**：队列上的活会等 tap 回调返回，反过来等就是死锁。
    /// 调用方自己用 `isInsideTapCallback` 判断；停引擎那条路径请直接用
    /// `performOffTheTapThread`，它已经替你判断过了。
    func perform<T>(_ body: () throws -> T) rethrows -> T {
        try queue.sync(execute: body)
    }

    /// 能就地做完就就地做完，正身处 tap 回调时挪到队列上异步做。
    ///
    /// 「异步」只是换个线程做，不是不做：活仍然排在同一条队列上，
    /// 与装 tap / 拆 tap 保持先来后到。
    func performOffTheTapThread(_ body: @escaping @Sendable () -> Void) {
        if isInsideTapCallback {
            queue.async(execute: body)
        } else {
            queue.sync(execute: body)
        }
    }

    /// 给当前线程打上「正在跑 tap 回调」的标记，`body` 一返回就摘掉。
    ///
    /// 摘这一下不能省：音频线程是被复用的，标记留在上面的话，这条线程往后
    /// 每一次 `stop()` 都会被当成「在 tap 回调里」而推迟。
    /// 不支持嵌套——tap 回调不会套着自己跑。
    func markingTapCallback<T>(_ body: () -> T) -> T {
        let dictionary = Thread.current.threadDictionary
        dictionary[markKey] = true
        defer { dictionary.removeObject(forKey: markKey) }
        return body()
    }
}
