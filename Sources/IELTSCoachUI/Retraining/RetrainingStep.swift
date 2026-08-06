import Foundation

/// 「带着本题进入复训」的三步：回看证据 → 重答原题 → 撤掉提示，开口说。
///
/// **撤掉的是答案，留下的是目标。** 原话、原答、高分版属于答案，开口前必须收走；
/// 「本次唯一目标」是一句行为指令（「回答后补一个原因和例子」），要一直留着。
/// 前者撤掉，复训才不是朗读；后者留着，复训才不是随便再练一遍。
public enum RetrainingStep: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 第一步：回看当时到底说了什么，以及复盘给的高分版长什么样。
    case evidence
    /// 第二步：提示已经撤掉，屏幕上只剩题目和这一次的唯一目标。
    case rehearsal
    /// 第三步：练习进行中，什么范答都不给看。
    case speaking

    public var id: String { rawValue }

    public var stepNumber: Int {
        switch self {
        case .evidence: return 1
        case .rehearsal: return 2
        case .speaking: return 3
        }
    }

    public var title: String {
        switch self {
        case .evidence: return "回看证据"
        case .rehearsal: return "重答原题"
        case .speaking: return "撤掉提示，开口说"
        }
    }

    /// 每一句都要同时说清「发生了什么」和「下一步做什么」（铁律 6）。
    ///
    /// **第一步这句原来不敢写「点『重答这道题』」**：那颗按钮当时还不存在（要等 Task 10 的
    /// `RetrainingFlowView`），而 `RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists`
    /// 会当场拦下——指着一颗界面上没有的按钮，比不写「下一步」还糟，用户会一直找它。
    /// Task 10 把 `Button("重答这道题")` 做出来了，所以这句改回了更具体的说法。
    /// 第二、三步指的两颗按钮（开始练习 / 我练完了）是 Phase 3 就有的，照原样保留。
    public var explanation: String {
        switch self {
        case .evidence:
            return "先看清上次到底说了什么，以及复盘给的高分版是什么样。"
                + "下一步：点「重答这道题」进入第二步，证据和高分版会被收走，只留下题目和这次的目标。"
        case .rehearsal:
            return "提示已经撤掉了——照着高分版念一遍不叫复训。"
                + "下一步：点「开始练习」，对着 ChatGPT 把这道题重新答一遍，答的时候记着这一次的目标。"
        case .speaking:
            return "练习进行中，屏幕上不会再出现任何范答。"
                + "下一步：说完之后点「我练完了」，复盘会自动取回并存档。"
        }
    }

    /// 是否显示当时说过的原话与逐字稿。
    public var showsEvidence: Bool { self == .evidence }

    /// 是否显示复盘给的高分版。**只有第一步能显示。**
    public var showsModelAnswer: Bool { self == .evidence }

    /// 是否显示「本次唯一目标」那一行。**三步都要显示**，理由见类型注释。
    public var showsGoal: Bool { true }

    /// 这一步能不能按「开始练习」。
    public var canStartPractice: Bool { self == .rehearsal }

    public var next: RetrainingStep? {
        switch self {
        case .evidence: return .rehearsal
        case .rehearsal: return .speaking
        case .speaking: return nil
        }
    }
}

/// 这一趟复训练的是原题还是换的题。
public enum RetrainingRun: String, CaseIterable, Equatable, Sendable {
    /// 重答原题。
    case original
    /// 换一道题验证。
    case transfer

    /// 换题验证**不再回看证据**：正因为不给看，才知道是不是真会了，
    /// 还是只记住了那个答案（DEFINITION-OF-DONE 第 2 节）。
    public var firstStep: RetrainingStep {
        switch self {
        case .original: return .evidence
        case .transfer: return .rehearsal
        }
    }

    public var title: String {
        switch self {
        case .original: return "带着这个目标重答原题"
        case .transfer: return "换一道题验证"
        }
    }
}
