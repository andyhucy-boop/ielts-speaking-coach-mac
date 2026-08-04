import Foundation

/// 练习的 Part 选择。用 String raw value 与上游 state.json 保持兼容。
public enum FocusPart: String, Codable, Equatable, Sendable, CaseIterable {
    case part1 = "Part 1"
    case part2 = "Part 2"
    case part3 = "Part 3"
    case fullMock = "full mock"
}
