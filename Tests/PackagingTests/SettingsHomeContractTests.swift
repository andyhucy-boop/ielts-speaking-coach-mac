import XCTest

/// 守「同一个设置不得有两个入口」。
///
/// Phase 10 之前，录音在 ⌘, 设置窗口、每周目标在首页齿轮、
/// 三项练习偏好在学习计划页页尾、「记录对话逐字稿」在训练记录页页头。
/// 合并之后必须**回不去**——而「回去」的形式往往只是某个页面里多了一行
/// `$0.settings.xxx = …`，代码审查一眼扫过去看不出来，
/// 用户却会遇到两个说法不一样的开关。
final class SettingsHomeContractTests: XCTestCase {

    private var sourcesRoot: URL {
        NotarizeScriptTests.repositoryRoot.appending(path: "Sources")
    }

    private func swiftFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func filesMatching(_ pattern: String) throws -> [String] {
        var owners: [String] = []
        for file in try swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.range(of: pattern, options: .regularExpression) != nil {
                owners.append(file.lastPathComponent)
            }
        }
        return owners.sorted()
    }

    func testThereAreFilesToScan() throws {
        XCTAssertGreaterThan(try swiftFiles().count, 20,
                             "扫不到源码，先检查这个路径：\(sourcesRoot.path)")
    }

    func testEverySettingIsWrittenFromExactlyOnePlace() throws {
        // 只匹配 `.settings.<字段> =` 这种「改的是某个 CoachState 里的设置」的写法。
        // CoachSettings 自己的 init 里写的是 `self.weeklyGoal = …`，不在此列，
        // 那是构造，不是入口。
        //
        // **transcriptEnabled 必须在这张清单里**（2026-08-06 复审补入）：
        // 它是 Phase 4 放在训练记录页顶部、又要收进设置窗口的那一个，
        // 也就是五个字段里**唯一真的出现过两个写入口**的那个。
        // 漏掉它，这条测试恰好看不见它本该拦住的那次事故。
        for field in ["transcriptEnabled", "weeklyGoal",
                      "defaultRoute", "feedbackTiming", "part2PrepMode"] {
            let owners = try filesMatching(#"\.settings\."# + field + #"\s*="#)
            XCTAssertEqual(owners, ["CoachSettingsViewModel.swift"],
                           "settings.\(field) 的写入口应当只有设置窗口的视图模型，实际在：\(owners)。"
                           + "同一个设置有两个写入口，迟早会出现两个说法不一样的开关。"
                           + "下一步：把那一处改成调 `CoachSettingsViewModel` 上对应的 set 方法，"
                           + "界面入口改成 `navigator.open(…)` + `openSettings()` 的深链接。")
        }
    }

    func testNobodyBypassesTheRecordingConsentHelper() throws {
        // 录音那一格是例外：它得先申请麦克风权限，同意时间戳的规则在 Core 的
        // RecordingConsent 里（它内部写的是 `updated.recordingEnabled = …`）。
        // 别处一旦直接改 `state.settings.recordingEnabled`，就会造出 Phase 5 明令禁止的状态：
        // 开关显示「开」、麦克风权限根本没申请过，用户练完发现什么都没录，且无从查起。
        let offenders = try filesMatching(#"\.settings\.recordingEnabled\s*="#)
        XCTAssertTrue(offenders.isEmpty,
                      "有人绕开 RecordingConsent 直接改了录音开关：\(offenders)。"
                      + "下一步：改成走 `RecordingSettingsViewModel.setEnabled(_:)`，"
                      + "那条路才会先申请麦克风权限、再记同意时间戳。")
    }

    /// 训练记录页上那个逐字稿开关必须真的没了（决策表第四行）。
    /// 留着它就是「同一个设置两个家」——而且这两个家改的还是同一个字段，
    /// 只是一个走 AppState、一个走 CoachSettingsViewModel，
    /// **谁后写盘谁说了算**，用户看到的是随机结果。
    func testTheTranscriptToggleLeftTheHistoryPage() throws {
        guard let file = try swiftFiles().first(where: { $0.lastPathComponent == "HistoryView.swift" })
        else { return }   // Phase 4 未交付时跳过
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertNil(text.range(of: #"Toggle\("#, options: .regularExpression),
                     "训练记录页还留着一个开关。逐字稿只在设置窗口的「练习偏好」里改。"
                     + "下一步：把开关换成一行只读现状 + 一颗「打开设置 › 练习偏好」按钮。")
        XCTAssertNil(text.range(of: "setTranscriptEnabled"),
                     "训练记录页还在自己写这个设置。"
                     + "下一步：写入口只留 `CoachSettingsViewModel.setTranscriptEnabled(_:)` 一处。")
    }

    func testTheOldWeeklyGoalSheetIsGoneForGood() {
        // 它就是「第二份界面」的定义。留着它，早晚有人把它再挂回某个页面。
        let path = NotarizeScriptTests.repositoryRoot
            .appending(path: "Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "WeeklyGoalSheet.swift 还在。每周目标应当只在设置窗口里改。"
                       + "下一步：把 `WeeklyGoalEditor` 留在 WeeklyGoalEditor.swift，"
                       + "面板本体连同文件一起删掉。")
    }

    func testTheGearButtonDoesNotFightTheSettingsSceneForCommandComma() throws {
        // Settings 场景自带 ⌘,。别处再挂一个，SwiftUI 不报错，
        // 只会由其中一个随机胜出——用户按 ⌘, 时而弹这个、时而弹那个。
        for name in ["RootView.swift", "TodayView.swift", "PlanView.swift"] {
            guard let file = try swiftFiles().first(where: { $0.lastPathComponent == name })
            else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertNil(text.range(of: #"keyboardShortcut\(\s*","#, options: .regularExpression),
                         "\(name) 里给 ⌘, 挂了第二个动作。"
                         + "下一步：把那一行 `.keyboardShortcut(\",\", modifiers: .command)` 删掉——"
                         + "`Settings` 场景本来就带这个快捷键。")
        }
    }
}
