# Phase 8 真机验收清单（给用户本人照着做）

日期：2026-08-07
对应计划：`docs/superpowers/plans/2026-08-06-phase8-plan-and-routes.md` 的 **Task 11**
代码基线：分支 `phase2-bridge`，最后一条提交 `0d2059b`（Task 9）。
**⚠️ Task 10（今日训练页接通三条路线）的改动还在工作区里、没有提交**，
`swift test` 因此有一条红的——详见第 1 节第一条，**那一条不解决就先别开始验收**。
自动化测试现状：`swift test` **1344 条，1 条失败**（12.081 秒）

---

## 0. 这份文件是什么

Task 11 是 Phase 8 唯一**不能由子代理代劳**的任务。前面十个任务的测试跑在纯函数与视图模型上，
证明的是「数据变换对」，证明不了「用起来对」。以下几件事只有你能做：

1. **升级之后你那份真实的 `state.json` 还读不读得出来**——这是 Task 1、2 那两组向后兼容解码
   唯一的真机检验，而唯一能证明它的数据就在你本机上（第 4 节，本清单重点）；
2. **重新生成计划之后，练过的题还算不算练过**——本阶段的成败判据（第 8 节）；
3. **复训那条路线的单点目标，有没有真的进到 ChatGPT 收到的提示词里**——
   目标没带进去而界面上什么都不说，是本项目最危险的那种失败（第 9 节）；
4. **屏幕上显示出来的每一条路线，点下去是不是真的能开练**（第 9、10 节）。

- **你要做的**：按第 3–11 节逐步操作，把每一项的实际结果记下来
- **结果写到哪**：`docs/phase8-acceptance.md`（计划 Task 11 Step 8 指定的文件名，第 12 节给了可直接复制的骨架）
- **大约要多久**：约 60–90 分钟。**含真练一场**（第 8 节要用到，那一场会真的开 ChatGPT 语音）
- **会不会动到你的数据**：第 4 节要用真实数据目录（**先备份**，见第 3 节）；
  第 6 节起全程用 `/tmp/ielts-phase8` 这份演示数据，真实数据不再被碰

---

## 1. ⚠️ 开工前必须先知道的六件事

全部来自刚刚读源码、跑测试、以及读你**真实的** `state.json` 得到的，不是猜的。
不先看，第 4、8、9 节都会当场卡住或者记下假缺陷。

### ⚠️ 一、`swift test` 现在是红的，而且 Task 10 还没提交（头号阻断）

```
Tests/IELTSCoachUITests/NavigationStateTests.swift:112: error:
-[IELTSCoachUITests.NavigationStateTests testTheTodayPageRoutesTheRetrainCardToTheRetrainingCenter]
: XCTAssertTrue failed - `act(_:)` 里没有 `startPractice(route)`，另外三条路线点下去什么都不会发生。
Executed 1344 tests, with 1 failure
```

原因查清了，**不是功能坏了，是一条 Phase 6 时期的源码守卫比对的字符串过期了**：

| | 代码里现在长什么样 | 那条测试比对的是 |
|---|---|---|
| `TodayView.act(_:)` | `startPractice(route, setup: setup)` / `startPractice(route, setup: nil)` | `startPractice(route)` |

Task 10 给 `startPractice` 加了 `setup:` 参数（它就是「解析出来的这一场」的载体），
调用形状变了，而 `NavigationStateTests` 里那句字面量没跟着改。

**处理办法（由开发侧做，不该你来）**：把那条断言的比对串改成 `startPractice(route,`
——约束力不变（仍然钉着「另外三条路线真的会开练」），只是不再依赖旧的调用形状。
改完 `swift test` 应当全绿，然后把 Task 10 的四个文件提交上去。

**在这条变绿、Task 10 提交之前，不要开始下面的验收**：你验的会是一份没有提交的代码，
出了问题也说不清是哪一版。

### ⚠️ 二、你真实的 `state.json` 里 **没有计划、没有练习记录、题库只有 1 道题**

刚读过 `~/Library/Application Support/IELTS Speaking Coach/state.json`（2026-08-07）：

```
schemaVersion: 3
sessions:   0     issues: 0     vocabulary: 0
questions:  1     （id p1-home-001，Part 1 · Home，"What do you like most about your home?"）
targets:    1     （id grammar_sentence_control，label「先说完整主干句，再补充细节」，
                    sourceSessionId "2026-08-05T14:30:44Z" ← sessions 里没有这一场）
plan:       null  ← **没有计划**
settings:   只有 recordingEnabled / recordingConsentAt
            （缺 transcriptEnabled、weeklyGoal、defaultRoute、feedbackTiming、part2PrepMode）
learner.displayName: ""
pending-reviews/sync-1785940167.txt   ← 一份没导回来的复盘
```

这直接决定了**计划 Task 11 Step 2 那张表有两行在你真实数据上根本验不出来**：

| 计划 Step 2 里的那一行 | 在你真实数据上能不能验 |
|---|---|
| 训练记录还在吗 | 能验，但你的记录**本来就是 0 条**——判据要改成「三处数字与升级前的 `state.json` 一致，且页面不是一片空白」 |
| 有没有报「训练数据文件已损坏」 | **能验，而且这是最要紧的一条**（缺三个新键的老文件能不能照常读出来） |
| 已有的计划还在吗 | **验不了**：`plan` 是 `null` |
| 原计划的重点 Part 显示成「全真模考」 | **验不了**，得在**副本**上造一份旧格式计划来补验（第 5 节） |

**第 4 节按这份实情重写过判据**，照计划原文走会得到一堆「不适用」。

顺带两条不要误判成缺陷的：

- **问题档案页顶上会有一张橙色警告卡**（「有 1 次练习只在档案里留了记录……」）。
  来源是上面那条 `targets` 引用了一场 `sessions` 里没有的练习，Phase 7 验收时已经确认过，
  **不是 Phase 8 的账**。
- 首页问候语只有「早上好」没有名字，因为 `displayName` 是空的——**这是对的**。

### ⚠️ 三、「复训一个旧问题」在今日训练页点下去是**换页，不是开练**

计划 Step 5 最后一行写的是「开练后 ChatGPT 收到的提示词里有没有那段「本次唯一目标」」。
**照字面走会卡住**：`TodayView.act(_:)` 的 `.retrain` 那一支直接跳到「复训中心」
（Phase 6 已交付），按钮上写的也是「**去复训中心**」而不是「开始练习」。

这不是缺陷，是刻意的（计划本身第 56–58 行预告过这种情形）：复训要先回看证据、撤掉提示，
在今日训练页直接开练的话，那一场既不带目标也不挂进复训台账。

**所以第 9 节把那一行拆成两段验**：先在今日训练页确认卡片上写出了目标原文，
再进复训中心把那一场真的开起来，然后去 ChatGPT 窗口里翻提示词。

### ⚠️ 四、从复训中心开的那一场**不带你在计划页设的练习偏好**（已知缺口，请如实记）

