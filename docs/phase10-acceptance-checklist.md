# Phase 10 真机验收清单（Task 11 + Task 19，给用户本人照着做）

> **本文件分两部分。** 第 1–12 节是 **Task 11**（签名、关于页、引导、拷给别人、换机器、麦克风、界面十条）；
> 第 13 节起是 **Task 19 追加部分**（深色模式、设置窗口、「功能升级」页、「问题反馈」页、
> 侧边栏十项、减弱动态效果与最大字号）。计划自己写着**两者合起来才是整个 Phase 10 的验收**，
> 建议一次做完。第二部分的抬头信息、注意事项与出入清单单列在第 13–14 节与附录 C、D。

日期：2026-08-08
对应计划：`docs/superpowers/plans/2026-08-06-phase10-packaging-and-distribution.md` 的 **Task 11**（第 3123 行起）
代码基线：分支 `phase2-bridge`。写这份清单时 HEAD 是 `5ca5514`（数据目录搬迁的自动化验证）、
构建号 `303`——**这两个数字在本文件自己被提交的那一刻就作废了**（提交它就多一条提交），
所以下文所有「构建号 / 提交应当是多少」的判据一律让你**现场跑命令取值再比**，一处都不写死。
见第 1 节第十一条。
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
**第 1–12 节只覆盖 Task 11 的 8 个 Step**（签名稳定性、关于页、引导、拷给别人、换机器、麦克风、界面十条）。
深色模式逐页看、设置窗口四分区、「功能升级」页、「问题反馈」页那四块归 Task 19——
**它的清单已经写好，就在第 13 节起**（2026-08-08 追加）。

顺序上建议先把第 2 节那 12 步走完（尤其 Step 2 那条一票否决），再走第二部分：
第二部分要看的是**重打出来的那份干净的 `.app`**，而那一份要到第 2 节第 3 步才有。

### 文件名与计划不一致，是有意的

计划 Step 9 说「写进 `docs/phase10-acceptance.md`」。**那个文件名留给结果**；
本文件叫 `phase10-acceptance-checklist.md`，跟 Phase 4–9 的六份清单同一套命名
（`docs/phase4-acceptance-checklist.md` … `docs/phase9-acceptance-checklist.md`）。
清单是我写的、结果是你写的，两份分开。

---

## 1. ⚠️ 开工前必须先知道的十一件事

全部是 2026-08-08 在本机实读、实跑得到的，不是猜的。不先看，第 3、5、6、8 节都会当场卡住，
或者让你记下一条假缺陷。

### 一、`.build` 里现在那份 `.app` 是**旧的**，别拿它当验收对象

```
.build/IELTS Speaking Coach.app/Contents/Info.plist   ← 2026-08-08 实读
  CFBundleShortVersionString  1.0.0
  CFBundleVersion             296
  IELTSBuildCommit            1e630de
  IELTSBuildDate              2026-08-07T22:46:51Z
```

自己跑这两条，看 HEAD 比包里那两行新了多少（**别抄我写清单时的值**——那时是 `5ca5514` / `303`，
你跑出来一定更大，第 1 节第十一条）：

```bash
git rev-parse --short HEAD     # 重打之后 IELTSBuildCommit 应当等于它
git rev-list --count HEAD      # 重打之后 CFBundleVersion 应当等于它
```

包是 `1e630de`（Task 16 那次重构）打的，之后又提交了好几次。
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
（不带 `IELTS_BUILD_NUMBER`），构建号会回到 `git rev-list --count HEAD` **当场算出来的那个值**
（现场跑一下取，别抄数字，第 1 节第十一条）。这一步已经写进第 4 节的操作里了。

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

Step 2 的判据是「不重新授权直接打开，不再要求你去系统设置勾选任何东西」
（**具体看屏幕上哪句话，见第 4 节——不是「环境就绪」，计划原文那句是错的**）。
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
版本：1.0.0（构建 <当场的 git rev-list --count HEAD>）
提交：<当场的 git rev-parse --short HEAD>
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

### 十一、**构建号与提交是活的，本清单里一个都不写死**——期望值请现场取

`scripts/build-app.sh:50` 用 `git rev-list --count HEAD` 定构建号、`:52` 用
`git rev-parse --short HEAD` 定提交。也就是说：**每多一条提交，这两个期望值就都变了**——
包括提交这份清单自己的那一条：写清单时是 `303` / `5ca5514`，清单被提交（`3f50c7e`）之后当场变成
`304`，此后每提交一次再加一。**你跑出来的值只会更大，一律以你跑出来的为准。**

所以第 4、5、9 节里所有涉及构建号 / 提交的判据，写的都是**「与当场跑出来的值一致」**，
不是某个具体数字。核对方法固定用这两条（**没有输出才算过**）：

```bash
diff <(git rev-list --count HEAD) \
     <(plutil -extract CFBundleVersion raw ".build/IELTS Speaking Coach.app/Contents/Info.plist")
diff <(git rev-parse --short HEAD) \
     <(plutil -extract IELTSBuildCommit raw ".build/IELTS Speaking Coach.app/Contents/Info.plist")
```

**若你在验收过程中又提交了东西**（比如中途改了 `open-instructions.txt`），
上面两条就会开始报差异——那不是缺陷，是包比 HEAD 旧了，重跑一次 `./scripts/build-app.sh` 再比。
本文件里凡是出现具体数字的地方，都只是「写清单时的基线」，**已逐处标明会过期**。

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
按第 1 节第六条，你现在多半会落进**首次引导**。点「开始设置」走到第二步
（「让它能替你操作 ChatGPT」），**判据是这一步正文下面那张卡片写了什么**：

- ✅ **通过（授权保住了）**：一张带勾的绿色卡片，第一行逐字是
  **「这台电脑已经给过辅助功能授权了」**，下面接「所以上面那段「先跳过」这次用不上，
  这一步不用做什么。下一步：直接往下走。……」；底下只有「上一步」和一颗「下一步」
- ⛔ **失败（授权没了）**：顶上出现 **「还差一步：辅助功能权限」**，下面是
  「打开系统设置」「重新检查」「复制诊断信息」「先跳过」四颗按钮。**立刻停下并报告**

> **别去找「环境就绪」那四个字——授权还在的时候它根本不会出现。**
> 「环境就绪」（`PermissionStatus.title(for: .ready)`）只印在 `PermissionGateView` 顶上
> （`PermissionGateView.swift:60`），而那一页**只在环境不就绪时才摆**：
> `WelcomeFlowView.swift:235` 是 `private var showsPermissionGate: Bool { app.permission != .ready }`。
> 就绪时走的是 `:254` 起的 `permissionReadyCard`，也就是上面那张绿卡。
> 计划原文 Step 2 写的「仍然显示「环境就绪」」是错的，附录 A 第 5 行记着。
> 而它偏偏是本阶段的一票否决判据（见下），**判据必须是屏幕上真会出现的那句话**——
> 照着找一句不会出现的，只会白折腾，或者记下一条假缺陷。

