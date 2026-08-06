# 待修问题清单

每一条都是**真去改了代码、真跑了测试、真看到结果**才报出来的——
不是「看起来可能有问题」，是「已经证明这个缺陷现在就能溜过去」。

修完一条就从这里删掉。**但只有自己做过突变、亲眼看到红，才允许删。**

**最后一次整体复核：2026-08-06。基线 `swift test` = 522 条 / 0 失败 / 5.2–5.6 秒。**
（复核当时工作区有 6 个文件的改动，见「零、本轮复核」；除此之外与 `phase2-bridge` HEAD 一致。）

> 上一版这里写的是 484 条。484 是更早一次复核的数字，中间几批补测试之后
> 实测就是 521 条；本轮我自己又加了 1 条，共 522。别再拿 484 当基线。

---

## 零、本轮复核：做了什么、看到了什么

### 四个「曾经全绿」的最狠突变，现在全部变红

| 突变 | 结果 | 咬住它的测试 |
| --- | --- | --- |
| `QuestionBankView.runImport` 的 `catch` 块清空 | **4 条断言红** | `QuestionBankViewTests.testAFailedImportAlwaysPutsSomethingOnScreenInsteadOfSwallowingTheError` |
| `ReviewReportView` 的 `ForEach(document.sections)` → `ForEach([ReviewSection]())` | **2 条测试红** | `ReviewReportViewTests` 的分区断言 + 顺序断言 |
| `PracticeSheet.actions` 的 `default:` → `EmptyView()` | **8 条断言红**（8 个 stage 各报一次） | `PracticeSheetTests.testEveryPracticeStageHasAWayOut` |
| `QuestionBankViewModel` 的 `PDFDocument(url:)?.string` → `.page(at: 0)?.string` | **3 条测试红** | `QuestionBankPDFImportTests` 三条真 PDF 守卫 |

每次突变后都 `git checkout --` 还原并确认 `git status` 干净。

### 顺带复验的六个突变，也都咬住了

`panel.canChooseDirectories = false` 删掉、`panel.allowedContentTypes = …` 删掉、
`try app.applyImport(result)` 换成就地伪造的 `QuestionBankImportOutcome(…)`、
`.sheet(item:)` 闭包架空成 `EmptyView()`、PDF 抽取器的 part2 自己另写一套 id、
part3 丢掉 `topic` —— 六个全部变红。第一节（原「题库页导入全线无人看守」）
与第三节前两条据此删除。

### 本轮修掉的两件（都不是上面点名的四条）

1. **警告行的守卫其实一直没有咬合**——见下面第五节「已修，记一笔」。
2. **三个 shell 脚本在 UTF-8 locale 下直接崩**——见下面第六节「已修，记一笔」。

---

## 一、扫源码证明不了渲染（结构性边界 → 归 Task 11 人工验收）

**这一条不是待办，是这个手段的固有边界。写在这里是为了不让下一个人重新发现一遍。**

`SourceGuard` 那一整套做的是「源码里有没有这段文本」，不是「屏幕上有没有这个东西」。
因此下面这类突变，**扫源码永远拦不住**：

- **干净删除**：把渲染成员的声明和调用**一起**删掉，不留孤儿。
  `RenderReachabilitySweepTests` 只报「走不到的」，不报「不见了的」——
  它自己的失败文案就写着「确实不要了就连声明一起删掉」。
- **代码还在但跑不到**：`if let target = document.priorityTarget, false { … }`
  这类恒假条件，文本全在，断言全绿，界面上什么都没有。
- **叶子函数被掏空**：没有下级视图成员的渲染函数（例如 `statusBadge(for:)`）
  整个换成 `EmptyView()`，可达性扫描看不出来——守卫只钉得住上层那句调用。

**已经定了：不往这里投人，也不引第三方依赖（零依赖是硬约束）。**
真要堵死得引入渲染层测试框架（`ViewInspector` 之类），成本与约束都不允许。

