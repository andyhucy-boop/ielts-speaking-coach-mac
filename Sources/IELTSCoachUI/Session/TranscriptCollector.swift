import ChatGPTBridge
import Foundation
import IELTSCoachCore
import Observation

/// 练习进行中的逐字稿收集。
///
/// 只负责「采一次样 → 并进拼接器 → 失败就记账」，**节拍由 `PracticeRunner` 驱动**
/// （它拿一个 Task 每隔几秒调一次 `tick()`）。把定时器留在外面，是为了让这个类
/// 100% 同步、100% 可测——定时器会让测试变成靠 sleep 碰运气。
///
/// **本类型的每一个方法都不抛错。** 逐字稿是增强，不是必需，
/// 采样失败不得中断练习（ROADMAP 3.2）。但也绝不静默：练完之后 `notice` 会
/// 如实说明缺了什么、下一步做什么。
@MainActor
@Observable
public final class TranscriptCollector {
    private let sampler: (any TranscriptSampling)?
    private let now: @Sendable () -> Date
    private var assembler = TranscriptAssembler()

    public private(set) var isCollecting = false
    public private(set) var turns: [PracticeSession.TranscriptTurn] = []
    /// 逐字稿不完整时的中文说明。**非 nil 时界面必须显示它。**
    public private(set) var notice: String?
    public private(set) var samplingFailureCount = 0

    /// - Parameter sampler: 传 nil 表示用户在设置里关掉了「记录对话逐字稿」。
    ///   此时本类型安静地什么都不做——不报错、不留提示。
    ///   **不要把「用户主动关掉」渲染成警告**，那是在为用户自己的选择报警。
    public init(sampler: (any TranscriptSampling)?,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.sampler = sampler
        self.now = now
    }

    /// 采一次样当背景板，然后开始收集。在练习进入 `.practicing` 那一刻调用。
    public func begin() {
        guard let sampler else { return }
        let sweep = sampler.sample()
        if let failure = sweep.failure {
            assembler.noteSamplingFailure(failure)
            samplingFailureCount += 1
        } else {
            assembler.seedBaseline(sweep.fragments)
        }
        isCollecting = true
        refresh()
    }

    /// 采一次样并并入。**绝不抛错。**
    public func tick() {
        guard isCollecting, let sampler else { return }
        let sweep = sampler.sample()
        if let failure = sweep.failure {
            assembler.noteSamplingFailure(failure)
            samplingFailureCount += 1
        } else {
            assembler.ingest(sweep.fragments, at: now())
        }
        refresh()
    }

    /// 最后再采一次样，然后停。
    ///
    /// **必须在发复盘请求之前调用。** 晚一步的话，复盘那一大坨 JSON 会被采进逐字稿里。
    public func finish() {
        guard isCollecting else { return }
        tick()
        isCollecting = false
        refresh()
    }

    /// 练习失败或被取消时停止收集。**已经采到的内容在这个对象里一个字都不丢**——
    /// 用户练到一半出错，前面说过的话仍然是他的练习记录。
    ///
    /// **但这不等于它一定会被存下来。** 这个类只管「采到了什么」，
    /// 「这一场进不进训练记录」是 `PracticeRunner` 的事：中途取消时那一场根本不落盘，
    /// 采到的话就地丢掉。所以下面那句「下一步」**不许承诺它会被存进训练记录**——
    /// 复审第 6 条实测：这里原来写着「仍然会存进「训练记录」，不会丢」，
    /// 而取消路径上的实现与它正相反。留没留下由放弃时那段交代逐字说明。
    public func abandon(reason: String) {
        guard isCollecting else { return }
        isCollecting = false
        // 这一句照计划保留，但**它当前打不出任何差别**：`isCollecting == true` 意味着
        // `begin()` 跑过，而 `begin()` 与 `tick()` 每次都以 `refresh()` 收尾，
        // 所以走到这里时 `turns` 与 `notice` 一定已经是最新的。
        // 计划 Task 5 突变表第 5 行说「删掉它 testAbandonKeepsWhatWasAlreadyCollected 会变红」，
        // 实测不会（2026-08-06 逐条跑过）。留着是为了将来 `abandon` 被挪到别处调用时不出错，
        // 真正有牙齿的是下面那句 `existing`——它保住了已经记下的采样失败说明。
        refresh()
        let existing = notice.map { $0 + " " } ?? ""
        notice = existing + "这一场没有正常走完：\(reason) "
            + "已经记下的 \(turns.count) 条对话就到这里为止，后面没有再采样。"
            + "下一步：这几条对话留没留下，看这一屏上那段「这一场已经放弃了…」的交代，那里逐条写明了。"
    }

    private func refresh() {
        turns = assembler.turns
        notice = assembler.completenessNote
    }
}
