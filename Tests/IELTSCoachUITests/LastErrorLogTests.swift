import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class LastErrorLogTests: XCTestCase {
    private let secret = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
    private let moment = Date(timeIntervalSince1970: 1_785_931_530)

    func testStartsEmpty() {
        XCTAssertNil(LastErrorLog().last)
    }

    func testRecordsTheStageAndTheCodeButNeverTheMessage() throws {
        // 这是本任务的核心约束。CoachError 的消息里完全可能带着复盘原文的片段，
        // 而复盘原文里全是用户说过的英语。
        let log = LastErrorLog()
        log.record(CoachError.invalidReviewText("复盘里出现了 \(secret)，解析不了"),
                   at: .parsingReview, now: moment)

        let last = try XCTUnwrap(log.last)
        XCTAssertEqual(last.stage, .parsingReview)
        XCTAssertEqual(last.code, "review-invalid-text")
        XCTAssertFalse(last.summary.contains(secret), "把错误原文带进来了：\(last.summary)")
        XCTAssertFalse(last.occurredAt.isEmpty)
    }

    func testOnlyTheMostRecentOneIsKept() {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("a"), at: .fetchingReview, now: moment)
        log.record(CoachError.planImpossible("b"), at: .buildingPlan, now: moment)
        XCTAssertEqual(log.last?.code, "plan-impossible")
    }

    func testClearingActuallyClears() {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("a"), at: .fetchingReview, now: moment)
        log.clear()
        XCTAssertNil(log.last)
    }

    /// **两处与计划原文不同，都是照源码核对之后改的：**
    ///
    /// 一、计划列的是六个 case，源码里是七个——`CoachError` 在计划成文之后多了
    /// `.invalidSessionID`。少列一个不会让这条测试变红，只会让那一个错误的代号无人管，
    /// 而它完全可能抄了隔壁的代号，那正是这条测试要拦的事。
    ///
    /// 二、计划把每个错误的消息写成 `"x"`，再断言代号里不含 `"x"`。**那条断言必然误报**：
    /// 正确的代号 `review-invalid-text` 本身就带着一个 x（`text` 里的）。
    /// 实测确认过：按计划实现之后跑这条，报的就是「代号里混进了错误消息：review-invalid-text」。
    /// 意图是「代号里不许出现错误消息的内容」，所以改用一段不可能与代号撞车的哨兵串——
    /// 这是把断言改准，不是放宽：`"x"` 那个版本对「代号 = 错误原文」这种真正的泄漏
    /// 反而只能靠碰运气认出来。
    func testEveryCoachErrorHasItsOwnCode() {
        // 七个 case 全挤成一个代号的话，「最近一次错误」就没有排障价值了。
        let body = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
        let errors: [CoachError] = [.invalidReviewText(body), .reviewNotFound(body),
                                    .reviewIncomplete(body), .stateUnreadable(body),
                                    .questionBankInvalid(body), .planImpossible(body),
                                    .invalidSessionID(body)]
        let codes = errors.map { DiagnosticsCode.of($0) }
        XCTAssertEqual(Set(codes).count, codes.count, "有两个错误共用了同一个代号：\(codes)")
        for code in codes {
            XCTAssertFalse(code.isEmpty)
            XCTAssertFalse(code.contains("SECRET"), "代号里混进了错误消息：\(code)")
        }
    }

    func testUnknownErrorsStillGetAStableCodeWithoutLeakingAnything() {
        struct SomethingElse: Error { let detail: String }
        let code = DiagnosticsCode.of(SomethingElse(detail: "MY-SECRET-ANSWER"))
        XCTAssertFalse(code.isEmpty, "认不出来也得给个代号，不能是空的")
        XCTAssertFalse(code.contains("MY-SECRET"), "把错误内容带出来了：\(code)")
    }

    func testEveryStageHasAChineseTitle() {
        // 「最近一次错误：parsingReview」对用户等于没写。
        for stage in DiagnosticsStage.allCases {
            XCTAssertFalse(stage.title.isEmpty, "\(stage) 没有中文说法")
            XCTAssertFalse(stage.title.contains(stage.rawValue), "\(stage) 直接显示了枚举名")
        }
    }

    func testSummaryReadsLikeASentenceAndCarriesAllThree() throws {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("x"), at: .fetchingReview, now: moment)
        let summary = try XCTUnwrap(log.last).summary
        XCTAssertTrue(summary.contains(DiagnosticsStage.fetchingReview.title))
        XCTAssertTrue(summary.contains("review-not-found"))
        XCTAssertTrue(summary.contains("2026"), "没带时间：\(summary)")
    }
}
