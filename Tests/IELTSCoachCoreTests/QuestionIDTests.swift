import XCTest

@testable import IELTSCoachCore

/// 题目 id 的契约：**id 由内容算出来，而且内容变了 id 必须跟着变。**
///
/// ## 为什么要单独开一个文件守它
///
/// 原先守这件事的两条测试（`PDFQuestionExtractorTests` 与 `QuestionBankImporterTests` 里各一条）
/// 都只问了一半：「在前面插入一个新话题之后，原有题目的 id 变没变」。
/// **常量 id 也满足这一条。** 复审把 `QuestionBankImporter.questionID` 改成
/// `_ = (topic, prompt); return "p\(part)"`（完全不看内容），全量测试 0 失败。
///
/// 那样改的后果不是「id 难看」，是**毁数据**：拿用户真实那份 81 页 PDF 实测，
/// 抽出来仍是 1264 道题，但 distinct id 只剩 3 个，经 `QuestionBankImporter.merge`
/// （按 id 去重）之后整个题库塌成 3 道题。练习记录、训练计划都按 id 索引，一起报废。
/// 这正是成品标准第 12 条（换季重新导入不错位）要守的东西。
///
/// ## 这里两个方向都断言
///
/// - **内容不同 → id 必须不同**，且 part / topic / prompt 三个维度各自单独变化都要覆盖
///   （只测「整体改一遍」的话，「只看 prompt 不看 topic」这种半残实现照样溜过去）；
/// - **内容相同 → id 必须相同**，跨进程、跨导入格式、跨位置都相同。
///
/// ## 边界
///
/// 它守的是 id 这个函数与三条导入路的契约，守不了「用户改了一个字的题算不算同一道题」——
/// 按本设计那就是新的一道题，这是刻意的取舍（见 `questionID` 的注释）。
final class QuestionIDTests: XCTestCase {

    private static let topic = "Home"
    private static let prompt = "Do you live in a house or a flat?"

    // MARK: - 内容不同 → id 必须不同（三个维度各自单独变）

    /// part 单独变。
    ///
    /// 可达性不是假设：JSON 题库里同一条题干既可以出现在 `part2Questions` 里，
    /// 又作为 `part3Questions` 的一条——下面 `testAPart2AndAPart3WithIdenticalText…`
    /// 就是走完整条导入路的那一半。
    func testChangingOnlyThePartChangesTheID() {
        let ids = [1, 2, 3].map {
            QuestionBankImporter.questionID(part: $0, topic: Self.topic, prompt: Self.prompt)
        }
        XCTAssertEqual(Set(ids).count, 3,
                       "只有 part 不同的三道题拿到了同一个 id：\(ids)。"
                           + "merge 按 id 去重，它们会互相覆盖，题库当场少题。")
    }

    /// topic 单独变。守的是「只拿 prompt 算哈希」那种半残实现——
    /// 真实题库里同一句题干挂在不同话题下很常见（「Why?」「How often?」这类追问尤其）。
    func testChangingOnlyTheTopicChangesTheID() {
        let first = QuestionBankImporter.questionID(part: 1, topic: "Home", prompt: Self.prompt)
        let second = QuestionBankImporter.questionID(part: 1, topic: "Hometown", prompt: Self.prompt)
        XCTAssertNotEqual(first, second,
                          "换了话题、题干不变，id 却一样：\(first)。"
                              + "两道题会在 merge 时互相覆盖，用户会发现题库莫名其妙少了题。")
    }

    /// prompt 单独变。守的是「只拿 topic 算哈希」那种半残实现——
    /// 一个话题下面通常有五到十道题，那样实现的话一个话题只会剩一道题。
    func testChangingOnlyThePromptChangesTheID() {
        let first = QuestionBankImporter.questionID(part: 1, topic: Self.topic,
                                                    prompt: "Do you live in a house or a flat?")
        let second = QuestionBankImporter.questionID(part: 1, topic: Self.topic,
                                                     prompt: "What do you like about your home?")
        XCTAssertNotEqual(first, second,
                          "同一话题下的两道不同题目拿到了同一个 id：\(first)。"
                              + "这个话题最后只会剩一道题。")
    }

