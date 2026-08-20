import XCTest

@testable import IELTSCoachCore

/// 随机抽题给考官的是**一整套材料**（`SessionSetup.drawnQuestions`），
/// 而在这之前一场只供一道题、其余几段由考官自己编。
///
/// 这个文件盯两件事：
///
/// 1. **一份材料那一场，提示词一个字都不许变。** 那些措辞是实测调出来的，
///    上一轮 Part 3 翻车（第一句问出 `Describe a book you recently read`）就是栽在这儿。
/// 2. **一整套材料时，规则正文与材料清单不许自相矛盾。** 清单里列着 3 个话题、
///    规则里写着「自己再挑几个话题」，或者清单里 3 张卡、规则里写着 "Present one cue card"——
///    这种矛盾不会报错，只会让用户抽到的题有一半在考场上根本不出现。
final class ExaminerPromptMaterialTests: XCTestCase {

    private func topic(_ name: String, prompts: [String]) -> Question {
        TopicQuestions.part1(topic: name, prompts: prompts)
    }

    private func card(_ prompt: String, topic: String = "Place") -> Question {
        Question(id: "card-\(topic)-\(prompt.count)", part: 2, topic: topic,
                 prompt: prompt, followups: ["Where it is", "Why you like it"])
    }

    private func discussion(forCard prompt: String, prompts: [String]) -> Question {
        TopicQuestions.part3(cueCard: prompt, prompts: prompts)
    }

    private func setup(_ material: [Question], focusPart: FocusPart) -> SessionSetup {
        SessionSetup(question: material[0], focusPart: focusPart,
                     durationMinutes: 14, goal: "", drawnQuestions: material)
    }

    // MARK: - 一份材料的那一场

    /// **黄金对照**：材料里只有一道题时，走的必须是原来那条路，输出逐字一致。
    /// 这一条是这次改动最贵的一道闸——它红了就说明每一场既有练习的提示词都被动了。
    func testASingleMaterialSessionIsByteForByteWhatItAlwaysWas() {
        let question = card("Describe a useful skill you learned", topic: "Skills")
        let before = SessionSetup(question: question, focusPart: .part2,
                                  durationMinutes: 4, goal: "")
        let after = SessionSetup(question: question, focusPart: .part2,
                                 durationMinutes: 4, goal: "", drawnQuestions: [question])
        XCTAssertEqual(ExaminerPrompt.build(setup: before), ExaminerPrompt.build(setup: after))
        XCTAssertTrue(ExaminerPrompt.build(setup: before).contains("Present one cue card."))
    }

    /// 抽出来的那一组里漏了开场题时补回去。少了这条不变量，训练记录上写着练了这道题，
    /// 而考官手里根本没有它——静默，且事后无从发现。
    func testTheOpeningQuestionIsAlwaysInTheMaterialList() {
        let opening = topic("Borrowing", prompts: ["Do you lend things?"])
        let other = topic("Weather", prompts: ["Do you like rain?"])
        let session = SessionSetup(question: opening, focusPart: .part1, durationMinutes: 7,
                                   goal: "", drawnQuestions: [other])
        XCTAssertEqual(session.materialQuestions.map(\.id), [opening.id, other.id])
    }

    // MARK: - 一整套材料

