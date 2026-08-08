import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 「最近一次错误」的**接线**：真出错的那四个地方，到底有没有往 `LastErrorLog.shared` 里记一笔。
///
/// ## 为什么这组测试非有不可
///
/// `LastErrorLogTests` 守的是这个类型自己的行为（记什么、不记什么），
/// `DiagnosticsReportTests` / `FeedbackViewTests` 守的是「记下来的东西怎么写进那段文字」。
/// 两者都跳过了中间那一段：**这条日志到底有没有被接到会出错的地方去。**
///
/// 2026-08-08 复审实测：把 `PracticeRunner.fail`、`AppState.reload`、`AppState.mutate`、
/// `PendingReviewViewModel.reimport` 里那四行 `LastErrorLog.shared.record(...)` 分别删掉，
/// 完整 `swift test` 四次全部 0 失败。也就是说整页唯一的信息源可以被静默摘掉，
/// 而「问题反馈」页会理直气壮地写「最近没有出错」——**刚出完错却告诉用户没出错，
/// 是一句假话，比一片空白更糟**：用户会照着「不是程序的问题」这个假结论去找别的原因。
///
/// 同理，`PracticeStage.diagnosticsStage` 那个十分支映射此前 `grep -rn diagnosticsStage Tests/`
/// 零命中——把「写训练数据」映射成「操作 ChatGPT」也没人会发现，而收到诊断信息的人
/// 会照着那个阶段去查一个根本没碰过的方向。
///
/// ## 为什么断言落在 `LastErrorLog.shared` 上，而不是注入一个假的
///
/// 「问题反馈」页默认读的就是 `.shared`（`FeedbackPageModel.init` 的 `log: LastErrorLog = .shared`）。
/// 注入一个替身只能证明「这段代码会往我给它的那个对象里记」，证明不了
/// 「它记的是那一页真正会去读的那一份」——而两者走岔正是这类接线最常见的坏法。
///
/// 单例是跨测试共享的，所以每条测试前后都清一次。全部测试都在 `@MainActor` 上，
/// 不存在并发写。
@MainActor
final class LastErrorLogWiringTests: XCTestCase {

    private var directory: DataDirectory!

    /// **写成 `async` 的那一对，不是 `setUpWithError`。** `LastErrorLog.shared` 是
    /// `@MainActor` 的，而 `setUpWithError` 是 nonisolated；在那里碰它 Swift 6 会警告
    /// 「main actor-isolated class property 'shared' can not be referenced from a
    /// nonisolated context」。`async` 的那一对继承本类的 `@MainActor`，没有这个问题。
    override func setUp() async throws {
        LastErrorLog.shared.clear()
        directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-lasterror-\(UUID().uuidString)"))
        try directory.createIfNeeded()
    }

    override func tearDown() async throws {
        LastErrorLog.shared.clear()
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 一、练习失败：记的是「断在哪一步」，而且不是一个写死的常量

    /// 开练阶段断掉时，「最近一次错误」要记下当时正在操作 ChatGPT。
    func testAPracticeThatBreaksWhileDrivingChatGPTIsRecorded() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                                    directory: directory,
                                    now: { Date(timeIntervalSince1970: 1_700_000_000) })

        try? await runner.start(setup: Self.setup)

