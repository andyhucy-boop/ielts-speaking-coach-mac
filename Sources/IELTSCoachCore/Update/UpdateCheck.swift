import Foundation

/// GitHub 上最新那一版发布。
public struct GitHubRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    /// 发布标题。GitHub 上留空时回落成 tag 本身，**不许是空串**——
    /// 空串会让界面上出现「最新版本是 」这种半句话。
    public let title: String
    /// 这一版的发布页。用户点「去看看」打开的就是它。
    public let pageURL: URL
    /// 发布日期原文（ISO8601）。显示用，比不上版本号可靠，所以不参与任何判断。
    public let publishedAt: String

    public init(version: ReleaseVersion, title: String, pageURL: URL, publishedAt: String) {
        self.version = version
        self.title = title
        self.pageURL = pageURL
        self.publishedAt = publishedAt
    }
}

/// 检查更新的结论。
///
/// **四种都要能说出话。** 「查不了」这一支尤其不能省：网络不通、仓库不公开、
/// 被 GitHub 限流，这三件事在界面上不能都长成「已经是最新版本」——
/// 那是最坏的一种沉默，用户会一直以为自己用的是最新的（铁律 7）。
public enum UpdateOutcome: Equatable, Sendable {
    /// 本机版本 ≥ 线上最新版。
    case upToDate(current: ReleaseVersion, latest: ReleaseVersion)
    case updateAvailable(current: ReleaseVersion, release: GitHubRelease)
    /// 本机版本读不出来（`swift run` 直接跑时没有 App bundle）。
    case unknownLocalVersion(raw: String)
    /// 查不了。附一句中文：发生了什么 + 下一步做什么。
    case failed(String)
}

/// 「有没有新版本」这件事里**不碰网络**的那一半：地址怎么拼、返回的 JSON 怎么读、
/// 两个版本号怎么比、以及每种结论用中文怎么说。
///
/// 抽成纯函数是因为这几件事全都可以在没有网络的情况下测，而真发一次 HTTP 请求
/// 在测试里既慢又不稳，还会因为「今天 GitHub 恰好限流」而随机变红。
/// 网络那一半在 `IELTSCoachUI` 的 `UpdateCheckViewModel` 里，靠注入。
public enum UpdateCheck {

    // MARK: - 去哪儿查

    /// 仓库坐标。**只写在这一处。**
    public static let owner = "andyhucy-boop"
    public static let repository = "ielts-speaking-coach-mac"

