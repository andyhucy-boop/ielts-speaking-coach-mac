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

    /// 失败一次之后再成功，那条错误必须消失。
    ///
    /// **必须在同一台 `AppState` 上先失败再成功。** 上一版开了两台——错误设在「目录被占」
    /// 那台上，而「已被清空」这条断言查的是另一台从头到尾没失败过的，它的 `settingsError`
    /// 本来就是 nil，断言恒真。实测：把 `AppState.setWeeklyGoal` 里那句 `settingsError = nil`
    /// 整行删掉，1171 条全绿——也就是「成功一次就把上一次的错误擦掉」这件事根本没人守。
    ///
    /// 做法：数据目录的位置先被一个同名文件占着（第一次必然失败），再把那个文件删掉
    /// （相当于用户照提示把目录修好），用**同一台** app 再存一次。
    func testASuccessfulSaveClearsTheEarlierFailureMessage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-weekly-goal-recover-\(UUID().uuidString)")
        try Data("这是个文件，不是目录".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = makeApp(DataDirectory(root: root))
        XCTAssertFalse(app.setWeeklyGoal(4),
                       "第一次就该失败——它不失败的话，下面「成功之后旧错误没了」问的是一件"
                           + "从来没发生过的事，这条测试当场变成空转")
        XCTAssertNotNil(app.settingsError, "失败了却没有留下给用户看的说明（铁律 7）")

        // 障碍拿掉：`StateStore.mutate` 会自己 `createIfNeeded()` 把目录建起来。
        try FileManager.default.removeItem(at: root)

        XCTAssertTrue(app.setWeeklyGoal(4), "目录已经修好了，这一次该存得下来")
        XCTAssertEqual(try StateStore(directory: DataDirectory(root: root)).load()
            .settings.weeklyGoal, 4,
                       "返回了 true，磁盘上却不是新目标——那是最坏的一种静默失败")
        XCTAssertNil(app.settingsError,
                     "这一次存成功了，上一次那条错误却还挂着。面板本身照样会关"
                         + "（`WeeklyGoalSheet.save()` 只看返回值），"
                         + "但用户下次打开「每周训练目标」时，顶上会摆着一条"
                         + "「这次没能存下来」——说的是一件早就修好的事，"
                         + "他会以为刚改的目标又没存上，然后再改一遍。")
    }
}

// MARK: - 面板本身：八条验收要求，之前一条视图层测试都没有
//
// **这一组补的是和上一个提交（5f09fb7「首页四格补上视图层测试」）同一类的窟窿。**
// `WeeklyGoalSheet.swift` 新写了约 110 行视图代码、八条「必须做到」的验收要求，
// 却没有任何一条测试扫得到它——`WeeklyGoalEntryPointTests` 扫的是 `RootView.swift`
// 和 `Today/TodayView.swift`，`RenderReachabilitySweepTests` 只问「成员从 body 走不走得到」。
// 实测把下面四处**同时**改掉，1171 条一条不红：
//
// - 验收 5「写盘失败就不许关面板」：`guard app.setWeeklyGoal(draft) else { return }`
//   换成 `_ = app.setWeeklyGoal(draft)` → 存不下来也照关，用户以为改好了，
//   下次打开发现又变回去，而且永远不知道为什么（铁律 7 点名的那一种）；
// - 验收 5「错误全文显示 + 可选中」：`Text(message)` 换成 `Text("操作失败")`
//   并去掉 `.textSelection(.enabled)` → 一条没有「下一步」的文案，铁律 6 明令不合格，
//   而且系统给的原始报错再也复制不走；
// - 验收 7「打开时 Stepper 初值取当前目标」：`State(initialValue: 5)` →
//   用户把目标定成 12，打开面板显示 5，随手一按「保存」就把 12 改成了 5；
// - 验收 2「等宽数字」：删掉 Stepper 标签那一行的 `.monospacedDigit()` →
//   从 9 调到 10 时那一行横向抖一下（DESIGN-SYSTEM 第 6 节最后一条）。
//
// 边界与本项目其余视图层测试一致（见 `TodayViewTests` 开头）：扫源码不执行代码，
// 「调用还在但条件永远为假」拦不住，排版好不好看归人工验收。
final class WeeklyGoalSheetTests: XCTestCase {

    // MARK: - 验收 5：存不下来就不许关面板