> ⛔ **这一条一票否决。** 授权真的失效了，说明加 Hardened Runtime 之后签名不稳定，
> 整个打包方案要重做，后面的验收都没有意义。停下来，把
> `verify-signature-stability.sh` 的完整输出、
> `codesign -d -r- ".build/IELTS Speaking Coach.app"` 的输出、
> 以及系统设置里那一行的截图一起记下来。

**趁着还在引导里，把它走完**（最后点「开始使用」）——第 1 节第六条说了为什么。

确认无误之后，**重打一次干净的包**，把构建号从 90002 换回真实值：

```bash
./scripts/build-app.sh

# 期望值现场取，不写死（第 1 节第十一条）。两条都**没有输出**才算过。
diff <(git rev-list --count HEAD) \
     <(plutil -extract CFBundleVersion raw ".build/IELTS Speaking Coach.app/Contents/Info.plist")
diff <(git rev-parse --short HEAD) \
     <(plutil -extract IELTSBuildCommit raw ".build/IELTS Speaking Coach.app/Contents/Info.plist")
```

再开一次，**确认这一次同样不要求重新授权**（这才是「日常重新打包」的真实场景，90001/90002 不是）。

| 记什么 | 你的结果 |
|---|---|
| 脚本是否 ✅ | |
| designated 是否与基线逐字相同 | |
| 打开后是否要求重新授权 | |
| 引导第二步显示的是哪一张（绿卡「已经给过辅助功能授权了」／权限页「还差一步」） | |
| 重打干净包之后是否仍不要求授权 | |
| 重打后的构建号 / 提交（抄两条 `diff` 的结果，空输出就写「一致」） | |

---

## 5. Step 3：关于页逐项核对

苹果菜单 ›「关于 IELTS Speaking Coach」。
**先点一次「重新检查」**（第 1 节第八条），等它从「正在检查…」变出结论。

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 版本 | `1.0.0（构建 N）`，N 与 `plutil -extract CFBundleVersion raw …/Info.plist` 一致；刚重打过干净包，所以它同时应当等于**当场跑出来的** `git rev-list --count HEAD`。**别抄清单里的数字**（第 1 节第十一条） | |
| 提交 | 与**当场跑出来的** `git rev-parse --short HEAD` 一致 | |
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
| 4 | 每个列表的空状态都有「说明 + 下一步 + 按钮」 | **不适用：本轮没有可验的对象**，见表下那段 | |
| 5 | 每页只有一个主行动 | 眼睛 | |
| 6 | Tab 能走遍所有可点元素，焦点环可见 | **键盘，必须真按**。关于页三颗按钮 + 引导页的主按钮与「先跳过」 | |
| 7 | 打开系统「减弱动态效果」后无动画且功能正常 | **必须真开**。系统设置 › 辅助功能 › 显示 › 减弱动态效果；然后看引导页的步骤切换 | |
| 8 | 系统文字调到最大时不截断、不重叠 | **必须真调**。关于页的致谢与许可那几段最长，最容易出问题 | |
| 9 | 所有超过 300ms 的操作都有进度提示 | 眼睛：「重新检查」那九秒里，那一行是不是一直在说「正在检查…」 | |
| 10 | 统计数字用等宽数字，变化时不抖动 | 眼睛（关于页数字少，这条主要归 Task 19 的首页） | |

> **第 4 条为什么标「不适用」，而不是让你去引导页找。** Task 11 的范围只有关于页与引导页：
> 关于页没有列表；引导页里唯一沾边的是「先把你的题库导进来」那一步，而它两头都不成立——
>
> 1. **它在这台机器上根本不渲染。** `Sources/IELTSCoachUI/Onboarding/OnboardingFlow.swift` 的
>    `steps()` 里写着 `if questionCount == 0 { steps.append(.questionBank) }`，你的题库有 1 题
>    （第 1 节第四条），所以这一步被跳过——第 8 节和第 10 节也正是这么写的
>    （「**不该出现**「先把你的题库导进来」」）。
> 2. **就算渲染出来，它也不是列表空状态**，只是一张说明卡（`WelcomeFlowView.questionBankStep`），
>    没有列表、没有独立按钮。
>
> 真正有列表空状态的是首页、历史、错题本、我的词汇那几页，**归 Task 19 验**。
> 本轮唯一可能顺带看到那一步的机会，是第 9 节在第二台机器上**没有**把数据目录拷过去时
> （那时题库为空，引导会变成五步）——若碰上了就顺手看一眼，记在报告里。
> **本行不要写「通过」**，写「不适用（本轮无对象）」或你实际看到的情况。
> 指一个渲染不出来的东西比不写还糟，这和 `RenderReachabilitySweepTests` 拦的是同一类问题。

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

它会先重新 `build-app.sh`（所以构建号是真实的那个，即**当场的** `git rev-list --count HEAD`，
不是 90002，也不是清单里写过的任何数字），再用 `ditto -c -k --keepParent` 压包，
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
| 授予辅助功能后 | **同样别找「环境就绪」四个字**（理由见第 4 节那段注）。两条路都算通过：**(a)** 就在引导里点「重新检查」——查完（约九秒）引导会**自己往前走一步**到「要不要录下你的回答？」，不会停在环境步（`OnboardingFlowModel.consumeRecheckResult`）；**(b)** 退出 App 再重开——环境那一步显示绿卡「这台电脑已经给过辅助功能授权了」。若点完「重新检查」既没前进、也没变绿卡，那才是缺陷 | |
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

## 附录 A：本清单与计划原文的六处出入

写清单时逐条核对源码与本机实际状态发现的（第 5、6 行是 2026-08-08 复审补的）。
**六处都以本清单为准**，理由都在第 1 节与第 4 节，报告里若与计划原文冲突，按这里写的判。