`RetrainingCoordinator` 调的是
`RetrainingSetupBuilder.makeSetup(target:question:)`——后两个参数用的是函数默认值
（`.deferred` / `.countdown`），**没有从 `settings` 里取**。

后果：你在学习计划页把「反馈时机」改成「当场点出」之后，
从**今日训练页**开的那三条路线会照办（走 `RouteDefaults(settings:)`），
而从**复训中心**开的那一场仍然是「全程零反馈」，界面上一个字都不会提。

第 9 节有一步专门验它。**这一条大概率会不满足**——请照实记下来，它是 Phase 6 与 Phase 8
两个阶段的接口缺口，不是你操作错了。

### ⚠️ 五、演示数据的题库**仍然是空的**（与 Phase 7 同一个坑，这次更致命）

`scripts/seed-demo-data.swift` 写出来的 `state.json` 里 `"questions": []`、`"plan": null`。
Phase 7 时它只是让首页四格不显示；**在 Phase 8 它会让第 7、8、9、10 节全部走不下去**——
没有题就生成不出计划，四条路线里三条不成立。

第 6 节给了一段**已经实跑验证过**的补题命令（补出 Part 1×30、Part 2×8、Part 3×5，共 43 题），
题数是按第 7 节要验的每一档故意配的，别随手改数字。

### ⚠️ 六、演示目录里练一场，同样会真的开 ChatGPT 并起语音

数据写到 `/tmp/ielts-phase8`，**但 ChatGPT 那一侧是你真实的账号**：会真的新建一条会话、
真的进语音通话。第 8 节要用到一次（那是本阶段的成败判据，省不掉）；
**其余各节看到「开始练习」按钮不要顺手点**。

---

## 2. 子代理已经代跑的自动化项（这几条你不用再跑）

每条都是刚刚在本机实际执行过的，输出照抄在这里。**报告里引用即可。**

| 完成标准里的哪一条 | 命令 / 依据 | 实际结果 |
|---|---|---|
| `swift test` 全绿 | `swift test` | ❌ **1344 条，1 失败**。失败原文与根因见第 1 节第一条。**这一条现在不达标** |
| `IELTSCoachCore` 只依赖 Foundation | `grep -rn "^import " Sources/IELTSCoachCore/ \| grep -v Foundation` | **零命中** ✅ |
| 计划页/路线/今日页没有字面颜色、字号、圆角、间距 | `grep -rnE "Color\(red\|cornerRadius: [0-9]\|\.font\(\.[a-z]\|padding\([0-9]\|spacing: [0-9]" Sources/IELTSCoachUI/{Plan,Session,Today}` | **零命中** ✅ |
| 没有 emoji 当图标 | 同样三个目录扫 `✅⚠️🎉👍🔥❌▸` | 4 处命中：2 处在 `#Preview` 假数据、1 处在注释、**1 处在真实文案**——`Session/PracticeRunner.swift:478` 的 `"\n⚠️ 复盘里有 …"`。**那是 Phase 5 的既有代码，不是 Phase 8 新增**，但请在报告里记一笔 |
| 计划天数只有 7/14/30 | `PlanBuilder.supportedLengths == [7, 14, 30]` | ✅ |
| 手写的演示数据能被真实模型读出来 | 实跑 `swift build --product coach` + `IELTS_SPEAKING_DATA_DIR=… coach questions list` | ✅ 读出 43 题（Part 1 = 30 / Part 2 = 8 / Part 3 = 5） |
| **缺 `focusPart` 的旧格式计划能不能解码** | 在你真实数据的**副本**上塞了一份没有 `focusPart` 的 plan，再用 `coach questions list` 读 | ✅ **正常读出，没有报「训练数据文件已损坏」**。第 5 节让你再在界面上确认它显示成「全真模考」 |
| 演示脚本拒绝写入真实数据目录 | `SeedDemoDataScriptTests` 六条安全闸 | ✅ 已自动化，不用手动试 |
| **第 4 节那条判据背后的测试有没有约束力**（突变验证一） | 把 `TrainingPlan.init(from:)` 里 `focusPart` 那两行改成 `try c.decode(FocusPart.self, forKey: .focusPart)`，跑 `swift test --filter TrainingPlanCodableTests` | ✅ **当场变红 2 条**（`testDecodesLegacyPlanWithoutFocusPart` 报 `keyNotFound: focusPart`；`testDecodesUnknownFocusPartStringAsFullMockInsteadOfBrickingTheWholeFile` 报 `dataCorrupted`）。已改回，5 条全绿 |
| **同上**（突变验证二） | 把 `CoachSettings.init(from:)` 里 `defaultRoute` 那两行改成 `try container.decode(String.self, forKey: .defaultRoute)`，跑 `swift test --filter CoachSettingsCompatibilityTests` | ✅ **当场变红 4 条**，其中 `testWholeLegacyStateJSONStillDecodes` 报的正是你真实文件的那种形状（`keyNotFound: defaultRoute, Path: settings`）。已改回，7 条全绿 |

**打包这一条子代理没有替你跑**：`build-app.sh` 要用钥匙串里那把私钥，
在非交互会话里可能弹出「codesign 想访问密钥」的授权框，那会把整个会话挂住。
**留给你在第 3 节做掉。**

---

## 3. 准备工作（约 10 分钟）

### 3.1 备份真实数据目录（**这一步在打开 App 之前做，不许跳过**）

```bash
cp -R "$HOME/Library/Application Support/IELTS Speaking Coach" \
      "$HOME/Library/Application Support/IELTS Speaking Coach.phase8-backup"
```

- [ ] 备份完成，且 `ls` 得到确认

> **为什么必须先备份**：只是「打开 App 看一眼」确实不会改写 `state.json`
>（`StateStore.load()` 只读，只有 `mutate` 才写盘）。但第 4 节之后你会在真实数据上
> **改练习偏好**，那一下就会把三个新键写进去。写进去本身是对的（这正是升级），
> 但万一中途发现问题，你要有一份**升级前的原件**能拿回来对照，否则「到底丢没丢」
> 就永远说不清了。

### 3.2 记下升级前的数字（只读，不动文件）

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/Library/Application Support/IELTS Speaking Coach/state.json")
d = json.load(open(p))
for k in ["sessions", "issues", "vocabulary", "questions", "targets", "questionSources"]:
    print("%-15s %d" % (k, len(d.get(k) or [])))
