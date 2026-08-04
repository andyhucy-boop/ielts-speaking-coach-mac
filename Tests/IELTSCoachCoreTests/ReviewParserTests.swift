import XCTest
@testable import IELTSCoachCore

final class ReviewParserTests: XCTestCase {
    private let reviewJSON = """
    {"summary":"ok","must_correct":[],"natural_upgrades":[],"logic_feedback":[],\
    "answer_upgrades":[{"question":"Why?","original_answer":"Because it is useful.",\
    "revised_answer":"I believe it is useful because it helps me work more efficiently.",\
    "changes":["补全句子结构"]}],"priority_target":{"id":"expand"}}
    """

    func testParsesIELTSMarkedBlock() throws {
        let text = "<<<IELTS_REVIEW_JSON>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testParsesStartOfJSONMarker() throws {
        let text = "<<<START_OF_JSON>>>\n\(reviewJSON)\n<<<END_OF_JSON>>>"
        XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"))
    }

    func testParsesMarkerWithRequestID() throws {
        let text = "<<<IELTS_REVIEW_JSON:sync-123>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON:sync-123>>>"
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

    func testRepairsSingleQuotesAndTrailingComma() throws {
        let messy = "{'summary':'ok','must_correct':[],'priority_target':{'id':'expand'},}"
        XCTAssertEqual(try ReviewParser.parse(messy)["summary"], .string("ok"))
    }

    func testFindsExistingReviewFromLatestAssistantTurn() {
        let turns = [
            ConversationTurn(role: "user", text: "answer"),
            ConversationTurn(role: "assistant", text: "<<<JSON>>>\(reviewJSON)<<<END_JSON>>>")
        ]
        XCTAssertEqual(ReviewParser.findExisting(turns: turns)?.index, 1)
    }

    func testFindsReviewSplitAcrossTurnsAfterRequest() {
        let turns = [
            ConversationTurn(role: "assistant", text: "old reply"),
            ConversationTurn(role: "user", text: "generate report [SYNC_REQUEST_ID:sync-123]"),
            ConversationTurn(role: "assistant", text: "本次训练已结束"),
            ConversationTurn(role: "assistant", text: "<<<IELTS_REVIEW_JSON:sync-123>>>"),
            ConversationTurn(role: "assistant", text: reviewJSON),
            ConversationTurn(role: "assistant", text: "<<<END_IELTS_REVIEW_JSON:sync-123>>>")
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
            let text = "<<<IELTS_REVIEW_JSON:\(requestID)>>>\n\(reviewJSON)\n<<<END_IELTS_REVIEW_JSON:\(requestID)>>>"
            XCTAssertEqual(try ReviewParser.parse(text)["summary"], .string("ok"),
                           "request-id 未被 marker 正则接受：\(requestID)")
        }
    }

    // 诊断用：上面那条测试其实测不出 marker 正则本身有没有认出下划线，因为 parse()
    // 还有「扫全文第一个 { 到最后一个 } 」的兜底候选——markers 之间只包着纯净的
    // reviewJSON、markers 本身不含大括号，所以就算 marker 正则完全没匹配上，
    // 兜底候选照样能抠出同一段合法 JSON，测试照样绿，掩盖了正则的问题。
    // 这里在 markers 外面放一个不相关但结构合法的 JSON 对象作诱饵，破坏兜底候选
    // （首尾大括号之间会把诱饵、marker 文本、reviewJSON 全部囊括进去，不再是合法
    // JSON），逼 parse() 真正依赖 marker 正则本身取出内容。
    func testMarkerRegexAloneAcceptsUnderscoreRequestID() throws {
        let decoy = #"{"note":"unrelated"}"#
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
