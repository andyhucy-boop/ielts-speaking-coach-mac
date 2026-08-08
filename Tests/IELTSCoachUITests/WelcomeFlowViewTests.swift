import ChatGPTBridge
import Foundation
import IELTSCoachCore
import XCTest

@testable import IELTSCoachUI

/// 首次使用引导那一页上，**逻辑写对了、但可能根本没被接上/没被画出来**的几件事。
///
/// `OnboardingFlowTests` 钉的是「哪几步、每步说什么」，那部分是纯函数，测得很实。
/// 它证明不了的恰恰是这一页真正的价值所在：这几步有没有被摆上根视图、
/// 「先跳过」是不是真的按 `canSkip` 显示、录音那一步有没有偷偷自己写一遍开关逻辑。
/// 本项目在 `PracticeSheet`、`QuestionBankImportResultSheet` 上因为这类缺口栽过两次：
/// 渲染那一段整段删掉，全套测试照样全绿。
///
/// 边界与 `PermissionGateViewTests` 一样：扫源码不执行代码，拦得住「整段被删」
/// 「写好了没摆上」「偷偷另写一套」，拦不住「代码还在但条件永远为假」；
/// 排版好不好看、九秒里读起来顺不顺，归人工验收（计划 Step 7）。
final class WelcomeFlowViewTests: XCTestCase {
    static let viewPath = "Onboarding/WelcomeFlowView.swift"
    static let rootPath = "RootView.swift"
    static let gatePath = "Onboarding/PermissionGateView.swift"
    static let recordingModelPath = "Recording/RecordingSettingsViewModel.swift"

    // MARK: - 引导真的被摆上了根视图

    /// 这几步算得再准，根视图不显示它就等于没做。
    func testTheRootViewActuallyShowsTheFlowOnTheOnboardingBranch() {
        SourceGuard.assertRenders("case .onboarding:", inBodyOf: "public var body",
                                  of: Self.rootPath,
                                  because: "根视图的路由里没有引导那一支，"
                                      + "`RootRouter` 判出 `.onboarding` 之后没有任何东西被画出来。")
        SourceGuard.assertRenders("WelcomeFlowView(", inBodyOf: "public var body", of: Self.rootPath,
                                  because: "引导页没有被摆进根视图。"
                                      + "下一步：`case .onboarding:` 那一支要画 `WelcomeFlowView(...)`。")
    }

    /// 「弹不弹」必须读磁盘上那个标记，不能写死。
    ///
    /// 写死成 `true`，全新安装的人一个引导都看不到；写死成 `false`，
    /// 每次开机都从「欢迎」重头来一遍。两种都不会有任何一条别的测试变红。
    func testWhetherToPresentIsFedByTheRealStoreAndNotHardcoded() {
        SourceGuard.assertRenders("onboardingStore.completedVersion()", in: Self.rootPath,
                                  because: "根视图没去问「引导看过没有」，那个标记等于白记。"
                                      + "下一步：`hasCompletedOnboarding` 要读 "
                                      + "`OnboardingProgressStore.completedVersion()`。")
        SourceGuard.assertRenders("OnboardingFlow.currentVersion", in: Self.rootPath, atLeast: 2,
                                  because: "版本号只用了一处（要么比对、要么记账少了一边）。"
                                      + "少了比对那一边，将来把 `currentVersion` 加 1 也没人会重看引导；"
                                      + "少了记账那一边，记下去的版本号对不上，引导永远弹。")
    }

    /// 收工要做两件事，缺一不可。
    ///
    /// 只记不放行：`OnboardingFlow.steps` 会因为权限仍缺立刻算出 `[.environment]`，
    /// 引导当场又弹回用户脸上——他刚点完「先跳过」。
    /// 只放行不记：下次开机从「欢迎」重头再来一遍。
    func testFinishingTheFlowBothRecordsItAndLetsTheUserIn() {
        SourceGuard.assertRenders("onboardingStore.markCompleted(version: OnboardingFlow.currentVersion)",
                                  inBodyOf: "private func finishOnboarding", of: Self.rootPath,
                                  because: "走完引导没有记下「看过了」，下次开机又从「欢迎」重头来。")
        SourceGuard.assertRenders("app.onboardingDismissed = true",
                                  inBodyOf: "private func finishOnboarding", of: Self.rootPath,
                                  because: "走完引导没有放行。权限仍缺时 `steps` 会立刻算出 "
                                      + "`[.environment]`，用户点完最后一步又被弹回同一屏。")
    }

