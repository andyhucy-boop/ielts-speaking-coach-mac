import Foundation
import XCTest

@testable import IELTSCoachUI

/// 复盘报告页的视图层守卫。**这一页此前视图层一条测试都没有。**
///
/// `ReviewReportViewModel` / `ReviewReportLoader` 已经被 `ReviewReportViewModelTests` 测得很扎实：
/// 分区怎么拆、优先目标怎么取、会话怎么排序、读不到时说哪句话，全都钉死了。
/// 缺的一直是最后一步——**那些算好的东西真的被画到屏幕上了吗**。实测确认过两处：
///
/// - 把 `reportPane` 里 `ForEach(document.sections)` 换成 `ForEach([ReviewSection]())`
///   → **484 条全绿**。调用点还在、可达性检查也还在，但「必须纠正的表达 / 更自然的说法 /
///   词汇升级 / 逐题高分版」一条都不画，右半边只剩一行文件路径。
/// - 删掉 `if let target = document.priorityTarget { priorityCard(target) }` 那一句、
///   同时删掉整个 `priorityCard` 函数（干净删除、不留孤儿）→ **484 条全绿**。
///   而那块深色的 NEXT SINGLE TARGET 是这个文件自己的注释写的
///   「设计稿里最显眼的一块，也是这个产品真正的价值所在」：
///   复盘给出的那**一个**具体目标，成品标准第 2 节「改进闭环」的起点。没有它，
///   这一页就退化成一份读完就忘的清单。
///
/// 第二个突变说明了为什么本文件里每一条断言都要**连数据源一起钉**：
/// 「函数被调了」问不出「喂进去的是不是真数据」，「声明还在」问不出「有没有摆上屏」。
/// 所以下面统一的写法是——**在渲染那一段的大括号里，找那句带着数据源的调用**
/// （`ForEach(document.sections)`、`originalFileFooter(document.path)`、
/// `if let target = document.priorityTarget`），而不是在全文里找一个名字。
///
/// **边界（与 `TodayViewTests` / `PracticeSheetTests` 一致，是实测出来的不是估计的）**：
/// 扫源码不执行代码。「调用还在但条件永远为假」（`if let x, false`）拦不住，
/// 排版好不好看、那块深色摆得对不对也拦不住——那部分归 Task 11 人工验收。
/// 它拦得住的是本项目已经真实发生过四次的那一种：整段渲染被删、数据源被换成空的、
/// 写好的组件没摆进页面。
final class ReviewReportViewTests: XCTestCase {

    private static let view = "Review/ReviewReportView.swift"

