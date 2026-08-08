import IELTSCoachCore
import SwiftUI

/// 挑题列表里的「一栏」：一个 Part，加它底下那一堆题。
///
/// 泛型是为了让**自由选题弹层（`[Question]`）与复训换题（`[TransferCandidate]`）
/// 共用同一份分栏逻辑**。本项目已经反复出现「改了一处、另一处照旧」，
/// 两边各写一份 `filter { $0.part == n }` 迟早会给出两种不同的分栏方式。
public struct QuestionPartSection<Item>: Identifiable {
    public let part: Int
    public let items: [Item]

    public var id: Int { part }

    /// 栏标题。**条数写在标题上**：折起来的时候，用户唯一能据以决定「点不点开」的
    /// 就是这一行；不写条数的话，他得每一栏都点开看一眼。
    public var title: String { QuestionPartSections.title(forPart: part, count: items.count) }

    public init(part: Int, items: [Item]) {
        self.part = part
        self.items = items
    }
}

/// **把挑题列表按 Part 分成几栏。** 用户原话：
/// 「你可以把它做成三栏，Part one 一栏，Part one 一堆，然后 part two 一堆，
/// 然后 part three 一堆。」
///
/// ## 为什么要分栏
///
/// 题库现在 258 道（Part 1 60 / Part 2 99 / Part 3 99），此前是一张平铺列表、
/// Part 1 全排在最前面：想练 Part 3 得滑过 159 条。
///
/// ## 它和那三个「这一场练哪几个 Part」的勾选框是什么关系
///
/// **不是两套筛选，是一件事的两层**，所以不会打架：
///
/// - 勾选框（`PracticePicker.selectableParts`）决定**这一场按哪几段考、列表里列哪些题**，
///   选出来的组合会一路走进 `SessionSetup`；
/// - 这里的分栏只决定**剩下这些题怎么排、先看哪一堆**，一道题都不筛掉，
///   也不影响这一场的考法。
///
/// 关键在于：**一个 Part 都没勾时勾选框什么都没筛掉**，而那正是用户要滑过 159 条的那一档——
/// 分栏补的就是勾选框补不了的那一档。勾了单个 Part 时同样画栏标题
/// （只有一栏、默认展开），所以两种情况下的交互完全一样，不会出现
/// 「不勾一个样、勾一个另一个样」。
///
/// > 注：这段说明从前写的是「分段控件 `PracticePicker.partOptions`」，还提到一颗
/// > 「练完 Part 2 接着练 Part 3」开关。那两样都在同一次改动里被换掉/删掉了
/// > （分段控件 → 三个勾选框；那颗开关的语义现在就是「同时勾上 Part 2 和 Part 3」）。
/// > `partOptions` 今天只存在于另一个类型 `QuestionPartFilter`（题库浏览页），
/// > 与这里无关。
public enum QuestionPartSections {

    // MARK: - 分栏

    /// 按每一条自己的 Part 分栏，Part 小的在前。
    ///
    /// **不认「只有 1/2/3」这件事。** 题库是用户自己导入的，`Question.part` 是个 Int，
    /// 导进来一条 part 是 0 或 4 的题完全可能。写死三栏的话，那几条会**一声不响地
    /// 从列表里消失**——用户在训练题库页数得到 258 道，在挑题弹层里却只看得见 257 道，
    /// 而界面上没有任何异样（铁律 5：禁止静默失败）。
    /// 所以出现过的 Part 一个都不许丢，哪怕它长得很怪。
    ///
    /// 栏内顺序原样保留，**不重排**：顺序归调用方定（自由选题那边是
    /// `TodayViewModel.pickableQuestions`，复训换题那边是 `TransferQuestionPolicy`），
    /// 在这里再排一次的话，展开收起一次列表顺序就变了，用户刚才看到的那一道就找不回来。
    public static func split<Item>(_ items: [Item],
                                   part: (Item) -> Int) -> [QuestionPartSection<Item>] {
        var buckets: [Int: [Item]] = [:]
        for item in items { buckets[part(item), default: []].append(item) }
        return buckets.keys.sorted().map { QuestionPartSection(part: $0, items: buckets[$0] ?? []) }
    }

    /// 栏标题：`Part 1 · 60 道`。
    public static func title(forPart part: Int, count: Int) -> String {
        "Part \(part) · \(count) 道"
    }

    // MARK: - 默认展开哪一栏