| # | 计划原文 | 实际 | 依据 |
|---|---|---|---|
| 1 | Step 6：换机器后「引导只出现「环境」一步」 | **从欢迎页开始的四步**，题库那步被跳过 | `OnboardingProgressStore` 的注释、`OnboardingFlow.steps`、`OnboardingFlowTests.testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere` |
| 2 | Step 1：`swift test` 总耗时 2 秒以内 | **18.60 秒 / 1744 条**；进 Phase 10 之前（Phase 9 验收）已经是 12.36 秒 / 1490 条 | 2026-08-08 两次实跑；`docs/phase9-acceptance-checklist.md` 抬头 |
| 3 | Step 2 之后直接做 Step 3、Step 5 | 中间必须补一次干净的 `build-app.sh`，否则包的构建号是 **90002** | `scripts/verify-signature-stability.sh:77-78` |
| 4 | Step 9：结果写进 `docs/phase10-acceptance.md` | 文件名沿用，但**清单**另存为 `phase10-acceptance-checklist.md`，与 Phase 4–9 一致 | `docs/` 下六份既有清单 |
| 5 | Step 2「仍然显示「环境就绪」」、Step 5「授予辅助功能后显示「环境就绪」」 | **授权还在时屏幕上不会出现「环境就绪」**。就绪走的是绿卡「这台电脑已经给过辅助功能授权了」；在引导里点「重新检查」转就绪，还会自动前进一步 | `WelcomeFlowView.swift:235`（`showsPermissionGate = app.permission != .ready`）、`:254` 的 `permissionReadyCard`、`PermissionGateView.swift:60`、`OnboardingFlowModel.consumeRecheckResult` |
| 6 | Step 8 第 4 条：去「引导页看题库那一步」验列表空状态 | **那一步在本机不渲染**（题库 1 题），而且它本来也不是列表空状态。本轮标「不适用」 | `OnboardingFlow.steps()` 的 `if questionCount == 0`、`WelcomeFlowView.questionBankStep` |

## 附录 B：这一轮我**没有**替你跑的东西，以及为什么

| 没跑 | 为什么 |
|---|---|
| `verify-signature-stability.sh`、`build-app.sh`、`package-app.sh` | 本任务的指令是「只写清单，不要真的执行」。而且 Step 2 的判据是「**你**的授权还在不在」，我跑一遍不构成验收 |
| `open` 那个 `.app` | 同上；而且它会把 ChatGPT 拉到前台，打断你手上的事 |
| `coach portability`（真实目录） | 留给 Step 3 用真实数据跑。第 1 节第九条那份诊断信息是**按源码与你当前 `state.json` 推算**的，不是实测输出 |
| 任何驱动 ChatGPT 的东西（`coach practice`、`axprobe press`） | 铁律 5：那会在你账号里产生真实对话和语音通话 |
| 跑了的：`swift test`（两次） | 结果见抬头与第 1 节第三条 |

---
---

# 第二部分：Task 19 追加验收清单（深色模式、设置合并、两页）

追加日期：2026-08-08
对应计划：同一份计划的 **Task 19**（第 5783 行起）
代码基线：写这一部分时 HEAD 是 `7897b0c`、`git rev-list --count HEAD` = `305`。
**这两个数字同样在本文件被提交的那一刻作废**——第 1 节第十一条那条规矩对这一部分**原样适用**，
凡涉及构建号 / 提交的判据一律现场跑命令取值再比。
自动化测试现状：`swift test` **1744 条全绿，17.29 秒**（2026-08-08 实跑）。

---

## 13. 这一部分是什么

| | Task 11（第 1–12 节） | Task 19（第 13 节起） |
|---|---|---|
| 验什么 | 签名稳定性、关于页、首次引导、拷给别人、换机器、麦克风、界面十条 | 深色模式逐页、设置窗口、「功能升级」页、「问题反馈」页、侧边栏十项、减弱动态效果与最大字号 |
| 一票否决项 | 有（Step 2 重新打包后授权失效） | 无 |
| 要第二台 Mac | 要（Step 5、6） | **不要**，全部在本机 |
| 大约耗时 | 本机 60–90 分钟 + 第二台 30–45 分钟 | 60–80 分钟（真练一场另算） |

**建议的执行顺序**：第 2 节那 12 步走完 → 再走这一部分。
理由：这一部分看的是**重打出来的那份干净的 `.app`**（构建号是真实值，不是 `90002`），
而那一份要到第 2 节第 3 步才有。

**我一步都没有替你跑**（同第一部分，本任务的指令是「只写清单」）。
这一部分我额外做了**两次突变验证**，目的只有一个：搞清楚「哪些事机器已经守住了、
哪些只能靠你的眼睛」。结果在第 14 节第三条，那也是第 15 节全部价值的来源。

---

## 14. ⚠️ 开工前必须先知道的七件事（这一部分专有）

### 一、你这台机器现在是**浅色**，Step 1 的第一件事是切深色

```
sw_vers                              → macOS 26.5.2（BuildVersion 25F84）
defaults read -g AppleInterfaceStyle → 无输出 = 当前浅色
```

路径：**系统设置 › 外观 › 深色**。**App 保持开着**——
计划要求的就是「不重启也要跟着变」（动态令牌是绘制时按当前外观解析的），
关掉重开再看等于把这条判据整个放过去了。

想快速来回切，也可以用这一条（第一次会向你要「自动化」权限；不想给就走系统设置）：

```bash
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'
```

### 二、深色下**最可能出问题的是那些「醒目按钮」**，这是本步的重点

`Palette.dark.accent` 是调亮并降饱和的浅紫 `#A6A1E0`（`Palette.swift:87`）。
而 `.buttonStyle(.borderedProminent) + .tint(Palette.accent)` 这一对里，
**按钮上那行字的颜色是系统自己挑的，不是 `Palette.textOnAccent`**。
`Palette.swift:83-85` 自己的注释写着：白字压在调亮后的主色上只有 **2.7:1**。

全 App 有 **24 处 `.borderedProminent`、27 处 `.tint(Palette.accent)`**。
**没有任何测试守得住这一条**：`AppearanceContrastTests` 只对它知道的那 15 组令牌配对算比值，
而系统替按钮挑的那个文字色根本不是一个令牌。

深色下要逐个看清楚的醒目按钮：

| 在哪儿 | 按钮 | 源码 |
|---|---|---|
| 读不到数据时的错误屏 | 「重试」 | `RootView.swift:275` |
| 所有空状态卡片 | 各页各自的那颗 | `DesignSystem/Components.swift:177`（`EmptyStateView`）|
| 学习计划页 | 「生成计划」/「重新生成」 | `Plan/PlanView.swift:360` |
| 训练题库导入结果 sheet | 「知道了」 | `QuestionBank/QuestionBankImportResultSheet.swift:53` |
| 关于窗口 | 「重新检查」 | `About/AboutView.swift:368` |
| **问题反馈页** | **「复制诊断信息」**（这一页唯一的主行动）| `Feedback/FeedbackView.swift:250` |
| 复盘报告 › 待处理收件箱 | 「重新导入」 | `Review/PendingReviewInboxView.swift:151` |
| 引导页 | 每一步的主按钮、「打开系统设置」、「重新检查」 | `Onboarding/WelcomeFlowView.swift:335`、`PermissionGateView.swift:93,101` |
| 复训流程 sheet | 「开始练习」「重答这道题」「我练完了」「放弃这一场」「我已经复制好了」「完成」「这个问题我不用再练了」 | `Retraining/RetrainingFlowView.swift:550-620` |
| 练习中的 sheet | 「开始练习」「我练完了」「我已经复制好了」「完成」 | `Session/PracticeSheet.swift:328-365` |

