# IELTS Speaking Coach for macOS — 设计文档

日期：2026-08-04
上游参考：https://github.com/lindsey-labs/ielts-speaking-coach（v0.1.49）

## 1. 背景

上游项目是一套雅思口语训练工作流：导入题库 → 选题 → 用 ChatGPT Voice 模拟考官 → 生成结构化复盘 → 归档错题与词汇 → 单点重训。它由三部分组成：一个 Electron 桌面应用、一个本地 MCP server、一个 Codex 插件。

上游的桌面应用把 chatgpt.com 装进一个 Electron 窗口，靠操控网页 DOM 来发送提示词、点击 Voice 按钮、读回对话文本。这套做法在 macOS 上有多处失效点，且始终受制于 ChatGPT 网页结构的变化。

本项目不是把上游移植到 macOS，而是**用原生技术重写，并把「操控网页」换成「驱动本机的 ChatGPT 桌面应用」**。

## 2. 实测前提

以下结论来自 2026-08-04 在目标机器（macOS 26.5.2，Apple Silicon）上的**动态实测**——在真实运行的应用上、在真实的语音会话进行中采集，非静态推断。

> **本节初稿的结论是错的，且错得很彻底。** 保留纠错记录见 2.5，因为那个错误的推理方式比结论本身更值得记住。

### 2.1 本机存在两个 ChatGPT 应用

| | `/Applications/ChatGPT.app` | `/Applications/ChatGPT Classic.app` |
|---|---|---|
| Bundle ID | **`com.openai.codex`** | `com.openai.chat` |
| 版本 | 26.727.51351（Chromium 150.0.7871.182）| 1.2026.160 |
| 实现 | Chromium 壳（Codex Framework）| 原生 Swift |
| **live 语音** | ✅ **有**（实测语音会话）| ❌ **无**（输入区无任何语音按钮）|
| Info.plist 麦克风声明 | `for voice input` + 摄像头 + `NSAudioCaptureUsageDescription` + `audio/ogg`、`audio/webm` | `for voice mode, dictation, and meeting recordings`（措辞如此，但界面无对应功能）|
| URL scheme | `codex://`（二进制内搜不到任何可用路径）| `chatgpt://`、`openai://`（路径丰富，但无语音）|
| AppleScript | 继承 Chrome 完整 sdef（含 `execute javascript`），**但是空壳** | 无 sdef |
| AX 内容树 | ✅ 完整暴露（见 2.3）| 对话列表为 `AXCollectionList children=0` |

**结论：本项目驱动的目标是 `com.openai.codex`（新 ChatGPT.app）。**

### 2.2 两条已排除的路径

**deep link —— 不适用。** `chatgpt://new-conversation` / `new-voice-conversation` / `end-voice-conversation` / `pause-voice-conversation` / `followup-prompt` 这批链接确实存在，但它们属于 **ChatGPT Classic**，而 Classic 没有语音。新目标只注册 `codex://` scheme，其 255MB 主二进制内**搜不到任何 `codex://` 路径字符串**。

**AppleScript 注入 JavaScript —— 不可用。** 新目标继承了 Chrome 的完整 AppleScript 字典，含 `execute … javascript`，一度看起来是比 AX 更强的通道。实测否定：System Events 报告该进程有 1 个可见窗口，而应用自己的 AppleScript 报 `windows=0`，取不到任何 tab。字典是继承来的空壳，窗口/标签模型未接线。

### 2.3 新目标的 AX 能力（实测通过）

Chromium 的无障碍树是**惰性构建**的。初次探测仅 234 节点、深度 7、无 `AXWebArea`；对 application 元素尝试设置 `AXManualAccessibility` / `AXEnhancedUserInterface`（两者均返回错误码）并等待约 3 秒后，树扩展到 **675 节点、深度 34、`AXWebArea`×12**。

在真实语音会话进行中采集到的关键节点：

| 用途 | 节点 |
|---|---|
| 启动语音 | `AXButton`，desc 为 `"Start voice chat"` 或 `"Start new voice chat"`（**标签不稳定，见 2.3.1**）|
| 结束语音 | `AXButton desc="Stop voice chat"` |
| 语音进行中标志 | `AXImage desc="Voice chat active"` |
| 静音状态 | `AXCheckBox desc="Mute voice chat"` / `"Unmute microphone"` / `"Mute speakers"` |
| 语音控制浮层 | `AXWindow title="Codex Pet Voice Controls Glass"` |
| 输入框 | `AXTextArea desc="Work with ChatGPT"` |
| 对话文本 | `AXStaticText`（考官原话 166 字符逐字读出）|

