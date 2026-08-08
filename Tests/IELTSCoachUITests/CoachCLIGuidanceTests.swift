import Foundation
import XCTest

/// **命令行给出的「下一步」，必须是它真的兑现得了的那一件事。**
///
/// 这组测试守两件已经真实发生过的事：
///
/// 1. `PracticeCommand` 里「复盘写不进 reports/」那条分支，一边说「这一场还没有记进
///    训练记录」，一边把下一步写成「运行 coach reimport 把这份原文重新入库」。
///    可 `coach reimport` 只调 `ReviewArchiver.archive` 归错题与词汇，
///    它既不写 `reports/<id>.json`、也不往 `state.sessions` 里加任何东西——
///    用户照着做完，「训练记录」和「复盘报告」两页里这一场依然永远不存在，
///    而消息里一个字都没提。`PendingReviewViewModel.successNotice` 的文档注释
///    早就把这条规矩写死了：**「下一步」不许承诺一件兑现不了的事。**
/// 2. `ReimportCommand` 里那段解释文件名来历的注释，说文件名与 `PracticeCommand` 的
///    `requestID` 同源。Phase 4 把那行代码删掉了（现在文件名由
///    `PendingReviewStore.write` 产生），注释却留着，指向的代码已经不存在。
///
/// ## 为什么是扫源码
///
/// `coach` 是可执行 target，没有测试 target（计划 Task 12 也写明「PracticeCommand 本身
/// 没有单元测试」），而这段文案还夹在一条必须驱动真实 ChatGPT 的流程中间（铁律 5 禁止
/// 在测试里跑它）。所以只能退一步扫源码——用的是本项目共用的 `SourceGuard`
/// （读不到文件会抛错，不会拿空串把断言变成永远绿）。`AppSceneTests` 已经用同样的方式
/// 守着 `Sources/IELTSCoachApp`，这里沿用它。
///
/// 边界：扫源码不执行代码。它证明不了这几句 `print` 在真机上真的被打出来——那归
/// 计划 Task 13 的人工验收。它守得住的是「这句话还是不是假话」。
final class CoachCLIGuidanceTests: XCTestCase {
    static let practicePath = "Sources/coach/PracticeCommand.swift"
    static let reimportPath = "Sources/coach/ReimportCommand.swift"

    // MARK: - 前提：coach reimport 到底补得回什么

    /// 上面那条文案的全部前提，就是这条测试里的三句断言。
    ///
    /// 把它写成测试而不是写在注释里，是为了让「将来 reimport 真的开始补训练记录了」
    /// 这件事当场变红，逼人回头把 `PracticeCommand` 那句限定一起改掉——
    /// 否则文案会从「太保守」慢慢变成又一句假话，方向反过来而已。
    func testReimportRestoresNeitherTheReportFileNorTheSessionRecord() throws {
        let code = try SourceGuard.repositoryCode(Self.reimportPath)

        XCTAssertTrue(
            code.contains("ReviewArchiver.archive"),
            "扫到的不是 coach reimport 的实现，这条测试等于空转。"
                + "下一步：确认 \(Self.reimportPath) 还在、归档还是走 ReviewArchiver.archive。")

        XCTAssertFalse(
            code.contains("reportsDirectory"),
            "coach reimport 开始写 reports/ 了。那 PracticeCommand 里「报告写不进去」"
                + "那条分支的限定（现在写的是「reimport 只补错题和词汇」）就成了新的假话，"
                + "只是方向反过来——它会劝用户重新练一场，其实 reimport 已经补得回来了。"
                + "下一步：把那句限定连同这条断言一起改掉。")

        XCTAssertFalse(
            code.contains("sessions"),
            "coach reimport 开始往 state.sessions 里写了。同上：PracticeCommand 那句"
                + "「训练记录补不回来，只能重新练一次」立刻过期。"
                + "下一步：把那句限定连同这条断言一起改掉。")
    }

    // MARK: - 报告写盘失败那条分支

