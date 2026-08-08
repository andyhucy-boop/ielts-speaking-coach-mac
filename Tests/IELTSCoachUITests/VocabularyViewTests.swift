import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

/// 我的词汇页的视图层守卫，一条对一条地钉住计划 Task 7 Step 3 给这一页的八条验收要求。
///
/// ## 为什么这一页需要这么一份测试
///
/// 计划 Task 7 只给了视图模型的三处突变，把 `View` 的正确性推给 Task 11 的人工验收。
/// `IssueArchiveViewTests` / `HistoryViewTests` 的文件注释里已经写过同一件事的结论：
/// **人工验收只跑一次，而回归会发生无数次。** 本项目实测过三次「整段渲染删掉、全绿」。
///
/// 这一页的赌注比别的页大一档：它是**唯一一页会往磁盘和剪贴板写东西**的。
/// 「导出成功了却没说文件怎么用」「跳过了几条却只显示导出成功」「剪贴板写失败了还说已复制」
/// 这三件事都不会让任何一条现有测试变红，而用户要到 Anki 里才发现卡片少了几张。
///
/// 所以照 `IssueArchiveViewTests` 的办法办：能抽成纯函数的（配色、汇总那句话、
/// 导出后那几句反馈、格式到文件类型的映射）真跑起来验，剩下的接线扫源码。
///
/// ## 边界（与 `IssueArchiveViewTests` 一致）
///
/// 扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——
/// 那部分归 Task 11 的人工验收。它拦得住的是：整段渲染被删、数据源被换掉、
/// 跳过的条目被吞掉、写好的组件没摆进页面。
@MainActor
final class VocabularyViewTests: XCTestCase {

