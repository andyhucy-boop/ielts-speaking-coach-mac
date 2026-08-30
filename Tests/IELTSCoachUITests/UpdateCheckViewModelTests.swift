import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 检查更新里**碰网络**的那一半，靠注入验——一条真请求都不发。
///
/// 理由和本项目其他外部依赖一样：真发请求既慢又不稳，还会因为「今天 GitHub 恰好限流」
/// 随机变红；而这个功能最要紧的几条（404 怎么说、限流怎么说、断网怎么说）
/// 恰恰**只有假回复测得了**——真跑一次永远只能碰到其中一种。
@MainActor
final class UpdateCheckViewModelTests: XCTestCase {

    /// 记下被要过哪些地址，并按脚本返回。
    /// `@MainActor` 而不是自己上锁：这一整组测试都在主 actor 上跑，
    /// 而 `NSLock` 在异步上下文里是禁用的（Swift 6）。
    @MainActor
    private final class FakeFetcher: ReleaseFetching {
        var result: Result<(data: Data, status: Int), Error>
        private(set) var requested: [URL] = []

        init(json: String = "{}", status: Int = 200) {
            result = .success((Data(json.utf8), status))
        }

        nonisolated func fetch(_ url: URL) async throws -> (data: Data, status: Int) {
            await MainActor.run { requested.append(url) }
            return try await MainActor.run { result }.get()
        }
    }

    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "网络连接已中断" }
    }

    private func model(_ fetcher: FakeFetcher,
                       lastChecked: Date? = nil,
                       now: Date = Date(timeIntervalSince1970: 1_800_000_000))
    -> UpdateCheckViewModel {
        UpdateCheckViewModel(fetcher: fetcher,
                             store: InMemoryUpdateCheckStore(lastChecked: lastChecked),
                             now: { now })
    }

    private static let newer = """
    {"tag_name":"v9.9.9","name":"未来版","html_url":"https://github.com/o/r/releases/tag/v9.9.9"}
    """

    // MARK: - 查到了

    func testANewerReleaseShowsUpWithItsOwnPageLink() async {
        let fetcher = FakeFetcher(json: Self.newer)
        let model = model(fetcher)
        await model.check(localVersion: "1.2.0")

        XCTAssertEqual(fetcher.requested, [UpdateCheck.latestReleaseAPI],
                       "查的不是 GitHub 那个「最新发布」接口")
        XCTAssertTrue(model.hasUpdate, "9.9.9 对 1.2.0 没判成有新版本")
        XCTAssertEqual(model.pageURL.absoluteString,
                       "https://github.com/o/r/releases/tag/v9.9.9",
                       "「去 GitHub 看这一版」应该开那一版自己的页面，而不是发布列表")
        let message = try? XCTUnwrap(model.message)
        XCTAssertTrue(message?.contains("9.9.9") ?? false, "没说新版本号是多少")
    }

    func testBeingCurrentSaysSoInsteadOfStayingSilent() async {
        let model = model(FakeFetcher(json: #"{"tag_name":"v1.2.0","html_url":"https://x/y"}"#))
        await model.check(localVersion: "1.2.0")
        XCTAssertFalse(model.hasUpdate)
        XCTAssertTrue(model.message?.contains("已经是最新版本") ?? false,
                      "查完没有说话。「查过、是最新的」和「还没查」不能长得一样，"
                          + "否则用户不知道这颗按钮到底有没有生效。实际是：\(model.message ?? "nil")")
    }

    // MARK: - 三种查不了

    /// **这三条是这个功能真正的价值所在。** 三种失败在界面上都长成
    /// 「已经是最新版本」的话，用户会一直以为自己用的是最新的（铁律 7）。
    func testEveryKindOfFailureSaysSoInsteadOfLookingLikeUpToDate() async {
        let transport = FakeFetcher(); transport.result = .failure(Boom())
        let notFound = FakeFetcher(json: #"{"message":"Not Found"}"#, status: 404)
        let rateLimited = FakeFetcher(json: "{}", status: 403)
        let garbage = FakeFetcher(json: "这不是 JSON")

        for (name, fetcher, needle) in [
            ("断网", transport, "连不上 GitHub"),
            ("私有仓库 / 还没发布", notFound, "私有"),
            ("被限流", rateLimited, "太频繁"),
            ("回复读不出来", garbage, "读不出来")
        ] {
            let model = model(fetcher)
            await model.check(localVersion: "1.2.0")
            let message = model.message ?? "nil"
            XCTAssertFalse(model.hasUpdate, "「\(name)」被当成了查到新版本")
            XCTAssertFalse(message.contains("已经是最新版本"),
                           "「\(name)」这种查不了的情况被说成了「已经是最新版本」——"
                               + "用户会一直以为自己用的是最新的。实际是：\(message)")
            XCTAssertTrue(message.contains(needle),
                          "「\(name)」没说清发生了什么（找不到「\(needle)」）：\(message)")
            XCTAssertTrue(message.contains("下一步"),
                          "「\(name)」没说下一步做什么：\(message)")
        }
    }

    /// 查失败时那颗「打开发布页」按钮仍然得有个地址可去——**那时用户最需要它**。
    func testAFailedCheckStillOffersAPageToOpen() async {
        let model = model(FakeFetcher(json: "{}", status: 404))
        await model.check(localVersion: "1.2.0")
        XCTAssertEqual(model.pageURL, UpdateCheck.releasesPage,
                       "查失败时没有给出可以打开的发布页，那颗按钮成了死的")
    }

    // MARK: - 节流

    func testTheAutomaticCheckIsThrottledButTheManualOneNeverIs() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fetcher = FakeFetcher(json: Self.newer)
        let model = model(fetcher, lastChecked: now.addingTimeInterval(-60), now: now)

        await model.checkIfDue(localVersion: "1.2.0")
        XCTAssertTrue(fetcher.requested.isEmpty,
                      "一分钟前刚查过，打开这一页又查了一次。GitHub 对匿名请求每小时只给 60 次，"
                          + "打满之后返回 403——这个功能会在最需要它的时候恰好是坏的。")

        await model.check(localVersion: "1.2.0")
        XCTAssertEqual(fetcher.requested.count, 1,
                       "用户自己点「检查更新」也被节流掉了——那颗按钮看着就像坏了")
    }

    func testTheVeryFirstLaunchDoesCheck() async {
        let fetcher = FakeFetcher(json: Self.newer)
        await model(fetcher, lastChecked: nil).checkIfDue(localVersion: "1.2.0")
        XCTAssertEqual(fetcher.requested.count, 1,
                       "从来没查过时也不查，那这个功能对新装的人是不存在的")
    }

    /// 失败也要记一笔「查过了」。不记的话，断网时每次打开这一页都会再卡一次超时。
    func testAFailedCheckStillCountsAsHavingChecked() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = InMemoryUpdateCheckStore()
        let fetcher = FakeFetcher(); fetcher.result = .failure(Boom())
        let model = UpdateCheckViewModel(fetcher: fetcher, store: store, now: { now })
        await model.check(localVersion: "1.2.0")
        XCTAssertEqual(store.lastChecked(), now,
                       "查失败没有记时间，于是断网时每次打开这一页都要再卡一次超时")
    }

    // MARK: - 只检测，不自动装

    /// **这条守的是一条边界。** 这个功能只告诉你有新版本、并把发布页打开；
    /// 它不下载任何东西，更不会替换正在运行的 App——那需要 Sparkle 那一套和一对签名密钥，
    /// 而「让程序去下载并执行一个来自网络的二进制」是本项目明令不做的一类操作。
    func testTheUpdaterNeverDownloadsOrExecutesAnything() throws {
        for path in ["Upgrade/UpdateCheckViewModel.swift", "Upgrade/UpgradeView.swift"] {
            let code = try SourceGuard.code(path)
            for forbidden in ["downloadTask", "Process(", "unzip", "FileManager.default.removeItem",
                              "replaceItemAt"] {
                XCTAssertFalse(
                    code.contains(forbidden),
                    "\(path) 里出现了「\(forbidden)」。检查更新只该做两件事：问一句、"
                        + "把发布页打开。自己下载或替换 App 需要 Sparkle 那一套和一对签名密钥，"
                        + "在那之前，「程序自己去下载并执行一个网络来的二进制」是不做的。")
            }
        }
    }
}
