import XCTest
@testable import IELTSCoachCore

/// 一条练习记录里的一个字段坏掉，不许把**整份**训练数据挡在门外（复审第 5 条）。
///
/// 修之前：`PracticeSession` 用的是 Swift 合成的解码器，`focusPart` 只要不是
/// `"Part 1"/"Part 2"/"Part 3"/"full mock"` 这四个字符串之一就抛 `dataCorrupted`，
/// 那个错一路冒泡到 `StateStore`，用户开 App 看到的是
/// 「训练数据文件已损坏，无法读取……下一步：把该文件改名备份后重新启动」——
/// **练习记录、错题本、词汇本、复训目标、计划、题库、设置全部一起读不出来**，
/// 而坏掉的只是某一条记录里的一个展示用字段。
/// 用户照着那句提示改名之后，全部历史才真正作废。
///
/// 触发来源都是真实的：本工具自己的错误提示会引导用户去手改 state.json；
/// 从 Windows/JS 版带过来的数据；将来给 `FocusPart` 加了新 case 之后回退到旧版本。
///
/// 策略与 `TrainingPlan` 那处完全一致：认不出来就退回默认值，
/// 代价是那一条记录的 Part 标签显示得不准，换整份数据还能打开。
final class PracticeSessionCodableTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, questionId: String = "q1") -> PracticeSession {
        PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "先给答案再补原因",
                        transcript: [PracticeSession.TranscriptTurn(
                            role: "assistant", text: "Do you work or study?",
                            capturedAt: "2026-08-06T10:01:00Z")],
                        reportPath: "reports/\(id).json", recordingPath: "")
    }

    // MARK: - 用本工具自己的写盘代码造数据，再手改一个字符

    /// **这条是第 5 条的复现。** 走的是真实的读写路径：
    /// 先用 `StateStore` 写出一份带练习记录、错题本、词汇本、题库的 state.json，
    /// 再像用户那样手改一个字符（`"Part 1"` → `"part 1"`，大小写打错），然后重新读。
    func testOneMistypedFocusPartDoesNotLockTheUserOutOfEverythingElse() throws {
        let store = StateStore(directory: directory)
        try store.mutate { state in
            state.sessions = [self.session("2026-08-06-001"), self.session("2026-08-06-002")]
            state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                        correction: "I really like it", whyItMatters: "搭配",
                                        occurrences: 1, sourceSessionIds: ["2026-08-06-001"],
                                        lastSeenAt: "2026-08-06T10:20:00Z")]
            state.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good",
                                                 betterExpression: "rewarding",
                                                 collocation: "a rewarding experience",
                                                 priority: "high",
                                                 sourceSessionIds: ["2026-08-06-001"])]
            state.questions = [Question(id: "q1", part: 1, topic: "Work", prompt: "Do you work?")]
        }

        // 用户打开 state.json 手改（本工具的录音错误提示正是这么引导他的），大小写打错了。
        let raw = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"Part 1\""), "前提没成立：写出来的文件里没有这个字段")
        try raw.replacingOccurrences(of: "\"Part 1\"", with: "\"part 1\"")
            .write(to: directory.stateFile, atomically: true, encoding: .utf8)

        let reloaded = try StateStore(directory: directory).load()

        XCTAssertEqual(reloaded.sessions.count, 2, "两条练习记录一条都不能少")
        XCTAssertEqual(reloaded.sessions[0].focusPart, .fullMock,
                       "认不出来的 Part 退回全真模考，而不是让整份数据打不开")
        XCTAssertEqual(reloaded.sessions[0].goal, "先给答案再补原因", "同一条记录的其余字段要原样在")
        XCTAssertEqual(reloaded.sessions[0].transcript.count, 1, "逐字稿不能因为一个坏字段丢掉")
        XCTAssertEqual(reloaded.sessions[0].reportPath, "reports/2026-08-06-001.json")
        XCTAssertEqual(reloaded.issues.count, 1, "错题本被一条坏记录连累了")
        XCTAssertEqual(reloaded.vocabulary.count, 1, "词汇本被一条坏记录连累了")
        XCTAssertEqual(reloaded.questions.count, 1, "题库被一条坏记录连累了")
    }

    /// 跨版本回退那条路：将来加了 `"Part 4"` 这种新 case，旧版本 App 读到必须退回默认值。
    func testAFocusPartFromANewerVersionFallsBackInsteadOfThrowing() throws {
        let json = """
        {"id":"2026-08-06-001","questionId":"q1","focusPart":"Part 4",
         "startedAt":"2026-08-06T10:00:00Z","endedAt":"2026-08-06T10:20:00Z","goal":"",
         "transcript":[],"reportPath":"reports/a.json","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.focusPart, .fullMock)
        XCTAssertEqual(decoded.id, "2026-08-06-001")
    }

    /// 认识的四个值一个都不许被这道闸改掉——改掉的话每条记录的 Part 标签都会显示成全真模考。
    func testEveryKnownFocusPartStillDecodesToItself() throws {
        for part in FocusPart.allCases {
            let json = """
            {"id":"s","questionId":"q","focusPart":"\(part.rawValue)",
             "startedAt":"","endedAt":"","goal":"","transcript":[],
             "reportPath":"","recordingPath":""}
            """
            XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8)).focusPart,
                           part, "「\(part.rawValue)」被这道容错闸误伤了")
        }
    }

    // MARK: - 同一个结构里的其余字段

    /// 复审第 5 条最后一句：同一个结构里另外几个字段同样是「缺一个就炸」。
    /// 手改 state.json 时删掉一行、或从别的版本带数据过来，缺的常常是这些。
    func testAMissingOptionalFieldDoesNotBrickTheWholeFileEither() throws {
        // 只留 id 和 questionId，其余全缺。
        let json = #"{"id":"2026-08-06-001","questionId":"q1"}"#
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, "2026-08-06-001")
        XCTAssertEqual(decoded.questionId, "q1")
        XCTAssertEqual(decoded.focusPart, .fullMock)
        XCTAssertEqual(decoded.startedAt, "")
        XCTAssertEqual(decoded.transcript, [])
        XCTAssertEqual(decoded.reportPath, "")
        XCTAssertNil(decoded.retraining)
    }

    /// 类型也可能被改坏（把字符串写成了数字），同样不许连累整份文件。
    func testAFieldOfTheWrongTypeFallsBackInsteadOfThrowing() throws {
        let json = """
        {"id":"2026-08-06-001","questionId":"q1","focusPart":"Part 2",
         "startedAt":12345,"endedAt":"2026-08-06T10:20:00Z","goal":"",
         "transcript":[],"reportPath":"reports/a.json","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.startedAt, "", "坏掉的时间戳退回空串")
        XCTAssertEqual(decoded.focusPart, .part2, "别的字段不受影响")
        XCTAssertEqual(decoded.reportPath, "reports/a.json")
    }

    /// 逐字稿里的一句坏掉，不许把整场记录（连带整份文件）拖下水。
    func testABrokenTranscriptTurnDoesNotThrowAwayTheWholeSession() throws {
        let json = """
        {"id":"2026-08-06-001","questionId":"q1","focusPart":"Part 1",
         "startedAt":"","endedAt":"","goal":"","reportPath":"","recordingPath":"",
         "transcript":[{"role":"assistant","text":"Do you work?","capturedAt":"t1"},
                       {"role":"user"}]}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        // 刻意不用下标：断言红了之后下标会越界崩掉整个测试进程，
        // 后面所有测试的结果就一起看不见了。
        XCTAssertEqual(decoded.transcript.count, 2, "缺字段的那一句不该让整条记录读不出来")
        XCTAssertEqual(decoded.transcript.first?.text, "Do you work?")
        XCTAssertEqual(decoded.transcript.last?.text, "", "缺 text 的那一句退回空串")
        XCTAssertEqual(decoded.transcript.last?.role, "user", "同一句里没坏的字段要留着")
    }

    /// `id` 是**唯一**仍然必需的字段，而且必须继续必需。
    ///
    /// 没有 id 的记录在界面上无法寻址：列表的唯一键、删除、复盘、复训全靠它。
    /// 给它兜一个空串，两条这样的记录就会在 SwiftUI 的 ForEach 里撞成同一行，
    /// 用户删掉一条会看到另一条跟着消失——比读不出来更糟。
    func testARecordWithoutAnIDIsStillARealError() {
        let json = #"{"questionId":"q1","focusPart":"Part 1"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8)))
    }

    // MARK: - 写回去的还得是原来那份

    /// 容错只加在读这一侧，写出来的形状一个字都不许变：
    /// 变了的话，用户拿这份数据回上游 Windows/JS 版就读不出来了。
    func testEncodingStillWritesEveryFieldSoTheFileShapeDoesNotChange() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let raw = try XCTUnwrap(String(data: try encoder.encode(session("2026-08-06-001")),
                                       encoding: .utf8))
        for key in ["id", "questionId", "focusPart", "startedAt", "endedAt", "goal",
                    "transcript", "reportPath", "recordingPath"] {
            XCTAssertTrue(raw.contains("\"\(key)\""), "写出来的记录里少了 \(key)：\(raw)")
        }
        XCTAssertTrue(raw.contains("\"Part 1\""), "focusPart 还得按原来的字符串写出去")
        XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self, from: Data(raw.utf8)),
                       session("2026-08-06-001"))
    }
}
