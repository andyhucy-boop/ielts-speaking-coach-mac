import Foundation
import IELTSCoachCore

/// **上一场练习没有正常结束**（崩溃、误关窗口、Mac 重启）时留在盘上的那一条。
///
/// ## 它是为了补一个真实的洞
///
/// 在这之前，一场练习在用户按下「我练完了」之前**磁盘上一个字都没有**：
/// 练到一半 App 崩了或 Mac 重启，这半小时就等于没发生过——不进「本周 N/5」、
/// 学习计划不前进、题目不打「已练」，那段录音变成一个没人认领的孤儿文件。
///
/// 现在开练那一刻就在 `state.currentSession` 上占好位置
/// （`PracticeRunner.beginSessionRecord`），逐字稿每采一次存一次。
///
/// ## 为什么不自动收进训练记录
///
/// **那会替他做一个他没做的决定。** `currentSession` 里躺着的可能是：
/// 真的练到一半崩了（该留），也可能是他开了个头就去干别的了（不该留，
/// 留了会让「本周训练 3/5」凭空多一次）。这两种在数据上分不开——
/// 分得开的唯一办法是问他。
///
/// **也不自动丢掉**：那是他半小时的录音和逐字稿。
public enum UnfinishedSession {

    /// 值得拿出来问用户的那一条；没有就是 nil。
    ///
    /// **必须有逐字稿才算数。** 一条什么都没采到的记录（开练几秒就崩了）拿出来问，
    /// 用户点「存下来」得到的是一条空记录，比不问更让人困惑。
    public static func pending(in state: CoachState) -> PracticeSession? {
        guard let session = state.currentSession, !session.transcript.isEmpty else { return nil }
        return session
    }

    /// 那张卡片上说什么。
    ///
    /// 三样一个不少：**发生了什么**（哪一天、练的哪道题、采到几条）、
    /// **下一步做什么**（两颗按钮各是什么后果）、以及**它现在还在**——
    /// 不说最后这一句的话，用户会以为东西已经丢了，那两颗按钮就没人敢按。
    public static func notice(for session: PracticeSession, in state: CoachState,
                              calendar: Calendar = .current) -> String {
        let day = CoachTime.parse(session.startedAt)
            .map { CoachTime.dayString($0, calendar: calendar) } ?? "时间不详"
        let question = state.questions.first { $0.id == session.questionId }?.prompt
        let about = question.map { "练的是「\($0)」。" } ?? ""
        return "上一场练习没有正常结束（\(day)）。\(about)"
            + "已经采到 \(session.transcript.count) 条对话，都还在，一个字没丢。"
            + "下一步：点「存进训练记录」把它收下（会算进本周次数，但它没有复盘报告）；"
            + "或者点「丢掉这一场」——那之后这条记录就没了，"
            + "而已经归进错题本和词汇本的内容不受影响。"
    }

    /// 把它收进正式的训练记录。
    ///
    /// **`endedAt` 用「最后一次采到逐字稿的时间」，不是现在。**
    /// 用现在的话，一场昨天崩掉的练习会被算成「从昨天练到今天」，
    /// 而首页那个「本周开口时长」会当场多出十几个小时——
    /// 那正是 `TrainingStats` 里那条「超过 2 小时按 2 小时计」在兜的坑，
    /// 这里不该再往里扔一次。采不到时间时留空，
    /// 首页会如实说「有 N 场没有结束时间，没算进去」。
    public static func keep(_ session: PracticeSession, in state: inout CoachState) {
        var kept = session
        kept.endedAt = session.transcript.last?.capturedAt ?? ""
        guard !state.sessions.contains(where: { $0.id == kept.id }) else {
            state.currentSession = nil
            return
        }
        state.sessions.append(kept)
        state.currentSession = nil
    }

    /// 丢掉它。**只动 `currentSession` 这一处**——错题本、词汇本里已经归档的内容
    /// 不属于这一条，卡片上那句话也是这么承诺的。
    public static func discard(in state: inout CoachState) {
        state.currentSession = nil
    }
}
