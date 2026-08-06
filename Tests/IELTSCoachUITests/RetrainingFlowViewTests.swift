import Foundation
import XCTest

@testable import IELTSCoachUI

/// 复训流程页的视图层守卫。**这一页的头号保证在这里，不在 `RetrainingStepTests` 里。**
///
/// ## 为什么必须有这一份
///
/// `RetrainingFlowView.swift` 的文件注释第一句写着「开口之后屏幕上不许再出现任何范答」，
/// DEFINITION-OF-DONE 第 2 节点着它的名，计划 Task 10 Step 4 的表格把它标成
/// 「屏幕上绝对不能有」。而复审实测：往第二步那一段里加上
///
/// ```swift
/// if let evidence, !evidence.modelAnswer.isEmpty {
///     textCard(title: "复盘给的高分版", text: evidence.modelAnswer)
/// }
/// ```
///
/// 再跑 `swift test`——**941 条 0 失败**。`run == .original` 那一趟 `evidence` 在第一步的
/// `onAppear` 里就读进来了，所以这个改动在真机上真的会把高分版画在开口前那一屏上：
/// 用户对着念一遍，练完他和这个工具都会以为那个毛病改掉了。
///
/// `RetrainingStepTests.testModelAnswerIsOnlyVisibleWhileReviewingEvidence`（它自己的注释写着
/// 「本任务最重要的一条」）守的是 `RetrainingStep.showsModelAnswer` 这个属性；
/// 属性答得再对，视图不问它也没用。所以这里两头都钉：
///
/// 1. **视图真的去问 `RetrainingStep`**——三段材料各自一句 `if`，条件全是那几个属性，
///    而且每段材料在整份源码里只有那一个调用点（多一个就是多一条没人把关的上屏通道）；
/// 2. **除了那三段之外，谁都不许碰证据字段**——从 `body` 出发能走到的视图成员里，
///    只有那三段（及它们独有的下游）允许出现 `modelAnswer` / `originalAnswer` /
///    `evidence.quotes` 这些名字。第二步、第三步、结果卡片都在这条规矩之内。
///
/// ## 边界（与 `HistoryViewTests` / `ReviewReportViewTests` 一致）
///
/// 扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住——
/// 那部分归 Task 11 的人工验收。它拦得住的是：整段渲染被删、材料被搬到不该出现的那一屏上、
/// 失败提示被摘掉、写好的组件没摆进页面。
final class RetrainingFlowViewTests: XCTestCase {

    private static let view = "Retraining/RetrainingFlowView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("struct RetrainingFlowView"),
                      "没扫到 RetrainingFlowView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 头号保证：开口之后，范答一个字都不许上屏

    /// 证据字段的名字。出现在「不该出现的那一屏」上，就是范答泄漏。报错时用来指名道姓。
    ///
    /// `evidence.learnerTurns` 也算：那是学员自己上一次说过的原话，
    /// 照着念和照着高分版念是同一件事。
    private static let answerLeaks = [
        "evidence.modelAnswer", "evidence.originalAnswer", "evidence.quotes",
        "evidence.changes", "evidence.learnerTurns", "evidence.missingNote"
    ]

    /// 只有这三段允许碰证据，而且它们各自被一句 `RetrainingStep` 的 `if` 把着门。
    private static let evidenceSections = ["evidenceBody", "modelAnswerCard", "transcriptBody"]

