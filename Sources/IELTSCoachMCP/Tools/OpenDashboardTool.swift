import Foundation
import IELTSCoachCore

enum OpenDashboardTool {
    private struct Payload: Encodable {
        let opened: String
        let section: String
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let allowed = CoachRoute.allCases.map(\.rawValue)
        return MCPTool.throwing(
            name: "open_dashboard",
            description: "唤起本机的 IELTS Speaking Coach 应用并跳到指定页面。"
                + "可选页面：\(allowed.joined(separator: "、"))，默认 dashboard（今日训练）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "section": .object([
                        "type": .string("string"),
                        "enum": .array(allowed.map { JSONValue.string($0) }),
                        "description": .string("要打开的页面，默认 dashboard。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let raw = try arguments.optionalChoice("section", allowed: allowed,
                default: CoachRoute.dashboard.rawValue,
                hint: "把 section 改成这几个之一：\(allowed.joined(separator: "、"))。")
            // optionalChoice 已经保证 raw 在 allowed 里，这里再兜一层是因为
            // allowed 与 CoachRoute 万一将来对不上，宁可报错也不要打开一个错的页面。
            guard let route = CoachRoute(rawValue: raw) else {
                throw ToolInputError(message: "无法识别的页面「\(raw)」。"
                    + "下一步：改用 \(allowed.joined(separator: "、")) 之一。")
            }

            try environment.opener.open(route.url)

            return try ToolJSON.text(Payload(
                opened: route.url.absoluteString,
                section: route.rawValue,
                note: "已请求系统打开 IELTS Speaking Coach。若窗口没出现，"
                    + "下一步：确认 .app 已经装好并手动双击打开过一次——"
                    + "系统只有在应用被打开过之后才会登记 ieltscoach:// 这个链接。"))
        }
    }
}
