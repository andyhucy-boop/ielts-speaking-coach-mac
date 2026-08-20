import Foundation

/// **随机抽题**：自己定每个 Part 抽几道，剩下的交给运气。
///
/// 用户原话（2026-08-20）：
///
/// > 我觉得你可以加一个功能，就是 random 随机题库，就是我来选 part one part two part three
/// > 分别多少道，然后你可以来个转盘或者怎么样的，然后来随机抽选。
/// > 然后也可以选择支持我选择是否要之前练过的题目。
///
/// ## 它和「从题库自由选题」不是一回事
///
/// 自由选题一场只带**一道**题，其余几段的材料由考官自己挑（`ExaminerPrompt` 里那句
/// "Choose your own material for …"）。也就是说勾了 Part 1 + Part 2 的那一场，
/// 题库只供了一段的料，另一段是 ChatGPT 现编的——题库里 258 道真题白放着。
///
/// 随机抽题给的是**一整套材料**：Part 1 抽几个话题、Part 2 抽几张卡、Part 3 抽几组讨论，
/// 全部随题目一起发给考官。所以它顺带补掉了组合档那个「另外几段没有真题」的洞。
///
/// ## 三条规矩
///
/// 1. **抽不够必须说出来，不许闷声少给。** 题库里 Part 2 只有 3 张卡、他要 5 张时，
///    结果里会带一条 `DrawShortfall`，界面照着它说清「要 5 道、只有 3 道、为什么」。
///    静默地少给两道，是本项目最忌讳的失败形态。
/// 2. **Part 3 跟着 cue card 走。** 同一场里既抽了 Part 2 又抽了 Part 3 时，
///    Part 3 优先取每张卡自己那一组追问（`LinkedPart3`）。独立随机抽的话，
///    会出现「卡讲的是逛商店、讨论题问的是环保立法」——而提示词里白纸黑字要求
///    Part 3 必须顺着 Part 2 的主题，两者当场打架。
/// 3. **抽到什么就是什么。** 这一场跑哪几段由**真的抽到的**题决定，不由他要了几道决定
///    （`DrawResult.focusPart`）。要了 Part 3 却一道都没抽到时，这一场就不含 Part 3——
///    否则提示词会宣布有一段 Part 3，而那一段一份材料都没有。
public enum RandomDraw {

    // MARK: - 要抽几道

    /// 每个 Part 各抽几道。
    public struct Counts: Equatable, Sendable {
        /// 单个 Part 的上限。
        ///
        /// **这是一道护栏，不是产品设定**：界面上的步进器另外还会卡在「这个 Part 现在
        /// 真的有几道可抽」上，所以正常用是碰不到它的。它挡的是别处传进来的荒唐值
        /// （手改的配置、将来的命令行参数）——抽 200 道 Part 2 会生成一份没人读得完的
        /// 提示词，然后一场练习凭空变成十几个小时。
        ///
        /// 取 9 是因为界面上那三个数字要并排显示，两位数会把步进器挤换行。
        public static let maximumPerPart = 9

        private var storage: [ExamPart: Int]

        public init(one: Int = 0, two: Int = 0, three: Int = 0) {
            storage = [:]
            self[.one] = one
            self[.two] = two
            self[.three] = three
        }

        /// 越界一律夹回 `0...maximumPerPart`。**夹了不吭声是可以的**，
        /// 因为界面上的步进器本来就走不出这个范围，用户看到的数字永远就是生效的数字。
        public subscript(part: ExamPart) -> Int {
            get { storage[part] ?? 0 }
            set { storage[part] = min(max(newValue, 0), Self.maximumPerPart) }
        }

        public var total: Int { ExamPart.allCases.reduce(0) { $0 + self[$1] } }

        /// 要了至少一道的那几个 Part，升序。
        public var parts: [ExamPart] { ExamPart.allCases.filter { self[$0] > 0 } }

