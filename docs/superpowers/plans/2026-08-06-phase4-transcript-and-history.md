# Phase 4：逐字稿采集 + 训练记录

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每一场练习都在 `state.sessions` 里留下一条完整记录——题目、起止时间、**问答逐字稿**、复盘报告路径；「训练记录」页按月分组把它们列出来、能点开回看、能单条删除（连带清掉录音）；复盘自动取回失败时，用户能在界面里把 `pending-reviews/` 里的原文重新导入，**不需要打开终端**。

**Architecture:** 沿用既有的四层依赖方向（`App → UI → Core + Bridge`，`Bridge → Core`，`Core` 谁都不依赖）。本阶段最难的一块是「AX 树里的碎片文本 → 干净的逐字稿」，因此**刻意把它劈成两半**：

| 半边 | 放哪儿 | 为什么能测 |
|---|---|---|
| **采样**：从 AX 树里捞出文本碎片、判断是谁说的 | `ChatGPTBridge/AXTranscriptSampler.swift` | 走已有的 `AXAccess` protocol 接缝，用 `FakeAXAccess` 摆出任意一棵树 |
| **拼接去重**：把十几个版本的同一条消息收敛成一条 | `IELTSCoachCore/Transcript/TranscriptAssembler.swift` | 纯字符串逻辑，不碰 AX、不碰文件、**不碰时钟**（时间由调用方传入） |

这一刀是本阶段能不能做对的关键。合在一起写的话，「拼接规则对不对」就只能靠真机反复练来验证，而真机每验一次要半小时。

**Tech Stack:** Swift 6.3.3、SPM、SwiftUI、XCTest。无第三方依赖。

---

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**
- `ChatGPTBridge` 可依赖 Core、AppKit、ApplicationServices
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、SwiftUI
- 所有面向用户的文案（错误、警告、空状态、按钮说明）必须是**中文**，且同时说明「**发生了什么**」和「**下一步做什么**」
- **禁止静默失败，禁止无限等待**
- 界面必须遵循 `docs/superpowers/DESIGN-SYSTEM.md`：**视图里不得出现字面颜色、字号、圆角**，全部走令牌
- 目标 ChatGPT 应用固定 `com.openai.codex`
- 无第三方依赖
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准，不接受推断

### 本阶段独有的一条硬约束

> **逐字稿是增强，不是必需。采样失败绝不允许中断练习。**

这是「禁止静默失败」的**唯一例外场景**，处理方式不是「抛错终止」，而是：

1. 记下这一次失败（次数 + 最后一次的原因）
2. **练习照常继续**
3. 练完之后**如实告诉用户**逐字稿可能不完整、缺在哪、下一步做什么

理由：用户对着 ChatGPT 说了二十分钟英语，因为读界面失败就把他打断，代价完全不成比例。ROADMAP 3.2 原话是「采样失败不得中断练习——逐字稿是增强，不是必需」。

**注意这不等于可以静默。** 失败必须被记账并在练完后显示出来。悄悄丢掉几分钟对话、逐字稿看起来一切正常，才是本项目最忌讳的失败形态。

---

## 已经拍板的七个决策（不要再纠结，照此执行）

用户在夜间无人值守期间由跨阶段复审代为定夺，原文见 `docs/superpowers/DECISIONS-2026-08-06.md`。**每一条的决策与理由都写在下面，便于早上复核。**

### 决策 1 —— 会话编号统一成 `YYYY-MM-DD-NNN`

**决定：** 新产生的会话编号一律形如 `2026-08-05-003`。但 `SessionID.validated` **必须同时接受旧的 ISO8601 形状**（`2026-08-05T14:03:11Z`）。

**理由：** 前者人能读、能排序，模型注释（`PracticeSession.id`）与 Phase 9 的 `SessionID.next` 都已是这个形状。而用户现有的 `state.json` 里**已经存在** ISO8601 形状的 id（`Sources/coach/PracticeCommand.swift` 第 115 行一直是这么生成的）——拒绝它等于让已有练习记录全部失效。

**落点：** Task 1。**必须有测试守住两头**：旧 id 读得进来（`validated` 放行）、新 id 是新形状（`next` 产出 `YYYY-MM-DD-NNN`）。

### 决策 2 —— 复盘取回失败后的补救必须做进界面

**决定：** 在**复盘报告页**加「重新导入待处理的复盘」入口：列出 `pending-reviews/` 里的条目（时间、题目、字节数），可**单条重试**、**查看原文**、**删除**。

**理由：** 成品标准第 2 条是「全程不需要打开终端」，而**出错恰恰是最需要它成立的时候**。现在唯一途径是终端里跑 `coach reimport`——一个顺利时不用终端、出错时把用户推回终端的工具，等于在他最慌的时候把他扔下。

**落点：** Task 10。

### 决策 3 —— `.history` 由 Phase 4 标进 `SidebarItem.isImplemented`

**理由：** 七份既有计划里没有一份认领这件事。训练记录页做出来了却不标，用户点进去看到的还是占位页。

**落点：** Task 8。

### 决策 4 —— 单条训练记录删除时，同时清理关联的录音文件

**决定：** 删一条训练记录时，**同时删掉它的录音文件和复盘报告文件**，并在确认对话框里逐条列明会删掉什么。

**理由：** 不删录音会留下永远不会被引用的孤儿音频文件，慢慢把磁盘吃满，而用户完全看不见。

**Phase 5 尚未交付时怎么办：** 这段清理逻辑写成「**有 `recordingPath` 就删，没有就跳过**」，不得硬依赖 Phase 5 的 `RecordingStore`。Phase 4 只需要 `FileManager` 和一个相对路径。

**落点：** Task 9。

### 决策 5 —— 「记录对话逐字稿」开关归 Phase 4，加进 `CoachSettings`，**默认开**

**理由：** 逐字稿只多采集 AX 树，没有隐私成本、不需要额外权限，且是复盘质量与训练记录的共同基础。录音默认关是因为要麦克风权限和磁盘占用，两者性质不同。ROADMAP 第 5 节原本就这么定的，只是没人认领。

> ### ⚠️ 点名提醒：Phase 7 与 Phase 8 都会「整体替换」`CoachSettings`
>
> - **Phase 7 Task 1** 会把 `CoachSettings` 整体替换掉，加上 `weeklyGoal`
> - **Phase 8 Task 2** 会再整体替换一次，加上 `defaultRoute` / `feedbackTiming` / `part2PrepMode`
>
> 那两份计划里已经写了警示，要求替换前先 `grep -n "public var" Sources/IELTSCoachCore/Model/CoachState.swift`
> 把已有字段一个不落地抄进去，并**点名提到了 Phase 4 的 `transcriptEnabled`**。
>
> **少抄一个字段编译照样过**（新参数都带默认值），只是那个设置会在下一次写盘时被默认值悄悄盖掉——
> 用户明明关掉了逐字稿，下次打开又是开着的，且没有任何提示。
> Task 2 里那条 `testOldStateFileWithoutTheKeyStillDefaultsToOn` 测试就是为这件事准备的：
> 谁把 `transcriptEnabled` 抄丢了，它会立刻变红。

**落点：** Task 2（模型）+ Task 8（界面上的开关）。

### 决策 6 —— 复训目标 label 为空时，一律回落成 `targetKey` 照常开练

**决定：** 统一采用 Phase 6 的做法（回落成 `targetKey` 继续练），**不**采用 Phase 8 的「拒绝并说明下一步」。

**理由：** 用户是来练英语的。因为一个内部字段是空的就不让他练，代价不成比例。

**落点：不在 Phase 4。** 写在这里是为了留痕。**Phase 8 的实现者请照此执行**：`Sources/IELTSCoachUI/...` 里凡是遇到 `target.label.isEmpty` 就拒绝开练的分支，改成 `let label = target.label.isEmpty ? target.targetKey : target.label` 继续。

### 决策 7 —— 深色模式、设置合并、「功能升级」「问题反馈」两页，全部推到 Phase 10

**理由：** 这三样都是跨所有页面的收尾工作，在所有页面存在之前做等于返工。

**落点：不在 Phase 4。** 但本阶段有一个直接后果需要 Phase 10 知道：
**「记录对话逐字稿」开关本阶段放在「训练记录」页顶部**，而不是新建一个设置窗口——因为 Phase 5 才会建 ⌘, 的设置场景，Phase 4 抢先建一个只会让 Phase 5 重做一遍。Phase 10 做「设置合并」时把它一并收进去。

---

## 前置依赖：Phase 3 必须已经提供的东西

**动手前逐条用命令确认。任何一条不成立，停下来报告，不要自己发明一个替代品，也不要顺手替 Phase 3 把活干了。**

| # | 依赖 | 来自 | 怎么确认 | 不满足怎么办 |
|---|---|---|---|---|
| P3-1 | 设计令牌 `Palette` / `Spacing` / `Radius` 与组件 `CoachCard` / `PrimaryActionCard` / `SectionHeader(number:label:title:)` / `EmptyStateView(message:hint:actionTitle:action:)` | Phase 3 Task 7 | `ls Sources/IELTSCoachUI/DesignSystem/` | 停下来报告：本阶段两个新页面无从取值 |
| P3-2 | `enum SidebarItem`（十项，含 `title`、`systemImage`、`isImplemented`）与 `@Observable final class AppState`（含 `state: CoachState`、`reload()`、私有 `store: StateStore`） | Phase 3 Task 3 | `ls Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/AppState.swift` | 停下来报告 |
| P3-3 | `enum PracticeStage` 与 `@MainActor @Observable final class PracticeRunner`（含 `stage`、`start(setup:) async throws`、`finishPractice() async`、`cancel()`），且**只依赖 `CoachBridge` protocol** | Phase 3 Task 9 | `ls Sources/IELTSCoachUI/Session/PracticeRunner.swift` | 停下来报告：逐字稿采集没地方挂 |
| P3-4 | `Tests/IELTSCoachUITests/` 下已有可编程的 `FakeBridge` 与 `FakePasteboard` | Phase 3 Task 9 | `grep -rn "class FakeBridge" Tests/IELTSCoachUITests/` | 可以自己补一个，照 Phase 3 计划 Task 9 Step 1 里那份写 |
| P3-5 | 复盘报告页 `Sources/IELTSCoachUI/Review/ReviewReportView.swift` | Phase 3 Task 5 | `ls Sources/IELTSCoachUI/Review/` | 停下来报告：Task 10 的入口挂不上去 |
| P3-6 | `Tests/ChatGPTBridgeTests/FakeAXAccess.swift` | Phase 2 | `grep -n "class FakeAXAccess" Tests/ChatGPTBridgeTests/FakeAXAccess.swift` | 已确认存在（2026-08-06） |

### 已确认存在、可以直接用的 Core / Bridge 能力（2026-08-06 逐个打开源码核对过）

| 东西 | 确切签名 |
|---|---|
| `PracticeSession` | `init(id:questionId:focusPart:startedAt:endedAt:goal:transcript:reportPath:recordingPath:)` |
| `PracticeSession.TranscriptTurn` | `init(role: String, text: String, capturedAt: String)`，`role` 取 `"user"` / `"assistant"` |
| `CoachState` | `sessions: [PracticeSession]`、`currentSession: PracticeSession?`、`settings: CoachSettings`、`questions: [Question]`、`static func empty(displayName:createdAt:)` |
| `CoachSettings` | `init(recordingEnabled: Bool, recordingConsentAt: String)` |
| `StateStore` | `init(directory: DataDirectory)`、`load() throws -> CoachState`、`mutate<T>(_ body: (inout CoachState) throws -> T) throws -> T` |
| `DataDirectory` | `init(root: URL)`、`static func resolve(environment:) -> DataDirectory`、`root` / `stateFile` / `reportsDirectory` / `pendingReviewsDirectory` / `recordingsDirectory`、`createIfNeeded() throws` |
| `ReviewParser` | `static func parse(_ text: String, requireAnswerUpgrades: Bool = false) throws -> JSONValue` |
| `ReviewArchiver` | `static func archive(report:into:sessionID:questionID:at:) -> ArchiveOutcome`；`ArchiveOutcome` 含 `state`、`skipped: [String]` |
| `ReviewRequestPrompt` | `static func marker(requestID:) -> (open: String, close: String)`、`static func build(requestID:focusPart:) -> String` |
| `JSONValue` | `Codable`、`static func decode(from text: String) throws -> JSONValue`、下标、`arrayValue` / `objectValue` / `stringValue` / `isBlank` |
| `CoachError` | `invalidReviewText` / `reviewNotFound` / `reviewIncomplete` / `stateUnreadable` / `questionBankInvalid` / `planImpossible`，**目前还没有 `invalidSessionID`**（Task 1 加） |
| `AXAccess` | `snapshotTree() -> [AXNodeSnapshot]`（**深度优先前序遍历**，见 `LiveAXAccess.walk`） |
| `AXNodeSnapshot` | `init(element:role:subrole:title:value:descriptionText:identifier:childCount:childRoles:)`（除前两个外全有默认值）、`label`、`isIconOnlyControl`、`isEmptyComposer` |
| `ChatGPTLabels` | `copyAssistantMessage = ["Copy", "复制"]`、`controlRoles`、`matchControl`、`matchLastControl`；**目前还没有「用户自己那条消息的复制按钮」这个常量**（Task 4 加） |

---

## 关于本计划里 `View` 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略**（沿用 Phase 3 计划第 79–86 行的理由）。

布局是需要看着调的东西。把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务写明「必须显示什么、空状态说什么、失败时说什么、什么绝对不能出现在屏幕上」，具体怎么摆由实现者定，由 `DESIGN-SYSTEM.md` 的令牌与组件约束，再由 Task 12 的人工验收把关。

这与「禁止占位符」不冲突：占位符是「TBD、以后再说」，这里给的是明确到能判定通过与否的验收标准。若某处要求不清楚到无法动手，**停下来问，不要猜**。

---

## 本阶段的三个设计决定（连同理由，实现时不要推翻）

### 设计决定 1：采样与拼接彻底分家，中间只传一个纯数据结构

`ChatGPTBridge` 产出 `TranscriptSweep`（一次采样的结果），`IELTSCoachCore` 的 `TranscriptAssembler` 吃进去。**`TranscriptFragment` 这个数据结构定义在 Core**，Bridge 依赖 Core 所以能产出它，方向不反。

好处是两边各自都能测到底：

- 拼接规则错了 → `TranscriptAssemblerTests` 变红，不需要 ChatGPT
- AX 树结构变了 → `AXTranscriptSamplerTests` 变红，不需要 ChatGPT
- 真机上出问题时，**只要看逐字稿是「碎的」还是「乱的」就知道该改哪一半**

### 设计决定 2：`PracticeRunner` 不认识 AX，逐字稿采样器从外面注入

**不往 `CoachBridge` protocol 上加方法。** 理由有二：

1. 加了之后 Phase 3 写的 `FakeBridge`、Phase 5/6 写的测试全都要跟着改，牵一发动全身
2. 更要紧的是：**给 protocol 加一个带默认实现的方法，等于埋一个静默失败**——某个假实现忘了实现它，默认实现返回空，测试照样绿，而逐字稿永远是空的

改为新建一个独立的 `protocol TranscriptSampling`，由 `PracticeRunner(..., transcript: (any TranscriptSampling)? = nil)` 注入。这与 Phase 5 注入录音器（`recording: (any PracticeRecording)? = nil`）的做法完全一致，两个阶段的接线方式不会互相打架。

参数带默认值 `nil`，所以 **Phase 3 已有的调用点一处都不用改**。

### 设计决定 3：「练习开始那一刻屏幕上已经有的东西」全部当作背景板

考官提示词是一条**两千字符的用户消息**，它会以几十个 `AXStaticText` 碎片的形式一直挂在树上；侧边栏的历史会话名、按钮说明、设置面板的长段文字也一样。这些统统不属于本次对话。

**做法：** 练习进入 `.practicing` 那一刻先采一次样，把结果整个喂给 `TranscriptAssembler.seedBaseline(_:)`，这些槽位被标成 baseline，**`turns` 里永远不出现它们，但它们必须留在槽位序列里**——正是它们让后面的对齐游标能走到「真正的对话从这里开始」的位置。

**为什么不用「按内容过滤掉提示词里出现过的文字」：** 因为**今天要练的那道题的题干本身就写在考官提示词里**，考官问出口时说的就是那句话。按内容过滤会把它一起滤掉，而成品标准第 5 条要求「逐字稿里能找到考官问过的每一个问题」。这条陷阱很自然、很难自己想到，Task 3 有一条专门的测试守着它。

---

## File Structure

```
Sources/
├── IELTSCoachCore/
│   ├── CoachError.swift                        【改】加 invalidSessionID
│   ├── Model/
│   │   ├── SessionID.swift                     【新】会话编号生成 + 文件名安全校验
│   │   └── CoachState.swift                    【改】CoachSettings 加 transcriptEnabled
│   ├── Transcript/                             【新目录】只依赖 Foundation
│   │   ├── TranscriptSpeaker.swift             说话人（含 unknown）
│   │   ├── TranscriptFragment.swift            一次采样里的一个碎片
│   │   └── TranscriptAssembler.swift           ★ 拼接去重，本阶段的核心
│   └── Storage/
│       └── PendingReviewStore.swift            【新】落盘 + 列举 + 标记 + 删除
├── ChatGPTBridge/
│   ├── ChatGPTLabels.swift                     【改】加 copyUserMessage 与 speakerMarker
│   ├── TranscriptSampling.swift                【新】protocol + TranscriptSweep
│   └── AXTranscriptSampler.swift               【新】★ 从 AX 树采样，走 AXAccess 接缝
├── IELTSCoachUI/
│   ├── AppState.swift                          【改】加 setTranscriptEnabled
│   ├── Navigation.swift                        【改】.history 标为已实现
│   ├── RootView.swift                          【改】接上训练记录页
│   ├── Session/
│   │   ├── TranscriptCollector.swift           【新】采样节奏、失败记账、完整性说明
│   │   └── PracticeRunner.swift                【改】落会话记录 + 接逐字稿 + finishedSessionID
│   ├── History/
│   │   ├── HistoryViewModel.swift              【新】按月分组（纯逻辑，可测）
│   │   ├── SessionDeleter.swift                【新】单条删除 + 关联文件清理（可测）
│   │   └── HistoryView.swift                   【新】页面（人工验收）
│   └── Review/
│       ├── PendingReviewViewModel.swift        【新】待处理复盘的列表与重试（可测）
│       ├── PendingReviewInboxView.swift        【新】页面（人工验收）
│       └── ReviewReportView.swift              【改】加「重新导入待处理的复盘」入口
└── coach/
    └── PracticeCommand.swift                   【改】会话编号改用 SessionID.next 并落会话记录
Tests/
├── IELTSCoachCoreTests/
│   ├── SessionIDTests.swift                    【新】
│   ├── TranscriptSettingsTests.swift           【新】
│   ├── TranscriptAssemblerTests.swift          【新】★ 六种情况全在这里
│   └── PendingReviewStoreTests.swift           【新】
├── ChatGPTBridgeTests/
│   └── AXTranscriptSamplerTests.swift          【新】
└── IELTSCoachUITests/
    ├── NavigationTests.swift                   【改】.history 进已实现集合
    ├── TranscriptCollectorTests.swift          【新】
    ├── PracticeRunnerArchiveTests.swift        【新】
    ├── HistoryViewModelTests.swift             【新】
    ├── SessionDeleterTests.swift               【新】
    └── PendingReviewViewModelTests.swift       【新】
```

**共 13 个任务。**

| 任务 | 内容 | 性质 |
|---|---|---|
| 1–5 | 会话编号、逐字稿开关、拼接去重、AX 采样、采样节拍 | 纯逻辑，不碰界面，可以一口气做完 |
| 7 | 待处理复盘的落盘与清点 | 纯逻辑。**实际动手顺序上要排在 Task 6 之前**，因为 Task 6 用它 |
| 6 | 把逐字稿与会话记录接进 `PracticeRunner` | 接线，全阶段风险最高的一步 |
| 8–11 | 训练记录页、单条删除、重新导入待处理的复盘 | 界面 |
| 12 | 命令行跟上新的会话编号与会话落库 | 收尾 |
| 13 | 真机验收 | **只能人做，子代理不得代劳** |

**实际执行顺序：1 → 2 → 3 → 4 → 5 → 7 → 6 → 8 → 9 → 10 → 11 → 12 → 13。**

---

## Task 1: 会话编号 `SessionID`（决策 1）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Model/SessionID.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/CoachError.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/SessionIDTests.swift`

**Interfaces:**
- Consumes: `PracticeSession`（字段 `id`）、`CoachError`
- Produces:
  - `public enum SessionID`
    - `public static func next(existing: [PracticeSession], now: Date, timeZone: TimeZone = .current) -> String`
    - `public static func validated(_ raw: String) throws -> String`
  - `CoachError.invalidSessionID(String)`

**为什么会话编号要有安全校验：** 这个字符串会被直接拼进 `pending-reviews/<id>.txt` 与 `reports/<id>.json`。放行 `../../..` 等于让调用方往数据目录外面写文件。Phase 9 的 `save_session_review` 的 `sessionId` 由模型给出，拼错一个路径就会发生——不是假想威胁。

