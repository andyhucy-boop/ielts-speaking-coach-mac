import XCTest
@testable import IELTSCoachCore

/// 删掉词汇本里的一条词（2026-08-08 复审第 11 条）。
///
/// 这个入口存在的理由：导出跳过残缺词条时给的两条「下一步」之一就是
/// 「到「我的词汇」页把这条删掉」，而在这之前**全应用没有任何地方能删单条词汇**，
/// 用户唯一的出路是手动去改 state.json——那在任何面向用户的文案里都没提过。
final class VocabularyDeletionTests: XCTestCase {

    private func record(id: String, word: String, sessions: [String] = ["s1"]) -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: word, betterExpression: "b",
                         collocation: "c", priority: "high", sourceSessionIds: sessions)
    }

    private func state(_ records: [VocabularyRecord]) -> CoachState {
        var value = CoachState.empty()
        value.vocabulary = records
        return value
    }

    func testRemovesExactlyTheOneRow() {
        var value = state([record(id: "v1", word: "good"), record(id: "v2", word: "nice")])
        XCTAssertTrue(VocabularyDeletion.remove(id: "v1", from: &value))
        XCTAssertEqual(value.vocabulary.map(\.id), ["v2"])
    }

    /// **按 id 删，不许按词删。** state.json 被外部工具写坏时会出现两条同词记录，
    /// 按词删会一次删掉两条，而用户只点了一条——一次不可撤销的多删。
    func testTwoRecordsOfTheSameWordAreNotDeletedTogether() {
        var value = state([record(id: "v1", word: "good"), record(id: "v2", word: "good")])
        XCTAssertTrue(VocabularyDeletion.remove(id: "v1", from: &value))
        XCTAssertEqual(value.vocabulary.map(\.id), ["v2"])
    }

    /// 删一条词**只动词汇本**。练习记录、复盘、错题、复训目标一个字都不许碰——
    /// 「顺手清理一下相关数据」正是这个项目在别处栽过的那种改动。
    func testNothingButTheVocabularyListIsTouched() {
        var value = state([record(id: "v1", word: "good")])
        value.sessions = [PracticeSession(id: "s1", questionId: "q", focusPart: .part1,
                                          startedAt: "2026-08-01T10:00:00Z",
                                          endedAt: "2026-08-01T10:20:00Z", goal: "",
                                          transcript: [], reportPath: "reports/s1.json",
                                          recordingPath: "")]
        value.issues = [IssueRecord(id: "i1", learnerSaid: "s", correction: "c",
                                    whyItMatters: "w", occurrences: 1,
                                    sourceSessionIds: ["s1"], lastSeenAt: "t")]
        value.targets = [RetrainingTarget(targetKey: "k", label: "l", status: "new",
                                          evidence: [], sourceSessionId: "s1", createdAt: "t")]
        let before = value

        VocabularyDeletion.remove(id: "v1", from: &value)

        XCTAssertTrue(value.vocabulary.isEmpty)
        XCTAssertEqual(value.sessions, before.sessions)
        XCTAssertEqual(value.issues, before.issues)
        XCTAssertEqual(value.targets, before.targets)
    }

    /// 那条已经不在了要如实返回 false。装作删成功了，用户会以为界面在骗他。
    func testDeletingSomethingThatIsAlreadyGoneReportsIt() {
        var value = state([record(id: "v1", word: "good")])
        XCTAssertFalse(VocabularyDeletion.remove(id: "v9", from: &value))
        XCTAssertEqual(value.vocabulary.count, 1)
    }

    // MARK: - 文案

    func testConfirmationSaysWhatDisappearsAndWhatDoesNot() {
        let text = VocabularyDeletion.confirmationText(
            for: record(id: "v1", word: "good", sessions: ["s1", "s2", "s1"]))
        XCTAssertTrue(text.contains("「good」"), text)
        XCTAssertTrue(text.contains("2 场"), "同一场重复引用只算一场：\(text)")
        XCTAssertTrue(text.contains("不受影响"), "得说清练习记录不会跟着删：\(text)")
        XCTAssertTrue(text.contains("没有撤销"), "不可撤销这件事必须写在按下去之前：\(text)")
        XCTAssertTrue(text.contains("下一步"), text)
    }

    /// 残缺条目（原词也是空的）正是这个入口的头号服务对象。
    /// 拼出「删掉「」？」这种句子的话，用户根本不知道自己在删什么。
    func testAnEntryWithoutEvenABasicWordStillGetsAReadableConfirmation() {
        let blank = VocabularyRecord(id: "v1", basicWord: "  ", betterExpression: "",
                                     collocation: "", priority: "normal", sourceSessionIds: ["s1"])
        let text = VocabularyDeletion.confirmationText(for: blank)
        XCTAssertFalse(text.contains("「」"), "空词拼出了一对空引号：\(text)")
        XCTAssertTrue(text.contains("没有原词"), text)
    }

    func testSuccessNoticeSaysWhatIsLeftAndWhatWasNotTouched() {
        let text = VocabularyDeletion.successNotice(for: record(id: "v1", word: "good"),
                                                    remaining: 12)
        XCTAssertTrue(text.contains("「good」"), text)
        XCTAssertTrue(text.contains("12"), "得说清还剩几个，否则用户不知道删掉的是不是他点的那条：\(text)")
        XCTAssertTrue(text.contains("下一步"), text)
    }

    func testAlreadyGoneNoticeDoesNotClaimSuccess() {
        let text = VocabularyDeletion.alreadyGoneNotice(remaining: 3)
        XCTAssertTrue(text.contains("没有删除"), text)
        XCTAssertTrue(text.contains("下一步"), text)
    }
}
