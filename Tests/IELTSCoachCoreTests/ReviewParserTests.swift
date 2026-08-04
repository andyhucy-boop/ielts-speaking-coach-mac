import XCTest
@testable import IELTSCoachCore

final class ReviewParserTests: XCTestCase {
    private let reviewJSON = """
    {"summary":"ok","must_correct":[],"natural_upgrades":[],"logic_feedback":[],\
    "answer_upgrades":[{"question":"Why?","original_answer":"Because it is useful.",\
    "revised_answer":"I believe it is useful because it helps me work more efficiently.",\
    "changes":["补全句子结构"]}],"priority_target":{"id":"expand"}}
    """

    // 诱饵：markers 之外放一个不相关但结构合法的 JSON 对象。若不这样做，marker 正则
    // 就算完全失效（改成永不匹配），parse() 的「扫全文第一个 { 到最后一个 }」兜底
    // 照样能把 markers 之间的 reviewJSON 原样抠出来（markers 本身不含大括号），测试
    // 照样绿，测不出 marker 正则本身有没有起作用。诱饵的 { 会把兜底候选的起点往前拉，
    // 跨越诱饵、marker 文本和 reviewJSON 产出非法拼接，逼 parse() 真正依赖 marker 正则。
    private let decoy = #"{"note":"unrelated"}"#

