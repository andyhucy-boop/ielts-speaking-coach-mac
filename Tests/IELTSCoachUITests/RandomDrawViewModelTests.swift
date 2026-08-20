import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 「随机抽题」弹层上那些可测的东西：每个 Part 现在有多少可抽、三个数字加起来是一场
/// 什么练习、抽之前提醒什么、抽完交代什么。
///
/// 界面本身（三个步进器、那颗勾选框、抽签动画）没法单元测，钉它们的是文件末尾那几条
/// 源码闸——它们守的都是「屏幕上说的」和「真正发生的」不许分家。
@MainActor
final class RandomDrawViewModelTests: XCTestCase {

    private func topic(_ name: String, status: String = "new") -> Question {
        var question = TopicQuestions.part1(topic: name, prompts: ["Do you like \(name)?"])
        question.status = status
        return question
    }

    private func card(_ name: String, status: String = "new") -> Question {
        Question(id: "card-\(name)", part: 2, topic: "Place",
                 prompt: "Describe \(name).", status: status)
    }

    private func discussion(_ name: String) -> Question {
        TopicQuestions.part3(cueCard: "Describe \(name).", prompts: ["Is that a good thing?"])
    }

    private var bank: [Question] {
        [topic("Home"), topic("Food"), topic("Weather", status: "practiced"),
         card("a shop"), card("a person", status: "practiced"),
         discussion("a shop")]
    }

    private var model: RandomDrawViewModel { RandomDrawViewModel(questions: bank) }

    // MARK: - 现在有多少可抽

    /// 两个数都要有：只写总数的话，勾上「只抽没练过的」之后用户不知道还剩多少；
    /// 只写没练过的话，他不知道题库到底有多大。
    func testTheAvailabilityLineShowsBothTheTotalAndTheFreshCount() {
        XCTAssertEqual(model.availabilityLine(forPart: .one), "共 3 道，没练过 2 道")
        XCTAssertEqual(model.availabilityLine(forPart: .two), "共 2 道，没练过 1 道")
    }

    /// **步进器卡在「一共多少道」上，不是「没练过多少道」上。**
    ///
    /// 卡在后者的话，用户勾上「只抽没练过的」那一刻，他刚设好的数字会被悄悄改小——
    /// 而他并没有动那个数字。要得比没练过的多是允许的，抽之前有提醒、抽完有交代。
    func testTheStepperCeilingIsTheWholePartNotJustTheFreshOnes() {
        XCTAssertEqual(model.maximum(inPart: .two), 2)
        XCTAssertEqual(model.fresh(inPart: .two), 1)
    }

    func testTheStepperCeilingNeverExceedsTheGuardRail() {
        let many = (1...30).map { topic("Topic \($0)") }
        XCTAssertEqual(RandomDrawViewModel(questions: many).maximum(inPart: .one),
                       RandomDraw.Counts.maximumPerPart)
    }

    /// 打开弹层那一刻，默认值要夹到「现在真的抽得到」的范围里——
    /// 否则步进器会停在一个它根本调不到的数上（范围是 `0...0`），
    /// 屏幕上写着 1、抽出来是 0，而没有任何解释。
    func testTheDefaultCountsAreClampedToWhatTheBankActuallyHas() {
        let onlyPart1 = RandomDrawViewModel(questions: [topic("Home")])
        let clamped = onlyPart1.clampedToAvailable(RandomDrawViewModel.defaultCounts)
        XCTAssertEqual(clamped[.one], 1)
        XCTAssertEqual(clamped[.two], 0)
        XCTAssertEqual(clamped[.three], 0)
    }

    // MARK: - 抽之前那句话

    func testTheSummarySaysWhatWillBeDrawnAndHowLongItTakes() throws {
        let counts = RandomDraw.Counts(one: 2, two: 1, three: 1)
        let summary = try XCTUnwrap(model.summary(forCounts: counts))
        XCTAssertTrue(summary.contains("Part 1 2 道"), summary)
        XCTAssertTrue(summary.contains("Part 1 → Part 2 → Part 3"), summary)
        XCTAssertTrue(summary.contains("\(model.estimatedMinutes(forCounts: counts)) 分钟"), summary)
    }