    // MARK: - 三句文案逐字来自 OnboardingStep

    /// 视图里再写一套的话，`OnboardingFlowTests` 那几条文案断言就管不到屏幕上的东西了。
    func testThePageTakesEveryWordFromTheStepInsteadOfWritingItsOwn() {
        for member in ["step.title", "step.body", "step.primaryActionTitle"] {
            SourceGuard.assertRenders(member, in: Self.viewPath,
                                      because: "引导页没有用 `OnboardingStep` 的这一项。"
                                          + "下一步：三句话（标题、正文、主按钮）都从枚举取，"
                                          + "视图里不要另写一套——另写一套的那份没有任何测试管得住。")
        }
    }

    /// 「第 N 步 / 共 M 步」是这条流程里唯一告诉用户「还剩几步」的东西。
    /// 没有它，用户不知道自己是在一分钟的开头还是结尾。
    func testTheProgressCounterIsOnScreen() {
        SourceGuard.assertRenders("第 \\(index + 1) 步 / 共 \\(steps.count) 步",
                                  inBodyOf: "private var progressLine", of: Self.viewPath,
                                  because: "步数指示没了。下一步：把「第 N 步 / 共 M 步」摆回去，"
                                      + "而且两个数字都要从真实的步骤数组来，不能写死。")
        SourceGuard.assertRenders("progressLine", inBodyOf: "public var body", of: Self.viewPath,
                                  because: "步数指示声明了却没摆进 body，用户一个字看不到。")
    }

    // MARK: - 「先跳过」由 canSkip 决定，不是写死

    func testTheSkipButtonIsGatedOnCanSkip() {
        SourceGuard.assertRenders("step.canSkip", inBodyOf: "private func footer", of: Self.viewPath,
                                  because: "「先跳过」不是按 `step.canSkip` 显示的。"
                                      + "写死的话，`OnboardingFlowTests` 里那条"
                                      + "「只有环境和题库能跳过」就跟屏幕上的按钮没关系了——"
                                      + "最糟的一种走法是「录音」那一步也长出一颗「先跳过」，"
                                      + "而那一步本来就是个二选一。")
    }

    /// **同一屏上不许出现两组同名按钮。**
    ///
    /// 「环境」那一步整块复用 `PermissionGateView`，它自带「打开系统设置」「重新检查」
    /// 「复制诊断信息」「先跳过」四颗。流程页要是照着别的步骤的样子再画一颗「打开系统设置」
    /// 和一颗「先跳过」，用户就得在两颗写着同样字的按钮之间猜哪颗是真的。
    func testTheFlowDoesNotDrawASecondCopyOfThePermissionGatesButtons() {
        SourceGuard.assertRenders("ownsActionRow", in: Self.viewPath, atLeast: 3,
                                  because: "「这一步的动作行归谁画」这个判断没了（声明一次、用两次）。"
                                      + "没有它，「环境」那一步会同时出现流程页和权限页两套按钮。")
        SourceGuard.assertOmits("Button(\"打开系统设置\")", in: Self.viewPath,
                                because: "这颗按钮归 `PermissionGateView`。"
                                    + "下一步：删掉这一颗；真要改成流程页自己画，"
                                    + "就得把权限页那一颗一起摘掉，否则同一屏两颗同名按钮。")
    }

    // MARK: - 三步各自复用现成的页面

    func testTheEnvironmentStepReusesThePermissionGate() {
        SourceGuard.assertRenders("PermissionGateView(",
                                  inBodyOf: "private var environmentStep", of: Self.viewPath,
                                  because: "「环境」那一步没有复用 Phase 3 的授权页。"
                                      + "另写一套的后果不是重复代码，是两套说法：那一页的引导语会按宿主"
                                      + "（.app / 命令行）说清该把**谁**加进辅助功能列表，"
                                      + "而这个坑本项目已经踩过一次。")
        SourceGuard.assertRenders("environmentStep", inBodyOf: "private func stepContent",
                                  of: Self.viewPath,
                                  because: "「环境」那一步声明了却没摆进步骤内容里。")
    }