> ### ⚠️ 白名单里必须有 `:` 和 `+`（这是决策 1 的落点，别照 Phase 9 的原稿抄）
>
> Phase 9 计划里那份 `validated` 的白名单是
> `A-Za-z0-9-_.`，**没有冒号**，因此它会拒绝 `2026-08-05T14:03:11Z`。
> 而用户现有的 `state.json` 里就有这种形状的 id（`coach practice` 一直是这么生成的）。
>
> Phase 9 的计划已经写明了两条出路，并要求「不要沉默地保持现状」。
> **决策 1 选的是 (a)：把 `:` 与 `+` 加进白名单。** 它们不构成路径穿越，
> 只是文件名里不好看；而拒绝它们等于让用户已有的练习记录全部失效。
>
> 本任务就是那条出路的落地。Phase 9 Task 1 届时会发现这个文件已经存在——
> 见本计划末尾「写给后续阶段实现者的话」。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/SessionIDTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class SessionIDTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let noon = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!

    private func session(_ id: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: "",
                        endedAt: "", goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    // MARK: - next：新产生的编号一律是新形状

    func testFirstSessionOfTheDayIsNumberedOne() {
        XCTAssertEqual(SessionID.next(existing: [], now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testContinuesFromTheHighestNumberNotTheCount() {
        // 用「已有条数 + 1」会在有空缺时撞号：只剩 003 时会算出 002，
        // 而 002 可能只是被删掉的那条（训练记录允许单条删除，见 Task 9）。
        // 撞号意味着两次练习的复盘写到同一个 reports/<id>.json 上，后一次直接盖掉前一次。
        let existing = [session("2026-08-06-003")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-004")
    }

    func testCountsOnlyTheSameDay() {
        let existing = [session("2026-08-05-009"), session("2026-08-06-001")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-002")
    }

    func testIgnoresSessionIDsInOtherFormats() {
        // 旧数据里的 sessionID 是 ISO8601 时间戳（coach practice 当初就是这么生成的），
        // 不能因为解析不出编号就崩，也不能让它影响今天的编号。
        let existing = [session("2026-08-06T10:00:00Z"), session("随便什么")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testUsesTheGivenTimeZoneNotTheMachineOne() {
        // 东八区的凌晨 1 点，在 UTC 还是前一天的 17 点。编号里的日期必须跟着传入的时区走，
        // 否则用户在午夜前后练的两场会被编到看起来矛盾的日期上。
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let lateNight = ISO8601DateFormatter().date(from: "2026-08-06T17:00:00Z")!
        XCTAssertEqual(SessionID.next(existing: [], now: lateNight, timeZone: shanghai),
                       "2026-08-07-001")
        XCTAssertEqual(SessionID.next(existing: [], now: lateNight, timeZone: utc),
                       "2026-08-06-001")
    }

    // MARK: - validated：旧编号必须仍然读得进来（决策 1）

    func testValidatedAcceptsTheNewShape() throws {
        XCTAssertEqual(try SessionID.validated("2026-08-06-001"), "2026-08-06-001")
        XCTAssertEqual(try SessionID.validated("  sync-1785940167 "), "sync-1785940167")
    }

    /// **决策 1 的守卫。** 用户现有的 state.json 里就是这种 id。
    /// 拒绝它 = 已有练习记录全部失效。
    func testValidatedStillAcceptsTheOldISO8601IDs() throws {
        XCTAssertEqual(try SessionID.validated("2026-08-05T14:03:11Z"), "2026-08-05T14:03:11Z")
        XCTAssertEqual(try SessionID.validated("2026-08-05T14:03:11+08:00"),
                       "2026-08-05T14:03:11+08:00")
    }

    func testValidatedRejectsAnythingThatCouldEscapeTheDataDirectory() {
        // 这个字符串会直接拼进 pending-reviews/<id>.txt 和 reports/<id>.json。
        for bad in ["../evil", "a/b", "..", ".", "", "   ", "a\u{0000}b", "~/secret", "a\\b"] {
            XCTAssertThrowsError(try SessionID.validated(bad), "「\(bad)」不该被放行") { error in
                XCTAssertTrue("\(error.localizedDescription)".contains("下一步"),
                              "错误信息必须告诉用户下一步做什么")
            }
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SessionIDTests`
Expected: 编译失败 —— `SessionID` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Model/SessionID.swift`：

```swift
import Foundation

public enum SessionID {
    /// 会话编号 `YYYY-MM-DD-NNN`，与 `PracticeSession.id` 的文档格式一致。
    ///
    /// 取当天已有编号的**最大值 +1**，不是「条数 +1」：训练记录允许单条删除，
    /// 有空缺时后者会撞号，而撞号意味着两次练习的复盘写到同一个
    /// `reports/<id>.json` 上，后一次直接盖掉前一次。
    public static func next(existing: [PracticeSession], now: Date,
                            timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        // 不跟随用户的日历与地区，否则可能出佛历年份或本地化数字
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)

        let highest = existing.reduce(0) { current, session in
            guard session.id.hasPrefix("\(today)-") else { return current }
            let suffix = session.id.dropFirst(today.count + 1)
            // 旧格式（ISO8601 时间戳）解析不出数字，忽略掉即可，不能因此崩溃
            guard let number = Int(suffix) else { return current }
            return max(current, number)
        }
        return String(format: "%@-%03d", today, highest + 1)
    }

    /// 会话编号会直接拼进 `pending-reviews/<id>.txt` 与 `reports/<id>.json`。
    /// 放行 `/`、`..`、控制字符，等于让调用方往数据目录外面写文件。
    ///
    /// **白名单里有 `:` 和 `+` 是刻意的**（决策 1）：用户现有的 `state.json` 里
    /// 已经存在 `2026-08-05T14:03:11Z` 这种形状的会话 id（`coach practice` 一直
    /// 这么生成）。拒绝它等于让已有练习记录全部失效。这两个字符不构成路径穿越，
    /// 只是文件名里不好看。**新产生的编号一律走 `next(existing:now:timeZone:)`，
    /// 是 `YYYY-MM-DD-NNN` 形状。**
    public static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.:+")
        guard !trimmed.isEmpty,
              trimmed != ".", trimmed != "..",
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CoachError.invalidSessionID(
                "会话编号「\(raw)」不合法：只能用字母、数字、连字符、下划线、点、冒号和加号，"
                + "且不能是 . 或 .. 。"
                + "下一步：省略会话编号让工具自动生成，或改用「训练记录」页里列出的那些编号。")
        }
        return trimmed
    }
}
```

`Sources/IELTSCoachCore/CoachError.swift`：往 `case` 列表和 `errorDescription` 的模式匹配里各加一项。

```swift
public enum CoachError: Error, Equatable, LocalizedError {
    case invalidReviewText(String)
    case reviewNotFound(String)
    case reviewIncomplete(String)
    case stateUnreadable(String)
    case questionBankInvalid(String)
    case planImpossible(String)
    case invalidSessionID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReviewText(let m), .reviewNotFound(let m), .reviewIncomplete(let m),
             .stateUnreadable(let m), .questionBankInvalid(let m), .planImpossible(let m),
             .invalidSessionID(let m):
            return m
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SessionIDTests`
Expected: PASS（8 个测试）

Run: `swift test`
Expected: 全绿（既有测试一条都不能红——本任务只做新增）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `next` 里的 `max(current, number)` → `current + 1` | `testContinuesFromTheHighestNumberNotTheCount` |
| `next` 里的 `formatter.timeZone = timeZone` → `formatter.timeZone = TimeZone(identifier: "UTC")` | `testUsesTheGivenTimeZoneNotTheMachineOne` |
| `validated` 白名单字符串末尾的 `:+` 删掉 | `testValidatedStillAcceptsTheOldISO8601IDs` |
| `validated` 里 `trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })` 整个条件删掉 | `testValidatedRejectsAnythingThatCouldEscapeTheDataDirectory` |

四条逐个改、逐个跑、逐个改回。**改回后必须再跑一次 `swift test` 确认全绿**——突变验证最常见的事故是忘了改回来。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/SessionID.swift \
        Sources/IELTSCoachCore/CoachError.swift \
        Tests/IELTSCoachCoreTests/SessionIDTests.swift
git commit -m "feat(core): 会话编号统一成 YYYY-MM-DD-NNN，并兼容旧的 ISO8601 编号"
```

---

## Task 2: 「记录对话逐字稿」开关（决策 5）

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Model/CoachState.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/TranscriptSettingsTests.swift`

**Interfaces:**
- Consumes: `CoachSettings`、`CoachState`、`StateStore`、`DataDirectory`
- Produces:
  - `CoachSettings.transcriptEnabled: Bool`
  - `CoachSettings.defaultTranscriptEnabled: Bool`（= `true`）
  - `CoachSettings.init(recordingEnabled:recordingConsentAt:transcriptEnabled:)`（第三参有默认值，**既有调用点一处都不用改**）

**这个字段最容易出的事故不是写错，是被后面的阶段抄丢。** 见本计划前面「决策 5」下那段针对 Phase 7 / Phase 8 的点名提醒。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/TranscriptSettingsTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class TranscriptSettingsTests: XCTestCase {
    func testDefaultIsOn() {
        // ROADMAP 第 5 节：逐字稿默认开、录音默认关。
        // 前者只多采集 AX 树（无隐私与权限成本，且是复盘质量的基础），
        // 后者涉及麦克风权限与磁盘占用，须用户明确同意。
        XCTAssertTrue(CoachSettings.defaultTranscriptEnabled)
        XCTAssertTrue(CoachState.empty().settings.transcriptEnabled)
        XCTAssertFalse(CoachState.empty().settings.recordingEnabled, "录音默认必须仍然是关的")
    }

    func testTheThirdParameterIsOptionalSoExistingCallSitesKeepCompiling() {
        let settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "")
        XCTAssertTrue(settings.transcriptEnabled)
    }

    /// **这条守的是「升级一次版本，用户的设置被默认值悄悄盖掉」。**
    /// 老的 state.json 里没有 transcriptEnabled 这个键，合成的解码器遇到缺键会直接抛错，
    /// 等于「升级一次，全部训练数据读不出来」。必须容错，且缺键时回落到**开**。
    func testOldStateFileWithoutTheKeyStillDefaultsToOn() throws {
        let old = #"{"schemaVersion":3,"settings":{"recordingEnabled":true,"recordingConsentAt":"t"}}"#
        let state = try JSONDecoder().decode(CoachState.self, from: Data(old.utf8))
        XCTAssertTrue(state.settings.transcriptEnabled, "缺这个键时必须默认开，不是默认关")
        XCTAssertTrue(state.settings.recordingEnabled, "同一份设置里别的字段不能被带歪")
    }

    func testTheStoredValueSurvivesARoundTrip() throws {
        var state = CoachState.empty()
        state.settings.transcriptEnabled = false
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(CoachState.self, from: data)
        XCTAssertFalse(restored.settings.transcriptEnabled,
                       "用户关掉之后必须真的关着，下次打开不能又变回开")
    }

    func testItReallyReachesTheDiskThroughStateStore() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        let directory = DataDirectory(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: directory)

        try store.mutate { $0.settings.transcriptEnabled = false }
        XCTAssertFalse(try store.load().settings.transcriptEnabled)

        let onDisk = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("transcriptEnabled"),
                      "字段必须真的写进 state.json，否则换台机器拷目录就丢了")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TranscriptSettingsTests`
Expected: 编译失败 —— `CoachSettings` 没有 `transcriptEnabled`

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Model/CoachState.swift`：把既有的 `CoachSettings`（第 13–21 行）**整体替换**为下面这段。**文件里其余部分一个字都不要动**——`CoachState` 的 `init(from:)` 已经用 `decodeIfPresent(CoachSettings.self, ...) ?? CoachSettings(recordingEnabled: false, recordingConsentAt: "")` 兜底了缺 `settings` 整块的情况，那行不需要改（第三参有默认值）。

```swift
public struct CoachSettings: Codable, Equatable, Sendable {
    public var recordingEnabled: Bool
    public var recordingConsentAt: String
    /// 「记录对话逐字稿」。ROADMAP 第 5 节：开 / 关，**默认开**。
    ///
    /// 与录音开关的区别，别把两者混为一谈：
    /// 逐字稿只多采集 AX 树，没有隐私成本、不需要任何系统权限，且是复盘质量与
    /// 训练记录的共同基础；录音要麦克风权限、要磁盘，所以默认关、且需要明确同意。
    public var transcriptEnabled: Bool

    public static let defaultTranscriptEnabled = true

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    // transcriptEnabled 给默认值，既有调用点（CoachState.empty、各处测试）不用改。
    public init(recordingEnabled: Bool, recordingConsentAt: String,
                transcriptEnabled: Bool = CoachSettings.defaultTranscriptEnabled) {
        self.recordingEnabled = recordingEnabled
        self.recordingConsentAt = recordingConsentAt
        self.transcriptEnabled = transcriptEnabled
    }

    enum CodingKeys: String, CodingKey {
        case recordingEnabled, recordingConsentAt, transcriptEnabled
    }

    /// 手写解码：transcriptEnabled 是 Phase 4 才加的字段，老的 state.json 里没有它。
    /// 合成的解码器遇到缺键会直接抛错，等于「升级一次版本，全部训练数据读不出来」。
    /// 与 `CoachState.init(from:)` 的容错策略一致。
    ///
    /// 编码仍由 Swift 合成——只手写 Decodable 那一半时，Encodable 的合成不受影响。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? false
        recordingConsentAt = try container.decodeIfPresent(String.self, forKey: .recordingConsentAt) ?? ""
        transcriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .transcriptEnabled)
            ?? CoachSettings.defaultTranscriptEnabled
    }
}
```

**与上游 Windows 版的兼容性：** 这是一次纯追加的字段变更，`schemaVersion` 仍是 3。上游读到不认识的 `transcriptEnabled` 键会忽略它；本工具读到没有该键的旧文件会补默认值。两个方向都不丢数据，因此不需要升 `schemaVersion`（spec 4.6）。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TranscriptSettingsTests`
Expected: PASS（5 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `?? CoachSettings.defaultTranscriptEnabled` → `?? false` | `testOldStateFileWithoutTheKeyStillDefaultsToOn` |
| `public static let defaultTranscriptEnabled = true` → `= false` | `testDefaultIsOn` |
| 把 `CodingKeys` 里的 `transcriptEnabled` 删掉 | `testTheStoredValueSurvivesARoundTrip` 与 `testItReallyReachesTheDiskThroughStateStore` |

第三条正是「后面的阶段整体替换 `CoachSettings` 时把这个字段抄丢」会造成的效果。**记住它长什么样。**

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/CoachState.swift \
        Tests/IELTSCoachCoreTests/TranscriptSettingsTests.swift
git commit -m "feat(core): 加「记录对话逐字稿」开关，默认开"
```

---

## Task 3: ★ 拼接去重 `TranscriptAssembler`（本阶段最难、最该下功夫的一步）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Transcript/TranscriptSpeaker.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Transcript/TranscriptFragment.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Transcript/TranscriptAssembler.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/TranscriptAssemblerTests.swift`

**Interfaces:**
- Consumes: `PracticeSession.TranscriptTurn`（`init(role:text:capturedAt:)`）
- Produces:
  - `public enum TranscriptSpeaker: String, Codable, Equatable, Sendable, CaseIterable`，三个 case：`learner = "user"`、`examiner = "assistant"`、`unknown = "unknown"`
  - `public struct TranscriptFragment: Equatable, Sendable`，含 `speaker: TranscriptSpeaker`、`text: String`、`init(speaker:text:)`
  - `public struct TranscriptAssembler: Sendable`，含
    - `init()`
    - `mutating func seedBaseline(_ fragments: [TranscriptFragment])`
    - `mutating func ingest(_ fragments: [TranscriptFragment], at timestamp: Date)`
    - `mutating func noteSamplingFailure(_ message: String)`
    - `var turns: [PracticeSession.TranscriptTurn]`
    - `var samplingFailureCount: Int`
    - `var lastSamplingFailure: String?`
    - `var unknownSpeakerCount: Int`
    - `var completenessNote: String?`

### 这一步到底在解决什么问题

spec 2.3.9 的实测记录：**ChatGPT 的文本在 AX 树里是碎片化的**，连复盘的定界标记都被拆成三段：

```
AXStaticText value="}"
AXStaticText value="<<<END_IELTS_REVIEW_JSON"
AXStaticText value=":sync-1785940167"
AXStaticText value=">>>"
```

逐字稿每 2~3 秒采样一次，而流式输出让同一条消息不断变长。一场二十分钟的练习下来，**同一条考官提问会被读到十几个长度不同的版本**。直接把每次采样的结果追加进去，得到的是一堆越来越长的重复片段，完全没法看。

### 拼接规则（五条，实现时不要自己发明第六条）

| # | 规则 | 它挡的是什么 |
|---|---|---|
| **R1** | **同一次采样里的两个片段，绝不允许并进同一个槽位。** 对齐游标只前进不回头 | 两条不同消息恰好前缀相同时被合并成一条（一次采样看到的是**某一瞬间**的界面，两个节点就是两条消息） |
| **R2** | 跨采样时，同一个槽位**只保留最长的那个版本** | 流式增长、迟到的旧采样、完全重复的片段——三种情况一条规则全包 |
| **R3** | 说话人不同的片段**永不合并**；`unknown` 可以被升级成已知说话人，反过来不行 | 考官的问题和自己的回答混成一条 |
| **R4** | 匹配不上就新开一个槽位，**插在游标当前位置**，顺序不乱 | 新消息跑到列表最前面 |
| **R4 补丁**（2026-08-06 实现后修正） | 光「插在游标当前位置」挡不住这一栏自己写的事故：这一次一条已有消息都没对上时游标停在 0，`insert(at: 0)` 正好把新消息插到最前面，而对话区一滚动、只读到最新一条正是常态。改为：游标没动过时，先看这一次采样后面还有没有片段对得上已有槽位——有就插在它正前面（界面往回滚了，读到的是更早的内容），一个都没有就追加到末尾（逐字稿是追加式的） | 同上，这次是真的挡住了 |
| **R5** | 采样失败只记账、不抛错 | 把用户的练习打断 |

**R1 是最不直觉、也最重要的一条。** 请把 `matchIndex(..., from: cursor)` 里那个 `cursor` 当成整段逻辑的核心，它同时解决了「消息边界」和「考官问出题干时不被当成提示词的一部分」两个问题。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/TranscriptAssemblerTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class TranscriptAssemblerTests: XCTestCase {
    private let t1 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
    private let t2 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:03Z")!
    private let t3 = ISO8601DateFormatter().date(from: "2026-08-06T10:00:06Z")!

    private func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }
    private func unknown(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .unknown, text: text)
    }

    // MARK: - 情况一：片段递增（流式输出）

    /// 同一条消息越来越长，最后只能留一条，且是最长的那个版本。
    func testAGrowingMessageKeepsOnlyItsLongestVersion() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live")], at: t1)
        assembler.ingest([examiner("Do you live in a house")], at: t2)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)

        XCTAssertEqual(assembler.turns.count, 1, "同一条消息的十几个版本必须收敛成一条")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
        XCTAssertEqual(assembler.turns[0].role, "assistant")
    }

    /// capturedAt 记的是这条消息**第一次出现**的时刻，不是最后一次采到它的时刻。
    /// 记成最后一次的话，一条说了三十秒的长回答会显示成它说完的那一刻。
    func testCapturedAtIsWhenTheMessageFirstAppeared() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live")], at: t1)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)

        let expected = ISO8601DateFormatter().string(from: t1)
        XCTAssertEqual(assembler.turns[0].capturedAt, expected)
    }

    // MARK: - 情况二：片段乱序到达

    /// 采样是在后台按节拍跑的，一次慢一点的采样完全可能在更晚的那次之后才并进来。
    /// 迟到的旧版本**不许把已经拼好的内容缩回去**。
    func testALateArrivingEarlierSampleDoesNotShrinkWhatWeAlreadyHave() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)
        assembler.ingest([examiner("Do you live")], at: t1)   // 迟到的早期采样

        XCTAssertEqual(assembler.turns.count, 1, "迟到的旧片段不能变成第二条")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// 迟到的旧采样带着更早的时间戳，capturedAt 要跟着往前修正。
    func testALateArrivingEarlierSampleCorrectsTheTimestampBackwards() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t3)
        assembler.ingest([examiner("Do you live")], at: t1)

        XCTAssertEqual(assembler.turns[0].capturedAt, ISO8601DateFormatter().string(from: t1))
    }

    // MARK: - 情况三：完全重复的片段

    /// 界面十秒没动，采样了五次，读到的是一模一样的东西。不能堆出五条。
    func testIdenticalFragmentsNeverPileUp() {
        var assembler = TranscriptAssembler()
        for _ in 0..<5 {
            assembler.ingest([examiner("Do you live in a house or a flat?"),
                              learner("I live in a flat with my parents.")], at: t1)
        }
        XCTAssertEqual(assembler.turns.count, 2)
        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Do you live in a house or a flat?",
                        "I live in a flat with my parents."])
    }

    /// 空白与换行的差异不算差异——AX 读回来的文本会带各种换行与缩进。
    func testWhitespaceOnlyDifferencesAreNotTreatedAsNewMessages() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house?")], at: t1)
        assembler.ingest([examiner("  Do you   live in a\n house?  ")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1)
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house?")
    }

    // MARK: - 情况四：消息边界（两条不同消息恰好前缀相同）

    /// **本任务最关键的一条。** 考官先问「Do you live in a house?」，
    /// 追问时又问「Do you live in a house or a flat?」——后者以前者为前缀。
    /// 它们在**同一次采样**里同时出现，就是两条不同的消息，绝不能合并成一条。
    /// 合并的后果是逐字稿里少了一个考官问过的问题，直接违反成品标准第 5 条。
    func testTwoMessagesThatSharePrefixStayTwoMessages() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house?"),
                          examiner("Do you live in a house or a flat?")], at: t1)

        XCTAssertEqual(assembler.turns.count, 2, "同一次采样里的两个片段永远是两条消息")
        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Do you live in a house?", "Do you live in a house or a flat?"])
    }

    /// 边界稳定：再采几次，仍然是两条，不会因为反复并入而互相吞掉。
    func testThePrefixBoundaryHoldsAcrossRepeatedSamples() {
        var assembler = TranscriptAssembler()
        for timestamp in [t1, t2, t3] {
            assembler.ingest([examiner("Do you live in a house?"),
                              examiner("Do you live in a house or a flat?")], at: timestamp)
        }
        XCTAssertEqual(assembler.turns.count, 2)
    }

    // MARK: - 情况五：说话人切换

    func testExaminerAndLearnerNeverMergeIntoOneTurn() {
        var assembler = TranscriptAssembler()
        // 学员复述了考官的问题开头——文本兼容，但说话人不同，绝不能并成一条
        assembler.ingest([examiner("Do you live in a house or a flat?"),
                          learner("Do you live")], at: t1)

        XCTAssertEqual(assembler.turns.count, 2)
        XCTAssertEqual(assembler.turns.map(\.role), ["assistant", "user"])
    }

    /// 正在流式输出的那条消息，界面上还没出现复制按钮，采样时判不出是谁说的。
    /// 等它说完、按钮出现了，同一条消息就要**升级**成已知说话人，
    /// 而不是变成第二条 role 不同的记录。
    func testAnUnattributedFragmentIsUpgradedWhenTheSpeakerBecomesKnown() {
        var assembler = TranscriptAssembler()
        assembler.ingest([unknown("Do you live in a")], at: t1)
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1, "判出说话人不能让同一条消息变成两条")
        XCTAssertEqual(assembler.turns[0].role, "assistant")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// 反过来不行：已经判定是考官说的，后面一次采样判不出来，不能把它降级回 unknown。
    func testAKnownSpeakerIsNeverDowngradedBackToUnknown() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.ingest([unknown("Do you live in a house or a flat?")], at: t2)

        XCTAssertEqual(assembler.turns.count, 1)
        XCTAssertEqual(assembler.turns[0].role, "assistant")
    }

    // MARK: - 情况六：采样中途失败（不得中断练习）

    /// 采样失败只记账，已经拼好的内容一个字都不许丢，
    /// 而且**必须在练完之后如实告诉用户**——静默地少几分钟对话是本项目最忌讳的失败形态。
    func testSamplingFailuresAreRecordedWithoutLosingAnything() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.noteSamplingFailure("没能读到 ChatGPT 的界面内容")
        assembler.noteSamplingFailure("ChatGPT 窗口被切走了")
        assembler.ingest([learner("I live in a flat.")], at: t3)

        XCTAssertEqual(assembler.turns.count, 2, "失败前后采到的内容都要在")
        XCTAssertEqual(assembler.samplingFailureCount, 2)
        XCTAssertEqual(assembler.lastSamplingFailure, "ChatGPT 窗口被切走了")
    }

    func testTheCompletenessNoteSaysWhatHappenedAndWhatToDoNext() throws {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?")], at: t1)
        assembler.noteSamplingFailure("没能读到 ChatGPT 的界面内容")

        let note = try XCTUnwrap(assembler.completenessNote, "有失败就必须有说明")
        XCTAssertTrue(note.contains("1 次"), "要说清失败了几次")
        XCTAssertTrue(note.contains("没能读到 ChatGPT 的界面内容"), "要带上最后一次的原因")
        XCTAssertTrue(note.contains("下一步"), "必须告诉用户下一步做什么")
        XCTAssertTrue(note.contains("练习本身"), "必须说明练习和复盘没受影响，别让用户白担心")
    }

    func testNoNoiseWhenEverythingWentFine() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Do you live in a house or a flat?"),
                          learner("I live in a flat.")], at: t1)
        XCTAssertNil(assembler.completenessNote, "一切正常时不要弹一句没用的提示")
    }

    func testUnattributedTurnsAreAlsoReportedAsIncomplete() throws {
        var assembler = TranscriptAssembler()
        assembler.ingest([unknown("Do you live in a house or a flat?")], at: t1)

        let note = try XCTUnwrap(assembler.completenessNote)
        XCTAssertTrue(note.contains("没能判断"), "判不出谁说的也要如实说，不能装作正常")
        XCTAssertEqual(assembler.unknownSpeakerCount, 1)
        XCTAssertEqual(assembler.turns[0].role, "unknown")
    }

    // MARK: - 背景板：练习开始那一刻屏幕上已经有的东西

    /// 考官提示词是一条两千字符的用户消息，会以几十个碎片一直挂在树上；
    /// 侧边栏会话名、按钮说明也一样。它们不属于本次对话。
    func testWhatWasAlreadyOnScreenIsNotPartOfTheTranscript() {
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([learner("You will act as an IELTS Speaking examiner."),
                                unknown("New chat"),
                                learner("Today's question (Part 1, topic: Home):")])
        assembler.ingest([learner("You will act as an IELTS Speaking examiner."),
                          unknown("New chat"),
                          learner("Today's question (Part 1, topic: Home):"),
                          examiner("Do you live in a house or a flat?")], at: t1)

        XCTAssertEqual(assembler.turns.count, 1, "背景板不算对话")
        XCTAssertEqual(assembler.turns[0].text, "Do you live in a house or a flat?")
    }

    /// **成品标准第 5 条的守卫，也是本任务最容易想不到的一条。**
    ///
    /// 今天要练的题干**本身就写在考官提示词里**，考官问出口时说的就是那句话。
    /// 如果按「内容出现过就滤掉」来过滤背景板，这个问题会从逐字稿里凭空消失——
    /// 而它恰恰是整场练习的第一个问题。
    ///
    /// 靠的是 R1：游标已经走过背景板那几个槽位，后面同样的文字只能新开槽位。
    /// 这里刻意用 unknown 说话人，因为万一说话人判别整个失效，这条防线也必须还在。
    func testTheExaminerAskingTheQuestionThatWasAlsoInThePromptStillShowsUp() {
        let question = "Describe a place you like to visit."
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([unknown("Today's question (Part 2, topic: Places):"),
                                unknown(question)])
        assembler.ingest([unknown("Today's question (Part 2, topic: Places):"),
                          unknown(question),
                          unknown(question)], at: t1)

        XCTAssertEqual(assembler.turns.count, 1,
                       "考官把题干问出口时，必须作为一条新对话出现在逐字稿里")
        XCTAssertEqual(assembler.turns[0].text, question)
    }

    func testBaselineFragmentsThatKeepGrowingStayHidden() {
        var assembler = TranscriptAssembler()
        assembler.seedBaseline([learner("You will act as an IELTS")])
        assembler.ingest([learner("You will act as an IELTS Speaking examiner.")], at: t1)

        XCTAssertTrue(assembler.turns.isEmpty, "背景板长长了还是背景板")
    }

    // MARK: - 杂项

    func testBlankFragmentsAreDropped() {
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("   "), examiner("\n\n"), examiner("Hello?")], at: t1)
        XCTAssertEqual(assembler.turns.map(\.text), ["Hello?"])
    }

    func testANewMessageArrivingBetweenTwoKnownOnesKeepsTheOrder() {
        // 采样漏掉过中间那条（界面正好在重绘），下一次又读到了。
        // 它必须回到它本来的位置，不能被追加到最后。
        var assembler = TranscriptAssembler()
        assembler.ingest([examiner("Question one?"), learner("Answer one.")], at: t1)
        assembler.ingest([examiner("Question one?"),
                          learner("Answer one."),
                          examiner("Question two?")], at: t2)

        XCTAssertEqual(assembler.turns.map(\.text),
                       ["Question one?", "Answer one.", "Question two?"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TranscriptAssemblerTests`
Expected: 编译失败 —— `TranscriptAssembler`、`TranscriptFragment`、`TranscriptSpeaker` 均未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Transcript/TranscriptSpeaker.swift`：

```swift
import Foundation

/// 逐字稿里一条对话是谁说的。
///
/// raw value 直接写进 `PracticeSession.TranscriptTurn.role`，与上游 state.json 兼容：
/// `"user"` 是学员，`"assistant"` 是考官（ChatGPT）。
///
/// **`unknown` 是本项目新增的第三个取值。** 实测（spec 2.3.9）里，界面上区分
/// 「谁说的」靠的是消息下方那个复制按钮（`Copy message` 属于用户自己那条，
/// `Copy` 属于 ChatGPT 的回复），而正在流式输出的消息还没有按钮。判不出来时
/// 老老实实记成 `unknown`，**不许猜**——猜错会让复训时「回看自己说过的话」
/// 显示成考官说的话，而这种错误没有任何信号提示。
///
/// 下游消费方（Phase 6 的证据装配）只挑 `role == "user"`，`unknown` 会被自然跳过，
/// 属于可接受的降级；同时 `TranscriptAssembler.completenessNote` 会如实告诉用户
/// 有多少条没能判断。
public enum TranscriptSpeaker: String, Codable, Equatable, Sendable, CaseIterable {
    case learner = "user"
    case examiner = "assistant"
    case unknown = "unknown"
}
```

`Sources/IELTSCoachCore/Transcript/TranscriptFragment.swift`：

```swift
import Foundation

/// 一次 AX 采样里读到的一个文本碎片。
///
/// 由 `ChatGPTBridge` 的采样器产出，由 `TranscriptAssembler` 消费。
/// 定义在 Core 是为了让两边共享同一个数据结构而不产生反向依赖
/// （Bridge 依赖 Core，Core 不依赖任何人）。
public struct TranscriptFragment: Equatable, Sendable {
    public let speaker: TranscriptSpeaker
    public let text: String

    public init(speaker: TranscriptSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}
```

`Sources/IELTSCoachCore/Transcript/TranscriptAssembler.swift`：

```swift
import Foundation

/// 把一次次 AX 采样得到的碎片，拼接去重成一条条对话。
///
/// **为什么必须有这个东西**（spec 2.3.9 实测）：ChatGPT 的文本在 AX 树里是碎片化的，
/// 连复盘的定界标记都被拆成三段。逐字稿每 2~3 秒采样一次，而流式输出让同一条消息
/// 不断变长——一场练习下来，同一条考官提问会被读到十几个长度不同的版本。
///
/// **本类型只做字符串**：不碰 AX、不碰文件、不碰时钟（时间由调用方传进来）。
/// 采样在 `ChatGPTBridge`，拼接在这里，两边各自可测到底。
///
/// 五条规则，实现时不要自己发明第六条：
/// - R1 同一次采样里的两个片段绝不并进同一个槽位（游标只前进不回头）
/// - R2 跨采样时同一槽位只保留最长版本
/// - R3 说话人不同的片段永不合并；unknown 可升级，不可降级
/// - R4 匹配不上就新开槽位，插在游标当前位置
/// - R5 采样失败只记账、不抛错
public struct TranscriptAssembler: Sendable {
    private struct Slot {
        var speaker: TranscriptSpeaker
        var text: String
        var firstSeenAt: Date
        /// 练习开始那一刻就已经在屏幕上的内容（考官提示词那条消息、侧边栏会话名、
        /// 按钮说明……）。它们不属于本次对话，`turns` 里不出现，
        /// **但必须留在槽位序列里**——正是它们让对齐游标能走到
        /// 「真正的对话从这里开始」的位置。
        var isBaseline: Bool
    }

    private var slots: [Slot] = []
    private var failures: [String] = []

    public init() {}

    // MARK: - 采集

    /// 记下练习开始那一刻界面上已经有的文本。**只在第一次 `ingest` 之前调用一次。**
    ///
    /// 不用「按内容过滤掉考官提示词里出现过的文字」，因为**今天要练的题干本身
    /// 就写在提示词里**，考官问出口时说的就是那句话——按内容过滤会把整场练习的
    /// 第一个问题一起滤掉，直接违反成品标准第 5 条。
    public mutating func seedBaseline(_ fragments: [TranscriptFragment]) {
        for fragment in fragments {
            let text = Self.normalize(fragment.text)
            guard !text.isEmpty else { continue }
            slots.append(Slot(speaker: fragment.speaker, text: text,
                              firstSeenAt: .distantPast, isBaseline: true))
        }
    }

    /// 并入一次采样的结果。`timestamp` 是这次采样发生的时刻，由调用方给出——
    /// 内部不读时钟，否则这段逻辑就没法测了。
    public mutating func ingest(_ fragments: [TranscriptFragment], at timestamp: Date) {
        // R1：游标只前进不回头。一次采样看到的是**某一瞬间**的界面，
        // 两个节点就是两条消息，哪怕它们的文本一个是另一个的前缀。
        var cursor = 0
        for fragment in fragments {
            let text = Self.normalize(fragment.text)
            guard !text.isEmpty else { continue }

            if let hit = matchIndex(speaker: fragment.speaker, text: text, from: cursor) {
                merge(at: hit, speaker: fragment.speaker, text: text, timestamp: timestamp)
                cursor = hit + 1
            } else {
                // R4：插在游标当前位置，而不是一律追加到末尾。
                // 采样漏掉过中间那条、下一次又读到时，它要回到它本来的位置。
                let insertion = min(cursor, slots.count)
                slots.insert(Slot(speaker: fragment.speaker, text: text,
                                  firstSeenAt: timestamp, isBaseline: false), at: insertion)
                cursor = insertion + 1
            }
        }
    }

    /// R5：这一次没读到。**只记账，绝不抛错**——逐字稿是增强，不是必需，
    /// 采样失败不得中断练习（ROADMAP 3.2）。但也绝不静默：
    /// `completenessNote` 会在练完之后如实告诉用户。
    public mutating func noteSamplingFailure(_ message: String) {
        failures.append(message)
    }

    // MARK: - 结果

    public var turns: [PracticeSession.TranscriptTurn] {
        let formatter = ISO8601DateFormatter()
        return slots.filter { !$0.isBaseline }.map {
            PracticeSession.TranscriptTurn(role: $0.speaker.rawValue,
                                           text: $0.text,
                                           capturedAt: formatter.string(from: $0.firstSeenAt))
        }
    }

    public var samplingFailureCount: Int { failures.count }
    public var lastSamplingFailure: String? { failures.last }

    public var unknownSpeakerCount: Int {
        slots.filter { !$0.isBaseline && $0.speaker == .unknown }.count
    }

    /// 逐字稿完不完整。一切正常时是 nil；有问题时给一句中文，
    /// 同时说明「发生了什么」和「下一步做什么」。**非 nil 时界面必须显示它。**
    public var completenessNote: String? {
        var parts: [String] = []
        if let last = failures.last {
            parts.append("有 \(failures.count) 次没能读到 ChatGPT 的界面，"
                + "这几秒里说的话可能没记进来（最后一次的原因：\(last)）")
        }
        if unknownSpeakerCount > 0 {
            parts.append("有 \(unknownSpeakerCount) 段没能判断是考官说的还是你说的，"
                + "已按出现顺序原样保留")
        }
        guard !parts.isEmpty else { return nil }
        return "本次逐字稿可能不完整：" + parts.joined(separator: "；") + "。"
            + "练习本身和复盘都不受影响。"
            + "下一步：到「训练记录」里点开这一场，对照 ChatGPT 窗口看看缺了什么；"
            + "如果每次都这样，多半是这一版 ChatGPT 改了界面，请把这句提示告诉开发者。"
    }

    // MARK: - 私有

    /// 从 `cursor` 开始往后找第一个能合并的槽位。**不许从 0 开始找**（R1）。
    private func matchIndex(speaker: TranscriptSpeaker, text: String, from cursor: Int) -> Int? {
        guard cursor < slots.count else { return nil }
        for index in cursor..<slots.count
        where Self.canMerge(slots[index].speaker, slots[index].text, speaker, text) {
            return index
        }
        return nil
    }

    private mutating func merge(at index: Int, speaker: TranscriptSpeaker,
                                text: String, timestamp: Date) {
        // R2：只保留最长版本。两者必有一个是另一个的前缀（canMerge 保证），
        // 所以「更长」就等于「内容更全」。
        if text.count > slots[index].text.count { slots[index].text = text }
        // R3：unknown 可以被升级成已知说话人，反过来不行。
        if slots[index].speaker == .unknown && speaker != .unknown {
            slots[index].speaker = speaker
        }
        // 迟到的旧采样带着更早的时间戳，capturedAt 要跟着往前修正。
        if timestamp < slots[index].firstSeenAt { slots[index].firstSeenAt = timestamp }
    }

    static func canMerge(_ existingSpeaker: TranscriptSpeaker, _ existingText: String,
                         _ speaker: TranscriptSpeaker, _ text: String) -> Bool {
        let speakerOK = existingSpeaker == speaker
            || existingSpeaker == .unknown || speaker == .unknown
        guard speakerOK else { return false }
        return existingText.hasPrefix(text) || text.hasPrefix(existingText)
    }

    /// 去掉首尾空白，并把中间连续的空白（含换行）压成一个空格。
    /// AX 读回来的文本带各种换行与缩进，不归一化的话「同一句话」会被当成两句。
    static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TranscriptAssemblerTests`
Expected: PASS（19 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（本阶段最重要的一次，五条都要做）**

| # | 把这一行改成 | 哪条测试必须变红 | 它守的是什么 |
|---|---|---|---|
| 1 | `matchIndex(speaker:text:from:)` 里的 `for index in cursor..<slots.count` → `for index in 0..<slots.count` | `testTwoMessagesThatSharePrefixStayTwoMessages`、`testTheExaminerAskingTheQuestionThatWasAlsoInThePromptStillShowsUp` | R1，同时是成品标准第 5 条的防线 |
| 2 | `merge` 里的 `if text.count > slots[index].text.count` → 去掉条件，直接 `slots[index].text = text` | `testALateArrivingEarlierSampleDoesNotShrinkWhatWeAlreadyHave` | R2 |
| 3 | `merge` 里的 `if slots[index].speaker == .unknown && speaker != .unknown` → `if true`（无条件覆盖说话人） | `testAKnownSpeakerIsNeverDowngradedBackToUnknown` | R3 |
| 4 | `canMerge` 里的 `guard speakerOK else { return false }` 整行删掉 | `testExaminerAndLearnerNeverMergeIntoOneTurn` | R3 |
| 5 | `turns` 里的 `slots.filter { !$0.isBaseline }` → `slots` | `testWhatWasAlreadyOnScreenIsNotPartOfTheTranscript`、`testBaselineFragmentsThatKeepGrowingStayHidden` | 设计决定 3 |
| 6 | `merge` 里的 `if timestamp < slots[index].firstSeenAt` 整行删掉 | `testALateArrivingEarlierSampleCorrectsTheTimestampBackwards` | capturedAt 的准确性 |
| 7 | `noteSamplingFailure` 改成 `fatalError("采样失败")` 或抛错 | 编译失败或 `testSamplingFailuresAreRecordedWithoutLosingAnything` 崩 | R5：采样失败不得中断练习 |

**七条逐个改、逐个跑、逐个改回，最后再跑一次 `swift test` 确认全绿。**

如果第 1 条改完测试没变红，说明测试写错了或者实现根本没用游标——**停下来查清楚再往下走**，这一条是整个 Phase 4 的地基。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Transcript/ \
        Tests/IELTSCoachCoreTests/TranscriptAssemblerTests.swift
git commit -m "feat(core): 逐字稿碎片的拼接去重"
```

---

## Task 4: ★ AX 采样 `AXTranscriptSampler`

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/ChatGPTBridge/TranscriptSampling.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/ChatGPTBridge/AXTranscriptSampler.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/ChatGPTBridge/ChatGPTLabels.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/ChatGPTBridgeTests/AXTranscriptSamplerTests.swift`

**Interfaces:**
- Consumes: `AXAccess.snapshotTree() -> [AXNodeSnapshot]`、`AXNodeSnapshot`（`role`、`value`、`label`、`isIconOnlyControl`）、`ChatGPTLabels.controlRoles`、`TranscriptFragment`、`TranscriptSpeaker`
- Produces:
  - `public struct TranscriptSweep: Equatable, Sendable`，含 `fragments: [TranscriptFragment]`、`failure: String?`、`init(fragments:failure:)`、`static let unavailable: TranscriptSweep`
  - `public protocol TranscriptSampling: Sendable`，唯一要求 `func sample() -> TranscriptSweep`
  - `public struct AXTranscriptSampler: TranscriptSampling`，含 `init(access: any AXAccess, minimumLength: Int = 2)`
  - `ChatGPTLabels.copyUserMessage: [String]`（= `["Copy message", "复制消息"]`）
  - `ChatGPTLabels.speakerMarker(_ node: AXNodeSnapshot) -> TranscriptSpeaker?`

### 说话人怎么判（实测依据 spec 2.3.9）

界面上有两个长得一模一样的复制按钮，**只能靠标签精确区分**：

| 节点 | 归属 | 相邻元素 |
|---|---|---|
| `AXButton desc="Copy message"` | **用户自己**发的消息 | 挨着 `Edit message` |
| `AXButton desc="Copy"` | **ChatGPT 的回复** | 挨着 `Good response` |

`snapshotTree()` 是**深度优先前序遍历**（见 `LiveAXAccess.walk`），因此节点顺序 ≈ 文档顺序：一条消息的文本节点排在它自己那个复制按钮的**前面**。

**算法：** 顺序扫一遍，把遇到的 `AXStaticText` 攒进 `pending`；一旦撞上一个能判定说话人的复制按钮，就把 `pending` 里攒的全部归给这个说话人并清空。扫完之后 `pending` 里剩下的（多半是正在流式输出、按钮还没出现的那条）归 `.unknown`。

> **⚠️ 这一条判据没有在真机上验证过，是本阶段最大的未知。**
>
> 已知的事实只有 spec 2.3.9 记录的那两个按钮标签，那是**在普通聊天界面上**采到的。
> 语音会话进行中，实时字幕是不是也带这两个按钮，没人验证过。
>
> 所以本任务的设计前提是**判不出来也不能出事**：
> 判不出就记 `.unknown`，逐字稿内容照样完整、顺序照样对，
> `TranscriptAssembler.completenessNote` 会如实告诉用户「有 N 段没能判断是谁说的」。
> **绝不允许猜**——猜错会让复训时「回看自己说过的话」显示成考官的话，而且没有任何信号。
>
> Task 12 的真机验收有专门一步核对这件事，并要求把结果写进验收报告。
> 若真机上根本没有这两个按钮，**下一轮只需要改 `ChatGPTLabels.speakerMarker` 这一个函数**——
> 这正是把界面特征全部集中在 `ChatGPTLabels` 里的意义。

- [ ] **Step 1: 写失败的测试**

`Tests/ChatGPTBridgeTests/AXTranscriptSamplerTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import ChatGPTBridge

final class AXTranscriptSamplerTests: XCTestCase {
    private var nextID = 0

    private func text(_ value: String) -> AXNodeSnapshot {
        nextID += 1
        return AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                              role: "AXStaticText", value: value)
    }

    /// 一个「只有一个 AXImage 子节点」的图标按钮，符合 spec 2.3.1 的结构判据。
    private func iconButton(_ description: String, role: String = "AXButton") -> AXNodeSnapshot {
        nextID += 1
        return AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                              role: role, descriptionText: description,
                              childCount: 1, childRoles: ["AXImage"])
    }

    private func sampler(_ nodes: [AXNodeSnapshot]) -> (AXTranscriptSampler, FakeAXAccess) {
        let access = FakeAXAccess()
        access.nodes = nodes
        return (AXTranscriptSampler(access: access), access)
    }

    // MARK: - 说话人判别

    func testTextBeforeTheAssistantCopyButtonBelongsToTheExaminer() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house or a flat?"),
            iconButton("Copy")
        ])
        let sweep = sampler.sample()
        XCTAssertNil(sweep.failure)
        XCTAssertEqual(sweep.fragments,
                       [TranscriptFragment(speaker: .examiner,
                                           text: "Do you live in a house or a flat?")])
    }

    /// `Copy message` 是**用户自己**那条消息的复制按钮（spec 2.3.9），
    /// 两个按钮结构完全相同，只能靠标签区分。搞反了会让整份逐字稿的说话人全反。
    func testTextBeforeTheUserCopyButtonBelongsToTheLearner() {
        let (sampler, _) = self.sampler([
            text("I live in a flat with my parents."),
            iconButton("Copy message")
        ])
        XCTAssertEqual(sampler.sample().fragments,
                       [TranscriptFragment(speaker: .learner,
                                           text: "I live in a flat with my parents.")])
    }

    func testAWholeConversationIsAttributedTurnByTurn() {
        let (sampler, _) = self.sampler([
            text("You will act as an IELTS Speaking examiner."),
            iconButton("Copy message"),
            text("Do you live in a house or a flat?"),
            iconButton("Copy"),
            text("I live in a flat."),
            iconButton("Copy message")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker),
                       [.learner, .examiner, .learner])
    }

    /// 正在流式输出的那条消息还没有复制按钮。**不许猜，也不许丢。**
    func testTextWithNoSpeakerMarkerIsKeptAsUnknownInsteadOfDropped() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house or a flat?"),
            iconButton("Copy"),
            text("I live in a fl")            // 还在往外冒字，按钮还没出现
        ])
        let fragments = sampler.sample().fragments
        XCTAssertEqual(fragments.count, 2, "判不出说话人也不能把内容丢掉")
        XCTAssertEqual(fragments[1].speaker, .unknown)
        XCTAssertEqual(fragments[1].text, "I live in a fl")
    }

    /// 一条消息在 AX 树里被切成好几段（spec 2.3.9 实测）。
    /// 采样器不做拼接——那是 TranscriptAssembler 的活——但必须**按原顺序**全都带出来。
    func testFragmentsOfOneMessageComeOutInDocumentOrder() {
        let (sampler, _) = self.sampler([
            text("Do you live"), text("in a house"), text("or a flat?"),
            iconButton("Copy")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.text),
                       ["Do you live", "in a house", "or a flat?"])
        XCTAssertEqual(Set(sampler.sample().fragments.map(\.speaker)), [.examiner])
    }

    // MARK: - 过滤

    func testOnlyStaticTextIsCollected() {
        nextID += 1
        let composer = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                      role: "AXTextArea", value: "\nWork with ChatGPT",
                                      descriptionText: "Work with ChatGPT")
        let (sampler, _) = self.sampler([composer, text("Hello?"), iconButton("Copy")])
        XCTAssertEqual(sampler.sample().fragments.map(\.text), ["Hello?"])
    }

    func testBlankAndOneCharacterNoiseIsDropped() {
        let (sampler, _) = self.sampler([
            text("   "), text("\n"), text("·"), text("Hello?"), iconButton("Copy")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.text), ["Hello?"])
    }

    /// 侧边栏里的会话行也带按钮，但它们**不是**图标按钮（嵌套 AXButton，含 Pin chat /
    /// Archive chat），不满足 spec 2.3.1 的结构判据，不能被当成说话人标记。
    func testASidebarRowNamedCopyIsNotMistakenForACopyButton() {
        nextID += 1
        let sidebarRow = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                        role: "AXButton", descriptionText: "Copy",
                                        childCount: 2, childRoles: ["AXStaticText", "AXButton"])
        let (sampler, _) = self.sampler([text("Do you live in a house?"), sidebarRow])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker), [.unknown],
                       "结构不符的同名元素不能用来判定说话人")
    }

    // MARK: - 失败（绝不抛错）

    /// 读不到界面时返回 failure，**不抛错**——逐字稿是增强，不是必需，
    /// 采样失败不得中断练习（ROADMAP 3.2）。
    func testAnEmptyTreeIsReportedAsAFailureNotAsAnEmptyConversation() throws {
        let (sampler, _) = self.sampler([])
        let sweep = sampler.sample()
        XCTAssertTrue(sweep.fragments.isEmpty)
        let failure = try XCTUnwrap(sweep.failure, "读不到就必须说读不到，不能装作这一秒没人说话")
        XCTAssertFalse(failure.isEmpty)
    }

    func testATreeWithChromeButNoConversationIsNotAFailure() {
        // 练习刚开始、还没人说话：树是有内容的，只是没有对话。这不是失败。
        nextID += 1
        let chrome = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                    role: "AXButton", descriptionText: "New chat",
                                    childCount: 1, childRoles: ["AXImage"])
        let (sampler, _) = self.sampler([chrome])
        let sweep = sampler.sample()
        XCTAssertNil(sweep.failure)
        XCTAssertTrue(sweep.fragments.isEmpty)
    }

    func testSamplingTwiceReallyRereadsTheTree() {
        let (sampler, access) = self.sampler([text("Hello?"), iconButton("Copy")])
        _ = sampler.sample()
        _ = sampler.sample()
        XCTAssertEqual(access.snapshotCount, 2, "每次采样都必须重新读树，不能缓存")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AXTranscriptSamplerTests`
Expected: 编译失败 —— `AXTranscriptSampler`、`TranscriptSweep` 未定义

- [ ] **Step 3: 实现**

`Sources/ChatGPTBridge/TranscriptSampling.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 一次采样的结果。
public struct TranscriptSweep: Equatable, Sendable {
    public let fragments: [TranscriptFragment]
    /// 这一次没读到时的中文原因。**非 nil 不代表练习出错**——
    /// 逐字稿是增强，不是必需，调用方只需记账并继续。
    public let failure: String?

    public init(fragments: [TranscriptFragment], failure: String? = nil) {
        self.fragments = fragments
        self.failure = failure
    }

    public static let unavailable = TranscriptSweep(
        fragments: [],
        failure: "没能读到 ChatGPT 的界面内容（无障碍树是空的）")
}

/// 逐字稿采样的接缝。
///
/// **刻意不挂在 `CoachBridge` 上。** 给已有 protocol 加一个带默认实现的方法，
/// 等于埋一个静默失败：某个假实现忘了实现它，默认实现返回空，测试照样绿，
/// 而逐字稿永远是空的。做成独立 protocol 并由 `PracticeRunner` 注入，
/// 与 Phase 5 注入录音器的做法一致。
public protocol TranscriptSampling: Sendable {
    /// 采一次样。**绝不抛错**：读不到就把原因放进 `TranscriptSweep.failure`。
    func sample() -> TranscriptSweep
}
```

`Sources/ChatGPTBridge/AXTranscriptSampler.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 从 ChatGPT 的 AX 树里采一次对话文本。
///
/// **只做采样，不做拼接。** 拼接去重在 `IELTSCoachCore.TranscriptAssembler`，
/// 那边是纯字符串逻辑、能测到底；这边只负责「树长什么样 → 碎片是什么」，
/// 走 `AXAccess` 接缝，用 `FakeAXAccess` 摆出任意一棵树来测。
///
/// 说话人判别依据 spec 2.3.9：一条消息的文本节点排在它自己那个复制按钮**前面**
/// （`snapshotTree()` 是深度优先前序遍历，顺序 ≈ 文档顺序），
/// 而 `Copy message` 属于用户自己那条、`Copy` 属于 ChatGPT 的回复。
/// **判不出来就记 `.unknown`，绝不猜。**
public struct AXTranscriptSampler: TranscriptSampling {
    private let access: any AXAccess
    /// 短于这个长度的文本一律丢掉。界面上到处是单字符的装饰性文本节点，
    /// 它们混进逐字稿只会让人看不下去。
    private let minimumLength: Int

    public init(access: any AXAccess, minimumLength: Int = 2) {
        self.access = access
        self.minimumLength = minimumLength
    }

    public func sample() -> TranscriptSweep {
        let nodes = access.snapshotTree()
        // 树整个是空的 = 这一次真的没读到（应用被切走、树塌了、权限出问题）。
        // 这与「树有内容但还没人说话」是两回事，后者不是失败。
        guard !nodes.isEmpty else { return .unavailable }

        var fragments: [TranscriptFragment] = []
        var pending: [String] = []

        for node in nodes {
            if node.role == "AXStaticText" {
                let value = node.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= minimumLength { pending.append(node.value) }
                continue
            }
            if let speaker = ChatGPTLabels.speakerMarker(node) {
                fragments.append(contentsOf: pending.map {
                    TranscriptFragment(speaker: speaker, text: $0)
                })
                pending.removeAll()
            }
        }

        // 扫完还剩下的：多半是正在流式输出、复制按钮还没渲染出来的那条消息。
        // **不许丢掉**——那正是刚说完的最后一句话。判不出说话人就记 unknown。
        fragments.append(contentsOf: pending.map {
            TranscriptFragment(speaker: .unknown, text: $0)
        })

        return TranscriptSweep(fragments: fragments, failure: nil)
    }
}
```

`Sources/ChatGPTBridge/ChatGPTLabels.swift`：在 `copyAssistantMessage` 那行**下面**追加常量，并在文件末尾（`isVoiceActive` 之后、闭合大括号之前）追加 `speakerMarker`。

```swift
    /// **用户自己**那条消息下方的复制按钮（spec 2.3.9 实测，挨着 `Edit message`）。
    /// 与 `copyAssistantMessage` 结构完全相同（都是单个 AXImage 子节点），
    /// **只能靠标签精确区分**。逐字稿靠这两个标签判断每段话是谁说的，搞反会让整份记录的
    /// 说话人全反，而且不报错、不崩溃。
    public static let copyUserMessage = ["Copy message", "复制消息"]
```

```swift
    /// 这个节点能不能用来判定「前面攒的那些文本是谁说的」。
    ///
    /// 判据与 `matchControl` 对称（role + label + 结构三重，见 spec 2.3.1）：
    /// 侧边栏里可能存在同名的会话行，但它嵌套着 AXButton（Pin chat / Archive chat），
    /// 不是单个 AXImage 子节点，不满足结构判据。只按标签匹配会让说话人判别随机出错。
    ///
    /// **必须先判 `copyUserMessage` 再判 `copyAssistantMessage`** ——
    /// 两个集合的元素是精确相等比较，不存在前缀吞并问题，但顺序写反了读起来容易误解，
    /// 保持「先用户、后助手」这个固定顺序。
    public static func speakerMarker(_ node: AXNodeSnapshot) -> TranscriptSpeaker? {
        guard controlRoles.contains(node.role), node.isIconOnlyControl else { return nil }
        if copyUserMessage.contains(node.label) { return .learner }
        if copyAssistantMessage.contains(node.label) { return .examiner }
        return nil
    }
```

`ChatGPTLabels.swift` 顶部的 `import Foundation` 之后需要加 `import IELTSCoachCore`（`TranscriptSpeaker` 定义在 Core）。**若文件里已经 import 过就不要重复加。**

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AXTranscriptSamplerTests`
Expected: PASS（10 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `speakerMarker` 里 `copyUserMessage` 与 `copyAssistantMessage` 两行**对调返回值**（`.examiner` / `.learner` 互换） | `testTextBeforeTheAssistantCopyButtonBelongsToTheExaminer` 与 `testTextBeforeTheUserCopyButtonBelongsToTheLearner` |
| `sample()` 结尾那段「剩下的 pending 归 unknown」整块删掉 | `testTextWithNoSpeakerMarkerIsKeptAsUnknownInsteadOfDropped` |
| `speakerMarker` 里的 `node.isIconOnlyControl` 条件删掉 | `testASidebarRowNamedCopyIsNotMistakenForACopyButton` |
| `guard !nodes.isEmpty else { return .unavailable }` 删掉 | `testAnEmptyTreeIsReportedAsAFailureNotAsAnEmptyConversation` |

**第二条尤其要做。** 「剩下的归 unknown」这段看起来像是可有可无的收尾，实际上丢的是**用户刚说完的最后一句话**——每一轮都丢一句，而且完全无声无息。

- [ ] **Step 6: 提交**

```bash
git add Sources/ChatGPTBridge/TranscriptSampling.swift \
        Sources/ChatGPTBridge/AXTranscriptSampler.swift \
        Sources/ChatGPTBridge/ChatGPTLabels.swift \
        Tests/ChatGPTBridgeTests/AXTranscriptSamplerTests.swift
git commit -m "feat(bridge): 从 AX 树采集对话逐字稿碎片"
```

---

## Task 5: 采样节拍与失败记账 `TranscriptCollector`

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Session/TranscriptCollector.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/TranscriptCollectorTests.swift`

**Interfaces:**
- Consumes: `TranscriptSampling`、`TranscriptSweep`、`TranscriptAssembler`、`PracticeSession.TranscriptTurn`
- Produces:
  - `@MainActor @Observable public final class TranscriptCollector`
    - `init(sampler: (any TranscriptSampling)?, now: @escaping @Sendable () -> Date = { Date() })`
    - `public private(set) var isCollecting: Bool`
    - `public private(set) var turns: [PracticeSession.TranscriptTurn]`
    - `public private(set) var notice: String?`
    - `public private(set) var samplingFailureCount: Int`
    - `public func begin()` —— 采一次样当背景板，开始收集
    - `public func tick()` —— 采一次样并并入。**绝不抛错**
    - `public func finish()` —— 最后再采一次，停止收集，算出 `notice`
    - `public func abandon(reason: String)` —— 练习失败/取消时停止收集，内容保留

**为什么定时器不在这个类里：** 定时器让测试变成靠 `sleep` 碰运气。这里只提供 `begin` / `tick` / `finish` 三个同步方法，**节拍由 `PracticeRunner` 拿一个 `Task` 驱动**（Task 6）。这样这个类 100% 同步、100% 可测，而定时那几行是薄到看得出对错的接线。

**为什么 `sampler` 可以是 nil：** 用户在设置里关掉「记录对话逐字稿」时，`PracticeRunner` 直接传 nil。这个类要能安静地什么都不做——不报错、不留提示、`turns` 为空。**不要把「用户主动关掉」渲染成一条警告**，那是在为用户自己的选择报警。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/TranscriptCollectorTests.swift`：

```swift
import ChatGPTBridge
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假采样器：按脚本一次返回一个 sweep，用完之后重复最后一个。
final class FakeTranscriptSampler: TranscriptSampling, @unchecked Sendable {
    private var script: [TranscriptSweep]
    private(set) var sampleCount = 0

    init(_ script: [TranscriptSweep]) { self.script = script }

    func sample() -> TranscriptSweep {
        defer { sampleCount += 1 }
        guard !script.isEmpty else { return TranscriptSweep(fragments: []) }
        let index = min(sampleCount, script.count - 1)
        return script[index]
    }
}

@MainActor
final class TranscriptCollectorTests: XCTestCase {
    private func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }
    private func sweep(_ fragments: [TranscriptFragment]) -> TranscriptSweep {
        TranscriptSweep(fragments: fragments)
    }

    private var clock = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
    private func now() -> Date {
        clock = clock.addingTimeInterval(3)
        return clock
    }

    // MARK: - 正常路径

    func testWhatWasOnScreenAtTheStartIsTreatedAsBackground() {
        let sampler = FakeTranscriptSampler([
            sweep([learner("You will act as an IELTS Speaking examiner.")]),   // begin：背景板
            sweep([learner("You will act as an IELTS Speaking examiner."),
                   examiner("Do you live in a house or a flat?")])            // tick
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.tick()

        XCTAssertEqual(collector.turns.map(\.text), ["Do you live in a house or a flat?"],
                       "练习开始时就在屏幕上的考官提示词不算对话")
    }

    func testFinishTakesOneLastSampleSoTheClosingLineIsNotLost() {
        let sampler = FakeTranscriptSampler([
            sweep([]),
            sweep([examiner("Do you live in a house or a flat?")]),
            sweep([examiner("Do you live in a house or a flat?"),
                   learner("I live in a flat with my parents.")])
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.tick()
        collector.finish()

        XCTAssertEqual(collector.turns.count, 2, "finish 必须再采一次，否则最后一句话会丢")
        XCTAssertFalse(collector.isCollecting)
    }

    func testTickingAfterFinishDoesNothing() {
        let sampler = FakeTranscriptSampler([sweep([]), sweep([examiner("Q?")])])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.finish()
        let countAfterFinish = sampler.sampleCount
        collector.tick()
        XCTAssertEqual(sampler.sampleCount, countAfterFinish,
                       "已经结束了还在采样，只会把复盘 JSON 采进逐字稿")
    }

    // MARK: - 采样失败绝不中断

    /// **本任务的核心。** 中间失败几次，前后采到的内容都要在，
    /// 而且必须在 `notice` 里如实说出来。
    func testAFailedSampleNeitherThrowsNorLosesAnything() throws {
        let sampler = FakeTranscriptSampler([
            sweep([]),
            sweep([examiner("Do you live in a house or a flat?")]),
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容"),
            sweep([examiner("Do you live in a house or a flat?"),
                   learner("I live in a flat.")])
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.tick()
        collector.tick()        // 这一次失败
        collector.tick()
        collector.finish()

        XCTAssertEqual(collector.turns.count, 2, "失败前后采到的内容都要在")
        XCTAssertEqual(collector.samplingFailureCount, 1)
        let notice = try XCTUnwrap(collector.notice)
        XCTAssertTrue(notice.contains("下一步"))
    }

    func testAFailedBaselineIsRecordedAndCollectionStillStarts() {
        let sampler = FakeTranscriptSampler([
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容"),
            sweep([examiner("Do you live in a house or a flat?")])
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        XCTAssertTrue(collector.isCollecting, "背景板没采到也要照常开始收集")
        collector.tick()
        collector.finish()
        XCTAssertEqual(collector.samplingFailureCount, 1)
        XCTAssertEqual(collector.turns.count, 1)
    }

    func testAbandonKeepsWhatWasAlreadyCollected() throws {
        let sampler = FakeTranscriptSampler([
            sweep([]), sweep([examiner("Do you live in a house or a flat?")])
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.tick()
        collector.abandon(reason: "练习中途出错了")

        XCTAssertFalse(collector.isCollecting)
        XCTAssertEqual(collector.turns.count, 1, "练习失败了，已经采到的话也不能丢")
        XCTAssertTrue(try XCTUnwrap(collector.notice).contains("练习中途出错了"))
    }

    // MARK: - 用户关掉了开关

    func testNoSamplerMeansSilentlyDoingNothing() {
        let collector = TranscriptCollector(sampler: nil, now: { self.now() })
        collector.begin()
        collector.tick()
        collector.finish()

        XCTAssertTrue(collector.turns.isEmpty)
        XCTAssertNil(collector.notice, "用户自己关掉的功能，不该为此报警")
        XCTAssertEqual(collector.samplingFailureCount, 0)
        XCTAssertFalse(collector.isCollecting)
    }

    func testNoNoiseWhenEverythingWentFine() {
        let sampler = FakeTranscriptSampler([
            sweep([]), sweep([examiner("Q?"), learner("A.")])
        ])
        let collector = TranscriptCollector(sampler: sampler, now: { self.now() })
        collector.begin()
        collector.tick()
        collector.finish()
        XCTAssertNil(collector.notice)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TranscriptCollectorTests`
Expected: 编译失败 —— `TranscriptCollector` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Session/TranscriptCollector.swift`：

```swift
import ChatGPTBridge
import Foundation
import IELTSCoachCore
import Observation

/// 练习进行中的逐字稿收集。
///
/// 只负责「采一次样 → 并进拼接器 → 失败就记账」，**节拍由 `PracticeRunner` 驱动**
/// （它拿一个 Task 每隔几秒调一次 `tick()`）。把定时器留在外面，是为了让这个类
/// 100% 同步、100% 可测——定时器会让测试变成靠 sleep 碰运气。
///
/// **本类型的每一个方法都不抛错。** 逐字稿是增强，不是必需，
/// 采样失败不得中断练习（ROADMAP 3.2）。但也绝不静默：练完之后 `notice` 会
/// 如实说明缺了什么、下一步做什么。
@MainActor
@Observable
public final class TranscriptCollector {
    private let sampler: (any TranscriptSampling)?
    private let now: @Sendable () -> Date
    private var assembler = TranscriptAssembler()

    public private(set) var isCollecting = false
    public private(set) var turns: [PracticeSession.TranscriptTurn] = []
    /// 逐字稿不完整时的中文说明。**非 nil 时界面必须显示它。**
    public private(set) var notice: String?
    public private(set) var samplingFailureCount = 0

    /// - Parameter sampler: 传 nil 表示用户在设置里关掉了「记录对话逐字稿」。
    ///   此时本类型安静地什么都不做——不报错、不留提示。
    ///   **不要把「用户主动关掉」渲染成警告**，那是在为用户自己的选择报警。
    public init(sampler: (any TranscriptSampling)?,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.sampler = sampler
        self.now = now
    }

    /// 采一次样当背景板，然后开始收集。在练习进入 `.practicing` 那一刻调用。
    public func begin() {
        guard let sampler else { return }
        let sweep = sampler.sample()
        if let failure = sweep.failure {
            assembler.noteSamplingFailure(failure)
            samplingFailureCount += 1
        } else {
            assembler.seedBaseline(sweep.fragments)
        }
        isCollecting = true
        refresh()
    }

    /// 采一次样并并入。**绝不抛错。**
    public func tick() {
        guard isCollecting, let sampler else { return }
        let sweep = sampler.sample()
        if let failure = sweep.failure {
            assembler.noteSamplingFailure(failure)
            samplingFailureCount += 1
        } else {
            assembler.ingest(sweep.fragments, at: now())
        }
        refresh()
    }

    /// 最后再采一次样，然后停。
    ///
    /// **必须在发复盘请求之前调用。** 晚一步的话，复盘那一大坨 JSON 会被采进逐字稿里。
    public func finish() {
        guard isCollecting else { return }
        tick()
        isCollecting = false
        refresh()
    }

    /// 练习失败或被取消时停止收集。**已经采到的内容一个字都不丢**——
    /// 用户练到一半出错，前面说过的话仍然是他的练习记录。
    public func abandon(reason: String) {
        guard isCollecting else { return }
        isCollecting = false
        refresh()
        let existing = notice.map { $0 + " " } ?? ""
        notice = existing + "这一场没有正常走完：\(reason) "
            + "下一步：上面这些已经记下来的对话仍然会存进「训练记录」，不会丢。"
    }

    private func refresh() {
        turns = assembler.turns
        notice = assembler.completenessNote
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TranscriptCollectorTests`
Expected: PASS（8 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `finish()` 里的 `tick()` 删掉 | `testFinishTakesOneLastSampleSoTheClosingLineIsNotLost` |
| `tick()` 里 `if let failure = sweep.failure` 那一支改成 `return`（失败就整个不管） | `testAFailedSampleNeitherThrowsNorLosesAnything` |
| `begin()` 里的 `assembler.seedBaseline(sweep.fragments)` 改成 `assembler.ingest(sweep.fragments, at: now())` | `testWhatWasOnScreenAtTheStartIsTreatedAsBackground` |
| `tick()` 开头的 `guard isCollecting` 删掉 | `testTickingAfterFinishDoesNothing` |
| `abandon` 里的 `refresh()` 删掉 | `testAbandonKeepsWhatWasAlreadyCollected` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Session/TranscriptCollector.swift \
        Tests/IELTSCoachUITests/TranscriptCollectorTests.swift
git commit -m "feat(ui): 练习中的逐字稿收集与失败记账"
```

---

## Task 6: ★ 把逐字稿与会话记录接进 `PracticeRunner`

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Session/PracticeRunner.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Session/PracticeSheet.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/PracticeRunnerArchiveTests.swift`

**Interfaces:**
- Consumes: `CoachBridge`、`TranscriptSampling`、`TranscriptCollector`、`SessionID.next`、`PendingReviewStore.write`（Task 7 产出——**本任务排在 Task 7 之后做，见下方说明**）、`ReviewParser.parse`、`ReviewArchiver.archive`、`StateStore.mutate`、`DataDirectory`、`JSONValue`
- Produces（都是加在既有 `PracticeRunner` 上的）：
  - `PracticeRunner.init(bridge:pasteboard:directory:transcript:now:)` —— **新增的三个参数都带默认值，Phase 3 已有的调用点一处都不用改**
  - `public private(set) var finishedSessionID: String?`
  - `public private(set) var transcriptNotice: String?`
  - `public private(set) var transcriptTurnCount: Int`

> ### ⚠️ 执行顺序：先做 Task 7，再回来做 Task 6
>
> 本任务要用 `PendingReviewStore.write(rawText:sessionID:directory:)`（Task 7 产出）。
> 编号排在这里是为了让「逐字稿」那条主线读起来连贯，**实际动手时先把 Task 7 做完**。
> 若你已经先做了本任务并卡在 `PendingReviewStore` 未定义上，去把 Task 7 做掉再回来。

### 这一步兑现四件已经被别的阶段等着的事

| 谁在等 | 等什么 |
|---|---|
| Phase 5 P4-2 / Task 7 / Task 9 | 每次练习真的往 `state.sessions` 里落一条 `PracticeSession` |
| Phase 6 P2 / P3 | 同上，外加 `PracticeRunner.finishedSessionID` |
| Phase 7 依赖 1 | 同上（否则首页四格里三格恒为 0） |
| Phase 3 的复盘报告页 | `state.sessions` 里有带 `reportPath` 的会话（否则那一页永远是空的） |

**写这份计划时（2026-08-06）核对过：全工程没有任何一行代码往 `state.sessions` 里写过东西。** `Sources/coach/PracticeCommand.swift` 走完整场练习只调 `ReviewArchiver.archive(...)`，而 `ReviewArchiver` 只动 `issues` / `vocabulary` / `targets` / `plan` / `questions`。

### 必须遵守的七条接线规则

1. **不许动既有的阶段流转顺序。** spec 2.3.5 定死的「先新建会话 → 再启动语音 → 等语音输入框 → 最后发提示词」一个字都不能改。Live 语音只能在还没发送过消息的会话里启动，反过来做会让整场练习白练。
2. **逐字稿在 `.practicing` 那一刻开始收集**，即考官提示词已经发出去之后。更早开始只会把提示词本身采成背景板以外的东西。
3. **`collector.finish()` 必须是 `finishPractice()` 的第一件事**，早于结束语音、早于发复盘请求。晚一步的话，复盘那一大坨 JSON 会被采进逐字稿里。
4. **每一条会走到头的路径都要停掉收集**：`finishPractice()` 开头、`start(setup:)` 抛错的 catch 里、`cancel()` 里。漏掉任何一条，那个 Task 会一直转下去，一边空转一边把复盘采进逐字稿。
5. **会话记录要在取复盘之前就写进 `state.sessions`。** 取复盘、解析、归档任何一步失败，用户练的这一场和已经采到的逐字稿都必须留下来（成品标准第 7 条）。写完之后再去补 `reportPath`。
6. **先落盘再解析**，一个字都不能省。练了半小时换来的复盘，不能因为解析出错就没了。
7. **失败文案不许把用户推回终端。** 解析失败时指向界面里的「重新导入待处理的复盘」（Task 10），不是 `coach reimport`。

### `finishPractice()` 的确切顺序

```
1  collector.finish()                      ← 规则 3，第一件事
2  sessionID = SessionID.next(existing: 已有会话, now: now(), timeZone: .current)
3  把这一场 upsert 进 state.sessions（带逐字稿、起止时间、题目、目标）  ← 规则 5
4  finishedSessionID = sessionID
5  若语音还开着 → endVoice()                 stage = .endingVoice
6  sendText(ReviewRequestPrompt.build(...))  stage = .requestingReview
7  waitForAssistantReply(timeout: 60)
8  取复盘（复制按钮 → AX 读取 → 提示手动 ⌘C）  stage = .capturingReview
9  PendingReviewStore.write(...)             ← 规则 6，落盘
10 ReviewParser.parse(...)
11 ReviewArchiver.archive(...) + 写 reports/<id>.json + 回填 reportPath   stage = .archiving
12 stage = .done
```

第 5 步之后的任何一步抛错 → `stage = .failed(中文说明)`，**但第 3、4 步写下的东西不许回滚**。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PracticeRunnerArchiveTests.swift`：

```swift
import ChatGPTBridge
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class PracticeRunnerArchiveTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private static func setup(goal: String = "") -> SessionSetup {
        SessionSetup(question: Question(id: "p1-home-001", part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?"),
                     focusPart: .part1, durationMinutes: 5, goal: goal)
    }

    private let fixedNow = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

    private func examiner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .examiner, text: text)
    }
    private func learner(_ text: String) -> TranscriptFragment {
        TranscriptFragment(speaker: .learner, text: text)
    }

    /// 背景板一次、练习中一次、finish 时一次。
    private func scriptedSampler() -> FakeTranscriptSampler {
        FakeTranscriptSampler([
            TranscriptSweep(fragments: [learner("You will act as an IELTS Speaking examiner.")]),
            TranscriptSweep(fragments: [learner("You will act as an IELTS Speaking examiner."),
                                        examiner("Do you live in a house or a flat?")]),
            TranscriptSweep(fragments: [learner("You will act as an IELTS Speaking examiner."),
                                        examiner("Do you live in a house or a flat?"),
                                        learner("I live in a flat with my parents.")])
        ])
    }

    private func runner(bridge: FakeBridge = FakeBridge(),
                        sampler: (any TranscriptSampling)? = nil) -> PracticeRunner {
        PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                       directory: directory, transcript: sampler, now: { self.fixedNow })
    }

    // MARK: - 会话记录（Phase 5 / 6 / 7 都在等这个）

    func testAFinishedPracticeLandsInStateSessions() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup(goal: "回答后补一个原因和例子"))
        await runner.finishPractice()

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.count, 1, "练完一场必须留下一条训练记录")
        let session = try XCTUnwrap(saved.sessions.first)
        XCTAssertEqual(session.questionId, "p1-home-001")
        XCTAssertEqual(session.focusPart, .part1)
        XCTAssertEqual(session.goal, "回答后补一个原因和例子")
        XCTAssertFalse(session.startedAt.isEmpty, "没有开始时间的记录没法按月分组")
        XCTAssertFalse(session.endedAt.isEmpty)
    }

    /// 决策 1：新产生的编号一律是 `YYYY-MM-DD-NNN`，不再是 ISO8601 时间戳。
    func testTheSessionIDUsesTheNewShape() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        let id = try XCTUnwrap(try store.load().sessions.first?.id)
        XCTAssertEqual(id, "2026-08-06-001")
        XCTAssertEqual(runner.finishedSessionID, id, "Phase 6 要靠它把这一场和复训目标挂钩")
    }

    func testASecondPracticeOnTheSameDayGetsTheNextNumber() async throws {
        try store.mutate {
            $0.sessions.append(PracticeSession(id: "2026-08-06-003", questionId: "q",
                                               focusPart: .part1, startedAt: "", endedAt: "",
                                               goal: "", transcript: [], reportPath: "",
                                               recordingPath: ""))
        }
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        XCTAssertEqual(runner.finishedSessionID, "2026-08-06-004")
        XCTAssertEqual(try store.load().sessions.count, 2, "不能把已有的记录冲掉")
    }

    func testTheParsedReviewIsWrittenToReportsAndLinkedFromTheSession() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        let session = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(session.reportPath, "reports/2026-08-06-001.json",
                       "必须是相对数据目录的路径——写成绝对路径的话，换台电脑拷目录就全打不开了")
        let file = directory.root.appending(path: session.reportPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // reports/ 里存的必须是解析后的复盘本身，不是带定界标记的原文
        let json = try JSONValue.decode(from: String(contentsOf: file, encoding: .utf8))
        XCTAssertNotNil(json["must_correct"])
    }

    func testTheRawReviewIsOnDiskBeforeItIsEverParsed() async throws {
        let runner = self.runner()
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        let pending = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
            .filter { $0.hasSuffix(".txt") }
        XCTAssertEqual(pending, ["2026-08-06-001.txt"],
                       "原文必须先落盘再解析——练了半小时换来的复盘不能因为解析出错就没了")
    }

    // MARK: - 逐字稿

    func testTheTranscriptEndsUpOnThePracticeSession() async throws {
        let runner = self.runner(sampler: scriptedSampler())
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        let session = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(session.transcript.map(\.text),
                       ["Do you live in a house or a flat?", "I live in a flat with my parents."])
        XCTAssertEqual(session.transcript.map(\.role), ["assistant", "user"])
        XCTAssertEqual(runner.transcriptTurnCount, 2)
    }

    func testNoSamplerMeansAnEmptyTranscriptAndNoComplaint() async throws {
        let runner = self.runner(sampler: nil)
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        XCTAssertTrue(try XCTUnwrap(try store.load().sessions.first).transcript.isEmpty)
        XCTAssertNil(runner.transcriptNotice, "用户自己关掉的功能不该报警")
    }

    /// **本阶段的硬约束。** 采样一路失败，练习必须照常走完，
    /// 而且练完要如实告诉用户逐字稿不完整。
    func testSamplingFailureNeverBreaksThePractice() async throws {
        let alwaysFailing = FakeTranscriptSampler([
            TranscriptSweep(fragments: [], failure: "没能读到 ChatGPT 的界面内容")
        ])
        let runner = self.runner(sampler: alwaysFailing)
        try await runner.start(setup: Self.setup())

        XCTAssertEqual(runner.stage, .practicing, "采样失败绝不能把练习打断")
        await runner.finishPractice()
        XCTAssertEqual(runner.stage, .done, "练习必须照常走完")

        let notice = try XCTUnwrap(runner.transcriptNotice, "不完整就必须说出来，不能装作正常")
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertEqual(try store.load().sessions.count, 1, "逐字稿没采到，这一场也照样要记下来")
    }

    // MARK: - 失败路径：已经产生的内容一点都不能丢（成品标准第 7 条）

    func testWhenTheReviewCannotBeParsedThePracticeIsStillRecorded() async throws {
        let bridge = FakeBridge()
        bridge.reviewText = "ChatGPT 这次输出了一段没有定界标记的闲聊"
        let runner = self.runner(bridge: bridge, sampler: scriptedSampler())
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        guard case .failed(let message) = runner.stage else {
            return XCTFail("解析不了就该停在失败态，不能假装成功")
        }
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertFalse(message.contains("终端"),
                       "不许把用户推回终端——界面里已经有「重新导入待处理的复盘」了")
        XCTAssertTrue(message.contains("重新导入"), "要指出界面里那个入口")

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.count, 1, "复盘挂了，练习本身和逐字稿都还得在")
        XCTAssertEqual(saved.sessions[0].transcript.count, 2)
        XCTAssertTrue(saved.sessions[0].reportPath.isEmpty, "没有报告就不要假装有")
    }

    func testTheRawReviewSurvivesAParseFailure() async throws {
        let bridge = FakeBridge()
        bridge.reviewText = "没有定界标记的闲聊"
        let runner = self.runner(bridge: bridge)
        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        let pending = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(pending.count, 1, "解析失败时原文更不能丢")
    }

    func testAFailureDuringStartStopsCollectingAndRecordsNothing() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = self.runner(bridge: bridge, sampler: scriptedSampler())
        try? await runner.start(setup: Self.setup())

        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertNil(runner.finishedSessionID, "根本没练成，不能留下一条训练记录")
        XCTAssertEqual((try? store.load())?.sessions.count, 0)
    }
}
```

**`FakeBridge` 需要补一个可编程的 `reviewText`。** Phase 3 Task 9 那份 `FakeBridge` 的 `copyLatestAssistantMessage` 返回的是写死的一段合法复盘。本任务要能让它返回一段解析不了的文本，因此在 `Tests/IELTSCoachUITests/` 里找到 `FakeBridge`，加一个属性并改那一个方法：

```swift
    /// 让测试能造出「ChatGPT 输出了解析不了的东西」这种情况。
    var reviewText = #"<<<IELTS_REVIEW_JSON:x>>>{"must_correct":[]}<<<END_IELTS_REVIEW_JSON:x>>>"#

    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                    timeout: TimeInterval) throws -> String {
        try step("copy", .capturingReview)
        return reviewText
    }
```

**`FakeBridge` 的其余部分一个字都不要动。**

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRunnerArchiveTests`
Expected: 编译失败 —— `PracticeRunner` 没有 `directory:` / `transcript:` / `now:` 参数，也没有 `finishedSessionID`

- [ ] **Step 3: 实现**

在既有的 `PracticeRunner` 上按下面改。**不要重写整个文件**，只加属性、改初始化、按上面那份「确切顺序」调整 `finishPractice()`。

**（a）新增存储属性与初始化参数**

```swift
    private let directory: DataDirectory
    private let store: StateStore
    private let collector: TranscriptCollector
    private let now: @Sendable () -> Date
    /// 逐字稿采样的节拍。实测每 2~3 秒一次足够跟上流式输出，
    /// 又不会把 CPU 耗在反复遍历几百个 AX 节点上。
    private let samplingInterval: TimeInterval = 2.5
    private var samplingTask: Task<Void, Never>?
    /// 这一场的起止时刻与设置，归档时要写进 PracticeSession。
    private var startedAt: Date?
    private var currentSetup: SessionSetup?

    /// 本次练习归档后写进 `state.sessions` 的那条记录的 id。未完成时为 nil。
    /// 复训要靠它把「这一场」和「哪个目标」挂上钩（Phase 6 前置依赖 P3）。
    public private(set) var finishedSessionID: String?
    /// 逐字稿不完整时的中文说明。**非 nil 时界面必须显示它。**
    public private(set) var transcriptNotice: String?
    public private(set) var transcriptTurnCount = 0

    public init(bridge: any CoachBridge,
                pasteboard: any PasteboardAccess,
                directory: DataDirectory = .resolve(),
                transcript: (any TranscriptSampling)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.bridge = bridge
        self.pasteboard = pasteboard
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.collector = TranscriptCollector(sampler: transcript, now: now)
        self.now = now
    }
```

> **给 Phase 5 实现者的提醒：** Phase 5 Task 7 的测试里写的是
> `PracticeRunner(bridge:pasteboard:store:recording:)`。**实际签名是 `directory:`**，
> store 由它自己从 directory 派生——传 `store:` 而不传 `directory:` 会让报告和
> 待处理复盘写到用户真实数据目录里去，而 store 指向临时目录，测试看起来通过、
> 实际污染了用户数据。Phase 5 的计划已写明「以实际签名为准」，照着改测试即可。

**（b）`start(setup:)` 的改动**

- 开头记下 `startedAt = now()`、`currentSetup = setup`
- 走到 `.practicing` 之后（**考官提示词已经发出去**），启动收集与节拍：

```swift
        collector.begin()
        samplingTask = Task { [weak self, samplingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(samplingInterval))
                if Task.isCancelled { return }
                await self?.collector.tick()
            }
        }
        stage = .practicing
```

- 任何一步抛错的 catch 里，先 `stopSampling()` 再 `stage = .failed(...)`

**（c）新增两个私有方法**

```swift
    private func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    /// 把这一场写进 state.sessions。**按 id upsert，不是无脑 append**——
    /// 同一个编号重存不该产生第二条记录（Phase 9 的 save_session_review 也按同样规则做）。
    @discardableResult
    private func upsertSession(id: String, reportPath: String?) -> Bool {
        guard let setup = currentSetup else { return false }
        let formatter = ISO8601DateFormatter()
        do {
            try store.mutate { state in
                var session = state.sessions.first { $0.id == id }
                    ?? PracticeSession(id: id, questionId: setup.question.id,
                                       focusPart: setup.focusPart,
                                       startedAt: formatter.string(from: self.startedAt ?? self.now()),
                                       endedAt: "", goal: setup.goal,
                                       transcript: [], reportPath: "", recordingPath: "")
                session.endedAt = formatter.string(from: self.now())
                session.transcript = self.collector.turns
                if let reportPath { session.reportPath = reportPath }
                if let index = state.sessions.firstIndex(where: { $0.id == id }) {
                    state.sessions[index] = session
                } else {
                    state.sessions.append(session)
                }
                if state.currentSession?.id == id { state.currentSession = nil }
            }
            return true
        } catch {
            // 训练记录写不进去是真事故（这一场就真的没了），必须让用户看见。
            transcriptNotice = "这一场没能存进训练记录：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › IELTS Speaking Coach」），"
                + "然后重新练一场；复盘原文若已取回，仍然保存在 pending-reviews 目录里。"
            return false
        }
    }
```

**（d）`finishPractice()` 按前面那份「确切顺序」改**。关键片段：

```swift
        // 规则 3：第一件事。晚一步的话复盘那一大坨 JSON 会被采进逐字稿。
        stopSampling()
        collector.finish()
        transcriptTurnCount = collector.turns.count
        transcriptNotice = collector.notice

        let existing = (try? store.load())?.sessions ?? []
        let sessionID = SessionID.next(existing: existing, now: now(), timeZone: .current)

        // 规则 5：取复盘之前就把这一场记下来。后面任何一步失败，
        // 用户练的这一场和已经采到的逐字稿都还在（成品标准第 7 条）。
        upsertSession(id: sessionID, reportPath: nil)
        finishedSessionID = sessionID
```

取复盘之后：

```swift
        // 规则 6：先落盘再解析，一个字都不能省。
        let pendingURL: URL
        do {
            pendingURL = try PendingReviewStore.write(rawText: raw, sessionID: sessionID,
                                                      directory: directory)
        } catch {
            stage = .failed("复盘取回来了，但没能存到磁盘上：\(error.localizedDescription) "
                + "下一步：确认数据目录可写后，在 ChatGPT 里选中整段复盘按 ⌘C 再重试一次。")
            return
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
        } catch {
            // 规则 7：不许把用户推回终端。
            stage = .failed("\(error.localizedDescription) "
                + "好消息是原文没丢，已经存在 \(pendingURL.lastPathComponent)，这一场也已经记进训练记录了。"
                + "下一步：到「复盘报告」页点「重新导入待处理的复盘」，可以查看原文并重试；"
                + "若确实格式不对，回 ChatGPT 里让它按要求重新输出一次再导入。")
            return
        }
```

归档：

```swift
        let reportRelativePath = "reports/\(sessionID).json"
        do {
            try directory.createIfNeeded()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(sessionID).json"),
                       options: .atomic)

            let outcome = try store.mutate { state -> ArchiveOutcome in
                let result = ReviewArchiver.archive(report: report, into: state,
                                                    sessionID: sessionID,
                                                    questionID: currentSetup?.question.id ?? "",
                                                    at: ISO8601DateFormatter().string(from: now()))
                state = result.state
                return result
            }
            upsertSession(id: sessionID, reportPath: reportRelativePath)

            if !outcome.skipped.isEmpty {
                // 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
                // 这是本项目已知最危险的失败形态，绝不能静默。
                transcriptNotice = (transcriptNotice.map { $0 + " " } ?? "")
                    + "复盘里有 \(outcome.skipped.joined(separator: "、"))，但一条都没能归进档案。"
                    + "这通常意味着 ChatGPT 用的字段名和本工具读的对不上。"
                    + "下一步：原文完整保存在 \(pendingURL.lastPathComponent)，"
                    + "到「复盘报告」页用「重新导入待处理的复盘」可以重试，这场练习不会白费。"
            }
            stage = .done
        } catch {
            stage = .failed("复盘解析成功了，但归档时出错：\(error.localizedDescription) "
                + "好消息是原文和这一场的训练记录都还在。"
                + "下一步：到「复盘报告」页点「重新导入待处理的复盘」重试一次。")
        }
```

**（e）`cancel()`** 里加 `stopSampling()` 与 `collector.abandon(reason: "你中途取消了这次练习。")`。

**（f）`PracticeSheet` 的改动**（只给验收要求）：

- `.practicing` 时，若 `runner.transcriptTurnCount > 0`，显示一行「已记录 N 条对话」。用等宽数字（`.monospacedDigit()`），否则数字跳动时整行会抖
- `.done` 与 `.failed` 时，若 `runner.transcriptNotice != nil`，**必须**把它完整显示出来，可选中复制
- 不要因为逐字稿不完整就把整块渲染成红色错误——它是提示，不是失败。用 `Palette.warning`

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRunnerArchiveTests`
Expected: PASS（11 个测试）

Run: `swift test --filter PracticeRunnerTests`
Expected: PASS —— **Phase 3 的既有测试一条都不能红**。新参数都带默认值，那些调用点不用改

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 | 它守的是什么 |
|---|---|---|
| `finishPractice()` 里的 `upsertSession(id: sessionID, reportPath: nil)`（取复盘**之前**那一次）删掉 | `testWhenTheReviewCannotBeParsedThePracticeIsStillRecorded` | 成品标准第 7 条 |
| `upsertSession` 里的 `session.transcript = self.collector.turns` 删掉 | `testTheTranscriptEndsUpOnThePracticeSession` | 逐字稿真的落库 |
| `upsertSession` 里的 upsert 判断改成无条件 `state.sessions.append(session)` | `testASecondPracticeOnTheSameDayGetsTheNextNumber`（会变成 3 条） | 同一编号不产生第二条 |
| `reportRelativePath` 改成 `directory.reportsDirectory.appending(path: "\(sessionID).json").path`（绝对路径） | `testTheParsedReviewIsWrittenToReportsAndLinkedFromTheSession` | 成品标准第 10 条（拷目录换机器） |
| 把 `PendingReviewStore.write` 那一段挪到 `ReviewParser.parse` **之后** | `testTheRawReviewSurvivesAParseFailure` | 规则 6 |
| `finishPractice()` 开头的 `stopSampling()` + `collector.finish()` 挪到方法末尾 | `testTheTranscriptEndsUpOnThePracticeSession`（复盘 JSON 会被采进来） | 规则 3 |
| `start` 的 catch 里的 `stopSampling()` 删掉 | `testAFailureDuringStartStopsCollectingAndRecordsNothing`（可能不会立刻红——**这条要手工确认 Task 真的被取消了**，用 `runner.stage` 之外的方式，例如给 `FakeTranscriptSampler` 加一个 `sampleCount` 断言） | 规则 4 |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Session/PracticeRunner.swift \
        Sources/IELTSCoachUI/Session/PracticeSheet.swift \
        Tests/IELTSCoachUITests/PracticeRunnerArchiveTests.swift \
        Tests/IELTSCoachUITests/FakeBridge.swift
git commit -m "feat(ui): 练习结束落训练记录、逐字稿与复盘报告"
```

> `FakeBridge` 若不在单独的 `FakeBridge.swift` 里（Phase 3 可能把它放在
> `PracticeRunnerTests.swift` 内），把上面最后一行换成那个文件的路径。
> **不要用 `git add -A`。**

---

## Task 7: 待处理复盘的落盘与清点 `PendingReviewStore`（决策 2 的地基）

**先做这一个，再做 Task 6。**

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/PendingReviewStoreTests.swift`

**Interfaces:**
- Consumes: `DataDirectory`（`pendingReviewsDirectory`、`createIfNeeded()`）、`SessionID.validated(_:)`、`CoachError`
- Produces:
  - `public struct PendingReviewEntry: Equatable, Sendable, Identifiable`，含 `fileName: String`、`sessionID: String`、`modifiedAt: Date`、`byteCount: Int`、`url: URL`、`id: String { fileName }`
  - `public enum PendingReviewStore`
    - `public static let importedSuffix = ".imported"`
    - `@discardableResult public static func write(rawText: String, sessionID: String, directory: DataDirectory) throws -> URL`
    - `public static func list(directory: DataDirectory) throws -> [PendingReviewEntry]`
    - `public static func read(_ entry: PendingReviewEntry) throws -> String`
    - `@discardableResult public static func markImported(_ entry: PendingReviewEntry) throws -> URL`
    - `public static func delete(_ entry: PendingReviewEntry) throws`

**为什么落盘要单独一个可复用的东西：** 这是成品标准第 7 条（「任何一步失败，已产生的内容都还在」）的落点。`coach practice` 里已经有一份内联实现，本任务把它做成有测试的公共件，`PracticeRunner`（Task 6）与 Phase 9 的 `save_session_review` 都用它。

**为什么清点也放在这里：** 决策 2 要在界面里列出 `pending-reviews/` 的条目。列举、读原文、标记已入库、删除，这四件事和写入是同一份文件格式的两面，分成两个类型只会让「文件名规则」这条隐式契约散在两处。

**`.imported` 后缀是从 `coach reimport` 抄过来的既有约定**（见 `Sources/coach/ReimportCommand.swift` 第 26 行的长注释），两边必须一致，否则界面里导入过的文件，命令行会再导一遍：

- **不删**：用户可能想再打开看当时 ChatGPT 到底写了什么
- **不能原样保留**：`ReviewArchiver` 对「同一 session 重复归档」只在 `sourceSessionIds` 上去重，`IssueRecord.occurrences` 会跟着重复调用继续累加。反复导入会让「这句话说错了几次」悄悄失真，且没有任何提示

> ### 写给 Phase 9 实现者的话
>
> Phase 9 Task 3 也要创建 `Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`。
> **Phase 4 已经把它建好了，届时不要新建、不要覆盖**，跑一次
> `swift test --filter PendingReviewStoreTests` 确认全绿即可，然后直接进 Task 4。
>
> **注意：Phase 4 这一份的 `write` 比 Phase 9 计划里抄的那份严格**——它在判断文件名
> 是否被占用时，连 `<id>.txt.imported` 一起看（原因见下面 `write` 的文档注释）。
> 拿 Phase 9 计划里那段代码覆盖回去，会把这道防线拆掉，
> `PendingReviewStoreTests` 里的 `testANameWhoseImportedTwinExistsIsNeverHandedOutAgain`
> 会变红。以磁盘上这一份为准。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/PendingReviewStoreTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class PendingReviewStoreTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-pending-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 落盘

    func testWritesTheRawTextAndCreatesTheDirectoryOnItsOwn() throws {
        // 刻意没有先 createIfNeeded：落盘这一步发生在最危险的时刻，
        // 不能因为目录还不存在就把用户的复盘丢了。
        let url = try PendingReviewStore.write(rawText: "复盘原文", sessionID: "2026-08-06-001",
                                               directory: directory)
        XCTAssertEqual(url.lastPathComponent, "2026-08-06-001.txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "复盘原文")
    }

    func testWritingTheSameTextTwiceReusesTheSameFile() throws {
        let first = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                 directory: directory)
        let second = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(first, second, "重试一次不该多出一个一模一样的文件")
        let files = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(files.count, 1)
    }

    func testDifferentTextNeverOverwritesWhatIsAlreadyThere() throws {
        let first = try PendingReviewStore.write(rawText: "第一次的复盘", sessionID: "s1",
                                                 directory: directory)
        let second = try PendingReviewStore.write(rawText: "第二次的复盘", sessionID: "s1",
                                                  directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "第一次的复盘",
                       "先落盘的那份一个字都不能被覆盖")
    }

    func testANameWhoseImportedTwinExistsIsNeverHandedOutAgain() throws {
        // 复盘解析失败的那一场压根不会进 state.sessions，下一次 SessionID.next 取
        // 「当天已有编号的最大值 +1」，算出来还是同一个编号。此时 `<id>.txt` 确实
        // 已经不在了（被改名成 `<id>.txt.imported`），只看 `<id>.txt` 在不在，
        // 就会把这个已经用过的名字再发一次。
        _ = try PendingReviewStore.write(rawText: "第一次的复盘", sessionID: "s1",
                                         directory: directory)
        let first = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        let marked = try PendingReviewStore.markImported(first)

        let second = try PendingReviewStore.write(rawText: "第二次的复盘", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt",
                       "s1.txt 这个名字已经被 s1.txt.imported 占掉了，不能再发一次")
        XCTAssertEqual(try String(contentsOf: marked, encoding: .utf8), "第一次的复盘",
                       "已经入库的那份原文一个字都不能被动")

        // write 交出来的路径，必须保证它的 .imported 孪生名也是空的。否则归档做完了、
        // markImported 却因为目标已存在而失败，文件留在待处理列表里，用户再点一次
        // 导入就再归档一次，IssueRecord.occurrences 会一次次累加。
        let secondEntry = try XCTUnwrap(
            try PendingReviewStore.list(directory: directory)
                .first { $0.fileName == second.lastPathComponent })
        XCTAssertNoThrow(try PendingReviewStore.markImported(secondEntry),
                         "落盘时发的名字必须是连 .imported 孪生名一起空着的")
    }

    func testTextIdenticalToAnAlreadyImportedFileStillGetsItsOwnPendingFile() throws {
        // 「内容相同就复用」这条捷径不能跨过 .imported：那份已经入库，不在待处理列表里，
        // 把它的路径交回去，调用方会以为自己落盘成功了，用户却在收件箱里看不到这一份。
        _ = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                         directory: directory)
        let first = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        _ = try PendingReviewStore.markImported(first)

        let second = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                  directory: directory)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt")
        XCTAssertEqual(try PendingReviewStore.list(directory: directory).map(\.fileName),
                       ["s1-2.txt"], "新落盘的这一份必须能在待处理列表里看见")
    }

    func testAPendingFileIsNotReusedWhenItsImportedTwinIsAlreadyThere() throws {
        // 磁盘上同时躺着 s1.txt 和 s1.txt.imported——用户手工往 pending-reviews 里
        // 放过文件，或者旧版本留下的。内容一模一样也不能把 s1.txt 交回去：
        // 它的 .imported 名字已经被占，归档做完后 markImported 会失败。
        _ = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                         directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.copyItem(
            at: entry.url,
            to: entry.url.deletingLastPathComponent()
                .appendingPathComponent(entry.fileName + PendingReviewStore.importedSuffix))

        let again = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1",
                                                 directory: directory)
        XCTAssertEqual(again.lastPathComponent, "s1-2.txt")
        let againEntry = try XCTUnwrap(
            try PendingReviewStore.list(directory: directory)
                .first { $0.fileName == again.lastPathComponent })
        XCTAssertNoThrow(try PendingReviewStore.markImported(againEntry))
    }

    func testRejectsSessionIDsThatEscapeTheDataDirectory() {
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "x", sessionID: "../escaped",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
        let escaped = directory.root.deletingLastPathComponent().appending(path: "escaped.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testGivesUpWithAnActionableErrorInsteadOfLoopingForever() throws {
        // 同一个 sessionID 塞满 100 个不同内容之后必须报错退出，不能无限试下去
        //（禁止无限等待）。这条同时保证了实现里那个循环有出口。
        for index in 0..<100 {
            _ = try PendingReviewStore.write(rawText: "内容 \(index)", sessionID: "s1",
                                             directory: directory)
        }
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "第 101 份", sessionID: "s1",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
    }

    // MARK: - 清点

    func testListingAnAbsentDirectoryIsEmptyNotAnError() throws {
        // 全新安装、从没练过：目录还不存在。这不是错误，界面该显示空状态。
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty)
    }

    func testListsOnlyTxtFilesNewestFirst() throws {
        let old = try PendingReviewStore.write(rawText: "旧的", sessionID: "2026-08-05-001",
                                               directory: directory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: old.path)
        _ = try PendingReviewStore.write(rawText: "新的", sessionID: "2026-08-06-001",
                                         directory: directory)
        // 已经入库过的那份不该再出现在列表里
        let done = try PendingReviewStore.write(rawText: "已入库", sessionID: "2026-08-04-001",
                                                directory: directory)
        try FileManager.default.moveItem(
            at: done,
            to: done.deletingLastPathComponent()
                .appendingPathComponent(done.lastPathComponent + PendingReviewStore.importedSuffix))

        let entries = try PendingReviewStore.list(directory: directory)
        XCTAssertEqual(entries.map(\.sessionID), ["2026-08-06-001", "2026-08-05-001"])
        XCTAssertEqual(entries[0].byteCount, Data("新的".utf8).count)
    }

    func testTheSessionIDComesFromTheFileNameWithoutExtension() throws {
        _ = try PendingReviewStore.write(rawText: "x", sessionID: "sync-1785940167",
                                         directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        XCTAssertEqual(entry.sessionID, "sync-1785940167")
        XCTAssertEqual(entry.fileName, "sync-1785940167.txt")
    }

    func testReadingGivesBackExactlyWhatWasWritten() throws {
        let text = "<<<IELTS_REVIEW_JSON:x>>>{\"must_correct\":[]}<<<END_IELTS_REVIEW_JSON:x>>>"
        _ = try PendingReviewStore.write(rawText: text, sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        XCTAssertEqual(try PendingReviewStore.read(entry), text)
    }

    // MARK: - 标记与删除

    func testMarkingAsImportedKeepsTheFileButHidesItFromTheList() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        let marked = try PendingReviewStore.markImported(entry)

        XCTAssertEqual(marked.lastPathComponent, "s1.txt.imported")
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty,
                      "入库过的不该再出现在待处理列表里，否则会被反复导入")
        XCTAssertEqual(try String(contentsOf: marked, encoding: .utf8), "原文",
                       "原文一个字都不能改——用户可能想回头看当时 ChatGPT 写了什么")
    }

    func testMarkingImportedOntoAnOccupiedNameExplainsItselfInChinese() throws {
        // 手工往 pending-reviews 里放文件是允许的（`coach reimport` 就是这么用的），
        // 所以「`<id>.txt` 和 `<id>.txt.imported` 同时存在」没法从源头彻底杜绝。
        // 撞上了要说人话：归档发生在标记之前，此刻档案已经写完了，
        // 用户再点一次导入就再归档一次，IssueRecord.occurrences 会重复累加。
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.copyItem(
            at: entry.url,
            to: entry.url.deletingLastPathComponent()
                .appendingPathComponent(entry.fileName + PendingReviewStore.importedSuffix))

        XCTAssertThrowsError(try PendingReviewStore.markImported(entry)) { error in
            XCTAssertTrue(error is CoachError,
                          "不能把 Foundation 的英文原始错误直接摆到界面上：\(error)")
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("下一步"), "要说清下一步做什么：\(message)")
            XCTAssertTrue(message.contains("s1.txt"), "要说清是哪个文件：\(message)")
            XCTAssertTrue(message.contains("导入"), "要提醒别再导一次，否则出现次数会重复累加：\(message)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.url.path),
                      "标记失败也不能把原文弄丢")
    }

    func testDeletingReallyRemovesTheFile() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try PendingReviewStore.delete(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.url.path))
        XCTAssertTrue(try PendingReviewStore.list(directory: directory).isEmpty)
    }

    func testReadingAFileThatIsGoneSaysSoInsteadOfReturningEmpty() throws {
        _ = try PendingReviewStore.write(rawText: "原文", sessionID: "s1", directory: directory)
        let entry = try XCTUnwrap(try PendingReviewStore.list(directory: directory).first)
        try FileManager.default.removeItem(at: entry.url)

        XCTAssertThrowsError(try PendingReviewStore.read(entry)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"),
                          "读不到就要说清楚，返回空字符串等于假装它是一份空复盘")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PendingReviewStoreTests`
Expected: 编译失败 —— `PendingReviewStore` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`：

```swift
import Foundation

/// `pending-reviews/` 里的一份待入库复盘原文。
public struct PendingReviewEntry: Equatable, Sendable, Identifiable {
    public let fileName: String
    /// 文件名去掉扩展名，即当初落盘时用的会话编号。
    public let sessionID: String
    public let modifiedAt: Date
    public let byteCount: Int
    public let url: URL

    public var id: String { fileName }

    public init(fileName: String, sessionID: String, modifiedAt: Date,
                byteCount: Int, url: URL) {
        self.fileName = fileName; self.sessionID = sessionID
        self.modifiedAt = modifiedAt; self.byteCount = byteCount; self.url = url
    }
}

/// 复盘原文的落盘与清点。
///
/// **`write` 必须在解析之前调用。** spec 第 5 节：「复盘先落盘再入库，中途崩溃或
/// 误关窗口都不丢数据」。反过来写的话，解析一抛错，用户练了一整场换来的原文就没了，
/// 只能从头再练一次。
public enum PendingReviewStore {
    /// 成功入库后给文件追加的后缀。**与 `coach reimport` 的约定必须一致**
    /// （见 `Sources/coach/ReimportCommand.swift`），否则界面里导入过的文件，
    /// 命令行会再导一遍，而 `IssueRecord.occurrences` 会跟着重复累加、悄悄失真。
    public static let importedSuffix = ".imported"

    /// 同名文件已存在时的行为：
    /// - 内容完全相同 → 直接复用，重试不会堆出一堆一样的文件
    /// - 内容不同 → 改用 `<id>-2.txt`、`<id>-3.txt`…，**绝不覆盖已经落盘的内容**
    /// - 名字被 `<id>.txt.imported` 占着 → 一样要换名，见下
    ///
    /// **交出去的路径，必须保证它的 `.imported` 孪生名也是空的。** `markImported`
    /// 只改名不删除，而复盘解析失败的那一场压根不会进 `state.sessions`，
    /// 下一次 `SessionID.next` 取「当天已有编号的最大值 +1」会算出同一个编号。
    /// 此时 `<id>.txt` 确实不在了，光看它在不在就会把这个用过的名字再发一次；
    /// 等归档做完、`markImported` 撞上已存在的 `<id>.txt.imported` 抛错，文件就
    /// 留在了待处理列表里——用户再点一次导入就再归档一次，
    /// 而 `ReviewArchiver` 只在 `sourceSessionIds` 上去重，`IssueRecord.occurrences`
    /// 会跟着一次次累加，且没有任何提示。这正是决策 2 要防的那种静默失真。
    @discardableResult
    public static func write(rawText: String, sessionID: String,
                             directory: DataDirectory) throws -> URL {
        let safeID = try SessionID.validated(sessionID)
        try directory.createIfNeeded()

        let fileManager = FileManager.default
        var candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID).txt")
        var suffix = 2
        while true {
            let markedTwinExists = fileManager.fileExists(atPath: importedTwin(of: candidate).path)
            guard fileManager.fileExists(atPath: candidate.path) || markedTwinExists else { break }
            // 「内容相同就复用」这条捷径不能跨过已入库的那一份：它不在待处理列表里，
            // 把它的路径交回去，调用方会以为落盘成功了，用户却在收件箱里看不到这一份。
            if !markedTwinExists,
               let existing = try? String(contentsOf: candidate, encoding: .utf8),
               existing == rawText {
                return candidate
            }
            guard suffix <= 100 else {
                throw CoachError.stateUnreadable(
                    "同一个会话编号「\(safeID)」下已经占用了 100 个文件名"
                    + "（含已经标记为入库的），不再继续新建文件。"
                    + "下一步：到 \(directory.pendingReviewsDirectory.path) 清理掉不需要的文件，"
                    + "或在「复盘报告」页用「重新导入待处理的复盘」把它们处理掉。")
            }
            candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID)-\(suffix).txt")
            suffix += 1
        }

        try rawText.write(to: candidate, atomically: true, encoding: .utf8)
        return candidate
    }

    /// `<name>.txt` 对应的已入库标记文件 `<name>.txt.imported`。
    private static func importedTwin(of url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + importedSuffix)
    }

    /// 列出还没入库的复盘原文，新的在前。
    ///
    /// 只认 `.txt`：打过 `.imported` 标记的文件扫不到，但原文一字不改地留在磁盘上。
    /// **目录不存在不是错误**（全新安装、从没练过），返回空数组即可——
    /// 界面该显示的是空状态，不是一句报错。
    public static func list(directory: DataDirectory) throws -> [PendingReviewEntry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.pendingReviewsDirectory.path) else {
            return []
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directory.pendingReviewsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])

        return urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { url in
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey])
                return PendingReviewEntry(
                    fileName: url.lastPathComponent,
                    sessionID: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    byteCount: values?.fileSize ?? 0,
                    url: url)
            }
            // 时间相同时按文件名倒序，保证顺序稳定——列表每次刷新都跳来跳去很难用
            .sorted { ($0.modifiedAt, $0.fileName) > ($1.modifiedAt, $1.fileName) }
    }

    public static func read(_ entry: PendingReviewEntry) throws -> String {
        do {
            return try String(contentsOf: entry.url, encoding: .utf8)
        } catch {
            throw CoachError.reviewNotFound(
                "读不到待处理的复盘原文「\(entry.fileName)」：\(error.localizedDescription) "
                + "下一步：确认这个文件还在数据目录的 pending-reviews 里；"
                + "若已经被手工删掉了，在列表里把这一条也删掉即可，其余记录不受影响。")
        }
    }

    /// 标记为已入库：**不删除，只改名**。
    ///
    /// 失败了要说人话。`write` 已经保证自己发出去的名字连 `.imported` 孪生名一起空着，
    /// 但用户手工往 `pending-reviews/` 里放文件是允许的（`coach reimport` 就是这么用的），
    /// 所以撞名这件事没法从源头彻底杜绝。而这一步失败的后果比一般的改名失败重：
    /// 归档发生在标记之前，此刻档案已经写完，文件却还留在待处理列表里，
    /// 用户再点一次导入就再归档一次，`IssueRecord.occurrences` 会重复累加。
    /// 提示里必须把「别再导一次」说出来（`coach reimport` 同一情形下的警告也是这么写的）。
    @discardableResult
    public static func markImported(_ entry: PendingReviewEntry) throws -> URL {
        let target = importedTwin(of: entry.url)
        do {
            try FileManager.default.moveItem(at: entry.url, to: target)
        } catch {
            throw CoachError.stateUnreadable(
                "「\(entry.fileName)」的内容已经归进档案，但要把它标记为已入库（改名成"
                + "「\(target.lastPathComponent)」）时失败了：\(error.localizedDescription) "
                + "最常见的原因是这个名字已经被占。"
                + "下一步：先别再点一次导入——归档已经做完，再导一次会让错题的「出现次数」重复累加；"
                + "到 \(entry.url.deletingLastPathComponent().path) 把这个编号下不需要的那份"
                + "删掉或改个别的名字，再回来刷新列表。")
        }
        return target
    }

    public static func delete(_ entry: PendingReviewEntry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PendingReviewStoreTests`
Expected: PASS（16 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `write` 里 `if !markedTwinExists, let existing = ... { return candidate }` 整块删掉 | `testWritingTheSameTextTwiceReusesTheSameFile` |
| `write` 里那个 `while true` 循环整个删掉（直接写 `<id>.txt`） | `testDifferentTextNeverOverwritesWhatIsAlreadyThere`、`testGivesUpWithAnActionableErrorInsteadOfLoopingForever`、`testANameWhoseImportedTwinExistsIsNeverHandedOutAgain` 等 5 条 |
| `write` 的存在性判断去掉 `\|\| markedTwinExists`（只看 `<id>.txt`） | `testANameWhoseImportedTwinExistsIsNeverHandedOutAgain`、`testTextIdenticalToAnAlreadyImportedFileStillGetsItsOwnPendingFile` |
| `write` 复用捷径的 `!markedTwinExists,` 去掉 | `testAPendingFileIsNotReusedWhenItsImportedTwinIsAlreadyThere` |
| `write` 里的 `let safeID = try SessionID.validated(sessionID)` 改成 `let safeID = sessionID` | `testRejectsSessionIDsThatEscapeTheDataDirectory` |
| `list` 里的 `.filter { $0.pathExtension.lowercased() == "txt" }` 删掉 | `testMarkingAsImportedKeepsTheFileButHidesItFromTheList` |
| `read` 里的 `do/catch` 去掉、直接 `try? ... ?? ""` | `testReadingAFileThatIsGoneSaysSoInsteadOfReturningEmpty` |
| `markImported` 里的 `do/catch` 去掉、直接 `try moveItem` | `testMarkingImportedOntoAnOccupiedNameExplainsItselfInChinese` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Storage/PendingReviewStore.swift \
        Tests/IELTSCoachCoreTests/PendingReviewStoreTests.swift
git commit -m "feat(core): 待处理复盘的落盘、清点与标记"
```

---

## Task 8: 训练记录的视图模型（按月分组）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/History/HistoryViewModel.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/HistoryViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`sessions`、`questions`）、`PracticeSession`、`Question`
- Produces:
  - `public struct HistoryRow: Equatable, Identifiable, Sendable`，含 `id`、`session: PracticeSession`、`dateText`、`partText`、`questionText`、`questionIsMissing: Bool`、`turnCountText`、`reviewStatusText`、`hasReport: Bool`、`hasRecording: Bool`
  - `public struct HistoryMonth: Equatable, Identifiable, Sendable`，含 `id: String`、`title: String`、`rows: [HistoryRow]`
  - `public struct HistoryViewModel: Sendable`，含 `init(state: CoachState, timeZone: TimeZone = .current)`、`months: [HistoryMonth]`、`isEmpty: Bool`、`totalCount: Int`

### 三条必须做对的事

1. **两种会话编号都要认。** 决策 1 之后新记录是 `2026-08-06-001`，而用户已有的记录是 `2026-08-05T14:03:11Z`。分组优先用 `startedAt`，它为空时退回从 id 的日期前缀解析。**两条路都要有测试**——解析不出来就把那条归到「时间不详」并排在最后，**绝不能让它从列表里消失**。
2. **题目找不到不许藏起来。** 换季导入新题库后旧题可能不在了（成品标准第 12 条讲的正是这件事），此时显示「题目已不在题库里（id：xxx）」，而不是空白，更不是把这条记录跳过。
3. **月份标题自己拼，不要用 `DateFormatter` 的本地化格式。** 本地化格式会跟着用户的系统语言变，测试就没法写死断言了。直接用 `"\(year) 年 \(month) 月"`。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/HistoryViewModelTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class HistoryViewModelTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func session(_ id: String, startedAt: String, questionId: String = "q1",
                         part: FocusPart = .part1, turns: Int = 0,
                         reportPath: String = "", recordingPath: String = "") -> PracticeSession {
        PracticeSession(
            id: id, questionId: questionId, focusPart: part,
            startedAt: startedAt, endedAt: startedAt, goal: "",
            transcript: (0..<turns).map {
                PracticeSession.TranscriptTurn(role: $0 % 2 == 0 ? "assistant" : "user",
                                               text: "T\($0)", capturedAt: startedAt)
            },
            reportPath: reportPath, recordingPath: recordingPath)
    }

    private func state(_ sessions: [PracticeSession],
                       questions: [Question] = [Question(id: "q1", part: 1, topic: "Home",
                                                         prompt: "Do you live in a house or a flat?")])
        -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.questions = questions
        return value
    }

    // MARK: - 分组

    func testGroupsByMonthNewestFirst() {
        let model = HistoryViewModel(state: state([
            session("2026-07-30-001", startedAt: "2026-07-30T10:00:00Z"),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z"),
            session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.map(\.id), ["2026-08", "2026-07"])
        XCTAssertEqual(model.months[0].title, "2026 年 8 月")
        XCTAssertEqual(model.months[0].rows.count, 2)
        XCTAssertEqual(model.totalCount, 3)
    }

    func testRowsWithinAMonthAreNewestFirst() {
        let model = HistoryViewModel(state: state([
            session("2026-08-01-001", startedAt: "2026-08-01T10:00:00Z"),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months[0].rows.map(\.id), ["2026-08-06-001", "2026-08-01-001"])
    }

    /// 决策 1 之前的记录只有 ISO8601 形状的 id，且当时根本没往 sessions 里写过
    /// `startedAt`。这类记录必须照样能按月份归位，不能因为解析不出来就消失。
    func testFallsBackToTheDatePrefixOfTheSessionIDWhenStartedAtIsMissing() {
        let model = HistoryViewModel(state: state([
            session("2026-08-05T14:03:11Z", startedAt: "")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.map(\.id), ["2026-08"])
        XCTAssertEqual(model.months[0].rows[0].dateText, "8 月 5 日")
    }

    /// 连日期都解析不出来的记录（比如 `sync-1785940167`）也不许丢——
    /// 凭空消失会让用户以为练习记录没了。归到「时间不详」，排在最后。
    func testUnparseableRecordsGoToTheirOwnBucketAtTheEndInsteadOfVanishing() {
        let model = HistoryViewModel(state: state([
            session("sync-1785940167", startedAt: ""),
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)

        XCTAssertEqual(model.months.count, 2)
        XCTAssertEqual(model.months.last?.title, "时间不详")
        XCTAssertEqual(model.months.last?.rows.map(\.id), ["sync-1785940167"])
        XCTAssertEqual(model.totalCount, 2, "一条都不能少")
    }

    func testGroupingUsesTheGivenTimeZone() {
        // UTC 的 7 月 31 日 17 点，在东八区已经是 8 月 1 日。
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let sessions = [session("2026-07-31-001", startedAt: "2026-07-31T17:00:00Z")]
        XCTAssertEqual(HistoryViewModel(state: state(sessions), timeZone: utc).months.map(\.id),
                       ["2026-07"])
        XCTAssertEqual(HistoryViewModel(state: state(sessions), timeZone: shanghai).months.map(\.id),
                       ["2026-08"])
    }

    // MARK: - 每一行显示什么

    func testARowShowsDatePartQuestionTurnCountAndReviewStatus() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", part: .part2,
                    turns: 12, reportPath: "reports/2026-08-06-001.json")
        ]), timeZone: utc)

        let row = model.months[0].rows[0]
        XCTAssertEqual(row.dateText, "8 月 6 日")
        XCTAssertEqual(row.partText, "Part 2")
        XCTAssertEqual(row.questionText, "Do you live in a house or a flat?")
        XCTAssertFalse(row.questionIsMissing)
        XCTAssertEqual(row.turnCountText, "12 条对话")
        XCTAssertEqual(row.reviewStatusText, "复盘已存档")
        XCTAssertTrue(row.hasReport)
        XCTAssertFalse(row.hasRecording)
    }

    func testNoReportIsSaidPlainlyRatherThanLeftBlank() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z")
        ]), timeZone: utc)
        XCTAssertEqual(model.months[0].rows[0].reviewStatusText, "没有复盘")
        XCTAssertFalse(model.months[0].rows[0].hasReport)
    }

    func testNoTranscriptIsSaidPlainlyRatherThanShowingZero() {
        // 「0 条对话」看起来像出了什么问题；「没有逐字稿」是在陈述事实。
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", turns: 0)
        ]), timeZone: utc)
        XCTAssertEqual(model.months[0].rows[0].turnCountText, "没有逐字稿")
    }

    /// 换季导入新题库后旧题可能不在了（成品标准第 12 条）。
    /// 那一行必须还在，而且要说清楚发生了什么。
    func testAQuestionThatIsNoLongerInTheBankIsSpelledOutNotHidden() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z", questionId: "gone-001")
        ]), timeZone: utc)

        let row = model.months[0].rows[0]
        XCTAssertTrue(row.questionIsMissing)
        XCTAssertTrue(row.questionText.contains("gone-001"),
                      "要带上题目 id，用户才有办法自己去查")
        XCTAssertTrue(row.questionText.contains("题库"))
    }

    func testARecordingIsFlaggedSoPhase5CanHangThePlayerThere() {
        let model = HistoryViewModel(state: state([
            session("2026-08-06-001", startedAt: "2026-08-06T10:00:00Z",
                    recordingPath: "recordings/2026-08-06T10-00-00Z.m4a")
        ]), timeZone: utc)
        XCTAssertTrue(model.months[0].rows[0].hasRecording)
    }

    // MARK: - 空

    func testEmptyStateIsEmptyNotACrash() {
        let model = HistoryViewModel(state: state([]), timeZone: utc)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.months.isEmpty)
        XCTAssertEqual(model.totalCount, 0)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter HistoryViewModelTests`
Expected: 编译失败 —— `HistoryViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/History/HistoryViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct HistoryRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let session: PracticeSession
    public let dateText: String
    public let partText: String
    public let questionText: String
    /// 题目已经不在题库里（换季导入过新题库）。界面要把这一行标出来，
    /// **但绝不能因此把这条记录藏起来**——凭空消失会让用户以为练习记录丢了。
    public let questionIsMissing: Bool
    public let turnCountText: String
    public let reviewStatusText: String
    public let hasReport: Bool
    /// Phase 5 会在这一行下面挂回听播放器。
    public let hasRecording: Bool
}

