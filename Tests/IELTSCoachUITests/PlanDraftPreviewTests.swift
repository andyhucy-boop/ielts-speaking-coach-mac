import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PlanDraftPreviewTests: XCTestCase {

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    private func state(_ questions: [Question]) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        return s
    }

    func testDefaultDraftIsSevenDaysFullMock() {
        let draft = PlanDraft()
        XCTAssertEqual(draft.lengthDays, 7)
        XCTAssertEqual(draft.focusPart, .fullMock)
    }

    func testEvenSplitReadsAsASingleNumber() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...21).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertEqual(preview.questionCount, 21)
        XCTAssertEqual(preview.perDayText, "每天 3 题")
    }

    func testUnevenSplitReadsAsARange() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...23).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertEqual(preview.perDayText, "每天 3–4 题")
    }

    func testEmptyBankPointsAtTheQuestionBankPage() {
        let preview = PlanDraftPreviewBuilder.preview(state: state([]), draft: PlanDraft())
        XCTAssertFalse(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.contains("训练题库"))
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
        XCTAssertTrue(preview.perDayText.isEmpty,
                      "生成不了的时候还渲染「每天 N 题」，界面上会同时出现一句安排和一句拒绝，自相矛盾")
    }

    func testPartWithoutQuestionsSaysWhichPart() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...10).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part2))
        XCTAssertFalse(preview.canBuild)
        XCTAssertEqual(preview.questionCount, 0)
        XCTAssertTrue(preview.blockingReason.contains("Part 2"))
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
        XCTAssertTrue(preview.perDayText.isEmpty,
                      "生成不了的时候还渲染「每天 N 题」，界面上会同时出现一句安排和一句拒绝，自相矛盾")
    }

    /// `PlanDraft.lengthDays` 是不受约束的 Int，所以 `PlanDraft(lengthDays: 10)` 构造得出来。
    /// 真正生成时 `PlanBuilder.build` 只认 7/14/30，预览必须在同一档上也说不能生成，
    /// 否则就是「预览说能生成、点下去却报错」。
    func testUnsupportedCycleLengthIsBlockedWithASupportedAlternative() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...21).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 10, focusPart: .part1))
        XCTAssertFalse(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.contains("10"), "要说清现在选的是几天")
        XCTAssertTrue(preview.blockingReason.contains("7、14、30"), "要说清哪几档才受支持")
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
        XCTAssertTrue(preview.perDayText.isEmpty)
    }

    /// 天数闸门还在 `PlanBuilder` 里的时候，`PlanDraft(lengthDays: 0)` 会让预览
    /// 走到 `count / draft.lengthDays` 上除零崩溃——连报错都来不及。
    func testZeroDayCycleIsBlockedInsteadOfCrashing() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...21).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 0, focusPart: .part1))
        XCTAssertFalse(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
        XCTAssertTrue(preview.perDayText.isEmpty)
    }

    func testBlockingReasonIsEmptyWhenItCanBuild() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...14).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.isEmpty)
    }

    /// 预览说「能生成」，点下去却报错，是最伤信任的一类界面缺陷。
    /// 两处必须用同一个判据，这条穷举验证它们从不分歧。
    ///
    /// **10 是故意混进来的不受支持档位。** 只穷举 7/14/30 的话，恰好绕开了唯一
    /// 会分歧的那一档（`PlanBuilder` 的天数闸门），全绿也证明不了两处一致。
    func testPreviewAgreesWithWhatRegenerationActuallyDoes() {
        for count in 0...20 {
            for days in [7, 10, 14, 30] {
                let s = state((0..<count).map { q("b\($0)", 2) })
                let preview = PlanDraftPreviewBuilder.preview(
                    state: s, draft: PlanDraft(lengthDays: days, focusPart: .part2))
                var succeeded = false
                do {
                    _ = try PlanRegenerator.regenerate(state: s, lengthDays: days,
                                                       focusPart: .part2, createdAt: "t")
                    succeeded = true
                } catch { succeeded = false }
                XCTAssertEqual(preview.canBuild, succeeded,
                               "题数 \(count)、周期 \(days) 天：预览与实际不一致")
            }
        }
    }
}
