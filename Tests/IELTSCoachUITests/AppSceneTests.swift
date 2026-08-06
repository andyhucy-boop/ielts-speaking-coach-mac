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
            "找不到窗口场景。下一步：确认入口仍然是 `Window(\"…\", id: …) { RootView() }`。")

        XCTAssertEqual(
            SourceGuard.occurrences(of: "RootView()", in: code), 1,
            "入口文件里 `RootView()` 出现了不止一次——多一次就多一份 `AppState`，"
                + "也就多一次开机 preflight。下一步：确认没有第二个场景在开第二个根视图。")
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
