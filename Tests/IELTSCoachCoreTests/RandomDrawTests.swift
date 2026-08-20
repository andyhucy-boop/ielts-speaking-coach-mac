import XCTest

@testable import IELTSCoachCore

/// 随机抽题（用户 2026-08-20 的要求）：自己定每个 Part 抽几道，剩下的交给运气。
///
/// 判据一律是「把被测那段改成空实现或最笨的实现，这条会不会红」。
/// 其中最要紧的一条是 `testTwoDifferentSeedsDoNotAlwaysGiveTheSameQuestion`：
/// 去掉 `shuffled` 之后，抽题会退化成「永远拿题库里前 N 道」，
/// 而上面每一条数量、配对、短缺的断言**照样全绿**——只有那一条会红。
final class RandomDrawTests: XCTestCase {

    /// 可复现的随机源（xorshift64）。**测试必须能钉住结果**，
    /// 否则这一整个文件只能断言「数量对」，抽到的是哪几道永远测不了。
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
        }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private func draw(_ bank: [Question], _ counts: RandomDraw.Counts,
                      excludingPracticed: Bool = false,
                      seed: UInt64 = 1) -> RandomDraw.Result {
        var generator = SeededGenerator(seed: seed)
        return RandomDraw.draw(from: bank, counts: counts,
                               excludingPracticed: excludingPracticed, using: &generator)
    }

    // MARK: - 题库

    private func topic(_ name: String, status: String = "new") -> Question {
        var question = TopicQuestions.part1(topic: name, prompts: ["Do you like \(name)?"])
        question.status = status
        return question
    }

    private func card(_ prompt: String, status: String = "new") -> Question {
        Question(id: "card-\(prompt.hashValue)", part: 2, topic: "Place",
                 prompt: prompt, followups: ["Where is it?"], status: status)
    }

    /// 这张卡自己那一组 Part 3 追问（配对靠 `topic == 卡的 prompt`，见 `LinkedPart3`）。
    private func discussion(forCard cardPrompt: String, status: String = "new") -> Question {
        var question = TopicQuestions.part3(cueCard: cardPrompt,
                                            prompts: ["Why do people go there?"])
        question.status = status
        return question
    }

    private func bank(topics: Int = 6, cards: Int = 4, extraDiscussions: Int = 3) -> [Question] {
        var questions: [Question] = (1...max(topics, 1)).prefix(topics).map { topic("Topic \($0)") }
        for index in 0..<cards {
            let prompt = "Describe place number \(index)."
            questions.append(card(prompt))
            questions.append(discussion(forCard: prompt))
        }
        for index in 0..<extraDiscussions {
            questions.append(TopicQuestions.part3(cueCard: "Unpaired theme \(index).",
                                                  prompts: ["Is that a good thing?"]))
        }
        return questions
    }

    // MARK: - 数量

    func testDrawsExactlyTheRequestedNumberFromEachPart() {
        let result = draw(bank(), RandomDraw.Counts(one: 3, two: 2, three: 2))
        XCTAssertEqual(result.count(inPart: .one), 3)
        XCTAssertEqual(result.count(inPart: .two), 2)
        XCTAssertEqual(result.count(inPart: .three), 2)
        XCTAssertTrue(result.shortfalls.isEmpty, "题库够用时不该报短缺")
    }

    func testQuestionsComeBackInPartOrder() {
        let result = draw(bank(), RandomDraw.Counts(one: 2, two: 1, three: 1))
        XCTAssertEqual(result.questions.map(\.part), [1, 1, 2, 3],
                       "抽出来的顺序就是考官会用到的顺序，必须按 Part 升序")
        XCTAssertEqual(result.openingQuestion?.part, 1, "开场那道要记进训练记录，不能取错")
    }

    func testAskingForNothingGivesAnEmptyDrawInsteadOfGuessing() {
        let result = draw(bank(), RandomDraw.Counts())
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.focusPart, "一道都没要时不许替他挑一档考法")
        XCTAssertTrue(result.shortfalls.isEmpty, "没要就谈不上短缺")
    }

    func testCountsAreClampedToTheGuardRail() {
        var counts = RandomDraw.Counts()
        counts[.two] = 400
        XCTAssertEqual(counts[.two], RandomDraw.Counts.maximumPerPart)
        counts[.one] = -3
        XCTAssertEqual(counts[.one], 0)
    }

    // MARK: - 抽不够必须说出来

    func testShortfallSaysHowManyWereAskedForAndHowManyExist() {
        let result = draw(bank(cards: 1), RandomDraw.Counts(two: 3))
        let shortfall = result.shortfalls.first { $0.part == .two }
        XCTAssertEqual(shortfall?.asked, 3)
        XCTAssertEqual(shortfall?.got, 1)
        XCTAssertEqual(shortfall?.causedByExcludingPracticed, false,
                       "题库里本来就只有一张卡，这和「只抽没练过的」那个开关没关系")
    }

    /// 两种短缺的下一步完全不同：题库本来不够只能去导题，而这一种把开关关掉就有了。
    /// 分不清的话，界面只能说一句「题目不够」，而用户手边明明有一个一按就解决的开关。
    func testShortfallPointsAtTheExcludePracticedSwitchWhenThatIsTheCause() {
        var questions = bank(cards: 3)
        for index in questions.indices where questions[index].part == 2 {
            questions[index].status = "practiced"
        }
        let result = draw(questions, RandomDraw.Counts(two: 2), excludingPracticed: true)
        let shortfall = result.shortfalls.first { $0.part == .two }
        XCTAssertEqual(shortfall?.got, 0)
        XCTAssertEqual(shortfall?.causedByExcludingPracticed, true)
    }

    // MARK: - 只抽没练过的

    func testExcludingPracticedLeavesThePracticedOnesOut() {
        var questions = [topic("Fresh"), topic("Done", status: "practiced")]
        questions.append(contentsOf: bank(topics: 0, cards: 0, extraDiscussions: 0))
        let result = draw(questions, RandomDraw.Counts(one: 2), excludingPracticed: true)
        XCTAssertEqual(result.questions.map(\.topic), ["Fresh"])
        XCTAssertEqual(result.shortfalls.first?.part, .one)
    }

    func testNotExcludingPracticedLetsThemBeDrawnAgain() {
        let questions = [topic("Done", status: "practiced")]
        let result = draw(questions, RandomDraw.Counts(one: 1), excludingPracticed: false)
        XCTAssertEqual(result.questions.map(\.topic), ["Done"])
        XCTAssertTrue(result.shortfalls.isEmpty)
    }

    // MARK: - Part 3 跟着 cue card 走

    /// 独立随机抽的话会出现「卡讲的是逛商店、讨论题问的是环保立法」，
    /// 而提示词里白纸黑字要求 Part 3 顺着 Part 2 的主题——两者当场打架。
    func testPart3FollowsTheCueCardsThatWereDrawn() {
        let result = draw(bank(cards: 4), RandomDraw.Counts(two: 2, three: 2))
        let cards = result.questions.filter { $0.part == 2 }
        let discussions = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(discussions.count, 2)
        for discussion in discussions {
            guard let owner = LinkedPart3.cueCard(for: discussion, among: cards) else {
                XCTFail("抽到的讨论题「\(discussion.topic)」不属于这一场的任何一张卡")
                continue
            }
            XCTAssertEqual(result.part3CardIDs[discussion.id], owner.id)
        }
    }

    /// 讨论题要得比卡多时，多出来的从题库里自由抽——但不许和已经抽到的重复。
    func testExtraDiscussionsComeFromTheBankWithoutRepeating() {
        let result = draw(bank(cards: 1, extraDiscussions: 5),
                          RandomDraw.Counts(two: 1, three: 3))
        let discussions = result.questions.filter { $0.part == 3 }
        XCTAssertEqual(discussions.count, 3)
        XCTAssertEqual(Set(discussions.map(\.id)).count, 3, "同一道讨论题被抽了两次")
        let paired = discussions.filter { result.part3CardIDs[$0.id] != nil }
        XCTAssertEqual(paired.count, 1, "只有一张卡，所以只应该有一道讨论题是跟着卡来的")
    }

    // MARK: - 这一场跑哪几段

    /// 要了 Part 3 却一道都没抽到时，这一场就不含 Part 3——
    /// 否则提示词会宣布有一段 Part 3，而那一段一份材料都没有。
    func testFocusPartFollowsWhatWasActuallyDrawnNotWhatWasAskedFor() {
        let result = draw(bank(topics: 5, cards: 0, extraDiscussions: 0),
                          RandomDraw.Counts(one: 2, three: 2))
        XCTAssertEqual(result.focusPart, .part1)
        XCTAssertEqual(result.shortfalls.map(\.part), [.three])
    }

    // MARK: - 时长

    /// 各抽一道 == 勾满三个 Part。两条路给出两个时长的话，
    /// 用户没有任何办法知道哪个是真的。
    func testOneOfEachRunsAsLongAsAFullMock() {
        let result = draw(bank(), RandomDraw.Counts(one: 1, two: 1, three: 1))
        XCTAssertEqual(result.estimatedMinutes, FocusPart.fullMock.defaultDurationMinutes)
    }

    func testEachExtraItemAddsTime() {
        let one = draw(bank(), RandomDraw.Counts(two: 1)).estimatedMinutes
        let two = draw(bank(), RandomDraw.Counts(two: 2)).estimatedMinutes
        XCTAssertEqual(two - one, ExamPart.two.additionalItemMinutes,
                       "多一张卡就是再来一遍「准备 + 两分钟独白 + 收尾」，时长必须跟着涨")
    }

    // MARK: - 它真的在随机

    /// **这一条是整个文件的关键。** 去掉 `shuffled` 之后抽题会退化成
    /// 「永远拿题库里前 N 道」，而上面每一条断言照样全绿：数量对、配对对、短缺对。
    /// 用户点十次「重抽」拿到同一道题，是这个功能唯一彻底的失败方式。
    func testTwoDifferentSeedsDoNotAlwaysGiveTheSameQuestion() {
        let questions = bank(topics: 20, cards: 0, extraDiscussions: 0)
        let drawn = Set((1...12).map { seed in
            draw(questions, RandomDraw.Counts(one: 1), seed: UInt64(seed))
                .questions.first?.id ?? ""
        })
        XCTAssertGreaterThan(drawn.count, 1,
                             "12 个不同的随机种子抽出来的是同一道题——这不是随机，是取第一道")
    }

    /// 反过来：同一个种子必须给出同一个结果，否则上面那些断言只是碰巧成立。
    func testTheSameSeedAlwaysGivesTheSameDraw() {
        let questions = bank(topics: 20)
        let first = draw(questions, RandomDraw.Counts(one: 3, two: 2, three: 2), seed: 7)
        let again = draw(questions, RandomDraw.Counts(one: 3, two: 2, three: 2), seed: 7)
        XCTAssertEqual(first.questions.map(\.id), again.questions.map(\.id))
    }
}
