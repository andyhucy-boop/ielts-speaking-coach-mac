# 待修问题清单

每一条都是**真去改了代码、真跑了测试、真看到全绿**才报出来的——
不是「看起来可能有问题」，是「已经证明这个缺陷现在就能溜过去」。

修完一条就从这里删掉。

**最后一次整体复核：2026-08-06。当时基线 `swift test` = 484 条 / 0 失败 / 5.1 秒。**
（484 条里含 5 条尚未提交的工作区测试，见下面「零、交付状态」。）

---

## 零、交付状态（先看这条，不然会数错）

- **Batch A 第 1–4 条（权限页与 AppState）的修复在工作区里，没有提交。**
  改动涉及 `Sources/IELTSCoachApp/main.swift`、`AppState.swift`、`PermissionGateView.swift`、
  `PermissionStatus.swift`、`RootView.swift`，外加两个未跟踪的新测试文件
  （`AppSceneTests.swift`、`PermissionGateViewTests.swift`）。
  复核实测有牙齿：删掉 `AppState.swift:107` 的 `isCheckingPermission = true` →
  `testRecheckSaysItIsCheckingWhileThePreflightIsStillRunning` 当场变红。
  **下一步：把这批改动按显式路径提交，否则下一次 `git checkout` 会全丢。**
- 第 8、9 条（题库页）**这一轮产出为 0**，git log 里没有任何提交碰过 QuestionBank。
  见下面第一节，复核已重新实测确认。

---

## 一、题库页的导入接线全线无人看守（原第 8、9 条，一条都没修）

`Sources/IELTSCoachUI/QuestionBank/QuestionBankView.swift`

**2026-08-06 复核实测**：一次性做了三处突变——

1. 删掉 `panel.allowedContentTypes = QuestionBankImport.allowedContentTypes`
2. 删掉 `panel.canChooseDirectories = false`
3. 把 `runImport` 的整个 `catch` 块清空

→ `swift test` **484 条 0 失败**。

后果分别是：

1. `NSOpenPanel` 的 `allowedContentTypes` 为空 = 放行一切文件类型。用户能选中一张 `.jpg`，
   走到 `format(ofFileName:)` 才被拒——白跑一趟，而这正是 `QuestionBankView.swift:233-234`
   那句注释（「各写一份的话，面板放行了、解析却不认」）想防的事。
2. 用户能选中一个文件夹，报出来的提示是「把题库另存为 CSV」——对一个文件夹是句听不懂的话（铁律 4）。
3. **导入失败时屏幕上什么都不发生**：`feedback` 保持 nil、sheet 不弹。用户点了「导入」、
   选完文件、面板关掉，零反馈——教科书式的静默失败（铁律 5），
   而 `QuestionBankViewModel.swift:267` 那一整套写好的中文文案就此接不上任何东西。

同一批还有（上一轮复核实测，本轮未复验）：

- `try app.applyImport(result)` 换成就地伪造的 `QuestionBankImportOutcome` → 全绿。
  题目一道都没写进 `state.json`，用户却看到「导入完成，38 题」。
- 话题卡片列表、顶部三个统计数字、Part 筛选 Picker 各自换成 `EmptyView` → 全绿。
- `QuestionBankViewTests` 那条 `.sheet(item: $feedback)` 守卫可以被 `{ _ in EmptyView() }`
  架空（它查的第二个字符串 `QuestionBankImportFeedback` 命中的是第 27 行的 `@State` 声明，
  不是 sheet 内容）；警告守卫只要求 body 里出现 `ForEach` 与两次 `feedback.warnings`，
  管不到 `ForEach` 里画的是什么（换成一句泛泛的话、或 `.prefix(1)` 只画第一条，都全绿）。

