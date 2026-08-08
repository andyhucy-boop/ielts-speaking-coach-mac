import Foundation

/// 「训练题库」页那排**单选**的 Part 筛选：全部 / Part 1 / Part 2 / Part 3。
///
/// ## 为什么它是自己一份，不再借开练弹层那一份
///
/// 这两处从前共用 `PracticePicker` 的档位常量，理由是「两处『按 Part 筛』别长成两个样子」。
/// 多选 Part 之后这个理由不成立了：**它们已经是两个不同的控件，管的是两件不同的事**——
///
/// - 这一页是**浏览**：一次看一个 Part 的题，或者看全部。单选，天然只有四档。
/// - 开练弹层是**决定这一场考几段**：可以同时勾 Part 1 和 Part 2，勾了就连着练。
///
/// 硬把两者绑在同一份常量上，只会让其中一处每次都要绕开另一处的语义
///（比如这一页得解释「勾多个」在浏览语境下是什么意思——什么也不是）。
public enum QuestionPartFilter {

    /// 「全部」这一档。**用 0 而不是 `Int?`。**
    ///
    /// `Picker` 的 Optional tag 极容易写成不匹配的类型（`.tag(1)` 是 `Int`，
    /// 而 selection 是 `Int?`），一旦对不上，分段控件看着能点、列表却纹丝不动——
    /// 编译器不会说一个字。
    public static let allParts = 0

    /// 分段控件上的四档，顺序固定。
    public static let partOptions = [allParts, 1, 2, 3]

    /// 分段控件上那一格写什么。**保持短**：四格挤在一行里，写长了会被截断。
    public static func segmentTitle(forPart part: Int) -> String {
        part == allParts ? "全部" : "Part \(part)"
    }
}
