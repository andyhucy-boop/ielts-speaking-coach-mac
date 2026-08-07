import Foundation
import IELTSCoachCore

/// 参数不合法。会被 `MCPTool.throwing` 转成 `isError` 结果，模型能读到并自我纠正。
/// `message` 必须同时说清「哪里不对」和「下一步怎么改」。
public struct ToolInputError: Error, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

/// 读 tool 的 arguments。7 个 tool 共用这一层，
/// 免得同一种错误出现 7 种措辞，其中总有一两处忘了写「下一步」。
public struct ToolArguments {
    public let value: JSONValue

    public init(_ value: JSONValue) { self.value = value }

    public subscript(key: String) -> JSONValue? { value[key] }

    public func requiredString(_ key: String, trimmed: Bool = true, hint: String) throws -> String {
        guard let raw = value[key], raw != .null else {
            throw ToolInputError(message: "缺少必填参数「\(key)」。下一步：\(hint)")
        }
        guard let text = raw.stringValue else {
            throw ToolInputError(message: "参数「\(key)」必须是字符串。下一步：\(hint)")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolInputError(message: "参数「\(key)」是空的。下一步：\(hint)")
        }
        return trimmed ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }

    /// 缺失、null、空白一律当作「没传」。
    public func optionalString(_ key: String) -> String? {
        guard let text = value[key]?.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// **越界报错，不夹紧。** 夹紧等于「调用方以为自己传的是 0，拿到的却是 1 的行为，
    /// 而且没有任何提示」——本项目反复消灭的正是这类静默失败。
    public func optionalInt(_ key: String, in range: ClosedRange<Int>,
                            default fallback: Int, hint: String) throws -> Int {
        guard let raw = value[key], raw != .null else { return fallback }
        guard let number = raw.intValue else {
            throw ToolInputError(message: "参数「\(key)」必须是整数。下一步：\(hint)")
        }
        guard range.contains(number) else {
            throw ToolInputError(message:
                "参数「\(key)」必须在 \(range.lowerBound)–\(range.upperBound) 之间，收到的是 \(number)。"
                + "下一步：\(hint)")
        }
        return number
    }

    /// 同上：不认识的取值报错，不悄悄退回默认值。
    public func optionalChoice(_ key: String, allowed: [String],
                               default fallback: String, hint: String) throws -> String {
        guard let raw = value[key], raw != .null else { return fallback }
        guard let text = raw.stringValue else {
            throw ToolInputError(message: "参数「\(key)」必须是字符串。下一步：\(hint)")
        }
        guard allowed.contains(text) else {
            throw ToolInputError(message:
                "参数「\(key)」的取值「\(text)」不认识，只能是 \(allowed.joined(separator: "、"))。"
                + "下一步：\(hint)")
        }
        return text
    }
}
