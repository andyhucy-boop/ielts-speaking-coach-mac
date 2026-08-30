import Foundation
import XCTest

@testable import IELTSCoachUI

/// 复训中心页的视图层守卫，一条对一条地钉住计划 Task 10 Step 4 给这一页的七条验收要求。
///
/// ## 为什么这一页需要这么一份测试
///
/// 计划 Task 10 只给了 `NavigationState.consumePendingRetrainingTarget()` 一条突变，
/// 并把两个视图的正确性推给 Task 11 的人工验收。`HistoryViewTests` 的文件注释里
/// 已经写过同一件事的结论：**人工验收只跑一次，而回归会发生无数次。**
///
/// 复审在这一页上一次性做了三处突变，`swift test` 941 条 0 失败：
///
/// - `Label(issue.message, systemImage:)` 换成 `Text("—")` → 链断了那句
///   「找不回当时练的是哪道题…下一步：…」整段消失，用户只看到一条没有解释的目标；
/// - `notice = app.setRetrainingStatus(...)` 换成 `_ = app.setRetrainingStatus(...)` →
///   「重新放回待复训」失败时一声不吭，列表纹丝不动而没有任何说明（铁律 7）；
/// - 待复训列表那段渲染整块换掉 → 这一页只剩一个页头。
///
/// ## 边界（与 `HistoryViewTests` / `ReviewReportViewTests` 一致）
///
/// 扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——
/// 那部分归 Task 11 的人工验收。它拦得住的是：整段渲染被删、数据源被换掉、
/// 失败提示被吞掉、写好的组件没摆进页面。
final class RetrainingCenterViewTests: XCTestCase {

