import Foundation
import IELTSCoachCore

/// 开练之前那一步：**先决定这一场练 Part 几，再从那个 Part 里挑一道题。**
///
/// ## 为什么这一步必须存在
///
/// 用户原话：「首先应该可以选择是训练 part one part two 还是 part three，
/// 这样方便区分开来选。」
///
/// 在这之前，「从题库自由选题」弹出来的是一张**平铺的全库列表**——重建模之后仍有
/// 258 道题，重建模之前是 1265 道。想练 Part 2 就得一直往下滚，滚过 60 个 Part 1 话题。
/// 三个 Part 是三种完全不同的题型（Part 1 日常问答、Part 2 两分钟独白、Part 3 抽象讨论），
/// 一次练习只可能是其中一种，把它们混在一张列表里等于让用户每次都做一次无谓的筛选。
///
/// ## 它与「学习计划」页那个「重点 Part」是什么关系
///
/// **两者管的不是同一件事，所以不会打架：**
///
/// - 学习计划页的「重点 Part」决定**排计划时挑哪些题**（`PlanScope.select`），
///   它影响的是「按计划练今天」那条路线每天给你哪几道；
/// - 这里的 Part 选择决定**这一次自由选题时列出哪些题**，只影响眼前这一场。
///
/// 为了让两者看起来是一件事的两个层次而不是两套设置，这里的**默认值跟着计划的重点 Part 走**
/// （`defaultPart(forPlanFocus:)`），并且当场用一句话说清它是从哪儿来的、怎么改
/// （`planFocusNotice(for:)`）。用户切到别的 Part 时**不会**去改学习计划——
/// 一次临时选择偷偷改掉一份长期计划，是最让人不信任的那种行为。
public struct PracticePicker: Sendable {

    /// 「全部」这一档。**用 0 而不是 `Int?`。**
    ///
    /// 理由与 `QuestionBankView.partSelection` 那一处完全相同：`Picker` 的 Optional tag
    /// 极容易写成不匹配的类型（`.tag(1)` 是 `Int`，而 selection 是 `Int?`），
    /// 一旦对不上，分段控件看着能点、列表却纹丝不动——编译器不会说一个字。
    public static let allParts = 0

    /// 分段控件上的四档，顺序固定。
    public static let partOptions = [allParts, 1, 2, 3]

    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    // MARK: - 筛

    /// 这个 Part 下可以练的题。`allParts` 时返回全部。
    ///
    /// **顺序与 `TodayViewModel.pickableQuestions` 保持一致**（先按 Part、再按题库原有顺序），
    /// 这里只做筛选不重排：切一下 Part 又切回来，列表顺序变了的话，
    /// 用户刚才看到的那一道就找不回来了。
    public func questions(inPart part: Int) -> [Question] {
        guard part != Self.allParts else { return questions }
        return questions.filter { $0.part == part }
    }

    public func count(inPart part: Int) -> Int { questions(inPart: part).count }

    // MARK: - 文案

    /// 分段控件上那一格写什么。**保持短**：四格挤在一行里，写长了会被截断。
    public static func segmentTitle(forPart part: Int) -> String {
        part == allParts ? "全部" : "Part \(part)"
    }

    /// 分段控件下面那一行：每个 Part 各有多少道题。
    ///
    /// **不能省。** 分段控件本身只有四个词，用户点之前不知道 Part 2 底下有没有题；
    /// 点进去发现是空的，再点回来，是一次白跑。
    public var countsLine: String {
        let parts = [1, 2, 3]
            .map { "Part \($0) \(count(inPart: $0)) 道" }
            .joined(separator: " · ")
        return "题库里共 \(questions.count) 道：\(parts)。"
    }

    /// 当前这一档筛出来多少道。列表上方那一句。
    ///
    /// 「全部」这一档说的是**分栏**而不是「排好序」：列表已经按 Part 折成几栏了
    /// （`QuestionPartSections`），还写「按 Part 1 → 2 → 3 排好序」的话，
    /// 用户会以为下面是一张一路滑到底的长列表，而屏幕上其实是三行栏标题。
    public func selectionSummary(forPart part: Int) -> String {
        guard part != Self.allParts else {
            return "现在列出的是全部 \(questions.count) 道题，按 Part 分栏。"
        }
        return "现在只列 Part \(part) 的 \(count(inPart: part)) 道题。"
    }

    // MARK: - 「练完 Part 2 接着练 Part 3」

    /// 那颗开关的标题。**它就是用户当初要的那个功能**，用户原话：
    /// 「你可以加一个功能，是否同时练习 part2 和 part3。」
    ///
    /// 标题写在这里而不是只写在视图里，是为了让「界面上真有这颗开关」这件事
    /// 有一处可被测试引用的出处；视图那边 `Toggle(PracticePicker.linkPart3Title)` 直接用它。
    public static let linkPart3Title = "练完 Part 2 接着练 Part 3"

