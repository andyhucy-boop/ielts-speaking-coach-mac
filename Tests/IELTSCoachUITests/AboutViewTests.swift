import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 关于页（苹果菜单 › 关于 IELTS Speaking Coach）。
///
/// ## 为什么这一页非有这组测试不可
///
/// 计划 Task 7 只写了「改 main.swift、写 AboutView、编译、人工验证」四步，**没有测试步骤**——
/// 而这一页恰好是本项目最容易出静默缺陷的那一类：
///
/// - 它是**独立窗口**，拿不到主窗口的 `AppState`，自己读一次 `state.json`。读失败时若不显示，
///   用户看到的就是一片空白（DESIGN-SYSTEM 第 4 节：空白页会让人以为程序坏了）。
/// - 它上面每一行都是**给别人看的事实**（版本、签名、数据目录、可搬迁检查）。
///   说错了不会崩、不会报错，只会让拿到这个 `.app` 的人照着一句错话去做。
/// - `AboutViewModel` 那六行已经被 `AboutViewModelTests` 钉死了，**但那证明不了它们上了屏**。
///   本项目已经四次实测过「删掉一段渲染，全套测试照样绿」。
///
/// ## 分成两类
///
/// 一、**模型行为**（`AboutPageModel`）：读盘失败、重试、重新检查、复制诊断、在访达中显示。
/// 这些是真跑起来的断言，用临时数据目录 + 假 preflight，**全程不接触真实 ChatGPT（铁律 5）**。
///
/// 二、**扫源码**（`AboutView.swift` / `main.swift`）：做法与 `RecordingSettingsViewTests`
/// 一致——`swift test` 不画界面，所以退一步问「这段渲染还在不在渲染树里」。
/// 拦得住整段渲染被删、接线被换掉；拦不住「代码还在但条件永远为假」和排版好不好看，
/// 那部分归 Task 11 的人工验收。
@MainActor
final class AboutViewTests: XCTestCase {

    private static let view = "About/AboutView.swift"

    private var directory: DataDirectory!

    override func setUpWithError() throws {
        directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-about-\(UUID().uuidString)"))
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 测试替身：一律不碰真实 ChatGPT、不碰真实剪贴板、不真的打开访达

    /// 假 preflight。**绝不接触真实 ChatGPT（铁律 5）。**
    private final class PreflightSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations = 0
        private let result: BridgeReadiness

        init(_ result: BridgeReadiness) { self.result = result }

        var calls: Int { lock.withLock { invocations } }

        func run() -> BridgeReadiness {
            lock.withLock { invocations += 1 }
            return result
        }
    }

    /// 假剪贴板。记下真正被交出去的那段文字——断言落在内容上，不落在「调了几次」。
    private final class PasteboardSpy {
        private(set) var written: String?
        var succeeds = true

        func write(_ text: String) -> Bool {
            written = text
            return succeeds
        }
    }

    /// 假访达。**按「这儿真的是一个文件夹吗」作答**，与生产实现
    /// （`AboutPageModel.revealInFinder`）同一条判据：这样「显示之前先把目录建出来」
    /// 这件事才是有约束力的——不建就打不开，测试当场红。
    ///
    /// 只判 `fileExists` 不行：数据目录该在的位置被同名文件占住时它照样是 true，
    /// 于是「打不开要说话」那条测试会永远绿。
    private final class FinderSpy {
        private(set) var asked: URL?

