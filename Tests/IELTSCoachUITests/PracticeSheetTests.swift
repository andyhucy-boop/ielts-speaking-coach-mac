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
        //
        // `makeSetup` 现在收两个参数（题目 + 用户当场选的考法），所以这里钉的是
        // `makeSetup(question, mode)`——只钉 `makeSetup(question` 的话，把 `mode` 换成
        // 写死的 `nil` 照样能溜过去，而那正好就是「那颗开关拨了不算数」的形态。
        for (needle, what) in [("makeSetup(question, mode, trimmedGoal)", "把选中的题变成这一场的设置"),
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

    // MARK: - 放弃这一场：不许在同一帧把窗口关掉

    /// **复审第 6 条的界面这一半。**
    ///
    /// `runner.cancel()` 恰好在被点的那一刻做三件事：关掉录音（很可能因此生成一条
    /// 「录音中途因为插拔耳机断了一下」「写盘失败，已录到的部分保存在某处」的警告）、
    /// 把已经采到的逐字稿定案、写出那段「这一场已经放弃了…」的交代。
    ///
    /// 修之前 `abandon()` 是 `runner.cancel(); onClose()` 两句连着写的——
    /// 那三样东西**一帧都没画出来**就被同一次点击关掉了。
    /// 真发生过的录音故障，唯一的出口被同一次点击关掉，这是本项目最忌讳的那种静默。
    ///
    /// 关窗口归 `.abandoned` 那条分支里的「关掉」，由用户看完再点。
    func testAbandoningDoesNotCloseTheWindowInTheSameFrame() throws {
        let abandon = try SourceGuard.memberBody(of: "private func abandon", in: SourceGuard.code(Self.sheet))
        XCTAssertTrue(abandon.contains("runner.cancel("),
                      "「放弃这一场」没有接到 `runner.cancel()` 上，这条路是死的。实际取到的是：\n\(abandon)")
        XCTAssertFalse(abandon.contains("onClose()"),
                       "放弃之后在同一帧就把窗口关掉了。`cancel()` 这一刻刚生成的录音警告、"
                           + "刚写好的那段「逐字稿去哪儿了 / 录音留在哪儿 / ChatGPT 那通语音"
                           + "要不要自己挂」的交代，一个像素都画不出来。"
                           + "下一步：把 `onClose()` 从这里拿掉——`.abandoned` 那条分支里"
                           + "已经有一颗「关掉」，让用户看完再点。实际取到的是：\n\(abandon)")
    }

    /// 放弃之后那个状态必须有**自己**的一条分支，而且那条分支里是「关掉」。
    ///
    /// 落进 `default:` 的话，用户看到的是那颗「取消」——按下去又调一次 `abandon()`，
    /// 窗口永远关不掉。上面那条 `testEveryPracticeStageHasAWayOut` 拦不住这一种：
    /// `default:` 里那颗「取消」在它眼里是一颗合格的出口。
    func testTheAbandonedStateHasItsOwnBranchWhoseButtonActuallyCloses() throws {
        let actions = try SourceGuard.memberBody(of: "private var actions",
                                                 in: SourceGuard.code(Self.sheet))
        let branches = try SourceGuard.switchBranches(over: "runner.stage", in: actions)
        guard let branch = branches.first(where: { $0.cases.contains("abandoned") }) else {
            return XCTFail("按钮那一段里没有单独处理 `.abandoned`，它会落进 `default:` 那颗「取消」——"
                           + "按下去又是一次 `abandon()`，窗口永远关不掉。"
                           + "下一步：给它一条自己的分支，里面放一颗「关掉」。")
        }
        XCTAssertFalse(branch.isDefault, "`.abandoned` 落在了 `default:` 上，见上一条的理由")
        let exits = SourceGuard.unconditionalButtons(in: branch.body).filter(\.isWired)
        XCTAssertEqual(exits.map(\.label), [#""关掉""#],
                       "`.abandoned` 这条分支里该只有一颗「关掉」，实际是 \(exits.map(\.label))。"
                           + "这个状态下再没有别的事可做了：这一场已经停了，"
                           + "摆一颗「取消」或「我练完了」只会把用户绕回去。")
        XCTAssertTrue(branch.body.contains("onClose()"),
                      "`.abandoned` 那颗按钮没有接到 `onClose()` 上，按下去窗口不会关。"
                          + "实际取到的是：\n\(branch.body)")
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

    /// **Phase 5 的录音这一路，和上面逐字稿那条是同一种病。**
    ///
    /// 运行器那一半（`isRecording` / `recordingNotice` 什么时候是什么值）已经被
    /// `PracticeRunnerRecordingTests` 逐条钉住了，可**算出来的话能不能上屏，没人管**——
    /// 而这两样各自守着一件不能含糊的事：
    ///
    /// - `isRecording`：正在录音的指示。麦克风开着却一点表示都没有，用户不知道自己
    ///   什么时候在被录；
    /// - `recordingNotice`：**用户以为在录、实际没录**（没权限、麦克风被占），
    ///   或者中途插拔耳机断过一下。不显示就是骗人——练完点开回听才发现什么都没有。
    ///
    /// 分两层扫：`practiceBody` 里那句调用（摆上去了没有），加 `recordingBlock`
    /// 自己那一段里的两处取值（画的是不是那两个值）。只扫全文的话，两处都是
    /// 「文件里有这个词」，把调用点删掉照样绿。
    func testTheRecordingIndicatorAndNoticeAreShown() throws {
        SourceGuard.assertRenders(
            "recordingBlock", inBodyOf: "private func practiceBody", of: Self.sheet,
            because: "`recordingBlock` 只是声明着，没有被摆进 `practiceBody`——"
                + "录音这一路的交代一个像素都不上屏，而这不会有任何编译错误。"
                + "后果：用户既看不到自己正在被录音，也看不到「这次其实没录上」那句提示，"
                + "练完点开回听才发现什么都没有。"
                + "下一步：把 `recordingBlock` 放回 `practiceBody` 的 VStack 里；"
                + "换了别的名字就同步改这条测试。")

        for (piece, what) in [
            ("runner.isRecording",
             "「● 正在录音」那个指示——麦克风开着却一点表示都没有，用户不知道自己在被录"),
            ("runner.recordingNotice",
             "录音没录上 / 中途断过时那句中文说明（发生了什么、下一步做什么）")
        ] {
            SourceGuard.assertRenders(
                piece, inBodyOf: "private var recordingBlock", of: Self.sheet,
                because: "`recordingBlock` 里不再读 `\(piece)` 了，界面上少的是：\(what)。"
                    + "运行器把它算出来了却不上屏，等于静默失败（铁律 7）。"
                    + "下一步：把这半块画回 `recordingBlock`。")
        }

        // 图标只用 SF Symbols，不用 emoji（DESIGN-SYSTEM 第 4 节）。
        SourceGuard.assertRenders(
            "record.circle", inBodyOf: "private var recordingBlock", of: Self.sheet,
            because: "录音指示没有那个 SF Symbol。下一步：用 `Image(systemName: \"record.circle\")`，"
                + "**不要用 emoji**——emoji 在不同系统版本渲染不一致，也跟不了语义颜色。")
    }

    // MARK: - 「这一场只盯什么」（2026-08-20：整条管道早就在跑，缺的只是一个能打字的地方）

    /// `SessionSetup.goal` 会进考官提示词的「本次唯一目标」、进训练记录、进复盘请求。
    /// 在这之前**整个 App 一个文本输入框都没有**，所以除了复训和「继续上次」，
    /// 每一场的目标都是空的——他绝大多数练习都是没有焦点的泛泛一场。
    func testThePracticeSheetHasAPlaceToTypeThisSessionsGoal() throws {
        let code = try SourceGuard.code(Self.sheet)
        let field = try SourceGuard.memberBody(of: "private var goalField", in: code)
        XCTAssertTrue(field.contains("TextField"), "没有真的输入框：\n\(field)")
        XCTAssertTrue(field.contains("text: $goal"), "输入框没绑到 `goal` 上：\n\(field)")
        // 占位符要给一句真能照着写的话。写「请输入目标」的话，一个不知道该写什么的人
        // 会直接跳过它，这个框就白加了。
        XCTAssertTrue(field.contains("例如："), "占位符没给例子：\n\(field)")
    }

    /// **两条「自己挑材料」的路线上都得有这个框。** 只挂一条的话，
    /// 另一条上的用户永远没机会定这一场的焦点，而两条路看起来一模一样。
    func testBothPickerRoutesShowTheGoalField() throws {
        let code = try SourceGuard.code(Self.sheet)
        for member in ["private var picker", "private var randomDrawPicker"] {
            let body = try SourceGuard.memberBody(of: member, in: code)
            XCTAssertTrue(body.contains("goalField"),
                          "\(member) 里没有那个目标输入框。实际取到的是：\n\(body)")
        }
    }

    /// 随机抽题那条路同样要把目标带进这一场——只接一条的话，
    /// 输入框在另一条路上打得进字、却什么都不改（本项目最忌讳的静默失败）。
    func testTheDrawnSessionCarriesTheGoalToo() throws {
        let drawn = try SourceGuard.memberBody(of: "private var drawnSetup",
                                               in: try SourceGuard.code(Self.sheet))
        XCTAssertTrue(drawn.contains("makeDrawSetup(drawn, trimmedGoal)"),
                      "随机抽题那一场没有带上目标。实际取到的是：\n\(drawn)")
    }

    /// 只打了几个空格时要当成「没填」。
    ///
    /// 不去空白的话：`ExaminerPrompt` 那边判的是 trim 之后空不空，会正确地跳过整段；
    /// 而训练记录里却存着一句看不见的空白，复盘报告页那行「本次目标：」
    /// 就会显示成一片空白——同一件事，两处两个答案。
    func testAGoalOfOnlySpacesCountsAsNoGoal() throws {
        let trimmed = try SourceGuard.memberBody(of: "private var trimmedGoal",
                                                 in: try SourceGuard.code(Self.sheet))
        XCTAssertTrue(trimmed.contains("trimmingCharacters"), trimmed)
    }

    /// 录音指示**必须是静止的**。
    ///
    /// DESIGN-SYSTEM 第 5 节禁止循环装饰动画，Task 11 Step 3 的人工验收也要看这一条。
    /// 一个一直在呼吸闪烁的红点是这个界面上最容易让人分心的东西，
    /// 而用户这时候正要开口说英语。
    func testTheRecordingIndicatorDoesNotBlink() throws {
        let block = try SourceGuard.memberBody(of: "private var recordingBlock",
                                               in: try SourceGuard.code(Self.sheet))
        for banned in ["repeatForever", "withAnimation", "opacity(isBlinking", "symbolEffect"] {
            XCTAssertFalse(block.contains(banned),
                           "录音指示里出现了「\(banned)」，多半是加了呼吸闪烁那类循环动画。"
                               + "下一步：去掉它，静态就好——用户这时候正要开口说英语，"
                               + "界面上不该有东西一直在动（DESIGN-SYSTEM 第 5 节）。")
        }
    }

    // MARK: - 一个入口，两种做法

    /// 弹层里得有那个「自己挑 / 随机抽」的开关，而且**进来停在哪一档跟着路线走**。
    ///
    /// 今日训练页把这两条合成了一张卡片，差别就落在这一个开关上。
    /// 没有它的话，把默认路线设成「随机抽题」的人再也找不到自己挑题的入口，
    /// 反过来也一样——两条路线里有一条会彻底消失。
    func testTheSheetOffersBothWaysToPickAndOpensOnTheOneTheRouteAsked() throws {
        let code = try SourceGuard.code(Self.sheet)

        // **两支都要有。** 只在其中一支放开关的话，用户切到另一支就再也切不回来——
        // 而今日训练页已经把两条路线合成一张卡片了，切不回来 = 那种做法彻底消失。
        // 实测过：只留一支，`assertRenders` 那种「出现过就算」的写法照样全绿。
        let picker = try SourceGuard.memberBody(of: "private var picker", in: code)
        XCTAssertEqual(
            SourceGuard.occurrences(of: "modeSwitch", in: picker), 2,
            "「自己挑 / 随机抽」那个开关不是两支都有。少了哪一支，"
                + "用户切到那一支之后就再也切不回来了。实际取到的是：\n\(picker)")

        XCTAssertTrue(
            code.contains("PickMode(route: route)"),
            "进来停在哪一档没有跟着路线走。用户在学习计划页把默认路线设成「随机抽题」，"
                + "进来却停在「自己挑」，每次都得先点一下开关。")

        for mode in ["自己挑", "随机抽"] {
            XCTAssertTrue(code.contains(mode), "开关上少了「\(mode)」这一档")
        }
    }

    // MARK: - 抽题动画

    /// **结果在按下按钮那一刻就定了，动画只是把它揭开。**
    ///
    /// 让动画去决定抽到什么的话，中途关掉窗口、或者动画被系统打断，
    /// 这一场抽到的就成了一件谁也说不清的事。
    func testTheDrawIsDecidedBeforeTheAnimationNotByIt() throws {
        let roll = try SourceGuard.functionBody(named: "roll", in: try SourceGuard.code(Self.sheet))
        let decidedAt = roll.range(of: "RandomDraw.draw(")
        let animatedAt = roll.range(of: "isRolling = true")
        XCTAssertNotNil(decidedAt, "`roll()` 里不再调 `RandomDraw.draw`——那这一组是谁抽的？")
        if let decidedAt, let animatedAt {
            XCTAssertTrue(
                decidedAt.lowerBound < animatedAt.lowerBound,
                "抽签排在动画后面了。动画一旦被打断，这一场抽到什么就说不清了。"
                    + "下一步：先 `RandomDraw.draw(...)` 定下结果，再开始滚。")
        }
        XCTAssertTrue(
            roll.contains("guard !reduceMotion"),
            "开了「减弱动态效果」还是要滚一秒（规范第 5 节，硬性要求）。"
                + "实际取到的是：\n\(roll)")
    }

    /// 动画要演的是「**在抽什么**」，不是「在忙」。
    ///
    /// 从前是一行随机文字加一个转圈，演完 0.56 秒之后结果一帧硬切上来——
    /// 前面的铺垫在最后那一帧全被抵消，看起来像动画卡住然后跳完。
    /// 现在每个要抽的 Part 各占一行、各自滚动、依次定格。
    func testEachPartGetsItsOwnReelAndSettlesInTurn() throws {
        let code = try SourceGuard.code(Self.sheet)
        let outcome = try SourceGuard.memberBody(of: "private var drawOutcome", in: code)

        XCTAssertTrue(
            outcome.contains("ForEach(reelParts"),
            "抽的过程不再是逐个 Part 一行。只给一行随机文字的话，"
                + "用户看完只知道「它刚才忙了一下」，不知道抽到了哪几段。"
                + "实际取到的是：\n\(outcome)")

        XCTAssertTrue(
            outcome.contains("coachAnimation(Motion.standard, value: isRolling)"),
            "揭晓那一下是硬切。前面演了一秒，最后一帧「啪」地换上一张最高 220pt 的列表，"
                + "弹层高度当场跳一大截。实际取到的是：\n\(outcome)")

        let roll = try SourceGuard.functionBody(named: "roll", in: code)
        XCTAssertTrue(
            roll.contains("settledParts.insert"),
            "没有「依次定格」这件事了——那是这段动画要演的全部内容。"
                + "实际取到的是：\n\(roll)")

        // 池子空的 Part 不该进来滚：那一行会一直滚空字符串，看着像卡住。
        let parts = try SourceGuard.memberBody(of: "private var reelParts", in: code)
        XCTAssertTrue(
            parts.contains("candidates.contains"),
            "题库里那个 Part 一道题都没有时，它仍然会被摆进来滚一个空字符串，看着像卡住了。"
                + "实际取到的是：\n\(parts)")
    }
}