print("plan            ", "有" if d.get("plan") else "没有")
print("settings 里的键  ", sorted((d.get("settings") or {}).keys()))
PY
```

- [ ] 把这段输出**原样抄进报告**（第 12 节骨架里有位置）。它是第 4 节唯一的对照基准

> 上面那段必须**顶格粘贴**，一个前导空格都不能带：它是 heredoc，非 `<<-` 形式的结束符 `PY`
> 只有顶格才算数，而 Python 收到的每一行都会原样带着前导空格（Phase 7 实测踩过）。

### 3.3 连打包两次，确认签名稳定（成品标准第 9 条 / 计划 Step 1）

```bash
cd ~/Projects/ielts-speaking-coach-mac
./scripts/build-app.sh >/dev/null && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated
./scripts/build-app.sh >/dev/null && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated
```

- [ ] **两行一模一样**。不一致 = 辅助功能授权会反复失效，**立刻停下报告，不要往下走**
- [ ] 第一次跑时若弹出「codesign 想使用钥匙串里的私钥」，点「始终允许」

---

## 4. 【计划 Step 2】升级兼容性 —— **本阶段最该先验的一条**

> Task 1、Task 2 那两组向后兼容解码，全部的意义就在这一步。
> 单元测试证明的是「我构造的那份老 JSON 能读出来」；
> **只有你本机这一份真实的 `state.json` 能证明「升级之后训练记录没丢」。**

### 4.1 打开 App

```bash
open ".build/IELTS Speaking Coach.app"
```

- [ ] **没有再要一次辅助功能授权**。又被要求授权就**立刻停下并报告**——
      那说明签名稳定性回归了（Phase 3 完成标准第 3、4 条）

### 4.2 逐条确认（判据已按你真实数据的实情改写过，见第 1 节第二条）

| 看什么 | 判据 | 不满足时 |
|---|---|---|
| **有没有报「训练数据文件已损坏」** | **完全没有出现**。你那份 `settings` 里缺 `defaultRoute` / `feedbackTiming` / `part2PrepMode` 三个新键，这一步验的就是缺键照样读得出来 | **立刻停下报告**，并把备份目录换回去 |
| 训练记录还在吗 | 训练记录页、复盘报告页、问题档案页、我的词汇页的条数**与 3.2 抄下来的数字一致**（都是 0） | 立刻停下报告 |
| 题库还在吗 | 训练题库页仍是 **1 道题**（`p1-home-001`，Part 1 · Home） | 立刻停下报告 |
| 待处理的复盘还在吗 | 复盘报告页右上角写着「**待处理 1 份**」 | 记下来 |
| 三项练习偏好显示成默认值 | 学习计划页最下面：默认练习路线 = **按计划练今天**，反馈时机 = **全程零反馈**，Part 2 准备时间 = **一分钟倒计时** | 记下来（这是缺键回落的直接证据） |
| 今日训练页 | 只有**一条**路线卡片：「从题库自由选题」（紫色主行动）。**没有**「按计划练今天」（没计划）、**没有**「继续上次练习」（没记录）、**没有**「复训一个旧问题」（那条 target 的来源练习不在 `sessions` 里） | 多出任何一条 = 「显示出来却开不了练」，记下来 |
| 学习计划页 | 空状态「**你还没有学习计划**」+ 下面一段「有计划之后……」+ 一颗「**去下面选周期和重点 Part**」的按钮 | 一片空白就是缺陷 |
| 生成按钮 | **是灰的**，旁边逐字写着：「全真模考（Part 1 + 2 + 3）现在只有 1 道题，分不满 7 天，会有整天没题可练。下一步：到「训练题库」页导入更多题目——最短的 7 天计划也需要至少 7 道题。」 | 灰按钮旁边没有解释 = 缺陷（铁律 6） |

- [ ] **以上任何一条不满足，立刻停下并报告，不要继续往下做。**
      退回办法见第 13 节（要先 ⌘Q 完全退出 App）

### 4.3 顺手验一条只有真实数据能验的

- [ ] 在学习计划页把「反馈时机」改成「**当场点出**」，⌘Q 退出，重新打开——**还是「当场点出」**
- [ ] 再打开 `state.json` 看一眼，`settings` 里现在应当**多出了** `defaultRoute`、
      `feedbackTiming`、`part2PrepMode` 三个键（这就是「升级」发生的那一刻）
- [ ] 验完**改回「全程零反馈」**（第 9 节还要用它做对照）

```bash
python3 -c "
import json, os
p = os.path.expanduser('~/Library/Application Support/IELTS Speaking Coach/state.json')
print(sorted(json.load(open(p))['settings'].keys()))
"
```

---

## 5. 补验「旧计划的重点 Part 回落成全真模考」（在**副本**上做，不碰真实数据）

你真实数据里 `plan` 是 `null`，所以这条判据只能造一份旧格式计划来验。
**造在副本上**，真实目录一个字节都不动。

```bash
rm -rf /tmp/ielts-phase8-upgrade
cp -R "$HOME/Library/Application Support/IELTS Speaking Coach" /tmp/ielts-phase8-upgrade
```

```bash
python3 - <<'PY'
import json
p = "/tmp/ielts-phase8-upgrade/state.json"
d = json.load(open(p))
d["plan"] = {
    "lengthDays": 7,
    "createdAt": "2026-08-05T13:10:00Z",
    "days": [{"id": 1, "questionIds": ["p1-home-001"], "completedQuestionIds": []}]
}
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
print("已在副本里造了一份没有 focusPart 的旧格式计划")
PY
```

（这两段我已经实跑过：写完之后 `coach questions list` 照常读出 1 题，没有报「训练数据文件已损坏」。）

- [ ] ⌘Q **完全退出**刚才那个 App，然后带着副本目录打开：

```bash
IELTS_SPEAKING_DATA_DIR=/tmp/ielts-phase8-upgrade \
  ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"
```

> **注意用的是 `.app` 里的二进制加环境变量，不是 `open`。**
> `open` 传不进环境变量，会打到你真实的数据目录上去。

- [ ] 学习计划页最上面那张卡写着：「**7 天计划 · 全真模考（Part 1 + 2 + 3）**」
      ← 这就是 Task 1 那条回落（旧数据没有 `focusPart`）
- [ ] 进度那一行：「**已完成 0 / 1 题**」，下面一根紫色进度条
- [ ] 「每日安排」里只有「**第 1 天**」这一张卡，带一个「**今天练这几道**」的标记（`arrow.right.circle` 图标 + 文字）
- [ ] 概览里那句：「今天是第 1 天。这里的「第几天」按练完的进度走，不按日历。中间停几天回来，它还在原地等你。」
      **这句话必须在屏幕上**（计划要求：不写的话，请假两天回来的人会以为自己落后了）
- [ ] 没有报「训练数据文件已损坏」

- [ ] ⌘Q 退出，`rm -rf /tmp/ielts-phase8-upgrade`

---

## 6. 造 Phase 8 的演示数据（第 7 节起全程用它）

```bash
cd ~/Projects/ielts-speaking-coach-mac
swift scripts/seed-demo-data.swift /tmp/ielts-phase8
```

应当打印「✅ 演示数据已写入 /tmp/ielts-phase8」。**它的题库是空的**，接着补题：

**下面这段必须顶格粘贴**（heredoc，理由同 3.2）。

```bash
python3 - <<'PY'
import json
p = "/tmp/ielts-phase8/state.json"
d = json.load(open(p))