**判据**：深色下这行字读得清 = 过；糊成一片 = 记缺陷。
**修法**（写进报告供后续参考）：给那颗按钮显式指定 `.foregroundStyle(Palette.textOnAccent)`——
`PrimaryActionCard` 就是这么做的（`Components.swift:95`），所以今日训练页那块紫卡片理论上是稳的。

### 三、「一行字看不见」这类事，机器只守得住一半——我实测过

写这份清单时做了两次突变，各跑一次测试，**两次都已改回，`git status` 干净**：

| 我把什么改坏 | 哪条测试**变红** | 哪条**没有**变红 |
|---|---|---|
| `Palette.tokens(for:)` 的 `.dark` 分支改成 `return light`（`Palette.swift:104`）| `AppearanceContrastTests` 10 条里**红 2 条、共 3 处断言失败**：`testDarkIsActuallyDark`（两处断言：「深色的内容区底色并不比浅色暗」+「深色下正文比背景还暗」）、`testTheSameTokenResolvesDifferentlyInTheTwoAppearances`（点名 `Palette.canvas` 两套外观解析成同一个值）| **`testEveryTextPairMeetsAAInBothAppearances`（那张 15 组配对的矩阵）照样绿**——它等于拿浅色跑了两遍，每一对当然都达标。**计划完成标准里那句「矩阵那条不会红，所以这条不能省」是对的，实测确认。** `testTheDarkPaletteIsNotJustTheLightOneInverted` 也仍绿（它拦的是「反色」，指回同一套不算反色）|
| 往 `SettingsWindowView.swift` 的分区说明里塞 `.font(.system(size: 12))` + `.foregroundStyle(Color.gray)` | `DesignTokenContractTests.testNoViewOutsideTheTokenTablesHardcodesStyle`，报「Settings/SettingsWindowView.swift 有 2 处样式没走设计令牌」| **`DesignTokenSweepTests` 四条全绿** |

**结论，也就是这一部分的分工：**

| 这件事 | 谁守 |
|---|---|
| 令牌表本身（两套取值、对比度、alpha 合成）| 机器（`AppearanceContrastTests` 10 条）|
| 视图里有没有写死颜色 / 字号 / 圆角 | 机器（**是 `DesignTokenContractTests`，不是 `DesignTokenSweepTests`**——第 7 节把功劳记错了地方，见附录 C 第 4 行）|
| **令牌有没有用对地方**（次要色压在主色底上、醒目按钮的系统文字色、图标与文字挤在一起）| **只有你的眼睛。第 15 节全部的价值在这里。** |

### 四、**没有**「浅色 / 深色 / 跟随系统」开关，这是刻意的，别去找

`grep -rn "preferredColorScheme" Sources/` 零命中；设置窗口四个分区里也没有任何外观项。
深色只跟随系统（计划 Task 13 的决定，完成标准里逐字写着「**没有**新增这类开关」）。
**找不到不是缺陷。**

### 五、「最近一次错误」**不落盘**：退出 App 就没了

`LastErrorLog` 是进程内的单例，`LastErrorLog.swift:78-80` 的注释写明「**刻意不落盘**」。

所以 Step 4 那条「人为制造一次失败，回到这一页看它有没有记上」有一个隐含前提：
**制造失败和回来看这两步之间不能退出 App。** 退出再开，那一页会理直气壮地写
「最近没有出错」——**那不是 bug**。

另外，制造失败**不必真去动 ChatGPT**：把数据目录改成只读，再到设置窗口改一个值，
`AppState.mutate` 就会在 `.writingState` 阶段记一笔（`AppState.swift:216`）。
这一步和 Step 2 最后一行那条「改设置失败时」正好是同一个操作——**做一次验两条**，
具体命令在第 16 节。计划原文那种做法（练习中途把 ChatGPT 关掉）当然也行，
代价是要真开一场语音对话。

### 六、Step 2 那条「录音分区开一次关一次，占用数字跟着变」**验不出来，是计划写错了**

「录音占了多少地方」量的是 `recordings/` 目录里那些文件（`RecordingSettingsViewModel.refresh()` → `RecordingStore.usage()`）。
**拨一下开关既不产生也不删除任何录音文件**，所以那个数字不会动——
`setEnabled` 确实会 `refresh()` 重量一次，但量的还是同一批文件（而且你现在 `recordings/` 是空的）。

那个数字只有在**真的录了一段**、或**真的删了一条录音**之后才会变。

**改成这样验**：拨完开关之后，看那句同意时间戳（「你在 …… 同意保存录音。」）和下面那段说明
有没有跟着变；**占用数字留到第一部分第 6 节（Step 7 麦克风）真录一段之后再看**。
**别按计划原文记一条假缺陷。**

### 七、Step 2 有两行的原文与屏幕上的字不完全一样

| 计划写的 | 屏幕上真正的字 | 出处 |
|---|---|---|
| 训练记录页顶部「逐字稿记录：开 · 在设置里更改」 | 「逐字稿记录：开 · 在「**设置 › 练习偏好**」里更改」 | `Settings/PracticePreferenceEditor.swift:50-52` |
| 「每个分区顶部有一句「这一栏管什么」」 | 是分区标题**下面**那一句，四个分区各不相同（第 16 节把四句都列出来了）| `Settings/SettingsSection.swift:32-44` |

**按屏幕上的字核，不按计划原文逐字核。**

---

## 15. Step 1：深色模式逐页看

**先切深色（第 14 节第一条），App 不要关。**

要看的一共 **10 页 + 4 个窗口/浮层 + 5 张 sheet**。sheet 最容易漏，所以单列。

### 15.1 侧边栏十页（顺序就是侧边栏从上到下的顺序）