**兜底方式：Task 11 的人工验收。** 那一关要真的把应用跑起来、逐页看一遍，
特别是复盘报告页（分区、NEXT SINGLE TARGET、原文页脚）、今日训练页的四条路线、
练习流程等待期间的出口按钮。**清单上任何一条「已修」都不等于「屏幕上真的画出来了」。**

作为补偿，各页现在都有一条「本页声明的渲染成员必须全部可达」的存在性清单
（例如 `ReviewReportViewTests.testEverySectionThisPageDeclaresIsReachableFromItsBody`
列出 13 个成员）。它挡得住「悄悄少画一块」，挡不住「连清单带实现一起删」。

---

## 二、渲染数据源被换空，仍有两处无人看守（本轮实测复现）

第二节原来列了三处，其中复盘报告页那两处已被 `ReviewReportViewTests` 钉住（见第零节）。
**剩下这两处，本轮 2026-08-06 重新实测，仍然全绿：**

1. **今日训练页的次级路线卡片**
   `Sources/IELTSCoachUI/Today/TodayView.swift:177`
   `ForEach(Array(available.dropFirst()))` → `ForEach(Array(available.dropFirst().prefix(0)))`
   → **522 条 0 失败**。四条路线只剩第一条，其余三条静默消失，用户不知道自己少了三个选择。
   **修法：** 比照 `ReviewReportViewTests` 的做法，在 `TodayViewTests` 里用
   `memberBody` 切出那一段，钉住 `available.dropFirst()` 整串并禁掉 `.prefix(` / `.dropLast(`。

2. **练习流程的进度清单数据源**
   `Sources/IELTSCoachUI/Session/PracticeSheet.swift:214`
   `ForEach(steps, id: \.stepName)` → `ForEach([PracticeStage](), id: \.stepName)`
   → **522 条 0 失败**。调用还在、可达性还在，但那九秒里进度清单一格都不画，
   用户看不出程序是在跑还是卡死了。
   **修法：** 切出 `checklist` 成员体，钉住 `ForEach(steps` 这个字面串。

> 注意这两条与第一节不是同一回事：数据源被换空时**调用还在**，
> 所以扫源码是拦得住的（钉住数据源那个字面串即可），只是现在没人钉。
> 第一节那种「干净删除」才是真的拦不住。

---

## 三、Core：`|` 分隔符碰撞（已知并已写进断言，保留观察）

第 10、11 条与本节原来的前两条都已修并复验（见第零节）。剩这一条：

`questionID` 用 `"\(topic)|\(prompt)"` 拼串，所以
`topic="A|B"/prompt="C"` 与 `topic="A"/prompt="B|C"` 算出同一个 id。

**这不是待修缺陷，是一个记录在案、当前故意接受的取舍**——
`QuestionIDTests.testTheSeparatorCollisionIsAKnownAndDeliberatelyAcceptedTradeoff`
已经把现状、原因、什么时候该改、改了要同步哪些断言全部写进去了。

保留在清单上只为一件事：**将来出现带竖线的题库来源，或本来就要做 id 迁移时，
顺手换成带长度前缀/转义的编码并加版本前缀。** 单独为它改一次 id 外形不划算——
全体用户每道题的 id 会变一遍，练习记录与训练计划会全部指错题。

---

## 四、设计系统：扫描器本身的六个口子（上一轮实测，本轮未复验）

第 5、6、7 条已修。以下六条是上一轮复核实测能溜过去的写法，**本轮没有重新实测**，
按原样保留——写下这句是因为「未复验」和「已确认仍在」不是一回事。

- **N1（最严重）：`.opacity()` 写成独立的视图修饰符就完全不受管。**
  `Text(hint).foregroundStyle(Palette.textSecondary).opacity(0.35)` 与被堵住的
  `Palette.textSecondary.opacity(0.35)` 视觉结果一样（对比度掉到 2:1 上下），
  但 `colorViolations` 的正则要求两者连在一起。同族的 `.brightness(` / `.grayscale(` /
  `.saturation(` 同理。
