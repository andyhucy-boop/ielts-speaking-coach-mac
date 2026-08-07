import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PlanViewModelTests: XCTestCase {

    private func q(_ id: String, _ part: Int = 1) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "P-\(id)")
    }

    private func state(_ questions: [Question], _ plan: TrainingPlan?) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.plan = plan
        return s
    }

    private func plan(_ days: [PlanDay], length: Int = 7,
                      focus: FocusPart = .part1) -> TrainingPlan {
        TrainingPlan(lengthDays: length, createdAt: "2026-08-06T00:00:00Z",
                     days: days, focusPart: focus)
    }

    func testNoPlanMeansEmptyEverything() {
        let vm = PlanViewModel(state: state([q("a")], nil))
        XCTAssertFalse(vm.hasPlan)
        XCTAssertTrue(vm.dayRows.isEmpty)
        XCTAssertNil(vm.todayNumber)
        XCTAssertEqual(vm.progress.total, 0)
        XCTAssertFalse(vm.isFinished)
        // 没有计划时这两处必须是 nil，否则计划页会显示出一份根本不存在的计划的周期与重点。
        XCTAssertNil(vm.lengthDays)
        XCTAssertNil(vm.focusPart)
    }

    /// 「今天」= 第一个还有题没做完的那一天，与日历日期无关。
    /// 用日历推进会让请假两天的人一打开就看到「落后 2 天」——那只会让人不想练。
    func testTodayIsTheFirstDayThatStillHasSomethingToDo() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a", "b"]),
            PlanDay(id: 2, questionIds: ["c", "d"], completedQuestionIds: ["c"]),
            PlanDay(id: 3, questionIds: ["e"], completedQuestionIds: [])
        ])
        let vm = PlanViewModel(state: state(["a", "b", "c", "d", "e"].map { q($0) }, p))
        XCTAssertEqual(vm.todayNumber, 2, "第 2 天还有一道没做完，它就是「今天」")
        XCTAssertEqual(vm.dayRows.first(where: \.isToday)?.id, 2)
        XCTAssertEqual(vm.dayRows.filter(\.isToday).count, 1, "「今天」只能有一天")

        // 每天的「这天练完了没有」也得是真的：写死成 false 的话，
        // 练完的那几天在计划页上永远不打勾，用户会以为自己的练习没被记住。
        XCTAssertEqual(vm.dayRows[0].isComplete, true, "第 1 天两道题都做完了")
        XCTAssertEqual(vm.dayRows[1].isComplete, false, "第 2 天还差一道")
        XCTAssertEqual(vm.dayRows[2].isComplete, false, "第 3 天一道都没做")
    }

    func testProgressCountsQuestionsNotDays() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a", "b"]),
            PlanDay(id: 2, questionIds: ["c", "d"], completedQuestionIds: ["c"])
        ])
        let vm = PlanViewModel(state: state(["a", "b", "c", "d"].map { q($0) }, p))
        XCTAssertEqual(vm.progress.done, 3)
        XCTAssertEqual(vm.progress.total, 4)
        XCTAssertFalse(vm.isFinished)
    }

    /// 题数少于天数时（旧版本与命令行生成的计划就是这种形状），尾部会留下没有题的空天，
    /// 而 PlanDay.isComplete 要求 questionIds 非空，空天永远不算完成。
    /// 若进度沿用 TrainingPlan.isComplete，这类计划永远显示不出「已完成」，
    /// 用户会一直以为自己还差一点。
    func testFinishedEvenWhenLegacyPlanHasTrailingEmptyDays() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
            PlanDay(id: 2, questionIds: ["b"], completedQuestionIds: ["b"]),
            PlanDay(id: 3, questionIds: [], completedQuestionIds: []),
            PlanDay(id: 4, questionIds: [], completedQuestionIds: [])
        ])
        let vm = PlanViewModel(state: state([q("a"), q("b")], p))
        XCTAssertTrue(vm.isFinished)
        XCTAssertNil(vm.todayNumber, "全做完之后不该再有「今天」")
        XCTAssertEqual(vm.dayRows.count, 2, "没有题的空天不该出现在列表里")
    }

    func testRowsCarryPromptAndCompletionFromTheBank() throws {
        let p = plan([PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a"])])
        let vm = PlanViewModel(state: state([q("a"), q("b", 2)], p))
        let day = try XCTUnwrap(vm.dayRows.first)
        XCTAssertEqual(day.items.map(\.id), ["a", "b"])
        XCTAssertEqual(day.items[0].prompt, "P-a")
        XCTAssertEqual(day.items[0].topic, "Home", "话题写死成空串的话，计划页每行都少一个标签")
        XCTAssertTrue(day.items[0].isCompleted)
        XCTAssertFalse(day.items[1].isCompleted)
        XCTAssertEqual(day.items[0].part, 1)
        XCTAssertEqual(day.items[1].part, 2)
        XCTAssertFalse(day.items.contains(where: \.isMissing))
    }

    /// 换季重新导入时出题方删掉了某道题，计划里还留着它的 id。
    /// 这一行必须显示成「这道题没了 + 怎么办」，不能是一行空白——
    /// 空白会让用户以为程序坏了。
    func testMissingQuestionBecomesAnExplainedRowNotABlankOne() throws {
        let p = plan([PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])])
        let vm = PlanViewModel(state: state([q("a")], p))
        let row = try XCTUnwrap(vm.dayRows.first?.items.first)
        XCTAssertTrue(row.isMissing)
        XCTAssertFalse(row.prompt.isEmpty)
        XCTAssertTrue(row.prompt.contains("下一步"))
        // 那道题的 id 得留着，否则界面上连「是哪一道没了」都说不出来。
        XCTAssertEqual(row.id, "gone")
        XCTAssertEqual(row.part, 0, "题目不在题库里，Part 无从得知，按约定记 0")
    }

    /// 题目没了、但用户此前已经练过它——那一格进度不能因为题库更新就凭空消失。
    /// 换季重新导入是这个产品的日常（成品标准第 12 条），不是边缘情况。
    func testAMissingQuestionThatWasAlreadyPracticedStillCountsAsDone() throws {
        let p = plan([PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: ["gone"])])
        let vm = PlanViewModel(state: state([q("a")], p))
        let row = try XCTUnwrap(vm.dayRows.first?.items.first)
        XCTAssertTrue(row.isMissing)
        XCTAssertTrue(row.isCompleted, "练过的题不能因为题库里没有了就变回没练过")
        XCTAssertEqual(vm.progress.done, 1)
        XCTAssertTrue(vm.isFinished)
    }

    func testExposesLengthAndFocusPartOfTheCurrentPlan() {
        let p = plan([PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])],
                     length: 14, focus: .part3)
        let vm = PlanViewModel(state: state([q("a")], p))
        XCTAssertTrue(vm.hasPlan)
        XCTAssertEqual(vm.lengthDays, 14)
        XCTAssertEqual(vm.focusPart, .part3)
    }

    /// 手工拼的题库里同一个 id 出现两次很常见（复制粘贴忘改编号）。
    /// 用 Dictionary(uniqueKeysWithValues:) 建索引会直接 fatalError 闪退整个 App——
    /// QuestionBankImporter 里已经栽过一次，那条注释还在。
    func testDuplicateQuestionIDsInTheBankDoNotCrash() {
        let p = plan([PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])])
        let vm = PlanViewModel(state: state([q("a"), q("a")], p))
        XCTAssertEqual(vm.dayRows.first?.items.count, 1)
        XCTAssertEqual(vm.dayRows.first?.items.first?.prompt, "P-a",
                       "重复 id 不能让这一行退化成「这道题没了」")
    }
}