public struct HistoryMonth: Equatable, Identifiable, Sendable {
    /// `"2026-08"`，或时间解析不出来时的 `"unknown"`。
    public let id: String
    public let title: String
    public let rows: [HistoryRow]
}

/// 训练记录页要显示的东西。纯数据变换，不碰文件、不碰界面。
public struct HistoryViewModel: Sendable {
    public let months: [HistoryMonth]

    public init(state: CoachState, timeZone: TimeZone = .current) {
        let calendar = HistoryViewModel.calendar(in: timeZone)
        let questions = Dictionary(state.questions.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })

        // 先算出每条记录的时刻（可能为 nil），再排序、再分组。
        let dated: [(session: PracticeSession, moment: Date?)] = state.sessions.map {
            ($0, HistoryViewModel.moment(of: $0))
        }
        // 新的在前；时间不详的一律排到最后，但保持它们彼此之间按 id 倒序，顺序稳定。
        let sorted = dated.sorted { left, right in
            switch (left.moment, right.moment) {
            case let (l?, r?): return l == r ? left.session.id > right.session.id : l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.session.id > right.session.id
            }
        }

        var order: [String] = []
        var buckets: [String: [HistoryRow]] = [:]
        var titles: [String: String] = [:]

        for entry in sorted {
            let key: String
            let title: String
            let dateText: String
            if let moment = entry.moment {
                let parts = calendar.dateComponents([.year, .month, .day], from: moment)
                let year = parts.year ?? 0
                let month = parts.month ?? 0
                key = String(format: "%04d-%02d", year, month)
                title = "\(year) 年 \(month) 月"
                dateText = "\(month) 月 \(parts.day ?? 0) 日"
            } else {
                key = "unknown"
                title = "时间不详"
                dateText = "时间不详"
            }

            if buckets[key] == nil { order.append(key); titles[key] = title }
            buckets[key, default: []].append(
                HistoryViewModel.row(for: entry.session, dateText: dateText, questions: questions))
        }

