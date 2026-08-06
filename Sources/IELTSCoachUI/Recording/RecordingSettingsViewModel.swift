import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import Observation

/// 「保存我的回答录音」这一页的全部逻辑。**视图里不许再判一次「能不能录」**——
/// 那条规则只留在 `RecordingConsent` 与这里，两处各判一次迟早会走岔。
@MainActor
@Observable
public final class RecordingSettingsViewModel {
    /// 开关的当前值。**只反映已经落盘的事实。**
    /// 权限没拿到时它必须是 false——显示成「开」却什么都不录，
    /// 用户练完发现没录音时完全无从查起。
    public private(set) var enabled = false
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
            enabled = state.settings.recordingEnabled
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

    public var consentText: String {
        guard enabled, !consentAt.isEmpty else {
            return "录音默认关闭。打开之后才会申请麦克风权限。"
        }
        return "你在 \(consentAt) 同意保存录音。"
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
