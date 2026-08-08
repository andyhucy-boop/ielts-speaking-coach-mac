# Phase 10 Task 11 真机验收清单（给用户本人照着做）

日期：2026-08-08
对应计划：`docs/superpowers/plans/2026-08-06-phase10-packaging-and-distribution.md` 的 **Task 11**（第 3123 行起）
代码基线：分支 `phase2-bridge`，最后一条提交 `5ca5514`（数据目录搬迁的自动化验证）
自动化测试现状：`swift test` **1744 条全绿**，18.60 秒（2026-08-08 实跑两次）

---

## 0. 这份文件是什么

Task 11 是 Phase 10 里**不能由子代理代劳**的那一个。前面十个任务加 Task 12–18 的测试跑在纯逻辑、
脚本与源码扫描上，证明的是「逻辑对、脚本会拦、源码里没有字面值」，证明不了下面这四件事：

1. **系统认不认这个签名**——加了 Hardened Runtime 之后重新打包，你之前给的辅助功能授权还在不在；
2. **系统认不认那条 entitlement**——`codesign` 只能证明 `com.apple.security.device.audio-input`
   写进去了，证明不了麦克风真的能录；
3. **Gatekeeper 会怎么拦、说明能不能让别人打开**——这条按机器算，本机测不出来；
4. **文案读起来是不是人话**——只有眼睛能判断。

- **你要做的**：按第 3–11 节逐步操作，把每一项的实际结果记下来
- **结果写到哪**：`docs/phase10-acceptance.md`（计划 Step 9 指定的文件名，第 12 节给了可直接复制的骨架）
- **本文件不是结果**：它只是清单。**我一步都没有替你跑**（本任务的指令就是「只写清单，不要真的执行」）
- **大约要多久**：本机部分约 60–90 分钟；第二台 Mac 部分约 30–45 分钟
- **会不会碰真实的 ChatGPT**：**会，但只到「被启动」为止**。App 一启动就跑一次环境检查
  （`RootView` 的 `.task` → `AppState.startInitialPermissionCheckIfNeeded` → `AXDriver.preflight`），
  它在 ChatGPT 没运行时会 `launchTarget()` 把它拉起来，再等最多 8 秒让无障碍树醒过来。
  **它不新建会话、不发任何消息、不进语音**（`preflight` 全文见 `Sources/ChatGPTBridge/AXDriver.swift:47`）。
  关于页那颗「重新检查」是同一段代码，同样只到这一步
- **会不会动你的数据**：Step 1 的两个脚本都在临时目录里造假数据（`verify-portability.sh` 用
  `mktemp -d` + `IELTS_SPEAKING_DATA_DIR`），**一个字节都不碰真实目录**；Step 3 之后的界面操作会
  正常读写你的数据目录，Step 4 会清掉本机 UserDefaults 里的引导标记（见第 1 节第八条）

### 与 Task 19 的关系

计划自己写着：**Task 11 与 Task 19 合起来才是整个 Phase 10 的验收**，建议一次做完。
本文件**只覆盖 Task 11 的 8 个 Step**（签名稳定性、关于页、引导、拷给别人、换机器、麦克风、界面十条）。
深色模式逐页看、设置窗口四分区、「功能升级」页、「问题反馈」页那四块归 Task 19，
等它的清单写出来之后接着做，或者你自己照计划第 5783 行往下走。

### 文件名与计划不一致，是有意的

计划 Step 9 说「写进 `docs/phase10-acceptance.md`」。**那个文件名留给结果**；
本文件叫 `phase10-acceptance-checklist.md`，跟 Phase 4–9 的六份清单同一套命名
（`docs/phase4-acceptance-checklist.md` … `docs/phase9-acceptance-checklist.md`）。
清单是我写的、结果是你写的，两份分开。

---

## 1. ⚠️ 开工前必须先知道的十件事

全部是 2026-08-08 在本机实读、实跑得到的，不是猜的。不先看，第 3、5、6、8 节都会当场卡住，
或者让你记下一条假缺陷。

### 一、`.build` 里现在那份 `.app` 是**旧的**，别拿它当验收对象

```
.build/IELTS Speaking Coach.app/Contents/Info.plist
  CFBundleShortVersionString  1.0.0
  CFBundleVersion             296
  IELTSBuildCommit            1e630de
  IELTSBuildDate              2026-08-07T22:46:51Z

git rev-parse --short HEAD    5ca5514
git rev-list --count HEAD     303
```

它是 `1e630de`（Task 16 那次重构）打的，之后又提交了八次。
**Step 3 那条「提交与 `git rev-parse --short HEAD` 一致」现在必然对不上**——
那不是缺陷，是这份包还没重打。Step 2 会重打，所以照顺序走就行。

