import Foundation
import XCTest

@testable import IELTSCoachUI

/// 练习进行中那张 sheet 上，几件**没法靠数据断言守住、但决定这一场能不能走完**的事。
///
/// `PracticeRunner` 的状态流转已经被 `PracticeRunnerTests` 逐条钉住了，但那些状态得真的
/// 画到界面上、按钮得真的连到那几个方法上，否则整条链路在用户那边就是一块不动的白板。
///
/// 扫源码用的是共用的 `SourceGuard`（读不到文件会抛错，不会拿空串把断言变成永远绿）。
/// 边界与 `TodayViewTests` 一样：拦得住「整段被删掉 / 没接上」，
/// 拦不住「代码还在但跑不到」，也不管好不好看（那归人工验收）。
final class PracticeSheetTests: XCTestCase {

    private static let sheet = "Session/PracticeSheet.swift"

    /// 九秒的语音启动过程中，界面必须一直在说它在干什么（DESIGN-SYSTEM 第 5 节）。
    /// `userFacingText` 写得再好，不画出来也等于没有。
    func testTheSheetPaintsWhatEachStageIsDoing() throws {
        SourceGuard.assertRenders(
            "struct PracticeSheet", in: Self.sheet,
            because: "没扫到 PracticeSheet 的源码，这条测试等于空转。下一步：确认文件还在。")

        SourceGuard.assertRenders(
            "userFacingText", inBodyOf: "private var stageBlock", of: Self.sheet,
            because: "sheet 没有显示 `stage.userFacingText`。用户会对着一个不动的窗口等九秒"
                + "（启动语音实测约 9 秒），然后以为程序死了。"
                + "下一步：把当前阶段那句话画出来，并配一个进度指示。")
    }

    /// **这一条补的是一个已实测能溜过去的洞。**
    ///
    /// 上一条只问「文件里有没有 `userFacingText`」，而那个词写在 `stageBlock` 自己的声明里。
    /// 把 `practiceBody` 里那两句调用（`stageBlock` / `checklist`）删掉，
    /// 两段声明原封不动地留着，**369 条全绿**——而用户那边：启动语音那九秒是纯白板，
    /// 失败信息一个字都不上屏，`PracticeStage.failed` 那句写得最用心的中文错误说明
    /// 谁也看不到，只剩一个不动的窗口。
    ///
    /// 所以扫的是 `practiceBody` 那一段里有没有真的摆上它们——「写好了」和「摆上去了」
    /// 是两件事，本项目已经在四个地方分别栽过这同一跤。
    func testTheStageBlockAndChecklistAreActuallyPlacedInThePracticeBody() throws {
        for (piece, what) in [
            ("stageBlock", "当前这一步在干什么（启动语音那九秒全靠它，失败信息也在这里）"),
            ("checklist", "走到第几步了（没有它，用户不知道九秒里到底进行到哪儿）")
        ] {
            SourceGuard.assertRenders(
                piece, inBodyOf: "private func practiceBody", of: Self.sheet,
                because: "`\(piece)` 只是声明着，没有被摆进 `practiceBody`——写好的东西一个像素都不上屏，"
                    + "而这不会有任何编译错误。用户看到的是：\(what) 全没了。"
                    + "下一步：把 `\(piece)` 放回 `practiceBody` 的 VStack 里；"
                    + "换了别的名字就同步改这条测试。")
        }

        // 同时钉住声明还在。上面那条只看调用点，两处一起删的话它报的是「找不到声明」，
        // 这里让报错更直白一点。
        for piece in ["private var stageBlock", "private var checklist"] {
            SourceGuard.assertRenders(
                piece, in: Self.sheet,
                because: "这段声明被删了。下一步：确认它画的东西现在由谁负责——"
                    + "没人负责的话，那九秒的界面就是白板。")
        }
    }

