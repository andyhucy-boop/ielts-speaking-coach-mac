import AppKit
import Foundation
import IELTSCoachCore
import IELTSCoachMCP

/// 唤起 App 的生产实现。**放在可执行文件里而不是库里**，
/// 这样 IELTSCoachMCP 库只依赖 Foundation + Core，测试能在没有图形环境的地方跑。
/// 实现方式由 spec 4.4 钉死：NSWorkspace.open(URL(string: "ieltscoach://…"))。
struct WorkspaceDashboardOpener: DashboardOpening {
    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw DashboardOpenError(message:
                "系统没能打开 \(url.absoluteString)，通常是因为 IELTS Speaking Coach 还没被系统登记。"
                + "下一步：先运行 scripts/build-app.sh 生成 .app，"
                + "把它拖进「应用程序」并手动双击打开一次——"
                + "系统只有在应用被打开过之后才会登记 ieltscoach:// 这个链接。")
        }
    }
}

let directory = DataDirectory.resolve()
let environment = MCPEnvironment(directory: directory, opener: WorkspaceDashboardOpener())
let server = MCPServer(tools: ToolCatalog.tools(environment: environment))

let standardOutput = FileHandle.standardOutput
let standardError = FileHandle.standardError

/// 日志一律走 stderr。**往 stdout 打一行中文就会让客户端解析失败、连接当场断掉。**
func log(_ message: String) {
    standardError.write(Data("\(message)\n".utf8))
}

log("ielts-speaking-mcp \(MCPServer.serverVersion) 已启动。数据目录：\(directory.root.path)")

// 用 FileHandle 直接写而不是 print：print 走的是 C 的 stdout，
// 在管道下是块缓冲，响应会堆在缓冲区里发不出去，客户端一直等（禁止无限等待）。
// FileHandle.write 是无缓冲的 write(2)，不存在这个问题。
while let line = readLine(strippingNewline: true) {
    guard let response = server.handle(line: line) else { continue }
    standardOutput.write(Data((response + "\n").utf8))
}

// readLine 返回 nil 即 stdin 已关闭：客户端退出了，我们也退出。
log("stdin 已关闭，ielts-speaking-mcp 退出。")