`.build/dist/` 里那个 zip 同理，是 03:42 打的，比 HEAD 旧。

### 二、Step 2 跑完之后，`.app` 的构建号会变成 **90002**

`verify-signature-stability.sh` 故意用两个远离真实构建号的号连打两次
（`FIRST_BUILD_NUMBER=90001`、`SECOND_BUILD_NUMBER=90002`，脚本第 77–78 行），
为的是让两个包的内容确实不同。它跑完**不会**把包还原成正常构建号。

后果：紧接着做 Step 3，关于页会显示「1.0.0（构建 **90002**）」，
Step 5 若直接沿用这个包，发给别人的也是 90002。

**下一步：Step 2 结束、确认过不用重新授权之后，再跑一次干净的 `./scripts/build-app.sh`**
（不带 `IELTS_BUILD_NUMBER`），构建号会回到 `git rev-list --count HEAD`，
现在是 **303**。这一步已经写进第 4 节的操作里了。

再打一次包**不会**让辅助功能授权失效——那正是 Step 2 要证明的事。

### 三、`swift test` 的「2 秒预算」早就作废了，别按它记缺陷

计划 Step 1 写的 Expected 是「全绿，总耗时 2 秒以内（Phase 3 Task 10 定的预算）」。
**实测 18.60 秒 / 1744 条**（2026-08-08 跑了两次，18.60 与 17.73）。

而且这不是 Phase 10 拖的：Phase 9 的验收清单里记着「1490 条全绿，12.36 秒」——
**进 Phase 10 之前就已经是 12 秒了**。计划那句话成文时抄的是 Phase 3 的旧约束，没跟着改。

耗时是谁占的（第二次实跑的逐条数据）：

| 测试套 | 条数 | 耗时 | 它在跑什么 |
|---|---|---|---|
| `NotarizeScriptTests` | 10 | **4.175 s** | 真的 fork bash 子进程跑 `notarize.sh`，PATH 前面塞了假的 `codesign`/`xcrun`/`security` |
| `SeedDemoDataScriptTests` | 13 | 2.546 s | 同上，跑 `seed-demo-data.swift` |
| `IconPipelineTests` | 5 | 2.337 s | 真的调 `iconutil` 生成并校验 `.icns` |
| `AXDriverTests` | 40 | 1.834 s | 里面有几条真的在等短超时（0.02–0.8 秒量级） |
| `InstallCodexPluginScriptTests` | 11 | 1.116 s | 跑 `install-codex-plugin.sh` |
| 其余 1665 条 | | 约 6.6 s | |

`PackagingTests` 四个套一共 25 条、**4.30 秒**（`NotarizeScriptTests` 4.175 +
`SettingsHomeContractTests` 0.118 + `FeedbackPrivacyContractTests` 0.003 + `PackagingContractTests` 0.002）。

**判据改成这样**：全绿；总耗时记下实际数字；**不许为了压时间删断言**。
若你想让它回到秒级，那是另一件事（把跑子进程的那几套挪到单独的 scheme），不是本次验收的内容。

### 四、你真实的数据目录**几乎是空的**，Step 3 与 Step 6 有半张表验不出东西

实读 `~/Library/Application Support/IELTS Speaking Coach/`（2026-08-08）：

```
state.json          1188 字节，schemaVersion 3
  questions   1     （p1-home-001，Part 1 · Home，"What do you like most about your home?"）
  sessions    0
  issues      0
  vocabulary  0
  targets     1     （grammar_sentence_control）
  plan        null   currentSession null
  settings    只有 recordingEnabled(false) / recordingConsentAt("")
reports/            空
recordings/         空
pending-reviews/    1 份（Phase 9 清单记过：字段名是旧的那份）
```

直接后果：

| 受影响的判据 | 现在会发生什么 |
|---|---|
| Step 3「数据可搬迁检查用你真实的数据目录跑」 | 会显示「没有发现问题」，但那是**因为没有东西可查**——`DataPortabilityAudit` 查的是 `sessions[].reportPath` / `sessions[].recordingPath` / `questionSources[].sourceUrl`，前两样一条都没有 |
| Step 6「训练记录条数一致 / 复盘能打开 / 录音能播 / 错题本词汇本数字一致」 | 全是 0 对 0。**0 == 0 也叫「一致」，但它什么都没证明** |

**下一步（二选一，报告里写清选了哪个）：**

- **A（推荐，也是计划的本意）**：验收前先**真练一场**（首页「开始练习」，Part 1 那道题几分钟就够），
  让 `sessions`、`reports/`、`issues`、`vocabulary` 都从 0 变正，再做 Step 3 与 Step 6。
  这也顺带验了成品标准第 4 条。**注意这会产生一次真实的 ChatGPT 语音对话**，你自己决定什么时候做