    /// **这一条是本次复审的判据。**
    ///
    /// 问法不是「第二步那一段里有没有 `modelAnswer`」（那样把它挪到 `actions` 或
    /// `explanationCard` 里就溜了），而是结构性的：从 `body` 出发顺着调用关系能走到的视图成员，
    /// **减去**那三段证据区（及它们独有的下游）之后，剩下的一个都不许读 `evidence`。
    ///
    /// 判据用「有没有读 `evidence` 这个属性」而不是「有没有出现某几个字段名」：
    /// 字段名是可以绕的（换个局部变量名就行），而这一页的材料只有 `evidence` 一个来源，
    /// 读都读不到就画不出来。
    func testNothingOutsideTheThreeGatedSectionsCanPaintAnAnswerOnScreen() throws {
        let members = try Self.viewMembers()
        let names = Set(members.map(\.name))
        for section in Self.evidenceSections {
            XCTAssertTrue(names.contains(section),
                          "视图里已经没有「\(section)」这一段了。证据与范答现在由谁画、"
                              + "谁把门，这条守卫就答不上来了。"
                              + "下一步：要么把这一段放回去，要么同步改这份清单并说清新的把关方式。")
        }

        var allowed: Set<String> = []
        for section in Self.evidenceSections {
            allowed.formUnion(Self.reachable(from: section, among: members))
        }

        var report: [String] = []
        for name in Self.reachable(from: "body", among: members).sorted()
        where !allowed.contains(name) {
            guard let body = members.first(where: { $0.name == name })?.body else { continue }
            // `SourceGuard.mentions` 认得词边界与点号：`evidenceBody`、`step.showsEvidence`
            // 都不算「读了 `evidence`」，`if let evidence` 算。
            guard SourceGuard.mentions("evidence", in: body) else { continue }
            let fields = Self.answerLeaks.filter { body.contains($0) }
            report.append("\(name) 里读了 `evidence`"
                          + (fields.isEmpty ? "" : "（\(fields.joined(separator: "、"))）"))
        }

        XCTAssertTrue(report.isEmpty,
                      "证据／范答从三段把过门的区域之外漏到屏幕上了：\n"
                          + report.map { "  • " + $0 }.joined(separator: "\n")
                          + "\n这一页的成败判据只有一条：开口之后屏幕上不许再出现任何范答"
                          + "（DEFINITION-OF-DONE 第 2 节）。对着高分版念一遍不叫复训——"
                          + "那样练完，用户和这个工具都会以为他改掉了那个毛病。"
                          + "\n下一步：把这段材料搬回 `evidenceBody` / `modelAnswerCard` / "
                          + "`transcriptBody` 里去，让它照样受 `RetrainingStep` 那三句 `if` 管。")

        // 这一趟真的扫到东西了吗。扫了个空的话上面那条恒真——最坏的一种空转。
        XCTAssertGreaterThanOrEqual(members.count, 12,
                                    "扫到的视图成员太少（\(members.count) 个），这条测试多半失效了")
    }

    /// 「给不给看」必须真的去问 `RetrainingStep`，而且每段材料只有一个上屏通道。
    ///
    /// 只问「视图里有没有出现 `step.showsModelAnswer`」是不够的：再写一句没有把门的
    /// `modelAnswerCard` 照样能把它画出来。所以这里连调用次数一起数——
    /// 声明一次、在 `content` 里那句 `if` 后面用一次，正好两次。
    func testWhatEachStepShowsIsDecidedByRetrainingStepAndNothingElse() throws {
        let code = try Self.viewCode()
        let content = try SourceGuard.memberBody(of: "private var content", in: code)

        for (gate, section, why) in [
            ("step.showsGoal", "goalLine",
             "「本次唯一目标」是一句行为指令，三步都得留着；撤掉它，复训和随便再练一遍就没区别了"),
            ("step.showsEvidence", "evidenceBody",
             "当时说的原话与完整原答只有第一步能看；第二步一按下去它们就得没了"),
            ("step.showsModelAnswer", "modelAnswerCard",
             "复盘给的高分版只有第一步能看——这是这一页最不能破的那一条"),
            ("step.showsEvidence", "transcriptBody",
             "逐字稿里学员自己说过的话同样是证据，同样只有第一步能看")
        ] {
            XCTAssertTrue(content.contains("if \(gate) { \(section) }"),
                          "`content` 里没有「if \(gate) { \(section) }」这一句。\(why)。"
                              + "写成「每一步各画各的」的话，谁往第二步那一段里塞一句范答都"
                              + "编得过、跑得通，而 `RetrainingStepTests` 守的那个属性会退化成"
                              + "一段没有使用者的死代码。下一步：把这句 `if` 放回 `content` 里"
                              + "（改了写法就同步改这条断言）。实际取到的 `content` 是：\n\(content)")
        }

        for section in Self.evidenceSections + ["goalLine"] {
            let count = SourceGuard.standaloneOccurrences(of: section, in: code)
            XCTAssertEqual(count, 2,
                           "「\(section)」在整份源码里出现了 \(count) 次，应该正好两次："
                               + "声明一次、在 `content` 里那句 `if` 后面用一次。"
                               + "多出来的那次就是一条没人把门的上屏通道——"
                               + "而它画的正是开口之后绝对不许出现的东西。")
        }
    }

