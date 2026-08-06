import XCTest
import ChatGPTBridge
@testable import IELTSCoachUI

final class PermissionStatusTests: XCTestCase {
    func testReadyWhenPreflightOK() {
        let readiness = BridgeReadiness(ok: true, messages: ["✅ 环境就绪"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .ready)
    }

    func testNeedsAccessibilityWhenMessageMentionsIt() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsAccessibility)
    }

    func testNeedsChatGPTWhenNotInstalled() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testChatGPTTakesPrecedenceWhenBothMissing() {
        // 两样都缺时先引导装 ChatGPT —— 没有目标应用，给了权限也没用
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。",
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testUnknownWhenNotOKButNoRecognizedMessage() {
        // 不能默认当成「就绪」——那会让用户点进去撞一堵墙
        let readiness = BridgeReadiness(ok: false, messages: ["某种没见过的失败"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .unknown)
    }

    func testSystemSettingsURLPointsAtAccessibilityPane() {
        XCTAssertEqual(PermissionStatus.systemSettingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - 把消息的生产者和消费者绑在一起
    //
    // 上面那批测试全用手写字符串，管不住真正会坏的那一环：`evaluate` 认的
    // 「没找到 ChatGPT」「辅助功能」是写死在 AXDriver 里的文案，改了 AXDriver 的措辞，
    // 手写字符串的测试照样全绿，而 evaluate 会对「没装 ChatGPT」这个最常见的首次启动
    // 失败退化成 .unknown。下面这批让 preflight 的真实输出流过 evaluate。
    // 用假 AXAccess，全程不接触真实 ChatGPT（铁律 5）。

    private func realPreflight(installed: Bool, trusted: Bool,
                               host: HostEnvironment = .commandLine) -> BridgeReadiness {
        let access = FakeAXAccess()
        access.installed = installed
        access.trusted = trusted
        return AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01),
                        shortTimeout: 0.2, stateTimeout: 0.2, host: host).preflight()
    }

    /// 两种宿主都跑一遍：措辞按宿主分叉之后，判定结果不允许跟着分叉。
    private let allHosts: [HostEnvironment] = [.commandLine, .app(name: "IELTS Speaking Coach")]

    func testEvaluateUnderstandsRealPreflightWhenChatGPTIsNotInstalled() {
        for host in allHosts {
            let readiness = realPreflight(installed: false, trusted: true, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT,
                           "AXDriver 说的和 evaluate 认的对不上了（宿主：\(host)）："
                           + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenAccessibilityIsDenied() {
        for host in allHosts {
            let readiness = realPreflight(installed: true, trusted: false, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsAccessibility,
                           "AXDriver 说的和 evaluate 认的对不上了（宿主：\(host)）："
                           + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenBothAreMissing() {
        for host in allHosts {
            let readiness = realPreflight(installed: false, trusted: false, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT,
                           "两样都缺时先引导装 ChatGPT（宿主：\(host)）：" + readiness.messages.joined())
        }
    }

    func testEvaluateUnderstandsRealPreflightWhenEverythingIsReady() {
        for host in allHosts {
            let readiness = realPreflight(installed: true, trusted: true, host: host)
            XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .ready,
                           "宿主：\(host)：" + readiness.messages.joined())
        }
    }

    // MARK: - 页面最上面那行字：每一档说的必须是那一档真正缺的东西

    /// 每个状态该显示的标题。**写成 `switch` 而不是字典**：新加一个 `PermissionState`
    /// 时这里编译不过，逼人把新那一档的标题一起想清楚，而不是让它悄悄没人守。
    private func pinnedTitle(for state: PermissionState) -> String {
        switch state {
        case .ready: return "环境就绪"
        case .needsAccessibility: return "还差一步：辅助功能权限"
        case .needsChatGPT: return "还没装 ChatGPT"
        case .unknown: return "环境检查没通过"
        }
    }

    /// **这条是冲着复审那次突变来的。**
    ///
    /// 在这之前，唯一提到 `title(for:)` 的断言是 `diagnosticsText` 那条 `contains`，
    /// 而那行「状态：」正是用同一个 `title(for:)` 拼的——拿函数的输出跟它自己比，恒真。
    /// 实测把 `.needsAccessibility` 和 `.needsChatGPT` 的标题对调（复制粘贴最常见的错），
    /// 全套测试一条不红：装了 ChatGPT 只是没给权限的用户，看到的大标题是「还没装 ChatGPT」，
    /// 会跑去重装一遍应用，而真正卡住他的那个开关一直没动。
    func testEveryStateHasItsOwnHeadlineAndTwoOfThemCannotBeSwapped() {
        for state in PermissionState.allCases {
            XCTAssertEqual(PermissionStatus.title(for: state), pinnedTitle(for: state),
                           "\(state) 的标题变了。下一步：确认是有意改的措辞（那就同步改这里），"
                               + "还是两档被对调了（那用户会照着错的那句去做）。")
        }

        // 钉死字面量还不够：改措辞的人会顺手把上面那张表一起改掉，连对调也一起复制过去。
        // 所以再钉一次「这句话说的到底是不是这件事」——这几条不认具体措辞，只认说的是哪回事。
        let needsChatGPT = PermissionStatus.title(for: .needsChatGPT)
        XCTAssertTrue(needsChatGPT.contains("ChatGPT"), "没装 ChatGPT 那一档的标题得点名 ChatGPT")
        for wrong in ["权限", "辅助功能"] {
            XCTAssertFalse(needsChatGPT.contains(wrong),
                           "「没装 ChatGPT」的标题里出现了「\(wrong)」——这两档被对调了："
                               + needsChatGPT)
        }

        let needsAccessibility = PermissionStatus.title(for: .needsAccessibility)
        XCTAssertTrue(needsAccessibility.contains("辅助功能"),
                      "缺权限那一档的标题得点名辅助功能：" + needsAccessibility)
        XCTAssertFalse(needsAccessibility.contains("没装"),
                       "缺权限的用户被告知「还没装」，他会去重装一遍应用：" + needsAccessibility)

        let unknown = PermissionStatus.title(for: .unknown)
        for guessed in ["辅助功能", "没装"] {
            XCTAssertFalse(unknown.contains(guessed),
                           "原因不明那一档的标题却点了名，等于替用户猜了一个死因：" + unknown)
        }

        XCTAssertFalse(PermissionStatus.title(for: .ready).contains("没"),
                       "环境就绪那一档不该说「没」什么")

        let titles = PermissionState.allCases.map { PermissionStatus.title(for: $0) }
        XCTAssertEqual(Set(titles).count, titles.count, "有两档共用一个标题，用户分不出自己卡在哪儿")
        XCTAssertFalse(titles.contains(where: \.isEmpty), "有一档没有标题，那一页最上面会是空的")
    }

    /// 上一条只看函数本身。这一条让 `AXDriver.preflight()` 的**真实输出**一路流到标题上：
    /// 「装了 ChatGPT 但没给辅助功能权限」的用户，看到的第一行字必须说的是权限，不是安装。
    func testTheHeadlineOnScreenNamesWhatIsActuallyMissing() {
        for host in allHosts {
            let notInstalled = PermissionStatus.title(
                for: PermissionStatus.evaluate(readiness: realPreflight(installed: false,
                                                                       trusted: true, host: host)))
            XCTAssertTrue(notInstalled.contains("ChatGPT"),
                          "没装 ChatGPT 的用户看到的大标题是「\(notInstalled)」")
            XCTAssertFalse(notInstalled.contains("辅助功能"),
                           "没装 ChatGPT 的用户被支去调权限：" + notInstalled)

            let denied = PermissionStatus.title(
                for: PermissionStatus.evaluate(readiness: realPreflight(installed: true,
                                                                        trusted: false, host: host)))
            XCTAssertTrue(denied.contains("辅助功能"),
                          "装了 ChatGPT 只是没给权限的用户看到的大标题是「\(denied)」——"
                              + "他会跑去重装一遍应用，而开关一直没动")
            XCTAssertFalse(denied.contains("没装"), "同上：" + denied)
        }
    }

    // MARK: - 「重新检查」按下去必须有反馈（这一页按得最多的那颗）

    /// 还没点过就先摆一句「仍未通过」，是还没查就下的结论——权限页已经为这件事栽过一次
    /// （`RootRouter` 那条 `isCheckingPermission` 就是为它加的）。
    func testNoRecheckNoticeBeforeTheUserHasEverPressedTheButton() {
        for state in PermissionState.allCases {
            XCTAssertNil(PermissionStatus.recheckNotice(completedAttempts: 0, state: state,
                                                        host: .app(name: "IELTS Speaking Coach")),
                         "\(state)：用户还没点过「重新检查」，页面就先说了一句「已重新检查」")
        }
    }

    /// **这条是问题 2 的正面判据。**
    ///
    /// 重查结果和上一次一样时，`state` 和 `messages` 都不变，页面别处一个像素都不会变，
    /// 用户分不清是「查过了还是不行」还是「按钮坏了」。
    func testRecheckSaysItAlreadyCheckedAndWhyItStillFailed() throws {
        let host = HostEnvironment.app(name: "IELTS Speaking Coach")
        for state in PermissionState.allCases where state != .ready {
            let notice = try XCTUnwrap(
                PermissionStatus.recheckNotice(completedAttempts: 1, state: state, host: host),
                "\(state)：重查完了却一个字都不说，用户会以为按钮坏了")
            XCTAssertTrue(notice.isFailure, "\(state)：没通过却不是失败样式")
            XCTAssertTrue(notice.text.contains("已重新检查"),
                          "\(state)：没说「已经查过了」，用户分不清是按钮没响应：" + notice.text)
            XCTAssertTrue(notice.text.contains("仍未通过"),
                          "\(state)：没说这次仍然没过：" + notice.text)
            XCTAssertTrue(notice.text.contains("下一步"),
                          "\(state)：只说了失败没说下一步做什么（铁律 4）：" + notice.text)

            // 「下一步」不能把上面那段引导原样重复一遍——用户就是照着它做完才回来点的按钮。
            let guidance = PermissionStatus.guidance(for: state, host: host)
            XCTAssertFalse(guidance.contains(notice.text),
                           "\(state)：重查反馈是上面那段引导的原文复读，等于什么都没说：" + notice.text)
        }
    }

    /// 每一档的「原因」得说的是那一档的事，不能四档共用一句话——
    /// 那样这条反馈就退化成「反正就是没过」，跟没有差不多。
    func testEachFailureGivesItsOwnReasonAndItsOwnNextStep() throws {
        let host = HostEnvironment.commandLine
        let texts = try PermissionState.allCases.filter { $0 != .ready }.map {
            try XCTUnwrap(PermissionStatus.recheckNotice(completedAttempts: 1, state: $0,
                                                         host: host)).text
        }
        XCTAssertEqual(Set(texts).count, texts.count, "有两档的重查反馈一模一样：\(texts)")

        let accessibility = try XCTUnwrap(
            PermissionStatus.recheckNotice(completedAttempts: 1, state: .needsAccessibility,
                                           host: host)).text
        XCTAssertTrue(accessibility.contains("辅助功能"), accessibility)
        let chatGPT = try XCTUnwrap(
            PermissionStatus.recheckNotice(completedAttempts: 1, state: .needsChatGPT,
                                           host: host)).text
        XCTAssertTrue(chatGPT.contains("ChatGPT"), chatGPT)
    }

    /// 连按两次的话，文案一字不差就等于第二次又变回「点了没反应」。
    func testPressingItAgainChangesWhatIsOnScreen() throws {
        let host = HostEnvironment.app(name: "IELTS Speaking Coach")
        let first = try XCTUnwrap(PermissionStatus.recheckNotice(
            completedAttempts: 1, state: .needsAccessibility, host: host)).text
        let second = try XCTUnwrap(PermissionStatus.recheckNotice(
            completedAttempts: 2, state: .needsAccessibility, host: host)).text
        XCTAssertNotEqual(first, second,
                          "第二次点「重新检查」，屏幕上一个字都没变，用户又回到「按钮是不是坏了」")
        XCTAssertTrue(second.contains("2"), "第二次没说这是第几次：" + second)
    }

    /// 通过了就不该再挂一句话：那一刻整页会被主界面换掉，换屏本身就是最强的反馈，
    /// 多出来的一行只会在切换的瞬间闪一下。
    func testNoticeGoesAwayOnceTheEnvironmentIsReady() {
        XCTAssertNil(PermissionStatus.recheckNotice(completedAttempts: 3, state: .ready,
                                                    host: .commandLine))
    }

    /// 重查反馈里的「下一步」同样必须是用户在**这个宿主**里做得到的事。
    /// 这个坑本项目踩过一次（让 .app 用户去勾终端、去跑 axprobe），不能在新加的这句话上重犯。
    func testRecheckNoticeOnlyAsksForThingsThisHostCanActuallyDo() throws {
        let host = HostEnvironment.app(name: "IELTS Speaking Coach")
        for state in PermissionState.allCases where state != .ready {
            let text = try XCTUnwrap(
                PermissionStatus.recheckNotice(completedAttempts: 1, state: state, host: host)).text
            XCTAssertFalse(text.contains("axprobe"),
                           "\(state)：只装了 .app 的用户没有 axprobe 这个命令：" + text)
            XCTAssertFalse(text.contains("终端"), "\(state)：Phase 3 的目标是全程不需要打开终端：" + text)
        }
        let grantee = try XCTUnwrap(
            PermissionStatus.recheckNotice(completedAttempts: 1, state: .needsAccessibility,
                                           host: host)).text
        XCTAssertTrue(grantee.contains("IELTS Speaking Coach"),
                      "没说清该在辅助功能列表里勾谁——勾错对象正是「重查还是不过」最常见的原因："
                          + grantee)

        // 命令行宿主反过来：那边就该说终端，说「本应用」才是错的。
        let cli = try XCTUnwrap(
            PermissionStatus.recheckNotice(completedAttempts: 1, state: .needsAccessibility,
                                           host: .commandLine)).text
        XCTAssertTrue(cli.contains("终端"), "命令行宿主该勾的是终端：" + cli)
    }

    // MARK: - 同一屏上不许出现互相矛盾的「下一步」

    func testAppHostScreenNeverTellsUserToAuthorizeTheTerminal() {
        // 这条守的是复审抓到的原始故障：页面上方的引导语说「把本应用加进列表」，
        // 下方原样展示的 preflight 原文却说「把运行本工具的终端加进去」。
        // 照原文做的用户会去授权终端，回来点「重新检查」仍然失败。
        let host = HostEnvironment.app(name: "IELTS Speaking Coach")
        let readiness = realPreflight(installed: true, trusted: false, host: host)
        let state = PermissionStatus.evaluate(readiness: readiness)
        XCTAssertEqual(state, .needsAccessibility)

        let onScreen = (readiness.messages + [PermissionStatus.guidance(for: state, host: host)]).joined()
        XCTAssertTrue(onScreen.contains("IELTS Speaking Coach"))
        XCTAssertFalse(onScreen.contains("终端"),
                       "页面上任何一句话都不许让 .app 用户去勾终端——照做会白忙一场")
    }

    func testCommandLineHostScreenStillPointsAtTheTerminal() {
        let host = HostEnvironment.commandLine
        let readiness = realPreflight(installed: true, trusted: false, host: host)
        let state = PermissionStatus.evaluate(readiness: readiness)
        let onScreen = (readiness.messages + [PermissionStatus.guidance(for: state, host: host)]).joined()
        XCTAssertTrue(onScreen.contains("终端"))
    }

    // MARK: - 给出的「下一步」必须是用户做得到的事

    func testEveryGuidanceSaysWhatHappenedAndWhatToDoNext() {
        // 走 `allCases` 而不是手写四个：手写的清单不会跟着新加的状态长出来，
        // 而新加的那一档恰恰是最可能忘了写文案的那一档。
        for state in PermissionState.allCases {
            for host in allHosts {
                let text = PermissionStatus.guidance(for: state, host: host)
                XCTAssertFalse(text.isEmpty, "\(state) 没有引导语")
                if state != .ready {
                    XCTAssertTrue(text.contains("下一步"),
                                  "\(state)（宿主 \(host)）只说了失败没说下一步")
                }
            }
        }
    }

    func testUnknownGuidanceOnlyAsksForThingsAGUIUserCanActuallyDo() {
        for host in allHosts {
            let text = PermissionStatus.guidance(for: .unknown, host: host)
            XCTAssertFalse(text.contains("axprobe"),
                           "build-app.sh 只把 IELTSCoachApp 打进 .app，只装了 .app 的用户没有 axprobe")
            XCTAssertFalse(text.contains("终端"), "Phase 3 的目标是全程不需要打开终端")
            XCTAssertTrue(text.contains("复制诊断信息"), "得给一个界面里真按得到的按钮")
        }
    }

    func testAccessibilityGuidanceNamesWhoToTickAndHowToComeBack() {
        let text = PermissionStatus.guidance(for: .needsAccessibility,
                                             host: .app(name: "IELTS Speaking Coach"))
        XCTAssertTrue(text.contains("隐私与安全性 › 辅助功能"))
        XCTAssertTrue(text.contains("IELTS Speaking Coach"))
        XCTAssertTrue(text.contains("重新检查"))
    }

    // MARK: - 「打开系统设置」不许静默失败（铁律 7）

    func testOpenSettingsAsksTheSystemForTheAccessibilityPane() {
        var requested: URL?
        _ = PermissionStatus.openSettings(host: .commandLine) { url in
            requested = url
            return true
        }
        XCTAssertEqual(requested, PermissionStatus.systemSettingsURL)
    }

    func testOpenSettingsReportsFailureInsteadOfLookingLikeADeadButton() {
        // NSWorkspace.open 的返回值在 AppKit 上是 @discardableResult，丢掉它编译器不会警告，
        // 用户看到的就是「点了没反应」。
        let notice = PermissionStatus.openSettings(host: .app(name: "IELTS Speaking Coach")) { _ in false }
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("没能打开系统设置"), "要说清发生了什么")
        XCTAssertTrue(notice.text.contains("系统设置 › 隐私与安全性 › 辅助功能"),
                      "打不开时必须给出手动路径，否则用户无路可走")
        XCTAssertTrue(notice.text.contains("IELTS Speaking Coach"))
    }

    func testOpenSettingsSuccessIsNotReportedAsFailureButStillSaysWhatToDoThere() {
        // 就算 open 返回 true，也不保证真的落在「辅助功能」那一栏（URL 锚点是否被接受
        // 由系统决定），所以成功提示里也要写清到了那儿该做什么。
        let notice = PermissionStatus.openSettings(host: .commandLine) { _ in true }
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("下一步"))
        XCTAssertTrue(notice.text.contains("辅助功能"))
    }

    // MARK: - 「复制诊断信息」

    func testCopyDiagnosticsPutsThePreflightMessagesOnThePasteboard() {
        var written: String?
        _ = PermissionStatus.copyDiagnostics(state: .unknown,
                                             messages: ["❌ 某种没见过的失败", "⚠️ 另一条"],
                                             host: .app(name: "IELTS Speaking Coach"),
                                             systemVersion: "TEST-OS 1.2.3") { text in
            written = text
            return true
        }
        let text = written ?? ""
        XCTAssertTrue(text.contains("❌ 某种没见过的失败"))
        XCTAssertTrue(text.contains("⚠️ 另一条"))
        XCTAssertTrue(text.contains("TEST-OS 1.2.3"), "系统版本是排查这类问题的第一线索")
        XCTAssertTrue(text.contains("IELTS Speaking Coach"), "得写清是在哪个宿主里跑的")

        // 这里原来写的是 `text.contains(PermissionStatus.title(for: .unknown))`——
        // 而 `diagnosticsText` 里那行「状态：」正是用同一个 `title(for:)` 拼的，
        // 等于拿函数的输出跟它自己比，**恒真**。改成钉死那一行的原文：
        // 标题被改坏（比如两档对调）时，这条和上面那组标题断言会一起变红。
        XCTAssertTrue(text.contains("状态：环境检查没通过"),
                      "诊断信息里没有那行「状态：」，开发者拿到手第一眼看不出用户卡在哪一档：" + text)
    }

    /// 诊断信息里的「状态」得跟着状态走。四档都拼成同一句话的话，
    /// 用户粘过来的那份诊断信息就少了最要紧的一行。
    func testDiagnosticsStateLineFollowsTheStateItWasGiven() {
        var written: [PermissionState: String] = [:]
        for state in PermissionState.allCases {
            written[state] = PermissionStatus.diagnosticsText(
                state: state, messages: ["x"], host: .commandLine, systemVersion: "TEST-OS")
        }
        for state in PermissionState.allCases {
            XCTAssertTrue(written[state]?.contains("状态：\(pinnedTitle(for: state))") == true,
                          "\(state) 的诊断信息里那行「状态：」写的不是这一档：\(written[state] ?? "")")
        }
    }

    func testCopyDiagnosticsReportsFailureAndGivesAManualFallback() {
        let notice = PermissionStatus.copyDiagnostics(state: .unknown, messages: ["❌ 某种没见过的失败"],
                                                      host: .commandLine,
                                                      systemVersion: "TEST-OS") { _ in false }
        XCTAssertTrue(notice.isFailure)
        XCTAssertTrue(notice.text.contains("没能"), "写剪贴板失败要说出来，不能假装复制成功")
        XCTAssertTrue(notice.text.contains("下一步"))
        XCTAssertTrue(notice.text.contains("⌘C"), "得留一条不靠剪贴板 API 的退路")
    }

    func testCopyDiagnosticsSuccessConfirmsItIsOnThePasteboard() {
        let notice = PermissionStatus.copyDiagnostics(state: .unknown, messages: ["x"],
                                                      host: .commandLine,
                                                      systemVersion: "TEST-OS") { _ in true }
        XCTAssertFalse(notice.isFailure)
        XCTAssertTrue(notice.text.contains("已复制"))
    }
}