        /// 一道都没要时是 nil。
        public var focusPart: FocusPart? { FocusPart(parts: parts) }
    }

    // MARK: - 抽不够

    /// 某一个 Part 要了 N 道、只抽到 M 道。
    public struct Shortfall: Equatable, Sendable {
        public let part: ExamPart
        public let asked: Int
        public let got: Int
        /// **是不是「只抽没练过的」这个开关造成的。**
        ///
        /// 两种短缺的下一步完全不同，所以必须分开：题库本来就不够，只能去导更多题；
        /// 而这一种把开关关掉就有了。分不清的话，界面只能说一句「题目不够」，
        /// 而用户手边明明有一个一按就解决的开关。
        public let causedByExcludingPracticed: Bool

        public init(part: ExamPart, asked: Int, got: Int, causedByExcludingPracticed: Bool) {
            self.part = part
            self.asked = asked
            self.got = got
            self.causedByExcludingPracticed = causedByExcludingPracticed
        }
    }

    // MARK: - 抽出来的结果

    public struct Result: Equatable, Sendable {
        /// 抽到的题，**按 Part 升序**，同一个 Part 内保持抽签顺序。
        /// 顺序就是考官会用到它们的顺序，提示词直接照着排。
        public let questions: [Question]
        /// 哪几个 Part 没抽够。抽够了就是空数组。
        public let shortfalls: [Shortfall]
        /// 他当时要的是几道（用来在界面上说「要了 5 道」）。
        public let requested: Counts
        /// 这一次有没有把练过的题排除在外。
        public let excludedPracticed: Bool
        /// **Part 3 题 id → 它所属那张 cue card 的题 id。**
        /// 只有跟着卡抽出来的那几道会在里面；自由随机抽的那几道不在。
        public let part3CardIDs: [String: String]

        public init(questions: [Question], shortfalls: [Shortfall], requested: Counts,
                    excludedPracticed: Bool, part3CardIDs: [String: String]) {
            self.questions = questions
            self.shortfalls = shortfalls
            self.requested = requested
            self.excludedPracticed = excludedPracticed
            self.part3CardIDs = part3CardIDs
        }

        public var isEmpty: Bool { questions.isEmpty }

        /// 这一个 Part 真的抽到了几道。
        public func count(inPart part: ExamPart) -> Int {
            questions.filter { $0.part == part.rawValue }.count
        }

        /// 这一场真的会跑哪几段。**看抽到的，不看要的**（理由见类型文档第 3 条）。
        /// 一道都没抽到时是 nil。
        public var focusPart: FocusPart? {
            FocusPart(parts: ExamPart.allCases.filter { count(inPart: $0) > 0 })
        }

        /// 开场那一道。它会当成这一场的「题目」记进训练记录（`PracticeSession.questionId`）。
        public var openingQuestion: Question? { questions.first }

        /// 这一场大概练多久。**按真的抽到的份数算**：抽了 3 个 Part 1 话题却报 5 分钟的话，
        /// 考官会为了对上时间把话题砍掉两个（提示词里那句 `Target session length` 是硬约束）。
        public var estimatedMinutes: Int {
            ExamPart.allCases.reduce(0) { $0 + $1.minutes(forItems: count(inPart: $1)) }
        }
    }

    // MARK: - 现在有多少可抽

    /// 这个 Part 现在有几道可抽。
    ///
    /// **界面上那句「共 99 道，没练过 96 道」和抽题时真正的候选池，用的必须是这一个函数。**
    /// 界面另数一份的话，两个数字会在某次改动之后分家，而分家的表现是：
    /// 屏幕上写着「没练过 96 道」，抽 5 道却只抽到 3 道，且没有任何解释。
    public static func available(in bank: [Question], part: ExamPart,
                                 excludingPracticed: Bool) -> Int {
        eligible(in: bank, part: part, excludingPracticed: excludingPracticed).count
    }

