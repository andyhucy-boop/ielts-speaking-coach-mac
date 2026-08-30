import XCTest
@testable import IELTSCoachCore

final class CoachRouteTests: XCTestCase {
    func testEveryRouteProducesAValidIeltscoachURL() {
        // url 属性内部用 preconditionFailure 兜底非法拼装。这条测试的意义是：
        // 将来有人加了带空格或大写的 case，红的是测试，不是用户机器上的崩溃。
        for route in CoachRoute.allCases {
            XCTAssertEqual(route.url.scheme, "ieltscoach", "\(route) 的 scheme 不对")
            XCTAssertEqual(route.url.absoluteString, "ieltscoach://\(route.rawValue)")
        }
    }

    func testParseAcceptsHostForm() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://history"))
        XCTAssertEqual(CoachRoute.parse(url), .history)
    }

    func testParseIgnoresCaseAndTrailingSlash() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://Dashboard/"))
        XCTAssertEqual(CoachRoute.parse(url), .dashboard)
    }

    func testParseAcceptsSchemeColonForm() throws {
        // 有些客户端会拼成 ieltscoach:reviews（没有双斜杠），host 是 nil、路径才是页面名。
        let url = try XCTUnwrap(URL(string: "ieltscoach:reviews"))
        XCTAssertEqual(CoachRoute.parse(url), .reviews)
    }

    func testParseRejectsOtherSchemes() throws {
        // 不能只看 host —— https://history 也有 host "history"，认了就等于
        // 谁都能用一条网页链接把 App 支使到某一页去。
        let url = try XCTUnwrap(URL(string: "https://history"))
        XCTAssertNil(CoachRoute.parse(url))
    }

    func testParseRejectsUnknownPage() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://nope"))
        XCTAssertNil(CoachRoute.parse(url))
    }

    func testRawValuesAreStableBecauseTheyAreThePublicURLContract() {
        // 这些字符串会出现在用户抄进 Codex 的链接里、也会出现在 tool 的参数枚举里。
        // 改了就是破坏兼容，必须让改动者先看到这条测试红掉。
        XCTAssertEqual(CoachRoute.allCases.map(\.rawValue),
                       ["dashboard", "today", "questions", "plan", "retraining",
                        "reviews", "history", "issues", "vocabulary",
                        "upgrade", "feedback"])
    }
}
