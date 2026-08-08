import XCTest
@testable import IELTSCoachUI

final class RetrainingStepTests: XCTestCase {
    func testThereAreExactlyThreeStepsNumberedFromOne() {
        XCTAssertEqual(RetrainingStep.allCases, [.evidence, .rehearsal, .speaking])
        XCTAssertEqual(RetrainingStep.allCases.map(\.stepNumber), [1, 2, 3])
    }

    func testEveryStepHasChineseTitleAndExplanation() {
        for step in RetrainingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) 没有标题")
            XCTAssertFalse(step.explanation.isEmpty, "\(step) 没有说明")
        }
    }

    /// 全项目的硬性约束：面向用户的文案要同时说清「发生了什么」和「下一步做什么」。
    func testEveryExplanationTellsTheLearnerWhatToDoNext() {
        for step in RetrainingStep.allCases {
            XCTAssertTrue(step.explanation.contains("下一步"),
                          "\(step) 的说明没写下一步该做什么")
        }
    }

    /// **本任务最重要的一条。** 一旦开始答题还看得见高分版，学员就是在照着念，
    /// 复训退化成朗读，而界面上一点异常都看不出来。
    func testModelAnswerIsOnlyVisibleWhileReviewingEvidence() {
        XCTAssertTrue(RetrainingStep.evidence.showsModelAnswer)
        for step in RetrainingStep.allCases where step != .evidence {
            XCTAssertFalse(step.showsModelAnswer, "\(step) 还在显示高分版——那等于照着念")
        }
    }

    func testEvidenceIsAlsoWithdrawnOnceTheLearnerStartsAnswering() {
        XCTAssertTrue(RetrainingStep.evidence.showsEvidence)
        for step in RetrainingStep.allCases where step != .evidence {
            XCTAssertFalse(step.showsEvidence, "\(step) 还在显示当时的原话")
        }
    }

    /// 目标是行为指令，不是答案。撤掉它，学员就不知道这一次要做到什么，
    /// 复训和随便再练一遍就没区别了。
    func testTheSinglePointGoalStaysVisibleTheWholeTime() {
        for step in RetrainingStep.allCases {
            XCTAssertTrue(step.showsGoal, "\(step) 把本次唯一目标也撤掉了")
        }
    }

    func testOnlyTheRehearsalStepCanStartThePractice() {
        XCTAssertEqual(RetrainingStep.allCases.filter(\.canStartPractice), [.rehearsal])
    }

    func testStepsChainInOrderAndStopAtSpeaking() {
        XCTAssertEqual(RetrainingStep.evidence.next, .rehearsal)
        XCTAssertEqual(RetrainingStep.rehearsal.next, .speaking)
        XCTAssertNil(RetrainingStep.speaking.next)
    }

    /// 换题验证不再回看证据——**正因为不给看，才知道是不是真会了**。
    func testTransferRunSkipsTheEvidenceStep() {
        XCTAssertEqual(RetrainingRun.original.firstStep, .evidence)
        XCTAssertEqual(RetrainingRun.transfer.firstStep, .rehearsal)
    }

    func testBothRunsHaveChineseTitles() {
        for run in RetrainingRun.allCases {
            XCTAssertFalse(run.title.isEmpty, "\(run) 没有标题")
        }
    }

    // MARK: - 补两条守卫（不在计划里，理由见各自注释）

    /// 上面两条「有中文标题」其实只验了「非空」——三步全都返回 "x" 照样绿，
    /// 两条路线叫同一个名字也照样绿。而这两样都是用户唯一据以判断
    /// 「我现在在第几步」「这颗按钮会干什么」的东西。
    ///
    /// 参照 `PracticeRunnerTests.testEveryStageSaysSomethingDifferent`（同一类空转，
    /// 本项目已经在别处栽过一次）。
    func testEveryStepAndRunSaysSomethingOfItsOwn() {
        let titles = RetrainingStep.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "有两步叫同一个名字，用户分不出走到哪儿了")

        let explanations = RetrainingStep.allCases.map(\.explanation)
        XCTAssertEqual(Set(explanations).count, explanations.count,
                       "有两步的说明一模一样，那句「下一步」就指不到这一步该做的事")

        let runTitles = RetrainingRun.allCases.map(\.title)
        XCTAssertEqual(Set(runTitles).count, runTitles.count,
                       "「重答原题」和「换一道题验证」不能叫同一个名字——用户点之前得知道选的是哪一趟")
    }

    /// 铁律 6：面向用户的文案必须是中文。上面那两条测试的名字里写着 Chinese，
    /// 断言却只看非空——写成英文一样全绿。这里当场验有没有汉字。
    func testAllUserFacingCopyIsActuallyInChinese() {
        for step in RetrainingStep.allCases {
            XCTAssertTrue(containsHanCharacter(step.title), "\(step) 的标题不是中文：\(step.title)")
            XCTAssertTrue(containsHanCharacter(step.explanation),
                          "\(step) 的说明不是中文：\(step.explanation)")
        }
        for run in RetrainingRun.allCases {
            XCTAssertTrue(containsHanCharacter(run.title), "\(run) 的标题不是中文：\(run.title)")
        }
    }

    /// CJK 统一表意文字基本区。够用了：这里只要回答「这句话里有没有汉字」。
    private func containsHanCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