**输入框可写：** 对 `AXTextArea` 设置 `kAXValueAttribute` 返回码 0，写入即时生效，`AXUIElementIsAttributeSettable` 亦返回 true。

**`kAXPressAction` 可用：** 实测按下语音按钮真实进入语音会话，按下 `Stop voice chat` 真实结束（截图与 AX 树双重确认）。

#### 2.3.1 按标签匹配元素是不安全的 —— 必须结构化判别

实测踩到一次**假阳性**：按 `desc == "New voice chat"` 精确匹配并取深度优先第一个命中，返回成功（`kAXPressAction` 返回 0），但点中的是**侧边栏里一条同名的历史会话**，语音根本没启动。

两个独立的失效原因：

1. **控制按钮自身的标签会变。** 同一台机器上先后观察到 `Start new voice chat` 与 `Start voice chat` 两种 desc，均非最初记录的 `New voice chat`。
2. **侧边栏会话名会与控制标签撞车，且这个撞车是本产品自己制造的。** ChatGPT 每开一次语音就自动生成一条名为 `New voice chat` 的会话记录，还会自动改名成 `Voice Chat Title Generation` 之类。用得越久，侧边栏里的同名项越多。会话名由用户和 ChatGPT 生成，本质上不可信。

**结构判别规则（稳定，且与标签文字无关）：**

| | 真控制按钮 | 侧边栏会话行 |
|---|---|---|
| 子节点 | 恰好一个，且为 `AXImage` | 嵌套 `AXButton`（含 `Pin chat`、`Archive chat`）|
| 是否含文本后代 | 否（纯图标）| 是（显示会话标题）|
| 相邻元素 | `AXButton desc="Dictate"` | 会话列表中的其他会话 |

因此 `AXDriver` 查找控制元素时**必须**同时满足：role 为 `AXButton` 或 `AXCheckBox`、desc 命中候选标签集合、**且子节点恰好一个且为 `AXImage`**。仅凭标签匹配是缺陷。

**该结构规则的适用范围已实测验证覆盖全部语音控件**，不止按钮：

| 控件 | role | subrole | 子节点 |
|---|---|---|---|
| `Stop voice chat` | `AXButton` | — | 1 × `AXImage` |
| `Mute speakers` | `AXCheckBox` | `AXToggleButton` | 1 × `AXImage` |
| `Mute microphone` | `AXCheckBox` | `AXToggleButton` | 1 × `AXImage` |

静音类控件另带 `subrole=AXToggleButton`，可作为额外的判别信号；其 `value` 字段（`0`/`1`）即当前静音状态，无需另找指示器。

**由此确立的规则：任何「按标签找元素再操作」的代码，都必须有结构约束兜底，并且在操作后验证预期状态真的发生了**（例如按下启动语音后应能观察到 `Voice chat active` 出现）。返回码为 0 不等于动作生效。

#### 2.3.2 元素出现有延迟 —— 操作之间必须等待重试

实测：按下启动语音成功后**立即**查找 `Stop voice chat`，报「找不到」；等界面渲染完成后重试，同一按钮存在且可按下（结构也符合 2.3.1 的判据）。

语音浮层的渲染晚于 `kAXPressAction` 返回。因此 `AXDriver` 的每个操作都必须遵循「**等目标元素出现 → 操作 → 验证状态变化**」，不得在一次动作后假设下一个元素已经就位。惰性 AX 树的唤醒（`AXTree.wake`）只保证 `AXWebArea` 出现，不保证特定控件已渲染。

建议的通用原语：`waitForElement(role:labels:timeout:)`，轮询间隔 0.3 秒、默认超时 5 秒，超时按 spec 第 6 节的规则报中文错误并给出下一步。

#### 2.3.4 输入框的描述随状态而变；发送要用 Send 按钮而非回车

**2026-08-05 首次真机联调发现的三件事。** 前面所有 AX 结构都是在**语音会话进行中**采集的，导致把语音状态下的特征当成了通用特征。

