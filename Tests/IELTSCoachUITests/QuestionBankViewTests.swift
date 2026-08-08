import Foundation
import XCTest

@testable import IELTSCoachUI

/// 训练题库页里**唯一没法靠数据断言守住、但又决定用户看不看得见**的那件事：
/// 导入完成之后，那张交代到底出现在哪儿。
///
/// 背景：这一页的触发按钮（`importCard`）在页面最底下，而题库有几十个话题时，
/// 页面远超一屏（窗口 minHeight 600）。结果卡片一度是画在页面顶端的 —— 真实路径是
/// 「用户滚到底 → 点导入 → 选完文件 → 面板关闭 → 结果出现在屏幕外的页面顶端」，
/// 用户什么交代也看不到。计划 Task 4 Step 3 要求把 `ImportResult.warnings` **逐条**显示出来
/// （「你的 CSV 第 7 行缺 id，那道题没进来」），而那些警告不看就再也不会知道。
///
/// `swift test` 不画界面，也量不出滚动位置，所以这里退一步扫源码：结果必须走 `.sheet`
/// 弹出来，与滚动位置无关。扫源码用的是共用的 `SourceGuard`——它读不到文件会抛错，
/// 不会拿一段空串把下面每条断言都变成永远绿。
///
/// **这条测试的边界要说清**：它只能证明「有一个绑到导入结果的模态呈现」，
/// 证明不了弹出来的东西好不好看、排版对不对 —— 那部分仍归人工验收。
/// 但「用户看不看得见」这一条不是版面观感，它决定这一页有没有完成计划要求的事。
/// （弹窗里那些警告到底有没有被画出来，由 `QuestionBankImportResultSheetTests` 守。）
final class QuestionBankViewTests: XCTestCase {

    private static let view = "QuestionBank/QuestionBankView.swift"

    /// 去过注释的页面源码。读不到会抛错——`SourceGuard` 不会拿空串把下面每条断言变成恒真。
    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    func testImportResultIsPresentedAsASheetInsteadOfPaintedIntoTheScrollingPage() throws {
        let code = try Self.viewCode()

        XCTAssertTrue(
            code.contains("struct QuestionBankView"),
            "没扫到 QuestionBankView 的源码，这条测试等于空转。下一步：确认文件还在——\(Self.view)")

        SourceGuard.assertRenders(
            ".sheet(item: $feedback)", in: Self.view,
            because: "导入结果没有弹出来，而是画进了滚动页面里。触发按钮在页面最底下、页面远超一屏，"
                + "画在页面里的结果会落在屏幕外，用户选完文件回来什么交代也看不到，"
                + "计划要求逐条显示的那些警告尤其。"
                + "下一步：把结果交给 `.sheet(item: $feedback)` 呈现，"
                + "或换一种同样与滚动位置无关的办法（并同步改这条测试）。")

        // **这里查的是 `.sheet` 那个闭包体，不是全文里有没有出现过某个类型名。**
        // 原来的写法是「全文里出现过 `QuestionBankImportFeedback` 就算数」，
        // 而它命中的是页面顶上那句 `@State private var feedback: QuestionBankImportFeedback?`
        // 的声明——于是把闭包换成 `{ _ in EmptyView() }`，`.sheet` 还在、声明还在，
        // 断言照样全绿，而弹出来的是一张彻头彻尾的空白面板：用户点了导入、选完文件，
        // 屏幕上跳出一个什么都没有、也关不掉的框。
        let presented = try SourceGuard.memberBody(of: ".sheet(item: $feedback)", in: code)

        XCTAssertTrue(
            presented.contains("QuestionBankImportResultSheet("),
            "`.sheet(item: $feedback)` 弹出来的不是 `QuestionBankImportResultSheet`。"
                + "闭包里画什么，用户就看到什么——画成 `EmptyView()` 的话，"
                + "他会看到一张空白面板，导入了几题、哪几行有问题一个字都没有。"
                + "下一步：把 `QuestionBankImportResultSheet(feedback:dismiss:)` 放回这个闭包里。"
                + "实际取到的闭包体是：\n\(presented)")

        XCTAssertTrue(
            presented.contains("feedback = nil"),
            "弹窗没有把 `feedback` 清回 nil，那张 sheet 关不掉——`.sheet(item:)` 是靠"
                + "绑定的值变回 nil 才收起来的（铁律 5：不许无限等待）。"
                + "下一步：把 `dismiss` 闭包改回 `{ feedback = nil }`。"
                + "实际取到的闭包体是：\n\(presented)")
    }

