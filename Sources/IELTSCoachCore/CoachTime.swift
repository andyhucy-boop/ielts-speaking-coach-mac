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

        return formatters.date(from: trimmed)
    }

    /// 两个 formatter 只造一次，用锁护着复用。
    ///
    /// ## 这里原来写着「每次新建的开销可以忽略」，那句话是错的
    ///
    /// 2026-08-30 在本机实测（`swiftc -O` 单独复刻，没跑 App）：
    /// **建一个 `ISO8601DateFormatter` 约 34–46 µs**，而 `parse` 每次建两个。
    /// 于是「几百条」这个量级根本不能忽略——问题档案页把 `parse` 放在排序比较器里，
    /// 30 条错题一次排序就是几百次 parse、上千个 formatter，实测单次视图模型构造
    /// 要 159 ms，而那一页每次重绘构造 4 次 ≈ **0.6 秒的主线程阻塞**。
    /// 点一下筛选按钮，窗口卡半秒。
    ///
    /// ## 为什么是加锁的 class，不是 `static let`
    ///
    /// 原注释说得对：`ISO8601DateFormatter` 不是 `Sendable`，直接 `static let` 编不过。
    /// 但那不是「只能每次新建」的理由——把它装进一个自己保证线程安全的盒子就行。
    /// 锁的开销是几十纳秒，和 34 µs 差三个数量级。
    ///
    /// **不用 `nonisolated(unsafe)`**：那只是把编译器的嘴堵上，并没有真的让它安全。
    /// 这个类型在 UI（主 actor）和 MCP 服务（另一个进程/线程）两边都被调。
    private final class ISO8601Formatters: @unchecked Sendable {
        private let lock = NSLock()
        private let plain = ISO8601DateFormatter()
        private let fractional = ISO8601DateFormatter()

        init() {
            plain.formatOptions = [.withInternetDateTime]
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func date(from text: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            // **先试不带小数秒的那个。** 项目自己写出来的时间戳一律无小数秒
            // （`CoachTime.string(from:)` 与各处的 `ISO8601DateFormatter().string(from:)`
            // 用的都是默认的 `.withInternetDateTime`），所以这是常见形状。
            // 原来的顺序是先试带小数秒的，于是**每一次解析都必然先失败一次**。
            // 两个选项互斥（带小数秒的串过不了 plain，不带的过不了 fractional），
            // 所以换顺序只影响快慢，不影响结果。
            if let date = plain.date(from: text) { return date }
            return fractional.date(from: text)
        }
    }

    private static let formatters = ISO8601Formatters()

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

        return dayFormatter.date(from: String(trimmed.prefix(10)))
    }

    /// 同上，复用而不是每次新建。`DateFormatter` 比 `ISO8601DateFormatter` 更贵。
    ///
    /// 三个设置一个都不能少，且必须在这里设死：
    /// `en_US_POSIX` 让它不受用户区域设置影响；UTC 时区对应 id 里那十位；
    /// **`isLenient = false` 是关键**——宽松模式会把非法日期顺延成别的日期
    /// （实测 2026-13-45 → 2027-02-14，2026-02-30 → 2026-03-02），
    /// 坏 id 被静默归进错误的周/月，算错比算少更难发现。
    private final class DayFormatter: @unchecked Sendable {
        private let lock = NSLock()
        private let formatter = DateFormatter()

        init() {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
        }

        func date(from text: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return formatter.date(from: text)
        }
    }

    private static let dayFormatter = DayFormatter()

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
        writer.string(from: date)
    }

    /// 同上，写入端也复用。**单独一个盒子，不和解析共用**：
    /// 解析那两个是在锁里被反复试的，写入只用一个，混在一起会让锁的持有时间毫无必要地变长。
    private final class ISO8601Writer: @unchecked Sendable {
        private let lock = NSLock()
        private let formatter = ISO8601DateFormatter()

        init() { formatter.formatOptions = [.withInternetDateTime] }

        func string(from date: Date) -> String {
            lock.lock()
            defer { lock.unlock() }
            return formatter.string(from: date)
        }
    }

    private static let writer = ISO8601Writer()
}