part1 = [
    ("Home", "What do you like most about your home?"),
    ("Work", "Do you work or are you a student?"),
    ("Travel", "How do you usually get to work or school?"),
    ("Daily routine", "Do you prefer mornings or evenings?"),
    ("Food", "How often do you cook at home?"),
    ("Music", "What kind of music do you listen to?"),
    ("Shopping", "Do you enjoy shopping?"),
    ("Weekends", "How do you spend your weekends?"),
    ("Hometown", "Do you like the area you live in?"),
    ("School", "What was your favourite subject at school?"),
    ("Transport", "Do you use public transport often?"),
    ("Sport", "How important is exercise to you?"),
    ("Phones", "Do you prefer texting or calling?"),
    ("Weather", "What kind of weather do you like best?"),
    ("Reading", "Do you read much in your free time?"),
    ("Photos", "Do you take a lot of photographs?"),
    ("Friends", "How often do you meet your friends?"),
    ("Animals", "Are there many pets in your country?"),
    ("Colours", "Is there a colour you never wear?"),
    ("Gifts", "When was the last time you gave someone a gift?"),
    ("Holidays", "What do people in your country do on public holidays?"),
    ("Cinema", "Do you prefer watching films at home or at the cinema?"),
    ("Time", "Are you usually on time?"),
    ("Plants", "Do you have any plants at home?"),
    ("News", "How do you usually get the news?"),
    ("Cooking", "Who does most of the cooking in your family?"),
    ("Noise", "Is the place where you live noisy?"),
    ("Handwriting", "Do you often write things by hand?"),
    ("Sleep", "How many hours do you usually sleep?"),
    ("Languages", "Would you like to learn another language?"),
]
part2 = [
    "Describe a book you enjoyed reading.",
    "Describe a place you would like to visit.",
    "Describe a person who has helped you.",
    "Describe a skill you learned recently.",
    "Describe a time you were very busy.",
    "Describe an object you use every day.",
    "Describe a meal you remember well.",
    "Describe a piece of good news you received.",
]
part3 = [
    "Why do people read less than they used to?",
    "How does tourism change a city?",
    "Should schools teach more practical skills?",
    "Do people learn better alone or in groups?",
    "How has technology changed the way families talk?",
]

qs = [{"id": "demo-q0", "part": 1, "topic": part1[0][0], "prompt": part1[0][1]}]
for i, (topic, prompt) in enumerate(part1[1:], start=1):
    qs.append({"id": "p8-p1-%02d" % i, "part": 1, "topic": topic, "prompt": prompt})
for i, prompt in enumerate(part2, start=1):
    qs.append({"id": "p8-p2-%02d" % i, "part": 2, "topic": "Long turn", "prompt": prompt})
for i, prompt in enumerate(part3, start=1):
    qs.append({"id": "p8-p3-%02d" % i, "part": 3, "topic": "Discussion", "prompt": prompt})

d["questions"] = qs
d["sessions"][-1]["goal"] = "每个回答先说完整主干句"
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
print("题库补好了：共 %d 题（Part 1: %d，Part 2: %d，Part 3: %d）"
      % (len(qs), sum(1 for q in qs if q["part"] == 1),
         sum(1 for q in qs if q["part"] == 2), sum(1 for q in qs if q["part"] == 3)))
PY
```

- [ ] 打印「题库补好了：共 43 题（Part 1: 30，Part 2: 8，Part 3: 5）」

**题数是按第 7 节要验的每一档故意配的**（30 / 8 / 5 分别覆盖「够」「差一点」「差很多」三种），
别随手改。`demo-q0` 这个 id 也不能改——演示数据里最近那一场练习和那个复训目标都指着它，
改了「继续上次练习」和「复训一个旧问题」两条路线就都不出现了。

- [ ] 备份这份补好的演示数据（第 10 节要故意改坏它）：

```bash
cp /tmp/ielts-phase8/state.json /tmp/ielts-phase8/state.json.bak
```

- [ ] 带着演示数据打开 App：

```bash
IELTS_SPEAKING_DATA_DIR=/tmp/ielts-phase8 \
  ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"
