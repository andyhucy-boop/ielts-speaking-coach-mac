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


// MARK: - 真正写盘的那一条路
//
// **Phase 10 Task 16 起，每周目标的写入口只剩 `CoachSettingsViewModel.setWeeklyGoal` 一处**
//（`AppState.setWeeklyGoal` 与 `WeeklyGoalSheet` 一起删掉了，理由见
// `SettingsHomeContractTests`：同一个设置有两个写入口，谁后写盘谁说了算）。
//
// 这一组跟着改走那条路，**断言一条没放宽**。它守的两件事在
// `CoachSettingsViewModelTests` 里都还没有人守：
//
// - 越界值不许**原样落进 state.json**。那边那条查的是 `StateStore.load()`，
//   而 `CoachSettings.init(from:)` 解码时会再归一一次——也就是说，
//   把归一整个删掉，那条照样绿。这里直接读磁盘上的 JSON 原文。
// - **成功一次要把上一次那条错误擦掉。** 不擦的话，用户下次打开设置窗口，
//   顶上摆着一条说着早就修好的事的「这次没能存下来」，他会以为刚改的目标又没存上。
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

    private func makeSettings(_ directory: DataDirectory) -> CoachSettingsViewModel {
        CoachSettingsViewModel(app: makeApp(directory), directory: directory)
    }

    func testSavingWritesTheGoalToDiskAndShowsItImmediately() throws {
        let settings = makeSettings(directory)
        XCTAssertEqual(settings.weeklyGoal, 5, "默认目标应当是 5")

        settings.setWeeklyGoal(3)

        XCTAssertNil(settings.error, "这一次是成功的，不该挂着错误")
        XCTAssertEqual(settings.weeklyGoal, 3,
                       "改完没有重读，首页那格「本周 N/M」还显示旧目标，用户会以为没生效")
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 3,
                       "目标只改在内存里，重启之后又变回去，而用户不会知道为什么")
    }

    func testAnOutOfRangeGoalIsNormalizedBeforeItEverReachesTheDisk() throws {
        let settings = makeSettings(directory)
        settings.setWeeklyGoal(99)

        // 读回来的那一份会在解码时再归一一次，所以只看视图模型分不出
        // 「存的时候归一过」还是「存了 99、读的时候才被救回来」。
        // 越界值落进 state.json 是要传给命令行那一头的，这里直接查磁盘上的原文。
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.stateFile))
        let saved = try XCTUnwrap((raw as? [String: Any])?["settings"] as? [String: Any])
        XCTAssertEqual(saved["weeklyGoal"] as? Int, 5,
                       "越界的 99 原样落进了 state.json。下一步：确认 "
                           + "`CoachSettingsViewModel.setWeeklyGoal` 里那句 "
                           + "`CoachSettings.normalized(raw)` 还在。")
    }

    /// 写盘失败必须让用户看见，而且**控件不许停在用户刚拨到的位置**（铁律 7）。
    ///
    /// 静默失败会让他以为目标改好了，下次打开发现又变回去，且永远不知道为什么。
    func testAFailedSaveIsReportedInChineseWithANextStepAndTheStepperSnapsBack() throws {
        // 数据目录该在的位置被一个同名文件占了 → `store.mutate` 会抛。
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-blocked-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = makeSettings(DataDirectory(root: root))
        settings.setWeeklyGoal(4)

        let message = try XCTUnwrap(settings.error,
                                    "写盘失败一声不吭，用户永远不知道为什么目标没变")
        XCTAssertTrue(message.contains("下一步"), "只说失败不说下一步不算合格：" + message)
        XCTAssertNotEqual(settings.weeklyGoal, 4,
                          "没存进去，那颗 Stepper 却停在 4——界面在说一件磁盘上没发生的事")
    }

    /// 失败一次之后再成功，那条错误必须消失。
    ///
    /// **必须在同一台视图模型上先失败再成功。** 两台各跑一半的话，
    /// 「已被清空」这条断言查的是一台从头到尾没失败过的，它的 `error` 本来就是 nil，
    /// 断言恒真。实测过一次（那时守的还是 `AppState.settingsError`）：
    /// 把那句 `error = nil` 整行删掉，全套照样绿。
    ///
    /// 做法：数据目录的位置先被一个同名文件占着（第一次必然失败），再把那个文件删掉
    /// （相当于用户照提示把目录修好），用**同一台**视图模型再存一次。
    func testASuccessfulSaveClearsTheEarlierFailureMessage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-recover-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = makeSettings(DataDirectory(root: root))
        settings.setWeeklyGoal(4)
        XCTAssertNotNil(settings.error,
                        "第一次就该失败——它不失败的话，下面「成功之后旧错误没了」问的是一件"
                            + "从来没发生过的事，这条测试当场变成空转")

        // 障碍拿掉：`StateStore.mutate` 会自己 `createIfNeeded()` 把目录建起来。
        try FileManager.default.removeItem(at: root)

        settings.setWeeklyGoal(4)

        XCTAssertEqual(try StateStore(directory: DataDirectory(root: root)).load()
            .settings.weeklyGoal, 4,
                       "目录已经修好了，这一次却还是没存进磁盘")
        XCTAssertNil(settings.error,
                     "这一次存成功了，上一次那条错误却还挂着。用户下次打开设置窗口，"
                         + "顶上会摆着一条「这次没能存下来」——说的是一件早就修好的事，"
                         + "他会以为刚改的目标又没存上，然后再改一遍。")
    }
}

