import Foundation
import XCTest

/// **这个 App 开几个窗口，决定了进程里有几份 `AppState`。**
///
/// 原来 `Sources/IELTSCoachApp/main.swift` 用的是 `WindowGroup`，而 macOS 上它默认带
/// 「文件 ▸ 新建窗口」（⌘N）；`RootView` 每被 new 一次又自己 new 一个 `AppState`。
/// 于是开第二个窗口 = 第二次完整 preflight（又一次 `NSWorkspace.open` 把 ChatGPT 拉到前台、
/// 又一次最多八秒的无障碍树轮询），而且两个窗口的 `permission`、`loadError`、
/// `permissionSkipped` 互不相通：在一个窗口点了「先跳过」，另一个还挡着；
/// 在一个窗口导完题库，另一个显示的还是旧题库。
///
/// 修法选了 `Window`（理由写在 main.swift 的文档注释里）。**这组测试守的就是那个决定**：
/// 改回 `WindowGroup` 会在这里当场变红，逼人把「为什么可以多开窗口、多出来的那份 AppState
/// 归谁管」重新想一遍，而不是随手改一个词就把洞开回来。
///
/// 边界：扫源码不执行代码，它证明不了运行时真的只弹一个窗口——那归人工验收
/// （打开 .app，看「文件」菜单里有没有「新建窗口」）。它守的是「这个决定还在不在代码里」。
final class AppSceneTests: XCTestCase {
    static let mainPath = "Sources/IELTSCoachApp/main.swift"

    func testTheAppOpensExactlyOneWindowSoThereIsExactlyOneAppState() throws {
        // 读的是**去过注释**的源码：main.swift 的说明里必然要写清「为什么不用 WindowGroup」，
        // 连注释一起扫的话，下面那条断言会被自己的说明绊倒。
        let code = try SourceGuard.repositoryCode(Self.mainPath)

        XCTAssertTrue(code.contains("struct CoachApp"),
                      "扫到的不是 App 的入口文件，这条测试等于空转。"
                          + "下一步：确认 \(Self.mainPath) 还在、入口结构体还叫这个名字。")

        XCTAssertFalse(
            code.contains("WindowGroup"),
            "窗口场景改回了 `WindowGroup`。macOS 上它默认带 ⌘N「新建窗口」，"
                + "而每个 `RootView` 都会自己 new 一份 `AppState`：第二个窗口 = 第二次完整 "
                + "preflight（又把 ChatGPT 拉到前台一次）+ 两份互不相通的状态"
                + "（一个窗口点了「先跳过」，另一个还挡着；导完题库，另一个还是旧题库）。"
                + "下一步：换回 `Window(...)`；确实要支持多窗口的话，先把 `AppState` 提到 "
                + "App 层持有并下发、再单独处理 ⌘N，然后连同理由一起改这条测试。")

        XCTAssertTrue(
            code.contains("Window("),
            "找不到窗口场景。下一步：确认入口仍然是 `Window(\"…\", id: …) { RootView(app: app, …) }`。")

        XCTAssertEqual(
            SourceGuard.occurrences(of: "RootView(", in: code), 1,
            "入口文件里 `RootView(` 出现了不止一次——多一个根视图就多一个主窗口。"
                + "下一步：确认没有第二个场景在开第二个根视图。")
    }

