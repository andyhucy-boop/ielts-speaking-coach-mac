import Foundation

enum DumpCommand {
    static func run(outputPath: String?) -> Int32 {
        guard let app = AXTree.appElement(bundleID: Doctor.targetBundleID) else {
            print("❌ ChatGPT Classic 未在运行。先打开它并进入一个会话，再运行本命令。")
            return 1
        }

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
            if !node.value.isEmpty || !node.title.isEmpty { textBearing += 1 }
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = outputPath ?? "docs/phase0-dumps/ax-\(stamp).txt"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let header = """
        # AX dump @ \(stamp)
        # 节点总数：\(lines.count)
        # 带文本的节点数：\(textBearing)
        # 角色分布：\(roleCounts.sorted { $0.value > $1.value }.prefix(15).map { "\($0.key)=\($0.value)" }.joined(separator: " "))

        """
        try? (header + lines.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)

        print("✅ 已写入 \(path)")
        print("   节点总数 \(lines.count)，带文本节点 \(textBearing)")
        return 0
    }

    private static func quoted(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: "\\n")
        return flat.count > 200 ? "\"\(flat.prefix(200))…\"" : "\"\(flat)\""
    }
}
