import ChatGPTBridge
import Foundation
import IELTSCoachCore

enum DoctorCommand {
    static func run() -> Int32 {
        let access = LiveAXAccess()
        let driver = AXDriver(access: access, locator: AXLocator(access: access))
        let readiness = driver.preflight()
        readiness.messages.forEach { print($0) }

        let directory = DataDirectory.resolve()
        do {
            try directory.createIfNeeded()
            let state = try StateStore(directory: directory).load()
            print("✅ 训练数据：\(directory.root.path)")
            print("   题库 \(state.questions.count) 题，练习记录 \(state.sessions.count) 次，"
                + "错题 \(state.issues.count) 条，词汇 \(state.vocabulary.count) 条")
            if state.questions.isEmpty {
                print("ℹ️  题库是空的。下一步：coach questions import <你的题库文件>")
            }
        } catch {
            print("❌ 读取训练数据失败：\(error.localizedDescription)")
            return 1
        }
        return readiness.ok ? 0 : 1
    }
}
