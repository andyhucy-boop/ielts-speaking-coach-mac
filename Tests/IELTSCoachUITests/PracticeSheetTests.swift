import Foundation
import XCTest

@testable import IELTSCoachUI

/// 练习进行中那张 sheet 上，几件**没法靠数据断言守住、但决定这一场能不能走完**的事。
///
/// `PracticeRunner` 的状态流转已经被 `PracticeRunnerTests` 逐条钉住了，但那些状态得真的
/// 画到界面上、按钮得真的连到那几个方法上，否则整条链路在用户那边就是一块不动的白板。
/// 扫源码的边界与 `TodayViewTests` 一样：拦得住「整段被删掉 / 没接上」，
/// 拦不住「代码还在但跑不到」，也不管好不好看（那归 Task 11 人工验收）。
final class PracticeSheetTests: XCTestCase {

    /// 九秒的语音启动过程中，界面必须一直在说它在干什么（DESIGN-SYSTEM 第 5 节）。
    /// `userFacingText` 写得再好，不画出来也等于没有。
    func testTheSheetPaintsWhatEachStageIsDoing() throws {
        let code = try Self.sheetCode()

        XCTAssertTrue(
            code.contains("struct PracticeSheet"),
            "没扫到 PracticeSheet 的源码，这条测试等于空转。下一步：确认文件还在——"
                + Self.source.path)

        XCTAssertTrue(
            code.contains("userFacingText"),
            "sheet 没有显示 `stage.userFacingText`。用户会对着一个不动的窗口等九秒"
                + "（启动语音实测约 9 秒），然后以为程序死了。"
                + "下一步：把当前阶段那句话画出来，并配一个进度指示。")
    }

    /// 四个动作各自接到运行器的哪个方法上。接错一个，那条路就是死的：
    /// 「我练完了」不调 `finishPractice` 的话，用户练完之后没有任何办法取回复盘。
    ///
    /// 后两条只在 `actions` 那一段里找：`redo(_:)` 里对这两个方法各还留着一处调用，
    /// 扫全文的话，把「我练完了」整颗按钮删掉照样扫得到——那条路已经死了，测试却还是绿的。
    func testEveryButtonIsWiredToTheRunner() throws {
        let code = try Self.sheetCode()
        // 这两处不在 `actions` 里（分别在 `begin` 与 `abandon` 里），扫全文。
        for (call, what) in [("runner.start(setup:", "开练"), ("runner.cancel(", "中途取消")] {
            XCTAssertTrue(
                code.contains(call),
                "\(what)没有接到 `\(call)…)` 上，这条路是死的。"
                    + "下一步：把它接上；换了别的方法名就同步改这条测试。")
        }

        let actions = try Self.actionsCode()
        for (call, what) in [("runner.finishPractice(", "「我练完了」"),
                             ("runner.captureReviewFromClipboard(", "「我已经复制好了」（手动 ⌘C 兜底）")] {
            XCTAssertTrue(
                actions.contains(call),
                "\(what)那颗按钮没有接到 `\(call)…)` 上，这条路是死的。"
                    + "下一步：把它接上；换了别的方法名就同步改这条测试。")
        }
    }

    /// 三个需要用户动手的状态，各自得有一颗真按钮。少一颗，用户就卡在那儿：
    /// - `.practicing` 没有「我练完了」→ 练完之后没有任何办法取回复盘；
    /// - `.needsManualCopy` 没有「我已经复制好了」→ 复盘明明还在 ChatGPT 里却救不回来；
    /// - `.failed` 没有重试 → 只剩一句「失败了」，无从下手（铁律 6）。
    ///
    /// **扫的是按钮，不是 `switch` 的分支标签。** 同文件的 `stageIcon` / `stageTint` /
    /// `checklist` 里各还有一份纯装饰用的 switch，这三个 case 在那几处都出现过；
    /// 扫全文只扫得到那些装饰，把按钮整颗删掉一样绿（复审突变 M14 / M15 实测）。
    func testTheThreeStatesThatNeedAUserActionAllHaveOne() throws {
        let actions = try Self.actionsCode()
        let exits: [(state: String, control: String, what: String)] = [
            ("case .practicing", #"Button("我练完了")"#, "练完之后取回复盘"),
            ("case .needsManualCopy", #"Button("我已经复制好了")"#, "手动 ⌘C 之后把复盘救回来"),
            ("case .failed", "redo(retry)", "失败之后重试")
        ]
        for exit in exits {
            XCTAssertTrue(
                actions.contains(exit.state),
                "按钮那一段里没有单独处理 `\(exit.state)`，那个状态下用户没有任何可点的东西。"
                    + "下一步：给它一颗按钮——\(exit.what)。")
            XCTAssertTrue(
                actions.contains(exit.control),
                "`\(exit.state)` 下没有 `\(exit.control)` 这颗按钮，用户没法\(exit.what)。"
                    + "下一步：把按钮加回去；换了别的标题就同步改这条测试。")
        }
    }

    /// 存档之后那句交代（错题本几条、词汇本几条、原文存哪儿、有没有字段没读进去）必须显示。
    /// 只画一个「✅ 完成」的话，`ArchiveOutcome.skipped` 那种「复盘写得完整、档案纹丝不动」
    /// 的静默失败就永远没人看得见——那是本项目已知最危险的失败形态。
    func testTheArchiveNoticeIsShown() throws {
        let code = try Self.sheetCode()
        XCTAssertTrue(
            code.contains("archiveNotice"),
            "存档结果没有显示出来。下一步：把 `runner.archiveNotice` 画在完成态里。")
    }

    static var source: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources/IELTSCoachUI/Session/PracticeSheet.swift")
    }

    static func sheetCode() throws -> String {
        DesignSystemTests.strippingLineComments(
            try String(contentsOf: source, encoding: .utf8))
    }

    /// 只取 `private var actions` 那一段（截到下一个 `private` 声明）。
    ///
    /// 按钮之外的地方对 `.practicing` / `.needsManualCopy` / `.failed` 各还有一份
    /// 纯装饰用的 switch（图标、配色、进度清单），对 `finishPractice` /
    /// `captureReviewFromClipboard` 在 `redo(_:)` 里各还有一处调用。
    /// 扫全文的话，把按钮整颗删掉这些残影照样在，测试就成了空转。
    static func actionsCode() throws -> String {
        let code = try sheetCode()
        guard let start = code.range(of: "private var actions") else {
            XCTFail("没找到 `private var actions` 这一段，扫描范围失效，这几条测试等于空转。"
                        + "下一步：改了那段的名字就同步改这里——" + source.path)
            return ""
        }
        let rest = code[start.upperBound...]
        guard let end = rest.range(of: "\n    private ") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }
}
