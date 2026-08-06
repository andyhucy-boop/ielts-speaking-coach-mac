import Foundation

/// 这次练习到底录不录。
public enum RecordingReadiness: Equatable, Sendable {
    case ready
    /// 用户没开开关。这是**默认状态，不是故障**——界面不该为此报警，
    /// 也不该显示「正在录音」的指示。
    case disabledByUser
    /// 开关开着却录不了。message 是中文，且写明了发生了什么与下一步做什么。
    /// 这种情况**必须让用户看见**：他以为在录，实际没录。
    case blocked(String)
}

/// 「保存我的回答录音」开关与同意时间戳的全部规则。纯函数，不做任何 IO。
public enum RecordingConsent {
    /// 打开开关并记下同意时间。已经打开且已有时间戳时原样返回——
    /// 同意是一次性的事实，不该被重复点击刷新成「刚刚同意」。
    ///
    /// **必须「复制后就地改两个字段」，绝不能用 `CoachSettings(recordingEnabled:recordingConsentAt:)`
    /// 重新构造一个。** `CoachSettings` 已经有 `transcriptEnabled`（Phase 4），后续阶段还会加
    /// （Phase 7 的 `weeklyGoal`、Phase 8 的 `defaultRoute` / `feedbackTiming` / `part2PrepMode`），
    /// 而那些新参数都带默认值——重新构造会**编译通过、测试全绿**，然后在用户每次拨动录音开关时
    /// 把他的逐字稿开关、每周目标、默认路线、反馈时机悄悄重置回默认值。这正是本项目最忌讳的
    /// 失败形态：不报错、不崩溃、只是设置自己变回去了。
    /// 守着这条的是 `testTogglingRecordingLeavesEveryOtherSettingAlone`。
    public static func enable(_ settings: CoachSettings, at timestamp: String) -> CoachSettings {
        if settings.recordingEnabled && !settings.recordingConsentAt.isEmpty { return settings }
        var updated = settings
        updated.recordingEnabled = true
        updated.recordingConsentAt = timestamp
        return updated
    }

    /// 关掉开关并清空同意时间。关掉等于撤回同意，下次再开必须重新记一次。
    /// 同样只改这两个字段，其余设置原样保留（理由见 `enable` 上面那段注释）。
    public static func disable(_ settings: CoachSettings) -> CoachSettings {
        var updated = settings
        updated.recordingEnabled = false
        updated.recordingConsentAt = ""
        return updated
    }

    /// 顺序有意义：**先看开关，再看权限，最后看同意记录。**
    /// 开关关着时连问都不用问权限——那是用户的意愿，压过一切。
    public static func readiness(settings: CoachSettings,
                                 permission: MicrophonePermissionState) -> RecordingReadiness {
        guard settings.recordingEnabled else { return .disabledByUser }
        guard permission == .granted else {
            return .blocked(permission.guidance
                ?? "麦克风权限状态未知，这次不会录音。"
                 + "下一步：到「录音设置」（⌘,）把开关关掉再打开一次。")
        }
        guard !settings.recordingConsentAt.isEmpty else {
            return .blocked("录音开关是开的，但没有记录到你同意的时间，为稳妥起见这次不录音。"
                + "下一步：到「录音设置」（⌘,）把开关关掉再打开一次，就会重新记一次同意时间。")
        }
        return .ready
    }
}
