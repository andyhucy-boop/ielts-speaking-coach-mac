import Foundation

public struct ConversationTurn: Equatable, Sendable {
    public let role: String
    public let text: String
    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct ReviewLocation: Equatable, Sendable {
    public let index: Int
    public let rawReport: String
    public let report: JSONValue
}

public enum ReviewParser {
    /// 定界标记：<<<IELTS_REVIEW_JSON>>> / <<<START_OF_JSON>>> / <<<JSON>>>，可带 :request-id 后缀
    private static let markerPattern =
        "<<<(?:IELTS_REVIEW_JSON|START_OF_JSON|JSON)(?::[a-z0-9-]+)?>>>([\\s\\S]*?)"
        + "<<<(?:END_IELTS_REVIEW_JSON|END_OF_JSON|END_JSON)(?::[a-z0-9-]+)?>>>"

    public static func parse(_ text: String, requireAnswerUpgrades: Bool = false) throws -> JSONValue {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []

        if let marked = firstMarkedBlock(in: source) { candidates.append(marked) }
        candidates.append(strippingCodeFence(source))
        if let first = source.firstIndex(of: "{"), let last = source.lastIndex(of: "}"), first < last {
            candidates.append(String(source[first...last]))
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            for attempt in [candidate, JSONRepair.repair(candidate)] {
                guard let parsed = try? JSONValue.decode(from: attempt) else { continue }
                let normalized = normalize(parsed)
                if satisfies(normalized, requireAnswerUpgrades: requireAnswerUpgrades) { return normalized }
            }
        }

        throw requireAnswerUpgrades
            ? CoachError.reviewIncomplete("ChatGPT已经回复，但复盘缺少完整的回答建议。请点「补生成复盘报告」重新生成。")
            : CoachError.reviewNotFound("ChatGPT已经回复，但没有返回可识别的标准复盘JSON。请点「补生成复盘报告」重新生成。")
    }

    public static func findAfterRequest(turns: [ConversationTurn], requestID: String,
                                        requireAnswerUpgrades: Bool = false) -> ReviewLocation? {
        let token = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        guard let requestIndex = turns.lastIndex(where: {
            $0.role == "user" && $0.text.contains(token)
        }) else { return nil }

        let assistantTurns = turns.enumerated()
            .filter { $0.offset > requestIndex && $0.element.role == "assistant" && !$0.element.text.isEmpty }

        // 从最新往回找第一条能解析成功的
        for entry in assistantTurns.reversed() {
            if let report = try? parse(entry.element.text, requireAnswerUpgrades: requireAnswerUpgrades) {
                return ReviewLocation(index: entry.offset, rawReport: entry.element.text, report: report)
            }
        }

        // 复盘被拆成多条消息时，拼起来再试
        if assistantTurns.count > 1 {
            let joined = assistantTurns.map(\.element.text).joined(separator: "\n")
            if let report = try? parse(joined, requireAnswerUpgrades: requireAnswerUpgrades) {
                return ReviewLocation(index: assistantTurns[0].offset, rawReport: joined, report: report)
            }
        }
        return nil
    }

    public static func findExisting(turns: [ConversationTurn],
                                    requireAnswerUpgrades: Bool = false) -> ReviewLocation? {
        for (index, turn) in turns.enumerated().reversed() where turn.role == "assistant" {
            if let report = try? parse(turn.text, requireAnswerUpgrades: requireAnswerUpgrades) {
                return ReviewLocation(index: index, rawReport: turn.text, report: report)
            }
        }
        return nil
    }

    // MARK: - 私有

    private static func firstMarkedBlock(in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippingCodeFence(_ source: String) -> String {
        var text = source
        for prefix in ["```json", "```JSON", "```"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// answer_upgrades 有时是单个对象而非数组，统一成数组。
    private static func normalize(_ value: JSONValue) -> JSONValue {
        guard var dict = value.objectValue, let upgrades = dict["answer_upgrades"] else { return value }
        switch upgrades {
        case .array: return value
        case .object: dict["answer_upgrades"] = .array([upgrades])
        default: dict["answer_upgrades"] = .array([])
        }
        return .object(dict)
    }

    private static func looksLikeReview(_ value: JSONValue) -> Bool {
        guard value.objectValue != nil else { return false }
        if value["must_correct"]?.arrayValue != nil { return true }
        if value["natural_upgrades"]?.arrayValue != nil { return true }
        if value["logic_feedback"]?.arrayValue != nil { return true }
        if let target = value["priority_target"], target != .null { return true }
        return false
    }

    private static func satisfies(_ value: JSONValue, requireAnswerUpgrades: Bool) -> Bool {
        guard looksLikeReview(value) else { return false }
        guard requireAnswerUpgrades else { return true }
        guard let upgrades = value["answer_upgrades"]?.arrayValue else { return false }
        return upgrades.contains { item in
            guard item.objectValue != nil else { return false }
            let original = item["original_answer"] ?? .null
            let revised = item["revised_answer"] ?? .null
            return !original.isBlank && !revised.isBlank
        }
    }
}
