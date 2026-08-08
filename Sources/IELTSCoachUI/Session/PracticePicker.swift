import Foundation
import IELTSCoachCore

/// 开练之前那一步：**先勾这一场练哪几个 Part，再从里面挑一道题。**
///
/// ## 从「四选一」到「任意组合」
///
/// 用户第一次的要求是：「首先应该可以选择是训练 part one part two 还是 part three，
/// 这样方便区分开来选。」——做成了一排四格分段控件（全部 / Part 1 / Part 2 / Part 3），
/// 外加一颗「练完 Part 2 接着练 Part 3」开关。
///
/// 真机用了之后他补了一句：
///
/// > 我发现你这个目前练习好像无法同时选择多个问题啊。
/// > 比如我要多选 Part one 和 Part two，练完这个练那个。
///
/// 所以分段控件换成了三个勾选框。**那颗「练完 Part 2 接着练 Part 3」开关一起删掉了**：
/// 勾上 Part 2 和 Part 3 就是它，两个控件表达同一件事的话，它们迟早会互相矛盾
/// （开关开着、而 Part 3 没勾，屏幕上两处各说一套）。这不是砍功能：那个功能现在是
/// 七种组合里的一种，而且比从前更强——连着练时，那张卡自己的 Part 3 追问会一起发下去
/// （`LinkedPart3`）。
///
/// ## 一个都不勾是什么意思
///
/// **「不指定」**：列出全部题目，练哪个 Part 由挑中的那道题自己决定。
/// 这正是从前那个「全部」档的行为，一个像素都没变，只是从一格按钮变成了「都不勾」。
///
/// 不把「都不勾」当成「全都要」，是因为那会替用户做一个他没做的决定：
/// 他刚刚的动作是「一个都没勾」，把它读成「跑一整场三 Part 模考」是最糟的一种擅自主张。
///
/// ## 勾了两个以上时，列表列哪个 Part 的题
///
/// **只列开场那个 Part 的题。** 一场练习只带一道题（`SessionSetup`），
/// 而这道题必须落在某一段上；勾了 Part 1 + Part 2 时它落在 Part 1，
/// Part 2 的 cue card 由考官自己挑——真实考试里 cue card 本来就不是考生选的。
/// 这也和排计划那一侧对得上（`PlanScope.select` 同样只排开场那个 Part 的题）。
///
/// ## 它与「学习计划」页那个「重点 Part」是什么关系
///
/// **两者管的不是同一件事，所以不会打架：**
///
/// - 学习计划页的「重点 Part」决定**排计划时挑哪些题**（`PlanScope.select`）；
/// - 这里的勾选决定**这一次练哪几段、列出哪些题**，只影响眼前这一场。
///
/// 为了让两者看起来是一件事的两个层次，这里的**默认勾选跟着计划的重点 Part 走**
/// （`defaultParts(forPlanFocus:)`），并且当场用一句话说清它是从哪儿来的、怎么改
/// （`planFocusNotice(for:)`）。用户改勾选**不会**去改学习计划。
public struct PracticePicker: Sendable {

    /// 「一个都不勾」= 不指定。
    ///
    /// 用 `Set<Int>` 而不是 `Set<ExamPart>`，与 `QuestionBankView.partSelection`、
    /// `QuestionPartSections` 那两处保持同一种表示：题目自己的 `part` 就是 Int，
    /// 中间多一层转换只会多一处对不上的机会。
    public static let unspecified: Set<Int> = []

    /// 三个勾选框，顺序固定。
    public static let selectableParts = [1, 2, 3]

    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    // MARK: - 筛

    /// 这次勾选下可以练的题。
    ///
    /// - 一个都没勾：全部题目，顺序原样不动。
    /// - 勾了一个：那个 Part 的题。
    /// - 勾了两个以上：**只有开场那个 Part 的题**（理由见类型文档）。
    ///
    /// **顺序与 `TodayViewModel.pickableQuestions` 保持一致**（先按 Part、再按题库原有顺序），
    /// 这里只做筛选不重排：改一下勾选又改回来，列表顺序变了的话，
    /// 用户刚才看到的那一道就找不回来了。
    public func questions(inParts parts: Set<Int>) -> [Question] {
        guard let opening = parts.min() else { return questions }
        return questions.filter { $0.part == opening }
    }

    public func count(inPart part: Int) -> Int { questions.filter { $0.part == part }.count }

    // MARK: - 这一场按哪套考法跑

    /// 勾选 → 这一场的考法。**一个都没勾返回 nil**（= 按题目自身的 Part 走）。
    ///
    /// 只负责把界面上那几个勾翻译成一个 `FocusPart`；它怎么落到这一场上归
    /// `FocusPart.forExplicitSelection` 管，这里不再判一次——
    /// 另判一份的话，勾选框显示的条件和它生效的条件迟早会分家。
    public static func mode(forParts parts: Set<Int>) -> FocusPart? {
        let examParts = parts.sorted().compactMap(ExamPart.init(questionPart:))
        return FocusPart(parts: examParts)
    }

