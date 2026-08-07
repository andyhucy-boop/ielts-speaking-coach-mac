# Phase 9 真机验收清单（给用户本人照着做）

日期：2026-08-07
对应计划：`docs/superpowers/plans/2026-08-06-phase9-mcp-and-codex.md` 的 **Task 13**
代码基线：分支 `phase2-bridge`，最后一条提交 `1caa8e4`（安装脚本的两处修复）。
自动化测试现状：`swift test` **1490 条全绿**（12.36 秒，2026-08-07 实跑）。

---

## 0. 这份文件是什么

Task 13 是 Phase 9 唯一**不能由子代理代劳**的任务。前面十二个任务的测试跑在协议层与纯逻辑上，
证明的是「协议对、逻辑对」，证明不了下面这三件事：

1. **Codex 认不认这份配置**——取决于你本机 Codex 的版本与配置格式（第 1 节第一条已经替你核实过一半）；
2. **LaunchServices 认不认 `ieltscoach://`**——这是 `open_dashboard` 唯一的成败关键，
   而现在**它还不认**（第 1 节第二条，实测）；
3. **模型照着中文说明能不能把参数传对**——只有真让它调一遍才知道。

- **你要做的**：按第 3–8 节逐步操作，把每一项的实际结果记下来
- **结果写到哪**：`docs/phase9-acceptance.md`（计划 Task 13 Step 6 指定的文件名，第 8 节给了可直接复制的骨架）
- **大约要多久**：约 45–70 分钟
- **会不会动到你的数据**：**不会**，只要你照第 3 节把 `IELTS_SPEAKING_DATA_DIR` 指到
  `/tmp/ielts-phase9`。**这一步不是可选的**——第 1 节第三条会告诉你为什么
- **会不会在 ChatGPT 里产生真实练习**：**不会**。7 个工具一行都不碰 `ChatGPTBridge`，
  全程不会新建语音会话、不会打字发提示词。你在 Codex 里的那几句对话本身当然是真的对话，
  但那是文字，不是练习

---

## 1. ⚠️ 开工前必须先知道的七件事

全部来自 2026-08-07 在本机实跑、实读得到的，不是猜的。
不先看，第 4、5、7 节都会当场卡住或者记下假缺陷。

### ⚠️ 一、计划最大的那个悬念（Codex 配置格式）**已经替你核实了一半**

计划 Task 12 开头写着「这个任务里有一条我没能在本机验证的事实」。现在验了：

| 核实项 | 实际结果 |
|---|---|
| Codex CLI 版本 | `codex-cli 0.146.0`（`~/.local/bin/codex`） |
| 配置文件 | `~/.codex/config.toml` **存在**，里面**已经有** `[mcp_servers]`、`[mcp_servers.node_repl]`、`[mcp_servers.node_repl.env]`、`[mcp_servers.computer-use]` |
| 键名 | `command` / `args` / `env` 全部对得上，另外还认 `startup_timeout_sec`、`cwd`、`enabled` |
| `codex mcp` 子命令 | **存在**：`list` / `get` / `add` / `remove` / `login` / `logout` |
| `codex mcp add` 的形状 | `codex mcp add [OPTIONS] <NAME> (--url <URL> \| -- <COMMAND>...)`，支持 `--env KEY=VALUE` |

**结论：计划里的假定是对的**，`codex/ielts-speaking-mcp.toml` 与安装脚本的模板不用改。

**剩下没核实的那一半（第 4 节第一步验它）**：你平时用的到底是**终端里的 `codex`**，
还是 **`/Applications/ChatGPT.app`**（它的 bundle id 就是 `com.openai.codex`，也就是本项目一直在自动化的那个应用）。
两者是不是共用同一份 `~/.codex/config.toml`，我没法替你确认。
**在哪一侧验收，报告里就写哪一侧。**

### ⚠️ 二、`ieltscoach://` 现在**还没被系统登记**——`open_dashboard` 此刻一定是死的

实测（2026-08-07）：

```
lsregister -dump | grep -i ieltscoach   →  0 条
lsregister -dump | grep -i chatgpt      →  224 条（对照组，证明这条命令本身没问题）
```

而 `.app` 里的 plist 是对的：

```
plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"
→ ieltscoach
```

**两半里 Task 11 那一半已经做好了，缺的是「被系统登记」这一步**——它只有在
`.app` 被真的打开过一次之后才会发生。第 3.4 节就干这件事。**跳过它，第 7 节全部会失败，
而且失败的样子是「什么都没发生」。**

### ⚠️ 三、计划 Step 3 说那五个工具「只读」，**其中两个会写盘**

这一条是本清单与计划最要紧的一处出入。实测：

| 工具 | 真的只读吗 | 实测证据 |
|---|---|---|
| `initialize_ielts_workspace` | **不是。会重写 `state.json`** | 拿你真实的 `state.json` 复制一份、只调这一个工具：`settings` 的键从 `['recordingConsentAt', 'recordingEnabled']` 变成 `['defaultRoute', 'feedbackTiming', 'part2PrepMode', 'recordingConsentAt', 'recordingEnabled', 'transcriptEnabled', 'weeklyGoal']`，文件从 1150 字节变成 1308 字节；还会建出 `reports/`、`pending-reviews/`、`recordings/` 三个子目录 |
| `set_training_selection` | **不是。会写 `currentSession`** | 计划自己在「设计判断：选题存在哪」那一节就说了 |
| `get_dashboard_data` / `list_practice_history` / `get_training_context` | 是，只读 | — |

补键这件事本身是对的（那就是升级），但**它发生在你调用工具的那一刻，而不是你决定升级的那一刻**。
所以：**验收全程把数据目录指到 `/tmp/ielts-phase9`**（第 3.2 节复制一份真实数据过去），
真实目录一个字节都不动。

### ⚠️ 四、你真实的档案里几乎是空的（实读 2026-08-07）

```
schemaVersion 3
sessions   0     issues 0     vocabulary 0
questions  1     （p1-home-001，Part 1 · Home，"What do you like most about your home?"）
targets    1     （grammar_sentence_control，「先说完整主干句，再补充细节」）
plan       没有   currentSession 没有
settings   只有 recordingEnabled / recordingConsentAt
learner.displayName ""
pending-reviews/sync-1785940167.txt   ← 一份没导回来的复盘（6975 字节）
```

直接后果，**照计划原文走会有两行验不出来**：