- **N2（最严重）：把令牌写成 `var` 或计算属性，三条完整性守卫全部失明。**
  根因是 `SourceGuard.declaredTokenNames` 的正则 `public\s+static\s+let\s+(…)` 只认 `let`。
  漏掉 `public` 写成 `static let` 也一样溜。
- **N3：颜色和字体的 enum 名单是写死的，只有 `Metrics` 是从源码读的。**
  往 `Palette.swift` 里加 `public enum Ink { … }` 并在视图里用它 → 全绿。
- **N4：钉住了取值，却没人管这个令牌有没有被用上。**
  删掉 `.tracking(Tracking.label)`（模块里唯一的使用处）→ 全绿；
  删掉 `CoachCard` 那整段发丝边框 `.overlay(RoundedRectangle(…).strokeBorder(…))` → 全绿，
  而规范第 4 节写的是「靠边框和留白分层，不靠阴影」。
- **N5：扫描根只有 `Sources/IELTSCoachUI`，模块外还有一个 SwiftUI 文件。**
  `Sources/IELTSCoachApp/main.swift` 里挂在根视图上的样式作用于整个应用。
  `SourceGuard.swiftFiles(in:describedAs:)` 已经被 `TodayViewModelTests` 用来扫整个
  `Sources/`，扩范围的工具是现成的。
- **N6（轻）：「被钉住」的判据只是一段文本存在。**
  `pinning.contains("XCTAssertEqual(Radius.sheet,")` —— 写
  `XCTAssertEqual(Radius.sheet, Radius.sheet)` 就满足了。右边得强制是字面量才有牙齿。

另记两笔（不是缺陷）：

- `RootView.swift` / `PermissionGateView.swift` 仍未收编进设计系统（共 33 处字面样式），
  靠 `testTheUnmigratedPagesCannotGetAnyWorse` 的上限 17 / 16 做棘轮。
  **棘轮只在四类扫描认得出的违规内成立**，`.frame(width:)` 那类不计数。
- `testSpacingScaleIsMultiplesOfFour`（`DesignSystemTests.swift:200`）是条弱测试，仍在。
  留一条弱测试在强测试旁边本身无害；记一笔是因为更早的报告里说它「已经一并改掉了」——不实。

---

## 五、练习流程：出口按钮已钉住，同类仍能溜

`default:` 那条（等待期间一颗按钮都没有）已修，见第零节。以下未修：

- **`case .done` 那颗「完成」没人钉。本轮 2026-08-06 实测：整块删掉 → 522 条 0 失败。**
  删掉之后 `.done` 掉进 `default`，按钮变成「取消」且接的是 `abandon()` → `runner.cancel()`。
  **练完、复盘已存档之后，收尾按钮写着「取消」，按下去走的是取消语义**——
  这比没有按钮更糟：用户以为自己刚把成绩取消了。
  注意 `testEveryPracticeStageHasAWayOut` 拦不住它，因为它只问「有没有出路」，
  `default` 那颗「取消」满足了这个问题。
  **修法：** 单独钉 `.done` 分支：必须有 `Button("完成"` 且动作是 `onClose`，不许是 `abandon`。
- **`SourceGuard.clickTargets` 的正则 `点(?:一下)?「([^」]+)」` 只认「点」和「点一下」。**
  `点击「X」`、`按「X」`、`按一下「X」`、`选「X」`、用『』写的，全都直接穿过去。
  仓库里本来就在用这些变体（`PracticeRunner.swift:191`、`TodayView.swift:371`、
  `AppState.swift:144`），不是假想写法。
