import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 「问题反馈」页。
///
/// ## 为什么这一页要单独有一组测试
///
/// 计划 Task 18 的 Step 5 只给了一张验收表（「必须做到 / 判据」），没有测试步骤。
/// Task 5 的 `DiagnosticsReportTests` 守的是**那段文字**，`FeedbackPrivacyContractTests`
/// 守的是**源码里不许出现联网符号**——两者都证明不了「这一页真的把那段文字画出来了」，
/// 也证明不了「复制那一下真的写进了剪贴板、失败时真的说了话」。
/// 关于页（`AboutViewTests`）与功能升级页（`UpgradeViewTests`）都为同一个原因补过这组，
/// 本项目已实测过五次「算好了却一个像素都不上屏，全套测试照样绿」。
///
/// 分两类：
///
/// 一、**真跑起来的断言**（`FeedbackPageModel`）：复制成功 / 失败、打开数据目录成功 / 失败、
///    诊断文本里带什么不带什么。全程用临时数据目录与假 preflight，**绝不接触真实 ChatGPT**
///    （铁律 5），也不碰真实剪贴板与访达。
///
/// 二、**扫源码**（`Feedback/FeedbackView.swift`）：`swift test` 不画界面，
///    所以退一步问「这段渲染还在不在渲染树里」。拦得住整段被删、接线被换掉；
///    拦不住排版好不好看——那部分归 Task 19 的人工验收。
@MainActor
final class FeedbackViewTests: XCTestCase {

    private static let view = "Feedback/FeedbackView.swift"

    private var directory: DataDirectory!

    override func setUpWithError() throws {
        directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-feedback-\(UUID().uuidString)"))
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 测试替身：不碰真实 ChatGPT、不碰真实剪贴板、不真的打开访达

    private final class PasteboardSpy {
        private(set) var written: String?
        var succeeds = true

        func write(_ text: String) -> Bool {
            guard succeeds else { return false }
            written = text
            return true
        }
    }

    private final class FinderSpy {
        private(set) var opened: URL?
        var succeeds = true

        func reveal(_ url: URL) -> Bool {
            guard succeeds else { return false }
            opened = url
            return true
        }
    }

    /// 假 preflight。**绝不接触真实 ChatGPT（铁律 5）。**
    private func makeApp(messages: [String] = ["✅ 找到 ChatGPT"]) -> AppState {
        AppState(directory: directory,
                 preflight: { BridgeReadiness(ok: true, messages: messages) })
    }

    private func makeModel(app: AppState? = nil,
                           log: LastErrorLog = LastErrorLog(),
                           pasteboard: PasteboardSpy = PasteboardSpy(),
                           finder: FinderSpy = FinderSpy()) -> FeedbackPageModel {
        FeedbackPageModel(app: app ?? makeApp(),
                          log: log,
                          directory: directory,
                          metadata: AppMetadata(displayName: "IELTS Speaking Coach",
                                                bundleIdentifier: "com.ielts.speakingcoach",
                                                shortVersion: "1.0.0", buildNumber: "42",
                                                buildCommit: "a1b2c3d",
                                                buildDate: "2026-08-06T09:00:00Z",
                                                signingIdentity: "IELTS Coach Dev",
                                                channel: .selfSigned),
                          systemVersion: "macOS 26.5.2",
                          reveal: { finder.reveal($0) },
                          writeToPasteboard: { pasteboard.write($0) })
    }

    // MARK: - 一、复制：真的写进剪贴板，且成功失败都要说话

    func testCopyingPutsTheDiagnosticsOnThePasteboard() throws {
        let board = PasteboardSpy()
        let model = makeModel(pasteboard: board)

        model.copyDiagnostics()

        let copied = try XCTUnwrap(board.written, "「复制诊断信息」什么都没写进剪贴板")
        XCTAssertEqual(copied, model.diagnosticsText,
                       "写进剪贴板的和页面上显示的不是同一段文字，用户粘出来的会是另一份东西")
        XCTAssertTrue(copied.contains("1.0.0"), "诊断信息里连版本都没有：\n\(copied)")
    }

    /// **成功也要说话。** 只在失败时才出声的话，用户分不清「成功了」和「点了没反应」。
    func testCopyingSaysSoRightAway() throws {
        let model = makeModel()
        model.copyDiagnostics()

        let notice = try XCTUnwrap(model.notice, "复制成功了却一声不吭，用户不知道点没点上")
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("已复制"), notice.text)
    }