| | 普通聊天状态 | 语音会话中 |
|---|---|---|
| 输入框 desc | `Message ChatGPT` | `Work with ChatGPT` |

**发提示词时 ChatGPT 还没进语音**，所以匹配的是前者。初版只认 `Work with ChatGPT`，全靠「界面上只有一个 AXTextArea 就用它」的兜底才没写丢。两个都要作为候选。

**发送必须按 `AXButton desc="Send"`，不能靠模拟回车。** 该按钮就在输入框旁边、结构为单个 `AXImage` 子节点（符合 2.3.1 的判据）。实测模拟回车不会发送——文字留在输入框里。

**「输入框内容 ≠ 刚写进去的文字」不是有效的发送判据。** AX 读回的值与写入值不可能逐字节相同（应用会做换行与空白规范化），该判断一开始就成立，验证等于没做。正确判据是**输入框变空**。

这是本项目第二次栽在「验证只问『现在是不是目标态』、没问『到底变没变』」上（第一次见 2.3.1 的假阳性点击）。

#### 2.3.5 【已修正】必须先进语音，再发提示词

**用户第一次给的顺序是错的，第二次纠正了。** 实际约束是：

> **Live 语音只能在还没发送过任何消息的会话里启动。**

所以正确顺序是：**新建会话 → 点语音 → 等 5~10 秒它弹出输入框 → 再写入并发送提示词。**

先发提示词会让该会话失去启动 Live 的资格——这正是首次真机联调两次失败的根因。此约束从 AX 树上完全看不出来，只能靠实际使用发现。

由此也解释了 2.3.4 那个描述差异：`Work with ChatGPT` 是**语音模式下的**输入框，正是本流程该写入的那一个。

**推论：每次练习都应先按 `AXButton desc="New chat"` 新建会话**（结构为单个 `AXImage` 子节点，符合 2.3.1 判据），以保证「未发送过消息」这个前提成立。旧会话仍保留在侧边栏，不丢数据。

#### 2.3.7 Live 启动的真实时序（实测逐秒采样）

用户手动点 Live，每秒采样一次，连采 25 秒：

| 秒 | `Voice chat active` | `Send` 按钮 | 输入框 |
|---|---|---|---|
| 0–3 | 无 | 有 | `Message ChatGPT` |
| 4–8 | 无 | **消失** | `Message ChatGPT` |
| **9** | **✅ 出现** | 无 | `Message ChatGPT` |
| 10–11 | ✅ | 无 | `Message ChatGPT` |
| **12** | ✅ | 无 | **`Work with ChatGPT`** |
| 13–24 | ✅ | 无 | `Work with ChatGPT` |

**三条结论，每条都推翻了一处实现假设：**

1. **Live 需要约 9 秒才启动。** 原 `stateTimeout = 8.0` 正好卡在它起来的前一秒，这是首次真机联调「等了 8 秒，语音会话开始仍未发生」的直接原因。超时须放宽到 20 秒以上。
2. **语音输入框比语音本身还晚约 3 秒出现，且换了描述。** 第 9~11 秒这个窗口里界面上摆的仍是**普通**输入框 `Message ChatGPT`。「等到有输入框就发」会在第 9 秒命中它，把考官提示词发进错误的框。**必须专门等 `Work with ChatGPT` 出现。**
3. **语音模式下没有 Send 按钮**（第 4 秒起消失，整个语音期间未再出现）。「写入 + 按 Send」在语音模式下可能不可用，需要备选发送方式，且无论走哪条都要验证输入框回到空态。

空态 value 依然遵循 2.3.6 的规律：`\nWork with ChatGPT` = 换行 + 自身 description。

#### 2.3.6 空输入框的 AX value 是占位符，不是空字符串

实测：输入框为空时 `value` 为 `"\nMessage ChatGPT"` —— **换行 + 它自己的 description**。

因此「等到 value 变空」这个判据永远等不到，消息明明已经发出去了也会超时。这是本项目**第三次**栽在「验证的判据与实际观测对不上」：

1. 点中侧边栏同名会话，`kAXPressAction` 返回成功（2.3.1）
2. 「内容 ≠ 刚写进去的文字」永远成立，等于没验证（2.3.4）
3. 「value 变空」永远不成立，因为空态是占位符

