import Foundation
import SwiftUI
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

/// 问题档案页的视图层守卫，一条对一条地钉住计划 Task 6 Step 3 给这一页的十二条验收要求。
///
/// ## 为什么这一页需要这么一份测试
///
/// 计划 Task 6 只给了视图模型的两处突变，把 `View` 的正确性推给 Task 11 的人工验收。
/// `HistoryViewTests` / `RetrainingCenterViewTests` 的文件注释里已经写过同一件事的结论：
/// **人工验收只跑一次，而回归会发生无数次。** 本项目实测过三次「整段渲染删掉、全绿」。
///
/// 所以这一页也照那两页的办法办：能抽成纯函数的（趋势配色、汇总那句话、点开哪一行）
/// 真跑起来验，剩下的接线扫源码。
///
/// ## 边界（与 `HistoryViewTests` / `RetrainingCenterViewTests` 一致）
///
/// 扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——
/// 那部分归 Task 11 的人工验收。它拦得住的是：整段渲染被删、数据源被换掉、
/// 警告被吞掉、写好的组件没摆进页面。
@MainActor
final class IssueArchiveViewTests: XCTestCase {

    private static let view = "Issues/IssueArchiveView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct IssueArchiveView"),
                      "没扫到 IssueArchiveView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 要求 1：页头

    func testThePageHeaderSaysWhichPageThisIsAndWhatItIsFor() throws {
        SourceGuard.assertRenders(
            "PageHeader(number: 1, label: \"ISSUE ARCHIVE\"",
            inBodyOf: "private var header", of: Self.view,
            because: "页头不见了，用户点进来看到的是一堆没有标题的卡片"
                + "（DESIGN-SYSTEM 第 4 节）。")
        let header = try SourceGuard.memberBody(of: "private var header", in: try Self.viewCode())
        XCTAssertTrue(header.contains("你的问题档案"),
                      "页头的中文标题不见了。实际取到的是：\n\(header)")
        SourceGuard.assertRenders(
            "header", inBodyOf: "var body: some View", of: Self.view,
            because: "页头写好了却没摆进 `body`。下一步：把它放回去。")
    }

    // MARK: - 要求 2：标题下那行汇总，三个数字都得等宽

    /// 汇总那句话抽成纯函数，理由和 `HistoryView.speakerText(for:)` 一样：
    /// 扫源码只问得出「这儿有个 `Text`」，问不出它到底说了什么。
    func testTheSummaryLineQuotesAllThreeNumbers() {
        let text = IssueArchiveView.summaryText(total: 7, new: 2, improving: 3)
        XCTAssertTrue(text.contains("7"), "汇总里没有问题总数：\(text)")
        XCTAssertTrue(text.contains("2"), "汇总里没有「新问题」的个数：\(text)")
        XCTAssertTrue(text.contains("3"), "汇总里没有「正在变少」的个数：\(text)")
        XCTAssertTrue(text.contains("新问题"), "汇总没说清第二个数字是什么：\(text)")
        XCTAssertTrue(text.contains("变少"), "汇总没说清第三个数字是什么：\(text)")
    }

    func testTheSummaryLineIsBuiltFromTheViewModelCountsAndUsesMonospacedDigits() throws {
        let summary = try SourceGuard.memberBody(of: "private var summaryLine",
                                                 in: try Self.viewCode())
        XCTAssertTrue(summary.contains("summaryText(total:"),
                      "汇总那句话不是从 `summaryText` 来的，上面那条真跑起来的测试就在测"
                          + "一段没人用的实现。实际取到的是：\n\(summary)")
        XCTAssertTrue(summary.contains("counts.total") && summary.contains("counts.new")
                          && summary.contains("counts.improving"),
                      "汇总的三个数字没有全部来自 `IssueArchiveViewModel.counts`。"
                          + "实际取到的是：\n\(summary)")
        XCTAssertTrue(summary.contains(".monospacedDigit()"),
                      "汇总里的数字没用等宽数字。「共 9 个问题」跳到「共 10 个问题」时整行会"
                          + "横向抖一下（规范第 6 节最后一条）。实际取到的是：\n\(summary)")
        SourceGuard.assertRenders(
            "summaryLine", inBodyOf: "var body: some View", of: Self.view,
            because: "汇总那一行写好了却没摆进 `body`，用户看不到「一共几个、几个是新的、"
                + "几个正在变少」——那正是这一页最该先说的一句话。")
    }

    // MARK: - 要求 3：筛选控件

    func testTheFilterControlOffersEveryFilterFromTheModel() throws {
        let picker = try SourceGuard.memberBody(of: "private var filterPicker",
                                               in: try Self.viewCode())
        XCTAssertTrue(picker.contains("IssueFilter.allCases"),
                      "筛选控件的选项不是 `IssueFilter.allCases`。手抄一份的话，"
                          + "以后加一档筛选界面上不会出现，而 `IssueArchiveViewModelTests` "
                          + "照样绿。实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains(".title"),
                      "选项没用 `IssueFilter.title` 显示，用户看到的会是 `all` `recurring` "
                          + "这种英文 case 名（铁律 6：面向用户的文案必须中文）。"
                          + "实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains("$filter") || picker.contains("selection: $filter"),
                      "筛选控件没和 `filter` 绑起来，点了不会有任何变化。"
                          + "实际取到的是：\n\(picker)")
        SourceGuard.assertRenders(
            "filterPicker", inBodyOf: "var body: some View", of: Self.view,
            because: "筛选控件写好了却没摆进 `body`，用户没有任何办法只看「新问题」。")
    }

    func testTheListIsDrivenByTheSelectedFilter() throws {
        let list = try SourceGuard.memberBody(of: "private var listSection",
                                             in: try Self.viewCode())
        XCTAssertTrue(list.contains("rows(filter: filter)"),
                      "列表没有按当前筛选取行——筛选控件点了会变蓝，列表纹丝不动。"
                          + "实际取到的是：\n\(list)")
        XCTAssertTrue(list.contains("issueCard(row)"),
                      "遍历了行却没有画出每一条，这一页只剩一个页头。实际取到的是：\n\(list)")
        for forbidden in ["sorted", "filter { "] where list.contains(forbidden) {
            XCTFail("列表在视图里又 `\(forbidden)` 了一次。排序与筛选**原样**来自 "
                        + "`IssueArchiveViewModel`，这一页不许再排、再筛——那会造出第二套说法，"
                        + "而依据只有视图模型那一处有测试守着。实际取到的是：\n\(list)")
        }
        SourceGuard.assertRenders(
            "listSection", inBodyOf: "var body: some View", of: Self.view,
            because: "整个问题列表没摆进 `body`，这一页只剩一个页头。")
    }

    // MARK: - 要求 4：时间轴查出来的问题必须显示

    /// **「检查了但没告诉用户」等于没检查。** 本项目已经为同一个毛病写过
    /// `ArchiveOutcome.skipped`：查出问题却不显示，用户拿到的是一个他无法核对的结论。
    func testDataWarningsFromTheTimelineAreShownAboveTheList() throws {
        let code = try Self.viewCode()
        let warning = try SourceGuard.memberBody(of: "private var warningSection", in: code)
        XCTAssertTrue(warning.contains("model.dataWarnings"),
                      "时间轴查出来的数据问题没有上屏。那几条警告说清了「有几场练习只在档案里"
                          + "留了记录」「有几条读不出时间因此趋势可能偏乐观」——不显示的话，"
                          + "用户拿到的是一个他无法核对的趋势。实际取到的是：\n\(warning)")
        XCTAssertTrue(warning.contains("CoachCard"),
                      "警告没有走 `CoachCard`，会混在正文里没人注意到。实际取到的是：\n\(warning)")
        XCTAssertTrue(warning.contains("Palette.warning"),
                      "警告没有用 `Palette.warning` 标出来。实际取到的是：\n\(warning)")
        XCTAssertTrue(warning.contains("Palette.textPrimary"),
                      "警告正文用了警告色写字。`Palette.warning` 是给标记用的，"
                          + "拿它写整段中文正文对比度过不了（DESIGN-SYSTEM 第 2 节）。"
                          + "实际取到的是：\n\(warning)")
        SourceGuard.assertRenders(
            "warningSection", inBodyOf: "var body: some View", of: Self.view,
            because: "警告写好了却没摆进 `body`，等于没查。")
    }

    // MARK: - 要求 5：每一行要显示的东西

    func testEveryRowShowsEverythingTheUserNeedsToActOn() throws {
        let card = try SourceGuard.memberBody(of: "private func issueCard",
                                              in: try Self.viewCode())
        for (field, why) in [
            ("row.learnerSaid", "当时说的那句原话——它是「这条说的是哪个毛病」的唯一依据"),
            ("row.correction", "该怎么改。少了它这一页只是在报忧，用户不知道要做什么"),
            ("row.whyItMatters", "为什么要改"),
            ("row.occurrences", "一共犯过几场"),
            ("row.sessionCount", "出现在几场不同的练习里"),
            ("row.detail", "结论背后的原始数字，用户要靠它自己核对"),
            ("row.lastSeenText", "最近一次是什么时候")
        ] {
            XCTAssertTrue(card.contains(field),
                          "一行里没有\(why)（`\(field)`）。实际取到的是：\n\(card)")
        }
        XCTAssertTrue(SourceGuard.occurrences(of: ".monospacedDigit()", in: card) >= 2,
                      "行里的数字没用等宽数字。「出现在 9 场」跳到「10 场」时整行会横向抖"
                          + "（规范第 6 节最后一条）。实际取到的是：\n\(card)")
    }

    /// 要求 6：新问题的标记**必须是图标 + 文字**。
    ///
    /// 只靠颜色区分对色觉障碍用户等于没有标记（DESIGN-SYSTEM 第 4 节：只用 SF Symbols，
    /// 且颜色只能是辅助）。
    func testTheNewIssueBadgeIsAnIconPlusWordsNotJustAColor() throws {
        let card = try SourceGuard.memberBody(of: "private func issueCard",
                                              in: try Self.viewCode())
        XCTAssertTrue(card.contains("row.isNew"),
                      "「新问题」标记不见了。第一次出现的毛病和犯了十场的老毛病长得一模一样，"
                          + "用户分不出哪个该先治。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("Label(\"新问题\", systemImage:"),
                      "「新问题」不是「SF Symbol + 文字」的形式。只靠颜色区分对色觉障碍用户"
                          + "等于没有标记。实际取到的是：\n\(card)")
    }

    /// 要求 7：趋势的语义色。**颜色只是辅助，文字标签必须始终在。**
    func testTheTrendBadgeAlwaysCarriesWordsAndTheColourIsOnlyAHint() throws {
        let badge = try SourceGuard.memberBody(of: "private func trendBadge",
                                              in: try Self.viewCode())
        XCTAssertTrue(badge.contains("row.trend.badge"),
                      "趋势标签没有显示 `IssueTrend.badge` 那几个字，只剩一块颜色——"
                          + "色觉障碍用户什么都读不到。实际取到的是：\n\(badge)")
        XCTAssertTrue(badge.contains("Radius.pill"),
                      "趋势标签没做成 pill（计划要求 7）。实际取到的是：\n\(badge)")
        XCTAssertTrue(badge.contains("Self.trendColor(row.trend)"),
                      "趋势的配色不是从 `trendColor(_:)` 来的，下面那条真跑起来的测试"
                          + "就在测一段没人用的实现。实际取到的是：\n\(badge)")
    }

    /// 配色映射真跑一遍。扫源码问不出「`.increasing` 到底被画成了什么颜色」。
    func testTrendColoursMatchWhatEachTrendMeans() {
        XCTAssertEqual(IssueArchiveView.trendColor(.gone), Palette.success,
                       "「最近没再出现」不是好消息色")
        XCTAssertEqual(IssueArchiveView.trendColor(.decreasing), Palette.success,
                       "「出现变少了」不是好消息色")
        XCTAssertEqual(IssueArchiveView.trendColor(.increasing), Palette.danger,
                       "「出现变多了」没有被标出来，用户扫一眼看不出哪个在恶化")
        XCTAssertEqual(IssueArchiveView.trendColor(.steady), Palette.warning,
                       "「还是老样子」被画成了和好消息一样的颜色")
        XCTAssertEqual(IssueArchiveView.trendColor(.fresh), Palette.textSecondary,
                       "「新问题」被画成了好／坏消息色。它既不是好消息也不是坏消息，"
                           + "之前根本没犯过")
        XCTAssertEqual(IssueArchiveView.trendColor(.notEnoughData), Palette.textSecondary,
                       "「还看不出趋势」被画上了语义色，等于给了一个还没下的结论")
    }

    /// 上一条只比对了六个取值，**这一条守的是「六个还在不在」**：
    /// `IssueTrend` 将来加一档而这里漏掉一支，编译器会逼人补——但只有在 switch
    /// 穷尽的前提下。所以顺便钉住「不许用 `default:` 兜底」。
    func testTheTrendColourSwitchIsExhaustiveSoANewTrendCannotSlipThrough() throws {
        let mapping = try SourceGuard.memberBody(of: "static func trendColor",
                                                 in: try Self.viewCode())
        XCTAssertFalse(mapping.contains("default:"),
                       "趋势配色用了 `default:` 兜底。将来 `IssueTrend` 加一档，"
                           + "它会被静默地画成兜底那个颜色，编译器一声不吭。"
                           + "下一步：逐档写全。实际取到的是：\n\(mapping)")
        for trend in IssueTrend.allCases {
            XCTAssertTrue(mapping.contains(".\(trend.rawValue)"),
                          "趋势配色里没有 `.\(trend.rawValue)` 这一支。实际取到的是：\n\(mapping)")
        }
    }

    // MARK: - 要求 8：点开一行看「这个结论是怎么来的」

    /// 抽成纯函数的理由与 `HistoryView.toggling(_:to:)` 一致：扫源码只问得出
    /// 「这一行给 `expandedID` 赋了个值」，赋成 nil 也满足——而那之后
    /// `if expandedID == row.id` 永远为假，解释永远画不出来。
    func testClickingARowTogglesItOpenAndClosed() {
        XCTAssertEqual(IssueArchiveView.toggling(nil, to: "i1"), "i1",
                       "点一条没展开的行，没有展开它")
        XCTAssertNil(IssueArchiveView.toggling("i1", to: "i1"),
                     "再点一次同一行，没有收起来")
        XCTAssertEqual(IssueArchiveView.toggling("i1", to: "i2"), "i2",
                       "点另一行时没有换过去")
    }

    func testTheExplanationIsWiredUpAndSaysWhatToDoNext() throws {
        let card = try SourceGuard.memberBody(of: "private func issueCard",
                                              in: try Self.viewCode())
        XCTAssertTrue(card.contains("expandedID = Self.toggling(expandedID, to: row.id)"),
                      "行点下去没有把展开状态交给 `IssueArchiveView.toggling(_:to:)`。"
                          + "自己写一句赋值的话，赋成 nil 也扫得过，而那之后解释永远画不出来。"
                          + "实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("expandedID == row.id"),
                      "展开状态没有被用来决定画不画那段解释。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("row.trend.explanation"),
                      "展开之后没有显示 `IssueTrend.explanation`。那段话是这一页唯一"
                          + "告诉用户「下一步做什么」的地方（铁律 6）——自己另写一句的话，"
                          + "`IssueTrendAnalyzerTests` 里守着那段文案的测试就空转了。"
                          + "实际取到的是：\n\(card)")

        // 那段解释真的每一档都带「下一步」，由 Core 那边的测试钉着；这里只再确认一次
        // 「这一页拿到手的确实是带下一步的那份」，免得有人换成了 `badge`。
        for trend in IssueTrend.allCases {
            XCTAssertTrue(trend.explanation.contains("下一步"),
                          "\(trend) 的解释里没有「下一步」")
        }
    }

    // MARK: - 要求 9 / 10：两种空状态

    func testTheEmptyArchiveGivesAllThreeThings() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "emptyState", inBodyOf: "private var listSection", of: Self.view,
            because: "一个问题都没有时这一页不再走空状态那一支，用户看到的是一片空白"
                + "（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。")
        let empty = try SourceGuard.memberBody(of: "private var emptyState", in: code)
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "空状态没走 `EmptyStateView`，那三样（现状 / 下一步 / 一颗按钮）"
                          + "就没人管得住了。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("问题档案还是空的"),
                      "空状态没说清现状。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("下一步") || empty.contains("练一场"),
                      "空状态没说下一步该干什么。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("onGo(.today)"),
                      "空状态那颗按钮点下去哪儿也不去，用户读完还得自己回侧边栏翻。"
                          + "实际取到的是：\n\(empty)")
    }

    /// **筛选之后为空同样不能留白。** 选了「新问题」而一条都没有时摆一片空白，
    /// 用户会以为是筛选控件坏了。
    func testFilteringDownToNothingAlsoSaysSoAndOffersAWayBack() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "filteredEmptyState", inBodyOf: "private var listSection", of: Self.view,
            because: "筛到一条都不剩时这一页是一片空白，用户会以为筛选控件坏了。")
        let empty = try SourceGuard.memberBody(of: "private var filteredEmptyState", in: code)
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "筛选后的空状态没走 `EmptyStateView`。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("filter = .all"),
                      "「换成全部看看」那颗按钮点下去不会真的换回全部。"
                          + "按钮点了没反应是本项目最不能接受的那一类。实际取到的是：\n\(empty)")

        let hint = IssueArchiveView.filteredEmptyHint(.new)
        XCTAssertTrue(hint.contains(IssueFilter.new.title),
                      "筛选后的空状态没说清是哪一档筛空了：\(hint)")
        XCTAssertTrue(hint.contains("下一步"), "筛选后的空状态没说下一步做什么：\(hint)")
        XCTAssertTrue(hint.contains(IssueFilter.all.title),
                      "筛选后的空状态没告诉用户可以换回「全部」：\(hint)")
    }

    // MARK: - 要求 11：这一页不许出现任何分数、评级、水平判断

    /// DEFINITION-OF-DONE 第 4 节明令禁止雅思分数预测：给「你大概 6.5 分」这种数字
    /// 既不准也有害，会让人盯着数字而不是盯着问题。
    /// 这一页只回答「这个毛病出现了几次、最近有没有变少」。
    func testThisPageNeverPredictsABandScore() throws {
        let code = try Self.viewCode()
        for banned in ["band", "Band", "分数", "评分", "打分", "几分", "水平判断", "预测"] {
            XCTAssertFalse(
                code.contains(banned),
                "问题档案页里出现了「\(banned)」。本阶段不得出现任何形式的雅思分数预测或"
                    + "水平判断（DEFINITION-OF-DONE 第 4 节）。"
                    + "下一步：改成只说「这个毛病出现了几次、最近有没有变少」。")
        }
    }

    // MARK: - 接线：这一页得真的挂在侧边栏上

    func testTheSidebarActuallyRoutesToThisPage() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(root.contains("case .issues: IssueArchiveView(app: app"),
                      "`RootView` 的 detail 分支里没有这一页，侧边栏点「问题档案」落到的还是"
                          + "那张「还没做」的占位页——而 `SidebarItem.issues.isImplemented` "
                          + "已经写成 true，占位页连说明都不会有。")
    }
}
