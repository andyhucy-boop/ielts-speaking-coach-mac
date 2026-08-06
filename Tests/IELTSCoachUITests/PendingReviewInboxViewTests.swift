import Foundation
import XCTest

@testable import IELTSCoachUI

/// 「重新导入待处理的复盘」这条补救路径的**界面层**守卫。
///
/// `PendingReviewViewModelTests` 已经把逻辑钉死了：导入成功要打 `.imported` 标记、
/// 失败时一个字都不许动那个文件、归档 0 条要大声说出来。缺的是最后一步——
/// **这些能力真的摆到屏幕上了吗**。本项目在这一步已经栽过四次
/// （`PracticeSheet`、`QuestionBankImportResultSheet`、`priorityCard`、`ForEach(document.sections)`），
/// 每一次都是「逻辑测得很扎实，而那段渲染删掉全绿」。
///
/// 这条路径尤其不能这样：它存在的全部理由是成品标准第 2 条「全程不需要打开终端」，
/// 而**出错恰恰是最需要它成立的时候**。入口没画出来，用户唯一的补救办法又变回
/// 终端里跑 `coach reimport`——功能写完了，那条硬标准却还是不成立。
///
/// **边界（与 `ReviewReportViewTests` 一致）**：扫源码不执行代码。
/// 「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——那部分归 Task 13 人工验收。
final class PendingReviewInboxViewTests: XCTestCase {

    private static let inbox = "Review/PendingReviewInboxView.swift"
    private static let page = "Review/ReviewReportView.swift"

    private static func inboxCode() throws -> String { try SourceGuard.code(inbox) }
    private static func pageCode() throws -> String { try SourceGuard.code(page) }

