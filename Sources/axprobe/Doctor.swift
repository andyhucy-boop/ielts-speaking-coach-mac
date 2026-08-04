import AppKit
import ApplicationServices
import Foundation

enum Doctor {
    static let targetBundleID = "com.openai.chat"

    static func run() -> Int32 {
        var ok = true

        // 1. ChatGPT Classic 是否安装
        let chatGPTURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID)
        if let url = chatGPTURL {
            let plist = url.appending(path: "Contents/Info.plist")
            let version = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "未知"
            print("✅ ChatGPT Classic 已安装：\(url.path)（版本 \(version)）")
        } else {
            print("❌ 未找到 ChatGPT Classic（bundle id \(targetBundleID)）。")
            print("   下一步：安装 ChatGPT 桌面版。注意 com.openai.codex 那个 ChatGPT.app 没有语音能力，不是目标。")
            ok = false
        }

        // 2. chatgpt:// 由谁处理
        if let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "chatgpt://new-conversation")!) {
            print("✅ chatgpt:// 处理程序：\(handler.path)")
            if handler != chatGPTURL {
                print("⚠️  处理程序与 ChatGPT Classic 不是同一个应用，deep link 可能落到别处。")
            }
        } else {
            print("❌ 没有应用注册 chatgpt:// 协议。")
            ok = false
        }

        // 3. 辅助功能权限
        if AXIsProcessTrusted() {
            print("✅ 辅助功能权限已授予")
        } else {
            print("❌ 未获得辅助功能权限。")
            print("   下一步：系统设置 › 隐私与安全性 › 辅助功能，把运行本工具的终端加进去并勾选。")
            ok = false
        }

        // 4. ChatGPT Classic 是否正在运行
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == targetBundleID }
        print(running ? "✅ ChatGPT Classic 正在运行" : "ℹ️  ChatGPT Classic 未运行（部分实验需要它运行）")

        return ok ? 0 : 1
    }
}