**修法（一起堵才关得上）：** 用 `SourceGuard.functionBody(named:)` 扫 `chooseFile` 函数体，
要求同时出现 `panel.allowedContentTypes = QuestionBankImport.allowedContentTypes`
与 `panel.canChooseDirectories = false`，且不许出现字面的 `UTType` 列表；
扫 `runImport` 函数体，要求出现 `app.applyImport` 与 `catch` 分支里的
`QuestionBankImport.describeFailure`；sheet 那条改查闭包体里的 `QuestionBankImportResultSheet(`。

---

## 二、渲染守卫的根子：**干净删除照样全绿**（本次复核新发现，优先级最高）

上一轮建了 `RenderReachabilitySweepTests.testEveryViewMemberInTheModuleIsReachableFromItsBody`，
它确实有牙齿——删掉 `PracticeSheet` 里 `stageBlock` / `checklist` 那两句调用，
本次复核实测 5 条测试变红。

**但它只是一条「不留孤儿」的一致性检查，不是「这块内容在屏幕上」的存在性检查。**
它自己的失败文案就写着「确实不要了就连声明一起删掉」——也就是说，
**声明和调用一起删，是它明确放行的路径。**

2026-08-06 三次实测，全部 **484 条 0 失败**：

1. **复盘报告页的分区列表**：`ReviewReportView.swift:122`
   `ForEach(document.sections)` → `ForEach([ReviewSection]())`。
   调用还在、可达性还在，但「必须纠正的表达 / 更自然的说法 / 词汇升级」一条都不画。
2. **复盘报告页的 NEXT SINGLE TARGET**：删掉 `reportPane` 里那句
   `if let target = document.priorityTarget { priorityCard(target) }`，
   **同时**删掉整个 `priorityCard` 函数（干净删除，无孤儿）。
   这块是这个文件自己的注释写的「设计稿里最显眼的一块，也是这个产品真正的价值所在」。
3. **今日训练页的次级路线卡片**：`TodayView.swift:177`
   `ForEach(Array(available.dropFirst()))` → `.dropFirst().prefix(0)`。
   四条路线只剩第一条，其余三条静默消失。

**`ReviewReportView` 至今没有任何视图层测试**——`Tests/IELTSCoachUITests/` 下只有
`ReviewReportViewModelTests.swift`，没有 `ReviewReportViewTests.swift`。
整个复盘报告页（本产品的核心价值页）在视图层是零守卫。

**结论：贯穿 15 条的那个模式没有被解决，只是被打了补丁。**
被点过名的那几处现在有守卫了，没被点名的地方照旧。

**修的方向（择一或并用）：**

- 给可达性扫描加一个**存在性**维度：每个视图文件声明一份「这一页必须画出来的东西」清单
  （例如 `ReviewReportView` 必须画分区列表与 priorityCard），清单本身从规范文档读，
  而不是手写在测试里——手写清单的完整性问题见下面第四节 N3。
- 或者引入真正的视图求值（`ViewInspector` 之类），把「画出来了吗」从扫源码变成跑渲染。
  这是唯一能同时堵住「数据源被换空」和「干净删除」的做法。
- 最低成本的止血：至少给 `ReviewReportView` 补一个 `ReviewReportViewTests`，
  比照 `PracticeSheetTests` 钉住 `priorityCard` / `sectionCard` / `originalFileFooter`
  三处调用点与它们的数据源。

---

## 三、Core：内容哈希 id 与 PDF 抽取（第 10、11 条已修，以下是同类漏网）

第 10、11 条本身已修并验证：把 `questionID` 改成常量 → 本次复核实测 10 条测试变红。
剩下三条同类：

1. **真 PDF 只有一页，「只读第一页」照样全绿。**
   `QuestionBankViewModel.swift:289` 的 `PDFDocument(url: url)?.string` 改成
   `.page(at: 0)?.string` → 全绿。`Tests/IELTSCoachUITests/Support/TestPDF.swift`
   的 `data(lines:)` 从头到尾只 `beginPDFPage` 一次，所以四条真 PDF 守卫问的都是
   「有没有文字出来」，没人问「是不是全都出来了」。对用户那份 81 页题库，
   后果是静默丢题：导入成功、没有警告、只进来第一页那几道（铁律 5）。
   **修法：** `TestPDF` 加 `data(pages: [[String]])`，画两页，把第二页的某一行也写进断言。