- **文案扫描的范围只有 `Sources/IELTSCoachUI/`。**
  第 14 条那个 bug 本来就是从 `Sources/IELTSCoachCore/Review/ReviewParser.swift` 漏进来的。
  `Sources/ChatGPTBridge/HostEnvironment.swift` 今天也有两句直接指名图形界面按钮的文案，
  它们对得上靠的是 `HostEnvironmentTests:88` 一条手写断言，不是结构性检查。
  `SourceGuard` 已有 `swiftFiles(atRepositoryPath:)`，扩范围成本很低。
- **`SourceGuard.viewTypes(in:)` 把 `extension` 当独立类型切段**，又跳过不含 `body` 的段。
  结果任何写在 `extension SomeView { … }` 里的 `some View` 成员，可达性扫描完全看不见。
  「把成员按职责拆进 extension」是 SwiftUI 里最常见的整理手法。
  顺手要修的：`func …(…) -> some View` 那条正则的 `\([^)]*\)` 吃不下嵌套括号，
  带闭包参数的渲染方法会静默漏认；建议给「扫到的类型数」加一条硬对账
  （每个文件里 `: View` 的类型数必须与实际扫到的类型数相等）。

### 已修，但要记一笔：警告行的守卫此前一直没有咬合

`QuestionBankImportResultSheetTests.testEachWarningRowPrintsThatWarningInsteadOfAGenericSentence`
要求 `warning` 在 `ForEach` 闭包体里至少出现两次（闭包参数一次、真的画出来一次）。
**但它用的 `SourceGuard.occurrences` 是纯子串计数**，而那一行里同时有
闭包参数 `warning`、颜色令牌 `Palette.warning`、真正画出来的 `Label(warning, …)`——
**前两样就把「至少两次」凑满了。**

本轮实测：把 `Label(warning, …)` 换成一句泛泛之词 → **全绿**；
再把 `Palette.warning` 一并换掉才变红，证明它数到的是那个颜色令牌。

**已修**：新增 `SourceGuard.standaloneOccurrences(of:in:)`（前面挂点号的成员名、
以及只是撞了前缀的更长的名字都不算），该测试改用它，并补了 `SourceGuardTests` 自测。
修完复验：同一个突变现在 **1 条测试红**。

**教训（对后来者更重要）：凡是「参数收下了有没有真的用上」这类断言，
不要用 `occurrences`，用 `standaloneOccurrences`。** 纯子串计数很容易被
同名的令牌、同前缀的属性名悄悄凑满，测试看着有牙齿，其实一直是空转的。
清单里其他用次数做判据的地方值得照这个思路再扫一遍——本轮没有全面排查。

---

## 六、Bridge：两条同类未修

- **`PracticeRunner` 的三个注入超时全是空参数。本轮 2026-08-06 实测仍然全绿。**
  `Sources/IELTSCoachUI/Session/PracticeRunner.swift:77-79` 的
  `composerTimeout = 20` / `replyTimeout = 60` / `copyTimeout = 10`
  三行一起改成 `0.001` → **522 条 0 失败**。
  根因：`PracticeRunnerTests.swift:58/75/84` 的 `FakeBridge` 三个方法把 `timeout` 形参
  整个忽略，既不记录也不等待。全仓库没有第二个地方传这三个参数，所以它们今天纯粹是装饰。
  **注意这条不违反铁律 7**——要加的是守卫，不是改超时值本身。
  **修法：** `FakeBridge` 加 `recordedTimeouts`，断言拿到的是构造时传进去的那三个值
  （与 `FakeAXAccess` 的 `wakeTimeouts` 完全同构）。
- **`waitForAssistantReply` 自己的 `timeout` 形参是第 13 个等待点，扫描表漏了它。**
  （上一轮实测，本轮未复验。）`AXDriver.swift:181` 的 `addingTimeInterval(timeout)`
  改成 `addingTimeInterval(3.0)` → 全绿，唯一变化是耗时 1.80 → 4.68 秒。
  探针表里这条是全表唯一走成功路径的（`expectsFailure: false`），量到的只有采样间隔。
  生产上 CLI 传 60、`PracticeRunner` 传 `replyTimeout=60`；写死小了 → 3 秒就抛错，
  而错误文案是「等了 60 秒」（铁律 4 的假话）。
  **修法：** 加一条 `PacingProbe(step: "waitForAssistantReply 用调用方传进来的超时",
  atLeast: callerGiven * 0.8, expectsFailure: true)`，空树永远够不到 `minimumLength`。

