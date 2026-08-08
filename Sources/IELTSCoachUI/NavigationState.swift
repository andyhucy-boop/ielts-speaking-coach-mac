import Foundation
import Observation

/// 侧边栏选中项与跨页跳转意图。
///
/// **单独成类是为了能测**：`AppState` 的 init 会读磁盘、探辅助功能权限，
/// 在单元测试里既慢又依赖环境；导航是纯内存状态，拆出来就能直接测。
///
/// **也是为了只有一份。** 选中页原来是 `RootView` 自己的 `@State`，
/// 于是别的页面想跳转就只能靠一路往下传的回调；而回调传不到的地方
/// （今日训练页上「复训一个旧问题」那张卡片）就只能自己另开一条路，
/// 两份状态一走岔，按钮点下去屏幕不会有任何变化——用户会以为它坏了。
@MainActor
@Observable
public final class NavigationState {
    public var selection: SidebarItem = .today

    /// 从别的页面跳过来时要预先选中的复训目标（`RetrainingTarget.id`）。
    public private(set) var pendingRetrainingTargetID: String?

    public init() {}

    public func openRetrainingCenter(preselecting targetID: String?) {
        pendingRetrainingTargetID = targetID
        selection = .retraining
    }

    /// 取出并清空。**必须只生效一次**：不清空的话，用户在复训中心点开别的目标，
    /// 每次重绘都会被弹回最初那个目标，他会以为界面点不动。
    public func consumePendingRetrainingTarget() -> String? {
        defer { pendingRetrainingTargetID = nil }
        return pendingRetrainingTargetID
    }
}
