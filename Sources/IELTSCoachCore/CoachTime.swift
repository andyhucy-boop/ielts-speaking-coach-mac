import Foundation

/// 时间戳解析。**项目里所有「字符串变时间」都必须走这里，不要各处 new formatter。**
///
/// 原因：`ISO8601DateFormatter` 的默认选项是 `.withInternetDateTime`，
/// 解析不了带小数秒的时间戳。项目里的时间戳来自多处写法，
/// 一处解析不了，那条记录就被当成「没有时间」——统计与趋势会静默算少而不报错。
public enum CoachTime {
    /// 解析完整的 ISO8601 时间戳。带不带小数秒都认。
    public static func parse(_ text: String) -> Date? {
        // 这行 trim 目前**不可观测**：实测 macOS 26.5.2 上 ISO8601DateFormatter 自己就会
        // 跳过前导空白（空格 / \n / \t / NBSP / U+2028 / U+3000 都跳），带不带小数秒都一样，
        // 所以删掉它全套测试依然全绿——别浪费时间再验一次，也别据此写「测试 trim」的测试。
        // 保留它是对 Foundation 这个未写进文档的宽容行为的保险：哪天它收紧了，
        // 带空白的时间戳会变成「没有时间」被静默丢掉，正是本文件要防的失败形态。
        // 注意 parseDayPrefix 里那行 trim 不一样，那里是可观测的（见该函数注释）。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // ⚠️ 不要把这两个 formatter 提成 static let。Swift 6 语言模式下
        // ISO8601DateFormatter 不是 Sendable，static let 会直接编译不过。
        // 每次新建的开销在本项目的数据量（几百条）下可以忽略。
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    /// 只认前十位的日期，用于从 session id 兜底取时间。
    ///
    /// 两种已知的 session id 形状都以 `YYYY-MM-DD` 开头：
    /// 命令行归档时写的是完整 ISO8601 时间戳，`PracticeSession.id` 的文档形状是
    /// `"YYYY-MM-DD-NNN"`。两种都能落在这里。
    public static func parseDayPrefix(_ text: String) -> Date? {
        // 这里的 trim 是可观测的，别删：下面靠 prefix(10) 截字符串，前导空白会把窗口
        // 顶歪成 "  2026-08-"，一条正常 session id 就被当成「没有日期」丢掉。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")   // 不受用户区域设置影响
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        // 必须严格：宽松模式会把非法日期顺延成别的日期（实测 2026-13-45 → 2027-02-14，
        // 2026-02-30 → 2026-03-02），坏 id 被静默归进错误的周/月，算错比算少更难发现。
        formatter.isLenient = false
        return formatter.date(from: String(trimmed.prefix(10)))
    }

    /// 给界面显示用的「YYYY-MM-DD」。
    ///
    /// **必须按传入的日历（含时区）算**：晚上练的一场，UTC 日期与本地日期会差一天，
    /// 直接截时间戳前十位会把「8 月 6 日练的」显示成 8 月 5 日。
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 写入用。与项目既有写法保持一致（UTC、无小数秒）。
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
