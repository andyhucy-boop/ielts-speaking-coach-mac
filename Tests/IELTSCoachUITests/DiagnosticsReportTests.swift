import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class DiagnosticsReportTests: XCTestCase {
    private let secretAnswer = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
    private let secretIssue = "I-VERY-LIKE-IT-SECRET"
    private let secretWord = "SECRET-VOCAB-WORD"
    private let secretName = "SECRET-LEARNER-NAME"

    private func metadata() -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: .selfSigned)
    }

    private func loadedState() -> CoachState {
        var state = CoachState.empty(displayName: secretName)
        state.questions = [
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?"),
            Question(id: "q2", part: 2, topic: "Skills", prompt: "Describe a useful skill.")
        ]
        state.sessions = [
            PracticeSession(id: "s1", questionId: "q1", focusPart: .part1,
                            startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                            goal: "",
                            transcript: [PracticeSession.TranscriptTurn(
                                role: "user", text: secretAnswer, capturedAt: "2026-08-06T00:01:00Z")],
                            reportPath: "reports/s1.json", recordingPath: "")
        ]
        state.issues = [IssueRecord(id: "i1", learnerSaid: secretIssue, correction: "c",
                                    whyItMatters: "w", occurrences: 3,
                                    sourceSessionIds: ["s1"], lastSeenAt: "2026-08-06T00:00:00Z")]
        state.vocabulary = [VocabularyRecord(id: "v1", basicWord: secretWord,
                                             betterExpression: "b", collocation: "c",
                                             priority: "high", sourceSessionIds: ["s1"])]
        state.targets = [RetrainingTarget(targetKey: "t1", label: "L", status: "new",
                                          evidence: [], sourceSessionId: "s1", createdAt: "t")]
        return state
    }

    private func input(permission: PermissionState = .ready,
                       findings: Int = 0) -> DiagnosticsInput {
        DiagnosticsInput(metadata: metadata(),
                         dataDirectory: URL(fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach"),
                         systemVersion: "macOS 26.5.2",
                         permission: permission,
                         state: loadedState(),
                         portabilityFindingCount: findings)
    }

    func testContainsWhatSomeoneWouldNeedToDiagnoseIt() {
        let text = DiagnosticsReport.text(input())
        for needle in ["1.0.0", "42", "a1b2c3d", "com.ielts.speakingcoach",
                       "macOS 26.5.2",
                       "/Users/tester/Library/Application Support/IELTS Speaking Coach"] {
            XCTAssertTrue(text.contains(needle), "诊断信息里缺了「\(needle)」：\n\(text)")
        }
    }

    func testNeverLeaksPracticeContent() {
        // 这段话是要发给别人看的。数量可以给，内容一个字都不能带出去。
        let text = DiagnosticsReport.text(input())
        for secret in [secretAnswer, secretIssue, secretWord, secretName] {
            XCTAssertFalse(text.contains(secret),
                           "诊断信息把练习内容带出去了：「\(secret)」\n\(text)")
        }
    }

    func testReportsCountsInsteadOfContent() {
        let text = DiagnosticsReport.text(input())
        XCTAssertTrue(text.contains("2 题"), "题库数量应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 次"), "练习次数应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 条"), "错题/词汇数量应该给：\n\(text)")
    }

    func testEveryPermissionStateIsExplainedInChinese() {
        // 诊断信息里出现 "needsAccessibility" 这种枚举名，对用户等于没写。
        for state in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertFalse(text.contains("needsAccessibility"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("needsChatGPT"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("unknown"), "\(state) 露出了枚举名")
        }
    }

    func testUnreadyPermissionAlwaysCarriesANextStep() {
        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertTrue(text.contains("下一步"), "\(state) 没告诉用户下一步做什么：\n\(text)")
        }
    }

    func testPortabilityProblemsAreSurfacedWithANextStep() {
        let clean = DiagnosticsReport.text(input(findings: 0))
        XCTAssertTrue(clean.contains("没有发现问题"))

        let dirty = DiagnosticsReport.text(input(permission: .ready, findings: 3))
        XCTAssertTrue(dirty.contains("3"), "要说清有几处")
        XCTAssertTrue(dirty.contains("下一步"), "有问题就必须给下一步")
    }

    func testNoLineIsBlankOrEndsWithADanglingLabel() {
        // 「版本：」后面空着，比不写还糟：用户会以为程序坏了。
        let text = DiagnosticsReport.text(input())
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "有空行：\n\(text)")
            XCTAssertFalse(line.hasSuffix("："), "有标签后面没内容：「\(line)」")
        }
    }

    /// **这段文字绝不自己往外发。** 它只负责把环境与错误拼成一段话；
    /// 拼完之后放进剪贴板、粘到哪儿去，全由用户决定（Task 7 的「复制诊断信息」按钮）。
    ///
    /// 为什么要用扫源码守：`text(_:)` 今天是个纯函数，返回一段 `String`，
    /// 从签名上看不出「它有没有顺手发出去」——加一句
    /// `URLSession.shared.dataTask(with: …).resume()` 进去，上面七条测试一条都不会红，
    /// 而用户的数据目录路径、系统版本、练习数量就已经离开这台电脑了。
    /// 「顺手替用户把诊断发给开发者，省得他还要粘贴」是一个非常自然的改动，
    /// 所以这条边界只能由代码之外的东西守着。
    ///
    /// 剪贴板（`NSPasteboard`）不在禁止之列——复制正是这段文字的用途，
    /// 且粘到哪儿仍然是用户按的那一下决定的。
    func testTheReportIsAssembledButNeverSentAnywhere() throws {
        let source = try SourceGuard.code("About/DiagnosticsReport.swift")
        for sender in ["URLSession", "URLRequest", "NSSharingService", "NSXPCConnection",
                       "Process(", "mailto:", "http://", "https://", "Network."] {
            XCTAssertFalse(source.contains(sender),
                           "`DiagnosticsReport.swift` 里出现了「\(sender)」——"
                               + "这段诊断文字只许被拼出来，不许自己送到任何地方去。"
                               + "下一步：把发送那一步交回给用户（复制到剪贴板，粘去哪儿他自己定）。")
        }
        // 防空转：文件读空了、路径写错了，上面那圈会全绿。
        XCTAssertTrue(source.contains("public static func text"),
                      "没读到 `text(_:)` 的声明，这条测试多半在扫一个空字符串")
    }
}