    /// 四个动作各自接到运行器的哪个方法上。接错一个，那条路就是死的：
    /// 「我练完了」不调 `finishPractice` 的话，用户练完之后没有任何办法取回复盘。
    ///
    /// 后两条只在 `actions` 那一段里找：`redo(_:)` 里对这两个方法各还留着一处调用，
    /// 扫全文的话，把「我练完了」整颗按钮删掉照样扫得到——那条路已经死了，测试却还是绿的。
    func testEveryButtonIsWiredToTheRunner() throws {
        // 这两处不在 `actions` 里（分别在 `begin` 与 `abandon` 里），扫全文。
        for (call, what) in [("runner.start(setup:", "开练"), ("runner.cancel(", "中途取消")] {
            SourceGuard.assertRenders(
                call, in: Self.sheet,
                because: "\(what)没有接到 `\(call)…)` 上，这条路是死的。"
                    + "下一步：把它接上；换了别的方法名就同步改这条测试。")
        }

        for (call, what) in [("runner.finishPractice(", "「我练完了」"),
                             ("runner.captureReviewFromClipboard(", "「我已经复制好了」（手动 ⌘C 兜底）")] {
            SourceGuard.assertRenders(
                call, inBodyOf: "private var actions", of: Self.sheet,
                because: "\(what)那颗按钮没有接到 `\(call)…)` 上，这条路是死的。"
                    + "下一步：把它接上；换了别的方法名就同步改这条测试。")
        }
    }

    /// 三个需要用户动手的状态，各自得有一颗真按钮。少一颗，用户就卡在那儿：
    /// - `.practicing` 没有「我练完了」→ 练完之后没有任何办法取回复盘；
    /// - `.needsManualCopy` 没有「我已经复制好了」→ 复盘明明还在 ChatGPT 里却救不回来；
    /// - `.failed` 没有重试 → 只剩一句「失败了」，无从下手（铁律 5）。
    ///
    /// **扫的是按钮，不是 `switch` 的分支标签。** 同文件的 `stageIcon` / `stageTint` /
    /// `checklist` 里各还有一份纯装饰用的 switch，这三个 case 在那几处都出现过；
    /// 扫全文只扫得到那些装饰，把按钮整颗删掉一样绿（复审突变 M14 / M15 实测）。
    func testTheThreeStatesThatNeedAUserActionAllHaveOne() throws {
        let exits: [(state: String, control: String, what: String)] = [
            ("case .practicing", #"Button("我练完了")"#, "练完之后取回复盘"),
            ("case .needsManualCopy", #"Button("我已经复制好了")"#, "手动 ⌘C 之后把复盘救回来"),
            ("case .failed", "redo(retry)", "失败之后重试")
        ]
        for exit in exits {
            SourceGuard.assertRenders(
                exit.state, inBodyOf: "private var actions", of: Self.sheet,
                because: "按钮那一段里没有单独处理 `\(exit.state)`，那个状态下用户没有任何可点的东西。"
                    + "下一步：给它一颗按钮——\(exit.what)。")
            SourceGuard.assertRenders(
                exit.control, inBodyOf: "private var actions", of: Self.sheet,
                because: "`\(exit.state)` 下没有 `\(exit.control)` 这颗按钮，用户没法\(exit.what)。"
                    + "下一步：把按钮加回去；换了别的标题就同步改这条测试。")
        }
    }

    /// 存档之后那句交代（错题本几条、词汇本几条、原文存哪儿、有没有字段没读进去）必须显示。
    /// 只画一个「✅ 完成」的话，`ArchiveOutcome.skipped` 那种「复盘写得完整、档案纹丝不动」
    /// 的静默失败就永远没人看得见——那是本项目已知最危险的失败形态。
    ///
    /// 扫的是 `practiceBody` 那一段，理由同上面那条：光看文件里有没有这个词，
    /// 摆不摆进被渲染的那棵树是分不出来的。
    func testTheArchiveNoticeIsShown() throws {
        SourceGuard.assertRenders(
            "archiveNotice", inBodyOf: "private func practiceBody", of: Self.sheet,
            because: "存档结果没有显示出来。`ArchiveOutcome.skipped`（复盘看着正常、档案却纹丝不动）"
                + "就永远没人看得见了。下一步：把 `runner.archiveNotice` 画在完成态里。")
    }
}
