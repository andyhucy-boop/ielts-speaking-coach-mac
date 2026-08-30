import Foundation
import XCTest

@testable import IELTSCoachCore

/// 检查更新里**不碰网络**的那一半。
///
/// 网络那一半（真发 HTTP）在 `IELTSCoachUITests/UpdateCheckViewModelTests` 里靠注入验，
/// 一样不碰网络：测试里发真请求既慢又不稳，还会因为「今天 GitHub 恰好限流」随机变红。
final class UpdateCheckTests: XCTestCase {

    // MARK: - 版本号必须按数字比

    /// **这条是整个功能的地基。** 字符串比较下 `"1.10.0" < "1.9.0"` 是 true，
    /// 也就是发到 1.10.0 之后，所有停在 1.9.0 的人都会被告知「已经是最新版本」——
    /// 而且要等到第十个小版本才会出现，出现时界面上是一句完全正常的话。
    func testVersionsCompareAsNumbersNotAsText() throws {
        let ten = try XCTUnwrap(ReleaseVersion("1.10.0"))
        let nine = try XCTUnwrap(ReleaseVersion("1.9.0"))
        XCTAssertGreaterThan(ten, nine,
                            "1.10.0 没有被判成比 1.9.0 新。字符串比较会给出相反的结果，"
                                + "而那个 bug 要到第十个小版本才会显形。")
        XCTAssertTrue("1.10.0" < "1.9.0",
                      "这一行钉住的是「为什么必须按数字比」：字符串比较确实是反的。"
                          + "哪天它不再成立，上面那条测试就不再是在防一个真实的坑了。")
    }