    /// 打开时哪几栏是展开的。
    ///
    /// 三条规矩，各自堵一个具体的坑：
    ///
    /// 1. **只有一栏时展开它。** 那时分栏没有在替用户做任何选择，
    ///    折起来只是让他多点一下才看得见题。
    /// 2. **用户已经表达过偏好（分段控件停在 Part 3、或学习计划的重点 Part 是 Part 3）
    ///    就展开那一栏。** 这正是用户抱怨的那一句：「他选了只练 Part 3，
    ///    就该直接看到 Part 3 那一堆，而不是从 Part 1 开始滑。」
    /// 3. **没有偏好时一栏都不展开。** 替他展开哪一栏都是替他做了选择，
    ///    而展开 Part 1 恰好就是原来那个毛病（Part 1 一堆挡在最前面）。
    ///    这时屏幕上是三行带条数的栏标题，一眼看清、一点直达。
    public static func defaultExpandedParts(inSections parts: [Int],
                                            preferredPart: Int?) -> Set<Int> {
        guard parts.count > 1 else { return Set(parts) }
        if let preferredPart, parts.contains(preferredPart) { return [preferredPart] }
        return []
    }

    /// 此刻屏幕上**真的看得见**的那些条目：展开的那几栏里的。
    ///
    /// **挑题那一步必须只认这一份。** 折起来的那几栏里的题人是看不见的，
    /// 拿全量去找的话会出现本项目最忌讳的那种事：用户选中一道题、把那一栏折起来、
    /// 再点「开始练习」，练的是屏幕上一道也看不见的题（和切换 Part 档位时
    /// 必须清掉旧选择是同一条道理）。
    public static func visibleItems<Item>(in sections: [QuestionPartSection<Item>],
                                          expandedParts: Set<Int>) -> [Item] {
        sections.filter { expandedParts.contains($0.part) }.flatMap(\.items)
    }

    // MARK: - 文案

    /// 分栏这件事本身要对用户说的一句话。**只有一栏时返回 nil**——
    /// 那时屏幕上就是一栏题，没有什么要解释的，多一句话是骚扰。
    ///
    /// 说清「发生了什么」（这些题被分成了几栏、每栏标题上有条数）
    /// 和「下一步做什么」（点开你要练的那一栏）。下一步指的那几行栏标题
    /// 就在这句话下面，是真的可以点的（`QuestionPartSectionView` 那个 `DisclosureGroup`）。
    public static func notice<Item>(for sections: [QuestionPartSection<Item>]) -> String? {
        guard sections.count > 1 else { return nil }
        let total = sections.reduce(0) { $0 + $1.items.count }
        return "下面这 \(total) 道题按 Part 分成了 \(sections.count) 栏，"
            + "每一栏的标题上写着它有多少道。"
            + "下一步：点开你要练的那一栏，再从里面挑一道题，不用一路往下滑。"
    }
}

/// 一栏的外壳：可折叠的栏标题（写着这一栏有多少道）+ 底下那一堆。
///
/// **两处挑题列表共用这一个**（自由选题弹层 `PracticeSheet`、复训换题
/// `RetrainingFlowView`）。各写各的话，两处的折叠交互会长成两个样子，
/// 而这不会体现在任何一条测试上。
///
/// 折叠用 `DisclosureGroup`，和「功能升级」页那几条更新记录是同一种控件
/// （`UpgradeView.releaseCard`），不新造一种。
///
/// **不套 `CoachCard`**：栏里每一行题目自己已经带了一张卡（`Palette.card` + 发丝边框），
/// 外面再套一层同色的卡会变成卡中卡，边界糊在一起反而看不出哪一行是可点的。
/// 颜色、字号、间距仍然全部走令牌。
public struct QuestionPartSectionView<Content: View>: View {
    private let title: String
    @Binding private var isExpanded: Bool
    private let content: Content

    public init(title: String, isExpanded: Binding<Bool>,
                @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.sm)
        } label: {
            Text(title)
                .font(Typography.cardTitle)
                // 等宽数字：三栏的条数并排看时宽度不齐会很显眼（规范第 1 节最后一行）。
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Palette.accent)
    }
}

#if DEBUG
#Preview("按 Part 分栏") {
    QuestionPartSectionsPreview()
        .padding(Spacing.xl)
        .background(Palette.canvas)
}

/// 预览专用的壳：`#Preview` 里写不了 `@State`，而折叠要的是一个 `Binding`。
private struct QuestionPartSectionsPreview: View {
    @State private var expanded: Set<Int> = [2]

    private let sections = QuestionPartSections.split(
        [Question(id: "p1", part: 1, topic: "Home", prompt: "Do you live in a house or a flat?"),
         Question(id: "p2", part: 2, topic: "Skills",
                  prompt: "Describe a skill you learned recently."),
         Question(id: "p3", part: 3, topic: "Skills",
                  prompt: "What makes some skills harder to learn than others?")],
        part: { $0.part })

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let notice = QuestionPartSections.notice(for: sections) {
                Text(notice)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sections) { section in
                QuestionPartSectionView(
                    title: section.title,
                    isExpanded: Binding(get: { expanded.contains(section.part) },
                                        set: { on in
                                            if on {
                                                expanded.insert(section.part)
                                            } else {
                                                expanded.remove(section.part)
                                            }
                                        })) {
                    ForEach(section.items) { question in
                        Text(question.prompt)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
            }
        }
    }
}
#endif