    /// 同一招守另一条也「只有一根线、断了功能就整个废掉」的东西：
    /// 用户选完文件之后，这一页走的必须是 `QuestionBankImport.importFile(at:)` 那一条收口过的路。
    ///
    /// 背景：认格式、取文字、解析这三步各自都有测试，但「三步在界面里有没有真的串起来」
    /// 一度无人守——把取文字那一步换回 `String(contentsOf:encoding:.utf8)`，
    /// 真实 PDF 必然读不出来、导入功能整个废掉，而全部测试一条都不红。
    /// 三步已收进 `importFile`，`QuestionBankPDFImportTests` 守着它本身；
    /// 这里守的是最后那一段——视图确实调的是它，而不是自己另拼一条。
    ///
    /// 边界同上：扫源码证明不了运行时行为，只能证明这一页没有绕开那个入口。
    func testTheImportPathGoesThroughTheOneComposedEntryPoint() throws {
        SourceGuard.assertRenders(
            "struct QuestionBankView", in: Self.view,
            because: "没扫到 QuestionBankView 的源码，这条测试等于空转。下一步：确认文件还在。")

        SourceGuard.assertRenders(
            "QuestionBankImport.importFile(at:", in: Self.view,
            because: "这一页没有走 `QuestionBankImport.importFile(at:)`。认格式、取文字、解析三步"
                + "在界面里自己拼一遍的话，取文字那一步一旦写成按 UTF-8 读文件，"
                + "真实 PDF 就再也导不进来，而没有任何一条测试会红。"
                + "下一步：把导入改回调 `QuestionBankImport.importFile(at:)`（它已被"
                + "`QuestionBankPDFImportTests` 覆盖），或换一种同样可测的收口方式并同步改这条测试。")

        SourceGuard.assertOmits(
            "String(contentsOf: url", in: Self.view,
            because: "这一页又开始自己按文本读用户选中的文件了。PDF 不是文本文件，这样读必然失败，"
                + "而报出来的「另存为 UTF-8」对一份 PDF 是做不到的事。"
                + "下一步：读文件交给 `QuestionBankFileReader.text(at:format:)`（`importFile` 已经在用）。")

        // 同一类缺陷的另一条溜法：入口是调对了，却在这里塞进自己的取文字闭包，
        // 把走 PDFKit 的那个默认值顶掉。`QuestionBankPDFImportTests` 拿真 PDF 守的是
        // **默认参数**，覆盖掉默认值的话那几条照样绿，而用户选中的 PDF 已经读不出字了。
        SourceGuard.assertOmits(
            "pdfText:", in: Self.view,
            because: "这一页给 `importFile` 传了自己的取文字闭包，把默认的 PDFKit 那条路顶掉了。"
                + "拿真 PDF 守着默认参数的那几条测试管不到这儿——它们测的是默认值。"
                + "下一步：这一页只调 `QuestionBankImport.importFile(at:)`，取文字交给默认实现；"
                + "确实需要在界面里换实现的话，先补一条能覆盖新写法的测试。")
    }

    // MARK: - 导入失败必须上屏（铁律 5）

