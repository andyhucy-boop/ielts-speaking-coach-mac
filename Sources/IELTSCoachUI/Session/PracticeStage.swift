import Foundation

/// 一场练习走到哪一步，以及**这一步要对用户说什么**。
///
/// 单独分出来是因为「阶段 → 界面文案」是纯逻辑，可以单元测试；而 `View` 几乎测不了。
/// 判据照本项目一贯的那条：把 `userFacingText` 改成空实现，`PracticeRunnerTests` 会不会红。
///
/// **每一步都必须有话说。** 整条链路里最长的一步是启动语音——实测约 9 秒
/// （spec 2.3.7），中间界面一个像素都不动的话，用户会以为程序卡死然后去强退，
/// 而那时 ChatGPT 那边的语音通话已经开起来了（DESIGN-SYSTEM 第 5 节）。
public enum PracticeStage: Equatable, Sendable {
    /// 还没开始，或者已经取消。
    case idle
    case newChat
    case startingVoice
    case waitingComposer
    case sendingPrompt
    /// 考官提示词已经发过去，现在轮到用户说话。
    case practicing
    case endingVoice
    case requestingReview
    case capturingReview
    /// 两条自动取复盘的路都没走通，等用户在 ChatGPT 里手动 ⌘C。
    ///
    /// **这不是失败态。** 复盘这时完整地留在 ChatGPT 窗口里，用户复制一次就能救回来；
    /// 判成失败等于让他把练了半小时换来的那份东西白丢（成品标准第 7 条）。
    case needsManualCopy(String)
    case archiving
    case done
    case failed(String)
    /// 用户中途按了「放弃这一场」或「取消」，这一场就此打住。
    ///
    /// **它不是 `.idle` 的同义词，专门分出来是有原因的**：`.idle` 那句话写着
    /// 「下一步：点「开始练习」」，而放弃之后界面上根本没有这颗按钮，用户照着找会找不到
    /// （铁律 4）。更要紧的是，放弃这一刻有三件事必须当场交代清楚，而 `.idle` 一件都说不了：
    /// ChatGPT 那边的语音通话还要不要用户自己挂、已经采到的逐字稿去哪儿了、
    /// 已经录下的那一段留在哪儿。带的这段字符串就是那份交代。
    case abandoned(String)

    /// 这一步在整场练习里的先后次序，**只**用于界面把已经走完的步骤打上勾。
    ///
    /// `failed` 与 `abandoned` 给 -1：这两种收场都不该有任何一步显示成「已完成」，
    /// 那会让用户以为只差最后一点点。
    /// `needsManualCopy` 与 `capturingReview` 同格：它就停在取复盘这一步上等人。
    public var order: Int {
        switch self {
        case .failed, .abandoned: return -1
        case .idle: return 0
        case .newChat: return 1
        case .startingVoice: return 2
        case .waitingComposer: return 3
        case .sendingPrompt: return 4
        case .practicing: return 5
        case .endingVoice: return 6
        case .requestingReview: return 7
        case .capturingReview, .needsManualCopy: return 8
        case .archiving: return 9
        case .done: return 10
        }
    }

    /// 界面上那行「现在在干什么」。每一步说的都必须是这一步的事——
    /// 全都写成「请稍候…」的话，用户没法判断程序是在干活还是已经卡住了。
    public var userFacingText: String {
        switch self {
        case .idle:
            return "还没开始。下一步：点「开始练习」，本工具会自动打开 ChatGPT、进语音、"
                + "并把考官提示词发过去，你什么都不用输。"
        case .newChat:
            return "正在新建会话…语音只能在一条还没发过任何消息的会话里启动，所以这一步必须最先做。"
        case .startingVoice:
            return "正在启动语音…这一步大约要等 10 秒，是 ChatGPT 自己的启动耗时，不是卡住了。"
        case .waitingComposer:
            return "语音起来了，正在等语音模式的输入框出现…这一步通常几秒钟。"
        case .sendingPrompt:
            return "正在把今天这道题的考官提示词发给 ChatGPT…"
        case .practicing:
            return "开练了，直接对着 ChatGPT 说英语就行。"
                + "下一步：说完之后回到这里点「我练完了」，复盘会自动取回并存档。"
        case .endingVoice:
            return "正在结束语音通话…"
        case .requestingReview:
            return "正在请 ChatGPT 写复盘，并等它写完…这一步可能要一分钟左右。"
        case .capturingReview:
            return "正在把复盘取回来…"
        case .needsManualCopy(let message):
            return message
        case .archiving:
            return "正在把复盘存档，并更新错题本、词汇本和复训目标…"
        case .done:
            return "这一场结束了，复盘已经存档。下一步：到「复盘报告」页看这次的结果，"
                + "或者直接关掉这个窗口。"
        case .failed(let message):
            return message
        case .abandoned(let message):
            return message
        }
    }

    /// 这一步该不该画那列进度清单。
    ///
    /// **失败与放弃都不画**：两者的 `order` 都是 -1，一格都不会打勾，
    /// 画出来只是一列灰圈，反而把真正要读的那段话（失败原因 / 放弃之后的交代）挤下去。
    public var showsChecklist: Bool {
        switch self {
        case .failed, .abandoned: return false
        default: return true
        }
    }

    /// 这一步的短名字。用在进度清单上，以及失败信息的开头（「哪一步没成功」）。
    ///
    /// 失败信息不写清断在哪一步的话，用户拿到的是一句孤零零的技术报错，
    /// 既不知道练习有没有真的开始，也不知道该重练还是只需重取复盘（铁律 6）。
    public var stepName: String {
        switch self {
        case .idle: return "准备"
        case .newChat: return "新建会话"
        case .startingVoice: return "启动语音"
        case .waitingComposer: return "等语音输入框出现"
        case .sendingPrompt: return "发考官提示词"
        case .practicing: return "练习中"
        case .endingVoice: return "结束语音"
        case .requestingReview: return "请 ChatGPT 写复盘"
        case .capturingReview, .needsManualCopy: return "取回复盘"
        case .archiving: return "存档复盘"
        case .done: return "完成"
        case .failed: return "失败"
        case .abandoned: return "放弃"
        }
    }

    /// 这一步还在自动跑（界面要显示转圈），还是在等用户动作 / 已经走完。
    public var isBusy: Bool {
        switch self {
        case .idle, .practicing, .needsManualCopy, .done, .failed, .abandoned: return false
        default: return true
        }
    }
}