    func testReportWriteFailureDoesNotPromiseReimportCanRestoreTheSessionRecord() throws {
        let branch = try reportWriteFailureBranch()

        // 先确认切到的确实是那一段，不然下面几条全是空转。
        XCTAssertTrue(branch.contains("没能写成报告文件"),
                      "切出来的不是「报告写不进去」那条分支：\(branch)")
        XCTAssertTrue(branch.contains("下一步"),
                      "错误信息里没有「下一步」（铁律 6）：\(branch)")

        let statesTheLimit = branch.contains("补不回") || branch.contains("补不了")
            || branch.contains("恢复不了")
        let offersTheRealWayOut = branch.contains("重新练")

        XCTAssertFalse(
            branch.contains("reimport") && !(statesTheLimit && offersTheRealWayOut),
            "这条分支让用户去跑 coach reimport，却没说清 reimport 补不回什么。"
                + "reimport 只归错题与词汇（见 testReimportRestoresNeitherTheReportFileNorTheSessionRecord），"
                + "它不写 reports/<id>.json，也不往 state.sessions 里加东西——"
                + "用户照着做完，「训练记录」和「复盘报告」两页里这一场依然不存在，"
                + "而这段话里一个字都没提。下一步：要么在这句下一步里如实写明"
                + "「reimport 只补错题和词汇，这一场的训练记录补不回来，要重新练一次」，"
                + "要么把 store.mutate 挪到写报告之前、让会话记录先落住（那样也要重写这段话）。"
                + "实际内容：\(branch)")
    }

    // MARK: - 命令行导题库要和 App 排出同一份计划

    /// 复审第 9 条的接线守卫的另一半。
    ///
    /// 两边行为不一致的话，用命令行导题库的人回到 App 会发现首页没有「按计划练今天」——
    /// 而引导（`OnboardingStep.ready`）刚刚亲口说过已经排好了。
    /// 那条路走得通不是理论：`OnboardingFlow.steps` 在题库非空时**会跳过导入那一步**，
    /// 于是他看到的正是那句承诺，却没有计划。
    func testTheCommandLineImportLaysOutTheSamePlanTheAppDoes() throws {
        let code = try SourceGuard.repositoryCode("Sources/coach/QuestionsCommand.swift")
        XCTAssertTrue(
            code.contains("PlanBootstrap.planForFirstImport"),
            "命令行导题库没有走 PlanBootstrap，App 导会排计划、命令行导不会。"
                + "下一步：两条导入路径都调同一条规则（这条规则本身在 PlanBootstrapTests 里测）。")
        XCTAssertTrue(
            code.contains("PlanBootstrap.notice"),
            "命令行排了计划却一个字都不说。凭空多出一份计划，用户会以为是上一次用留下的。")
    }

    // MARK: - 手动兜底那一步接在谁身上

    /// 命令行练完一场可能整场复盘一个字都不留（复审第 13 条）的**接线守卫**。
    ///
    /// 真正的行为测试在 `ChatGPTBridgeTests.ManualReviewCaptureTests` / `ConsoleEnterWaiterTests`
    /// ——那边跑的是生产实现本身。这里守的是另一半：`PracticeCommand` 有没有真的接上它。
    /// 少了这一条，谁把这一行改回「打一句提示 + `enter.waitForPress()` + 读一次剪贴板」，
    /// 那两组测试照样全绿，而缺陷原样回来。
    func testTheManualFallbackGoesThroughTheTestedCapture() throws {
        let code = try SourceGuard.repositoryCode(Self.practicePath)

        XCTAssertTrue(
            code.contains("ManualReviewCapture.read"),
            "手动兜底那一步没有走 ManualReviewCapture。它是整条命令行流程里最后一道"
                + "能救回这一场的闸门（走不过去就是「复盘原文一个字不落盘」），"
                + "而 \(Self.practicePath) 所在的 coach 是可执行 target、没有测试 target，"
                + "自己写一份等于没有测试。下一步：把这一步交回 ManualReviewCapture.read。")

        XCTAssertFalse(
            code.contains("enter.waitForPress()") && code.contains("ClipboardFallback.readReview"),
            "这里又出现了「自己等一次回车 + 自己读一次剪贴板」的写法。"
                + "用 waitForPress 会把用户结束通话时顺手按的那一下回车当成对"
                + "「请按 ⌘C 然后回车」的回答，0 秒穿过去，这一场当场作废（复审第 13 条）。"
                + "下一步：交给 ManualReviewCapture.read，它内部用的是 waitForFreshPress。")
    }

