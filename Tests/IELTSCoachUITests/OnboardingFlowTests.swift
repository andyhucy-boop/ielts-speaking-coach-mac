import Foundation
import XCTest

import IELTSCoachCore
@testable import IELTSCoachUI

final class OnboardingFlowTests: XCTestCase {

    private func steps(permission: PermissionState, questions: Int,
                       completed: Bool) -> [OnboardingStep] {
        OnboardingFlow.steps(permission: permission, questionCount: questions,
                             hasCompletedBefore: completed)
    }

    // MARK: - 全新安装

    func testFreshInstallWalksThroughEverything() {
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 0, completed: false),
                       [.welcome, .environment, .questionBank, .recordingChoice, .ready])
    }

    func testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere() {
        // 这正是「把数据目录拷过来的人」在新机器上第一次开 App 的样子：
        // 题库在，练习记录也在，再让他导一次题库是在浪费他时间、也让人怀疑数据没拷成功。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: false),
                       [.welcome, .environment, .recordingChoice, .ready])
    }

    func testFreshInstallStillExplainsThePermissionEvenWhenAlreadyGranted() {
        // 权限已经给了也要过一遍这一步：用户有权知道这个 App 拿辅助功能去干什么。
        XCTAssertTrue(steps(permission: .ready, questions: 5, completed: false)
                        .contains(.environment))
    }

    func testFirstStepIsAlwaysWelcomeAndLastIsAlwaysReady() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 100] {
                let result = steps(permission: permission, questions: count, completed: false)
                XCTAssertEqual(result.first, .welcome, "\(permission)/\(count) 的第一步不是欢迎")
                XCTAssertEqual(result.last, .ready, "\(permission)/\(count) 的最后一步不是完成")
            }
        }
    }

    // MARK: - 已经走过引导的人

    func testReturningUserWithEverythingReadySeesNothing() {
        XCTAssertTrue(steps(permission: .ready, questions: 217, completed: true).isEmpty)
        XCTAssertTrue(steps(permission: .ready, questions: 0, completed: true).isEmpty,
                      "题库空不该再弹引导——首页的空状态已经在引导他导入了")
    }

    func testReturningUserWithoutAccessibilitySeesOnlyTheEnvironmentStep() {
        // 换机器场景：数据拷过来了，题库和记录都在，但辅助功能授权是本机的，必须重给。
        // 少了这一步，用户会打开一个「看起来一切正常、点开始练习却报错」的 App。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithoutChatGPTSeesTheEnvironmentStep() {
        XCTAssertEqual(steps(permission: .needsChatGPT, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithAnUnrecognizedFailureSeesTheEnvironmentStep() {
        // 不能因为「没认出来」就当成就绪放过去——那会让用户点进去撞一堵没有线索的墙。
        XCTAssertEqual(steps(permission: .unknown, questions: 217, completed: true),
                       [.environment])
    }

    func testShouldPresentAgreesWithSteps() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 217] {
                for completed in [true, false] {
                    let hasSteps = !steps(permission: permission, questions: count,
                                          completed: completed).isEmpty
                    XCTAssertEqual(
                        OnboardingFlow.shouldPresent(permission: permission, questionCount: count,
                                                     hasCompletedBefore: completed),
                        hasSteps,
                        "\(permission)/\(count)/\(completed) 两者对不上")
                }
            }
        }
    }

    // MARK: - 每一步自己

    func testOnlyEnvironmentAndQuestionBankCanBeSkipped() {
        // welcome / ready 只是叙述，没有可跳过的东西；
        // recordingChoice 本身就是一个二选一（默认关也是一种选择），不该给「跳过」。
        XCTAssertEqual(Set(OnboardingStep.allCases.filter(\.canSkip)),
                       [.environment, .questionBank])
    }

    func testEveryStepHasChineseTitleBodyAndPrimaryAction() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) 没标题")
            XCTAssertFalse(step.body.isEmpty, "\(step) 没正文")
            XCTAssertFalse(step.primaryActionTitle.isEmpty, "\(step) 没有主按钮文案")
        }
    }

    /// 跳过是允许的（设计文档第 7 节），但必须让他知道跳过之后是什么样子——
    /// **而且说的得是真的**。
    ///
    /// 这一步从前写着「跳过之后运行在半自动模式：提示词要你自己粘贴，复盘要你自己按 ⌘C，
    /// 其余功能照常」。那个模式在这个 App 里根本不存在（2026-08-08 复审第 8 条实测）：
    /// 用户照着做完全部动作，仍然一场都练不成，而且不知道为什么。
    func testEnvironmentStepTellsUserWhatHappensIfTheySkip() {
        let body = OnboardingStep.environment.body
        XCTAssertTrue(body.contains("练不成") || body.contains("练不了"),
                      "没说清「跳过之后练不了」这件最要紧的事：\(body)")
        XCTAssertFalse(body.contains("其余功能照常"),
                       "「其余功能照常」是假话：练习本身就是主功能，而它照不了常。\(body)")
        XCTAssertTrue(body.contains("题库") && body.contains("训练记录"),
                      "只说「练不了」会让人以为整个应用都白装了，"
                          + "得把跳过之后仍然能用的那几页列出来：\(body)")
    }

    /// 上一条的**前提**：那个「半自动模式」今天确实不存在。
    ///
    /// 单靠上一条的话，哪天有人真把这两个入口做出来了，文案还停在「练不了」——
    /// 方向反过来的同一种假话。所以把前提也钉住：这两条断言只要有一条红了，
    /// 就说明半自动这条路有人开始铺了，那时该回去把引导文案一起改。
    func testTheSemiAutomaticRouteReallyDoesNotExistYet() throws {
        let promptHolders = try SourceGuard.swiftFiles().filter { url in
            let code = try? SourceGuard.read(contentsOf: url,
                                             describedAs: try SourceGuard.relativePath(of: url))
            return code?.contains("ExaminerPrompt.build") == true
        }.map { try SourceGuard.relativePath(of: $0) }

        XCTAssertEqual(promptHolders, ["Session/PracticeRunner.swift"],
                       "考官提示词除了「直接发给 ChatGPT」之外多了别的去处。"
                           + "要是新增的那处是把它显示/复制给用户，半自动模式就成立了——"
                           + "下一步：把引导里那句「练不成一场」改回去，并说清怎么手动练。")

        let inbox = try SourceGuard.read("Review/PendingReviewInboxView.swift")
        XCTAssertFalse(inbox.contains("剪贴板"),
                       "待处理复盘页出现了剪贴板入口。手动 ⌘C 那条路一旦通了，"
                           + "引导里「没有半自动的练法」就成了新的假话——"
                           + "下一步：两处一起改。")
    }

    /// 最后一步说的「首页已经排好了」得和首页真正会显示的东西对得上（复审第 9 条）。
    ///
    /// 从前这句话是无条件的「首页已经给你排好今天练什么了」，而导入题库根本不生成计划——
    /// 用户进首页看到的唯一路线是「从题库自由选题」，每一场都得自己从整份季度题库里挑。
    /// 现在第一次导入会顺手排一份（`PlanBootstrap`），但**题目不足最短周期、
    /// 或者跳过了导入那一步**时仍然排不出来，所以这句话必须两种情形都说到。
    func testTheReadyStepMatchesWhatTheHomePageWillActuallyShow() {
        let body = OnboardingStep.ready.body
        XCTAssertTrue(body.contains("「开始练习」"), "入口那颗按钮得点名：\(body)")
        XCTAssertTrue(body.contains("学习计划"),
                      "排不出计划时用户得知道去哪儿自己排一份：\(body)")
        XCTAssertTrue(body.contains("不足 7 道") || body.contains("跳过了导入"),
                      "只说排好的那一种情形，另一种情形下这句话又是假的：\(body)")
        // 上面那个「7」不是随手写的数字：它是最短的那一档计划周期。
        // 哪天周期档位改了，这句话跟着就得改。
        XCTAssertEqual(PlanBuilder.supportedLengths.min(), 7,
                       "最短周期变了，引导里「不足 7 道」这句话就过期了")
    }

    func testRecordingStepSaysItIsOffByDefault() {
        // 录音默认关、开启需明确同意（ROADMAP 第 5 节）。这一步必须说清楚。
        let body = OnboardingStep.recordingChoice.body
        XCTAssertTrue(body.contains("默认"), "没说默认状态：\(body)")
        XCTAssertTrue(body.contains("本机"), "没说录音只存在本机：\(body)")
    }

    // MARK: - 进度的存放

    func testStoreRoundTripsWithinOneVersion() {
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)

        XCTAssertEqual(store.completedVersion(), 0, "没记过就是 0，不能是别的什么")
        store.markCompleted(version: OnboardingFlow.currentVersion)
        XCTAssertEqual(store.completedVersion(), OnboardingFlow.currentVersion)
    }

    func testBumpingTheVersionMakesOldUsersSeeItAgain() {
        // 将来引导内容大改时，把 currentVersion 加 1，老用户会再看一次。
        // 不留这个口子的话，改了引导也没人看得到。
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.markCompleted(version: 1)

        XCTAssertTrue(store.completedVersion() >= 1)
        XCTAssertFalse(store.completedVersion() >= 2, "版本号涨了就该重新引导")
    }
}