```

---

## 7. 【计划 Step 3】学习计划页逐项验收

点侧边栏「学习计划」。此刻还没有计划。

### 7.1 空状态

- [ ] 「**你还没有学习计划**」
- [ ] 下面一句：「有计划之后，「今日训练」页会直接告诉你今天练哪几道题，不用每次自己想。
      下一步：在下面的表单里选好周期和重点 Part，再生成一份。」
- [ ] 一颗「**去下面选周期和重点 Part**」的按钮，**点下去页面真的滚到表单**
      （只写一句「在下面」而不滚过去，等于让用户自己找）

### 7.2 切换周期与重点 Part —— 那行预览要**立刻**跟着变

表单：周期是 7 / 14 / 30 三档分段控件，重点 Part 是四个单选。逐格对：

| 重点 Part | 7 天 | 14 天 | 30 天 |
|---|---|---|---|
| 全真模考（Part 1 + 2 + 3） | 现在 43 题，分 7 天，**每天 6–7 题** | 43 题，分 14 天，**每天 3–4 题** | 43 题，分 30 天，**每天 1–2 题** |
| Part 1（日常话题问答） | 30 题，**每天 4–5 题** | 30 题，**每天 2–3 题** | 30 题，**每天 1 题** |
| Part 2（个人陈述） | 8 题，**每天 1–2 题** | ⛔ 生成不了 | ⛔ 生成不了 |
| Part 3（深入讨论） | ⛔ 生成不了 | ⛔ 生成不了 | ⛔ 生成不了 |

- [ ] 九个能生成的组合，那行字**每换一次选择就立刻变**，且题数、天数、每天几题都对得上
- [ ] 那行字的完整形状是：「〈重点 Part 的中文名〉现在 N 题，分 M 天，每天 X 题」

### 7.3 生成不了的组合：**灰按钮旁边必须写清为什么和怎么办**（本阶段的硬标准之一）

三种阻断文案各验一次，**逐字对**：

- [ ] **Part 2 + 14 天**（有可行档位）：
      「Part 2（个人陈述）现在只有 8 道题，分不满 14 天，会有整天没题可练。
      下一步：**把周期改成 7 天**，或先到「训练题库」页导入更多题目。」
- [ ] **Part 3 + 7 天**（一档都不可行）：
      「Part 3（深入讨论）现在只有 5 道题，分不满 7 天，会有整天没题可练。
      下一步：到「训练题库」页导入更多题目——**最短的 7 天计划也需要至少 7 道题**。」
- [ ] 这两种情况下「生成计划」按钮**是灰的**，且上面那段字**就在按钮旁边**（不是藏在别处）
- [ ] 阻断那一行左边有一个 `exclamationmark.triangle` 图标，**正文本身是正常的深色字**
      （不是整段橙色——整段警告色的中文正文对比度过不了线）
- [ ] 按上面那句「把周期改成 7 天」真的照做一次，确认按钮**当场变成可点**
      （**这一条最要紧**：说明里给的下一步必须真的管用）

### 7.4 生成一份计划

- [ ] 选「**Part 1（日常话题问答）**」+「**7 天**」，点「**生成计划**」（第一次生成**不弹确认框**，这是对的）
- [ ] 页面顶部出现一张说明卡，逐字应当是：
      「已生成 7 天计划：Part 1（日常话题问答），共 30 道题。下一步：回「今日训练」页点「按计划练今天」就能开始。」
      带一颗「知道了」按钮，**不是几秒后自己消失的浮层**
- [ ] 概览：「**7 天计划 · Part 1（日常话题问答）**」、「**已完成 0 / 30 题**」
- [ ] 「每日安排」7 张卡，**第 1 天带「今天练这几道」标记**，每张卡右侧写「共 N 题」「还没练完」
- [ ] 每一行题目前面有一个空心圆（还没练），后面是 `Part 1` 徽标 + 话题 + 题干
- [ ] 「今天」那一天**默认被滚到**（把窗口调矮一点更明显）
- [ ] 那句「按练完的进度走，不按日历」**在屏幕上**

### 7.5 练习偏好（改完要能存住）

- [ ] 三项都在：默认练习路线 / 反馈时机 / Part 2 准备时间
- [ ] 每一项下面都有一句说清代价的小字，例如反馈时机那句：
      「全程零反馈像真考试，但答砸的地方要等到最后才知道；当场点出纠正及时，
      代价是不再是真实考试节奏，单场时间也会拉长。」
- [ ] 把三项都改掉（默认路线 → **继续上次练习**，反馈时机 → **当场点出**，Part 2 → **自己决定**）
- [ ] ⌘Q 退出，用第 6 节那条命令重开，**三项都还是改后的值**
- [ ] 回到今日训练页：**最上面那张紫色主行动卡片变成了「继续上次练习」**
      （默认路线决定卡片顺序，第一张就是主行动）
- [ ] 验完把三项**改回**：默认路线 = 按计划练今天，反馈时机 = 全程零反馈，Part 2 = 一分钟倒计时

### 7.6 删除计划的确认框（**先别真删**，第 10 节还要用这份计划）

- [ ] 点「**删除计划**」，确认框标题「**删除计划？**」，正文逐字：
      「删掉之后「今日训练」页的「按计划练今天」会消失，但练习记录、复盘和题目的已练标记都还在。
      下一步：随时可以回到这一页重新生成一份计划。」
- [ ] **点「取消」**。确认框回车/ESC 的落点应当是「取消」，不是「删除」
- [ ] 「删除计划」那颗按钮**不是紫色实心**（整页只能有一个主行动，那一个是「生成计划」）
- [ ] 它下面那句「练习记录、复盘和题目的已练标记都不会跟着删掉。」在

---

## 8. 【计划 Step 4】重新生成不丢进度 —— **本阶段的成败判据**

按顺序做，**每一步把界面上的实际数字记下来**。

### 8.1 先记下基准数字

```bash
python3 -c "
import json
d = json.load(open('/tmp/ielts-phase8/state.json'))
print('sessions', len(d['sessions']), '| issues', len(d['issues']),
      '| vocabulary', len(d['vocabulary']), '| targets', len(d['targets']))
"
```

- [ ] 抄下来（演示数据的基线应当是 sessions 12 / issues 5 / vocabulary 6 / targets 1）

### 8.2 真练一场（这一场会真的开 ChatGPT 语音）

- [ ] 回「今日训练」页，最上面那张紫色卡片是「**按计划练今天**」，
      详情里写着「计划的第 1 天，共 5 道题，已经练完 0 道。」（7 天 30 题 → 第 1 天 5 道）
- [ ] **点列表里的第一道题**（整行可点），记下它的题干
- [ ] 练习弹层里应当依次出现进度：新建会话 → 启动语音（**约 9 秒，界面必须一直在说话**）→
      发考官提示词 → 练习中
- [ ] 练完点结束，让它取复盘并存档，**停在「完成」而不是「失败」**

> **复盘取回失败了怎么办**：弹层会说清断在哪一步，原文已经落进 `pending-reviews/`，一个字都没丢。
> 到「复盘报告」页点右上角进「**重新导入待处理的复盘**」，把那一份重新导入，
> 计划进度会随之前进。**这一步本身也是成品标准第 7 条的验收，顺手记下来。**

- [ ] 回「学习计划」页：**那道题前面变成了实心勾**，进度从「已完成 0 / 30 题」变成「**已完成 1 / 30 题**」

> **万一今天没法真练**：可以用下面这条命令把某道题手工标成已完成，只验「重新生成不丢进度」这一半。
> **但要在报告里写明你走的是这条路**——它证明不了 `ReviewArchiver.advancePlan` 那一段。
> ```bash
> python3 -c "
> import json
> p='/tmp/ielts-phase8/state.json'
> d=json.load(open(p))
> q=d['plan']['days'][0]['questionIds'][0]
> d['plan']['days'][0]['completedQuestionIds']=[q]
> json.dump(d, open(p,'w'), ensure_ascii=False, indent=2); print('已把', q, '标成练过')
> "
> ```

### 8.3 改周期重新生成 —— **进度必须还在**

- [ ] 把周期改成「**14 天**」（重点仍是 Part 1），点「**重新生成计划**」
- [ ] 这次**弹确认框**，标题「重新生成计划？」，正文逐字：
      「已经练过的题仍然算已完成，练习记录、复盘、错题本、词汇本都不受影响。
      下一步：确认后会按你选的周期和重点 Part，重排今后的每日安排。」
- [ ] 确认。说明卡应当写：
      「已生成 14 天计划：Part 1（日常话题问答），共 30 道题。**你之前练过的 1 道题仍然算已完成。**
      下一步：回「今日训练」页点「按计划练今天」就能开始。」
- [ ] **进度仍然是「已完成 1 / 30 题」**，那道题在新的每日安排里**仍然打着勾**

  ❌ 不满足 = **本阶段没做完**，立刻停下报告

### 8.4 换重点 Part 再来一次 —— **进度仍然必须还在**

- [ ] 重点改成「**全真模考（Part 1 + 2 + 3）**」，周期仍 14 天，重新生成
- [ ] 说明卡：「已生成 14 天计划：全真模考（Part 1 + 2 + 3），共 43 道题。你之前练过的 1 道题仍然算已完成。……」
- [ ] 进度变成「**已完成 1 / 43 题**」，那道题**仍然打着勾**

  ❌ 不满足 = **本阶段没做完**，立刻停下报告

- [ ] 顺手验一次「题掉出范围」的说法：把重点改成「**Part 2（个人陈述）**」+ **7 天**，重新生成。
      说明卡应当多出一段：「另有 1 道练过的题不在新计划范围内（换了重点 Part，或换季重新导入时
      题库里没有它了）；它们的练习记录与复盘仍然保留在「训练记录」和「复盘报告」里，没有丢。」
- [ ] 再改回「全真模考 + 14 天」重新生成，**那道题又回到已完成**（进度回到 1 / 43）
      ← 这证明进度是按题目 id 搬的，不是被谁清掉了

### 8.5 记录一条都不许少

```bash
python3 -c "
import json
d = json.load(open('/tmp/ielts-phase8/state.json'))
print('sessions', len(d['sessions']), '| issues', len(d['issues']),
      '| vocabulary', len(d['vocabulary']), '| targets', len(d['targets']))
