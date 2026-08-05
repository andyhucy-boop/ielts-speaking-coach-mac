# 待修问题清单

每一条都是独立复审**真去改了代码、真跑了测试、真看到全绿**才报出来的——
不是「看起来可能有问题」，是「已经证明这个缺陷现在就能溜过去」。

修完一条就从这里删掉。

---

## Batch A（Phase 3 Task 1/2/3/7）遗留

### ✅ 已修：打包脚本的两个闸门（b9e9a17）

### 1. `PermissionStatus.title(for:)` 没有任何测试管得住

`Sources/IELTSCoachUI/Onboarding/PermissionStatus.swift:42`

权限页最顶上的大标题，四个状态四句话。唯一提到它的断言是
`PermissionStatusTests.swift:204` 的
`XCTAssertTrue(text.contains(PermissionStatus.title(for: .unknown)))`——
而 `diagnosticsText` 里那行「状态：」正是用同一个 `title(for:)` 拼的，
**等于拿函数的输出跟它自己比，恒真，零约束力**。

复审实测：把 `.needsAccessibility` 和 `.needsChatGPT` 的标题对调
（很常见的复制粘贴错误），`swift test` 依然 223 全绿。

**后果：** 「装了 ChatGPT 但没给辅助功能权限」的用户，看到的大标题是
「还没装 ChatGPT」，会跑去重装一遍应用。

**修法：** 逐个状态钉死标题文本，别用 `title(for:)` 自己去比自己。

### 2. 「重新检查」按钮在失败时完全没有反馈

`Sources/IELTSCoachUI/Onboarding/PermissionGateView.swift:75, 78`

这是这个页面上用户按得最多的键——去系统设置勾完开关回来，第一件事就是按它。
但它是全页唯一一个不产出 `ActionNotice` 的按钮：重查结果和上次一样时
（授权没生效、TCC 还没刷新、勾错了对象），`state` 和 `messages` 都不变，
**视图不会有任何一个像素变化**，用户分不清是「查过了还是不行」还是「按钮坏了」。

同一个提交（c9e3e22）自己刚把「`NSWorkspace.open` 丢返回值 → 用户看到点了没反应」
认定为必须修，同一屏上却对最关键的按钮留了原样。

**修法：** 至少让「已重新检查，仍未通过：<原因>」显示出来。

### 3. `isCheckingPermission = true` 没有任何测试管得住

`Sources/IELTSCoachUI/AppState.swift:70`

复审实测：把这一行删掉，`swift test` 仍然 245/245 全绿。

这一行是「用户点『重新检查』期间界面有反馈」的唯一实现。删掉后
`RootRouter` 一路返回 `.permissionGate`，用户点完按钮要对着授权页冻最多十秒
（preflight 会 `NSWorkspace.open` 拉起 ChatGPT + `wakeAccessibilityTree(timeout: 8.0)`）
**且零反馈**——正是 DESIGN-SYSTEM 第 5 节「超过 300ms 必须有反馈」禁止的。

更要紧的是：Task 3 偏离计划（把环境检查从 init 挪到 `.task`）的**整个理由就是这个反馈**，
而首次检查那条路径有测试，重查这条没有。

### 4. `WindowGroup` 把整个 `AppState` 劈成两份

`Sources/IELTSCoachApp/main.swift:6` 用 `WindowGroup`，
而 `Sources/IELTSCoachUI/RootView.swift:7, 11` 让每个 `RootView` 自己 new 一个 `AppState()`。

macOS 上 `WindowGroup` 默认带「文件 ▸ 新建窗口」（⌘N）。开第二个窗口 =
第二个 `AppState` = **第二次完整 preflight**（又一次 `NSWorkspace.open(ChatGPT)`
把 ChatGPT 拉到前台），且两个窗口的 `state`、`loadError`、`permissionSkipped` 互不相通——
在一个窗口点了「先跳过」，另一个还挡着；导入题库之后，另一个窗口显示的是旧题库。

Task 3 之前 `RootView` 只是一行 Text，这个缺陷无害；**从那次提交起它才开始咬人**。

计划里从头到尾没提过窗口数量（phase3/5/10 三份都 grep 过），是计划的盲区。

**修法任选：** `main.swift` 改用 `Window(...)`；或保留 `WindowGroup` 但把 `AppState`
提到 App 层用 `@State` 持有并 `.environment` 下发，同时移除 ⌘N。

### 5. 字体扫描有一个一步就能绕过的口子

`Tests/IELTSCoachUITests/DesignSystemTests.swift:134-138`

`forbidden` 列表是 `["font(.", "fontWeight(", ".bold()"]`，**全部只认「点开头」的写法**。

复审实测：把 `Components.swift:135` 的 `.font(Typography.label)` 换成
`.font(Font.caption)`（完全限定写法，编译通过，渲染结果与 `.font(.caption)` 完全一致，
`SectionHeader` 的编号+英文标签当场从 medium 退回 regular），
`swift test --filter DesignSystemTests` → 10 tests / 0 failures，**全绿**。

也就是说：那次提交的全部意义是「让 SectionHeader 掉字重不可能再发生」，
而换一种同义写法它照样能发生，守门员看不见。
同类漏网写法还有 `.font(Typography.body.weight(...))`。

### 6. 「字面颜色值」和「圆角」在设计系统里零自动守卫

`testDesignSystemTakesFontsFromTypographyTokens` 只扫字体。

复审实测：把 `EmptyStateView` 的 `.foregroundStyle(Palette.textSecondary)` 换成
`.foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.62))`（**2.7:1 的灰，
正是规范第 2 节点名批评的「灰上加灰」**），同时把 `CoachCard` 的
`.background(Palette.card)` 换成字面米色、`cornerRadius: Radius.card` 换成 `6`，
→ 10 tests / 0 failures，**全绿**。

对比度那几条测试量的是 `Palette` 里的令牌，管不到视图有没有真的去用令牌。
铁律第 8 条写的是「字面颜色值、字号、圆角」，现在只守住了字号的一半。

### 7. `Spacing` 与 `Radius` 的取值完全没被钉住

`Tests/IELTSCoachUITests/DesignSystemTests.swift:104-108` 的
`testSpacingScaleIsMultiplesOfFour` **只断言「能被 4 整除」**。

复审实测：`Spacing.lg` 24→8、`Spacing.xl` 32→4、`Radius.card` 12→40、
`Radius.control` 8→0，→ 10 tests / 0 failures，**全绿**。

实际效果是卡片内边距塌成 8、页面内边距塌成 4、卡片变成胶囊——
正是 DESIGN-SYSTEM 第 3 节反复强调「留白很足是它显得高级的主要原因，不要压缩」的那条。
而 `Radius` 根本一条测试都没有，它还写在 Task 7 的 Produces 清单里。

同一个文件里 `Typography` 是逐行钉死的（`testTypographyTokensMatchTheSpecTable`），
第 1 节的表享受这个待遇、第 3 节的表不享受，**没有理由**。