    /// 先确认这两趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都是恒假——
    /// 会以「全红」的形式暴露，但报错指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesBothFiles() throws {
        XCTAssertTrue(try Self.inboxCode().contains("struct PendingReviewInboxView"),
                      "没扫到 `PendingReviewInboxView` 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.inbox)")
        XCTAssertTrue(try Self.pageCode().contains("struct ReviewReportView"),
                      "没扫到 `ReviewReportView` 的源码。下一步：确认文件还在——\(Self.page)")
    }

    // MARK: - 一、入口：找不到它，这条补救路径等于不存在

    /// 入口必须在复盘报告页上，**标题逐字是「重新导入待处理的复盘」**。
    ///
    /// 这不是措辞洁癖：`PracticeRunner` 取复盘失败时那两句话写死了
    /// 「到「复盘报告」页用「重新导入待处理的复盘」把这份原文补进来」，
    /// `PendingReviewStore` 落盘撞名时也这么说。名字对不上，用户拿着这句提示会一直找（铁律 4）。
    func testTheEntryIsOnTheReviewPageWithItsCount() throws {
        SourceGuard.assertRenders(
            "pendingReviewEntry", inBodyOf: "var body: some View", of: Self.page,
            because: "复盘报告页上没有「重新导入待处理的复盘」这个入口。复盘取回失败时，"
                + "用户把原文补进库的唯一途径又变回终端里跑 `coach reimport`——"
                + "成品标准第 2 条「全程不需要打开终端」在最需要它成立的时候不成立。"
                + "下一步：把这个入口摆回 `body` 里。")

        SourceGuard.assertRenders(
            #"Button("重新导入待处理的复盘")"#, inBodyOf: "private var pendingReviewEntry", of: Self.page,
            because: "入口的标题不再逐字是「重新导入待处理的复盘」。`PracticeRunner` 与 "
                + "`PendingReviewStore` 的失败文案里写死了这个名字，改了这里就等于让那几句话"
                + "指向一颗找不到的按钮（铁律 4）。下一步：改回来；真要换名字，"
                + "把那三处文案一起改。")

        SourceGuard.assertRenders(
            "isShowingInbox = true", inBodyOf: "private var pendingReviewEntry", of: Self.page,
            because: "入口那颗按钮点下去什么都不会发生（铁律 5：禁止静默失败）。"
                + "下一步：把打开收件箱那一句接回去。")

        SourceGuard.assertRenders(
            "inbox.rows.count", inBodyOf: "private var pendingCountText", of: Self.page,
            because: "入口不再显示待处理条数。用户没有任何办法知道这里躺着几份没入库的复盘，"
                + "也就不会想到要点进来。下一步：把条数接回去；"
                + "**必须是真实的条数**——写死一个数字或者永远显示 0 都算这一类。")
    }

    /// **条数为 0 时入口仍然要在。** 藏起来的话，用户出事时根本找不到它。
    ///
    /// 结构上问这件事的办法：入口那一句必须排在「一次复盘都没有」的分支**之前**，
    /// 也就是不管有没有已归档的复盘，它都画得出来。
    func testTheEntryStaysVisibleEvenWhenNothingIsPending() throws {
        let body = try SourceGuard.memberBody(of: "var body: some View", in: try Self.pageCode())
        guard let entryAt = body.range(of: "pendingReviewEntry"),
              let branchAt = body.range(of: "if sessions.isEmpty") else {
            return XCTFail("在 `body` 里找不到 `pendingReviewEntry` 或 `if sessions.isEmpty`，"
                           + "这条顺序断言等于空转。下一步：先修好上面那几条。")
        }
        XCTAssertTrue(entryAt.lowerBound < branchAt.lowerBound,
                      "入口被塞进了「有没有已归档复盘」的分支里。一次复盘都还没成功归档的人"
                          + "（恰恰最可能是取复盘一直失败的那位）看到的会是空状态，入口一并消失。"
                          + "下一步：把 `pendingReviewEntry` 挪回分支之前，让它永远画得出来。")
    }

    /// 入口不得是主行动：那个位置（`PrimaryActionCard`）留给复盘本身。
    /// 两个同样醒目的紫色大块会让人不知道该点哪个（DESIGN-SYSTEM 第 4 节）。
    func testTheEntryIsNotThePrimaryActionOfThisPage() throws {
        XCTAssertFalse(try Self.pageCode().contains("PrimaryActionCard"),
                       "复盘报告页上出现了 `PrimaryActionCard`。这一页的主角是复盘本身，"
                           + "补救入口必须是次一级的按钮样式（DESIGN-SYSTEM 第 4 节：每页最多一个主行动）。"
                           + "下一步：换成 `.bordered` 那一档。")
    }

    /// 入口背后接的必须是真的那份数据目录，而且真的去清点了。
    ///
    /// 视图自己 new 一个 `DataDirectory` 的话，补进去的复盘会落在另一个目录里，
    /// 用户回到这一页只会看到什么都没变——而且不会有任何报错。
    func testTheEntryIsWiredToTheRealDataDirectory() throws {
        SourceGuard.assertRenders(
            "app.makePendingReviewViewModel()", inBodyOf: "private func loadInbox", of: Self.page,
            because: "清点待处理复盘时没有走 `AppState`。视图自己解析一次数据目录的话，"
                + "补进去的复盘可能落在另一个目录里，用户回到这一页只会看到什么都没变。"
                + "下一步：改回 `app.makePendingReviewViewModel()`。")

        SourceGuard.assertRenders(
            "refresh()", inBodyOf: "private func loadInbox", of: Self.page,
            because: "造了视图模型却没让它去清点，入口永远显示「待处理 0 份」，"
                + "而磁盘上其实躺着几份没入库的复盘（铁律 7：禁止静默失败）。"
                + "下一步：把 `refresh()` 接回去。")

        SourceGuard.assertRenders(
            "loadInbox()", inBodyOf: "var body: some View", of: Self.page,
            because: "`loadInbox()` 写好了却没人调，条数永远是「正在清点…」。"
                + "下一步：把 `.task { loadInbox() }` 放回 `body` 上。")

        SourceGuard.assertRenders(
            "inboxSheet", inBodyOf: "var body: some View", of: Self.page,
            because: "点了入口却弹不出收件箱——按钮看着能点，点了什么都不发生（铁律 5）。"
                + "下一步：把 `.sheet(isPresented: $isShowingInbox) { inboxSheet }` 放回 `body` 上。")

        SourceGuard.assertRenders(
            "PendingReviewInboxView(model: inbox", inBodyOf: "private var inboxSheet", of: Self.page,
            because: "弹出来的不是收件箱本身，或者喂给它的不是刚清点出来的那份视图模型。"
                + "下一步：把 `PendingReviewInboxView(model: inbox, …)` 放回去。")
    }

    // MARK: - 二、列表：时间、题目、大小，一样都不能少

    func testEveryRowShowsWhenWhichQuestionAndHowBig() throws {
        SourceGuard.assertRenders(
            "ForEach(model.rows)", inBodyOf: "private var rowList", of: Self.inbox,
            because: "收件箱不再遍历 `model.rows`（换成空数组一样编得过、跑得动），"
                + "列表永远是空的，用户一条都点不到。下一步：把 `ForEach(model.rows) { … }` 放回去。")

        let list = try SourceGuard.memberBody(of: "private var rowList", in: try Self.inboxCode())
        let loop = try SourceGuard.memberBody(of: "ForEach(model.rows)", in: list)
        XCTAssertTrue(loop.contains("rowCard(row)"),
                      "遍历了 `model.rows`，循环体里却没有 `rowCard(row)`——每一条都被遍历了一遍"
                          + "然后什么都没画。实际取到的循环体是：\n\(loop)"
                          + "\n下一步：把 `rowCard(row)` 放回循环体里。")

        for (needle, what) in [
            ("row.timeText", "这份原文是什么时候落盘的——同一天失败两次的话，没有时间就分不出哪份是哪份"),
            ("row.questionText", "这份复盘属于哪道题（查不到时是一句中文说明，不会是空白）"),
            ("row.sizeText", "有多大——几十字节的那份多半是半截内容，值不值得重试看这个数")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func rowCard", of: Self.inbox,
                because: "列表行里没有\(what)。下一步：把它画回去；换了字段名就同步改这条测试。")
        }
    }

    // MARK: - 三、三个操作：重新导入、查看原文、删除

    func testEachRowOffersReimportInspectAndDelete() throws {
        let actions = try SourceGuard.memberBody(of: "private func actions", in: try Self.inboxCode())
        let required: [(needle: String, what: String)] = [
            (#"Button("重新导入")"#, "把这份原文补进库的那颗按钮——这一整页存在的理由"),
            ("model.reimport(row)", "那颗按钮真的去导入**这一行**的那份原文"),
            (#"Button("查看原文")"#, "打开原文自己看一眼的入口"),
            ("showRawText(of: row)", "「查看原文」真的去读这一行的原文"),
            // 连 `role: .destructive` 一起钉：这是全 App 唯一一处会永久销毁用户内容的操作，
            // 系统靠这个角色把它渲染成红色、并且不给默认焦点。
            (#"Button("删除", role: .destructive)"#, "删掉这份原文的入口（且标成销毁性操作）"),
            ("pendingDeletion = row", "「删除」先弹确认框，而不是直接删")
        ]
        for item in required {
            XCTAssertTrue(actions.contains(item.needle),
                          "每一行的操作里没有\(item.what)（找的是「\(item.needle)」）。"
                              + "实际取到的那一段是：\n\(actions)"
                              + "\n下一步：把它接回去；换了按钮标题或方法名就同步改这条测试，"
                              + "并确认 `PendingReviewViewModel` 里那几句「下一步：点「…」」指的还是这几颗。")
        }
    }

    /// 「查看原文」得真的把原文显示出来，而且能选中复制。
    ///
    /// 这一条不是锦上添花：本工具解析不了的那些复盘，用户唯一的出路就是自己打开看一眼，
    /// 然后回 ChatGPT 让它重新输出一次。`PendingReviewViewModel` 解析失败那句话里
    /// 写的正是「点「查看原文」看看 ChatGPT 到底输出了什么」。
    func testInspectingShowsTheRawTextAndLetsThemCopyIt() throws {
        SourceGuard.assertRenders(
            "rawTextPane", inBodyOf: "private func rowCard", of: Self.inbox,
            because: "行里没有摆放原文面板，「查看原文」点了之后什么都不会出现（铁律 5）。"
                + "下一步：把 `rawTextPane` 摆回行里。")

        SourceGuard.assertRenders(
            "model.rawText(of: row)", inBodyOf: "private func showRawText", of: Self.inbox,
            because: "「查看原文」没有真的去读那份原文。下一步：接回 `model.rawText(of:)`；"
                + "读不到时它会把原因写进 `notice`，那张卡片会显示出来。")

        for (needle, what) in [
            ("openedRawText", "读回来的原文本身"),
            ("ScrollView", "能滚动——一份复盘几千字，不滚动就只看得到开头"),
            (".textSelection(.enabled)", "能选中复制——用户要把它贴回 ChatGPT 让它重新输出")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private var rawTextPane", of: Self.inbox,
                because: "原文面板里没有\(what)。下一步：补回去。")
        }
    }

    /// 删除要二次确认，而且必须说清「删掉就没了」。
    ///
    /// 这是全 App 唯一一处会永久销毁用户内容的操作：`pending-reviews/` 里的原文是
    /// 那一场练习**唯一**的复盘来源，删掉之后连 `coach reimport` 都救不回来。
    func testDeletingAsksFirstAndSaysItCannotBeUndone() throws {
        SourceGuard.assertRenders(
            ".confirmationDialog", inBodyOf: "var body: some View", of: Self.inbox,
            because: "删除不再二次确认，点一下原文就永久没了——而它是那一场练习唯一的复盘来源。"
                + "下一步：把确认框放回 `body` 上。")

        SourceGuard.assertRenders(
            "删掉之后这份复盘原文就没了，无法恢复", in: Self.inbox,
            because: "确认框里没有说清后果。用户以为只是从列表里移走，点完才发现东西真没了。"
                + "下一步：把这句话写回确认框的说明里。")

        SourceGuard.assertRenders(
            "model.delete(row)", inBodyOf: "private func destroy", of: Self.inbox,
            because: "确认之后并没有真的删掉那份原文——界面上它消失了，磁盘上还在，"
                + "下次刷新又冒出来（铁律 5）。下一步：把 `model.delete(row)` 接回去。")
    }

    // MARK: - 四、说明必须留在屏幕上

    /// `notice` 是这一页与用户之间唯一的对话通道：导入成功了、字段名对不上、
    /// 归档失败了、文件读不到——每一句都带着「下一步做什么」。
    /// **不许做成一闪而过的提示**：那几句话有的很长（归档 0 条那句要指路去改文件名），
    /// 用户来不及读。
    func testTheNoticeIsShownInFullAndCanBeCopied() throws {
        SourceGuard.assertRenders(
            "model.notice", inBodyOf: "var body: some View", of: Self.inbox,
            because: "这一页不再显示 `model.notice`。导入成功、字段名对不上、归档失败——"
                + "每一种结果都变成「点了按钮，界面没反应」（铁律 5、7）。"
                + "下一步：把 `if let notice = model.notice { noticeCard(notice) }` 放回 `body`。")

        SourceGuard.assertRenders(
            "noticeCard(notice)", inBodyOf: "var body: some View", of: Self.inbox,
            because: "取到了那句话却没画出来。下一步：把 `noticeCard(notice)` 放回去。")

        for (needle, what) in [
            ("Text(message)", "那句话本身"),
            (".textSelection(.enabled)", "能选中复制——里面有文件名和目录，用户要拿去找文件")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func noticeCard", of: Self.inbox,
                because: "说明卡片里没有\(what)。下一步：补回去。")
        }
    }

    // MARK: - 五、空状态

    /// 空状态给足三样：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    ///
    /// 这一页的空状态尤其要说清「这里本来是干什么的」——用户多半是顺着别处的错误提示
    /// 找过来的，看到一片空白只会更慌。
    func testTheEmptyStateExplainsWhatThisPageIsFor() throws {
        SourceGuard.assertRenders(
            "model.isEmpty", inBodyOf: "var body: some View", of: Self.inbox,
            because: "一份待处理复盘都没有时，这一页不再走空状态那一支，用户看到的是一片空白"
                + "（DESIGN-SYSTEM 第 4 节：空白页会让用户以为程序坏了）。"
                + "下一步：把 `if model.isEmpty { emptyState } else { rowList }` 放回来。")

        for (needle, what) in [
            ("没有待处理的复盘", "现状：这里现在是空的"),
            ("复盘自动取回失败时", "这一页本来是干什么的——用户多半是顺着别处的错误提示找过来的"),
            ("model.refresh()", "那颗按钮真的去重新清点一次")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private var emptyState", of: Self.inbox,
                because: "空状态里没有\(what)。下一步：补回去；换了措辞就同步改这条测试。")
        }
    }

    // MARK: - 六、结构性兜底

    /// 上面那些逐条手写的断言补不完——漏的永远是下一次没写到的那一个。
    /// 这一条问的是结构：这一页声明的每个 `some View` 成员，从 `body` 顺着调用关系走得到吗？
    ///
    /// 全模块同样的一趟在 `RenderReachabilitySweepTests` 里。这里单独再钉一遍，
    /// 是因为**顺带把「这几段渲染必须存在」也钉住了**：全模块那一趟只问「有没有走不到的」，
    /// 一整段被干净删掉（声明和调用一起没）的话它是绿的。
    func testEverySectionThisSheetDeclaresIsReachableFromItsBody() throws {
        let code = try Self.inboxCode()
        guard let sheet = SourceGuard.viewTypes(in: code)
            .first(where: { $0.name == "PendingReviewInboxView" }) else {
            return XCTFail("在 \(Self.inbox) 里找不到带 `body` 的 `PendingReviewInboxView`，"
                           + "这条测试等于空转。下一步：确认这个类型还在、还是个 SwiftUI 视图。")
        }

        let names = Set(sheet.viewMembers.map(\.name))
        let required: [(name: String, what: String)] = [
            ("body", "整张表"),
            ("header", "抬头与「刷新」"),
            ("noticeCard", "每次操作之后那句带「下一步」的说明"),
            ("rowList", "待处理复盘的列表"),
            ("rowCard", "列表里的每一条"),
            ("actions", "重新导入 / 查看原文 / 删除三个操作"),
            ("rawTextPane", "「查看原文」展开的那块原文"),
            ("emptyState", "一份都没有时的说明")
        ]
        for piece in required {
            XCTAssertTrue(names.contains(piece.name),
                          "扫不到 `\(piece.name)` 这段渲染，也就是「\(piece.what)」这块内容"
                              + "在这一页上已经不存在了（连声明一起没了的话，"
                              + "全模块那趟可达性扫描是绿的——这正是它溜过去的走法）。"
                              + "下一步：改了名字就同步改这条测试；整段没了的话，"
                              + "先想清楚它画的东西现在归谁。")
        }

        XCTAssertEqual(sheet.unreachable, [],
                       "这几段渲染声明着，却从 `body` 顺着调用关系走不到——写好的东西一个像素都不上屏，"
                           + "而且不会有任何编译错误。下一步：把它们摆回渲染树里。")
    }
}