"
```

- [ ] 与 8.1 的基准比：**只增不减**（真练了一场的话 sessions +1，issues/vocabulary/targets 可能因复盘增加）
- [ ] 界面上再核一遍：**训练记录页、复盘报告页、问题档案页、我的词汇页，四处一条都没少**

  ❌ 少了任何一条 = **本阶段没做完**，立刻停下报告

---

## 9. 【计划 Step 5】四条路线各走一遍（**把终端关掉**）

计划这一步的原话是「把终端关掉」——成品标准第 2 条要求全程不需要终端。
（第 6 节那条带环境变量的启动命令是验收的脚手架，不算数；但**验收过程中不许再回终端做任何事**。）

### 9.1 按计划练今天

- [ ] 卡片详情写着「计划的第 N 天，共 X 道题，已经练完 Y 道。」，下面列出今天这几道题
- [ ] **练过的那道前面是实心勾**，没练的是空心圆
- [ ] 点整张卡片的「开始练习」→ 自动挑的是**今天第一道没练的**（不是已经练过的那道）
      —— 弹层出来之后确认题干，**然后关掉弹层**（不用真练第二场）

### 9.2 从题库自由选题

- [ ] 卡片上写着「题库里现在有 **43** 道题。点右边那颗按钮之后先挑一道，挑好才会开始。」
- [ ] 点「开始练习」→ 弹出**挑题列表**，能按 Part 筛
- [ ] 选中一道之后能开练（确认按钮变可点即可，**不用真练**），然后关掉

### 9.3 继续上次练习

- [ ] 卡片上写着「上次练的：**Home** · What do you like most about your home?」
- [ ] 「练的时间：〈今天的日期〉」
- [ ] 「**上次盯的目标：每个回答先说完整主干句**」← 上次有目标就必须显示出来
      （**演示数据里这个目标是第 6 节那段命令写进去的**，不是你练出来的）
- [ ] 点「开始练习」，弹层里应当出现一行「**本次目标：每个回答先说完整主干句**」
      —— 这就是「继续上次」把目标带过去了。**这一场可以真练也可以就此关掉**；
      要验目标有没有进提示词，用下面 9.4 那条更彻底

### 9.4 复训一个旧问题（**本节重点，且计划写的路径已经变了**）

**先在今日训练页确认卡片说了什么：**

- [ ] 卡片标题「复训一个旧问题」，副标题「带上一次复盘给出的目标」
- [ ] 详情第一行：「**排在最前面的目标：回答后补一个原因和一个例子**」
      ← **卡片上必须有目标原文**。没有的话，这条路线和普通练习在用户眼里没区别
- [ ] 详情第二行：「它出自 〈日期〉 那一场练习的复盘。到复训中心可以先回看当时的证据，再决定重练哪一个。」
- [ ] 按钮上写的是「**去复训中心**」，**不是**「开始练习」（点下去是换页，写「开始练习」就是骗人）
- [ ] 点它 → **真的跳到「复训中心」页**，且那个目标是选中的

**然后在复训中心把这一场真的开起来**（第二场真练，这一节的目的就是它）：

- [ ] 复训流程里「**本次唯一目标**」那一行显示的是同一句话：「回答后补一个原因和一个例子」
- [ ] 点「带着这个目标重练」，等它把提示词发出去
- [ ] **切到 ChatGPT 窗口，把发出去的那条提示词从头翻一遍**，确认里面有：

```
本次唯一目标：回答后补一个原因和一个例子
考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
```

  ❌ **这两行没有 = 白练一场，而且界面上看不出任何异样**。这是本项目最危险的失败形态，
  立刻停下报告

### 9.5 练习偏好有没有真的进提示词（第 1 节第四条那个已知缺口）

在同一个 ChatGPT 窗口里接着翻那条提示词：

- [ ] 现在设置里是「全程零反馈」，提示词里应当有
      `I will save all feedback until the end.`
- [ ] 回学习计划页把「反馈时机」改成「**当场点出**」，然后：
      - [ ] 从**今日训练页**开一场（任意路线）→ 提示词里应当变成
            `give exactly ONE short correction in 中文`。**这一条应当满足**
      - [ ] 从**复训中心**开一场 → 提示词里**大概率仍然是** `I will save all feedback until the end.`
            ← 第 1 节第四条说的那个缺口。**照实记下来**，并写清你实际看到的是哪一句

---

## 10. 【计划 Step 6】制造三种「路线不可用」

每一条的判据都是同一个：**读得懂**。找一个不懂技术的人试着照做（成品标准第 8 条的原话）。

### 10.1 删掉计划

- [ ] 学习计划页点「删除计划」→ 确认 → 说明卡：
      「计划已经删掉了。练习记录、复盘和题目的已练标记都还在。下一步：想重新排一份的话，
      在下面选好周期和重点 Part 再生成。」
- [ ] 回今日训练页：「**按计划练今天**」那张卡片**整个消失**，
      **不是变灰、也不是点了没反应**
- [ ] 训练记录、复盘报告、问题档案、我的词汇四处**一条都没少**（确认框逐字承诺过这件事）

### 10.2 计划里今天那道题从题库里消失

先重新生成一份**每天只有 1 题**的计划，好让「今天」只依赖一道题：

- [ ] 学习计划页选「**Part 1** + **30 天**」（30 题分 30 天，每天 1 题），生成
- [ ] 记下「第 1 天」那道题的题干

然后 ⌘Q 退出，把那道题从题库里删掉：

```bash
python3 -c "
import json
p='/tmp/ielts-phase8/state.json'
d=json.load(open(p))
gone=d['plan']['days'][0]['questionIds'][0]
d['questions']=[q for q in d['questions'] if q['id']!=gone]
json.dump(d, open(p,'w'), ensure_ascii=False, indent=2)
print('已把', gone, '从题库里删掉（计划里还留着它）')
"
```

- [ ] 用第 6 节那条命令重开 App
- [ ] **今日训练页**：「按计划练今天」那张卡片**消失了**
      —— 这是对的（显示一条点了没用的路线比不显示更糟），
      但请判断一句：**光看这一页，你看得出发生了什么吗？** 照实写进报告
- [ ] **学习计划页**：第 1 天那一行**照常显示**，徽标变成「**题目已失效**」，
      题干位置换成一段警示色的中文：
      「这道题已经不在题库里了（换季重新导入时可能被删掉）。下一步：在本页重新生成计划把它换掉，
      已经练过的进度不会丢。」
      ← **说明在这一页，不在今日训练页**。空白行或者整行消失都是缺陷
- [ ] 照那句话点一次「重新生成计划」，确认那一行真的被换掉了

- [ ] 还原：`cp /tmp/ielts-phase8/state.json.bak /tmp/ielts-phase8/state.json`

### 10.3 全新的空数据目录

```bash
rm -rf /tmp/ielts-phase8-empty && mkdir -p /tmp/ielts-phase8-empty
IELTS_SPEAKING_DATA_DIR=/tmp/ielts-phase8-empty \
  ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"