        func reveal(_ url: URL) -> Bool {
            asked = url
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path,
                                                        isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    private func makeModel(directory override: DataDirectory? = nil,
                           preflight: PreflightSpy? = nil,
                           pasteboard: PasteboardSpy? = nil,
                           finder: FinderSpy? = nil) -> AboutPageModel {
        let spy = preflight ?? PreflightSpy(BridgeReadiness(ok: true, messages: ["环境就绪"]))
        let board = pasteboard ?? PasteboardSpy()
        let finderSpy = finder ?? FinderSpy()
        return AboutPageModel(
            directory: override ?? directory,
            metadata: Self.metadata,
            systemVersion: "macOS 15.0",
            preflight: { spy.run() },
            reveal: { finderSpy.reveal($0) },
            writeToPasteboard: { board.write($0) })
    }

    private static let metadata = AppMetadata(
        displayName: "IELTS Speaking Coach",
        bundleIdentifier: "com.ielts.speakingcoach",
        shortVersion: "1.2.3", buildNumber: "42",
        buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
        signingIdentity: "IELTS Coach Dev", channel: .selfSigned)

    /// `AboutView` 那个 `body` 的大括号内容。
    ///
    /// **不能直接 `memberBody(of: "public var body")`**：这个文件里有两个 `public var body`
    /// （`AboutMenuButton` 一个、`AboutView` 一个），那样切出来的是排在前面的那一个，
    /// 于是「这一段摆进页面了吗」的断言全在检查另一个类型——最坏的一种空转。
    private func aboutViewBody() throws -> String {
        let type = try SourceGuard.memberBody(of: "public struct AboutView",
                                              in: try SourceGuard.code(Self.view))
        return try SourceGuard.memberBody(of: "public var body", in: type)
    }

    private func row(_ id: String, of model: AboutPageModel) throws -> AboutRow {
        try XCTUnwrap(model.rows.first { $0.id == id },
                      "关于页少了「\(id)」那一行。现在有的是：\(model.rows.map(\.id))")
    }

    /// 把一份能被 `DataPortabilityAudit` 挑出问题的记录写进磁盘。
    private func writeSessionWithAnAbsoluteReportPath() throws {
        try StateStore(directory: directory).mutate { state in
            state.sessions = [PracticeSession(
                id: "2026-08-06-001", questionId: "q1", focusPart: .part1,
                startedAt: "2026-08-06T09:00:00Z", endedAt: "2026-08-06T09:20:00Z",
                goal: "", transcript: [],
                reportPath: "/Users/someone/reports/a.json", recordingPath: "")]
        }
    }

    // MARK: - 一、辅助功能那一行：不许把「还没查」说成「查过了没通过」

    /// 打开关于页**不会**自动跑 preflight——那一下会 `NSWorkspace.open` 把 ChatGPT 拉到前台，
    /// 用户只是想看一眼版本号，界面却把他手上的事打断了，还要等最多十秒。
    ///
    /// 但「不自动查」不等于可以乱说：`PermissionState` 只有四档，直接拿 `.unknown` 去渲染，
    /// 这一行会写成「检查未通过」——一句**没查就下的结论**。所以这一行必须自己说「还没检查」，
    /// 并把下一步（点「重新检查」）给出来。
    func testThePermissionRowSaysItHasNotCheckedYetInsteadOfClaimingTheCheckFailed() throws {
        let spy = PreflightSpy(BridgeReadiness(ok: true, messages: ["环境就绪"]))
        let model = makeModel(preflight: spy)

        XCTAssertEqual(spy.calls, 0,
                       "打开关于页就跑了 preflight。那一下会把 ChatGPT 拉到前台并等最多十秒，"
                           + "而用户只是点开了「关于」。下一步：把检查留给「重新检查」那颗按钮。")

        let permission = try row("permission", of: model)
        XCTAssertTrue(permission.value.contains("还没检查"),
                      "还没查过，这一行却写着「\(permission.value)」。"
                          + "下一步：没查过时这一行要自己说「还没检查」，不要拿 `.unknown` 去渲染。")
        XCTAssertFalse(permission.value.contains("检查未通过"),
                       "一次都没查就说「检查未通过」，这是没查就下的结论。")
        XCTAssertTrue(permission.hint.contains("下一步") && permission.hint.contains("重新检查"),
                      "没告诉用户怎么才能查一次：\(permission.hint)")
    }

    /// 「重新检查」必须真的再跑一次 preflight，并把结论换到这一行上。
    func testRecheckRunsThePreflightAgainAndPutsItsConclusionOnThePage() async throws {
        let spy = PreflightSpy(BridgeReadiness(ok: false, messages: [
            "没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能…"
        ]))
        let model = makeModel(preflight: spy)

        await model.recheck()

        XCTAssertEqual(spy.calls, 1, "点了「重新检查」却没真的再查一次")
        XCTAssertEqual(model.permission, .needsAccessibility,
                       "查出来的结论没被记下来，这一页显示的还是「还没检查」")
        let permission = try row("permission", of: model)
        XCTAssertEqual(permission.value, "未授权（半自动模式）",
                       "查完了，这一行却还写着「\(permission.value)」")
    }

    /// `.unknown` 那一行的 hint 原话是「点「重新检查」看原始消息」。
    /// 那么检查结果原文就必须真的显示在这一页上，否则那句「下一步」指向空气。
    func testTheRawPreflightMessagesAreKeptBecauseTheHintPromisesThem() async {
        let spy = PreflightSpy(BridgeReadiness(ok: false, messages: ["某种没见过的失败：errno 42"]))
        let model = makeModel(preflight: spy)

        await model.recheck()

        XCTAssertEqual(model.permissionMessages, ["某种没见过的失败：errno 42"],
                       "检查结果原文被丢了。而「\(PermissionState.unknown)」那一行的下一步写的是"
                           + "「点「重新检查」看原始消息」——原文不留下来，那句话就指向空气。")
    }

    // MARK: - 二、读不到 state.json 时，这一页不能变成一片空白，也不能替它说好话

    /// 计划的验收表：读 `state.json` 失败时**不能空白**，要显示中文错误全文 + 数据目录路径 +
    /// 「重试」按钮；**其余各行（版本、签名、权限）仍要正常显示**——读不到训练数据不影响它们。
    func testAnUnreadableStateFileStillLeavesEveryOtherRowIntact() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)
        let model = makeModel()