2. **PDF 抽取器可以自己另写一套 id，part2/part3 无人看守。**
   `PDFQuestionExtractor.swift:335` 的 part2 id 换成 `"p2-" + stableHash(finished.prompt)`、
   `:342` 的 part3 id 换成 `"p3-" + stableHash(prompt)` → 全绿。
   新加的跨格式测试 `testTheSameQuestionImportedFromJSONAndFromAPDFGetsTheSameID`
   只拿 Part 1 试了。用户先导 JSON 版再导 PDF 版，全部 cue card 与全部 Part 3 追问会重一遍。
   另：只把 `:342` 改成 `questionID(part: 3, topic: "", prompt: prompt)` 也全绿——
   真实题库里不同 cue card 共用同一句追问是常态，丢掉 topic 后这些追问撞同一个 id，
   merge 当场吃掉一道。根因是 `QuestionIDTests.seasonalPDFText` 里三道 Part 3 题干互不相同。
   **修法：** 跨格式测试扩成 part1/part2/part3 各比一次；给第二张 cue card 加一句
   和第一张一模一样的追问，断言 9→10 道且 distinct id 仍等于题数。
3. **`|` 分隔符碰撞已知但没有任何断言记录。**
   `questionID` 用 `"\(topic)|\(prompt)"` 拼串，`topic="A|B"/prompt="C"` 与
   `topic="A"/prompt="B|C"` 算出同一个 id（`2y0jzboi0hdd3`）。
   「不在补测试的提交里顺手改 id 外形」这个决定是对的（要先想清数据迁移），
   但目前一条测试都没把这个取舍钉下来。
   **修法：** 加一条明确记录现状的断言，注释里写清为什么暂时接受、什么时候该改。

---

## 四、设计系统：三个守卫已修，但扫描器本身有六个口子

第 5、6、7 条已修并验证：`Spacing.lg` 24→8 → 本次复核实测当场变红。
以下是上一轮复核实测能溜过去的写法，均未修：

- **N1（最严重）：`.opacity()` 写成独立的视图修饰符就完全不受管。**
  `Text(hint).foregroundStyle(Palette.textSecondary).opacity(0.35)` 与被堵住的
  `Palette.textSecondary.opacity(0.35)` 视觉结果一样（对比度掉到 2:1 上下），
  但 `colorViolations` 的正则要求两者连在一起。同族的 `.brightness(` / `.grayscale(` /
  `.saturation(` 同理。
- **N2（最严重）：把令牌写成 `var` 或计算属性，三条完整性守卫全部失明。**
  根因是 `SourceGuard.declaredTokenNames` 的正则 `public\s+static\s+let\s+(…)` 只认 `let`。
  实测三个突变（`Radius.sheet` / `Palette.subtle` / `Typography.heading` 各写成 `var`
  并真用在视图上）一起改 → 全绿。漏掉 `public` 写成 `static let` 也一样溜。
- **N3：颜色和字体的 enum 名单是写死的，只有 `Metrics` 是从源码读的。**
  往 `Palette.swift` 里加 `public enum Ink { public static let faint = … }` 并在视图里用它
  → 全绿。提交信息里「enum 名单也从源码读」这句只对 `Metrics` 成立。
- **N4：钉住了取值，却没人管这个令牌有没有被用上。**
  删掉 `.tracking(Tracking.label)`（模块里唯一的使用处）→ 全绿；
  删掉 `CoachCard` 那整段 `.overlay(RoundedRectangle(…).strokeBorder(Palette.cardBorder, …))`
  → 全绿，所有卡片失去发丝边框，而规范第 4 节写的是「靠边框和留白分层，不靠阴影」。
  `testEveryViewActuallyReachesForTheTokens` 只要求每个文件 ≥1 处 `Typography.` 和
  ≥1 处 `Palette.`，挡不住逐个修饰符被删。