        months = order.map { HistoryMonth(id: $0, title: titles[$0] ?? $0, rows: buckets[$0] ?? []) }
    }

    public var isEmpty: Bool { months.isEmpty }
    public var totalCount: Int { months.reduce(0) { $0 + $1.rows.count } }

    // MARK: - 私有

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// 这条记录发生在什么时候。
    ///
    /// 优先用 `startedAt`；它为空或解析不了时，退回从 id 的日期前缀解析——
    /// 决策 1 之前用命令行练的那些记录，id 是 ISO8601 时间戳，`startedAt` 可能是空的。
    /// **两条路都解析不出来时返回 nil，那条记录归到「时间不详」，绝不丢弃。**
    static func moment(of session: PracticeSession) -> Date? {
        for formatter in isoFormatters {
            if let date = formatter.date(from: session.startedAt) { return date }
            if let date = formatter.date(from: session.id) { return date }
        }
        // "2026-08-06-001" / "2026-08-06T14:03:11Z" 都以 yyyy-MM-dd 开头
        let prefix = String(session.id.prefix(10))
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: prefix)
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    private static func row(for session: PracticeSession, dateText: String,
                            questions: [String: Question]) -> HistoryRow {
        let question = questions[session.questionId]
        let questionText = question?.prompt
            ?? "这道题已经不在题库里了（id：\(session.questionId)）。"
        let turnCount = session.transcript.count
        return HistoryRow(
            id: session.id,
            session: session,
            dateText: dateText,
            partText: session.focusPart.rawValue,
            questionText: questionText,
            questionIsMissing: question == nil,
            // 「0 条对话」看起来像出了什么问题；「没有逐字稿」是在陈述事实。
            turnCountText: turnCount > 0 ? "\(turnCount) 条对话" : "没有逐字稿",
            reviewStatusText: session.reportPath.isEmpty ? "没有复盘" : "复盘已存档",
            hasReport: !session.reportPath.isEmpty,
            hasRecording: !session.recordingPath.isEmpty)
    }
}
```

> **`focusPart.rawValue` 的取值是 `"Part 1"` / `"Part 2"` / `"Part 3"` / `"full mock"`**
> （见 `Sources/IELTSCoachCore/Model/FocusPart.swift`）。最后一个显示成 `"full mock"`
> 在中文界面里很扎眼，但**本阶段不要动 `FocusPart`**——它的 raw value 与上游
> `state.json` 兼容，改了会让已有数据读不出来。要中文显示名的话，
> 在 `HistoryViewModel` 里加一个 `switch` 映射（`.fullMock → "全真模考"`），
> 并给它补一条测试。这属于可做可不做，做的话记得测。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter HistoryViewModelTests`
Expected: PASS（11 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| 排序闭包里的 `return l > r` → `return l < r` | `testGroupsByMonthNewestFirst`、`testRowsWithinAMonthAreNewestFirst` |
| `moment(of:)` 里从 id 解析日期前缀那一段整块删掉（直接 `return nil`） | `testFallsBackToTheDatePrefixOfTheSessionIDWhenStartedAtIsMissing` |
| 构造循环里 `else { key = "unknown" ... }` 那一支改成 `continue`（跳过解析不了的） | `testUnparseableRecordsGoToTheirOwnBucketAtTheEndInsteadOfVanishing` |
| `row(for:)` 里的 `?? "这道题已经不在题库里了…"` 改成 `?? ""` | `testAQuestionThatIsNoLongerInTheBankIsSpelledOutNotHidden` |
| `turnCount > 0 ? ... : "没有逐字稿"` 改成 `"\(turnCount) 条对话"` | `testNoTranscriptIsSaidPlainlyRatherThanShowingZero` |
| `calendar.timeZone = timeZone` 删掉 | `testGroupingUsesTheGivenTimeZone` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/History/HistoryViewModel.swift \
        Tests/IELTSCoachUITests/HistoryViewModelTests.swift
