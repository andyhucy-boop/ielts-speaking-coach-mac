import Foundation
import IELTSCoachCore

/// 去 GitHub 取一次「最新发布」。
///
/// **做成协议而不是在视图模型里直接写 `URLSession`**，理由和本项目其他外部依赖一样：
/// 测试里发真请求既慢又不稳，还会因为「今天 GitHub 恰好限流」随机变红——
/// 而这个功能最要紧的几条（404 怎么说、限流怎么说、断网怎么说）恰恰只有假回复测得了。
public protocol ReleaseFetching: Sendable {
    /// - Returns: 回复体，以及 HTTP 状态码。
    func fetch(_ url: URL) async throws -> (data: Data, status: Int)
}

/// 真去发请求的那一个。
public struct LiveReleaseFetcher: ReleaseFetching {
    public init() {}

    public func fetch(_ url: URL) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        // GitHub 的 API 要求带 User-Agent，不带会直接被拒。
        request.setValue("IELTSSpeakingCoach", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // 查更新是可有可无的一件事，**绝不能让它把界面挂在那儿**。
        request.timeoutInterval = 15
        // 不吃缓存：上一次查的结果可能是几天前的 304，那样刚发布的新版永远看不见。
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}

/// 「上次是什么时候查的」记在哪儿。
///
/// 存本机 `UserDefaults`，**不进训练数据目录**：这是这台机器上的一个小状态，
/// 跟练习记录没有关系，混进去只会让那份数据多一个跟内容无关的字段。
/// 做成协议是为了让测试不去碰用户真实的偏好设置。
public protocol LastUpdateCheckStore: AnyObject, Sendable {
    func lastChecked() -> Date?
    func markChecked(at date: Date)
}

public final class UserDefaultsUpdateCheckStore: LastUpdateCheckStore, @unchecked Sendable {
    private static let key = "IELTSCoach.lastUpdateCheck"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func lastChecked() -> Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    public func markChecked(at date: Date) {
        defaults.set(date, forKey: Self.key)
    }
}

public final class InMemoryUpdateCheckStore: LastUpdateCheckStore, @unchecked Sendable {
    private var date: Date?
    public init(lastChecked: Date? = nil) { self.date = lastChecked }
    public func lastChecked() -> Date? { date }
    public func markChecked(at date: Date) { self.date = date }
}

/// 「功能升级」页上那块「有没有新版本」。
///
/// ## 边界：**只检测，不自动装**
///
/// 这里做的是「告诉你有新版本，并把发布页打开」，**不会自己下载、更不会自己替换 App**。
/// 自动装要么得引入 Sparkle 那一套（还要一对签名密钥），要么就是让程序去下载并执行
/// 一个来自网络的二进制——后者在本项目是明令不做的一类操作。
/// 换包是十秒钟的事，而「App 会自己改自己」这件事值得用户自己点一下头。
@MainActor
@Observable
public final class UpdateCheckViewModel {
    /// 这次检查的结论。nil 表示还没查过（**不是**「没有新版本」——两者不能长得一样）。
    public private(set) var outcome: UpdateOutcome?
    /// 正在查。超过 300ms 的操作都要有反馈（规范第 5 节）。
    public private(set) var isChecking = false

    private let fetcher: any ReleaseFetching
    private let store: any LastUpdateCheckStore
    private let now: @Sendable () -> Date

    /// 生产用的那一个。**全 App 共用一份。**
    ///
    /// `UpgradeView` 是结构体，父视图每重绘一次就重新构造它一次，而
    /// `State(initialValue:)` 只认第一次——其余每一个连同它们持有的 store 与取件器
    /// 立刻被丢弃。共用一份之后那些白造白丢就没有了，
    /// 而且「上次什么时候查的」这件事本来就该全 App 只有一份。
    @MainActor public static let live = UpdateCheckViewModel()

    public init(fetcher: any ReleaseFetching = LiveReleaseFetcher(),
                store: any LastUpdateCheckStore = UserDefaultsUpdateCheckStore(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.store = store
        self.now = now
    }

    /// 界面上要显示的那句话。还没查过时是 nil，那时界面只摆一颗按钮。
    public var message: String? {
        outcome.map(UpdateCheck.message(for:))
    }

    /// 有没有新版本可下。决定「去 GitHub 看这一版」那颗按钮出不出现。
    public var hasUpdate: Bool {
        if case .updateAvailable = outcome { return true }
        return false
    }

    /// 「去 GitHub 看这一版」打开哪个地址。
    ///
    /// 有具体那一版就开那一版的页面，否则开发布列表——**任何时候都给得出一个地址**。
    /// 查失败时尤其要给：那时用户最需要的就是自己去看一眼。
    public var pageURL: URL {
        if case .updateAvailable(_, let release) = outcome { return release.pageURL }
        return UpdateCheck.releasesPage
    }

    /// 打开这一页时自动查一次（每天最多一次，见 `UpdateCheckSchedule`）。
    public func checkIfDue(localVersion: String) async {
        guard UpdateCheckSchedule.shouldCheckAutomatically(lastChecked: store.lastChecked(),
                                                           now: now()) else { return }
        await check(localVersion: localVersion)
    }

    /// 用户自己点「检查更新」。**不受节流管**——那是他明确要求的一次，
    /// 节流掉会让按钮看着像坏了。
    public func check(localVersion: String) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        // 无论成败都记一笔：失败也算查过了，否则断网时每次打开这一页都会再卡一次超时。
        store.markChecked(at: now())

        let response: (data: Data, status: Int)
        do {
            response = try await fetcher.fetch(UpdateCheck.latestReleaseAPI)
        } catch {
            outcome = .failed(UpdateCheck.message(
                forTransportFailure: error.localizedDescription))
            return
        }
        guard response.status == 200 else {
            outcome = .failed(UpdateCheck.message(forStatus: response.status))
            return
        }
        do {
            let release = try UpdateCheck.release(fromJSON: response.data)
            outcome = UpdateCheck.outcome(localVersion: localVersion, latest: release)
        } catch let error as UpdateCheck.UpdateCheckError {
            outcome = .failed(UpdateCheck.message(for: error))
        } catch {
            outcome = .failed(UpdateCheck.message(for: .unreadableResponse))
        }
    }
}


/// 固定回复的取件器。**给预览与测试用**——生产代码一处都不该引用它。
///
/// 有了它，预览打开画布时不会真去 GitHub 发请求（铁律 5：预览不许碰真实的外部世界）。
public struct FixedReleaseFetcher: ReleaseFetching {
    private let payload: Data
    private let status: Int

    public init(json: String, status: Int = 200) {
        self.payload = Data(json.utf8)
        self.status = status
    }

    /// 一份「已经是最新版」的回复：tag 取 `Changelog` 里当前那一版。
    public static var upToDate: FixedReleaseFetcher {
        FixedReleaseFetcher(json: #"{"tag_name":"v"# + Changelog.current.version
            + #"","name":"当前版本","html_url":"https://github.com/"#
            + UpdateCheck.owner + "/" + UpdateCheck.repository + #"/releases"}"#)
    }

    public func fetch(_ url: URL) async throws -> (data: Data, status: Int) {
        (payload, status)
    }
}