    /// 关掉面板等于告诉用户「改好了」。`setWeeklyGoal` 的返回值必须真的挡住那一步——
    /// 把返回值丢掉（`_ = app.setWeeklyGoal(draft)`）编得过、跑得动，只是失败时也照关。
    func testSavingClosesThePanelOnlyWhenTheGoalActuallyReachedTheDisk() throws {
        let save = try SourceGuard.functionBody(named: "save", in: try Self.sheetCode())

        XCTAssertTrue(
            save.contains("app.setWeeklyGoal(draft)"),
            "「保存」没有把面板里正在编辑的那个值（`draft`）交给 `AppState.setWeeklyGoal`。"
                + "下一步：确认写盘走的是 `app.setWeeklyGoal(draft)`——"
                + "存别的值等于用户改了 A、存进去 B。实际取到的是：\n\(save)")

        let gated = save.contains("guard app.setWeeklyGoal(draft)")
            || save.contains("if app.setWeeklyGoal(draft)")
        XCTAssertTrue(
            gated,
            "`setWeeklyGoal` 的返回值没有挡住关面板那一步（找不到 `guard app.setWeeklyGoal(draft)` "
                + "或 `if app.setWeeklyGoal(draft)`）。写盘失败也照关的话，用户以为目标改好了，"
                + "下次打开发现又变回去，而且永远不知道为什么——铁律 7 点名的那种静默失败，"
                + "而验收要求第 5 条原话是「面板不关闭」。"
                + "下一步：写回 `guard app.setWeeklyGoal(draft) else { return }`；"
                + "换一种同样能挡住的写法，就同步改这条测试。实际取到的是：\n\(save)")

        XCTAssertTrue(
            save.contains("isPresented = false"),
            "存成功了面板也不关，用户点完「保存」什么都没发生，只会再点几下"
                + "（每点一次就多写一次盘）。实际取到的是：\n\(save)")
    }

    // MARK: - 验收 5 的另一半：失败时错误全文摆在面板上，而且复制得走

    func testTheFailureIsShownInFullAndCanBeCopied() throws {
        let code = try Self.sheetCode()

        XCTAssertTrue(
            code.contains("app.settingsError"),
            "面板压根没读 `app.settingsError`，写盘失败时它一个字都不显示——"
                + "用户只看到面板不肯关，却不知道为什么（铁律 7）。实际扫的是 "
                + Self.viewRelativePath)
        SourceGuard.assertRenders(
            "failureCard", inBodyOf: "var body: some View", of: Self.viewRelativePath,
            because: "失败说明写好了却没摆进 `body`，面板上是一片空白。")

        let card = try SourceGuard.memberBody(of: "private func failureCard", in: code)
        XCTAssertTrue(
            card.contains("Text(message)"),
            "失败说明没有原样显示出来。`AppState.setWeeklyGoal` 给的那句话里带着系统的原始报错"
                + "和「下一步确认数据目录可写」，换成一句自拟的「操作失败」就是铁律 6 明令不合格的"
                + "那一种——用户读完不知道该做什么。实际取到的是：\n\(card)")
        XCTAssertTrue(
            card.contains(".textSelection(.enabled)"),
            "失败说明选不中。里面那段系统原始报错是用户去搜、去问、去贴给别人的唯一线索，"
                + "不让复制等于让他照着屏幕手抄。实际取到的是：\n\(card)")
        XCTAssertTrue(
            card.contains(".fixedSize(horizontal: false, vertical: true)"),
            "失败说明没有允许换行，长句会被截成一行「每周训练目标没能存下来：The file …」，"
                + "而「下一步」正好在被截掉的后半截（验收要求第 5 条：**全文**显示）。"
                + "实际取到的是：\n\(card)")
        XCTAssertFalse(
            card.contains(".lineLimit("),
            "失败说明加了行数限制，等于把「下一步」那半句藏起来。实际取到的是：\n\(card)")
    }

    // MARK: - 验收 7：打开面板时显示的是用户现在的目标

    func testTheStepperOpensOnTheGoalTheUserActuallyHasAndCannotLeaveTheSavedRange() throws {
        let code = try Self.sheetCode()

        let initializer = try SourceGuard.memberBody(of: "public init(app: AppState", in: code)
        XCTAssertTrue(
            initializer.contains("State(initialValue: app.state.settings.weeklyGoal)"),
            "Stepper 的初值不是当前已保存的目标。写死一个数字的话，用户把目标定成 12、"
                + "打开面板看到的却是那个写死的数——他随手一按「保存」就把 12 改没了，"
                + "而且会以为「上次那 12 根本没存上」（验收要求第 7 条）。"
                + "实际取到的是：\n\(initializer)")

        let goalCard = try SourceGuard.memberBody(of: "private var goalCard", in: code)
        XCTAssertTrue(
            goalCard.contains("in: WeeklyGoalEditor.range"),
            "Stepper 的范围不是 `WeeklyGoalEditor.range`。另写一个范围的话，"
                + "`testRangeMatchesTheSettingsModel` 那条「界面范围 = 落盘归一范围」当场退化成"
                + "在测一段没人用的常量——界面让你选 30、存下去变成 5，用户会以为设置没生效。"
                + "实际取到的是：\n\(goalCard)")
    }

    // MARK: - 验收 2：那一行数字不许抖

