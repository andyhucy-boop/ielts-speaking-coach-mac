import Foundation
import IELTSCoachCore

/// 「用户偏好哪条练习路线」这件事在 Core 与 UI 之间的唯一翻译层。
///
/// `CoachSettings.defaultRoute` 存的是字符串而不是 `PracticeRoute`：
/// `PracticeRoute` 定义在 `IELTSCoachUI` 里，而 **Core 不允许依赖 UI**（见计划的 Global Constraints）。
/// 也就是说这两个模块之间靠一个约定好的字符串对齐，**没有任何类型能替我们检查它**——
/// 默认值写错一个字母，界面会不声不响地退回到别的路线，一条报错都不会有。
/// `PracticeRoutePreferenceTests.testCoreDefaultMatchesTheUIRoute` 就是那道唯一的闸。
public enum PracticeRoutePreference {
    /// ROADMAP 第 5 节：练习路线默认「按计划练今天」。
    public static let fallback: PracticeRoute = .planToday

    /// state.json 里存的是 `PracticeRoute` 的 rawValue。
    ///
    /// 认不出来时退回默认路线，**不能返回 nil 让界面空着**——
    /// 手改坏的 state.json、别的版本写进去的路线名都会走到这里，
    /// 而用户该看到的是一个能用的默认值，不是一片空白。
    public static func route(fromSettings raw: String) -> PracticeRoute {
        PracticeRoute(rawValue: raw) ?? fallback
    }

    /// 写回 state.json 时用的字符串。与上面那个函数成对，别在别处直接写 `route.rawValue`——
    /// 存与读只有一处定义，才不会出现「存的是这个、读的是那个」。
    public static func rawValue(for route: PracticeRoute) -> String { route.rawValue }
}

/// 开练时那两个用户可选项（spec 3.1）：考官何时给反馈、Part 2 的一分钟准备怎么处理。
///
/// 界面从设置里取（`init(settings:)`），测试里可以直接构造。
/// 两个默认值与 `CoachSettings` 里写的是同一套（ROADMAP 第 5 节：全程零反馈 + 一分钟倒计时）。
public struct RouteDefaults: Equatable, Sendable {
    public let feedbackTiming: FeedbackTiming
    public let part2PrepMode: Part2PrepMode

    public init(feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }

    public init(settings: CoachSettings) {
        self.init(feedbackTiming: settings.feedbackTiming,
                  part2PrepMode: settings.part2PrepMode)
    }
}

/// 今日训练页上「自由选题」和「随机抽题」合成一张卡片。
///
/// 抽成纯函数而不是在视图里写 `filter`：这段决定的是**用户看得见几张卡**，
/// 而视图里的一句 `filter` 没有任何测试管得住。
public enum PracticeRouteMerge {

    /// 合并之后要显示的路线列表。
    ///
    /// 两条选题路线只留一条：**留用户偏好的那一条**，因为进去之后弹层就停在它对应的档
    /// （偏好是「随机抽题」就直接停在随机那一档，不用再点一下）。
    /// 偏好不是这两条中的任何一条时，留先出现的那一条——`availableRoutes` 已经排过序，
    /// 那个顺序本身就是「最该先看的排前面」。
    ///
    /// **顺序不许重排。** 排序是解析器的事（默认路线排最前，而排最前的那张就是这一页
    /// 唯一的主行动）。这里只删，不动位置。
    public static func collapsePickRoutes(_ routes: [PracticeRoute],
                                          preferring preferred: PracticeRoute) -> [PracticeRoute] {
        // 留哪一条：偏好的那条**且它这次真的可用**，否则退回列表里现有的第一条。
        // 退回这一步不能省：偏好的那条被解析器筛掉时若直接按偏好去留，
        // 这张卡片会整个消失——而用户明明有题库，「挑一道题练」永远是可用的。
        //
        // 一个表达式写完。原来分成 `keep` / `guard` / `survivor` 三步，
        // 而「偏好不是选题路线」那一支算出来的 `keep` 必然来自 `routes`，
        // 那一步的 `routes.contains` 恒真——三步里有一步是死逻辑。
        let survivor = preferred.isPickEntry && routes.contains(preferred)
            ? preferred
            : routes.first(where: \.isPickEntry)
        // `survivor` 为 nil（列表里一条选题路线都没有）时下面这句原样返回。
        return routes.filter { !$0.isPickEntry || $0 == survivor }
    }
}