    /// **这一条守的是本项目最怕的那种缺陷：静默失败。**
    ///
    /// 实测过的突变：把 `runImport` 的整个 `catch` 块清空 → 484 条全绿。
    /// 那时用户看到的是——点「导入题库…」、选完文件、面板关掉，**屏幕上什么都不发生**。
    /// `feedback` 一直是 nil，sheet 不弹，没有任何一个字告诉他这次没成。
    /// 他只会以为自己没点对，再点一次，再什么都不发生。
    /// 而 `QuestionBankImport.describeFailure`（`QuestionBankViewModel.swift:267`）
    /// 那一整套按铁律 4 写好的中文文案，就此接不上任何东西——写了等于没写。
    ///
    /// 所以这里不问「文件里有没有出现过 describeFailure」（写在别处、写进注释都能骗过），
    /// 而是**把 `catch` 那一段单独切出来**，问它到底给 `feedback` 赋了什么。
    func testAFailedImportAlwaysPutsSomethingOnScreenInsteadOfSwallowingTheError() throws {
        let runImport = try SourceGuard.functionBody(named: "runImport", in: try Self.viewCode())

        // `memberBody` 从 `} catch` 往后取那对配对大括号里的内容——清空之后这里就是空的。
        let caught = try SourceGuard.memberBody(of: "} catch", in: runImport)

        XCTAssertTrue(
            caught.contains("feedback ="),
            "导入失败时 `catch` 里没有给 `feedback` 赋值，也就是**什么都不发生**（铁律 5：禁止静默失败）："
                + "用户点了「导入题库…」、选完文件、面板关掉，屏幕上一个字都没有，"
                + "他只会以为自己没点对，然后一遍遍重来。"
                + "下一步：在 `catch` 里把失败也做成一张 `QuestionBankImportFeedback` 交给 sheet 弹出来。"
                + "实际取到的 catch 分支是：「\(caught.trimmingCharacters(in: .whitespacesAndNewlines))」")

        XCTAssertTrue(
            caught.contains("QuestionBankImportFeedback("),
            "`catch` 里没有造出 `QuestionBankImportFeedback`，那张交代弹不出来。"
                + "下一步：`feedback = QuestionBankImportFeedback(failureMessage: …)`。"
                + "实际取到的 catch 分支是：「\(caught.trimmingCharacters(in: .whitespacesAndNewlines))」")

        XCTAssertTrue(
            caught.contains("QuestionBankImport.describeFailure("),
            "失败信息没有走 `QuestionBankImport.describeFailure`。系统 `NSError` 的原文只说"
                + "「发生了什么」，不说「下一步做什么」，措辞还未必是中文（铁律 4），"
                + "而 `describeFailure` 里那套中文文案就是为这一刻写的，绕开它等于白写。"
                + "下一步：`failureMessage: QuestionBankImport.describeFailure(error, fileName: …)`。"
                + "实际取到的 catch 分支是：「\(caught.trimmingCharacters(in: .whitespacesAndNewlines))」")

        XCTAssertTrue(
            caught.contains("url.lastPathComponent"),
            "失败文案里没有把用户选的那个文件名带上。一次导入可能连选好几个文件，"
                + "只说「导入失败」他不知道是哪一份的问题。"
                + "下一步：`describeFailure(error, fileName: url.lastPathComponent)`。"
                + "实际取到的 catch 分支是：「\(caught.trimmingCharacters(in: .whitespacesAndNewlines))」")
    }

