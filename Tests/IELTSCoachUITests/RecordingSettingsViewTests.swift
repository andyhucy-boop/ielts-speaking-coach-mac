import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 录音设置页（⌘,）上，几件**没法靠视图模型的断言守住、而错了就是在骗用户**的事。
///
/// ## 为什么这一页非补这组测试不可
///
/// `RecordingSettingsViewModel` 已经被 `RecordingSettingsViewModelTests` 逐条钉死了：
/// 权限没拿到时 `enabled` 必须是 false、权限事后被撤销时也必须回到 false、
/// 权限给回来才回到 true。那一半修得很干净。
///
/// **可决定屏幕上那颗开关显示什么的，是视图里的那一行 `get:`，而它此前一行测试都没管。**
/// 本轮实测三处突变，`swift test` **837 条全绿**：
///
/// - `RecordingSettingsView` 的 `get: { viewModel.enabled }` 改成 `get: { true }`
///   → 开关永远显示「开」，而一秒都不录。计划第 48 行的原话：
///   「权限没拿到时，界面上的开关**必须**停在「关」。**显示成「开」却什么都不录，
///   是本项目最不能接受的那种失败。**」
/// - 装着它的那一页（Phase 5 是 `RecordingSettingsScene`，Phase 10 Task 16 起是
///   `SettingsWindowView` 的「录音」分区）里，`RecordingSettingsView(viewModel: viewModel)`
///   换成 `EmptyView()` → 整格蒸发，⌘, 打开那一栏是空的。此前只有最外面那一环
///   （main.swift 里的 `Settings { … }`）被 `AppSceneTests` 守着。
/// - 删掉 `Text(viewModel.consentText)` 那五行 → 权限被撤销之后，
///   页面上唯一解释「开关为什么自己关了」的那段话没了，用户只会以为是程序抽风。
///
/// 而且这一页是整个界面模块里**唯一**一个没有 `*ViewTests.swift` 的页面
/// （HistoryView / TodayView / QuestionBankView / ReviewReportView / PermissionGateView /
/// PracticeSheet / PendingReviewInboxView / QuestionBankImportResultSheet 八个都有）。
///
/// ## 边界
///
/// 做法与 `PracticeSheetTests` 一致：扫源码，不画界面。拦得住「整段渲染被删」
/// 「接线被换掉」「文案指的控件不存在」；拦不住「代码还在但条件永远为假」，
/// 也不管排版好不好看——那部分归人工验收。
/// 读不到源码一律抛错（`SourceGuard` 从不返回空串），所以这组断言不会静静地空转。
final class RecordingSettingsViewTests: XCTestCase {

    private static let view = "Recording/RecordingSettingsView.swift"
    /// 装着这一页的那一格。Phase 10 Task 16 起是统一设置窗口的「录音」分区
    /// （从前是 `Recording/RecordingSettingsScene.swift`，那个文件已随合并删掉——
    /// 留着它就是同一页的第二份入口）。
    private static let host = "Settings/SettingsWindowView.swift"

    // MARK: - 一、开关显示什么，只能由视图模型说了算

    /// **这是这一页最要紧的一条。**
    ///
    /// 「这一刻到底录不录」的判断只有一处（`RecordingSettingsViewModel.enabled`：
    /// 磁盘上记着同意 **且** 麦克风权限还在手里）。屏幕上那颗开关必须原样照搬它，
    /// 中间不许有第二个取值——`get: { true }`、`get: { viewModel.consentAt.isEmpty == false }`、
    /// 或者视图自己另存一份 `@State`，三种写法都会让界面显示「开」而实际一秒不录。
    ///
    /// 实测：`get: { viewModel.enabled }` 改成 `get: { true }`，837 条全绿。
    ///
    /// 扫的是 `get:` / `set:` 各自那对大括号里的内容，不是整段 `toggle`：
    /// 只问「这一段里出现过 `viewModel.enabled` 吗」的话，把取值挪进 `set:`（或留在
    /// `.disabled(...)` 里）照样扫得到，而屏幕上那颗开关已经在撒谎了。
    func testTheSwitchOnScreenReadsItsValueFromTheViewModelAndNowhereElse() throws {
        let toggle = try SourceGuard.memberBody(of: "private var toggle",
                                                in: try SourceGuard.code(Self.view))

        let getter = try SourceGuard.memberBody(of: "get:", in: toggle)
        XCTAssertTrue(
            getter.contains("viewModel.enabled"),
            "开关的 `get:` 不再读 `viewModel.enabled` 了（现在读的是：\(getter.trimmed)）。"
                + "视图模型那边把「有同意 **且** 有权限」算得再对，屏幕上这颗开关也可以显示成别的样子——"
                + "而「显示成「开」却什么都不录」是本项目最不能接受的那种失败："
                + "用户练完一场回去点开回听，才发现什么都没有，而界面从头到尾都在告诉他录着呢。"
                + "下一步：`get:` 里只写 `viewModel.enabled`，判断留在视图模型里，这里不许再算一遍。")

        let setter = try SourceGuard.memberBody(of: "set:", in: toggle)
        XCTAssertTrue(
            setter.contains("viewModel.setEnabled("),
            "开关的 `set:` 没有接到 `viewModel.setEnabled(_:)` 上（现在写的是：\(setter.trimmed)）。"
                + "拨了开关什么都不会发生，也不会有任何编译错误——界面上看不出任何异样（铁律 5）。"
                + "下一步：把它接回去；换了别的方法名就同步改这条测试。")
    }