    /// 查最新发布的接口。`/releases/latest` 自动跳过草稿与预发布，
    /// 所以不需要在这边再过滤一遍。
    public static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    }

    /// 发布页（给用户点的那个）。接口查不到时也能用——例如仓库还不公开，
    /// 用户至少能拿这个地址去问作者。
    public static var releasesPage: URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases")!
    }

    // MARK: - 返回的东西怎么读

    /// 从 GitHub 的 JSON 里读出一条发布。读不出来时抛错，**不返回一个空壳**。
    public static func release(fromJSON data: Data) throws -> GitHubRelease {
        struct Payload: Decodable {
            let tag_name: String?
            let name: String?
            let html_url: String?
            let published_at: String?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateCheckError.unreadableResponse
        }
        guard let tag = payload.tag_name, let version = ReleaseVersion(tag) else {
            throw UpdateCheckError.unreadableVersion(tag: payload.tag_name ?? "（没有 tag_name 这一项）")
        }
        // 标题留空时回落成 tag，免得界面上出现「最新版本是 」这种半句话。
        let rawTitle = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? tag : rawTitle
        let page = payload.html_url.flatMap(URL.init(string:)) ?? releasesPage
        return GitHubRelease(version: version, title: title, pageURL: page,
                             publishedAt: payload.published_at ?? "")
    }

    public enum UpdateCheckError: Error, Equatable {
        case unreadableResponse
        case unreadableVersion(tag: String)
    }

    // MARK: - 结论

    /// 本机这一版和线上最新那一版比一比。
    ///
    /// - Parameter localVersion: `Info.plist` 里的 `CFBundleShortVersionString`。
    ///   `swift run` 直接跑时它是 `AppMetadata.unknownValue` 那句中文，解析不出来——
    ///   那时给的是 `.unknownLocalVersion`，**不是**「已经是最新版」。
    public static func outcome(localVersion: String, latest: GitHubRelease) -> UpdateOutcome {
        guard let current = ReleaseVersion(localVersion) else {
            return .unknownLocalVersion(raw: localVersion)
        }
        // 用 `<` 而不是 `!=`：本机比线上新是正常的（开发机上刚打的包还没发布），
        // 那种情况说「有新版本」会把人骗回 GitHub 去下一个更旧的。
        return current < latest.version
            ? .updateAvailable(current: current, release: latest)
            : .upToDate(current: current, latest: latest.version)
    }

    /// HTTP 状态码不是 200 时那句中文。
    ///
    /// **404 那一句是这里最要紧的一条。** 私有仓库对没有令牌的请求返回的就是 404，
    /// 和「还没发过任何版本」一模一样——两者在协议层分不开，所以这句话必须把
    /// 两种可能都说出来，否则用户会拿着一句「找不到」去查一个不存在的网络问题。
    public static func message(forStatus status: Int) -> String {
        switch status {
        case 404:
            return "GitHub 说这个仓库没有已发布的版本（HTTP 404）。"
                + "两种可能：仓库还是私有的，或者确实还没发布过任何一版。"
                + "下一步：私有仓库任何人都查不到更新，"
                + "要让别人能收到更新，得把仓库设为公开、并在 GitHub 上发布一个 Release。"
        case 403, 429:
            return "GitHub 暂时不让查了（HTTP \(status)），多半是同一个网络查得太频繁。"
                + "下一步：过一小时再点一次「检查更新」；也可以直接打开发布页自己看一眼。"
        case 500...599:
            return "GitHub 那边出错了（HTTP \(status)），不是你这边的问题。"
                + "下一步：过一会儿再点一次「检查更新」。"
        default:
            return "查更新时 GitHub 返回了 HTTP \(status)，本工具看不懂这个回复。"
                + "下一步：直接打开发布页自己看一眼最新版本号是多少。"
        }
    }

    /// 请求根本发不出去（断网、DNS、超时）时那句中文。
    public static func message(forTransportFailure description: String) -> String {
        "连不上 GitHub：\(description)。"
            + "下一步：确认这台电脑能上网之后再点一次「检查更新」；"
            + "网络没问题的话，直接打开发布页自己看一眼。"
    }

    /// 读回复出错时那句中文。
    public static func message(for error: UpdateCheckError) -> String {
        switch error {
        case .unreadableResponse:
            return "GitHub 的回复读不出来，本工具没法判断最新版本是多少。"
                + "下一步：直接打开发布页自己看一眼。"
        case .unreadableVersion(let tag):
            return "GitHub 上最新那一版的标签是「\(tag)」，本工具看不懂这个版本号"
                + "（认得的写法是 `1.2.0` 或 `v1.2.0`）。"
                + "下一步：直接打开发布页自己看一眼；发布时把标签写成 `v` 加三段数字最稳。"
        }
    }

    /// 结论在界面上怎么说。**每一种都得说出「发生了什么」，能说下一步的就说。**
    public static func message(for outcome: UpdateOutcome) -> String {
        switch outcome {
        case .upToDate(let current, let latest):
            return "已经是最新版本（本机 \(current)，GitHub 上最新 \(latest)）。"
        case .updateAvailable(let current, let release):
            return "有新版本：\(release.version)（\(release.title)）。你现在用的是 \(current)。"
                + "下一步：点「去 GitHub 看这一版」，在发布页上下载新的 .app 换掉旧的；"
                + "训练数据不在 App 里面，换包不会丢。"
        case .unknownLocalVersion(let raw):
            return "读不出本机版本（读到的是「\(raw)」），所以没法和 GitHub 上的比。"
                + "这通常是因为现在跑的是 `swift run` 的开发版本，不是打包好的 .app。"
                + "下一步：用打包好的 App 打开这一页；或者直接打开发布页自己看一眼。"
        case .failed(let message):
            return message
        }
    }
}

/// 自动检查的节流。
///
/// **不能每次打开这一页都发一次请求。** GitHub 对没有令牌的请求按 IP 限流
/// （每小时 60 次），而这一页在开发时会被反复打开；打满之后返回的是 403，
/// 于是「检查更新」这个功能在最需要它的时候恰好是坏的。
public enum UpdateCheckSchedule {
    /// 两次自动检查之间至少隔多久。手动点「检查更新」不受它管——
    /// 那是用户明确要求的一次，节流掉会让按钮看着像坏了。
    public static let interval: TimeInterval = 24 * 60 * 60

    /// 现在该不该自动查一次。
    /// - Parameter lastChecked: 上次查的时间；从来没查过时传 nil。
    public static func shouldCheckAutomatically(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        // 用绝对值：系统时间被往回调过的话，差值是负的，
        // 不取绝对值就会一直不查，而且没有任何迹象。
        return abs(now.timeIntervalSince(lastChecked)) >= interval
    }
}