| # | 页 | 深色下重点看什么 | 你的结果 |
|---|---|---|---|
| 1 | 今日训练 | 四格统计的等宽数字、进度条、**主行动卡片**（浅紫底 + 近黑字，用的是 `Palette.textOnAccent`，理论上稳）、「改目标」按钮 | |
| 2 | 训练题库 | 空状态/列表、导入按钮、`Palette.success` 那一行（`QuestionBankView.swift:169`）| |
| 3 | 学习计划 | 进度条与完成标记（success/textSecondary 交替）、页尾那张「练习偏好」说明卡 + 「打开设置 › 练习偏好」按钮 | |
| 4 | 复训中心 | 证据卡片、`Palette.warning` 那几行（`RetrainingCenterView.swift:102`）| |
| 5 | 复盘报告 | 长段落正文、`success/warning/danger` 三色同屏（`ReviewReportView.swift:299,314,330,345`）、选中态那一行用 `textOnAccent`（`:175`）| |
| 6 | 功能升级 | 这里只看深色；内容归 Step 3。**十个阶段那一列的三种状态色最集中** | |
| 7 | 问题反馈 | 这里只看深色；内容归 Step 4。**诊断全文那张卡是全 App 最长的一段小字**，最容易在深色下读不清 | |
| 8 | 训练记录 | 按月分组、顶部那行逐字稿现状、`Palette.warning` 三处（`HistoryView.swift:182,299,361`）| |
| 9 | 问题档案 | **三种趋势色同屏：`gone/decreasing`→success、`increasing`→danger、`steady`→warning（`IssueArchiveView.swift:249-251`）。计划点名的「三色彼此分得开」在这一页最好判。** | |
| 10 | 我的词汇 | 列表 + 导出结果的三种状态色（`VocabularyView.swift:349-351`）| |

### 15.2 四个窗口 / 浮层

| 看什么 | 怎么到 | 你的结果 |
|---|---|---|
| 关于窗口 | 苹果菜单 › 关于 IELTS Speaking Coach | |
| 设置窗口 | `⌘,`，**四个分区各看一遍** | |
| 引导页 | 第一部分第 8 节会清标记重走一遍。**那时顺手在深色下看**，别为它单独走一次 | |
| 坏链接横幅 | 终端 `open "ieltscoach://nope"`，窗口顶上出一条橙边横幅（`RootView.swift:211,229` 用 `Palette.warning`）| |

### 15.3 五张 sheet（最容易漏）

| sheet | 怎么调出来 | 代价 |
|---|---|---|
| **练习中的 sheet**（`PracticeSheet`）| 今日训练页点「开始练习」| **这会真的开一场 ChatGPT 语音对话。** 计划把它列进 Step 1，所以二选一：要么真练一场（顺带把第 1 节第四条那个「数据集为空」也一并解决），要么在报告里如实写「本轮未看」。**别写「通过」** |
| 导入结果 sheet | 训练题库页导入一份 CSV（一行的小文件就够）| 无 |
| 复训流程 sheet | 复训中心点一个目标 | 前几步不碰 ChatGPT，走到「开始练习」才碰 |
| 待处理复盘收件箱 | 复盘报告页 ›「重新导入待处理的复盘」| 无。你目录里正好有 1 份（第 1 节第四条）|
| 三处确认对话框 | 学习计划重新生成/删除、训练记录删一条、录音删一条 | **系统对话框，本来就跟随系统外观**，扫一眼即可，不必逐个较真 |

### 15.4 计划那张表的六条判据（补了一列「怎么判」）

| 看什么 | 判据 | 怎么判 | 你的结果 |
|---|---|---|---|
| 有没有哪一行字看不见 | **一行都不许有** | 重点在第 14 节第二条那些醒目按钮。发现一处就记下来（在哪一页、哪颗按钮、什么字）| |
| 卡片 | 比背景亮一点，不是一个洞 | `dark.card`(0.118) > `dark.canvas`(0.078)，`testCardsStandOutFromTheCanvasInBothAppearances` 已守着；你只要确认屏幕上真是这样 | |
| 主行动卡片 | 浅紫底 + 近黑字，读得清 | 今日训练页那块。它显式用了 `Palette.textOnAccent`（`Components.swift:95`），深色下 7.7:1 | |
| 成功 / 警告 / 危险三色 | 深色底上都读得清，且**彼此分得开** | **问题档案页**（三色同屏）最好判；「功能升级」页十个阶段那一列是另一处（已完成=success、进行中=accent、还没开始=textSecondary）| |
| 切回浅色 | 一切照旧，没有深色残迹 | **切回去之后同一个窗口不要关**再看一遍——动态令牌是绘制时解析的，关掉重开等于没验这一条 | |
| 浅色下的 `success` / `warning` | **明显更深，你能不能接受** | 这是计划点名要你拍板的一条。取值在 `Palette.swift:77-78`。能接受就不用说话；不能接受就说，重调的唯一前提是仍 ≥ 4.5:1 | |

---

## 16. Step 2：设置窗口

四个分区的那句「这一栏管什么」（`SettingsSection.summary`，核对用）：

| 分区 | 那句话 |
|---|---|
| 录音 | 要不要录下你的回答、麦克风权限、录音占了多少地方。 |
| 训练目标 | 每周想练几次。首页那格「本周 N/M 次」用的就是它。 |
| 练习偏好 | 默认从哪条路线开练、考官什么时候给反馈、Part 2 的一分钟准备怎么算、要不要记录对话逐字稿。 |
| 数据与隐私 | 你的数据存在哪儿、占了多少、怎么备份和搬走。 |

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| `⌘,` | 打开设置窗口，**四个分区都在**（录音、训练目标、练习偏好、数据与隐私），默认停在「录音」；每个分区标题下面有上表那一句 | |
| 首页齿轮 | 主窗口工具栏那颗齿轮（「每周训练目标」），点开的是**同一个窗口**且停在「训练目标」 | |
| 首页「改目标」 | 今日训练页「本周训练」那格下面那颗，**同样是同一个窗口的同一栏**（`TodayView.swift:273`）。两颗按钮打开两个不同的东西才是缺陷 | |
| 学习计划页底部 | 只有一行说明 + 一颗「打开设置 › 练习偏好」，**没有三个开关** | |
| 训练记录页顶部 | 只有一行「逐字稿记录：开 · 在「设置 › 练习偏好」里更改」+ 一颗按钮，**没有开关**；点按钮打开同一个窗口并停在「练习偏好」 | |
| 练习偏好分区 | **四张卡片**：默认练习路线、反馈时机、Part 2 准备时间、逐字稿。每张下面那句取舍说明都在 | |
| **跨窗口同步** | 见下面那六步。**M 当场变** | |
| 录音分区 | 与 Phase 5 那个窗口完全一样（就是同一个视图）。**「开一次关一次占用数字跟着变」验不出来，见第 14 节第六条** | |
| 数据与隐私分区 | 路径正确、可选中；占用与 Finder 显示的接近；「在访达中显示」打开的是对的文件夹 | |
| 改设置失败时 | 见下面那段只读演练 | |