// MARK: - 两个入口都得真的打开那个窗口，并且停在「训练目标」
//
// 面板写得再对，没人打开也等于没做——「写好了但没摆上屏幕」是本项目反复栽跟头的那一类
// （见 `RenderReachabilitySweepTests` 开头列的四次实测）。
// 那条全模块守卫只问「成员从 body 走不走得到」，问不了「这颗按钮到底打开了什么」。
//
// Phase 10 Task 16 之后这两个入口都不再自弹面板，而是**深链接**：
// 先 `navigator.open(.goals)` 把设置窗口的落点定下来，再 `openSettings()` 打开它。
// 少了前半句，用户点「改目标」会落在「录音」那一栏；少了后半句，点了什么都不会发生。
final class WeeklyGoalEntryPointTests: XCTestCase {

    /// 工具栏那颗齿轮。
    func testTheToolbarGearOpensTheSettingsWindowOnTheGoalsSection() throws {
        let code = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(code.contains("gearshape"),
                      "工具栏上没有那颗齿轮按钮（SF Symbols `gearshape`），用户找不到入口")
        XCTAssertTrue(code.contains("navigator.open(.goals)"),
                      "齿轮没有先把设置窗口定到「训练目标」那一栏，用户点开落在「录音」上，"
                          + "还得自己再找一次。下一步：`navigator.open(.goals); openSettings()`。")
        XCTAssertTrue(code.contains("openSettings()"),
                      "齿轮没有真的打开设置窗口——点下去什么都不会发生，"
                          + "而这一版的每周训练目标就是改不了的。")
        XCTAssertFalse(code.contains("WeeklyGoalSheet"),
                       "齿轮又弹回了自己那张面板。同一个设置两份界面，"
                           + "其中一份改完另一份显示的还是旧值。")
    }

    /// **⌘, 归 App 层那个 `Settings` 场景，这颗齿轮不许抢。**
    ///
    /// 两处绑同一个快捷键 SwiftUI 不会报错，只会随机胜出一个——
    /// 用户按 ⌘, 时而弹这个、时而弹那个，而全 App 有好几处中文提示写着「到「设置」（⌘,）…」，
    /// 那条指路会时灵时不灵。
    func testTheGearButtonDoesNotStealTheSettingsShortcut() throws {
        let scene = try SourceGuard.repositoryCode(SourceGuard.appSceneRelativePath)
        XCTAssertTrue(scene.contains("Settings {"),
                      "App 层那个 `Settings { … }` 场景不见了。它没了的话 ⌘, 就空出来了，"
                          + "这条测试的前提也就不成立。")

        let code = try SourceGuard.code("RootView.swift")
        XCTAssertFalse(code.contains("keyboardShortcut(\",\""),
                       "RootView 把 ⌘, 也绑了一遍，和设置窗口冲突。"
                           + "下一步：把这颗齿轮的 `.keyboardShortcut(\",\", modifiers: .command)` 去掉——"
                           + "它在工具栏上看得见，不需要抢一个已经有主的快捷键。")
    }

    /// 首页「本周训练」那一格里的「改目标」。
    ///
    /// **这颗按钮刻意保留**（Task 16 决策表第二行）：这一格写着「本周 3/5 次」，
    /// 旁边不给一个改目标的入口，用户看得见目标却不知道去哪儿改。
    func testTheWeekTileChangeGoalButtonOpensTheSameWindowOnTheSameSection() throws {
        let code = try SourceGuard.code("Today/TodayView.swift")
        XCTAssertTrue(code.contains("Button(\"改目标\")"),
                      "「本周训练」那一格里没有「改目标」按钮。"
                          + "下一步：在 `weekProgressBar` 旁边补一颗，走同一条深链接。")
        XCTAssertTrue(code.contains("navigator.open(.goals)"),
                      "「改目标」没有把设置窗口定到「训练目标」那一栏。")
        XCTAssertTrue(code.contains("openSettings()"),
                      "「改目标」没有真的打开设置窗口，点下去什么都不会发生——"
                          + "本项目最不能接受的那一类。")
        XCTAssertTrue(code.contains("let navigator: SettingsNavigator"),
                      "TodayView 自己造了一个 `SettingsNavigator` 的话，"
                          + "它和工具栏那颗齿轮就各定各的落点了。"
                          + "下一步：改成由 `RootView` 传进来，全 App 共用同一个。")
    }
}
