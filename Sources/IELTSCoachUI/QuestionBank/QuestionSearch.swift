import Foundation
import IELTSCoachCore

/// **按关键词找题。** 题库现在 258 道，Part 2 一栏就有 99 条。
///
/// 在这之前**整个 App 一个文本输入框都没有**：题库页只有一个 Part 四档单选，
/// 想找「上次那道讲书的题」或者「hometown 那一组」，只能一条条往下滑。
/// 开练弹层里更难受——那个小窗口里平铺滑 99 行。
///
/// ## 搜哪几个字段
///
/// 题干、话题、以及**每一条参考问句**。参考问句必须算进来：题库重建模之后，
/// Part 1 的题干就是话题名（「Borrowing」），他记得的那句
/// 「Do you like to lend things to others?」只存在于 `followups` 里——
/// 不搜它的话，他印象最深的那句话反而搜不到。
///
/// ## 大小写与空白
///
/// 一律不敏感（`localizedCaseInsensitiveContains`），首尾空白去掉。
/// 中文没有大小写，英文题干里 `Borrowing` / `borrowing` 都得命中。
/// **不做分词、不做模糊匹配**：一个错字就搜不到东西，好过搜出一堆不相干的题
/// 让他以为题库乱了。
public enum QuestionSearch {

    /// 关键词筛过之后剩下的题。**关键词为空时原样返回**（连顺序都不动）。
    public static func filter(_ questions: [Question], keyword: String) -> [Question] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return questions }
        return questions.filter { matches($0, needle: needle) }
    }

    private static func matches(_ question: Question, needle: String) -> Bool {
        if question.prompt.localizedCaseInsensitiveContains(needle) { return true }
        if question.topic.localizedCaseInsensitiveContains(needle) { return true }
        return question.followups.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// 搜不到时说什么。**有结果时返回 nil。**
    ///
    /// 三样一个不少：现状（搜的是什么、在多少道里搜的）、下一步、
    /// 而下一步指的那个搜索框就在这句话上面，真实存在。
    public static func emptyNotice(keyword: String, searchedCount: Int) -> String? {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return "在这 \(searchedCount) 道题里没找到含「\(needle)」的。"
            + "下一步：把关键词改短一点（只打一两个词），或者清空上面那个搜索框看全部题目。"
    }

    /// 搜索框上的提示语。**给的是能照着打的东西**，不是「搜索」两个字：
    /// 一个不知道能搜什么的人不会去用它。
    public static let placeholder = "搜题目、话题或参考问句，例如 borrowing"
}
