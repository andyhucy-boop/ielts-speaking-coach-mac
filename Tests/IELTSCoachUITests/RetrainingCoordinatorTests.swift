import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

/// 可编程的假练习驱动。**不碰真的 ChatGPT**（铁律 5）。
///
/// `finishPractice()` 声明成 `throws`，与 `PracticeRunner` 的真实签名一致：
/// 收尾失败（复盘取不回、写盘失败）是这条路上真会发生的事，假不出来就没人守着
/// 「收尾出错时这一场还挂不挂进复训进度」。
@MainActor
final class FakeLauncher: PracticeSessionLauncher {
    var stage: PracticeStage = .idle
    var finishedSessionID: String?
    var startError: Error?
    var finishError: Error?
    private(set) var startedSetups: [SessionSetup] = []
    private(set) var finishCount = 0

    func start(setup: SessionSetup) async throws {
        startedSetups.append(setup)
        if let startError {
            stage = .failed(startError.localizedDescription)
            throw startError
        }
        stage = .practicing
    }

    func finishPractice() async throws {
        finishCount += 1
        if let finishError {
            stage = .failed(finishError.localizedDescription)
            throw finishError
        }
        stage = .done
    }
}

/// 测试里的 state 容器。协调器只在主线程上用它。
@MainActor
final class StateBox {
    var state: CoachState
    init(_ state: CoachState) { self.state = state }
}

private struct Boom: LocalizedError {
    var errorDescription: String? { "假装失败。下一步：这是测试用的。" }
}

/// 一个连「下一步」都不带的错误——系统 NSError 就是这个样子。
/// 协调器不能原样转述它，否则用户拿到的是一句孤零零的技术报错（铁律 6）。
private struct BareBoom: LocalizedError {
    var errorDescription: String? { "磁盘满了" }
}