    /// **整个进程只许有一份 `AppState`，而且它建在 App 层。**
    ///
    /// Phase 10 Task 16 把它从 `RootView` 提了上来：设置窗口（⌘,）是另一个 Scene，
    /// 两个窗口只有共用同一个实例，「在设置窗口把每周目标改成 9、主窗口那格当场变成 N/9」
    /// 才是必然的；各建各的话就只能靠事后刷新去补，而漏一处就是一个在本机永远复现不了的 bug
    /// ——你改完总会顺手看一眼那个窗口。
    ///
    /// 所以这里数三个数：`AppState()` 只许出现一次，两个 Scene 都得拿着**那一个** `app`。
    func testBothScenesShareTheOneAndOnlyAppState() throws {
        let code = try SourceGuard.repositoryCode(Self.mainPath)

        XCTAssertEqual(
            SourceGuard.occurrences(of: "AppState()", in: code), 1,
            "入口文件里 `AppState()` 出现了 \(SourceGuard.occurrences(of: "AppState()", in: code)) 次。"
                + "多一份就是多一份状态：设置窗口改完，主窗口那格纹丝不动，"
                + "而且不会有任何编译错误。下一步：只建一份，两个 Scene 都传它。")

        XCTAssertTrue(
            code.contains("RootView(app: app"),
            "主窗口没有拿 App 层那份 `app`（多半是又自己 new 了一个）。"
                + "下一步：`RootView(app: app, navigator: settingsNavigator)`。")

        let settingsScene = try SourceGuard.settingsSceneBody(in: code)
        XCTAssertTrue(
            settingsScene.contains("app: app"),
            "设置窗口没有拿 App 层那份 `app`，它和主窗口就是两份互不相通的状态："
                + "在设置里改完，主窗口要切一次页才看得到（甚至永远看不到）。"
                + "实际取到的是：\n\(settingsScene)")
        XCTAssertTrue(
            settingsScene.contains("navigator: settingsNavigator"),
            "设置窗口没有拿 App 层那份 `SettingsNavigator`，首页齿轮那条"
                + "「打开设置并停在训练目标」的深链接就永远落不到那一栏。"
                + "实际取到的是：\n\(settingsScene)")
    }

    /// **设置窗口（⌘,）与它里面那一页的接线，同样得有人守。**
    ///
    /// 实测（Phase 5 那一版）：把 main.swift 里那句 `Settings { … }` 删掉，
    /// `swift test` 是 804 条全绿——因为「保存我的回答录音」那一页的测试测的是
    /// `RecordingSettingsViewModel`（逻辑），没有一条问过「这一页到底挂上 App 了吗」。
    /// 后果是整页从 App 里消失：开关、麦克风权限引导、磁盘占用提示全都没了，
    /// ⌘, 打开是一个空窗口，而全套测试照样绿。
    ///
    /// Phase 10 Task 16 之后这个窗口装的是 `SettingsWindowView`（四个分区），
    /// 它没了的话丢的就不止录音那一页，而是全 App 所有能改的设置。
    func testTheSettingsWindowActuallyOpensTheUnifiedSettingsPage() throws {
        let code = try SourceGuard.repositoryCode(Self.mainPath)

        XCTAssertTrue(
            code.contains("Settings {"),
            "入口文件里没有 `Settings { … }` 场景，⌘, 打开的会是一个空的设置窗口："
                + "录音、训练目标、练习偏好、数据与隐私四个分区整个从 App 里消失，"
                + "而首页齿轮和另外两处「打开设置 › 练习偏好」按钮全都会变成点了没反应。"
                + "下一步：把 `Settings { SettingsWindowView(…) }` 加回 `CoachApp.body`；"
                + "真要改成别的写法（例如 `Settings` 与 `{` 之间不留空格），同步改这条断言。")

        // 光有 `Settings { }` 不够——里面是空的一样等于这一页不存在。
        // 切的是 `Settings {` 后面那对大括号里的内容，找不到会抛错（不会静默放行）。
        let settingsScene = try SourceGuard.settingsSceneBody(in: code)
        XCTAssertTrue(
            settingsScene.contains("SettingsWindowView("),
            "设置窗口里没有 `SettingsWindowView(…)`，⌘, 打开的是一个空窗口。"
                + "下一步：确认它还在；这一页换了别的类型名的话，同步改这条断言。")
    }

    /// 同一类缺陷还能从哪儿溜过去：往 App 目标里再加一个文件，在里面开第二个场景。
    /// 上面那条只盯 main.swift，这条盯整个目标。
    func testNoOtherFileInTheAppTargetOpensASecondWindow() throws {
        // 目录不在、或一个 .swift 都没有，`SourceGuard` 会抛错而不是给个空数组——
        // 空数组会让下面这圈一次都不跑，而这条测试照样是绿的。
        let files = try SourceGuard.swiftFiles(atRepositoryPath: "Sources/IELTSCoachApp")
        for file in files {
            let code = SourceGuard.stripLineComments(
                try SourceGuard.read(contentsOf: file, describedAs: file.lastPathComponent))
            XCTAssertFalse(
                code.contains("WindowGroup"),
                "\(file.lastPathComponent) 里出现了 `WindowGroup`，它会把 ⌘N 和第二份 "
                    + "`AppState` 一起带回来。下一步：见上一条测试的说明。")
        }
    }
}
