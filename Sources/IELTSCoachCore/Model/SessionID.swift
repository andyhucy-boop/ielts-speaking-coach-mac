import Foundation

public enum SessionID {
    /// 会话编号 `YYYY-MM-DD-NNN`，与 `PracticeSession.id` 的文档格式一致。
    ///
    /// 取当天已有编号的**最大值 +1**，不是「条数 +1」：训练记录允许单条删除，
    /// 有空缺时后者会撞号，而撞号意味着两次练习的复盘写到同一个
    /// `reports/<id>.json` 上，后一次直接盖掉前一次。
    public static func next(existing: [PracticeSession], now: Date,
                            timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        // 不跟随用户的日历与地区，否则可能出佛历年份或本地化数字
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)

        let highest = existing.reduce(0) { current, session in
            guard session.id.hasPrefix("\(today)-") else { return current }
            let suffix = session.id.dropFirst(today.count + 1)
            // 旧格式（ISO8601 时间戳）解析不出数字，忽略掉即可，不能因此崩溃
            guard let number = Int(suffix) else { return current }
            return max(current, number)
        }
        return String(format: "%@-%03d", today, highest + 1)
    }

    /// 会话编号会直接拼进 `pending-reviews/<id>.txt` 与 `reports/<id>.json`。
    /// 放行 `/`、`..`、控制字符，等于让调用方往数据目录外面写文件。
    ///
    /// **白名单里有 `:` 和 `+` 是刻意的**（决策 1）：用户现有的 `state.json` 里
    /// 已经存在 `2026-08-05T14:03:11Z` 这种形状的会话 id（`coach practice` 一直
    /// 这么生成）。拒绝它等于让已有练习记录全部失效。这两个字符不构成路径穿越，
    /// 只是文件名里不好看。**新产生的编号一律走 `next(existing:now:timeZone:)`，
    /// 是 `YYYY-MM-DD-NNN` 形状。**
    public static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.:+")
        guard !trimmed.isEmpty,
              trimmed != ".", trimmed != "..",
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CoachError.invalidSessionID(
                "会话编号「\(raw)」不合法：只能用字母、数字、连字符、下划线、点、冒号和加号，"
                + "且不能是 . 或 .. 。"
                + "下一步：省略会话编号让工具自动生成，或改用「训练记录」页里列出的那些编号。")
        }
        return trimmed
    }
}
