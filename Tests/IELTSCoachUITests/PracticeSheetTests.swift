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

    /// **上一条那种逐个手写的断言补不完，这一条问的是结构。**
    ///
    /// 上一条钉的是「`stageBlock` / `checklist` 得在 `practiceBody` 里」，于是漏掉了上面一层：
    /// 本次实测把 `body` 里 `practiceBody(for: running)` 和 `actions` 那两句一起去掉，
    /// **465 条一条不红**——那时整张 sheet 只剩一行题目，进度、失败信息、按钮全没了，
    /// 用户开一场练习就再也退不出来。
    ///
    /// 所以这里改成问：这张 sheet 声明的每一段渲染，从 `body` 顺着调用关系走得到吗？
    /// 全模块同样的一趟在 `RenderReachabilitySweepTests` 里；这一条单独钉住这张 sheet，
    /// 是因为它是整条链路上唯一一处「失败信息上屏」的地方，报错要就地说清后果。
    func testEverySectionThisSheetDeclaresIsReachableFromItsBody() throws {
        let code = try SourceGuard.code(Self.sheet)
        guard let sheet = SourceGuard.viewTypes(in: code).first(where: { $0.name == "PracticeSheet" })
        else {
            return XCTFail("在 \(Self.sheet) 里找不到带 `body` 的 `PracticeSheet`，这条测试等于空转。"
                           + "下一步：确认这个类型还在、还是个 SwiftUI 视图。")
        }

        // 先钉住这一趟真的看见了那几段关键渲染，否则「没有走不到的」是恒真的。
        let names = Set(sheet.viewMembers.map(\.name))
        for required in ["body", "practiceBody", "picker", "actions", "stageBlock", "checklist"] {
            XCTAssertTrue(names.contains(required),
                          "扫不到 `\(required)` 这段渲染。下一步：改了名字就同步改这条测试；"
                              + "整段没了的话，先想清楚它画的东西现在归谁。")
        }

        XCTAssertEqual(sheet.unreachable, [],
                       "这几段渲染声明着，却从 `body` 走不到——写好的东西一个像素都不上屏，"
                           + "而且不会有任何编译错误。启动语音那九秒会是纯白板，"
                           + "失败信息一个字都不上屏，按钮那一排整个消失。"
                           + "下一步：把它们摆回 `body` 的 VStack 里。")
    }

    /// **自由选题那条路唯一的入口。**
    ///
    /// `TodayView` 传进来的 `preselected` 是 `model.plannedQuestion(for:)` 算出来的，
    /// freePick 那条路线、以及「路线原来指着的题在题库里已经没有了」这两种情况都是 nil。
    /// 那时 sheet 停在挑题列表，`.idle` 里这颗「开始练习」就是唯一能往下走的东西。
    ///
    /// 复审实测：把这整块删掉，**465 条全绿**（`startPicked()` 变成没人调的 private func，
    /// Swift 连警告都不给）。后果是用户挑完题之后，界面上没有任何可点的东西。
    ///
    /// 扫的是 `actions` 那一段：同文件的 `stageIcon` / `stageTint` / `checklist` 里
    /// 各有一份纯装饰用的 switch，扫全文的话 `case .idle` 在别处也扫得到。
    func testTheIdleStateHasTheStartButtonThatFreePickDependsOn() throws {
        for (needle, what) in [
            ("case .idle", "空闲态在按钮那一段里根本没被单独处理"),
            (#"Button("开始练习")"#, "空闲态下没有「开始练习」这颗按钮"),
            ("startPicked()", "「开始练习」没有接到 `startPicked()` 上，按下去什么都不会发生")
        ] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private var actions", of: Self.sheet,
                because: "\(what)。自由选题（以及「路线原来指着的题在题库里已经没有了」）"
                    + "那条路上 `preselected` 是 nil，sheet 停在挑题列表，"
                    + "没有这颗按钮就再也走不下去了。"
                    + "下一步：把它加回去；换了别的标题或方法名就同步改这条测试。")
        }

        // 按钮按下去之后真的把选中的题变成一场练习。`startPicked` 被掏空成 `{}` 时这条会红。
        for (needle, what) in [("makeSetup(question)", "把选中的题变成这一场的设置"),
                               ("begin(", "开练")] {
            SourceGuard.assertRenders(
                needle, inBodyOf: "private func startPicked", of: Self.sheet,
                because: "`startPicked()` 里没有\(what)，这颗按钮按下去什么都不会发生"
                    + "（而界面上看不出任何异样——铁律 5 说的静默失败）。"
                    + "下一步：把这一步接回去。")
        }

        // 挑题那一步也得能真的选中，否则按钮永远是 disabled 的。
        SourceGuard.assertRenders(
            "picked = question.id", inBodyOf: "private func questionRow", of: Self.sheet,
            because: "题目那一行点下去不会把它标成选中，「开始练习」就永远是灰的（`disabled(picked == nil)`），"
                + "自由选题这条路照样走不通。下一步：把选中这一步接回去。")
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

    /// **每一个 `PracticeStage` 下，界面上都得有一颗点得到的按钮。**
    ///
    /// 上一条钉的是三个「需要用户动手」的状态，于是漏掉了剩下那八个**自动跑**的状态——
    /// 它们全落在 `actions` 的 `default:` 分支里，而那颗「取消」此前一个人都没钉。
    /// 复审实测：把 `default:` 换成 `default: EmptyView()`，**全套测试一条不红**。
    ///
    /// 后果是：启动语音那 9 秒（`.newChat` / `.startingVoice` / `.waitingComposer` /
    /// `.sendingPrompt`，spec 2.3.7 实测约 9 秒）和请 ChatGPT 写复盘那一分钟左右
    /// （`.endingVoice` / `.requestingReview` / `.capturingReview` / `.archiving`）里，
    /// 界面上一颗按钮都没有。用户唯一的出路是强退，而那时 ChatGPT 那边的语音通话
    /// 已经拨出去了，退掉之后既挂不断也取不回复盘（铁律 5：禁止静默失败、禁止无限等待）。
    /// 这个文件自己的 MARK 就写着「按钮：每个状态都得有一条出口」。
    ///
    /// **状态清单是从 `PracticeStage` 的声明里读出来的，不是手写的**：手写清单的通病
    /// 是新加的那一项没人写进来。往 `PracticeStage` 里加一个 stage 却没给它出口，
    /// 也会在这里当场变红。
    ///
    /// 「点得到」比「有一颗 `Button`」严一档：写在 `if` 里的（条件不成立时根本不画）、
    /// 挂了 `.disabled(…)` 的（按不动）、闭包是空的（按了什么都不发生）都不算。
    func testEveryPracticeStageHasAWayOut() throws {
        let stages = try SourceGuard.declaredCaseNames(
            inEnum: "PracticeStage", of: try SourceGuard.code("Session/PracticeStage.swift"))

        // 先钉住这一趟真的把状态读全了。清单一空或者只剩几个，
        // 下面那个 for 就成了空转——「每个状态都有出口」会变成恒真。
        for required in ["idle", "newChat", "startingVoice", "waitingComposer", "sendingPrompt",
                         "practicing", "endingVoice", "requestingReview", "capturingReview",
                         "needsManualCopy", "archiving", "done", "failed"] {
            XCTAssertTrue(stages.contains(required),
                          "没从 `PracticeStage` 里读到 `.\(required)`，这条测试对它就没在守。"
                              + "下一步：状态改名了就同步改这条清单；真的删掉了，"
                              + "先确认界面上再没有一条路会停在那个状态上。")
        }

        let actions = try SourceGuard.memberBody(
            of: "private var actions", in: try SourceGuard.code(Self.sheet))
        let branches = try SourceGuard.switchBranches(over: "runner.stage", in: actions)

        // 同上：分支要是一条都没切出来、或者全糊成了一条，下面每一句都会失去依据。
        XCTAssertGreaterThanOrEqual(
            branches.filter { !$0.isDefault }.count, 3,
            "按钮那一段的 `switch runner.stage` 只切出了 \(branches.count) 条分支，"
                + "这多半是切分支的写法失效了——失效之后每个状态都会被算到同一条分支上，"
                + "断言就恒真了。下一步：确认 `actions` 里还是一个 `switch runner.stage`。")

        for stage in stages {
            guard let branch = branches.first(where: { $0.cases.contains(stage) })
                    ?? branches.first(where: \.isDefault) else {
                XCTFail("`.\(stage)` 在按钮那一段的 `switch` 里既没有自己的分支，也没有 `default` 兜底，"
                        + "这个状态下界面上一颗按钮都没有，用户只能强退。"
                        + "下一步：给它一条分支，或者留一个带「取消」的 `default`。")
                continue
            }
            let exits = SourceGuard.unconditionalButtons(in: branch.body)
            let usable = exits.filter(\.isWired)
            XCTAssertFalse(
                usable.isEmpty,
                "`.\(stage)` 落在 `\(branch.label)` 这条分支上，而这条分支里没有任何一颗"
                    + "「一定看得见、按得动、按下去真的会发生事情」的按钮"
                    + "（扫到的按钮：\(exits.isEmpty ? "一颗都没有" : exits.map(\.label).joined(separator: "、"))）。"
                    + "用户会停在这个状态上，界面上没有任何出路，只能强退——"
                    + "而这时 ChatGPT 那边的语音通话可能已经开起来了。"
                    + "下一步：给这条分支至少留一颗无条件、不 disabled、接了动作的按钮"
                    + "（自动跑的那几步留「取消」就够）。")
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

    /// **Phase 4 唯一那条硬约束的界面这一半。**
    ///
    /// 约束原话：「采样失败不中断练习，**但失败必须被记账并在练完后显示出来**」
    /// （ROADMAP 3.2 / 本阶段计划「本阶段独有的一条硬约束」）。运行器那一半
    /// （`transcriptNotice` / `transcriptTurnCount` 怎么算出来）已经被
    /// `PracticeRunnerArchiveTests` 逐条钉住了，可**算出来的话能不能上屏，此前一行测试都没管**。
    ///
    /// 复审实测过两次突变，两次都是 612 条全绿：
    ///
    /// - 把 `transcriptBlock` 的整段声明连同 `practiceBody` 里那句调用一起删掉；
    /// - 只删 `transcriptBlock` 里 `if let notice = runner.transcriptNotice { … }` 那半块，
    ///   保留「已记录 N 条对话」。
    ///
    /// 第二种正是计划里点名的「本项目最忌讳的失败形态」：悄悄丢掉几分钟对话，
    /// 而界面上那行计数看起来一切正常，用户没有任何理由怀疑逐字稿是残的。
    ///
    /// 所以这里分两层扫：`practiceBody` 里那句调用（摆上去了没有），
    /// 加 `transcriptBlock` 自己那一段里的两处取值（画的是不是那两个值）。
    /// 只扫全文的话，两处都是「文件里有这个词」，删掉调用点照样绿。
    func testTheTranscriptNoticeAndTurnCountAreShown() throws {
        SourceGuard.assertRenders(
            "transcriptBlock", inBodyOf: "private func practiceBody", of: Self.sheet,
            because: "`transcriptBlock` 只是声明着，没有被摆进 `practiceBody`——"
                + "逐字稿这一路的交代一个像素都不上屏，而这不会有任何编译错误。"
                + "后果：采样失败被记了账却没人看得见，用户以为逐字稿是全的，"
                + "实际悄悄少了几分钟对话——这是本项目最忌讳的失败形态。"
                + "下一步：把 `transcriptBlock` 放回 `practiceBody` 的 VStack 里；"
                + "换了别的名字就同步改这条测试。")

        for (piece, what) in [
            ("runner.transcriptNotice",
             "逐字稿不完整时那句中文说明（缺了什么、下一步做什么）"),
            ("runner.transcriptTurnCount",
             "练习中那行「已记录 N 条对话」——它是用户唯一能看出采样还活着的迹象")
        ] {
            SourceGuard.assertRenders(
                piece, inBodyOf: "private var transcriptBlock", of: Self.sheet,
                because: "`transcriptBlock` 里不再读 `\(piece)` 了，界面上少的是：\(what)。"
                    + "运行器把它算出来了却不上屏，等于静默失败。"
                    + "下一步：把这半块画回 `transcriptBlock`（说明用 `Palette.warning`，"
                    + "不要画成红色错误——逐字稿是增强，不是必需）。")
        }
    }
}
