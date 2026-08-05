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
    func testEveryButtonIsWiredToTheRunner() throws {
        let code = try Self.sheetCode()
        let wiring: [(String, String)] = [
            ("runner.start(setup:", "开练"),
            ("runner.finishPractice(", "「我练完了」"),
            ("runner.captureReviewFromClipboard(", "「我已经复制好了」（手动 ⌘C 兜底）"),
            ("runner.cancel(", "中途取消")
        ]
        for (call, what) in wiring {
            XCTAssertTrue(
                code.contains(call),
                "\(what)没有接到 `\(call)…)` 上，这条路是死的。"
                    + "下一步：把它接上；换了别的方法名就同步改这条测试。")
        }
    }

    /// 三个终点状态各自要画出来的东西。少画一个，用户就卡在那儿：
    /// - `.practicing` 没有「我练完了」→ 练完之后没有出口；
    /// - `.needsManualCopy` 没有那个按钮 → 复盘明明还在 ChatGPT 里却救不回来；
    /// - `.failed` 不显示原文 → 只剩一句「失败了」，无从下手（铁律 6）。
    func testTheThreeStatesThatNeedAUserActionAllHaveOne() throws {
        let code = try Self.sheetCode()
        for state in ["case .practicing", "case .needsManualCopy", "case .failed"] {
            XCTAssertTrue(
                code.contains(state),
                "sheet 没有单独处理 `\(state)`，那个状态下用户没有任何可点的东西。"
                    + "下一步：给它一个按钮——练完、手动复制、重试，各是一条出口。")
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
}
