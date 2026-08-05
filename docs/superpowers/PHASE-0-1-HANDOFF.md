# Phase 0 + Phase 1 交接说明

日期：2026-08-05
分支：`phase0-1-foundation`（53 个提交）
状态：**完成**。106 个测试全绿，全部经突变验证确认有实际约束力。

本文件是给 Phase 2 的输入。执行账本（`.superpowers/sdd/`）是 git 忽略的工作文件，其中对后续有价值的结论已固化到这里。

---

## 1. 已交付什么

### `axprobe` —— ChatGPT 诊断与排障工具（Phase 0 产出）

命令行工具，四个子命令：

| 命令 | 用途 |
|---|---|
| `axprobe doctor` | 环境预检：目标应用是否安装、辅助功能权限、AX 树能否唤醒 |
| `axprobe dump [路径]` | 导出 ChatGPT 的完整 Accessibility 树到文件 |
| `axprobe press "<desc>"` | 按下指定控件，并验证预期状态真的发生 |

**它不是一次性的探路脚本，是本项目最重要的长期排障工具。** spec 2.3 表格里那七个节点特征全都可能随 ChatGPT 更新而失效；届时用 `dump` 十分钟就能定位断在哪里。

### `IELTSCoachCore` —— 纯逻辑核心库（Phase 1 产出）

20 个源文件、1405 行，只依赖 Foundation，可在无 ChatGPT、无图形界面的环境下完整测试。

| 单元 | 职责 |
|---|---|
| `JSONValue` / `JSONRepair` | 动态 JSON 类型；ChatGPT 输出的容错修复（单引号、尾随逗号、截断）|
| `ReviewParser` | 从 ChatGPT 回复里挖出复盘 JSON。四级降级：定界块 → 代码围栏 → 剥首尾围栏 → 扫大括号 |
| `ReviewArchiver` | 复盘入库：归并错题与词汇、提取重训目标、推进计划进度 |
| `CoachState` + 11 个模型 | `state.json` 的完整模型，字段与上游 Windows 版逐字对齐 |
| `StateStore` | 原子写入 + 跨进程文件锁 |
| `DataDirectory` | 数据目录解析，App 与 MCP CLI 共用同一份实现 |
| `QuestionBankImporter` | CSV / JSON 题库导入，内容哈希 id |
| `PlanBuilder` | 7/14/30 天计划生成与进度推进 |
| `RetrainingPolicy` | 单点重训目标提取与排序 |
| `ExaminerPrompt` / `ReviewRequestPrompt` / `AnswerUpgradePolicy` | 考官提示词与复盘请求指令 |
| `VoiceEndPolicy` | 语音结束判定（去抖）|
| `FocusPart` | Part 选择枚举 |

---

## 2. 还不能做什么

- **没有界面。** Core 是库，没有任何 UI。
- **没有连上 ChatGPT。** `ChatGPTBridge` 是 Phase 2 的内容；`axprobe` 验证了每一个动作可行，但没有组装成会话流程。
- **没有 MCP server。** Phase 4。
- **没有打包。** 没有 `.app`、没有签名、没有图标。Phase 5。

**一句话：地基和验证工具都齐了，但还没有能给用户双击的东西。**

---

## 3. Phase 2 开工前必须知道的

### 3.1 目标应用与驱动方式

驱动 `com.openai.codex`（新 ChatGPT.app），**不是** `com.openai.chat`（Classic，无 live 语音）。

deep link 与 AppleScript-JS 两条路已实测排除，只走 Accessibility。详见 spec 2.1–2.3。

### 3.2 三条会咬人的实测规则（spec 2.3.1 / 2.3.2 / 2.3.3）

1. **按标签找元素必须加结构约束**。控制按钮的唯一子节点是 `AXImage`；侧边栏会话行嵌套 `Pin chat`/`Archive chat`。标签会变，而且侧边栏的同名会话是本产品自己制造的（每开一次语音就生成一条 `New voice chat`）。
2. **元素出现有延迟**。每个操作都要「等目标元素出现 → 操作 → 验证状态变化」。`kAXPressAction` 返回 0 不等于动作生效。
3. **`Voice chat active` 是会话级常驻**，静默 20 秒不消失。1.5 秒去抖窗口安全，**不要**加回上游的最短时长门槛。

### 3.3 Chromium 惰性 AX 树

每次会话开始必须先唤醒：对 application 元素设 `AXManualAccessibility` 与 `AXEnhancedUserInterface`（**两者返回错误码是正常的，不得据此判定失败**），然后轮询直到 `AXWebArea` 出现。跳过这步只能看到菜单栏。

### 3.4 唯一未验证的假设

