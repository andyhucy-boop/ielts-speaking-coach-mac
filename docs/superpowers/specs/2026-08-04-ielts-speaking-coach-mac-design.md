# IELTS Speaking Coach for macOS — 设计文档

日期：2026-08-04
上游参考：https://github.com/lindsey-labs/ielts-speaking-coach（v0.1.49）

## 1. 背景

上游项目是一套雅思口语训练工作流：导入题库 → 选题 → 用 ChatGPT Voice 模拟考官 → 生成结构化复盘 → 归档错题与词汇 → 单点重训。它由三部分组成：一个 Electron 桌面应用、一个本地 MCP server、一个 Codex 插件。

上游的桌面应用把 chatgpt.com 装进一个 Electron 窗口，靠操控网页 DOM 来发送提示词、点击 Voice 按钮、读回对话文本。这套做法在 macOS 上有多处失效点，且始终受制于 ChatGPT 网页结构的变化。

本项目不是把上游移植到 macOS，而是**用原生技术重写，并把「操控网页」换成「驱动本机的 ChatGPT 桌面应用」**。

## 2. 实测前提

以下结论来自 2026-08-04 在目标机器（macOS 26 / Darwin 25.5.0，Apple Silicon）上对已安装应用的静态检查，非推测。

### 2.1 本机存在两个 ChatGPT 应用

| | `/Applications/ChatGPT Classic.app` | `/Applications/ChatGPT.app` |
|---|---|---|
| Bundle ID | `com.openai.chat` | `com.openai.codex` |
| 版本 | 1.2026.160 | 26.727.51351 |
| 实现 | 原生 Swift | Chromium 壳（Codex 桌面版）|
| 语音能力 | 含 `LiveKitWebRTC.framework` | 无 |
| `LSMinimumSystemVersion` | 14.0 | — |
| AppleScript 字典 | 无（`NSAppleScriptEnabled` 未声明）| 有，但是 Chrome 的通用字典 |

**结论：本项目驱动的目标是 `com.openai.chat`（ChatGPT Classic）**，因为语音能力在它这边。

### 2.2 ChatGPT Classic 注册的 deep link

从 `ChatGPT.framework` 二进制中提取：

```
chatgpt://new-conversation
chatgpt://new-voice-conversation
chatgpt://end-voice-conversation
chatgpt://pause-voice-conversation
chatgpt://followup-prompt
chatgpt://settings/...（多个）
```

二进制中存在 Swift 类型 `NewConversationDeepLink`，其嵌套类型包含 `Mode`；反射字符串中可检出 `prompt`、`query`、`model`、`autoSend`、`auto_send`、`starterPrompt`、`starter_prompt`、`temporaryChat`、`voice_mode`、`hints`。

**推断（未验证）**：`chatgpt://new-conversation` 可能接受 prompt 与 mode 参数，若成立则一条 URL 即可完成「打开应用 + 带入提示词 + 进入语音」。参数的确切拼写必须由 Phase 0 实测确定，见第 12 节。

### 2.3 ChatGPT Classic 不可 AppleScript 化

无 sdef，未声明 `NSAppleScriptEnabled`。因此若 deep link 不支持带入提示词，唯一可行的注入手段是 Accessibility（AXUIElement），需要用户授予「辅助功能」权限。

## 3. 决策记录

