import ChatGPTBridge
import Foundation
import IELTSCoachCore
import SwiftUI

/// 练习进行中的界面。**Task 9 的交付物就是这张 sheet**：点一下「开始练习」之后，
/// 新建会话、启动语音、发考官提示词、练完取复盘、存档，全在这里发生，不需要打开终端
/// （成品标准第 2 条）。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// 最要紧的一条：**这张 sheet 必须一直在说话**。整条链路里最长的一步是启动语音，
/// 实测约 9 秒（spec 2.3.7）；中间界面一动不动的话，用户会以为程序卡死然后去强退，
/// 而那时 ChatGPT 那边的语音通话已经开起来了（DESIGN-SYSTEM 第 5 节）。
@MainActor
struct PracticeSheet: View {
    let runner: PracticeRunner
    let route: PracticeRoute
    /// 已经替用户定下来的这一场。nil 表示要先挑一道题（自由选题，
    /// 或者那条路线原来指着的题在题库里已经没有了）。
    let preselected: SessionSetup?
    /// 挑题用的候选。
    let candidates: [Question]
    /// 打开时默认勾上哪几个 Part（空集合 = 一个都不勾 = 不指定）。由调用方按学习计划的
    /// 「重点 Part」算出来，规则在 `PracticePicker.defaultParts(forPlanFocus:)`，那边有测试守着。
    let defaultParts: Set<Int>
    /// 学习计划的「重点 Part」，只用来解释上面那个默认值是从哪儿来的（可以是 nil）。
    let planFocusPart: FocusPart?
    /// 把选中的题 + 用户当场勾的那几个 Part，变成一场练习的设置。
    /// 逻辑在 `PracticeRouteResolver.setup(for:goal:defaults:chosen:bank:)` 里，那边有测试守着。
    ///
    /// **第二个参数不能省。** 省掉的话，用户在这张弹层上勾的 Part 不会有任何去处：
    /// 勾选框点得动、`SessionSetup` 照样是那道题自己的 Part，
    /// 而屏幕上一个字都不会提——本项目最忌讳的那种失败。
    let makeSetup: (Question, FocusPart?) -> SessionSetup
    /// 把**抽出来的一整组题**变成一场练习（`PracticeRouteResolver.setup(forDraw:…)`）。
    /// 抽了个空时返回 nil，那时「开始练习」是灰的。
    ///
    /// 与 `makeSetup` 分成两个闭包而不是合成一个：一场随机抽题带的是一整套材料、
    /// 时长按份数算、考法按**真的抽到的**那几段算——三件事没有一件和挑一道题相同。
    let makeDrawSetup: (RandomDraw.Result) -> SessionSetup?
    let onClose: () -> Void

    /// 这一场最终定下来的设置。nil 时显示挑题列表。
    @State private var running: SessionSetup?
    @State private var picked: String?
    /// 这一场勾了哪几个 Part。**空集合表示「一个都没勾」**，也就是「不指定」：
    /// 列出全部题目，练哪个 Part 由挑中的那道题自己决定（见 `PracticePicker`）。
    ///
    /// 初值来自 `defaultParts`，所以它跟着学习计划的重点 Part 走；
    /// 用户在这里改勾选**不会**回写学习计划。
    @State private var partSelection: Set<Int>
    /// 哪几栏是展开的。**`nil` 表示「用户还没动过折叠」，那时按默认来**
    /// （`QuestionPartSections.defaultExpandedParts`）。
    ///
    /// 用 Optional 而不是在 `init` 里算一份存进去，是因为默认值取决于**当前档位下有哪几栏**，
    /// 而档位是用户随时能切的。存死一份的话，从「全部」切到 Part 3 之后，
    /// 展开状态还停在切换之前那一套——Part 3 那一栏明明是他刚选的，却是折着的。
    @State private var expandedParts: Set<Int>?

    // MARK: - 随机抽题那条路线的状态

