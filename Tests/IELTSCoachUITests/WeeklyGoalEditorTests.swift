import Foundation
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

final class WeeklyGoalEditorTests: XCTestCase {

    func testRangeMatchesTheSettingsModel() {
        // 界面上的可选范围必须和落盘时的归一范围一致。
        // 不一致的话，Stepper 让你选 30，存下去却变成 5，用户会以为设置没生效。
        XCTAssertEqual(WeeklyGoalEditor.range, CoachSettings.weeklyGoalRange)
        XCTAssertEqual(WeeklyGoalEditor.range.lowerBound, 1)
        XCTAssertEqual(WeeklyGoalEditor.range.upperBound, 21)
    }

    func testLabelStatesTheGoal() {
        XCTAssertTrue(WeeklyGoalEditor.label(for: 5).contains("5"))
        XCTAssertTrue(WeeklyGoalEditor.label(for: 5).contains("次"))
    }

    func testHintTellsYouHowManyMoreAndWhatToDoNext() {
        let hint = WeeklyGoalEditor.hint(done: 2, goal: 5)
        XCTAssertTrue(hint.contains("2"), hint)
        XCTAssertTrue(hint.contains("3"), "要算出还差几次：\(hint)")
        XCTAssertTrue(hint.contains("下一步"), hint)
    }

    func testHintSaysDoneWhenTheGoalIsAlreadyMet() {
        let hint = WeeklyGoalEditor.hint(done: 6, goal: 5)
        XCTAssertTrue(hint.contains("达到"), hint)
        XCTAssertTrue(hint.contains("下一步"), hint)
        XCTAssertFalse(hint.contains("还差"), "已经达标了还说「还差」是错的：\(hint)")
    }

    func testHintNeverShowsANegativeRemainder() {
        XCTAssertFalse(WeeklyGoalEditor.hint(done: 9, goal: 5).contains("-"))
    }

    func testNoScorePredictionInTheSettingsCopy() {
        // 与首页同一条红线（DEFINITION-OF-DONE 第 4 节）：
        // 「每周练 5 次大概能到几分」这种话在这里最容易被顺手写上。
        let banned = ["分数", "评分", "打分", "得分", "预测", "band", "Band", "几分", "6.5", "7.0"]
        var texts = [WeeklyGoalEditor.label(for: 5),
                     WeeklyGoalEditor.hint(done: 2, goal: 5),
                     WeeklyGoalEditor.hint(done: 6, goal: 5)]
        for goal in WeeklyGoalEditor.range { texts.append(WeeklyGoalEditor.label(for: goal)) }
        for text in texts {
            for word in banned {
                XCTAssertFalse(text.contains(word), "「\(text)」里出现了被禁止的分数用语「\(word)」")
            }
        }
    }
}

// MARK: - 真正写盘的那一条路：AppState.setWeeklyGoal
//
// **计划补漏（铁律 11）。** 计划 Step 1 说「同时在 WeeklyGoalTests 里追加一条，
// 覆盖 `AppState.setWeeklyGoal` 走的那条写盘路径」，可它给的那段代码从头到尾没有提到
// `AppState`——它自己开一台 `StateStore`，把 `setWeeklyGoal` 做的事**又写了一遍**。
// 也就是说：把 `setWeeklyGoal` 整个换成 `{ true }`，那一条照样绿。
// 计划里那一条仍按原样加了（它确实守着 `CoachSettings.normalized` 这一环），
// 下面这几条才是「按下保存，目标真的存进磁盘、失败时用户看得见」的判据。
@MainActor
final class WeeklyGoalPersistenceTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    /// 假的环境检查：绝不碰真实 ChatGPT（铁律 5）。
    private func makeApp(_ directory: DataDirectory) -> AppState {
        AppState(directory: directory, preflight: { .init(ok: true, messages: []) })
    }

    func testSavingWritesTheGoalToDiskAndShowsItImmediately() throws {
        let app = makeApp(directory)
        XCTAssertEqual(app.state.settings.weeklyGoal, 5, "默认目标应当是 5")

        XCTAssertTrue(app.setWeeklyGoal(3), "写盘成功却返回 false，面板会以为失败而不肯关闭")

        XCTAssertEqual(app.state.settings.weeklyGoal, 3,
                       "改完没有重读，首页那格「本周 N/M」还显示旧目标，用户会以为没生效")
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 3,
                       "目标只改在内存里，重启之后又变回去，而用户不会知道为什么")
        XCTAssertNil(app.settingsError, "这一次是成功的，不该挂着错误")
    }

    func testAnOutOfRangeGoalIsNormalizedBeforeItEverReachesTheDisk() throws {
        let app = makeApp(directory)
        XCTAssertTrue(app.setWeeklyGoal(99))

        // 读回来的那一份会在解码时再归一一次，所以只看 `app.state` 分不出
        // 「存的时候归一过」还是「存了 99、读的时候才被救回来」。
        // 越界值落进 state.json 是要传给命令行那一头的，这里直接查磁盘上的原文。
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.stateFile))
        let settings = try XCTUnwrap((raw as? [String: Any])?["settings"] as? [String: Any])
        XCTAssertEqual(settings["weeklyGoal"] as? Int, 5,
                       "越界的 99 原样落进了 state.json。下一步：确认 `setWeeklyGoal` 里"
                           + "那句 `CoachSettings.normalized(goal)` 还在。")
    }

    func testAFailedSaveIsReportedInChineseWithANextStepAndDoesNotCloseThePanel() throws {
        // 数据目录该在的位置被一个同名文件占了 → `store.mutate` 会抛。
        // 这一路必须让用户看见：静默失败会让他以为目标改好了，下次打开发现又变回去（铁律 7）。
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = makeApp(DataDirectory(root: root))

        XCTAssertFalse(app.setWeeklyGoal(4),
                       "写盘失败却返回 true，面板会关掉，用户以为改好了（铁律 7）")
        let message = try XCTUnwrap(app.settingsError,
                                    "写盘失败一声不吭，用户永远不知道为什么目标没变")
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        XCTAssertTrue(message.contains("每周训练目标"), "得说清是哪件事没成：" + message)
    }

    func testASuccessfulSaveClearsTheEarlierFailureMessage() throws {
        let app = makeApp(directory)
        // 先制造一次失败：把数据目录整个换掉是做不到的，所以直接走「目录被占」那台 app
        // 拿不到，这里换个办法——先让它失败一次再修好，用的是同一台 AppState。
        let blockedRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-recover-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: blockedRoot)
        defer { try? FileManager.default.removeItem(at: blockedRoot) }
        let blocked = makeApp(DataDirectory(root: blockedRoot))
        XCTAssertFalse(blocked.setWeeklyGoal(4))
        XCTAssertNotNil(blocked.settingsError)

        // 换一台指向正常目录的：成功那一次必须把上一次的错误擦掉，
        // 否则面板会一直挂着一条已经不成立的红字，且按验收要求第 5 条永远关不上。
        XCTAssertTrue(app.setWeeklyGoal(4))
        XCTAssertNil(app.settingsError, "成功之后还挂着旧错误，面板就再也关不掉了")
    }
}