- **N5：扫描根只有 `Sources/IELTSCoachUI`，模块外还有一个 SwiftUI 文件。**
  `Sources/IELTSCoachApp/main.swift` 里挂在根视图上的样式作用于整个应用。
  实测在那里挂 `.font(Font.caption)` + 字面色 + `.padding(7)` → 全绿。
  `SourceGuard.swiftFiles(in:describedAs:)` 已经被 `TodayViewModelTests` 用来扫整个
  `Sources/`，扩范围的工具是现成的。
- **N6（轻）：「被钉住」的判据只是一段文本存在。**
  `pinning.contains("XCTAssertEqual(Radius.sheet,")` —— 写
  `XCTAssertEqual(Radius.sheet, Radius.sheet)` 就满足了。要有牙齿，右边得强制是字面量。

另外两条不是缺陷但要记一笔：

- `RootView.swift` / `PermissionGateView.swift` 仍未收编进设计系统（共 33 处字面样式），
  现在靠 `testTheUnmigratedPagesCannotGetAnyWorse` 的上限 17 / 16 做棘轮。
  **注意棘轮只在四类扫描认得出的违规内成立**，`.frame(width:)` 那类不计数。
- 上一轮报告里说 `testSpacingScaleIsMultiplesOfFour`「已经一并改掉了」——**不实**。
  它现在还在 `DesignSystemTests.swift:200`，一个字没改。留一条弱测试在强测试旁边本身无害，
  但报告里说改了而实际没动，比留着那条弱测试更值得记一笔。

---

## 五、练习流程：第 12、13、14 条已修，同类仍能溜

第 12 条已修并验证：删掉 `PracticeSheet` 里 `stageBlock` / `checklist` 两句调用 →
本次复核实测 5 条测试变红（`PracticeSheetTests` 2 条 + `RenderReachabilitySweepTests` 1 条
+ `SourceGuardTests` 1 条 + 1 条断言）。以下未修：

- **`private var actions` 的 `default:` 分支那颗唯一的「取消」没人钉。**
  换成 `default: EmptyView()` → 全绿。启动语音那 9 秒 + 请复盘那 1 分钟里，
  界面上一颗按钮都没有，用户唯一的出路是强退（铁律 5），
  而这个文件自己的 MARK 就写着「按钮：每个状态都得有一条出口」。
- **`case .done` 那颗「完成」也没人钉。** 删掉整块 → 全绿。删掉之后 `.done` 掉进 `default`，
  按钮变成「取消」且接的是 `abandon()` → `runner.cancel()`——练完存好档之后，
  收尾按钮写着「取消」、按下去走的是取消语义。
- **`SourceGuard.clickTargets` 的正则 `点(?:一下)?「([^」]+)」` 只认「点」和「点一下」。**
  `点击「X」`、`按「X」`、`按一下「X」`、`选「X」`、用『』写的，全都直接穿过去。
  仓库里本来就在用这些变体（`PracticeRunner.swift:191`、`TodayView.swift:371`、
  `AppState.swift:144`），不是假想写法。
- **文案扫描的范围只有 `Sources/IELTSCoachUI/`，而第 14 条这个 bug 本来就是从
  `Sources/IELTSCoachCore/Review/ReviewParser.swift` 漏进来的。**
  `Sources/ChatGPTBridge/HostEnvironment.swift` 今天也有两句直接指名图形界面按钮的文案，
  它们对得上靠的是 `HostEnvironmentTests:88` 一条手写断言，不是结构性检查。
  实测在 `HostEnvironment.retryInstruction` 里加一句指向不存在按钮的文案 → 全绿。
  `SourceGuard` 已有 `swiftFiles(atRepositoryPath:)`，扩范围成本很低。