    // MARK: - 文案

    /// 勾选框上写什么。**保持短**：三个挤在一行里，写长了会被截断。
    public static func partTitle(forPart part: Int) -> String { "Part \(part)" }

    /// 勾选框下面那一行：每个 Part 各有多少道题。
    ///
    /// **不能省。** 三个勾选框只有三个词，用户勾之前不知道 Part 2 底下有没有题；
    /// 勾进去发现是空的，再取消，是一次白跑。
    public var countsLine: String {
        let parts = Self.selectableParts
            .map { "Part \($0) \(count(inPart: $0)) 道" }
            .joined(separator: " · ")
        return "题库里共 \(questions.count) 道：\(parts)。"
    }

    /// 列表上方那一句：这一场会怎么考、下面列的是哪些题。
    ///
    /// 三种勾选状态的说法完全不同，**一句都不能省**：勾了 Part 1 + Part 2 却只看到
    /// Part 1 的题时，用户会以为 Part 2 那一勾没生效。
    public func selectionSummary(forParts parts: Set<Int>) -> String {
        let listed = questions(inParts: parts).count
        guard let mode = Self.mode(forParts: parts) else {
            return "还没勾任何 Part：下面列出全部 \(questions.count) 道题，按 Part 分栏，"
                + "练哪个 Part 由你挑的那道题决定。"
        }
        guard mode.isCombined else {
            return "这一场只练 \(mode.openingPart.englishName)，下面列它的 \(listed) 道题。"
        }
        let names = mode.parts.map(\.englishName).joined(separator: " → ")
        let others = mode.parts.dropFirst().map(\.englishName).joined(separator: "、")
        return "这一场按 \(names) 的顺序连着练。下面列的是开场那一段"
            + "（\(mode.openingPart.englishName)）的 \(listed) 道题；"
            + "\(others) 的题目由考官顺着同一个话题当场出。"
    }

    /// 这次勾选下一道题都没有时说什么。有题时返回 nil。
    ///
    /// 三样一个不少：说明现状、说明下一步、下一步指向的控件在这张弹层上真实存在
    /// （那三个勾选框就在这句话上面）。
    public func emptyNotice(forParts parts: Set<Int>) -> String? {
        guard let opening = parts.min(), count(inPart: opening) == 0 else { return nil }
        guard !questions.isEmpty else {
            return "题库还是空的，哪个 Part 都没有题。"
                + "下一步：关掉这个窗口，到「训练题库」页导入你的题库文件。"
        }
        return "题库里共有 \(questions.count) 道题，但没有一道属于 Part \(opening)——"
            + "而这一场是从 Part \(opening) 开场的，所以列不出题来。"
            + "下一步：把上面「Part \(opening)」那个勾去掉，"
            + "或到「训练题库」页导入一份包含 Part \(opening) 的题库文件。"
    }

    // MARK: - 默认勾哪几个

    /// 打开弹层时默认勾上哪几个 Part。跟着学习计划的「重点 Part」走；
    /// 没有计划时一个都不勾（= 列出全部题目，练哪个 Part 由题目自己决定）。
    ///
    /// **全真模考也照勾三个。** 从前它停在「全部」，因为那时没有「一次练三段」这种考法；
    /// 现在有了，而计划里选的既然是全真模考，默认就该是那一场，
    /// 不勾反而是把他明确选过的东西丢掉。
    public static func defaultParts(forPlanFocus focusPart: FocusPart?) -> Set<Int> {
        guard let focusPart else { return unspecified }
        return Set(focusPart.parts.map(\.rawValue))
    }

    /// 默认勾选是从学习计划带过来的时候，得说一句它是从哪儿来的、改了会不会影响计划。
    ///
    /// 不说的话，用户打开弹层看到只有 Part 2 的题，会以为题库里别的 Part 没了。
    /// 没有计划时返回 nil——那时一个都没勾，没有什么要解释的。
    public static func planFocusNotice(for focusPart: FocusPart?) -> String? {
        guard let focusPart else { return nil }
        var notice = "默认勾的是 \(PlanScope.label(for: focusPart))，因为你在「学习计划」页"
            + "把重点 Part 设成了它。"
        // 组合档下列表只列开场那一段的题。不说这一句的话，用户看到的是一列 Part 2 的题，
        // 会以为计划里那个「连着练」根本没生效。
        if focusPart.isCombined {
            notice += "下面列的是开场那一段（\(focusPart.openingPart.englishName)）的题，"
                + "其余几段考官会顺着同一个话题接着考。"
        }
        return notice + "下一步：想练别的 Part，直接改上面那几个勾——"
            + "这只影响眼前这一场，学习计划不会跟着改。"
    }
}
