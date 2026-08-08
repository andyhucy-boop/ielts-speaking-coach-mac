import Foundation

/// 一条「换台电脑就会断」的问题。
public struct PortabilityFinding: Equatable, Sendable, Identifiable {
    /// 位置即唯一键：同一个字段只报一次。
    public var id: String { location }
    /// 精确到字段，例如 "sessions[3].reportPath"。含糊的位置等于没报。
    public let location: String
    public let value: String
    /// 发生了什么。
    public let problem: String
    /// 下一步做什么。
    public let nextStep: String

    public init(location: String, value: String, problem: String, nextStep: String) {
        self.location = location; self.value = value
        self.problem = problem; self.nextStep = nextStep
    }

    /// 界面和命令行都用这一句，保证「发生了什么 + 下一步做什么」不会只讲一半。
    public var message: String { "\(location)：\(problem) 下一步：\(nextStep)" }
}

/// 检查数据目录能不能原样拷到另一台电脑接着用（成品标准第 10 条）。
///
/// **判据只有一条：里面存的路径必须全都相对于数据目录本身。**
/// 一旦某处存成绝对路径，在原机器上一切正常，什么都不会报错 ——
/// 只有换机器的那天才会发现历史复盘全打不开。这属于本项目最危险的那类失败：
/// 静默的、要到很久以后才暴露的。
public enum DataPortabilityAudit {

    /// 只看 `state.json` 里的路径写法，不碰磁盘。
    public static func audit(state: CoachState) -> [PortabilityFinding] {
        var findings: [PortabilityFinding] = []
        for (index, session) in state.sessions.enumerated() {
            if let finding = checkRelativePath(session.reportPath,
                                               at: "sessions[\(index)].reportPath",
                                               what: "这次练习的复盘文件") {
                findings.append(finding)
            }
            if let finding = checkRelativePath(session.recordingPath,
                                               at: "sessions[\(index)].recordingPath",
                                               what: "这次练习的录音文件") {
                findings.append(finding)
            }
        }
        for (index, source) in state.questionSources.enumerated() {
            if let finding = checkSourceURL(source.sourceUrl,
                                            at: "questionSources[\(index)].sourceUrl") {
                findings.append(finding)
            }
        }
        return findings
    }

    /// 在路径写法之外，再检查引用到的文件是不是真的在数据目录里。
    /// 路径写法没问题但文件没跟着拷过来，换机器后点开历史复盘会是一片空白。
    public static func audit(state: CoachState, directory: DataDirectory,
                             fileManager: FileManager = .default) -> [PortabilityFinding] {
        var findings = audit(state: state)
        let alreadyReported = Set(findings.map(\.location))

        func checkExists(_ path: String, at location: String, what: String) {
            // 写法本身已经报过的，不再重复报「找不到」——
            // 同一个字段报两条，用户会以为有两个不同的问题要修。
            guard !alreadyReported.contains(location) else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            // 空字符串是合法的：练习还没生成复盘 / 没开录音时这两个字段本来就是空的。
            // **这一行是那条豁免真正的落点**：删掉它，空路径会拼成数据目录本身，
            // 被下面「是个文件夹」那一支报出来，用户每次打开关于页都要看一屏红字。
            // `testEmptyPathsAreNotFindings` 守着这一行。
            guard !trimmed.isEmpty else { return }
            let url = directory.root.appending(path: trimmed)
            // 只判 fileExists 不够：目录也算「存在」。reportPath 若写成 "reports"
            // 这种指向文件夹的值，在本机同样点不开，属于同一类故障，必须报出来。
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if !exists {
                findings.append(PortabilityFinding(
                    location: location, value: trimmed,
                    problem: "记录里指着 \(what)「\(trimmed)」，但数据目录里找不到这个文件。",
                    nextStep: "确认拷贝数据目录时把 reports/ 和 recordings/ 两个子目录整个带上了；"
                        + "若这个文件本来就被删过，可以在训练记录里删掉这一条，其余记录不受影响。"))
            } else if isDirectory.boolValue {
                findings.append(PortabilityFinding(
                    location: location, value: trimmed,
                    problem: "记录里指着 \(what)「\(trimmed)」，但数据目录里这个位置是个文件夹，不是文件，点开会是一片空白。",
                    nextStep: "检查写入这个字段的代码，让它存成具体的文件（形如 reports/<会话id>.json "
                        + "或 recordings/<会话id>.m4a）；也可以在训练记录里删掉这一条，其余记录不受影响。"))
            }
        }

        for (index, session) in state.sessions.enumerated() {
            checkExists(session.reportPath, at: "sessions[\(index)].reportPath", what: "复盘文件")
            checkExists(session.recordingPath, at: "sessions[\(index)].recordingPath", what: "录音文件")
        }
        return findings
    }

    // MARK: - 私有

    private static func checkRelativePath(_ raw: String, at location: String,
                                          what: String) -> PortabilityFinding? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空字符串是合法的：练习还没生成复盘 / 没开录音时这两个字段本来就是空的。
        // 说明白一点：**这一行今天是纯防御，删掉它行为不变**——空串对下面四条检查
        // 天然都不成立。真正拦住空路径的是 `checkExists` 里那一行（有测试守着）。
        // 保留它是为了以后有人往下面加「必须形如 reports/xxx」这类正向校验时，
        // 空值豁免不至于连同被加进来的规则一起失守。
        guard !path.isEmpty else { return nil }

        let advice = "把它改写成相对于数据目录的路径（形如 reports/<会话id>.json 或 recordings/<会话id>.m4a），"
            + "并检查写入这个字段的代码——存绝对路径在本机不会报任何错，只有换电脑那天才会暴露。"

        if path.hasPrefix("file://") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是 file:// 开头的完整 URL，里面带着这台电脑的用户名与目录结构。",
                nextStep: advice)
        }
        if path.hasPrefix("/") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是绝对路径，换台电脑后这个位置根本不存在。",
                nextStep: advice)
        }
        if path.hasPrefix("~") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是以 ~ 开头的路径，它不会被当成家目录展开，会被当成一个叫「~」的文件夹。",
                nextStep: advice)
        }
        if path.split(separator: "/").contains("..") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)的路径里有 ..，指到了数据目录外面，拷贝数据目录时不会被带走。",
                nextStep: advice)
        }
        return nil
    }

    private static func checkSourceURL(_ raw: String, at location: String) -> PortabilityFinding? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // https 链接换机器照样打得开，不是问题；本机文件路径才是。
        guard value.hasPrefix("/") || value.hasPrefix("file://") else { return nil }
        return PortabilityFinding(
            location: location, value: value,
            problem: "题库来源记的是这台电脑上的文件路径，换台电脑后点开是空的。",
            nextStep: "这条不影响已经导入的题目，可以不管；"
                + "若希望干净，重新导入一次题库并让来源只记文件名，不记完整路径。")
    }
}
