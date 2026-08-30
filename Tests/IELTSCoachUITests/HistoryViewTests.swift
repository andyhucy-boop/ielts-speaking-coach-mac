import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 训练记录页的视图层守卫，一条对一条地钉住计划 Task 9 的十二条验收要求。
///
/// **为什么这一页需要这么一份测试。** 计划 Task 9 Step 5 只给了 `isImplemented` 两条突变，
/// 并写明「`HistoryView` 的正确性由 Task 13 的人工验收把关」。但本项目已经四次实测到
/// 「整段渲染被删掉、几百条测试全绿」——`ReviewReportView` 那次是把
/// `ForEach(document.sections)` 换成空数组，484 条一条不红。人工验收只跑一次，
/// 而回归会发生无数次。
///
/// **边界（与 `ReviewReportViewTests` 一致）**：扫源码不执行代码。
/// 「调用还在但条件永远为假」拦不住，排版好不好看、那个开关摆得对不对也拦不住——
/// 那部分归 Task 13 的人工验收（尤其是「拨过开关关掉 App 再打开还在不在」那一条，
/// 落盘那一半由 `AppStateTests` 守，界面那一半只能人工看）。
/// 它拦得住的是：整段渲染被删、数据源被换掉、五个字段里悄悄少一个。
@MainActor
final class HistoryViewTests: XCTestCase {