    private static let view = "Vocabulary/VocabularyView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    private func record(_ id: String, basic: String, priority: String) -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: basic, betterExpression: "better-\(basic)",
                         collocation: "colloc-\(basic)", priority: priority,
                         sourceSessionIds: ["s1"])
    }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct VocabularyView"),
                      "没扫到 VocabularyView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 要求 1：页头

    func testThePageHeaderSaysWhichPageThisIsAndWhatItIsFor() throws {
        SourceGuard.assertRenders(
            "SectionHeader(number: 1, label: \"VOCABULARY\"",
            inBodyOf: "private var header", of: Self.view,
            because: "页头不见了，用户点进来看到的是一堆没有标题的卡片"
                + "（DESIGN-SYSTEM 第 4 节）。")
        let header = try SourceGuard.memberBody(of: "private var header", in: try Self.viewCode())
        XCTAssertTrue(header.contains("我的词汇"),
                      "页头的中文标题不见了。实际取到的是：\n\(header)")
        SourceGuard.assertRenders(
            "header", inBodyOf: "var body: some View", of: Self.view,
            because: "页头写好了却没摆进 `body`。下一步：把它放回去。")
    }

    // MARK: - 要求 2：汇总行「共 N 个词 · 其中 M 个要优先记」

    /// 汇总那句话抽成纯函数，理由和 `IssueArchiveView.summaryText` 一样：
    /// 扫源码只问得出「这儿有个 `Text`」，问不出它到底说了什么。
    func testTheSummaryLineQuotesBothNumbers() {
        let text = VocabularyView.summaryText(total: 12, high: 4)
        XCTAssertTrue(text.contains("12"), "汇总里没有词的总数：\(text)")
        XCTAssertTrue(text.contains("4"), "汇总里没有「要优先记」的个数：\(text)")
        XCTAssertTrue(text.contains(VocabularyPriority.high.title),
                      "汇总没说清第二个数字是什么——「其中 4 个」是 4 个什么？：\(text)")
    }

    func testTheSummaryLineIsBuiltFromTheViewModelCountsAndUsesMonospacedDigits() throws {
        let summary = try SourceGuard.memberBody(of: "private var summaryLine",
                                                 in: try Self.viewCode())
        XCTAssertTrue(summary.contains("summaryText(total:"),
                      "汇总那句话不是从 `summaryText` 来的，上面那条真跑起来的测试就在测"
                          + "一段没人用的实现。实际取到的是：\n\(summary)")
        XCTAssertTrue(summary.contains("counts.total") && summary.contains("counts.high"),
                      "汇总的两个数字没有全部来自 `VocabularyViewModel.counts`。"
                          + "实际取到的是：\n\(summary)")
        XCTAssertTrue(summary.contains(".monospacedDigit()"),
                      "汇总里的数字没用等宽数字。「共 9 个词」跳到「共 10 个词」时整行会"
                          + "横向抖一下（规范第 6 节最后一条）。实际取到的是：\n\(summary)")
        SourceGuard.assertRenders(
            "summaryLine", inBodyOf: "var body: some View", of: Self.view,
            because: "汇总那一行写好了却没摆进 `body`，用户看不到「一共几个词、几个要优先记」。")
    }

    // MARK: - 要求 3：筛选控件

    func testTheFilterControlOffersEveryFilterFromTheModel() throws {
        let picker = try SourceGuard.memberBody(of: "private var filterPicker",
                                               in: try Self.viewCode())
        XCTAssertTrue(picker.contains("VocabularyFilter.allCases"),
                      "筛选控件的选项不是 `VocabularyFilter.allCases`。手抄一份的话，"
                          + "以后加一档筛选界面上不会出现，而 `VocabularyViewModelTests` "
                          + "照样绿。实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains(".title"),
                      "选项没用 `VocabularyFilter.title` 显示，用户看到的会是 `all` `high` "
                          + "这种英文 case 名（铁律 6：面向用户的文案必须中文）。"
                          + "实际取到的是：\n\(picker)")
        XCTAssertTrue(picker.contains("$filter"),
                      "筛选控件没和 `filter` 绑起来，点了不会有任何变化。"
                          + "实际取到的是：\n\(picker)")
        SourceGuard.assertRenders(
            "filterPicker", inBodyOf: "var body: some View", of: Self.view,
            because: "筛选控件写好了却没摆进 `body`，用户没有任何办法只看「优先记」那一档。")
    }

    func testTheListIsDrivenByTheSelectedFilter() throws {
        let list = try SourceGuard.memberBody(of: "private var listSection",
                                             in: try Self.viewCode())
        XCTAssertTrue(list.contains("rows(filter: filter)"),
                      "列表没有按当前筛选取行——筛选控件点了会变蓝，列表纹丝不动。"
                          + "实际取到的是：\n\(list)")
        XCTAssertTrue(list.contains("vocabularyCard(row)"),
                      "遍历了行却没有画出每一条，这一页只剩一个页头。实际取到的是：\n\(list)")
        for forbidden in ["sorted", "filter { "] where list.contains(forbidden) {
            XCTFail("列表在视图里又 `\(forbidden)` 了一次。排序与筛选**原样**来自 "
                        + "`VocabularyViewModel`，这一页不许再排、再筛——那会造出第二套说法，"
                        + "而依据只有视图模型那一处有测试守着。实际取到的是：\n\(list)")
        }
        SourceGuard.assertRenders(
            "listSection", inBodyOf: "var body: some View", of: Self.view,
            because: "整个词汇列表没摆进 `body`，这一页只剩一个页头。")
    }

    // MARK: - 要求 4：每一行要显示的东西

    func testEveryRowShowsEverythingTheUserNeedsToMemoriseTheWord() throws {
        let card = try SourceGuard.memberBody(of: "private func vocabularyCard",
                                              in: try Self.viewCode())
        for (field, why) in [
            ("row.basicWord", "原来的说法——它是「这条说的是哪个词」的唯一依据"),
            ("row.betterExpression", "更好的说法。少了它这一页只是在列旧词，用户不知道要改成什么"),
            ("row.collocation", "搭配。少了它用户知道换个词，却不知道这个词怎么用"),
            ("row.priority.title", "优先记还是先放着"),
            ("row.sessionCount", "这个词在几场练习里被推荐过——反复被推荐的更该先记")
        ] {
            XCTAssertTrue(card.contains(field),
                          "一行里没有\(why)（`\(field)`）。实际取到的是：\n\(card)")
        }
        XCTAssertTrue(card.contains("Image(systemName: \"arrow.right\")"),
                      "「原来的说法 → 更好的说法」之间没有方向感，两串英文并排摆着，"
                          + "用户分不出哪个是该改成的那个。DESIGN-SYSTEM 第 4 节要求用 "
                          + "SF Symbols，不用 emoji。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains(".monospacedDigit()"),
                      "行里的场次数字没用等宽数字。「出现在 9 场」跳到「10 场」时整行会横向抖"
                          + "（规范第 6 节最后一条）。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("Radius.pill"),
                      "优先级没做成 pill（计划要求 4）。实际取到的是：\n\(card)")
    }

    // MARK: - 要求 5：导出

    /// **导出必须跟随当前筛选。** 用户筛到「优先记」再点导出却拿到全部词汇，
    /// 是典型的「界面骗人」——而他要到 Anki 里才会发现。
    func testWhatGetsExportedFollowsWhatIsOnScreen() throws {
        let builder = try SourceGuard.memberBody(of: "private func exportDocument",
                                                 in: try Self.viewCode())
        XCTAssertTrue(builder.contains("filter: filter"),
                      "导出没有带上当前筛选，用户筛完再导出拿到的是全部词汇。"
                          + "`VocabularyViewModelTests.testExportOnlyIncludesTheCurrentFilter` "
                          + "守的是视图模型那一层，视图这儿传错照样全绿。实际取到的是：\n\(builder)")
        XCTAssertTrue(builder.contains("model.exportDocument("),
                      "导出的内容不是从 `VocabularyViewModel.exportDocument` 来的——"
                          + "另拼一份的话，「顺序与界面一致」「筛空时说清是筛选的事」"
                          + "那两条测试就都空转了。实际取到的是：\n\(builder)")
    }

    func testTheExportMenuOffersEveryFormatAndSavesThroughTheFileExporter() throws {
        let code = try Self.viewCode()
        let menu = try SourceGuard.memberBody(of: "private var exportMenu", in: code)
        XCTAssertTrue(menu.contains("VocabularyExportFormat.allCases"),
                      "导出菜单的格式不是 `VocabularyExportFormat.allCases`。手抄一份的话，"
                          + "以后加一种格式界面上不会出现。实际取到的是：\n\(menu)")
        XCTAssertTrue(menu.contains("format.title"),
                      "菜单项没用 `format.title` 显示，用户看到的是 `ankiTSV` 这种英文 case 名"
                          + "（铁律 6）。实际取到的是：\n\(menu)")
        XCTAssertTrue(menu.contains("savingFormat = format"),
                      "点了菜单项不会打开保存面板，等于点了没反应。实际取到的是：\n\(menu)")
        XCTAssertTrue(code.contains(".fileExporter("),
                      "没有 `.fileExporter`，选了格式之后没有任何地方能把文件存下来。")
        XCTAssertTrue(code.contains("defaultFilename: savingFileName"),
                      "保存面板没有带上 `ExportDocument.suggestedFileName`，"
                          + "用户拿到的是一个叫「未命名」的文件。")
        SourceGuard.assertRenders(
            "exportMenu", inBodyOf: "private var exportSection", of: Self.view,
            because: "导出菜单写好了却没摆进那一排按钮里，用户没有任何入口能把词存成文件。")
        SourceGuard.assertRenders(
            "exportSection", inBodyOf: "var body: some View", of: Self.view,
            because: "导出入口写好了却没摆进 `body`，这一页就只是个只能看的词表——"
                + "而导出正是 Task 7 的核心交付。")
    }

    /// **真正写到磁盘和剪贴板的那两份内容，必须走同一个带筛选的入口。**
    ///
    /// 这一条守的是本项目实测过的两处退化：
    ///
    /// - 把 `savingDocument` 里那句改成 `model.exportDocument(format:…, filter: .all)`
    ///   （用户筛到「优先记」、存出来的文件却是全部词汇）——全量 1131 条全绿；
    /// - 把「复制到剪贴板」那句改成同样的写法——同样全绿。
    ///
    /// 原因是上面那条 `testWhatGetsExportedFollowsWhatIsOnScreen` 只切了
    /// `exportDocument(for:)` 这一段的函数体来扫，而文件的字节与剪贴板的内容都不从那儿来。
    /// 所以这里问的是「唯一入口」：全文只允许有一处碰 `model.exportDocument(`，
    /// 而且它必须在 `exportDocument(for:)` 里、必须带上当前筛选。
    func testEveryExportPathGoesThroughTheOneBuilderThatCarriesTheFilter() throws {
        let code = try Self.viewCode()

        XCTAssertEqual(SourceGuard.occurrences(of: "model.exportDocument(", in: code), 1,
                       "这一页有不止一处直接调 `VocabularyViewModel.exportDocument(…)`。"
                           + "多出来的那一处可以自己传一个 `filter:`，于是用户筛到「优先记」"
                           + "却导出了全部词汇，而所有测试照样绿。"
                           + "下一步：让所有导出路径都走 `exportDocument(for:)` 这一个入口。")

        let builder = try SourceGuard.memberBody(of: "private func exportDocument", in: code)
        XCTAssertTrue(builder.contains("model.exportDocument("),
                      "唯一入口 `exportDocument(for:)` 自己不再调视图模型了，"
                          + "那上面那条「只有一处」的断言就守了一处不相干的代码。"
                          + "实际取到的是：\n\(builder)")

        let saving = try SourceGuard.memberBody(of: "private var savingDocument", in: code)
        XCTAssertTrue(saving.contains("exportDocument(for: savingFormat)"),
                      "存到磁盘的那份文档不是从 `exportDocument(for:)` 来的——"
                          + "文件里的字节正是这一处决定的，绕过去就等于导出不跟随筛选。"
                          + "实际取到的是：\n\(saving)")

        let fileName = try SourceGuard.memberBody(of: "private var savingFileName", in: code)
        XCTAssertTrue(fileName.contains("exportDocument(for:"),
                      "预填的文件名不是从 `exportDocument(for:)` 来的。"
                          + "实际取到的是：\n\(fileName)")

        let copy = try SourceGuard.memberBody(of: "private var copyButton", in: code)
        XCTAssertTrue(copy.contains("exportDocument(for: Self.clipboardFormat)"),
                      "复制到剪贴板的那份内容不是从 `exportDocument(for:)` 来的——"
                          + "剪贴板里的字正是这一处决定的。实际取到的是：\n\(copy)")

        XCTAssertTrue(code.contains("document: savingDocument"),
                      "`.fileExporter` 交出去的不是 `savingDocument`，"
                          + "上面那条针对 `savingDocument` 的断言就在守一段没人用的实现。")
    }

    /// **导出一个文件却不说怎么用，等于没做这个功能。**
    ///
    /// `VocabularyExportFormat.howToUse` 那两段话（Anki 导入对话框怎么点、
    /// AnkiConnect 怎么发）在 Core 那边有测试守着内容，这里守的是它真的上了屏。
    func testHowToUseIsOnScreenBeforeTheUserEverClicksExport() throws {
        let howTo = try SourceGuard.memberBody(of: "private var howToUseSection",
                                               in: try Self.viewCode())
        XCTAssertTrue(howTo.contains("VocabularyExportFormat.allCases"),
                      "只说了其中一种格式怎么用。实际取到的是：\n\(howTo)")
        XCTAssertTrue(howTo.contains("format.howToUse"),
                      "「这个文件怎么用」没有上屏。用户导出一个 .txt 之后会拿着它发呆——"
                          + "导出一个文件却不说怎么用，等于没做这个功能。实际取到的是：\n\(howTo)")
        XCTAssertTrue(howTo.contains("format.title"),
                      "两段说明没标清各自说的是哪种格式。实际取到的是：\n\(howTo)")
        SourceGuard.assertRenders(
            "howToUseSection", inBodyOf: "var body: some View", of: Self.view,
            because: "「导出的文件怎么用」写好了却没摆进 `body`。")
    }

    /// 格式到文件类型的映射真跑一遍。扫源码问不出「`.ankiConnectJSON` 到底存成了什么类型」，
    /// 而存错类型的后果是用户拿到一个扩展名是 .json、系统却认成纯文本的文件。
    func testEveryExportFormatMapsToTheRightContentType() {
        XCTAssertEqual(VocabularyView.contentType(for: .ankiTSV), .plainText,
                       "Anki 导入文件应当是纯文本")
        XCTAssertEqual(VocabularyView.contentType(for: .ankiConnectJSON), .json,
                       "AnkiConnect 请求应当是 JSON")
    }

    /// 上一条只比对了两个取值，**这一条守的是「两个还在不在」**：
    /// `VocabularyExportFormat` 将来加一种而这里漏掉一支，编译器会逼人补——
    /// 但只有在 switch 穷尽的前提下。
    func testTheContentTypeSwitchIsExhaustiveSoANewFormatCannotSlipThrough() throws {
        let mapping = try SourceGuard.memberBody(of: "static func contentType",
                                                 in: try Self.viewCode())
        XCTAssertFalse(mapping.contains("default:"),
                       "文件类型映射用了 `default:` 兜底。将来加一种导出格式，"
                           + "它会被静默地存成兜底那个类型，编译器一声不吭。"
                           + "下一步：逐种写全。实际取到的是：\n\(mapping)")
        for format in VocabularyExportFormat.allCases {
            XCTAssertTrue(mapping.contains(".\(format.rawValue)"),
                          "文件类型映射里没有 `.\(format.rawValue)` 这一支。实际取到的是：\n\(mapping)")
        }
    }

    // MARK: - 要求 5（续）：导出之后必须把 skipped 每一条都说出来

    /// **不能只显示「导出成功」。** `ExportDocument.skipped` 里每一条都是
    /// 「这条词为什么没进文件 + 下一步怎么办」；吞掉它们的话，用户拿到的是一份
    /// 比他以为的少几张卡的牌组，而他要到 Anki 里才会发现。
    func testTheSavedNoticeCarriesEverySkippedLineAndSaysHowToUseTheFile() {
        let document = ExportDocument(text: "x", suggestedFileName: "v.txt", exportedCount: 3,
                                      skipped: ["跳过了「aaa」：…下一步：…", "跳过了「bbb」：…下一步：…"])
        let notice = VocabularyView.savedNotice(fileName: "v.txt", document: document,
                                                format: .ankiTSV)
        XCTAssertEqual(notice.kind, .done)
        XCTAssertTrue(notice.title.contains("3"), "没说清导出了几张卡：\(notice.title)")
        XCTAssertTrue(notice.title.contains("v.txt"), "没说清存到哪个文件：\(notice.title)")
        XCTAssertTrue(notice.title.contains(VocabularyExportFormat.ankiTSV.howToUse),
                      "存完之后没说这个文件怎么用：\(notice.title)")
        XCTAssertEqual(notice.details, document.skipped,
                       "跳过的那几条被吞掉了，用户只看到「导出成功」")
    }

    /// 一张卡都没导出去时，**不能报喜**。文件确实写下去了，但里面是空的。
    func testAnExportThatWroteNoCardsDoesNotPretendItWorked() {
        let document = ExportDocument(text: "x", suggestedFileName: "v.txt", exportedCount: 0,
                                      skipped: ["当前筛选（优先记）下一条词都没有…下一步：…"])
        let notice = VocabularyView.savedNotice(fileName: "v.txt", document: document,
                                                format: .ankiTSV)
        XCTAssertEqual(notice.kind, .nothingExported,
                       "0 张卡的导出被报成了成功：\(notice.title)")
        XCTAssertEqual(notice.details, document.skipped)
    }

    /// 存盘失败必须说清「发生了什么 + 下一步做什么」（铁律 6），不许一声不吭（铁律 7）。
    func testTheSaveFailureNoticeSaysWhatHappenedAndWhatToDoNext() {
        let notice = VocabularyView.failureNotice(
            NSError(domain: "test", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "没有写入权限"]))
        XCTAssertEqual(notice.kind, .failed)
        XCTAssertTrue(notice.title.contains("没有写入权限"),
                      "没把系统给的原因带出来，用户不知道到底哪儿不行：\(notice.title)")
        XCTAssertTrue(notice.title.contains("下一步"),
                      "只说了失败，没说下一步做什么：\(notice.title)")
    }

    /// 剪贴板：**点了要有明确反馈，写失败了更要说**。
    /// `NSPasteboard.setString` 是有返回值的，吞掉它然后显示「已复制」是本项目明令禁止的
    /// 静默失败（铁律 7）。
    func testCopyingToTheClipboardAlwaysSaysWhatHappened() {
        let document = ExportDocument(text: "x", suggestedFileName: "v.json", exportedCount: 2,
                                      skipped: ["跳过了「aaa」：…下一步：…"])

        let copied = VocabularyView.clipboardNotice(didWrite: true, document: document,
                                                    format: .ankiConnectJSON)
        XCTAssertEqual(copied.kind, .done)
        XCTAssertTrue(copied.title.contains("2"), "没说清复制了几张卡：\(copied.title)")
        XCTAssertTrue(copied.title.contains(VocabularyExportFormat.ankiConnectJSON.howToUse),
                      "复制完之后没说剪贴板里那份东西怎么用：\(copied.title)")
        XCTAssertEqual(copied.details, document.skipped, "跳过的那几条被吞掉了")

        let failed = VocabularyView.clipboardNotice(didWrite: false, document: document,
                                                    format: .ankiConnectJSON)
        XCTAssertEqual(failed.kind, .failed,
                       "剪贴板写失败了却报成成功——用户会去 Anki 里粘一份空白：\(failed.title)")
        XCTAssertTrue(failed.title.contains("下一步"),
                      "剪贴板失败只说了失败，没说下一步做什么：\(failed.title)")

        let nothing = VocabularyView.clipboardNotice(
            didWrite: true,
            document: ExportDocument(text: "", suggestedFileName: "v.json", exportedCount: 0,
                                     skipped: ["当前筛选（优先记）下一条词都没有…下一步：…"]),
            format: .ankiConnectJSON)
        XCTAssertEqual(nothing.kind, .nothingExported,
                       "复制了一份空内容却报成成功：\(nothing.title)")
    }

    func testTheClipboardButtonReallyWritesAndReallyChecksTheResult() throws {
        let copy = try SourceGuard.memberBody(of: "private var copyButton",
                                              in: try Self.viewCode())
        XCTAssertTrue(copy.contains("Button(\"复制到剪贴板\")"),
                      "没有「复制到剪贴板」这颗按钮。用户已有的 AnkiConnect 脚本"
                          + "可以直接吃剪贴板内容，这是这一页最短的一条路。实际取到的是：\n\(copy)")
        XCTAssertTrue(copy.contains("writeToPasteboard("),
                      "「复制到剪贴板」点下去没有真的写剪贴板。实际取到的是：\n\(copy)")
        XCTAssertTrue(copy.contains("clipboardNotice(didWrite:"),
                      "写剪贴板的成败没有交给 `clipboardNotice(didWrite:document:format:)` 判断——"
                          + "自己写一句「已复制」的话，上面那条真跑起来的测试就在测一段没人用的实现，"
                          + "而 `NSPasteboard.setString` 返回 false 时用户会被告知复制成功。"
                          + "实际取到的是：\n\(copy)")
        SourceGuard.assertRenders(
            "copyButton", inBodyOf: "private var exportSection", of: Self.view,
            because: "「复制到剪贴板」写好了却没摆进那一排按钮里，用户点不到它。")
    }

    /// 反馈得真的画出来，而且 `details` 里每一条都要画。
    func testTheNoticeIsRenderedIncludingEveryDetailLine() throws {
        let notice = try SourceGuard.memberBody(of: "private var noticeSection",
                                                in: try Self.viewCode())
        XCTAssertTrue(notice.contains("notice.title"),
                      "导出/复制之后那句反馈没有上屏，用户点完不知道发生了什么。"
                          + "实际取到的是：\n\(notice)")
        XCTAssertTrue(notice.contains("notice.details"),
                      "跳过的那几条写好了却没画出来，用户只看到「导出成功」。"
                          + "实际取到的是：\n\(notice)")
        XCTAssertTrue(notice.contains("CoachCard"),
                      "反馈没走 `CoachCard`，会混在正文里没人注意到。实际取到的是：\n\(notice)")
        SourceGuard.assertRenders(
            "noticeSection", inBodyOf: "var body: some View", of: Self.view,
            because: "导出之后那段反馈没摆进 `body`，等于点了导出没反应。")
    }

    /// 三种反馈的语义色。**逐档写全，不许 `default:` 兜底**——将来加一档，
    /// 兜底会把它静默地画成某个已有的颜色，编译器一声不吭。
    func testNoticeColoursMatchWhatEachKindMeans() throws {
        XCTAssertEqual(VocabularyView.noticeColor(.done), Palette.success)
        XCTAssertEqual(VocabularyView.noticeColor(.nothingExported), Palette.warning,
                       "「一张卡都没导出去」被画成了好消息色")
        XCTAssertEqual(VocabularyView.noticeColor(.failed), Palette.danger,
                       "失败没有被标出来，用户扫一眼看不出出事了")

        let mapping = try SourceGuard.memberBody(of: "static func noticeColor",
                                                 in: try Self.viewCode())
        XCTAssertFalse(mapping.contains("default:"),
                       "反馈配色用了 `default:` 兜底。实际取到的是：\n\(mapping)")
    }

    /// 反馈图标只能是 SF Symbols（DESIGN-SYSTEM 第 4 节：不用 emoji），
    /// 而且名字打错不会报错、只会渲染成空白——这里当场问系统认不认。
    func testEveryNoticeIconIsARealSFSymbol() {
        for kind in VocabularyExportNotice.Kind.allCases {
            let name = VocabularyView.noticeIcon(kind)
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "系统不认识 SF Symbol「\(name)」（\(kind)），这个标记会显示成空白")
        }
    }

    // MARK: - 要求 6 / 7：两种空状态，以及空词汇本时导出必须禁用

    func testTheEmptyVocabularyGivesAllThreeThings() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "emptyState", inBodyOf: "private var listSection", of: Self.view,
            because: "一个词都没有时这一页不再走空状态那一支，用户看到的是一片空白"
                + "（DESIGN-SYSTEM 第 4 节要求空状态必须给足三样）。")
        let empty = try SourceGuard.memberBody(of: "private var emptyState", in: code)
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "空状态没走 `EmptyStateView`，那三样（现状 / 下一步 / 一颗按钮）"
                          + "就没人管得住了。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("词汇本还是空的"),
                      "空状态没说清现状。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("下一步") || empty.contains("练一场"),
                      "空状态没说下一步该干什么。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("onGo(.today)"),
                      "空状态那颗按钮点下去哪儿也不去，用户读完还得自己回侧边栏翻。"
                          + "实际取到的是：\n\(empty)")
    }

    /// 词汇本为空时导出必须禁用（计划 Step 3 验收要求 6）。
    ///
    /// **两颗按钮各断言各的。** 从前这里写的是
    /// `export.contains(".disabled(model.rows.isEmpty)")` ——纯子串判断，
    /// 而 `exportSection` 里有两处 `.disabled(model.rows.isEmpty)`，
    /// 删掉任意一处另一处照样让断言为真（实测：单删导出菜单那一句，
    /// 空词汇本也能点导出、存出一个没有任何卡片的文件，全量 1131 条全绿）。
    func testTheExportMenuIsDisabledOnAnEmptyVocabulary() throws {
        let menu = try SourceGuard.memberBody(of: "private var exportMenu",
                                              in: try Self.viewCode())
        XCTAssertTrue(menu.contains(".disabled(model.rows.isEmpty)"),
                      "词汇本为空时导出菜单还能点，点下去会存出一个没有任何卡片的文件。"
                          + "实际取到的是：\n\(menu)")
    }

    func testTheCopyButtonIsDisabledOnAnEmptyVocabulary() throws {
        let copy = try SourceGuard.memberBody(of: "private var copyButton",
                                              in: try Self.viewCode())
        XCTAssertTrue(copy.contains(".disabled(model.rows.isEmpty)"),
                      "词汇本为空时「复制到剪贴板」还能点，点下去会把一份没有任何卡片的内容"
                          + "写进剪贴板，把用户正在复制的东西冲掉。实际取到的是：\n\(copy)")
    }

    /// 灰掉的按钮必须说清为什么灰。
    /// 一颗点了什么都不会发生的按钮，比一颗灰掉并写明原因的按钮更让人困惑。
    func testTheDisabledExportSaysWhyItIsDisabled() throws {
        let export = try SourceGuard.memberBody(of: "private var exportSection",
                                                in: try Self.viewCode())
        XCTAssertTrue(export.contains("disabledHint"),
                      "导出灰掉了却没说为什么。实际取到的是：\n\(export)")
        XCTAssertTrue(export.contains("model.rows.isEmpty ?"),
                      "那句说明没有按「词汇本空不空」切换，用户在有词的时候也会读到"
                          + "「现在没有任何东西可以导出」。实际取到的是：\n\(export)")
        let hint = VocabularyView.disabledHint
        XCTAssertFalse(hint.isEmpty)
        XCTAssertTrue(hint.contains("下一步"), "禁用说明没说下一步做什么：\(hint)")
    }

    /// **筛选之后为空同样不能留白。** 选了「优先记」而一条都没有时摆一片空白，
    /// 用户会以为是筛选控件坏了。
    func testFilteringDownToNothingAlsoSaysSoAndOffersAWayBack() throws {
        SourceGuard.assertRenders(
            "filteredEmptyState", inBodyOf: "private var listSection", of: Self.view,
            because: "筛到一条都不剩时这一页是一片空白，用户会以为筛选控件坏了。")
        let empty = try SourceGuard.memberBody(of: "private var filteredEmptyState",
                                               in: try Self.viewCode())
        XCTAssertTrue(empty.contains("EmptyStateView("),
                      "筛选后的空状态没走 `EmptyStateView`。实际取到的是：\n\(empty)")
        XCTAssertTrue(empty.contains("filter = .all"),
                      "「换成全部看看」那颗按钮点下去不会真的换回全部。"
                          + "按钮点了没反应是本项目最不能接受的那一类。实际取到的是：\n\(empty)")

        // 问的是 `VocabularyPriority.high.title` 而不是 `VocabularyFilter.high.title`：
        // 后者和被测那句话是同一个属性产出的，档次名一起变英文时这条断言恒真（自证式断言）。
        // Core 那边已经把 `VocabularyPriority.high.title` 钉成了「优先记」。
        let hint = VocabularyView.filteredEmptyHint(.high)
        XCTAssertTrue(hint.contains(VocabularyPriority.high.title),
                      "筛选后的空状态没说清是哪一档筛空了：\(hint)")
        XCTAssertTrue(hint.contains("下一步"), "筛选后的空状态没说下一步做什么：\(hint)")
        XCTAssertTrue(hint.contains(VocabularyFilter.all.title),
                      "筛选后的空状态没告诉用户可以换回「全部」：\(hint)")
    }

    // MARK: - 删掉一条词（复审第 11 条）

    /// 导出跳过残缺词条时给的下一步是「到「我的词汇」页点这条右边的「删掉这个词」」。
    /// **这条测试就是那句话的兑现凭证**：那颗按钮得真的在这一页上，
    /// 而且点下去要先弹确认框、真的走 `AppState.deleteVocabulary`。
    ///
    /// 复审实测：在这之前全应用（含命令行与 MCP）没有任何地方能删掉一条词汇，
    /// 用户站在这一页上翻遍整页也找不到入口，只能手动去改 state.json。
    func testTheDeleteEntryPromisedByTheExporterReallyExistsOnThisPage() throws {
        let exporter = try SourceGuard.repositoryCode(
            "Sources/IELTSCoachCore/Export/VocabularyExporter.swift")
        XCTAssertTrue(exporter.contains("「我的词汇」页"),
                      "导出那两句「下一步」不再把用户指到这一页了，这条测试的前提失效。"
                          + "下一步：确认那两句现在指的是哪儿，再改这条断言。")
        let promised = "删掉这个词"
        XCTAssertTrue(exporter.contains(promised),
                      "导出的提示没有点名那颗按钮，用户得自己在页面上找：\(exporter.prefix(0))")

        let controls = try SourceGuard.literalControlTitles()
        XCTAssertTrue(controls.contains(promised),
                      "全 App 找不到叫「\(promised)」的按钮，而导出的提示正让用户去点它（铁律 4）。"
                          + "界面上真有的是：\(controls.sorted().joined(separator: "、"))")

        let code = try Self.viewCode()
        SourceGuard.assertRenders("deleteButton(row)", inBodyOf: "private func vocabularyCard",
                                  of: Self.view,
                                  because: "删除入口没有画在词汇卡片上——声明着但一个像素都不上屏，"
                                      + "而导出的提示正让用户去点它。")
        XCTAssertTrue(code.contains(".confirmationDialog("),
                      "删一条词是不可撤销的，必须先弹确认框，不许点一下就删。")
        XCTAssertTrue(code.contains("app.deleteVocabulary("),
                      "删除没有走 AppState.deleteVocabulary，那就没有落盘、也没有重读，"
                          + "用户关掉窗口再打开会发现它又回来了。")
    }

    /// 确认框和删完那句话**原样取 Core 那一份**，这一页不另写一套说法。
    /// 另写一套的话，只有 Core 那份有测试守着，而屏幕上显示的是没人守的那份。
    func testTheDeletionCopyComesFromTheOneTestedSource() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("VocabularyDeletion.confirmationText(for:"),
                      "确认框里的正文不是 VocabularyDeletion 那一份。")
        XCTAssertTrue(code.contains("deletionNotice = app.deleteVocabulary("),
                      "删完之后没有把那句中文说明接到界面上——成功也要说话，"
                          + "一行悄悄消失，用户分不清「删掉了」和「点了没反应」。")
        SourceGuard.assertRenders("deletionNotice", inBodyOf: "@ViewBuilder private var deletionNoticeSection",
                                  of: Self.view, atLeast: 2,
                                  because: "删完那句话没有被画出来。")
    }

    /// 确认框标题得说清删的是哪个词；残缺条目（原词也空）不许拼出「删掉「」？」。
    func testTheDeletionTitleNamesTheWordAndSurvivesABlankOne() {
        let named = VocabularyRow(record: record("v1", basic: "good", priority: "high"))
        XCTAssertTrue(VocabularyView.deletionTitle(named).contains("good"),
                      VocabularyView.deletionTitle(named))
        let blank = VocabularyRow(record: VocabularyRecord(id: "v2", basicWord: " ",
                                                          betterExpression: "", collocation: "",
                                                          priority: "normal",
                                                          sourceSessionIds: ["s1"]))
        XCTAssertFalse(VocabularyView.deletionTitle(blank).contains("「」"),
                       VocabularyView.deletionTitle(blank))
    }

    // MARK: - 接线：这一页得真的挂在侧边栏上

    func testTheSidebarActuallyRoutesToThisPage() throws {
        let root = try SourceGuard.code("RootView.swift")
        XCTAssertTrue(root.contains("case .vocabulary: VocabularyView(app: app"),
                      "`RootView` 的 detail 分支里没有这一页，侧边栏点「我的词汇」落到的还是"
                          + "那张「还没做」的占位页——而 `SidebarItem.vocabulary.isImplemented` "
                          + "已经写成 true，占位页连说明都不会有。")
    }
}
