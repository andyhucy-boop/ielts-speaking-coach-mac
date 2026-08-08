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
                       findings: Int = 0,
                       usage: DataUsageReport? = nil,
                       environmentMessages: [String]? = nil,
                       lastError: DiagnosticsError? = nil) -> DiagnosticsInput {
        DiagnosticsInput(metadata: metadata(),
                         dataDirectory: URL(fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach"),
                         systemVersion: "macOS 26.5.2",
                         permission: permission,
                         state: loadedState(),
                         portabilityFindingCount: findings,
                         usage: usage,
                         environmentMessages: environmentMessages,
                         lastError: lastError)
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
        // 例外只有一种：以「：」结尾但下一行是列表项（如「环境检查：」后面跟着 - 开头的几行）。
        let text = DiagnosticsReport.text(input(environmentMessages: ["✅ 找到 ChatGPT"]))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "有空行：\n\(text)")
            guard line.hasSuffix("：") else { continue }
            let next = index + 1 < lines.count ? String(lines[index + 1]) : ""
            XCTAssertTrue(next.hasPrefix("- "),
                          "「\(line)」后面既没有内容也没有列表：\n\(text)")
        }
    }

    // MARK: - Phase 10 Task 18 追加的四行：占用、环境检查原文、最近一次错误

    func testDiagnosticsCarryTheEnvironmentCheckOutput() {
        // 「ChatGPT 改版打断自动化」是已知风险（ROADMAP 第 6 节）。
        // 真出问题时，preflight 的原文就是最有用的那几行。
        let text = DiagnosticsReport.text(
            input(environmentMessages: ["✅ 找到 ChatGPT", "❌ 没有辅助功能权限"]))
        XCTAssertTrue(text.contains("没有辅助功能权限"), text)
    }

    /// 「还没查过」和「查过了却没出声」是两件事，诊断文字里必须说成两句话。
    ///
    /// 关于页刻意不自动检查环境（那会把 ChatGPT 拉到前台，打断用户手上的事），
    /// 所以「一条输出都没有」正是它**没被点过「重新检查」时的正常状态**。
    /// 把它写成「这本身就不正常」，收到这段话的人会从一个假线索查起；
    /// 而页面若再补一句「这是设计如此」，同一段文字里就有两句打架的话了
    /// （2026-08-08 复审实测：关于页复制出来的原文正是这样）。
    func testAnEnvironmentThatWasNeverCheckedIsCalledUncheckedNotAbnormal() {
        let text = DiagnosticsReport.text(input(environmentMessages: nil))
        XCTAssertTrue(text.contains("还没查过"),
                      "没说清环境检查压根还没跑过：\n\(text)")
        XCTAssertFalse(text.contains("不正常"),
                       "还没查过是正常状态，说成「不正常」是把人往假线索上引：\n\(text)")
        XCTAssertTrue(text.contains("下一步"),
                      "只说「还没查过」不说怎么才能查（铁律 6）：\n\(text)")
    }

    /// 反过来的那一半：**真的查过了却一条输出都没有，那才是不正常**，必须点出来。
    /// 少了这条，把上面那一支写成「两种情况都说成还没查过」也是绿的。
    func testACheckThatRanButSaidNothingIsCalledOutAsAbnormal() {
        let text = DiagnosticsReport.text(input(environmentMessages: []))
        XCTAssertTrue(text.contains("不正常"),
                      "环境检查跑过了却一句话都没输出，这确实不正常，诊断里得说出来：\n\(text)")
        XCTAssertFalse(text.contains("还没查过"),
                       "查过了却说成「还没查过」，收到这段话的人会让用户再查一遍：\n\(text)")
    }

    func testDiagnosticsCarryTheDataDirectoryUsage() {
        let usage = DataUsageReport(totalBytes: 2_048, stateBytes: 48, reportBytes: 1_000,
                                    recordingBytes: 1_000, pendingReviewBytes: 0, fileCount: 3)
        XCTAssertTrue(DiagnosticsReport.text(input(usage: usage)).contains("KB"),
                      "占用要写成人看得懂的单位")
    }

    /// `LastErrorLog` 是 `@MainActor` 的（它是 `@Observable`，界面直接读），
    /// 所以这一条要标 `@MainActor`，否则 Swift 6 的并发检查过不去。
    @MainActor
    func testTheLastErrorNeverCarriesTheErrorMessageItself() {
        // 这一条是「最近一次错误」这个新字段唯一的存在条件。
        // CoachError 的消息里完全可能带着复盘原文，而复盘原文里全是用户说过的英语。
        let log = LastErrorLog()
        log.record(CoachError.invalidReviewText("复盘里出现了 \(secretAnswer)"),
                   at: .parsingReview, now: Date(timeIntervalSince1970: 1_785_931_530))
        let text = DiagnosticsReport.text(input(lastError: log.last))

        XCTAssertFalse(text.contains(secretAnswer), "诊断信息把错误原文带出去了：\n\(text)")
        XCTAssertTrue(text.contains("review-invalid-text"), "错误代号没带上，等于没记：\n\(text)")
    }

    func testSaysSoWhenNothingHasGoneWrongYet() {
        // 「最近一次错误：」后面空着，比不写还糟。
        let text = DiagnosticsReport.text(input(lastError: nil))
        XCTAssertTrue(text.contains("最近没有出错"), text)
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