    /// 同一件事的另一条溜法：**视图自己再存一份状态。**
    ///
    /// 视图里多一个 `@State private var isOn` 并让开关读它，上面那条就绕过去了
    /// （`get:` 里仍然可以写一句 `viewModel.enabled` 去初始化它），
    /// 而屏幕上显示的从此是那份副本——权限在系统设置里被关掉之后它不会跟着变。
    /// 这一页的类型注释第 1 条写的就是这件事。
    ///
    /// 所以这里钉住数量：这一页**只该有一份** `@State`（`actionNotice`，
    /// 两颗按钮点失败时的反馈）。多出来的那份得先说清它凭什么存在。
    func testThisPageKeepsNoSecondCopyOfTheOnOffState() throws {
        let code = try SourceGuard.code(Self.view)
        XCTAssertEqual(
            SourceGuard.occurrences(of: "@State", in: code), 1,
            "这一页的 `@State` 不止一个了。它原本只该有一份（`actionNotice`：两颗按钮点失败时的反馈）。"
                + "多出来的那份若存着开关的开/关，界面显示的就不再是"
                + "「这一刻到底录不录」——用户事后在系统设置里关掉麦克风，这颗开关不会跟着回到「关」，"
                + "于是页面一直显示「开」而练习一秒都不录。"
                + "下一步：开关的取值一律走 `viewModel.enabled`；"
                + "真有别的东西非用 `@State` 不可（不换屏的局部反馈），连理由一起改这条断言。")
    }

    // MARK: - 二、这一页真的被摆进设置窗口了吗

    /// `AppSceneTests` 守的是 main.swift 里 `Settings { … }` 那一环，
    /// 再往里一层此前没人管：实测把 `RecordingSettingsView(viewModel: viewModel)` 换成
    /// `EmptyView()`，837 条全绿——⌘, 打开是一个空窗口，开关、权限引导、磁盘占用全没了。
    ///
    /// `onAppear` 里那次 `refresh()` 同样是这一条的一部分，而且守的正是本页头号缺陷：
    /// 用户在系统设置里撤掉麦克风权限之后，**只有重读一遍权限状态**，
    /// 这颗开关才会从「开」回到「关」。删掉它，页面会一直照着上次的结果显示「开」。
    func testTheSettingsWindowActuallyPutsThisPageOnScreenAndRereadsTheDisk() throws {
        let body = try SourceGuard.memberBody(of: "private var recordingSection",
                                              in: try SourceGuard.code(Self.host))

        XCTAssertTrue(
            body.contains("RecordingSettingsView(viewModel:"),
            "设置窗口「录音」那一格里没有 `RecordingSettingsView(viewModel: …)`，整页一个像素都不上屏："
                + "⌘, 打开那一栏是空的，录音开关、麦克风权限引导、磁盘占用提示全都没了，"
                + "而这不会有任何编译错误。"
                + "下一步：把它摆回那一格；换了别的初始化写法就同步改这条测试。")

        XCTAssertTrue(
            body.contains("recording.refresh()"),
            "打开这一页时不再 `refresh()` 了。后果有两件，第二件是这一页最要命的："
                + "磁盘占用会停在打开 App 那一刻的数字；"
                + "**而麦克风权限是否还在手里也不会重读**——用户在系统设置里把麦克风关掉之后，"
                + "这颗开关会一直显示「开」而练习一秒都不录。"
                + "下一步：把 `.onAppear { recording.refresh() }` 加回那一格。")
    }

    // MARK: - 三、视图模型算给用户看的每一句话，都得真的上屏

