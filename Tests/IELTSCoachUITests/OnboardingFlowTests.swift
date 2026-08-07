import Foundation
import XCTest
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

    func testEnvironmentStepTellsUserWhatHappensIfTheySkip() {
        // 跳过是允许的（设计文档第 7 节），但必须让他知道跳过之后是什么样子。
        XCTAssertTrue(OnboardingStep.environment.body.contains("半自动"),
                      "没说清跳过之后会怎样：\(OnboardingStep.environment.body)")
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