### 已修，但要记一笔：三个 shell 脚本在 UTF-8 locale 下直接崩

本轮先是发现 `IconPipelineTests` 会**间歇性**失败（5 次里 5 次红，另外几次全绿），
追下去不是偶发，是**环境相关的必现**：

```
scripts/verify-iconset.sh: line 45: name?: unbound variable
```

根因：macOS 自带的是 **bash 3.2**。脚本里写了 `"…缺少 $name（$ICONSET）。"`——
`$name` 后面紧跟一个**全角括号**。当 `LC_CTYPE` 是 UTF-8 时，
bash 3.2 会把全角字符的第一个字节吞进变量名，变成 `name\xef`，
`set -u` 当场以「unbound variable」中止脚本。`LC_CTYPE` 没设时反而正常。

**为什么之前没人发现**：这台机器上 `LANG` / `LC_ALL` 都是空的，直接跑 `swift test` 一路全绿；
只有当调用方（例如 Python，PEP 538 会把 `LC_CTYPE` 强制成 `C.UTF-8` 并传给子进程）
带进一个 UTF-8 locale 时才炸。**而正常开发机和绝大多数 CI 镜像的 locale 就是 UTF-8。**

后果（铁律 4 + 5）：用户看到的不是「缺了哪个文件、下一步做什么」那句中文，
而是一句 bash 报错；`make-icon.sh` 整个非零退出。
`scripts/build-app.sh:69` 那句签名失败提示同样中招——**恰恰是最需要看懂错误的时刻。**

**已修**：把 5 处 `$变量` + 全角字符全部改成 `${变量}`（`verify-iconset.sh` 3 处、
`make-icon.sh` 1 处、`build-app.sh` 1 处）。
复验：`LC_CTYPE=UTF-8 swift test` → 522 条 0 失败；去掉大括号还原成原写法 → 当场 2 条红。

**仍未修（记录在案）：整个测试基线是随 locale 变的。**
没有任何地方把 `LC_CTYPE` 钉死，所以「本机全绿」不代表「CI 全绿」。
上面那个脚本 bug 在本机是**完全隐形**的——测试写对了、也确实会红，只是从来没在会红的环境里跑过。
**修法：** 在测试里显式给子进程设 `LC_CTYPE`（至少跑一遍 UTF-8），
或在 CI 里固定 `LANG=en_US.UTF-8`。**建议优先级高**：这类「基线本身不可信」的问题，
比清单上任何一条具体缺陷都更能让人误判交付状态。

---

## 七、两条已知局限，不是缺陷，但别让下一个人当成保证

- 等待点扫描测试的上界是全表统一的 0.5 秒。将来谁加一个 0.3 秒的「缓一拍」字面量，扫描照样绿。
- `testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately`
  （`AXDriverTests.swift:175`）在机器忙的时候会偶发 unexpected failure（20 次里见到 1 次）。
  它用 `asyncAfter` 整树替换 `access.nodes`，而 `FakeAXAccess` 无锁、`onPress` 又对同一个
  数组做原地修改，后续 `waitUntil` 只有 0.05 秒窗口。
  建议改成用 `onSnapshot`（按采样次数造场景）而不是墙上时间的 `asyncAfter`。

---

## 八、报数口径

- 本轮基线：**522 条 / 0 失败 / 5.2–5.6 秒**（`LC_CTYPE` 空和 `LC_CTYPE=UTF-8` 两种都跑过）。
- 报数时请注明**工作区状态**与 **locale**。没有 locale 这一项的话，
  「全绿」这个说法本身是不完整的——见第六节。
