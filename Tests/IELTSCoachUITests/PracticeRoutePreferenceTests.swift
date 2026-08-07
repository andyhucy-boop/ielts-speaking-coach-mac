import XCTest
import IELTSCoachCore

@testable import IELTSCoachUI

final class PracticeRoutePreferenceTests: XCTestCase {

    func testKnownRawValuesRoundTrip() {
        for route in PracticeRoute.allCases {
            XCTAssertEqual(
                PracticeRoutePreference.route(fromSettings: PracticeRoutePreference.rawValue(for: route)),
                route)
        }
    }

    /// state.json 是纯文本，可以被手改，也可能是别的版本写的。
    /// 认不出来的路线名必须退回默认路线，而不是让今日训练页空着。
    func testUnknownRawValueFallsBackToThePlanRoute() {
        XCTAssertEqual(PracticeRoutePreference.route(fromSettings: "somethingElse"), .planToday)
        XCTAssertEqual(PracticeRoutePreference.route(fromSettings: ""), .planToday)
    }

    /// Core 存的是字符串（Core 不允许依赖 UI，所以它看不见 `PracticeRoute`）。
    /// 这条测试是两个模块之间唯一的对齐点：默认值写错一个字母，这里就会红。
    func testCoreDefaultMatchesTheUIRoute() {
        XCTAssertEqual(PracticeRoute(rawValue: CoachSettings.defaultRouteFallback),
                       PracticeRoutePreference.fallback)
        XCTAssertEqual(PracticeRoutePreference.fallback, .planToday,
                       "ROADMAP 第 5 节：练习路线默认「按计划练今天」")
        // 上面两条只钉住「Core 的默认字符串认得出来」。写进 state.json 的那一头是
        // `rawValue(for:)`（Task 9 的设置面板就是这么存的），它自己也得跟 Core 的默认值同名——
        // 否则用户明确选了「按计划练今天」，存进去的字符串却与 Core 认的默认值不是一个，
        // 两边各自都「能用」，只是再也对不上，而且不会报任何错。
        XCTAssertEqual(PracticeRoutePreference.rawValue(for: .planToday),
                       CoachSettings.defaultRouteFallback,
                       "存进 state.json 的默认路线名必须与 Core 的 defaultRouteFallback 一致")
    }

    func testRouteDefaultsComeFromSettings() {
        var settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "")
        settings.feedbackTiming = .immediate
        settings.part2PrepMode = .learnerControlled
        let defaults = RouteDefaults(settings: settings)
        XCTAssertEqual(defaults.feedbackTiming, .immediate)
        XCTAssertEqual(defaults.part2PrepMode, .learnerControlled)
    }

    func testRouteDefaultsFallBackToTheDocumentedDefaults() {
        let defaults = RouteDefaults()
        XCTAssertEqual(defaults.feedbackTiming, .deferred)
        XCTAssertEqual(defaults.part2PrepMode, .countdown)
    }
}
