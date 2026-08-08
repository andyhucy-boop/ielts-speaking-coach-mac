import Foundation
import IELTSCoachCore

/// 一次采样的结果。
public struct TranscriptSweep: Equatable, Sendable {
    public let fragments: [TranscriptFragment]
    /// 这一次没读到时的中文原因。**非 nil 不代表练习出错**——
    /// 逐字稿是增强，不是必需，调用方只需记账并继续。
    ///
    /// 这句话最终会原样出现在 `TranscriptAssembler.completenessNote` 的
    /// 「最后一次的原因：……」里给用户看，所以必须是中文、必须说清读不到的是什么。
    /// 「下一步做什么」由 `completenessNote` 统一给出，这里只说「发生了什么」，
    /// 否则用户会看到两句叠在一起的「下一步」。
    public let failure: String?

    public init(fragments: [TranscriptFragment], failure: String? = nil) {
        self.fragments = fragments
        self.failure = failure
    }

    public static let unavailable = TranscriptSweep(
        fragments: [],
        failure: "没能读到 ChatGPT 的界面内容（无障碍树是空的）")
}

/// 逐字稿采样的接缝。
///
/// **刻意不挂在 `CoachBridge` 上。** 给已有 protocol 加一个带默认实现的方法，
/// 等于埋一个静默失败：某个假实现忘了实现它，默认实现返回空，测试照样绿，
/// 而逐字稿永远是空的。做成独立 protocol 并由 `PracticeRunner` 注入，
/// 与 Phase 5 注入录音器的做法一致。
public protocol TranscriptSampling: Sendable {
    /// 采一次样。**绝不抛错**：读不到就把原因放进 `TranscriptSweep.failure`。
    func sample() -> TranscriptSweep
}