    /// 算出来了却不上屏，就是静默失败（铁律 5）。这一页有五处这样的取值，
    /// 每一处都各自守着一件说不清就会让用户误判的事。
    ///
    /// 实测：把 `Text(viewModel.consentText)` 那五行整段删掉，837 条全绿。
    /// 而权限被撤销之后，**那段话是页面上唯一解释「开关为什么自己关了」的东西**——
    /// 没有它，用户看到的就是一个自己跳回「关」的开关，只会以为程序坏了。
    ///
    /// 扫的是各自那一段的大括号内，不是全文：`consentText` / `notice` 这些词在这份源码的
    /// 别处（`viewModel` 的声明、注释被剥掉后剩下的调用）还可能出现，扫全文的话，
    /// 把真正画出来的那一行删掉照样绿。
    func testEverySentenceTheViewModelComputesForTheUserIsActuallyPainted() throws {
        let painted: [(value: String, section: String, what: String)] = [
            ("viewModel.consentText", "private var recordingSection",
             "权限被事后撤销时，页面上唯一一句解释「你在某年某月同意过，但权限现在不在本应用手里，"
                + "所以开关停在「关」」的话。没有它，用户只会以为开关自己抽风"),
            ("viewModel.notice", "private var recordingSection",
             "刚拨完开关那句反馈：开成功了没有、没开成是因为什么、设置有没有真的存进磁盘。"
                + "没有它，保存失败会变成一次彻底的静默失败"),
            ("viewModel.permission.guidance", "private var systemSettingsCard",
             "权限不在本应用手里时那条出路说明（去哪儿开、开完回来做什么）"),
            ("viewModel.usage.summaryText", "private var usageSection",
             "录音一共占了多少地方——这一页第 2 节的全部内容"),
            ("viewModel.orphanNotice", "private var usageSection",
             "磁盘上有、但没有任何训练记录指向的录音（多半是练习中途出错留下的）。"
                + "不显示的话，这些文件会一直悄悄占着地方，没人知道它们存在")
        ]

        for piece in painted {
            SourceGuard.assertRenders(
                piece.value, inBodyOf: piece.section, of: Self.view,
                because: "`\(piece.section)` 里不再读 `\(piece.value)` 了。界面上少的是：\(piece.what)。"
                    + "视图模型把它算出来了却不上屏，等于静默失败（铁律 5），"
                    + "而且不会有任何编译错误。下一步：把这一段画回去。")
        }
    }

    /// 权限被拒 / 被限制时那条能点的出路。
    ///
    /// macOS 一个 App 一辈子只为麦克风弹一次系统对话框，拒过之后再拨开关什么都不会发生——
    /// 没有这颗「打开系统设置」，用户就只能对着一个永远不出现的弹窗干等（铁律 5：禁止无限等待）。
    /// 这一页的类型注释第 2 条写的就是它。
    func testThePermissionDeadEndAlwaysHasAWayOut() throws {
        let code = try SourceGuard.code(Self.view)

        // 那颗按钮无条件画在卡片里、且真的接了动作。
        let card = try SourceGuard.memberBody(of: "private var systemSettingsCard", in: code)
        let exits = SourceGuard.unconditionalButtons(in: card).filter(\.isWired)
        XCTAssertFalse(
            exits.isEmpty,
            "权限被拒那张卡片里没有一颗「一定看得见、按得动、按下去真的会发生事情」的按钮"
                + "（扫到的：\(SourceGuard.unconditionalButtons(in: card).map(\.label))）。"
                + "macOS 拒过一次之后不会再弹第二次对话框，拨开关也不会有任何反应——"
                + "用户会对着一个永远不出现的弹窗干等。"
                + "下一步：把「打开系统设置」那颗按钮加回去，并接上 `openSystemSettings()`。")

        // 卡片得真的被摆进页面，而且是在权限被拒 / 被限制时才摆。
        SourceGuard.assertRenders(
            "systemSettingsCard", inBodyOf: "private var recordingSection", of: Self.view,
            because: "`systemSettingsCard` 只是声明着，没有被摆进 `recordingSection`——"
                + "权限被拒之后，页面上就没有任何一条能点的出路了。"
                + "下一步：把 `if needsSystemSettings { systemSettingsCard }` 放回去。")

        for state in ["denied", "restricted"] {
            SourceGuard.assertRenders(
                state, inBodyOf: "private var needsSystemSettings", of: Self.view,
                because: "`needsSystemSettings` 不再把 `.\(state)` 算成「需要去系统设置」了，"
                    + "那种状态下用户看不到那颗「打开系统设置」，也就没有出路。"
                    + "下一步：把这个状态加回判断里"
                    + "（`.restricted` 也要留着：用户至少能在那一栏里看到是谁把它锁上的）。")
        }

        // 两颗按钮点失败时必须说话，不许「点了没反应」。
        //
        // **扫的是 `guard … else { }` 里那一段，不是整个函数。** 两个函数的成功路径末尾
        // 都有一句 `actionNotice = nil`，扫整个函数的话，把失败分支那句赋值改掉
        // （例如换成 `_ =`）照样扫得到 `actionNotice =`——本轮实测这么改，845 条全绿。
        for (function, failureBranch, what) in [
            ("private func openSystemSettings", "guard let url", "打开系统设置"),
            ("private func openRecordingsFolder", "guard revealFolder", "打开录音文件夹")
        ] {
            let body = try SourceGuard.memberBody(of: function, in: code)
            let failurePath = try SourceGuard.memberBody(of: failureBranch, in: body)
            XCTAssertTrue(
                failurePath.contains("actionNotice ="),
                "「\(what)」这颗按钮**失败**时不再给用户任何反馈了（那一段现在是：\(failurePath.trimmed)）。"
                    + "`NSWorkspace` 那两下都可能失败（系统不认这个设置页链接、文件夹还没建出来），"
                    + "而返回值丢掉不会有任何编译警告——用户看到的就是一颗点了没反应的按钮（铁律 5）。"
                    + "下一步：在这个 `guard … else` 里写一句 `actionNotice`，"
                    + "说清发生了什么和下一步怎么做。")
        }
    }