    /// 导入成功那一侧同样只有一根线：题目必须真的经 `AppState.applyImport` 落进 `state.json`。
    ///
    /// 实测过的突变：把 `try app.applyImport(result)` 换成就地伪造的
    /// `QuestionBankImportOutcome(importedCount: 38, …)` → 484 条全绿。
    /// 那时**一道题都没有写进 `state.json`**，而弹窗上明明白白写着「导入完成，已导入 38 道题」。
    /// 用户关掉窗口、下次打开，题库还是空的——他会以为是这个程序丢了他的数据。
    func testTheImportedQuestionsActuallyGoThroughAppStateInsteadOfAFakedOutcome() throws {
        let runImport = try SourceGuard.functionBody(named: "runImport", in: try Self.viewCode())

        XCTAssertTrue(
            runImport.contains("QuestionBankImport.importFile(at:"),
            "`runImport` 没有调 `QuestionBankImport.importFile(at:)`。"
                + "下一步：认格式、取文字、解析三步交给那个收口过的入口，不要在视图里各写一遍。"
                + "实际取到的函数体是：\n\(runImport)")

        XCTAssertTrue(
            runImport.contains("try app.applyImport(result)"),
            "解析出来的题目没有交给 `app.applyImport` 落盘。这条线断了之后，"
                + "题目一道都没写进 `state.json`，而弹窗照样说「导入完成，已导入 N 题」——"
                + "用户下次打开发现题库还是空的，只会以为程序把他的数据弄丢了。"
                + "下一步：`feedback = QuestionBankImportFeedback(outcome: try app.applyImport(result))`。"
                + "实际取到的函数体是：\n\(runImport)")

        XCTAssertFalse(
            runImport.contains("QuestionBankImportOutcome("),
            "`runImport` 自己造了一个 `QuestionBankImportOutcome`。那个数字就不再是"
                + "「真的写进去了几道」，而是视图随口报的一个数——`AppStateTests` 里"
                + "守着 `applyImport` 的那几条测试管不到这儿。"
                + "下一步：结果只能来自 `app.applyImport(result)` 的返回值。"
                + "实际取到的函数体是：\n\(runImport)")
    }

    // MARK: - 文件面板：别让用户白跑一趟

    /// 文件面板放行什么，必须和 `parse` 认什么来自同一个真源。
    ///
    /// 实测过的两个突变，各自都能让 484 条全绿：
    ///
    /// - 删掉 `panel.allowedContentTypes = QuestionBankImport.allowedContentTypes`：
    ///   `NSOpenPanel` 的 `allowedContentTypes` 为空**不是**「什么都不放行」，
    ///   恰恰是「放行一切文件类型」。用户能选中一张 `.jpg`，一路走到
    ///   `format(ofFileName:)` 才被拒——选文件、等一下、再被拒，全程白跑。
    /// - 删掉 `panel.canChooseDirectories = false`：用户能选中一个文件夹，
    ///   而报出来的是「把题库另存为 CSV（第一行是 id,part,topic,prompt,followups）再导入」——
    ///   对一个文件夹说这句话，用户根本不知道该做什么（铁律 4）。
    func testTheFilePanelOnlyOffersWhatTheParserCanActuallyAccept() throws {
        let chooseFile = try SourceGuard.functionBody(named: "chooseFile", in: try Self.viewCode())

        XCTAssertTrue(
            chooseFile.contains("panel.allowedContentTypes = QuestionBankImport.allowedContentTypes"),
            "文件面板没有限定放行的类型。`NSOpenPanel.allowedContentTypes` 为空的含义"
                + "**不是**「什么都不放行」，恰恰是「放行一切文件类型」——用户能选中一张 .jpg、"
                + "一份 .docx，走到认格式那一步才被拒，白跑一趟。"
                + "下一步：把 `panel.allowedContentTypes = QuestionBankImport.allowedContentTypes` 放回去"
                + "（面板放行的类型与 `parse` 认的格式必须来自同一个 `QuestionBankImport.Format`）。"
                + "实际取到的函数体是：\n\(chooseFile)")

        XCTAssertEqual(
            SourceGuard.occurrences(of: "panel.allowedContentTypes", in: chooseFile), 1,
            "`panel.allowedContentTypes` 在 `chooseFile` 里被赋了不止一次，最后生效的是哪一次"
                + "只能靠读代码猜，而后一次很可能把收口过的那份清单顶掉了。"
                + "下一步：只留 `panel.allowedContentTypes = QuestionBankImport.allowedContentTypes` 这一句。"
                + "实际取到的函数体是：\n\(chooseFile)")

        XCTAssertFalse(
            chooseFile.contains("UTType"),
            "`chooseFile` 里自己列了一份 `UTType` 清单。这份清单在这儿和 `QuestionBankImport.Format` "
                + "里各写一份的话，只是**恰好**一致：加一种格式时这里漏改，面板就再也不放行它，"
                + "而全部测试无一变红。"
                + "下一步：类型清单只从 `QuestionBankImport.allowedContentTypes` 取。"
                + "实际取到的函数体是：\n\(chooseFile)")

        XCTAssertTrue(
            chooseFile.contains("panel.canChooseDirectories = false"),
            "文件面板放行了文件夹。用户选中一个文件夹之后，程序回给他的是"
                + "「把题库另存为 CSV（第一行是 id,part,topic,prompt,followups）再导入」——"
                + "对一个文件夹说这句话，他不知道该做什么，只会反复再选一次（铁律 4）。"
                + "下一步：把 `panel.canChooseDirectories = false` 放回去，从源头上不让他选中文件夹。"
                + "实际取到的函数体是：\n\(chooseFile)")

        XCTAssertEqual(
            SourceGuard.occurrences(of: "panel.canChooseDirectories", in: chooseFile), 1,
            "`panel.canChooseDirectories` 被赋了不止一次，后一次会把 `false` 顶掉。"
                + "下一步：只留 `panel.canChooseDirectories = false` 这一句。"
                + "实际取到的函数体是：\n\(chooseFile)")

        XCTAssertTrue(
            chooseFile.contains("runImport(from: url)"),
            "选完文件之后没有接着走导入。那样用户点了「导入」、选完文件，什么都不会发生（铁律 5）。"
                + "下一步：`guard panel.runModal() == .OK, let url = panel.url else { return }` 之后"
                + "调 `runImport(from: url)`。实际取到的函数体是：\n\(chooseFile)")
    }