@MainActor
final class RetrainingCoordinatorTests: XCTestCase {
    private func target() -> RetrainingTarget {
        RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                         evidence: [], sourceSessionId: "s0", createdAt: "t")
    }

    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "prompt-\(id)")
    }

    private func session(_ id: String, question: String) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func make(state: CoachState, launcher: FakeLauncher)
        -> (RetrainingCoordinator, StateBox) {
        let box = StateBox(state)
        let coordinator = RetrainingCoordinator(launcher: launcher,
                                                mutate: { body in body(&box.state) })
        return (coordinator, box)
    }

    /// 写盘失败的协调器：`mutate` 一律抛错。
    private func makeUnwritable(launcher: FakeLauncher) -> RetrainingCoordinator {
        RetrainingCoordinator(launcher: launcher, mutate: { _ in throw BareBoom() })
    }

    func testStartMarksTheTargetAsSelectedAndSendsTheGoalIntoTheSetup() async {
        var state = CoachState.empty()
        state.targets = [target()]
        let launcher = FakeLauncher()
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.start(target: target(), question: question("q1"),
                                originalQuestionID: "q1")

        XCTAssertEqual(box.state.targets[0].status, "selected")
        XCTAssertEqual(launcher.startedSetups.count, 1)
        XCTAssertEqual(launcher.startedSetups[0].goal, "补一个原因和例子")
        XCTAssertNil(coordinator.failure)
    }

    func testFinishAttachesTheLinkToTheFinishedSession() async {
        var state = CoachState.empty()
        state.targets = [target()]
        state.sessions = [session("s9", question: "q-other")]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertEqual(launcher.finishCount, 1)
        XCTAssertEqual(box.state.sessions[0].retraining,
                       RetrainingLink(targetKey: "logic-explain", sourceSessionId: "s0",
                                      originalQuestionId: "q1"))
        XCTAssertEqual(box.state.sessions[0].retrainingKind, .transfer,
                       "练的是另一道题，就该记成换题验证")
        XCTAssertEqual(coordinator.linkedSessionID, "s9")
        XCTAssertNil(coordinator.failure)
    }

    /// **本任务最重要的一条。** 挂不上台账却一声不吭，用户会看到「已记录」
    /// 而复训进度纹丝不动，没有任何线索可查。
    func testMissingSessionIDIsReportedNotSwallowed() async {
        var state = CoachState.empty()
        state.targets = [target()]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = nil
        let (coordinator, _) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        let failure = try? XCTUnwrap(coordinator.failure)
        XCTAssertTrue((failure ?? "").contains("下一步"),
                      "失败信息必须说清发生了什么和下一步做什么")
        XCTAssertNil(coordinator.linkedSessionID)
    }

    func testAttachFailureOnAForeignSessionIsReported() async {
        var state = CoachState.empty()
        state.targets = [target()]
        var taken = session("s9", question: "q-other")
        taken.retraining = RetrainingLink(targetKey: "另一个目标", sourceSessionId: "sX",
                                          originalQuestionId: "qX")
        state.sessions = [taken]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertNotNil(coordinator.failure)
        XCTAssertTrue((coordinator.failure ?? "").contains("下一步"),
                      "失败信息必须说清发生了什么和下一步做什么")
        XCTAssertNil(coordinator.linkedSessionID, "没挂上就不能报一个挂上了的记录编号")
        XCTAssertEqual(box.state.sessions[0].retraining?.targetKey, "另一个目标",
                       "别人的挂钩不许被覆盖")
    }

    func testStartFailureDoesNotPretendTheRetrainingHappened() async {
        var state = CoachState.empty()
        state.targets = [target()]
        state.sessions = [session("s9", question: "q1")]
        let launcher = FakeLauncher()
        launcher.startError = Boom()
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.start(target: target(), question: question("q1"),
                                originalQuestionID: "q1")

        XCTAssertNotNil(coordinator.failure)
        XCTAssertNil(box.state.sessions[0].retraining, "没练成就不能记一笔")
        XCTAssertNil(coordinator.linkedSessionID)
    }

    // MARK: - 收尾抛错与写盘失败（协议按 PracticeRunner 的真实签名带 throws，见实现里的说明）

    /// `PracticeRunner` 是**先把这一场写进训练记录、再去取复盘**的（`finishedSessionID`
    /// 在归档之前就赋了值）。所以收尾抛错时那条记录已经在了，台账照样得挂——
    /// 就此返回的话，用户练成的这一场永远不计入复训进度，而界面上看不出任何异常。
    func testWrapUpFailureStillLinksTheSessionAndIsReported() async {
        var state = CoachState.empty()
        state.targets = [target()]
        state.sessions = [session("s9", question: "q-other")]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        launcher.finishError = Boom()
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertEqual(coordinator.linkedSessionID, "s9",
                       "收尾出错不该让这一场落在复训进度之外")
        XCTAssertEqual(box.state.sessions[0].retraining?.targetKey, "logic-explain")
        XCTAssertTrue((coordinator.failure ?? "").contains("下一步"),
                      "收尾出错必须说出来，且要写清下一步")
    }

    /// 写盘失败必须说出来。`try?` 吞掉再画一个「已记录」，是本项目反复栽的那一类（铁律 7）。
    func testAFailedWriteWhileLinkingIsReported() async {
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        let coordinator = makeUnwritable(launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertNil(coordinator.linkedSessionID, "没写进去就不能说挂上了")
        let failure = coordinator.failure ?? ""
        XCTAssertTrue(failure.contains("磁盘满了"), "系统说的原因要转述出来，否则没法排查")
        XCTAssertTrue(failure.contains("下一步"), "失败信息必须说清下一步做什么")
    }

    /// 标记目标失败**不阻断练习**——练习本身比台账重要——但必须说出来。
    func testAFailedStatusWriteDoesNotBlockThePracticeButIsReported() async {
        let launcher = FakeLauncher()
        let coordinator = makeUnwritable(launcher: launcher)

        await coordinator.start(target: target(), question: question("q1"),
                                originalQuestionID: "q1")

        XCTAssertEqual(launcher.startedSetups.count, 1, "台账写不下也照样开练")
        let failure = coordinator.failure ?? ""
        XCTAssertTrue(failure.contains("磁盘满了"))
        XCTAssertTrue(failure.contains("下一步"), "失败信息必须说清下一步做什么")
    }
}