git commit -m "feat(ui): 训练记录按月分组的视图模型"
```

---

## Task 9: 训练记录页 + 侧边栏解锁 + 逐字稿开关（决策 3、决策 5）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/History/HistoryView.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Navigation.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/RootView.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/AppState.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/NavigationTests.swift`

**Interfaces:**
- Consumes: `HistoryViewModel`、`AppState`、`SidebarItem`、`Palette` / `Spacing` / `Radius`、`CoachCard` / `SectionHeader` / `EmptyStateView`、`StateStore.mutate`
- Produces:
  - `SidebarItem.isImplemented` 对 `.history` 返回 `true`
  - `AppState.setTranscriptEnabled(_ enabled: Bool)`
  - `public struct HistoryView: View`，`init(app: AppState)`

- [ ] **Step 1: 改测试（先让它红）**

`Tests/IELTSCoachUITests/NavigationTests.swift`：找到那条断言「已实现页面集合」的测试（Phase 3 里叫 `testPhase3ImplementsExactlyThreePages`），**改名并把 `.history` 加进集合**：

```swift
    func testImplementedPagesMatchWhatIsActuallyBuilt() {
        // 断言集合相等而不是「至少包含」——多标一项会让用户点进一个空页面，
        // 而空页面会让人以为程序坏了。
        // Phase 4 把「训练记录」加了进来。后续阶段各自往里加自己的那一项，
        // 不要把别人加的删掉：Phase 6 加 .retraining，Phase 7 加 .issues 与 .vocabulary，
        // Phase 8 加 .plan，Phase 10 加 .upgrade 与 .feedback。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertEqual(Set(implemented), [.today, .questionBank, .reviewReports, .history])
    }
```