    /// 这个 Part 现在的候选池。**`available` 与 `draw` 共用它**，
    /// 各写各的话，「屏幕上说没练过 96 道」和「实际抽得到几道」迟早会分家。
    private static func eligible(in bank: [Question], part: ExamPart,
                                 excludingPracticed: Bool) -> [Question] {
        bank.filter {
            $0.part == part.rawValue && (!excludingPracticed || $0.status != "practiced")
        }
    }

    // MARK: - 抽

    /// 从题库里抽一组题。
    ///
    /// - Parameters:
    ///   - bank: 整个题库。**要传全的**：Part 3 配对（`LinkedPart3`）要在整库里找那张卡的追问，
    ///     只传候选子集会让配对无声地失效，于是抽到的讨论题和 cue card 讲的不是一件事。
    ///   - excludingPracticed: 「只抽没练过的」。判据是 `Question.status == "practiced"`，
    ///     与训练题库页上那个 ✓、以及 `CoachState.reconcilePracticedStatus` 是同一个标记——
    ///     在这里另立一套「练过」的判据，两处迟早对不上。
    ///   - generator: 随机源。**可注入**，否则这段逻辑一条测试都写不了。
    public static func draw<G: RandomNumberGenerator>(from bank: [Question],
                                                      counts: Counts,
                                                      excludingPracticed: Bool,
                                                      using generator: inout G) -> Result {
        func pool(_ part: ExamPart) -> [Question] {
            Self.eligible(in: bank, part: part, excludingPracticed: false)
        }
        func eligible(_ part: ExamPart) -> [Question] {
            Self.eligible(in: bank, part: part, excludingPracticed: excludingPracticed)
        }

        let ones = Array(eligible(.one).shuffled(using: &generator).prefix(counts[.one]))
        let twos = Array(eligible(.two).shuffled(using: &generator).prefix(counts[.two]))

        // Part 3 先跟着卡走（规矩 2）。这一段刻意**不看「练没练过」**：
        // 它是那张卡自己的讨论题，换一道就等于讨论和卡讲的不是一件事——
        // 而卡本身已经按开关筛过了，所以正常情况下它的追问也是新的。
        var threes: [Question] = []
        var cardIDs: [String: String] = [:]
        if counts[.three] > 0 {
            for card in twos where threes.count < counts[.three] {
                guard let reference = LinkedPart3.reference(for: card, in: bank),
                      !threes.contains(where: { $0.id == reference.id }) else { continue }
                threes.append(reference)
                cardIDs[reference.id] = card.id
            }
            let taken = Set(threes.map(\.id))
            let rest = eligible(.three).filter { !taken.contains($0.id) }
                .shuffled(using: &generator)
            threes += rest.prefix(counts[.three] - threes.count)
        }

        let picked: [ExamPart: [Question]] = [.one: ones, .two: twos, .three: threes]
        let shortfalls: [Shortfall] = ExamPart.allCases.compactMap { part in
            let asked = counts[part]
            let got = picked[part]?.count ?? 0
            guard asked > 0, got < asked else { return nil }
            return Shortfall(part: part, asked: asked, got: got,
                             // 「关掉开关就够了吗」——按整个 Part 的题量判，
                             // 而不是按「练过的有几道」：后者算得出「练过的够多」
                             // 却仍然凑不齐总数的假结论。
                             causedByExcludingPracticed: excludingPracticed
                                && pool(part).count >= asked)
        }

        return Result(questions: ExamPart.allCases.flatMap { picked[$0] ?? [] },
                      shortfalls: shortfalls,
                      requested: counts,
                      excludedPracticed: excludingPracticed,
                      part3CardIDs: cardIDs)
    }

    /// 生产用的入口，随机源走系统的那一个。
    public static func draw(from bank: [Question], counts: Counts,
                            excludingPracticed: Bool) -> Result {
        var generator = SystemRandomNumberGenerator()
        return draw(from: bank, counts: counts, excludingPracticed: excludingPracticed,
                    using: &generator)
    }
}