// MARK: - 两个入口必须真的接上
//
// 面板写得再对，没人打开也等于没做——「写好了但没摆上屏幕」是本项目反复栽跟头的那一类
// （见 `RenderReachabilitySweepTests` 开头列的四次实测）。
// 那条全模块守卫只问「成员从 body 走不走得到」，问不了「这张 sheet 有没有入口」。
final class WeeklyGoalEntryPointTests: XCTestCase {

    func testTheToolbarGearOpensTheWeeklyGoalSheet() throws {
        let code = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(code.contains("showingWeeklyGoal"),
                      "RootView 里没有开关这张面板的状态，齿轮按钮无从谈起")
        XCTAssertTrue(code.contains("WeeklyGoalSheet("),
                      "工具栏的齿轮按钮没有弹出 `WeeklyGoalSheet`，"
                          + "那么这一版的每周训练目标就是改不了的。"
                          + "下一步：在 detail 上挂 `.sheet(isPresented: $showingWeeklyGoal)`。")
        XCTAssertTrue(code.contains("gearshape"),
                      "工具栏上没有那颗齿轮按钮（SF Symbols `gearshape`），用户找不到入口")
    }

    /// **⌘, 归 Phase 5 的录音设置窗口，这颗齿轮不许抢。**
    ///
    /// `Sources/IELTSCoachApp/main.swift` 里已经有 `Settings { RecordingSettingsScene() }`，
    /// 那个场景自带「设置…」菜单项与 ⌘,。两处绑同一个快捷键 SwiftUI 不会报错，
    /// 只会随机胜出一个——用户按 ⌘, 时而弹录音设置、时而弹每周目标，
    /// 而 Phase 5 有三处中文提示写着「到「录音设置」（⌘,）…」，那条指路会时灵时不灵。
    func testTheGearButtonDoesNotStealTheSettingsShortcutFromPhase5() throws {
        let scene = try SourceGuard.repositoryCode(SourceGuard.appSceneRelativePath)
        XCTAssertTrue(scene.contains("Settings {"),
                      "App 层那个 `Settings { … }` 场景不见了。它没了的话 ⌘, 就空出来了，"
                          + "这条测试的前提也就不成立。下一步：确认 Phase 5 Task 8 还在。")

        let code = try SourceGuard.code("RootView.swift")
        XCTAssertFalse(code.contains("keyboardShortcut(\",\""),
                       "RootView 把 ⌘, 也绑了一遍，和 Phase 5 的设置窗口冲突。"
                           + "下一步：把这颗齿轮的 `.keyboardShortcut(\",\", modifiers: .command)` 去掉——"
                           + "它在工具栏上看得见，不需要抢一个已经有主的快捷键。")
    }

    func testTheWeekTileHasAChangeGoalButtonWiredToTheSameSheet() throws {
        let code = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(code.contains("Button(\"改目标\")"),
                      "「本周训练」那一格里没有「改目标」按钮（计划 Task 8 视图验收第 2 条）。"
                          + "下一步：在 `weekProgressBar` 旁边补一颗，点了翻 `showingWeeklyGoal`。")
        XCTAssertTrue(code.contains("showingWeeklyGoal = true"),
                      "「改目标」按钮没有把面板打开，点下去什么都不会发生——"
                          + "本项目最不能接受的那一类。")
        XCTAssertTrue(code.contains("@Binding var showingWeeklyGoal"),
                      "TodayView 自己存了一份开关状态的话，`RootView` 工具栏那颗齿轮"
                          + "和这颗「改目标」就各开各的面板了。下一步：改成 `@Binding`，两处共用一个。")
    }
}
