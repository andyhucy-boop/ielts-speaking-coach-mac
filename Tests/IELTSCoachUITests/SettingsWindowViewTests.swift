import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 设置窗口本体（Phase 10 Task 16）。
///
/// ## 为什么这一份非有不可
///
/// 这次合并把四处旧入口收成了一个窗口。窗口里那两百来行视图代码要是整段被删掉，
/// **全套测试照样绿**——`CoachSettingsViewModelTests` 测的是视图模型（逻辑），
/// 它证明不了那些控件真的上了屏；`SettingsHomeContractTests` 只问「有没有第二个写入口」，
/// 一个都没有（连唯一那个也没画出来）时它同样是绿的。
/// 这正是本项目栽过四次的那一类：「写好了，但没摆上屏幕」。
///
/// ## 边界
///
/// 与本项目其余视图层测试一致：扫源码，不画界面。拦得住「整段渲染被删」「接线被换掉」
/// 「共用卡片把传进来的控件丢了」；拦不住「代码还在但条件永远为假」，
/// 也不管排版好不好看、深色下好不好读——那部分归 Task 19 的人工验收。
final class SettingsWindowViewTests: XCTestCase {

    private static let view = "Settings/SettingsWindowView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        XCTAssertTrue(try Self.viewCode().contains("struct SettingsWindowView"),
                      "没扫到设置窗口的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 一、四个分区，一个都不能少，而且全部来自 SettingsSection

    /// 分区不许在视图里另写一套。
    ///
    /// 手抄一份的话，`CoachSettingsViewModelTests.testThereAreExactlyFourSections`
    /// 那条「恰好四个」就变成在测一段没人用的枚举：加一个分区只改枚举，窗口里不会出现；
    /// 或者反过来，窗口里多出一栏而枚举不知道。
    func testTheFourTabsComeFromTheSectionEnumAndNotFromAHandWrittenList() throws {
        let body = try SourceGuard.memberBody(of: "public var body", in: try Self.viewCode())
        XCTAssertTrue(body.contains("ForEach(SettingsSection.allCases)"),
                      "分区不是从 `SettingsSection.allCases` 来的，视图里另写了一套。"
                          + "实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("section.title") && body.contains("section.systemImage"),
                      "标签页的标题或图标不是从 `SettingsSection` 取的。"
                          + "实际取到的是：\n\(body)")
    }

    /// **四个分支一个都不能少，而且每一支画的必须是它自己那一栏。**
    ///
    /// 少一支，那一栏就是一片空白，而这不会有任何编译错误
    ///（`@ViewBuilder` 的 `switch` 少一支编不过，但把某一支换成 `EmptyView()` 编得过）。
    ///
    /// **配对必须逐支断言，不能对整个函数体各问各的。** 这里从前写的是
    /// `body.contains("case .goals") && body.contains("goalsSection")`——
    /// 两件事分开问，谁画谁完全没人管。2026-08-08 复审实测：把 `.goals` 与 `.data`
    /// 两支的内容对调（`case .goals: pane(section, content: dataSection)`），
    /// `swift test` 1671 条一条不红。而那正是 Task 16 的头号功能坏掉的样子：
    /// 首页齿轮 `navigator.open(.goals)` + `openSettings()` 进来，标签停在「训练目标」上，
    /// 页面却是「数据与隐私」——用户彻底改不了每周目标，且全套测试全绿。
    ///
    /// 所以改成先把 `switch section` 逐支切开（`SourceGuard.switchBranches`，
    /// 它自己被 `SourceGuardTests` 守着），再问「这一支的大括号里画的是不是它自己那一栏」。
    func testEverySectionDrawsItsOwnPaneAndNotAnotherSections() throws {
        let body = try SourceGuard.memberBody(of: "private func sectionBody",
                                              in: try Self.viewCode())
        let branches = try SourceGuard.switchBranches(over: "section", in: body)

        // 先确认这一趟真的切出了分支。切了个空的话，下面那个循环里的 `first(where:)`
        // 会全部落空——那还是会红，但红的理由会指向四个分区而不是「切分失效了」。
        XCTAssertEqual(branches.count, SettingsSection.allCases.count,
                       "`switch section` 切出了 \(branches.count) 支，而 `SettingsSection` "
                           + "有 \(SettingsSection.allCases.count) 项。要么少了一栏"
                           + "（用户点过去是一片空白），要么这段 switch 的写法变了、"
                           + "切分失效了。实际取到的是：\n\(body)")
        XCTAssertFalse(branches.contains(where: \.isDefault),
                       "`switch section` 用了 `default:` 兜底。将来加一个分区，"
                           + "它会静默地落进别人的分支里，编译器一声不吭。"
                           + "下一步：逐支写全。实际取到的是：\n\(body)")

        for (caseName, member) in [("recording", "recordingSection"),
                                   ("goals", "goalsSection"),
                                   ("practice", "practiceSection"),
                                   ("data", "dataSection")] {
            let branch = try XCTUnwrap(
                branches.first { $0.cases.contains(caseName) },
                "`switch section` 里没有接住 `.\(caseName)` 的那一支，那一栏是一片空白。"
                    + "实际取到的是：\n\(body)")
            XCTAssertTrue(SourceGuard.mentions(member, in: branch.body),
                          "`case .\(caseName)` 那一支画的不是 `\(member)`。"
                              + "画成别的分区的话，用户从深链接进来标签停在「\(caseName)」上、"
                              + "页面却是另一栏的内容——他会以为这个设置根本不存在。"
                              + "这一支实际取到的是：\n\(branch.body)")
        }
    }