- **`checklist` 的数据源被换掉照样全绿**：`ForEach(steps, id:)` 改成
  `ForEach([PracticeStage](), id:)` → 全绿。调用还在、可达性还在，但九秒里那列进度一格都不画。
  这与第二节是同一个根子。
- **`SourceGuard.viewTypes(in:)` 把 `extension` 当独立类型切段**，又跳过不含 `body` 的段。
  结果任何写在 `extension SomeView { … }` 里的 `some View` 成员，可达性扫描完全看不见。
  实测把 `PracticeSheet.header` 整段搬进 `extension` 并删掉 body 里那一句 → 全绿。
  「把成员按职责拆进 extension」是 SwiftUI 里最常见的整理手法。
  顺手要修的：`func …(…) -> some View` 那条正则的 `\([^)]*\)` 吃不下嵌套括号，
  带闭包参数的渲染方法会静默漏认；建议给「扫到的类型数」加一条硬对账
  （每个文件里 `: View` 的类型数必须与实际扫到的类型数相等）。

---

## 六、Bridge：第 15 条已修，两条同类未修

- **`PracticeRunner` 的三个注入超时全是空参数。**
  `Sources/IELTSCoachUI/Session/PracticeRunner.swift:61-63/77-79` 注入了
  `composerTimeout=20` / `replyTimeout=60` / `copyTimeout=10`，分别在 `:110` / `:152` / `:219`
  传给 bridge。把构造函数里那三行赋值全改成 `= 0.001` → **484 条全绿**。
  根因：`PracticeRunnerTests.swift:58/75/84` 的 `FakeBridge` 三个方法把 `timeout` 形参
  整个忽略，既不记录也不等待。全仓库没有第二个地方传这三个参数，所以它们今天纯粹是装饰。
  **修法：** `FakeBridge` 加 `recordedTimeouts`，断言拿到的是构造时传进去的那三个值
  （与这次给 `FakeAXAccess` 加 `wakeTimeouts` 完全同构）。
- **`waitForAssistantReply` 自己的 `timeout` 形参是第 13 个等待点，新扫描表漏了它。**
  `AXDriver.swift:181` 的 `addingTimeInterval(timeout)` 改成 `addingTimeInterval(3.0)`
  → 40 条全绿，唯一变化是耗时 1.80 → 4.68 秒。
  探针表里这条是全表唯一走成功路径的（`expectsFailure: false`），量到的只有采样间隔，
  deadline 根本没进入 0.5 秒上界的射程。生产上 CLI 传 60、`PracticeRunner` 传
  `replyTimeout=60`；写死小了 → 3 秒就抛错，而错误文案是「等了 60 秒」（铁律 4 的假话）。
  **修法：** 加一条 `PacingProbe(step: "waitForAssistantReply 用调用方传进来的超时",
  atLeast: callerGiven * 0.8, expectsFailure: true)`，空树永远够不到 `minimumLength`。

### 两条已知局限，不是缺陷，但别让下一个人当成保证

- 扫描测试的上界是全表统一的 0.5 秒。将来谁加一个 0.3 秒的「缓一拍」字面量，扫描照样绿。
- `testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately`
  （`AXDriverTests.swift:175`）在机器忙的时候会偶发 unexpected failure（20 次里见到 1 次）。
  它用 `asyncAfter` 整树替换 `access.nodes`，而 `FakeAXAccess` 无锁、`onPress` 又对同一个
  数组做原地修改，后续 `waitUntil` 只有 0.05 秒窗口。
  建议改成用 `onSnapshot`（按采样次数造场景）而不是墙上时间的 `asyncAfter`。

---

## 七、报数口径

下一轮别拿 484 当干净基线：其中 5 条来自工作区里尚未提交的
`AppSceneTests.swift`（2 条）与 `PermissionGateViewTests.swift`（3 条）。
以后报数请注明工作区状态，或在干净 worktree 里取基线。
