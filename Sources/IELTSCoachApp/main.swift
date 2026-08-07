import IELTSCoachUI
import SwiftUI

/// **只开一个窗口，因此进程里只有一份 `AppState`。**
///
/// 这里原来用的是 `WindowGroup`，而 macOS 上 `WindowGroup` 默认带「文件 ▸ 新建窗口」（⌘N）。
/// `RootView` 每被 new 一次就自己 new 一个 `AppState`（`RootView.init()`），于是第二个窗口 =
/// 第二份状态 + 第二次完整 preflight——又一次 `NSWorkspace.open` 把 ChatGPT 拉到前台，
/// 又一次最多八秒的无障碍树轮询。而且两个窗口的 `permission`、`loadError`、
/// `permissionSkipped` 互不相通：在一个窗口点了「先跳过」，另一个还挡着；
/// 在一个窗口导完题库，另一个显示的还是旧题库。计划里从头到尾没提过窗口数量。
///
/// 两条修法之间选了 `Window`：
///
/// - **`Window`（选它）**：场景类型上就只有一个窗口，⌘N 根本不会出现，`AppState` 也就
///   不可能出现第二份。改一处，洞就关死了。这个工具本来也没有开两个窗口的用途——
///   它对着的是唯一一个 ChatGPT 实例和唯一一份数据目录（`DataDirectory.resolve()`）。
/// - **保留 `WindowGroup` + 把 `AppState` 提到 App 层下发 + 单独禁掉 ⌘N**：要三处一起改
///   才关得上，任何一处被改回去就漏；而且「两个窗口共用一份状态」这件事只在真的多开时
///   才看得出对不对，不好守。它换来的是「能同时开两个窗口」，而这个工具不需要。
///
/// `AppSceneTests` 扫这个文件，守住这个决定：改回 `WindowGroup` 会当场变红。
struct CoachApp: App {
    var body: some Scene {
        Window("IELTS Speaking Coach", id: "coach-main") { RootView() }
            .defaultSize(width: 1100, height: 720)
            .commands {
                // 把苹果菜单里的「关于 …」换成本应用自己的那一页。
                // 不换的话，点开的是系统默认的小面板：版本、签名、数据目录、
                // 可搬迁检查一样都看不到，而这几样正是把 .app 拷给别人之后要用到的。
                //
                // **关于页放苹果菜单是 Mac 应用的标准位置，不要为它在侧边栏加第十一项**——
                // 侧边栏那十项是产品设计稿定死的（Phase 3 的 `testSidebarHasAllTenItems` 守着）。
                CommandGroup(replacing: .appInfo) { AboutMenuButton() }
            }

        // macOS 的设置窗口（⌘,）。录音开关放这里，不塞进侧边栏——
        // 侧边栏那十项是产品设计稿定死的（ROADMAP 第 1 节），加第十一项会破坏它，
        // 而 ⌘, 打开设置本来就是 Mac 的惯例。
        //
        // 这一页不共享 `AppState`：它自己开一份 `StateStore` 读写 state.json 的 settings，
        // 主窗口那边在开练前会重读一次磁盘（`AppState.makePracticeRunner()`），
        // 所以刚拨的开关下一场就算数。**不要因为这里多了一个场景就去掉那次 reload。**
        Settings { RecordingSettingsScene() }

        // 关于窗口。**它同样不共享主窗口的 `AppState`**（拿不到，也不该拿）：
        // 这是一页只读的信息，自己读一次 `state.json` 就够了，
        // 换成到处传 `AppState` 反而会把主窗口的生命周期和一个偶尔打开的小窗绑死。
        //
        // `id` 走 `AboutWindow.id`，与 `AboutMenuButton` 里那句 `openWindow(id:)` 同一个来源：
        // 写死成两处字符串的话，改错一个字母就是「菜单点了没反应」，
        // 而 `openWindow` 找不到窗口时只在控制台抱怨一句，界面上一点动静都没有。
        Window("关于 IELTS Speaking Coach", id: AboutWindow.id) { AboutView() }
            .windowResizability(.contentSize)
    }
}

CoachApp.main()
