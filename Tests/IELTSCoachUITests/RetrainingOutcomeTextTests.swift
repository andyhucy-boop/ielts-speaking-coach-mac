import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingOutcomeTextTests: XCTestCase {
    func testEveryOutcomeHasChineseHeadlineAndDetail() {
        for outcome in RetrainingOutcome.allCases {
            XCTAssertFalse(RetrainingOutcomeText.headline(for: outcome).isEmpty, "\(outcome) 缺标题")
            XCTAssertFalse(RetrainingOutcomeText.detail(for: outcome).isEmpty, "\(outcome) 缺说明")
        }
    }

    /// 一次没被点名不等于改掉了。给一个看起来精确、实则站不住的结论，
    /// 会让人盯着结论而不是盯着问题——与「不预测雅思分数」是同一条原则
    /// （DEFINITION-OF-DONE 第 4 节）。
    func testGoodNewsIsNeverUpgradedIntoAVerdict() {
        let text = RetrainingOutcomeText.headline(for: .notNamedAgain)
            + RetrainingOutcomeText.detail(for: .notNamedAgain)
        // 拦的是**词干**，不是「已掌握」这几个整词。实测过：把标题改成
        //「这个问题已经改掉了」，整词名单一条都不命中——多一个「经」字就绕过去了。
        for forbidden in ["掌握", "改掉", "解决", "不用再练"] {
            XCTAssertFalse(text.contains(forbidden), "文案里出现了下结论的措辞：\(forbidden)")
        }
        XCTAssertTrue(RetrainingOutcomeText.headline(for: .notNamedAgain).contains("没有再被点名"))
    }

    func testEveryDetailTellsTheLearnerWhatToDoNext() {
        for outcome in RetrainingOutcome.allCases {
            XCTAssertTrue(RetrainingOutcomeText.detail(for: outcome).contains("下一步"),
                          "\(outcome) 的说明没写下一步该做什么")
        }
    }

    func testNoReportSaysTheDataIsMissingRatherThanClaimingSuccess() {
        let text = RetrainingOutcomeText.headline(for: .noReport)
            + RetrainingOutcomeText.detail(for: .noReport)
        XCTAssertFalse(text.contains("没有再被点名"), "拿不到复盘不能说成好消息")
    }

    /// 三种结果的标题必须互不相同。全都返回同一句话（哪怕是一句正确的中文）
    /// 会让「又被点名」和「没有再被点名」在界面上长得一模一样——
    /// 那时上面几条测试仍然全绿，用户却完全分不出这一场练成没练成。
    func testTheThreeOutcomesDoNotShareTheSameWording() {
        let headlines = Set(RetrainingOutcome.allCases.map(RetrainingOutcomeText.headline(for:)))
        XCTAssertEqual(headlines.count, RetrainingOutcome.allCases.count, "三种结果的标题撞了")
        let details = Set(RetrainingOutcome.allCases.map(RetrainingOutcomeText.detail(for:)))
        XCTAssertEqual(details.count, RetrainingOutcome.allCases.count, "三种结果的说明撞了")
    }
}
