import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import Observation

/// 「保存我的回答录音」这一页的全部逻辑。**视图里不许再判一次「能不能录」**——
/// 那条规则只留在 `RecordingConsent` 与这里，两处各判一次迟早会走岔。
@MainActor
@Observable
public final class RecordingSettingsViewModel {
    /// 开关的当前值 = **这一刻到底录不录**，也就是「磁盘上存着同意」**且**「麦克风权限在手里」。
    ///
    /// 权限没拿到时它必须是 false——显示成「开」却什么都不录，
    /// 用户练完发现没录音时完全无从查起。这有两条路会走到：
    ///
    /// 1. 拨开关的当下就没拿到权限（`setEnabled` 里那条 guard）；
    /// 2. **先前在有权限时开过，后来权限没了**——用户在系统设置里关掉了麦克风，
    ///    或换了台机器 / 重装后 TCC 被重置。这时磁盘上仍写着 `recordingEnabled=true`，
    ///    而 `RecordingConsent.readiness` 会判 `.blocked`，练习一秒都不会录。
    ///    照着磁盘显示成「开」，界面就在说一件不成立的事。
    ///
    /// 所以这里存的**不是**磁盘原值。磁盘上那句「同意」由 `consentAt` 照实反映：
    /// 它不会因为权限没了就被抹掉（那是用户给过的授权，`refresh()` 更不该反过来写盘），
    /// 权限给回来之后开关自己回到「开」。两条都由
    /// `testTheSwitchGoesBackToOffWhenThePermissionIsRevokedAfterConsent` 与
    /// `testTheSwitchIsOnAgainOnceThePermissionComesBack` 守着。
    public private(set) var enabled = false
    /// 磁盘上记的那次同意的时间戳。空串 = 没同意过。
    /// **它跟着磁盘走，不跟着权限走**——理由见 `enabled`。
    public private(set) var consentAt = ""
    public private(set) var permission: MicrophonePermissionState = .notDetermined
    /// 非 nil 时界面必须显示。中文，写明发生了什么与下一步做什么。
    public private(set) var notice: String?
    public private(set) var usage = RecordingUsage(count: 0, bytes: 0)
    /// 磁盘上有、但没有训练记录指向的录音。非 nil 时界面必须显示。
    public private(set) var orphanNotice: String?
    /// 正在等系统权限对话框时为 true，界面据此禁用开关，避免连点。
    public private(set) var isWorking = false

    private let store: StateStore
    private let recordings: RecordingStore
    private let authorizer: any MicrophoneAuthorizing
    private let now: () -> Date

    public init(store: StateStore, recordings: RecordingStore,
                authorizer: any MicrophoneAuthorizing,
                now: @escaping () -> Date = Date.init) {
        self.store = store
        self.recordings = recordings
        self.authorizer = authorizer
        self.now = now
        refresh()
    }

    /// 重新读一遍磁盘上的事实。**不清 notice**——用户刚做完的那个操作
    /// 说了什么，不该因为刷新一下就消失。
    public func refresh() {
        permission = authorizer.currentStatus()
        do {
            let state = try store.load()
            // 磁盘上的同意 **且** 权限还在手里，才算「开」。少了后半句，
            // 用户事后在系统设置里关掉麦克风之后，这一页会一直显示「开」而一秒都不录。
            enabled = state.settings.recordingEnabled && permission == .granted
            consentAt = state.settings.recordingConsentAt
            usage = try recordings.usage()

            var referenced = state.sessions.map(\.recordingPath)
            if let current = state.currentSession { referenced.append(current.recordingPath) }
            let orphans = try recordings.orphanFileNames(referencedPaths: referenced)
            orphanNotice = orphans.isEmpty ? nil
                : "有 \(orphans.count) 个录音文件在磁盘上，但没有任何训练记录指向它们"
                + "（多半是练习中途出错留下的）。"
                + "下一步：确认不需要之后，点下面的「打开录音文件夹」自己删掉；"
                + "本应用不会替你删任何录音。"
        } catch {
            notice = "读不到录音设置：\(error.localizedDescription)"
                + "\n下一步：确认数据目录（~/Library/Application Support/IELTS Speaking Coach/）"
                + "存在且可读写，然后重新打开这一页。"
        }
    }

    public func setEnabled(_ turnOn: Bool) async {
        isWorking = true
        defer { isWorking = false }
        notice = nil

        guard turnOn else {
            guard persist(RecordingConsent.disable) else { return }
            notice = "已关掉录音。已经录下的录音不会被删除。"
                + "若现在正有一场练习在进行，这一次仍会录完（文件已经在写了），下一次起不再录音。"
                + "下一步：想删已有录音的话，到「训练记录」页逐条删，或点下面的「打开录音文件夹」。"
            return
        }

        var status = authorizer.currentStatus()
        if status.canPrompt {
            // 这一步会弹出系统对话框。**只有用户本人能点「允许」**，任何自动化都替不了。
            // 被拒过的状态下不能走到这里——系统不会再弹，用户会对着界面干等。
            status = await authorizer.requestAccess()
        }
        permission = status

        guard status == .granted else {
            // 关键：权限没拿到就绝不能把开关置成开，也绝不能写进 state.json。
            enabled = false
            notice = status.guidance
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        guard persist({ RecordingConsent.enable($0, at: timestamp) }) else { return }
        notice = "已开启。从下一次练习开始，你的回答会录在本机的 recordings 目录里，"
            + "只存在这台电脑上，不上传任何地方，随时可以逐条删除。"
            + "下一步：建议戴耳机练——用外放的话，麦克风会把 ChatGPT 的声音也一起录进去。"
    }

    /// 打开录音文件夹用的 URL。视图拿它去调 NSWorkspace。
    public var recordingsFolderURL: URL { recordings.directory.recordingsDirectory }

    /// 三句话对三种处境。中间那句是**权限被事后撤销**才会出现的：
    /// 开关显示成「关」而磁盘上确实记着一次同意，不把这个错位说破的话，
    /// 用户只会觉得「我明明开过，怎么自己关了」。
    public var consentText: String {
        guard !consentAt.isEmpty else {
            return "录音默认关闭。打开之后才会申请麦克风权限。"
        }
        // `guidance` 只在权限不在手里时非 nil（granted 时没什么要说的）。
        guard !enabled, let blocked = permission.guidance else {
            return "你在 \(consentAt) 同意保存录音。"
        }
        return "你在 \(consentAt) 同意保存录音，但麦克风权限现在不在本应用手里，"
            + "所以上面的开关停在「关」，练习时不会录音（已经录下的录音都还在）。"
            + blocked
    }

    /// 落盘。**返回 false 时调用方必须直接返回**，不能接着报一句「已开启」——
    /// 那会在没保存成功的情况下告诉用户保存成功了。
    private func persist(_ transform: (CoachSettings) -> CoachSettings) -> Bool {
        do {
            try store.mutate { state in state.settings = transform(state.settings) }
            refresh()
            return true
        } catch {
            notice = "设置没能保存：\(error.localizedDescription)"
                + "\n下一步：确认数据目录（~/Library/Application Support/IELTS Speaking Coach/）"
                + "可写，然后再试一次。"
            return false
        }
    }
}