### 跨窗口同步（这一条是 Task 15/16 的核心交付，务必逐步做）

1. 主窗口切到「今日训练」，记下「本周训练」那格现在显示的 `N/M`（你现在 `sessions` 为 0，多半是 `0/5`）
2. `⌘,` → 「训练目标」→ Stepper 按到 **9**
3. **设置窗口不要关**，直接把主窗口挪出来看那一格
4. **判据**：那格当场变成 `0/9`，而且下面那句脚注同时变成「离本周目标还差 9 次。……」
5. 为什么它必然同步：`Sources/IELTSCoachApp/main.swift:20` 整个进程只建了**一个** `AppState`，
   两个 Scene 拿的是同一个实例；`TodayView` 每次重绘现造 `TodayViewModel(state: app.state)`。
   **不同步就是真 bug，记下来**，别自己去点一下别的页面「刷新」再说它同步了
6. 验完把每周目标改回你原来的值

### 改设置失败时（顺带把 Step 4 的「最近一次错误」也造出来）

```bash
DIR=~/Library/Application\ Support/IELTS\ Speaking\ Coach
chmod a-w "$DIR"          # 只改目录本身，不动里面任何文件
#   → 到设置窗口「训练目标」把 Stepper 按一下
chmod u+w "$DIR"          # ← 验完立刻改回来，别忘
```

| 判据 | 你的结果 |
|---|---|
| 分区顶部出现一张卡片，标题「**这次没能存下来**」，正文是中文且带「下一步」（`SettingsWindowView.swift:351` 的 `failureCard`）| |
| **Stepper 自己弹回落盘的那个值**——所有取值都是现读磁盘的计算属性，没有 `@State` 副本 | |
| `state.json` 一个字节没变（写盘是「临时文件 + rename」，临时文件都建不出来，原文件根本没被碰；`StateStore.writeUnlocked`）| |
| 顺带：这一下已经把「最近一次错误」记成 `写训练数据 · NSCocoaErrorDomain#…` 了，**Step 4 直接用，中途别退出 App**（第 14 节第五条）| |

---

## 17. Step 3：「功能升级」页

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 当前版本 | 与 `plutil -extract CFBundleShortVersionString raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"` 一致（`build-app.sh:25` 的 `APP_VERSION` 现在是 `1.0.0`）；构建号与提交同样**现场取值**再比（第 1 节第十一条）| |
| 有没有那句「你现在跑的是 …」 | 打的是干净的包时**不该出现**。出现了说明版本对不上，把那句话原文抄下来 | |
| 更新记录 | 默认只展开最新那一条。逐条读，见下表 | |
| 十个阶段 | **逐条核对状态**，见下下表 | |

### 1.0.0 那八条改动（逐条读，说得不准的就改）

| # | 现在写的 | 准不准 |
|---|---|---|
| 1 | 今日训练、训练题库、学习计划、复训中心、复盘报告、训练记录、问题档案、我的词汇都能用了 | |
| 2 | 点一下「开始练习」就会自动打开 ChatGPT、进语音、发考官提示词，全程不用碰终端 | |
| 3 | 练完自动取回复盘并归档到错题本、词汇本与下次的重训目标 | |
| 4 | 可选开启录音，练完能回听自己的回答，可单条删除 | |
| 5 | 支持 CSV / JSON / 文字版 PDF 导入自己的题库 | |
| 6 | 深色模式，跟随系统外观 | |
| 7 | 设置合并成一个窗口（⌘,）：录音、训练目标、练习偏好、数据与隐私 | |
| 8 | 能在 Codex 里通过 MCP 调用，也能用 ieltscoach:// 唤起界面 | |

### 十个阶段现在标的状态（`Changelog.swift:129-161`）

| Phase | 标题 | 现在标的 | 你的判断（维持 / 改成什么） |
|---|---|---|---|
| 0–1 | 探路与地基 | 已完成 | |
| 2 | 驱动与命令行 | 已完成 | |
| 3 | 图形界面骨架 | 已完成 | |
| 4 | 逐字稿与训练记录 | 已完成 | |
| 5 | 录音与回听 | 已完成 | |
| 6 | 复训中心 | 已完成 | |
| 7 | 问题档案与词汇本 | 已完成 | |
| 8 | 学习计划与练习路线 | 已完成 | |
| 9 | 在 Codex 里调用 | 已完成 | |
| 10 | 打包与分发 | **进行中** | |

> **两处请特别留意：**
>
> 1. **Phase 4 标的是「已完成」，但 `DEFINITION-OF-DONE.md` 第 3 节那张复审表里写着
>    「说话人判别未在真机验证过」。** 你真练一场、逐条核对过逐字稿之后，再决定这一行维不维持。
> 2. **Phase 10 标的是「进行中」，而你正在做的就是它的验收。** 全部走完、缺陷都记下来之后，
>    它是不是该改成「已完成」由你判断——**注意公证（notarize）本期明确不做**，
>    所以「已完成」的含义要以计划里 Phase 10 的交付定义为准，不是以「什么都做了」为准。
>
> **标成「已完成」但实际没做的，当场改掉。这一页的全部价值就是它说的是真的。**

---

## 18. Step 4：「问题反馈」页

### 18.1 复制出来的那段话

点「复制诊断信息」→ 应出现「已复制。这段文字现在在你的剪贴板里，粘给谁、发不发由你决定。」→

```bash
pbpaste
```

应当正好是这些行（`DiagnosticsReport.text`，逐行对；**具体数值现场取，别抄这里**）：

```
IELTS Speaking Coach 诊断信息
版本：1.0.0（构建 <当场的 git rev-list --count HEAD>）
提交：<当场的 git rev-parse --short HEAD>
构建时间：…
签名：自签名（未经 Apple 公证）（身份：IELTS Coach Dev）
标识：com.ielts.speakingcoach
系统：…
数据目录：/Users/…/Library/Application Support/IELTS Speaking Coach
数据量：题库 N 题 · 练习记录 N 次 · 错题 N 条 · 词汇 N 条 · 重训目标 N 个
辅助功能：…
数据可搬迁检查：没有发现问题
数据目录占用：…          ← **这一行是这一页比关于页多出来的**（第 1 节第九条）
环境检查：…
最近一次错误：…
——错误只记阶段与代号，不记原文；原文里可能有你说过的英语。
——以上只有数量，不含任何练习内容。要看具体内容请直接打开数据目录。
```

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 有没有练习内容 | **一句英语、一个题目、一个人名都不该有。** 「数据量」那行只有数字 | |
| 「数据目录占用」这一行 | **该有**（关于页那份没有，这是两页刻意的分工）| |
| 「环境检查」这一行 | 没点过「重新检查环境」时是那句「还没查过……」；点过之后是逐条原文。**两者都正常，不要当缺陷** | |
| 「最近一次错误」 | 见 18.2 | |

