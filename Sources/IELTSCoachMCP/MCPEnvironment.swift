import Foundation
import IELTSCoachCore

/// 唤起 App 的通道。抽成 protocol 是为了让单元测试用假实现——
/// **测试里一次都不许真的去开一个应用窗口。**
public protocol DashboardOpening {
    func open(_ url: URL) throws
}

/// 唤起 App（`ieltscoach://`）失败。message 必须是中文，
/// 且同时说清「发生了什么」与「下一步做什么」。
public struct DashboardOpenError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// 7 个 tool 共用的运行环境。时间与时区都注入进来，
/// 测试断言才不会随「今天几号」「跑在哪个时区」变化。
public struct MCPEnvironment {
    public let directory: DataDirectory
    /// 由 directory 构造，两者不可能指向不同地方。
    public let store: StateStore
    public let opener: any DashboardOpening
    public let now: () -> Date
    public let timeZone: TimeZone

    public init(directory: DataDirectory, opener: any DashboardOpening,
                now: @escaping () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.opener = opener
        self.now = now
        self.timeZone = timeZone
    }

    /// 全项目统一的时间戳格式。各处格式不一致会让按 startedAt 的字符串排序错乱。
    public var timestamp: String { ISO8601DateFormatter().string(from: now()) }
}
