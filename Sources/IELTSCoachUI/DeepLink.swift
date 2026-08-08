import Foundation
import IELTSCoachCore

public enum DeepLinkResolution: Equatable, Sendable {
    case open(SidebarItem)
    /// 无法处理的链接。文案必须说清「发生了什么」与「下一步做什么」——
    /// 点了链接、窗口跳出来却毫无反应，用户只会以为程序坏了。
    case rejected(String)
}

public enum DeepLinkResolver {
    public static func resolve(_ url: URL) -> DeepLinkResolution {
        guard url.scheme?.lowercased() == CoachRoute.scheme else {
            return .rejected("这个链接不是本应用能打开的：\(url.absoluteString)。"
                + "下一步：本应用只认 \(CoachRoute.scheme):// 开头的链接，"
                + "例如 \(CoachRoute.dashboard.url.absoluteString)。")
        }
        guard let route = CoachRoute.parse(url) else {
            let page = url.host(percentEncoded: false) ?? url.path
            return .rejected("链接里的页面名「\(page)」不认识。"
                + "下一步：改用这些之一——\(CoachRoute.allCases.map(\.rawValue).joined(separator: "、"))。")
        }
        return .open(SidebarItem(route: route))
    }
}