### 18.2 「最近一次错误」怎么造、怎么判

**推荐做法**：直接用第 16 节那个只读目录的操作（不碰 ChatGPT，一次验两条）。
计划原文那种（练习中途把 ChatGPT 关掉）也行，代价是要真开一场。

**前提**：制造失败之后**不要退出 App**（第 14 节第五条）。

| 判据 | 你的结果 |
|---|---|
| 那一行只有 `时间 · 阶段 · 代号` 三样，形如 `2026-08-08T…Z · 写训练数据 · NSCocoaErrorDomain#513` | |
| **一个字的错误原文都没有** | |
| 卡片下面那句解释在（「只记了「什么时候、在做什么、错误代号」三样……」）| |
| 没出过错时是「最近没有出错。」+ 一句下一步，**不是一片空白** | |

### 18.3 这一页有没有「发送」的入口

整页只有三颗按钮，**一个「发送」都不该有**：

| 按钮 | 它干什么 | 注意 |
|---|---|---|
| 复制诊断信息（主行动）| 只写剪贴板 | |
| 重新检查环境 | 再跑一次 preflight | **这一下会把整个窗口换成「正在检查运行环境…」约九秒，并且会把 ChatGPT 拉到前台。** 查完回到这一页是全新的一份，上一次点按钮留下的「已复制」不会跟过来——**那不是 bug** |
| 打开数据目录 | 访达 | |

| 看什么 | 判据 | 你的结果 |
|---|---|---|
| 有没有提交按钮 / 邮件 / 外链 | 一个都不该有。源码层面由 `PackagingTests/FeedbackPrivacyContractTests` 扫 `Sources/IELTSCoachUI/Feedback/`，禁 `URLSession`/`NSURLConnection`/`NWConnection`/`CFSocket`/`mailto:`/`http://`/`https://` | |
| 顶上那句承诺在不在 | 「这一页不会把任何东西发到任何地方。复制之后要粘给谁、发不发，全由你决定。」| |
| 找一个不懂技术的人读一遍 | 他知不知道这一页要他做什么 | |

---

## 19. Step 5：侧边栏十项全齐

**现状（源码层面已确认）**：`SidebarItem.isImplemented` 十项全是 `true`；
`PlaceholderView` 已作为死代码删除；`RootView.detail` 那个 `switch` 是穷尽的、没有 `default:`
（`RootView.swift:282-313` 与文件末尾那段注释）。

所以这一步你点一遍十项，**不该再看到任何「还没做」的占位页**。

| 判据 | 你的结果 |
|---|---|
| 十项点一遍，一项都不是占位页 | |
| 若真看到占位页 | **如实记下来是哪一项，不要通过改测试让它变绿**（计划原文原话）| |

> 「有内容」不等于「内容对」。内容那一层你在第 15.1 节已经逐页看过一遍了，
> 这一步只是再确认一次没有占位页。

---

## 20. Step 6：减弱动态效果与最大字号

### 20.1 减弱动态效果

**系统设置 › 辅助功能 › 显示 › 减弱动态效果**，打开。

| 看什么 | 代码里怎么处理的 | 判据 | 你的结果 |
|---|---|---|---|
| 引导页翻页 | **有显式处理**：`WelcomeFlowView.swift:163` `.animation(reduceMotion ? nil : .easeOut(0.2), value: model.index)` | 无动画，翻页照常 | |
| 坏链接横幅 | **有显式处理**：`RootView.swift:115` | 同上 | |
| 复训中心 / 复训流程 | **有显式处理**：`RetrainingCenterView.swift:311,319`、`RetrainingFlowView.swift:640` | 同上 | |
| **设置窗口切分区** | **没有任何显式处理**——`SettingsWindowView.swift` 里 grep 不到 `reduceMotion`，靠 `TabView` 自己和系统 | 若还有滑动/淡入动画，**记下来**：那是真缺陷，归 DESIGN-SYSTEM 第 5 节那条硬性要求 | |
| **「功能升级」展开更新记录** | **同样没有显式处理**——`DisclosureGroup` 的默认展开动画 | 同上 | |

**最后两行是这一步唯一可能出问题的地方，务必真开真看。**
前三行有代码守着，看一眼确认即可。

### 20.2 最大字号

macOS 26 的路径：**系统设置 › 辅助功能 › 显示 › 文字大小**。

> **注意**：macOS 的这一档不像 iOS 那样对所有 App 一视同仁——它给的是一份**按 App** 的清单。
> 若清单里没有「IELTS Speaking Coach」，就没法用这条路调；
> **这时如实记「本机无法调节，未验证」，不要记「通过」。**
> 退而求其次可以用「系统设置 › 显示器 › 更大文字」的缩放分辨率整体放大一档，
> 多数截断 / 重叠问题在那一档下也看得出来（但那不是同一件事，报告里写清你用的是哪一种）。

| 看什么（计划点名的三处）| 判据 | 你的结果 |
|---|---|---|
| 设置窗口四个分区 | 不截断、不重叠。**「练习偏好」那一栏四张卡片最高**，窗口最小高度按它定的（600）| |
| 「功能升级」页展开后的更新记录 | 八条改动每一条都是长中文句，最容易折行出问题 | |
| 「问题反馈」页的诊断全文 | 全 App 最长的一段小字 | |

---

## 21. Step 7：记录并提交

把每一项的实际结果追加进 `docs/phase10-acceptance.md`（**和第一部分同一份结果文件**），
**包括不好的部分**——「哪里让我不想用」这类信息只有使用者有（成品标准第 5 节）。

```bash
git add docs/phase10-acceptance.md
git commit -m "docs: Phase 10 追加部分（深色模式、设置合并、两页）的验收结果"
```

**只用显式路径，别用 `git add -A`。**

---

## 22. 结果文件骨架（Task 19 那一半，接在第 12 节那份后面）

