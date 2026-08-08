import Foundation
import IELTSCoachCore

public struct DiagnosticsInput: Sendable {
    public let metadata: AppMetadata
    public let dataDirectory: URL
    public let systemVersion: String
    public let permission: PermissionState
    public let state: CoachState
    public let portabilityFindingCount: Int
    /// 数据目录占了多少地。Task 18 追加，**带默认值**——Task 5 的既有调用点一行都不用改。
    public let usage: DataUsageReport?
    /// 环境检查（preflight）的输出原文。「ChatGPT 改版打断自动化」是已知风险，
    /// 真出问题时这几行就是最有用的线索。
    ///
    /// **三种取值是三件不同的事，不许混成两件：**
    /// - `nil`：**还没查过**。关于页刻意不自动检查（检查要把 ChatGPT 拉到前台，
    ///   会打断用户手上的事），所以「一条输出都没有」正是它没被点过「重新检查」时的常态。
    /// - `[]`：查过了，**却一条输出都没有**。那才真是不正常，要在文字里点出来。
    /// - 非空：原样列出来。
    ///
    /// 混成两件的后果本项目实测过（2026-08-08 复审）：关于页把 `nil` 那种情况
    /// 送进了「没有输出（这本身就不正常）」这一支，然后自己在末尾补一句
    /// 「打开关于页不会自动检查，所以那一行不是结论」——同一段要转发给别人的文字里，
    /// 一句说「不正常」，紧接着一句说「设计如此」。
    public let environmentMessages: [String]?
    /// 最近一次错误。**只有阶段、代号、时间**，一个字的错误原文都没有——
    /// 原文里可能夹着复盘片段，而复盘片段里全是用户说过的英语（见 `LastErrorLog`）。
    public let lastError: DiagnosticsError?

    public init(metadata: AppMetadata, dataDirectory: URL, systemVersion: String,
                permission: PermissionState, state: CoachState,
                portabilityFindingCount: Int,
                usage: DataUsageReport? = nil,
                environmentMessages: [String]? = nil,
                lastError: DiagnosticsError? = nil) {
        self.metadata = metadata; self.dataDirectory = dataDirectory
        self.systemVersion = systemVersion; self.permission = permission
        self.state = state; self.portabilityFindingCount = portabilityFindingCount
        self.usage = usage; self.environmentMessages = environmentMessages
        self.lastError = lastError
    }
}

/// 一段可以一键复制、直接发给别人的诊断文本。
///
/// **只报数量，不报内容。** 逐字稿、错题原句、词汇、姓名都不进这段文字 ——
/// 用户复制它的时候不会逐字检查里面有什么，所以这个边界只能由代码保证。
///
/// **它也不自己往外发。** 这里只负责把环境与错误拼成一段话；送到哪儿去是用户
/// 按下「复制诊断信息」之后、他自己粘贴时才决定的事。
/// `DiagnosticsReportTests.testTheReportIsAssembledButNeverSentAnywhere` 守着这一条。
public enum DiagnosticsReport {
    public static func text(_ input: DiagnosticsInput) -> String {
        var lines: [String] = []
        lines.append("IELTS Speaking Coach 诊断信息")
        lines.append("版本：\(input.metadata.versionLine)")
        lines.append("提交：\(input.metadata.buildCommit)")
        lines.append("构建时间：\(input.metadata.buildDate)")
        lines.append("签名：\(input.metadata.channel.title)（身份：\(input.metadata.signingIdentity)）")
        lines.append("标识：\(input.metadata.bundleIdentifier)")
        lines.append("系统：\(input.systemVersion)")
        lines.append("数据目录：\(input.dataDirectory.path)")
        lines.append("数据量：题库 \(input.state.questions.count) 题 · "
            + "练习记录 \(input.state.sessions.count) 次 · "
            + "错题 \(input.state.issues.count) 条 · "
            + "词汇 \(input.state.vocabulary.count) 条 · "
            + "重训目标 \(input.state.targets.count) 个")
        lines.append("辅助功能：\(permissionText(input.permission))")
        if input.portabilityFindingCount == 0 {
            lines.append("数据可搬迁检查：没有发现问题")
        } else {
            // 计划原文这里写的是「在关于页点「查看详情」」，**那颗按钮不存在，也不会存在**：
            // Task 6 的 `AboutViewModel.portabilityRow` 把每一处问题的位置与修法直接写进
            // 那一行的 hint，Task 7 的关于页只有「在访达中显示」「复制诊断信息」「重新检查」
            // 三颗按钮。指一颗不存在的按钮比不写还糟——用户会一直找
            // （`RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists`
            // 正是冲着这类幽灵控件来的，照抄计划原文会被它当场报出来，本任务实测过）。
            // 所以改成指那一行本身。
            lines.append("数据可搬迁检查：发现 \(input.portabilityFindingCount) 处问题。"
                + "下一步：回到关于页，「数据可搬迁检查」那一行会写清是哪一处、该怎么改。")
        }
        if let usage = input.usage {
            lines.append("数据目录占用：\(usage.summaryText)")
        }
        // 三支，不是两支：**「还没查过」不是「查过了没出声」。**
        // 混成两支的话，一段要转发给别人的文字里会同时出现「这本身就不正常」
        // 和「这是设计如此」，收到的人不知道该信哪一句（2026-08-08 复审实测到过）。
        switch input.environmentMessages {
        case nil:
            lines.append("环境检查：还没查过。查一次要启动 ChatGPT、会打断你手上的事，"
                + "所以不会自动查——上面「辅助功能」那一行因此不是结论，别照着它排查。"
                + "下一步：点「重新检查」（问题反馈页上这颗按钮写的是「重新检查环境」），"
                + "查完再复制一次。")
        case let messages? where messages.isEmpty:
            lines.append("环境检查：查过了，但一条输出都没有（这本身就不正常，请一并说明）")
        case let messages?:
            lines.append("环境检查：")
            lines += messages.map { "- \($0)" }
        }
        if let error = input.lastError {
            lines.append("最近一次错误：\(error.summary)")
        } else {
            lines.append("最近一次错误：最近没有出错")
        }
        lines.append("——错误只记阶段与代号，不记原文；原文里可能有你说过的英语。")
        lines.append("——以上只有数量，不含任何练习内容。要看具体内容请直接打开数据目录。")
        return lines.joined(separator: "\n")
    }

    private static func permissionText(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "已授权，自动化可用"
        case .needsAccessibility:
            return "未授权，只能半自动运行。下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选。"
        case .needsChatGPT:
            return "判断不了——本机没找到 ChatGPT（新版桌面应用）。下一步：先安装它，再回来重新检查。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。下一步：在关于页点「重新检查」，把它显示的原始消息一并发出来。"
        }
    }
}