| 决策 | 选择 | 备注 |
|---|---|---|
| 功能范围 | 与上游完整对等 | 含题库、计划、复盘、错题、词汇、重训、仪表盘、MCP、Codex 插件 |
| 技术栈 | 全原生 SwiftUI 重写 | 已知代价：工作量远大于复用方案，且无法再跟随上游更新 |
| ChatGPT 驱动方式 | deep link 优先，AX 兜底 | |
| 复盘回收 | 半自动（剪贴板）打底 + 全自动（AX）先试 | 两条都实现，AX 失败自动降级 |
| MCP server | Swift 重写为独立 target | 与 App 共享 `IELTSCoachCore` |
| 分发 | 先自用，架构预留分发能力 | 不购买 Developer ID，但签名/公证/授权引导流程预留 |
| 语音结束判定 | AX 探测 + 手动按钮双保险 | AX 判定失败退回按钮 |
| 辅助功能授权时机 | 首次启动引导 | 可跳过，跳过则运行在半自动模式 |
| 题库来源 | 电子表格/文档导入 | 不做 OCR 工具 |
| 提示词组装 | App 自动拼装，用户不手写 | |
| 最低系统版本 | macOS 14.0 | ChatGPT Classic 自身要求 14.0，更低版本无意义 |
| Bundle ID | `com.ielts.speakingcoach` | 与上游一致；AX 授权绑定它，必须固定 |
| 项目位置 | `~/Projects/ielts-speaking-coach-mac` | |

## 4. 架构

Swift Package Manager 工程，四个模块：

```
IELTSCoach/
├── Sources/IELTSCoachCore/       library     纯逻辑；不依赖 UI，不依赖外部应用
├── Sources/ChatGPTBridge/        library     唯一与 ChatGPT Classic 交互的模块
├── Sources/IELTSCoachApp/        app         SwiftUI 界面
└── Sources/ielts-speaking-mcp/   executable  MCP stdio server
```

依赖方向严格单向：`App → Core + Bridge`，`mcp → Core`，`Bridge → Core`。`Core` 不依赖任何其他模块。

**隔离 `ChatGPTBridge` 是本项目最重要的架构决定。** 它是全工程唯一会因 ChatGPT 更新而失效的地方。集中在一个模块内意味着：失效时只改这一处；App 层只依赖 protocol，可用 mock 完成测试。

### 4.1 IELTSCoachCore

依赖：仅 Foundation。可在无 ChatGPT、无图形界面的环境下完整单元测试。

| 单元 | 职责 | 上游对应 |
|---|---|---|
| `State` | `state.json` 的 Swift 模型，`schemaVersion: 3` | `mcp/server.mjs` 的 `emptyState()` 等 |
| `StateStore` | 原子读写、文件锁、变更通知 | `server.mjs` 数据层 |
| `ReviewParser` | 定界块提取 → JSON 容错修复 → schema 校验 | `desktop/review-parser.mjs` |
| `ReviewArchiver` | 复盘入库：归并错题与词汇、提取重训目标、推进计划进度（第 5 节第 12–16 步）| `server.mjs` 的 `save_session_review` |
| `ExaminerPrompt` | 按 Part/题目/时长/单点目标组装考官提示词 | `references/examiner-protocol.md` |
| `ReviewRequestPrompt` | 组装「请输出结构化复盘」的追加指令 | 同上 |
| `QuestionBank` | CSV / JSON 题库解析、校验、去重、来源标记 | `server.mjs` 题库部分 |
| `PlanBuilder` | 7 / 14 / 30 天计划生成与进度推进 | `server.mjs` 计划部分 |
| `RetrainingPolicy` | 从复盘中选出下次的单点重训目标 | `references/retraining-policy.md` |
| `AnswerUpgradePolicy` | 回答升级建议策略 | `desktop/answer-upgrade-policy.mjs` |
| `VoiceEndPolicy` | 语音结束状态机 | `desktop/voice-end-policy.mjs` |

### 4.2 ChatGPTBridge

依赖：Core、AppKit、ApplicationServices。

对外只暴露一个 protocol，App 层不感知内部用的是 deep link 还是 AX：

```swift
protocol CoachBridge {
    func preflight() async -> BridgeReadiness
    func startSession(prompt: String) async throws -> SessionHandle
    func observeVoiceState() -> AsyncStream<VoiceState>
    func requestReview(instruction: String) async throws
    func captureLatestAssistantMessage() async throws -> CaptureResult
    func endVoice() async throws
}
```

