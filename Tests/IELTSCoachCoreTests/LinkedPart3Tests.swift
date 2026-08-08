import XCTest
@testable import IELTSCoachCore

/// 一张 Part 2 cue card **自己那一组 Part 3 追问**。
///
/// 用户原话：「我练 Part two 的时候，顺带也把对应的 Part three 问题一起给练了。」
/// 「对应的」三个字是全部重点：真实考试里 Part 3 就是紧接着**这张卡**问下来的。
final class LinkedPart3Tests: XCTestCase {

    private let cueCard = Question(
        id: "p2-shop", part: 2, topic: "地点",
        prompt: "Describe a shop or store you enjoy visiting",
        followups: ["Where it is", "What it sells"])

    /// 题库真实的挂法：Part 3 那道题的 `topic` 与题干**都等于**那张卡的原文
    /// （`TopicQuestions.part3`）。这一条同时钉住了配对判据的来源——
    /// 判据不是我编的，是题库建模决定的。
    private func pairedPart3(for cueCard: Question,
                             prompts: [String] = ["How have shopping habits changed?",
                                                  "Why do some people prefer small shops?"])
    -> Question {
        TopicQuestions.part3(cueCard: cueCard.prompt, prompts: prompts)
    }

    func testTheJoinKeyIsTheOneTheQuestionBankActuallyUses() {
        let part3 = pairedPart3(for: cueCard)
        XCTAssertEqual(part3.topic, cueCard.prompt,
                       "题库里 Part 3 的 topic 就是它所属 cue card 的题干——"
                           + "这正是配对唯一的依据（`TopicQuestions.part3`）")
        XCTAssertEqual(part3.part, 3)
    }

    func testItFindsTheCardsOwnPart3Questions() throws {
        let bank = [cueCard,
                    Question(id: "p2-other", part: 2, topic: "地点",
                             prompt: "Describe a park you like"),
                    pairedPart3(for: cueCard),
                    TopicQuestions.part3(cueCard: "Describe a park you like",
                                         prompts: ["Are city parks important?"])]
        let found = try XCTUnwrap(LinkedPart3.reference(for: cueCard, in: bank))
        XCTAssertEqual(found.topic, cueCard.prompt)
        XCTAssertEqual(found.followups.first, "How have shopping habits changed?",
                       "配到了别的一组追问——考官会拿另一张卡的问题来问考生")
    }

    /// **判据要窄。** 同话题标签（`topic == "地点"`）、题干相近都不算数。
    /// 配错一张卡的后果是考官拿着另一张卡的追问去问，而屏幕上一切正常——
    /// 宁可配不上然后明说，也不要配错然后闭嘴。
    func testItRefusesToGuessWhenNothingMatchesExactly() {
        let nearMiss = TopicQuestions.part3(
            cueCard: "Describe a shop or store you enjoy visiting a lot",
            prompts: ["How have shopping habits changed?"])
        let sameCategory = Question(id: "p3-cat", part: 3, topic: "地点",
                                    prompt: "地点", followups: ["Are cities changing?"])
        XCTAssertNil(LinkedPart3.reference(for: cueCard, in: [nearMiss, sameCategory]),
                     "题干只是相近、或者只是同一个话题标签，就被当成了这张卡的追问")
    }

    /// 空追问 = 没配上。一条空的参考题和没配上完全等价，
    /// 而把它当成配上了会让提示词里那句「你得自己临场编」消失——
    /// 考官既没拿到问句、也没被告知要编（铁律：禁止静默失败）。
    func testAPairedQuestionWithNoFollowupsCountsAsNotFound() {
        let empty = TopicQuestions.part3(cueCard: cueCard.prompt, prompts: [])
        XCTAssertNil(LinkedPart3.reference(for: cueCard, in: [empty]))
    }

    /// 只有 Part 2 的题才有「对应的 Part 3 追问」这回事。
    ///
    /// 拿一道 Part 3 的题去配的话，它会配到自己（`topic == prompt`），
    /// 于是同一组问句在提示词里出现两遍。
    func testOnlyACueCardHasAPairedPart3Set() {
        let part3 = pairedPart3(for: cueCard)
        XCTAssertNil(LinkedPart3.reference(for: part3, in: [part3]),
                     "一道 Part 3 的题配到了它自己，那组问句会在提示词里出现两遍")

        let part1 = TopicQuestions.part1(topic: "Home", prompts: ["Do you live in a flat?"])
        XCTAssertNil(LinkedPart3.reference(for: part1, in: [part1]))
    }

    /// 题干是空的（导入残缺）时不许乱配：空字符串会匹配上一堆 topic 也为空的脏数据。
    func testAnEmptyCueCardTextNeverMatchesAnything() {
        let broken = Question(id: "p2-broken", part: 2, topic: "地点", prompt: "   ")
        let alsoBroken = Question(id: "p3-broken", part: 3, topic: "",
                                  prompt: "", followups: ["x"])
        XCTAssertNil(LinkedPart3.reference(for: broken, in: [alsoBroken]))
    }

    /// 题库里根本没有配对的那道题（用户自己用 CSV 加的卡、或者导入残缺）。
    func testItReturnsNilWhenTheBankHasNoPart3ForThatCard() {
        XCTAssertNil(LinkedPart3.reference(for: cueCard, in: [cueCard]))
        XCTAssertNil(LinkedPart3.reference(for: cueCard, in: []))
    }

    /// **这条把配对一路验到提示词里。** 中间任何一环断掉（配对没做、
    /// `SessionSetup` 没带、提示词没拼），这条就红。
    func testThePairedQuestionsTravelAllTheWayIntoTheExaminerPrompt() {
        let bank = [cueCard, pairedPart3(for: cueCard)]
        let setup = SessionSetup(
            question: cueCard, focusPart: .part2And3, durationMinutes: 9, goal: "",
            part3Reference: LinkedPart3.reference(for: cueCard, in: bank))
        let text = ExaminerPrompt.build(setup: setup)
        XCTAssertTrue(text.contains("- How have shopping habits changed?"),
                      "配对好的追问没有进提示词：\n\(text)")
        XCTAssertFalse(text.contains("No Part 3 reference questions were found"),
                       "明明配上了，提示词却还在说没配上：\n\(text)")
    }
}
