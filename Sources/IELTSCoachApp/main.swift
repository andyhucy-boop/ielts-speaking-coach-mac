import IELTSCoachUI
import SwiftUI

/// **`AppState` 建在这一层，而且整个进程只有这一份。**
///
/// 设置窗口（⌘,）是另一个 Scene，它和主窗口只有共用同一个实例才可能同步；
/// 各建各的话，「在设置窗口改了、主窗口立刻看到」就只能靠事后刷新去补，
/// 而那种补法漏一处就是一个在本机永远复现不了的 bug——你改完总会顺手看一眼那个窗口。
///
/// 主窗口用的是 `Window` 而不是 `WindowGroup`（Phase 8 起就是这样，理由如下）：
/// macOS 上 `WindowGroup` 默认带「文件 ▸ 新建窗口」（⌘N），开第二个窗口就是第二次完整
/// preflight（又一次 `NSWorkspace.open` 把 ChatGPT 拉到前台、又一次最多八秒的无障碍树轮询），
/// 而这个工具本来也没有开两个窗口的用途——它对着的是唯一一个 ChatGPT 实例和唯一一份数据目录。
///
/// Phase 10 Task 16 的计划给的示例代码写的是 `WindowGroup`；**这里刻意保留 `Window`**：
/// 状态提到 App 层之后，`WindowGroup` 的那个洞（每个窗口一份 `AppState`）确实堵上了，
/// 但「⌘N 会开出第二个窗口」这件事本身仍然没有用处，而 `Window` 一并把它关死。
/// `AppSceneTests` 扫这个文件，守着这个决定。
struct CoachApp: App {
    @State private var app = AppState()
    /// 只管「设置窗口停在哪一栏」，不管任何设置的值。
    @State private var settingsNavigator = SettingsNavigator()

    var body: some Scene {
        Window("IELTS Speaking Coach", id: "coach-main") {
            RootView(app: app, navigator: settingsNavigator)
        }
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

        // macOS 的设置窗口（⌘,）。四个分区：录音、训练目标、练习偏好、数据与隐私。
        // Phase 5 只放了录音；Phase 10 Task 16 把散在首页齿轮、学习计划页页尾和
        // 训练记录页页头的另外几项也收进来了，用户不用再猜某个设置藏在哪一页。
        //
        // **它和主窗口拿的是同一个 `app`**，所以在这里改完，主窗口那一格当场就变。
        Settings {
            SettingsWindowView(app: app, navigator: settingsNavigator)
        }

        // 关于窗口。**它同样不共享主窗口的 `AppState`**（不需要，也不该要）：
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