| 计划 Step 3 那张表里的一行 | 在你的数据上能不能验 |
|---|---|
| `list_practice_history`：最近几场练习都在吗？顺序是从新到旧吗？ | **验不了，一场都没有**。第 5.4 节改成「先用前面几步造出两场，再看顺序」 |
| `get_dashboard_data`：本周次数、计划天数与 App 里看到的一致吗？ | 能验，但答案都是 0 / 没有计划。判据改成「与 App 显示的一致，且 `weekGoal` 是 **5**（缺 `weeklyGoal` 键时的默认值）」 |
| `set_training_selection`：传一个真实题号 | 只有 1 道题、还是 Part 1。第 3.3 节补一道 Part 2 的题进临时目录，好把 Part 2 的默认时长（4 分钟）也验掉 |

### ⚠️ 五、你那份唯一的真实复盘**字段名是旧的**，拿它验不出「成功路径」

计划 Step 5 第 3 步让你把 `pending-reviews/` 里那份真实复盘交给 `save_session_review`，
第 4 步要求「错题本与词汇本数字从 0 变正、返回里没有 `warning`」。

**这两条用那份文件永远达不到。** 实读那份文件：

```
must_correct[0] 的键：issue / examples / fix        ← 归档读的是 learner_said / correction / why_it_matters
vocabulary：是一个对象 {"useful_replacements": …}    ← 归档读的是数组
```

它是**字段名修好之前**留下的（`DEFINITION-OF-DONE` 第 6 节那句「复盘字段名刚修好，需再练一场验证」说的就是这件事）。
实跑的结果：

```
issuesAdded 0、vocabularyAdded 0、skipped ["must_correct","vocabulary"]、warning 有
```

**这不是缺陷，这恰恰是最该验的那一条**（完成标准里的「顶层键存在却一条都没归进去时会报警，不谎称成功」）。
所以第 7 节把它拆成三条路径：新格式样本验成功、你那份旧文件验报警、随便一段文字验解析失败。

### ⚠️ 六、别用 `coach practice` 去对比考官提示词

计划 Step 3 最后一行写「把它和 `coach practice` 发出去的那份对比一眼」。
**照做的代价是真开一场 ChatGPT 语音**，而且完全没必要：

```
Sources/coach/PracticeCommand.swift:81        ExaminerPrompt.build(setup: setup)
Sources/IELTSCoachUI/Session/PracticeRunner.swift:178  ExaminerPrompt.build(setup: setup)
Sources/IELTSCoachMCP/Tools/GetTrainingContextTool.swift:113  ExaminerPrompt.build(setup: setup)
```

三处调的是**同一个函数**，唯一可能不同的是塞进 `SessionSetup` 的那几个值。
第 5.5 节给了五句可以逐字核对的锚点，比跑一场练习更彻底。

### ⚠️ 七、第 3.4 节打开的那个 App，读的是**真实**数据目录

`open` 传不进环境变量，所以从 `.build` 双击打开的 App 用的是
`~/Library/Application Support/IELTS Speaking Coach`。**这没问题**——第 7 节只是让它跳页，不写数据。

但请注意两件事：

- **别在那个窗口里点「开始练习」**：那会真的开 ChatGPT 语音，并且写进你真实的档案
- 第 5 节 `get_dashboard_data` 的数字要和 App 对照时，对照的是**同一份真实数据的副本**，
  数字应当一致；不一致就说明副本没复制干净（第 3.2 节重来一次）

---

## 2. 子代理已经代跑的自动化项（这几条你不用再跑）

每条都是 2026-08-07 在本机实际执行过的，输出照抄在这里。**报告里引用即可。**

| 完成标准里的哪一条 | 命令 / 依据 | 实际结果 |
|---|---|---|
| `swift test` 全绿 | `swift test` | ✅ **1490 条全绿**（12.36 秒） |
| `./scripts/mcp-smoke.sh` 通过 | 实跑 | ✅ 原样输出：「MCP stdio 冒烟测试通过：5 条响应、7 个工具齐全、坏消息之后仍存活、读到 EOF 自行退出、stdout 干净。」 |
| **已经装好的那个二进制**能不能用 | 直接喂 `initialize` + `tools/list` 给 `~/.local/bin/ielts-speaking-mcp`（临时数据目录） | ✅ `serverInfo {name: ielts-speaking-mcp, version: 0.9.0}`、`protocolVersion 2025-06-18`；stderr 有启动行 |
| `tools/list` 的 7 个名字与顺序与 spec 4.4 逐字一致 | 同上 | ✅ `initialize_ielts_workspace, open_dashboard, set_training_selection, get_training_context, save_session_review, list_practice_history, get_dashboard_data` |
| Info.plist 注册了 `ieltscoach://` | `plutil -extract …` | ✅ 读到 `ieltscoach` |
| **LaunchServices 登记了没有** | `lsregister -dump \| grep -i ieltscoach` | ❌ **零命中**（见第 1 节第二条，第 3.4 节修它） |
| Codex 的配置格式 | `codex --version`、`codex mcp --help`、读 `~/.codex/config.toml` 的段落头 | ✅ 与计划假定一致（见第 1 节第一条） |
| 零第三方依赖 | `Package.swift` 的 `dependencies` | ✅ 仍为空 |
| 七个工具的返回负载与错误文案 | 用**临时目录里的一份真实数据副本**，把 14 条消息喂给已安装的二进制实跑一遍 | ✅ 第 5、7 节里所有「预期」都是这次跑出来的，不是写出来的 |

**这两条子代理没有替你跑**，理由都不是偷懒：

- `./scripts/build-app.sh`：要用钥匙串里那把私钥，非交互会话里会弹「codesign 想访问密钥」，
  那会把整个会话挂住。**留给你在第 3.4 节做**
- `./scripts/install-codex-plugin.sh`：它会往 `~/.local/bin` 里写东西。
  （`~/.local/bin/ielts-speaking-mcp` 现在**已经在了**，2026-08-07 22:19 装的，
  就是 Task 12 那次；第 3.5 节让你重装一次以确保它是最新代码）

### 三处突变验证（证明清单里那三条判据背后的测试真的有约束力）