    // MARK: - 页面主体：三个数字、一个筛选器、一列话题卡片

    /// 顶部那三个统计数字。
    ///
    /// 实测过的突变：把 `statistic(_:caption:)` 的函数体换成 `EmptyView()` → 484 条全绿。
    /// 那时页面顶上那张卡片是一片空白——题库有多少题、练过几道、还剩几道，一个数字都没有。
    /// `QuestionBankViewModelTests` 只测到 `model.counts` 这个元组算得对，
    /// **算得对和画出来是两件事**。
    func testTheThreeCountersAtTheTopActuallyPaintTheirNumbers() throws {
        let code = try Self.viewCode()
        let header = try SourceGuard.memberBody(of: "private var header", in: code)

        XCTAssertEqual(
            SourceGuard.occurrences(of: "statistic(", in: header), 3,
            "顶部那张卡片不再是三个统计数字（总题数 / 已经练过 / 还没练过）。"
                + "少一个，用户就看不到那一项；一个不剩时卡片是一片空白。"
                + "下一步：把三处 `statistic(…, caption: …)` 都摆回 `header`。"
                + "实际取到的是：\n\(header)")

        for counted in ["model.counts.total", "model.counts.practiced"] {
            XCTAssertTrue(
                header.contains(counted),
                "顶部统计没有用 `\(counted)`，那几个数字就不是从题库算出来的了。"
                    + "下一步：三个数字都从 `model.counts` 取（`QuestionBankViewModelTests` 守着它）。"
                    + "实际取到的是：\n\(header)")
        }

        let statistic = try SourceGuard.functionBody(named: "statistic", in: code)

        XCTAssertTrue(
            statistic.contains("Text(\"\\(value)\")"),
            "`statistic` 没有把数字画出来。函数体被掏空（例如换成 `EmptyView()`）之后，"
                + "三处调用还在、可达性扫描也走得到它，但用户看到的是一片空白。"
                + "下一步：把 `Text(\"\\(value)\")` 放回去。实际取到的函数体是：\n\(statistic)")

        XCTAssertTrue(
            statistic.contains("Text(caption)"),
            "`statistic` 没有把说明文字画出来。三个光秃秃的数字并排放着，"
                + "用户不知道哪个是总数、哪个是练过的。"
                + "下一步：把 `Text(caption)` 放回去。实际取到的函数体是：\n\(statistic)")
    }