**正确判据：** 去空白后为空，**或**等于该元素自己的 `description`。


#### 2.3.3 `Voice chat active` 是会话级常驻，不随语音活动闪烁

实测：启动语音后**全程不说话**，每 500ms 采样一次、持续 20 秒（40 次采样），`AXImage desc="Voice chat active"` **一次都没有消失**。

```
时间轴（# = 指示器在，每格 0.5 秒）
########## ########## ########## ##########
消失次数：0/40
```

**这条实测关闭了一个真实的设计风险。** 审查曾指出：新的 `VoiceEndPolicy` 去掉了上游那个「最短 12 秒」门槛，只靠 3 次轮询（约 1.5 秒）去抖；若该指示器跟随语音活动（VAD）闪烁，考生思考时的正常停顿就会击穿去抖窗口，把练习中途误判为结束——对非母语考生来说停顿几秒极为常见。

实测结果表明该指示器是**会话级**信号，静默不影响它。因此：

- 1.5 秒去抖窗口是安全的
- **不要**把上游的最短时长门槛加回来。它在上游是必需的，因为上游的信号本身不可靠；这里的信号是直接且稳定的，加时长门槛只会让短题目无法正常结束

### 2.3.8 复盘指令必须规定到**每条内部**的字段名

首次真机练习成功后发现：复盘 JSON 完整（6975 字符、标记齐全、七个顶层键全在），但归档进错题本 0 条、词汇本 0 条。

原因是 `ReviewRequestPrompt` **只规定了顶层键名，没规定每条里面的字段名**。实测对照：

| 顶层键 | 指令是否规定了内部结构 | ChatGPT 实际输出 |
|---|---|---|
| `answer_upgrades` | ✅ 规定了 | `{question, original_answer, revised_answer, changes}` —— **完全对上** |
| `priority_target` | ✅ 规定了 | `{id, label, status, evidence}` —— **完全对上** |
| `must_correct` | ❌ 只写了键名 | `{issue, examples, fix}`（归档代码找的是 `learner_said`/`correction`/`why_it_matters`）|
| `vocabulary` | ❌ | **对象**而非数组：`{useful_replacements, pronunciation}` |
| `natural_upgrades` | ❌ | `{area, advice}` |
| `logic_feedback` | ❌ | `{question_area, feedback}` |
| `habits` | ❌ | 纯字符串数组 |

**规律：指令规定到哪一层，输出就对齐到哪一层。** 这不是模型不听话，是指令只写了一半。

**后果属于本项目反复出现的那一类：不报错、不崩溃、只是悄悄什么都没归档。** 解析器只校验顶层键是否存在，内部结构不合它一概不管。用户练一场、复盘写得好好的，而错题本永远是空的。

由此确立两条规则：

1. **`ReviewRequestPrompt` 必须把每个数组元素的字段名逐一写死**，与 `ReviewArchiver` 读取的字段严格一一对应。
2. **`ReviewArchiver` 必须能报告「顶层键存在但一条都没归进去」**。归档 0 条不等于没错题——更可能是字段名对不上。静默的 0 是本项目已知最危险的失败形态。

### 2.4 输入框与语音共存

`AXTextArea desc="Work with ChatGPT"` 与 `Stop voice chat`、`Mute speakers` 等按钮**位于同一控制条内**——语音进行中依然可以发送文字。

这一条推翻了原设计的流程假设。原方案（沿袭上游）是「发提示词 → 进语音 → **退出语音** → 发复盘指令 → 读复盘」。实测后改为**全程不离开语音**：提示词、口语练习、复盘指令、读回复盘在同一个语音会话内连续完成。

同时它作废了上游 `voice-end-policy.mjs` 的移植价值：那套状态机靠「语音界面消失、输入框重新出现」推断结束，而此处两者共存，前提不成立。改用 `AXImage desc="Voice chat active"` 直接判定。

### 2.5 纠错记录：一个方法论错误

初稿断定「语音在 Classic」，依据是 Classic 打包了 `LiveKitWebRTC.framework` 而新应用没有。两处都错：

1. **打包了框架 ≠ 具备该功能。** 框架可能服务于会议录制等其他用途，或是历史残留。
2. **反向推理更错。** 新应用是 Chromium 壳，WebRTC 由 Chromium 自身提供，本就不需要单独打包 LiveKit。「它没有该框架」对其语音能力**不构成任何证据**。