    private static let view = "Retraining/RetrainingCenterView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct RetrainingCenterView"),
                      "没扫到 RetrainingCenterView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 要求 1：页头

    func testThePageHeaderSaysWhichPageThisIsAndWhatItIsFor() throws {
        SourceGuard.assertRenders(
            "PageHeader(number: 4, label: \"RETRAINING\"",
            inBodyOf: "private var header", of: Self.view,
            because: "页头不见了，用户点进来看到的是一堆没有标题的卡片"
                + "（DESIGN-SYSTEM 第 4 节）。")
        let header = try SourceGuard.memberBody(of: "private var header", in: try Self.viewCode())
        XCTAssertTrue(header.contains("一次只解决一个问题"),
                      "页头那句话不见了。「一次只解决一个问题」是这一整个阶段的立场，"
                          + "也是用户理解「为什么这里一次只让我练一个目标」的唯一说明。")
        XCTAssertTrue(header.contains("换一道题") || header.contains("只记住了那个答案"),
                      "页头没有解释「重答原题之后还要换一道题验证」。"
                          + "不写这一句，用户会以为重答完原题就结束了——而那正是这一页要防的事。")
        SourceGuard.assertRenders(
            "header", inBodyOf: "var body: some View", of: Self.view,
            because: "页头写好了却没摆进 `body`。下一步：把它放回去。")
    }

    // MARK: - 要求 2：待复训列表，顺序原样来自视图模型

    /// 这一页必须走 `RetrainingCenterViewModel`，**不许在视图里再排一次**。
    ///
    /// 视图里自己 `sorted` 的话会造出第二套说法，而排序的依据
    ///（证据命中高频错题）只有 `RetrainingPolicy.rank` 那一处有测试守着。
    func testThePendingListComesFromTheViewModelAndIsNeverSortedAgain() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "RetrainingCenterViewModel(state: app.state)", inBodyOf: "private var model",
            of: Self.view,
            because: "这一页自己拼了一份待复训列表，没有走 `RetrainingCenterViewModel`。"
                + "那样 `RetrainingCenterViewModelTests` 那一整组断言"
                + "（顺序、链断了怎么办、退休的怎么列）全都在测一份没人用的实现。")

        let pending = try SourceGuard.memberBody(of: "private var pendingSection", in: code)
        XCTAssertTrue(pending.contains("model.pending"),
                      "列表的数据源不再是 `model.pending`。实际取到的是：\n\(pending)")
        XCTAssertTrue(pending.contains("pendingRow(item"),
                      "遍历了列表却没有画出每一条——这一页只剩一个页头。"
                          + "实际取到的是：\n\(pending)")
        for forbidden in ["sorted", "filter"] where pending.contains(forbidden) {
            XCTFail("待复训列表在视图里又 `\(forbidden)` 了一次。顺序**原样**来自 "
                        + "`RetrainingPolicy.rank`（经 `RetrainingCenterViewModel.pending`），"
                        + "这一页不许再排、再筛——那会造出第二套说法，"
                        + "而依据只有那一处有测试守着。实际取到的是：\n\(pending)")
        }

        SourceGuard.assertRenders(
            "pendingSection", inBodyOf: "var body: some View", of: Self.view,
            because: "整个待复训列表没摆进 `body`，这一页只剩一个页头。")
    }

    /// 计划要求每条显示五样：目标名、第一条证据原话、状态、来源日期、原题。
    /// 少一样不会有任何编译错误，也不会有别的测试发现——只会让用户在一堆
    /// 「还没开始复训」里分不出哪一条是哪一条。
    func testEveryRowShowsAllFiveThings() throws {
        let code = try Self.viewCode()
        let detail = try SourceGuard.memberBody(of: "private func targetDetail", in: code)
        for (field, why) in [
            ("firstQuote(of: item)", "当时说的那句原话——它是「为什么要练这个目标」的唯一依据"),
            ("dateText(item.target.createdAt)", "这个目标是哪天的复盘留下的"),
            ("item.originalQuestion", "当时练的是哪道题")
        ] {
            XCTAssertTrue(detail.contains(field),
                          "一条待复训里没有\(why)（`\(field)`）。实际取到的是：\n\(detail)")
        }
        XCTAssertTrue(detail.contains("promptText(question)"),
                      "原题那一行只有 Part 没有题干，用户认不出是哪道题。")
        XCTAssertTrue(detail.contains(".monospacedDigit()"),
                      "日期没用等宽数字，几条并排时会横向抖（规范第 1 节最后一行）。")

        for card in ["private func primaryTargetCard", "private func secondaryTargetCard"] {
            let body = try SourceGuard.memberBody(of: card, in: code)
            XCTAssertTrue(body.contains("title(of: item)"),
                          "\(card) 没有显示目标名。实际取到的是：\n\(body)")
            XCTAssertTrue(body.contains("item.statusLabel"),
                          "\(card) 没有显示进度（还没开始／已重答原题几次／已换题验证几次）。"
                              + "用户不知道这一条自己走到哪儿了。实际取到的是：\n\(body)")
            XCTAssertTrue(body.contains("targetDetail(item)"),
                          "\(card) 没有画那几行正文。实际取到的是：\n\(body)")
        }

        // label 为空时退回 targetKey：一行没有标题的记录用户根本不知道那是什么。
        let title = try SourceGuard.memberBody(of: "private func title", in: code)
        XCTAssertTrue(title.contains("item.target.targetKey"),
                      "目标名为空时没有退回 `targetKey`，那一条会显示成一片空白。"
                          + "实际取到的是：\n\(title)")
    }

    /// **这一条比上面那条重要**：显示得全不全是观感，藏不藏是数据。
    ///
    /// 复审实测把 `Label(issue.message, systemImage:)` 换成 `Text("—")`，941 条全绿——
    /// 而那之后，来源记录被删、题库换季导致原题找不到的那些目标，
    /// 屏幕上只剩一个破折号：用户既不知道发生了什么，也不知道下一步能做什么（铁律 6）。
    func testABrokenSourceLinkIsSaidOutLoudAndTheRowStaysInTheList() throws {
        let code = try Self.viewCode()
        let detail = try SourceGuard.memberBody(of: "private func targetDetail", in: code)
        XCTAssertTrue(detail.contains("item.sourceIssue"),
                      "链断了的那些目标没有任何标记，和正常目标长得一模一样——"
                          + "用户点「带着本题进入复训」会发现根本没有本题。"
                          + "实际取到的是：\n\(detail)")
        XCTAssertTrue(detail.contains("issue.message"),
                      "链断了却没有把 `RetrainingSourceIssue.message` 原样显示出来。"
                          + "那段话同时说清了「找不回当时练的是哪道题」和「下一步仍然可以"
                          + "带着这个目标自己挑一道题练」（铁律 6）——自己另写一句的话，"
                          + "`RetrainingCenterViewModelTests` 里守着那段文案的测试就空转了。"
                          + "实际取到的是：\n\(detail)")

        // 藏起来比标错更糟：凭空消失会让用户以为练习记录丢了。
        for hiding in ["sourceIssue == nil }", "sourceIssue != nil { continue",
                       "filter { $0.sourceIssue == nil }"] {
            SourceGuard.assertOmits(
                hiding, in: Self.view,
                because: "链断了的目标被从列表里过滤掉了。**不能把这一条藏起来**——"
                    + "凭空消失会让用户以为练习记录丢了，而它们都还在 state.json 里。"
                    + "下一步：照常显示这一条，把 `sourceIssue.message` 摆在同一屏上。")
        }
    }

    // MARK: - 要求 3：每条一个主行动，按原题还在不在分两种

    func testTheMainActionMatchesWhetherTheOriginalQuestionIsStillThere() throws {
        let code = try Self.viewCode()
        let title = try SourceGuard.memberBody(of: "private func mainActionTitle", in: code)
        XCTAssertTrue(title.contains("item.canRetryOriginal"),
                      "主行动的文字不再按「原题还在不在」分。原题已经找不到了还写"
                          + "「带着本题进入复训」，点下去只会发现没有本题。实际取到的是：\n\(title)")
        XCTAssertTrue(title.contains("带着本题进入复训") && title.contains("挑一道题带着这个目标练"),
                      "两句主行动文案缺了一句。实际取到的是：\n\(title)")

        let button = try SourceGuard.memberBody(of: "private func mainActionButton", in: code)
        XCTAssertTrue(button.contains("Button(\"带着本题进入复训\")")
                          && button.contains("Button(\"挑一道题带着这个目标练\")"),
                      "两句按钮文字没有以字面量留在源码里。"
                          + "`RenderReachabilitySweepTests` 要靠这份字面清单回答"
                          + "「文案里指名让用户点的东西，界面上真有吗」。实际取到的是：\n\(button)")
        XCTAssertTrue(button.contains("openMainAction(item)"),
                      "按钮点下去没有任何动作。按钮点了没反应是本项目最不能接受的那一类。")

        let open = try SourceGuard.memberBody(of: "private func openMainAction", in: code)
        XCTAssertTrue(open.contains("item.originalQuestion"),
                      "主行动没有按「原题还在不在」分路。实际取到的是：\n\(open)")
        XCTAssertTrue(open.contains("openTransfer(item)"),
                      "原题找不到时没有退回「自己挑一道题」那条路，这一条就成了死路。")
        XCTAssertTrue(open.contains("run: .original"),
                      "原题还在时那一趟没有按「重答原题」记，会被算成换题验证。"
                          + "实际取到的是：\n\(open)")

        let transfer = try SourceGuard.memberBody(of: "private func openTransfer", in: code)
        XCTAssertTrue(transfer.contains("run: .transfer"),
                      "换题那一趟没有按 `.transfer` 记。实际取到的是：\n\(transfer)")
    }

    // MARK: - 要求 4：已经重答过原题的，额外给一条「换一道题验证」

    /// **这才是本阶段真正的交付物**：只重练原题，分不清是真会了还是只记住了那个答案。
    func testTheTransferActionShowsUpOnceTheOriginalHasBeenRetried() throws {
        let row = try SourceGuard.memberBody(of: "private func pendingRow", in: try Self.viewCode())
        XCTAssertTrue(row.contains("item.progress.stage != .notStarted"),
                      "「换一道题验证」不再按进度显示。一次都还没练过就摆出来的话，"
                          + "用户会跳过「重答原题」直接换题——那一趟没有对照，"
                          + "看不出他到底改没改。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains("Button(\"换一道题验证\")"),
                      "「换一道题验证」这颗按钮不见了。重答完原题之后，"
                          + "用户在这一页没有任何办法做第二步。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains("openTransfer(item)"),
                      "「换一道题验证」点下去没有动作。实际取到的是：\n\(row)")
    }

    // MARK: - 要求 5：一个目标都没有的时候

    func testTheEmptyPageGivesAllThreeThings() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "emptyState", inBodyOf: "private var pendingSection", of: Self.view,
            because: "一个待复训目标都没有时这一页不再走空状态那一支，"
                + "用户看到的是一片空白（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。")
        let empty = try SourceGuard.memberBody(of: "private var emptyState", in: code)
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "空状态没走 `EmptyStateView`，那三样（现状 / 下一步 / 一颗按钮）"
                          + "就没人管得住了。")
        XCTAssertTrue(empty.contains("model.emptyStateMessage"),
                      "空状态没用 `RetrainingCenterViewModel.emptyStateMessage`。"
                          + "视图里另写一句的话，守着那句话的测试就空转了。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("onGo(.today)"),
                      "空状态那颗按钮点下去哪儿也不去，用户读完还得自己回侧边栏翻。")
    }

    // MARK: - 要求 6：退休不等于删除

    func testRetiredTargetsAreStillListedAndCanBePutBack() throws {
        let code = try Self.viewCode()
        let section = try SourceGuard.memberBody(of: "private var retiredSection", in: code)
        XCTAssertTrue(section.contains("model.retired"),
                      "已退休的目标不再列出来。**退休不等于删除**——凭空消失会让用户"
                          + "以为自己按错了什么，而这一步本来就是他自己点的。"
                          + "实际取到的是：\n\(section)")
        XCTAssertTrue(section.contains("retiredRow(item)"),
                      "遍历了退休目标却没有画出每一条。实际取到的是：\n\(section)")
        XCTAssertTrue(section.contains("不是系统替你判定"),
                      "折叠区里没有说清「这些是你自己标的，不是系统替你判定改掉了」。"
                          + "计划的「决定 4」写死了这一条：系统永远不替用户做这个判定，"
                          + "那就得在界面上说出来。实际取到的是：\n\(section)")
        XCTAssertTrue(section.contains(".monospacedDigit()"),
                      "折叠区标题里那个条数没用等宽数字（规范第 1 节最后一行）。")
        SourceGuard.assertRenders(
            "retiredSection", inBodyOf: "var body: some View", of: Self.view,
            because: "退休区写好了却没摆进 `body`，用户没有任何办法把一个目标放回来。")

        let row = try SourceGuard.memberBody(of: "private func retiredRow", in: code)
        XCTAssertTrue(row.contains("Button(\"重新放回待复训\")"),
                      "「重新放回待复训」这颗按钮不见了。折叠区里那句话明写"
                          + "「点它右边的「重新放回待复训」」，指一颗不存在的按钮比不写还糟。"
                          + "实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains("restore(item)"),
                      "那颗按钮点下去没有动作。实际取到的是：\n\(row)")
    }

    /// **禁止静默失败（铁律 7）。** 复审实测把 `notice = app.setRetrainingStatus(...)`
    /// 改成 `_ = app.setRetrainingStatus(...)`，941 条全绿——而那之后
    /// 「重新放回待复训」失败时列表纹丝不动，一个字的解释都没有，用户只会再点一次。
    func testPuttingATargetBackSaysSoWhenItDoesNotWork() throws {
        let code = try Self.viewCode()
        let restore = try SourceGuard.memberBody(of: "private func restore", in: code)
        XCTAssertTrue(restore.contains("app.setRetrainingStatus(.new, of: item.target.id)"),
                      "「重新放回待复训」没有真的去改状态。实际取到的是：\n\(restore)")
        XCTAssertTrue(restore.contains("notice = app.setRetrainingStatus("),
                      "改状态的结果被丢掉了（铁律 7）。`AppState.setRetrainingStatus` "
                          + "失败时返回的是一句中文说明，必须接住并显示出来——"
                          + "静默的话用户会看到列表纹丝不动而没有任何解释，只会再点一次。"
                          + "实际取到的是：\n\(restore)")

        SourceGuard.assertOmits(
            "_ = app.setRetrainingStatus(", in: Self.view,
            because: "改状态的结果被 `_ =` 丢掉了，失败时一声不吭（铁律 7）。"
                + "下一步：接住那句中文说明，赋给 `notice` 让它上屏。")

        SourceGuard.assertRenders(
            "noticeCard", inBodyOf: "var body: some View", of: Self.view,
            because: "那句中文说明写好了却没摆进 `body`，失败时用户一个字都看不到。")
        // 2026-08-30 改版：这块从手搓的「CoachCard + 三角图标 + 警告色」换成了 `NoticeCard`。
        // 语义色、图标、可选中现在**由那个组件保证**，所以这里守的是「用的是警告那一档」，
        // 底下三件事由 `testTheNoticeComponentAlwaysCarriesItsTintIconAndSelectableText` 一并守。
        let notice = try SourceGuard.memberBody(of: "private var noticeCard", in: code)
        XCTAssertTrue(notice.contains("NoticeCard(.warning"),
                      "失败说明没走 `NoticeCard(.warning …)`，混在正文里没人会注意到。"
                          + "实际取到的是：\n\(notice)")
    }

    /// `NoticeCard` 是全项目每一句「发生了什么 + 下一步做什么」的唯一出口。
    ///
    /// 改版前这块在六个页面各手搓了一遍，于是「语义色 / 图标 / 文字可选中」这三件事
    /// 要在六处各守一遍——而实际上只有两三处真的守着。现在收成一个组件，
    /// 这一条替所有调用点守住那三件事：
    ///
    /// - **语义色**：不标出来就会混在正文里没人注意到；
    /// - **图标**：光靠颜色传达状态过不了无障碍那一关（规范第 4 节）；
    /// - **可选中**：这些句子里带着目标编号、文件路径，用户要复制出来核对。
    func testTheNoticeComponentAlwaysCarriesItsTintIconAndSelectableText() throws {
        let body = try SourceGuard.memberBody(
            of: "public struct NoticeCard",
            in: try SourceGuard.code("DesignSystem/Components.swift"))
        for (needle, why) in [
            ("Image(systemName: symbol)", "没有图标——只靠颜色传达状态，色觉障碍的用户看不出这是一条警告"),
            ("foregroundStyle(tint)", "图标没上语义色，四种语气长得一模一样"),
            ("Palette.warning", "警告那一档没有接到 `Palette.warning`"),
            ("Palette.danger", "错误那一档没有接到 `Palette.danger`"),
            (".textSelection(.enabled)", "文字选不中——这些句子里带着目标编号和文件路径，用户要复制出来核对")
        ] {
            XCTAssertTrue(body.contains(needle),
                          "`NoticeCard` 里\(why)（缺 `\(needle)`）。"
                              + "它是全项目每一句提示的唯一出口，这里丢一样，六个页面一起丢。")
        }
    }

    // MARK: - 要求 7：从别的页面跳过来，只生效一次

    /// **只消费一次。** 不清空的话，用户在这一页点开别的目标，
    /// 每次重绘都会被弹回最初那一个，他会以为界面点不动。
    /// 清空这一半由 `NavigationState` 自己那条测试真跑起来验；这里只管接线——
    /// 判断写对了却没人调用，等于没写。
    func testTheCrossPageJumpIsAdoptedExactlyOnceAndScrollsToThatTarget() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "adoptPendingTarget(using: proxy)", inBodyOf: "var body: some View", of: Self.view,
            because: "从今日训练跳过来时没人去取那个预选目标，用户点「复训一个旧问题」"
                + "会落到一页普通的列表上，不知道该点哪一条。")

        let adopt = try SourceGuard.memberBody(of: "private func adoptPendingTarget", in: code)
        XCTAssertTrue(adopt.contains("app.navigation.consumePendingRetrainingTarget()"),
                      "没有走 `consumePendingRetrainingTarget()`。自己读 "
                          + "`pendingRetrainingTargetID` 而不清空的话，用户点开别的目标"
                          + "每次重绘都会被弹回最初那一个。实际取到的是：\n\(adopt)")
        XCTAssertTrue(adopt.contains("selectedID = targetID"),
                      "取到了预选目标却没有选中它。实际取到的是：\n\(adopt)")
        XCTAssertTrue(adopt.contains("proxy.scrollTo(targetID"),
                      "选中了却没有滚过去。目标多的时候它在屏幕外，用户看到的是"
                          + "一页没有主行动卡片的列表。实际取到的是：\n\(adopt)")
        XCTAssertTrue(adopt.contains("if reduceMotion"),
                      "滚动没有按「减弱动态效果」分支（规范第 5 节）。实际取到的是：\n\(adopt)")
    }

    // MARK: - 三步流程页要真的弹得出来，回来之后要重读

    func testTheFlowSheetIsPresentedAndTheStateIsRereadWhenItCloses() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains(".sheet(item: $flow"),
                      "三步流程页弹不出来。这一页所有按钮点下去都不会有任何事发生。")
        XCTAssertTrue(code.contains("RetrainingFlowView(app: app"),
                      "sheet 里没有 `RetrainingFlowView`。实际取到的源码里找不到这一句。")
        XCTAssertTrue(code.contains("onDismiss: { app.reload() }"),
                      "关掉三步流程之后没有重读 state.json。一趟复训会改训练记录、"
                          + "复训台账和错题本，不重读的话这一页显示的还是开练之前那份，"
                          + "用户会以为刚才那一趟没算数（铁律 7）。")
        XCTAssertTrue(code.contains("originalQuestionID: originalQuestionID(of: item)")
                          || code.contains("originalQuestionID: originalQuestionID("),
                      "没有把「来源那一场练的是哪道题」传给三步流程。"
                          + "「这一场算原题重练还是换题验证」全靠它判，不传就永远判成换题验证。")

        let launch = try SourceGuard.memberBody(of: "private func originalQuestionID", in: code)
        XCTAssertTrue(launch.contains("?? \"\""),
                      "来源记录也被删掉时没有退回空串。那时是真的无从得知，"
                          + "而这个函数必须永远给得出答案（含义写在它自己的注释里）。"
                          + "实际取到的是：\n\(launch)")
    }
}
