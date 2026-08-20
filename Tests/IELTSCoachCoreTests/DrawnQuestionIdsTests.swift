import Foundation
import XCTest

@testable import IELTSCoachCore

/// 随机抽题那一场安排到的**整组**题号（`PracticeSession.drawnQuestionIds`）。
///
/// 这一组 id 只服务一件事：让「这道题练没练过」这本账记对。记不对的后果全都是静默的——
/// 「只抽没练过的」把练过的题一遍遍再抽出来，训练题库页那个「已练 N / 258」永远偏小，
/// 而屏幕上没有任何异样。
final class DrawnQuestionIdsTests: XCTestCase {

    private func session(id: String, questionId: String, drawn: [String]? = nil) -> PracticeSession {
        PracticeSession(id: id, questionId: questionId, focusPart: .fullMock,
                        startedAt: "2026-08-20T09:00:00Z", endedAt: "2026-08-20T09:14:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        drawnQuestionIds: drawn)
    }

    private func question(_ id: String, part: Int = 1, status: String = "new") -> Question {
        Question(id: id, part: part, topic: id, prompt: id, status: status)
    }

    // MARK: - 这一场到底练了哪些题

    func testAnOrdinarySessionStillCountsAsOneQuestion() {
        XCTAssertEqual(session(id: "s1", questionId: "q1").allQuestionIds, ["q1"])
    }

    func testADrawnSessionCountsEveryQuestionItWasGiven() {
        let drawn = session(id: "s1", questionId: "q1", drawn: ["q1", "q2", "q3"])
        XCTAssertEqual(drawn.allQuestionIds, ["q1", "q2", "q3"])
    }

    /// 开场那道永远排第一，而且只出现一次——两处都真会发生：
    /// 抽签结果里它本来就在组里（重复），而手改过的 state.json 里可能漏了它（缺）。
    func testTheOpeningQuestionComesFirstAndOnlyOnce() {
        let odd = session(id: "s1", questionId: "q2", drawn: ["q1", "q2", "q2", ""])
        XCTAssertEqual(odd.allQuestionIds, ["q2", "q1"])
    }

    // MARK: - 落盘

    /// **普通练习写出去的 JSON 一个字节都不能变**：这个字段是 Optional，
    /// Swift 合成的编码器对它走 `encodeIfPresent`，所以旧版本 App 与上游 Windows 版
    /// 读到的仍然是原来那份形状（与 `retraining` 同一套做法）。
    func testAnOrdinarySessionDoesNotGainANewKeyOnDisk() throws {
        let data = try JSONEncoder().encode(session(id: "s1", questionId: "q1"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("drawnQuestionIds"))
    }

    func testDrawnIdsSurviveARoundTrip() throws {
        let original = session(id: "s1", questionId: "q1", drawn: ["q1", "q2"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: data)
        XCTAssertEqual(decoded.drawnQuestionIds, ["q1", "q2"])
    }

    /// 这个字段坏掉时退回「这不是随机抽题的一场」，**不许把整份训练数据挡在门外**
    /// （与 `retraining`、`focusPart` 同一条容错约定）。
    func testABrokenFieldDoesNotTakeTheWholeRecordDown() throws {
        let json = #"""
        {"id":"s1","questionId":"q1","focusPart":"Part 1","startedAt":"","endedAt":"",
         "goal":"","transcript":[],"reportPath":"","recordingPath":"",
         "drawnQuestionIds":"q1,q2"}
        """#
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertNil(decoded.drawnQuestionIds)
        XCTAssertEqual(decoded.allQuestionIds, ["q1"])
    }

    // MARK: - 「已练」标记

    /// 一场抽了三道全练了，却只有开场那道被标成已练的话，另外两道会永远停在「新题」。
    func testEveryQuestionInADrawIsMarkedPracticed() {
        let questions = [question("q1"), question("q2"), question("q3"), question("q4")]
        let reconciled = CoachState.reconcilePracticedStatus(
            questions: questions,
            sessions: [session(id: "s1", questionId: "q1", drawn: ["q1", "q2", "q3"])])
        XCTAssertEqual(reconciled.filter { $0.status == "practiced" }.map(\.id),
                       ["q1", "q2", "q3"])
        XCTAssertEqual(reconciled.first { $0.id == "q4" }?.status, "new",
                       "没被抽到的题一个字都不该动")
    }

    // MARK: - 换季重导之后还得认得出来

    /// 题库重建模会把 Part 1 / Part 3 每一道题的 id 都换掉（题号是内容哈希）。
    /// 这一组 id 不跟着搬的话，那几道题的「已练」标记再也算不回来——
    /// 数据都在，只是对不上号了。
    func testDrawnIdsAreCarriedOverWhenQuestionIDsChange() {
        var state = CoachState.empty()
        state.sessions = [session(id: "s1", questionId: "old-1", drawn: ["old-1", "old-2"])]
        let changed = QuestionBankMigration.remapQuestionIDs(
            in: &state, replacements: ["old-1": "new-1", "old-2": "new-1"])
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(state.sessions[0].questionId, "new-1")
        XCTAssertEqual(state.sessions[0].drawnQuestionIds, ["new-1"],
                       "两道旧碎片搬到同一道话题题上时要去重，否则这一场会被算成练了两遍")
    }
}