    // MARK: - 四、文案指名让用户去拨的那个开关，屏幕上真有吗

    /// **这一条守的是 Phase 5 的第二个缺陷。**
    ///
    /// `MicrophonePermissionState.notDetermined.guidance` 原话是
    /// 「下一步：点「开启录音」，系统会弹出一个对话框」，而 **全 App 没有任何按钮或开关
    /// 叫「开启录音」**（`grep -rn "开启录音" Sources/` 只命中这句文案自己）。
    /// 屏幕上那颗开关叫「保存我的回答录音」。用户照着去找一颗不存在的开关，
    /// 比不给下一步还糟——他会一直找，然后以为是自己没看见。
    ///
    /// 本项目已经因为同一类问题修过一次（`ReviewParser` 那句「点「补生成复盘报告」」
    /// 是命令行时代的说法，`PracticeRunner.diagnosisOnly` 把它砍掉了）。这次踩上的是主场景。
    ///
    /// **开关标题是从视图源码里读出来的，不是写死在这条测试里的**：写死的话，
    /// 哪天有人把 `Toggle` 的标题改了，两边一起走岔而测试照样绿。
    func testTheMicrophoneGuidanceNamesTheSwitchThatIsActuallyOnThisPage() throws {
        let title = try Self.recordingSwitchTitle()

        // 先钉住读到的确实是一句人话，不是空串或一段代码——否则下面全是恒真。
        XCTAssertFalse(title.isEmpty)
        XCTAssertFalse(title.contains("\\("),
                       "开关标题变成了字符串插值（\(title)），扫源码就查不动了。"
                           + "下一步：标题保持字面量；真要动态生成，这条守卫得换成运行期的断言。")

        // 这两种状态下，用户的下一步就是回到这一页拨那颗开关，所以必须点名它。
        for state: MicrophonePermissionState in [.notDetermined, .denied] {
            let guidance = state.guidance ?? ""
            XCTAssertTrue(
                guidance.contains(title),
                "`\(state)` 的说明没有点名屏幕上那颗开关「\(title)」，现在写的是：\(guidance)。"
                    + "用户读完这句话得知道去拨哪一个东西；名字对不上，他就得自己在页面上猜。"
                    + "下一步：把这句话里的控件名改成「\(title)」（与 `Toggle` 的标题一字不差），"
                    + "并且把去哪儿找它也说清（这几句话也会显示在练习中的 sheet 上，"
                    + "那时设置窗口根本没开）。")
            XCTAssertTrue(
                guidance.contains("录音设置") && guidance.contains("⌘,"),
                "`\(state)` 的说明没说去哪儿拨那颗开关，现在写的是：\(guidance)。"
                    + "这句话有一个出口是练习进行中那张 sheet（`RecordingConsent.readiness` 判 "
                    + "`.blocked` 时原样带过去），那时用户在练习界面上，设置窗口根本没开——"
                    + "只说「拨那个开关」等于没说。"
                    + "下一步：把「到「录音设置」（⌘,）」这一句加回去。")
        }

        // `restricted` 反过来：那种情况用户自己改不了，指着一个拨不动的开关同样是空指一步。
        XCTAssertFalse(
            (MicrophonePermissionState.restricted.guidance ?? "").contains(title),
            "`restricted` 的说明让用户去拨「\(title)」，可这台电脑的麦克风是被系统策略锁住的，"
                + "那颗开关拨了也不会有任何反应——这和指一颗不存在的按钮是同一种骗法。"
                + "下一步：这条的下一步只能是「找管理这台电脑的人解除限制」。")
    }

