import AppKit
import ApplicationServices
import ChatGPTBridge
import Foundation

enum Doctor {
    static let targetBundleID = "com.openai.codex"      // 新 ChatGPT.app，有 live 语音
    static let classicBundleID = "com.openai.chat"      // ChatGPT Classic，无语音，仅用于误装提示

    static func run() -> Int32 {
        var ok = true

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID) {
            let plist = url.appending(path: "Contents/Info.plist")
            let version = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "未知"
            print("✅ ChatGPT（新版，含 live 语音）已安装：\(url.path)（版本 \(version)）")
        } else {
            print("❌ 未找到目标应用（bundle id \(targetBundleID)）。")
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: classicBundleID) != nil {
                print("   你装的是 ChatGPT Classic，它没有 live 语音功能，本工具无法驱动它。")
            }
            print("   下一步：安装新版 ChatGPT 桌面应用（openai.com/chatgpt/download），装好后重跑本命令。")
            ok = false
        }

        if AXIsProcessTrusted() {
            print("✅ 辅助功能权限已授予")
        } else {
            print("❌ 未获得辅助功能权限。")
            print("   下一步：系统设置 › 隐私与安全性 › 辅助功能，把运行本工具的终端加进去并勾选，然后重跑。")
            ok = false
        }

        let access = LiveAXAccess()
        guard access.isTargetRunning() else {
            print("ℹ️  目标应用未运行。下一步：打开 ChatGPT 并进入一个会话后重跑，才能检查 AX 树。")
            return ok ? 0 : 1
        }

        _ = access.wakeAccessibilityTree(timeout: 8.0)
        let nodes = access.snapshotTree()
        if nodes.contains(where: { $0.role == "AXTextArea" }) {
            print("✅ AX 树已唤醒，找到输入框")
        } else {
            print("❌ AX 树唤醒后仍找不到输入框（AXTextArea）。")
            print("   下一步：确认 ChatGPT 窗口可见且已打开一个会话，然后重跑；仍失败请运行 axprobe dump 收集诊断信息。")
            ok = false
        }

        return ok ? 0 : 1
    }
}