    // MARK: - 第一步：材料要齐，缺了要说

    func testTheEvidenceStepShowsEverythingTheLearnerNeeds() throws {
        let code = try Self.viewCode()
        let evidence = try SourceGuard.memberBody(of: "private var evidenceBody", in: code)
        for (field, why) in [
            ("evidence.missingNote", "材料不齐时那句中文说明。少一块内容不要紧，少了还不说才要命"),
            ("evidence.quotes", "复盘点名的那几句原话——这是「为什么要练这个目标」的唯一依据"),
            ("evidence.originalAnswer", "当时的完整原答"),
            ("evidence.changes", "复盘说要改什么")
        ] {
            XCTAssertTrue(evidence.contains(field),
                          "第一步没有显示\(why)（`\(field)`）。实际取到的是：\n\(evidence)")
        }

        let model = try SourceGuard.memberBody(of: "private var modelAnswerCard", in: code)
        XCTAssertTrue(model.contains("evidence.modelAnswer"),
                      "「复盘给的高分版」那一段没有真的画出 `evidence.modelAnswer`。"
                          + "第一步的全部意义就是让学员看清高分版长什么样。实际取到的是：\n\(model)")

        let transcript = try SourceGuard.memberBody(of: "private var transcriptBody", in: code)
        XCTAssertTrue(transcript.contains("evidence.learnerTurns"),
                      "第一步没有显示逐字稿里学员说过的话。实际取到的是：\n\(transcript)")
        XCTAssertTrue(transcript.contains("下一步"),
                      "逐字稿为空的那句说明没写「下一步做什么」（铁律 6）。实际取到的是：\n\(transcript)")
    }