    private static let view = "History/HistoryView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct HistoryView"),
                      "没扫到 HistoryView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 要求 1：页头

    func testThePageHeaderSaysWhichPageThisIs() throws {
        SourceGuard.assertRenders(
            "PageHeader(number: 2, label: \"TRAINING HISTORY\"",
            inBodyOf: "private var header", of: Self.view,
            because: "页头不见了，用户点进来看到的是一堆没有标题的卡片。"
                + "下一步：把 `SectionHeader` 放回去（DESIGN-SYSTEM 第 4 节）。")
        SourceGuard.assertRenders(
            "SidebarItem.history.title", inBodyOf: "private var header", of: Self.view,
            because: "页头标题是手写死的字符串，和侧边栏那一项对不上了——"
                + "侧边栏改了名字，这一页还叫老名字。下一步：改回 `SidebarItem.history.title`。")
        SourceGuard.assertRenders(
            "header", inBodyOf: "var body: some View", of: Self.view,
            because: "页头写好了却没摆进 `body`。下一步：把它放回去。")
    }

    // MARK: - 要求 2：逐字稿记录开着没有（Phase 10 Task 16 起是只读现状 + 一条深链接）

    /// 这一行必须**说清现状、并给一条能走的路**，而且**自己一个字都不许写盘**。
    ///
    /// Phase 4 把开关本体放在这里；Task 16 把它收进设置窗口的「练习偏好」——
    /// 它决定的是每一场练习要不要采集逐字稿，不是训练记录页的属性。
    /// 两处都留一个开关的话，改的是同一个字段却各写各的盘，谁后写谁说了算，
    /// 用户看到的是随机结果（`SettingsHomeContractTests` 从写入口那一头守着同一件事）。
    ///
    /// 那一行仍然要有：这一页就是逐字稿的产物，看到记录里没有对话时，
    /// 抬头能看见是不是自己把它关了——这是当初把开关放在这儿的本意，保留了下来。
    func testThePageShowsWhetherTranscriptRecordingIsOnAndWhereToChangeIt() throws {
        let status = try SourceGuard.memberBody(of: "private var transcriptStatus",
                                                in: try Self.viewCode())
        XCTAssertTrue(status.contains("PracticePreferenceEditor.transcriptStatusText("),
                      "这一行没走 `PracticePreferenceEditor.transcriptStatusText(enabled:)`，"
                          + "自己拼一句的话，它和设置窗口那边迟早说不一样的话。"
                          + "实际取到的是：\n\(status)")
        XCTAssertTrue(status.contains("app.state.settings.transcriptEnabled"),
                      "这一行显示的现状不是从 `settings.transcriptEnabled` 取的，"
                          + "也就是它和真实设置无关——用户看到「开」，实际可能是关的。"
                          + "实际取到的是：\n\(status)")
        XCTAssertTrue(status.contains("Button(\"打开设置 › 练习偏好\")"),
                      "只写了一句现状却没给按钮，用户读完还得自己去翻菜单。"
                          + "实际取到的是：\n\(status)")
        XCTAssertTrue(status.contains("navigator.open(.practice)"),
                      "按钮没有把设置窗口定到「练习偏好」那一栏，用户点开落在「录音」上。"
                          + "实际取到的是：\n\(status)")
        XCTAssertTrue(status.contains("openSettings()"),
                      "按钮没有真的打开设置窗口，点下去什么都不会发生。实际取到的是：\n\(status)")

        SourceGuard.assertRenders(
            "transcriptStatus", inBodyOf: "private var header", of: Self.view,
            because: "这一行写好了却没摆进页头，用户看不到逐字稿到底开着没有。下一步：把它放回去。")
    }

    /// **这一页不许再有任何写设置的入口。**
    ///
    /// 上一条只问「路标在不在」，把开关留在路标旁边它照样绿——而那正是这次合并要消灭的东西。
    func testTheTranscriptSwitchItselfIsGoneFromThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertFalse(code.contains("Toggle("),
                       "训练记录页还留着一个开关。逐字稿只在设置窗口的「练习偏好」里改。")
        XCTAssertFalse(code.contains("setTranscriptEnabled"),
                       "训练记录页还在自己写这个设置。写入口只留 "
                           + "`CoachSettingsViewModel.setTranscriptEnabled(_:)` 一处。")
    }

    // MARK: - 要求 3：按月分组，数据来自 HistoryViewModel

    /// 这一页必须走 `HistoryViewModel`，不许自己现拼一份分组。
    ///
    /// 视图里自己 `filter` + `sorted` 的话，`HistoryViewModelTests` 那 12 条
    ///（「时间不详的不许消失」「题目不在题库里要说出来」…）会当场退化成空转——
    /// 测的是一份没人用的实现。
    func testTheMonthsComeFromTheViewModel() throws {
        SourceGuard.assertRenders(
            "HistoryViewModel(state: app.state)", inBodyOf: "private var model", of: Self.view,
            because: "这一页自己拼了一份训练记录，没有走 `HistoryViewModel`。"
                + "那样「时间不详的记录不许消失」「题目不在题库里要说出来」那些测试"
                + "全都在测一份没人用的实现。下一步：改回调用视图模型。")

        SourceGuard.assertRenders(
            "ForEach(model.months)", inBodyOf: "private var monthList", of: Self.view,
            because: "列表不再遍历 `model.months`（换成空数组一样编得过），"
                + "整页一条记录都不显示，用户会以为练习记录全没了。下一步：把 `ForEach` 放回去。")

        let list = try SourceGuard.memberBody(of: "private var monthList", in: try Self.viewCode())
        let loop = try SourceGuard.memberBody(of: "ForEach(model.months)", in: list)
        XCTAssertTrue(loop.contains("monthSection(month)"),
                      "遍历了 `model.months`，循环体里却没有 `monthSection(month)`——"
                          + "每个月份都是空的。实际取到的循环体是：\n\(loop)")

        let section = try SourceGuard.memberBody(of: "private func monthSection",
                                                 in: try Self.viewCode())
        XCTAssertTrue(section.contains("month.title"),
                      "月份标题没画出来，几个月的记录会连成一片分不开。")
        XCTAssertTrue(section.contains("ForEach(month.rows)") && section.contains("rowCard(row)"),
                      "月份里没有遍历 `month.rows` 并画出每一行——这个月是空的。"
                          + "实际取到的是：\n\(section)")

        SourceGuard.assertRenders(
            "monthList", inBodyOf: "var body: some View", of: Self.view,
            because: "整个列表没摆进 `body`，这一页只剩一个页头。下一步：把它放回去。")
    }

    // MARK: - 要求 4：每一行五项，缺一不可

    /// 这五项是 ROADMAP Phase 4 交付清单里写死的。
    ///
    /// 少一项不会有任何编译错误，也不会有别的测试发现——只会让用户在一堆
    /// 「8 月 6 日 / Part 1」里分不出哪一场是哪一场。
    func testEveryRowShowsAllFiveFields() throws {
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: try Self.viewCode())
        for (field, why) in [
            ("row.dateText", "哪天练的"),
            ("row.partText", "练的哪个 Part"),
            ("row.questionText", "练的哪道题——只有日期的话，同一天的几场分不出哪次是哪次"),
            ("row.turnCountText", "这一场说了多少轮，也是「有没有逐字稿」的唯一提示"),
            ("row.reviewStatusText", "有没有复盘")
        ] {
            XCTAssertTrue(card.contains(field),
                          "行里没有\(why)（`\(field)`）。这五项是 ROADMAP Phase 4 "
                              + "交付清单里写死的，缺一不可。")
        }
    }

    // MARK: - 要求 5：题目不在题库里，要标出来但绝不藏起来

    func testAMissingQuestionIsFlaggedAndTheRowStaysThere() throws {
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: try Self.viewCode())
        XCTAssertTrue(card.contains("row.questionIsMissing"),
                      "题目已经不在题库里的那些行没有任何标记，用户看到一句"
                          + "「这道题已经不在题库里了」却和正常题目长得一模一样。")
        XCTAssertTrue(card.contains("Palette.warning"),
                      "标记没用 `Palette.warning`。下一步：按 DESIGN-SYSTEM 第 2 节用语义色。")

        // **这一条比上面两条重要**：标不标是观感，藏不藏是数据。
        SourceGuard.assertOmits(
            "questionIsMissing { continue", in: Self.view,
            because: "题目不在题库里就把整行跳过了。用户会以为这几场练习记录丢了，"
                + "而实际上它们都还在 state.json 里（成品标准第 12 条）。"
                + "下一步：照常显示这一行，只把题目那一格标成 `Palette.warning`。")
        SourceGuard.assertOmits(
            "filter { !$0.questionIsMissing }", in: Self.view,
            because: "同上——题目不在题库里的记录被过滤掉了，等于凭空消失。")
    }

    // MARK: - 要求 6：数字用等宽

    func testTheTurnCountUsesMonospacedDigits() throws {
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: try Self.viewCode())
        XCTAssertTrue(card.contains(".monospacedDigit()"),
                      "行里的数字没有用等宽数字，条数一变整行会跟着抖"
                          + "（DESIGN-SYSTEM 第 1 节把等宽数字焊在数字那一档令牌里，"
                          + "就是为了避免这件事）。")
    }

    // MARK: - 要求 7：点开一行看逐字稿全文

    func testOpeningARowPaintsTheWholeTranscript() throws {
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: try Self.viewCode())
        // **指名 `Self.toggling(...)`，不是只问「有没有给 expandedSessionID 赋值」。**
        // 后者任何赋值都满足：复审实测把这一行改成 `expandedSessionID = nil`，656 条全绿，
        // 而那之后逐字稿面板永远画不出来（见下面那条真跑起来的测试）。
        XCTAssertTrue(card.contains("expandedSessionID = Self.toggling(expandedSessionID, to: row.id)"),
                      "行点下去没有把展开状态交给 `HistoryView.toggling(_:to:)`。"
                          + "自己在这儿现写一句赋值的话，「点开 / 再点收起 / 点另一行」"
                          + "就没有任何真跑起来的测试管得住了。实际取到的行是：\n\(card)")
        XCTAssertTrue(card.contains("transcriptPane(row)"),
                      "展开之后没有画逐字稿。实际取到的是：\n\(card)")

        let pane = try SourceGuard.memberBody(of: "private func transcriptPane",
                                              in: try Self.viewCode())
        XCTAssertTrue(pane.contains("row.session.transcript"),
                      "逐字稿那一块没有从这一场的 `transcript` 取内容。")
        XCTAssertTrue(pane.contains("turnView(turn)"),
                      "遍历了逐字稿却没有画出每一条。实际取到的是：\n\(pane)")

        let turn = try SourceGuard.memberBody(of: "private func turnView", in: try Self.viewCode())
        XCTAssertTrue(turn.contains("turn.text"),
                      "每一条只画了说话人没画内容，逐字稿等于没有。")
        XCTAssertTrue(turn.contains("speakerText(for: turn.role)"),
                      "没有标出这句是谁说的。考官的问题和自己的回答混成一片，"
                          + "复盘时根本没法看。")
    }

    /// **这条是复审 BI-2 的判据。**
    ///
    /// 上一条只扫源码，扫得出的只是「行里给 `expandedSessionID` 赋了个值」。
    /// 复审实测把那一行改成 `expandedSessionID = nil`，656 条全绿——之后
    /// `if expandedSessionID == row.id` 永远为假，逐字稿面板永远画不出来：
    /// 验收要求 7（点开一行看这一场逐字稿全文，这一页的头号功能）整条死掉，
    /// 而上一条测试后面那一串（transcriptPane / turn.text / speakerText / 复盘按钮）
    /// 全在扫一段永远渲染不到的代码，一起退化成空转。
    ///
    /// 所以照 `speakerText(for:)` 那一招，把「点一下之后展开哪一场」抽成纯函数，
    /// 用真跑起来的断言钉住三种点法。
    func testClickingARowOpensItAndClickingTheSameRowAgainClosesIt() {
        XCTAssertEqual(HistoryView.toggling(nil, to: "2026-08-06-001"), "2026-08-06-001",
                       "一行都没展开时点一行，那一场没被展开——逐字稿永远看不到，"
                           + "而这是这一页的头号功能。")
        XCTAssertNil(HistoryView.toggling("2026-08-06-001", to: "2026-08-06-001"),
                     "再点一次已经展开的那一行没有收起来，用户没有任何办法把它关上。")
        XCTAssertEqual(HistoryView.toggling("2026-08-06-001", to: "2026-08-05-002"),
                       "2026-08-05-002",
                       "点另一行时展开的还是原来那一场——用户看的是别人家的逐字稿，"
                           + "内容看着完全正常，比一片空白更难被发现。")
    }

    /// 判不出是谁说的那些（`role == "unknown"`，spec 2.3.9：流式输出中的消息还没有
    /// 复制按钮，判不出来）**不许猜**。猜错会让用户把考官说的话当成自己说的，
    /// 而这种错误没有任何信号提示。
    func testAnUnknownSpeakerIsSaidOutLoudRatherThanGuessed() {
        XCTAssertEqual(HistoryView.speakerText(for: "assistant"), "考官")
        XCTAssertEqual(HistoryView.speakerText(for: "user"), "我")
        XCTAssertEqual(HistoryView.speakerText(for: "unknown"), "说不准是谁说的")
        // 将来上游多出一个没见过的取值时，同样不许猜成某一方。
        XCTAssertEqual(HistoryView.speakerText(for: "system"), "说不准是谁说的",
                       "没见过的 role 被猜成了某一方。判不出来就要说判不出来（spec 2.3.9）。")
    }

    // MARK: - 要求 8：这一场没有逐字稿时，说清为什么

    func testAnEmptyTranscriptExplainsItselfInsteadOfShowingNothing() throws {
        let pane = try SourceGuard.memberBody(of: "private func transcriptPane",
                                              in: try Self.viewCode())
        XCTAssertTrue(pane.contains("transcript.isEmpty"),
                      "没有逐字稿的那些场次走的是和有逐字稿一样的分支，展开之后是一块空白，"
                          + "用户会以为这一页坏了。")
        for phrase in ["这一场没有逐字稿", "关着的", "上线之前", "下一步"] {
            XCTAssertTrue(pane.contains(phrase),
                          "空逐字稿的说明里没有「\(phrase)」。铁律 6：既要说发生了什么，"
                              + "也要说下一步做什么。实际取到的是：\n\(pane)")
        }
    }

    // MARK: - 要求 9：有复盘就能直接跳过去看

    func testTheReviewButtonOnlyAppearsWhenThereIsOneAndActuallyNavigates() throws {
        let pane = try SourceGuard.memberBody(of: "private func transcriptPane",
                                              in: try Self.viewCode())
        XCTAssertTrue(pane.contains("row.hasReport"),
                      "「看这次的复盘」这颗按钮没有按 `hasReport` 判断，"
                          + "没有复盘的场次也会显示它——点下去只会跳到一页找不到内容的复盘。")
        XCTAssertTrue(pane.contains("Button(\"看这次的复盘\")"),
                      "「看这次的复盘」按钮不见了。用户在这一页看到「复盘已存档」，"
                          + "却只能自己回侧边栏再翻一遍。")
        XCTAssertTrue(pane.contains("onOpenReview(row.session)"),
                      "按钮点下去没有把这一场传出去，跳过去之后选中的还是最近那一场，"
                          + "而不是他点的那一场。")
    }

    /// 上一条只管到这一页的边界。跳过去之后**真的选中那一场**要靠 `RootView` 接线 +
    /// `ReviewReportView` 认这个参数，这里一并钉住——中间断一环，
    /// 用户点「看这次的复盘」看到的就是别人家的复盘，比一片空白更难被发现。
    func testTheHandoffToTheReviewPageIsActuallyWiredUp() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(root.contains("case .history: HistoryView("),
                      "侧边栏点「训练记录」还是落到占位页——`.history` 已经标成做好了，"
                          + "用户点进来会看到「这一页还没做」。")
        XCTAssertTrue(root.contains("requestedReviewSessionID = session.id"),
                      "`onOpenReview` 收到的那一场没被记下来，跳过去也不知道要选哪一场。")
        XCTAssertTrue(root.contains("requestedSessionID: requestedReviewSessionID"),
                      "记下来了却没传给复盘报告页，等于没记。")

        let review = try SourceGuard.code("Review/ReviewReportView.swift")
        // 标记要带上返回类型：只写 `private var selected` 的话，
        // `@State private var selectedSessionID` 会先被匹配到，扫的就是另一个成员了。
        SourceGuard.assertRenders(
            "requestedSessionID", inBodyOf: "private var selected: PracticeSession?",
            of: "Review/ReviewReportView.swift",
            because: "复盘报告页收下了「要看哪一场」却没用它挑会话，"
                + "从训练记录跳过去看到的还是最近那一场——内容看着完全正常，但是别人家的。")
        XCTAssertTrue(review.contains("selectedSessionID ?? requestedSessionID"),
                      "两个来源的优先级没写清。用户在复盘页自己点过之后，"
                          + "他点的那一场必须压过从训练记录带过来的那一场。")
    }

    /// 上一条守的是「跳过去要落到他点的那一场」，这一条守的是它的另一半：
    /// **用户自己切页之后，带过来的那一场就得作废**（复审 BI-3）。
    ///
    /// 判断本身是纯函数，由 `NavigationTests` 里两条真跑起来的测试钉着；
    /// 这里只管接线——判断写对了却没人调用，等于没写。
    func testEveryNavigationTheUserMakesHimselfGoesThroughTheDropper() throws {
        let root = try SourceGuard.code("RootView.swift")
        SourceGuard.assertRenders(
            "RootRouter.carriedReviewSession(", inBodyOf: "private func go(to item:",
            of: "RootView.swift",
            because: "切页时没有把「从训练记录带过来的那一场」交给 "
                + "`RootRouter.carriedReviewSession(_:navigatingFrom:to:)` 处理，"
                + "那个值就又变成只写不清的了：用户点过一次「看这次的复盘」之后，"
                + "此后每一次从侧边栏点「复盘报告」，落到的都是那一场旧的。")
        // 2026-08-30 改版：侧边栏从系统 `List(selection:)` 换成了自绘的 `SidebarView`，
        // 于是那个 `sidebarSelection` 绑定不再需要——它存在的理由就是「`List` 只收可选值」。
        // 现在选中项直接回调 `go(to:)`，路径更短，但要守的还是同一件事。
        XCTAssertTrue(root.contains("SidebarView(selection: current, onSelect: { go(to: $0) })"),
                      "侧边栏没有把选中项交给 `go(to:)`——用户从侧边栏切页时，"
                          + "「从训练记录带过来的那一场」清不掉，"
                          + "此后每次点「复盘报告」落到的都是那一场旧的。")
        SourceGuard.assertOmits(
            "app.navigation.selection = $0", in: "RootView.swift",
            because: "侧边栏又绕过 `go(to:)` 直接写导航状态了，那段清理逻辑一次都不会跑。")
        SourceGuard.assertRenders(
            "onGo: { go(to: $0) }", in: "RootView.swift", atLeast: 4,
            because: "页面里那些「去今日训练」「看复盘报告」按钮没走 `go(to:)`。"
                + "`TodayView` 里就有一颗「看复盘报告」——从那儿进去同样会落到"
                + "上回从训练记录带过来的那一场旧的。")
        SourceGuard.assertOmits(
            "onGo: { selection = $0 }", in: "RootView.swift",
            because: "这是没走 `go(to:)` 的老写法，等于绕开了那段清理。")
    }

    // MARK: - 要求 10：一场都没练过的时候

    func testTheEmptyPageGivesAllThreeThings() throws {
        SourceGuard.assertRenders(
            "model.isEmpty", inBodyOf: "var body: some View", of: Self.view,
            because: "一条记录都没有时这一页不再走空状态那一支，用户看到的是一片空白"
                + "（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。")
        SourceGuard.assertRenders(
            "emptyState", inBodyOf: "var body: some View", of: Self.view,
            because: "空状态写好了却没摆进 `body`，用户一个字都看不到。")

        let empty = try SourceGuard.memberBody(of: "private var emptyState", in: try Self.viewCode())
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "空状态没走 `EmptyStateView`，那三样（现状 / 下一步 / 一颗按钮）"
                          + "就没人管得住了。")
        XCTAssertTrue(empty.contains("还没有训练记录"), "空状态没说清现在是什么情况。")
        XCTAssertTrue(empty.contains("按月列出"), "空状态没说清练完之后这里会有什么。")
        XCTAssertTrue(empty.contains("onGo(.today)"),
                      "空状态那颗按钮点下去哪儿也不去，用户读完还得自己回侧边栏翻。")
    }

    // MARK: - 要求 12：每行的删除入口

    /// 计划 Task 9 要求「每行留出一个删除入口」，并说删除行为由 Task 10 接。
    /// **但 Task 10 已经先落地了**（`SessionDeleter` 与它的 8 条测试都在仓库里），
    /// 只是当时 `HistoryView` 还不存在，所以那一半改动没做成。
    /// 现在这一页建起来了，就得把它接上——留一颗点了没反应的按钮比不留更糟，
    /// 而不接的话 `SessionDeleter` 是一段界面上完全走不到的死代码。
    func testEveryRowHasADeleteEntryThatAsksBeforeItDestroysAnything() throws {
        let code = try Self.viewCode()
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: code)
        XCTAssertTrue(card.contains("deleteButton(row)"),
                      "行上没有删除入口。用户练错的、重复的那些场次永远清不掉。"
                          + "实际取到的行是：\n\(card)")
        let button = try SourceGuard.memberBody(of: "private func deleteButton", in: code)
        XCTAssertTrue(button.contains("pendingDeletion = row"),
                      "删除按钮点下去没有把这一行交给确认框——按钮在那儿，点了没反应。")

        XCTAssertTrue(code.contains(".confirmationDialog("),
                      "删除没有确认对话框，点一下就没了，而且不进废纸篓、没有撤销。")
        XCTAssertTrue(code.contains("SessionDeletion.plan(for: row.session).confirmationText"),
                      "确认框里没有原样显示 `SessionDeletionPlan.confirmationText`。"
                          + "那段话逐条列明了会删掉哪些文件、以及什么不会跟着删——"
                          + "自己另写一句的话，`SessionDeleterTests` 里守着那段文案的测试就空转了。")
        XCTAssertTrue(code.contains("role: .destructive"),
                      "确认按钮没用 `.destructive` 角色，看起来和普通按钮一样。")
        XCTAssertTrue(code.contains("Button(\"取消\", role: .cancel)"),
                      "确认框里没有「取消」。`SessionDeletion.plan` 的文案里明写"
                          + "「想留着就点「取消」」，指一颗不存在的按钮比不写还糟。")
        XCTAssertTrue(code.contains("app.deleteSession(row.session)"),
                      "确认之后没有真的去删。按钮点了没反应是本项目最不能接受的那一类。")
    }

    /// 删不掉的文件必须原地说出来，而且能选中复制——用一闪而过的提示，用户来不及读。
    func testAPartialFailureIsSaidOutLoudAndStaysOnScreen() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "deletionFailure", inBodyOf: "var body: some View", of: Self.view,
            because: "删除只完成了一半（记录删了、文件没删掉）时那段说明没有摆上屏。"
                + "用户永远不会知道磁盘上还躺着那些孤儿文件（铁律 7）。")
        let card = try SourceGuard.memberBody(of: "private func deletionFailureCard", in: code)
        XCTAssertTrue(card.contains(".textSelection(.enabled)"),
                      "那段说明里带着文件路径，必须能选中复制，用户要拿它去访达里找。")
        XCTAssertTrue(card.contains("Palette.warning"),
                      "没用 `Palette.warning` 标出来，混在正文里没人会注意到。")
    }
}