| # | 改了哪一行 | 跑了什么 | 看到什么 |
|---|---|---|---|
| 1 | `Sources/IELTSCoachMCP/Tools/SetTrainingSelectionTool.swift:50`：`state.questions.first(where: { $0.id == questionID })` → `state.questions.first` | `swift test --filter SelectionToolsTests` | ❌ **18 条里红 12 条**。要紧的是 `testUnknownQuestionIsRejectedAndNothingIsWritten`（`SelectionToolsTests.swift:58/59/61`），最后一条断言的原话是「选题失败时不能留下半个选择——下一次 get_training_context 会拿它去练」。已改回 |
| 2 | `Sources/IELTSCoachMCP/Tools/SaveSessionReviewTool.swift:149`：`let warning = outcome.skipped.isEmpty ? nil : …` → `let warning: String? = true ? nil : …`（等于永远不报警） | `swift test --filter SaveSessionReviewToolTests` | ❌ **9 条里红 1 条**：`testReportsSilentlyEmptyArchivesInsteadOfClaimingSuccess`（`SaveSessionReviewToolTests.swift:119`，`XCTUnwrap failed: expected non-nil value of type "String"`）。已改回 |
| 3 | `Sources/IELTSCoachUI/DeepLink.swift:18`：`guard let route = CoachRoute.parse(url) else` → `guard let route = CoachRoute.parse(url) ?? CoachRoute.dashboard as CoachRoute? else`（等于不认识的页面默默跳首页） | `swift test --filter DeepLinkTests` | ❌ **9 条里红 1 条**：`testUnknownPageIsRejectedWithAnActionableChineseMessage`（`DeepLinkTests.swift:65`，断言原话「不认识的页面必须被拒绝，而不是默默跳到首页」）。已改回 |

三处都已改回，改回后 `swift test` **1490 条全绿**，工作区干净。
它们分别守着第 5.3 节、第 7.3 节、第 6.4 节要你验的那三件事——
也就是说那三条判据在真机上要是不满足，**是真机的问题，不是测试放水**。

### 第四处：证明**清单第 5.3 节那条检查本身**有约束力

上面三处验的是「单元测试有没有约束力」。这一处验的是**这份清单里的检查项**有没有约束力——
因为本清单上一版在 5.3 节写的就是一条空转检查（拿 `sessionTotal` 验「有没有留下半个选择」）。

拿第 1 处那个突变（`state.questions.first(where:…)` → `state.questions.first`，
等于不存在的题号也会被「选中」）重新编译出真的二进制，
再拿**真实数据的副本**照 5.3 节的步骤跑一遍「故意传不存在的题号」：

| 检查项 | 突变后的结果 |
|---|---|
| **旧检查**：`get_dashboard_data` 的 `sessionTotal` 仍是 0 | ✅ **绿——漏报**。写进去的是 `currentSession`，`sessionTotal` 数的是 `sessions`，两者无关 |
| **新检查 A**：再调 `get_training_context`，应当仍是「还没有选定题目…」 | ❌ **红**。它返回了一整份真实上下文 |
| **新检查 B**：`state.json` 的 `currentSession` 应当是 `None` | ❌ **红**。实际是 `{'id': '2026-08-07-001', 'questionId': 'p1-home-001'}`——**还选错了题** |

同一个缺陷，旧检查一声不吭，新检查两条都红。已改回，`swift test` **1490 条全绿**。

---

## 3. 准备工作（约 15 分钟）

### 3.1 备份真实数据目录（**第一件事，不许跳过**）

```bash
cp -R "$HOME/Library/Application Support/IELTS Speaking Coach" \
      "$HOME/Library/Application Support/IELTS Speaking Coach.phase9-backup"
ls "$HOME/Library/Application Support/IELTS Speaking Coach.phase9-backup"
```

- [ ] 备份完成，`ls` 得到确认

> 按本清单走，真实目录全程不会被写。备份是为了「万一你手滑把 `env` 那一行写成了真实路径」——
> 到那时你需要一份升级前的原件，而不是一份「大概没坏吧」的猜测。

### 3.2 造验收专用的数据目录（**真实数据的副本**）

```bash
rm -rf /tmp/ielts-phase9 && mkdir -p /tmp/ielts-phase9
cp -R "$HOME/Library/Application Support/IELTS Speaking Coach/." /tmp/ielts-phase9/
ls -la /tmp/ielts-phase9
```

- [ ] 里面有 `state.json`、`pending-reviews/sync-1785940167.txt`

### 3.3 往副本里补一道 Part 2 的题（好把默认时长 4 分钟也验掉）

**下面这段必须顶格粘贴**（heredoc，非 `<<-` 形式的结束符 `PY` 只有顶格才算数）。

```bash
python3 - <<'PY'
import json
p = "/tmp/ielts-phase9/state.json"
d = json.load(open(p))
if not any(q["id"] == "p2-skill-001" for q in d["questions"]):
    d["questions"].append({
        "id": "p2-skill-001", "part": 2, "topic": "Long turn",
        "prompt": "Describe a skill you learned recently.",
        "followups": ["Why did you want to learn it?"]})
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
print("题库现在有 %d 道题：%s" % (len(d["questions"]), [q["id"] for q in d["questions"]]))
PY
```

- [ ] 打印「题库现在有 2 道题：['p1-home-001', 'p2-skill-001']」

### 3.4 打包、核签名、**让系统登记 `ieltscoach://`**（第 7 节的前提）

```bash
cd ~/Projects/ielts-speaking-coach-mac
./scripts/build-app.sh && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated
./scripts/build-app.sh && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated
```

> **别给 `build-app.sh` 加 `>/dev/null`。** 它的四道闸门——URL scheme（`:78`）、麦克风用途说明（`:91`）、
> 签名身份缺失（`:103`）、指定要求形状不对（`:131`）——**报警和诊断全都走 stdout**。
> 丢掉 stdout 再用 `&&` 串起来的话，脚本一失败整行只会输出**一片空白**，
> 你拿不到任何线索，而 3.4 是第 6、7 节的硬前提。输出啰嗦一点，好过失败时无声无息。

- [ ] 第一次跑时若弹出「codesign 想使用钥匙串里的私钥」，点「始终允许」
- [ ] **两行 `designated` 一模一样**（成品标准第 9 条）。不一致 = 辅助功能授权会反复失效，**立刻停下报告**
- [ ] 打包过程里看到了 `✓ 已注册 URL scheme：ieltscoach://` 和 `✓ 麦克风用途说明：…`
- [ ] **看到以 `❌` 开头的中文诊断就停下**，照它的「下一步」处理，别继续往下做。
      最可能撞上的是这一条（子代理没法替你跑签名，理由见第 2 节）：
      「找不到可用的签名身份「IELTS Coach Dev」（证书或私钥缺失）。」——
      它后面跟着的三行讲的就是「证书在、私钥不在」这种半截状态怎么修