    /// 连一个字符的差别也要认出来（哈希把整段内容都吃进去了，不是只看开头几个字）。
    func testIDsDifferEvenWhenTheContentDiffersByASingleCharacter() {
        let first = QuestionBankImporter.questionID(part: 1, topic: Self.topic,
                                                    prompt: "Do you like your home?")
        let second = QuestionBankImporter.questionID(part: 1, topic: Self.topic,
                                                     prompt: "Do you like your house?")
        XCTAssertNotEqual(first, second, "改一个词就该是另一道题")
    }

    // MARK: - 内容相同 → id 必须相同

    func testTheSameContentAlwaysGetsTheSameID() {
        let first = QuestionBankImporter.questionID(part: 1, topic: Self.topic, prompt: Self.prompt)
        let second = QuestionBankImporter.questionID(part: 1, topic: Self.topic, prompt: Self.prompt)
        XCTAssertEqual(first, second,
                       "同样的内容两次算出不同的 id，二次导入会把每一道题都当成新题追加进来")
    }

    /// **id 必须跨进程稳定**，所以哈希不能用 Swift 的 `hashValue`（每次启动换种子）。
    ///
    /// 这条断言拿的是**独立算出来的** FNV-1a 64 位值（用 Python 按 offset basis
    /// 0xcbf29ce484222325、prime 0x100000001b3 逐字节算了一遍，再转 36 进制），
    /// 不是「把实现跑一遍抄下来」——抄下来的话实现怎么改它都跟着对，等于没测。
    ///
    /// 顺带把 id 的**外形**也钉死了：换分隔符、换进制、换前缀都会让全体用户的 id 变一遍，
    /// 那等于把练习记录和训练计划一起作废。真要改，得先想清楚数据怎么迁移，
    /// 而不是顺手改完发现测试还是绿的。
    func testStableHashMatchesAnIndependentlyComputedFNV1a() {
        XCTAssertEqual(QuestionBankImporter.stableHash(""), "33niihzj4ux45",
                       "空串的 FNV-1a 应当就是 offset basis 本身")
        XCTAssertEqual(QuestionBankImporter.stableHash("a"), "2o0ongoiv4rrg")
        XCTAssertEqual(QuestionBankImporter.stableHash("Home|Do you live in a house or a flat?"),
                       "3qf2gp1ky2w7s")
        XCTAssertEqual(QuestionBankImporter.stableHash("人物|Describe a person"), "3pwtfp02lp6wl",
                       "中文得按 UTF-8 逐字节算，题库里 Part 2 的话题全是中文")

        XCTAssertEqual(
            QuestionBankImporter.questionID(part: 1, topic: "Home",
                                            prompt: "Do you live in a house or a flat?"),
            "p1-3qf2gp1ky2w7s",
            "id 的外形变了。全体用户的题目 id 会跟着变一遍，历史练习记录与训练计划全部指错题。")
    }

    /// 顺序不同的同一批字节必须算出不同的哈希（`ab` 与 `ba`）。
    /// 这条挡的是「把字节加起来」之类的伪哈希——那种实现下
    /// 「Do you like it?」和「it? Do you like」会是同一道题。
    func testStableHashDependsOnTheOrderOfTheBytes() {
        XCTAssertNotEqual(QuestionBankImporter.stableHash("ab"),
                          QuestionBankImporter.stableHash("ba"))
        XCTAssertNotEqual(QuestionBankImporter.stableHash("ab"),
                          QuestionBankImporter.stableHash("abc"))
    }

    // MARK: - 走完整条导入路：PDF

