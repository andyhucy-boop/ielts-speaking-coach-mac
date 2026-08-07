import Foundation
import IELTSCoachCore

public struct AboutRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    /// 补充说明。凡是用户可能要做点什么的行，这里必须含「下一步」。
    public let hint: String

    public init(id: String, label: String, value: String, hint: String) {
        self.id = id; self.label = label; self.value = value; self.hint = hint
    }
}

public struct Acknowledgement: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    /// 它在这个项目里到底起了什么作用。只写名字等于没致谢。
    public let role: String
    public let license: String
    public let url: String

    public init(name: String, role: String, license: String, url: String) {
        self.name = name; self.role = role; self.license = license; self.url = url
    }
}

public enum AboutViewModel {

    public static func rows(metadata: AppMetadata, dataDirectory: URL,
                            permission: PermissionState,
                            portabilityFindings: [PortabilityFinding]) -> [AboutRow] {
        [
            AboutRow(id: "version", label: "版本", value: metadata.versionLine,
                     hint: "构建于 \(metadata.buildDate)，提交 \(metadata.buildCommit)。"),
            AboutRow(id: "bundle", label: "标识", value: metadata.bundleIdentifier,
                     hint: "系统的辅助功能授权绑定这个标识，因此它在任何版本里都不会变。"
                         + "看到授权莫名失效时，先确认这一行还是它。"),
            AboutRow(id: "signature", label: "签名", value: metadata.channel.title,
                     hint: "\(metadata.channel.explanation) \(metadata.channel.nextStep)"),
            AboutRow(id: "permission", label: "辅助功能", value: permissionValue(permission),
                     hint: permissionHint(permission)),
            AboutRow(id: "dataDirectory", label: "数据目录", value: dataDirectory.path,
                     hint: "你的题库、练习记录、复盘、录音全在这个文件夹里。"
                         + "换电脑时把它整个拷过去就能接着用；备份就是拷贝它。"),
            portabilityRow(portabilityFindings)
        ]
    }

    private static func permissionValue(_ state: PermissionState) -> String {
        switch state {
        case .ready: return "已授权"
        case .needsAccessibility: return "未授权（半自动模式）"
        case .needsChatGPT: return "无法判断"
        case .unknown: return "检查未通过"
        }
    }

    private static func permissionHint(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "本 App 用它来替你操作 ChatGPT：新建会话、点开语音、发考官提示词、取回复盘。"
        case .needsAccessibility:
            return "没有它就只能半自动：提示词要你自己粘、复盘要你自己 ⌘C。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选，回来点「重新检查」。"
        case .needsChatGPT:
            return "本机没找到 ChatGPT（新版桌面应用）。注意 ChatGPT Classic 没有语音，不是这里要的那个。"
                + "下一步：装好新版 ChatGPT.app 之后回来点「重新检查」。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。"
                + "下一步：点「重新检查」看原始消息；若看不懂，用「复制诊断信息」把它整段发出来。"
        }
    }

    private static func portabilityRow(_ findings: [PortabilityFinding]) -> AboutRow {
        guard let first = findings.first else {
            return AboutRow(id: "portability", label: "数据可搬迁检查",
                            value: "没有发现问题",
                            hint: "这个目录可以整个拷到另一台电脑接着用。")
        }
        let more = findings.count > 1 ? "（共 \(findings.count) 处，这里只列第一条）" : ""
        return AboutRow(id: "portability", label: "数据可搬迁检查",
                        value: "发现 \(findings.count) 处问题",
                        hint: "\(first.message)\(more)")
    }

    // MARK: - 致谢

    public static let acknowledgements: [Acknowledgement] = [
        // **这一条与计划原文不同，是核对源码之后改的。**
        // 计划里写的是「没有复制它的任何代码」「未使用其代码，因此不受其许可证约束」，
        // 而工程里明确有逐字沿用的上游文本：
        // `AnswerUpgradePolicy`（注释原文「正文逐字移植自上游 desktop/answer-upgrade-policy.mjs」）、
        // `ExaminerPrompt`（「正文依据上游 references/examiner-protocol.md，英文契约句必须逐字保留」），
        // 设计文档还写着三个逻辑测试是「逐一对译」上游的。
        // 计划自己要求碰到这种情况必须停下来核对上游许可证——核对结果是 MIT
        // （https://github.com/lindsey-labs/ielts-speaking-coach，设计文档记的版本 v0.1.49）。
        // MIT 允许把这些内容用进本工具、并把编译好的副本给别人，**唯一的条件是保留版权与许可声明**，
        // 所以那份声明必须真的出现在用户看得到的地方——就是下面这一条。
        // 写成「未使用其代码」不只是不准确，它会让本工具在分发时不满足 MIT 的那个条件。
        Acknowledgement(
            name: "lindsey-labs/ielts-speaking-coach",
            role: "上游项目。本工具的功能范围、复盘规范与 state.json 的字段结构都来自它；"
                + "回答升级规则的正文、考官提示词里的英文契约句逐字沿用了它的文本，"
                + "其余部分是 macOS 原生重写，不是移植。",
            license: "MIT 许可证。Copyright (c) 2026 IELTS Speaking Coach contributors。"
                + "MIT 允许把它的内容用进本工具并把编译好的副本给别人，"
                + "条件是保留上面这行版权声明与许可声明——这一条就是它。",
            url: "https://github.com/lindsey-labs/ielts-speaking-coach"),
        Acknowledgement(
            name: "SF Symbols",
            role: "界面里的全部图标。",
            license: "Apple 提供。可在应用界面中使用，不得改造成自有字体，也不得用作商标。",
            url: "https://developer.apple.com/sf-symbols/"),
        Acknowledgement(
            name: "SF Pro（macOS 系统字体）",
            role: "界面里的全部文字。",
            license: "随系统提供，未打包进本 App。",
            url: ""),
        Acknowledgement(
            name: "OpenAI ChatGPT",
            role: "本工具驱动你本机已安装的 ChatGPT 应用完成练习与复盘，"
                + "不调用 OpenAI 的任何接口，也不产生额外费用。",
            license: "本工具与 OpenAI 无隶属关系，也未获其背书。",
            url: ""),
        Acknowledgement(
            name: "第三方依赖",
            role: "没有。整个工程只用 Swift 标准库与系统框架。",
            license: "不适用。",
            url: "")
    ]

    /// 与仓库根目录的 LICENSE 保持一致。要改就两处一起改。
    ///
    /// **界面上这份是摘要**：LICENSE 里另有两段（不内置商业题库、不调用 OpenAI 接口）没搬进来，
    /// 因为关于页已经在致谢里说过同样的事，摆两遍反而没人读。改条款时仍然两处一起改。
    public static let licenseNotice = """
        版权所有 © 2026 IELTS Speaking Coach 的作者。保留所有权利。

        本工具为个人自用而写。作者可以把编译好的副本给任何人，收到副本的人可以自用；\
        未授予公开再分发、修改或商业使用的许可。

        本工具与 OpenAI 无隶属关系，也不隶属于任何雅思考试主办方\
        （British Council、IDP、Cambridge Assessment English）。\
        "IELTS" 与 "ChatGPT" 是各自权利人的商标，此处仅用于说明本工具的用途。

        本工具按现状提供，不作任何明示或默示的担保。
        """
}
