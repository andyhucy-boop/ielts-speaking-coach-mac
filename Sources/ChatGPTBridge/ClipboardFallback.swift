import AppKit
import Foundation

public protocol PasteboardAccess: Sendable {
    func readString() -> String?
}

public struct SystemPasteboard: PasteboardAccess {
    public init() {}
    public func readString() -> String? { NSPasteboard.general.string(forType: .string) }
}

public enum ClipboardFallback {
    /// 复盘 JSON 至少这么长。低于此长度多半是用户没选中就按了 ⌘C。
    ///
    /// **40 太松**：光两个定界标记加起来就超过 40 字符，等于没有防护。
    /// 真实的复盘 JSON 含 must_correct / answer_upgrades 等多个数组，实测都在数百字符以上。
    /// 取 200 作为下限：足以挡掉误复制的零碎内容，又不至于误伤特别简短的复盘。
    public static let minimumLength = 200

    public static func readReview(from pasteboard: any PasteboardAccess) throws -> String {
        let raw = (pasteboard.readString() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw BridgeError.elementNotFound("剪贴板是空的。"
                + "下一步：在 ChatGPT 里选中整段复盘（含首尾标记）按 ⌘C，然后重试。")
        }
        guard raw.count >= minimumLength else {
            throw BridgeError.elementNotFound("剪贴板里的内容太短（\(raw.count) 个字符），不像是一份复盘。"
                + "下一步：确认已经选中整段复盘再按 ⌘C，然后重试。")
        }
        return raw
    }
}
