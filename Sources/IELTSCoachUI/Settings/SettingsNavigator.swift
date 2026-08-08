import Observation

/// 设置窗口当前停在哪一栏。
///
/// 由 App 层持有，同时传给主窗口和设置窗口——所以首页齿轮
/// 可以先 `open(.goals)` 再调 `openSettings()`，窗口打开时就已经在那一栏了。
///
/// **它只管「停在哪一栏」，不管任何设置的值。** 值一律在 `AppState` 里，
/// 那是「两个窗口不可能不同步」的前提（Task 15）。
/// 把某个设置的取值也塞进这里的话，就又多了一份可能和磁盘不一致的状态，
/// 而这次合并要消灭的恰恰是那种东西。
@MainActor
@Observable
public final class SettingsNavigator {
    /// 默认停在「录音」：⌘, 在 Phase 5 打开的就是录音那一页，
    /// 直接按快捷键进来的人看到的东西不该因为这次合并而变。
    public var section: SettingsSection = .recording

    public init() {}

    public func open(_ section: SettingsSection) { self.section = section }
}
