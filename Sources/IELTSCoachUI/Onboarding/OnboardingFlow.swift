import Foundation

/// 首次使用引导的一步。
///
/// **每一步的三句文案（标题、正文、主按钮）都在这里，不在视图里。**
/// 理由和 `DiagnosticsStage.title` 一样：视图里的 `switch` 写漏一支只会安静地
/// 返回空字符串，没人看得见；收在枚举上，`OnboardingFlowTests` 才能把每一档都数一遍。
public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case environment
    case questionBank
    case recordingChoice
    case ready

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .environment: return "让它能替你操作 ChatGPT"
        case .questionBank: return "先把你的题库导进来"
        case .recordingChoice: return "要不要录下你的回答？"
        case .ready: return "可以开练了"
        }
    }

    public var body: String {
        switch self {
        case .welcome:
            return "这个工具替你打理练习前后的杂事：想今天练什么、输考官提示词、"
                + "把复盘和错题归档、记住上次的毛病。说英语的部分还是你自己来。\n"
                + "接下来三步，一分钟就能弄完。"
        case .environment:
            // ⚠️ 这一段从前写的是「跳过之后运行在半自动模式：提示词要你自己粘贴，
            // 复盘要你自己按 ⌘C，其余功能照常」——**那个模式在这个 App 里根本不存在**
            // （2026-08-08 复审第 8 条实测）：界面从不把考官提示词显示或复制给你，
            // 手动 ⌘C 的入口只在自动开练成功之后才可能出现，待处理复盘页也没有
            // 「从剪贴板导入」。照着那句话做完全部动作，仍然一场都练不成。
            //
            // 所以这里改成实话，并且把「跳过之后还能做什么」逐样列出来——
            // 只说「练不了」会让人以为整个应用都白装了，而题库、记录、档案这几页是真能用的。
            return "本工具靠系统的「辅助功能」权限替你操作 ChatGPT：新建会话、点开语音、"
                + "把考官提示词发过去、练完取回复盘。它不读你别的应用，也不上传任何东西。\n"
                + "你可以先跳过，但要先说清楚：没有这个权限就练不成一场——"
                + "点「开始练习」会卡在第一步（新建会话）然后报错，"
                + "本工具也没有「自己粘提示词、自己按 ⌘C」这种半自动的练法。\n"
                + "跳过之后仍然能用的是：导入并浏览训练题库、排学习计划、"
                + "翻训练记录、复盘报告、问题档案和我的词汇——已有的数据一样都不会少。\n"
                + "之后在系统设置里授权了，重开本应用就会自动恢复；"
                + "也可以在「关于」页点「重新检查」确认它生效了没有。"
        case .questionBank:
            return "本工具不内置商业题库，只带原创样例——你的题库由你自己导入。\n"
                + "支持 CSV、JSON 和文字版 PDF（雅思季度题库通常是 PDF）。\n"
                + "现在没有也没关系，之后在「训练题库」页随时能导。"
        case .recordingChoice:
            return "开启后，练习时会用麦克风录下你的回答，练完能回听自己的发音、语调和卡顿。\n"
                + "这个开关默认关闭。录音只存在本机的数据目录里，不上传，随时可以单条删除。\n"
                + "只录你自己的声音，不录 ChatGPT——考官问了什么由逐字稿给文字。"
        case .ready:
            // 计划初稿写的是「点「开始」就行」，而首页那颗按钮叫「开始练习」——
            // 指一颗不存在的按钮比不写还糟，用户会一直找
            // （`RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists` 当场抓到了）。
            //
            // ⚠️ 这段话从前只有第一句「首页已经给你排好今天练什么了」。那句话当时是假的：
            // 导入题库不生成计划，没有计划「按计划练今天」那张卡片整块不显示，
            // 首页排得出来的唯一路线是「从题库自由选题」——每一场都得自己从整份题库里挑
            //（2026-08-08 复审第 9 条）。现在第一次导入题库会顺手排好一份计划
            //（`PlanBootstrap`），但**题目少于 7 道、或者跳过了导入题库那一步**时仍然排不出来，
            // 所以这里两种情形都得说到，不能只说排好的那一种。
            return "首页「今天练什么？」那一段就是每天的入口，点「开始练习」开练。\n"
                + "刚导进来的题库已经替你排成了一份学习计划，今天练哪几道都定好了；"
                + "题目太少（不足 7 道）或者你跳过了导入那一步的话，"
                + "首页会先请你导题库，导完随时能在「学习计划」页排一份。\n"
                + "练完会自动归档复盘、错题、词汇和下次的重点目标，你只要关掉窗口。"
        }
    }

    /// 这一步的主行动叫什么。
    ///
    /// ## 两处与计划初稿不同，都是为了不让按钮说假话
    ///
    /// **`.environment` 是「打开系统设置」而不是「打开系统设置去授权」**：这一步整块复用
    /// Phase 3 的 `PermissionGateView`（计划 Step 6 明写「不要另写一套说同一件事的界面」），
    /// 而那一页上本来就有一颗 `Button("打开系统设置")`。流程页再画一颗只会在同一屏上出现
    /// 两颗写着几乎一样的字的按钮，用户不知道该点哪个。所以这里给的名字要与那颗**逐字相同**，
    /// `OnboardingFlowTests.testTheEnvironmentStepPointsAtAButtonThatReallyExists` 查这件事——
    /// 哪天那颗按钮改了名，这条会红，逼人把两边一起改。
    ///
    /// **`.recordingChoice` 是「继续」而不是「保持关闭」**：计划初稿让流程页自己画一个开关，
    /// 后来被跨阶段复审推翻，改成内嵌 Phase 5 的 `RecordingSettingsView`（那才是唯一一处
    /// 「问权限 → 拿到 granted 才写盘」的实现）。开关既然在页面上，用户完全可能刚把它拨开，
    /// 而下面那颗前进按钮还写着「保持关闭」——界面在说一件不成立的事。
    public var primaryActionTitle: String {
        switch self {
        case .welcome: return "开始设置"
        case .environment: return "打开系统设置"
        case .questionBank: return "现在导入题库…"
        case .recordingChoice: return "继续"
        case .ready: return "开始使用"
        }
    }

    /// welcome / ready 只是叙述，没有可跳过的东西；
    /// recordingChoice 本身就是一个二选一（保持关闭也是一种选择），给「跳过」反而含糊。
    ///
    /// 换个角度看这条规则会更清楚：**可跳过的正是那两步「主按钮按下去不会前进」的**
    /// （打开系统设置、挑一个题库文件）。它们要是没有「先跳过」，用户就没有前进的路了。
    public var canSkip: Bool {
        switch self {
        case .environment, .questionBank: return true
        case .welcome, .recordingChoice, .ready: return false
        }
    }
}

public enum OnboardingFlow {
    /// 引导内容大改时把它加 1，老用户会再看一次。
    /// 不留这个口子的话，改了引导也没人看得到。
    public static let currentVersion = 1

    public static func steps(permission: PermissionState, questionCount: Int,
                             hasCompletedBefore: Bool) -> [OnboardingStep] {
        guard hasCompletedBefore else {
            var steps: [OnboardingStep] = [.welcome, .environment]
            // 题库已经有题（多半是把数据目录拷过来的），就别再让他导一次——
            // 那会让人怀疑自己的数据没拷成功。
            if questionCount == 0 { steps.append(.questionBank) }
            steps.append(.recordingChoice)
            steps.append(.ready)
            return steps
        }
        // 已经走过引导的人，只有一种情况会再看到它：环境不就绪。
        // 最典型的就是换了一台电脑——数据拷过来了，但辅助功能授权是本机 TCC 的，必须重给。
        return permission == .ready ? [] : [.environment]
    }

    public static func shouldPresent(permission: PermissionState, questionCount: Int,
                                     hasCompletedBefore: Bool) -> Bool {
        !steps(permission: permission, questionCount: questionCount,
               hasCompletedBefore: hasCompletedBefore).isEmpty
    }
}
