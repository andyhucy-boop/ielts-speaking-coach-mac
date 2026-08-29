import Foundation

public struct PracticeSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String                  // "YYYY-MM-DD-NNN"
    public var questionId: String
    public var focusPart: FocusPart
    public var startedAt: String
    public var endedAt: String
    public var goal: String                // 本次的单点目标，可为空
    public var transcript: [TranscriptTurn]
    public var reportPath: String          // reports/<id>.json，未完成时为空
    public var recordingPath: String       // 未录音时为空

    /// 非 nil 表示这是一场复训会话（Phase 6）。普通练习为 nil。
    /// Optional 属性由 Swift 合成的解码器走 decodeIfPresent，
    /// 因此不带这个键的历史记录仍然能正常读出来——不要改成非 Optional。
    public var retraining: RetrainingLink?

    /// 随机抽题抽出来的**整组**题目 id（含 `questionId` 那一道）。
    /// 普通练习是 nil——那一场就练 `questionId` 一道。
    ///
    /// ## 为什么必须存下来
    ///
    /// 「这道题练没练过」全工程只认一个标记：`Question.status == "practiced"`，
    /// 而它的唯一真凭实据是 `CoachState.reconcilePracticedStatus`——那段代码读的是
    /// 练习记录里的题目 id。随机抽题一场抽 5 道全练了，只记下开场那一道的话：
    ///
    /// - 「只抽没练过的」会把另外 4 道当成新题，一遍遍再抽给他；
    /// - 训练题库页那个「已练 N / 258」永远少数 4 道，而屏幕上没有任何异样。
    ///
    /// 两样都是本项目最忌讳的静默错账，所以这一组 id 必须落盘。
    ///
    /// **Optional 且带默认值**：Swift 合成的编码器对 Optional 走 `encodeIfPresent`，
    /// 所以普通练习写出去的 state.json 一个字节都没变（与 `retraining` 同一套做法），
    /// 旧版本 App 与上游 Windows 版照样读得出来。
    ///
    /// **口径是「这一场安排了哪几道」，不是「他真的答完了哪几道」**：这一组 id 在
    /// **点「我练完了」那一刻**随整条记录一起落盘（`PracticeRunner.finishPractice`
    /// → `upsertSession`），与开场那一道题的既有口径完全一致。
    /// 换成「答完才算」需要逐题回执，而语音会话里根本拿不到那种回执。
    ///
    /// > **更正（2026-08-20 晚）**：这段话原先写的是「练习记录在开练那一刻就建好了，
    /// > 中途放弃同样会留下这一组 id」。**两句都是反的。**
    /// > `upsertSession` 全工程只有两个调用点，都在收尾链路上（`finishPractice`
    /// > 与 `archive`）；而 `cancel()` 一个字都不写盘——放弃那一场既不进训练记录，
    /// > 也不会把任何题标成已练。行为本身没问题，写错的是这段说明。
    public var drawnQuestionIds: [String]?

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    //
    // `drawnQuestionIds` **带默认值且排在最后**：这是随机抽题追加的字段，
    // 前面所有阶段的调用点（复训、命令行、各处测试）一处都不用改。
    public init(id: String, questionId: String, focusPart: FocusPart, startedAt: String,
                endedAt: String, goal: String, transcript: [TranscriptTurn],
                reportPath: String, recordingPath: String,
                retraining: RetrainingLink? = nil,
                drawnQuestionIds: [String]? = nil) {
        self.id = id; self.questionId = questionId; self.focusPart = focusPart
        self.startedAt = startedAt; self.endedAt = endedAt; self.goal = goal
        self.transcript = transcript; self.reportPath = reportPath
        self.recordingPath = recordingPath; self.retraining = retraining
        self.drawnQuestionIds = drawnQuestionIds
    }

    enum CodingKeys: String, CodingKey {
        case id, questionId, focusPart, startedAt, endedAt, goal
        case transcript, reportPath, recordingPath, retraining, drawnQuestionIds
    }

    /// 这一场安排到的全部题目 id，开场那道排在最前面，去重、去空串。
    ///
    /// **凡是要问「这一场练了哪些题」的地方一律用它**，不要直接读 `questionId`：
    /// 直接读的那几处会把随机抽题的一场当成只练了一道题（见 `drawnQuestionIds` 的说明）。
    public var allQuestionIds: [String] {
        var ids: [String] = []
        for id in [questionId] + (drawnQuestionIds ?? [])
        where !id.isEmpty && !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// 手写解码，只为一件事：**一条记录里的一个字段坏掉，不许把整份训练数据挡在门外。**
    ///
    /// 合成的解码器对 `focusPart` 要求必须是 `"Part 1"/"Part 2"/"Part 3"/"full mock"`
    /// 四个字符串之一，否则抛 `dataCorrupted`；缺任何一个非 Optional 字段则抛
    /// `keyNotFound`。这两个错都会一路冒泡到 `StateStore`，用户开 App 读到的是
    /// 「训练数据文件已损坏，无法读取……下一步：把该文件改名备份后重新启动，
    /// App 会新建一份空白记录」——**练习记录、错题本、词汇本、复训目标、计划、题库、
    /// 设置全部一起读不出来**，而坏掉的只是某一条记录里的一个字段。
    /// 文件其实还完整躺在硬盘上，真正作废发生在用户照着那句提示改名之后。
    ///
    /// 触发来源都是真实的，不是理论：
    /// - **本工具自己的错误提示会引导用户去手改这个文件**（`RecordingStore.url(forRelativePath:)`
    ///   那句「打开数据目录里的 state.json，检查这一条的 recordingPath 字段」），人打开了就可能打错；
    /// - 从上游 Windows/JS 版带过来的数据；
    /// - 将来给 `FocusPart` 加了新 case 之后，回退或跨机同步到的旧版本 App。
    ///
    /// 策略与 `TrainingPlan` / `CoachSettings` 那两处完全一致：认不出来就退回默认值。
    /// 代价是那一条记录的 Part 标签显示得不准，换整份数据还能打开——不成比例的是反过来。
    ///
    /// **这个代价是永久的，要清楚**：退回默认值之后，下一次写盘就会把那个认不出来的
    /// 字符串换成 `"full mock"`，用户原来打错的那几个字看不到了。
    /// 留着原文需要多一个存储字段（会改内存布局，也会改 state.json 的形状）；
    /// 权衡下来不值——真正要紧的是别让他的全部历史被一个字段挡在门外。
    ///
    /// **`id` 是唯一仍然必需的字段，而且必须继续必需**：没有 id 的记录在界面上无法寻址
    /// （列表唯一键、删除、复盘、复训全靠它），兜一个空串会让两条这样的记录在
    /// SwiftUI 的 `ForEach` 里撞成同一行。
    ///
    /// 编码仍由 Swift 合成——只手写 Decodable 那一半时不影响 Encodable 的合成
    /// （与 `CoachSettings`、`IssueRecord` 一致），所以写出去的文件形状一个字都没变，
    /// 拿回上游版本照样读得出来。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        questionId = Self.tolerantString(c, .questionId)
        // 先按字符串读再转枚举：**枚举的 decodeIfPresent 只挡「键不存在」，
        // 遇到不认识的字符串照样抛 dataCorrupted**，那一层不能省。
        focusPart = FocusPart(rawValue: Self.tolerantString(c, .focusPart)) ?? .fullMock
        startedAt = Self.tolerantString(c, .startedAt)
        endedAt = Self.tolerantString(c, .endedAt)
        goal = Self.tolerantString(c, .goal)
        // 逐字稿整段的类型都被改坏时（写成了字符串之类）退回空数组。
        // 单独一句缺字段不会走到这里——`TranscriptTurn` 自己也容错。
        transcript = ((try? c.decodeIfPresent([TranscriptTurn].self, forKey: .transcript)) ?? nil) ?? []
        reportPath = Self.tolerantString(c, .reportPath)
        recordingPath = Self.tolerantString(c, .recordingPath)
        // 复训链接坏掉时退回「这不是一场复训」：复训进度不准，好过整份数据打不开。
        retraining = (try? c.decodeIfPresent(RetrainingLink.self, forKey: .retraining)) ?? nil
        // 同一套容错：这一组 id 坏掉时退回「这不是随机抽题的一场」。
        // 代价是那几道题的「已练」标记算不回来，换整份训练数据还能打开。
        drawnQuestionIds = ((try? c.decodeIfPresent([String].self, forKey: .drawnQuestionIds)) ?? nil)
            .map { $0.filter { !$0.isEmpty } }
    }

    /// 键不存在、值是 null、值的类型不对——三种都退回空串，不抛错。
    /// `decodeIfPresent` 只挡前两种，所以外面还要包一层 `try?`。
    private static func tolerantString(_ c: KeyedDecodingContainer<CodingKeys>,
                                       _ key: CodingKeys) -> String {
        ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil) ?? ""
    }

    public struct TranscriptTurn: Codable, Equatable, Sendable {
        public var role: String            // "user" | "assistant"
        public var text: String
        public var capturedAt: String

        // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
        public init(role: String, text: String, capturedAt: String) {
            self.role = role; self.text = text; self.capturedAt = capturedAt
        }

        enum CodingKeys: String, CodingKey { case role, text, capturedAt }

        /// 同一个理由，往下再走一层：逐字稿里**一句**的一个字段坏掉，
        /// 不许把这一整场（进而把整份 state.json）拖下水。
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = ((try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil) ?? ""
            text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
            capturedAt = ((try? c.decodeIfPresent(String.self, forKey: .capturedAt)) ?? nil) ?? ""
        }
    }
}
