import ApplicationServices
import Foundation

enum PressCommand {
    static func run(description: String) -> Int32 {
        guard let app = AXTree.appElement(bundleID: Doctor.targetBundleID) else {
            print("❌ 目标应用未运行。")
            print("   下一步：打开 ChatGPT 后重跑本命令。")
            return 1
        }
        AXTree.wake(app)

        var target: AXUIElement?
        var candidates: [String] = []
        AXTree.walk(app) { node, element in
            guard node.role == "AXButton" || node.role == "AXCheckBox" else { return }
            let label = node.descriptionText.isEmpty ? node.title : node.descriptionText
            guard !label.isEmpty else { return }
            candidates.append(label)
            if target == nil, label == description { target = element }
        }

        guard let button = target else {
            print("❌ 没找到 description 为「\(description)」的按钮。")
            print("   下一步：从下列实际存在的按钮里挑一个重试（前 25 个）：")
            for label in Array(Set(candidates)).sorted().prefix(25) { print("     \(label)") }
            return 1
        }

        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        if result == .success {
            print("✅ 已按下「\(description)」")
            return 0
        }
        print("❌ 按下「\(description)」失败，AX 返回码 \(result.rawValue)。")
        print("   下一步：确认 ChatGPT 窗口在前台且该按钮当前可点击，然后重试。")
        return 1
    }
}