`CaptureResult` 携带来源标记（`.accessibility` / `.clipboard`），供界面提示与诊断使用。

内部三层，按顺序尝试并降级：

1. `DeepLinkLauncher` — 通过 `NSWorkspace.open` 调用 `chatgpt://` 系列
2. `AXDriver` — `AXUIElement` 遍历窗口、注入文本、读取消息、探测语音状态
3. `ClipboardFallback` — 提示词写入 `NSPasteboard` 供粘贴；复盘由用户 ⌘C 后从 `NSPasteboard` 读回

`preflight()` 在会话开始前检查：ChatGPT Classic 是否安装、bundle id 是否为 `com.openai.chat`、辅助功能权限是否已授予（`AXIsProcessTrusted()`）。

另附一个 `AXProbe` 诊断入口：dump 目标窗口的完整 AX 树到文件。Phase 0 用它探路，后续 ChatGPT 改版时用它快速定位失效点。

### 4.3 IELTSCoachApp

SwiftUI。注册自有 URL scheme `ieltscoach://`，供 MCP 的 `open_dashboard` 唤起。

界面清单：仪表盘、练习（选题与进行中）、历史记录、错题本、词汇本、计划、题库导入、单点重训、设置。

### 4.4 ielts-speaking-mcp

只依赖 Core，**不依赖 Bridge**。MCP over stdio（JSON-RPC 2.0），7 个 tool 与上游一致：

`initialize_ielts_workspace`、`open_dashboard`、`set_training_selection`、`get_training_context`、`save_session_review`、`list_practice_history`、`get_dashboard_data`

**上游的 `127.0.0.1:43127` HTTP 服务整体删除**——仪表盘已原生化，不再需要 web 服务。`open_dashboard` 改为 `NSWorkspace.open(URL(string: "ieltscoach://dashboard"))`。

### 4.5 并发写入

App 与 MCP CLI 是两个进程，上游靠「同进程 import」规避的并发问题在此必须正面解决：

- `StateStore` 写入：`flock(F_SETLKW)` 获取排他锁 → 写临时文件 → `rename()` 原子替换 → 释放锁
- `StateStore` 读取：共享锁读取
- App 侧用 `DispatchSource.makeFileSystemObjectSource` 监听 `state.json` 变化，自动重载

7 个 tool 的写入频率极低，无需引入 XPC。

### 4.6 数据目录

`~/Library/Application Support/IELTS Speaking Coach/`

```
state.json          训练状态、题库、计划、错题、词汇、重训目标
reports/            每次复盘的完整报告
pending-reviews/    尚未入库的复盘缓存
recordings/         可选的本地麦克风录音（默认关闭）
```

App 与 MCP CLI 使用同一份路径解析实现。环境变量 `IELTS_SPEAKING_DATA_DIR` 可覆盖（供测试用）。

保持上游 `state.json` 的 schema 不变（`schemaVersion: 3`，文档见上游 `references/storage-schema.md`）。理由：可直接读取已有数据、可与 Windows 版互通、备份即拷贝目录、Codex 插件协议无需改动。

## 5. 端到端流程

### 练习前
1. 用户打开 App，看到当日计划
2. 选择题目、时长、可选的单点目标
3. `ExaminerPrompt` 组装考官提示词

### 开始练习
4. `CoachBridge.preflight()` 检查环境
5. `CoachBridge.startSession(prompt:)`
   - 主路径：`chatgpt://new-conversation?<prompt 参数>&<voice 模式参数>`
   - 降级路径：`chatgpt://new-conversation` → 提示词写入剪贴板 → AX 注入或用户粘贴 → 回车 → `chatgpt://new-voice-conversation`
6. App 进入「练习中」状态