    /// 当前停在哪一栏必须**读写都走 `navigator`**。
    ///
    /// 只写不读：从首页齿轮点进来永远落在默认那一栏（用户还得自己再找一次）。
    /// 只读不写：用户在窗口里点了另一栏，`navigator` 不知道，下次深链接会把他弹回去。
    func testTheSelectedTabIsTheNavigatorsAndNotASecondCopy() throws {
        let binding = try SourceGuard.memberBody(of: "private var sectionSelection",
                                                 in: try Self.viewCode())
        XCTAssertTrue(binding.contains("navigator.section"),
                      "选中哪一栏不是从 `navigator` 读的，深链接（先 `open(.goals)` 再"
                          + "`openSettings()`）会永远落在默认那一栏。实际取到的是：\n\(binding)")
        XCTAssertTrue(binding.contains("navigator.open("),
                      "用户在窗口里换栏没有写回 `navigator`。实际取到的是：\n\(binding)")
    }

    /// 三个自绘分区共用的那张外壳，**三句渲染一句都不许少**。
    ///
    /// `content()` 那一句被删掉时可达性扫描完全看不见——控件是以闭包传进来的，
    /// 而 `goalsSection` / `practiceSection` / `dataSection` 三个成员确实「可达」。
    /// 后果是三栏各剩一个标题和一句「这一栏管什么」，一个可点的控件都没有。
    func testTheSharedPaneDrawsTheSummaryTheFailureAndTheContent() throws {
        let pane = try SourceGuard.memberBody(of: "private func pane", in: try Self.viewCode())
        XCTAssertTrue(pane.contains("summary(section)"),
                      "外壳没画那句「这一栏管什么」，用户得点进去挨个猜。实际取到的是：\n\(pane)")
        XCTAssertTrue(pane.contains("settings.error") && pane.contains("failureCard("),
                      "写盘失败那段说明没摆进外壳。存不下来却一个字都不说，"
                          + "用户以为改好了，下次打开发现又变回去（铁律 7）。实际取到的是：\n\(pane)")
        XCTAssertTrue(pane.contains("content"),
                      "外壳收下了内容却没画出来：三栏各剩一个标题，一个可点的控件都没有，"
                          + "而可达性扫描只问「成员走不走得到」，问不出这件事。"
                          + "实际取到的是：\n\(pane)")
    }

    /// 那句「这一栏管什么」必须来自 `SettingsSection.summary`，不是视图里另写的一份。
    func testTheSectionSummaryComesFromTheEnum() throws {
        let summary = try SourceGuard.memberBody(of: "private func summary",
                                                 in: try Self.viewCode())
        XCTAssertTrue(summary.contains("section.summary"),
                      "分区抬头下面那句话不是 `SettingsSection.summary`。两处各写一份的话，"
                          + "加一个分区就得改两处，而漏改的那一处不会报错。"
                          + "实际取到的是：\n\(summary)")
        XCTAssertTrue(summary.contains("section.title"),
                      "分区抬头的标题是手写的。实际取到的是：\n\(summary)")
    }

