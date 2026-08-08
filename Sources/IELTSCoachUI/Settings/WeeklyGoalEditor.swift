import IELTSCoachCore

/// 「每周训练目标」这块设置里的纯文案与取值范围。
/// 拆出来是为了能测——`View` 测不了，这几句话能测。
public enum WeeklyGoalEditor {
    /// 与落盘时的归一范围保持同一个来源。两处写死两个范围的话，
    /// Stepper 让你选 30、存下去却变成 5，用户会以为设置没生效。
    public static let range = CoachSettings.weeklyGoalRange

    public static func label(for goal: Int) -> String { "每周练 \(goal) 次" }

    /// 面板上那句「现在什么情况 + 下一步做什么」（铁律 6）。
    ///
    /// **已达标那一支不许说「还差」**：达标了还被告知「还差 -1 次」，
    /// 是这类文案最常见也最伤人的错法。
    public static func hint(done: Int, goal: Int) -> String {
        if done >= goal {
            return "本周已经练了 \(done) 次，达到目标了。"
                + "下一步：想继续练就继续，这个目标只是下限，不是上限。"
        }
        return "本周已经练了 \(done) 次，离目标还差 \(goal - done) 次。"
            + "下一步：目标定得能坚持下来，比定得高有用——定不下来的目标只会让人不想打开这个 App。"
    }
}