    func testVersionParsingAcceptsTheTagShapesGitHubActuallyUses() throws {
        XCTAssertEqual(ReleaseVersion("v1.2.0"), ReleaseVersion(major: 1, minor: 2, patch: 0),
                       "GitHub 的 tag 惯例带 `v`，不认的话每一次发布都对不上号")
        XCTAssertEqual(ReleaseVersion("V1.2.0"), ReleaseVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(ReleaseVersion("1.2.0"), ReleaseVersion(major: 1, minor: 2, patch: 0),
                       "Info.plist 里的版本号不带 `v`，两边要能对上")
        XCTAssertEqual(ReleaseVersion("1.2"), ReleaseVersion(major: 1, minor: 2, patch: 0),
                       "缺的位补 0")
    }

    /// 解析不了就说不出话，**不许兜底成 0.0.0 或者 999.0.0**。
    ///
    /// 0.0.0 比任何真实版本都小 → 本机永远「更新」，真发了新版也没人收得到。
    /// 反过来兜底成一个大数 → 每个人每次打开都被告知「有新版本」。两种都比说不出话糟。
    func testGarbageVersionsRefuseToParseInsteadOfFallingBackToSomething() {
        for bad in ["", "   ", "latest", "v", "1.2.3.4", "1.-2.0", "一点二"] {
            XCTAssertNil(ReleaseVersion(bad),
                         "「\(bad)」被解析成了一个版本号。兜底出来的那个值会安静地"
                             + "把「有没有新版本」判反，而界面上是一句完全正常的话。")
        }
    }

    // MARK: - 结论

    func testANewerReleaseIsReportedAsAnUpdate() {
        let outcome = UpdateCheck.outcome(localVersion: "1.2.0", latest: release("v1.3.0"))
        guard case .updateAvailable(let current, let found) = outcome else {
            return XCTFail("1.2.0 对 1.3.0 没有判成有新版本，实际是：\(outcome)")
        }
        XCTAssertEqual(current, ReleaseVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(found.version, ReleaseVersion(major: 1, minor: 3, patch: 0))
    }

    /// 本机比线上新是正常的（开发机上刚打的包还没发布）。
    /// 判成「有新版本」的话，会把人骗回 GitHub 去下一个更旧的。
    func testBeingAheadOfTheReleaseIsNotAnUpdate() {
        let outcome = UpdateCheck.outcome(localVersion: "1.3.0", latest: release("v1.2.0"))
        guard case .upToDate = outcome else {
            return XCTFail("本机比线上新，却说有新版本可以下——那会让人下到一个更旧的。"
                           + "实际是：\(outcome)")
        }
    }

    func testTheSameVersionIsUpToDate() {
        guard case .upToDate = UpdateCheck.outcome(localVersion: "1.2.0",
                                                   latest: release("v1.2.0")) else {
            return XCTFail("版本一样却没说「已经是最新版本」")
        }
    }

    /// `swift run` 直接跑时读到的是「未知（开发运行）」。
    /// **那时绝不能说「已经是最新版本」**——那是一句没有依据的结论。
    func testAnUnreadableLocalVersionSaysSoInsteadOfClaimingToBeUpToDate() {
        let outcome = UpdateCheck.outcome(localVersion: "未知（开发运行）",
                                          latest: release("v9.9.9"))
        guard case .unknownLocalVersion = outcome else {
            return XCTFail("读不出本机版本时给了一个有依据的结论，实际是：\(outcome)")
        }
        let text = UpdateCheck.message(for: outcome)
        XCTAssertTrue(text.contains("下一步"), "这句话没说下一步做什么：\(text)")
        XCTAssertFalse(text.contains("已经是最新"),
                       "读不出本机版本却说「已经是最新」，那是一句编出来的结论：\(text)")
    }

    // MARK: - JSON

    func testReadsTagTitleAndPageOutOfGitHubsJSON() throws {
        let json = """
        {"tag_name":"v1.3.0","name":"1.3.0 界面改版",
         "html_url":"https://github.com/o/r/releases/tag/v1.3.0",
         "published_at":"2026-09-01T10:00:00Z"}
        """.data(using: .utf8)!
        let found = try UpdateCheck.release(fromJSON: json)
        XCTAssertEqual(found.version, ReleaseVersion(major: 1, minor: 3, patch: 0))
        XCTAssertEqual(found.title, "1.3.0 界面改版")
        XCTAssertEqual(found.pageURL.absoluteString,
                       "https://github.com/o/r/releases/tag/v1.3.0")
    }

    /// 标题在 GitHub 上可以留空。回落成 tag，否则界面上会出现「最新版本是 」这种半句话。
    func testAnEmptyReleaseTitleFallsBackToTheTagInsteadOfLeavingAHalfSentence() throws {
        let json = #"{"tag_name":"v1.3.0","name":"  ","html_url":"https://x/y"}"#
            .data(using: .utf8)!
        XCTAssertEqual(try UpdateCheck.release(fromJSON: json).title, "v1.3.0")
    }

    func testUnreadableJSONThrowsInsteadOfProducingAnEmptyRelease() {
        XCTAssertThrowsError(try UpdateCheck.release(fromJSON: Data("不是 JSON".utf8)))
        XCTAssertThrowsError(try UpdateCheck.release(fromJSON: Data("{}".utf8)),
                             "没有 tag_name 也该抛错，不能造一个 0.0.0 出来")
    }

    // MARK: - 说得出话

    /// **404 那一句是这里最要紧的一条。** 私有仓库对没有令牌的请求返回的就是 404，
    /// 和「还没发过任何版本」在协议层分不开——所以这句话必须把两种可能都说出来，
    /// 否则用户会拿着一句「找不到」去查一个不存在的网络问题。
    func test404SaysBothThingsItCouldMeanIncludingThePrivateRepo() {
        let text = UpdateCheck.message(forStatus: 404)
        XCTAssertTrue(text.contains("私有"), "404 没提「仓库可能还是私有的」：\(text)")
        XCTAssertTrue(text.contains("公开"), "404 没说清怎么才能让别人收到更新：\(text)")
        XCTAssertTrue(text.contains("下一步"), "404 没说下一步做什么：\(text)")
    }

    func testEveryFailureMessageSaysWhatHappenedAndWhatToDoNext() {
        var messages = [UpdateCheck.message(forStatus: 404),
                        UpdateCheck.message(forStatus: 403),
                        UpdateCheck.message(forStatus: 500),
                        UpdateCheck.message(forStatus: 418),
                        UpdateCheck.message(forTransportFailure: "网络连接已中断"),
                        UpdateCheck.message(for: .unreadableResponse),
                        UpdateCheck.message(for: .unreadableVersion(tag: "latest"))]
        messages.append(UpdateCheck.message(for: .failed(messages[0])))
        for text in messages {
            XCTAssertTrue(text.contains("下一步"),
                          "这句话没说下一步做什么，用户读完还是不知道该干嘛：\(text)")
            XCTAssertGreaterThan(text.count, 20, "这句话太短，说不清发生了什么：\(text)")
        }
    }

    /// 「有新版本」那句话必须交代**训练数据不会丢**。
    ///
    /// 换包是把 .app 整个替换掉，而这个工具的数据在「应用程序支持」目录里。
    /// 不说这一句的话，用户多半宁可不更新——那正是这个功能想避免的。
    func testTheUpdateMessageSaysTrainingDataSurvivesTheSwap() {
        let text = UpdateCheck.message(for: .updateAvailable(
            current: ReleaseVersion(major: 1, minor: 2, patch: 0), release: release("v1.3.0")))
        XCTAssertTrue(text.contains("不会丢"),
                      "没说清训练数据不会丢，用户多半宁可不更新：\(text)")
        XCTAssertTrue(text.contains("下一步"), "没说下一步做什么：\(text)")
    }

    // MARK: - 地址

    func testTheURLsPointAtTheRealRepository() {
        XCTAssertEqual(UpdateCheck.latestReleaseAPI.absoluteString,
                       "https://api.github.com/repos/andyhucy-boop/ielts-speaking-coach-mac"
                           + "/releases/latest")
        XCTAssertEqual(UpdateCheck.releasesPage.absoluteString,
                       "https://github.com/andyhucy-boop/ielts-speaking-coach-mac/releases")
    }

    // MARK: - 节流

    func testTheFirstEverCheckHappensAndThenNotMoreThanOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateCheckSchedule.shouldCheckAutomatically(lastChecked: nil, now: now),
                      "从来没查过时不查，那这个功能对新装的人是不存在的")
        XCTAssertFalse(UpdateCheckSchedule.shouldCheckAutomatically(
            lastChecked: now.addingTimeInterval(-60), now: now),
                       "一分钟前刚查过又查一次。这一页开发时会被反复打开，"
                           + "GitHub 对匿名请求每小时只给 60 次，打满之后返回 403——"
                           + "于是「检查更新」在最需要它的时候恰好是坏的。")
        XCTAssertTrue(UpdateCheckSchedule.shouldCheckAutomatically(
            lastChecked: now.addingTimeInterval(-UpdateCheckSchedule.interval - 1), now: now))
    }

    /// 系统时间被往回调过时，差值是负的。不取绝对值的话会**永远不再自动检查**，
    /// 而且没有任何迹象——用户只会觉得「这个功能好像从来没生效过」。
    func testAClockThatWentBackwardsDoesNotDisableCheckingForever() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateCheckSchedule.shouldCheckAutomatically(
            lastChecked: now.addingTimeInterval(UpdateCheckSchedule.interval + 1), now: now),
                      "上次检查的时间戳在未来（系统时间被调过），结果是再也不自动检查了")
    }

    private func release(_ tag: String) -> GitHubRelease {
        GitHubRelease(version: ReleaseVersion(tag)!, title: tag,
                      pageURL: UpdateCheck.releasesPage, publishedAt: "")
    }
}