    /// 反过来的一趟：这几句话里**凡是指名让用户去点的东西，界面上都得真有**。
    ///
    /// 上一条问「有没有点名那颗开关」，这一条问「有没有点名一个根本不存在的东西」。
    /// 两条缺一不可：只有上一条的话，把原来那句「点「开启录音」」原样留着、
    /// 再补一句正确的，照样是绿的。
    ///
    /// 界面模块自己的文案由 `RenderReachabilitySweepTests` 扫；这几句话在 `IELTSCoachCore` 里，
    /// 不在那一趟的范围内——**而它们是这一页和练习 sheet 上都会原样显示的用户文案**，
    /// 缺口正在这里。
    func testNoMicrophoneGuidanceSendsTheUserAfterAControlThatDoesNotExist() throws {
        let controls = try SourceGuard.literalControlTitles()

        // 唯一一项豁免：系统权限对话框上那颗「允许」是 macOS 画的，本 App 的源码里当然没有。
        // 写在这里而不是塞进扫描函数里，是为了让「多豁免一项」这件事必须多说一次理由。
        let systemDialogControls: Set<String> = ["允许"]

        var checked = 0
        var report: [String] = []
        for state in MicrophonePermissionState.allCases {
            for target in SourceGuard.clickTargets(in: state.guidance ?? "") {
                checked += 1
                guard !controls.contains(target),
                      !systemDialogControls.contains(target) else { continue }
                report.append("`\(state)` 的说明让用户去点「\(target)」")
            }
        }

        XCTAssertTrue(
            report.isEmpty,
            "下面这些「下一步」指的控件，App 里一个都找不到（铁律 4）：\n"
                + report.map { "  • " + $0 }.joined(separator: "\n")
                + "\n界面上真有的按钮和开关是：\(controls.sorted().joined(separator: "、"))。"
                + "\n下一步：把文案改成指界面上真有的那个；"
                + "**文案是对的、控件缺了的话，该做的是把那颗控件做出来，不是把话说含糊。**")

        XCTAssertGreaterThanOrEqual(
            checked, 2,
            "这几句话里一句「点『…』」都没扫到，这条测试等于空转。"
                + "下一步：确认 `guidance` 的写法没变成别的句式（那样这条守卫就得跟着改）。")

        // 豁免不许过期：哪天「允许」真的成了本 App 的一颗控件，这条豁免就会替真正的违规挡枪。
        for name in systemDialogControls {
            XCTAssertFalse(
                controls.contains(name),
                "「\(name)」现在真的是界面上的一个控件了，这条豁免已经过期。"
                    + "下一步：把它从 `systemDialogControls` 里删掉，让它跟其他控件一样被正常校验。")
        }
    }

    // MARK: - 从真源码里读那颗开关的标题

    /// 屏幕上那颗开关叫什么，**只能从视图源码里读**，不能写死在测试里。
    /// 写死的话，`Toggle` 的标题一改，文案和界面就走岔了而测试照样绿。
    private static func recordingSwitchTitle() throws -> String {
        let toggle = try SourceGuard.memberBody(of: "private var toggle",
                                                in: try SourceGuard.code(view))
        guard let open = toggle.range(of: "Toggle(\""),
              let close = toggle.range(of: "\"", range: open.upperBound..<toggle.endIndex) else {
            throw Failure.switchTitleNotFound(scanned: toggle.trimmed)
        }
        return String(toggle[open.upperBound..<close.lowerBound])
    }

    /// 读不到就抛错，绝不返回空串——空串会让上面每一条 `contains` 断言恒真/恒假。
    private enum Failure: Error, CustomStringConvertible {
        case switchTitleNotFound(scanned: String)

        var description: String {
            switch self {
            case .switchTitleNotFound(let scanned):
                return "在 \(RecordingSettingsViewTests.view) 的 `toggle` 那一段里找不到 "
                    + "`Toggle(\"…\")` 的字面标题，靠它的断言全部空转（扫到的是：\(scanned)）。"
                    + "下一步：开关的标题保持字面量；改成变量或本地化 key 的话，"
                    + "这几条守卫得换个查法（否则「文案指的开关存在吗」就再没人证明得了）。"
            }
        }
    }
}

private extension String {
    /// 报错里贴原文用：压成一行，太长就截断——报错本身不该刷屏。
    var trimmed: String {
        let flat = split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= 120 ? flat : String(flat.prefix(120)) + "…"
    }
}
