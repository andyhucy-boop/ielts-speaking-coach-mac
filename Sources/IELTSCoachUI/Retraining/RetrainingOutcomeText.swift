import Foundation
import IELTSCoachCore

/// 换题验证结果的文案。
///
/// **措辞上限是「这一次没有再被点名」。** 不许升级成「已掌握」「已改掉」这类结论：
/// ChatGPT 可能换个 id 说同一件事，也可能这次碰巧没抓到。给一个看起来精确、
/// 实则站不住的结论，会让人盯着结论而不是盯着问题——与「不预测雅思分数」
/// 是同一条原则（DEFINITION-OF-DONE 第 4 节）。
///
/// 「毛病有没有真的变少」由 Phase 7 的问题档案按出现次数的趋势回答，
/// 不由这里的单场结论回答。
public enum RetrainingOutcomeText {
    public static func headline(for outcome: RetrainingOutcome) -> String {
        switch outcome {
        case .noReport: return "这一场还没有可对照的复盘"
        case .namedAgain: return "这个目标又被点了一次"
        case .notNamedAgain: return "这一次没有再被点名"
        }
    }

    public static func detail(for outcome: RetrainingOutcome) -> String {
        switch outcome {
        case .noReport:
            return "复盘还没取回来，或取回的内容不成形，所以判断不了这次表现。"
                + "下一步：到「复盘报告」页看看这一场的报告在不在；不在的话可以重新生成一次复盘。"
        case .namedAgain:
            return "ChatGPT 在这次的复盘里又把同一个目标挑了出来，说明它还在。"
                + "下一步：再换一道题练一次，或者回到证据看看这次和上次差在哪。"
        case .notNamedAgain:
            return "ChatGPT 这次的复盘没有再挑出这个目标。"
                + "注意它换个说法描述同一件事也是可能的，一次结果说明不了全部。"
                + "下一步：再换一道题练一次会更有把握；也可以到「问题档案」看这个毛病的出现次数在怎么变。"
        }
    }
}