再在同一个文件里追加一条：

```swift
    func testHistoryHasAMeaningfulTitleAndIcon() {
        XCTAssertEqual(SidebarItem.history.title, "训练记录")
        XCTAssertFalse(SidebarItem.history.systemImage.isEmpty)
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter NavigationTests`
Expected: `testImplementedPagesMatchWhatIsActuallyBuilt` FAIL —— `.history` 还没标成已实现

- [ ] **Step 3: 实现**

**（a）`Navigation.swift`：** 在 `isImplemented` 的 `switch` 里把 `.history` 挪进 `true` 那一支。

```swift
    public var isImplemented: Bool {
        switch self {
        // Phase 4 加了 .history。后续阶段各自往这里加自己的那一项，不要删别人的。
        case .today, .questionBank, .reviewReports, .history: return true
        default: return false
        }
    }
```

`PlaceholderView` 里那条 `case .history: return "将来在这里按月回看…"` 可以留着（它已经走不到了），也可以删。**不要顺手改别的 case 的文案。**

**（b）`AppState.swift`：** 加一个写方法。

```swift
    /// 「记录对话逐字稿」开关（ROADMAP 第 5 节，默认开）。
    ///
    /// 写盘失败必须让用户看见——静默失败会让用户以为已经关掉了，实际还在记录。
    /// 这属于本项目最不能接受的那种失败：界面显示的状态和真实行为对不上。
    public func setTranscriptEnabled(_ enabled: Bool) {
        do {
            try store.mutate { $0.settings.transcriptEnabled = enabled }
            reload()
        } catch {
            loadError = "没能保存「记录对话逐字稿」这个设置：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重试；在此之前这个开关仍按原来的设置生效。"
        }
    }
```

**（c）`RootView.swift`：** 在 `detail` 的 `switch selection` 里加一行 `case .history: HistoryView(app: app)`。**别的 case 一个字都不要动。**

**（d）`HistoryView.swift` —— 只给验收要求，布局自己定**

必须做到：

| # | 要求 |
|---|---|
| 1 | 用 `SectionHeader` 做页头，形如 `02 TRAINING HISTORY` + `训练记录`（编号与英文标签用 `.caption` + `Palette.textSecondary`，中文标题 `.title2`——见 `DESIGN-SYSTEM.md` 第 4 节） |
| 2 | 页头右侧一个 **「记录对话逐字稿」开关**，绑 `app.state.settings.transcriptEnabled`，改动调 `app.setTranscriptEnabled(_:)`。**开关下方一行小字说明**：「开着时，练习中会把考官的问题和你的回答记下来，方便复盘时回看。它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网。」 |
| 3 | 按 `HistoryViewModel.months` 分组，每组一个月份标题 + 若干行 |
| 4 | 每行显示 `dateText` / `partText` / `questionText` / `turnCountText` / `reviewStatusText` 五项，缺一不可（这五项就是 ROADMAP Phase 4 交付清单里写死的） |
| 5 | `questionIsMissing` 为真时，题目那一格用 `Palette.warning` 并保持整行可点——**绝不能把这一行藏起来** |
| 6 | 数字（`N 条对话`）用 `.monospacedDigit()`，否则数值变化时整行会抖 |
| 7 | 点开一行，右侧（或下方）显示**逐字稿全文**：按 `session.transcript` 顺序，考官与自己用不同的对齐或底色区分；`role == "unknown"` 的那些标成「说不准是谁说的」，**不要猜** |
| 8 | 逐字稿为空时，那一块显示：「这一场没有逐字稿。可能是练习时「记录对话逐字稿」是关着的，也可能是这一场发生在这个功能上线之前。下一步：确认上面的开关是开的，下次练习就会记下来。」 |
| 9 | `hasReport` 为真时给一个「看这次的复盘」按钮，跳到复盘报告页并选中这一场 |
| 10 | 整页为空时用 `EmptyStateView`：「还没有训练记录。」/「练完第一场之后，这里会按月列出你练过的每一道题、每一次对话。」/ 按钮「去今日训练」，点了跳到 `.today` |
| 11 | 视图里**不得出现任何字面颜色、字号、圆角**，全部走令牌 |
| 12 | 每行留出一个删除入口（Task 10 接上去）。本任务先不实现删除行为 |

**这一页不要做搜索、筛选、导出。** 那些都不在 ROADMAP Phase 4 的交付清单里，加进来只会让本阶段更难验收。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter NavigationTests`
Expected: PASS

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `isImplemented` 里把 `.history` 拿掉 | `testImplementedPagesMatchWhatIsActuallyBuilt` |
| `isImplemented` 里再多标一项（比如 `.plan`） | 同上（集合相等断言两个方向都守） |

`AppState.setTranscriptEnabled` 与 `HistoryView` 的正确性由 Task 13 的人工验收把关——**开关拨过去之后关掉 App 再打开，必须还是拨过去的状态**，这一条务必真做一次。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/History/HistoryView.swift \
        Sources/IELTSCoachUI/Navigation.swift \
        Sources/IELTSCoachUI/RootView.swift \
        Sources/IELTSCoachUI/AppState.swift \
        Tests/IELTSCoachUITests/NavigationTests.swift
git commit -m "feat(ui): 训练记录页与「记录对话逐字稿」开关"
```

---

