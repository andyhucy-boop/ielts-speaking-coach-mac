import Foundation

/// 一次发布改了什么。
public struct ReleaseNote: Equatable, Identifiable, Sendable {
    public var id: String { version }
    public let version: String
    public let date: String
    /// 一句话概括。用户扫一眼就知道这一版值不值得换。
    public let headline: String
    public let changes: [String]

    public init(version: String, date: String, headline: String, changes: [String]) {
        self.version = version; self.date = date
        self.headline = headline; self.changes = changes
    }
}

public enum PhaseStatus: String, Equatable, Sendable {
    case shipped
    case inProgress
    case planned

    /// 页面上出现 "inProgress" 这种词，对用户等于没写。
    public var title: String {
        switch self {
        case .shipped: return "已完成"
        case .inProgress: return "进行中"
        case .planned: return "还没开始"
        }
    }
}

/// 一个阶段。**summary 写的是「用户因此能做什么」，不是「实现了什么类」。**
public struct PhaseMilestone: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let title: String
    public let summary: String
    public let status: PhaseStatus

    public init(label: String, title: String, summary: String, status: PhaseStatus) {
        self.label = label; self.title = title
        self.summary = summary; self.status = status
    }
}

/// 版本记录与阶段进展。
///
/// **手工维护，运行时不读 git。** 打包出去的 `.app` 里没有 git 仓库，
/// 也不走 SPM 的资源包——`scripts/build-app.sh` 只拷可执行文件，
/// `Bundle.module` 在 `.app` 里会 fatalError，表现是「开发时好好的，
/// 打成 App 一点这一页就闪退」。
///
/// **改这里的时候记得同步 `scripts/build-app.sh` 里的 `APP_VERSION`**——
/// `PackagingContractTests` 有一条测试盯着这两处。
public enum Changelog {

    public static let releases: [ReleaseNote] = [
        ReleaseNote(
            version: "1.2.0",
            date: "2026-08-20",
            headline: "对着上游把漏掉的东西补回来了：练前能定目标，练完不再丢复盘。",
            changes: [
                "开练前可以写一句「这一场只盯什么」，考试中考官不提它，只有复盘针对它给反馈",
                "「点我练完了」那一刻更稳了：等 ChatGPT 写完复盘有了准确的判据；"
                    + "格式不对会自动把哪里不对告诉它、让它重出一份",
                "复盘丢了能补回来：复盘报告页新增「从剪贴板补录这一场的复盘」",
                "开练那一刻就存档，中途崩溃或误关窗口不再丢掉整场；下次开 App 会问你要不要留着",
                "复盘多两节：「这几句你说对了」，以及每条错误配一个 30 秒练法",
                "「下次只盯这一个」会附一句可自查的达标线，卡片上多一颗「带着这条去复训」",
                "ChatGPT 万一写了雅思分数，会被挡在总结之外并说明（本工具从不给分）",
                "题库页和开练弹层都能按关键词搜题了（题干、话题、参考问句一起搜）",
                "训练记录每一场显示时长；首页多一排本周七天的柱子",
                "答砸的题可以在「训练题库」页标回「没练过」，让它重新参与抽题",
                "复盘报告页可以直接回听这一场的录音（需先开启录音）",
                "复训「重答原题」那一步会给一个答题骨架：观点 → 因为… → 一个具体例子 → 所以…"
            ]),
        ReleaseNote(
            version: "1.1.0",
            date: "2026-08-20",
            headline: "多了「随机抽题」，复盘多了一节「内容建议」。",
            changes: [
                // 每一条都要对得上界面上真有的字：用户是照着这几句去找控件的
                //（`RenderReachabilitySweepTests` 会把不存在的控件名当幽灵报出来）。
                "今日训练页新增「随机抽题练一场」：自己定 Part 1 / 2 / 3 各抽几道，剩下的交给运气",
                "抽题时可以勾「只抽没练过的题」；抽不够会当场说清是题库不够还是这个勾选造成的",
                "抽到的题会一整套发给考官：抽几个话题就问几个，抽几张卡就做几张，"
                    + "Part 3 会接着抽到的那张卡往下讨论",
                "复盘报告多一节「内容建议」：专门指出哪句话说得空、可以补什么、可以怎么说",
                "复盘里的示范不会替你编个人经历——要补个人细节而证据不足时，它会写明「请按真实情况调整」"
            ]),
        ReleaseNote(
            version: "1.0.0",
            date: "2026-08-06",
            headline: "第一个能给别人的版本：双击就能开练，练完自动归档。",
            changes: [
                "今日训练、训练题库、学习计划、复训中心、复盘报告、训练记录、问题档案、我的词汇都能用了",
                // 按钮的真名是「开始练习」。计划里这一条写的是「点一下「开始」」，
                // 而全 App 没有一颗叫「开始」的按钮——`RenderReachabilitySweepTests`
                // 当场把它报成了幽灵控件。更新记录同样是给用户照着找的文字，不能例外。
                "点一下「开始练习」就会自动打开 ChatGPT、进语音、发考官提示词，全程不用碰终端",
                "练完自动取回复盘并归档到错题本、词汇本与下次的重训目标",
                "可选开启录音，练完能回听自己的回答，可单条删除",
                "支持 CSV / JSON / 文字版 PDF 导入自己的题库",
                "深色模式，跟随系统外观",
                "设置合并成一个窗口（⌘,）：录音、训练目标、练习偏好、数据与隐私",
                "能在 Codex 里通过 MCP 调用，也能用 ieltscoach:// 唤起界面"
            ])
    ]