**假设 5：AX 能否读到滚出屏幕的历史消息。** 需要在新目标上造 30 轮以上长对话后 dump 统计。

- 若成立 → 复盘全自动
- 若不成立 → 复盘回收固定走剪贴板（用户按 ⌘C），其余架构不变

风险等级已从「可能推翻方案」降为「可能需要先滚动加载」——新目标是 Chromium 应用，问题变成「ChatGPT 网页端是否虚拟化 DOM」，而这正是上游 Electron 版跑通过的场景。

**建议在 Phase 2 联调时自然验证**，不必专门制造。

---

## 4. 留给后续的已知项

### Phase 2 应处理

- `ReviewParser.findAfterRequest` / `findExisting` 无法区分「没找到复盘」与「找到但不完整」，两者都返回 nil。界面应给这两种情况不同的提示与按钮。
- `satisfies` 的判据是「`answer_upgrades` 至少一条完整」。5 条里 4 条不完整也会被接受且用户看不到信号。界面应显示不完整条数。
- spec 4.1 要求 `StateStore` 含「变更通知」，当前未实现（spec 4.5 把它归给 App 侧的 `DispatchSource`）。**不要遗漏。**

### Phase 3 应处理

- **错题归并靠 `learner_said` 精确字符串匹配**。同一个错误被 ChatGPT 换个说法（标点、大小写、措辞）就会拆成两条，长期打散错题本。
  **裁定：不改为模糊匹配** —— 归并错了把两个不同错误混成一条，比不归并更糟。正确解法是界面上让用户手动合并。匹配逻辑目前分散在 `ReviewArchiver.mergeIssues` 与 `RetrainingPolicy.rank` 两处，建议届时抽成单一函数，让这个决策变成一行改动。
- 题库导入界面做预览时，一并处理：表头重名列静默只取第一列、引号内 `\r` 未过滤。

### 已裁定不改（不要在后续审查里当新发现重报）

- **`StateStore` 用阻塞 `flock`（无 `LOCK_NB`）**。临界区是 KB 级 JSON 的毫秒级读改写，持锁进程崩溃时 OS 自动释放，不存在真死锁。spec 第 6 节「禁止无限等待」针对的是 AX/外部应用那类**无界**等待。裁定理由已写进代码注释。
- **`VoiceEndPolicy` 规则 3 里的 `!busy`** 在数学上冗余（规则 2 已保证 busy 时 ticks 归零），但保留为防御性写法。
- **`RetrainingPolicy` 同权重时的稳定排序**无测试覆盖。测试会很脆、价值低，不补。
- **`axprobe` 的 `AXTree.children()` 每节点调两次**。诊断工具，性能可接受。

---

## 5. 这套代码的测试是可信的

执行过程中**共发现 14 处空转测试**（测试是绿的、但它守护的代码从未被执行或可被整段删除），已全部消灭。每一处的判定方式都是：**把被测逻辑改成空实现或明显错误的实现，确认对应测试真的变红。**

其中最严重的三处：

| 被改坏的逻辑 | 加固前红了几个测试 |
|---|---|
| `ReviewParser` 的定界标记正则（整套）| 1 / 96 |
| 剥代码围栏逻辑 | 0 / 96 |
| `looksLikeReview` 的 4 条判据只留 1 条 | 0 / 96 |

**由此确立的两条规则已写入计划的全局约束，后续阶段继续适用：**

1. 被测函数有多条降级路径时，走 happy path 的测试只能证明「函数能用」，不能证明「这条路径能用」。**要验证第 N 条路径，必须先让第 1..N-1 条失效。** 手法范例：在标记前放诱饵 JSON，让兜底的「扫首尾大括号」跨越诱饵产出非法内容而无法得救。
2. **修 bug 时新增的测试，必须先在未修复的代码上跑一次并确认它变红。** 不变红就是没有约束力，要重写而不是接受。

---

## 6. 一个方法论教训

spec 2.5 记了一次代价最大的错误：初稿断定 live 语音在 ChatGPT Classic，依据是 Classic 打包了 `LiveKitWebRTC.framework` 而新应用没有。两处推理都错——打包框架不等于具备该功能；新应用是 Chromium 壳，WebRTC 由 Chromium 提供，本就不需要单独打包，「它没有该框架」不构成任何证据。

**纠正这个错误的不是后续推理，而是用户的一句直接观察。** 而当时手上的 AX dump 里其实已经写着「Classic 输入区没有语音按钮」——证据早在手上，只是没被读懂。

**由此确立的规则：涉及外部应用能力的判断，一律以在运行中的应用上实测为准，不接受从二进制内容、框架清单、Info.plist 措辞推断出的结论。**
