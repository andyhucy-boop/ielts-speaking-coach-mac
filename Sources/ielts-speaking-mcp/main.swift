import Foundation

// 真正的 stdio 循环（逐行读 stdin 喂给 MCPServer、把响应写回 stdout）在 Phase 9 Task 10 实现。
//
// 在那之前这个可执行文件**必须明说自己还不能用**：静默退出会让人以为 MCP 已经接上了，
// 然后对着一个永远不回话的服务器排查半天——那正是「禁止静默失败」要防的形态。
FileHandle.standardError.write(Data("""
ielts-speaking-mcp 还没有实现 stdio 循环（Phase 9 Task 10 才做），现在启动它不会响应任何 MCP 请求。
下一步：等 Task 10 完成后再把它配置进 Codex；在那之前请继续用 coach 命令完成选题、取提示词与复盘归档。

""".utf8))
exit(1)