然后**手动打开一次**——这一步才是让系统登记链接的那一步：

```bash
open ".build/IELTS Speaking Coach.app"
```

- [ ] App 窗口起来了（**别点「开始练习」**，见第 1 节第七条）
- [ ] 回终端核实登记成功了：

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -dump | grep -i -m 5 ieltscoach
```

- [ ] **这次有命中**（之前是零，见第 1 节第二条）。仍然是零就**停下报告**，
      不要往下做——第 7 节全部会以「什么都没发生」的样子失败

### 3.5 重装一次可执行文件（确保 Codex 起的是最新代码）

```bash
cd ~/Projects/ielts-speaking-coach-mac
./scripts/install-codex-plugin.sh
```

- [ ] 打印 `✅ 已安装：/Users/…/.local/bin/ielts-speaking-mcp` 与那段 TOML
- [ ] **`~/.codex/config.toml` 没有被改动**（不加 `--write` 时它不该动你的配置）

```bash
ls -l ~/.local/bin/ielts-speaking-mcp
```

- [ ] 时间戳是刚刚

---

## 4. 【计划 Step 1 + 2】把 MCP server 接进 Codex

### 4.1 先确认你在哪一侧验收（第 1 节第一条剩下的那一半）

- [ ] 我这次验收用的是：**终端里的 `codex` CLI** / **`/Applications/ChatGPT.app`**（勾一个，写进报告）
- [ ] 若用的是应用：它读不读 `~/.codex/config.toml`？（第 4.4 节那句「列出可用的工具」就是答案。
      读不到的话，请在报告里写清它的配置入口在哪——**下一个读这份计划的人需要知道真相**）

### 4.2 接上（两条路，任选其一）

**路 A（推荐，本机已确认 `codex mcp add` 存在）：**

```bash
codex mcp add ielts_speaking \
  --env IELTS_SPEAKING_DATA_DIR=/tmp/ielts-phase9 \
  -- "$HOME/.local/bin/ielts-speaking-mcp"
```

> `--env` 那一行就是「先把数据目录指到临时目录」的落实（第 1 节第三条）。
> **别省掉它**，省掉就等于拿真实档案做实验。

**路 B（计划原文写的那条）：** 把 `./scripts/install-codex-plugin.sh` 打印的那段追加进
`~/.codex/config.toml`，再手工补一段 env：

```toml
[mcp_servers.ielts_speaking]
command = "/Users/你的用户名/.local/bin/ielts-speaking-mcp"
args = []

[mcp_servers.ielts_speaking.env]
IELTS_SPEAKING_DATA_DIR = "/tmp/ielts-phase9"
```

（或者运行 `./scripts/install-codex-plugin.sh --write` 让脚本追加前两段，env 那段自己补。
脚本会先备份，发现同名段落会拒绝覆盖并告诉你在第几行。）

### 4.3 确认配置真的进去了、而且文件还读得动

```bash
codex mcp list
codex mcp get ielts_speaking --json
```

- [ ] 列表里有 `ielts_speaking`，`command` 指向 `~/.local/bin/ielts-speaking-mcp`
- [ ] `env` 里有 `IELTS_SPEAKING_DATA_DIR=/tmp/ielts-phase9`
- [ ] **这两条命令都没报 TOML 解析错误**
      ← 你的配置里本来就有一个光秃秃的 `[mcp_servers]` 表，追加子表是合法的，但这一步顺手确认一次最省事

### 4.4 重启 Codex，问它一句

- [ ] CLI：退出当前会话重新开一个；应用：**完全退出**再打开
- [ ] 在 Codex 里问：「列出你现在能用的工具」
- [ ] **7 个 `ielts` 相关的工具都在**：`initialize_ielts_workspace`、`open_dashboard`、
      `set_training_selection`、`get_training_context`、`save_session_review`、
      `list_practice_history`、`get_dashboard_data`

### 4.5 一个工具都看不到时怎么排错（**先跑这条，再改任何东西**）

```bash
W=$(mktemp -d)
printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
 | IELTS_SPEAKING_DATA_DIR="$W" "$HOME/.local/bin/ielts-speaking-mcp"
