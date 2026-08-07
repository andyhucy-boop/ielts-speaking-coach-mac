import Foundation

/// 「引导看过没有」存在哪里。
///
/// **刻意存本机 UserDefaults，不进数据目录。**
/// 数据目录里只放换机器时要跟着走的东西，而这个标记恰恰不该跟着走：
/// 换了机器，辅助功能授权是本机 TCC 的，必须重给一次，引导应该再出现。
/// 把它写进 state.json 的话，新机器上的用户一进来就没有引导，
/// 直接撞上一堵「点开始练习却报错」的墙——而他手上的数据看起来一切正常。
public protocol OnboardingProgressStore: AnyObject {
    /// 从没走完过就返回 0。
    func completedVersion() -> Int
    func markCompleted(version: Int)
}

public final class UserDefaultsOnboardingStore: OnboardingProgressStore {
    public static let key = "com.ielts.speakingcoach.onboardingCompletedVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func completedVersion() -> Int { defaults.integer(forKey: Self.key) }

    public func markCompleted(version: Int) { defaults.set(version, forKey: Self.key) }
}

/// 只活在内存里的那一份，**给 SwiftUI 预览用**。
///
/// 预览体里的代码在 Xcode 打开画布时会真的跑起来，而引导页上「开始使用」按下去会
/// `markCompleted` 写盘。走 `UserDefaults.standard` 的话，「打开画布看一眼布局」
/// 就会往真实的偏好设置里写一笔——与 `PreviewSafetyTests` 拦的
/// 「预览别在用户真实数据目录里建文件」是同一类副作用，只是换了个存储。
public final class InMemoryOnboardingStore: OnboardingProgressStore {
    private var version: Int

    public init(completedVersion: Int = 0) { version = completedVersion }

    public func completedVersion() -> Int { version }

    public func markCompleted(version: Int) { self.version = version }
}