用一个单向的弱信号当成了双向的强证据。更该记住的是：纠正这个错误的不是后续推理，而是**用户的一句直接观察**，而当时手上的 AX dump 里其实已经写着「Classic 输入区只有 Attach / Search / Work with Apps / Options / Record meeting / Dictation / Send，没有语音按钮」——证据早已在手，只是没被读懂。

**由此确立的规则：涉及外部应用能力的判断，一律以在运行中的应用上实测为准，不接受从二进制内容、框架清单、Info.plist 措辞推断出的结论。**

## 3. 决策记录

| 决策 | 选择 | 备注 |
|---|---|---|
| 功能范围 | 与上游完整对等 | 含题库、计划、复盘、错题、词汇、重训、仪表盘、MCP、Codex 插件 |
| 技术栈 | 全原生 SwiftUI 重写 | 已知代价：工作量远大于复用方案，且无法再跟随上游更新 |
| **目标 ChatGPT 应用** | **`com.openai.codex`（新 ChatGPT.app）** | 实测确认语音在此。`com.openai.chat`（Classic）无语音，不是目标 |
| ChatGPT 驱动方式 | **AX 为主，剪贴板兜底** | deep link 与 AppleScript-JS 两条路均实测排除，见 2.2 |
| 会话流程 | **全程不离开语音** | 输入框与语音控制共存，实测确认，见 2.4 |
| 复盘回收 | 半自动（剪贴板）打底 + 全自动（AX）先试 | 两条都实现，AX 失败自动降级 |
| MCP server | Swift 重写为独立 target | 与 App 共享 `IELTSCoachCore` |
| 分发 | 先自用，架构预留分发能力 | 不购买 Developer ID，但签名/公证/授权引导流程预留 |
| 语音结束判定 | 读 `AXImage desc="Voice chat active"` + 手动按钮双保险 | **不移植上游 voice-end-policy.mjs**，其前提在新目标上不成立，见 2.4 |
| 辅助功能授权时机 | 首次启动引导 | 可跳过，跳过则运行在半自动模式 |
| 题库来源 | 电子表格/文档导入 | 不做 OCR 工具 |
| 提示词组装 | App 自动拼装，用户不手写 | |
| **反馈时机** | **用户可选：全程零反馈 / 当场点出** | 前者像真考试，后者牺牲考试真实感换即时纠正。见 3.1 |
| **Part 2 准备时间** | **用户可选：一分钟倒计时 / 学员自己决定** | 前者像真考试，后者不催人。见 3.1 |
| 停止口令 | 英文（`stop the test`）| 原为中文「结束训练」，混在英文提示词里易让 ChatGPT 出戏 |
| 反馈语言 | **中文** | 考官的即时点评与最终复盘都用中文；英文证据原文保留不译 |
| 最低系统版本 | macOS 14.0 | 保持不变；新目标为 Chromium 应用，系统要求不高于此 |
| Bundle ID | `com.ielts.speakingcoach` | 与上游一致；AX 授权绑定它，必须固定 |
| 项目位置 | `~/Projects/ielts-speaking-coach-mac` | |

### 3.1 两个练习模式开关（用户决策，2026-08-05）

这两项由用户在开始练习前选择，不是写死的规则。

**反馈时机 `FeedbackTiming`**

| 取值 | 行为 | 取舍 |
|---|---|---|
| `deferred` | 考官全程不纠错、不夸、不解释，所有反馈憋到最后的结构化复盘 | 像真考试。但答砸的地方要等到最后才知道 |
| `immediate` | 每答完一题，考官用中文当场点出最主要的一个问题（不超过两句），然后立刻问下一题 | 纠正来得及时。代价是不再是真实考试节奏，且会拖长单场时间 |

**Part 2 准备时间 `Part2PrepMode`**

| 取值 | 行为 | 取舍 |
|---|---|---|
| `countdown` | 宣布一分钟准备并倒计时，时间到自动开始 | 像真考试，练的是压力下组织语言 |
| `learnerControlled` | 让学员自己说准备好了再开始，不限时、不催 | 适合刚起步时先把内容想清楚 |