- **B**：接受「这一轮验不出来」，在报告里如实写「数据集为空，本行未验证」。
  **不要写成「通过」**——那是本项目最不想要的那种绿灯

> **不要用 `scripts/seed-demo-data.swift` 往真实目录灌演示数据**。那个脚本本来就拒绝写进真实数据目录
> （`SeedDemoDataScriptTests` 里有六条测试守着，连 `~`、相对路径、`..` 绕回去都拒），
> 而且用假数据去验「换机器之后我的东西还在不在」，验的是假数据搬没搬过去。

### 五、Step 6 那条「引导只出现「环境」一步」**与实现相反**，是计划写错了

计划 Step 6 最后一行写着：

> 引导 | **只出现「环境」一步**（辅助功能要在这台机器上重给），不是从欢迎页重来

**实现不是这样，而且是刻意不这样的。** 证据三处：

1. `Sources/IELTSCoachUI/Onboarding/OnboardingProgressStore.swift` 开头的注释：
   「刻意存本机 UserDefaults，不进数据目录……换了机器，辅助功能授权是本机 TCC 的，必须重给一次，
   **引导应该再出现**。把它写进 state.json 的话，新机器上的用户一进来就没有引导，
   直接撞上一堵「点开始练习却报错」的墙」
2. `OnboardingFlow.steps` 的分支：`hasCompletedBefore == false` 时走完整流程；
   「只出现环境一步」那条分支的前提是 `hasCompletedBefore == true`
3. `OnboardingFlowTests.testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere`
   的注释逐字写着：「**这正是「把数据目录拷过来的人」在新机器上第一次开 App 的样子**」，
   断言是 `[.welcome, .environment, .recordingChoice, .ready]`

**第二台机器上的正确预期**（把数据目录拷过去、题库非空）：

```
欢迎  →  让它能替你操作 ChatGPT  →  要不要录下你的回答？  →  可以开练了
```

**四步，从欢迎页开始，「先把你的题库导进来」那一步被跳过**——
**那一步被跳过，才是「数据拷成功了」的信号**。请按这个判据验，
若真的从欢迎页重来，**不是缺陷**；反过来，若第二台机器上出现了「先把你的题库导进来」，
**那才是缺陷**（说明题库没读到）。

计划 Step 4 最后一行说「这一条是换机器场景的本地等价物」——**本地那一条本身是对的**
（同机、走完引导、取消勾选后重开，确实只出现「环境」一步），**但它不等价于换机器**，
因为 UserDefaults 不跟着数据目录走。

### 六、`defaults` 域里现在**没有**引导标记，Step 4 的清标记这一步多半是空跑

```
defaults read com.ielts.speakingcoach
{
    "NSWindow Frame IELTSCoachUI.RootView-1-AppWindow-1" = "314 209 1100 720 0 0 1728 1084 ";
}
```

引导标记的键是 `com.ielts.speakingcoach.onboardingCompletedVersion`（`UserDefaultsOnboardingStore.key`），
**现在不在里面**——也就是说你从来没有把引导走完过。

后果：**Step 2 里那次 `open` 就会直接落进首次引导**，不是落在主界面。
Step 4 那句 `defaults delete` 到那时是空操作，除非你在 Step 2/3 里先把引导走完了。

**下一步**：Step 2/3 期间遇到引导，就**把它走完**（最后点「开始使用」），
这样 Step 4 才有东西可清、也才验得了「走完之后重开不再出现引导」。

另外两点：

- `defaults delete com.ielts.speakingcoach` 会**连窗口位置一起删掉**（无害，重开会回到默认位置）。
  只想清引导标记的话用：
  `defaults delete com.ielts.speakingcoach com.ielts.speakingcoach.onboardingCompletedVersion`
- 这个域只有 `.app` 会写。**`swift run IELTSCoachApp` 写的是别的域**，
  拿它验引导等于验了个寂寞

### 七、Step 2 有一个**前置条件**，不满足的话它验的是另一回事

Step 2 的判据是「不重新授权直接打开，仍然显示「环境就绪」」。
这句话成立的前提是**这台机器上已经给过这个 `.app` 辅助功能授权**。

**开工第一件事**：打开「系统设置 › 隐私与安全性 › 辅助功能」，确认列表里有
「IELTS Speaking Coach」**且开关是打开的**。截一张图放进报告。

- 若列表里根本没有它 → Step 2 验不出「授权没失效」，只能验出「本来就没授权」。
  这时先在 Step 2 之前授权一次（打开 App 走引导里的「打开系统设置」），
  **然后再跑 `verify-signature-stability.sh`**，顺序反了这一步就白做
- 我没法替你确认这件事：读 TCC 数据库要「完全磁盘访问权限」，不该为了写份清单去要