    /// 环境本来就绪时不许再摆那一页。
    ///
    /// `PermissionGateView` 最后一行写死着「「先跳过」后可以先浏览题库和历史复盘；
    /// 在上面的问题解决之前，自动驱动 ChatGPT 的练习没法进行」——环境就绪时根本没有
    /// 「上面的问题」，同一屏上还会同时出现「环境就绪」和「先跳过」，用户读不出该信哪句。
    /// 而这条路径不是边缘情况：在同一台 Mac 上重装、TCC 还记着授权的人走的就是它。
    func testTheEnvironmentStepDropsTheGateWhenNothingIsMissing() {
        SourceGuard.assertRenders("showsPermissionGate", in: Self.viewPath, atLeast: 3,
                                  because: "「环境就绪时还摆不摆权限页」这个判断没了"
                                      + "（声明一次、内容里用一次、动作行归属里用一次）。"
                                      + "没有它，已经授过权的人会在引导里读到一屏自相矛盾的话。")
        SourceGuard.assertRenders("permissionReadyCard",
                                  inBodyOf: "private var environmentStep", of: Self.viewPath,
                                  atLeast: 1,
                                  because: "环境就绪时这一步什么都不显示了。"
                                      + "这一步在就绪时也必须显示——用户有权知道这个 App "
                                      + "拿辅助功能去干什么，但要说成「已经拿到了」。")
        // 上面两条只问「这个判断还在不在」，把它改成恒真（`{ true }`）照样绿——
        // 而那正好是这条守卫要防的那一种。所以再钉一次它到底在判什么。
        SourceGuard.assertRenders("app.permission != .ready",
                                  inBodyOf: "private var showsPermissionGate", of: Self.viewPath,
                                  because: "「摆不摆权限页」不再是按真实的权限状态判的。"
                                      + "恒真的话，已经授过权的人会读到一屏自相矛盾的话；"
                                      + "恒假的话，缺权限的人在引导里根本拿不到"
                                      + "「打开系统设置」「重新检查」那几颗按钮。")
    }

    /// 「环境」那一步的主按钮名字，必须真的是界面上存在的一颗控件。
    ///
    /// 这一步的动作行由 `PermissionGateView` 画，所以 `primaryActionTitle` 在这里
    /// 不是「流程页要画的按钮」，而是「这一步的主行动叫什么」。两边一旦不同名，
    /// 就意味着枚举在描述一颗不存在的按钮——铁律 4 里那种「指了个找不到的东西」。
    func testTheEnvironmentStepPrimaryActionIsAButtonThatReallyExists() throws {
        let controls = try SourceGuard.literalControlTitles()
        XCTAssertTrue(
            controls.contains(OnboardingStep.environment.primaryActionTitle),
            "「环境」这一步的主行动叫「\(OnboardingStep.environment.primaryActionTitle)」，"
                + "而界面上没有这个名字的按钮或开关。"
                + "下一步：改成 `PermissionGateView` 上那颗按钮的名字（现在叫「打开系统设置」），"
                + "或者把那颗按钮改成这个名字——两边必须逐字相同。")
        SourceGuard.assertRenders("Button(\"\(OnboardingStep.environment.primaryActionTitle)\")",
                                  in: Self.gatePath,
                                  because: "权限页上那颗按钮不叫这个名字了，"
                                      + "而 `OnboardingStep.environment.primaryActionTitle` 还写着它。")
    }