    /// 每个 Part 各抽几道。初值是默认值夹到「现在真的抽得到」的范围里
    /// （`RandomDrawViewModel.clampedToAvailable`）。
    @State private var drawCounts = RandomDrawViewModel.defaultCounts
    /// 「只抽没练过的」。**默认开着**：用户提这个功能时说的是
    /// 「也可以选择支持我选择是否要之前练过的题目」，而会去想这件事的人默认要的是新题。
    @State private var excludePracticed = true
    /// 抽出来的那一组。nil = 还没抽（这时「开始练习」是灰的）。
    @State private var drawn: RandomDraw.Result?
    /// 抽签动画正在滚。**它只是动画**：结果在按下按钮那一刻就已经定了（见 `roll()`）。
    @State private var isRolling = false
    @State private var rollingLabel = ""
    /// 系统的「减弱动态效果」。开着时直接出结果，不滚。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(runner: PracticeRunner, route: PracticeRoute, preselected: SessionSetup?,
         candidates: [Question], defaultParts: Set<Int> = PracticePicker.unspecified,
         planFocusPart: FocusPart? = nil,
         makeSetup: @escaping (Question, FocusPart?) -> SessionSetup,
         makeDrawSetup: @escaping (RandomDraw.Result) -> SessionSetup? = { _ in nil },
         onClose: @escaping () -> Void) {
        self.runner = runner
        self.route = route
        self.preselected = preselected
        self.candidates = candidates
        self.defaultParts = defaultParts
        self.planFocusPart = planFocusPart
        self.makeSetup = makeSetup
        self.makeDrawSetup = makeDrawSetup
        self.onClose = onClose
        _partSelection = State(initialValue: defaultParts)
        _drawCounts = State(initialValue: RandomDrawViewModel(questions: candidates)
            .clampedToAvailable(RandomDrawViewModel.defaultCounts))
    }

    private var drawModel: RandomDrawViewModel { RandomDrawViewModel(questions: candidates) }

    private var partPicker: PracticePicker { PracticePicker(questions: candidates) }

    /// 当前这一档筛出来的题。**挑好的那道不在这一档里时要把选择清掉**——
    /// 否则用户选了 Part 1 的一道题、切到 Part 2、再点「开始练习」，
    /// 练的是屏幕上一道也看不见的题。
    private var visibleCandidates: [Question] {
        partPicker.questions(inParts: partSelection)
    }

    /// 当前这一档筛出来的题，再**按 Part 分成几栏**。用户原话：
    /// 「你可以把它做成三栏，Part one 一栏，Part one 一堆，然后 part two 一堆，
    /// 然后 part three 一堆。」
    ///
    /// 「全部」那一档下这里是三栏（此前是一张 258 条的平铺列表，Part 1 的 60 条全在最前，
    /// 想练 Part 3 得滑过 159 条）；单 Part 档下是一栏。分栏规则在
    /// `QuestionPartSections` 里，那边有测试守着。
    private var sectionsByPart: [QuestionPartSection<Question>] {
        QuestionPartSections.split(visibleCandidates) { $0.part }
    }

    /// 此刻哪几栏是展开的。用户还没动过折叠时按默认来。
    ///
    /// 「用户的偏好」就是他勾了哪几个 Part——初值又来自学习计划的重点 Part
    /// （`PracticePicker.defaultParts(forPlanFocus:)`）。一个都没勾时没有偏好可言，
    /// 传 nil，于是三栏都折着，屏幕上是三行带条数的栏标题。
    ///
    /// 勾了两个以上时列表只有开场那一段的题（`PracticePicker.questions(inParts:)`），
    /// 所以这里传的是**开场那个 Part**，不是勾了的全部——传全部的话，
    /// 那几栏里只有一栏真的存在，另外几个下标什么也匹配不上。
    private var expandedPartsNow: Set<Int> {
        expandedParts ?? QuestionPartSections.defaultExpandedParts(
            inSections: sectionsByPart.map(\.part),
            preferredPart: partSelection.min())
    }

    /// 此刻屏幕上真的看得见的那些题：展开的那几栏里的。**挑题只认这一份。**
    private var visibleInExpandedSections: [Question] {
        QuestionPartSections.visibleItems(in: sectionsByPart, expandedParts: expandedPartsNow)
    }

    /// 用户挑中的那道题。**折起来的栏里那道不算数**——
    /// 选中一道、把那一栏折起来、再点「开始练习」的话，练的会是屏幕上一道也看不见的题。
    private var pickedQuestion: Question? {
        guard let picked else { return nil }
        return visibleInExpandedSections.first { $0.id == picked }
    }

    /// 某一栏展开与否。`DisclosureGroup` 要的是 `Binding<Bool>`，这里转一道。
    ///
    /// **收起一栏的同时要把那一栏里挑好的题清掉**，理由同上：不清的话，
    /// 屏幕上看不见的一道题仍然是「已选中」，而按钮照样亮着。
    private func expansion(of part: Int) -> Binding<Bool> {
        Binding(get: { expandedPartsNow.contains(part) },
                set: { isExpanded in
                    var next = expandedPartsNow
                    if isExpanded {
                        next.insert(part)
                    } else {
                        next.remove(part)
                        if let picked, visibleCandidates.contains(where: {
                            $0.id == picked && $0.part == part
                        }) {
                            self.picked = nil
                        }
                    }
                    expandedParts = next
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if let running {
                practiceBody(for: running)
            } else {
                picker
            }
            Divider()
            actions
        }
        .padding(Spacing.xl)
        .frame(width: 620)
        .background(Palette.canvas)
        .task {
            // 题已经定下来的路线直接开练：多让用户按一次「确认」只是白按一下，
            // 而成品标准第 1 条数的就是点击次数。
            guard running == nil, let preselected else { return }
            await begin(preselected)
        }
    }

    private func begin(_ setup: SessionSetup) async {
        running = setup
        // 失败不靠抛出来的错处理：`runner` 已经把它翻译成中文放进 `stage` 了，
        // 下面的 `stageBlock` 会原样显示。这里再吞一次只是不让它冒泡到 Task 里。
        try? await runner.start(setup: setup)
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(route.title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(route.subtitle)
                .font(Typography.secondary)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - 还没定题：挑一道

    private var picker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if candidates.isEmpty {
                // 走不到这里（题库空时今日训练页整页都是导入引导），但真走到了也不能给白板。
                Text("题库里没有可以练的题目。下一步：关掉这个窗口，到「训练题库」导入你的题库文件。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if route == .randomDraw {
                randomDrawPicker
            } else {
                Text("先勾这一场练哪几个 Part（可以多勾，勾了就按 Part 1 → 2 → 3 的顺序连着练），"
                     + "再挑一道题。挑好之后本工具会自动打开 ChatGPT、进语音、"
                     + "并把这道题的考官提示词发过去——你什么都不用输。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                partSection
                if let notice = partPicker.emptyNotice(forParts: partSelection) {
                    emptyPartNotice(notice)
                } else {
                    sectionsNotice
                    questionSections
                }
            }
        }
    }

    // MARK: - 还没定题：随机抽一组

    /// **用户要的「随机抽题」就是这一段。** 原话：
    ///
    /// > 我来选 part one part two part three 分别多少道，然后你可以来个转盘或者怎么样的，
    /// > 然后来随机抽选。然后也可以选择支持我选择是否要之前练过的题目。
    ///
    /// 三个步进器 + 一个「只抽没练过的」勾选框 + 一颗抽题按钮，抽完在下面列出抽到的整组。
    /// 所有文案与数字都走 `RandomDrawViewModel`（那边有测试），这里一句都不现拼。
    private var randomDrawPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 字面量里不要写 Markdown 的星号：`Text` 收的是 String，星号会原样显示出来。
            Text("先定每个 Part 各抽几道，再点「抽题」。抽到的题会一整套发给考官："
                 + "抽到几个 Part 1 话题就问几个，抽到几张 Part 2 卡就做几张，"
                 + "Part 3 会接着抽到的那张卡往下讨论。")
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            drawCountsSection
            if let notice = drawModel.emptyNotice(forCounts: drawCounts) {
                emptyPartNotice(notice)
            } else {
                if let summary = drawModel.summary(forCounts: drawCounts) {
                    subtleLine(summary)
                }
                // 抽之前就提醒「要的比现在能抽的多」。等抽完再说的话，用户已经看着
                // 一组比他要的少的题，得先弄明白少了什么才知道怎么办。
                ForEach(drawModel.warnings(forCounts: drawCounts,
                                           excludingPracticed: excludePracticed), id: \.self) {
                    warningLine($0)
                }
            }
            drawButton
            drawOutcome
        }
    }

    private var drawCountsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(ExamPart.allCases, id: \.self) { part in
                HStack(spacing: Spacing.md) {
                    Text(part.englishName)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 56, alignment: .leading)
                    Stepper(value: drawCountBinding(for: part),
                            in: 0...max(drawModel.maximum(inPart: part), 0)) {
                        // 等宽数字：0 → 1 → 10 时这一行不许横向抖（规范第 6 节最后一条）。
                        Text("\(drawCounts[part]) 道")
                            .font(Typography.body)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .frame(width: 132)
                    // 两个数都要有：只写总数的话，勾上「只抽没练过的」之后用户不知道还剩多少。
                    Text(drawModel.availabilityLine(forPart: part))
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            Toggle("只抽没练过的题", isOn: $excludePracticed)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityHint("勾上之后，训练题库里已经标成「已练」的题不会被抽到")
        }
    }

    /// 改数量要**把上一次抽的结果清掉**。不清的话，用户把 Part 2 从 1 调成 3、
    /// 下面还挂着上一次那组只有 1 张卡的结果，而「开始练习」按下去练的正是那一组旧的——
    /// 屏幕上的数字和真正会练的东西对不上，一个字的提示都没有。
    private func drawCountBinding(for part: ExamPart) -> Binding<Int> {
        Binding(get: { drawCounts[part] },
                set: { value in
                    drawCounts[part] = value
                    drawn = nil
                })
    }

    private var drawButton: some View {
        HStack(spacing: Spacing.sm) {
            // 还没抽时抽题是这张弹层的主行动；抽完之后主行动变成底下那颗「开始练习」，
            // 这颗降成次一级（规范第 4 节：每页最多一个主行动）。
            if drawn == nil {
                Button("抽题") { roll() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .disabled(drawCounts.total == 0 || isRolling)
            } else {
                Button("重抽一组") { roll() }
                    .buttonStyle(.bordered)
                    .disabled(isRolling)
            }
            Spacer(minLength: 0)
        }
    }

    /// 抽的过程与结果。
    ///
    /// 滚动那 0.6 秒**不是装饰**：它是「正在替你抽」这件事的唯一表示。
    /// 没有它的话，点一下按钮、结果直接换一批，用户分不清这次到底抽没抽
    /// （尤其重抽时新旧两组长得差不多的情况）。
    /// 它有明确的起止、不循环，系统开了「减弱动态效果」时整段跳过（`roll()`）。
    @ViewBuilder
    private var drawOutcome: some View {
        if isRolling {
            CoachCard {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(rollingLabel)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        } else if let drawn {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                subtleLine(RandomDrawViewModel.resultSummary(for: drawn))
                // 抽不够时必须当场交代，而且两种原因说两句不同的话——
                // 「没练过的不够了」那一种，把开关关掉就有了。
                ForEach(RandomDrawViewModel.shortfallNotices(for: drawn), id: \.self) {
                    warningLine($0)
                }
                if !drawn.questions.isEmpty { drawnQuestionList(drawn) }
            }
        }
    }

    /// 抽到的整组，按 Part 分栏列出来。
    ///
    /// **必须逐条列出，不能只报个数。** 这一场真正会被问到的就是这几道，
    /// 只写「抽到 4 道」的话，用户要等考官开口才知道抽到了什么，
    /// 而那时已经没法重抽了。
    private func drawnQuestionList(_ result: RandomDraw.Result) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(QuestionPartSections.split(result.questions, part: { $0.part })) { section in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(section.title)
                            .font(Typography.cardTitle)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, question in
                            Text("· \(RandomDrawViewModel.label(for: question))")
                                .font(Typography.body)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    /// 抽一组。**结果在按下按钮那一刻就已经定了**，滚动只是把它慢慢揭开——
    /// 让动画去决定抽到什么的话，中途关掉窗口或者动画被系统打断，
    /// 这一场抽到的就成了一件谁也说不清的事。
    private func roll() {
        let result = RandomDraw.draw(from: candidates, counts: drawCounts,
                                     excludingPracticed: excludePracticed)
        guard !reduceMotion, !result.isEmpty else {
            drawn = result
            return
        }
        drawn = nil
        isRolling = true
        Task {
            let pool = candidates.map(RandomDrawViewModel.label(for:))
            for _ in 0..<8 {
                rollingLabel = pool.randomElement() ?? ""
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
            isRolling = false
            drawn = result
        }
    }

    private func subtleLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.label)
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 一条「发生了什么 + 下一步做什么」的提醒。用警告色而不是灰色：
    /// 灰色那一行是说明，这一行是要他动手改的。
    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
            Text(text)
                .font(Typography.label)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 分栏这件事本身的那一句交代。只有一栏时 `notice` 是 nil，这里什么都不画。
    @ViewBuilder
    private var sectionsNotice: some View {
        if let notice = QuestionPartSections.notice(for: sectionsByPart) {
            Text(notice)
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **用户要的那「三栏」就是这里。**
    ///
    /// 每一栏一个可折叠的标题（`Part 1 · 60 道`），默认展开哪一栏跟着他的选择走
    /// （`expandedPartsNow`）。外壳是 `QuestionPartSectionView`，
    /// 与复训换题那张列表共用同一个——各写各的话，两处的折叠交互会长成两个样子。
    private var questionSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(sectionsByPart) { section in
                    QuestionPartSectionView(title: section.title,
                                            isExpanded: expansion(of: section.part)) {
                        ForEach(section.items) { question in
                            questionRow(question)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    /// **这一段就是用户要的「多选 Part」。**
    ///
    /// 三个勾选框，勾几个就按 Part 1 → 2 → 3 的顺序连着练几段。从前这里是一排四格
    /// 分段控件（全部 / Part 1 / Part 2 / Part 3）加一颗「练完 Part 2 接着练 Part 3」开关，
    /// 只能四选一；用户实测后要求「多选 Part one 和 Part two，练完这个练那个」。
    ///
    /// 那颗开关一起删了：勾上 Part 2 和 Part 3 就是它。两个控件表达同一件事的话，
    /// 迟早会出现「开关开着、Part 3 却没勾」这种屏幕上自相矛盾的状态。
    ///
    /// 每一格的题数摆在下面那一行（`countsLine`）而不是格子里：三格挤在一行里，
    /// 写成「Part 1（60）」会被截断，而截断之后用户既看不清 Part 也看不清数。
    private var partSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.md) {
                ForEach(PracticePicker.selectableParts, id: \.self) { part in
                    Toggle(PracticePicker.partTitle(forPart: part), isOn: partBinding(for: part))
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityLabel("这一场练哪几个 Part")

            Text(partPicker.countsLine)
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(partPicker.selectionSummary(forParts: partSelection))
                .font(Typography.label)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = PracticePicker.planFocusNotice(for: planFocusPart) {
                Text(notice)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 一个 Part 的勾选框。`Toggle` 要的是 `Binding<Bool>`，这里从那个集合转一道。
    ///
    /// **改完勾选要做两件收尾**，一件都不能少：
    ///
    /// 1. 上一次勾选下挑好的那道题若已经不在列表里，必须清掉。不清的话，
    ///    用户选了 Part 1 的一道题、改勾成 Part 2、再点「开始练习」，
    ///    练的是屏幕上一道也看不见的题——一次静默做错事。
    /// 2. 展开状态重算：换了一组勾就是换了一组栏，刚勾上的那一栏不该还折着。
    private func partBinding(for part: Int) -> Binding<Bool> {
        Binding(get: { partSelection.contains(part) },
                set: { isOn in
                    var next = partSelection
                    if isOn { next.insert(part) } else { next.remove(part) }
                    partSelection = next
                    // 拿 `next` 去算还看得见哪些题，**不回头读 `partSelection`**：
                    // `@State` 的读写在同一次事件里不保证读到刚写进去的值，
                    // 读到旧值的话这道清理会漏掉，而漏掉的表现正是「练到一道看不见的题」。
                    let stillVisible = partPicker.questions(inParts: next)
                    if let picked, !stillVisible.contains(where: { $0.id == picked }) {
                        self.picked = nil
                    }
                    expandedParts = nil
                })
    }

    /// 这一档一道题都没有。**不给白板**：说清现状、说清下一步，
    /// 而下一步指的那排分段按钮就在这句话上面，真实存在。
    private func emptyPartNotice(_ notice: String) -> some View {
        CoachCard {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "tray")
                    .foregroundStyle(Palette.textSecondary)
                Text(notice)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func questionRow(_ question: Question) -> some View {
        Button {
            picked = question.id
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: picked == question.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(picked == question.id ? Palette.accent : Palette.textSecondary)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Part \(question.part) · \(question.topic)")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text(question.prompt.isEmpty ? "（这道题没有题干）" : question.prompt)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(picked == question.id ? Palette.accent : Palette.cardBorder,
                              lineWidth: BorderWidth.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 练起来之后：这一步在干什么

    @ViewBuilder
    private func practiceBody(for setup: SessionSetup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            CoachCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("这一场练的是")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Text("\(setup.focusPart.rawValue) · \(setup.question.prompt)")
                        .font(Typography.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    // 随机抽题那一场带的是一整套材料。**每一道都要列出来**：
                    // 只显示开场那道的话，用户会以为这一场就练那一道，
                    // 而考官手里其实还有另外几道（`SessionSetup.drawnQuestions`）。
                    if setup.drawnQuestions.count > 1 {
                        Text("这一场一共 \(setup.drawnQuestions.count) 道，按顺序练：")
                            .font(Typography.label)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                        ForEach(Array(setup.drawnQuestions.enumerated()), id: \.offset) { _, item in
                            Text("· Part \(item.part) · \(RandomDrawViewModel.label(for: item))")
                                .font(Typography.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !setup.goal.isEmpty {
                        Text("本次目标：\(setup.goal)")
                            .font(Typography.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            stageBlock
            recordingBlock
            transcriptBlock
            checklist
            if let notice = runner.archiveNotice {
                CoachCard {
                    Text(notice)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 当前这一步在干什么。**任何时候都得有内容**——空白等于「程序卡住了」。
    private var stageBlock: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if runner.stage.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: stageIcon)
                    .foregroundStyle(stageTint)
            }
            Text(runner.stage.userFacingText)
                .font(Typography.body)
                .foregroundStyle(stageTint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 录音这一路的交代。两半各守一件不能含糊的事：
    ///
    /// - **正在录音的指示**：麦克风开着却一点表示都没有，用户不知道自己什么时候在被录。
    ///   **静止的，不做呼吸闪烁**：一个一直在动的红点是这个界面上最容易让人分心的东西，
    ///   而用户这时候正要开口说英语（DESIGN-SYSTEM 第 5 节禁止循环装饰动画）。
    /// - **那句提示**：用户以为在录、实际没录（没权限、麦克风被别的程序占着），
    ///   或者中途插拔耳机断过一下。**不显示就是骗人**——练完点开回听才发现什么都没有。
    ///   用 `CoachCard` 装、文字可选中，方便用户把这句话复制去查。
    ///
    /// **开关关着时这里什么都不画**：那是默认状态，不是故障，为它摆一句提示会天天骚扰用户。
    /// `isRecording` 与 `recordingNotice` 那时都是 false / nil，两半自然都不出现。
    ///
    /// 两半都不抢「我练完了」那颗按钮的视觉主位：一行小字加一张说明卡，
    /// 主行动仍然只有底下那一颗（DESIGN-SYSTEM 第 4 节）。
    @ViewBuilder
    private var recordingBlock: some View {
        if runner.isRecording {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "record.circle")
                    .foregroundStyle(Palette.danger)
                Text("正在录音")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.danger)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在录音，这次练习你说的话会存在本机")
        }
        if let notice = runner.recordingNotice {
            CoachCard {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.bubble")
                        .foregroundStyle(Palette.warning)
                    Text(notice)
                        .font(Typography.secondary)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 逐字稿这一路的交代：练习中显示已经记下几条，练完/失败后如实说明缺了什么。
    ///
    /// **不画成红色的错误。** 逐字稿是增强，不是必需（ROADMAP 3.2）：采样失败不中断练习，
    /// 复盘和训练记录都照常。用 `Palette.warning` 而不是 `Palette.danger`，
    /// 是不想让用户以为这一场白练了。
    ///
    /// 但也**绝不省略**：悄悄丢掉几分钟对话、逐字稿看起来一切正常，
    /// 才是本项目最忌讳的失败形态。
    @ViewBuilder
    private var transcriptBlock: some View {
        if runner.transcriptTurnCount > 0 {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Palette.textSecondary)
                // 等宽数字：这个数字每采一次样就可能变，不等宽的话整行会跟着抖
                // （DESIGN-SYSTEM 第 6 节最后一条）。
                Text("已记录 \(runner.transcriptTurnCount) 条对话")
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
        if let notice = runner.transcriptNotice {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.bubble")
                    .foregroundStyle(Palette.warning)
                Text(notice)
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.warning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var stageIcon: String {
        switch runner.stage {
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        case .needsManualCopy: return "doc.on.clipboard"
        case .practicing: return "waveform"
        // 放弃不是故障，是用户自己的选择：给一个中性的「停」，不给三角警告。
        case .abandoned: return "stop.circle"
        default: return "circle"
        }
    }

    private var stageTint: Color {
        switch runner.stage {
        case .done: return Palette.success
        case .failed: return Palette.danger
        case .needsManualCopy: return Palette.warning
        default: return Palette.textPrimary
        }
    }

    /// 走到第几步了。失败与放弃时不画（`PracticeStage.showsChecklist`）：
    /// 这两种收场的 `order` 都是 -1，一格都不会打勾，画出来只是一列灰圈，
    /// 反而把那段真正要读的话（错误信息 / 放弃之后的交代）挤下去。
    @ViewBuilder
    private var checklist: some View {
        if !runner.stage.showsChecklist {
            EmptyView()
        } else {
            let steps = runner.stage.order > PracticeStage.practicing.order
                ? Self.wrapUpSteps : Self.startupSteps
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(steps, id: \.stepName) { step in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: runner.stage.order > step.order
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(runner.stage.order > step.order
                                             ? Palette.success : Palette.textSecondary)
                        Text(step.stepName)
                            .font(Typography.label)
                            .foregroundStyle(runner.stage.order >= step.order
                                             ? Palette.textPrimary : Palette.textSecondary)
                    }
                }
            }
        }
    }

    private static let startupSteps: [PracticeStage] =
        [.newChat, .startingVoice, .waitingComposer, .sendingPrompt]
    private static let wrapUpSteps: [PracticeStage] =
        [.endingVoice, .requestingReview, .capturingReview, .archiving]

    // MARK: - 按钮：每个状态都得有一条出口

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: Spacing.md)
            switch runner.stage {
            case .practicing:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我练完了") {
                    Task { try? await runner.finishPractice() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)

            case .needsManualCopy:
                Button("放弃这一场") { abandon() }
                    .buttonStyle(.bordered)
                Button("我已经复制好了") {
                    Task { try? await runner.captureReviewFromClipboard() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)

            case .failed:
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                if let retry = runner.retry {
                    Button(retry.buttonTitle) { redo(retry) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .keyboardShortcut(.defaultAction)
                }

            case .done:
                Button("完成", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)

            case .abandoned:
                // **放弃之后停在这里，不在同一帧关窗**（见 `abandon()`）。
                // 上面那段交代（逐字稿去哪儿了、录音留在哪儿、ChatGPT 那通语音要不要
                // 自己挂）和那张录音警告卡片，得有一帧画得出来才算数。
                // 这里只留「关掉」一颗：这个状态下再没有别的事可做了。
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)

            case .idle:
                Button("关掉") { onClose() }
                    .buttonStyle(.bordered)
                if running == nil {
                    Button("开始练习") { startPicked() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .disabled(!readyToStart)
                        .keyboardShortcut(.defaultAction)
                }

            default:
                // 正在自动跑的那几步。只留取消——这时候点别的都没有意义。
                Button("取消") { abandon() }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// 「重试」到底重做什么，由 `runner.retry` 说了算。
    ///
    /// **不能一律重跑 `start`**：收尾阶段失败时重跑 start 的第一步是按「新建会话」，
    /// 那条刚练完、复盘还在里面的会话当场就没了。
    ///
    /// 按钮上写什么字用的是 `PracticeRetry.buttonTitle`，**不在这里另写一份**：
    /// 运行器的错误信息里会指名道姓提到这颗按钮，两处各写一份的话，
    /// 改了这边的字，那边指的就成了一颗界面上不存在的按钮。
    private func redo(_ retry: PracticeRetry) {
        switch retry {
        case .restart:
            // `running` 在 `begin` 里就已经设上了，走到这儿必然非 nil；
            // 兜一个 `preselected` 只是不让这颗按钮有任何一条「按下去什么都不发生」的可能。
            guard let setup = running ?? preselected else { return }
            Task { await begin(setup) }
        case .wrapUp:
            Task { try? await runner.finishPractice() }
        case .clipboard:
            Task { try? await runner.captureReviewFromClipboard() }
        }
    }

    /// 只认**此刻屏幕上真的看得见**的那道题（`pickedQuestion` → 展开的那几栏里的）。
    /// 用 `candidates` 全库去找的话，切档或者折起一栏之后残留的那个 id 仍然找得到题——
    /// 用户会练到一道屏幕上一道也看不见的题。
    /// 「开始练习」现在能不能按。
    ///
    /// 两条路线两个判据，一条都不能含糊：
    ///
    /// - 挑题那几条看的是 `pickedQuestion` 而**不是** `picked`：把挑好那道题所在的栏
    ///   折起来之后它就不在屏幕上了，这时按钮还亮着的话，按下去练的是一道看不见的题。
    /// - 随机抽题看的是**这一组真的造得出一场练习**（`drawnSetup`），
    ///   而不是「抽过了」：抽了个空时 `drawn` 非 nil 但里面一道题都没有，
    ///   按下去会开一场什么都不考的练习。
    private var readyToStart: Bool {
        route == .randomDraw ? drawnSetup != nil : pickedQuestion != nil
    }

    /// 抽出来这一组对应的那一场。抽了个空、或者还没抽时是 nil。
    private var drawnSetup: SessionSetup? {
        guard let drawn, !isRolling else { return nil }
        return makeDrawSetup(drawn)
    }

    private func startPicked() {
        if route == .randomDraw {
            guard let setup = drawnSetup else { return }
            Task { await begin(setup) }
            return
        }
        guard let question = pickedQuestion else { return }
        // 考法跟着屏幕上那三个勾选框走。翻译规则在 `PracticePicker.mode(forParts:)`，
        // 这里不另判一次——另判一份的话，勾选框显示的条件和它生效的条件迟早会分家。
        let mode = PracticePicker.mode(forParts: partSelection)
        Task { await begin(makeSetup(question, mode)) }
    }

    /// 「放弃这一场」/「取消」。
    ///
    /// **这里不关窗口，一帧都不许提前关。** `runner.cancel()` 恰好在这一刻做三件事：
    /// 关掉录音（可能因此生成一条「中途插拔耳机断过」「写盘失败，已录到的部分存在某处」
    /// 的警告）、把已经采到的逐字稿定案、写出那段「这一场已经放弃了…」的交代。
    /// 在同一帧调 `onClose()` 的话，这三样一个像素都画不出来——
    /// 真发生过的录音故障，唯一的出口被同一次点击关掉了（复审第 6 条）。
    ///
    /// 关窗口归 `.abandoned` 那条分支里的「关掉」，由用户看完再点。
    private func abandon() {
        runner.cancel()
    }
}

#if DEBUG
/// 预览专用的空壳 Bridge：**一次也不碰真实 ChatGPT**（铁律 5）。
///
/// 打开画布就会执行预览体，而 `PracticeSheet` 在题已经定下来时会自动开练——
/// 用真 Bridge 的话，看一眼布局就会在用户账号里新建会话、拨一通语音。
/// 所以预览一律传这个空壳，且 `preselected` 传 nil，停在挑题那一步。
/// 每个方法都抛错而不是假装成功：万一哪天预览真的走到开练那一步，
/// 看到的会是一句「这是预览」，而不是一条看着正常、其实什么都没发生的流程。
private struct InertBridge: CoachBridge, Sendable {
    private var refuse: BridgeError {
        .actionFailed("这是 Xcode 预览，不驱动真实的 ChatGPT。下一步：要真练一场，请运行 App。")
    }
    func preflight() -> BridgeReadiness {
        BridgeReadiness(ok: false, messages: ["这是 Xcode 预览，不驱动真实的 ChatGPT。"])
    }
    func startNewChat() throws { throw refuse }
    func sendText(_ text: String, into target: ComposerTarget) throws { throw refuse }
    func startVoice() throws { throw refuse }
    func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot { throw refuse }
    func isVoiceActive() -> Bool { false }
    func endVoice() throws { throw refuse }
    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String { throw refuse }
    func assistantReplyCount() -> Int { 0 }
    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int,
                               afterReplyCount: Int?) throws { throw refuse }
    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                    timeout: TimeInterval) throws -> String { throw refuse }
}

/// 同理：预览里点任何东西都不该动用户真实的剪贴板。
private struct InertPasteboard: PasteboardAccess {
    func readString() -> String? { nil }
    func clear() {}
}

#Preview("挑一道题") {
    PracticeSheet(
        runner: PracticeRunner(bridge: InertBridge(), pasteboard: InertPasteboard()),
        route: .freePick,
        preselected: nil,
        candidates: [
            Question(id: "p1-home-001", part: 1, topic: "Home",
                     prompt: "Do you live in a house or a flat?"),
            Question(id: "p2-skill-001", part: 2, topic: "Skills",
                     prompt: "Describe a skill you learned recently.")
        ],
        defaultParts: PracticePicker.unspecified,
        planFocusPart: nil,
        makeSetup: { question, mode in
            let focusPart = mode.map { FocusPart.forExplicitSelection($0, questionPart: question.part) }
                ?? FocusPart.inferred(fromQuestionPart: question.part)
            return SessionSetup(question: question, focusPart: focusPart,
                                durationMinutes: focusPart.defaultDurationMinutes, goal: "")
        },
        onClose: {})
}

#Preview("随机抽题") {
    let bank: [Question] =
        (1...6).map { TopicQuestions.part1(topic: "Topic \($0)", prompts: ["Do you like it?"]) }
        + (1...4).map {
            Question(id: "p2-\($0)", part: 2, topic: "Place",
                     prompt: "Describe place number \($0).", followups: ["where it is"])
        }
        + (1...4).map {
            TopicQuestions.part3(cueCard: "Describe place number \($0).",
                                 prompts: ["Why do people go there?"])
        }
    return PracticeSheet(
        runner: PracticeRunner(bridge: InertBridge(), pasteboard: InertPasteboard()),
        route: .randomDraw,
        preselected: nil,
        candidates: bank,
        makeSetup: { question, _ in
            SessionSetup(question: question, focusPart: .part1, durationMinutes: 6, goal: "")
        },
        makeDrawSetup: { draw in
            PracticeRouteResolver.setup(forDraw: draw, defaults: RouteDefaults(), bank: bank)
        },
        onClose: {})
}
#endif