    public static var current: ReleaseNote { releases[0] }

    /// 打开这一页时哪几条更新记录是展开的：**只有最新那一条**。
    ///
    /// 全收起来的话，用户点进这一页只看得到一行版本号——那正是它作为占位页时的样子；
    /// 全展开则是一页翻不完的历史，最新那一条反而找不着。
    ///
    /// 写成收参数的纯函数而不是视图里的一句 `[current.version]`，
    /// 是为了让这条规则本身能被测试拿两条以上的记录问一遍——只有一条记录时，
    /// 「只展开最新的」和「全都展开」是同一个答案，断言不到任何东西。
    public static func defaultExpandedVersions(
        of releases: [ReleaseNote] = Changelog.releases) -> Set<String> {
        Set(releases.prefix(1).map(\.version))
    }

    /// 顶上那行「当前版本」和这份更新记录最新一条对不对得上。**对得上返回 nil。**
    ///
    /// 一直挂着的提示等于没有提示，所以只在真对不上时才出声。
    ///
    /// 两种对不上，说法不能混：
    ///
    /// - **从源码直接跑**（`swift run IELTSCoachApp`）时没有 App bundle，
    ///   `AppMetadata` 每个字段都是「未知（开发运行）」。这一页因此会同时显示
    ///   「未知（开发运行）」和一个具体版本号——不解释一句，看着就像这一页坏了。
    /// - **手上是一份真打出来的 `.app`，只是这张表还没补上那一版。**
    ///   这时照抄上面那句「多半是开发版本」就是一句假话，还会让人去跑一个不需要跑的脚本。
    ///   （正常情况下它不该发生：`PackagingContractTests` 盯着这张表的最新版本号
    ///   与 `build-app.sh` 里的 `APP_VERSION` 一致。）
    public static func versionNotice(
        runningShortVersion running: String,
        newestVersion newest: String = Changelog.current.version) -> String? {
        guard running != newest else { return nil }
        if running == AppMetadata.unknownValue {
            return "你现在跑的是「\(running)」，下面这份更新记录里最新的是 \(newest)。"
                + "下一步：这多半是从源码直接运行的开发版本——它没有 App 的版本信息可读，"
                + "不是这一页出了问题；跑 scripts/build-app.sh 打成 .app 再打开，"
                + "这里就会显示真实的版本号与构建时间。"
        }
        return "你现在跑的是 \(running)，下面这份更新记录里最新的是 \(newest)。"
            + "下一步：以顶上那行版本号为准——这张表还没补上你手上这一版，"
            + "它只影响你在这一页读到什么，不影响 App 的任何功能。"
    }

    /// 本项目的十个阶段（ROADMAP 第 4 节，Phase 0–1 合并算一个）。
    /// **每一条写的是「你因此能做什么」**，不是「实现了哪个类」——
    /// 这一页是给使用者看的，不是给开发者看的。
    ///
    /// `status` 按仓库的真实情况写：Phase 0–9 的代码都在（练习、逐字稿、录音、复训、
    /// 问题档案、词汇本、学习计划各自的页面都能点进去，`ielts-speaking-mcp` 也在），
    /// Phase 10 正做到一半（打包脚本、关于页、引导已经有了，公证与真机验收还没走完）。
    /// **不为了页面好看全标成已完成**——这一页的全部价值就是「它说的是真的」。
    public static let phases: [PhaseMilestone] = [
        PhaseMilestone(label: "0–1", title: "探路与地基",
                       summary: "把「能不能用辅助功能驱动 ChatGPT」这件事在真机上试通，并搭好数据存储。",
                       status: .shipped),
        PhaseMilestone(label: "2", title: "驱动与命令行",
                       summary: "完整跑通一场练习：新建会话、启动语音、发提示词、判断结束、取回复盘。",
                       status: .shipped),
        PhaseMilestone(label: "3", title: "图形界面骨架",
                       summary: "有了能双击打开的 App：选题、开练、看复盘不用再开终端。",
                       status: .shipped),
        PhaseMilestone(label: "4", title: "逐字稿与训练记录",
                       summary: "每次练习留下完整问答记录，按月回看考官问了什么、你怎么答的。",
                       status: .shipped),
        PhaseMilestone(label: "5", title: "录音与回听",
                       summary: "可选录下自己的回答，练完回听发音、语调和卡顿。默认关闭。",
                       status: .shipped),
        PhaseMilestone(label: "6", title: "复训中心",
                       summary: "从复盘里挑一个目标带着重练，再换一道题验证是真会了还是只记住了答案。",
                       status: .shipped),
        PhaseMilestone(label: "7", title: "问题档案与词汇本",
                       summary: "看见反复出现的问题有没有变少，积累的词汇可以导出。",
                       status: .shipped),
        PhaseMilestone(label: "8", title: "学习计划与练习路线",
                       summary: "7/14/30 天计划、重点 Part，四条练习路线全部可用。",
                       status: .shipped),
        PhaseMilestone(label: "9", title: "在 Codex 里调用",
                       summary: "通过 MCP 在 Codex 里查题、开练、存复盘，也能直接唤起界面。",
                       status: .shipped),
        PhaseMilestone(label: "10", title: "打包与分发",
                       summary: "签名稳定所以授权不会反复失效，数据目录拷到另一台电脑就能接着用，"
                           + "并且这份 App 可以直接交给别人。",
                       status: .inProgress)
    ]
}