    /// 剪贴板会失败（别的进程正占着它）。**吞掉它再说一句「已复制」是铁律 7 明禁的。**
    func testAFailedCopySaysWhatHappenedAndWhatToDoNext() throws {
        let board = PasteboardSpy()
        board.succeeds = false
        let model = makeModel(pasteboard: board)

        model.copyDiagnostics()

        let notice = try XCTUnwrap(model.notice, "写剪贴板失败了却一声不吭（铁律 7）")
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("下一步"), "只说了失败，没说下一步做什么：\(notice.text)")
        XCTAssertTrue(notice.text.contains("⌘C"),
                      "那句「下一步」得是用户真做得到的一步——这一页的诊断文本是可选中的，"
                      + "自己按 ⌘C 就是那条退路：\(notice.text)")
    }

    // MARK: - 二、打开数据目录：打不开必须说话

    func testOpeningTheDataDirectoryHandsFinderTheRightFolder() throws {
        let finder = FinderSpy()
        let model = makeModel(finder: finder)

        model.revealDataDirectory()

        XCTAssertEqual(finder.opened, directory.root)
        XCTAssertEqual(model.notice?.isFailure, false)
    }

    func testAFailedRevealSaysWhereTheFolderIsSoTheUserCanGoThereHimself() throws {
        let finder = FinderSpy()
        finder.succeeds = false
        let model = makeModel(finder: finder)

        model.revealDataDirectory()

        let notice = try XCTUnwrap(model.notice, "访达没打开却一声不吭（铁律 7）")
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains(directory.root.path),
                      "没把路径写出来，用户连自己去找都没法找：\(notice.text)")
        XCTAssertTrue(notice.text.contains("下一步"), notice.text)
    }

    // MARK: - 三、诊断文本：带够排障要的东西，一个字练习内容都不带

    func testTheDiagnosticsCarryTheEnvironmentCheckOutputOnceThereIsAny() async {
        let app = makeApp(messages: ["❌ 没有辅助功能权限"])
        let model = makeModel(app: app)
        await app.recheckPermission()

        XCTAssertTrue(model.diagnosticsText.contains("没有辅助功能权限"),
                      "环境检查原文没跟着发出去——「ChatGPT 改版打断自动化」时那几行是最有用的线索：\n"
                      + model.diagnosticsText)
    }

    func testTheDiagnosticsCarryTheLastErrorAsACodeAndNeverAsItsMessage() {
        let secret = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
        let log = LastErrorLog()
        log.record(CoachError.invalidReviewText("复盘里出现了 \(secret)"), at: .parsingReview)
        let text = makeModel(log: log).diagnosticsText

        XCTAssertTrue(text.contains("review-invalid-text"), "错误代号没带上，等于没记：\n\(text)")
        XCTAssertTrue(text.contains(DiagnosticsStage.parsingReview.title),
                      "没说清是哪一步出的错：\n\(text)")
        XCTAssertFalse(text.contains(secret), "这一页把错误原文带出去了：\n\(text)")
    }

    /// 还没出过错时，那一块要写字，不能是一片空白（DESIGN-SYSTEM 第 4 节）。
    func testAPageWithNoErrorsYetStillSaysSomethingAndGivesANextStep() {
        XCTAssertNil(makeModel().lastError)
        XCTAssertTrue(FeedbackPageModel.noErrorYet.contains("最近没有出错"))
        XCTAssertTrue(FeedbackPageModel.noErrorNextStep.contains("下一步"),
                      FeedbackPageModel.noErrorNextStep)
    }

    /// 量过之后，占用要真的进诊断文本。
    func testTheDiagnosticsCarryTheDataDirectoryUsageOnceItHasBeenMeasured() throws {
        try Data(repeating: 0x41, count: 3_000).write(to: directory.stateFile)
        let model = makeModel()
        XCTAssertFalse(model.diagnosticsText.contains("数据目录占用"),
                       "还没量就报了一个数字——那个数字从哪儿来的？")

        model.refreshUsage()

        XCTAssertTrue(model.diagnosticsText.contains("数据目录占用"),
                      "量过了却没进诊断文本：\n" + model.diagnosticsText)
        XCTAssertTrue(model.diagnosticsText.contains("KB"), "占用要写成人看得懂的单位")
    }

    // MARK: - 四、扫源码：这几块真的在渲染树里

    private func feedbackViewBody() throws -> String {
        let type = try SourceGuard.memberBody(of: "public struct FeedbackView",
                                              in: try SourceGuard.code(Self.view))
        return try SourceGuard.memberBody(of: "public var body", in: type)
    }

    /// **这一页的产品承诺，逐字。** 用户点进「问题反馈」时最先想知道的就是
    /// 「这玩意儿会不会把我的东西发出去」——这句话答的正是那个问题，少一个字都不行。
    func testThePromiseIsOnScreenVerbatim() throws {
        XCTAssertEqual(
            FeedbackPageModel.promise,
            "这一页不会把任何东西发到任何地方。复制之后要粘给谁、发不发，全由你决定。",
            "这一页的产品承诺被改写了。它不是一句普通文案：整页存在的前提就是这句话。")

        let code = try SourceGuard.code(Self.view)
        let header = try SourceGuard.memberBody(of: "private var header", in: code)
        XCTAssertTrue(header.contains("FeedbackPageModel.promise"),
                      "承诺那一句不在页头了：\(header.flattened)")
        XCTAssertTrue(try feedbackViewBody().contains("header"),
                      "`header` 只是声明着，没有被摆进 `FeedbackView.body`，一个像素都不会上屏。")
    }

    /// 隐私说明必须在屏幕上，而且要说清「有什么、没有什么」。
    func testThePrivacyNoteIsOnScreenAndSaysWhatIsNotInThere() throws {
        for piece in ["版本", "错误代号", "没有你说过的英语", "没有题目", "没有姓名"] {
            XCTAssertTrue(FeedbackPageModel.privacyNote.contains(piece),
                          "隐私说明里少了「\(piece)」：\(FeedbackPageModel.privacyNote)")
        }
        XCTAssertTrue(try feedbackViewBody().contains("privacyNote"),
                      "隐私说明没被摆进 `body`，用户按下「复制」之前看不到它。")
    }

    /// 诊断全文必须**可选中**：剪贴板失败时那句「自己按 ⌘C」就指着它。
    func testTheDiagnosticsBlockIsRenderedAndSelectable() throws {
        let card = try SourceGuard.memberBody(of: "private var diagnosticsCard",
                                              in: try SourceGuard.code(Self.view))
        XCTAssertTrue(card.contains("model.diagnosticsText"),
                      "诊断那一块不再读 `model.diagnosticsText` 了：\(card.flattened)")
        XCTAssertTrue(card.contains(".textSelection(.enabled)"),
                      "诊断全文选不中。剪贴板被别的程序占住时，那句「自己按 ⌘C」就指向空气了。")
        XCTAssertTrue(try feedbackViewBody().contains("diagnosticsCard"),
                      "`diagnosticsCard` 没被摆进 `body`——这一页就没有要复制的东西了。")
    }

    /// 三颗按钮各自接在该接的地方，且整页只有一个主行动。
    func testTheThreeButtonsAreWiredToTheThreeActions() throws {
        let actions = try SourceGuard.memberBody(of: "private var actions",
                                                 in: try SourceGuard.code(Self.view))
        for (title, call) in [("复制诊断信息", "model.copyDiagnostics()"),
                              ("重新检查环境", "model.recheckEnvironment()"),
                              ("打开数据目录", "model.revealDataDirectory()")] {
            XCTAssertTrue(actions.contains("Button(\"\(title)\")"),
                          "「\(title)」这颗按钮不见了：\(actions.flattened)")
            XCTAssertTrue(actions.contains(call),
                          "「\(title)」按下去不再调 `\(call)`：\(actions.flattened)")
        }
        XCTAssertEqual(SourceGuard.occurrences(of: ".borderedProminent", in: actions), 1,
                       "DESIGN-SYSTEM 第 4 节：每个页面最多一个主行动。"
                       + "两个同样醒目的紫色大块会让人不知道该点哪个。")
        XCTAssertTrue(try feedbackViewBody().contains("actions"),
                      "`actions` 没被摆进 `body`，这一页一颗按钮都没有。")
    }

    /// 「最近一次错误」那一块要在屏幕上，而且没出错时也得写字。
    func testTheLastErrorBlockIsRenderedAndNeverBlank() throws {
        let card = try SourceGuard.memberBody(of: "private var lastErrorCard",
                                              in: try SourceGuard.code(Self.view))
        XCTAssertTrue(card.contains("model.lastError"),
                      "这一块不再读 `model.lastError` 了：\(card.flattened)")
        XCTAssertTrue(card.contains("FeedbackPageModel.noErrorYet")
                      && card.contains("FeedbackPageModel.noErrorNextStep"),
                      "没出过错时这一块会是一片空白，用户会以为程序坏了：\(card.flattened)")
        XCTAssertTrue(try feedbackViewBody().contains("lastErrorCard"),
                      "`lastErrorCard` 没被摆进 `body`。")
    }

    /// 侧边栏点「问题反馈」落到的必须是这一页。
    ///
    /// `isImplemented` 标成 true 而 `RootView` 那个 `switch` 没接上的话，
    /// 用户点进去看到的是一片空白——而 `NavigationTests` 只问得到前半句。
    func testTheSidebarActuallyLandsOnThisPage() throws {
        let detail = try SourceGuard.memberBody(of: "private var detail",
                                                in: try SourceGuard.code("RootView.swift"))
        XCTAssertTrue(detail.contains("case .feedback: FeedbackView(app: app)"),
                      "侧边栏的「问题反馈」没接到 `FeedbackView` 上：\(detail.flattened)")
    }

    /// 样式全部走设计令牌（铁律 8）。全模块那一趟（`DesignTokenContractTests`）也扫得到这一页，
    /// 这里再点名一次，是为了这一页红的时候报错直接指到它。
    func testThePageTakesEveryStyleFromTheDesignTokens() {
        SourceGuard.assertUsesDesignTokens(in: Self.view)
    }
}

private extension String {
    /// 报错里贴原文用：压成一行，太长就截断——报错本身不该刷屏。
    var flattened: String {
        let flat = split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= 120 ? flat : String(flat.prefix(120)) + "…"
    }
}
