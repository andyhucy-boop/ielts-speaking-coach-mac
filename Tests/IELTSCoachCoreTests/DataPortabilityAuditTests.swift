import XCTest
@testable import IELTSCoachCore

final class DataPortabilityAuditTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "portability-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    // MARK: - 造数据

    private func session(_ id: String, report: String, recording: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                        goal: "", transcript: [], reportPath: report, recordingPath: recording)
    }

    private func state(_ sessions: [PracticeSession],
                       sources: [QuestionSource] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.questionSources = sources
        return value
    }

    private func writeFile(_ relativePath: String) throws {
        let url = directory.root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    // MARK: - 干净的数据目录

    func testRelativePathsWithExistingFilesProduceNoFindings() throws {
        try writeFile("reports/s1.json")
        try writeFile("recordings/s1.m4a")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
    }

    func testEmptyPathsAreNotFindings() throws {
        // 练习还没生成复盘、或者没开录音时，这两个字段本来就是空的。
        // 把它当成错误会让用户每次打开都看到一屏红字，最后学会忽略所有告警 ——
        // 那时真正的问题也一起被忽略了。
        let value = state([session("s1", report: "", recording: "")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty)
    }

    // MARK: - 不可搬迁的写法

    func testAbsoluteReportPathIsReportedWithItsExactLocation() {
        let value = state([
            session("s1", report: "reports/s1.json"),
            session("s2", report: "/Users/someone/Library/Application Support/IELTS Speaking Coach/reports/s2.json")
        ])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].location, "sessions[1].reportPath")
        XCTAssertTrue(findings[0].message.contains("下一步"), "每条问题都必须说下一步做什么")
    }

    func testTildePathIsReported() {
        let value = state([session("s1", report: "~/Documents/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testFileURLIsReported() {
        let value = state([session("s1", report: "file:///tmp/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testPathEscapingTheDataDirectoryIsReported() {
        let value = state([session("s1", report: "../elsewhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testAbsoluteRecordingPathIsReported() {
        let value = state([session("s1", report: "reports/s1.json",
                                   recording: "/Users/someone/Music/s1.m4a")])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].recordingPath"])
    }

    func testLocalQuestionSourceURLIsReportedButHTTPSIsFine() {
        let local = QuestionSource(title: "季度题库", sourceUrl: "/Users/someone/Downloads/题库.pdf",
                                   importedAt: "2026-08-06T00:00:00Z",
                                   importLevel: "full-question", questionCount: 10)
        let remote = QuestionSource(title: "线上题库", sourceUrl: "https://example.com/bank.json",
                                    importedAt: "2026-08-06T00:00:00Z",
                                    importLevel: "full-question", questionCount: 10)
        let findings = DataPortabilityAudit.audit(state: state([], sources: [local, remote]))
        XCTAssertEqual(findings.map(\.location), ["questionSources[0].sourceUrl"],
                       "https 链接换机器照样打得开，不该报；本机文件路径才是问题")
    }

    // MARK: - 文件到底在不在

    func testMissingReportFileIsReportedByTheDirectoryAudit() {
        // 路径写法没问题，但文件没跟着拷过来 —— 换机器后点开历史复盘会是一片空白。
        let value = state([session("s1", report: "reports/s1.json")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty,
                      "只看 state 时看不出文件在不在，这一层不该报")
        let findings = DataPortabilityAudit.audit(state: value, directory: directory)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].reportPath"])
        XCTAssertTrue(findings[0].problem.contains("找不到"), "要说清是文件不见了，不是路径写错了")
    }

    func testMissingRecordingFileIsReportedByTheDirectoryAudit() throws {
        try writeFile("reports/s1.json")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory)
                        .map(\.location), ["sessions[0].recordingPath"])
    }

    // 计划外补的一条：`checkExists` 里区分「不存在」与「存在但是文件夹」的那一支
    // 是本次实现比计划多出来的逻辑，多出来的产品代码必须有测试守着。
    // 它同时是 testEmptyPathsAreNotFindings 能变红的前提 —— 见报告里的突变 A′。
    func testPathPointingAtAFolderIsReportedToo() throws {
        // 只判 fileExists 会说「在」，可点开是一片空白，与「文件没跟着拷过来」
        // 是同一类故障：记录指着的东西打不开。
        try writeFile("reports/s1.json")     // 顺带把 reports/ 这个目录建出来
        let value = state([session("s1", report: "reports")])
        let findings = DataPortabilityAudit.audit(state: value, directory: directory)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].reportPath"])
        XCTAssertTrue(findings[0].problem.contains("文件夹"), "要说清是指错了对象，不是文件不见了")
        XCTAssertTrue(findings[0].message.contains("下一步"), "每条问题都必须说下一步做什么")
    }

    func testAbsolutePathIsNotAlsoReportedAsMissing() {
        // 同一个字段只能报一次，否则用户会以为有两个不同的问题要修。
        let value = state([session("s1", report: "/tmp/nowhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory).count, 1)
    }

    // MARK: - 报全，而不是只报第一条

    func testEveryProblemIsReportedNotJustTheFirst() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "~/b.m4a"),
            session("s2", report: "file:///c.json")
        ])
        XCTAssertEqual(Set(DataPortabilityAudit.audit(state: value).map(\.location)),
                       ["sessions[0].reportPath", "sessions[0].recordingPath", "sessions[1].reportPath"])
    }

    func testFindingIDsAreUnique() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "/abs/b.m4a"),
            session("s2", report: "/abs/c.json")
        ])
        let ids = DataPortabilityAudit.audit(state: value).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "列表渲染要用 id，重复会错乱")
    }
}