    /// 题库导入走「训练题库」页同一条路：认格式、取文字（PDF 走 PDFKit）、解析、落盘。
    ///
    /// 各写一份的后果是引导里导进去的题落在别处——用户走完引导到首页一看，题库还是空的，
    /// 而且不会有任何报错。
    func testTheQuestionBankStepGoesThroughTheSameImportPathAsTheQuestionBankPage() {
        SourceGuard.assertRenders("QuestionBankImport.importFile(at: url)",
                                  inBodyOf: "private func importQuestionBank", of: Self.viewPath,
                                  because: "引导里的导入没走 `QuestionBankImport.importFile(at:)`。"
                                      + "那三步（认格式 / 取文字 / 解析）散开写的话，"
                                      + "取文字那一步一旦按 UTF-8 读文件，真实 PDF 就再也导不进来，"
                                      + "而三步各自的测试全都照绿。")
        SourceGuard.assertRenders("app.applyImport(result)",
                                  inBodyOf: "private func importQuestionBank", of: Self.viewPath,
                                  because: "导进来的题没有经 `AppState` 落盘，"
                                      + "会写进另一个数据目录（或者根本没写）。")
        SourceGuard.assertRenders("QuestionBankImportResultSheet(",
                                  inBodyOf: "public var body", of: Self.viewPath,
                                  because: "导入之后没有那张交代，用户看不到导了几题、"
                                      + "更看不到「第 7 行缺 id，那道题没进来」这类警告——"
                                      + "不看就再也不会知道。")
        SourceGuard.assertRenders("QuestionBankImport.describeFailure(",
                                  inBodyOf: "private func importQuestionBank", of: Self.viewPath,
                                  because: "导入失败被吞掉了：用户选完文件回来屏幕纹丝不动，"
                                      + "只会以为这颗按钮坏了（铁律 7）。")
    }

    func testTheRecordingStepEmbedsThePhase5SettingsPage() {
        SourceGuard.assertRenders("RecordingSettingsView(viewModel:",
                                  inBodyOf: "private var recordingStep", of: Self.viewPath,
                                  because: "「录音」那一步没有内嵌 Phase 5 的录音设置页。")
        SourceGuard.assertRenders("app.makeRecordingSettingsViewModel()", in: Self.viewPath,
                                  because: "录音设置页拿到的不是 `AppState` 那一份视图模型，"
                                      + "多半意味着它连着另一个数据目录：引导里拨的开关"
                                      + "写进另一个 state.json，用户练完一场一秒录音都没有。")
        SourceGuard.assertRenders("recordingStep", inBodyOf: "private func stepContent",
                                  of: Self.viewPath,
                                  because: "「录音」那一步声明了却没摆进步骤内容里。")
    }

    // MARK: - 最要紧的一条：引导页不许自己写一遍录音开关

    /// 计划初稿让引导页自己 `mutate` 写 `recordingEnabled = true` 与 `recordingConsentAt`。
    /// **那会造出 Phase 5 明令禁止的那个状态**：开关显示「开」、麦克风权限根本没申请过，
    /// 于是用户练完一场发现什么都没录，而且完全无从查起。
    /// 它同时还把「同意时间戳怎么记」这条规则实现了第二遍。
    ///
    /// 所以整个 `Onboarding/` 目录里，这四个名字一个都不许出现——
    /// 它们只属于 `RecordingSettingsViewModel` 那一条路。
    static let onlyBelongToPhase5 = ["recordingEnabled", "recordingConsentAt",
                                     "RecordingConsent.", "requestAccess("]

    func testTheOnboardingNeverWritesTheRecordingConsentItself() throws {
        var scanned = 0
        for url in try SourceGuard.swiftFiles(under: "Onboarding") {
            let path = try SourceGuard.relativePath(of: url)
            scanned += 1
            for needle in Self.onlyBelongToPhase5 {
                SourceGuard.assertOmits(
                    needle, in: path,
                    because: "引导页在自己写一遍录音开关的逻辑。"
                        + "下一步：删掉它，改成内嵌 `RecordingSettingsView`——"
                        + "「问权限 → 只有 granted 才写盘 → 写盘走 `RecordingConsent.enable` →"
                        + "没拿到就把开关弹回「关」并显示引导」这一整条只该有一份实现。")
            }
        }
        // 防空转：目录挪了、一个文件都没扫到的话，上面那圈一次都不跑也是全绿。
        XCTAssertGreaterThanOrEqual(scanned, 3,
                                    "只扫到 \(scanned) 个引导页文件，这条测试很可能在空转。")
    }

    /// **上一条的牙齿。** 那四个名字要是拼错了（或者 Phase 5 改了写法），
    /// 「引导目录里没有它们」就成了一句恒真的废话。所以反过来问一遍：
    /// 它们必须真的出现在 Phase 5 那条路上。
    func testThoseNamesAreTheRealPhase5PathSoTheirAbsenceMeansSomething() throws {
        let code = try SourceGuard.code(Self.recordingModelPath)
        for needle in Self.onlyBelongToPhase5 {
            XCTAssertTrue(
                code.contains(needle),
                "「\(needle)」在 \(Self.recordingModelPath) 里找不到，"
                    + "那么「引导目录里没有它」这句话就什么也没证明。"
                    + "下一步：确认 Phase 5 那条路是不是改了写法，跟着改上面那份名单。")
        }
    }