```

预期（子代理实跑过）：stderr 上一行
`ielts-speaking-mcp 0.9.0 已启动。数据目录：…`，stdout 上**两行 JSON**，第二行里 7 个工具名齐全。

- [ ] 这条通了 → **问题在 Codex 那一侧**（配置路径、`env`、或者你验收的那一侧根本不读这份 config）。
      Codex 有没有把 MCP server 的 stderr 记在哪个日志里？本机 `~/.codex/` 下**没有** `log/` 目录，
      找不到的话就以这条手工命令为准
- [ ] 这条不通 → 问题在二进制，把报错贴进报告，**停下**

---

## 5. 【计划 Step 3】七个工具在 Codex 里逐个调

**从这里开始，全部在 Codex 的对话里进行**，不要回终端替它跑。
每一步都把 Codex 展示给你的返回记下来（至少记下面「看什么」那一列的值）。

下面每一条的「预期」都是子代理拿**你真实数据的副本**在本机实跑出来的（第 2 节最后一行），
不是照着代码写的。对不上就是真机与本地的差异，值得记。

### 5.1 `initialize_ielts_workspace`

对 Codex 说：「调用 initialize_ielts_workspace」。

| 看什么 | 预期 |
|---|---|
| `dataDirectory` | **`/tmp/ielts-phase9`** ← 是这个才说明 `env` 生效了；是 `~/Library/Application Support/IELTS Speaking Coach` 就**立刻停下**，回第 4.2 节把 `env` 补上 |
| `createdStateFile` | `false`（副本里已经有 state.json） |
| `questionCount` / `sessionCount` / `issueCount` / `vocabularyCount` / `targetCount` | `2 / 0 / 0 / 0 / 1` |
| `note` | 「工作区就绪。下一步：用 set_training_selection 选一道题。」 |

- [ ] `dataDirectory` 确认是临时目录（**这一条不对，后面全部别做**）

### 5.2 `get_dashboard_data`

| 看什么 | 预期 |
|---|---|
| `questionTotal` / `sessionTotal` / `issueTotal` / `vocabularyTotal` | `2 / 0 / 0 / 0` |
| `weekDone` / `weekGoal` | `0 / 5`（5 是缺 `weeklyGoal` 键时的默认值） |
| `plan` | `null`——**键必须在，不能整个消失** |
| `undatedSessionCount` | `0` |
| `note` | 「还没有学习计划。下一步：可以直接用 set_training_selection 挑一道题开练。」 |

- [ ] 打开 App（第 3.4 节那个窗口）对照一眼：题库页 **1 道题**（App 读的是真实目录，比副本少那道
      3.3 节补的 Part 2 题，**这是对的**），本周次数、计划都对得上

### 5.3 `set_training_selection` —— 先**故意做错一次**（对应成品标准第 8 条）

> **在选题之前，先把第 5.5 节开头那条「没选题时调 get_training_context」做掉**——
> 一旦选了题就再也回不到「没选过题」的状态了（除非等第 7 节存完复盘把 `currentSession` 清掉）。

对 Codex 说：「用 set_training_selection 选题号 `不存在的题号`」。

预期（逐字，实跑抄回）：

```
题库里没有题号「不存在的题号」（当前共 2 题）。下一步：调用 get_dashboard_data 看看现在有哪些题，或先在 App 的「训练题库」页导入题库。
```

- [ ] 是**中文**、说清了「发生了什么」（没有这个题号 + 现在共几题）和「下一步」（两条路）
- [ ] Codex 收到之后**自己纠正了**（去调 `get_dashboard_data` 找真题号）还是直接把错误甩给你？
      **两种都记下来**——这是「工具说明写得够不够清楚」的直接证据
- [ ] 紧接着让它再调一次 `get_training_context`（不传参数），预期**仍然是那句空状态文案**，逐字：

```
还没有选定题目，没有可用的练习上下文。下一步：先调用 set_training_selection 选一道题。
```

  这一条才是「选题失败不许留下半个选择」的真机验收。前提是你还没成功选过题——
  按本节开头那条提示，5.5 的第一步应当已经做过了，而它不写盘，状态仍是干净的。

- [ ] 回终端直接看盘，最硬的一条：

```bash
python3 -c "import json;print(json.load(open('/tmp/ielts-phase9/state.json')).get('currentSession'))"
```

  预期打印 `None`。打印出一个带 `id` / `questionId` 的字典 = 失败的选题把半个选择写进去了，**停下报告**。

> ⚠️ **别拿 `get_dashboard_data` 的 `sessionTotal` 验这件事**（本清单上一版就是这么写的，是错的）。
> `set_training_selection` 写的是 `state.currentSession`（`SetTrainingSelectionTool.swift:64`），
> 而 `sessionTotal` 数的是 `state.sessions`（`DashboardSummary.swift:91`），两者根本不是一回事，
> `get_dashboard_data` 的负载里也**没有** `currentSession` 这个字段。
> 实跑确认（2026-08-07，真实数据副本）：**成功**选中 `p2-skill-001`、`state.json` 里
> `currentSession` 确实写进去了之后，`get_dashboard_data` 返回的 `sessionTotal` **依然是 0**。
> 也就是说那条检查成功和失败都显示 0，永远不会红——正是本项目消灭过 15 次的那种空转检查。

然后选真的那道：「用 set_training_selection 选 `p2-skill-001`，目标写「回答后补一个原因和一个例子」」。

| 看什么 | 预期 |
|---|---|
| `sessionId` | `2026-08-07-001` 这种 `YYYY-MM-DD-NNN` 形状（日期是你验收当天） |
| `questionId` / `focusPart` | `p2-skill-001` / **`Part 2`**（没传 focusPart 时按题目自身的 part 推断） |
| `goal` | 你写的那句 |
| `note` | 「已选定。下一步：调用 get_training_context 取考官提示词。」 |

### 5.4 `list_practice_history`

现在还没有任何练习记录，先验空状态：

| 看什么 | 预期 |
|---|---|
| `total` / `returned` / `undatedSessionCount` | `0 / 0 / 0` |
| `note` | 「还没有任何练习记录。下一步：用 set_training_selection 选题、get_training_context 取考官提示词，练完把复盘交给 save_session_review。」 |

> **计划 Step 3 那张表里「最近几场练习都在吗？顺序是从新到旧吗？」在这里验不了**（第 1 节第四条）。
> 第 7 节存完两份复盘之后会造出两场记录，**那时再回来验顺序**（第 7.5 节）。

### 5.5 `get_training_context` —— 先验「没选题时会不会瞎给」

> 这一条要在 5.3 之前做才干净；已经选过题的话，验完 5.5 的其余部分再说，
> 或者让 Codex 存完复盘（第 7 节会清掉 `currentSession`）之后回头补验。

不带选题直接调，预期：

```
还没有选定题目，没有可用的练习上下文。下一步：先调用 set_training_selection 选一道题。
```

选好题之后再调（不传任何参数）：

| 看什么 | 预期 |
|---|---|
| `sessionId` | 与 5.3 返回的**同一个**编号 |
| `durationMinutes` | **`4`** ← Part 2 的默认值（其余 Part 是 6），与 `coach practice` 一致 |
| `feedbackTiming` / `part2PrepMode` | `deferred` / `countdown` |
| `reviewRequestId` | `sync-<那个 sessionId>` |
| `activeTargets` | 至少有 `grammar_sentence_control`（你档案里那个） |
| `examinerPrompt` | **44 行**，逐字核对下面五句 |

`examinerPrompt` 的五个锚点（**逐字**，别只看「看起来挺像」）：

1. 第一行：`You will act as an IELTS Speaking examiner. Stay neutral and concise. Ask one question at a time. Do not correct, praise, explain, or teach until examiner mode ends.`
2. 开场白里：`I will save all feedback until the end.`（`deferred` 才是这句）
3. `Section rules (Part 2):` 底下有 `Announce one minute of preparation and up to two minutes of speaking.`
4. `Target session length: about 4 minutes.`
5. 末尾两行：

```
本次唯一目标：回答后补一个原因和一个例子
考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
```

- [ ] 五句都在。**第 5 句缺了 = 目标没进提示词 = 白练一场且界面上看不出异样**，这是本项目最危险的失败形态
- [ ] 顺手试一次越界：让它传 `durationMinutes: 999`，预期
      「参数「durationMinutes」必须在 1–60 之间，收到的是 999。下一步：…」——
      **报错而不是悄悄夹到 60**

---

## 6. 【计划 Step 4】`open_dashboard`（本阶段最容易失败的一步）

前提：第 3.4 节已经做完，`lsregister` 里能搜到 `ieltscoach`。

### 6.1 正常唤起

在 Codex 里依次调用 `open_dashboard`，`section` 分别传 `dashboard`、`history`：

- [ ] `dashboard`：App 窗口**被带到前台**，侧边栏停在「**今日训练**」
- [ ] `history`：侧边栏跳到「**训练记录**」
- [ ] 返回负载里 `opened` 是 `ieltscoach://dashboard` / `ieltscoach://history`，且带着那句
      「已请求系统打开 IELTS Speaking Coach。若窗口没出现，下一步：…」