    // MARK: - reimport 里那段解释文件名来历的注释

    func testReimportCommentPointsAtWhoActuallyNamesThePendingFiles() throws {
        // 事实先从 PracticeCommand 上取，不写死在测试里。
        let practice = try SourceGuard.repositoryCode(Self.practicePath)
        XCTAssertTrue(
            practice.contains("PendingReviewStore.write"),
            "复盘原文的落盘不再走 PendingReviewStore.write 了，这条测试的前提失效。"
                + "下一步：确认 \(Self.practicePath) 里落盘那一步改成了什么，再改这条断言。")
        XCTAssertFalse(
            practice.contains(#"\(requestID).txt"#),
            "pending 文件名又回到由 requestID 拼出来了。下一步：确认这是有意的；"
                + "是的话，把 \(Self.reimportPath) 里解释文件名来历的注释一起改回去。")

        let reimport = try SourceGuard.repositoryRead(Self.reimportPath)
        XCTAssertTrue(
            reimport.contains("PendingReviewStore"),
            "\(Self.reimportPath) 里没有一处点出 pending 文件名是谁起的。"
                + "这条命令整个建立在「文件名就是会话编号」之上，来源写不清楚，"
                + "下一个人只能靠猜。下一步：在取 sessionID 那一行旁边写明文件名由"
                + " PendingReviewStore.write 产生。")
        XCTAssertFalse(
            reimport.contains("requestID"),
            "\(Self.reimportPath) 还在拿 requestID 解释文件名的来历，而 Phase 4 已经把"
                + "「文件名来自 requestID」这条行为删掉了（现在由 PendingReviewStore.write 命名）。"
                + "这条注释指向的代码已经不存在，断言的机制也不成立，留着只会误导。"
                + "下一步：把注释改成描述 PendingReviewStore.write 的实际命名；"
                + "将来真有正当理由再提 requestID，先确认那句话是不是事实，再改这条断言。")
    }

    // MARK: - 切出那条分支

    /// 切「把解析后的复盘写成 reports/<id>.json」那个 `do` 后面的 `catch` 块。
    ///
    /// **读的是去过注释的源码**：那条分支上方的注释里必然要写清「为什么不能用 try? 吞掉」，
    /// 而那段说明里就带着「训练记录」「reportPath」这些词——连注释一起扫的话，
    /// 上面的断言会被这段说明喂饱，变成永远绿。
    private func reportWriteFailureBranch() throws -> String {
        let code = try SourceGuard.repositoryCode(Self.practicePath)
        let anchor = "try encoder.encode(report).write(to: reportFile"
        let write = try XCTUnwrap(
            code.range(of: anchor),
            "在 \(Self.practicePath) 里找不到「\(anchor)」，切不出那条分支，整组断言等于空转。"
                + "下一步：写报告那一步改了写法的话，同步改这里的锚点。")
        let catchAt = try XCTUnwrap(
            code.range(of: "} catch {", range: write.upperBound..<code.endIndex),
            "写报告那一步后面没有 catch 块了。下一步：确认写盘失败现在由谁接住——"
                + "别是被 try? 吞掉了（铁律 7）。")
        return try XCTUnwrap(
            SourceGuard.balancedBody(after: catchAt.lowerBound, in: code),
            "找到了 catch 却没找到配对的大括号。下一步：确认那对 `{ … }` 是完整的。")
    }
}