    /// 真实题库那份 PDF 的形状：两个 Part 1 话题、两张 cue card、若干 Part 3 追问。
    private static let seasonalPDFText = """
        Part 1 T opics
        Part1 必 考 题
        1-Study and work
        Do you work or are you a student?
        What work do you do?
        2-Accommodation
        Do you live in a house or a flat?
        What do you like about your home?
        Part2 & 3 保 留 题
        人物
        1-Describe a person who solved a problem in a smart way
        You should say
        Who this person is
        Part3
        What are the qualities of a person who can solve problems in smart ways?
        Do children solve problems differently from adults?
        事件
        2-Describe a film you watched that disappointed you
        You should say
        What it was about
        Part3
        Why do people like watching films at the cinema?
        """

    /// **这一条直接对着复审实测的那个后果**：距离「题库塌成 3 道题」只差一次 `merge`。
    ///
    /// 单看条数是看不出问题的——常量 id 的实现照样抽出全部题目，
    /// 塌是塌在按 id 去重那一步。所以这里既数 distinct id，也真的跑一遍 merge。
    func testEveryQuestionExtractedFromAPDFGetsItsOwnIDAndSurvivesMerge() throws {
        let result = try PDFQuestionExtractor.extract(
            plainText: Self.seasonalPDFText, sourceTitle: "季度题库", sourceUrl: "")

        // 4 道 Part 1 + 2 张 cue card + 3 道 Part 3 追问。
        XCTAssertEqual(result.questions.count, 9, "样本本身变了，下面的断言就失去依据："
                        + "\(result.questions.map(\.prompt))")
        XCTAssertEqual(Set(result.questions.map(\.id)).count, result.questions.count,
                       "抽出 \(result.questions.count) 道题，却只有 "
                           + "\(Set(result.questions.map(\.id)).count) 个不同的 id。"
                           + "id 没有跟着内容走，下一步 merge 会把它们去重成几道。")

        // 真的走一遍导入时那条路：空题库 + 这一批。id 塌了的话这里当场少题。
        let merged = QuestionBankImporter.merge(existing: [], incoming: result.questions)
        XCTAssertEqual(merged.count, result.questions.count,
                       "merge 之后题库从 \(result.questions.count) 道塌成了 \(merged.count) 道")
        XCTAssertEqual(Set(merged.map(\.prompt)).count, result.questions.count,
                       "merge 之后有题目被同 id 的另一道覆盖掉了：\(merged.map(\.prompt))")
    }

    /// 换季重新导入：上一季与这一季共有的那道题必须认成同一道（id 不变、不重复出现），
    /// 各自独有的题必须都还在。这就是成品标准第 12 条的场景。
    ///
    /// 只测「插入新话题后 id 不变」的话，常量 id 也能全绿；这里连题数一起数，
    /// 常量 id 会让 merge 后只剩一两道。
    func testReimportingNextSeasonKeepsTheUnchangedQuestionAndAddsOnlyTheNewOnes() throws {
        let lastSeason = """
            Part 1 T opics
            Part1 必 考 题
            1-Study and work
            Do you work or are you a student?
            2-Accommodation
            Do you live in a house or a flat?
            """
        // 这一季：Study and work 那道原样保留，Accommodation 整个话题被换掉。
        let thisSeason = """
            Part 1 T opics
            Part1 必 考 题
            1-Study and work
            Do you work or are you a student?
            2-Weather
            What is the weather like in your hometown?
            """
        let old = try PDFQuestionExtractor.extract(
            plainText: lastSeason, sourceTitle: "上一季", sourceUrl: "")
        let new = try PDFQuestionExtractor.extract(
            plainText: thisSeason, sourceTitle: "这一季", sourceUrl: "")
        XCTAssertEqual(old.questions.count, 2)
        XCTAssertEqual(new.questions.count, 2)

        let merged = QuestionBankImporter.merge(existing: old.questions, incoming: new.questions)

        XCTAssertEqual(merged.map(\.prompt), [
            "Do you work or are you a student?",     // 两季都有：认成同一道，留在原位
            "Do you live in a house or a flat?",     // 只有上一季有：保留（练过的记录还挂在它上面）
            "What is the weather like in your hometown?"  // 只有这一季有：追加在后面
        ], "换季重新导入之后题库对不上了")

        let unchanged = try XCTUnwrap(
            merged.first { $0.prompt == "Do you work or are you a student?" })
        XCTAssertEqual(unchanged.id,
                       try XCTUnwrap(old.questions.first)?.id,
                       "没改过的那道题换了 id，挂在旧 id 上的练习记录与训练计划全部指错题")
    }

