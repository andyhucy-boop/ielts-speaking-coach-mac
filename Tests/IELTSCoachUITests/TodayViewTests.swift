import Foundation
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

/// 今日训练页上那几件**没法靠数据断言守住、但决定用户看不看得见**的事。
///
/// 扫源码这条路的边界要说清，边界是实测出来的，不是估计的：
/// - 拦得住的是真实的退化形态——按钮体被掏空、显示那段被删掉、写好的组件没摆进页面、
///   分支被整段拿掉。这几种都真去改了代码、真看到这里变红。
/// - 拦不住的是「代码还在但跑不到」，比如把条件改成 `if let x, false`：
///   扫源码不执行代码，也就判断不了条件的真假（实测这一种确实溜过去了）。
///   要拦这一种得把界面真的渲染出来（ViewInspector / 快照测试），本项目还没有那套工具。
/// - 画出来好不好看、位置对不对同样不在这里，归 Task 11 人工验收。
///
/// 但「用户看不看得见」不是版面观感，它决定这一页有没有做到计划要求的事。
final class TodayViewTests: XCTestCase {

    // MARK: - 「开始练习」必须真的开练（本阶段的交付物）

    /// **这一条就是 Task 9 的交付判据。**
    ///
    /// 上一版的「开始练习」弹出来的是一张写着 `swift run coach practice <id>` 的卡片，
    /// 让用户自己去开终端——直接违反成品标准第 2 条「全程不需要打开终端」。
    /// 把驱动接进按钮之后，这一页里就不该再有任何一句「去终端敲命令」。
    func testTheStartButtonActuallyLaunchesAPracticeInsteadOfSendingTheUserToATerminal() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("PracticeSheet("),
            "「开始练习」没有弹出 PracticeSheet，也就没有把 ChatGPT 驱动接进界面。"
                + "下一步：按钮改成弹 `PracticeSheet` 并由它调 `runner.start(setup:)`。")

        for forbidden in ["终端", "命令行", "swift run coach"] {
            XCTAssertFalse(
                code.contains(forbidden),
                "今日训练页里还留着「\(forbidden)」。这一页现在能直接开练了，"
                    + "再把用户支去命令行，就是给他一条比按钮更麻烦、而且已经不必要的路"
                    + "（成品标准第 2 条）。下一步：把那段文案删掉或改写。")
        }
    }

    /// 一场练习的设置（哪道题、哪个 Part、带什么目标、什么时候给反馈、Part 2 怎么准备）
    /// 必须来自 `PracticeRouteResolver`，而不是在视图里现拼。
    ///
    /// **Task 10 把这里从 `TodayViewModel.practiceSetup` 换成了解析器**，不是换个花样：
    /// `TodayViewModel.practiceSetup` 只填 Part、时长、目标三样，`feedbackTiming` 与
    /// `part2PrepMode` 走的是 `SessionSetup` 的参数默认值——也就是说用户在学习计划页
    /// 把「反馈时机」改成「当场点出」之后，从这一页开的每一场仍然是全程零反馈，
    /// 而界面上一个字都不会提。解析器从 `RouteDefaults(settings:)` 取这两项，
    /// 27 条 `PracticeRouteResolverTests` 守着它。
    func testTheSetupHandedToTheRunnerComesFromTheResolver() throws {
        let code = try Self.todayViewCode()
        XCTAssertTrue(
            code.contains("PracticeRouteResolver.resolve("),
            "这一页没有把「练哪道题、按什么设置练」交给 `PracticeRouteResolver.resolve(…)`。"
                + "下一步：每一条路线的点击都走解析器，那样用户设的反馈时机与 Part 2 准备方式"
                + "才会真的进到这一场里。")
        XCTAssertFalse(
            code.contains("SessionSetup("),
            "视图自己拼了 `SessionSetup`。视图里拼的那一份没有任何测试管得住，"
                + "而且一定会漏掉 `feedbackTiming` / `part2PrepMode`——用户改了练习偏好，"
                + "从这一页开的练习照旧，界面上还什么都不说。"
                + "下一步：改成用 `PracticeRouteResolver.resolve(…)` 返回的那一份。")
        XCTAssertFalse(
            code.contains("model.practiceSetup("),
            "这一页还在用 `TodayViewModel.practiceSetup(question:route:)`。它不带 "
                + "`feedbackTiming` / `part2PrepMode`，用户在学习计划页设的练习偏好会被静默丢掉。"
                + "下一步：改成 `PracticeRouteResolver.resolve(…)`。")
    }

    // MARK: - 四条路线：显示出来的每一条，点下去一定能开练（Task 10）

    /// **这一条是 Task 10 的交付判据。**
    ///
    /// Phase 3 的 `TodayViewModel.availableRoutes` 判的是「前提成立」——有计划、有记录、
    /// 有没退休的目标。而前提成立不等于开得了练：计划里今天那道题可能已经被换季导入删掉、
    /// 复训目标的来源记录可能被单条删过、上次那道题可能已经不在题库里。
    /// 那几种情况下卡片照样显示，点下去什么也不发生——用户会以为程序坏了，
    /// 而这一页是他每天打开的第一眼。
    ///
    /// `PracticeRouteResolver.availableRoutes` 用的是**解析同一条路线的那段代码**，
    /// `PracticeRouteResolverTests.testEveryShownRouteCanActuallyStart` 钉着这条不变量。
    func testTheRouteListComesFromTheResolverNotFromThePhase3Preconditions() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("PracticeRouteResolver.availableRoutes("),
            "路线列表不是从 `PracticeRouteResolver.availableRoutes(state:preferring:defaults:)` 来的。"
                + "下一步：换成解析器——只有它能保证「显示出来的每一条都点得动」。")
        XCTAssertFalse(
            code.contains("model.availableRoutes"),
            "这一页还在用 Phase 3 的 `TodayViewModel.availableRoutes` 排路线。那只判「前提成立」，"
                + "而前提成立不等于开得了练（今天那道题可能已被换季导入删掉、复训目标的来源记录"
                + "可能被删过）。显示一条点了没用的路线，比不显示更糟。"
                + "下一步：全部改走 `PracticeRouteResolver.availableRoutes(…)`。")
        XCTAssertTrue(
            code.contains("PracticeRoutePreference.route(fromSettings:"),
            "默认路线不是从设置里读的，那用户在学习计划页选的「默认练习路线」就白设了——"
                + "他改完之后这一页的卡片顺序纹丝不动，也没有任何解释。"
                + "下一步：用 `PracticeRoutePreference.route(fromSettings: app.state.settings.defaultRoute)`。")
        XCTAssertTrue(
            code.contains("RouteDefaults(settings:"),
            "解析路线时没有把用户的练习偏好传进去。那样「当场点出」「自己决定什么时候开口」"
                + "这两项设置对这一页开的每一场都不生效，而界面上什么都不说。"
                + "下一步：传 `RouteDefaults(settings: app.state.settings)`。")
    }

    /// 每一条路线的点击都得先解析一次，两种结果各有各的去处。
    ///
    /// 只处理 `.ready` 而把 `.unavailable` 丢掉的话，那句写好的中文（发生了什么 +
    /// 下一步做什么）一个字都不上屏，用户点下去界面纹丝不动——本项目最不能接受的那一类。
    func testEveryCardResolvesFirstAndBothOutcomesGoSomewhere() throws {
        let act = try SourceGuard.memberBody(of: "private func act", in: try Self.todayViewCode())
        for (needle, why) in [
            ("PracticeRouteResolver.resolve(", "先解析一次"),
            ("case .ready", "解析成功时开练"),
            ("case .unavailable", "解析不成功时把那句中文说明留在界面上")
        ] {
            XCTAssertTrue(act.contains(needle),
                          "点一张路线卡片之后没有\(why)（`\(needle)`）。实际取到的是：\n\(act)")
        }
    }

    /// **`.unavailable` 那段文字必须留在卡片下面，不能一闪而过。**
    ///
    /// 那段文字本身写的就是下一步该做什么（「到「学习计划」页重新生成计划，
    /// 已经练过的进度不会丢」这种）。一闪就没了等于没说，而用户这时候正想开练。
    func testTheUnavailableMessageStaysUnderTheCardInsteadOfFlashingBy() throws {
        let code = try Self.todayViewCode()

        // 存进 `@State`：存不下来的话，下一次重绘就没了。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: "blockedRoutes", in: code), 3,
            "「这条路线为什么开不了」没有被记在页面状态里（至少要有：声明一次、写入一次、读出来画一次）。"
                + "下一步：用一个 `@State` 按路线记着那句说明，并把它画在那张卡片下面。")

        SourceGuard.assertRenders(
            "blockedNotice", inBodyOf: "private func routeBlock", of: Self.viewRelativePath,
            because: "那句「这条路线现在开不了、下一步做什么」写好了却没摆在卡片下面，"
                + "用户点完之后界面上什么都不会变。")

        let notice = try SourceGuard.memberBody(of: "private func blockedNotice", in: code)
        XCTAssertTrue(
            notice.contains("blockedRoutes["),
            "那块提示画的不是刚才解析出来的那句话。实际取到的是：\n\(notice)")

        for transient in ["asyncAfter", "Task.sleep", "withAnimation(.easeIn"] {
            XCTAssertFalse(
                code.contains(transient),
                "这一页出现了「\(transient)」，多半是给那句说明加了自动消失。"
                    + "那段文字写的就是下一步该做什么，一闪就没了等于没说。"
                    + "下一步：让它一直留在卡片下面，直到这条路线真的能开练。")
        }
    }

    /// 「按计划练今天」这张卡片要说清**今天是第几天**、今天有哪几道题、哪几道已经练过了。
    ///
    /// 只列题目不打勾的话，一天两题练完一题回来看，卡片和练之前一模一样——
    /// 用户不知道自己练过了没有，只能再点一次。
    func testThePlanTodayCardShowsWhichDayItIsAndTicksOffWhatIsAlreadyDone() throws {
        let code = try Self.todayViewCode()
        let detail = try SourceGuard.memberBody(of: "private var planTodayDetail", in: code)
        XCTAssertTrue(
            detail.contains("day.id"),
            "卡片上没写今天是第几天。计划页说「第 5 天」，这一页什么都不说，"
                + "用户没法把两页对上。实际取到的是：\n\(detail)")
        XCTAssertTrue(
            detail.contains("planQuestionRow("),
            "今天的题目一道都没画出来，这张卡片上只剩一个动词。实际取到的是：\n\(detail)")

        let row = try SourceGuard.memberBody(of: "private func planQuestionRow", in: code)
        XCTAssertTrue(
            row.contains("isCompleted"),
            "题目行不分「练过的」和「没练的」。一天两题练完一题回来看，卡片和练之前一模一样，"
                + "用户只能再点一次。实际取到的是：\n\(row)")
        XCTAssertTrue(
            row.contains("checkmark"),
            "已经练过的那几道没有打勾（图标只用 SF Symbols，不用 emoji）。实际取到的是：\n\(row)")
        XCTAssertTrue(
            row.contains("act(.planToday"),
            "点某一道题不会去练那一道。计划里一天排两题，用户想先练第二道就没有任何办法。"
                + "实际取到的是：\n\(row)")
        XCTAssertTrue(
            row.contains("item.id"),
            "点题目时没有把那道题的 id 传给解析器，点哪一道都练同一道。实际取到的是：\n\(row)")
    }

    /// 「继续上次练习」得说清上次练的是哪道题、什么时候练的、上次盯的是什么目标。
    ///
    /// 上次的目标尤其不能省：这条路线的意思就是接着上次那件事再练一遍，
    /// 目标不显示的话，它和「随便再练一道」在用户眼里没有区别。
    func testTheContinueLastCardShowsTheQuestionTheTimeAndLastTimesGoal() throws {
        let detail = try SourceGuard.memberBody(of: "private var continueLastDetail",
                                                in: try Self.todayViewCode())
        for (needle, why) in [
            ("recentSessions.first", "上次那一场（顺序由 `TodayViewModel.recentSessions` 定，这一页不另排）"),
            ("topic", "那道题的话题"),
            ("dateText(", "上次是什么时候练的"),
            (".goal", "上次盯的那个单点目标——没有它，这条路线和随便再练一道没区别")
        ] {
            XCTAssertTrue(detail.contains(needle),
                          "「继续上次练习」卡片上没有\(why)（`\(needle)`）。实际取到的是：\n\(detail)")
        }
    }

    /// **复训卡片必须显示真正会发给考官的那段目标原文。**
    ///
    /// 用户得在开练之前就知道自己这一场要盯着哪件事——不显示的话，
    /// 这条路线和普通练习在他眼里没有区别（计划 Task 10 Step 3 原话）。
    ///
    /// 而且**必须取解析器给出的 `setup.goal`，不能取 `TodayViewModel.liveTarget?.label`**：
    /// 那两个挑的不是同一个目标（一个是「最后记下的」，一个是
    /// `RetrainingPolicy.rank` 排第一的），而且 label 为空时解析器会回落成 targetKey。
    /// 取错了，屏幕上写的和提示词里发的就是两码事。
    func testTheRetrainCardShowsTheGoalThatWillActuallyBeSent() throws {
        let code = try Self.todayViewCode()
        let detail = try SourceGuard.memberBody(of: "private var retrainDetail", in: code)
        XCTAssertTrue(
            detail.contains("setup.goal"),
            "复训卡片上没有这一场真正要盯的目标原文。用户开练之前不知道自己要改什么，"
                + "这条路线就退化成了「再练一道题」。实际取到的是：\n\(detail)")
        XCTAssertFalse(
            detail.contains("liveTarget"),
            "复训卡片显示的是 `TodayViewModel.liveTarget`（最后记下的那个目标），"
                + "而解析器练的是 `RetrainingPolicy.rank` 排第一的那个——两者常常不是同一个。"
                + "屏幕上写一句、提示词里发另一句，是本项目最危险的那种失败。"
                + "实际取到的是：\n\(detail)")
        XCTAssertTrue(
            detail.contains("retrainOrigin"),
            "卡片没说这个目标是哪一次练习提出来的。同一个毛病可能被点名过好几次，"
                + "不说出处，用户没法回去看当时的复盘。实际取到的是：\n\(detail)")
    }

    /// 「从题库自由选题」得先说清题库里有多少题，否则这张卡片上只有一个动词。
    func testTheFreePickCardSaysHowManyQuestionsTheBankHas() throws {
        let detail = try SourceGuard.memberBody(of: "private var freePickDetail",
                                                in: try Self.todayViewCode())
        XCTAssertTrue(
            detail.contains("app.state.questions.count"),
            "「从题库自由选题」卡片没说题库里有多少题。实际取到的是：\n\(detail)")
        XCTAssertTrue(
            detail.contains(".monospacedDigit()"),
            "题数没用等宽数字：导完一批题从「12」跳到「120」时这一行会横向抖"
                + "（DESIGN-SYSTEM 第 6 节最后一条）。实际取到的是：\n\(detail)")
    }

    /// **整页只有一个主行动**（DESIGN-SYSTEM 第 4 节）：排在第一位的那条路线。
    /// 两个同样醒目的紫色大块会让人不知道该点哪个。
    func testOnlyTheFirstRouteIsThePagesSinglePrimaryAction() throws {
        let code = try Self.todayViewCode()
        XCTAssertEqual(
            SourceGuard.occurrences(of: "PrimaryActionCard(", in: code), 1,
            "这一页构造了不止一处 `PrimaryActionCard`。规范第 4 节：每页最多一个主行动，"
                + "两块同样醒目的紫色会让人不知道该点哪个。")
        let block = try SourceGuard.memberBody(of: "private func routeBlock", in: code)
        for needle in ["isPrimary", "primaryCard(", "secondaryCard("] {
            XCTAssertTrue(block.contains(needle),
                          "路线卡片没有分出「第一张是主行动、其余次一级」（`\(needle)`）。"
                              + "实际取到的是：\n\(block)")
        }
        let section = try SourceGuard.memberBody(of: "private var routes", in: code)
        XCTAssertTrue(
            section.contains("index == 0"),
            "「哪一张是主行动」不是按顺序第一张定的。卡片顺序由 `availableRoutes` 决定"
                + "（默认路线在最前），主行动必须跟着它走。实际取到的是：\n\(section)")
    }

    /// 一条路线都排不出来时不许留白。三样一个不少：说明现状、说明下一步、一颗能直接点的按钮。
    func testWhenNoRouteCanStartThePageStillSaysWhatToDoNext() throws {
        let code = try Self.todayViewCode()
        SourceGuard.assertRenders(
            "noRouteCard", inBodyOf: "private var routes", of: Self.viewRelativePath,
            because: "一条路线都排不出来时这一段是一片空白，用户会以为程序坏了。")
        let card = try SourceGuard.memberBody(of: "private var noRouteCard", in: code)
        XCTAssertTrue(card.contains("下一步"),
                      "空状态没说下一步该干什么（铁律 6）。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("onGo(.plan)"),
                      "空状态那颗按钮没有把用户送到「学习计划」页——那正是排不出路线时"
                          + "唯一能做的事（生成一份计划）。实际取到的是：\n\(card)")
    }

    // MARK: - 题库空时，整页只做「去导入」这一件事

    /// 这个分支一度是这一页的头等大事，却没有任何测试钉住：整段删掉、无条件渲染
    /// `routes` + `recentPractice`，`swift test` 全绿。
    ///
    /// 删掉之后用户看到的是：`noRouteCard` 那句「题库里有 0 道题，但四条路线的前提一条都不成立。
    /// 下一步：到「训练题库」看一眼题库是不是正常，若不正常就重新导入一次」——
    /// 对一个刚装好、还没导过题库的人来说，这句话是在说他的题库坏了。
    func testEmptyBankTakesOverTheWholePageInsteadOfShowingRoutes() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("if app.state.questions.isEmpty {"),
            "题库空时整页不再单独走一条分支。用户会看到「题库里有 0 道题，但四条路线的前提"
                + "一条都不成立」——那句话是给「题库坏了」准备的，而他只是还没导入过。"
                + "下一步：把 `if app.state.questions.isEmpty { emptyBank } else { … }` 加回来；"
                + "换一种同样能只显示导入引导的写法，就同步改这条测试。")

        // 声明一次、用一次。只数「出现过」的话，把分支里那句 `emptyBank` 删掉、
        // 只留下面那个 `private var emptyBank` 的声明，这条断言照样绿。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: "emptyBank", in: code), 2,
            "emptyBank 只在源码里出现了一次，也就是光有声明、没人用它——题库空时画出来的是别的东西。"
                + "下一步：确认题库空的那一支显示的确实是那张导入引导。")
    }

    // MARK: - 训练记录这一版还没接上，这件事要说出来

    /// 「本周训练 N/5」和「最近练习」在当前工程里永远不会动：
    /// 全工程没有任何一行往 `CoachState.sessions` 里写东西（接线归 Phase 4，
    /// `TodayViewModelTests.testPracticeRecordingFlagMatchesWhetherAnyCodeWritesSessions`
    /// 扫源码钉着这个事实）。不说这句话，用户练完回到这一页看到的还是 0 次、
    /// 还是「还没有练习记录」，只会以为程序坏了。
    func testThePageSaysPracticeIsNotRecordedYet() throws {
        let code = try Self.todayViewCode()

        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)

        XCTAssertTrue(
            code.contains("TodayViewModel.unwiredRecordingNotice("),
            "页面没有交代「训练记录还没接上」。用户在这一页练完一整场，"
                + "回来看到的还是「0/5 次」「还没有练习记录」，会以为程序坏了。"
                + "下一步：把 `TodayViewModel.unwiredRecordingNotice()` 画到页面上"
                + "（记录接上之后它返回 nil，那块交代自己就消失了）。")

        // 同上：光有 `private var recordingNotice` 的声明不算数，页面 body 里得真的摆上它。
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: "recordingNotice", in: code), 2,
            "recordingNotice 只在源码里出现了一次，也就是写好了却没摆进页面，用户一个字也看不到。"
                + "下一步：把它放回 body 里（本周进度与「最近练习」之间）。")

        XCTAssertTrue(
            code.contains("TodayViewModel.practiceRecordingIsWired"),
            "「还没有练习记录」那张卡片还在无条件承诺「练完第一场之后，这里会按时间倒序列出最近五次」，"
                + "而这一版练完它也不会变——同一屏上两条互相矛盾的话，用户会照着做不到的那条去做。"
                + "本项目在权限页上已经吃过一次同屏矛盾指令的亏。"
                + "下一步：让那句话跟着 `TodayViewModel.practiceRecordingIsWired` 走，"
                + "记录接上之后再恢复原来的说法。")
    }

    // MARK: - 四格：数字和脚注都得真的画出来
    //
    // 这一组补的是 Task 8 的窟窿。原来这一页新写了约 130 行视图代码、五条「必须做到」的
    // 验收要求，一条视图层测试都没有，实测三个突变全部全绿（1148/1148）：
    //
    // - 删掉 `Text(tile.footnote)` → 四格脚注全消失，而脚注是首页上唯一写着
    //   「下一步做什么」的地方（铁律 6），计划里那条验收原话是
    //   「**不允许因为「太长了不好看」就不显示**」；
    // - 删掉 `Text(tile.value)` → 四个数字全不显示，只剩四个标题和四段脚注；
    // - 把「查看全部问题」的 `onGo(.issues)` 改成 `onGo(.reviewReports)` → 按钮跑到复盘报告页。
    //
    // `RenderReachabilitySweepTests` 拦得住「整个成员被删掉」，拦不住成员**内容**被改坏——
    // 上面三个突变里成员都还在，所以它一声不吭。

    /// 四格的内容必须一格不落地来自 `TodayViewModel.statTiles`：
    /// 视图里现拼一份的话，`HomeStatsTests` 那 12 条（含「绝不预测分数」那条红线）
    /// 当场退化成在测一段没人用的实现。
    func testTheFourTilesComeFromTheViewModelAndAreOnScreen() throws {
        let code = try Self.todayViewCode()
        let row = try SourceGuard.memberBody(of: "private var statsRow", in: code)

        XCTAssertTrue(
            row.contains("model.statTiles"),
            "四格不是从 `TodayViewModel.statTiles` 来的。视图里另拼一份的话，"
                + "`HomeStatsTests` 那一整组（包括「绝不预测分数」那条红线）就在测一段"
                + "没人用的实现。实际取到的是：\n\(row)")
        XCTAssertTrue(
            row.contains("statCard(tile)"),
            "遍历了四格却没有把每一格画出来，这一行只剩一块空白。实际取到的是：\n\(row)")
        SourceGuard.assertRenders(
            "statsRow", inBodyOf: "var body: some View", of: Self.viewRelativePath,
            because: "四格写好了却没摆进 `body`，用户一个数字都看不到。")
    }

    /// 一格里那四样缺一不可。**尤其是 `footnote`**——它是这一格里唯一说清
    /// 「下一步做什么」的地方（铁律 6），计划验收第 1 条特意写了
    /// 「不允许因为「太长了不好看」就不显示」。
    func testEveryTileShowsItsNumberItsUnitItsCaptionAndItsFootnote() throws {
        let card = try SourceGuard.memberBody(of: "private func statCard", in: try Self.todayViewCode())
        for (needle, why) in [
            ("Text(tile.value)", "这一格的数字。少了它，四张卡片上只剩标题和脚注，"
                + "「本周训练」到底练了几次一个字都看不到"),
            ("Text(tile.unit)", "单位。光一个「42」用户不知道是分钟还是次"),
            ("Text(tile.caption)", "这一格是什么。没有标题的数字没人看得懂"),
            ("Text(tile.footnote)", "脚注。它是这一格里唯一写着「下一步做什么」的地方（铁律 6），"
                + "计划验收第 1 条明写「不允许因为「太长了不好看」就不显示」")
        ] {
            XCTAssertTrue(card.contains(needle),
                          "四格里没有\(why)（`\(needle)`）。实际取到的是：\n\(card)")
        }
        XCTAssertTrue(
            card.contains(".monospacedDigit()"),
            "这一格的数字没用等宽数字：「3/5」跳到「10/5」、「9」跳到「10」时整行会横向抖一下"
                + "（DESIGN-SYSTEM 第 6 节最后一条）。实际取到的是：\n\(card)")
        XCTAssertTrue(
            card.contains("CoachCard"),
            "四格没走 `CoachCard`，会散在页面上没有边界（计划验收第 1 条）。"
                + "实际取到的是：\n\(card)")
    }

    /// 「本周训练」那一格里的进度条得跟着设置里的目标走，不是写死的 5。
    /// 认这一格靠 `StatTile.weekID`——两处各写一个 `"week"` 字面量的话，
    /// 改了一处另一处会安静地不再匹配，进度条就此消失。
    func testTheWeeklyProgressBarSitsInTheWeekTileAndFollowsTheConfiguredGoal() throws {
        let code = try Self.todayViewCode()
        let card = try SourceGuard.memberBody(of: "private func statCard", in: code)
        XCTAssertTrue(
            card.contains("StatTile.weekID"),
            "进度条没有靠 `StatTile.weekID` 认「本周训练」那一格。实际取到的是：\n\(card)")
        SourceGuard.assertRenders(
            "weekProgressBar", inBodyOf: "private func statCard", of: Self.viewRelativePath,
            because: "进度条写好了却没摆进那一格，用户只看得到「2/5」这个数字，看不到条。")
        let bar = try SourceGuard.memberBody(of: "private var weekProgressBar", in: code)
        XCTAssertTrue(
            bar.contains("model.weekProgress"),
            "进度条的目标次数不是从 `TodayViewModel.weekProgress` 来的。视图里写死 5 的话，"
                + "用户在设置里把目标改成 3，这根条还按 5 画，而「3/5」旁边写的却是 3——"
                + "他没有任何办法知道哪个是真的。实际取到的是：\n\(bar)")
    }

    // MARK: - 「你的问题正在怎么变化」

    func testTheIssueTrendSectionRendersTheRowsTheViewModelPicked() throws {
        let section = try SourceGuard.memberBody(of: "private var issueTrends",
                                                 in: try Self.todayViewCode())
        XCTAssertTrue(
            section.contains("SectionHeader(number: 4, label: \"ISSUE TRENDS\""),
            "区块标题不见了，这一段会变成几行没头没尾的句子（DESIGN-SYSTEM 第 4 节）。"
                + "实际取到的是：\n\(section)")
        XCTAssertTrue(
            section.contains("model.issueChanges"),
            "列表不是从 `TodayViewModel.issueChanges` 来的。视图里另排一份的话，"
                + "首页和问题档案页会给出两套顺序，用户不知道该信哪个，"
                + "而只有视图模型那一处有测试守着。实际取到的是：\n\(section)")
        XCTAssertTrue(
            section.contains("issueRow(row)"),
            "遍历了行却没有把每一条画出来，这一段只剩一个标题。实际取到的是：\n\(section)")
        for forbidden in ["sorted", "prefix(", "filter { "] where section.contains(forbidden) {
            XCTFail("这一段在视图里又 `\(forbidden)` 了一次。排序、截断与筛选**原样**来自"
                        + "`TodayViewModel.issueChanges`，这一页不许再来一遍——"
                        + "那会造出第二套说法，而依据只有视图模型那一处有测试守着。"
                        + "实际取到的是：\n\(section)")
        }
        SourceGuard.assertRenders(
            "issueTrends", inBodyOf: "var body: some View", of: Self.viewRelativePath,
            because: "整个「你的问题正在怎么变化」写好了却没摆进 `body`。")
    }

    /// 一条 = 一个毛病。少一样，用户就看不出「这条说的是哪个毛病、犯过几次、最近是好是坏」。
    func testEveryIssueRowShowsWhatWasSaidTheTrendAndHowOftenItHappened() throws {
        let row = try SourceGuard.memberBody(of: "private func issueRow", in: try Self.todayViewCode())
        for (field, why) in [
            ("row.learnerSaid", "当时说的那句原话——它是「这条说的是哪个毛病」的唯一依据"),
            ("row.trend.badge", "趋势那几个字。只剩一块颜色的话，色觉障碍用户什么都读不到"),
            ("row.detail", "结论背后的原始数字，用户要靠它自己核对"),
            ("row.occurrences", "一共犯过几次")
        ] {
            XCTAssertTrue(row.contains(field),
                          "一行里没有\(why)（`\(field)`）。实际取到的是：\n\(row)")
        }
        XCTAssertGreaterThanOrEqual(
            SourceGuard.occurrences(of: ".monospacedDigit()", in: row), 2,
            "行里的数字没有全部用等宽数字。「9 次」跳到「10 次」时这一列会横向抖"
                + "（DESIGN-SYSTEM 第 6 节最后一条）。实际取到的是：\n\(row)")
        XCTAssertTrue(
            row.contains("IssueArchiveView.trendColor(row.trend)"),
            "趋势的配色不是从 `IssueArchiveView.trendColor` 来的。两页各画各的话，"
                + "同一个「出现变多了」在首页和问题档案页会是两个颜色，"
                + "而只有那一处有测试守着每一档该是什么色。实际取到的是：\n\(row)")
    }

    /// **「查看全部问题」必须落到问题档案页。** 首页只放五条，剩下的全在那一页上；
    /// 指到别处去的话，用户点完到了一个跟「全部问题」无关的页面，
    /// 而他要找的那几条再也没有入口。
    func testTheSeeAllButtonGoesToTheIssueArchiveAndNowhereElse() throws {
        let section = try SourceGuard.memberBody(of: "private var issueTrends",
                                                 in: try Self.todayViewCode())
        XCTAssertTrue(
            section.contains("Button(\"查看全部问题\")"),
            "「查看全部问题」这颗按钮不见了。首页只放最要紧的五条，没有这颗按钮，"
                + "剩下的问题在这一页上就没有任何入口。实际取到的是：\n\(section)")
        XCTAssertTrue(
            section.contains("onGo(.issues)"),
            "「查看全部问题」没有切到 `.issues`。它写着「全部问题」，落到别的页面就是骗人——"
                + "而按钮点了跑到别处，是本项目最不能接受的那一类。实际取到的是：\n\(section)")
        for wrong in [".reviewReports", ".history", ".vocabulary", ".questionBank"] {
            XCTAssertFalse(
                section.contains("onGo(\(wrong))"),
                "「查看全部问题」那一段里出现了 `onGo(\(wrong))`，用户点「查看全部问题」"
                    + "会被送到另一页。实际取到的是：\n\(section)")
        }
    }

    /// 一条问题都没有时不许留白。三样一个不少：说明现状、说明下一步、一颗能直接点的按钮。
    func testTheEmptyIssueListStillSaysWhatIsGoingOnAndWhatToDoNext() throws {
        let code = try Self.todayViewCode()
        SourceGuard.assertRenders(
            "noIssueCard", inBodyOf: "private var issueTrends", of: Self.viewRelativePath,
            because: "一条问题都没有时这一段是一片空白，用户会以为这块内容坏了"
                + "（DESIGN-SYSTEM 第 4 节要求空状态给足三样）。")
        let empty = try SourceGuard.memberBody(of: "private var noIssueCard", in: code)
        XCTAssertTrue(empty.contains("还没有记录到反复出现的问题"),
                      "空状态没说清现状。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("下一步"),
                      "空状态没说下一步该干什么（铁律 6）。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("Button(\"开始练习\")"),
                      "空状态没有那颗能直接点的按钮，用户读完还得自己回上面找。"
                          + "实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("act("),
                      "空状态那颗「开始练习」点下去什么也不发生。按钮点了没反应是本项目"
                          + "最不能接受的那一类。实际取到的是：\n\(empty)")
    }

    // MARK: - 整页不许出现分数、评级、水平判断

    /// 计划 Task 8 视图验收第 4 条、DEFINITION-OF-DONE 第 4 节第一条：**不预测雅思分数。**
    ///
    /// `HomeStatsTests.testNoScorePredictionInAnyUserFacingText` 扫的是视图模型给出的文案，
    /// 而这一页上还有一批**硬写在视图里**的中文（`noIssueCard`、`noSessionCard`、
    /// `noRouteCard`、`emptyBank`、问候语），它们不归那条测试管——
    /// 顺手在空状态里写一句「练够了大概能到 6.5」，那边照样全绿。
    /// 这条补的就是这一段。做法与 `IssueArchiveViewTests.testThisPageNeverPredictsABandScore` 一致。
    func testThisPageNeverPredictsABandScore() throws {
        let code = try Self.todayViewCode()
        XCTAssertTrue(
            code.contains("struct TodayView"),
            "没扫到 TodayView 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.viewRelativePath)
        for banned in ["band", "Band", "BAND", "score", "Score",
                       "分数", "评分", "打分", "得分", "几分", "水平分", "评级", "水平判断", "预测"] {
            XCTAssertFalse(
                code.contains(banned),
                "今日训练页里出现了「\(banned)」。本阶段不得出现任何形式的雅思分数预测或"
                    + "水平判断（DEFINITION-OF-DONE 第 4 节）：给「你大概 6.5 分」这种数字"
                    + "既不准也有害，会让人盯着数字而不是盯着问题。"
                    + "下一步：改成只说「练了几次、开口多久、哪个毛病在变少」。")
        }
    }

    // MARK: - 脚注指的方向，得和按钮在页面上的真实位置对得上

    /// 四格的脚注写着「点「开始练习」」，而那颗按钮在页面上是在四格上面还是下面，
    /// 由 `body` 里两段的先后顺序决定。**指反了比不指更糟**：用户会照着往上翻，
    /// 去找一颗根本不在那儿的按钮。本项目在权限页上已经吃过一次同屏矛盾指令的亏。
    ///
    /// 期望的方向是从源码里的相对位置**推出来**的，不是写死的：以后把四格挪到
    /// 「今天练什么？」下面，这条测试会当场变红，逼人把文案一起改。
    func testTileFootnotesPointTowardWhereTheStartButtonActuallyIs() throws {
        let body = try SourceGuard.memberBody(of: "var body: some View", in: try Self.todayViewCode())

        // 锚点必须各只有一处，否则「谁在前面」只能靠猜，而猜错等于这条断言在查别的东西。
        for anchor in ["statsRow", "routes"] {
            XCTAssertEqual(
                SourceGuard.occurrences(of: anchor, in: body), 1,
                "`body` 里「\(anchor)」不是恰好出现一次，「四格在按钮上面还是下面」就没法从"
                    + "源码里读出来。下一步：改了 body 的写法，就同步改这条测试的锚点。"
                    + "实际取到的是：\n\(body)")
        }
        guard let tiles = body.range(of: "statsRow"), let button = body.range(of: "routes") else {
            return XCTFail("`body` 里找不到 `statsRow` 或 `routes`，这条测试无从判断方向。"
                               + "下一步：确认这两段还在 body 里。实际取到的是：\n\(body)")
        }
        // 「开始练习」那颗按钮由 `routes` 那一段画：`actionTitle(_:)` 对除复训以外的路线
        // 返回的就是「开始练习」，而排在第一位的那条路线（题库非空时至少有「从题库自由选题」）
        // 永远不是复训。
        let tilesComeFirst = tiles.lowerBound < button.lowerBound
        let wrongWay = tilesComeFirst ? Self.upwardWords : Self.downwardWords
        let rightWay = tilesComeFirst ? Self.downwardWords : Self.upwardWords

        var checked = 0
        var directed = 0
        for tile in TodayViewModel(state: CoachState.empty()).statTiles {
            guard let clause = Self.clause(before: "开始练习", in: tile.footnote) else { continue }
            checked += 1
            if rightWay.contains(where: clause.contains) { directed += 1 }
            for word in wrongWay {
                XCTAssertFalse(
                    clause.contains(word),
                    "「\(tile.caption)」那一格的脚注把用户指向「\(word)」，"
                        + "而「开始练习」在页面上位于四格的\(tilesComeFirst ? "下面" : "上面")"
                        + "（`body` 里 statsRow 排在 routes \(tilesComeFirst ? "前" : "后")面）。"
                        + "照着做的人会往错的方向翻，去找一颗不在那儿的按钮。"
                        + "下一步：把方向词改成对的那个，或者干脆去掉、只说「点「开始练习」」。"
                        + "实际脚注：\(tile.footnote)")
            }
        }

        XCTAssertGreaterThanOrEqual(
            checked, 2,
            "四格脚注里一句提到「开始练习」的都没扫到，这条测试等于空转。"
                + "下一步：确认空数据下的「本周训练」「累计训练」两格仍然告诉用户去开练。")
        XCTAssertGreaterThanOrEqual(
            directed, 1,
            "四格脚注里没有一句带方向词，上面那圈「方向必须和 body 里的位置对得上」"
                + "就没有样本可查。下一步：确认这是有意去掉方向词——是的话把这条断言一起删掉"
                + "并在提交信息里写明；不是的话把方向词加回去。")
    }

    /// 「往上找」的各种说法。`上一步` `上次` 这类不在里面：它们说的不是位置。
    static let upwardWords = ["上面", "上方", "往上", "上边", "上头"]
    /// 「往下找」的各种说法。
    static let downwardWords = ["下面", "下方", "往下", "下边"]

    /// 取 `needle` 前面**同一小句**里的那几个字。
    ///
    /// 不扫整条脚注，是为了不误报：一条脚注完全可以一边说「上面那条说明」、
    /// 一边让用户去点下面的按钮，那两句话各说各的。误报几次，这条守卫就会被人整条删掉
    /// （`SourceGuard.directions` 里已经写过同一个道理）。
    static func clause(before needle: String, in text: String) -> String? {
        guard let found = text.range(of: needle) else { return nil }
        let head = text[text.startIndex..<found.lowerBound]
        let separators: Set<Character> = ["。", "；", "！", "？", "，", "、", "：", ";", "\n"]
        guard let lastBreak = head.lastIndex(where: { separators.contains($0) }) else {
            return String(head)
        }
        return String(head[head.index(after: lastBreak)...])
    }

    // MARK: - 扫源码用的小工具

    static let viewRelativePath = "Today/TodayView.swift"

    /// 注释里必然要解释「为什么这么写」，连注释一起扫的话这些测试会被自己的说明绊倒。
    ///
    /// 走 `SourceGuard`：文件挪了位置或改了名会**抛错**，而不是拿一段空串继续跑——
    /// 空串会让下面每条 `contains` 恒假、每条 `!contains` 恒真。
    static func todayViewCode() throws -> String { try SourceGuard.code(viewRelativePath) }
}