**语言规则（两种模式都适用）：** 考官提问与追问用英文；**所有点评、解释、复盘用中文**；引用学员原话或给出英文范例时保持英文原文不译。

**注意 `immediate` 模式的固有代价**：它让 ChatGPT 在考试中途跳出考官角色。这与「考官全程保持中立」的契约天然冲突，因此该模式下的提示词必须明确限定点评的长度与形式（一到两句、只说最重要的一个问题、说完立刻回到考官角色），否则 ChatGPT 容易越讲越多，把练习变成上课。

## 4. 架构

Swift Package Manager 工程，四个模块：

```
IELTSCoach/
├── Sources/IELTSCoachCore/       library     纯逻辑；不依赖 UI，不依赖外部应用
├── Sources/ChatGPTBridge/        library     唯一与 ChatGPT.app 交互的模块
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
| `VoiceEndPolicy` | 语音结束判定 | **不移植上游** —— 上游靠「语音界面消失、输入框重新出现」推断，该前提在新目标上不成立（2.4）。改为读 `AXImage desc="Voice chat active"` 的直接信号，配合去抖动窗口避免瞬时抖动误判 |

### 4.2 ChatGPTBridge

依赖：Core、AppKit、ApplicationServices。

对外只暴露一个 protocol，App 层不感知内部用的是 AX 还是剪贴板：

```swift
protocol CoachBridge {
    func preflight() async -> BridgeReadiness
    func sendText(_ text: String) async throws          // 写入输入框并发送
    func startVoice() async throws
    func observeVoiceState() -> AsyncStream<VoiceState>
    func captureLatestAssistantMessage() async throws -> CaptureResult
    func endVoice() async throws
}
```

`CaptureResult` 携带来源标记（`.accessibility` / `.clipboard`），供界面提示与诊断使用。

**注意 `sendText` 取代了原设计的 `startSession(prompt:)` 与 `requestReview(instruction:)`。** 既然输入框与语音共存（2.4），发考官提示词和发复盘指令是同一个动作，没有理由拆成两个方法。

内部两层，按顺序尝试并降级：

1. `AXDriver` — 主路径。启用惰性 AX 树后：写 `AXTextArea` 的 `kAXValueAttribute` 注入文本、对按钮执行 `kAXPressAction`、遍历 `AXStaticText` 读消息、读 `AXImage desc="Voice chat active"` 判定语音状态
2. `ClipboardFallback` — 提示词写入 `NSPasteboard` 供用户粘贴；复盘由用户 ⌘C 后从 `NSPasteboard` 读回

原设计的 `DeepLinkLauncher` 层**已删除**——deep link 对新目标不适用（2.2）。降级层数由三层减为两层。

`AXDriver` 必须在每次会话开始时执行**惰性树唤醒**：对 application 元素设置 `AXManualAccessibility` 与 `AXEnhancedUserInterface`（两者返回错误码属正常，不得据此判定失败），随后等待并轮询直到 `AXWebArea` 出现或超时。跳过这一步会看到一棵只有菜单栏的空树。

`preflight()` 在会话开始前检查：`com.openai.codex` 是否安装并运行、辅助功能权限是否已授予（`AXIsProcessTrusted()`）、惰性树唤醒后能否找到 `AXTextArea desc="Work with ChatGPT"`。

另附一个 `AXProbe` 诊断入口：dump 目标窗口的完整 AX 树到文件。后续 ChatGPT 改版时用它快速定位失效点——**这是本项目最重要的排障工具**，因为 2.3 表格里那七个节点特征全都可能随 ChatGPT 更新而改变。

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
4. `CoachBridge.preflight()` 检查环境并唤醒惰性 AX 树
5. `CoachBridge.sendText(examinerPrompt)` — 写入 `AXTextArea` 并发送
6. `CoachBridge.startVoice()` — 对 `AXButton desc="New voice chat"` 执行 `kAXPressAction`
7. App 进入「练习中」状态，`observeVoiceState()` 轮询 `AXImage desc="Voice chat active"`

### 练习结束
8. 结束判定二选一先到者：`observeVoiceState()` 探测到 `Voice chat active` 消失，或用户点击 App 内的「我练完了」按钮
9. `CoachBridge.sendText(reviewInstruction)` — **不需要退出语音**（2.4）
10. `captureLatestAssistantMessage()`
    - 优先 AX 读取 `AXStaticText`
    - 失败或内容不完整 → 降级为提示用户 ⌘C，从剪贴板读回
11. `ReviewParser` 提取定界块 → JSON 容错修复 → schema 校验
12. 写入 `pending-reviews/`

> 第 9 步刻意保留在语音会话内。上游必须先退出语音才能发文字，本设计不必——整场练习是一个连续的语音会话，ChatGPT 的上下文不被打断，复盘质量更有保障。

### 存档之后
13. 从 `pending-reviews/` 正式入库：写 `reports/`，更新 `state.json`
14. 复盘中的语法/发音问题进错题本，重复出现的标记为高优先级
15. 推荐词汇进词汇本
16. `RetrainingPolicy` 选出下次的单点重训目标
17. 计划进度推进

**第 12 步与第 13 步分离是刻意的**（沿用上游设计）：复盘先落盘再入库，中途崩溃或误关窗口都不丢数据，下次启动可继续处理。

## 6. 降级与错误处理

| 失败情形 | 行为 |
|---|---|
| 未安装 `com.openai.codex`（新 ChatGPT.app）| 明确报错 + 提供下载指引，不进入练习流程 |
| 只装了 `com.openai.chat`（Classic）| 识别 bundle id，明确说明 Classic 没有 live 语音、需要安装新版 ChatGPT.app |
| 目标应用未运行 | 用 `NSWorkspace` 启动它并等待就绪；超时则报错并提示用户手动打开 |
| 惰性 AX 树唤醒后仍找不到 `AXWebArea` 或输入框 | 视为 AX 通道不可用，整体降级到剪贴板模式，并提示运行 `AXProbe` 收集诊断信息 |
| 未授予辅助功能权限 | 跳转 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`，说明用途；用户拒绝则运行在半自动模式 |
| 找不到 `New voice chat` 按钮 | 提示用户手动点击语音按钮，App 继续用 `Voice chat active` 监测状态 |
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

