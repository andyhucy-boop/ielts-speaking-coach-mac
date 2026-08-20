import Foundation

/// 一张 Part 2 cue card **自己那一组 Part 3 追问**。
///
/// ## 用户要的是什么
///
/// > 我练 Part two 的时候，顺带也把对应的 Part three 问题一起给练了。
///
/// 注意「对应的」三个字：真实考试里 Part 3 就是紧接着**这张卡**问下来的，
/// 不是随便挑一组讨论题。
///
/// ## 上一轮在这里判断错了
///
/// 上一轮给「Part 2 + Part 3 连着练」写的规则是「Part 3 那一半没有参考问句、
/// 要全部临场编」，理由是「题库里一张 cue card 底下只有 You should say 提示点」。
///
/// **题库重建模之后这个前提已经不成立。** 现在每张 cue card 都有一条对应的 Part 3 题
/// （`part == 3`，题干与 `topic` 都等于那张卡的原文，见 `TopicQuestions.part3`），
/// 底下挂着那一组真实追问。让考官凭空编，等于把题库里现成的真题扔掉。
///
/// ## 配对靠什么
///
/// **Part 3 题的 `topic` == Part 2 cue card 的 `prompt`。** 这不是照着描述信的：
/// 在用户本机的题库（258 题：Part 1 六十、Part 2 九十九、Part 3 九十九）上核过，
/// 99 张 cue card 的题干与 99 条 Part 3 题的 topic **一一对上，一条不差**。
///
/// 判据只认这一条，刻意不做模糊匹配（去标点、取前几个词、按话题标签靠拢）：
/// 配错一张卡的后果是考官拿着**另一张卡**的追问去问考生，而屏幕上一切正常——
/// 宁可配不上然后明说，也不要配错然后闭嘴。
public enum LinkedPart3 {

    /// 这张 cue card 对应的那条 Part 3 题；配不上返回 nil。
    ///
    /// - Parameter cueCard: 必须是 Part 2 的题。别的 Part 一律返回 nil：
    ///   Part 1 的话题题、Part 3 的题本身都没有「对应的 Part 3 追问」这回事。
    ///
    /// **要求那条题真的带着追问**（`followups` 非空）：一条空的参考题和没配上完全等价，
    /// 而把它当成配上了会让下面那句兜底提示消失——考官既没拿到问句、也没被告知要临场编。
    public static func reference(for cueCard: Question, in bank: [Question]) -> Question? {
        guard cueCard.part == 2 else { return nil }
        let key = cueCard.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return bank.first {
            $0.part == 3
                && $0.topic.trimmingCharacters(in: .whitespacesAndNewlines) == key
                && !$0.followups.isEmpty
        }
    }

    /// 反过来问：**这条 Part 3 题属于下面哪一张卡？** 配不上返回 nil。
    ///
    /// 随机抽题一场里可能有好几张卡、好几组讨论题，提示词得说清「第 2 组讨论是接着第 1 张卡的」——
    /// 说不清的话，考官只能自己猜配对，而它猜错时屏幕上一切正常。
    ///
    /// **判据与 `reference` 是同一条**（Part 3 的 `topic` == cue card 的 `prompt`），
    /// 刻意不在这里另写一份：两份判据迟早会对同一对题给出不同的答案。
    /// 这里不要求 `followups` 非空——那个条件是 `reference` 为了「配上了却没有问句
    /// 等于没配上」加的，而这里问的只是归属。
    public static func cueCard(for part3: Question, among cards: [Question]) -> Question? {
        guard part3.part == 3 else { return nil }
        let key = part3.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return cards.first {
            $0.part == 2 && $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == key
        }
    }
}
