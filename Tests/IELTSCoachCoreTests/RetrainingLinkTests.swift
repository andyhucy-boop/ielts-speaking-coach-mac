import XCTest
@testable import IELTSCoachCore

final class RetrainingLinkTests: XCTestCase {
    private func session(id: String, questionId: String,
                         link: RetrainingLink?) -> PracticeSession {
        PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private let link = RetrainingLink(targetKey: "logic-explain-example",
                                      sourceSessionId: "2026-08-05-001",
                                      originalQuestionId: "p1-home-001")

    /// 普通练习不能被当成复训——否则复训进度会凭空多出几场，
    /// 用户以为自己已经换题验证过了，其实一次都没练。
    func testPlainSessionHasNoRetrainingKind() {
        XCTAssertNil(session(id: "s1", questionId: "p1-home-001", link: nil).retrainingKind)
    }

    func testSameQuestionIsCountedAsOriginalRetry() {
        XCTAssertEqual(session(id: "s1", questionId: "p1-home-001", link: link).retrainingKind,
                       .original)
    }

    /// 这一条守的是本阶段的核心：换了题才叫验证。
    func testDifferentQuestionIsCountedAsTransfer() {
        XCTAssertEqual(session(id: "s2", questionId: "p1-work-007", link: link).retrainingKind,
                       .transfer)
    }

    /// 用户已经练过的记录里没有 retraining 这个键。解码必须容忍它缺失，
    /// 否则升级到这一版之后，全部历史训练记录会一起读不出来。
    func testDecodesOldSessionJSONWithoutTheNewField() throws {
        let json = """
        {"id":"2026-08-05-001","questionId":"p1-home-001","focusPart":"Part 1",
         "startedAt":"2026-08-05T10:00:00Z","endedAt":"2026-08-05T10:20:00Z","goal":"",
         "transcript":[],"reportPath":"reports/2026-08-05-001.json","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertNil(decoded.retraining)
        XCTAssertNil(decoded.retrainingKind)
    }

    func testRoundTripsThroughJSON() throws {
        let original = session(id: "s2", questionId: "p1-work-007", link: link)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self, from: data), original)
    }

    /// link 与 target 必须能对上，否则界面上「这条训练记录属于哪个目标」永远匹配不到，
    /// 复训进度会一直显示「还没开始」。
    func testTargetIDMatchesRetrainingTargetID() {
        let target = RetrainingTarget(targetKey: "logic-explain-example", label: "补一个原因和例子",
                                      status: "new", evidence: [],
                                      sourceSessionId: "2026-08-05-001", createdAt: "t")
        XCTAssertEqual(link.targetID, target.id)
    }
}