    func testParsesIELTSMarkedBlock() throws {
        let text = "\(decoy)\n<<<IELTS_REVIEW_JSON>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testParsesStartOfJSONMarker() throws {
        let text = "\(decoy)\n<<<START_OF_JSON>>>\n\(reviewJSON)\n<<<END_OF_JSON>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testParsesMarkerWithRequestID() throws {
        let text = "\(decoy)\n<<<IELTS_REVIEW_JSON:sync-123>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON:sync-123>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testParsesJSONEmbeddedInProse() throws {
        let text = "报告如下：\n\(reviewJSON)\n请查收。"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testNormalizesSingleAnswerUpgradeObjectToArray() throws {
        let single = """
        {"summary":"ok","must_correct":[],"answer_upgrades":{"question":"Why?",\
        "original_answer":"a","revised_answer":"b","changes":[]},"priority_target":{"id":"expand"}}
        """
        XCTAssertEqual(try ReviewParser.parse(single)["answer_upgrades"]?.arrayValue?.count, 1)
    }

    // normalize() 对 answer_upgrades 的 default 分支：既不是数组也不是对象（这里是
    // null）时应规范化成空数组，而不是原样保留 null 往下传。
    func testNormalizesNullAnswerUpgradesToEmptyArray() throws {
        let withNullUpgrades =
            #"{"summary":"ok","must_correct":[],"answer_upgrades":null,"priority_target":{"id":"t"}}"#
        let parsed = try ReviewParser.parse(withNullUpgrades)
        XCTAssertEqual(parsed["answer_upgrades"], .array([]))
    }

    func testRepairsSingleQuotesAndTrailingComma() throws {
        let messy = "{'summary':'ok','must_correct':[],'priority_target':{'id':'expand'},}"
        XCTAssertEqual(try ReviewParser.parse(messy)["summary"], .string("ok"))
    }

    func testFindsExistingReviewFromLatestAssistantTurn() {
        let turns = [
            ConversationTurn(role: "user", text: "answer"),
            ConversationTurn(role: "assistant", text: "\(decoy)<<<JSON>>>\(reviewJSON)<<<END_JSON>>>")
        ]
        XCTAssertEqual(ReviewParser.findExisting(turns: turns)?.index, 1)
    }

    func testFindsReviewSplitAcrossTurnsAfterRequest() {
        // 加固两处，缺一都会让这条测试测不到它该测的东西：
        // 1) markers 外带诱饵——理由同上，防止兜底的大括号扫描绕过 marker 正则。
        // 2) reviewJSON 真正劈成两半分放两条相邻 assistant turn——原版整段 reviewJSON
        //    完整落在单条 turn 上，逐条 parse 就能成功，根本走不到 findAfterRequest
        //    里「拼起来再试」那段 join 逻辑（第 73-78 行），删掉那段代码也不会有测试变红。
        //    这里在 "answer_upgrades" 键之前切开：前半段不含任何 "}"，单独解析
        //    （含 JSONRepair 兜底修复）必然失败；后半段不以 "{" 开头，单独解析、
        //    以及原始大括号扫描都必然失败——两条 turn 单独都过不了，逼真正走到 join。
        let boundary = reviewJSON.range(of: "\"answer_upgrades\"")!.lowerBound
        let firstHalf = String(reviewJSON[..<boundary])
        let secondHalf = String(reviewJSON[boundary...])
        let turns = [
            ConversationTurn(role: "assistant", text: "old reply"),
            ConversationTurn(role: "user", text: "generate report [SYNC_REQUEST_ID:sync-123]"),
            ConversationTurn(role: "assistant", text: "本次训练已结束"),
            ConversationTurn(role: "assistant", text: "\(decoy)\n<<<IELTS_REVIEW_JSON:sync-123>>>\n\(firstHalf)"),
            ConversationTurn(role: "assistant", text: "\(secondHalf)\n<<<END_IELTS_REVIEW_JSON:sync-123>>>")
        ]
        XCTAssertEqual(ReviewParser.findAfterRequest(turns: turns, requestID: "sync-123")?
            .report["summary"], .string("ok"))
    }

    func testIgnoresReviewWhenRequestIDAbsent() {
        let turns = [
            ConversationTurn(role: "user", text: "another request"),
            ConversationTurn(role: "assistant", text: reviewJSON)
        ]
        XCTAssertNil(ReviewParser.findAfterRequest(turns: turns, requestID: "sync-123"))
    }

    func testRejectsOrdinaryChatReply() {
        XCTAssertThrowsError(try ReviewParser.parse("普通聊天回复"))
    }

    // looksLikeReview 有 4 条判据（must_correct / natural_upgrades / logic_feedback /
    // priority_target），命中任意一条就算复盘。下面 3 条各自只含其中一条判据、且刻意
    // 不含 must_correct，逼这 3 条判据本身都被真正用到，而不是全指望 must_correct 兜底。
    func testRecognizesReviewByNaturalUpgradesAlone() throws {
        let text = #"{"summary":"ok","natural_upgrades":[{"basic":"good","better":"great"}]}"#
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testRecognizesReviewByLogicFeedbackAlone() throws {
        let text = #"{"summary":"ok","logic_feedback":["补一个原因和例子"]}"#
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testRecognizesReviewByPriorityTargetAlone() throws {
        let text = #"{"summary":"ok","priority_target":{"id":"expand"}}"#
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testRejectsReviewMissingAnswerUpgradesWhenRequired() {
        let incomplete = #"{"summary":"incomplete","must_correct":[],"priority_target":{"id":"expand"}}"#
        XCTAssertThrowsError(try ReviewParser.parse(incomplete, requireAnswerUpgrades: true)) { error in
            XCTAssertTrue("\(error)".contains("缺少完整的回答建议"))
        }
    }

    func testAcceptsCompleteReviewWhenAnswerUpgradesRequired() throws {
        XCTAssertEqual(try ReviewParser.parse(reviewJSON, requireAnswerUpgrades: true)["summary"],
                       .string("ok"))
    }

    func testFindAfterRequestReturnsNilWhenUpgradesRequiredButMissing() {
        let turns = [
            ConversationTurn(role: "user", text: "generate report [SYNC_REQUEST_ID:sync-incomplete]"),
            ConversationTurn(role: "assistant", text: #"{"summary":"incomplete","must_correct":[]}"#)
        ]
        XCTAssertNil(ReviewParser.findAfterRequest(turns: turns, requestID: "sync-incomplete",
                                                   requireAnswerUpgrades: true))
    }

    func testAcceptsRequestIDWithUnderscoreAndUppercase() throws {
        for requestID in ["sync_123", "8B7F2A1C-4D5E-6789-ABCD-EF0123456789"] {
            let text = "\(decoy)\n<<<IELTS_REVIEW_JSON:\(requestID)>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON:\(requestID)>>>"
            XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"),
                           "request-id 未被 marker 正则接受：\(requestID)")
        }
    }

    // 诊断用：验证 marker 正则本身认下划线 request-id，不靠兜底候选救场（原理见
    // 上面 testAcceptsRequestIDWithUnderscoreAndUppercase 现在共用的 decoy 说明）。
    func testMarkerRegexAloneAcceptsUnderscoreRequestID() throws {
        let text = "\(decoy)\n<<<IELTS_REVIEW_JSON:sync_123>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON:sync_123>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testErrorMessagesCarryNextStep() {
        XCTAssertThrowsError(try ReviewParser.parse("普通聊天回复")) { error in
            XCTAssertTrue("\(error)".contains("下一步"), "reviewNotFound 缺少下一步：\(error)")
        }
        let incomplete = #"{"summary":"x","must_correct":[],"priority_target":{"id":"t"}}"#
        XCTAssertThrowsError(try ReviewParser.parse(incomplete, requireAnswerUpgrades: true)) { error in
            XCTAssertTrue("\(error)".contains("下一步"), "reviewIncomplete 缺少下一步：\(error)")
        }
    }
}