    /// 抽之前说的时长与抽完之后说的，必须是同一套算法。
    /// 抽完变短是正常的（少抽了几道），而对同一组题给出两个数字就不正常了。
    func testTheEstimateBeforeDrawingMatchesTheOneAfter() {
        let counts = RandomDraw.Counts(one: 2, two: 1, three: 1)
        var generator = SystemRandomNumberGenerator()
        let result = RandomDraw.draw(from: bank, counts: counts, excludingPracticed: false,
                                     using: &generator)
        XCTAssertEqual(result.count(inPart: .one), 2, "题库够用，这一条才有意义")
        XCTAssertEqual(model.estimatedMinutes(forCounts: counts), result.estimatedMinutes)
    }

    /// 默认值抽出来恰好等于一场全真模考的时长。两条路给出两个数字的话，
    /// 用户没有任何办法知道哪个是真的。
    func testTheDefaultCountsRunAsLongAsAFullMock() {
        XCTAssertEqual(model.estimatedMinutes(forCounts: RandomDrawViewModel.defaultCounts),
                       FocusPart.fullMock.defaultDurationMinutes)
    }

    /// 全 0 与题库空是两件事，说的话也不一样：一个改数量就行，一个得先去导题库。
    func testTheTwoWaysOfHavingNothingToDrawSayDifferentThings() throws {
        let allZero = try XCTUnwrap(model.emptyNotice(forCounts: RandomDraw.Counts()))
        XCTAssertTrue(allZero.contains("调到 1 以上"), allZero)

        let emptyBank = try XCTUnwrap(RandomDrawViewModel(questions: [])
            .emptyNotice(forCounts: RandomDraw.Counts()))
        XCTAssertTrue(emptyBank.contains("训练题库"), emptyBank)
        XCTAssertNil(model.emptyNotice(forCounts: RandomDraw.Counts(one: 1)))
    }

    /// **抽之前就得提醒。** 等抽完再说的话，用户已经看着一组比他要的少的题，
    /// 得先弄明白少了什么才知道怎么办。
    func testAskingForMoreThanTheFreshOnesWarnsBeforeDrawing() throws {
        let warnings = model.warnings(forCounts: RandomDraw.Counts(two: 2),
                                      excludingPracticed: true)
        let line = try XCTUnwrap(warnings.first)
        XCTAssertTrue(line.contains("只抽没练过的"),
                      "没指向那个一按就解决的开关：\(line)")
        XCTAssertTrue(model.warnings(forCounts: RandomDraw.Counts(two: 2),
                                     excludingPracticed: false).isEmpty,
                      "开关关掉之后题库里够 2 道，不该再提醒")
    }

    func testAskingForMoreThanTheBankHasPointsAtImportingInstead() throws {
        let line = try XCTUnwrap(model.warnings(forCounts: RandomDraw.Counts(two: 5),
                                                excludingPracticed: false).first)
        XCTAssertTrue(line.contains("训练题库"), line)
        XCTAssertFalse(line.contains("取消勾选"),
                       "题库本来就不够，叫他去动那个开关是白动一次：\(line)")
    }

    // MARK: - 抽完之后那句话

    /// 两种短缺的下一步完全不同，说的话必须不一样——分不清的话，
    /// 用户手边那个一按就解决的开关他不会想到去按。
    func testTheTwoKindsOfShortfallGiveDifferentNextSteps() {
        let bySwitch = RandomDraw.Result(
            questions: [], shortfalls: [.init(part: .two, asked: 2, got: 0,
                                              causedByExcludingPracticed: true)],
            requested: RandomDraw.Counts(two: 2), excludedPracticed: true, part3CardIDs: [:])
        let byBank = RandomDraw.Result(
            questions: [], shortfalls: [.init(part: .two, asked: 9, got: 2,
                                              causedByExcludingPracticed: false)],
            requested: RandomDraw.Counts(two: 9), excludedPracticed: false, part3CardIDs: [:])
        XCTAssertTrue(RandomDrawViewModel.shortfallNotices(for: bySwitch)[0].contains("取消勾选"))
        XCTAssertTrue(RandomDrawViewModel.shortfallNotices(for: byBank)[0].contains("训练题库"))
    }