    // MARK: - 减弱动态效果

    /// DESIGN-SYSTEM 第 5 节：开了系统「减弱动态效果」就不许有过渡。这是硬性要求。
    func testTheFlowRespectsReduceMotion() {
        SourceGuard.assertRenders("accessibilityReduceMotion", in: Self.viewPath,
                                  because: "引导页没有读系统的「减弱动态效果」设置。")
        SourceGuard.assertRenders("reduceMotion ? nil :", inBodyOf: "public var body",
                                  of: Self.viewPath,
                                  because: "读了设置却没有按它禁用过渡，等于没读。")
    }

    // MARK: - 步骤游标本身（这一段是真跑逻辑，不是扫源码）

    /// 步骤一旦定下来就不能再变。
    ///
    /// 不冻的话：用户在「题库」那一步真导进来几道题之后，`OnboardingFlow.steps` 里
    /// 「题库已经有题就不问导入」那一条会翻转，步骤数组当场少一项，
    /// 后面几步的下标全部往前挪一格——用户会被凭空推到下一步，
    /// 而刚导入的那份交代（含逐条警告）还没来得及看。
    @MainActor func testTheStepsAreFrozenTheFirstTimeTheyAreShown() {
        let model = OnboardingFlowModel()
        XCTAssertNil(model.frozenSteps, "还没显示过就已经有冻好的步骤了")

        model.freeze([.welcome, .environment, .questionBank, .recordingChoice, .ready])
        // 导入之后再算一次，题库那一步没了——它不该覆盖已经冻住的那份。
        model.freeze([.welcome, .environment, .recordingChoice, .ready])

        XCTAssertEqual(model.frozenSteps,
                       [.welcome, .environment, .questionBank, .recordingChoice, .ready],
                       "步骤被第二次计算覆盖了：用户会在导完题库那一瞬间被凭空推到下一步。")
    }

    @MainActor func testGoingBackFromTheFirstStepStaysPut() {
        let model = OnboardingFlowModel()
        model.goBack()
        XCTAssertEqual(model.index, 0, "从第一步再往回退，下标成了负数——那会当场越界崩掉。")

        model.advance()
        model.advance()
        model.goBack()
        XCTAssertEqual(model.index, 1, "「上一步」没有真的退回去")
    }

    // MARK: - 「重新检查」查到就绪之后，替用户把这一步走掉

    /// **这一段守的是一次已经真实发生过的空转。**
    ///
    /// 初版写的是 `.onChange(of: app.permission) { … advance() }`，而它在真实运行路径上
    /// 一次都触发不了：唯一会写 `AppState.permission` 的 `runPermissionCheck()`
    /// **先**把 `isCheckingPermission` 拨成 true、再 await 那个最长约十秒的检查、
    /// 最后才写 `permission`（写完到把标志拨回 false 之间没有挂起点，所以没有任何一帧
    /// 能看到「permission 变了、但没在检查」）；而 `RootRouter.screen` 在
    /// `isCheckingPermission == true` 时返回 `.checkingEnvironment`
    /// （`AppStateTests.testRecheckSaysItIsCheckingWhileThePreflightIsStillRunning`
    /// 钉着这件事），于是这十秒里 `WelcomeFlowView` 整个被摘出视图树。
    /// 等检查跑完，回来的是**全新的一份**视图，而 `.onChange` 默认的 `initial: false`
    /// 不会为「自己不在场时发生的那次变化」补触发——代码在那儿，一次也没跑过，
    /// 注释却写着「查到就绪自动往前走一步」，用户实际上正要再点一次「下一步」。
    ///
    /// 所以判据不能是 `permission` 的「变化」，只能是一个**活得过这次重建**的信号：
    /// `AppState.recheckAttempts`（只增不减）配上记在 `OnboardingFlowModel` 里的
    /// 「已经消化到第几次了」——模型在 `RootView` 手上，躲得过这次重建
    /// （与 `frozenSteps` / `index` 提到那一层是同一个理由）。
    @MainActor func testARecheckThatFoundEverythingReadyMovesTheFlowForward() {
        let model = OnboardingFlowModel()
        model.freeze([.welcome, .environment, .questionBank, .recordingChoice, .ready])
        model.advance()                          // 用户停在「环境」这一步

        XCTAssertTrue(
            model.consumeRecheckResult(attempts: 1, step: .environment, permission: .ready),
            "「重新检查」查到就绪了，流程却不肯往前走。用户刚在系统设置里勾完开关回来，"
                + "让他再点一次「下一步」是在问一个已经有答案的问题。")
    }