### 八、关于页的「辅助功能」那一行**默认是「还没检查」**，这是设计，不是坏了

`AboutPageModel.honest(_:)` 里明写：`permission == nil` 时那一行显示「还没检查」，
提示语是「打开这一页不会自动检查——检查要启动 ChatGPT，会打断你手上的事。
下一步：点「重新检查」查一次」。

所以 Step 3 那一行的正确做法是：**先点「重新检查」，等它从「正在检查…」变成结论，再核对**。
「正在检查…」那一档的提示语写着「实测约需九秒」，等满它。

### 九、关于页复制出来的诊断信息**没有「数据目录占用」那一行**，也是设计

`AboutPageModel.diagnosticsText` 调 `DiagnosticsReport.text(...)` 时**没传 `usage`**，
那一行由 Task 18 的「问题反馈」页负责（归 Task 19 验）。
关于页复制出来的应当正好是这些行（按你当前的 `state.json` 推算，**我没有替你跑**）：

```
IELTS Speaking Coach 诊断信息
版本：1.0.0（构建 303）
提交：5ca5514
构建时间：…
签名：自签名（未经 Apple 公证）（身份：IELTS Coach Dev）
标识：com.ielts.speakingcoach
系统：…
数据目录：/Users/…/Library/Application Support/IELTS Speaking Coach
数据量：题库 1 题 · 练习记录 0 次 · 错题 0 条 · 词汇 0 条 · 重训目标 1 个
辅助功能：…（四档之一）
数据可搬迁检查：没有发现问题
环境检查：…（点过「重新检查」就是逐条原文；没点过是那句「还没查过…」）
最近一次错误：最近没有出错
——错误只记阶段与代号，不记原文；原文里可能有你说过的英语。
——以上只有数量，不含任何练习内容。要看具体内容请直接打开数据目录。
```

**「数据量」那一行只有数字，没有一个题目、一句英语、一个名字**——这正是 Step 3 最后一行要你逐行确认的。

### 十、Step 5 与 Step 6 **必须在第二台 Mac 上做**，本机测不出来

计划「需要用户参与的环节」那张表里写死了这一条。原因：

| 要验的东西 | 为什么本机不行 |
|---|---|
| Gatekeeper 拦截 | 隔离属性（`com.apple.quarantine`）是**传输方式**打上的。本机 `cp` 一份不打隔离属性，双击直接就开了，看起来「没被拦」——而别人那边一定会被拦 |
| 辅助功能要重给 | TCC 按（机器 × 用户）算 |
| 数据目录换机器 | 要的就是「原来那台不在了」 |

**第二个 macOS 用户账号能顶一部分**：TCC 是按用户算的、隔离属性是按文件算的，
所以 Gatekeeper 与「授权要重给」这两条在第二个账号上验得出来。
**验不出来的是**：不同的 macOS 版本（「如何打开.txt」里的系统设置路径在别的版本上可能对不上）、
不同的硬件、以及「另一台机器上根本没有这套开发环境」这件事本身。

**报告里必须写清你用的是第二台机器还是第二个账号**，两者的结论强度不一样。

---

## 2. 顺序与时间

计划的 Step 编号照抄不动，但**实际执行顺序建议这样**（理由都在第 1 节）：

| 顺序 | 做什么 | 大约 | 在哪台机器 |
|---|---|---|---|
| 0 | 确认辅助功能已授权（第 1 节第七条） | 2 分钟 | 本机 |
| 1 | Step 1 全量回归 | 5 分钟 | 本机 |
| 2 | Step 2 签名稳定性 + 不重新授权直接开 | 15 分钟 | 本机 |
| 3 | 重打一次干净的包（第 1 节第二条） | 3 分钟 | 本机 |
| 4 | （可选但强烈建议）真练一场，让数据非空（第 1 节第四条） | 20 分钟 | 本机 |
| 5 | Step 3 关于页逐项核对 | 15 分钟 | 本机 |
| 6 | Step 7 麦克风 | 5 分钟 | 本机 |
| 7 | Step 8 界面十条 | 15 分钟 | 本机 |
| 8 | Step 4 清引导标记重走一遍 | 15 分钟 | 本机 |
| 9 | Step 5 打包 + 拷过去 | 20 分钟 | **第二台** |
| 10 | Step 6 数据目录换机器 | 20 分钟 | **第二台** |
| 11 | Step 9 记录并提交 | 20 分钟 | 本机 |

**Step 4 排在关于页与界面验收之后**，是因为它会把你扔回引导流程，主界面要重走一遍才回得去。

---

## 3. Step 1：全量回归

```bash
cd ~/Projects/ielts-speaking-coach-mac
time swift test
```