    /// Part 筛选那个分段控件。
    ///
    /// 实测过的突变：把 `Picker` 那一段换成 `EmptyView()` → 484 条全绿。
    /// 那时用户再也没法只看 Part 2 的题——而 `partSelection` / `partFilter` /
    /// `groupedByTopic(part:)` 那一整条筛选逻辑还原封不动地留在代码里，谁也碰不到它。
    func testThePartFilterIsAControlTheUserCanActuallyOperate() throws {
        let bank = try SourceGuard.memberBody(of: "private var bank", in: try Self.viewCode())

        XCTAssertTrue(
            bank.contains("Picker(") && bank.contains("selection: $partSelection"),
            "按 Part 筛选的控件不在页面上了。筛选逻辑（`partFilter` → `groupedByTopic(part:)`）"
                + "还留在代码里，但用户没有任何办法触发它，只能一直看全部题目。"
                + "下一步：把绑到 `$partSelection` 的 `Picker` 摆回 `bank`。实际取到的是：\n\(bank)")

        XCTAssertTrue(
            bank.contains(".pickerStyle(.segmented)"),
            "Part 筛选不再是分段控件。默认的下拉菜单要点开才看得到有哪几个 Part，"
                + "而这里一共就四个选项，分段控件一眼就能看全、一下就能切。"
                + "下一步：把 `.pickerStyle(.segmented)` 放回去。实际取到的是：\n\(bank)")

        // 0 是「全部」，1/2/3 是三个 Part。少一个 tag，那一档就再也选不到，
        // 而 `Picker` 看着仍然正常——这正是 `partSelection` 那段注释在防的失效形态。
        for tag in 0...3 {
            XCTAssertTrue(
                bank.contains(".tag(\(tag))"),
                "Part 筛选里少了 `.tag(\(tag))` 这一档"
                    + "（0 是「全部」，1/2/3 是三个 Part）。少一档，用户就再也筛不到它，"
                    + "而控件看着仍然正常。下一步：把这一档补回去。实际取到的是：\n\(bank)")
        }
    }