    /// 同一次结果只算一次。
    ///
    /// 这个判断挂在 `.onChange(initial: true)` 上，视图每重新出现一次就会问一次
    /// （而这一页本来就会被反复重建，见上面那段）。每次都算数的话，用户会被一路推过
    /// 「题库」和「录音」——两步都没看见，题库还是空的，录音开关他压根没被问过。
    @MainActor func testTheSameRecheckResultOnlyMovesTheFlowForwardOnce() {
        let model = OnboardingFlowModel()
        XCTAssertTrue(
            model.consumeRecheckResult(attempts: 1, step: .environment, permission: .ready))

        XCTAssertFalse(
            model.consumeRecheckResult(attempts: 1, step: .environment, permission: .ready),
            "同一次检查结果被消化了两次：用户会被连推两步，中间那几步一眼都没看到。")
    }

    /// **不许退化成「权限已经就绪就直接跳过环境步」。**
    ///
    /// 那一步在就绪时也必须让用户读到——他有权知道这个 App 拿辅助功能去干什么
    /// （`OnboardingFlowTests.testFreshInstallStillExplainsThePermissionEvenWhenAlreadyGranted`
    /// 钉着这件事）。自动前进的前提是「用户刚点过一次『重新检查』」，
    /// 而不是「权限恰好是就绪的」。
    @MainActor func testAFlowThatWasNeverRecheckedStillWalksThroughTheEnvironmentStep() {
        let model = OnboardingFlowModel()
        XCTAssertFalse(
            model.consumeRecheckResult(attempts: 0, step: .environment, permission: .ready),
            "一次「重新检查」都没点过，就因为权限本来就有把「环境」这一步跳掉了。"
                + "在同一台 Mac 上重装、TCC 还记着授权的人走的正是这条路，"
                + "他会完全不知道这个 App 要辅助功能干什么。")
    }