**Expected**：`Executed 1744 tests, with 0 failures`。
耗时按第 1 节第三条记实际数字，**不要按计划里那句「2 秒以内」判失败**。

```bash
swift build          # verify-portability.sh 要 .build/debug/coach，没有它会直接告诉你先 build
./scripts/verify-portability.sh
```

**Expected**（脚本最后四行逐字）：

```
✅ 数据目录可以整个拷到另一台电脑接着用（成品标准第 10 条）。
   正例：删掉原目录后仍然读得到题库与复盘。
   负例 1：存了绝对路径的目录被正确揪出，并给出了下一步。
   负例 2：写法坏但文件在的路径也被揪出——「看写法」那组规则确实还活着。
```

这个脚本全程在 `mktemp -d` 出来的临时目录里干活，**不碰你的真实数据**。

| 记什么 | 你的结果 |
|---|---|
| 测试条数 / 失败数 | |
| 总耗时 | |
| `verify-portability.sh` 正例 | |
| `verify-portability.sh` 负例 1 / 负例 2 | |

---

## 4. Step 2：签名稳定性（本阶段最关键的一条，一票否决）

**先做第 1 节第七条那个前置确认，再往下。**

```bash
./scripts/verify-signature-stability.sh
```

它会连打两次包（构建号 90001 / 90002），每次都过一遍 `build-app.sh` 自己的四道自检。
约 2–4 分钟。

**Expected**（脚本最后那段）：

```
✅ 连打两次，两个内容确实不同的包都通过了 build-app.sh 的「指定要求」闸门，
   复核两次的值也逐字一致、与基线相符：
   designated => identifier "com.ielts.speakingcoach" and certificate leaf = H"4bffcd37377a383d9d75460f2c2c9d85174fc82a"
   两次的构建号分别是 90001 / 90002，CDHash 分别是 … / …
```

那串 `H"4bffcd…"` 必须与 `packaging/expected-designated-requirement.txt` 里的**逐字相同**。

然后**不重新授权**直接打开：

```bash
open ".build/IELTS Speaking Coach.app"
```

**Expected**：不再要求你去系统设置勾选任何东西。
按第 1 节第六条，你现在多半会落进**首次引导**——引导的第二步（「让它能替你操作 ChatGPT」）
顶上那行字应当是 **「环境就绪」**（`PermissionStatus.title(for: .ready)`）。
若显示的是「还差一步：辅助功能权限」，**立刻停下并报告**。

> ⛔ **这一条一票否决。** 授权真的失效了，说明加 Hardened Runtime 之后签名不稳定，
> 整个打包方案要重做，后面的验收都没有意义。停下来，把
> `verify-signature-stability.sh` 的完整输出、
> `codesign -d -r- ".build/IELTS Speaking Coach.app"` 的输出、
> 以及系统设置里那一行的截图一起记下来。

**趁着还在引导里，把它走完**（最后点「开始使用」）——第 1 节第六条说了为什么。

确认无误之后，**重打一次干净的包**，把构建号从 90002 换回真实值：

```bash
./scripts/build-app.sh
plutil -extract CFBundleVersion raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"   # 应当是 303
plutil -extract IELTSBuildCommit raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"  # 应当是 5ca5514
```

再开一次，**确认这一次同样不要求重新授权**（这才是「日常重新打包」的真实场景，90001/90002 不是）。

| 记什么 | 你的结果 |
|---|---|
| 脚本是否 ✅ | |
| designated 是否与基线逐字相同 | |
| 打开后是否要求重新授权 | |
| 引导第二步顶上那行字 | |
| 重打干净包之后是否仍不要求授权 | |
| 重打后的构建号 / 提交 | |

---

## 5. Step 3：关于页逐项核对

苹果菜单 ›「关于 IELTS Speaking Coach」。
**先点一次「重新检查」**（第 1 节第八条），等它从「正在检查…」变出结论。

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 版本 | `1.0.0（构建 303）`，与 `CFBundleShortVersionString` / `CFBundleVersion` 一致 | |
| 提交 | 与 `git rev-parse --short HEAD`（`5ca5514`）一致 | |
| 标识 | `com.ielts.speakingcoach` | |
| 签名 | 「自签名（未经 Apple 公证）」，且下面那句说清了别人怎么打开 | |
| 辅助功能 | 与实际状态一致 | |
| 辅助功能（取消勾选后） | 去系统设置**取消勾选**本 App，回来点「重新检查」，**这一行必须跟着变**成「未授权（半自动模式）」。验完记得勾回去 | |
| 数据目录 | 路径正确；「在访达中显示」打开的是对的文件夹，并出现「已在访达中打开数据目录。」 | |
| 数据可搬迁检查 | **先读第 1 节第四条**。报了问题就把每一条原文抄下来——那是真 bug | |
| 致谢 | 五条逐条读：上游 MIT、SF Symbols、SF Pro、OpenAI、第三方依赖（「没有」）。有说得不准的就记下来 | |
| 许可与声明 | 第三方声明那段 MIT 原文必须完整（`Permission is hereby granted` 到 `THE SOFTWARE.`）。它是分发合规的条件，不是装饰 | |
| 复制诊断信息 | 点它 → 出现「诊断信息已复制到剪贴板」→ `pbpaste` 逐行读 | |