        let error = try XCTUnwrap(model.loadError, "读不出训练数据却一声不吭（铁律 7）")
        XCTAssertTrue(error.contains("下一步"), "错误信息没说下一步做什么：\(error)")
        XCTAssertTrue(error.contains(directory.stateFile.path) || error.contains(directory.root.path),
                      "错误信息里没有出事的那个文件的路径，用户不知道去哪儿看：\(error)")

        for id in ["version", "bundle", "signature", "permission", "dataDirectory"] {
            let line = try row(id, of: model)
            XCTAssertFalse(line.value.isEmpty,
                           "读不到训练数据不影响「\(id)」这一行，它却空了——"
                               + "而这一页正是用户在出问题时才会打开的那一页。")
        }
        XCTAssertEqual(try row("version", of: model).value, "1.2.3（构建 42）")
    }

    /// **读不到就不许替它说「没有发现问题」。**
    ///
    /// 可搬迁检查的输入是 `state.json`。读不到时若照常把空清单交给 `AboutViewModel.rows`，
    /// 这一行会显示「没有发现问题」——一句凭空的保证，而用户正准备照着它换电脑。
    func testThePortabilityRowDoesNotClaimEverythingIsFineWhenItCouldNotRead() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)
        let model = makeModel()

        let portability = try row("portability", of: model)
        XCTAssertFalse(portability.value.contains("没有发现问题"),
                       "训练数据根本没读出来，这一行却保证「没有发现问题」。"
                           + "用户会照着这句话把数据目录拷去另一台电脑。")
        XCTAssertTrue(portability.hint.contains("下一步"),
                      "查不成也要说清下一步：\(portability.hint)")
    }

    /// 「重试」按钮：文件修好之后再读一次，错误必须消失、内容必须回来。
    /// 只显示错误不给出路，用户只能关掉窗口重开 App。
    func testRetryReadsTheFileAgainAndClearsTheErrorOnceItIsFixed() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)
        let model = makeModel()
        XCTAssertNotNil(model.loadError)

        try FileManager.default.removeItem(at: directory.stateFile)
        model.reload()

        XCTAssertNil(model.loadError, "文件已经修好了，错误却还挂着：\(model.loadError ?? "")")
        XCTAssertTrue(try row("portability", of: model).value.contains("没有发现问题"),
                      "重试之后可搬迁检查没有跟着重跑")
    }

    /// 「重新检查」除了查环境，还要**重跑一遍可搬迁审计**（计划验收表的原话）。
    /// 只查环境不重读磁盘的话，用户按了半天，那一行显示的还是打开窗口那一刻的旧结论。
    func testRecheckAlsoReRunsThePortabilityAuditAgainstTheDiskAsItIsNow() async throws {
        let model = makeModel()
        XCTAssertTrue(try row("portability", of: model).value.contains("没有发现问题"))

        try writeSessionWithAnAbsoluteReportPath()
        await model.recheck()

        let portability = try row("portability", of: model)
        XCTAssertTrue(portability.value.contains("1"),
                      "磁盘上已经有一处绝对路径了，这一行还是「\(portability.value)」——"
                          + "「重新检查」没有重跑可搬迁审计。")
        XCTAssertTrue(portability.hint.contains("sessions[0].reportPath"),
                      "没说是哪一处出的问题：\(portability.hint)")
    }

    // MARK: - 三、复制诊断信息：写进剪贴板、给出反馈、不许把读不到的东西说成 0

    func testCopyingDiagnosticsWritesTheReportAndSaysItIsCopied() throws {
        let board = PasteboardSpy()
        let model = makeModel(pasteboard: board)

        model.copyDiagnostics()

        let copied = try XCTUnwrap(board.written, "点了「复制诊断信息」，剪贴板一个字都没收到")
        XCTAssertTrue(copied.contains("1.2.3（构建 42）"), "诊断里没有版本：\(copied)")
        XCTAssertTrue(copied.contains(directory.root.path), "诊断里没有数据目录：\(copied)")
        let notice = try XCTUnwrap(model.notice,
                                   "复制成功却什么都不说，用户不知道点没点上（计划验收表要求「即时反馈」）")
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("已复制"), "反馈里没说复制好了：\(notice.text)")
    }

    /// 写剪贴板会失败（`NSPasteboard.setString` 返回 false）。失败不说话就是静默失败：
    /// 用户去粘贴，粘出来的是上一次复制的东西。
    func testCopyingDiagnosticsFailureSaysWhatHappenedAndWhatToDoNext() throws {
        let board = PasteboardSpy()
        board.succeeds = false
        let model = makeModel(pasteboard: board)

        model.copyDiagnostics()

        let notice = try XCTUnwrap(model.notice, "写剪贴板失败了却一声不吭（铁律 7）")
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("下一步"), "没说下一步怎么办：\(notice.text)")
    }

    /// **诊断信息里不许出现凭空的 0。**
    ///
    /// `DiagnosticsReport` 收的是一份 `CoachState`。读盘失败时若拿 `.empty()` 顶上，
    /// 那段文字会写着「题库 0 题 · 练习记录 0 次」，而收到这段文字的人（多半是开发者）
    /// 会照着它去找一个根本不存在的方向。同理，环境还没查过时那一行也不是结论。
    func testTheCopiedDiagnosticsAdmitWhatItCouldNotRead() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)
        let board = PasteboardSpy()
        let model = makeModel(pasteboard: board)

        model.copyDiagnostics()
        let copied = try XCTUnwrap(board.written)

        XCTAssertTrue(copied.contains("读不到训练数据"),
                      "读盘失败了，诊断文本却只字未提，里面那行「数据量：题库 0 题…」"
                          + "会被当成真实数字：\(copied)")
        XCTAssertTrue(copied.contains("还没") && copied.contains("重新检查"),
                      "环境一次都没查过，诊断里那行「辅助功能」却当成结论发了出去：\(copied)")
    }

    /// **这一段文字里不许出现两句互相矛盾的话。**
    ///
    /// 关于页刻意不自动检查环境（检查要把 ChatGPT 拉到前台，会打断用户手上的事），
    /// 所以「一条检查输出都没有」恰恰是这一页**没被点过「重新检查」时的正常状态**。
    /// 把它写成「这本身就不正常，请一并说明」，再在同一段话的末尾补一句
    /// 「打开关于页不会自动检查，所以那一行不是结论」，等于把两句打架的话一起
    /// 发给了收这段文字的人——他不知道该信哪一句，而这段文字存在的全部意义就是被转发。
    ///
    /// 2026-08-08 复审实测：改之前这两句真的一起出现在剪贴板里。
    func testTheDiagnosticsCallAnUncheckedEnvironmentUncheckedInsteadOfAbnormal() throws {
        let board = PasteboardSpy()
        let model = makeModel(pasteboard: board)
        XCTAssertNil(model.permission,
                     "这条测试的前提是「这一页还没查过环境」。前提没了，它就在检查另一件事。")

        model.copyDiagnostics()
        let copied = try XCTUnwrap(board.written)

        XCTAssertFalse(copied.contains("不正常"),
                       "还没点过「重新检查」是关于页的正常状态，诊断里却说它「不正常」。"
                           + "收到这段话的人会从一个假线索查起：\n\(copied)")
        XCTAssertTrue(copied.contains("还没查过"),
                      "没说清环境检查压根还没跑过，那几行「辅助功能」会被当成结论：\n\(copied)")
    }

    /// 查过之后，检查结果原文要跟着诊断一起发出去——
    /// `.unknown` 那一行的原话是「用「复制诊断信息」把它整段发出来」。
    func testTheCopiedDiagnosticsCarryTheRawCheckMessagesOnceThereAreAny() async throws {
        let board = PasteboardSpy()
        let model = makeModel(preflight: PreflightSpy(
            BridgeReadiness(ok: false, messages: ["某种没见过的失败：errno 42"])),
                              pasteboard: board)

        await model.recheck()
        model.copyDiagnostics()

        let copied = try XCTUnwrap(board.written)
        XCTAssertTrue(copied.contains("errno 42"),
                      "检查结果原文没跟着发出去，而那一行的下一步正是「用「复制诊断信息」"
                          + "把它整段发出来」：\(copied)")
        XCTAssertFalse(copied.contains("还没查过"),
                      "已经查完了，诊断里还写着「还没查过」——上面那几行结论会被当成没效："
                          + "\n\(copied)")
    }

    // MARK: - 四、在访达中显示：先把目录建出来，建不出来要说话

    func testRevealingTheDataDirectoryCreatesItFirstSoFinderHasSomethingToOpen() throws {
        let finder = FinderSpy()
        let model = makeModel(finder: finder)
        // 全新安装、还没练过一场时，这个目录可能压根不存在。
        try FileManager.default.removeItem(at: directory.root)

        model.revealDataDirectory()

        XCTAssertEqual(finder.asked, directory.root, "交给访达的不是数据目录本身")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.root.path),
                      "目录不存在时没有先建出来，访达打开的会是一个不存在的位置")
        let notice = try XCTUnwrap(model.notice, "点了按钮却什么反馈都没有")
        XCTAssertFalse(notice.isFailure, "该成功的一次被报成了失败：\(notice.text)")
    }

    /// 目录建不出来（位置被一个同名文件占了、盘满、只读卷）时**必须说话**。
    /// `try?` 吞掉失败再说一句「已打开」，正是铁律 7 点名禁止的那种事。
    func testRevealingSaysSoWhenTheDirectoryCannotBeOpenedInsteadOfPretending() throws {
        let blocked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-about-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let model = makeModel(directory: DataDirectory(root: blocked))
        model.revealDataDirectory()

        let notice = try XCTUnwrap(model.notice, "打不开却一声不吭（铁律 7）")
        XCTAssertTrue(notice.isFailure, "明明没打开，却给了一句成功提示：\(notice.text)")
        XCTAssertTrue(notice.text.contains(blocked.path), "没说是哪个位置打不开：\(notice.text)")
        XCTAssertTrue(notice.text.contains("下一步"), "没说下一步怎么办：\(notice.text)")
    }

    // MARK: - 五、菜单与窗口的接线（扫源码）

    /// 关于页在苹果菜单里，不在侧边栏（侧边栏固定十项，Phase 3 的
    /// `testSidebarHasAllTenItems` 守着）。这条守的是「菜单项真的指向这个窗口」——
    /// 少了任何一环，苹果菜单里的「关于」还是系统默认那个小面板，这一页永远打不开。
    func testTheAppleMenuItemOpensTheAboutWindowThatIsActuallyRegistered() throws {
        let code = try SourceGuard.repositoryCode(SourceGuard.appSceneRelativePath)

        let commands = try SourceGuard.memberBody(of: "CommandGroup(replacing: .appInfo)", in: code)
        XCTAssertTrue(
            commands.contains("AboutMenuButton()"),
            "苹果菜单的「关于 …」没有换成本应用自己的那一项，点开的会是系统默认的小面板："
                + "版本、签名、数据目录、可搬迁检查一样都看不到。"
                + "下一步：`CommandGroup(replacing: .appInfo) { AboutMenuButton() }`。")

        XCTAssertTrue(
            code.contains("id: AboutWindow.id"),
            "App 里没有注册 id 为 `AboutWindow.id` 的窗口，菜单项按下去会没有任何反应"
                + "（`openWindow(id:)` 找不到窗口时只在控制台抱怨一句，界面上一点动静都没有）。"
                + "下一步：加一个 `Window(\"关于 …\", id: AboutWindow.id) { AboutView() }` 场景。")
        XCTAssertGreaterThan(
            SourceGuard.occurrences(of: "AboutView()", in: code), 0,
            "关于窗口里没有 `AboutView()`，打开的是一个空窗口。")

        // 计划 Step 1 给的那段完整代码用的是 `WindowGroup` 且没有 `Settings` 场景，
        // 照抄会同时打破 `AppSceneTests` 那两条。这里再钉一遍，免得下次有人照抄。
        XCTAssertFalse(code.contains("WindowGroup"),
                       "主窗口被改回了 `WindowGroup`（⌘N 会带回第二份 `AppState`），"
                           + "详见 `AppSceneTests` 里那条测试的说明。")
        XCTAssertTrue(code.contains("Settings {"),
                      "⌘, 那个设置场景被删掉了：录音开关、麦克风引导、磁盘占用整页消失。")
    }

    func testTheMenuButtonReallyOpensThatWindow() throws {
        let button = try SourceGuard.memberBody(of: "public struct AboutMenuButton",
                                                in: try SourceGuard.code(Self.view))
        XCTAssertTrue(
            button.contains("openWindow(id: AboutWindow.id)"),
            "菜单项没有接到 `openWindow(id: AboutWindow.id)` 上——按下去什么都不会发生，"
                + "而且不会有任何编译错误（铁律 7）。下一步：把它接回去。")
    }

    // MARK: - 六、这一页画出来的东西（扫源码）

    /// 六行事实都得逐行画出来：标签、内容、补充说明一样都不能少。
    /// 只画 `label` 不画 `value`，这一页就成了一张只有抬头的表。
    func testEveryRowIsPaintedWithItsLabelValueAndHint() throws {
        let line = try SourceGuard.memberBody(of: "private func rowLine",
                                              in: try SourceGuard.code(Self.view))
        for piece in ["row.label", "row.value", "row.hint"] {
            XCTAssertTrue(
                line.contains(piece),
                "每一行里不再画 `\(piece)` 了。`AboutViewModel` 把六行都算好了却不上屏，"
                    + "等于静默失败（铁律 7），而且不会有任何编译错误。下一步：把它画回去。")
        }
        XCTAssertTrue(
            line.contains("hint.isEmpty"),
            "没有判 `hint` 是不是空的。空 hint 会画出一行空白，"
                + "用户会以为那儿本该有话却没显示出来（计划验收表：hint 为空时不显示空行）。")

        SourceGuard.assertRenders(
            "rowLine", inBodyOf: "private var factsCard", of: Self.view, atLeast: 1,
            because: "六行事实没有被摆进卡片里，这一页最主要的内容一个字都不上屏。")
        SourceGuard.assertRenders(
            "model.rows", inBodyOf: "private var factsCard", of: Self.view,
            because: "这一页不再遍历 `model.rows` 了，画出来的将是一张固定的死表。")

        let body = try aboutViewBody()
        for member in ["factsCard", "actions"] {
            XCTAssertTrue(body.contains(member),
                          "`\(member)` 只是声明着，没有被摆进 `AboutView.body`，"
                              + "一个像素都不会上屏（本项目已实测过四次这种退化，全套测试照样绿）。")
        }
    }

    /// 顶上那行版本必须来自 `AppMetadata`，不许写死。
    /// 写死的版本号在每一次发版之后都是错的，而且错得毫无迹象。
    func testTheVersionHeaderComesFromAppMetadataAndIsNotHardCoded() throws {
        let code = try SourceGuard.code(Self.view)
        let header = try SourceGuard.memberBody(of: "private var header", in: code)
        XCTAssertTrue(header.contains("metadata.versionLine"),
                      "顶部那行版本不再取自 `AppMetadata.versionLine` 了：\(header.flattened)")
        XCTAssertTrue(header.contains("metadata.displayName"),
                      "顶部没有 App 名称：\(header.flattened)")
        for hardCoded in ["1.0.0", "1.2.3"] {
            XCTAssertFalse(code.contains(hardCoded),
                           "这一页里写死了版本号「\(hardCoded)」。下一版发出去它就是错的，"
                               + "而且不会有任何迹象。下一步：一律走 `AppMetadata`。")
        }
    }

    /// 三颗按钮：一颗都不能少，而且都得真的接上动作。
    /// 「重新检查」查的时候会被 `.disabled` 挡住（防止连点），所以它单独查。
    func testTheThreeActionsAreOnScreenAndActuallyWired() throws {
        let code = try SourceGuard.code(Self.view)
        let actions = try SourceGuard.memberBody(of: "private var actions", in: code)

        let always = SourceGuard.unconditionalButtons(in: actions)
        for title in ["\"在访达中显示\"", "\"复制诊断信息\""] {
            let button = always.first { $0.label.contains(title) }
            XCTAssertNotNil(button,
                            "这一页上没有一颗一定看得见的 \(title) 按钮"
                                + "（扫到的是：\(always.map(\.label))）。")
            XCTAssertTrue(button?.isWired ?? false,
                          "\(title) 是一颗空按钮：点下去什么都不发生，界面上看不出任何异样。")
        }

        XCTAssertTrue(actions.contains("Button(\"重新检查\")"),
                      "「重新检查」不见了。而这一页上到处都写着「下一步：点「重新检查」」"
                          + "（`AboutViewModel` 的三条 hint、`DiagnosticsReport` 里那一句），"
                          + "按钮没了，那几句话就全指向空气。")
        XCTAssertTrue(actions.contains("model.recheck()"),
                      "「重新检查」没接到 `model.recheck()` 上：\(actions.flattened)")
        XCTAssertTrue(actions.contains("model.revealDataDirectory()"),
                      "「在访达中显示」没接到 `model.revealDataDirectory()` 上")
        XCTAssertTrue(actions.contains("model.copyDiagnostics()"),
                      "「复制诊断信息」没接到 `model.copyDiagnostics()` 上")

        // 那十秒里界面必须一直在说话（DESIGN-SYSTEM 第 5 节：超过 300ms 就要有反馈）。
        XCTAssertTrue(actions.contains("model.isChecking"),
                      "查环境要启动 ChatGPT 并等它的界面醒过来（实测约九秒），"
                          + "而这段时间这一页一个字都不说，用户会以为按钮坏了。")
    }

    /// 按钮点完之后那一句反馈，必须把 `notice.text` 原样画出来。
    ///
    /// **模型层算得对不等于用户看得见**：`testCopyingDiagnosticsWritesTheReportAndSaysItIsCopied`
    /// 与 `testRevealingSaysSoWhenTheDirectoryCannotBeOpenedInsteadOfPretending`
    /// 断言的都是 `model.notice.text`，管不到这一句有没有上屏。
    /// 实测把 `Label(notice.text, …)` 换成 `Label("操作完成", …)`（`noticeLine` 仍可达、
    /// 仍被 `body` 调用），全套测试照样绿——而那时「复制诊断信息」成功后用户看到的是
    /// 一句无意义的「操作完成」，「在访达中显示」失败时那段带路径、带「下一步」的说明
    /// （铁律 7）一个字都不上屏。
    func testTheActionFeedbackIsPaintedWordForWordAndNotReplacedByACannedLine() throws {
        let code = try SourceGuard.code(Self.view)
        let notice = try SourceGuard.memberBody(of: "private func noticeLine", in: code)

        XCTAssertTrue(
            notice.contains("notice.text"),
            "这一句反馈不再画 `notice.text` 了：\(notice.flattened)。"
                + "模型层把话算好了却不上屏，等于静默失败（铁律 7），而且不会有任何编译错误——"
                + "「已复制」变成一句写死的空话，「在访达中显示」失败时那段带路径、"
                + "带「下一步」的说明整段消失。下一步：把 `notice.text` 画回去。")

        XCTAssertTrue(
            try aboutViewBody().contains("noticeLine"),
            "`noticeLine` 只是声明着，没有被摆进 `AboutView.body`——"
                + "那三颗按钮点下去将一句反馈都没有，用户分不清「成功了」和「点了没反应」。")
    }

    /// 检查结果原文必须逐条画出来。
    ///
    /// `AboutViewModel.permissionHint(.unknown)` 的原话是「下一步：点「重新检查」看原始消息」，
    /// 这一块就是那句话指的地方。已有的
    /// `testTheRawPreflightMessagesAreKeptBecauseTheHintPromisesThem` 只管到
    /// `model` 有没有把消息留住；实测把整段 `ForEach` 换成一句写死的话，全套测试照样绿，
    /// 而那条「下一步」就指向空气了。
    func testTheRawCheckMessagesAreActuallyPaintedOneByOne() throws {
        let code = try SourceGuard.code(Self.view)
        let output = try SourceGuard.memberBody(of: "private var checkOutputCard", in: code)

        XCTAssertTrue(
            output.contains("model.permissionMessages"),
            "「检查结果原文」那一块不再读 `model.permissionMessages` 了：\(output.flattened)。"
                + "而「\(PermissionState.unknown)」那一行的下一步写的是"
                + "「点「重新检查」看原始消息」——原文不画出来，那句话就指向空气。")
        XCTAssertTrue(
            output.contains("Text(message)"),
            "遍历到了消息却没把每一条画成一行文字：\(output.flattened)。"
                + "下一步：逐条 `Text(message)` 画出来，别用一句概括替掉原文。")

        XCTAssertTrue(
            try aboutViewBody().contains("checkOutputCard"),
            "`checkOutputCard` 只是声明着，没有被摆进 `AboutView.body`，"
                + "查出来的原始消息一个字都不会上屏。")
    }

    /// 读盘失败那一块：错误全文 + 数据目录路径 + 一颗能点的「重试」。
    func testTheLoadErrorBlockShowsTheWholeMessageThePathAndAWayOut() throws {
        let code = try SourceGuard.code(Self.view)
        let block = try SourceGuard.memberBody(of: "private func loadErrorCard", in: code)

        XCTAssertTrue(block.contains("message"),
                      "读盘失败那一块不再显示错误原文了，用户看到的是一片空白：\(block.flattened)")
        XCTAssertTrue(block.contains("dataDirectoryPath") || block.contains("directory.root.path"),
                      "没有把数据目录的路径写出来，用户不知道去哪儿找那个文件：\(block.flattened)")

        let exits = SourceGuard.unconditionalButtons(in: block).filter(\.isWired)
        XCTAssertFalse(exits.isEmpty,
                       "读盘失败那一块里没有一颗能点的按钮（扫到的是："
                           + "\(SourceGuard.unconditionalButtons(in: block).map(\.label))）。"
                           + "只报错不给出路，用户只能关掉窗口重开一次 App。"
                           + "下一步：把「重试」按钮加回去，并接上 `model.reload()`。")
        XCTAssertTrue(block.contains("model.reload()"),
                      "「重试」没接到 `model.reload()` 上，点了不会重读磁盘")

        XCTAssertTrue(
            try aboutViewBody().contains("loadErrorCard"),
            "读盘失败那一块只是声明着，没有被摆进 `AboutView.body`——"
                + "读不出训练数据时这一页上不会有任何提示，用户看到的是一张少了半截的表。")
    }

    /// 致谢与许可：都得逐条画出来，许可全文还要能选中复制。
    ///
    /// **许可这一段不是装饰**：工程里有逐字沿用自上游（MIT）的文本，
    /// MIT 唯一的条件就是把那份声明的原文随副本一起交付，而交出去的是 `.app`——
    /// 里面没有源码树，这一页的许可区就是那份原文唯一的容身之处。
    func testTheAcknowledgementsAndTheLicenseAreActuallyPainted() throws {
        let code = try SourceGuard.code(Self.view)

        let credits = try SourceGuard.memberBody(of: "private var acknowledgementsSection", in: code)
        XCTAssertTrue(credits.contains("AboutViewModel.acknowledgements"),
                      "致谢区不再读 `AboutViewModel.acknowledgements` 了")
        for piece in ["item.name", "item.role", "item.license"] {
            XCTAssertTrue(credits.contains(piece),
                          "致谢里不画 `\(piece)` 了。只写名字等于没致谢，"
                              + "少了 license 那一条则连许可情况都看不到。")
        }
        XCTAssertTrue(credits.contains("item.url.isEmpty"),
                      "没有判 `url` 是不是空的：SF Pro 和「第三方依赖」两条本来就没有链接，"
                          + "照画会出现一个点不开的空链接。")

        let license = try SourceGuard.memberBody(of: "private var licenseSection", in: code)
        XCTAssertTrue(license.contains("AboutViewModel.licenseNotice"),
                      "许可区不再显示 `licenseNotice` 全文了。工程里有逐字沿用自上游（MIT）的文本，"
                          + "而 MIT 的条件就是把那份声明的原文随副本一起交付——"
                          + "交出去的是 `.app`，这一页就是那份原文唯一的容身之处。")
        XCTAssertTrue(license.contains("textSelection(.enabled)"),
                      "许可全文选不中也就复制不走（计划验收表：可选中复制）")

        let body = try aboutViewBody()
        for member in ["acknowledgementsSection", "licenseSection"] {
            XCTAssertTrue(body.contains(member),
                          "`\(member)` 只是声明着，没有被摆进 `AboutView.body`，一个像素都不会上屏。")
        }
    }

    /// 图标只用 SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节：
    /// emoji 在不同系统版本渲染不一致，也不会跟着语义颜色走）。
    func testTheAboutPageUsesSFSymbolsAndNoEmoji() throws {
        let raw = try SourceGuard.read(Self.view)
        XCTAssertGreaterThan(SourceGuard.occurrences(of: "Image(systemName:", in: raw)
                                + SourceGuard.occurrences(of: "systemImage:", in: raw), 0,
                             "这一页一个 SF Symbol 都没有，多半是图标被换成了别的东西")

        let emoji = raw.unicodeScalars.filter { scalar in
            (0x1F300...0x1FAFF).contains(scalar.value) || (0x2600...0x27BF).contains(scalar.value)
        }
        XCTAssertTrue(emoji.isEmpty,
                      "这一页里出现了 emoji（\(String(String.UnicodeScalarView(emoji)))）。"
                          + "下一步：换成 SF Symbols（`Image(systemName:)`）。")

        // 样式全部走设计令牌（铁律 8）。全模块那一趟（`DesignTokenSweepTests`）也扫得到这一页，
        // 这里再点名一次，是为了这一页红的时候报错直接指到它。
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