    /// 查完仍然不就绪就得留在原地：那句「已重新检查，仍未通过」是他唯一的线索。
    @MainActor func testARecheckThatStillFindsSomethingMissingStaysPut() {
        for permission in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let model = OnboardingFlowModel()
            XCTAssertFalse(
                model.consumeRecheckResult(attempts: 1, step: .environment, permission: permission),
                "\(permission)：查完仍然不就绪，却把用户推到了下一步。"
                    + "他会带着一个残的环境走完引导，而「已重新检查，仍未通过」"
                    + "那句话一眼都没看到。")
        }
    }

    /// 别的步骤跟环境检查没关系，一次检查结果不该推着它们走。
    @MainActor func testARecheckResultNeverMovesAStepOtherThanTheEnvironment() {
        for step in [OnboardingStep.welcome, .questionBank, .recordingChoice, .ready] {
            let model = OnboardingFlowModel()
            XCTAssertFalse(
                model.consumeRecheckResult(attempts: 1, step: step, permission: .ready),
                "\(step)：这一步跟环境检查没关系，却被一次检查结果推着往前走了。")
        }
        let model = OnboardingFlowModel()
        XCTAssertFalse(model.consumeRecheckResult(attempts: 1, step: nil, permission: .ready),
                       "一步都算不出来的时候（`nothingToConfirm` 那一屏）还在往前走。")
    }

    /// 把上面那几条接到**真的** `AppState` 上跑一遍。
    ///
    /// 单独测那个纯判断，管不住「它盯的这个信号在真实路径上根本不来」——
    /// 而这正是被修的那个 bug 的形状。所以这里让 `AXDriver.preflight()` 的真实输出
    /// 流过 `AppState`：先是没授权（自动检查那一次不算数、也不许推人），
    /// 然后模拟用户去系统设置勾上开关、回来点「重新检查」。全程用假的无障碍接口，
    /// 一次都不碰真实 ChatGPT（铁律 5）。
    @MainActor func testTheRealRecheckPathProducesExactlyTheSignalTheFlowWatches() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-onboarding-\(UUID().uuidString)")
        let directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        defer { try? FileManager.default.removeItem(at: root) }

        let access = FakeAXAccess()
        access.installed = true
        access.trusted = false
        let app = AppState(directory: directory, preflight: {
            AXDriver(access: access,
                     locator: AXLocator(access: access, pollInterval: 0.01),
                     shortTimeout: 0.2, stateTimeout: 0.2,
                     host: .app(name: "IELTS Speaking Coach")).preflight()
        })

        let model = OnboardingFlowModel()
        model.freeze([.welcome, .environment, .questionBank, .recordingChoice, .ready])
        model.advance()                          // 用户停在「环境」这一步

        await app.startInitialPermissionCheckIfNeeded()
        XCTAssertEqual(app.permission, .needsAccessibility)
        XCTAssertFalse(
            model.consumeRecheckResult(attempts: app.recheckAttempts,
                                       step: .environment, permission: app.permission),
            "开机第一次自动检查就把用户推走了——那一次不是他点出来的，何况环境还是缺的。")

        // 用户去「系统设置 › 隐私与安全性 › 辅助功能」把开关勾上了，回来点「重新检查」。
        access.trusted = true
        await app.recheckPermission()

        XCTAssertEqual(app.permission, .ready)
        XCTAssertTrue(
            model.consumeRecheckResult(attempts: app.recheckAttempts,
                                       step: .environment, permission: app.permission),
            "用户勾完开关回来点「重新检查」，查到就绪了，流程还停在原地等他再点一次「下一步」。")
    }

    /// 上面那几条只管住「这个判断本身对不对」。判断写对了却没接上界面，用户什么也感觉不到——
    /// 而那恰恰是初版的病：代码在那儿，一次都跑不到。
    func testTheFlowActuallyAsksThatQuestionWhenARecheckComesBack() {
        SourceGuard.assertRenders("app.recheckAttempts", inBodyOf: "public var body",
                                  of: Self.viewPath,
                                  because: "引导页没有盯着「重新检查」跑完的次数。"
                                      + "下一步：`.onChange(of: app.recheckAttempts, initial: true)`。"
                                      + "盯 `app.permission` 是不行的——那一次变化发生在这一页"
                                      + "被摘出视图树的那十秒里，`.onChange` 不会为它补触发。")
        SourceGuard.assertRenders("model.consumeRecheckResult(", inBodyOf: "public var body",
                                  of: Self.viewPath,
                                  because: "查完回来之后没有问一句「要不要替用户往前走一步」，"
                                      + "计划 Task 8 Step 6 里「检查到就绪后自动前进一步」那条没落地。")
        SourceGuard.assertRenders("initial: true", inBodyOf: "public var body", of: Self.viewPath,
                                  because: "`.onChange` 没写 `initial: true`。"
                                      + "默认的 `initial: false` 只认「这一页在场时发生的变化」，"
                                      + "而要处理的那一次恰恰发生在它不在场的时候——"
                                      + "少了这两个字，这一整条会退回到一次都不触发，跟没写一样。")
    }

    /// 那种一次都触发不了的写法不许再回来。
    func testTheFlowDoesNotGoBackToWatchingThePermissionItself() {
        SourceGuard.assertOmits("onChange(of: app.permission", in: Self.viewPath,
                                because: "「重新检查」会把 `AppState.isCheckingPermission` 拨成 true，"
                                    + "根视图整屏换成「正在检查运行环境…」，这一页连同它的 "
                                    + "`.onChange` 一起被销毁；等 `permission` 真的变了，"
                                    + "回来的是全新的一份视图，`.onChange` 不会为"
                                    + "「自己不在场时发生的那次变化」补触发——这种写法一次都跑不到。"
                                    + "下一步：改盯 `app.recheckAttempts`（它只增不减），"
                                    + "并把「已经消化到第几次」记进 `OnboardingFlowModel`。")
    }
}
