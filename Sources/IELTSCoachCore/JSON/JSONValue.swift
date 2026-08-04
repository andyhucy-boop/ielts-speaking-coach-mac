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
            throw CoachError.invalidReviewText("复盘文本不是有效的 UTF-8 编码。请重新复制一次。")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
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

    /// 用于「必须有非空文本」的校验：非字符串或去空白后为空都算空。
    public var isBlank: Bool {
        (stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
