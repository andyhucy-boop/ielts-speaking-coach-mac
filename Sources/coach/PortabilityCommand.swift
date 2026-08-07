import Foundation
import IELTSCoachCore

/// 兑现成品标准第 10 条：换一台电脑，把数据目录拷过去就能接着用。
///
/// 判据只有一条：`state.json` 里存的路径必须全都相对于数据目录本身。
/// 存成绝对路径在本机一切正常、什么都不报，只有换机器那天才会发现历史复盘全打不开——
/// 所以必须有一条能主动跑的检查，而不是等着它自己暴露。
enum PortabilityCommand {
    static func run() -> Int32 {
        let directory = DataDirectory.resolve()
        let state: CoachState
        do {
            state = try StateStore(directory: directory).load()
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }

        print("数据目录：\(directory.root.path)")
        print("题库 \(state.questions.count) 题，练习记录 \(state.sessions.count) 次，"
            + "错题 \(state.issues.count) 条，词汇 \(state.vocabulary.count) 条")

        let findings = DataPortabilityAudit.audit(state: state, directory: directory)
        guard !findings.isEmpty else {
            print("✅ 这个目录可以整个拷到另一台电脑接着用，没发现任何依赖本机路径的地方。")
            return 0
        }
        print("\n⚠️  发现 \(findings.count) 处换电脑后会断掉的地方：")
        for finding in findings { print("   • \(finding.message)") }
        return 1
    }
}