    /// 开关旁边那句解释。说清打开之后这一场会变成什么样、以及它为什么值得打开。
    public static let linkPart3Hint = "真实考试里 Part 3 就是紧接着 Part 2 的同一个话题问下来的。"
        + "打开之后这一场会先做 cue card 的两分钟陈述，再直接进入 Part 3 讨论，中间不停。"
        + "关着就只做 Part 2。"

    /// 这颗开关只在 Part 2 那一档出现——**其余档位一律不显示，也不生效**。
    ///
    /// 这不是偷懒，是在堵一个「屏幕上写着一回事、实际发生另一回事」的口子：
    /// 「全部」那一档里既有 Part 1 也有 Part 3 的题，开关亮着而用户挑了一道 Part 1，
    /// `FocusPart.forSession` 会照常回落成 Part 1（一张 Part 1 话题卡做不出两分钟长陈述），
    /// 于是开关开着、这一场却和它毫无关系。不显示就不会有这种矛盾。
    public static func showsLinkPart3(forPart part: Int) -> Bool { part == 2 }

    /// 这一场最终按哪套考法跑。`nil` = 按题目自身的 Part 走。
    ///
    /// 结论只交给 `FocusPart.forSession` 去落地，这里只负责把界面上的两个状态
    ///（当前档位 + 开关）翻译成一个 `FocusPart?`。
    public static func mode(forPart part: Int, linksPart3: Bool) -> FocusPart? {
        showsLinkPart3(forPart: part) && linksPart3 ? .part2And3 : nil
    }

    /// 打开弹层时那颗开关默认是开还是关。跟着学习计划的「重点 Part」走，理由与
    /// `defaultPart(forPlanFocus:)` 完全一样：两处 Part 选择要像同一件事的两个层次。
    public static func defaultLinksPart3(forPlanFocus focusPart: FocusPart?) -> Bool {
        focusPart == .part2And3
    }

    /// 这一档下一道题都没有时说什么。有题时返回 nil。
    ///
    /// 三样一个不少：说明现状、说明下一步、下一步指向的控件在这张弹层上真实存在
    /// （那颗分段控件就在这句话上面）。
    public func emptyNotice(forPart part: Int) -> String? {
        guard part != Self.allParts, count(inPart: part) == 0 else { return nil }
        guard !questions.isEmpty else {
            return "题库还是空的，哪个 Part 都没有题。"
                + "下一步：关掉这个窗口，到「训练题库」页导入你的题库文件。"
        }
        return "题库里共有 \(questions.count) 道题，但没有一道属于 Part \(part)。"
            + "下一步：点上面那排按钮切回「全部」看看现有的题，"
            + "或到「训练题库」页导入一份包含 Part \(part) 的题库文件。"
    }

    // MARK: - 默认停在哪一档

    /// 打开弹层时默认选中哪一档。跟着学习计划的「重点 Part」走；
    /// 没有计划、或者计划是全真模考时停在「全部」。
    public static func defaultPart(forPlanFocus focusPart: FocusPart?) -> Int {
        switch focusPart {
        case .part1: return 1
        case .part2: return 2
        case .part3: return 3
        // 「Part 2 + Part 3 连着练」排的就是 Part 2 那批 cue card（`PlanScope.select`），
        // 所以档位停在 Part 2；那一档的差别由那颗开关表达，默认跟着计划打开
        //（`defaultLinksPart3(forPlanFocus:)`）。
        case .part2And3: return 2
        case .fullMock, nil: return allParts
        }
    }

    /// 默认档位是从学习计划带过来的时候，得说一句它是从哪儿来的、改了会不会影响计划。
    ///
    /// 不说的话，用户打开弹层看到只有 Part 2 的题，会以为题库里别的 Part 没了。
    /// 全真模考 / 没有计划时返回 nil——那时默认就是「全部」，没有什么要解释的。
    public static func planFocusNotice(for focusPart: FocusPart?) -> String? {
        guard let focusPart, focusPart != .fullMock else { return nil }
        var notice = "默认停在 \(PlanScope.label(for: focusPart))，因为你在「学习计划」页"
            + "把重点 Part 设成了它。"
        // 计划选的是「连着练」时，档位停在 Part 2 而那颗开关也替他打开了。
        // 不说这一句的话，用户看到的是「Part 2」这一档，会以为计划里那个选择没生效。
        if focusPart == .part2And3 {
            notice += "题目列的是 Part 2 的 cue card，下面那个「\(linkPart3Title)」也已经替你打开。"
        }
        return notice + "下一步：想练别的 Part，点上面那排按钮直接切——"
            + "这只影响眼前这一场，学习计划不会跟着改。"
    }
}