    func testEveryDrawnQuestionShowsUpInThePrompt() {
        let material = [topic("Borrowing", prompts: ["Do you lend things?"]),
                        topic("Weather", prompts: ["Do you like rain?"]),
                        card("Describe a shop you enjoy visiting.")]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part1And2))
        for question in material {
            XCTAssertTrue(text.contains(question.prompt),
                          "抽到的「\(question.prompt)」没有出现在提示词里")
        }
        XCTAssertTrue(text.contains("Do you like rain?"),
                      "第二个话题的参考问句丢了——那个话题会变成一个没有问句的空壳")
    }

    /// 清单里三个话题，规则里却写着「自己再挑几个话题」的话，
    /// 用户抽到的那几道有一半根本不会被问到，而屏幕上抽签结果明明白白列着。
    func testPart1RulesCoverTheSuppliedTopicsInsteadOfInventingMore() {
        let material = (1...3).map { topic("Topic \($0)", prompts: ["Q\($0)?"]) }
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part1))
        XCTAssertTrue(text.contains("Cover the 3 supplied topics"))
        XCTAssertTrue(text.contains("Do not add topics of your own"))
        XCTAssertFalse(text.contains("then move on to other everyday topics of your choice"),
                       "供了 3 个话题还叫它自己再挑，两条规则当场打架")
    }

    func testPart2RulesPresentEveryDrawnCard() {
        let material = [card("Describe a shop you enjoy visiting.", topic: "Place"),
                        card("Describe a person who helped you.", topic: "People")]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part2))
        XCTAssertTrue(text.contains("Present the 2 supplied cue cards one at a time"))
        XCTAssertFalse(text.contains("- Present one cue card."),
                       "清单里两张卡，规则里还写着「出一张卡」——它多半只做第一张")
        XCTAssertTrue(text.contains("after each long turn"))
    }

    /// 写死「全场 4–8 问」而清单里列着 3 个讨论主题的话，每个主题分到 1–2 问，
    /// 那不是 Part 3 讨论，是三次蜻蜓点水。
    func testPart3QuestionCountIsPerDiscussionWhenThereAreSeveral() {
        let material = (1...3).map {
            discussion(forCard: "Describe object number \($0).", prompts: ["Why is that?"])
        }
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part3))
        XCTAssertTrue(text.contains("Ask 4–6 questions in each of the 3 supplied discussions"))
        XCTAssertFalse(text.contains("Ask 4–8 questions in total."))
    }

    // MARK: - 哪一组讨论接哪一张卡

    /// 不说的话，考官只能自己猜配对，而它猜错时屏幕上一切正常：
    /// 考生做完一张卡的独白，接着被问一段不相干的讨论。
    func testEachDiscussionSaysWhichCardItBelongsTo() {
        let first = "Describe a shop you enjoy visiting."
        let second = "Describe a person who helped you."
        let material = [card(first, topic: "Place"), card(second, topic: "People"),
                        discussion(forCard: second, prompts: ["Who helps whom in society?"]),
                        discussion(forCard: first, prompts: ["Why do small shops close?"])]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part2And3))
        XCTAssertTrue(text.contains("Discussion 1 — this is the discussion that belongs to Card 2"),
                      "第一组讨论接的是第二张卡，提示词没说出来")
        XCTAssertTrue(text.contains("Discussion 2 — this is the discussion that belongs to Card 1"))
    }

    func testADiscussionWithNoMatchingCardSaysSoInsteadOfBeingGuessed() {
        let material = [card("Describe a shop you enjoy visiting.", topic: "Place"),
                        discussion(forCard: "Describe something else entirely.",
                                   prompts: ["Is that a good thing?"])]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part2And3))
        XCTAssertTrue(text.contains("none of the cue cards above belongs to it"))
    }

    /// 题库里 Part 3 的题干**就是**它所属 cue card 的原文。原样印出去的话，
    /// 那句 `Describe …` 会把考官引去出一张卡——用户 2026-08-08 实测踩到的正是这一次。
    func testAPart3ThemeIsRewrittenSoNoDescribeTaskLeaksIn() {
        let material = (1...2).map {
            discussion(forCard: "Describe a shop you enjoy visiting number \($0).",
                       prompts: ["Why do small shops close?"])
        }
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .part3))
        for line in text.split(separator: "\n") where line.hasPrefix("Theme: ") {
            XCTAssertFalse(line.lowercased().contains("describe"),
                           "Part 3 的主题行里还留着 Describe：\(line)")
        }
        // `DiscussionTheme.phrase` 会砍掉句号——主题是个短语，不是一句话。
        XCTAssertTrue(text.contains("Theme: a shop you enjoy visiting number 1\n"),
                      "主题短语没有被改写成预期的样子")
    }

    // MARK: - 「自己挑材料」那句话什么时候该消失

    func testNoPartIsToldToInventMaterialWhenEveryPartHasSome() {
        let material = [topic("Borrowing", prompts: ["Do you lend things?"]),
                        card("Describe a shop you enjoy visiting."),
                        discussion(forCard: "Describe a shop you enjoy visiting.",
                                   prompts: ["Why do small shops close?"])]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .fullMock))
        XCTAssertFalse(text.contains("Choose your own material for"),
                       "三段全供了料，还叫考官自己挑——题库里的真题就白抽了")
        XCTAssertTrue(text.contains("The material supplied below covers Part 1 and Part 2 and Part 3"))
    }

    /// 反过来：只有两段有材料时，剩下那一段必须照旧被告知自己挑。
    func testThePartWithoutMaterialIsStillToldToChooseItsOwn() {
        let material = [topic("Borrowing", prompts: ["Do you lend things?"]),
                        card("Describe a shop you enjoy visiting.")]
        let text = ExaminerPrompt.build(setup: setup(material, focusPart: .fullMock))
        XCTAssertTrue(text.contains("Choose your own material for Part 3"))
    }
}