    // MARK: - 二、录音那一格原样嵌 Phase 5 的实现

    /// **不许在这里重写一遍录音开关。**
    ///
    /// `RecordingSettingsViewModel` 那套「权限没拿到时开关必须停在关」的逻辑是踩过坑换来的。
    /// 在这里自己写一个 `Toggle("保存我的回答录音")` 会造出 Phase 5 明令禁止的状态：
    /// 开关显示「开」、麦克风权限根本没申请过，用户练完发现什么都没录，且无从查起。
    ///
    /// 具体那一格画没画出来、`refresh()` 还在不在，由 `RecordingSettingsViewTests` 守
    ///（它现在扫的就是这个文件的 `recordingSection`）。
    func testTheRecordingSectionEmbedsPhaseFivesPageInsteadOfRewritingIt() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("RecordingSettingsView(viewModel: recording)"),
                      "录音那一格没有嵌 Phase 5 的 `RecordingSettingsView`。")
        XCTAssertFalse(code.contains("保存我的回答录音"),
                       "这个文件里出现了「保存我的回答录音」——录音开关被重写了一遍。"
                           + "两份实现迟早走岔，而走岔的形态是「界面显示在录、实际一秒没录」。")
        XCTAssertFalse(code.contains("recordingEnabled"),
                       "这个文件直接碰了 `recordingEnabled`。那条路只许走 "
                           + "`RecordingSettingsViewModel.setEnabled(_:)`——它才会先申请麦克风权限。")
    }

    /// 录音那一格写完盘之后，主窗口那份 `AppState` 必须重读。
    ///
    /// 它持有自己的 `StateStore`，写盘不经过 `AppState`。少了这根线，
    /// 用户在设置窗口开了录音、转身开练，主窗口交给录音器的还是旧值。
    ///
    /// **这条只守「这个窗口要的是工厂那一份」，不守「工厂上真的挂了 `onChange`」。**
    /// 这里从前写着「那根线由 `RecordingSettingsViewModelTests` 那条 `onChange` 测试守着行为」
    /// ——那句话是错的，2026-08-08 复审当场戳破：那条测试自己 new 了一台视图模型、
    /// 自己把 `{ app.reload() }` 传了进去，证明的是「只要接上就会 reload」，
    /// 证明不了生产路径接了；实测把 `AppState.makeRecordingSettingsViewModel()` 里
    /// `onChange:` 那一行整句删掉（参数有默认值 `{}`，编译照过），全库一条不红。
    /// 「既没有守卫、又留着一句说自己被守着的注释」比没有注释更坏——
    /// 下一个人照着它看一眼就放过去了。
    ///
    /// 那件事现在由 `AppStateTests.`
    /// `testTheRecordingSettingsViewModelFromTheAppTellsTheMainWindowToRefresh` 守：
    /// 它走的是 `app.makeRecordingSettingsViewModel()` 本身，
    /// `setEnabled(true)` 之后断言 `app.state.settings.recordingEnabled` 真的变了。
    func testTheRecordingSectionUsesTheViewModelThatNotifiesTheMainWindow() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("app.makeRecordingSettingsViewModel()"),
                      "录音那一格的视图模型不是从 `AppState` 要的，也就没有那根 `onChange`："
                          + "在这里开了录音，主窗口那份状态还是旧的（开练时交给录音器的仍是旧值）。")
        XCTAssertFalse(code.contains("RecordingSettingsViewModel(store:"),
                       "这个窗口自己 new 了一台 `RecordingSettingsViewModel`。那一台没有 `onChange`，"
                           + "而且它的 `StateStore` 未必和 `AppState` 指着同一个目录。"
                           + "下一步：改回 `app.makeRecordingSettingsViewModel()`。")
    }

    // MARK: - 三、训练目标

    /// 等宽数字那一条**必须钉在它说的那一行上**。
    ///
    /// 这里从前问的是「`goalsSection` 里任意位置出现过 `.monospacedDigit()` 吗」，
    /// 而这一段里有两处（目标数字那行、下面的提示那行）。2026-08-08 复审实测：
    /// 只删掉目标数字那一句——也就是失败信息逐字点名的「从「每周练 9 次」按到
    /// 「每周练 10 次」时整行会横向抖」的那一行——`swift test` 1671 条一条不红，
    /// 两处一起删才会红。也就是说它实际守的是「这一块里还有等宽数字」。
    /// 现在改成对两处各切各的修饰符链，各断言各的。
    func testTheGoalStepperUsesTheSharedRangeAndDoesNotJitter() throws {
        let section = try SourceGuard.memberBody(of: "private var goalsSection",
                                                 in: try Self.viewCode())
        XCTAssertTrue(section.contains("in: WeeklyGoalEditor.range"),
                      "Stepper 的范围不是 `WeeklyGoalEditor.range`（也就是落盘时的归一范围本身）。"
                          + "另写一个范围的话，界面让你选 30、存下去变成 5，"
                          + "用户会以为设置没生效。实际取到的是：\n\(section)")
        XCTAssertTrue(section.contains("WeeklyGoalEditor.label(for: settings.weeklyGoal)"),
                      "那一行显示的不是当前已保存的目标。写死一个数字或者显示别的取值的话，"
                          + "用户按加号看到的数字和磁盘上的对不上。实际取到的是：\n\(section)")

        let number = try SourceGuard.modifierChain(
            after: "Text(WeeklyGoalEditor.label(for: settings.weeklyGoal))", in: section)
        XCTAssertTrue(number.contains(".monospacedDigit()"),
                      "**目标数字那一行**没用等宽数字：从「每周练 9 次」按到「每周练 10 次」时"
                          + "整行会横向抖一下，而这恰恰是用户唯一会反复来回按的地方"
                          + "（DESIGN-SYSTEM 第 1 节与第 6 节最后一条）。"
                          + "注意这一条只看这一行自己的修饰符链——"
                          + "下面提示那行上的 `.monospacedDigit()` 替它挡不了枪。"
                          + "这一行实际取到的是：\n\(number)")

        XCTAssertTrue(section.contains("settings.weeklyGoalHint"),
                      "少了那句「本周练了几次、离目标还差几次」（铁律 6 要的现状 + 下一步）。"
                          + "实际取到的是：\n\(section)")
        let hint = try SourceGuard.modifierChain(after: "Text(settings.weeklyGoalHint)",
                                                 in: section)
        XCTAssertTrue(hint.contains(".monospacedDigit()"),
                      "**提示那一行**没用等宽数字。它写的是「本周练了 9 次」这种句子，"
                          + "练到第 10 次时整句会跟着横向抖一下"
                          + "（DESIGN-SYSTEM 第 1 节：数字一律等宽）。"
                          + "这一行实际取到的是：\n\(hint)")
    }

    /// **没存进去的话，那颗 Stepper 必须自己弹回落盘的事实。**
    ///
    /// 判据是「中间没有第二份状态」：读的是视图模型的计算属性（它又现读 `app.state`），
    /// 写的是视图模型的方法。中间存一份 `@State` 的话，写盘失败时它会停在用户刚拨到的位置，
    /// 界面就在说一件磁盘上没发生的事（铁律 7）。
    func testTheGoalBindingKeepsNoSecondCopyOfTheValue() throws {
        let binding = try SourceGuard.memberBody(of: "private var goalBinding",
                                                 in: try Self.viewCode())
        XCTAssertTrue(binding.contains("settings.weeklyGoal"),
                      "Stepper 读的不是视图模型现算的取值。实际取到的是：\n\(binding)")
        XCTAssertTrue(binding.contains("settings.setWeeklyGoal("),
                      "Stepper 拨过去之后没有落盘，用户重开 App 又变回去了。"
                          + "实际取到的是：\n\(binding)")
    }

    // MARK: - 四、练习偏好（四项，含从训练记录页收进来的逐字稿）

    func testAllFourPracticePreferencesAreOnThePage() throws {
        let section = try SourceGuard.memberBody(of: "private var practiceSection",
                                                 in: try Self.viewCode())
        for member in ["routePreference", "feedbackPreference",
                       "prepPreference", "transcriptPreference"] {
            XCTAssertTrue(section.contains(member),
                          "「练习偏好」里少了 `\(member)`。四项少一项，那个设置就没有家了——"
                              + "而它的旧入口已经在这次合并里撤掉。实际取到的是：\n\(section)")
        }
    }

    /// 四项共用的那张卡片，**三句渲染一句都不许少**（做法与从前学习计划页那一版一致）。
    func testThePreferenceCardDrawsItsTitleItsControlAndItsTradeOffLine() throws {
        let card = try SourceGuard.memberBody(of: "private func preferenceCard",
                                              in: try Self.viewCode())
        XCTAssertTrue(card.contains("Text(title)"),
                      "偏好卡片没把 `title` 画出来，四张卡片会变成四坨没有抬头的控件。"
                          + "实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("control"),
                      "偏好卡片收下了控件却没画出来（四个控件一个都不上屏，只剩四张空卡片）。"
                          + "注意可达性扫描看不见这件事——控件是当参数传进来的。"
                          + "实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("Text(explanation)"),
                      "偏好卡片收下了取舍说明却没画出来。那行小字不是装饰："
                          + "两个选项哪个合适取决于用户现在想练什么，不写清代价他只能靠猜，"
                          + "而猜错要练完一整场才发现。实际取到的是：\n\(card)")
    }

    /// 四项各自把**自己那一行**取舍说明交给卡片。
    ///
    /// 上面那条守的是「卡片画不画」，这一条守的是「传进去的是不是那一份」。
    /// 少了它，`explanation:` 传成空串或者四处传同一份，上面那条照样绿。
    func testEachPreferenceHandsItsOwnTradeOffLineToTheCard() throws {
        let code = try Self.viewCode()
        for (marker, constant, name) in [
            ("private var routePreference",
             "PracticePreferenceEditor.defaultRouteExplanation", "默认练习路线"),
            ("private var feedbackPreference",
             "PracticePreferenceEditor.feedbackTimingExplanation", "反馈时机"),
            ("private var prepPreference",
             "PracticePreferenceEditor.part2PrepExplanation", "Part 2 准备时间"),
            ("private var transcriptPreference",
             "PracticePreferenceEditor.transcriptExplanation", "记录对话逐字稿")
        ] {
            let control = try SourceGuard.memberBody(of: marker, in: code)
            XCTAssertTrue(control.contains("preferenceCard("),
                          "「\(name)」没走共用的 `preferenceCard`，那张卡片上的三句渲染"
                              + "对它就一句都不作数。实际取到的是：\n\(control)")
            XCTAssertTrue(control.contains(constant),
                          "「\(name)」下面那行小字不是 `\(constant)`。"
                              + "传错一份或者传成空串，用户读到的就是别一项的取舍。"
                              + "实际取到的是：\n\(control)")
        }
    }

    func testTheOptionListsComeFromTheEnumsAndNotFromAHandWrittenCopy() throws {
        let code = try Self.viewCode()
        for (marker, needle, name) in [
            ("private var routePreference", "PracticeRoute.allCases", "默认练习路线"),
            ("private var feedbackPreference", "FeedbackTiming.allCases", "反馈时机"),
            ("private var prepPreference", "Part2PrepMode.allCases", "Part 2 准备时间")
        ] {
            let control = try SourceGuard.memberBody(of: marker, in: code)
            XCTAssertTrue(control.contains(needle),
                          "「\(name)」的选项是手抄的一份，不是 `\(needle)`。"
                              + "将来加一档，界面上不会出现，而编译器一声不吭。"
                              + "实际取到的是：\n\(control)")
        }
        let route = try SourceGuard.memberBody(of: "private var routePreference", in: code)
        XCTAssertTrue(route.contains("route.title"),
                      "路线选项没用 `PracticeRoute.title` 显示，用户看到的会是 `planToday` "
                          + "这种英文 case 名。实际取到的是：\n\(route)")
    }

    /// 四项偏好的绑定：**读现值、写视图模型，中间没有第二份状态。**
    ///
    /// 默认路线那一项还多守一件事：Core 存的是字符串，两边靠 `PracticeRoutePreference`
    /// 对齐；这一层只认 `PracticeRoute`，翻译收在视图模型里一处。
    func testEveryPreferenceIsWiredBothWaysThroughTheViewModel() throws {
        let code = try Self.viewCode()
        for (marker, reader, writer, name) in [
            ("private var routeBinding", "settings.defaultRoute",
             "settings.setDefaultRoute(", "默认练习路线"),
            ("private var feedbackBinding", "settings.feedbackTiming",
             "settings.setFeedbackTiming(", "反馈时机"),
            ("private var prepBinding", "settings.part2PrepMode",
             "settings.setPart2PrepMode(", "Part 2 准备时间"),
            ("private var transcriptBinding", "settings.transcriptEnabled",
             "settings.setTranscriptEnabled(", "记录对话逐字稿")
        ] {
            let binding = try SourceGuard.memberBody(of: marker, in: code)
            XCTAssertTrue(binding.contains(reader),
                          "「\(name)」显示的不是 `\(reader)`——控件显示的值和真实设置无关。"
                              + "实际取到的是：\n\(binding)")
            XCTAssertTrue(binding.contains(writer),
                          "「\(name)」拨过去之后没有调 `\(writer)…)`，也就是根本没落盘："
                              + "关掉 App 再打开它会自己弹回来。实际取到的是：\n\(binding)")
        }
    }

    // MARK: - 五、数据与隐私

    /// 「可选中」那一条**必须钉在路径那一行上**。
    ///
    /// 这里从前问的是「`dataLocationCard` 里任意位置出现过 `.textSelection(.enabled)` 吗」，
    /// 而这张卡片里有两处（路径、占用）。2026-08-08 复审实测：只删掉路径那一句——
    /// 也就是计划 Step 4 明写的「数据目录完整路径（**可选中复制**）」、
    /// 也是下面这条失败信息逐字点名的那一行——`swift test` **全库 1671 条一条不红**，
    /// 全库再没有第二条兜底。而成品标准第 10 条（换电脑把这个目录整个拷过去）
    /// 就靠用户能把这条路径复制走。
    func testTheDataSectionShowsThePathTheUsageAndAWayIntoFinder() throws {
        let card = try SourceGuard.memberBody(of: "private var dataLocationCard",
                                              in: try Self.viewCode())
        XCTAssertTrue(card.contains("settings.dataDirectoryURL.path"),
                      "没有把数据目录的完整路径显示出来。成品标准第 10 条（拷这个目录换机器）"
                          + "全靠用户知道它在哪儿。实际取到的是：\n\(card)")
        let path = try SourceGuard.modifierChain(after: "Text(settings.dataDirectoryURL.path)",
                                                 in: card)
        XCTAssertTrue(path.contains(".textSelection(.enabled)"),
                      "那条路径选不中，用户只能照着屏幕手抄一串几十个字符的路径。"
                          + "注意这一条只看路径那一行自己的修饰符链——"
                          + "占用那行上的 `.textSelection(.enabled)` 替它挡不了枪。"
                          + "这一行实际取到的是：\n\(path)")
        XCTAssertTrue(card.contains("settings.usage.summaryText"),
                      "没显示占用。算出来了不上屏就是白算（本项目栽过好几次）。"
                          + "实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("Button(\"在访达中显示\")"),
                      "没有「在访达中显示」这颗按钮，用户得自己去访达里按路径一层层找。"
                          + "实际取到的是：\n\(card)")
    }

    /// 目录还没建出来时访达会一声不响地什么都不做——这一路必须说话（铁律 7）。
    func testTheFinderButtonSaysSomethingWhenThereIsNothingToOpen() throws {
        let reveal = try SourceGuard.functionBody(named: "reveal", in: try Self.viewCode())
        XCTAssertTrue(reveal.contains("revealNotice ="),
                      "打不开时一个字都不说，用户看到的是一颗「点了没反应」的按钮。"
                          + "实际取到的是：\n\(reveal)")
        XCTAssertTrue(reveal.contains("下一步"),
                      "只说打不开、不说下一步做什么，不算合格（铁律 6）。实际取到的是：\n\(reveal)")
    }

    /// 换机器与隐私那两句话必须真的在页面上。
    ///
    /// 它们不是装饰：一句是成品标准第 10 条的操作说明，
    /// 一句是这个产品最要紧的承诺（不上传任何东西）。
    func testThePrivacyPromiseAndTheBackupInstructionAreOnScreen() throws {
        let card = try SourceGuard.memberBody(of: "private var privacyCard",
                                              in: try Self.viewCode())
        for phrase in ["换电脑时把这个文件夹整个拷过去就能接着用", "备份就是拷贝它",
                       "只在这台电脑上", "不上传任何东西"] {
            XCTAssertTrue(card.contains(phrase),
                          "少了「\(phrase)」这句话。实际取到的是：\n\(card)")
        }
    }

    // MARK: - 六、失败说明与红线

    /// 写盘失败那段话要**全文显示、可选中、不许截断**——「下一步」在后半截。
    func testTheFailureIsShownInFullAndCanBeCopied() throws {
        let card = try SourceGuard.memberBody(of: "private func failureCard",
                                              in: try Self.viewCode())
        XCTAssertTrue(card.contains("Text(message)"),
                      "失败说明没有原样显示出来。视图模型给的那句话里带着系统的原始报错和"
                          + "「下一步确认数据目录可写」，换成一句自拟的「操作失败」"
                          + "就是铁律 6 明令不合格的那一种。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains(".textSelection(.enabled)"),
                      "失败说明选不中。里面那段系统原始报错是用户去搜、去问、去贴给别人的唯一线索。"
                          + "实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains(".fixedSize(horizontal: false, vertical: true)"),
                      "失败说明没有允许换行，长句会被截成一行，而「下一步」正好在被截掉的后半截。"
                          + "实际取到的是：\n\(card)")
        XCTAssertFalse(card.contains(".lineLimit("),
                       "失败说明加了行数限制，等于把「下一步」那半句藏起来。实际取到的是：\n\(card)")
    }

    /// 这个窗口不许出现任何形式的雅思分数预测或水平判断（DEFINITION-OF-DONE 第 4 节）。
    /// 「每周练几次能到几分」这种话在设置目标的地方最容易被顺手写上。
    func testThisWindowNeverPredictsABandScore() throws {
        let code = try Self.viewCode()
        for banned in ["band", "Band", "BAND", "score", "Score",
                       "分数", "评分", "打分", "得分", "几分", "水平分", "评级", "水平判断", "预测"] {
            XCTAssertFalse(code.contains(banned),
                           "设置窗口里出现了「\(banned)」。"
                               + "下一步：改成只说「练了几次、离目标还差几次」。")
        }
    }
}