    /// 话题卡片那一列——这一页的正文，用户来这儿就是为了看它。
    ///
    /// 实测过的突变：把 `ForEach(groups)` 那一段、或 `topicCard` 的函数体换成 `EmptyView()`
    /// → 484 条全绿。那时页面上只剩三个统计数字和一个筛选器，题一道都不显示，
    /// 而 `QuestionBankViewModelTests` 里 `groupedByTopic` 那几条照样绿——
    /// **分组算得对和分组画出来是两件事。**
    func testEveryTopicGroupIsPaintedWithItsQuestions() throws {
        let code = try Self.viewCode()
        let bank = try SourceGuard.memberBody(of: "private var bank", in: code)

        XCTAssertTrue(
            bank.contains("model.groupedByTopic(part: partFilter)"),
            "题库列表不再按话题分组取数。下一步：`model.groupedByTopic(part: partFilter)`"
                + "（`QuestionBankViewModelTests` 守着它的排序与分组）。实际取到的是：\n\(bank)")

        XCTAssertTrue(
            bank.contains("ForEach(groups") && bank.contains("topicCard("),
            "分好组的话题没有被**逐组**画出来。用户来这一页就是为了看题库里有什么，"
                + "这一段没了，页面上只剩三个统计数字和一个筛选器，题一道都看不到。"
                + "下一步：`ForEach(groups, id: \\.topic) { topicCard(topic:questions:) }`。"
                + "实际取到的是：\n\(bank)")

        XCTAssertTrue(
            bank.contains("noQuestionsInThisPart"),
            "当前这个 Part 一道题都没有时，页面上是一片空白，不说发生了什么、也不说下一步"
                + "（铁律 4/5）。下一步：把 `if groups.isEmpty { noQuestionsInThisPart }` 那一支放回去。"
                + "实际取到的是：\n\(bank)")

        let topicCard = try SourceGuard.functionBody(named: "topicCard", in: code)

        XCTAssertTrue(
            topicCard.contains("topic.isEmpty"),
            "话题卡片没有画话题名（连「未标注话题」那个兜底也没有）。"
                + "下一步：把 `Text(topic.isEmpty ? \"未标注话题\" : topic)` 放回去。"
                + "实际取到的函数体是：\n\(topicCard)")

        XCTAssertTrue(
            topicCard.contains("questions.count"),
            "话题卡片没有画这一组有几题。下一步：把 `Text(\"\\(questions.count) 题\")` 放回去。"
                + "实际取到的函数体是：\n\(topicCard)")

        XCTAssertTrue(
            topicCard.contains("ForEach(") && topicCard.contains("questionRow("),
            "话题卡片里的题目没有被逐道画出来。卡片壳子还在、标题还在，里面却是空的——"
                + "用户看到「旅行 · 6 题」，展开一看一道都没有。"
                + "下一步：把 `ForEach(Array(questions.enumerated()), id: \\.offset) { questionRow($0) }`"
                + "放回去。实际取到的函数体是：\n\(topicCard)")

        let questionRow = try SourceGuard.functionBody(named: "questionRow", in: code)

        for painted in ["question.part", "question.prompt", "statusBadge(for: question)"] {
            XCTAssertTrue(
                questionRow.contains(painted),
                "题目那一行没有画 `\(painted)`。三样缺一样，这一行就说不清"
                    + "「这是第几 Part 的哪道题、练没练过」。"
                    + "下一步：把它放回 `questionRow`。实际取到的函数体是：\n\(questionRow)")
        }
    }

    // MARK: - 「你的题库还是旧结构」那句话得真的画在页面上

    /// 文案本身在 `QuestionBankViewModel.legacyShapeNotice` 里，那边可测；
    /// **这一页有没有真的把它摆上屏幕，只有扫源码能守。**
    ///
    /// 写好一段渲染却没接进 `body` 是本项目的老毛病（见 `RenderReachabilitySweepTests`）。
    /// 那条全模块守卫只问「从 body 走不走得到这个成员」，答得了「摆没摆上去」，
    /// 答不了「摆在了列表前面还是几十个话题之后」——而这句话要解释的正是
    /// 下面那张列表为什么长成那样（一个话题下面挂着六道几乎一样的「题」），
    /// 摆在列表之后等于没写。
    func testTheLegacyShapeNoticeIsPaintedAboveTheQuestionList() throws {
        SourceGuard.assertRenders(
            "legacyShapeCard", inBodyOf: "var body", of: Self.view, atLeast: 1,
            because: "题库还是旧结构时那句提示没有摆进渲染树，用户永远不会知道"
                + "该再导入一次，题库就一直停在「一问一题」上。")
        SourceGuard.assertRenders(
            "model.legacyShapeNotice", in: Self.view,
            because: "这一页没有去读那句提示，卡片是空的。")

        // 顺序：提示必须排在题目列表 `bank` 前面。
        let code = try Self.viewCode()
        let bodyStart = try XCTUnwrap(code.range(of: "var body"))
        let tail = code[bodyStart.upperBound...]
        let notice = try XCTUnwrap(tail.range(of: "legacyShapeCard"),
                                   "body 里没有 legacyShapeCard")
        let list = try XCTUnwrap(tail.range(of: "bank"), "body 里没有 bank")
        XCTAssertTrue(notice.lowerBound < list.lowerBound,
                      "提示排在了题目列表后面。题库有几十个话题时列表远超一屏，"
                          + "排在后面的解释用户看不到。")
    }
}
