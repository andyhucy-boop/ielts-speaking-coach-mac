import ApplicationServices
import Foundation

enum PressCommand {
    /// 已知的"开始语音"按钮标签变体。ChatGPT 桌面版的这颗按钮文案会随场景/版本漂移
    /// （实测见过 "New voice chat"、"Start voice chat"、"Start new voice chat" 三种），
    /// 这里列出已知取值，供操作后验证判断"这次按下预期应该让语音变为激活"。
    static let startVoiceLabels: Set<String> = ["Start voice chat", "Start new voice chat", "New voice chat"]
    /// 已知的"结束语音"按钮标签。
    static let stopVoiceLabels: Set<String> = ["Stop voice chat"]

    static func run(description: String) -> Int32 {
        guard let app = AXTree.appElement(bundleID: Doctor.targetBundleID) else {
            print("❌ 目标应用未运行。")
            print("   下一步：打开 ChatGPT 后重跑本命令。")
            return 1
        }
        AXTree.wake(app)

        var target: AXUIElement?
        var candidates: [String] = []
        // 标签对上了、但结构不是"纯图标控制按钮"的元素——多半是撞名的历史记录/列表项。
        var structMismatches: [(role: String, childRoles: [String])] = []

        AXTree.walk(app) { node, element in
            guard node.role == "AXButton" || node.role == "AXCheckBox" else { return }
            let label = node.descriptionText.isEmpty ? node.title : node.descriptionText
            guard !label.isEmpty else { return }
            candidates.append(label)
            guard label == description else { return }

            if AXTree.isIconOnlyControl(element) {
                if target == nil { target = element }
            } else {
                structMismatches.append((node.role, AXTree.childRoles(element)))
            }
        }

        guard let button = target else {
            if !structMismatches.isEmpty {
                print("❌ 标签为「\(description)」的元素找到了 \(structMismatches.count) 个，但都不是控制按钮的结构。")
                print("   （真正的控制按钮应恰好有 1 个 AXImage 子节点；下面这些命中项结构不同，很可能是撞名的历史会话/列表项）")
                for m in structMismatches.prefix(10) {
                    print("     role=\(m.role) children=[\(m.childRoles.joined(separator: ", "))]")
                }
                print("   下一步：运行 axprobe dump 核对真正控制按钮当前的 description（同一功能的按钮文案会随场景/版本变化），再用正确的名字重试。")
                return 1
            }
            print("❌ 没找到 description 为「\(description)」的按钮。")
            print("   下一步：从下列实际存在的按钮里挑一个重试（前 25 个）：")
            for label in Array(Set(candidates)).sorted().prefix(25) { print("     \(label)") }
            return 1
        }

        // 操作前先记一笔"语音是否激活"的现状，方便按下后对比。
        let activeBefore = AXTree.findElement(role: "AXImage", description: "Voice chat active") != nil

        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            print("❌ 按下「\(description)」失败，AX 返回码 \(result.rawValue)。")
            print("   下一步：确认 ChatGPT 窗口在前台且该按钮当前可点击，然后重试。")
            return 1
        }

        // kAXPressAction 返回成功只代表"AX 层认为点击动作发出去了"，不代表应用真的响应了——
        // 这正是最初把侧边栏历史项误判为"按下成功"的原因。所以必须回头看真实状态是否变化。
        Thread.sleep(forTimeInterval: 1.5)
        let activeAfter = AXTree.findElement(role: "AXImage", description: "Voice chat active") != nil

        let changeText: String
        switch (activeBefore, activeAfter) {
        case (false, true): changeText = "从「不存在」变为「存在」（语音已激活）"
        case (true, false): changeText = "从「存在」变为「不存在」（语音已停止）"
        case (true, true): changeText = "按下前后均为「存在」（未变化）"
        case (false, false): changeText = "按下前后均为「不存在」（未变化）"
        }
        print("ℹ️  验证：按下后等待 1.5 秒重新遍历，语音状态图标「Voice chat active」\(changeText)。")

        if startVoiceLabels.contains(description) {
            guard activeAfter else {
                print("❌ 按下「\(description)」后 AX 返回成功，但语音会话并没有真正被激活。")
                print("   下一步：这可能又是一次标签撞车或文案漂移；运行 axprobe dump 核对真正的控制按钮 description 后重试。")
                return 1
            }
            print("✅ 已按下「\(description)」，且确认语音会话已激活。")
            return 0
        }

        if stopVoiceLabels.contains(description) {
            guard !activeAfter else {
                print("❌ 按下「\(description)」后 AX 返回成功，但语音会话仍处于激活状态。")
                print("   下一步：语音通话可能还没真正挂断，请手动检查 ChatGPT 窗口，必要时手动结束通话。")
                return 1
            }
            print("✅ 已按下「\(description)」，且确认语音会话已停止。")
            return 0
        }

        // 非已知语音开关：沿用 AX 返回码作为成功判据，仍然把状态观察打印出来供参考。
        print("✅ 已按下「\(description)」（AX 返回成功；该按钮不属于已知语音开关，未对状态变化做强制校验）。")
        return 0
    }
}