/// 「停在哪一栏」这件事本身。
///
/// 它只有三行，但那三行是四处深链接共同的落点：错一个字，
/// 首页齿轮、学习计划页和训练记录页那三颗按钮就一起落到错的分区上。
@MainActor
final class SettingsNavigatorTests: XCTestCase {

    /// 默认停在「录音」：⌘, 在 Phase 5 打开的就是录音那一页，
    /// 直接按快捷键进来的人看到的东西不该因为这次合并而变。
    func testItStartsOnTheRecordingSection() {
        XCTAssertEqual(SettingsNavigator().section, .recording)
    }

    /// 每一栏都得真的到得了。只测一栏的话，`open(_:)` 写死成
    /// `section = .goals` 也是绿的——而那意味着另外三颗按钮全都落错地方。
    func testItOpensEverySectionIncludingBackToTheFirstOne() {
        let navigator = SettingsNavigator()
        for section in SettingsSection.allCases {
            navigator.open(section)
            XCTAssertEqual(navigator.section, section, "`open(\(section))` 没停在那一栏")
        }
        navigator.open(.recording)
        XCTAssertEqual(navigator.section, .recording, "换回第一栏没生效")
    }

    /// **它不许存任何设置的取值。** 存了的话就又多了一份可能和磁盘不一致的状态，
    /// 而这次合并要消灭的恰恰是那种东西。
    func testItHoldsNothingButTheSelectedSection() throws {
        let code = try SourceGuard.code("Settings/SettingsNavigator.swift")
        for banned in ["weeklyGoal", "transcriptEnabled", "feedbackTiming",
                       "part2PrepMode", "defaultRoute", "recordingEnabled"] {
            XCTAssertFalse(code.contains(banned),
                           "`SettingsNavigator` 里出现了 `\(banned)`。它只该记「停在哪一栏」；"
                               + "设置的取值一律在 `AppState` 里，那是「两个窗口不可能不同步」的前提。")
        }
    }
}