    /// 复盘读不到就传 nil，**不许编一份空的顶上**：`RetrainingEvidenceBuilder` 会给出
    /// 一句中文说明（Task 7 已经测过那句话），那才是用户需要的东西。
    ///
    /// 顺带钉住「只读一次」：放在 `body` 里就是每重绘一次读一遍磁盘。
    func testTheEvidenceIsReadOnceOnAppearAndNeverFakedWhenItIsMissing() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "loadEvidenceIfNeeded()", inBodyOf: "var body: some View", of: Self.view,
            because: "第一步的材料没人去读了，那一屏永远停在「正在读取那一场的复盘和逐字稿」。"
                + "下一步：把 `.onAppear { loadEvidenceIfNeeded() }` 放回 `body`。")

        let load = try SourceGuard.memberBody(of: "private func loadEvidenceIfNeeded", in: code)
        XCTAssertTrue(load.contains("RetrainingEvidenceBuilder.build("),
                      "材料不再由 `RetrainingEvidenceBuilder` 装配。Task 7 那一整组测试"
                          + "（缺哪一块、缺了说什么）会当场退化成在测一份没人用的实现。")
        XCTAssertTrue(load.contains("app.loadReviewJSON(for: $0)") || load.contains("loadReviewJSON("),
                      "复盘没有从磁盘读出来，第一步只剩下目标本身那几个字。")
        XCTAssertTrue(load.contains("guard evidence == nil"),
                      "没有「已经读过就不再读」这道闸，界面每重绘一次就读一遍磁盘文件。")

        XCTAssertEqual(SourceGuard.occurrences(of: "RetrainingEvidenceBuilder.build(", in: code), 1,
                       "`RetrainingEvidenceBuilder.build(` 在这份源码里不止一处。"
                           + "多出来的那处多半是在 `body` 里现读——那是一次磁盘 IO，"
                           + "放在 `body` 里等于每重绘一次读一遍文件。")
    }

    // MARK: - 顶部：走到第几步了，以及故意跳过的那一步

    func testTheStepBarShowsAllThreeStepsAndSaysWhichOneWasSkippedOnPurpose() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "ForEach(RetrainingStep.allCases)", inBodyOf: "private var stepBar", of: Self.view,
            because: "三步进度指示不再遍历 `RetrainingStep.allCases`（换成空数组一样编得过），"
                + "用户不知道自己走到第几步、后面还有什么。")
        SourceGuard.assertRenders(
            "stepBar", inBodyOf: "var body: some View", of: Self.view,
            because: "进度指示写好了却没摆进 `body`。下一步：把它放回去。")

        let chip = try SourceGuard.memberBody(of: "private func stepChip", in: code)
        XCTAssertTrue(chip.contains("candidate.stepNumber") && chip.contains("candidate.title"),
                      "进度指示里没有步骤号或步骤名。实际取到的是：\n\(chip)")
        XCTAssertTrue(chip.contains("run == .transfer && candidate == .evidence"),
                      "换题验证那一趟没有把第一步标成「已跳过」。少一格会让人以为自己漏了一步，"
                          + "而这一步是**故意**不给的——不给回看，才知道是不是真会了。")
        XCTAssertTrue(chip.contains("换题验证跳过这一步"),
                      "「已跳过」那一格没有说清为什么跳过。实际取到的是：\n\(chip)")
        XCTAssertTrue(chip.contains(".monospacedDigit()"),
                      "步骤号没用等宽数字，三格并排时数字宽度不齐会很显眼（规范第 1 节最后一行）。")
    }

    /// 每一步都要把 `step.explanation` 摆出来：它同时说清这一步在干什么、下一步做什么。
    func testEveryStepExplainsItselfAndKeepsTheSingleGoalOnScreen() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "step.explanation", inBodyOf: "private var explanationCard", of: Self.view,
            because: "这一步在干什么、下一步做什么那句话没了（铁律 6）。"
                + "自己在视图里另写一句的话，`RetrainingStepTests` 里守着那三句说明的测试就空转了。")
        SourceGuard.assertRenders(
            "explanationCard", inBodyOf: "private var content", of: Self.view,
            because: "说明写好了却没摆进正文，三步都没有任何解释。")

        let goal = try SourceGuard.memberBody(of: "private var goalLine", in: code)
        XCTAssertTrue(goal.contains("RetrainingSetupBuilder.goalText(for: item.target)"),
                      "「本次唯一目标」那一行不再取自 `RetrainingSetupBuilder.goalText`。"
                          + "各写一份的话，屏幕上写的和真正发给考官的提示词里那一段就可能不是同一句。"
                          + "实际取到的是：\n\(goal)")
        XCTAssertTrue(goal.contains("本次唯一目标"),
                      "那一行没有标题，用户不知道这段字是干什么的。")
    }

    // MARK: - 第二步：只剩题目和目标

    func testTheRehearsalStepShowsTheWholeQuestionOrLetsTheLearnerPickOne() throws {
        let code = try Self.viewCode()
        let rehearsal = try SourceGuard.memberBody(of: "private var rehearsalBody", in: code)
        XCTAssertTrue(rehearsal.contains("questionCard(question)"),
                      "第二步没有画出题目。屏幕上只剩一个目标，用户不知道要答哪道题。"
                          + "实际取到的是：\n\(rehearsal)")
        XCTAssertTrue(rehearsal.contains("questionPicker"),
                      "题还没定下来时（换题验证从复训中心直接进来就是这种）没有挑题的地方，"
                          + "这一趟走不下去。实际取到的是：\n\(rehearsal)")

        let card = try SourceGuard.memberBody(of: "private func questionCard", in: code)
        XCTAssertTrue(card.contains("question.prompt"), "题目卡片里没有题干。")
        XCTAssertTrue(card.contains("question.followups"),
                      "题目卡片里没有追问。Part 1 那几道题的追问才是真正要答的东西。")

        let picker = try SourceGuard.memberBody(of: "private var questionPicker", in: code)
        XCTAssertTrue(picker.contains("EmptyStateView("),
                      "一道题都挑不出来时没有空状态，用户看到的是一块无法解释的空白。")
        XCTAssertTrue(picker.contains("onGo(.questionBank)"),
                      "空状态那颗按钮点下去哪儿也不去，用户读完还得自己回侧边栏翻。")
        XCTAssertTrue(picker.contains("ForEach(pickable)"),
                      "候选题没有遍历 `pickable`，一条都列不出来。实际取到的是：\n\(picker)")
    }

    /// 同话题的候选**必须标出来**：同话题太接近原题，验证力度打折。
    /// 不给用会让题库小的用户当场卡死，所以留着，但要让他知道自己选的是什么。
    func testSameTopicCandidatesAreFlaggedInBothPlacesTheyAreOffered() throws {
        let code = try Self.viewCode()
        for member in ["private func candidateRow", "private func transferRow"] {
            let body = try SourceGuard.memberBody(of: member, in: code)
            XCTAssertTrue(body.contains("candidate.sameTopicAsOriginal"),
                          "\(member) 没有按 `sameTopicAsOriginal` 标出同话题的那几条。"
                              + "用户会以为自己做了一次有效的换题验证，其实换的是同一个话题。")
            XCTAssertTrue(body.contains("和原题同一个话题，验证力度打折"),
                          "\(member) 里那句提醒不见了。实际取到的是：\n\(body)")
            XCTAssertTrue(body.contains("Palette.warning"),
                          "\(member) 的提醒没用 `Palette.warning` 标出来，混在正文里没人会注意到。")
        }

        let pickable = try SourceGuard.memberBody(of: "private var pickable", in: code)
        XCTAssertTrue(pickable.contains("TransferQuestionPolicy.candidates("),
                      "候选题不再走 `TransferQuestionPolicy`（不跨 Part、排掉练过的、换话题的排前面）。"
                          + "视图里自己筛一份的话，那一整组测试都在测一份没人用的实现。"
                          + "实际取到的是：\n\(pickable)")
    }

    // MARK: - 第三步：进度要有，失败要响

    func testTheSpeakingStepAlwaysShowsWhatIsHappening() throws {
        let code = try Self.viewCode()
        let speaking = try SourceGuard.memberBody(of: "private var speakingBody", in: code)
        XCTAssertTrue(speaking.contains("stageCard(runner)"),
                      "第三步没有画进度。整条链路里最长的一步是启动语音，实测约 9 秒——"
                          + "那九秒界面是一块白板，用户会以为程序卡死了。实际取到的是：\n\(speaking)")
        for notice in ["runner.archiveNotice", "runner.transcriptNotice", "runner.recordingNotice"] {
            XCTAssertTrue(speaking.contains(notice),
                          "第三步不再显示 `\(notice)`。归档／逐字稿／录音出问题时一声不吭，"
                              + "用户会以为这一场完整地存下来了（铁律 7）。")
        }

        let stage = try SourceGuard.memberBody(of: "private func stageCard", in: code)
        XCTAssertTrue(stage.contains("runner.stage.userFacingText"),
                      "进度卡片里没有那句「现在在干什么」。空白等于「程序卡住了」。")
        XCTAssertTrue(stage.contains("runner.stage.isBusy") && stage.contains("ProgressView()"),
                      "自动跑的那几步没有转圈提示。规范第 5 节：超过 300ms 的操作都要有进度提示。")
        XCTAssertTrue(stage.contains("runner.isRecording"),
                      "正在录音这件事没有显示出来。用户不知道自己该不该开口。")
        XCTAssertTrue(stage.contains("runner.transcriptTurnCount"),
                      "「已记录几条对话」没了，用户没有任何办法确认逐字稿在正常记。")
    }

    /// **这条守的是本项目已知最危险的失败形态**（`RetrainingCoordinator` 自己的注释这么写的）：
    /// 这一场练完了、复盘也存了，却一个字都没挂进复训台账——进度纹丝不动，
    /// 而界面上看不出任何异样。所以第三步和结果卡片上都必须原样显示 `coordinator.failure`。
    ///
    /// 复审实测：把这两句一起删掉，941 条一条不红。
    func testAFailedLedgerHookupIsSaidOutLoudOnBothScreens() throws {
        let code = try Self.viewCode()
        for (member, when) in [
            ("private var speakingBody", "练习进行中"),
            ("private var resultBody", "练完之后那张结果卡片上")
        ] {
            let body = try SourceGuard.memberBody(of: member, in: code)
            XCTAssertTrue(body.contains("coordinator?.failure"),
                          "\(when)不再显示 `coordinator.failure`。挂不上复训台账时用户会看到"
                              + "「这一次没有再被点名」而进度纹丝不动，且没有任何线索——"
                              + "这是本项目已知最危险的失败形态（铁律 7）。"
                              + "实际取到的是：\n\(body)")
            XCTAssertTrue(body.contains("warningCard(failure)"),
                          "\(when)取到了 `failure` 却没有画出来。实际取到的是：\n\(body)")
        }

        let warning = try SourceGuard.memberBody(of: "private func warningCard", in: code)
        XCTAssertTrue(warning.contains(".textSelection(.enabled)"),
                      "那段说明里带着文件路径与目标编号，必须能选中复制。")
        XCTAssertTrue(warning.contains(".fixedSize(horizontal: false, vertical: true)"),
                      "那段说明会被截断成一行。**不许折叠、不许省略**——"
                          + "它是用户唯一能知道「哪一步没走通」的地方。")
    }

    // MARK: - 练完之后

    func testTheResultCardUsesTheSharedCopyAndOffersATransferRun() throws {
        let code = try Self.viewCode()
        let result = try SourceGuard.memberBody(of: "private var resultBody", in: code)
        for call in ["RetrainingOutcomeText.headline(for: outcome)",
                     "RetrainingOutcomeText.detail(for: outcome)"] {
            XCTAssertTrue(result.contains(call),
                          "结果卡片没有走 `\(call)`。视图里自己写一句判词的话，"
                              + "`RetrainingOutcomeTextTests` 就在测一份没人用的实现——"
                              + "而那几句话的分寸（「这一次没有再被点名」而不是「你改掉了」）"
                              + "正是这一整个阶段的立场。")
        }
        XCTAssertTrue(result.contains("transferSection"),
                      "结果卡片上没有换题验证那一段。**这是整个 Phase 6 的价值所在**："
                          + "同一道题第二次答得好，可能只是记住了上次那份高分版。")

        let transfer = try SourceGuard.memberBody(of: "private var transferSection", in: code)
        XCTAssertTrue(transfer.contains("pickable.prefix(5)"),
                      "换题验证那一段没有限制成前 5 条，题库大的时候会铺满整屏。"
                          + "实际取到的是：\n\(transfer)")
        XCTAssertTrue(transfer.contains("EmptyStateView("),
                      "一道题都换不出来时没有空状态，用户看到的是一块无法解释的空白。")
        XCTAssertTrue(transfer.contains("onGo(.questionBank)"),
                      "空状态那颗按钮点下去哪儿也不去。")

        let hint = try SourceGuard.memberBody(of: "private var emptyCandidatesHint", in: code)
        XCTAssertTrue(hint.contains("下一步") && hint.contains("训练题库"),
                      "换不出题时那句说明没写下一步（铁律 6）。实际取到的是：\n\(hint)")
    }

    /// 「这个问题我不用再练了」**只能由用户点，系统不许自动做**（计划的「决定 4」）：
    /// 一次没被点名不等于改掉了。所以整份源码里 `.retired` 只允许出现在那颗按钮的动作里。
    func testRetiringATargetIsOnlyEverDoneByTheUserAndSaysSoWhenItFails() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "Button(\"这个问题我不用再练了\")", inBodyOf: "private var actions", of: Self.view,
            because: "结果卡片上没有「这个问题我不用再练了」。用户没有任何办法把一个"
                + "已经改掉的目标撤下来，复训中心会一直越堆越长。")

        let retire = try SourceGuard.memberBody(of: "private func retire", in: code)
        XCTAssertTrue(retire.contains("app.setRetrainingStatus(.retired, of: item.target.id)"),
                      "那颗按钮点下去没有真的去改状态。按钮点了没反应是本项目最不能接受的那一类。"
                          + "实际取到的是：\n\(retire)")
        XCTAssertTrue(retire.contains("notice = failure"),
                      "改状态失败时一声不吭（铁律 7）。用户会看到窗口纹丝不动而没有任何解释，"
                          + "只会再点一次。实际取到的是：\n\(retire)")

        XCTAssertEqual(SourceGuard.occurrences(of: "setRetrainingStatus(.retired", in: code), 1,
                       "`.retired` 在这份源码里不止一处。多出来的那处多半是系统替用户"
                           + "自动做了这个判定——一次没被点名不等于改掉了（计划的「决定 4」）。")
    }

    // MARK: - 每个状态都得有一条出口

    /// 练习进行中那几个状态，**每一个都必须有一颗一定点得到的按钮**。
    ///
    /// 少一个的后果是：用户开一场复训就再也退不出来（`PracticeSheet` 上真发生过一次，
    /// 见 `RenderReachabilitySweepTests` 的说明）。这里按 `runner.stage` 逐条分支查，
    /// 而不是扫全文——扫全文的话，把某一条分支整块掏空，别处的按钮照样扫得到。
    func testEveryPracticeStageLeavesTheUserAWayOut() throws {
        let code = try Self.viewCode()
        let actions = try SourceGuard.memberBody(of: "private var speakingActions", in: code)
        let branches = try SourceGuard.switchBranches(over: "runner.stage", in: actions)
        XCTAssertGreaterThanOrEqual(branches.count, 4,
                                    "只切出了 \(branches.count) 条分支，这条测试多半失效了")

        for branch in branches {
            let exits = SourceGuard.unconditionalButtons(in: branch.body).filter(\.isWired)
            XCTAssertFalse(exits.isEmpty,
                           "`\(branch.label)` 这条分支里没有任何一颗一定点得到、"
                               + "而且真的接了动作的按钮。用户开一场复训就再也退不出来（铁律 7）。"
                               + "实际取到的是：\n\(branch.body)")
        }

        SourceGuard.assertRenders(
            "actions", inBodyOf: "var body: some View", of: Self.view,
            because: "整排按钮没摆进 `body`，这张 sheet 一颗按钮都没有。")
        SourceGuard.assertRenders(
            "noticeCard", inBodyOf: "var body: some View", of: Self.view,
            because: "上一次操作失败时那句中文说明没摆上屏（铁律 7）。")
    }

    // MARK: - 规范第 5 节：尊重「减弱动态效果」

    func testReduceMotionIsRespected() throws {
        let code = try Self.viewCode()
        XCTAssertTrue(code.contains("@Environment(\\.accessibilityReduceMotion)"),
                      "这一页没有读「减弱动态效果」，开着这个开关的用户照样会看到过渡动画"
                          + "（规范第 5 节）。")
        let advance = try SourceGuard.memberBody(of: "private func advance", in: code)
        XCTAssertTrue(advance.contains("if reduceMotion"),
                      "换步时没有按「减弱动态效果」分支。实际取到的是：\n\(advance)")
    }

    // MARK: - 扫源码用的小工具

    /// 这一页声明的全部视图成员（名字 → 大括号里的内容）。
    private static func viewMembers() throws -> [(name: String, body: String)] {
        let code = try viewCode()
        let type = try XCTUnwrap(
            SourceGuard.viewTypes(in: code).first { $0.name == "RetrainingFlowView" },
            "从 \(view) 里切不出 `RetrainingFlowView` 这个视图类型，"
                + "这一整条守卫等于空转。下一步：确认这个类型还在、还有 `var body: some View`。")
        return type.viewMembers
    }

    /// 从某个成员出发，顺着调用关系能走到的全部视图成员（含它自己）。
    ///
    /// 判断用的是 `SourceGuard.mentions`——和全模块那趟可达性扫描同一份实现
    /// （`runner.stage` 里的 `stage` 不算「调用了本类型的 stage」，`self.` 前缀算同一处引用）。
    /// 只是起点换成了指定的那一个：这里要问的不是「有没有人调它」，
    /// 而是「这一屏上顺着调用关系最终会画出哪些东西」。
    private static func reachable(from root: String,
                                  among members: [(name: String, body: String)]) -> Set<String> {
        let bodies = Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.body) })
        var reached: Set<String> = [root]
        var queue = [root]
        while let current = queue.popLast() {
            guard let body = bodies[current] else { continue }
            for candidate in members.map(\.name) where !reached.contains(candidate) {
                guard SourceGuard.mentions(candidate, in: body) else { continue }
                reached.insert(candidate)
                queue.append(candidate)
            }
        }
        return reached
    }
}
