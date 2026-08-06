import Foundation

/// 时间戳解析。**项目里所有「字符串变时间」都必须走这里，不要各处 new formatter。**
///
/// 原因：`ISO8601DateFormatter` 的默认选项是 `.withInternetDateTime`，
/// 解析不了带小数秒的时间戳。项目里的时间戳来自多处写法，
/// 一处解析不了，那条记录就被当成「没有时间」——统计与趋势会静默算少而不报错。
public enum CoachTime {
    /// 解析完整的 ISO8601 时间戳。带不带小数秒都认。
    public static func parse(_ text: String) -> Date? {
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")   // 不受用户区域设置影响
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
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