/// 四项练习偏好的中文说法与取舍说明。
///
/// **这些句子是从学习计划页页尾原样搬过来的**（Phase 10 Task 16），
/// 逐字断言就是「搬家没搬坏」的守门员：改一个字，用户读到的取舍就变了。
final class PracticePreferenceEditorTests: XCTestCase {

    /// 三个选项的中文标题真跑一遍，并且**穷尽**：将来给这两个枚举加一档，
    /// 编译器会当场逼人补上，前提是这里的 `switch` 没有 `default:` 兜底。
    func testEveryOptionHasADistinctChineseTitle() throws {
        XCTAssertEqual(PracticePreferenceEditor.feedbackTimingTitle(.deferred), "全程零反馈")
        XCTAssertEqual(PracticePreferenceEditor.feedbackTimingTitle(.immediate), "当场点出")
        XCTAssertEqual(PracticePreferenceEditor.part2PrepTitle(.countdown), "一分钟倒计时")
        XCTAssertEqual(PracticePreferenceEditor.part2PrepTitle(.learnerControlled), "自己决定")

        let code = try SourceGuard.code("Settings/PracticePreferenceEditor.swift")
        for name in ["feedbackTimingTitle", "part2PrepTitle"] {
            let body = try SourceGuard.functionBody(named: name, in: code)
            XCTAssertFalse(body.contains("default:"),
                           "`\(name)` 用了 `default:` 兜底。将来加一档，它会被静默地显示成"
                               + "某个已有选项的名字，编译器一声不吭。下一步：逐档写全。")
        }
    }