## Task 10: 单条训练记录删除，连带清理录音与复盘报告（决策 4）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/History/SessionDeleter.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/History/HistoryView.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/SessionDeleterTests.swift`

**Interfaces:**
- Consumes: `PracticeSession`、`DataDirectory`、`StateStore.mutate`
- Produces:
  - `public struct SessionDeletionPlan: Equatable, Sendable`，含 `sessionID: String`、`relativePaths: [String]`、`confirmationText: String`
  - `public enum SessionDeletion`，含 `static func plan(for session: PracticeSession) -> SessionDeletionPlan`
  - `public protocol FileRemoving: Sendable`，含 `func fileExists(at url: URL) -> Bool`、`func remove(at url: URL) throws`
  - `public struct SystemFileRemover: FileRemoving`
  - `@MainActor public final class SessionDeleter`，含 `init(directory:store:fileRemover:)`、`func delete(_ session: PracticeSession) -> String?`

### 为什么要连带删文件

决策 4：不删录音会留下**永远不会被引用的孤儿音频文件**，慢慢把磁盘吃满，而用户完全看不见。复盘报告文件同理——删掉训练记录却留着 `reports/<id>.json`，复盘报告页还会继续列出这一场，用户会以为删除没生效。

### 三条必须做对的事

1. **Phase 5 还没交付时不得硬依赖它。** 清理逻辑就是「`recordingPath` 非空就按相对路径删，空就跳过」，只用 `FileManager` 和 `DataDirectory.root`，**不许 import 任何 Phase 5 的类型**。
2. **确认对话框必须逐条列明会删掉什么，也要说清什么不会删。** 错题本与词汇本里已经归档的内容不跟着删——那是有意的（那些是跨场累积的统计），但必须说出来，否则用户会以为一并清了。
3. **删文件失败不许静默。** state 里的记录已经删掉了、文件却删不掉，是很常见的情况（文件被别的程序占着、权限变了）。此时如实告诉用户哪几个文件没删掉、在哪儿，让他能自己去清。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/SessionDeleterTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假文件删除器：能指定「哪些路径删起来会失败」。
final class FakeFileRemover: FileRemoving, @unchecked Sendable {
    var existing: Set<String> = []
    var failingPaths: Set<String> = []
    private(set) var removed: [String] = []

    func fileExists(at url: URL) -> Bool { existing.contains(url.lastPathComponent) }

    func remove(at url: URL) throws {
        if failingPaths.contains(url.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission)
        }
        removed.append(url.lastPathComponent)
        existing.remove(url.lastPathComponent)
    }
}

@MainActor
final class SessionDeleterTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, reportPath: String = "",
                         recordingPath: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: reportPath,
                        recordingPath: recordingPath)
    }

    // MARK: - 确认文案

    func testTheConfirmationSpellsOutEveryFileItWillDelete() {
        let plan = SessionDeletion.plan(for: session("2026-08-06-001",
                                                     reportPath: "reports/2026-08-06-001.json",
                                                     recordingPath: "recordings/a.m4a"))
        XCTAssertEqual(plan.relativePaths,
                       ["reports/2026-08-06-001.json", "recordings/a.m4a"])
        XCTAssertTrue(plan.confirmationText.contains("录音"))
        XCTAssertTrue(plan.confirmationText.contains("复盘"))
        XCTAssertTrue(plan.confirmationText.contains("错题本"),
                      "必须说清什么不会跟着删，否则用户会以为全清了")
    }

    func testASessionWithoutARecordingDoesNotPretendToHaveOne() {
        let plan = SessionDeletion.plan(for: session("2026-08-06-001",
                                                     reportPath: "reports/2026-08-06-001.json"))
        XCTAssertEqual(plan.relativePaths, ["reports/2026-08-06-001.json"])
        XCTAssertFalse(plan.confirmationText.contains("录音"))
    }

    // MARK: - 真的删掉

    func testDeletingRemovesTheRecordFromState() throws {
        try store.mutate { $0.sessions = [self.session("a"), self.session("b")] }
        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover())
        let notice = deleter.delete(session("a"))

        XCTAssertNil(notice, "一切顺利时不要弹提示")
        XCTAssertEqual(try store.load().sessions.map(\.id), ["b"])
    }

    /// **决策 4 的守卫。** 不删录音会留下永远不会被引用的孤儿文件把磁盘吃满，
    /// 而用户完全看不见。
    func testDeletingAlsoRemovesTheRecordingAndTheReport() throws {
        let remover = FakeFileRemover()
        remover.existing = ["2026-08-06-001.json", "a.m4a"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json",
                                        recordingPath: "recordings/a.m4a")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        _ = deleter.delete(session("2026-08-06-001",
                                   reportPath: "reports/2026-08-06-001.json",
                                   recordingPath: "recordings/a.m4a"))

        XCTAssertEqual(Set(remover.removed), ["2026-08-06-001.json", "a.m4a"])
    }

    /// Phase 5 还没交付时，绝大多数记录的 recordingPath 就是空的。
    /// 「有就删、没有就跳过」，不许硬依赖 Phase 5 的任何类型。
    func testAnEmptyRecordingPathIsJustSkipped() throws {
        let remover = FakeFileRemover()
        remover.existing = ["2026-08-06-001.json"]
        try store.mutate {
            $0.sessions = [self.session("2026-08-06-001",
                                        reportPath: "reports/2026-08-06-001.json")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)
        let notice = deleter.delete(session("2026-08-06-001",
                                            reportPath: "reports/2026-08-06-001.json"))

        XCTAssertNil(notice)
        XCTAssertEqual(remover.removed, ["2026-08-06-001.json"])
    }

    func testAFileThatIsAlreadyGoneIsNotAnError() throws {
        let remover = FakeFileRemover()          // existing 是空的，什么都不在
        try store.mutate {
            $0.sessions = [self.session("a", reportPath: "reports/a.json",
                                        recordingPath: "recordings/a.m4a")]
        }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)

        XCTAssertNil(deleter.delete(session("a", reportPath: "reports/a.json",
                                            recordingPath: "recordings/a.m4a")),
                     "文件本来就不在，不该报错")
        XCTAssertEqual(try store.load().sessions.count, 0)
    }

    // MARK: - 失败要说出来

    /// 记录删掉了、文件删不掉（被占用、权限变了），必须如实告诉用户是哪个文件、在哪儿。
    /// 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
    func testAFileThatCouldNotBeDeletedIsReportedWithItsPath() throws {
        let remover = FakeFileRemover()
        remover.existing = ["a.m4a"]
        remover.failingPaths = ["a.m4a"]
        try store.mutate { $0.sessions = [self.session("a", recordingPath: "recordings/a.m4a")] }
        let deleter = SessionDeleter(directory: directory, store: store, fileRemover: remover)

        let notice = try XCTUnwrap(deleter.delete(session("a", recordingPath: "recordings/a.m4a")))
        XCTAssertTrue(notice.contains("recordings/a.m4a"))
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertEqual(try store.load().sessions.count, 0,
                       "文件删不掉不该拦住记录本身的删除，否则用户就卡住了")
    }

    func testAFailingStateWriteIsReportedInsteadOfSilentlyDoingNothing() throws {
        // 数据目录整个不可写时，删除必须报出来，不能装作删掉了。
        try FileManager.default.removeItem(at: directory.root)
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try store.mutate { $0.sessions = [self.session("a")] }
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: directory.root.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: directory.root.path)
        }

        let deleter = SessionDeleter(directory: directory, store: store,
                                     fileRemover: FakeFileRemover())
        let notice = deleter.delete(session("a"))
        XCTAssertNotNil(notice, "写不进去就必须说出来")
        XCTAssertTrue(try XCTUnwrap(notice).contains("下一步"))
    }
}
```

> **最后那条测试用改目录权限来造失败。** 若在你的环境里 `flock` / `replaceItemAt`
> 的行为与预期不同导致它不稳定，**可以把它删掉**，但必须换一条等价的：
> 用一个会抛错的假 store 包装也行。**不许直接不测「写盘失败」这条路径**。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SessionDeleterTests`
Expected: 编译失败 —— `SessionDeletion`、`SessionDeleter` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/History/SessionDeleter.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 删一条训练记录会连带删掉哪些文件。**纯计算，不碰磁盘**，所以能测。
public struct SessionDeletionPlan: Equatable, Sendable {
    public let sessionID: String
    /// 相对数据目录的路径，顺序固定：先复盘报告，再录音。
    public let relativePaths: [String]
    /// 给用户看的确认文案。**必须逐条列明会删掉什么、也说清什么不会删。**
    public let confirmationText: String
}

public enum SessionDeletion {
    public static func plan(for session: PracticeSession) -> SessionDeletionPlan {
        var paths: [String] = []
        var pieces: [String] = ["这一场的训练记录和逐字稿"]
        if !session.reportPath.isEmpty {
            paths.append(session.reportPath)
            pieces.append("它的复盘报告")
        }
        // Phase 5 还没交付时，recordingPath 基本都是空的——「有就删、没有就跳过」，
        // 不硬依赖 Phase 5 的任何类型（决策 4）。
        if !session.recordingPath.isEmpty {
            paths.append(session.recordingPath)
            pieces.append("它的录音文件")
        }
        return SessionDeletionPlan(
            sessionID: session.id,
            relativePaths: paths,
            confirmationText: "删掉之后，\(pieces.joined(separator: "、"))都会从磁盘上消失，无法恢复。"
                + "已经归进错题本和词汇本的内容不会跟着删——那些是跨场累积的，"
                + "只删这一场不会让它们对不上。"
                + "下一步：确定要删就点「删除」，想留着就点「取消」。")
    }
}

/// 文件删除的接缝。**唯一目的是可测性**——有了它，「删不掉时要如实报告」
/// 这条路径才能在不真的把文件锁住的情况下被测到。
public protocol FileRemoving: Sendable {
    func fileExists(at url: URL) -> Bool
    func remove(at url: URL) throws
}

public struct SystemFileRemover: FileRemoving {
    public init() {}
    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    public func remove(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// 删一条训练记录。
@MainActor
public final class SessionDeleter {
    private let directory: DataDirectory
    private let store: StateStore
    private let fileRemover: any FileRemoving

    public init(directory: DataDirectory, store: StateStore,
                fileRemover: any FileRemoving = SystemFileRemover()) {
        self.directory = directory
        self.store = store
        self.fileRemover = fileRemover
    }

    /// 删除。**永不抛错**：返回 nil 表示一切顺利，返回字符串是给用户看的中文说明。
    ///
    /// 顺序刻意是「先删记录，再删文件」：文件删不掉不该拦住记录本身的删除，
    /// 否则用户会卡在一条删不掉的记录上，而他真正想做的只是让它从列表里消失。
    @discardableResult
    public func delete(_ session: PracticeSession) -> String? {
        do {
            try store.mutate { state in
                state.sessions.removeAll { $0.id == session.id }
                if state.currentSession?.id == session.id { state.currentSession = nil }
            }
        } catch {
            return "没能删掉这条训练记录：\(error.localizedDescription) "
                + "下一步：确认数据目录可写（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后重试。这一条仍然在列表里，什么都没被改动。"
        }

        var failed: [String] = []
        for relativePath in SessionDeletion.plan(for: session).relativePaths {
            let url = directory.root.appending(path: relativePath)
            // 文件本来就不在（用户手工删过、拷目录时漏了）不是错误
            guard fileRemover.fileExists(at: url) else { continue }
            do { try fileRemover.remove(at: url) } catch { failed.append(relativePath) }
        }

        guard !failed.isEmpty else { return nil }
        // 静默吞掉的话，用户永远不知道磁盘上还躺着这些东西。
        return "训练记录已经删掉了，但有 \(failed.count) 个文件没能删除："
            + failed.joined(separator: "、") + "。"
            + "下一步：到数据目录里手动删掉它们（默认在「资源库 › Application Support › "
            + "IELTS Speaking Coach」）；留着不影响使用，只是白占磁盘。"
    }
}
```

**`HistoryView` 的改动（只给验收要求）：**

- 每一行有一个删除入口（右键菜单或行尾的按钮，二选一，不要两个都做）
- 点了**必须先弹确认对话框**，标题写清是哪一场（日期 + 题目），正文原样显示 `SessionDeletionPlan.confirmationText`
- 确认按钮用 `.destructive` 角色；默认焦点在「取消」上
- 删完调 `app.reload()`
- `delete` 返回非 nil 时，把那段中文完整显示出来（可选中复制），用 `Palette.warning`，**不要用一闪而过的 toast**——用户来不及读

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SessionDeleterTests`
Expected: PASS（8 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `plan(for:)` 里 `if !session.recordingPath.isEmpty` 那一块整个删掉 | `testDeletingAlsoRemovesTheRecordingAndTheReport`、`testTheConfirmationSpellsOutEveryFileItWillDelete` |
| `delete` 里 `guard !failed.isEmpty else { return nil }` 改成 `return nil` | `testAFileThatCouldNotBeDeletedIsReportedWithItsPath` |
| `delete` 里 `catch { failed.append(relativePath) }` 改成 `catch { }` | 同上 |
| `plan(for:)` 的 `confirmationText` 里「已经归进错题本和词汇本的内容不会跟着删」那句删掉 | `testTheConfirmationSpellsOutEveryFileItWillDelete` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/History/SessionDeleter.swift \
        Sources/IELTSCoachUI/History/HistoryView.swift \
        Tests/IELTSCoachUITests/SessionDeleterTests.swift
git commit -m "feat(ui): 单条训练记录删除，连带清理录音与复盘报告"
```

---

## Task 11: 「重新导入待处理的复盘」（决策 2）

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Review/PendingReviewViewModel.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Review/PendingReviewInboxView.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Review/ReviewReportView.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/PendingReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `PendingReviewStore`（`list` / `read` / `markImported` / `delete`）、`PendingReviewEntry`、`ReviewParser.parse`、`ReviewArchiver.archive`、`ArchiveOutcome`、`StateStore.mutate` / `load`、`DataDirectory`、`JSONValue`
- Produces:
  - `public struct PendingReviewRow: Equatable, Identifiable, Sendable`，含 `id`、`entry: PendingReviewEntry`、`sessionID`、`timeText`、`questionText`、`sizeText`
  - `public enum PendingReviewRowBuilder`，含 `static func rows(entries: [PendingReviewEntry], state: CoachState, timeZone: TimeZone) -> [PendingReviewRow]`
  - `@MainActor @Observable public final class PendingReviewViewModel`，含 `init(directory:store:timeZone:now:)`、`rows`、`notice`、`isEmpty`、`refresh()`、`reimport(_:)`、`delete(_:)`、`rawText(of:) -> String?`
  - `public struct PendingReviewInboxView: View`

### 为什么这件事必须做

成品标准第 2 条是「全程不需要打开终端」，而现在复盘自动取回失败时，把原文补进库的**唯一途径是终端里跑 `coach reimport`**。硬标准第 7 条（失败不丢数据）成立了，第 2 条却在最需要它的时候不成立。

### 两条必须做对的事

1. **导入成功后必须打 `.imported` 标记。** `ReviewArchiver` 对「同一 session 重复归档」只在 `sourceSessionIds` 上去重，`IssueRecord.occurrences` 会跟着重复调用继续累加。不打标记的话，用户手一抖点两次，「这句话说错了几次」就悄悄失真了——这正是本项目最忌讳的静默错误。
2. **题目查不到不许留空。** `pending-reviews/` 里的文件名只有会话编号，题目要靠编号回查 `state.sessions`。查不到（那一场根本没能写进记录）时明说，而不是显示一个空格。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PendingReviewViewModelTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class PendingReviewViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private let utc = TimeZone(identifier: "UTC")!
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private static let goodReview = #"""
    <<<IELTS_REVIEW_JSON:sync-1>>>
    {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
    "why_it_matters":"very 不能修饰动词"}],
    "vocabulary":[{"basic":"good","better":"decent","collocation":"a decent meal","priority":"high"}]}
    <<<END_IELTS_REVIEW_JSON:sync-1>>>
    """#

    private func model() -> PendingReviewViewModel {
        PendingReviewViewModel(directory: directory, store: store, timeZone: utc,
                               now: { self.fixedNow })
    }

    private func seedSession(_ id: String, questionId: String = "q1") throws {
        try store.mutate { state in
            state.questions = [Question(id: questionId, part: 1, topic: "Home",
                                        prompt: "Do you live in a house or a flat?")]
            state.sessions = [PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                                              startedAt: "2026-08-06T10:00:00Z",
                                              endedAt: "2026-08-06T10:20:00Z", goal: "",
                                              transcript: [], reportPath: "", recordingPath: "")]
        }
    }

    // MARK: - 列表

    func testAnEmptyInboxIsEmptyNotAnError() {
        let model = self.model()
        model.refresh()
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.notice)
    }

    func testARowShowsTimeQuestionAndSize() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()

        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(row.sessionID, "2026-08-06-001")
        XCTAssertEqual(row.questionText, "Do you live in a house or a flat?")
        XCTAssertFalse(row.timeText.isEmpty)
        XCTAssertTrue(row.sizeText.contains("KB") || row.sizeText.contains("字节"))
    }

    /// 那一场根本没能写进训练记录时，题目无从查起。**明说，不要留空。**
    func testAnUnknownQuestionIsSpelledOut() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "sync-1785940167",
                                         directory: directory)
        let model = self.model()
        model.refresh()

        let row = try XCTUnwrap(model.rows.first)
        XCTAssertTrue(row.questionText.contains("查不到"))
        XCTAssertFalse(row.questionText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testTheRawTextCanBeReadForInspection() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(model.rawText(of: row), Self.goodReview)
    }

    // MARK: - 重新导入

    func testReimportingArchivesTheReviewAndLinksTheReport() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let saved = try store.load()
        XCTAssertEqual(saved.issues.count, 1, "错题必须真的归进去")
        XCTAssertEqual(saved.vocabulary.count, 1)
        XCTAssertEqual(saved.sessions.first?.reportPath, "reports/2026-08-06-001.json")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.reportsDirectory.appending(path: "2026-08-06-001.json").path))
        XCTAssertTrue(model.isEmpty, "导入成功之后这一条就该从待处理列表里消失")
    }

    /// **本任务最重要的一条。** 不打 .imported 标记的话，用户手一抖点两次，
    /// `IssueRecord.occurrences` 就悄悄多加了一次，「这句话说错了几次」永久失真。
    func testAnImportedFileIsMarkedSoItCannotBeImportedTwice() throws {
        try seedSession("2026-08-06-001")
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "2026-08-06-001",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        XCTAssertEqual(try store.load().issues.first?.occurrences, 1)
        model.refresh()
        XCTAssertTrue(model.rows.isEmpty)

        let files = try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(files, ["2026-08-06-001.txt.imported"],
                       "原文要留着（用户可能想回头看），但不能再被扫到")
    }

    func testAReviewThatStillCannotBeParsedLeavesTheFileAlone() throws {
        _ = try PendingReviewStore.write(rawText: "这不是一份复盘", sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let notice = try XCTUnwrap(model.notice)
        XCTAssertTrue(notice.contains("下一步"))
        XCTAssertFalse(model.rows.isEmpty, "导不进去的那条要留在列表里，让用户能看原文、能删")
        XCTAssertEqual(try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path),
                       ["s1.txt"], "解析失败时一个字都不许动那个文件")
    }

    /// 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
    /// **静默的 0 是本项目已知最危险的失败形态。**
    func testArchivingNothingIsReportedLoudly() throws {
        let wrongFieldNames = #"""
        <<<IELTS_REVIEW_JSON:x>>>
        {"must_correct":[{"issue":"very like","examples":["I very like it."],"fix":"really like"}]}
        <<<END_IELTS_REVIEW_JSON:x>>>
        """#
        _ = try PendingReviewStore.write(rawText: wrongFieldNames, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.reimport(try XCTUnwrap(model.rows.first))

        let notice = try XCTUnwrap(model.notice)
        XCTAssertTrue(notice.contains("must_correct"))
        XCTAssertTrue(notice.contains("一条都没"))
        XCTAssertTrue(notice.contains("下一步"))
    }

    // MARK: - 删除

    func testDeletingRemovesTheFileForGood() throws {
        _ = try PendingReviewStore.write(rawText: Self.goodReview, sessionID: "s1",
                                         directory: directory)
        let model = self.model()
        model.refresh()
        model.delete(try XCTUnwrap(model.rows.first))

        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(try FileManager.default
            .contentsOfDirectory(atPath: directory.pendingReviewsDirectory.path).isEmpty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PendingReviewViewModelTests`
Expected: 编译失败 —— `PendingReviewViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Review/PendingReviewViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore
import Observation

public struct PendingReviewRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let entry: PendingReviewEntry
    public let sessionID: String
    public let timeText: String
    /// 这份复盘属于哪道题。查不到时是一句中文说明，**不会是空字符串**。
    public let questionText: String
    public let sizeText: String
}

/// 把「文件清单」和「训练记录」拼成界面要显示的行。**纯函数，所以能测。**
public enum PendingReviewRowBuilder {
    public static func rows(entries: [PendingReviewEntry], state: CoachState,
                            timeZone: TimeZone) -> [PendingReviewRow] {
        let sessions = Dictionary(state.sessions.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let questions = Dictionary(state.questions.map { ($0.id, $0) },
                                   uniquingKeysWith: { first, _ in first })

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return entries.map { entry in
            // 文件名可能是 "2026-08-06-001-2.txt"（同一场的第二份原文），
            // 先按完整编号找，找不到再去掉 "-N" 后缀找一次。
            let session = sessions[entry.sessionID] ?? sessions[trimmedCopySuffix(entry.sessionID)]
            let questionText: String
            if let session, let question = questions[session.questionId] {
                questionText = question.prompt
            } else if let session {
                questionText = "这一场练的题目已经不在题库里了（id：\(session.questionId)）。"
            } else {
                questionText = "查不到这份复盘属于哪一场练习"
                    + "（编号「\(entry.sessionID)」不在训练记录里，多半是那次练习没能存进去）。"
            }

            return PendingReviewRow(
                id: entry.id, entry: entry, sessionID: entry.sessionID,
                timeText: formatter.string(from: entry.modifiedAt),
                questionText: questionText,
                sizeText: sizeText(entry.byteCount))
        }
    }

    private static func trimmedCopySuffix(_ sessionID: String) -> String {
        guard let dash = sessionID.lastIndex(of: "-"),
              Int(sessionID[sessionID.index(after: dash)...]) != nil else { return sessionID }
        return String(sessionID[..<dash])
    }

    static func sizeText(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) 字节"
                     : String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
}

/// 「重新导入待处理的复盘」。
///
/// **为什么它必须存在**（决策 2）：复盘自动取回失败时，原文确实落在 `pending-reviews/`
/// 里没丢，但把它补进库的唯一途径原本是终端里跑 `coach reimport`。成品标准第 2 条是
/// 「全程不需要打开终端」，而**出错恰恰是最需要它成立的时候**。
@MainActor
@Observable
public final class PendingReviewViewModel {
    private let directory: DataDirectory
    private let store: StateStore
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    public private(set) var rows: [PendingReviewRow] = []
    /// 给用户看的中文说明（成功或失败）。**非 nil 时界面必须显示它。**
    public private(set) var notice: String?

    public init(directory: DataDirectory, store: StateStore,
                timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.store = store
        self.timeZone = timeZone
        self.now = now
    }

    public var isEmpty: Bool { rows.isEmpty }

    public func refresh() {
        do {
            let entries = try PendingReviewStore.list(directory: directory)
            let state = try store.load()
            rows = PendingReviewRowBuilder.rows(entries: entries, state: state, timeZone: timeZone)
        } catch {
            rows = []
            notice = "没能列出待处理的复盘：\(error.localizedDescription) "
                + "下一步：确认数据目录能读（默认在「资源库 › Application Support › "
                + "IELTS Speaking Coach」），然后点「刷新」重试。"
        }
    }

    public func rawText(of row: PendingReviewRow) -> String? {
        do { return try PendingReviewStore.read(row.entry) } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    public func reimport(_ row: PendingReviewRow) {
        let raw: String
        do { raw = try PendingReviewStore.read(row.entry) } catch {
            notice = error.localizedDescription
            return
        }

        let report: JSONValue
        do {
            report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
        } catch {
            // 解析失败时**一个字都不许动那个文件**——它是用户练了半小时换来的东西。
            notice = "「\(row.sessionID)」还是解析不了：\(error.localizedDescription) "
                + "下一步：点「查看原文」看看 ChatGPT 到底输出了什么；"
                + "若确实不是标准格式，回 ChatGPT 里让它按要求重新输出一次，"
                + "复制之后新练一场时会自动落盘。这个文件原样留着，没有被改动。"
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        let reportRelativePath = "reports/\(row.sessionID).json"
        do {
            try directory.createIfNeeded()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(row.sessionID).json"),
                       options: .atomic)

            let outcome = try store.mutate { state -> ArchiveOutcome in
                let questionID = state.sessions.first { $0.id == row.sessionID }?.questionId ?? ""
                let result = ReviewArchiver.archive(report: report, into: state,
                                                    sessionID: row.sessionID,
                                                    questionID: questionID, at: timestamp)
                state = result.state
                if let index = state.sessions.firstIndex(where: { $0.id == row.sessionID }) {
                    state.sessions[index].reportPath = reportRelativePath
                }
                return result
            }

            // 打标记必须在归档成功之后。归档失败还打了标记，用户就再也点不到它了。
            try PendingReviewStore.markImported(row.entry)

            if outcome.skipped.isEmpty {
                notice = "「\(row.sessionID)」已经重新入库。"
                    + "下一步：到上面的复盘列表里就能看到它了。"
            } else {
                // 归档 0 条不等于没错题——更可能是字段名对不上（spec 2.3.8）。
                // 静默的 0 是本项目已知最危险的失败形态。
                notice = "「\(row.sessionID)」入库了，但复盘里的 "
                    + outcome.skipped.joined(separator: "、")
                    + " 一条都没能归进档案。这通常意味着 ChatGPT 用的字段名和本工具读的对不上。"
                    + "下一步：原文已经改名成 \(row.entry.fileName)\(PendingReviewStore.importedSuffix) "
                    + "留在 pending-reviews 目录里，可以打开对照着看；"
                    + "若想重来，把 .imported 后缀去掉它就会重新出现在这个列表里。"
            }
        } catch {
            notice = "「\(row.sessionID)」解析成功了，但入库时出错：\(error.localizedDescription) "
                + "下一步：确认数据目录可写后再点一次「重新导入」；原文没有被改动，不会丢。"
        }
        refresh()
    }

    public func delete(_ row: PendingReviewRow) {
        do {
            try PendingReviewStore.delete(row.entry)
            notice = "已经删掉「\(row.entry.fileName)」。下一步：无需其他操作。"
        } catch {
            notice = "没能删掉「\(row.entry.fileName)」：\(error.localizedDescription) "
                + "下一步：到数据目录的 pending-reviews 里手动删除。"
        }
        refresh()
    }
}
```

**`PendingReviewInboxView` 与 `ReviewReportView` 的改动（只给验收要求）：**

| # | 要求 |
|---|---|
| 1 | `ReviewReportView` 上加一个入口，标题**逐字**是「重新导入待处理的复盘」，并显示待处理条数（如「重新导入待处理的复盘（2）」）。条数为 0 时**入口仍然要在**，点开显示空状态——藏起来的话，用户出事时根本找不到它 |
| 2 | 入口不得是主行动（`PrimaryActionCard` 每页只能有一个，那个位置留给复盘本身），用次一级的按钮样式 |
| 3 | 列表每行显示 `timeText` / `questionText` / `sizeText` 三项，外加三个操作：**重新导入**、**查看原文**、**删除** |
| 4 | 「查看原文」把 `rawText(of:)` 的结果显示在一个可滚动、可选中复制的区域里；返回 nil 时显示 `notice` |
| 5 | 「删除」要二次确认，文案说明「删掉之后这份复盘原文就没了，无法恢复」 |
| 6 | `notice` 非 nil 时完整显示，可选中复制，**不要用一闪而过的 toast** |
| 7 | 空状态用 `EmptyStateView`：「没有待处理的复盘。」/「复盘自动取回失败时，原文会先存到这里，然后就能在这一页把它补进库。」/ 不需要按钮 |
| 8 | 视图里不得出现字面颜色、字号、圆角 |

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PendingReviewViewModelTests`
Expected: PASS（9 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `reimport` 里的 `try PendingReviewStore.markImported(row.entry)` 删掉 | `testAnImportedFileIsMarkedSoItCannotBeImportedTwice` |
| 把 `markImported` 挪到 `store.mutate` **之前** | `testAReviewThatStillCannotBeParsedLeavesTheFileAlone`（解析失败那条要先改成也走到这一步才测得出；若测不出，改成手工核对「归档抛错时文件仍在」） |
| `reimport` 里 `if outcome.skipped.isEmpty` 的 else 分支删掉 | `testArchivingNothingIsReportedLoudly` |
| `PendingReviewRowBuilder` 里 `questionText = "查不到这份复盘属于哪一场练习…"` 改成 `""` | `testAnUnknownQuestionIsSpelledOut` |
| 解析失败那一支里加上 `try? PendingReviewStore.markImported(row.entry)` | `testAReviewThatStillCannotBeParsedLeavesTheFileAlone` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Review/PendingReviewViewModel.swift \
        Sources/IELTSCoachUI/Review/PendingReviewInboxView.swift \
        Sources/IELTSCoachUI/Review/ReviewReportView.swift \
        Tests/IELTSCoachUITests/PendingReviewViewModelTests.swift
git commit -m "feat(ui): 界面里重新导入待处理的复盘，不再把用户推回终端"
```

---

## Task 12: 让命令行跟上（会话编号与会话落库）

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/coach/PracticeCommand.swift`

**Interfaces:**
- Consumes: `SessionID.next`、`PendingReviewStore.write`、`StateStore.mutate`、`PracticeSession`
- Produces: 无新公开类型

**为什么必须做：** 决策 1 说「新产生的一律用新形状」。命令行现在写的是 `ISO8601DateFormatter().string(from: Date())`（第 115 行）。不改的话，同一台机器上界面练的和命令行练的会是两种编号，Phase 7 的统计会走两条不同的解析路径，Phase 9 的 `save_session_review` 也会对其中一种报「非法编号」。

**为什么只改这几处：** `coach practice` 现在跑得好好的，Phase 2 验收过。改多了会把 Phase 2 的验收拖进来重做。

- [ ] **Step 1: 改会话编号的产生方式**

把这一行：

```swift
            let sessionID = ISO8601DateFormatter().string(from: Date())
```

改成：

```swift
            // 决策 1：会话编号统一成 YYYY-MM-DD-NNN。旧的 ISO8601 编号仍然读得进来
            //（SessionID.validated 白名单里留了冒号），但新产生的一律用新形状——
            // 否则界面练的和命令行练的会是两种编号，统计与 MCP 都要各走一条路。
            let existingSessions = (try? store.load())?.sessions ?? []
            let sessionID = SessionID.next(existing: existingSessions, now: Date(),
                                           timeZone: .current)
```

- [ ] **Step 2: 落盘改用 `PendingReviewStore`，文件名改成会话编号**

把这三行：

```swift
            let pendingPath = directory.pendingReviewsDirectory.appending(path: "\(requestID).txt")
            try raw.write(to: pendingPath, atomically: true, encoding: .utf8)
            print("▶︎ 复盘原文已存到 \(pendingPath.path)")
```

改成：

```swift
            // 文件名用会话编号而不是 requestID：coach reimport 与界面里的
            // 「重新导入待处理的复盘」都从文件名取 sessionID，用同一个值才能保证
            // 「当场归档」和「事后补导」落进档案的编号一致。
            let pendingPath = try PendingReviewStore.write(rawText: raw, sessionID: sessionID,
                                                           directory: directory)
            print("▶︎ 复盘原文已存到 \(pendingPath.path)")
```

**上面那句 `try directory.createIfNeeded()` 可以留着**（`PendingReviewStore.write` 内部也会建目录，重复调用无害）。

- [ ] **Step 3: 归档时往 `state.sessions` 里落一条**

在既有的 `store.mutate { ... }` 块里，`state = result.state` 之后追加：

```swift
                // Phase 4：命令行也要留下训练记录，否则界面上的「训练记录」页
                // 看不到用命令行练的那些场次。字段与 PracticeRunner 落的那条保持一致。
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let session = PracticeSession(
                    id: sessionID, questionId: question.id, focusPart: focusPart,
                    startedAt: timestamp, endedAt: timestamp, goal: goal,
                    transcript: [],                       // 命令行不采逐字稿
                    reportPath: "reports/\(sessionID).json", recordingPath: "")
                if let index = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                    state.sessions[index] = session
                } else {
                    state.sessions.append(session)
                }
```

并在 `store.mutate` **之前**把解析后的复盘写进 `reports/`：

```swift
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report)
                .write(to: directory.reportsDirectory.appending(path: "\(sessionID).json"),
                       options: .atomic)