诊断信息的逐行检查（对照第 1 节第九条那份预期）：

```bash
pbpaste
```

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 有没有练习内容 | **一句英语、一个题目、一个人名都不该有**。「数据量」那行只有数字 | |
| 「最近一次错误」 | 只有时间、阶段、代号，没有一个字的错误原文 | |
| 「数据目录占用」这一行 | **不该有**（第 1 节第九条）。有的话反倒说明接错了 | |
| 「环境检查」这一行 | 你刚点过「重新检查」，所以应当是逐条原文，不是那句「还没查过」 | |

**顺带一条命令行交叉验证**（可选，与关于页那一行比对）：

```bash
.build/debug/coach portability
```

---

## 6. Step 7：麦克风在 Hardened Runtime 下真的能用

**这一步是 entitlement 唯一的真机判据。** 单元测试与 `codesign` 自检只能证明
`com.apple.security.device.audio-input` 写进去了，证明不了系统认。

`⌘,` 打开设置窗口 ›「录音」分区 → 打开「保存我的回答录音」。

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 系统有没有弹麦克风授权对话框 | 应该弹。弹出来的说明文字应当是 Info.plist 里那句「开启「保存我的回答录音」后，用于录下你练习时的回答，便于回听。录音只存在本机，可随时删除。」 | |
| 点「允许」之后 | 开关真的留在「开」的位置（`RecordingConsent` 拿到 granted 才写盘） | |
| 真的录一小段 | 练一次（或用录音页自带的入口）录出一个文件，`recordings/` 里能看到，**能播放出声** | |
| 若被系统直接拒掉 | **立刻记下来**：那说明 entitlement 没生效，是 Task 1 的缺陷 | |

> 注意：你当前的 `state.json` 里 `recordingEnabled` 是 `false`、`recordingConsentAt` 是空串，
> 所以这一步是**第一次**授权，对话框应该会弹。若没弹，先确认
> 「系统设置 › 隐私与安全性 › 麦克风」里是不是已经有本 App 了。

---

## 7. Step 8：界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节）

十条清单，逐条走关于页与引导页。**其中三条已经被自动化测试守住了**，先跑一遍，
跑完剩下的才需要眼睛：

```bash
swift test --filter DesignTokenSweepTests      # 视图里有没有字面颜色 / 字号 / 圆角
swift test --filter DesignTokenContractTests
swift test --filter AppearanceContrastTests    # 两套外观 × 15 组配对的对比度矩阵
```

`DesignTokenSweepTests` 扫的是 `Sources/IELTSCoachUI/` 下除三张令牌表
（`DesignSystem/Typography.swift`、`Palette.swift`、`Metrics.swift`）之外的每一个文件，
**整文件豁免名单本身也被钉死了**。所以第 8 节第三条（「关于页里有没有出现字面颜色、字号、圆角」）
不用你翻源码——绿了就是没有。

| # | 十条清单 | 谁来验 | 你的结果 |
|---|---|---|---|
| 1 | 视图里没有字面颜色/字号/圆角 | `DesignTokenSweepTests` | |
| 2 | 正文与次要文字对比度 ≥ 4.5:1 | `AppearanceContrastTests`（合成 alpha 之后算） | |
| 3 | 没有 emoji 当图标 | 眼睛 | |
| 4 | 每个列表的空状态都有「说明 + 下一步 + 按钮」 | 眼睛（关于页没有列表；引导页看题库那一步） | |
| 5 | 每页只有一个主行动 | 眼睛 | |
| 6 | Tab 能走遍所有可点元素，焦点环可见 | **键盘，必须真按**。关于页三颗按钮 + 引导页的主按钮与「先跳过」 | |
| 7 | 打开系统「减弱动态效果」后无动画且功能正常 | **必须真开**。系统设置 › 辅助功能 › 显示 › 减弱动态效果；然后看引导页的步骤切换 | |
| 8 | 系统文字调到最大时不截断、不重叠 | **必须真调**。关于页的致谢与许可那几段最长，最容易出问题 | |
| 9 | 所有超过 300ms 的操作都有进度提示 | 眼睛：「重新检查」那九秒里，那一行是不是一直在说「正在检查…」 | |
| 10 | 统计数字用等宽数字，变化时不抖动 | 眼睛（关于页数字少，这条主要归 Task 19 的首页） | |