    /// 四行取舍说明逐字来自 spec 3.1（前三行）与 Phase 4（逐字稿那一行）。
    ///
    /// **它们不是装饰。** 「全程零反馈」和「当场点出」哪个更好取决于用户现在想练什么，
    /// 不写代价的话，他只能靠猜，而猜错要练完一整场才发现。
    func testEachPreferenceSpellsOutWhatItCostsYou() {
        XCTAssertEqual(PracticePreferenceEditor.defaultRouteExplanation,
                       "今日训练页会把这条路线排在最前面。")
        XCTAssertEqual(
            PracticePreferenceEditor.feedbackTimingExplanation,
            "全程零反馈像真考试，但答砸的地方要等到最后才知道；"
                + "当场点出纠正及时，代价是不再是真实考试节奏，单场时间也会拉长。")
        XCTAssertEqual(
            PracticePreferenceEditor.part2PrepExplanation,
            "一分钟倒计时像真考试，练的是压力下组织语言；自己决定适合刚起步时先把内容想清楚。")
        // 逐字来自 Phase 4（原先写在训练记录页那个开关下面）。
        // 「记录对话」四个字很容易被理解成录音，少了这一句，谨慎的用户只会把它关掉。
        XCTAssertEqual(
            PracticePreferenceEditor.transcriptExplanation,
            "开着时，练习中会把考官的问题和你的回答记下来，方便复盘时回看。"
                + "它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网。")
    }

    /// 训练记录页那一行只读现状：**两种状态都得说得出来，而且都得指路。**
    ///
    /// 只测一种的话，`"逐字稿记录：开 · …"` 这种写死的实现是绿的——
    /// 而那意味着用户明明关掉了，那一行还写着「开」。
    func testTheReadOnlyStatusLineSaysBothStatesAndWhereToChangeThem() {
        let on = PracticePreferenceEditor.transcriptStatusText(enabled: true)
        let off = PracticePreferenceEditor.transcriptStatusText(enabled: false)
        XCTAssertNotEqual(on, off, "开和关显示的是同一句话，那一行等于没说")
        XCTAssertTrue(on.contains("开"), on)
        XCTAssertTrue(off.contains("关"), off)
        for text in [on, off] {
            XCTAssertTrue(text.contains("设置") && text.contains("练习偏好"),
                          "没告诉用户去哪儿改，他只能自己翻遍每一页：\(text)")
        }
    }
}