### 练习结束
7. 结束判定二选一先到者：`observeVoiceState()` 探测到结束，或用户点击 App 内的「我练完了」按钮
8. `requestReview(instruction:)` 发送复盘指令
9. `captureLatestAssistantMessage()`
   - 优先 AX 读取
   - 失败或内容不完整 → 降级为提示用户 ⌘C，从剪贴板读回
10. `ReviewParser` 提取定界块 → JSON 容错修复 → schema 校验
11. 写入 `pending-reviews/`

### 存档之后
12. 从 `pending-reviews/` 正式入库：写 `reports/`，更新 `state.json`
13. 复盘中的语法/发音问题进错题本，重复出现的标记为高优先级
14. 推荐词汇进词汇本
15. `RetrainingPolicy` 选出下次的单点重训目标
16. 计划进度推进

**第 11 步与第 12 步分离是刻意的**（沿用上游设计）：复盘先落盘再入库，中途崩溃或误关窗口都不丢数据，下次启动可继续处理。

## 6. 降级与错误处理

| 失败情形 | 行为 |
|---|---|
| 未安装 ChatGPT Classic | 明确报错 + 提供下载指引，不进入练习流程 |
| 只装了 `com.openai.codex` 那个 ChatGPT | 识别 bundle id，明确提示需要 ChatGPT Classic |
| deep link 不支持 prompt 参数 | 自动降级为剪贴板 + 粘贴，用户无感 |
| 未授予辅助功能权限 | 跳转 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`，说明用途；用户拒绝则运行在半自动模式 |
| AX 读不到复盘或内容截断 | 降级为「请按 ⌘C」，界面明确提示 |
| 复盘 JSON 格式残缺 | 先自动修复；仍失败则保留原文到 `pending-reviews/`，界面提供「重新生成」 |
| ChatGPT 大改版导致 AX 全面失效 | 全流程降级为半手动：App 负责组装提示词 + 剪贴板收发。核心功能保持可用 |
| 练习中途 App 崩溃 | 复盘留在 `pending-reviews/`，下次启动继续处理 |

**硬性原则：任何失败都必须以自然语言告知用户发生了什么、下一步该做什么。禁止静默失败，禁止无限等待。**

上游用 `phase` 状态机 + 中文提示实现了这一点，本项目沿用该思路，在 SwiftUI 中以 `@Observable` 的会话状态机表达。

最后一行的全面降级路径是整套设计的安全网：即便 OpenAI 大幅改动 ChatGPT，本 App 也不会变为不可用，只是从全自动退回「多按一次 ⌘C」。

## 7. 权限与分发

- **辅助功能**：首次启动引导授权，可跳过；跳过后运行在半自动模式，设置中可随时开启
- **麦克风**：仅在用户启用本地录音时申请，`NSMicrophoneUsageDescription` 声明用途
- **签名**：开发阶段必须使用固定的签名身份。ad-hoc 签名每次编译都会变，导致辅助功能授权反复失效
- **分发预留**：Hardened Runtime、`com.apple.security.device.audio-input` entitlement、公证脚本在 Phase 5 一并配好，但不购买 Developer ID；未来需要分发时只需接入证书重新打包

## 8. 测试策略

| 层 | 方式 |
|---|---|
| `IELTSCoachCore` | XCTest 单元测试。上游 3 个逻辑测试文件（`review-parser`、`answer-upgrade-policy`、`voice-end-policy`）逐一对译 |
| `ChatGPTBridge` | 依赖 protocol + mock 完成逻辑测试。真机集成测试单独标记，手动执行 |
| `ielts-speaking-mcp` | 对译上游 `mcp/test-client.mjs` 的 stdio 冒烟测试 |
| 界面 | 人工验收，按 Phase 3 逐屏交付 |
| 诊断 | `AXProbe` dump 工具，用于 Phase 0 探路与后续故障定位 |

上游第 4 个测试文件 `review-controls.test.mjs` **不移植**：它是对 `dashboard.html` 与 IPC 通道名的字符串断言，与 Electron/HTML 实现强绑定，在 SwiftUI 中无对应物。其真实意图——保证「同步复盘报告」与「补生成复盘报告」是两个始终存在且语义互不混淆的操作——改由界面人工验收覆盖，并在 Phase 3 的验收清单中列明。

## 9. 阶段划分

| 阶段 | 内容 | 可并行 | 交付物 |
|---|---|---|---|
| **0 · 探路** | 实测 deep link 参数、AX 可读性 | 否，必须最先 | 实测结论 + `AXProbe` 雏形 |
| **1 · 地基** | `IELTSCoachCore` 全部单元 + 测试 | 是 | 测试全绿 |
| **2 · 能练一次** | `ChatGPTBridge` + 最小练习界面 | 部分 | **第一个可用版本：能完成一次练习并存下复盘** |
| **3 · 全部界面** | 仪表盘、历史、错题本、词汇本、计划、题库导入、重训、设置 | 是，按屏切分 | 逐屏交付验收 |
| **4 · MCP** | `ielts-speaking-mcp` + Codex 插件配置 | 是 | Codex 可调用 |
| **5 · 收尾** | 授权引导、图标、打包、固定签名 | 部分 | 可双击安装的 `.app` / `.dmg` |

Phase 0 不可并行跳过：其结果会改变 `ChatGPTBridge` 的设计，提前开工等于让并行工作朝可能错误的方向推进。

Phase 2 之后用户即可实际使用，其后均为增量。

## 10. 明确不做的事

- **不做 OCR 题库导入工具**：用户题库已是电子表格形态。上游的 `scripts/ocr-*.ps1` 不移植
- **不内置商业题库**：仅附带原创样例题库，与上游的版权立场一致
- **不做 HTTP dashboard 服务**：仪表盘已原生化
- **不引入 OpenAI API 依赖**：复盘由 ChatGPT 自身在同一会话内生成，不产生额外 API 费用
- **不做系统音频录制**：ScreenCaptureKit 录制 ChatGPT 输出音频的双轨方案本次不纳入。注意与之区分：**本地麦克风录音（可选、默认关闭）属于范围内**，与上游一致，见 4.6 与第 7 节
- **不购买 Developer ID / 不做公证**：架构预留，本期不执行
- **不跟随上游更新**：全原生重写即自立门户，这是已知且已接受的代价

## 11. 待验证的假设（Phase 0）

以下假设直接影响 `ChatGPTBridge` 设计，必须在 Phase 1 开工前用实测给出结论。每条都附有明确的决策规则，不存在悬空状态。

| # | 假设 | 验证方法 | 若不成立 |
|---|---|---|---|
| 1 | `chatgpt://new-conversation` 接受携带提示词的查询参数 | 依次实测候选拼写：`prompt`、`query`、`starter_prompt`、`starterPrompt` | 降级：deep link 开新会话 + 剪贴板 + AX 注入 |
| 2 | 同一 deep link 可直接指定语音模式 | 实测 `mode=voice`、`voice_mode=1` 等候选 | 降级：先建会话，再调 `chatgpt://new-voice-conversation` |
| 3 | 存在自动发送参数 | 实测 `auto_send`、`autoSend` | 降级：AX 注入后模拟回车 |
| 4 | AX 树暴露对话消息文本 | `AXProbe` dump 窗口树，检查是否存在消息节点 | 复盘回收固定走剪贴板路径，AX 仅用于语音状态探测 |
| 5 | AX 能读到滚出屏幕的历史消息 | 制造长对话后 dump，比对可读条数 | 同上；这是最可能不成立的一条 |
| 6 | AX 能探测语音会话的开始与结束 | 语音进行中与结束后各 dump 一次，比对差异 | 语音结束完全依赖用户点击 App 内按钮 |

假设 4 与 5 若均不成立，则「全自动复盘」不可行，项目按半自动模式交付——这已在决策阶段被接受，不构成阻塞。
