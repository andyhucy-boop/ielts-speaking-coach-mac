import Foundation
import IELTSCoachCore
import Observation

public enum RecordingPlaybackState: Equatable, Sendable {
    /// 这次练习本来就没录音（开关关着，或那次录音失败了）。不显示播放器，也不报警。
    case none
    /// 记录里有录音路径，但文件不在了。
    /// **必须说出来**——什么都不显示的话，用户会以为自己记错了，或者以为程序坏了。
    case missing(String)
    case ready(URL)
}

@MainActor
@Observable
public final class RecordingPlaybackViewModel {
    public private(set) var state: RecordingPlaybackState = .none
    /// 非 nil 时界面必须显示。
    public private(set) var notice: String?

    public let sessionID: String
    private var relativePath: String
    private let store: StateStore
    private let recordings: RecordingStore

    public init(sessionID: String, relativePath: String,
                store: StateStore, recordings: RecordingStore) {
        self.sessionID = sessionID
        self.relativePath = relativePath
        self.store = store
        self.recordings = recordings
        refresh()
    }

    public func refresh() {
        guard !relativePath.isEmpty else { state = .none; return }
        do {
            let url = try recordings.url(forRelativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                state = .missing(
                    "这次练习的录音文件找不到了（记录里指向 \(relativePath)）。"
                    + "下一步：文件可能被手动删掉或移走了；"
                    + "点「清除这条录音记录」把这个指向去掉，"
                    + "这次练习的题目、逐字稿和复盘都不受影响。")
                return
            }
            state = .ready(url)
        } catch {
            state = .missing(error.localizedDescription)
        }
    }

    public var deleteConfirmationText: String {
        "删掉这条录音之后，就再也听不到这次练习你是怎么说的了。"
        + "这次的题目、逐字稿和复盘都会保留。"
        + "下一步：确定要删就点「删除录音」，不删就点「取消」。"
    }

    /// 删这一条录音：**先删文件，成功之后再清记录里的路径。**
    ///
    /// 顺序不能反。先清路径再删文件的话，删文件万一失败，那个文件就变成了
    /// 界面上看不见、用户也不知道存在的孤儿，只能靠 Finder 手动去翻。
    ///
    /// **文件删掉了不等于这条就删干净了。** 训练记录那一半没写成功时，
    /// 绝不能接着报「录音已删除，其他都还在」——那是两重的谎：记录压根没更新，
    /// 而磁盘上那个文件已经没了。所以这里看 `clearReferenceOnly()` 的成败，
    /// 只有记录真的更新上了才说成功；没更新上就把它那句失败说明留在屏幕上（铁律 7）。
    public func delete() {
        do {
            try recordings.delete(relativePath: relativePath)
        } catch {
            notice = error.localizedDescription
            return
        }
        guard clearReferenceOnly() else { return }
        notice = "录音已删除。这次练习的题目、逐字稿和复盘都还在。"
    }

    /// 只把记录里的路径清掉，不碰任何文件。用于文件已经不在的情况。
    ///
    /// **返回记录是否真的更新成功。** `delete()` 靠它决定该不该说「已删除」——
    /// 不交回来的话，写盘失败刚设进 `notice` 的那句说明会被下一行的成功文案盖掉。
    @discardableResult
    public func clearReferenceOnly() -> Bool {
        let target = sessionID
        do {
            try store.mutate { state in
                for index in state.sessions.indices where state.sessions[index].id == target {
                    state.sessions[index].recordingPath = ""
                }
                if state.currentSession?.id == target {
                    state.currentSession?.recordingPath = ""
                }
            }
            relativePath = ""
            state = .none
            return true
        } catch {
            notice = "训练记录没能更新：\(error.localizedDescription)"
                + "\n下一步：确认数据目录可写、没有别的实例正在运行，然后再试一次。"
            // 记录里那条路径还在，而它指的文件可能刚刚已经被 `delete()` 删掉了。
            // 重算一次状态，让界面画的东西和磁盘现状对得上——不能一边说「没能更新」，
            // 一边还摆着一颗按下去必然是哑的播放键。
            refresh()
            return false
        }
    }
}
