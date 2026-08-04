import AppKit
import Foundation

enum DeepLinkExperiment {
    /// 打开一条 deep link，等待应用响应，然后读回输入框内容。
    static func run(rawURL: String) -> Int32 {
        guard let url = URL(string: rawURL) else {
            print("❌ 不是合法 URL：\(rawURL)")
            return 2
        }
        print("→ 打开：\(rawURL)")
        NSWorkspace.shared.open(url)

        // 给 ChatGPT 时间处理 deep link 并渲染界面
        Thread.sleep(forTimeInterval: 3.0)

        guard AXTree.appElement(bundleID: Doctor.targetBundleID) != nil else {
            print("❌ ChatGPT Classic 未在运行，无法读回。")
            return 1
        }

        let composer = AXTree.findComposerText() ?? ""
        if composer.isEmpty {
            print("← 输入框为空：提示词没有被带入（或 AX 读不到输入框，见 dump 结果）")
        } else {
            print("← 输入框内容：\(composer)")
        }
        return 0
    }
}
