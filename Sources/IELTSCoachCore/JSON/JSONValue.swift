import Foundation

/// 动态 JSON 值。复盘报告的结构由 ChatGPT 生成，不能用固定 struct 表达。
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法识别的 JSON 值")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

extension JSONValue {
    public static func decode(from text: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw CoachError.invalidReviewText(
                "复盘文本不是有效的 UTF-8 编码。下一步：重新复制一次 ChatGPT 的输出后重试。")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            // 真正高频的失败在这里，不是上面那个 UTF-8 分支：
            // ChatGPT 的输出可能被截断、或在 JSON 前后混入解释性文字。
            // 原生 DecodingError 是英文且不含处置建议，必须包装。
            throw CoachError.invalidReviewText(
                "这段文本不是合法的 JSON，可能是内容被截断，或 JSON 前后混入了额外文字。"
                + "下一步：确认已完整复制 ChatGPT 输出的整个复盘块（含首尾标记）后重试。")
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let items) = self else { return nil }
        return items
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let dict) = self else { return nil }
        return dict
    }

    public var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    public var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    /// 只接受整数。3.5 不会被截断成 3——静默截断意味着调用方传了 3.5、
    /// 拿到的却是 3 的行为，而且没有任何提示。
    ///
    /// 用 `Int(exactly:)` 一步做完「是整数」与「在 Int 范围内」两件事，而不是
    /// 「先 `rounded() == value`、再 `value <= Double(Int.max)`、最后 `Int(value)`」：
    /// `Double(Int.max)` 实际是 2^63，比 `Int.max` 大 1，那种写法在参数恰好是 2^63 时
    /// 会通过范围判断、然后在转换处崩溃——MCP server 一崩，stdio 连接就断了，
    /// 客户端只会显示「服务器没响应」，用户拿不到任何线索。
    public var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(exactly: value)
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// 用于「必须有非空文本」的校验：非字符串或去空白后为空都算空。
    public var isBlank: Bool {
        (stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