- [ ] **从调用到窗口起来大约几秒？** 记下来（报告要回答「体验上像不像一回事」）

### 6.2 九个页面名都能落到真做出来的页面上

九个合法取值：`dashboard`、`today`、`questions`、`plan`、`retraining`、`reviews`、`history`、`issues`、`vocabulary`。

- [ ] 随便再挑三个试（建议 `plan`、`issues`、`vocabulary`），确认**没有一个落到「这一页还没做」的占位页**
      （代码上九个都指向已实现的页面，这一步是复核）

### 6.3 不存在的 section

让 Codex 传 `section: "nope"`。预期（逐字，实跑抄回）：

```
参数「section」的取值「nope」不认识，只能是 dashboard、today、questions、plan、retraining、reviews、history、issues、vocabulary。下一步：把 section 改成这几个之一：dashboard、today、questions、plan、retraining、reviews、history、issues、vocabulary。
```

- [ ] 是中文、列出了全部可用页面名、**而且什么都没打开**
- [ ] 顺手判断一句：这句话把九个页面名**说了两遍**，读起来啰嗦吗？
      （不是缺陷，是文案观察，写进报告第七节即可）

### 6.4 深链接的「禁止静默失败」——**这一条要回终端做**

```bash
open "ieltscoach://nope"
```

- [ ] App 窗口顶上出现一条**中文横幅**：
      「链接里的页面名「nope」不认识。下一步：改用这些之一——dashboard、today、questions、plan、retraining、reviews、history、issues、vocabulary。」
- [ ] 横幅**不截断**（后半句「下一步」必须看得见），右边有个 × 能关掉

> **别试 `open "ielts-coach://dashboard"` 这种「换个 scheme」的用例**：LaunchServices 按 scheme 派发，
> 别的 scheme 压根**送不到**这个 App，你只会看到系统的「没有应用可以打开这个网址」。
> `DeepLinkResolver` 里那条「不是本应用能打开的链接」的分支从外部触发不了，
> 由 `DeepLinkTests` 守着即可。**这不是缺陷，是没法从外面测。**

> 这一条验的是「点了链接、窗口跳出来却毫无反应」这种失败形态有没有被堵住。
> 背后那条测试子代理做过突变验证（第 2 节表格第 3 行）：把「不认识就拒绝」改成「默默跳首页」，
> `DeepLinkTests.swift:65` 当场变红。

### 6.5 窗口打不开时的排查顺序（**照这个顺序来，别在代码里乱试**）

1. `plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"` → 应当是 `ieltscoach`
2. `lsregister -dump | grep -i ieltscoach` → 应当有命中；没有就回第 3.4 节再双击一次
3. 你是不是同时有两份 App（`.build` 里一份、「应用程序」里一份）？两份都注册了同一个 scheme 时，
   系统挑哪一份是不确定的，**跳出来的可能是旧的那份**。删掉不用的那份再试
4. 三条都对还是不行 → **停下报告**

---

## 7. 【计划 Step 5】`save_session_review` 的三条路径（**这一节是本阶段最有信息量的部分**）

数据目录已经是 `/tmp/ielts-phase9`（第 4.2 节的 `env`），真实档案不会被碰。

### 7.1 先准备一份**新格式**的复盘样本（计划没给，但没有它就验不出成功路径）

**顶格粘贴**：

```bash
cat > /tmp/ielts-phase9-sample-review.txt <<'TXT'
<<<IELTS_REVIEW_JSON:验收样本>>>
{
  "summary": "回答能说清主要意思，但句子结构和词形还需要稳定。",
  "must_correct": [
    {"learner_said": "I'm not go there on weekdays", "correction": "I don't go there on weekdays", "why_it_matters": "否定句里 be 动词和实义动词不能同时出现，考官会判为基础语法错误。"},
    {"learner_said": "feel really relax and happiness", "correction": "feel really relaxed and happy", "why_it_matters": "形容词与名词混用会让描述听起来不自然。"}
  ],
  "natural_upgrades": [
    {"learner_said": "beautiful air", "more_natural": "fresh air", "usage_note": "air 一般搭配 fresh，不搭配 beautiful。"}
  ],
  "vocabulary": [
    {"basic": "normal park", "better": "an ordinary local park", "collocation": "an ordinary local park near my flat", "priority": "high"},
    {"basic": "spare time", "better": "downtime", "collocation": "in my downtime", "priority": "medium"}
  ],
  "habits": [
    {"habit": "回答前有较长停顿", "evidence": "多次出现 3 秒以上的空白。"}
  ],
  "logic_feedback": [
    {"question": "What do you like most about your home?", "issue": "没有先直接回应问题", "improvement": "先一句话给答案，再补原因和例子。"}
  ],
  "answer_upgrades": [
    {"question": "What do you like most about your home?", "original_answer": "I like my home because it is quiet.", "revised_answer": "What I like most is how quiet it is — I live on the top floor, so I hardly hear any traffic, which makes it easy to focus after work.", "changes": ["先给出直接答案", "补了一个具体原因", "补了一个生活化的例子"]}
  ],
  "priority_target": {"id": "grammar_negation", "label": "否定句先想清楚用 don't 还是 am not", "status": "new", "evidence": ["I'm not go there on weekdays"]}
}
<<<END_IELTS_REVIEW_JSON:验收样本>>>
TXT
echo "样本已写好：$(wc -l < /tmp/ielts-phase9-sample-review.txt) 行"
```

> 字段名照 `ReviewRequestPrompt` 里写死的那份（`learner_said` / `correction` / `why_it_matters`；
> `vocabulary` 是**数组**）。这就是「ChatGPT 按提示词正确输出时」的样子。

### 7.2 成功路径

对 Codex 说：「把 `/tmp/ielts-phase9-sample-review.txt` 的内容原样作为 `reviewText` 传给 `save_session_review`」。

| 看什么 | 预期（实跑值） |
|---|---|
| `isError` | `false` |
| `sessionId` / `questionId` | 5.3 选的那一场 / `p2-skill-001` |
| `issuesAdded` / `vocabularyAdded` | **`2` / `2`** ← 从 0 变正，成品标准第 4 条 |
| `issueTotal` / `vocabularyTotal` | `2` / `2` |
| `skipped` / `warning` | `[]` / **没有** |
| `reportPath` / `reportFile` | `reports/<sessionId>.json` / 绝对路径 |
| `pendingReviewPath` | `/tmp/ielts-phase9/pending-reviews/<sessionId>.txt` |