---

## 8. Step 4：首次引导（清标记重来一遍）

**先确认你已经在 Step 2 里把引导走完了**（第 1 节第六条），不然这一步没东西可清。

```bash
osascript -e 'quit app "IELTS Speaking Coach"' 2>/dev/null || true
defaults delete com.ielts.speakingcoach com.ielts.speakingcoach.onboardingCompletedVersion
open ".build/IELTS Speaking Coach.app"
```

（想连窗口位置一起清就用计划原文的 `defaults delete com.ielts.speakingcoach`，无害。
**必须先退出 App**——运行中的 App 会在退出时把内存里的值写回去，把你刚删的又写回来。）

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 步骤顺序 | 欢迎 → 让它能替你操作 ChatGPT → 要不要录下你的回答？ → 可以开练了。**因为你的题库非空（1 题），不该出现「先把你的题库导进来」** | |
| 每一步的文案 | 找一个不懂技术的人读一遍，他知不知道要干什么 | |
| 「先跳过」 | 只有「环境」与「题库」两步有。点了能直接进主界面，且主界面可用 | |
| 主按钮名字 | 环境那步是「打开系统设置」，与页面上那颗真实按钮**逐字相同**（不该出现两颗写着差不多字的按钮） | |
| 走完之后重开 App | 不再出现引导 | |
| 去系统设置**取消**辅助功能勾选，重开 App | **只出现「让它能替你操作 ChatGPT」一步**，不是从欢迎页重来。验完记得勾回去 | |

最后一条务必真做。**但请注意它不是换机器场景的等价物**——理由见第 1 节第五条，
换机器时 UserDefaults 不跟着走，第二台机器上会从欢迎页开始。

---

## 9. Step 5：把 `.app` 给别人（第二台 Mac）

在本机：

```bash
./scripts/package-app.sh
```

它会先重新 `build-app.sh`（所以构建号是真实的 303），再用 `ditto -c -k --keepParent` 压包，
**并自己解压回来验一次签名**。产出：

```
.build/dist/IELTS Speaking Coach.zip
.build/dist/如何打开.txt
```

脚本最后会打印大小与 SHA256，抄进报告。

传过去的方式**必须会打上隔离属性**：AirDrop、邮件附件、下载链接都行。
**`cp` 到共享盘 / U 盘不打隔离属性，那样测不出 Gatekeeper**（第 1 节第十条）。

在第二台 Mac 上：

```bash
# 先确认隔离属性真的在，不在的话这一步白做
xattr -p com.apple.quarantine ~/Downloads/"IELTS Speaking Coach.zip"
```

解压、拖进「应用程序」、双击，然后按「如何打开.txt」的步骤走。

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 隔离属性在不在 | `xattr -p com.apple.quarantine` 有输出 | |
| 是否被 Gatekeeper 拦下 | **应该会**（自签名未公证）。可交叉验证：`spctl -a -vv "/Applications/IELTS Speaking Coach.app"` 应当报 rejected | |
| 签名本身有没有坏 | `codesign --verify --strict --verbose=2 "/Applications/IELTS Speaking Coach.app"` 应当通过。**若这里报「已损坏」，那是打包问题，不是公证问题**，回来查 `package-app.sh` | |
| 按「如何打开.txt」能不能打开 | **能**。若说明里的系统设置路径在这台机器的 macOS 版本上不存在，**把实际路径记下来并改说明**（改 `packaging/open-instructions.txt`） | |
| 打开后 | 出现首次引导（欢迎开始，四步或五步取决于有没有题库） | |
| 程序坞图标 | 不是白纸（`AppIcon.icns` 在 `Contents/Resources/`，200 KB） | |
| 授予辅助功能后 | 环境那一步显示「环境就绪」 | |
| 用的是第二台机器还是第二个账号 | **必须写清**（第 1 节第十条） | |

---

## 10. Step 6：数据目录换机器（成品标准第 10 条，必须真做）

**先读第 1 节第四条。** 数据集为空的话这一步全是 0 对 0。

在第一台机器上，先把「真相」记下来（照抄进报告，第二台机器上逐项对）：

```bash
.build/debug/coach portability      # 题库 N 题，练习记录 N 次，错题 N 条，词汇 N 条
cp -R ~/Library/Application\ Support/IELTS\ Speaking\ Coach ~/Desktop/coach-data-backup
```

把 `coach-data-backup` 拷到第二台机器的
`~/Library/Application Support/IELTS Speaking Coach`，打开 App。