```

（先 ⌘Q 完全退出上一个，否则只是把已经在跑的那个切到前台。）

- [ ] **今日训练页整页只有一件事**：「**题库还是空的**」+「没有题目，四条练习路线一条都走不通。
      下一步：到「训练题库」页导入你的题库文件（…），导完回到这一页就能开始。」+ 一颗「去训练题库」按钮
      ← 四条路线卡片**一条都不显示**是对的
- [ ] **学习计划页**：空状态「你还没有学习计划」，生成按钮是灰的，旁边写着
      「题库里没有全真模考（Part 1 + 2 + 3）的题目，生成不了计划。
      下一步：换一个重点 Part，或到「训练题库」页导入含该 Part 的题目。」
- [ ] ⚠️ **请判断一句**：题库整个是空的时候，「换一个重点 Part」这个下一步**根本没用**
      （四个 Part 都是 0 题）。你照着做会不会白转一圈？觉得该改成
      「先到「训练题库」页导入题库」的话，写进报告——这是文案缺陷，不是你理解错了
- [ ] ⌘Q，`rm -rf /tmp/ielts-phase8-empty`

---

## 11. 【计划 Step 7】界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节十条）

用第 6 节的演示数据重开 App，学习计划页 + 今日训练页各走一遍。

- [ ] **先在计划页生成一份「全真模考 + 14 天」的计划**——第 10.2 节末尾那次还原
      把计划也一起还原掉了（`state.json.bak` 是第 6 节、还没有计划时存的），
      不先生成的话，下面那段等宽数字的命令会因为 `plan` 是 `null` 直接报错

其中三条最容易被忽略，也最该细验：

- [ ] **打开系统「减弱动态效果」**（系统设置 › 辅助功能 › 显示）之后，
      计划页**无动画且功能正常**（生成 / 重新生成 / 删除 / 滚到今天，四样都要试）
- [ ] **系统文字调到最大**（系统设置 › 辅助功能 › 显示 › 文字大小）之后，
      **每日拆分列表不截断、不重叠**。
      ⚠️ 最可能崩的是「30 天 · 每天 1 题」那种长题干行，以及首页四格
      （`LazyVGrid(.adaptive(minimum: 220))` + 长脚注）。**崩了就截图**
- [ ] **进度数字变化时不抖动**（等宽数字）。这么造（改之前先 ⌘Q 退出 App）：

```bash
python3 -c "
import json
p='/tmp/ielts-phase8/state.json'
d=json.load(open(p))
ids=[q for day in d['plan']['days'] for q in day['questionIds']][:10]
done=set(ids[:9])
for day in d['plan']['days']:
    day['completedQuestionIds']=[q for q in day['questionIds'] if q in done]
json.dump(d, open(p,'w'), ensure_ascii=False, indent=2); print('已标成练过 9 题')
"
```
      重开看「已完成 **9** / N 题」，再把上面的 `[:9]` 改成 `[:10]` 跑一遍看「已完成 **10** / N 题」。
- [ ] 两次之间**那一行横向纹丝不动**。整行左右跳 = 漏了 `.monospacedDigit()`，记下是哪一处
- [ ] 验完还原：`cp /tmp/ielts-phase8/state.json.bak /tmp/ielts-phase8/state.json`

其余七条顺手过：

- [ ] 视图里没有字面颜色/字号/圆角/间距——静态扫描第 2 节已代跑，零命中；这里靠眼睛复核有没有哪块看起来是临时凑的
- [ ] 正文与次要文字都读得清（阻断说明那一段压在白卡上尤其要看）
- [ ] 没有 emoji 当图标（本阶段用的是 `calendar` / `arrow.right.circle` / `checkmark.circle.fill` /
      `circle` / `exclamationmark.triangle`）
- [ ] **每页只有一个主行动**：计划页只有「生成计划 / 重新生成计划」是紫色实心，
      「删除计划」是次一级；今日训练页只有排第一的那条路线是紫色大卡片
- [ ] **Tab 能走遍**周期分段控件、四个重点 Part 单选、生成按钮、删除按钮、三项偏好、
      每日安排里可点的元素，**焦点环可见**。
      先在「系统设置 › 键盘」里打开「使用键盘导航在控制项之间移动焦点」（macOS 默认是关的），
      **报告里注明你是在哪种设置下测的**
- [ ] **所有超过 300ms 的操作都有进度提示**（本阶段最长的是开练那 9 秒：
      「新建会话 → 启动语音 → 发考官提示词」三段字必须一直在动）
- [ ] 每个空状态都有「说明 + 下一步 + 按钮」三样（计划页空状态、今日训练页题库空、
      今日训练页没有练习记录、没有问题变化，四处都看一眼）

---

## 12. 收尾、报告与提交

- [ ] 把每一项的实际结果写进 `docs/phase8-acceptance.md`（骨架在下面），**包括不好的部分**
- [ ] 确认真实数据目录没有被玩坏（第 4 节之后就没再碰过它）
- [ ] 验证无误后删掉备份与演示数据：

```bash
rm -rf "$HOME/Library/Application Support/IELTS Speaking Coach.phase8-backup"
rm -rf /tmp/ielts-phase8 /tmp/ielts-phase8-upgrade /tmp/ielts-phase8-empty
```

```bash
cd ~/Projects/ielts-speaking-coach-mac
git add docs/phase8-acceptance.md
git commit -m "docs: Phase 8 真机验收结果"
```

### 报告骨架（复制到 `docs/phase8-acceptance.md`）

```markdown
# Phase 8 真机验收结果

日期：
代码基线：分支 phase2-bridge，提交 <填 Task 10 提交之后的 sha>
swift test：<条数> 条 / <失败数> 失败
键盘导航设置：<系统「键盘导航」开 / 关>

## 零、升级前的基准数字（清单 3.2 的输出，原样贴）

## 一、升级兼容性（清单第 4、5 节，本阶段头号判据）
- 有没有报「训练数据文件已损坏」：
- 四处记录条数与升级前是否一致：
- 题库、待处理复盘还在吗：
- 三项练习偏好是不是默认值（缺键回落）：
- 改一项偏好 → 重启后还在吗：
- state.json 里是否多出了 defaultRoute / feedbackTiming / part2PrepMode：
- 副本上那份旧格式计划显示成「全真模考」了吗：

