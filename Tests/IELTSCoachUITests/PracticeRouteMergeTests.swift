import XCTest

@testable import IELTSCoachUI

/// 「自由选题」和「随机抽题」在今日训练页上合成一张卡片。
///
/// 这段决定的是**用户看得见几张卡**，而视图里的一句 `filter` 没有任何测试管得住——
/// 所以它是纯函数，也所以有这一组。
final class PracticeRouteMergeTests: XCTestCase {

    private let all: [PracticeRoute] = [.planToday, .freePick, .randomDraw, .continueLast, .retrain]

    func testTheTwoPickRoutesBecomeOne() {
        let merged = PracticeRouteMerge.collapsePickRoutes(all, preferring: .planToday)
        XCTAssertEqual(merged.filter(\.isPickEntry).count, 1,
                       "两条选题路线没有合成一张卡片，实际是：\(merged)")
    }

    /// **留下的必须是用户偏好的那一条。**
    ///
    /// 进去之后弹层就停在它对应的档（偏好「随机抽题」就直接停在随机那一档）。
    /// 留错的话，把默认路线设成随机抽题的人，每次都得先点一下开关。
    func testItKeepsTheRouteTheUserPrefersSoTheSheetOpensOnThatMode() {
        let merged = PracticeRouteMerge.collapsePickRoutes(all, preferring: .randomDraw)
        XCTAssertTrue(merged.contains(.randomDraw), "偏好随机抽题，留下的却不是它：\(merged)")
        XCTAssertFalse(merged.contains(.freePick))

        let other = PracticeRouteMerge.collapsePickRoutes(all, preferring: .freePick)
        XCTAssertTrue(other.contains(.freePick))
        XCTAssertFalse(other.contains(.randomDraw))
    }

    /// 偏好不是这两条中任何一条时，留列表里先出现的那一条。
    func testWhenThePreferenceIsSomethingElseItKeepsTheFirstOne() {
        XCTAssertEqual(
            PracticeRouteMerge.collapsePickRoutes([.randomDraw, .freePick], preferring: .retrain),
            [.randomDraw],
            "偏好与选题无关时，该留列表里先出现的那一条")
    }

    /// **顺序不许重排。** 排序是解析器的事——排最前的那张是这一页唯一的主行动，
    /// 而它跟着用户在学习计划页选的默认路线走。这里只删，不动位置。
    func testItOnlyRemovesAndNeverReorders() {
        let input: [PracticeRoute] = [.continueLast, .randomDraw, .planToday, .freePick, .retrain]
        let merged = PracticeRouteMerge.collapsePickRoutes(input, preferring: .freePick)
        XCTAssertEqual(merged, [.continueLast, .planToday, .freePick, .retrain],
                       "顺序被动过了。排最前的那张是这一页唯一的主行动。实际是：\(merged)")
    }

    /// 偏好的那条这次不可用时（被解析器筛掉了），退回列表里现有的那一条。
    /// 直接按偏好去留的话，这张卡片会整个消失——而用户明明有题库。
    func testAPreferredRouteThatIsNotAvailableFallsBackInsteadOfLosingTheCard() {
        let merged = PracticeRouteMerge.collapsePickRoutes([.planToday, .freePick],
                                                           preferring: .randomDraw)
        XCTAssertTrue(merged.contains(.freePick),
                      "偏好的那条不在列表里，结果连另一条也没留下——选题卡片整个消失了：\(merged)")
    }

    /// 一条选题路线都没有时原样返回，不许凭空造一条出来。
    func testWithNoPickRouteAtAllNothingIsInvented() {
        XCTAssertEqual(
            PracticeRouteMerge.collapsePickRoutes([.planToday, .retrain], preferring: .freePick),
            [.planToday, .retrain])
    }

    /// 合并卡片那两句文案不能是空的——空的话卡片上只剩一个箭头。
    func testTheMergedCardHasItsOwnCopy() {
        XCTAssertFalse(PracticeRoute.pickEntryTitle.isEmpty)
        XCTAssertFalse(PracticeRoute.pickEntrySubtitle.isEmpty)
        // 标题不许偏向其中一种做法：先说哪一种都会让另一种像是次要的。
        for biased in ["随机", "自由"] {
            XCTAssertFalse(
                PracticeRoute.pickEntryTitle.contains(biased),
                "合并卡片的标题里出现了「\(biased)」，那会让另一种做法显得次要。"
                    + "实际是：\(PracticeRoute.pickEntryTitle)")
        }
        // 副标题要说清「可多选 Part」——那几个勾选框真的在弹层里，不说没人会去勾。
        XCTAssertTrue(PracticeRoute.pickEntrySubtitle.contains("可多选"),
                      "副标题没说 Part 可以多选：\(PracticeRoute.pickEntrySubtitle)")
    }
}