- [ ] 回终端确认文件真的在：`ls -l /tmp/ielts-phase9/reports /tmp/ielts-phase9/pending-reviews`
- [ ] 再让 Codex 调一次 `get_dashboard_data`：`issueTotal` / `vocabularyTotal` 都是 2，`weekDone` 变成 1

### 7.3 报警路径（**用你那份真实的旧复盘**，第 1 节第五条说的那份）

对 Codex 说：「把 `/tmp/ielts-phase9/pending-reviews/sync-1785940167.txt` 的内容原样作为 `reviewText` 传给 `save_session_review`」。

| 看什么 | 预期（实跑值） |
|---|---|
| `isError` | `false`（**它算成功归档，只是有话要说**） |
| `issuesAdded` / `vocabularyAdded` | `0` / `0` |
| `skipped` | **`["must_correct", "vocabulary"]`** |
| `warning` | 有，开头是「复盘里有 must_correct、vocabulary，但一条都没能归进档案。这通常意味着 ChatGPT 用的字段名和本工具读的对不上——归档 0 条不等于没错题。下一步：原文完整保存在 …」 |
| `questionId` | **空字符串**（这一场没先选题，工具不瞎猜是对的） |

- [ ] `warning` 里给的路径**真的存在**（`ls` 一下）
- [ ] **这一条是完成标准里「归档 0 条时必须报警、不谎称成功」的真机验收**，请把 `warning` 原文抄进报告
- [ ] 顺手判断一句：光看 Codex 转述给你的这段话，**你知道下一步该干什么吗**？

### 7.4 解析失败路径（原文一个字都不能丢）

对 Codex 说：「把这段话交给 save_session_review：今天练得还行，没什么好说的。」

预期（实跑抄回，两段）：

```
ChatGPT已经回复，但没有返回可识别的标准复盘JSON。下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次。
好消息是原文没丢，已经存在 /tmp/ielts-phase9/pending-reviews/<某个编号>.txt。下一步：打开这个文件看看 ChatGPT 到底输出了什么；让它按 get_training_context 给的 reviewRequestPrompt 重新输出一次后再调一次本工具；也可以在 App 的「复盘报告」页点「重新导入待处理的复盘」，或在终端运行 coach reimport 把已落盘的复盘补入库。
```

- [ ] `isError` 是 `true`
- [ ] **那个文件真的在**：`ls -l /tmp/ielts-phase9/pending-reviews/` ← 这一条验的是「先落盘再解析」
- [ ] 第一句里那个「点「补生成复盘报告」」是 App 里的说法，在 Codex 的语境里读着别扭吗？
      （文案观察，写进报告；`DEFINITION-OF-DONE` 第 3 节那张表说过「MCP 的错误文案提 `coach reimport` 可以保留」）

### 7.5 回头补验 `list_practice_history` 的顺序（第 5.4 节欠的那一条）

再让 Codex 调一次 `list_practice_history`：

| 看什么 | 预期（实跑值） |
|---|---|
| `total` / `returned` | `2` / `2`（7.4 那条没归档，不产生记录） |
| 顺序 | **从新到旧**：`…-002`（7.3 那份旧复盘）在前，`…-001`（7.2 那份）在后 |
| `undatedSessionCount` | `0` |
| 每行 | 都有 `hasReport: true`；`…-002` 那行的 `questionId` 是空的（见 7.3） |

- [ ] 顺序对
- [ ] 让 Codex 用 `limit: 1` 再调一次：只返回最新那条，`total` 仍是 2

---

## 8. 【计划 Step 6】收尾、报告与提交

### 8.1 把数据目录改回真实位置（**别忘了这一步**）

```bash
codex mcp remove ielts_speaking          # 路 A 装的
# 或者手工把 ~/.codex/config.toml 里那两段删掉（路 B）
```

想留着日常用的话，重新装一次**不带 env** 的：

```bash
codex mcp add ielts_speaking -- "$HOME/.local/bin/ielts-speaking-mcp"
codex mcp get ielts_speaking --json      # 确认没有 IELTS_SPEAKING_DATA_DIR 这一项
```

- [ ] 重启 Codex，调一次 `initialize_ielts_workspace`，确认 `dataDirectory` 回到
      `~/Library/Application Support/IELTS Speaking Coach`
- [ ] ⚠️ 注意：这一调**会把你真实的 `state.json` 补上五个 settings 键**（第 1 节第三条）。
      那就是升级，是对的；备份还在，心里有底即可

### 8.2 清理

```bash
rm -rf /tmp/ielts-phase9 /tmp/ielts-phase9-sample-review.txt
# 确认真实数据没事之后再删备份：
rm -rf "$HOME/Library/Application Support/IELTS Speaking Coach.phase9-backup"
```

### 8.3 提交

```bash
cd ~/Projects/ielts-speaking-coach-mac
git add docs/phase9-acceptance.md
git commit -m "docs: Phase 9 真机验收结果"
```

### 报告骨架（复制到 `docs/phase9-acceptance.md`）

