import Foundation

/// 修复 ChatGPT 常见的 JSON 输出瑕疵。尽力而为，永不抛错。
/// 覆盖：单引号字符串、尾随逗号、被截断的结尾。
public enum JSONRepair {
    public static func repair(_ text: String) -> String {
        // 已经合法就原样返回，避免无谓改动
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return text
        }

        var output = ""
        var inString = false
        var stringDelimiter: Character = "\""
        var escaped = false
        var stack: [Character] = []

        for character in text {
            if inString {
                if escaped {
                    output.append(character)
                    escaped = false
                    continue
                }
                if character == "\\" {
                    output.append(character)
                    escaped = true
                    continue
                }
                if character == stringDelimiter {
                    output.append("\"")      // 无论原来是 ' 还是 "，一律输出 "
                    inString = false
                    continue
                }
                // 单引号字符串内部出现的双引号必须转义
                if character == "\"" && stringDelimiter == "'" {
                    output.append("\\\"")
                    continue
                }
                output.append(character)
                continue
            }

            switch character {
            case "\"", "'":
                inString = true
                stringDelimiter = character
                output.append("\"")
            case "{", "[":
                stack.append(character == "{" ? "}" : "]")
                output.append(character)
            case "}", "]":
                if stack.last == character { stack.removeLast() }
                output.append(character)
            default:
                output.append(character)
            }
        }

        // 字符串没闭合就补一个引号
        if inString { output.append("\"") }

        output = removeTrailingCommas(output)

        // 补齐未闭合的括号（处理被截断的输出）
        while let expected = stack.popLast() {
            output = removeTrailingCommas(output)
            output.append(expected)
        }

        return removeTrailingCommas(output)
    }

    /// 删除 `,` 与随后的 `}` 或 `]` 之间只隔着空白的那个逗号。
    private static func removeTrailingCommas(_ text: String) -> String {
        var characters = Array(text)
        var index = characters.count - 1
        while index >= 0 {
            if characters[index] == "}" || characters[index] == "]" {
                var probe = index - 1
                while probe >= 0, characters[probe].isWhitespace { probe -= 1 }
                if probe >= 0, characters[probe] == "," {
                    characters.remove(at: probe)
                    index = probe
                    continue
                }
            }
            index -= 1
        }
        return String(characters)
    }
}