## 11. Phase 0 假设的验证结果

初稿列了 6 条假设。实测后，其中 3 条随目标应用变更而作废，2 条成立，1 条待验证。**结论均以在运行中的应用上实测为准**（见 2.5 确立的规则）。

| # | 假设 | 结论 | 依据 |
|---|---|---|---|
| 1 | deep link 接受携带提示词的查询参数 | **作废** | 属于 Classic，而 Classic 无语音。新目标无可用 deep link（2.2）。改由 AX 写 `kAXValueAttribute`，已实测成功 |
| 2 | deep link 可直接指定语音模式 | **作废** | 同上。改由 AX 按下 `AXButton desc="New voice chat"` |
| 3 | 存在自动发送参数 | **作废** | 同上。改由 AX 发送 |
| 4 | AX 树暴露对话消息文本 | ✅ **成立** | 语音会话中读出考官原话 166 字符，逐字可读（2.3）|
| 5 | AX 能读到滚出屏幕的历史消息 | ⏳ **待验证** | 见下 |
| 6 | AX 能探测语音会话的开始与结束 | ✅ **成立** | `AXImage desc="Voice chat active"`、`AXButton desc="Stop voice chat"`（2.3）|

### 关于假设 5

这是唯一未关闭的一条，需要在新目标上造出 30 轮以上的长对话后 dump，统计可读消息条数。

**它的风险性质已经改变。** 初稿担心的是「SwiftUI 列表懒加载，读不到就是绕不过去」；新目标是 Chromium 应用，问题变成「ChatGPT 网页端是否虚拟化 DOM」——而这正是上游 Electron 版本已经跑通过的场景。风险等级由「可能推翻方案」降为「可能需要先滚动加载」。

**若不成立：** 复盘回收固定走剪贴板路径（用户按 ⌘C），AX 仍用于写入、启停语音、状态探测。全自动降为半自动，其余架构不变。这已在决策阶段被接受，不构成阻塞。

### 仍需实测的两个动作

以下两项属 AX 标准操作，风险低，但不接受「标准操作应该没问题」这种论证，须在 Phase 2 实装时各真跑一次：

- 对按钮执行 `kAXPressAction`（用于启停语音）
- 发送已写入的文本（回车键事件或按下发送按钮）