    /// 去过注释的页面源码。读不到会**抛错**——`SourceGuard` 不会拿空串把下面每条断言变成恒真。
    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 右半边那一整块的大括号内容。这一页几乎所有「有没有画出来」的问题都问在这里面。
    ///
    /// 扫这一段而不是扫全文，是因为同一个文件里到处是「残影」：
    /// `document`、`sections`、`priorityCard` 这些名字在声明处、在 `loadSelected` 里、
    /// 在 `emptyState` 的文案里都还各有一份，扫全文的话把真正画出来的那句删掉照样绿。
    private static func reportPaneBody() throws -> String {
        try SourceGuard.memberBody(of: "private var reportPane", in: try viewCode())
    }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都是恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct ReviewReportView"),
                      "没扫到 ReviewReportView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
        XCTAssertFalse(try Self.reportPaneBody().trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty,
                       "`reportPane` 的大括号里是空的，右半边什么都不画。"
                           + "下一步：确认这一段渲染是不是被整段清空了。")
    }

    // MARK: - 一、NEXT SINGLE TARGET：这个产品真正的价值所在

    /// **这一条守的是整个产品的核心价值。**
    ///
    /// 复审实测：把 `reportPane` 里那句 `if let target = document.priorityTarget
    /// { priorityCard(target) }` 删掉，同时把整个 `priorityCard` 函数一起删掉
    /// （干净删除，不留孤儿，可达性扫描也扫不出问题）——**484 条全绿**。
    ///
    /// 用户那边的后果：复盘还是一长串清单，但「下次只盯这一个」那句话没了。
    /// 成品标准第 2 节的「改进闭环」是靠这一个目标闭合的——没有它，
    /// 用户练完看一眼、点点头、下次照旧，这个工具就退化成一个复盘存档器。
    ///
    /// 所以这里三层一起钉：**调用点在**、**喂进去的是 `document.priorityTarget`**、
    /// **函数体里真的画出了那三样**（标题、目标本身、下一步怎么用它）。
    func testThePriorityTargetCardIsPaintedFromTheDocument() throws {
        // ① 数据源：右半边必须从 document 里取那个优先目标。
        SourceGuard.assertRenders(
            "document.priorityTarget", inBodyOf: "private var reportPane", of: Self.view,
            because: "右半边根本没有去取 `document.priorityTarget`。那块深色的 NEXT SINGLE TARGET"
                + "（这个文件自己的注释写的「设计稿里最显眼的一块，也是这个产品真正的价值所在」）"
                + "整块消失，复盘退化成一份读完就忘的清单，成品标准第 2 节的「改进闭环」当场断掉。"
                + "下一步：把 `if let target = document.priorityTarget { priorityCard(target) }` "
                + "放回 `reportPane` 最上面；换了别的写法就同步改这条测试。")

        // ② 调用点：取到了还得真的画。
        SourceGuard.assertRenders(
            "priorityCard(", inBodyOf: "private var reportPane", of: Self.view,
            because: "取到了优先目标却没有把 `priorityCard(…)` 摆进 `reportPane`——"
                + "算出来的东西一个像素都不上屏，而且不会有任何编译错误。"
                + "下一步：把这句调用放回去。")

        // ③ 两者接在一起：取到的那个值就是喂给卡片的那个值。
        //    只分别断言 ①② 的话，`priorityCard(ReviewRow(id:"",…))` 这种假数据也能过。
        let pane = try Self.reportPaneBody()
        let bound = try SourceGuard.memberBody(of: "if let target = document.priorityTarget",
                                               in: pane)
        XCTAssertTrue(bound.contains("priorityCard(target)"),
                      "`if let target = document.priorityTarget` 这一支里没有 `priorityCard(target)`，"
                          + "也就是取到了优先目标却拿它去画了别的东西（或者什么都没画）。"
                          + "实际取到的那一段是：\n\(bound)"
                          + "\n下一步：把 `priorityCard(target)` 放回这一支里。")

        // ④ 顺序：它必须排在所有分区前面。排到下面去，用户滚不到就看不见，
        //    而「排在最前面」正是这个文件顶上那段注释写死的要求。
        guard let targetAt = pane.range(of: "priorityCard("),
              let sectionsAt = pane.range(of: "ForEach(document.sections)") else {
            return XCTFail("在 `reportPane` 里找不到 `priorityCard(` 或 `ForEach(document.sections)`，"
                           + "这条顺序断言等于空转。下一步：先修好上面那几条。")
        }
        XCTAssertTrue(targetAt.lowerBound < sectionsAt.lowerBound,
                      "NEXT SINGLE TARGET 被排到了各个分区后面。复盘长的时候它会落在屏幕外，"
                          + "用户滚不到就看不见——而这一页存在的理由就是让他看见那一个目标。"
                          + "下一步：把 `priorityCard(target)` 移回 `reportPane` 的最上面"
                          + "（失败提示与「有几节没能显示出来」之外，它排第一）。")
    }

    /// 那块卡片自己得真的画出「目标是什么」和「拿它干什么」。
    ///
    /// 只钉调用点的话，把 `priorityCard` 的函数体掏成 `EmptyView()` 照样绿——
    /// 用户看到的是一块纯深色的空条。
    func testThePriorityCardShowsTheTargetAndWhatToDoWithIt() throws {
        SourceGuard.assertRenders(
            "private func priorityCard", in: Self.view,
            because: "`priorityCard` 这段声明被删了。下一步：先想清楚那块 NEXT SINGLE TARGET "
                + "现在由谁负责——没人负责的话，这个产品的「改进闭环」就没有起点了。")

        for (needle, what) in [
            ("NEXT SINGLE TARGET", "这块深色卡片的抬头（设计稿第 5 屏）"),
            ("target.primary", "下次要盯的那一个目标本身——这是整块卡片唯一不可省的内容"),
            ("target.note", "「你当时说的」那句原话，没有它用户不知道这个目标从哪儿来的"),
            ("下次练习时只盯这一个", "怎么用这个目标（铁律 4 要求的「下一步做什么」）")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func priorityCard", of: Self.view,
                because: "这块卡片里没有\(what)。下一步：把它画回去；"
                    + "换了别的字段名或措辞就同步改这条测试。")
        }
    }

    // MARK: - 二、四个分区：复盘的正文

    /// **这一条守的是复盘正文，而且是连数据源一起守。**
    ///
    /// 复审实测：把 `ForEach(document.sections)` 换成 `ForEach([ReviewSection]())`——
    /// 调用点还在（`sectionCard(section)` 一个字没动）、可达性扫描照样走得到、
    /// **484 条全绿**。用户那边：「必须纠正的表达」「更自然的表达」「词汇升级」
    /// 「逐题高分版」四节一条都不画，右半边只剩优先目标和一行文件路径，
    /// 而 `ReviewReportViewModelTests` 里那十几条拆分区的断言当场变成空转——
    /// 拆得再对，没人画。
    ///
    /// 所以这里问的不是「`sectionCard` 被调了吗」，而是
    /// **「`ForEach` 遍历的是不是 `document.sections`，循环体里是不是真的在画每一节」**。
    func testEverySectionOfTheReviewIsPaintedFromTheDocumentsSections() throws {
        SourceGuard.assertRenders(
            "ForEach(document.sections)", inBodyOf: "private var reportPane", of: Self.view,
            because: "右半边不再遍历 `document.sections`——复盘的四个分区（必须纠正的表达、"
                + "更自然的表达、词汇升级、逐题高分版）一条都不会画出来，"
                + "而 `ReviewReportViewModelTests` 里那十几条拆分区的断言会一起退化成空转："
                + "拆得再对也没人画。**注意换成 `ForEach([ReviewSection]())` 这种空数组也算这一类**，"
                + "它编得过、跑得动、界面上什么都没有。"
                + "下一步：把 `ForEach(document.sections) { section in sectionCard(section) }` 放回去。")

        let pane = try Self.reportPaneBody()
        let loop = try SourceGuard.memberBody(of: "ForEach(document.sections)", in: pane)
        XCTAssertTrue(loop.contains("sectionCard(section)"),
                      "遍历到了 `document.sections`，循环体里却没有 `sectionCard(section)`——"
                          + "每一节都被遍历了一遍然后什么都没画。实际取到的循环体是：\n\(loop)"
                          + "\n下一步：把 `sectionCard(section)` 放回循环体里。")
    }

    /// 一节卡片自己得画出：这一节叫什么、有几条、每一条长什么样。
    ///
    /// 第三条同样是「连数据源一起钉」：把 `ForEach(Array(section.rows.enumerated())` 换成空数组，
    /// 整节就只剩一个标题和一个「N 条」，底下全白——那正是 `ReviewRow.isBlank` 的注释里
    /// 写的「看着像渲染坏了」的样子，只不过这次是真的坏了。
    func testASectionCardShowsItsTitleCountAndEveryRow() throws {
        for (needle, what) in [
            ("section.title", "这一节叫什么（不标题的话四节混成一片，谁也认不出哪节是哪节）"),
            ("section.rows.count", "这一节有几条"),
            ("ForEach(Array(section.rows.enumerated())", "逐条遍历这一节的内容")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func sectionCard", of: Self.view,
                because: "分区卡片里没有\(what)。下一步：把它画回去；"
                    + "特别注意遍历的必须是 `section.rows` 本身——换成空数组一样编得过，"
                    + "而界面上这一节就只剩一个标题、底下全白。")
        }

        let card = try SourceGuard.memberBody(of: "private func sectionCard",
                                             in: try Self.viewCode())
        let loop = try SourceGuard.memberBody(of: "ForEach(Array(section.rows.enumerated())",
                                              in: card)
        XCTAssertTrue(loop.contains("rowView(row, in: section)"),
                      "逐条遍历了这一节，循环体里却没有 `rowView(row, in: section)`——"
                          + "每一条都被遍历了一遍然后什么都没画。实际取到的循环体是：\n\(loop)"
                          + "\n下一步：把 `rowView(row, in: section)` 放回循环体里。")
    }

    /// 一行三格，**三格各画各的**。
    ///
    /// `ReviewRow` 的注释写明三格的含义由所属分区说了算（「必须纠正的表达」里第二格是改正后的说法，
    /// 「逐题高分版」里第二格是学员原来的回答）。所以标注必须跟着分区走，取值必须跟着行走——
    /// 少画一格，或者三格都画成 `row.primary`，用户看到的是
    /// 「good / good / good」这种谁也看不出所以然的东西，而且不会有任何编译错误。
    func testEveryRowPaintsAllThreeFieldsWithTheLabelsItsSectionDefines() throws {
        let rowView = try SourceGuard.memberBody(of: "private func rowView", in: try Self.viewCode())
        let fields: [(label: String, value: String, what: String)] = [
            ("section.primaryLabel", "row.primary", "你当时说的那句原话"),
            ("section.secondaryLabel", "row.secondary", "改成什么——这一行真正要看的东西"),
            ("section.noteLabel", "row.note", "为什么要改 / 什么时候用")
        ]
        for field in fields {
            XCTAssertTrue(rowView.contains(field.label),
                          "行里没有 `\(field.label)` 这个标注。`ReviewRow` 三格的含义由分区说了算，"
                              + "不标注的话 `good / rewarding / a rewarding trip` 摆在一起，"
                              + "谁也看不出哪行是自己说的、哪行是建议。下一步：把标注画回去。")
            XCTAssertTrue(rowView.contains(field.value),
                          "行里没有 `\(field.value)`，也就是「\(field.what)」这一格根本不画。"
                              + "下一步：把这一格补回去；换了字段名就同步改这条测试。")
        }
    }

    // MARK: - 三、原文在哪儿：本工具读不出来的，用户自己读得出来

    /// 「让用户能自己去看原文」是这一页的硬要求（见 `originalFileFooter` 的注释）。
    ///
    /// 而且路径必须来自 `document.path`：换成一个写死的字符串或者别的路径，
    /// 「在访达中显示原文」就会打开一个不存在的地方，用户会以为自己的复盘丢了——
    /// 这比不显示还糟。
    func testTheOriginalFileFooterIsPaintedWithTheDocumentsOwnPath() throws {
        SourceGuard.assertRenders(
            "originalFileFooter(document.path)", inBodyOf: "private var reportPane", of: Self.view,
            because: "右半边不再显示复盘原文在哪儿。本工具读不出来的字段（`unreadableSections` 说的那种）"
                + "就再也没有别的办法看到了，而那句提示里写的正是「点下面的『在访达中显示原文』」——"
                + "指向一颗不存在的按钮（铁律 4）。**路径必须是 `document.path`**："
                + "换成写死的字符串会打开一个不存在的地方，用户会以为复盘丢了。"
                + "下一步：把 `originalFileFooter(document.path)` 放回 `reportPane` 末尾。")

        for (needle, what) in [
            ("复盘原文：\\(path)", "原文的完整路径（用户要拿它去访达里找）"),
            (#"Button("在访达中显示原文")"#, "直接打开它的那颗按钮"),
            ("NSWorkspace.shared.activateFileViewerSelecting", "按钮真的去访达里选中那个文件")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func originalFileFooter", of: Self.view,
                because: "页脚里没有\(what)。下一步：把它接回去；"
                    + "换了别的按钮标题就同步改这条测试，并确认 `unreadableCard` 那句"
                    + "「点下面的『在访达中显示原文』」指的还是这一颗。")
        }
    }

    // MARK: - 四、悄悄少显示一节：本项目已知最危险的失败形态

    /// 复盘里有内容、却一条都没读出来时，必须说出来。
    ///
    /// 这与 `ArchiveOutcome.skipped` 守的是同一件事：**读出 0 条不等于复盘里没有**。
    /// 不说的话，界面看着完全正常，而用户少看了一整节，永远不会知道。
    func testTheUnreadableSectionsNoticeIsPaintedFromTheDocument() throws {
        SourceGuard.assertRenders(
            "document.unreadableSections", inBodyOf: "private var reportPane", of: Self.view,
            because: "右半边不再检查 `document.unreadableSections`。ChatGPT 换个字段名或者"
                + "把数组写成对象时，那一整节会被悄悄跳过，界面看着完全正常——"
                + "这是本项目已知最危险的失败形态（同 `ArchiveOutcome.skipped`）。"
                + "下一步：把那段警告放回 `reportPane`。")

        SourceGuard.assertRenders(
            "unreadableCard(document.unreadableSections)",
            inBodyOf: "private var reportPane", of: Self.view,
            because: "检查了却没把结果画出来，或者画的不是从 document 里取出的那一份。"
                + "下一步：把 `unreadableCard(document.unreadableSections)` 放回去。")

        for (needle, what) in [
            ("titles.count", "有几节没显示出来"),
            ("titles.joined", "具体是哪几节——不点名的话用户根本不知道该去原文里找什么"),
            ("在访达中显示原文", "下一步怎么补救（铁律 4）")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func unreadableCard", of: Self.view,
                because: "这张警告卡片里没有\(what)。下一步：补回去。")
        }
    }

    /// 解析成功但一个字都没有时，也得说一句。右半边全白会让用户以为程序坏了。
    func testAnEmptyReportSaysSoInsteadOfShowingABlankPane() throws {
        SourceGuard.assertRenders(
            "document.isEmpty", inBodyOf: "private var reportPane", of: Self.view,
            because: "「这份复盘是空的」这一支没了。文件读到了、格式也对、里面什么都没有时，"
                + "右半边是一整片白，用户会以为程序坏了（铁律 5：禁止静默失败）。"
                + "下一步：把 `if document.isEmpty { emptyReportCard() }` 放回去。")

        SourceGuard.assertRenders(
            "emptyReportCard()", inBodyOf: "private var reportPane", of: Self.view,
            because: "判断了是空的，却没有把那张说明卡画出来。下一步：把调用放回去。")

        for (needle, what) in [
            ("这份复盘是空的", "现状：发生了什么"),
            ("下一步：到「今日训练」再练一场", "下一步：该做什么（铁律 4）")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func emptyReportCard", of: Self.view,
                because: "这张卡片里没有说清「\(what)」。下一步：把这句话补回去。")
        }
    }

    // MARK: - 五、读不出原文时的提示

    /// 打不开时那句中文说明（带文件路径）必须上屏，而且要给一条回头路。
    ///
    /// `ReviewReportLoader` 为三种失败各写了一句很用心的中文（文件不见了 / 读不动 / 格式不认得），
    /// 每一句都带着完整路径。这些话只写在 `failure` 这个 `@State` 里是不算数的——
    /// 画不出来的话，用户点开一次练习看到的是一片空白。
    func testTheFailureMessageAndAWayOutAreActuallyPainted() throws {
        SourceGuard.assertRenders(
            "if let failure", inBodyOf: "private var reportPane", of: Self.view,
            because: "右半边不再单独处理「打不开」这一支。`ReviewReportLoader` 为三种失败"
                + "（文件不见了 / 读不动 / 格式不认得）各写的那句带路径的中文，一个字都不上屏，"
                + "用户点开一次练习看到的是一片空白（铁律 5）。"
                + "下一步：把 `if let failure { failureCard(failure) }` 放回 `reportPane` 最前面。")

        SourceGuard.assertRenders(
            "failureCard(failure)", inBodyOf: "private var reportPane", of: Self.view,
            because: "判断了失败，却没有把那句话画出来，或者画的不是 `failure` 里那一句。"
                + "下一步：把 `failureCard(failure)` 放回去。")

        for (needle, what) in [
            ("这一次的复盘打不开", "抬头：发生了什么"),
            ("Text(message)", "那句带着完整文件路径的说明本身——这是唯一告诉用户去哪儿找文件的地方"),
            (#"Button("再试一次", action: loadSelected)"#, "重试的出口（铁律 5：不许只剩一句「失败了」）")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func failureCard", of: Self.view,
                because: "失败卡片里没有\(what)。下一步：补回去；"
                    + "换了别的按钮标题或方法名就同步改这条测试。")
        }

        // 那句话真的是从读盘失败里来的。`loadSelected` 被掏空成 `{}` 时这两条会红。
        for (needle, what) in [
            ("app.loadReview(for: session)", "去读这一次的复盘原文"),
            ("failure = error.localizedDescription", "把失败原因存下来给上面那张卡片画")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func loadSelected", of: Self.view,
                because: "`loadSelected()` 里没有\(what)，这一页要么永远在转圈，"
                    + "要么失败了却一声不吭（铁律 5）。下一步：把这一步接回去。")
        }
    }

    /// 「还没读」和「读完是空的」不能长得一样。
    ///
    /// 前者要说一句「正在打开」，否则用户对着一块白板不知道是在加载还是坏了；
    /// 后者由 `emptyReportCard` 负责。两者混成一样的空白，就是最典型的静默失败。
    func testTheLoadingStateSaysItIsOpeningInsteadOfLookingBroken() throws {
        for (needle, what) in [
            ("ProgressView()", "转圈的指示"),
            ("正在打开这一次的复盘", "一句说明它在干什么")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private var reportPane", of: Self.view,
                because: "还没读出来的那一支里没有\(what)。「还没读」和「读完是空的」长得一模一样，"
                    + "用户分不出是在加载还是程序坏了（铁律 5）。下一步：把它放回 `else` 那一支。")
        }
    }

    /// 换一次会话就得重读一次文件。
    ///
    /// 这句 `.task(id:)` 删掉之后，`loadSelected()` 只在第一次出现时跑一次：
    /// 用户点左边第二次练习，右边显示的还是第一次的复盘——内容看着完全正常，
    /// 但**是别人家的**。这种「显示了错误的正确内容」比空白更难被发现。
    func testSwitchingSessionsReloadsTheReport() throws {
        SourceGuard.assertRenders(
            ".task(id: selected?.id)", inBodyOf: "var body: some View", of: Self.view,
            because: "换会话不再触发重读。用户点左边第二次练习，右边显示的还是上一次的复盘——"
                + "内容看着完全正常，但是别人家的，比一片空白更难被发现。"
                + "下一步：把 `.task(id: selected?.id) { loadSelected() }` 放回 `body` 上；"
                + "换成别的写法（`onChange` 等）就同步改这条测试。")

        SourceGuard.assertRenders(
            "loadSelected()", inBodyOf: ".task(id: selected?.id)", of: Self.view,
            because: "`.task(id:)` 的闭包里没有 `loadSelected()`——换会话时什么都不会发生，"
                + "右半边永远停在「正在打开这一次的复盘…」。下一步：把它放回闭包里。")
    }

    // MARK: - 六、左边那一列会话

    /// 左边这一列必须走 `ReviewReportViewModel.archivedSessions(in:)`。
    ///
    /// 视图里自己现拼一份 `filter` + `sorted` 的话，
    /// `ReviewReportViewModelTests` 里「没有 reportPath 的不能进来」「必须倒序」那两条
    /// 会当场退化成空转——测的是一份没人用的实现。
    /// 而那两条守的都是真事：进来一条没有原文的，点开只会是「找不到复盘原文」，
    /// 用户会以为自己的记录坏了；顺序反了，练完立刻来看的人每次都得滚到底。
    func testTheSessionListComesFromTheViewModelAndIsActuallyPainted() throws {
        SourceGuard.assertRenders(
            "ReviewReportViewModel.archivedSessions(in: app.state)",
            inBodyOf: "private var sessions", of: Self.view,
            because: "这一页自己拼了一份会话列表，没有走 `ReviewReportViewModel.archivedSessions(in:)`。"
                + "那样「没有 reportPath 的不能进来」和「必须按时间倒序」两条测试就都在测"
                + "一份没人用的实现（空转）。下一步：改回调用视图模型。")

        SourceGuard.assertRenders(
            "sessionList", inBodyOf: "var body: some View", of: Self.view,
            because: "左边那一列没有摆进 `body`，用户没有任何办法切换到别的那几次练习——"
                + "这一页就只剩最近一次能看。下一步：把 `sessionList` 放回 `HStack` 里。")

        SourceGuard.assertRenders(
            "reportPane", inBodyOf: "var body: some View", of: Self.view,
            because: "右半边没有摆进 `body`，整页只剩一列日期，复盘一个字都看不到。"
                + "下一步：把 `reportPane` 放回 `HStack` 里。")

        SourceGuard.assertRenders(
            "ForEach(sessions)", inBodyOf: "private var sessionList", of: Self.view,
            because: "左边那一列不再遍历 `sessions`（换成空数组一样编得过），"
                + "列表是空的，用户切不了会话。下一步：把 `ForEach(sessions) { … }` 放回去。")

        let list = try SourceGuard.memberBody(of: "private var sessionList", in: try Self.viewCode())
        let loop = try SourceGuard.memberBody(of: "ForEach(sessions)", in: list)
        XCTAssertTrue(loop.contains("sessionRow(session)"),
                      "遍历了 `sessions`，循环体里却没有 `sessionRow(session)`——列表里每一行都是空的。"
                          + "实际取到的循环体是：\n\(loop)"
                          + "\n下一步：把 `sessionRow(session)` 放回循环体里。")

        SourceGuard.assertRenders(
            "sessions.count", inBodyOf: "private var sessionList", of: Self.view,
            because: "「已归档 N 次」那一行没了。用户看不出自己一共存下过几次复盘，"
                + "也就分不清「列表只有三行」是因为真的只练过三次，还是别的几次没归档成功。"
                + "下一步：把那一行放回去。")
    }

    /// 列表里每一行得能认得出是哪一次，也得真的能点。
    func testEachSessionRowIsIdentifiableAndSelectable() throws {
        for (needle, what) in [
            ("selectedSessionID = session.id", "点下去把这一次标成选中——没有它整列都是死的，"
                + "用户永远只能看最近那一次"),
            ("dateText(session.startedAt)", "这一次是什么时候练的"),
            ("questionText(session)", "练的是哪道题——只有日期的话，"
                + "三次同一天的练习摆在一起分不出哪次是哪次"),
            ("session.focusPart.rawValue", "练的是哪个 Part")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func sessionRow", of: Self.view,
                because: "列表行里没有\(what)。下一步：把它接回去；"
                    + "换了别的字段名就同步改这条测试。")
        }

        // 认不出来的时间戳原样显示，不显示成空白——空白会让人以为这一行坏了。
        SourceGuard.assertRenders(
            "return iso", inBodyOf: "private func dateText", of: Self.view,
            because: "认不出来的时间戳被显示成空白了。用户会以为这一行记录坏了，"
                + "而实际上只是格式认不出来。下一步：认不出来时原样显示那串原文。")
    }

    // MARK: - 七、一次复盘都还没有的时候

    /// 空状态给足三样：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    ///
    /// 而且**两种说法要分开**：一次都没练过，和练过但一次都没存下复盘。
    /// 后者是真出过事的情况，「原文没丢、在哪儿」必须说清——用户最怕练了半小时的东西不见了。
    /// 只说「还没有复盘可看」的话，他会以为是自己没练。
    func testTheEmptyStateTellsThemWhatHappenedAndWhatToDoNext() throws {
        SourceGuard.assertRenders(
            "sessions.isEmpty", inBodyOf: "var body: some View", of: Self.view,
            because: "一次复盘都没有时，这一页不再单独走空状态那一支。用户看到的是一列空白"
                + "加一块空白，什么提示都没有（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。"
                + "下一步：把 `if sessions.isEmpty { emptyState } else { … }` 放回来。")

        SourceGuard.assertRenders(
            "emptyState", inBodyOf: "var body: some View", of: Self.view,
            because: "空状态写好了却没摆进 `body`，用户一个字都看不到。下一步：把它放回那一支里。")

        for (needle, what) in [
            ("app.state.sessions.count", "分辨「一次都没练过」和「练过但没存下复盘」——"
                + "这两种情况要说的话完全不同"),
            ("还没有复盘可看", "第一种情况的现状"),
            ("但没有一次存下复盘", "第二种情况的现状（真出过事的那一种）"),
            ("已经取回来的原文不会丢", "第二种情况下最要紧的那句话——"
                + "用户最怕练了半小时的东西不见了"),
            (#"actionTitle: "去今日训练""#, "一个能直接点的出口"),
            ("onGo(.today)", "那颗按钮真的把人送到今日训练")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private var emptyState", of: Self.view,
                because: "空状态里没有\(what)。下一步：补回去；换了措辞就同步改这条测试。")
        }
    }

    // MARK: - 八、结构性兜底：这一页声明的每一段渲染都得从 body 走得到

    /// 上面那些逐条手写的断言补不完——漏的永远是下一次没写到的那一个。
    /// 这一条问的是结构：这一页声明的每个 `some View` 成员，从 `body` 顺着调用关系走得到吗？
    ///
    /// 全模块同样的一趟在 `RenderReachabilitySweepTests` 里。这里单独再钉一遍这一页，
    /// 是因为**顺带把「这几段渲染必须存在」也钉住了**：全模块那一趟只问「有没有走不到的」，
    /// 一整段被干净删掉（声明和调用一起没）的话它是绿的——而那正是 `priorityCard`
    /// 实测溜过去的走法。
    func testEverySectionThisPageDeclaresIsReachableFromItsBody() throws {
        let code = try Self.viewCode()
        guard let page = SourceGuard.viewTypes(in: code)
            .first(where: { $0.name == "ReviewReportView" }) else {
            return XCTFail("在 \(Self.view) 里找不到带 `body` 的 `ReviewReportView`，这条测试等于空转。"
                           + "下一步：确认这个类型还在、还是个 SwiftUI 视图。")
        }

        let names = Set(page.viewMembers.map(\.name))
        let required: [(name: String, what: String)] = [
            ("body", "整页"),
            ("sessionList", "左边那一列已归档的练习"),
            ("sessionRow", "列表里的每一行"),
            ("reportPane", "右边整块复盘"),
            ("priorityCard", "NEXT SINGLE TARGET——这个产品真正的价值所在"),
            ("sectionCard", "复盘的四个分区"),
            ("rowView", "每一条的三格"),
            ("field", "三格里的每一格"),
            ("unreadableCard", "「有 N 节没能显示出来」那句警告"),
            ("emptyReportCard", "「这份复盘是空的」"),
            ("failureCard", "「这一次的复盘打不开」"),
            ("originalFileFooter", "原文在哪儿 + 在访达中打开"),
            ("emptyState", "一次复盘都还没有时的引导")
        ]
        for piece in required {
            XCTAssertTrue(names.contains(piece.name),
                          "扫不到 `\(piece.name)` 这段渲染，也就是「\(piece.what)」这块内容"
                              + "在这一页上已经不存在了（连声明一起没了的话，"
                              + "全模块那趟可达性扫描是绿的——这正是它溜过去的走法）。"
                              + "下一步：改了名字就同步改这条测试；整段没了的话，"
                              + "先想清楚它画的东西现在归谁。")
        }

        XCTAssertEqual(page.unreachable, [],
                       "这几段渲染声明着，却从 `body` 顺着调用关系走不到——写好的东西一个像素都不上屏，"
                           + "而且不会有任何编译错误。下一步：把它们摆回渲染树里。")
    }
}