        let last = LastErrorLog.shared.last
        XCTAssertNotNil(last,
                        "一场练习刚在「启动语音」上失败，「最近一次错误」却是空的。"
                            + "问题反馈页这时会写「最近没有出错」——刚出完错却说没出错，是一句假话。")
        XCTAssertEqual(last?.stage, .drivingChatGPT,
                       "记错了阶段：收到诊断信息的人会照着它去查一个没碰过的方向。")
    }

    /// **收尾阶段断掉时记的必须是另一个阶段。** 上面那条自己没有牙齿：
    /// 把 `failedAt.diagnosticsStage` 换成写死的 `.drivingChatGPT` 它照样绿，
    /// 而那样一来「断在哪一步」这条线索就等于没了。
    func testAPracticeThatBreaksWhileFetchingTheReviewIsRecordedAtADifferentStage() async throws {
        let bridge = FakeBridge()
        bridge.failAt = .requestingReview
        let runner = PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                                    directory: directory,
                                    now: { Date(timeIntervalSince1970: 1_700_000_000) })

        try await runner.start(setup: Self.setup)
        LastErrorLog.shared.clear()
        try? await runner.finishPractice()

        let last = try XCTUnwrap(LastErrorLog.shared.last,
                                 "收尾失败了却一笔都没记（铁律 7：不许静默失败）")
        XCTAssertEqual(last.stage, .fetchingReview,
                       "断在「请复盘」上却记成了 \(last.stage)。"
                           + "两个阶段记成同一个的话，这条线索等于没有。")
    }

    /// 记的是阶段与代号，**错误原文一个字都不进来**——这条接线也得守着这一点，
    /// 不然「只记代号」这条产品承诺在类型内部成立、在调用点被绕过。
    func testAFailedPracticeRecordsACodeAndNotTheBridgeMessage() async throws {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                                    directory: directory,
                                    now: { Date(timeIntervalSince1970: 1_700_000_000) })

        try? await runner.start(setup: Self.setup)

        let last = try XCTUnwrap(LastErrorLog.shared.last)
        XCTAssertFalse(last.summary.contains("假装失败"),
                       "把桥那边的错误原文带进来了：\(last.summary)")
        XCTAssertFalse(last.code.isEmpty, "代号是空的，等于什么都没记")
    }

    // MARK: - 二、读写训练数据失败

    /// `state.json` 读不出来时要记一笔。这是「问题反馈」页最该派上用场的一种故障。
    func testAnUnreadableStateFileIsRecordedAsAReadFailure() throws {
        try Data("{ 这不是 JSON".utf8).write(to: directory.stateFile)

        let app = AppState(directory: directory,
                           preflight: { BridgeReadiness(ok: true, messages: ["✅ 假的"]) })

        XCTAssertNotNil(app.loadError, "这条测试的前提是「这次真的读失败了」")
        let last = try XCTUnwrap(LastErrorLog.shared.last,
                                 "训练数据读不出来却一笔都没记，问题反馈页会说「最近没有出错」")
        XCTAssertEqual(last.stage, .readingState,
                       "读盘失败被记成了 \(last.stage)")
    }

    /// 写盘失败时要记一笔，而且记的阶段**要和读盘失败区分开**。
    /// 两者都记成 `.readingState` 的话，收到诊断信息的人会去查一个只读的方向。
    func testAFailedWriteIsRecordedAsAWriteFailureNotAReadOne() throws {
        let app = AppState(directory: directory,
                           preflight: { BridgeReadiness(ok: true, messages: ["✅ 假的"]) })
        LastErrorLog.shared.clear()

        let failure = app.mutate { _ in throw CoachError.planImpossible("写不进去") }

        XCTAssertNotNil(failure, "这条测试的前提是「这次写盘真的失败了」")
        let last = try XCTUnwrap(LastErrorLog.shared.last,
                                 "写盘失败却一笔都没记（铁律 7）")
        XCTAssertEqual(last.stage, .writingState,
                       "写盘失败被记成了 \(last.stage)")
        XCTAssertEqual(last.code, "plan-impossible")
        XCTAssertFalse(last.summary.contains("写不进去"),
                       "把错误原文带进来了：\(last.summary)")
    }

    // MARK: - 三、复盘解析失败

    /// 「重新导入待处理的复盘」解析不了时要记一笔。
    ///
    /// **这一处尤其不能记原文**：解析失败的消息里常常夹着复盘正文的片段，
    /// 而那里全是用户说过的英语。
    func testAReviewThatCannotBeParsedIsRecordedWithoutOneWordOfItsText() throws {
        let secret = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
        let store = StateStore(directory: directory)
        _ = try PendingReviewStore.write(rawText: "这不是一份复盘，里面还有 \(secret)",
                                         sessionID: "s1", directory: directory)
        let model = PendingReviewViewModel(directory: directory, store: store,
                                           timeZone: TimeZone(identifier: "UTC")!,
                                           now: { Date(timeIntervalSince1970: 1_700_000_000) })
        model.refresh()
        LastErrorLog.shared.clear()

        model.reimport(try XCTUnwrap(model.rows.first))

        XCTAssertNotNil(model.notice, "这条测试的前提是「这次真的解析失败了」")
        let last = try XCTUnwrap(LastErrorLog.shared.last,
                                 "复盘解析失败却一笔都没记，问题反馈页会说「最近没有出错」")
        XCTAssertEqual(last.stage, .parsingReview, "解析失败被记成了 \(last.stage)")
        XCTAssertFalse(last.summary.contains(secret),
                       "把复盘原文带进「最近一次错误」了——那段文字是要发给别人看的：\(last.summary)")
    }

    // MARK: - 四、阶段映射：每一步都得映到它本来在做的那件事

    /// `PracticeStage` → `DiagnosticsStage` 的完整对照表。
    ///
    /// **逐支写死，不是「非空即可」**：这个映射唯一的用途就是告诉别人「当时在做什么」，
    /// 把「写训练数据」映射成「操作 ChatGPT」比不写还糟——它会把排障的人引到
    /// 一个根本没碰过的方向去。此前 `grep -rn diagnosticsStage Tests/` 零命中。
    func testEveryPracticeStageMapsToWhatWasActuallyHappening() {
        let expected: [(PracticeStage, DiagnosticsStage)] = [
            (.idle, .startingPractice),
            (.newChat, .drivingChatGPT),
            (.startingVoice, .drivingChatGPT),
            (.waitingComposer, .drivingChatGPT),
            (.sendingPrompt, .drivingChatGPT),
            (.practicing, .drivingChatGPT),
            (.endingVoice, .drivingChatGPT),
            (.requestingReview, .fetchingReview),
            (.capturingReview, .fetchingReview),
            (.needsManualCopy("手动复制说明"), .fetchingReview),
            (.archiving, .archivingReview),
            (.done, .archivingReview),
            (.failed("出事了。下一步：重试。"), .archivingReview)
        ]
        for (stage, want) in expected {
            XCTAssertEqual(stage.diagnosticsStage, want,
                           "\(stage) 被映射成了「\(stage.diagnosticsStage.title)」，"
                               + "而它当时在做的是「\(want.title)」")
        }
        XCTAssertEqual(expected.map(\.0).count, PracticeRunnerTests.allStages.count,
                       "`PracticeStage` 加了新的一步，这张对照表却没跟上。"
                           + "下一步：把新那一步补进 `expected`，别让它悄悄落进某个不相干的阶段。")
    }

    /// 上面那条的牙齿之一：这个映射**不是把所有步骤都倒进同一个桶**。
    /// 全部返回 `.drivingChatGPT` 的话，上面那条会红，但只红在措辞上；
    /// 这一条把「它到底有没有在区分」单独问一遍。
    func testTheStageMappingActuallyTellsThePhasesApart() {
        let mapped = Set(PracticeRunnerTests.allStages.map(\.diagnosticsStage))
        XCTAssertGreaterThanOrEqual(mapped.count, 3,
                                    "一整场练习的所有步骤只映出 \(mapped.count) 个阶段——"
                                        + "「当时在做什么」这条线索基本等于没有：\(mapped)")
    }

    // MARK: - 装置

    private static let setup = SessionSetup(
        question: Question(id: "q1", part: 1, topic: "Home",
                           prompt: "Do you live in a house or a flat?"),
        focusPart: .part1, durationMinutes: 5, goal: "")
}
