import Foundation

enum DumpCommand {
    static func run(outputPath: String?) -> Int32 {
        guard let app = AXTree.appElement(bundleID: Doctor.targetBundleID) else {
            print("❌ 目标应用未在运行。")
            print("   下一步：打开 ChatGPT（新版，bundle id \(Doctor.targetBundleID)）并进入一个会话，再运行本命令。")
            return 1
        }

        AXTree.wake(app)

        var lines: [String] = []
        var roleCounts: [String: Int] = [:]
        var textBearing = 0

        AXTree.walk(app) { node, _ in
            let indent = String(repeating: "  ", count: node.depth)
            var parts = ["\(indent)\(node.role)"]
            if !node.subrole.isEmpty { parts.append("subrole=\(node.subrole)") }
            if !node.identifier.isEmpty { parts.append("id=\(node.identifier)") }
            if !node.title.isEmpty { parts.append("title=\(quoted(node.title))") }
            if !node.descriptionText.isEmpty { parts.append("desc=\(quoted(node.descriptionText))") }
            if !node.value.isEmpty { parts.append("value=\(quoted(node.value))") }
            parts.append("children=\(node.childCount)")
            lines.append(parts.joined(separator: " "))

            roleCounts[node.role, default: 0] += 1
            // 菜单栏动辄两百多个节点，会把「带文本节点数」灌水到失去意义。
            // 这个统计只服务于「会话消息能不能被 AX 读到」的人工判断，所以排除掉。
            let isMenu = node.role.hasPrefix("AXMenu")
            if !isMenu, !node.value.isEmpty || !node.title.isEmpty { textBearing += 1 }
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = outputPath ?? "docs/phase0-dumps/ax-\(stamp).txt"
        let url = URL(fileURLWithPath: path)

        let header = """
        # AX dump @ \(stamp)
        # 节点总数：\(lines.count)
        # 带文本的节点数（不含菜单栏）：\(textBearing)
        # 角色分布：\(roleCounts.sorted { $0.value > $1.value }.prefix(15).map { "\($0.key)=\($0.value)" }.joined(separator: " "))

        """

        // 绝不静默失败：写不成必须报错并返回非 0，否则用户会以为 dump 成功了。
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (header + lines.joined(separator: "\n"))
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("❌ 写入 dump 文件失败：\(path)")
            print("   下一步：确认该路径所在目录可写；或换一个明确可写的路径重跑，例如 axprobe dump /tmp/ax.txt")
            print("   系统报错：\(error.localizedDescription)")
            return 1
        }

        print("✅ 已写入 \(path)")
        print("   节点总数 \(lines.count)，带文本节点（不含菜单栏）\(textBearing)")
        return 0
    }

    private static func quoted(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: "\\n")
        return flat.count > 200 ? "\"\(flat.prefix(200))…\"" : "\"\(flat)\""
    }
}