    // MARK: - 走完整条导入路：JSON

    /// JSON 那条路同样是内容哈希（`QuestionBankImporterTests` 里那条只问了位置那一半）。
    func testJSONImportGivesEachQuestionItsOwnContentDerivedID() throws {
        let json = """
            {"title":"t","sourceUrl":"","importedAt":"2026-08-06T00:00:00.000Z",
             "importLevel":"full-question",
             "part1":[{"raw":"Home","questions":["Do you live in a house or a flat?",
                                                 "What do you like about your home?"]},
                      {"raw":"Hometown","questions":["Do you live in a house or a flat?"]}]}
            """
        let result = try QuestionBankImporter.importJSON(json, sourceTitle: "t")
        XCTAssertEqual(result.questions.count, 3)
        XCTAssertEqual(Set(result.questions.map(\.id)).count, 3,
                       "三道题只有 \(Set(result.questions.map(\.id)).count) 个 id。"
                           + "同一句题干挂在两个话题下是真实题库里的常态"
                           + "（第三道与第一道题干相同、话题不同），它们必须是两道题。")
    }

    /// part 那一维走完整条路的那一半：同一话题、同一句话，一条作为 cue card、
    /// 一条作为它的 Part 3 追问，id 必须不同。
    func testAPart2AndAPart3WithIdenticalTextStillGetDifferentIDs() throws {
        let json = """
            {"title":"t","sourceUrl":"","importedAt":"2026-08-06T00:00:00.000Z",
             "importLevel":"full-question",
             "part23":[{"raw":"人物",
                        "part2Questions":["Describe a person you admire"],
                        "part3Questions":["Describe a person you admire"]}]}
            """
        let result = try QuestionBankImporter.importJSON(json, sourceTitle: "t")
        XCTAssertEqual(result.questions.count, 2)
        XCTAssertNotEqual(result.questions[0].id, result.questions[1].id,
                          "Part 2 与 Part 3 的题拿到了同一个 id，merge 会把其中一道吃掉")
    }

    // MARK: - 两条导入路必须对得上

    /// 同一道题从 JSON 导一次、从 PDF 再导一次，必须是同一个 id。
    ///
    /// `questionID` 写成 `internal` 就是为了让 `PDFQuestionExtractor` 用同一份实现
    /// （见它的注释）。PDF 那边一旦自己再写一遍哈希，同一道题会变成两道，merge 也去不掉重——
    /// 而在补这条之前，那样改一条测试都不红。
    func testTheSameQuestionImportedFromJSONAndFromAPDFGetsTheSameID() throws {
        let json = """
            {"title":"t","sourceUrl":"","importedAt":"2026-08-06T00:00:00.000Z",
             "importLevel":"full-question",
             "part1":[{"raw":"Study and work","questions":["Do you work or are you a student?"]}]}
            """
        let fromJSON = try QuestionBankImporter.importJSON(json, sourceTitle: "t")
        let fromPDF = try PDFQuestionExtractor.extract(plainText: """
            Part 1 T opics
            Part1 必 考 题
            1-Study and work
            Do you work or are you a student?
            """, sourceTitle: "t", sourceUrl: "")

        let jsonQuestion = try XCTUnwrap(fromJSON.questions.first)
        let pdfQuestion = try XCTUnwrap(fromPDF.questions.first)
        XCTAssertEqual(jsonQuestion.prompt, pdfQuestion.prompt, "样本没对齐，这条测试失去依据")
        XCTAssertEqual(jsonQuestion.topic, pdfQuestion.topic, "样本没对齐，这条测试失去依据")
        XCTAssertEqual(jsonQuestion.id, pdfQuestion.id,
                       "同一道题从两条路导进来拿到了两个 id。用户先导 JSON 再导 PDF（或反过来）"
                           + "会得到两份重复的题，merge 去不掉。")
    }
}