    func testTheGoalLineShowsTheDraftInMonospacedDigits() throws {
        let goalCard = try SourceGuard.memberBody(of: "private var goalCard", in: try Self.sheetCode())
        let stepperLabel = try SourceGuard.memberBody(of: "Stepper(", in: goalCard)

        XCTAssertTrue(
            stepperLabel.contains("WeeklyGoalEditor.label(for: draft)"),
            "Stepper 那一行显示的不是正在编辑的 `draft`。显示已保存的那个值的话，"
                + "按加号数字纹丝不动，用户会以为这个 Stepper 是坏的。实际取到的是：\n\(stepperLabel)")
        XCTAssertTrue(
            stepperLabel.contains(".monospacedDigit()"),
            "Stepper 那一行的数字没用等宽数字：从「每周练 9 次」按到「每周练 10 次」时整行会横向"
                + "抖一下，而这恰恰是用户唯一会反复来回按的地方"
                + "（DESIGN-SYSTEM 第 1 节与第 6 节最后一条，本阶段完成标准也单列了一条）。"
                + "实际取到的是：\n\(stepperLabel)")
    }

    // MARK: - 验收 3：面板里的「本周练了几次」必须和首页那一格是同一个数

    func testTheHintCountsTheWeekTheSameWayTheHomePageDoes() throws {
        let code = try Self.sheetCode()

        let goalCard = try SourceGuard.memberBody(of: "private var goalCard", in: code)
        XCTAssertTrue(
            goalCard.contains("WeeklyGoalEditor.hint(done: weeklyDone, goal: draft)"),
            "面板上没有那句「现在什么情况 + 下一步做什么」（铁律 6），"
                + "或者它算的不是「本周已练 `weeklyDone` 次、目标是正在编辑的 `draft`」。"
                + "拿已保存的目标去算的话，用户把目标从 5 拖到 12，那句话还在说「离目标还差 3 次」。"
                + "实际取到的是：\n\(goalCard)")

        let weeklyDone = try SourceGuard.memberBody(of: "private var weeklyDone", in: code)
        XCTAssertTrue(
            weeklyDone.contains("TodayViewModel(state: app.state).weekProgress.done"),
            "「本周练了几次」不是从 `TodayViewModel.weekProgress` 来的。面板里另算一份的话，"
                + "首页那一格说「本周 2/5」、面板里说「本周已经练了 3 次」，"
                + "用户没有任何办法知道哪个是真的，而只有视图模型那一处有测试守着。"
                + "实际取到的是：\n\(weeklyDone)")
    }

    // MARK: - 验收 6：「取消」一个字都不写盘

    func testCancelClosesWithoutWritingAnything() throws {
        let actions = try SourceGuard.memberBody(of: "private var actions",
                                                 in: try Self.sheetCode())

        XCTAssertTrue(
            actions.contains("Button(\"取消\")"),
            "面板上没有「取消」。改了一半又不想改的人只能按 Esc 猜，"
                + "或者被迫存一个他并不想要的数（验收要求第 6 条）。实际取到的是：\n\(actions)")
        XCTAssertTrue(
            actions.contains("Button(\"保存\")") && actions.contains("save()"),
            "面板上没有「保存」，或者它没接上 `save()`——按钮点了什么都不发生，"
                + "是本项目最不能接受的那一类。实际取到的是：\n\(actions)")
        XCTAssertEqual(
            SourceGuard.occurrences(of: "setWeeklyGoal", in: actions), 0,
            "两颗按钮那一段里直接出现了 `setWeeklyGoal`。「取消」必须一个字都不写盘，"
                + "而「保存」该走 `save()`——那儿才有「失败就不关面板」那道闸。"
                + "实际取到的是：\n\(actions)")
    }

    // MARK: - 整个面板不许出现分数、评级、水平判断

    /// `testNoScorePredictionInTheSettingsCopy` 扫的是 `WeeklyGoalEditor` 给出的那几句话，
    /// 而面板里还有一批**硬写在视图里**的中文（标题、那句「改它不会动到任何已经练过的记录」、
    /// 失败卡片的抬头），它们不归那条测试管——顺手在标题下面写一句
    /// 「每周练 5 次，大概三个月能到 6.5 分」，那边照样全绿。做法与
    /// `TodayViewTests.testThisPageNeverPredictsABandScore` 一致。
    func testThisPanelNeverPredictsABandScore() throws {
        let code = try Self.sheetCode()
        XCTAssertTrue(
            code.contains("struct WeeklyGoalSheet"),
            "没扫到 WeeklyGoalSheet 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)
        for banned in ["band", "Band", "BAND", "score", "Score",
                       "分数", "评分", "打分", "得分", "几分", "水平分", "评级", "水平判断", "预测"] {
            XCTAssertFalse(
                code.contains(banned),
                "每周训练目标面板里出现了「\(banned)」。本阶段不得出现任何形式的雅思分数预测或"
                    + "水平判断（DEFINITION-OF-DONE 第 4 节）——而「每周练几次能到几分」"
                    + "这种话在设置目标的地方最容易被顺手写上。"
                    + "下一步：改成只说「练了几次、离目标还差几次」。")
        }
    }

    // MARK: - 扫源码用的小工具

    static let viewRelativePath = "Settings/WeeklyGoalSheet.swift"

    /// 注释里必然要解释「为什么这么写」，连注释一起扫的话这些测试会被自己的说明绊倒。
    /// 走 `SourceGuard`：文件挪了位置或改了名会**抛错**，而不是拿一段空串继续跑。
    static func sheetCode() throws -> String { try SourceGuard.code(viewRelativePath) }
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
