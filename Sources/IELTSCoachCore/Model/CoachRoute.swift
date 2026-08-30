import Foundation

/// App 的深链接路由：`ieltscoach://<route>`。
///
/// **放在 Core 是因为两个进程都要用它**：MCP server 用它拼 URL（open_dashboard），
/// App 用它解析收到的 URL。各写一份的话，改了一边忘了另一边，链接就静默失效——
/// 而链接打不开时 macOS 不给任何提示，用户只会觉得「点了没反应」。
///
/// **侧边栏十项每一项都有一条路由。** 2026-08-30 之前「功能升级」「问题反馈」
/// 刻意缺席（理由是「从外部唤起这两页没有意义」），但那条理由站不住：
/// 链接打不开时给出的提示会把认得的页面逐个列出来，而那份列表里没有这两页，
/// 用户读完只会以为自己记错了名字；MCP 的 `open_dashboard` 同样少两页。
public enum CoachRoute: String, CaseIterable, Sendable {
    // 侧边栏十项**每一项都要有一条**（`dashboard` 是 `today` 的别名）。
    // 少了哪一项，那一页就既不能用深链接打开、也不在 MCP 的 `open_dashboard` 里——
    // 而这一条链接打不开时给出的那句提示会把「认得的页面」逐个列出来，
    // 列表里没有的那两页，用户读完只会以为自己记错了名字。
    case dashboard, today, questions, plan, retraining, reviews, history, issues, vocabulary
    case upgrade, feedback

    public static let scheme = "ieltscoach"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        guard let url = components.url else {
            // rawValue 全是小写 ASCII 字母，走不到这里。真走到了说明有人加了
            // 带空格或非 ASCII 的 case——那种情况必须当场炸给开发者看，
            // 不能返回一个打不开的 URL 让用户去猜为什么没反应。
            preconditionFailure(
                "CoachRoute.\(rawValue) 拼不出合法 URL。下一步：把这个 case 的 rawValue 改成纯小写 ASCII 字母。")
        }
        return url
    }

    /// 解析一条深链接。scheme 不对、页面名不认识都返回 nil，由调用方给中文提示。
    public static func parse(_ url: URL) -> CoachRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        // 两种写法都要认：ieltscoach://reviews（host 形式）与 ieltscoach:reviews（路径形式）。
        let candidate = (url.host(percentEncoded: false) ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return CoachRoute(rawValue: candidate)
    }
}