## 二、重新生成不丢进度（清单第 8 节，本阶段成败判据）
- 练的是哪道题、复盘归档成功了吗（还是走了手工标记那条替代路径）：
- 练完之后进度：已完成 __ / __
- 改成 14 天重新生成之后：已完成 __ / __        ← 必须还是练过的
- 换成全真模考重新生成之后：已完成 __ / __      ← 必须还是练过的
- 换成 Part 2（题掉出范围）时那段说明的原文：
- 四处记录（训练记录/复盘/错题本/词汇本）有没有少：

## 三、四条路线（清单第 9 节）
| 路线 | 卡片上显示了什么 | 点下去发生了什么 |
| 按计划练今天 | | |
| 从题库自由选题 | | |
| 继续上次练习 | | |
| 复训一个旧问题 | | |
- 复训那一场，ChatGPT 收到的提示词里「本次唯一目标：…」两行**原样抄在这里**：
- 「当场点出」从今日训练页开的那场，提示词里是哪一句：
- 「当场点出」从复训中心开的那场，提示词里是哪一句：（已知缺口，见清单第 1 节第四条）

## 四、学习计划页（清单第 7 节）
| 项 | 结果 |
| 空状态三样齐不齐 | |
| 九个组合的预览数字对不对 | |
| 两种阻断文案逐字对不对 | |
| 照阻断说明改一下，按钮真的变可点吗 | |
| 「第几天不按日历」那句话在不在 | |
| 三项偏好改完重启还在吗 | |
| 改默认路线后，主行动卡片跟着变了吗 | |
| 两个确认框的原话对不对 | |

## 五、路线不可用（清单第 10 节）
- 删掉计划后卡片是消失还是变灰：
- 题目从题库消失后，今日训练页/计划页分别是什么表现：
- **光看今日训练页，你看得出发生了什么吗**：
- 空数据目录下两页的表现：
- 空题库时「换一个重点 Part」这个下一步，你照着做有用吗：

## 六、界面验收（清单第 11 节）
- 减弱动态效果打开后：
- 系统文字最大时每日拆分与首页四格：
- 9 → 10 时进度那一行抖不抖：
- Tab 与焦点环：
- 每页只有一个主行动吗：

## 七、哪里让我不想用
（成品标准第 5 节。请写实话，包括不好的部分——这类信息只有你有。
 特别想知道：学习计划页那一长条表单，你会真的用它每周调一次吗？
 还是生成一次之后就再也不来了？）

## 八、发现的问题与下一步
| 现象 | 该改哪儿 | 要补什么测试 |
| | | |
```

---

## 13. 出事了怎么退回去

- **真实数据被动坏了** → 先 ⌘Q 完全退出 App，再把备份整个换回去：
  ```bash
  rm -rf "$HOME/Library/Application Support/IELTS Speaking Coach"
  cp -R "$HOME/Library/Application Support/IELTS Speaking Coach.phase8-backup" \
        "$HOME/Library/Application Support/IELTS Speaking Coach"
  ```
- **演示数据改坏了** → `cp /tmp/ielts-phase8/state.json.bak /tmp/ielts-phase8/state.json`；
  实在不行按第 6 节重来一遍（两条命令）
- **换数据目录不生效** → 一定要**先 ⌘Q 完全退出**，否则只是把已经在跑的那个切到前台；
  另外不要用 `open`，它传不进环境变量
- **不小心真开了一场练习** → 在 App 里点结束，在 ChatGPT 里删掉那条会话即可；
  数据写在 `/tmp/ielts-phase8`，碰不到你真实的记录
- **又被要求授权辅助功能** → **停下来报告**，不要一路点确定。那说明签名的指定要求变了
  （第 3.3 节那两行不一致就是这个）

---

## 14. 这份清单与计划 Task 11 的七处出入（子代理发现的）

写下来免得你在现场犹豫。**第 2、3、4、5 条照计划字面走会卡住或记下假缺陷。**

| # | 计划怎么写的 | 实际怎么回事 | 处理 |
|---|---|---|---|
| 1 | 产出文件叫 `docs/phase8-acceptance.md` | 本文件叫 `phase8-acceptance-checklist.md`，与 Phase 4–7 的命名一致；**验收结果仍然写进 `phase8-acceptance.md`** | 无需改动，只是两份文件 |
| 2 | Step 2 那张表有「已有的计划还在吗」「原计划的重点 Part 显示成全真模考」两行 | 你真实的 `state.json` 里 **`plan` 是 `null`**，这两行在真实数据上**验不出来** | 第 4 节改写了判据，第 5 节在**副本**上补验旧格式计划的回落 |
| 3 | Step 2「训练记录还在吗：数字与升级前一致」 | 你的 `sessions` / `issues` / `vocabulary` **本来就是 0** | 第 3.2 节先把升级前的数字抄下来，第 4 节按它对；判据改成「一致 + 页面不是空白」 |
| 4 | Step 5「复训一个旧问题：**开练后**看提示词」 | 今日训练页那张卡片点下去是**跳到复训中心**（按钮写「去复训中心」），不在这一页开练 | 第 9.4 节拆成两段：先在卡片上看目标原文，再进复训中心真开一场，然后翻提示词 |
| 5 | Step 1 直接「打包 → 打开 App」 | 备份必须排在打开之前，而且**先把升级前的数字抄下来**才有对照基准 | 顺序改成 备份 → 抄数字 → 打包两次 → 打开（第 3、4 节） |
| 6 | Step 3–6 默认演示数据可用 | `seed-demo-data.swift` 的 `questions` 是 **空数组**、`plan` 是 `null`——Phase 7 踩过一次，这次会让第 7–10 节**全部走不下去** | 第 6 节补了一段实跑验证过的补题命令（43 题，题数按每一档故意配的） |
| 7 | 完成标准里「四条练习路线全部能从今日训练页开练」 | **「复训一个旧问题」不是从今日训练页开练**（见第 4 条），而且从复训中心开的那一场**不带练习偏好**（`RetrainingCoordinator` 没把 `settings` 传给 `RetrainingSetupBuilder.makeSetup`） | 第 9.5 节专门验它；这是 Phase 6 与 Phase 8 的接口缺口，如实记录 |

另外三条计划没提、但现场很容易被误判成缺陷的：

- **`swift test` 现在是红的**（1 条），根因是 Phase 6 那条源码守卫比对的字符串没跟上
  Task 10 的调用形状（第 1 节第一条）。**不是功能坏了**，但要先修好再验收
- **问题档案页顶上那条橙色警告**在真实数据下必然出现（`targets` 引用了一场 `sessions` 里没有的练习），
  Phase 7 已经确认过，**不是 Phase 8 的账**
- **空题库时计划页那句「换一个重点 Part」没用**（四个 Part 都是 0 题）——
  这是文案缺陷，第 10.3 节请你判断一句，别当成自己理解错了