```markdown
## Task 19 追加部分

验收时的系统外观切换方式：系统设置 / osascript
是否为了 Step 1 真练了一场（看练习中的 sheet）：是 / 否

### Step 1 深色模式逐页
- 十页（逐页一行）：
- 关于窗口 / 设置窗口 / 引导页 / 坏链接横幅：
- 五张 sheet（哪几张看了、哪几张没看）：
- **醒目按钮在深色下读得清吗**（第 14 节第二条那张表，逐颗）：
- 三种状态色在深色下彼此分得开吗（问题档案页）：
- 切回浅色有没有残迹：
- **浅色下的 success / warning 能不能接受**：能 / 不能（不能的话你想要什么样）

### Step 2 设置窗口
- 四个分区 + 四句「这一栏管什么」：
- 三处深链接（首页齿轮 / 首页「改目标」/ 学习计划页 / 训练记录页）：
- **跨窗口同步（0/5 → 0/9 当场变，脚注也变）**：
- 只读目录时的失败文案与控件回弹：
- 录音分区（占用数字那一行按第 14 节第六条判）：
- 数据与隐私分区：

### Step 3 功能升级页
- 版本 / 构建号 / 提交是否与当场取值一致：
- 八条更新记录逐条：
- **十个阶段逐条核对结果（改过哪几条、为什么）**：

### Step 4 问题反馈页
- pbpaste 逐行读的结论（有没有练习内容）：
- 「数据目录占用」那一行在不在：
- 「最近一次错误」是怎么造出来的、长什么样：
- 有没有任何「发送」入口：
- 找人读了没有、他的反应：

### Step 5 侧边栏十项
- 有没有占位页：

### Step 6 减弱动态效果 / 最大字号
- **设置窗口切分区有没有动画**：
- **功能升级展开有没有动画**：
- 文字大小这一档在本机能不能调（能 / 不能，用的是哪种放大方式）：
- 三处有没有截断、重叠：

### 这一部分里哪里让我不想用
**别省。** 成品标准第 5 节：这类信息只有使用者有。

### 这一部分发现的缺陷
| # | 在哪一步 | 现象 | 我认为的原因 | 归谁 |
|---|---|---|---|---|
```

---

## 附录 C：Task 19 这一部分与计划原文的四处出入

写清单时逐条核对源码与本机实际状态发现的。**四处都以本清单为准**，
理由都在第 14 节，报告里若与计划原文冲突，按这里写的判。

| # | 计划原文 | 实际 | 依据 |
|---|---|---|---|
| 1 | Step 2：录音分区「开一次关一次，占用数字跟着变」 | 占用量的是 `recordings/` 里的文件，**拨开关既不产生也不删除文件，数字不会变**。它只在真录了一段或真删了一条之后才变 | `RecordingSettingsViewModel.setEnabled/refresh` → `RecordingStore.usage()`；你现在 `recordings/` 是空的 |
| 2 | Step 2：训练记录页顶部「逐字稿记录：开 · 在设置里更改」 | 屏幕上是「逐字稿记录：开 · 在「**设置 › 练习偏好**」里更改」 | `Settings/PracticePreferenceEditor.swift:50-52` |
| 3 | Phase 10 完成标准：「**七个**用户可配置项全在这个窗口里」 | **六个**：`recordingEnabled`、`transcriptEnabled`、`weeklyGoal`、`defaultRoute`、`feedbackTiming`、`part2PrepMode`。`CoachSettings` 确实有七个存储字段，但第七个 `recordingConsentAt` 是「你哪一天同意录音」的时间戳，不是用户能拨的东西 | `Sources/IELTSCoachCore/Model/CoachState.swift:19-35`；计划 Task 15 的 Interfaces 里写的也是「六个字段」；`SettingsSection.swift:3` 的注释同样写「六个」；`SettingsHomeContractTests` 的清单是五个字段 + `recordingEnabled` 单列 |
| 4 | 本文件第 7 节把「视图里有没有字面颜色 / 字号 / 圆角」记在 `DesignTokenSweepTests` 头上 | 实测拦住它的是 **`DesignTokenContractTests.testNoViewOutsideTheTokenTablesHardcodesStyle`**；`DesignTokenSweepTests` 守的是**反面**（每个视图**真的**从令牌取过样式，以及逐行豁免的账）。两条都要跑，但报错会出在 Contract 那一条 | 第 14 节第三条那次突变：塞进字面字号与灰色之后，Sweep 四条全绿、Contract 那条红并点名文件与处数 |

## 附录 D：这一部分我跑了什么、没跑什么

| 跑了 | 结果 |
|---|---|
| `swift test`（全量）| **1744 条全绿，17.29 秒** |
| **突变一**：`Palette.swift:104` 的 `.dark` 分支改成 `return light` | `AppearanceContrastTests` 10 条里**红 2 条、共 3 处断言失败**（`testDarkIsActuallyDark` 两处 + `testTheSameTokenResolvesDifferentlyInTheTwoAppearances` 一处）；**矩阵那条 `testEveryTextPairMeetsAAInBothAppearances` 仍绿**，`testTheDarkPaletteIsNotJustTheLightOneInverted` 也仍绿。已改回 |
| **突变二**：`SettingsWindowView.swift` 的分区说明塞进 `.font(.system(size: 12))` + `.foregroundStyle(Color.gray)` | `DesignTokenContractTests` 那条红并报「有 2 处样式没走设计令牌」；**`DesignTokenSweepTests` 四条全绿**。已改回 |
| 改回之后 | `git status --porcelain` 空输出 |
| `sw_vers`、`defaults read -g AppleInterfaceStyle` | macOS 26.5.2；**当前是浅色** |
| `grep` 一批源码事实 | 十项 `isImplemented`、`PlaceholderView` 已删、无 `preferredColorScheme`、无第二处 `keyboardShortcut(",")`、`reduceMotion` 的五处落点 |

| **没跑** | 为什么 |
|---|---|
| 切深色、逐页看界面 | 本任务的指令是「只写清单」；而且「哪一行字在深色下看不见」只有你的眼睛判得了（计划「需要用户参与的环节」那张表里也是这么写的）|
| 打开设置窗口 / 功能升级 / 问题反馈 / 关于窗口 | 同上；且开 App 会跑一次 preflight 把 ChatGPT 拉到前台，打断你手上的事 |
| 任何驱动 ChatGPT 的东西（`coach practice`、`axprobe press`）| 铁律 5：那会在你账号里产生真实对话和语音通话 |
| `chmod a-w` 你的真实数据目录 | 那是你的数据。写盘是「临时文件 + rename」，验完 `chmod u+w` 就复原，风险很小——但这一步该由你自己按第 16 节做 |
| `pbpaste` 的真实输出 | 要先打开 App 点那颗按钮。第 18.1 节那份是**按源码逐行推算**的，不是实测输出 |
