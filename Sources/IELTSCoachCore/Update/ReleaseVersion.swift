import Foundation

/// 一个版本号，**按数字比大小**。
///
/// ## 为什么不能直接比字符串
///
/// `"1.10.0" < "1.9.0"` 在字符串比较下是 **true**（`'1' < '9'`）。
/// 也就是说：发到 1.10.0 之后，所有还停在 1.9.0 的人会被告知「已经是最新版」，
/// 而且这条 bug 要等到第十个小版本才会出现，出现时也毫无征兆——
/// 界面上写的是一句完全正常的「已经是最新版本」。
///
/// 认这几种写法：`1.2.0`、`v1.2.0`、`1.2`（缺的位补 0）。
/// GitHub 的 tag 习惯上带 `v`，而 `Info.plist` 里的 `CFBundleShortVersionString` 不带，
/// 两边要能对上。
public struct ReleaseVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// 解析失败返回 nil。**不要改成「解析不了就当 0.0.0」**——
    /// 那样一个乱七八糟的 tag 会让每个人都被告知「有新版本」，
    /// 而 0.0.0 比任何真实版本都小，方向恰好反过来：本机版本永远「更新」，
    /// 于是真发了新版也没人收得到。两种都比「说不出话」糟。
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // GitHub 的 tag 惯例是 `v1.2.0`；大小写都认，省得为一个字母对不上号。
        let stripped = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst()) : trimmed
        guard !stripped.isEmpty else { return nil }
        let parts = stripped.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        // 缺的位补 0：`1.2` 就是 `1.2.0`。
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
