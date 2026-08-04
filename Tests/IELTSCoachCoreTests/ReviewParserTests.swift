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
}