| 看什么 | 判据 | 第一台 | 第二台 |
|---|---|---|---|
| 题库 | 题目数量一致 | | |
| 训练记录 | 条数一致，点开任意一条能看到题目与逐字稿 | | |
| 复盘报告 | 能打开，内容完整 | | |
| 录音 | 若开过录音，点播放能出声 | | |
| 错题本 | 数字一致 | | |
| 我的词汇 | 数字一致 | | |
| 重训目标 | 数字一致 | | |
| `coach portability` | 两边输出一致，且都是「✅ 没发现任何依赖本机路径的地方」 | | |
| 引导 | **欢迎 → 环境 → 录音 → 完成 四步**，且**没有**「先把你的题库导进来」那一步（第 1 节第五条）。计划原文写的「只出现环境一步」是错的，别照它记缺陷 | | |

**任何一项对不上都如实记下来**，连同两边 `coach portability` 的完整输出。

---

## 11. Step 9：记录并提交

```bash
git add docs/phase10-acceptance.md
git commit -m "docs: Phase 10 真机验收结果"
```

**只用显式路径**，别用 `git add -A`。

---

## 12. 结果文件骨架（可直接复制进 `docs/phase10-acceptance.md`）

```markdown
# Phase 10 真机验收结果（Task 11）

日期：
机器 A：（型号 / macOS 版本）
机器 B：（型号 / macOS 版本；若用的是第二个用户账号，写「同机第二账号」并说明）
验收时的提交：
验收时的包：版本 / 构建号 / 提交

## 前置确认
- 辅助功能授权状态（验收开始前）：
- 数据集状态：（题库 N 题 / 练习 N 次 / 错题 N / 词汇 N / 目标 N）
- 是否为了验收先真练了一场：是 / 否

## Step 1 全量回归
- swift test：条 / 失败 条 / 秒
- verify-portability.sh：

## Step 2 签名稳定性 ⛔一票否决
- 脚本结果：
- designated：
- 不重新授权直接打开：
- 重打干净包之后：

## Step 3 关于页
（逐行）

## Step 7 麦克风
- 授权对话框：
- 真录一段：

## Step 8 界面十条
（逐条）

## Step 4 首次引导
（逐行）

## Step 5 拷给别人
（逐行，含 spctl / codesign 原文）

## Step 6 数据目录换机器
（两列对照表）

## 哪里让我不想用
**这一节最重要，别省。** 成品标准第 5 节：这类信息只有使用者有。

## 发现的缺陷
| # | 在哪一步 | 现象 | 我认为的原因 | 归谁 |
|---|---|---|---|---|

## 还演示不出来的成品标准
（十二条里若还有哪条演示不出来，写在这里。这是下一步的输入，不是可以含糊过去的事）
```

---

## 附录 A：本清单与计划原文的四处出入

写清单时逐条核对源码与本机实际状态发现的。**四处都以本清单为准**，
理由都在第 1 节，报告里若与计划原文冲突，按这里写的判。

| # | 计划原文 | 实际 | 依据 |
|---|---|---|---|
| 1 | Step 6：换机器后「引导只出现「环境」一步」 | **从欢迎页开始的四步**，题库那步被跳过 | `OnboardingProgressStore` 的注释、`OnboardingFlow.steps`、`OnboardingFlowTests.testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere` |
| 2 | Step 1：`swift test` 总耗时 2 秒以内 | **18.60 秒 / 1744 条**；进 Phase 10 之前（Phase 9 验收）已经是 12.36 秒 / 1490 条 | 2026-08-08 两次实跑；`docs/phase9-acceptance-checklist.md` 抬头 |
| 3 | Step 2 之后直接做 Step 3、Step 5 | 中间必须补一次干净的 `build-app.sh`，否则包的构建号是 **90002** | `scripts/verify-signature-stability.sh:77-78` |
| 4 | Step 9：结果写进 `docs/phase10-acceptance.md` | 文件名沿用，但**清单**另存为 `phase10-acceptance-checklist.md`，与 Phase 4–9 一致 | `docs/` 下六份既有清单 |

## 附录 B：这一轮我**没有**替你跑的东西，以及为什么

| 没跑 | 为什么 |
|---|---|
| `verify-signature-stability.sh`、`build-app.sh`、`package-app.sh` | 本任务的指令是「只写清单，不要真的执行」。而且 Step 2 的判据是「**你**的授权还在不在」，我跑一遍不构成验收 |
| `open` 那个 `.app` | 同上；而且它会把 ChatGPT 拉到前台，打断你手上的事 |
| `coach portability`（真实目录） | 留给 Step 3 用真实数据跑。第 1 节第九条那份诊断信息是**按源码与你当前 `state.json` 推算**的，不是实测输出 |
| 任何驱动 ChatGPT 的东西（`coach practice`、`axprobe press`） | 铁律 5：那会在你账号里产生真实对话和语音通话 |
| 跑了的：`swift test`（两次） | 结果见抬头与第 1 节第三条 |
