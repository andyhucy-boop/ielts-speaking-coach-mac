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
    public let environmentMessages: [String]
    /// 最近一次错误。**只有阶段、代号、时间**，一个字的错误原文都没有——
    /// 原文里可能夹着复盘片段，而复盘片段里全是用户说过的英语（见 `LastErrorLog`）。
    public let lastError: DiagnosticsError?

    public init(metadata: AppMetadata, dataDirectory: URL, systemVersion: String,
                permission: PermissionState, state: CoachState,
                portabilityFindingCount: Int,
                usage: DataUsageReport? = nil,
                environmentMessages: [String] = [],
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
        if input.environmentMessages.isEmpty {
            lines.append("环境检查：没有输出（这本身就不正常，请一并说明）")
        } else {
            lines.append("环境检查：")
            lines += input.environmentMessages.map { "- \($0)" }
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