```

> **`startedAt` 用的是归档时刻，不是真正的开始时刻。** 命令行没有记录开始时间的地方，
> 而为此改造 `PracticeCommand` 的结构不值得——界面才是主路径。
> 这个近似只影响「本周开口时长」这类统计对命令行场次的精度，
> **注释里要写明这一点**，别让后来的人以为它是准的。

- [ ] **Step 4: 验证**

Run: `swift build`
Expected: 编译通过

Run: `swift test`
Expected: 全绿（`PracticeCommand` 本身没有单元测试，本步骤靠编译 + Task 13 的真机验收把关）

**不要在这里造一场假的 `coach practice` 运行来「验证」。** 它要驱动真实的 ChatGPT，属于 Task 13 用户亲自做的事。

- [ ] **Step 5: 提交**

```bash
git add Sources/coach/PracticeCommand.swift
git commit -m "feat(cli): 命令行也用新的会话编号并落训练记录"
```

---

## Task 13: 真机验收（**人工，不可由子代理代劳**）

**Files:** 无代码改动。产出 `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/docs/phase4-acceptance.md`

前面所有测试跑的都是「数据变换对不对」，证明不了「从 ChatGPT 那棵真实的 AX 树里到底捞出了什么」。**本阶段最大的未知——说话人判别在语音会话里是否成立——只能靠这一步回答。**

- [ ] **Step 1: 打包并打开**

```bash
cd ~/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

若提示需要重新授权辅助功能，说明签名不稳定，**停下来报告**——那是 Phase 3 的验收项，不该在这里翻车。

- [ ] **Step 2: 真练一场（本阶段的成败判据）**

**把终端关掉**，只用界面：

1. 到「训练记录」页，确认「记录对话逐字稿」开关是**开着**的（默认应该就是开的）
2. 回「今日训练」，点「开始」，真的对着 ChatGPT 练一场（Part 1 即可，六到八分钟）
3. 练习过程中留意练习面板上的「已记录 N 条对话」有没有在涨
4. 点「我练完了」，等它取回复盘

- [ ] **Step 3: 逐条核对逐字稿（成品标准第 5 条）**

到「训练记录」页点开刚才那一场，**对照 ChatGPT 窗口逐条核**，把下面每一项的实际结果写进验收报告：

| 要核的 | 怎么判断 |
|---|---|
| **考官问过的每一个问题都能找到** | 把 ChatGPT 窗口里考官的每一句提问，在逐字稿里挨个找。**这是成品标准第 5 条，一句都不能少** |
| 自己说的话在不在 | 语音转文字本身可能不准，那不是本工具的问题；要核的是「有没有这一条」，不是「字对不对」 |
| **说话人判对了没有** | 考官的话标成考官、自己的话标成自己。若大量显示成「说不准是谁说的」，把实际比例记下来 |
| 有没有重复 | 同一句话出现两遍及以上 = 拼接规则有问题，把重复的原文抄进报告 |
| 有没有混进不是对话的东西 | 侧边栏会话名、按钮说明、考官提示词的片段。**把混进来的原文一字不差地抄进报告** |
| 顺序对不对 | 是不是按实际发生顺序排的 |
| 完整性提示 | 若显示了「本次逐字稿可能不完整…」，把整句抄下来 |

> **预期这一步会发现问题，而且需要至少一轮调整。** ROADMAP 第 6 节把「逐字稿拼接的正确性」
> 列成已知风险，写着「需真机多轮验证」。发现问题**不算失败**，把现象记清楚才是这一步的价值。
>
> 按现象定位该改哪儿：
>
> | 现象 | 改哪儿 |
> |---|---|
> | 说话人大面积判不出 / 判反 | `ChatGPTLabels.speakerMarker`（Task 4）——**只改这一个函数** |
> | 同一句话重复出现 | `TranscriptAssembler` 的合并规则（Task 3） |
> | 混进侧边栏、按钮文字 | `AXTranscriptSampler` 的过滤（Task 4），或把它们纳入背景板 |
> | 缺了考官的某个问题 | 先看是不是被当成背景板滤掉了（Task 3 的 `seedBaseline`） |
>
> **改完之后必须给那个现象补一条测试**，然后再练一场复验。

- [ ] **Step 4: 核对训练记录页本身**

| 看什么 | 判据 |
|---|---|
| 按月分组 | 月份标题对不对、新的在不在最前面 |
| 每行五项 | 日期 / Part / 题目 / 对话轮数 / 复盘状态，一项都不能缺 |
| 数字不抖 | 「12 条对话」变成「8 条对话」时整行不该跳动（等宽数字） |
| 用命令行练过的旧记录 | 若 `state.json` 里本来就有 ISO8601 编号的会话，它们能不能正常显示、归到正确的月份 |
| 空状态 | 临时把 `IELTS_SPEAKING_DATA_DIR` 指到一个空目录跑一次，看空状态文案说没说清「下一步」 |

- [ ] **Step 5: 核对开关会不会掉**

1. 把「记录对话逐字稿」关掉
2. **完全退出 App**（⌘Q，不是关窗口），再打开
3. 开关必须还是关着的
4. 再练一场（可以很短），确认这一场的 `transcript` 是空的、且**没有**弹出任何「逐字稿不完整」的警告
5. 把开关打开，恢复默认

**第 3 步失败的话，多半是 `AppState.setTranscriptEnabled` 没写进盘，或 `CoachSettings` 的 `CodingKeys` 漏了字段。**

- [ ] **Step 6: 核对单条删除（决策 4）**

1. 挑一条有复盘的记录，先记下 `reports/` 里对应的文件名
2. 点删除，读确认对话框——**它有没有说清会删掉哪些东西、什么不会删**
3. 确认删除
4. 到数据目录看 `reports/<id>.json` 是不是真的没了
5. 到「复盘报告」页确认这一场也不再列出
6. 到「问题档案」（还是占位页也没关系）或直接看 `state.json`，确认 `issues` / `vocabulary` **没有**跟着少

- [ ] **Step 7: 核对「重新导入待处理的复盘」（决策 2）**

**人为制造一次失败**，这是成品标准第 7 条与第 2 条的联合验收：

1. 再练一场（可以很短，两三个问题就行）
2. 点「我练完了」之后，**在 ChatGPT 输出复盘的过程中把 ChatGPT 窗口关掉**（或断网）
3. App 应当停在失败态，并显示一段中文：说明发生了什么 + 指向「重新导入待处理的复盘」
4. **确认这段文案里没有出现「终端」「命令行」「coach reimport」**——出现了就是决策 2 没落实
5. 到「复盘报告」页点「重新导入待处理的复盘」，看列表里有没有这一条，时间 / 题目 / 字节数对不对
6. 点「查看原文」，确认能看到 ChatGPT 当时输出了什么
7. 若原文是完整的，点「重新导入」，确认错题本与词汇本的数字从原来的值变大
8. 再点一次刷新，确认这一条已经从列表里消失（`.imported` 标记生效）

- [ ] **Step 8: 记录并提交**

把每一项的实际结果写进 `docs/phase4-acceptance.md`，含原文摘录。**包括不好的部分**——「哪里让我不想用」这类信息只有你有（成品标准第 5 节）。

特别要写清楚的三件事：

1. **说话人判别在语音会话里到底成不成立**（这是本阶段唯一没法靠测试回答的问题）
2. **逐字稿里混进了哪些不是对话的东西**（原文照抄，下一轮据此收紧过滤）
3. **考官问过的问题有没有漏**（成品标准第 5 条能不能勾）

```bash
git add docs/phase4-acceptance.md
git commit -m "docs: Phase 4 真机验收结果"
```

---

## Phase 4 完成标准

- [ ] `swift test` 全绿，且总耗时仍在 2 秒以内（Phase 3 Task 10 定的线，不要让新测试把它拖回去）
- [ ] **每一场练习都会在 `state.sessions` 里留下一条 `PracticeSession`**，含 `startedAt` / `endedAt` / `questionId` / `focusPart` / `goal` / `transcript` / `reportPath`
- [ ] `PracticeRunner.finishedSessionID` 在归档成功之后（而不是之前）被赋值
- [ ] 会话编号是 `YYYY-MM-DD-NNN`；旧的 ISO8601 编号仍然读得进来、显示得出来
- [ ] `reports/<id>.json` 真的被写出来了，且 `PracticeSession.reportPath` 是**相对路径**
- [ ] **逐字稿拼接去重的六种情况全部有测试**：片段递增、乱序到达、完全重复、消息边界、说话人切换、采样失败
- [ ] **采样失败不中断练习**，且练完会如实告知逐字稿可能不完整
- [ ] 「训练记录」页按月分组，每条显示日期 / Part / 题目 / 对话轮数 / 复盘状态
- [ ] 点开一条能看到完整逐字稿；没有逐字稿时有中文说明而不是空白
- [ ] 单条删除可用，且**连带删掉录音与复盘报告文件**，确认框逐条列明
- [ ] `.history` 已标进 `SidebarItem.isImplemented`，且 `NavigationTests` 用集合相等断言守着
- [ ] 「记录对话逐字稿」开关默认开、能关、退出 App 再打开不掉
- [ ] 「复盘报告」页有「重新导入待处理的复盘」入口，能列出、能看原文、能重试、能删
- [ ] **复盘取回失败时的文案里不出现「终端」「命令行」「coach reimport」**
- [ ] `coach practice` 也用新的会话编号并落训练记录
- [ ] 每个关键任务的突变验证都做过，且做完改回、全绿
- [ ] `docs/phase4-acceptance.md` 已写，且第 3 步「逐条核对逐字稿」的结果是真核过的

达成后进 Phase 5：录音与回听。

**Phase 4 打通之后，成品标准里原本达不成的三条同时具备了条件：**

| 条 | 之前 | 现在 |
|---|---|---|
| **5**（逐字稿里能找到考官问过的每一个问题）| ❌ 完全没有 | ✅ 本阶段交付（真机核对见 Task 13 Step 3）|
| **6**（能听自己那次的录音）| ❌ 回听入口无处可挂 | ⏳ 挂点已就位（`HistoryRow.hasRecording`），录音本身由 Phase 5 做 |
| **2 + 8**（不用终端；错误信息的下一步要能照着做）| ⚠️ 出错时把用户推回终端 | ✅ 决策 2 落地 |

---

## 写给后续阶段实现者的话

Phase 4 动了几处别的计划已经写好的地方。**接手时先看这一节，能省掉一轮返工。**

### 给 Phase 5（录音与回听）

| 事 | 说明 |
|---|---|
| **P4-1 / P4-2 都已满足** | `Sources/IELTSCoachUI/History/HistoryView.swift` 与 `HistoryViewModel.swift` 已存在；`PracticeRunner` 真的会往 `state.sessions` 里落记录。Task 9 可以照常做 |
| **`PracticeRunner` 的签名是 `directory:` 不是 `store:`** | Phase 5 Task 7 的测试里写的是 `PracticeRunner(bridge:pasteboard:store:recording:)`。实际是 `(bridge:pasteboard:directory:transcript:now:)`，store 由它自己从 directory 派生。**传 store 而不传 directory 会让报告和待处理复盘写进用户真实数据目录**，测试看起来通过、实际污染了用户数据。Phase 5 计划已写明「以实际签名为准」 |
| **`recording:` 参数加在哪儿** | 加在 `now:` 之前或之后都行，只要带默认值 nil。加完之后 `PracticeRunner` 的初始化参数是五个，全都有默认值（除了 bridge 与 pasteboard） |
| **`recordingPath` 往哪儿写** | `PracticeRunner` 里有一个私有方法 `upsertSession(id:reportPath:)`。给它加一个 `recordingPath: String?` 参数，与 `reportPath` 同样处理（非 nil 才写）。**不要另写一套会话落库逻辑** |
| **录音删除与训练记录删除的关系** | Phase 4 的 `SessionDeleter` 已经会删录音文件（决策 4）。Phase 5 的 `RecordingPlaybackViewModel.delete()` 删的是「只删录音、保留记录」，两者不冲突，但**两个删除入口都要在界面上说清各自删了什么** |
| **`.missing` 状态** | `HistoryRow.hasRecording` 只看 `recordingPath` 非空，不看文件在不在。文件不在时的 `.missing` 提示是 Phase 5 Task 9 的活，照它自己的计划做 |

### 给 Phase 6（复训中心）

| 事 | 说明 |
|---|---|
| **P2 / P3 都已满足** | `sessions.append` 与 `finishedSessionID` 都在 `Sources/IELTSCoachUI/Session/PracticeRunner.swift` 里。P3 的「补法」不需要做了 |
| **P4（逐字稿）也满足了** | `PracticeSession.transcript` 里有内容，`role` 取 `"user"` / `"assistant"` / **`"unknown"`**。`RetrainingEvidenceBuilder` 里 `$0.role == "user"` 那个筛选照旧能用，`unknown` 会被自然跳过——这是可接受的降级，不要改成把 unknown 也算成学员 |
| **决策 6 归你落地** | 复训目标 `label` 为空时回落成 `targetKey` 照常开练。Phase 6 本来就是这么设计的，保持即可 |
| **`PracticeSession` 加字段时当心** | Phase 6 要给它加 retraining 字段并重写 memberwise init。`PracticeRunner.upsertSession` 与 `coach practice` 都在构造 `PracticeSession`，新参数**必须带默认值**，否则这两处会编译不过 |

### 给 Phase 7（问题档案、词汇本、统计）

| 事 | 说明 |
|---|---|
| **依赖 1 已满足** | `state.sessions` 里有真实记录了，首页四格不会再恒为 0。Task 11 的验收报告里不用再写「等 Phase 4 接上后复验」 |
| **依赖 2 已统一** | 新记录的编号是 `YYYY-MM-DD-NNN`，`startedAt` 也是填好的，`SessionTimeline` 会走更精确的那条路。但**旧的 ISO8601 编号仍然存在**（用户已有数据），`CoachTime.parseDayPrefix` 那条兜底路径不要删 |
| **⚠️ 整体替换 `CoachSettings` 时别抄丢 `transcriptEnabled`** | Task 1 会把 `CoachSettings` 整体替换成带 `weeklyGoal` 的版本。**替换前先跑 `grep -n "public var" Sources/IELTSCoachCore/Model/CoachState.swift`**，把 `transcriptEnabled`（连同 `CodingKeys` 里那一项和手写 `init(from:)` 里那一行）一并抄进去。抄丢了编译照样过，只是用户关掉的逐字稿开关会在下一次写盘时被默认值悄悄盖回开——`TranscriptSettingsTests` 会变红，**看到它红了不要改测试，去把字段补回来** |

### 给 Phase 8（学习计划与练习路线）

- 同样的 `CoachSettings` 整体替换提醒：`transcriptEnabled` 与 Phase 7 的 `weeklyGoal` **两个都要保留**
- 决策 6：复训目标 `label` 为空时**回落成 `targetKey` 照常开练**，不要用「拒绝并说明下一步」

### 给 Phase 9（MCP + Codex 插件）

| 它计划要建的 | 现状 |
|---|---|
| `Sources/IELTSCoachCore/Model/SessionID.swift` | **Phase 4 已建。** `next` 与计划里那份一致；`validated` 的白名单**多了 `:` 和 `+`**——那正是 Phase 9 计划里那个 ⚠️ 块给的两条出路中的 (a)，决策 1 已经选定并落地。**不要新建、不要把冒号删掉** |
| `CoachError.invalidSessionID` | **Phase 4 已加。** |
| `Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`（Task 3） | **Phase 4 已建，`write` 与计划里那份逐字一致**，另外多了 `list` / `read` / `markImported` / `delete`。跑一次 `swift test --filter PendingReviewStoreTests` 确认全绿即可，直接进下一个任务 |
| `save_session_review` 里的会话 upsert | Phase 4 的 `PracticeRunner` 用的是同样的 upsert 规则（按 id 找，有就替换、没有就追加，并清掉同 id 的 `currentSession`）。两边保持一致，不要一边 append 一边 upsert |
| 错误文案「或在终端运行 coach reimport」 | 可以保留（MCP 的使用者本来就在终端里），但**建议同时提一句「也可以在 App 的复盘报告页用『重新导入待处理的复盘』」**，与决策 2 一致 |

### 给 Phase 10（打包与分发）

| 事 | 说明 |
|---|---|
| **设置合并（决策 7）** | 「记录对话逐字稿」开关本阶段放在**训练记录页顶部**，写入口是 `AppState.setTranscriptEnabled(_:)`。**Phase 10 Task 16 已把这两样都排进删除清单**（那张「旧入口去留」表的第四行）：开关撤掉、换成一行只读现状 + 「打开设置 › 练习偏好」按钮，`AppState.setTranscriptEnabled` 与 `setWeeklyGoal` 一起删，唯一写入口变成 `CoachSettingsViewModel.setTranscriptEnabled(_:)`；`SettingsHomeContractTests` 的字段清单里也已加上 `transcriptEnabled`。**开关下面那句说明原样搬进设置窗口，不要两边各留一份。** |
| **相对路径检查** | Phase 10 有一步专门查 `PracticeSession.reportPath` 是不是相对路径。Phase 4 写的是 `"reports/<id>.json"`，`PracticeRunnerArchiveTests.testTheParsedReviewIsWrittenToReportsAndLinkedFromTheSession` 已经守着这一条 |
| **拷目录换机器** | 逐字稿存在 `state.json` 里，不产生额外文件，天然跟着走 |
| **深色模式** | 训练记录页与待处理复盘页全部走令牌，加深色模式时不用改这两个文件 |

---

## 明确不做的事（写下来防止范围扩大）

| 不做 | 为什么 |
|---|---|
| **逐字稿的搜索、筛选、导出** | 不在 ROADMAP Phase 4 的交付清单里。训练记录页的清单只有「按月分组 + 五项信息 + 单条删除」三件事 |
| **编辑逐字稿** | 它是「你真正说过的话」的记录。可编辑之后它就不再是记录了，而复盘与复训都建立在「这是真实发生的」这个前提上 |
| **把 ChatGPT 的声音录下来当逐字稿的补充** | 需要屏幕录制权限，观感代价不值（ROADMAP 3.3、DEFINITION-OF-DONE 第 4 节）。考官问了什么由文字给 |
| **改 `FocusPart` 的 raw value** | 它与上游 `state.json` 兼容，改了已有数据读不出来。要中文显示名就在视图模型里映射 |
| **升 `schemaVersion`** | 本阶段是纯追加字段（`transcriptEnabled`），两个方向都不丢数据，仍是 3（spec 4.6） |
| **给 `CoachBridge` 加采样方法** | 见「设计决定 2」：带默认实现的新 protocol 要求是一个静默失败温床 |
| **深色模式、设置合并、「功能升级」「问题反馈」两页** | 决策 7，全部推到 Phase 10 |
| **自动清理 `pending-reviews/`** | 那是用户练了半小时换来的原文。删不删由他自己在界面上决定（Task 11），程序不替他做主 |