```markdown
# Phase 9 真机验收结果

日期：
代码基线：分支 phase2-bridge，提交 1caa8e4（自己跑一次 `git log --oneline -1` 核对）
swift test：<条数> 条 / <失败数> 失败
我在哪一侧验的：<终端 codex CLI / ChatGPT.app（com.openai.codex）>
Codex 版本：

## 一、Codex 的配置格式（计划 Step 1）
- 与计划假定（~/.codex/config.toml 的 [mcp_servers.<名字>] + command/args/env）一致吗：
- 我用的是 codex mcp add 还是手工粘贴：
- 我验收的那一侧读不读这份 config.toml：
- 若不一致，实际的格式是：

## 二、7 个工具在 Codex 里都调通了吗（清单第 5、6、7 节）
| 工具 | 调通了吗 | 返回里最该记的那个值 |
| initialize_ielts_workspace | | dataDirectory = |
| get_dashboard_data | | questionTotal/weekDone/weekGoal = |
| set_training_selection | | sessionId = |
| get_training_context | | durationMinutes = ，五个锚点齐不齐 = |
| save_session_review | | issuesAdded/vocabularyAdded = |
| list_practice_history | | total = ，顺序对不对 = |
| open_dashboard | | 窗口起来了吗 = |

## 三、错的时候说清楚了吗（成品标准第 8 条）
- 不存在的题号，Codex 收到的原话：
- 收到之后模型自己纠正了吗，还是甩给你了：
- 不存在的 section，原话：
- save_session_review 收到一段不是复盘的文字，原话：
- 那份原文真的落盘了吗（路径 + ls 结果）：

## 四、旧字段名那份真实复盘（清单 7.3）
- skipped 是哪几个：
- warning 原文：
- 光看这段话，你知道下一步该干什么吗：

## 五、open_dashboard（清单第 6 节）
- lsregister 登记成功了吗（第 3.4 节）：
- 从调用到窗口起来大约几秒：
- 侧边栏跳对页面了吗（试了哪几个 section）：
- open "ieltscoach://nope" 的横幅原文：
- 体验上像不像一回事：

## 六、工具的中文说明，模型是不是照着用了
（有没有出现「参数传错了才发现说明写得不清楚」的情况？哪一个工具的说明最含糊？）

## 七、文案观察（不是判据，但只有你能给）
- open_dashboard 的错误把九个页面名说了两遍，啰嗦吗：
- save_session_review 失败时提「点「补生成复盘报告」」「coach reimport」，在 Codex 语境里读着别扭吗：

## 八、你会用它吗？（成品标准第 5 节，本阶段真正的判据）
（还是宁可直接开 App？什么情况下你会想在 Codex 里调这些工具，什么情况下不会？
 这类信息我拿不到，只有你有。）

## 九、发现的问题与下一步
| 现象 | 该改哪儿 | 要补什么测试 |
| | | |
```

---

## 9. 出事了怎么退回去

- **真实数据被动坏了** → 先 ⌘Q 完全退出 App，再把备份整个换回去：
  ```bash
  rm -rf "$HOME/Library/Application Support/IELTS Speaking Coach"
  cp -R "$HOME/Library/Application Support/IELTS Speaking Coach.phase9-backup" \
        "$HOME/Library/Application Support/IELTS Speaking Coach"
  ```
- **临时目录改坏了** → 按第 3.2、3.3 节重来一遍（两条命令）
- **`~/.codex/config.toml` 被写坏了** → `--write` 那条路径会先备份成
  `config.toml.bak-<时间戳>`；`codex mcp add` 走的是 Codex 自己的写入，出问题用
  `codex mcp remove ielts_speaking` 撤掉
- **Codex 里看不到工具** → 第 4.5 节那条手工命令先分清是哪一侧的问题，**再动东西**
- **窗口打不开** → 第 6.5 节的四步排查顺序
- **不小心让 Codex 往真实目录写了东西** → 备份换回去（第一条）。
  能造成的最大损伤是 `state.json` 被补上五个 settings 键和多出几条记录，不会丢数据

---

## 10. 这份清单与计划 Task 13 的七处出入（子代理发现的）

写下来免得你在现场犹豫。**第 2、3、4、5 条照计划字面走会卡住或记下假缺陷。**

| # | 计划怎么写的 | 实际怎么回事 | 处理 |
|---|---|---|---|
| 1 | 产出文件叫 `docs/phase9-acceptance.md` | 本文件叫 `phase9-acceptance-checklist.md`，与 Phase 4–8 的命名一致；**验收结果仍然写进 `phase9-acceptance.md`** | 无需改动，只是两份文件 |
| 2 | Step 3：「只读的那五个，用真实数据」 | **`initialize_ielts_workspace` 会重写 `state.json`（补五个 settings 键、建三个子目录），`set_training_selection` 会写 `currentSession`**——五个里有两个写盘 | 第 3.2 节改成「复制一份真实数据到 `/tmp/ielts-phase9`」，第 4.2 节用 `env` 把数据目录指过去，**全程不碰真实档案** |
| 3 | Step 5 第 4 步：把过去真实练习留下的复盘交给 `save_session_review`，「确认错题本与词汇本数字从 0 变正、返回里没有 warning」 | 你那份唯一的真实复盘是**字段名修好之前**留下的（`issue`/`examples`/`fix`，`vocabulary` 还是对象），实跑结果是 `issuesAdded 0`、`vocabularyAdded 0`、**必有 warning** | 第 7 节拆成三条路径：7.1 给了一份新格式样本验成功、7.3 用你那份旧文件验**报警**（它恰好是最该验的那条）、7.4 验解析失败 |
| 4 | Step 3：`list_practice_history` 看「最近几场练习都在吗、顺序从新到旧吗」 | 你的 `sessions` 是 **0 条**，一场都没有 | 第 5.4 节先验空状态的 note，第 7.5 节等存完两份复盘之后再回来验顺序 |
| 5 | Step 3：`examinerPrompt` 「和 `coach practice` 发出去的那份对比一眼」 | 跑 `coach practice` 会真开一场 ChatGPT 语音；而三处（CLI / App / MCP）调的**是同一个 `ExaminerPrompt.build`** | 第 5.5 节给了五句逐字锚点，离线核对，比跑一场更彻底 |
| 6 | Step 2：把打印的那段追加进 `~/.codex/config.toml` | 本机的 `codex` 有 `mcp add` 子命令（`--env KEY=VALUE` 现成的），比手工粘贴稳 | 第 4.2 节给了两条路，路 A 推荐 `codex mcp add` |
| 7 | Step 4 的前提只写「.app 已打包并手动双击过一次」 | **现在 `lsregister` 里 `ieltscoach` 零命中**，也就是这个前提当前不成立；而 Info.plist 那一半是好的 | 第 3.4 节把「双击一次 + 用 `lsregister` 复核」列成了硬性前置，不通过就停 |

另外几条计划没提、但现场很容易被误判成缺陷的：

- **`open_dashboard` 的错误把九个页面名说了两遍**（「只能是 …。下一步：把 section 改成这几个之一：…」）——
  啰嗦，但两句各有各的作用（前半句说事实，后半句说动作）。**不是缺陷**，请当文案观察记下来
- **7.3 那一场的 `questionId` 是空字符串**——因为存那份旧复盘之前没有选题，
  工具没有替你猜一道题。**这是对的**，不要记成「题号丢了」
- **App 读的是真实目录，MCP 读的是临时目录**，所以第 5.2 节里两边题目数会差一道
  （副本里多了 3.3 节补的那道 Part 2）。**这是对的**
- **`weekGoal` 显示 5** 是缺 `weeklyGoal` 键时的默认值，不是有人设过 5