    func testDrawingNothingAtAllSaysSoInsteadOfShowingAnEmptyList() {
        let empty = RandomDraw.Result(questions: [], shortfalls: [],
                                      requested: RandomDraw.Counts(), excludedPracticed: false,
                                      part3CardIDs: [:])
        XCTAssertTrue(RandomDrawViewModel.resultSummary(for: empty).contains("一道题都没抽到"))
    }

    /// 题库里 Part 3 的题干**就是**它所属 cue card 的原文。原样显示的话，
    /// 屏幕上会是一句「Describe a shop.」，而这一场其实是抽象讨论——
    /// 提示词那边已经为这件事改过一轮，界面不能还在显示那句会误导人的原话。
    func testAPart3RowShowsTheDiscussionThemeNotTheCueCardSentence() {
        let label = RandomDrawViewModel.label(for: discussion("a shop"))
        XCTAssertFalse(label.lowercased().contains("describe"), label)
        XCTAssertEqual(label, "a shop")
        XCTAssertEqual(RandomDrawViewModel.label(for: card("a shop")), "Describe a shop.",
                       "Part 2 的题干就是那张卡本身，不许改写")
    }

    // MARK: - 屏幕上说的 == 真正发生的

    /// 卡片副标题里承诺的两样东西，弹层里都得真有——
    /// 不然用户会去找一个不存在的控件（`freePick` 那条副标题就踩过这个坑）。
    func testTheRandomDrawSubtitleMatchesWhatTheSheetActuallyHas() throws {
        let subtitle = PracticeRoute.randomDraw.subtitle
        let sheet = try SourceGuard.code("Session/PracticeSheet.swift")

        XCTAssertTrue(subtitle.contains("每个 Part 抽几道"),
                      "副标题没说「每个 Part 抽几道」，而那正是这条路线和自由选题的区别：\(subtitle)")
        XCTAssertTrue(sheet.contains("Stepper(value: drawCountBinding(for: part)"),
                      "弹层里没有那三个绑到 `drawCountBinding(for:)` 的步进器，"
                          + "副标题却承诺可以定每个 Part 抽几道。")

        XCTAssertTrue(subtitle.contains("练过的"),
                      "副标题没提「练过的要不要」——那是用户点名要的第二件事：\(subtitle)")
        XCTAssertTrue(sheet.contains(#"Toggle("只抽没练过的题", isOn: $excludePracticed)"#),
                      "弹层里没有「只抽没练过的题」那个勾选框，副标题却承诺可以选。")
    }

    /// 改了数量却不清掉上一次抽的结果的话，屏幕上的数字和真正会练的那一组对不上，
    /// 而「开始练习」按下去练的正是那一组旧的——一个字的提示都没有。
    func testChangingACountThrowsAwayThePreviousDraw() throws {
        let binding = try SourceGuard.functionBody(
            named: "drawCountBinding", in: try SourceGuard.code("Session/PracticeSheet.swift"))
        XCTAssertTrue(binding.contains("drawn = nil"),
                      "改数量之后上一次抽的那一组还挂在下面。实际取到的是：\n\(binding)")
    }

    /// **抽签结果在按下按钮那一刻就定了，动画只是把它揭开。**
    /// 让动画去决定抽到什么的话，中途关掉窗口或者动画被系统打断，
    /// 这一场抽到的就成了一件谁也说不清的事。
    func testTheDrawIsDecidedBeforeTheAnimationStarts() throws {
        let roll = try SourceGuard.functionBody(
            named: "roll", in: try SourceGuard.code("Session/PracticeSheet.swift"))
        let decided = try XCTUnwrap(roll.range(of: "RandomDraw.draw("))
        let animated = try XCTUnwrap(roll.range(of: "isRolling = true"))
        XCTAssertTrue(decided.lowerBound < animated.lowerBound,
                      "动画先开、结果后算。实际取到的是：\n\(roll)")
        XCTAssertTrue(roll.contains("reduceMotion"),
                      "没有尊重系统的「减弱动态效果」。实际取到的是：\n\(roll)")
    }
}
