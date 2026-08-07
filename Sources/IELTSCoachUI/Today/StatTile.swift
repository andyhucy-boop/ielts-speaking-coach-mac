import Foundation

/// 首页的一格统计。
///
/// 把四格做成数据而不是散在视图里的字符串，有两个原因：
/// 一是 `value` 集中在一处，视图只要对它统一加 `.monospacedDigit()`，
/// 数值变化时整行就不会横向抖动（DESIGN-SYSTEM 第 6 节最后一条）；
/// 二是文案可测——`HomeStatsTests` 里那条「绝不预测分数」的守卫
/// 就是把这些字符串扫一遍。
public struct StatTile: Equatable, Identifiable, Sendable {
    /// 「本周训练」那一格的 id。
    ///
    /// 单独立个常量而不是两处各写一个 `"week"`：视图要在这一格里额外画一根进度条，
    /// 靠这个 id 认人。两处各写一份字面量的话，改了一处另一处会安静地不再匹配——
    /// 进度条就此消失，编译器和测试都不会吭声。
    public static let weekID = "week"

    public let id: String
    /// 这格是什么，例如「本周训练」。
    public let caption: String
    /// 数字本身，例如 "3/5"。**视图必须对它用 .monospacedDigit()**。
    public let value: String
    /// 单位，例如「次」「分钟」「个」。
    public let unit: String
    /// 一句话解释这个数字，并告诉用户下一步做什么。不允许为空。
    public let footnote: String

    public init(id: String, caption: String, value: String, unit: String, footnote: String) {
        self.id = id; self.caption = caption; self.value = value
        self.unit = unit; self.footnote = footnote
    }
}
