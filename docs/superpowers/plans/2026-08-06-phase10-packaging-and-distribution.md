# Phase 10：打包与分发

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个**能给别人**的 `.app`：有关于页（版本、数据目录、许可、致谢）、有首次使用引导、开了 Hardened Runtime 并带定稿的 entitlements、有一套「将来要公证时照着跑就行」的脚本（**本期不购买 Developer ID，不实际执行公证**）。同时把两件事从「应该没问题」变成「每次都自动验」：

1. **签名的「指定要求」跨打包稳定**——加了 Hardened Runtime 与 entitlements 之后仍然一模一样。它一变，用户的辅助功能授权当场失效，得回系统设置重新勾。这是这个产品最恼人的失败模式，因为它不报错、不崩溃，只是「今天怎么又不能自动开练了」。
2. **数据目录整个拷到另一台电脑就能接着用**（成品标准第 10 条）。

**本阶段还要收掉三件跨全部页面的尾（2026-08-06 跨阶段复审归入，见 Task 12–19）：**

3. **深色模式**（`DESIGN-SYSTEM.md` 第 2 节从 Phase 3 就写着「Phase 7 加深色模式时只改这一个文件」，Phase 7 没做，8/9 也没接）。放在这里做是对的：所有页面都存在之后再做，才不用返工。
4. **把散在三处的设置合并成一个 `⌘,` 设置窗口**（录音在 Phase 5 的设置窗口、每周目标在 Phase 7 的首页齿轮、三项练习偏好在 Phase 8 的学习计划页底部）。用户要改个东西得先猜它在哪。
5. **把侧边栏里「功能升级」「问题反馈」两项从占位做成真页面**——不新增条目，仍是十项。做完之后**十项全部有内容**，`PlaceholderView` 变成死代码。

**Architecture:** 保持 SPM 单一构建系统，不引入 `.xcodeproj`。打包仍由 `scripts/build-app.sh` 组装 `.app` 并签名；本阶段把它从「能签出来」升级成「签完立刻自检四件事，任何一件不对就退出非零」。关于页与首次引导是纯 SwiftUI，逻辑（版本解析、诊断文本、引导步骤计算）全部拆成可单元测试的值类型放 `IELTSCoachUI`，与设备无关的「数据可搬迁审计」放 `IELTSCoachCore`。公证与分发是四个 shell 脚本，由一个不依赖任何产品代码的测试 target `PackagingTests` 守住契约。

深色模式的做法是：**颜色令牌从一套变成两套静态取值**（`Palette.light` / `Palette.dark`），视图用的 `Palette.accent` 那一组变成随系统外观自动解析的动态颜色。两套取值都是能被单独取出来的值类型，因此「每一组前景/背景的对比度」是可以跑测试的。设置窗口与主窗口**共用同一个 `@Observable AppState` 实例**（从 `RootView` 提到 App 层），这是「在设置窗口改了、主窗口立刻看到」的机制本身，而不是靠事后刷新。「功能升级」的内容来自一个手工维护的 Swift 常量表，**运行时不读 git**——打包出去的 `.app` 里没有 git 仓库。

**Tech Stack:** Swift 6.3.3、SPM、SwiftUI、XCTest、`codesign`、`ditto`、`xcrun notarytool`（仅预留，不执行）。无第三方依赖，且本阶段新增一条测试守住「无第三方依赖」这个事实。

---

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit 的代码放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、`IELTSCoachAudio`（Phase 5 加的）、`IELTSCoachMCP` 不参与界面、SwiftUI
- 所有面向用户的文案必须是中文，且同时说明「**发生了什么**」和「**下一步做什么**」。这条对关于页、引导页、脚本输出一视同仁
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- 界面必须走设计令牌（`Palette` / `Spacing` / `Radius`），视图里不得出现字面颜色、字号、圆角。唯一视觉依据是 `docs/superpowers/DESIGN-SYSTEM.md`
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- 测试用 XCTest

---

## 本阶段明确不做的事

写下来防止范围扩大，也防止实现者「顺手多做一点」：

| 不做 | 为什么 |
|---|---|
| **不重做 App 图标** | Phase 3 Task 1 已经做掉（`scripts/make-icon.swift` + `make-icon.sh`）。本阶段只是继续调用它，一行都不改 |
| **不购买 Developer ID、不实际公证** | 设计文档第 10 节已定。本阶段只把架构和脚本预留好 |
| **不做 `.dmg`** | `.zip` 已经能把 `.app` 完整交给别人且不破坏签名（`ditto` 保留扩展属性）。`.dmg` 只是更好看，不解决任何实际问题 |
| **不做自动更新（Sparkle 之类）** | 需要引入第三方依赖 + 一个能长期挂着的更新服务器。这是个自用工具，换版本就是重新拷一个 `.app` |
| **不改 `state.json` 的 schema** | `schemaVersion: 3` 与上游/Windows 版兼容（设计文档 4.6）。本阶段新增的「是否看过引导」是**本机**状态，不进数据目录，理由见 Task 8 |
| **不新增侧边栏条目** | 侧边栏固定十项，Phase 3 有一条 `testSidebarHasAllTenItems` 守着，那条测试是对的。**关于页放在苹果菜单里**（`⌘` 菜单的「关于 …」），这是 Mac 应用的标准位置，不占侧边栏。**Task 17 / 18 把既有的「功能升级」「问题反馈」两项从占位做成真页面，这是填内容不是加条目**，十项一项不多一项不少 |
| **深色模式不做手动切换开关** | 只跟随系统（Task 13 有决策与理由）。macOS 用户改外观的地方是系统设置，App 再给一个「浅色/深色/跟随系统」三选一，等于多一份要同步的状态、多一个要测的组合，换来的是一个 Mac 用户本来就不会去 App 里找的开关 |
| **「问题反馈」不做工单系统、不自动发送任何东西** | 这是个人自用工具。这一页只做一件事：把诊断信息复制到剪贴板，粘给谁由用户自己决定。Task 18 有一条测试扫源码，`Sources/IELTSCoachUI/Feedback/` 里出现任何联网符号就红 |
| **不开 App Sandbox** | 沙盒会切断「用辅助功能驱动别的应用」和「读用户随手挑的题库文件」，产品直接不可用。公证**不要求**沙盒，只有 Mac App Store 要求。详见 Task 1 |

---

## 前置依赖（本阶段消费什么，由谁产出）

**如果下面任何一条不成立，先停下来报告，不要假装它存在。**

| 依赖 | 来自 | 本阶段怎么用 |
|---|---|---|
| `Palette` / `Spacing` / `Radius`；`CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView` | Phase 3 Task 7 | 关于页与引导页全部用它们搭，不自己写样式 |
| `enum PermissionState { case ready, needsAccessibility, needsChatGPT, unknown }`、`PermissionStatus.evaluate(readiness:) -> PermissionState`、`PermissionStatus.systemSettingsURL` | Phase 3 Task 2 | 引导的「环境」步骤与关于页的权限行 |
| `PermissionGateView(state:messages:onRecheck:onSkip:)` | Phase 3 Task 2 | **复用**为引导「环境」步骤的内容，不另写一套说同一件事的文案 |
| `@Observable final class AppState`（`state: CoachState`、`permission: PermissionState`、`permissionMessages: [String]`、`reload()`、`recheckPermission()`） | Phase 3 Task 3 | `RootView` 决定要不要显示引导 |
| `RootView` | Phase 3 Task 3 | 本阶段改它的顶层分支：把「权限没给就挡一下」换成完整的首次引导 |
| `scripts/build-app.sh`、`scripts/make-icon.sh` | Phase 3 Task 1 | 前者本阶段重写，后者原样调用 |
| 自签名证书 `IELTS Coach Dev` 在 login 钥匙串里 | Phase 3 前置条件 | 签名身份。**没有它整个阶段无法开工** |
| `CoachSettings.recordingEnabled` / `recordingConsentAt` | 已在 Core 里（`Sources/IELTSCoachCore/Model/CoachState.swift`） | 引导的「录音开关」步骤写它 |
| `PracticeSession.reportPath` / `recordingPath` 里存的是**相对于数据目录**的路径 | Phase 3 / 4 / 5 的写入代码 | Task 4 的审计就是来验证这个约定有没有被破坏的。**若审计一上来就报一堆问题，说明约定已经被破坏了，那是真 bug，不是审计写错了** |
| `ieltscoach://` 的处理（`onOpenURL`）与 `Info.plist` 里的 `CFBundleURLTypes` | Phase 9 Task 11 | **Phase 9 已经把两半都做了**，`build-app.sh` 里已经有 `CFBundleURLTypes` 那一段和一条校验。本阶段重写 `build-app.sh` 时**必须把它们一起搬过去**（Task 1 Step 2 的 Info.plist 与自检里已经带上了）。若 Phase 9 未完成，注册后点链接会打开 App 但不跳转——已知且可接受 |
| `NSMicrophoneUsageDescription` 的存在性校验 | Phase 5 Task 10 | 同上，本阶段重写脚本时不得丢掉这条校验。丢了不会报错，只会在真机上变成「一开录音就闪退、崩溃报告看不出原因」 |

**Task 12–19（深色模式、设置合并、两页）额外消费下面这些。它们分别来自 Phase 5 / 7 / 8，缺任何一条都要停下来报告，不要现造一个顶上：**

| 依赖 | 来自 | 本阶段怎么用 |
|---|---|---|
| `Palette` / `Spacing` / `Radius`、`DesignSystemTests.swift` | Phase 3 Task 7 | Task 12 把 `Palette` 从一套取值改成两套；`Spacing` / `Radius` 一个字不动 |
| `SidebarItem`（十项，含 `isImplemented`）、`PlaceholderView`、`NavigationTests` | Phase 3 Task 3 | Task 17 / 18 把 `.upgrade` / `.feedback` 标成已实现，并删掉变成死代码的 `PlaceholderView` |
| `AppState`（`state`、`permission`、`permissionMessages`、`loadError`、`reload()`、`recheckPermission()`、私有 `store`） | Phase 3 Task 3 | Task 15 给它加一个只给测试用的构造参数；Task 16 把它从 `RootView` 提到 App 层 |
| `AppState.mutate(_:) -> String?` | Phase 8 Task 9 | 设置窗口**唯一**的写盘路径 |
| `AppState.setWeeklyGoal(_:)`、`AppState.settingsError`、`WeeklyGoalSheet` | Phase 7 Task 9 | **Task 16 删掉这三样**，改由设置窗口统一承担；`WeeklyGoalEditor`（纯文案）搬家保留 |
| `RecordingSettingsView` / `RecordingSettingsViewModel` / `RecordingSettingsScene`、`RecordingStore`、`RecordingUsage.humanReadable(bytes:)`、`MicrophoneAuthorizing`、`FakeMicrophoneAuthorizer`（测试里的假实现） | Phase 5 Task 3 / Task 8 | Task 15 给视图模型加一个 `onChange` 钩子；Task 16 把 `RecordingSettingsView` **原样嵌进**设置窗口的「录音」分区，不重写 |
| `PracticeRoute`（`planToday` / `freePick` / `continueLast` / `retrain`，含 `title` / `subtitle`） | Phase 3 Task 6 | 「练习偏好」分区里的默认路线四选一 |
| `PracticeRoutePreference.route(fromSettings:)` / `.rawValue(for:)` | Phase 8 Task 7 | 同上，字符串与枚举的换算只走它 |
| `CoachSettings` 的七个字段（`recordingEnabled`、`recordingConsentAt`、**`transcriptEnabled`**、`weeklyGoal`、`defaultRoute`、`feedbackTiming`、`part2PrepMode`）与 `CoachSettings.normalized(_:)` | Phase 4 / 5 / 7 / 8 | 设置窗口四个分区正好覆盖这七个字段。**`transcriptEnabled`（跨阶段决策 5，Phase 4 Task 2）归「练习偏好」分区**，见 Task 15 的补注与 Task 16 那张「旧入口去留」表的第四行 |
| `AppState.setTranscriptEnabled(_:)` 与「训练记录」页顶部的逐字稿开关 | Phase 4 Task 9 | **Task 16 删掉这两样**，改由设置窗口的「练习偏好」分区统一承担，训练记录页改成一行说明 + 深链接按钮 |
| `FeedbackTiming` / `Part2PrepMode` | 已在 Core（`Sources/IELTSCoachCore/Model/PracticeMode.swift`） | 「练习偏好」分区里的两项二选一 |
| `DataDirectory.resolve()` / `.root`、`RecordingStore.usage()` | Phase 0–2 / Phase 5 | 「数据与隐私」分区显示位置与占用 |

---

## 前置事实（2026-08-06 在本机实测，不是推断）

这几条决定了本阶段的做法，实测命令与输出都在下面，实现者可以自己复现。

| 事实 | 怎么测的 | 结论 |
|---|---|---|
| **加 Hardened Runtime + entitlements 不改变「指定要求」** | 把已有的 `.app` 复制两份，各自用 `codesign --force --options runtime --entitlements … --sign "IELTS Coach Dev" --identifier com.ielts.speakingcoach` 重签 | 两份的 designated 都仍是 `identifier "com.ielts.speakingcoach" and certificate leaf = H"4bffcd37377a383d9d75460f2c2c9d85174fc82a"`，与加 Hardened Runtime **之前**完全一致 |
| **改了 `Info.plist` 内容，CDHash 确实会变** | 其中一份先 `PlistBuddy -c "Set :CFBundleVersion 999"` 再签 | 两份 CDHash 不同（`5e202846…` / `ee17b4ca…`）。**这条是「两次打包比较不是空转」的依据**——不制造差异的话，两次打出同一个包，比较当然一致 |
| Hardened Runtime 标志确实打上了 | `codesign -dvvv` | `flags=0x10000(runtime)`、`Runtime Version=26.5.0` |
| 签名在 Hardened Runtime 下仍然有效 | `codesign --verify --strict --verbose=2` | `valid on disk` + `satisfies its Designated Requirement` |
| **可执行文件只链接系统库** | `otool -L .build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp` | 全部是 `/usr/lib/*`、`/System/Library/Frameworks/*`、`/usr/lib/swift/*`。**因此不需要 `disable-library-validation`**，Hardened Runtime 默认的库校验不会拦任何东西 |
| **自签名的包会被 Gatekeeper 拒** | `spctl -a -vvv -t exec` | `rejected`、`origin=IELTS Coach Dev`。这是没公证的必然结果，关于页与「如何打开」说明必须如实告诉用户 |
| `notarytool` / `stapler` 本机已有 | `xcrun --find notarytool` / `xcrun --find stapler` | 都在 Xcode 里。**将来缺的只是证书与凭据，不是工具** |

另有两条**不要浪费时间去找**的东西：

- **辅助功能没有对应的 `Info.plist` 用途说明键。** 不存在 `NSAccessibilityUsageDescription` 这种东西，系统不读它，写了也没用。辅助功能是 TCC 里由用户手动勾选的，弹的是系统固定文案的对话框。
- **AX 驱动别的应用不需要任何 entitlement。** 它由 TCC（辅助功能）管，不由 Hardened Runtime 管。**唯一**需要因 Hardened Runtime 而补的 entitlement 是麦克风（`com.apple.security.device.audio-input`）。

---

## File Structure

```
LICENSE                                        新增
packaging/                                     新增目录，必须提交进仓库
├── IELTSCoach.entitlements                    entitlements 定稿
├── expected-designated-requirement.txt         签名基线（打包时逐字比对）
└── open-instructions.txt                       随分发包附上的中文「如何打开」
scripts/
├── build-app.sh                               Modify：Hardened Runtime + entitlements + Info.plist 定稿 + 四项自检
├── make-icon.sh / make-icon.swift              不动（Phase 3 已完成）
├── verify-signature-stability.sh              新增：连打两次，比对 designated
├── package-app.sh                             新增：产出可以直接发给别人的 zip
├── notarize.sh                                新增：公证脚本，默认 dry-run，本期不执行
└── verify-portability.sh                      新增：模拟「换了一台电脑」
Sources/
├── IELTSCoachCore/Storage/
│   ├── DataPortabilityAudit.swift             新增：数据目录可搬迁审计（纯 Foundation）
│   └── DataUsage.swift                        新增（Task 14）：数据目录占用统计（纯 Foundation）
├── IELTSCoachUI/About/
│   ├── AppMetadata.swift                      新增：版本、构建、签名通道
│   ├── DiagnosticsReport.swift                新增：可复制的诊断文本（不含练习内容）
│   ├── AboutViewModel.swift                   新增：关于页的行、致谢、许可
│   └── AboutView.swift                        新增：关于页（独立窗口）
├── IELTSCoachUI/Onboarding/
│   ├── OnboardingFlow.swift                   新增：引导步骤计算（纯逻辑）
│   ├── OnboardingProgressStore.swift          新增：「看过引导没有」存本机 UserDefaults
│   └── WelcomeFlowView.swift                  新增：引导界面
├── IELTSCoachUI/DesignSystem/
│   ├── Palette.swift                          Modify（Task 12）：一套取值 → 两套 + 动态令牌
│   └── ContrastMath.swift                     新增（Task 12）：会合成 alpha 的对比度计算
├── IELTSCoachUI/Settings/
│   ├── WeeklyGoalEditor.swift                 新增（Task 16）：从 WeeklyGoalSheet.swift 搬过来
│   ├── WeeklyGoalSheet.swift                  **删除**（Task 16）：并进设置窗口
│   ├── SettingsSection.swift                  新增（Task 15）：四个分区
│   ├── SettingsNavigator.swift                新增（Task 16）：从别处跳到某个分区
│   ├── CoachSettingsViewModel.swift           新增（Task 15）：设置窗口的读写（可测）
│   └── SettingsWindowView.swift               新增（Task 16）：⌘, 那个窗口本体
├── IELTSCoachUI/Recording/
│   └── RecordingSettingsViewModel.swift       Modify（Task 15）：加 onChange 钩子
├── IELTSCoachUI/Upgrade/
│   ├── Changelog.swift                        新增（Task 17）：版本记录与十阶段进展（手工维护）
│   └── UpgradeView.swift                      新增（Task 17）：「功能升级」页
├── IELTSCoachUI/Feedback/
│   ├── LastErrorLog.swift                     新增（Task 18）：最近一次错误（只记阶段与代号）
│   └── FeedbackView.swift                     新增（Task 18）：「问题反馈」页
├── IELTSCoachUI/Navigation.swift              Modify（Task 17/18）：两项标为已实现
├── IELTSCoachUI/AppState.swift                Modify（Task 15/16）：测试用构造参数；删掉每周目标的旧写入口
├── IELTSCoachUI/Onboarding/PermissionGateView.swift   Modify（Task 13）：修掉写死的 Color.red
├── IELTSCoachUI/RootView.swift                Modify：顶层分支改走引导；接入两页；齿轮按钮改开设置窗口
├── IELTSCoachUI/Today/TodayView.swift         Modify（Task 16）：「改目标」改成跳设置窗口
├── IELTSCoachUI/Plan/PlanView.swift           Modify（Task 16）：撤掉页尾的练习偏好区块
├── IELTSCoachApp/main.swift                   Modify：关于窗口 + 苹果菜单 + 设置窗口 + AppState 提到 App 层
└── coach/
    ├── PortabilityCommand.swift               新增：coach portability
    └── main.swift                             Modify：注册新子命令
Tests/
├── IELTSCoachCoreTests/DataPortabilityAuditTests.swift    新增
├── IELTSCoachCoreTests/DataUsageTests.swift               新增（Task 14）
├── IELTSCoachUITests/AppMetadataTests.swift               新增
├── IELTSCoachUITests/DiagnosticsReportTests.swift         新增；Task 18 追加三条
├── IELTSCoachUITests/AboutViewModelTests.swift            新增
├── IELTSCoachUITests/OnboardingFlowTests.swift            新增
├── IELTSCoachUITests/DesignSystemTests.swift              Modify（Task 12）：对比度那四条并进矩阵
├── IELTSCoachUITests/AppearanceContrastTests.swift        新增（Task 12）：两套外观的对比度矩阵
├── IELTSCoachUITests/CoachSettingsViewModelTests.swift    新增（Task 15）
├── IELTSCoachUITests/ChangelogTests.swift                 新增（Task 17）
├── IELTSCoachUITests/LastErrorLogTests.swift              新增（Task 18）
├── IELTSCoachUITests/NavigationTests.swift                Modify（Task 17/18）：已实现集合 → 十项全齐
└── PackagingTests/                                        新增 test target（不依赖任何产品代码）
    ├── NotarizeScriptTests.swift
    ├── PackagingContractTests.swift                       Task 17 追加一条：版本号与 build-app.sh 一致
    ├── DesignTokenContractTests.swift                     新增（Task 13）：扫源码，禁字面颜色/字号/圆角
    ├── SettingsHomeContractTests.swift                    新增（Task 16）：一个设置只有一个家
    └── FeedbackPrivacyContractTests.swift                 新增（Task 18）：问题反馈页碰不到网络
Package.swift                                  Modify：加 PackagingTests
```

### 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略。** 理由与 Phase 3 计划第 79–86 行完全相同：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来。所以每个 `View` 的任务里写明「必须显示什么、空状态说什么、失败时说什么」，具体怎么摆由实现者定，由设计令牌与 Task 11 的人工验收把关。

**唯一例外是 `Sources/IELTSCoachApp/main.swift`**：它不是布局，是 Scene 与菜单的结构，摆错了关于页根本打不开。所以那一段给完整代码。

若实现者认为某处要求不清楚到无法动手，**应当停下来问，而不是猜**。

---

## Task 1: entitlements 与 Info.plist 定稿，打开 Hardened Runtime

**Files:**
- Create: `packaging/IELTSCoach.entitlements`
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Consumes: `scripts/make-icon.sh`（Phase 3 产出，原样调用）；钥匙串里的证书 `IELTS Coach Dev`
- Produces:
  - 已签名的 `.build/IELTS Speaking Coach.app`，带 `flags=0x10000(runtime)` 与麦克风 entitlement
  - `Info.plist` 里四个供关于页读取的自定义键：`IELTSBuildCommit`、`IELTSBuildDate`、`IELTSSigningIdentity`、`IELTSSignatureChannel`
  - `build-app.sh` 支持两个环境变量：`IELTS_BUILD_NUMBER`（覆盖构建号）、`IELTS_SIGN_IDENTITY` / `IELTS_SIGNATURE_CHANNEL`（供 `notarize.sh` 用 Developer ID 重签时复用同一套组装逻辑）

### entitlements 为什么只有一条

**只加需要的，一条都不多加。** 每多一条 entitlement 就多削弱一分 Hardened Runtime，而 Hardened Runtime 是公证的硬性前提。逐条说明为什么其余的都不加：

| entitlement | 加不加 | 理由 |
|---|---|---|
| `com.apple.security.device.audio-input` | **加** | Phase 5 的麦克风录音。Hardened Runtime 打开后，没有这条的 App 一碰麦克风就被系统直接拒掉，用户打开「保存我的回答录音」时会失败，而且失败得很难看懂 |
| `com.apple.security.app-sandbox` | **不加** | 沙盒会切断辅助功能驱动别的应用、也切断读用户随手挑的题库文件。产品直接不可用。**公证不要求沙盒**，只有 Mac App Store 要求 |
| `com.apple.security.cs.disable-library-validation` | **不加** | 实测 `otool -L` 显示可执行文件只链接 `/usr/lib`、`/System/Library/Frameworks`、`/usr/lib/swift`，全是系统签名的库，库校验不会拦任何东西。加了等于白白削弱。**遇到 Hardened Runtime 报错时最容易被顺手粘上来的就是这一条，Task 9 有测试专门拦它** |
| `com.apple.security.cs.allow-jit`、`allow-unsigned-executable-memory`、`disable-executable-page-protection` | **不加** | SwiftUI 应用不 JIT、不生成可执行内存 |
| `com.apple.security.automation.apple-events` | **不加** | 本项目实测排除了 AppleScript 通道（设计文档 2.2：新目标的 AppleScript 字典是继承来的空壳），全部走 AX API，而 AX 不经 Apple Events。**将来若真要发 Apple Event，必须同时加这条 entitlement 与 `NSAppleEventsUsageDescription`，缺一个都会在 Hardened Runtime 下被拒** |

- [ ] **Step 1: 写 entitlements 文件**

`packaging/IELTSCoach.entitlements`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!--
      唯一一条 entitlement：麦克风。
      Hardened Runtime 打开后，没有它 App 一碰麦克风就会被系统直接拒掉
      （Phase 5 的「保存我的回答录音」开关会失败，且失败信息很难看懂）。

      为什么没有别的：
      · 不开 App Sandbox —— 沙盒会切断辅助功能驱动 ChatGPT、也切断读任意题库文件，
        产品直接不可用。公证不要求沙盒，只有 Mac App Store 要求。
      · 不加 disable-library-validation —— 实测 otool -L 显示只链接系统库，
        库校验不会拦任何东西，加了只是白白削弱。
      · 不加 apple-events —— 本项目全部走 AX API，不发 Apple Event（设计文档 2.2）。
      · 辅助功能不需要任何 entitlement，它由 TCC 管，不由 Hardened Runtime 管。
    -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

Run: `plutil -lint packaging/IELTSCoach.entitlements`
Expected: `packaging/IELTSCoach.entitlements: OK`

- [ ] **Step 2: 重写 `scripts/build-app.sh`**

完整替换原文件：

```bash
#!/bin/bash
set -euo pipefail

# 组装 .app 包并签名。
#
# 为什么必须用固定的签名身份而不是 ad-hoc（codesign -s -）：
# TCC（辅助功能授权）记的是签名的「指定要求」。ad-hoc 绑的是二进制指纹 cdhash，
# 每次编译都变，用户得反复去系统设置重新勾选。固定证书绑「标识 + 证书」，
# 编译多少次都不变。
#
# 组装完先自检两件事（Phase 5 Task 10 / Phase 9 Task 11 留下来的，重写脚本时勿丢）：
#   · Info.plist 里有 NSMicrophoneUsageDescription
#   · Info.plist 里有 CFBundleURLTypes 且 scheme 是 ieltscoach
#
# 签完之后立刻自检四件事，任何一件不对都直接退出非零：
#   1. 签名本身有效（codesign --verify --strict）
#   2. 带了 Hardened Runtime 标志
#   3. 带了麦克风 entitlement（没有它，Hardened Runtime 下录音会被系统拒掉）
#   4. 「指定要求」与 packaging/expected-designated-requirement.txt 逐字一致
# 第 4 条是本产品最恼人失败模式的守门员：它一变，用户的辅助功能授权就没了，
# 而且不会有任何报错，只是「今天怎么又不能自动开练了」。

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
APP_VERSION="1.0.0"

# 可被环境变量覆盖，供 notarize.sh 用 Developer ID 重签时复用同一套组装逻辑。
SIGN_IDENTITY="${IELTS_SIGN_IDENTITY:-IELTS Coach Dev}"
SIGNATURE_CHANNEL="${IELTS_SIGNATURE_CHANNEL:-self-signed}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/packaging/IELTSCoach.entitlements"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "❌ 找不到 entitlements 文件：$ENTITLEMENTS"
    echo "   发生了什么：packaging/ 目录不完整。"
    echo "   下一步：确认这个文件在仓库里并已提交；缺了它，签出来的包在 Hardened Runtime 下用不了麦克风。"
    exit 1
fi

# 构建号默认取 git 提交数（单调递增）。
# IELTS_BUILD_NUMBER 存在时优先 —— verify-signature-stability.sh 靠它制造
# 「两次打包内容确实不同」的条件，否则那个比较是空转的。
if [[ -n "${IELTS_BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$IELTS_BUILD_NUMBER"
else
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
fi
BUILD_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "▶︎ 编译…"
swift build -c release --product IELTSCoachApp

echo "▶︎ 组装 .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/IELTSCoachApp" "$APP/Contents/MacOS/IELTSCoachApp"

echo "▶︎ 生成图标…"
"$ROOT/scripts/make-icon.sh"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 注意：没有 NSAccessibilityUsageDescription 这种键，系统不读它。
# 辅助功能是 TCC 里由用户手动勾选的，弹的是系统固定文案，不是 App 能自定义的。
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>IELTSCoachApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 IELTS Speaking Coach 作者。与 OpenAI、British Council、IDP、Cambridge Assessment English 均无隶属关系。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>开启「保存我的回答录音」后，用于录下你练习时的回答，便于回听。录音只存在本机，可随时删除。</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array><string>ieltscoach</string></array>
        </dict>
    </array>
    <key>IELTSBuildCommit</key><string>$BUILD_COMMIT</string>
    <key>IELTSBuildDate</key><string>$BUILD_DATE</string>
    <key>IELTSSigningIdentity</key><string>$SIGN_IDENTITY</string>
    <key>IELTSSignatureChannel</key><string>$SIGNATURE_CHANNEL</string>
</dict>
</plist>
PLIST

# 立即校验生成的 plist 是否合法。少一个闭合标签就会让 App 起不来，
# 而那时的报错往往含糊到看不出是 plist 的问题。
plutil -lint "$APP/Contents/Info.plist" >/dev/null || {
    echo "❌ 生成的 Info.plist 不是合法 plist。"
    echo "   下一步：检查 build-app.sh 里那段 heredoc 的标签是否闭合。"
    exit 1
}

# ↓ 这两条来自 Phase 5 Task 10 与 Phase 9 Task 11。本任务整体重写了这个脚本，
#   一不小心就会把它们丢掉——而 plutil -lint 只管 plist 合不合法，管不了某个键在不在。
#   丢了不会有任何报错，只会在真机上变成两种极难排查的症状。

# 缺 NSMicrophoneUsageDescription：App 第一次申请麦克风权限时直接闪退，
# 崩溃报告里看不出跟这个键有任何关系。
MIC_USAGE="$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$MIC_USAGE" ]; then
    echo "❌ Info.plist 里缺少 NSMicrophoneUsageDescription。"
    echo "   后果：App 一申请麦克风权限就会闪退，且崩溃信息看不出原因。"
    echo "   下一步：在上面那段 Info.plist heredoc 里补回这个键，"
    echo "   内容要用中文说明「录音用来做什么、存在哪里、能不能删」。"
    exit 1
fi

# 缺 CFBundleURLTypes：LaunchServices 不知道谁该处理 ieltscoach://，
# MCP 的 open_dashboard 会永远打不开窗口，而 NSWorkspace.open 只是返回 false，一句话都不说。
REGISTERED_SCHEME="$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw \
    "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$REGISTERED_SCHEME" != "ieltscoach" ]; then
    echo "❌ Info.plist 里没有正确注册 ieltscoach:// 这个 URL scheme（读到的是「$REGISTERED_SCHEME」）。"
    echo "   后果：MCP 的 open_dashboard 会永远打不开窗口，而且不报错。"
    echo "   下一步：检查上面 Info.plist heredoc 里 CFBundleURLTypes 那一段是否完整。"
    exit 1
fi

echo "▶︎ 签名（Hardened Runtime + entitlements）…"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "❌ 找不到签名证书「$SIGN_IDENTITY」。"
    echo "   下一步：按 docs/superpowers/plans/2026-08-05-phase3-gui-shell.md「前置条件」一节重新创建，"
    echo "   否则每次编译后辅助功能授权都会失效，需反复去系统设置重新勾选。"
    exit 1
fi

# 不加 --deep：Apple 已不建议，且本包里没有嵌套代码，加了只会掩盖问题。
# --timestamp=none：本地打包不联网。公证路径由 notarize.sh 用 --timestamp 重签。
codesign --force \
         --sign "$SIGN_IDENTITY" \
         --identifier "$BUNDLE_ID" \
         --options runtime \
         --entitlements "$ENTITLEMENTS" \
         --timestamp=none \
         "$APP"

echo "▶︎ 自检…"

if ! codesign --verify --strict --verbose=2 "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
    echo "❌ 签名校验没通过。"
    echo "   下一步：跑 codesign --verify --strict --verbose=4 \"$APP\" 看具体是哪一项不满足。"
    exit 1
fi

if ! codesign -dvvv "$APP" 2>&1 | grep -qE 'flags=0x[0-9a-f]+\(.*runtime'; then
    echo "❌ 签出来的包没有 Hardened Runtime 标志。"
    echo "   发生了什么：codesign 的 --options runtime 没生效。"
    echo "   下一步：确认上面那条 codesign 命令里的 --options runtime 还在，然后重打。"
    exit 1
fi

if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "com.apple.security.device.audio-input"; then
    echo "❌ 签名里没带上麦克风 entitlement。"
    echo "   发生了什么：Hardened Runtime 打开后，没有这条 entitlement 的 App 一碰麦克风就会被系统直接拒掉，"
    echo "   用户开「保存我的回答录音」时会失败，而且失败得很难看懂。"
    echo "   下一步：检查 $ENTITLEMENTS 的内容，以及签名命令里的 --entitlements 参数。"
    exit 1
fi

ACTUAL_DR="$(codesign -d -r- "$APP" 2>&1 | grep '^designated' || true)"
if [[ -z "$ACTUAL_DR" ]]; then
    echo "❌ 读不出签名的「指定要求」。"
    echo "   下一步：跑 codesign -d -r- \"$APP\" 看它到底输出了什么。"
    exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
    printf '%s\n' "$ACTUAL_DR" > "$BASELINE"
    echo "ℹ️  首次记录签名基线到 $BASELINE"
    echo "   下一步：把这个文件提交进仓库。以后每次打包都会跟它逐字比对，"
    echo "   一旦变了就说明辅助功能授权会失效，脚本会当场拦下来。"
elif [[ "$ACTUAL_DR" != "$(cat "$BASELINE")" ]]; then
    echo "❌ 签名的「指定要求」和仓库里记录的基线不一致。"
    echo "   基线：$(cat "$BASELINE")"
    echo "   本次：$ACTUAL_DR"
    echo "   发生了什么：系统会把这次打出来的 App 当成另一个程序，"
    echo "   之前授予的辅助功能权限会失效，用户得回系统设置重新勾一次。"
    echo "   下一步（二选一）："
    echo "     A. 你不是故意换证书：确认 login 钥匙串里的「$SIGN_IDENTITY」证书还在、没被重新生成，修好后重打。"
    echo "     B. 你是故意换证书（例如换成 Developer ID 准备公证）：把新值写进"
    echo "        $BASELINE 并提交，然后到 系统设置 › 隐私与安全性 › 辅助功能 里"
    echo "        删掉旧条目、重新勾选一次。"
    exit 1
fi

echo "✅ 已生成 $APP"
echo "   版本 $APP_VERSION（构建 $BUILD_NUMBER，提交 $BUILD_COMMIT，通道 $SIGNATURE_CHANNEL）"
echo "   $ACTUAL_DR"
```

- [ ] **Step 3: 打一次包，确认自检全过**

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: 走完组装期两项 + 签名后四项自检，最后打印 `✅ 已生成 …` 与
`designated => identifier "com.ielts.speakingcoach" and certificate leaf = H"…"`。
并且**首次运行会生成 `packaging/expected-designated-requirement.txt`**，内容就是那一行。

Run: `codesign -dvvv ".build/IELTS Speaking Coach.app" 2>&1 | grep -E "flags|Runtime Version"`
Expected: 含 `flags=0x10000(runtime)` 与 `Runtime Version=`

Run: `codesign -d --entitlements - --xml ".build/IELTS Speaking Coach.app" 2>/dev/null`
Expected: XML 里有 `com.apple.security.device.audio-input`

- [ ] **Step 4: 确认 App 在 Hardened Runtime 下真的还能驱动 ChatGPT**

Run: `open ".build/IELTS Speaking Coach.app"`
Expected: App 打开后显示「环境就绪」（即 `preflight()` 成功找到 ChatGPT、辅助功能权限有效、惰性 AX 树能唤醒）。

**这一步不产生任何 ChatGPT 对话**——`preflight()` 只做检查，不新建会话、不发消息、不启动语音。

若这里变成「没有辅助功能权限」：先看 Step 5 的判断，不要急着重新授权。

- [ ] **Step 5: 突变验证（改脚本，看自检会不会红）**

**突变 A —— 摘掉 Hardened Runtime：**
把 `codesign` 命令里的 `--options runtime \` 整行删掉，重跑 `./scripts/build-app.sh`。
Expected: 停在 `❌ 签出来的包没有 Hardened Runtime 标志。`，退出码非零。改回后重跑必须通过。

**突变 B —— 摘掉 entitlements：**
把 `--entitlements "$ENTITLEMENTS" \` 整行删掉，重跑。
Expected: 停在 `❌ 签名里没带上麦克风 entitlement。`，退出码非零。改回后重跑必须通过。

**把两次的实际输出写进报告。** 这两条守的是「自检不是摆设」——一个只会打印 ✅ 的自检等于没有自检，而这类空转在本项目已经消灭过 15 处。

- [ ] **Step 6: 提交**

```bash
git add packaging/IELTSCoach.entitlements packaging/expected-designated-requirement.txt scripts/build-app.sh
git commit -m "feat(packaging): Hardened Runtime、entitlements 与 Info.plist 定稿"
```

---

## Task 2: 签名稳定性回归脚本

**Files:**
- Create: `scripts/verify-signature-stability.sh`

**Interfaces:**
- Consumes: `scripts/build-app.sh`（认 `IELTS_BUILD_NUMBER`）、`packaging/expected-designated-requirement.txt`
- Produces: `scripts/verify-signature-stability.sh`，退出 0 表示「连打两次包，designated 完全一致，且与基线相符，且这次比较不是空转的」

**这是本阶段最要紧的一条。** macOS 的 TCC（辅助功能授权）记的就是「指定要求」这个字符串。它一变，系统把新包当成另一个程序，用户之前勾的权限当场失效。这个失败不报错、不崩溃，用户的感受只是「今天怎么又不能自动开练了」——所以必须由脚本每次替他检查。

**为什么两次要用不同的构建号：** 不制造差异的话，两次打出来的是同一个包，designated 当然一致，等于什么都没验。脚本因此额外断言「两次的 CDHash 必须不同」——这一条不成立时，比较本身是空转的，脚本要报错。

- [ ] **Step 1: 写脚本**

`scripts/verify-signature-stability.sh`：

```bash
#!/bin/bash
set -euo pipefail

# 连打两次包，验证签名的「指定要求」完全一致。
#
# 为什么这是本阶段最要紧的一条：macOS 的 TCC（辅助功能授权）记的就是这个字符串。
# 它一变，系统就把新包当成另一个程序，用户之前勾的辅助功能权限当场失效，
# 得回系统设置重新勾一次。对这个产品来说这是最恼人的失败模式——
# 它不报错、不崩溃，只是「今天怎么又不能自动开练了」。
#
# 两次打包故意用不同的构建号，让包的内容确实不同。
# 不这么做的话两次打出一模一样的包，比较当然一致，等于什么都没验。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IELTS Speaking Coach"
APP="$ROOT/.build/$APP_NAME.app"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

read_designated() { codesign -d -r- "$APP" 2>&1 | grep '^designated' || true; }
read_cdhash()     { codesign -dvvv  "$APP" 2>&1 | grep '^CDHash=' | head -1 || true; }

echo "▶︎ 第一次打包（构建号 90001）…"
IELTS_BUILD_NUMBER=90001 "$ROOT/scripts/build-app.sh" >/dev/null
DR1="$(read_designated)"; HASH1="$(read_cdhash)"

echo "▶︎ 第二次打包（构建号 90002，内容与第一次确实不同）…"
IELTS_BUILD_NUMBER=90002 "$ROOT/scripts/build-app.sh" >/dev/null
DR2="$(read_designated)"; HASH2="$(read_cdhash)"

FAILED=0

if [[ -z "$DR1" || -z "$DR2" ]]; then
    echo "❌ 有一次没读出「指定要求」。"
    echo "   下一步：单独跑 codesign -d -r- \"$APP\" 看它输出了什么。"
    FAILED=1
fi

if [[ "$HASH1" == "$HASH2" ]]; then
    echo "❌ 两次打包的 CDHash 一模一样（$HASH1）。"
    echo "   发生了什么：两次打出来的是同一个包，这次比较什么都没验证到。"
    echo "   下一步：确认 build-app.sh 真的把 IELTS_BUILD_NUMBER 写进了 Info.plist 的 CFBundleVersion。"
    FAILED=1
fi

if [[ "$DR1" != "$DR2" ]]; then
    echo "❌ 两次打包的「指定要求」不一致 —— 这正是要拦住的事。"
    echo "   第一次：$DR1"
    echo "   第二次：$DR2"
    echo "   发生了什么：签名不稳定，最常见的原因是用了 ad-hoc 签名（codesign -s -）。"
    echo "   后果：每次重新打包，用户的辅助功能授权都会失效，要回系统设置重新勾。"
    echo "   下一步：确认 build-app.sh 用的是固定证书「IELTS Coach Dev」，不是 -。"
    FAILED=1
fi

if [[ -f "$BASELINE" && "$DR2" != "$(cat "$BASELINE")" ]]; then
    echo "❌ 「指定要求」与仓库里记录的基线不一致。"
    echo "   基线：$(cat "$BASELINE")"
    echo "   本次：$DR2"
    echo "   下一步：见 build-app.sh 里同名检查打印的两条处理办法（A 修证书 / B 更新基线并重新授权）。"
    FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then exit 1; fi

echo "✅ 连打两次，「指定要求」完全一致，且与基线相符："
echo "   $DR2"
echo "   两次 CDHash 分别是 $HASH1 / $HASH2（不同，说明这次比较是有效的）"
```

- [ ] **Step 2: 跑一次，确认通过**

Run: `chmod +x scripts/verify-signature-stability.sh && ./scripts/verify-signature-stability.sh`
Expected: 打印 `✅ 连打两次，「指定要求」完全一致…`，退出 0。

- [ ] **Step 3: 突变验证（两条，都必须做）**

**突变 A —— 把签名换成 ad-hoc：**
把 `scripts/build-app.sh` 里的 `--sign "$SIGN_IDENTITY" \` 改成 `--sign - \`，重跑 `./scripts/verify-signature-stability.sh`。
Expected: designated 变成 `cdhash H"…"` 形式且两次互不相同，脚本停在 `❌ 两次打包的「指定要求」不一致`，退出非零。改回后重跑必须通过。

**这条守的就是本产品最恼人的失败模式**：ad-hoc 签名每次编译都变，用户每次都要回系统设置重新勾辅助功能。

**突变 B —— 让两次打包变成同一个包：**
把 `verify-signature-stability.sh` 里第二次的 `IELTS_BUILD_NUMBER=90002` 改成 `90001`，重跑。
Expected: 停在 `❌ 两次打包的 CDHash 一模一样`，退出非零。改回后重跑必须通过。

**这条守的是「比较本身不能是空转的」**——两次打出一模一样的包，designated 当然一致，那样的绿灯毫无意义。

把两次突变的实际输出写进报告。

- [ ] **Step 4: 提交**

```bash
git add scripts/verify-signature-stability.sh
git commit -m "feat(packaging): 签名指定要求的稳定性回归脚本"
```

---

## Task 3: 版本与签名通道（AppMetadata）

**Files:**
- Create: `Sources/IELTSCoachUI/About/AppMetadata.swift`
- Create: `Tests/IELTSCoachUITests/AppMetadataTests.swift`

**Interfaces:**
- Consumes: `Bundle.main.infoDictionary`（生产环境）；Task 1 写进 `Info.plist` 的 `IELTSBuildCommit` / `IELTSBuildDate` / `IELTSSigningIdentity` / `IELTSSignatureChannel`
- Produces:
  - `enum SignatureChannel: String, Equatable, Sendable, CaseIterable { case selfSigned = "self-signed", developerID = "developer-id", unknown }`
    - `SignatureChannel.from(_ raw: String?) -> SignatureChannel`
    - `var title: String` / `var explanation: String` / `var nextStep: String`
  - `struct AppMetadata: Equatable, Sendable`，字段 `displayName`、`bundleIdentifier`、`shortVersion`、`buildNumber`、`buildCommit`、`buildDate`、`signingIdentity`、`channel`
    - `static let unknownValue = "未知（开发运行）"`
    - `static func from(infoDictionary: [String: Any]?) -> AppMetadata`
    - `static var current: AppMetadata`
    - `var versionLine: String`

**为什么要单独拆一个类型：** `swift run IELTSCoachApp` 直接跑时**没有 App bundle**，`Bundle.main.infoDictionary` 里什么都没有。关于页在这种情况下必须仍然显示得像样，而不是一片空白或者 `Optional(nil)`。这段「缺什么就说缺什么」的逻辑是纯函数，可以完整测试；`View` 只负责摆。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/AppMetadataTests.swift`：

```swift
import XCTest
@testable import IELTSCoachUI

final class AppMetadataTests: XCTestCase {
    private func fullDictionary() -> [String: Any] {
        [
            "CFBundleDisplayName": "IELTS Speaking Coach",
            "CFBundleIdentifier": "com.ielts.speakingcoach",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "42",
            "IELTSBuildCommit": "a1b2c3d",
            "IELTSBuildDate": "2026-08-06T09:00:00Z",
            "IELTSSigningIdentity": "IELTS Coach Dev",
            "IELTSSignatureChannel": "self-signed"
        ]
    }

    func testReadsEveryFieldFromACompleteDictionary() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.displayName, "IELTS Speaking Coach")
        XCTAssertEqual(metadata.bundleIdentifier, "com.ielts.speakingcoach")
        XCTAssertEqual(metadata.shortVersion, "1.0.0")
        XCTAssertEqual(metadata.buildNumber, "42")
        XCTAssertEqual(metadata.buildCommit, "a1b2c3d")
        XCTAssertEqual(metadata.buildDate, "2026-08-06T09:00:00Z")
        XCTAssertEqual(metadata.signingIdentity, "IELTS Coach Dev")
        XCTAssertEqual(metadata.channel, .selfSigned)
    }

    func testMissingDictionaryProducesReadableChineseInsteadOfBlanks() {
        // swift run 直接跑时没有 App bundle，infoDictionary 是 nil。
        // 关于页在这种情况下不能出现空白行、也不能露出 "nil" / "Optional"。
        let metadata = AppMetadata.from(infoDictionary: nil)
        for value in [metadata.displayName, metadata.bundleIdentifier, metadata.shortVersion,
                      metadata.buildNumber, metadata.buildCommit, metadata.buildDate,
                      metadata.signingIdentity] {
            XCTAssertFalse(value.isEmpty, "缺字段时不能返回空串")
            XCTAssertFalse(value.contains("nil"), "不能把 nil 直接显示给用户：\(value)")
            XCTAssertFalse(value.contains("Optional"), "不能把 Optional 直接显示给用户：\(value)")
        }
        XCTAssertEqual(metadata.channel, .unknown)
    }

    func testOnlyTheAbsentKeysFallBack() {
        var dictionary = fullDictionary()
        dictionary.removeValue(forKey: "IELTSBuildCommit")
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildCommit, AppMetadata.unknownValue)
        XCTAssertEqual(metadata.shortVersion, "1.0.0", "别的字段不该被连坐")
    }

    func testEmptyStringCountsAsMissing() {
        // plist 里把值写成空串，跟没写是一回事：界面上都是空白一行。
        var dictionary = fullDictionary()
        dictionary["IELTSSigningIdentity"] = "   "
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.signingIdentity, AppMetadata.unknownValue)
    }

    func testNonStringValuesAreStillDisplayable() {
        // plist 里 CFBundleVersion 被写成 <integer> 是常见事故，不能因此变成「未知」。
        var dictionary = fullDictionary()
        dictionary["CFBundleVersion"] = 99
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildNumber, "99")
    }

    func testVersionLineCombinesVersionAndBuild() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.versionLine, "1.0.0（构建 42）")
    }

    func testUnknownChannelWhenValueIsGarbage() {
        var dictionary = fullDictionary()
        dictionary["IELTSSignatureChannel"] = "随便写的"
        XCTAssertEqual(AppMetadata.from(infoDictionary: dictionary).channel, .unknown)
    }

    func testEverySignatureChannelExplainsItselfAndGivesANextStep() {
        // 三种通道对用户的含义完全不同（能不能直接双击打开）。
        // 少写一种，用户在别人的电脑上被 Gatekeeper 拦下时就没有任何线索。
        for channel in SignatureChannel.allCases {
            XCTAssertFalse(channel.title.isEmpty, "\(channel) 没有标题")
            XCTAssertFalse(channel.explanation.isEmpty, "\(channel) 没说发生了什么")
            XCTAssertFalse(channel.nextStep.isEmpty, "\(channel) 没说下一步做什么")
        }
    }

    func testSelfSignedTellsTheRecipientHowToGetPastGatekeeper() {
        // 实测：自签名未公证的包 spctl 判定为 rejected。
        // 对方双击打不开时必须能从这句话里知道怎么办。
        let nextStep = SignatureChannel.selfSigned.nextStep
        XCTAssertTrue(nextStep.contains("系统设置"), "没告诉用户去哪儿：\(nextStep)")
        XCTAssertTrue(nextStep.contains("仍要打开"), "没告诉用户点什么：\(nextStep)")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AppMetadataTests`
Expected: 编译失败 —— `AppMetadata`、`SignatureChannel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/About/AppMetadata.swift`：

```swift
import Foundation

/// 这份 App 是怎么签的，以及这对拿到它的人意味着什么。
/// 取值由 `scripts/build-app.sh` 写进 Info.plist 的 `IELTSSignatureChannel`。
public enum SignatureChannel: String, Equatable, Sendable, CaseIterable {
    case selfSigned = "self-signed"
    case developerID = "developer-id"
    case unknown

    public static func from(_ raw: String?) -> SignatureChannel {
        guard let raw, let channel = SignatureChannel(rawValue: raw) else { return .unknown }
        return channel
    }

    public var title: String {
        switch self {
        case .selfSigned: return "自签名（未经 Apple 公证）"
        case .developerID: return "Developer ID 签名，已通过 Apple 公证"
        case .unknown: return "无签名信息（从源码直接运行）"
        }
    }

    /// 发生了什么。
    public var explanation: String {
        switch self {
        case .selfSigned:
            return "这份 App 用作者本机生成的证书签名，没有购买 Apple 开发者账号做公证。"
                + "Apple 对所有未公证的 App 都会拦一下，这与它本身是否安全无关。"
        case .developerID:
            return "这份 App 用 Apple 签发的 Developer ID 证书签名，并且通过了 Apple 的公证。"
        case .unknown:
            return "现在跑的是从源码直接启动的开发版本，没有打包成 .app，因此读不到签名信息。"
        }
    }

    /// 下一步做什么。
    public var nextStep: String {
        switch self {
        case .selfSigned:
            return "拷给别人时，对方第一次打开会被系统拦下。"
                + "让他打开 系统设置 › 隐私与安全性，在「安全性」一节找到被阻止的这一条，点「仍要打开」，再确认一次。"
        case .developerID:
            return "对方双击即可打开，不会被系统拦下。"
        case .unknown:
            return "要得到可以拷给别人的版本，运行 scripts/package-app.sh。"
        }
    }
}

/// 关于页与诊断信息要显示的「这是哪一份 App」。
///
/// **为什么每个字段都要有兜底：** `swift run IELTSCoachApp` 直接跑时没有 App bundle，
/// `Bundle.main.infoDictionary` 是 nil。关于页这时不能变成一片空白 ——
/// 空白页会让用户以为程序坏了（DESIGN-SYSTEM.md 第 4 节的原则，对关于页同样成立）。
public struct AppMetadata: Equatable, Sendable {
    public static let unknownValue = "未知（开发运行）"

    public let displayName: String
    public let bundleIdentifier: String
    public let shortVersion: String
    public let buildNumber: String
    public let buildCommit: String
    public let buildDate: String
    public let signingIdentity: String
    public let channel: SignatureChannel

    public init(displayName: String, bundleIdentifier: String, shortVersion: String,
                buildNumber: String, buildCommit: String, buildDate: String,
                signingIdentity: String, channel: SignatureChannel) {
        self.displayName = displayName; self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion; self.buildNumber = buildNumber
        self.buildCommit = buildCommit; self.buildDate = buildDate
        self.signingIdentity = signingIdentity; self.channel = channel
    }

    public static func from(infoDictionary: [String: Any]?) -> AppMetadata {
        func value(_ key: String) -> String {
            guard let raw = infoDictionary?[key] else { return unknownValue }
            // String(describing:) 兼顾 plist 里被写成 <integer> 的值（常见事故），
            // 也保证 String 原样返回。
            let text = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? unknownValue : text
        }
        return AppMetadata(
            displayName: value("CFBundleDisplayName"),
            bundleIdentifier: value("CFBundleIdentifier"),
            shortVersion: value("CFBundleShortVersionString"),
            buildNumber: value("CFBundleVersion"),
            buildCommit: value("IELTSBuildCommit"),
            buildDate: value("IELTSBuildDate"),
            signingIdentity: value("IELTSSigningIdentity"),
            channel: SignatureChannel.from(infoDictionary?["IELTSSignatureChannel"] as? String))
    }

    public static var current: AppMetadata { from(infoDictionary: Bundle.main.infoDictionary) }

    public var versionLine: String { "\(shortVersion)（构建 \(buildNumber)）" }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AppMetadataTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证**

把 `from(infoDictionary:)` 里的
`return text.isEmpty ? unknownValue : text`
改成
`return text`
重跑：`testEmptyStringCountsAsMissing` 必须变红。改回后确认全绿，把两次输出写进报告。

**这条守的是「界面上出现一行只有标签、没有内容的空白」**——用户看到那种行不会觉得「这个字段没填」，只会觉得「这软件坏了」。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/About/AppMetadata.swift Tests/IELTSCoachUITests/AppMetadataTests.swift
git commit -m "feat(ui): 版本与签名通道信息"
```

---

## Task 4: 数据目录可搬迁审计 + `coach portability`

**Files:**
- Create: `Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift`
- Create: `Sources/coach/PortabilityCommand.swift`
- Modify: `Sources/coach/main.swift`
- Create: `Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`sessions: [PracticeSession]`、`questionSources: [QuestionSource]`）、`PracticeSession.reportPath` / `.recordingPath`、`QuestionSource.sourceUrl`、`DataDirectory`（`root`、`stateFile`、`reportsDirectory`、`recordingsDirectory`）、`StateStore.load()`
- Produces:
  - `struct PortabilityFinding: Equatable, Sendable, Identifiable`
    - `var id: String { location }`、`let location: String`、`let value: String`、`let problem: String`、`let nextStep: String`
    - `init(location:value:problem:nextStep:)`
    - `var message: String`
  - `enum DataPortabilityAudit`
    - `static func audit(state: CoachState) -> [PortabilityFinding]`
    - `static func audit(state: CoachState, directory: DataDirectory, fileManager: FileManager = .default) -> [PortabilityFinding]`
  - 命令行 `coach portability`

**这一条兑现成品标准第 10 条。** 数据目录能不能整个拷到另一台电脑接着用，取决于一件事：**里面存的路径是不是全都相对于数据目录本身**。`PracticeSession.reportPath` 的注释写着 `reports/<id>.json`，但没有任何东西在强制它——某个阶段顺手写成 `URL.path` 就会变成绝对路径，而那时**什么都不会报错**，只有换机器的那天才会发现历史复盘全打不开。这正是本项目最危险的那类失败：静默的、要到很久以后才暴露的。

**为什么放在 Core：** 它只依赖 Foundation（`FileManager` 属于 Foundation），可以在没有界面、没有 ChatGPT 的环境里完整测试；命令行与关于页共用同一份判断。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class DataPortabilityAuditTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "portability-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    // MARK: - 造数据

    private func session(_ id: String, report: String, recording: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                        goal: "", transcript: [], reportPath: report, recordingPath: recording)
    }

    private func state(_ sessions: [PracticeSession],
                       sources: [QuestionSource] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.questionSources = sources
        return value
    }

    private func writeFile(_ relativePath: String) throws {
        let url = directory.root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    // MARK: - 干净的数据目录

    func testRelativePathsWithExistingFilesProduceNoFindings() throws {
        try writeFile("reports/s1.json")
        try writeFile("recordings/s1.m4a")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
    }

    func testEmptyPathsAreNotFindings() throws {
        // 练习还没生成复盘、或者没开录音时，这两个字段本来就是空的。
        // 把它当成错误会让用户每次打开都看到一屏红字，最后学会忽略所有告警 ——
        // 那时真正的问题也一起被忽略了。
        let value = state([session("s1", report: "", recording: "")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty)
    }

    // MARK: - 不可搬迁的写法

    func testAbsoluteReportPathIsReportedWithItsExactLocation() {
        let value = state([
            session("s1", report: "reports/s1.json"),
            session("s2", report: "/Users/someone/Library/Application Support/IELTS Speaking Coach/reports/s2.json")
        ])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].location, "sessions[1].reportPath")
        XCTAssertTrue(findings[0].message.contains("下一步"), "每条问题都必须说下一步做什么")
    }

    func testTildePathIsReported() {
        let value = state([session("s1", report: "~/Documents/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testFileURLIsReported() {
        let value = state([session("s1", report: "file:///tmp/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testPathEscapingTheDataDirectoryIsReported() {
        let value = state([session("s1", report: "../elsewhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testAbsoluteRecordingPathIsReported() {
        let value = state([session("s1", report: "reports/s1.json",
                                   recording: "/Users/someone/Music/s1.m4a")])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].recordingPath"])
    }

    func testLocalQuestionSourceURLIsReportedButHTTPSIsFine() {
        let local = QuestionSource(title: "季度题库", sourceUrl: "/Users/someone/Downloads/题库.pdf",
                                   importedAt: "2026-08-06T00:00:00Z",
                                   importLevel: "full-question", questionCount: 10)
        let remote = QuestionSource(title: "线上题库", sourceUrl: "https://example.com/bank.json",
                                    importedAt: "2026-08-06T00:00:00Z",
                                    importLevel: "full-question", questionCount: 10)
        let findings = DataPortabilityAudit.audit(state: state([], sources: [local, remote]))
        XCTAssertEqual(findings.map(\.location), ["questionSources[0].sourceUrl"],
                       "https 链接换机器照样打得开，不该报；本机文件路径才是问题")
    }

    // MARK: - 文件到底在不在

    func testMissingReportFileIsReportedByTheDirectoryAudit() {
        // 路径写法没问题，但文件没跟着拷过来 —— 换机器后点开历史复盘会是一片空白。
        let value = state([session("s1", report: "reports/s1.json")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty,
                      "只看 state 时看不出文件在不在，这一层不该报")
        let findings = DataPortabilityAudit.audit(state: value, directory: directory)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].reportPath"])
        XCTAssertTrue(findings[0].problem.contains("找不到"), "要说清是文件不见了，不是路径写错了")
    }

    func testMissingRecordingFileIsReportedByTheDirectoryAudit() throws {
        try writeFile("reports/s1.json")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory)
                        .map(\.location), ["sessions[0].recordingPath"])
    }

    func testAbsolutePathIsNotAlsoReportedAsMissing() {
        // 同一个字段只能报一次，否则用户会以为有两个不同的问题要修。
        let value = state([session("s1", report: "/tmp/nowhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory).count, 1)
    }

    // MARK: - 报全，而不是只报第一条

    func testEveryProblemIsReportedNotJustTheFirst() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "~/b.m4a"),
            session("s2", report: "file:///c.json")
        ])
        XCTAssertEqual(Set(DataPortabilityAudit.audit(state: value).map(\.location)),
                       ["sessions[0].reportPath", "sessions[0].recordingPath", "sessions[1].reportPath"])
    }

    func testFindingIDsAreUnique() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "/abs/b.m4a"),
            session("s2", report: "/abs/c.json")
        ])
        let ids = DataPortabilityAudit.audit(state: value).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "列表渲染要用 id，重复会错乱")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DataPortabilityAuditTests`
Expected: 编译失败 —— `DataPortabilityAudit`、`PortabilityFinding` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift`：

```swift
import Foundation

/// 一条「换台电脑就会断」的问题。
public struct PortabilityFinding: Equatable, Sendable, Identifiable {
    /// 位置即唯一键：同一个字段只报一次。
    public var id: String { location }
    /// 精确到字段，例如 "sessions[3].reportPath"。含糊的位置等于没报。
    public let location: String
    public let value: String
    /// 发生了什么。
    public let problem: String
    /// 下一步做什么。
    public let nextStep: String

    public init(location: String, value: String, problem: String, nextStep: String) {
        self.location = location; self.value = value
        self.problem = problem; self.nextStep = nextStep
    }

    /// 界面和命令行都用这一句，保证「发生了什么 + 下一步做什么」不会只讲一半。
    public var message: String { "\(location)：\(problem) 下一步：\(nextStep)" }
}

/// 检查数据目录能不能原样拷到另一台电脑接着用（成品标准第 10 条）。
///
/// **判据只有一条：里面存的路径必须全都相对于数据目录本身。**
/// 一旦某处存成绝对路径，在原机器上一切正常，什么都不会报错 ——
/// 只有换机器的那天才会发现历史复盘全打不开。这属于本项目最危险的那类失败：
/// 静默的、要到很久以后才暴露的。
public enum DataPortabilityAudit {

    /// 只看 `state.json` 里的路径写法，不碰磁盘。
    public static func audit(state: CoachState) -> [PortabilityFinding] {
        var findings: [PortabilityFinding] = []
        for (index, session) in state.sessions.enumerated() {
            if let finding = checkRelativePath(session.reportPath,
                                               at: "sessions[\(index)].reportPath",
                                               what: "这次练习的复盘文件") {
                findings.append(finding)
            }
            if let finding = checkRelativePath(session.recordingPath,
                                               at: "sessions[\(index)].recordingPath",
                                               what: "这次练习的录音文件") {
                findings.append(finding)
            }
        }
        for (index, source) in state.questionSources.enumerated() {
            if let finding = checkSourceURL(source.sourceUrl,
                                            at: "questionSources[\(index)].sourceUrl") {
                findings.append(finding)
            }
        }
        return findings
    }

    /// 在路径写法之外，再检查引用到的文件是不是真的在数据目录里。
    /// 路径写法没问题但文件没跟着拷过来，换机器后点开历史复盘会是一片空白。
    public static func audit(state: CoachState, directory: DataDirectory,
                             fileManager: FileManager = .default) -> [PortabilityFinding] {
        var findings = audit(state: state)
        let alreadyReported = Set(findings.map(\.location))

        func checkExists(_ path: String, at location: String, what: String) {
            // 写法本身已经报过的，不再重复报「找不到」——
            // 同一个字段报两条，用户会以为有两个不同的问题要修。
            guard !alreadyReported.contains(location) else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let url = directory.root.appending(path: trimmed)
            guard !fileManager.fileExists(atPath: url.path) else { return }
            findings.append(PortabilityFinding(
                location: location, value: trimmed,
                problem: "记录里指着 \(what)「\(trimmed)」，但数据目录里找不到这个文件。",
                nextStep: "确认拷贝数据目录时把 reports/ 和 recordings/ 两个子目录整个带上了；"
                    + "若这个文件本来就被删过，可以在训练记录里删掉这一条，其余记录不受影响。"))
        }

        for (index, session) in state.sessions.enumerated() {
            checkExists(session.reportPath, at: "sessions[\(index)].reportPath", what: "复盘文件")
            checkExists(session.recordingPath, at: "sessions[\(index)].recordingPath", what: "录音文件")
        }
        return findings
    }

    // MARK: - 私有

    private static func checkRelativePath(_ raw: String, at location: String,
                                          what: String) -> PortabilityFinding? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空字符串是合法的：练习还没生成复盘 / 没开录音时这两个字段本来就是空的。
        guard !path.isEmpty else { return nil }

        let advice = "把它改写成相对于数据目录的路径（形如 reports/<会话id>.json 或 recordings/<会话id>.m4a），"
            + "并检查写入这个字段的代码——存绝对路径在本机不会报任何错，只有换电脑那天才会暴露。"

        if path.hasPrefix("file://") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是 file:// 开头的完整 URL，里面带着这台电脑的用户名与目录结构。",
                nextStep: advice)
        }
        if path.hasPrefix("/") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是绝对路径，换台电脑后这个位置根本不存在。",
                nextStep: advice)
        }
        if path.hasPrefix("~") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是以 ~ 开头的路径，它不会被当成家目录展开，会被当成一个叫「~」的文件夹。",
                nextStep: advice)
        }
        if path.split(separator: "/").contains("..") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)的路径里有 ..，指到了数据目录外面，拷贝数据目录时不会被带走。",
                nextStep: advice)
        }
        return nil
    }

    private static func checkSourceURL(_ raw: String, at location: String) -> PortabilityFinding? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // https 链接换机器照样打得开，不是问题；本机文件路径才是。
        guard value.hasPrefix("/") || value.hasPrefix("file://") else { return nil }
        return PortabilityFinding(
            location: location, value: value,
            problem: "题库来源记的是这台电脑上的文件路径，换台电脑后点开是空的。",
            nextStep: "这条不影响已经导入的题目，可以不管；"
                + "若希望干净，重新导入一次题库并让来源只记文件名，不记完整路径。")
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DataPortabilityAuditTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证（两条）**

**突变 A：** 把 `checkRelativePath` 里的
`guard !path.isEmpty else { return nil }`
改成
`guard !path.isEmpty || true else { return nil }`（即取消空值豁免）
重跑：`testEmptyPathsAreNotFindings` 必须变红。

**这条守的是「误报比漏报更致命」**：把「练习还没出复盘」当成数据损坏，用户每次打开关于页都看到一屏红字，几天之后他会学会无视所有告警——那时真正的问题也一起被无视了。

**突变 B：** 把 `audit(state:directory:fileManager:)` 里 `checkExists` 的整个 `findings.append(...)` 删掉（改成什么都不做）。
重跑：`testMissingReportFileIsReportedByTheDirectoryAudit` 与 `testMissingRecordingFileIsReportedByTheDirectoryAudit` 必须变红。

改回后确认全绿，把两次输出写进报告。

- [ ] **Step 6: 接上命令行**

`Sources/coach/PortabilityCommand.swift`：

```swift
import Foundation
import IELTSCoachCore

enum PortabilityCommand {
    static func run() -> Int32 {
        let directory = DataDirectory.resolve()
        let state: CoachState
        do {
            state = try StateStore(directory: directory).load()
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }

        print("数据目录：\(directory.root.path)")
        print("题库 \(state.questions.count) 题，练习记录 \(state.sessions.count) 次，"
            + "错题 \(state.issues.count) 条，词汇 \(state.vocabulary.count) 条")

        let findings = DataPortabilityAudit.audit(state: state, directory: directory)
        guard !findings.isEmpty else {
            print("✅ 这个目录可以整个拷到另一台电脑接着用，没发现任何依赖本机路径的地方。")
            return 0
        }
        print("\n⚠️  发现 \(findings.count) 处换电脑后会断掉的地方：")
        for finding in findings { print("   • \(finding.message)") }
        return 1
    }
}
```

`Sources/coach/main.swift`：用法文本里加一行，`switch` 里加一个分支。

```swift
      coach portability             检查数据目录能否原样搬到另一台电脑
```

```swift
case "portability":
    exit(PortabilityCommand.run())
```

- [ ] **Step 7: 验证命令行**

Run: `swift build && IELTS_SPEAKING_DATA_DIR="$(mktemp -d)" ./.build/debug/coach portability`
Expected: 打印数据目录路径与全 0 的统计，最后 `✅ 这个目录可以整个拷到另一台电脑接着用…`，退出码 0

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift Sources/coach/PortabilityCommand.swift Sources/coach/main.swift Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift
git commit -m "feat(core): 数据目录可搬迁审计与 coach portability"
```

---

## Task 5: 诊断信息（可复制，且不含练习内容）

**Files:**
- Create: `Sources/IELTSCoachUI/About/DiagnosticsReport.swift`
- Create: `Tests/IELTSCoachUITests/DiagnosticsReportTests.swift`

**Interfaces:**
- Consumes: `AppMetadata`（Task 3）、`PermissionState`（Phase 3）、`CoachState`、`PortabilityFinding`（Task 4）
- Produces:
  - `struct DiagnosticsInput: Sendable`，字段 `metadata: AppMetadata`、`dataDirectory: URL`、`systemVersion: String`、`permission: PermissionState`、`state: CoachState`、`portabilityFindingCount: Int`；`init(metadata:dataDirectory:systemVersion:permission:state:portabilityFindingCount:)`
  - `enum DiagnosticsReport { static func text(_ input: DiagnosticsInput) -> String }`

**为什么要有这个东西：** 「ChatGPT 改版导致自动化失效」是已知且不可避免的风险（ROADMAP 第 6 节）。真出问题时，用户需要能一键复制一段话发出来，而这段话必须**足够说明问题、又不带走任何练习内容**——逐字稿、错题原句、词汇、姓名都不能出现在里面。只报数量，不报内容。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/DiagnosticsReportTests.swift`：

```swift
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class DiagnosticsReportTests: XCTestCase {
    private let secretAnswer = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
    private let secretIssue = "I-VERY-LIKE-IT-SECRET"
    private let secretWord = "SECRET-VOCAB-WORD"
    private let secretName = "SECRET-LEARNER-NAME"

    private func metadata() -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: .selfSigned)
    }

    private func loadedState() -> CoachState {
        var state = CoachState.empty(displayName: secretName)
        state.questions = [
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?"),
            Question(id: "q2", part: 2, topic: "Skills", prompt: "Describe a useful skill.")
        ]
        state.sessions = [
            PracticeSession(id: "s1", questionId: "q1", focusPart: .part1,
                            startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                            goal: "",
                            transcript: [PracticeSession.TranscriptTurn(
                                role: "user", text: secretAnswer, capturedAt: "2026-08-06T00:01:00Z")],
                            reportPath: "reports/s1.json", recordingPath: "")
        ]
        state.issues = [IssueRecord(id: "i1", learnerSaid: secretIssue, correction: "c",
                                    whyItMatters: "w", occurrences: 3,
                                    sourceSessionIds: ["s1"], lastSeenAt: "2026-08-06T00:00:00Z")]
        state.vocabulary = [VocabularyRecord(id: "v1", basicWord: secretWord,
                                             betterExpression: "b", collocation: "c",
                                             priority: "high", sourceSessionIds: ["s1"])]
        state.targets = [RetrainingTarget(targetKey: "t1", label: "L", status: "new",
                                          evidence: [], sourceSessionId: "s1", createdAt: "t")]
        return state
    }

    private func input(permission: PermissionState = .ready,
                       findings: Int = 0) -> DiagnosticsInput {
        DiagnosticsInput(metadata: metadata(),
                         dataDirectory: URL(fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach"),
                         systemVersion: "macOS 26.5.2",
                         permission: permission,
                         state: loadedState(),
                         portabilityFindingCount: findings)
    }

    func testContainsWhatSomeoneWouldNeedToDiagnoseIt() {
        let text = DiagnosticsReport.text(input())
        for needle in ["1.0.0", "42", "a1b2c3d", "com.ielts.speakingcoach",
                       "macOS 26.5.2",
                       "/Users/tester/Library/Application Support/IELTS Speaking Coach"] {
            XCTAssertTrue(text.contains(needle), "诊断信息里缺了「\(needle)」：\n\(text)")
        }
    }

    func testNeverLeaksPracticeContent() {
        // 这段话是要发给别人看的。数量可以给，内容一个字都不能带出去。
        let text = DiagnosticsReport.text(input())
        for secret in [secretAnswer, secretIssue, secretWord, secretName] {
            XCTAssertFalse(text.contains(secret),
                           "诊断信息把练习内容带出去了：「\(secret)」\n\(text)")
        }
    }

    func testReportsCountsInsteadOfContent() {
        let text = DiagnosticsReport.text(input())
        XCTAssertTrue(text.contains("2 题"), "题库数量应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 次"), "练习次数应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 条"), "错题/词汇数量应该给：\n\(text)")
    }

    func testEveryPermissionStateIsExplainedInChinese() {
        // 诊断信息里出现 "needsAccessibility" 这种枚举名，对用户等于没写。
        for state in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertFalse(text.contains("needsAccessibility"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("needsChatGPT"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("unknown"), "\(state) 露出了枚举名")
        }
    }

    func testUnreadyPermissionAlwaysCarriesANextStep() {
        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertTrue(text.contains("下一步"), "\(state) 没告诉用户下一步做什么：\n\(text)")
        }
    }

    func testPortabilityProblemsAreSurfacedWithANextStep() {
        let clean = DiagnosticsReport.text(input(findings: 0))
        XCTAssertTrue(clean.contains("没有发现问题"))

        let dirty = DiagnosticsReport.text(input(permission: .ready, findings: 3))
        XCTAssertTrue(dirty.contains("3"), "要说清有几处")
        XCTAssertTrue(dirty.contains("下一步"), "有问题就必须给下一步")
    }

    func testNoLineIsBlankOrEndsWithADanglingLabel() {
        // 「版本：」后面空着，比不写还糟：用户会以为程序坏了。
        let text = DiagnosticsReport.text(input())
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "有空行：\n\(text)")
            XCTAssertFalse(line.hasSuffix("："), "有标签后面没内容：「\(line)」")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DiagnosticsReportTests`
Expected: 编译失败 —— `DiagnosticsReport`、`DiagnosticsInput` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/About/DiagnosticsReport.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct DiagnosticsInput: Sendable {
    public let metadata: AppMetadata
    public let dataDirectory: URL
    public let systemVersion: String
    public let permission: PermissionState
    public let state: CoachState
    public let portabilityFindingCount: Int

    public init(metadata: AppMetadata, dataDirectory: URL, systemVersion: String,
                permission: PermissionState, state: CoachState,
                portabilityFindingCount: Int) {
        self.metadata = metadata; self.dataDirectory = dataDirectory
        self.systemVersion = systemVersion; self.permission = permission
        self.state = state; self.portabilityFindingCount = portabilityFindingCount
    }
}

/// 一段可以一键复制、直接发给别人的诊断文本。
///
/// **只报数量，不报内容。** 逐字稿、错题原句、词汇、姓名都不进这段文字 ——
/// 用户复制它的时候不会逐字检查里面有什么，所以这个边界只能由代码保证。
public enum DiagnosticsReport {
    public static func text(_ input: DiagnosticsInput) -> String {
        var lines: [String] = []
        lines.append("IELTS Speaking Coach 诊断信息")
        lines.append("版本：\(input.metadata.versionLine)")
        lines.append("提交：\(input.metadata.buildCommit)")
        lines.append("构建时间：\(input.metadata.buildDate)")
        lines.append("签名：\(input.metadata.channel.title)（身份：\(input.metadata.signingIdentity)）")
        lines.append("标识：\(input.metadata.bundleIdentifier)")
        lines.append("系统：\(input.systemVersion)")
        lines.append("数据目录：\(input.dataDirectory.path)")
        lines.append("数据量：题库 \(input.state.questions.count) 题 · "
            + "练习记录 \(input.state.sessions.count) 次 · "
            + "错题 \(input.state.issues.count) 条 · "
            + "词汇 \(input.state.vocabulary.count) 条 · "
            + "重训目标 \(input.state.targets.count) 个")
        lines.append("辅助功能：\(permissionText(input.permission))")
        if input.portabilityFindingCount == 0 {
            lines.append("数据可搬迁检查：没有发现问题")
        } else {
            lines.append("数据可搬迁检查：发现 \(input.portabilityFindingCount) 处问题。"
                + "下一步：在关于页点「查看详情」，按每条给的提示逐条处理。")
        }
        lines.append("——以上只有数量，不含任何练习内容。要看具体内容请直接打开数据目录。")
        return lines.joined(separator: "\n")
    }

    private static func permissionText(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "已授权，自动化可用"
        case .needsAccessibility:
            return "未授权，只能半自动运行。下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选。"
        case .needsChatGPT:
            return "判断不了——本机没找到 ChatGPT（新版桌面应用）。下一步：先安装它，再回来重新检查。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。下一步：在关于页点「重新检查」，把它显示的原始消息一并发出来。"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DiagnosticsReportTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

在 `text(_:)` 里加一行
`lines.append("学员：\(input.state.learner.displayName)")`
重跑：`testNeverLeaksPracticeContent` 必须变红。删掉后确认全绿。

**这条守的是隐私边界不是靠自觉维持的**。「顺手把姓名也带上，好认一点」是一个非常自然的改动，而这段文字的用途就是发给别人看。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/About/DiagnosticsReport.swift Tests/IELTSCoachUITests/DiagnosticsReportTests.swift
git commit -m "feat(ui): 可复制的诊断信息"
```

---

## Task 6: 关于页视图模型、致谢与许可

**Files:**
- Create: `LICENSE`
- Create: `Sources/IELTSCoachUI/About/AboutViewModel.swift`
- Create: `Tests/IELTSCoachUITests/AboutViewModelTests.swift`

**Interfaces:**
- Consumes: `AppMetadata`、`SignatureChannel`（Task 3）、`PermissionState`（Phase 3）、`PortabilityFinding`（Task 4）
- Produces:
  - `struct AboutRow: Equatable, Identifiable, Sendable { let id: String; let label: String; let value: String; let hint: String }`
  - `struct Acknowledgement: Equatable, Identifiable, Sendable { var id: String { name }; let name: String; let role: String; let license: String; let url: String }`
  - `enum AboutViewModel`
    - `static func rows(metadata: AppMetadata, dataDirectory: URL, permission: PermissionState, portabilityFindings: [PortabilityFinding]) -> [AboutRow]`
    - `static let acknowledgements: [Acknowledgement]`
    - `static let licenseNotice: String`

### 许可怎么定

仓库现在没有 `LICENSE` 文件。**默认取「保留所有权利、个人自用」**，理由：这是个自用工具（成品标准第 4 节明确「不做云同步、不做多用户」，ROADMAP 决策记录写的是「先自用，架构预留分发能力」）。把编译好的副本给朋友，在这个条款下是作者自己在行使权利，完全没问题。

**若用户想开源，只需要改两处**：`LICENSE` 文件本身，和 `AboutViewModel.licenseNotice`。这一条列进本阶段需要用户确认的事项（见文末「需要用户参与的环节」）。

商标声明必须有，而且必须准确——这个 App 会被交到别人手上，不能让人误以为它是 OpenAI 或雅思主办方的产品。

- [ ] **Step 1: 写 `LICENSE`**

仓库根目录 `LICENSE`：

```
版权所有 © 2026 IELTS Speaking Coach 的作者。保留所有权利。

本工具为个人自用而写。作者可以把编译好的副本给任何人，收到副本的人可以自用；
未授予公开再分发、修改或商业使用的许可。

本工具与 OpenAI 无隶属关系，也不隶属于任何雅思考试主办方
（British Council、IDP、Cambridge Assessment English）。
"IELTS" 与 "ChatGPT" 是各自权利人的商标，此处仅用于说明本工具的用途。

本工具不内置任何商业题库，只带原创样例；你的题库由你自己导入。
本工具不调用 OpenAI 的任何接口，复盘由你自己的 ChatGPT 账号在本机生成。

本工具按现状提供，不作任何明示或默示的担保。
```

- [ ] **Step 2: 写失败的测试**

`Tests/IELTSCoachUITests/AboutViewModelTests.swift`：

```swift
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class AboutViewModelTests: XCTestCase {
    private let dataDirectory = URL(
        fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach")

    private func metadata(channel: SignatureChannel = .selfSigned) -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: channel)
    }

    private func rows(channel: SignatureChannel = .selfSigned,
                      permission: PermissionState = .ready,
                      findings: [PortabilityFinding] = []) -> [AboutRow] {
        AboutViewModel.rows(metadata: metadata(channel: channel),
                            dataDirectory: dataDirectory,
                            permission: permission,
                            portabilityFindings: findings)
    }

    func testEveryRowHasBothALabelAndAValue() {
        // 只有标签没有内容的一行，会让人以为程序坏了。
        for row in rows() {
            XCTAssertFalse(row.label.isEmpty, "\(row.id) 缺标签")
            XCTAssertFalse(row.value.isEmpty, "\(row.id) 缺内容")
        }
    }

    func testRowIDsAreUnique() {
        let ids = rows().map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ForEach 用 id 渲染，重复会错乱")
    }

    func testDataDirectoryRowShowsTheRealPathAndSaysItIsPortable() {
        let row = rows().first { $0.id == "dataDirectory" }
        XCTAssertEqual(row?.value, dataDirectory.path)
        XCTAssertTrue(row?.hint.contains("拷") ?? false,
                      "数据目录这行必须告诉用户「换电脑时拷这个文件夹」，那是这一行存在的全部意义")
    }

    func testBundleIdentifierRowExplainsWhyItNeverChanges() {
        let row = rows().first { $0.id == "bundle" }
        XCTAssertEqual(row?.value, "com.ielts.speakingcoach")
        XCTAssertFalse(row?.hint.isEmpty ?? true,
                       "这一行要解释为什么这个标识永远不变——它是辅助功能授权的锚")
    }

    func testSelfSignedSignatureRowTellsTheRecipientHowToOpenIt() {
        let row = rows(channel: .selfSigned).first { $0.id == "signature" }
        let hint = row?.hint ?? ""
        XCTAssertTrue(hint.contains("系统设置"), "没说去哪儿：\(hint)")
        XCTAssertTrue(hint.contains("仍要打开"), "没说点什么：\(hint)")
    }

    func testDeveloperIDSignatureRowDoesNotScareTheUser() {
        let hint = rows(channel: .developerID).first { $0.id == "signature" }?.hint ?? ""
        XCTAssertFalse(hint.contains("仍要打开"),
                       "已公证的包双击就能开，不该还教人绕 Gatekeeper")
    }

    func testPermissionRowCarriesANextStepWhenNotGranted() {
        let granted = rows(permission: .ready).first { $0.id == "permission" }
        XCTAssertFalse(granted?.value.isEmpty ?? true)

        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let row = rows(permission: state).first { $0.id == "permission" }
            XCTAssertTrue(row?.hint.contains("下一步") ?? false,
                          "\(state) 没告诉用户下一步做什么")
        }
    }

    func testPortabilityRowSaysOKWhenCleanAndCountsWhenNot() {
        let clean = rows().first { $0.id == "portability" }
        XCTAssertTrue(clean?.value.contains("没有发现问题") ?? false)

        let finding = PortabilityFinding(location: "sessions[0].reportPath", value: "/abs/a.json",
                                         problem: "绝对路径。", nextStep: "改成相对路径。")
        let dirty = rows(findings: [finding, finding]).first { $0.id == "portability" }
        XCTAssertTrue(dirty?.value.contains("2") ?? false, "要说清有几处")
        XCTAssertTrue(dirty?.hint.contains("sessions[0].reportPath") ?? false,
                      "至少要把第一条的位置显示出来，否则用户不知道去哪儿看")
    }

    func testDevelopmentRunStillProducesCompleteRows() {
        // swift run 直接跑（没有 App bundle）时，关于页照样得能看。
        let rows = AboutViewModel.rows(metadata: AppMetadata.from(infoDictionary: nil),
                                       dataDirectory: dataDirectory,
                                       permission: .ready, portabilityFindings: [])
        XCTAssertFalse(rows.isEmpty)
        for row in rows { XCTAssertFalse(row.value.isEmpty, "\(row.id) 在开发运行时变成了空白") }
    }

    // MARK: - 致谢与许可

    func testAcknowledgementsCreditTheUpstreamProject() {
        let upstream = AboutViewModel.acknowledgements
            .first { $0.name.contains("ielts-speaking-coach") }
        XCTAssertNotNil(upstream, "本项目的功能范围、复盘规范与 state.json 结构都来自上游，出处必须写明")
        XCTAssertFalse(upstream?.url.isEmpty ?? true, "上游要给得出链接")
    }

    func testAcknowledgementsStateTheOpenAIDisclaimer() {
        let joined = AboutViewModel.acknowledgements
            .map { "\($0.name)\($0.role)\($0.license)" }.joined()
        XCTAssertTrue(joined.contains("无隶属关系"),
                      "这个 App 会被交到别人手上，必须写明与 OpenAI 无隶属关系")
    }

    func testEveryAcknowledgementIsComplete() {
        for item in AboutViewModel.acknowledgements {
            XCTAssertFalse(item.name.isEmpty, "致谢条目缺名字")
            XCTAssertFalse(item.role.isEmpty, "「\(item.name)」没说它在这个项目里是干什么的")
            XCTAssertFalse(item.license.isEmpty, "「\(item.name)」没写许可情况")
        }
    }

    func testAcknowledgementIDsAreUnique() {
        let ids = AboutViewModel.acknowledgements.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLicenseNoticeCoversTrademarksAndRedistribution() {
        let notice = AboutViewModel.licenseNotice
        XCTAssertFalse(notice.isEmpty)
        XCTAssertTrue(notice.contains("商标"), "许可说明里要有商标声明")
        XCTAssertTrue(notice.contains("再分发"), "许可说明里要说清能不能再分发")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter AboutViewModelTests`
Expected: 编译失败 —— `AboutViewModel` 未定义

- [ ] **Step 4: 实现**

`Sources/IELTSCoachUI/About/AboutViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct AboutRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    /// 补充说明。凡是用户可能要做点什么的行，这里必须含「下一步」。
    public let hint: String

    public init(id: String, label: String, value: String, hint: String) {
        self.id = id; self.label = label; self.value = value; self.hint = hint
    }
}

public struct Acknowledgement: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    /// 它在这个项目里到底起了什么作用。只写名字等于没致谢。
    public let role: String
    public let license: String
    public let url: String

    public init(name: String, role: String, license: String, url: String) {
        self.name = name; self.role = role; self.license = license; self.url = url
    }
}

public enum AboutViewModel {

    public static func rows(metadata: AppMetadata, dataDirectory: URL,
                            permission: PermissionState,
                            portabilityFindings: [PortabilityFinding]) -> [AboutRow] {
        [
            AboutRow(id: "version", label: "版本", value: metadata.versionLine,
                     hint: "构建于 \(metadata.buildDate)，提交 \(metadata.buildCommit)。"),
            AboutRow(id: "bundle", label: "标识", value: metadata.bundleIdentifier,
                     hint: "系统的辅助功能授权绑定这个标识，因此它在任何版本里都不会变。"
                         + "看到授权莫名失效时，先确认这一行还是它。"),
            AboutRow(id: "signature", label: "签名", value: metadata.channel.title,
                     hint: "\(metadata.channel.explanation) \(metadata.channel.nextStep)"),
            AboutRow(id: "permission", label: "辅助功能", value: permissionValue(permission),
                     hint: permissionHint(permission)),
            AboutRow(id: "dataDirectory", label: "数据目录", value: dataDirectory.path,
                     hint: "你的题库、练习记录、复盘、录音全在这个文件夹里。"
                         + "换电脑时把它整个拷过去就能接着用；备份就是拷贝它。"),
            portabilityRow(portabilityFindings)
        ]
    }

    private static func permissionValue(_ state: PermissionState) -> String {
        switch state {
        case .ready: return "已授权"
        case .needsAccessibility: return "未授权（半自动模式）"
        case .needsChatGPT: return "无法判断"
        case .unknown: return "检查未通过"
        }
    }

    private static func permissionHint(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "本 App 用它来替你操作 ChatGPT：新建会话、点开语音、发考官提示词、取回复盘。"
        case .needsAccessibility:
            return "没有它就只能半自动：提示词要你自己粘、复盘要你自己 ⌘C。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选，回来点「重新检查」。"
        case .needsChatGPT:
            return "本机没找到 ChatGPT（新版桌面应用）。注意 ChatGPT Classic 没有语音，不是这里要的那个。"
                + "下一步：装好新版 ChatGPT.app 之后回来点「重新检查」。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。"
                + "下一步：点「重新检查」看原始消息；若看不懂，用「复制诊断信息」把它整段发出来。"
        }
    }

    private static func portabilityRow(_ findings: [PortabilityFinding]) -> AboutRow {
        guard let first = findings.first else {
            return AboutRow(id: "portability", label: "数据可搬迁检查",
                            value: "没有发现问题",
                            hint: "这个目录可以整个拷到另一台电脑接着用。")
        }
        let more = findings.count > 1 ? "（共 \(findings.count) 处，这里只列第一条）" : ""
        return AboutRow(id: "portability", label: "数据可搬迁检查",
                        value: "发现 \(findings.count) 处问题",
                        hint: "\(first.message)\(more)")
    }

    // MARK: - 致谢

    public static let acknowledgements: [Acknowledgement] = [
        Acknowledgement(
            name: "lindsey-labs/ielts-speaking-coach",
            role: "上游项目。本工具的功能范围、复盘规范与 state.json 结构都来自它。"
                + "本工具是 macOS 原生重写，没有复制它的任何代码。",
            license: "未使用其代码，因此不受其许可证约束；此处仅作出处致谢。",
            url: "https://github.com/lindsey-labs/ielts-speaking-coach"),
        Acknowledgement(
            name: "SF Symbols",
            role: "界面里的全部图标。",
            license: "Apple 提供。可在应用界面中使用，不得改造成自有字体，也不得用作商标。",
            url: "https://developer.apple.com/sf-symbols/"),
        Acknowledgement(
            name: "SF Pro（macOS 系统字体）",
            role: "界面里的全部文字。",
            license: "随系统提供，未打包进本 App。",
            url: ""),
        Acknowledgement(
            name: "OpenAI ChatGPT",
            role: "本工具驱动你本机已安装的 ChatGPT 应用完成练习与复盘，"
                + "不调用 OpenAI 的任何接口，也不产生额外费用。",
            license: "本工具与 OpenAI 无隶属关系，也未获其背书。",
            url: ""),
        Acknowledgement(
            name: "第三方依赖",
            role: "没有。整个工程只用 Swift 标准库与系统框架。",
            license: "不适用。",
            url: "")
    ]

    /// 与仓库根目录的 LICENSE 保持一致。要改就两处一起改。
    public static let licenseNotice = """
        版权所有 © 2026 IELTS Speaking Coach 的作者。保留所有权利。

        本工具为个人自用而写。作者可以把编译好的副本给任何人，收到副本的人可以自用；\
        未授予公开再分发、修改或商业使用的许可。

        本工具与 OpenAI 无隶属关系，也不隶属于任何雅思考试主办方\
        （British Council、IDP、Cambridge Assessment English）。\
        "IELTS" 与 "ChatGPT" 是各自权利人的商标，此处仅用于说明本工具的用途。

        本工具按现状提供，不作任何明示或默示的担保。
        """
}
```

**若实现过程中发现工程里其实复制了上游的任何代码**（比如逐字移植的算法、逐字照抄的提示词文本），**必须停下来**：去核对上游仓库的 LICENSE，把 `acknowledgements` 里那一条的 `license` 改成真实的许可证名，并确认本项目的分发方式与之相容。这不是形式问题，是许可证问题。

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter AboutViewModelTests`
Expected: PASS（14 个测试）

- [ ] **Step 6: 突变验证（两条）**

**突变 A：** 把 `SignatureChannel.selfSigned.nextStep` 的返回值改成 `""`。
重跑：`testSelfSignedSignatureRowTellsTheRecipientHowToOpenIt`（Task 6）与 `testSelfSignedTellsTheRecipientHowToGetPastGatekeeper`（Task 3）必须同时变红。

**这条守的是这个阶段的交付定义本身**：交付物是「一个能给别人的 `.app`」。实测过 `spctl` 判定为 `rejected`——对方双击一定打不开。少了这句话，这个 `.app` 就只是「能给别人，但别人打不开」。

**突变 B：** 把 `portabilityRow` 里 `guard let first = findings.first else { ... }` 的两个分支对调（有问题时返回「没有发现问题」）。
重跑：`testPortabilityRowSaysOKWhenCleanAndCountsWhenNot` 必须变红。

改回后确认全绿，把输出写进报告。

- [ ] **Step 7: 提交**

```bash
git add LICENSE Sources/IELTSCoachUI/About/AboutViewModel.swift Tests/IELTSCoachUITests/AboutViewModelTests.swift
git commit -m "feat(ui): 关于页视图模型、致谢与许可"
```

---

## Task 7: 关于页界面与菜单接入

**Files:**
- Create: `Sources/IELTSCoachUI/About/AboutView.swift`
- Modify: `Sources/IELTSCoachApp/main.swift`

**Interfaces:**
- Consumes: `AboutViewModel.rows(...)`、`AboutViewModel.acknowledgements`、`AboutViewModel.licenseNotice`、`AppMetadata.current`、`DiagnosticsReport.text(_:)`、`DataPortabilityAudit.audit(state:directory:)`、`DataDirectory.resolve()`、`StateStore.load()`、`PermissionStatus.evaluate(readiness:)`、设计令牌与 `CoachCard` / `SectionHeader`
- Produces:
  - `enum AboutWindow { static let id = "about" }`
  - `struct AboutMenuButton: View`（`public init()`）
  - `struct AboutView: View`（`public init()`）

**关于页是独立窗口，拿不到主窗口的 `AppState`，所以它自己读一次。** 这是只读页，重复读一次 `state.json` 的代价可以忽略；换成到处传 `AppState` 反而会把主窗口的生命周期和一个偶尔打开的小窗绑死。

**不要往侧边栏加第 11 项。** 侧边栏固定十项，Phase 3 的 `testSidebarHasAllTenItems` 守着它，那条测试是对的。关于页在苹果菜单里（`关于 IELTS Speaking Coach`），这是 Mac 应用的标准位置。

- [ ] **Step 1: 改 `Sources/IELTSCoachApp/main.swift`**

这一段给完整代码——它不是布局，是 Scene 与菜单的结构，摆错了关于页根本打不开。

```swift
import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") { RootView() }
            .defaultSize(width: 1100, height: 720)
            .commands {
                // 替换系统默认的「关于 …」，指向我们自己的窗口。
                // 放在苹果菜单里是 Mac 应用的标准位置——不要为它在侧边栏加第 11 项。
                CommandGroup(replacing: .appInfo) { AboutMenuButton() }
            }

        Window("关于 IELTS Speaking Coach", id: AboutWindow.id) { AboutView() }
            .windowResizability(.contentSize)
    }
}

CoachApp.main()
```

- [ ] **Step 2: 写 `AboutView.swift`**

`AboutWindow` 与 `AboutMenuButton` 给完整代码（结构性的）：

```swift
import AppKit
import SwiftUI

public enum AboutWindow {
    public static let id = "about"
}

/// 苹果菜单里的「关于 …」。
public struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("关于 IELTS Speaking Coach") { openWindow(id: AboutWindow.id) }
    }
}
```

`AboutView` 只给验收要求，布局由实现者定：

| 必须做到 | 判据 |
|---|---|
| 顶部显示 App 名称与版本行 | 文案取 `AppMetadata.current.versionLine`，不得写死 |
| 逐行显示 `AboutViewModel.rows(...)` 的六行 | 每行显示 `label` / `value` / `hint`；`hint` 为空时不显示空行 |
| 「在访达中显示」按钮 | 点了调 `NSWorkspace.shared.activateFileViewerSelecting([dataDirectory])`；数据目录不存在时先 `try? DataDirectory.resolve().createIfNeeded()` |
| 「复制诊断信息」按钮 | 把 `DiagnosticsReport.text(...)` 写进 `NSPasteboard.general`，并给一句「已复制」的即时反馈（否则用户不知道点没点上） |
| 「重新检查」按钮 | 重新跑 `preflight()` + 可搬迁审计，刷新页面 |
| 致谢区 | 逐条显示 `acknowledgements` 的 `name` / `role` / `license`；`url` 非空时才显示可点的链接 |
| 许可区 | 显示 `AboutViewModel.licenseNotice` 全文，可选中复制 |
| 读 `state.json` 失败时 | **不能空白**。显示中文错误全文 + 数据目录路径 + 「重试」按钮。其余各行（版本、签名、权限）仍要正常显示——读不到训练数据不影响它们 |
| 全部走设计令牌 | 视图里不得出现字面颜色、字号、圆角 |
| 图标只用 SF Symbols | 不得用 emoji |
| 窗口尺寸 | 内容自适应，`.windowResizability(.contentSize)`；文字放大到系统最大档时不截断、不重叠 |

**这一页有一个容易踩的坑：** 它在 `swift run IELTSCoachApp` 下运行时 `AppMetadata` 全是「未知（开发运行）」，看上去像坏了。**这不是 bug**，Task 3 的测试专门保证了它显示得像样。要看真实版本号，得跑 `./scripts/build-app.sh` 之后打开 `.app`。

- [ ] **Step 3: 编译与人工验证**

Run: `swift build && swift test`
Expected: 构建通过，全部测试绿

Run: `./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"`
Expected: 菜单栏 `IELTS Speaking Coach › 关于 IELTS Speaking Coach` 能打开关于窗口；六行都有内容；版本显示 `1.0.0（构建 N）`；签名那行显示「自签名（未经 Apple 公证）」并给出「系统设置 › … › 仍要打开」的说明；数据目录那行显示真实路径且「在访达中显示」能打开 Finder。

Run: 在关于页点「复制诊断信息」，然后 `pbpaste`
Expected: 打印出诊断文本；**逐行读一遍，确认里面没有任何练习内容**（这是 Task 5 测试之外的一次人眼复核）

- [ ] **Step 4: 提交**

```bash
git add Sources/IELTSCoachUI/About/AboutView.swift Sources/IELTSCoachApp/main.swift
git commit -m "feat(ui): 关于页与菜单接入"
```

---

## Task 8: 首次使用引导

**Files:**
- Create: `Sources/IELTSCoachUI/Onboarding/OnboardingFlow.swift`
- Create: `Sources/IELTSCoachUI/Onboarding/OnboardingProgressStore.swift`
- Create: `Sources/IELTSCoachUI/Onboarding/WelcomeFlowView.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Tests/IELTSCoachUITests/OnboardingFlowTests.swift`

**Interfaces:**
- Consumes: `PermissionState`、`PermissionStatus.systemSettingsURL`、`PermissionGateView(state:messages:onRecheck:onSkip:)`（全部来自 Phase 3 Task 2）、`AppState`、`CoachState.questions`、`CoachSettings`、`StateStore.mutate`
- Produces:
  - `enum OnboardingStep: String, CaseIterable, Identifiable, Sendable { case welcome, environment, questionBank, recordingChoice, ready }`
    - `var title: String` / `var body: String` / `var primaryActionTitle: String` / `var canSkip: Bool`
  - `enum OnboardingFlow`
    - `static let currentVersion = 1`
    - `static func steps(permission: PermissionState, questionCount: Int, hasCompletedBefore: Bool) -> [OnboardingStep]`
    - `static func shouldPresent(permission: PermissionState, questionCount: Int, hasCompletedBefore: Bool) -> Bool`
  - `protocol OnboardingProgressStore: AnyObject { func completedVersion() -> Int; func markCompleted(version: Int) }`
  - `final class UserDefaultsOnboardingStore: OnboardingProgressStore`，`static let key = "com.ielts.speakingcoach.onboardingCompletedVersion"`，`init(defaults: UserDefaults = .standard)`
  - `struct WelcomeFlowView: View`

### 两条决定了这个任务全部形状的设计判断

**一、「看过引导没有」这个标记存在本机 `UserDefaults`，不存进数据目录。**

这不是偷懒，是这一整个阶段的核心命题的直接推论。数据目录里应该**只放换机器时要跟着走的东西**；而「引导看过没有」恰恰是**不该**跟着走的：换了机器，辅助功能授权是本机 TCC 的，必须重给一次。要是把这个标记写进 `state.json`，新机器上的用户一进来就没有引导，直接撞上一堵「点开始练习却报错」的墙——而他手上的数据看起来一切正常，根本想不到问题出在权限。

**二、走过引导的人，只有一种情况会再看到它：辅助功能权限不在了。**

（换了机器、系统升级后 TCC 被重置、或者用户自己取消了勾选。）这时只显示「环境」那一步。其余步骤不再打扰：题库空不空首页已经有空状态引导，录音开关在设置里随时能改。

**「环境」这一步永远可跳过**，跳过就直接进主界面跑半自动模式（设计文档第 7 节：授权可跳过）。跳过之后如果权限仍然缺，**下次启动还会再问一次**——这是刻意的：没有辅助功能权限，这个产品的核心自动化就是残的，每次开机温和地提醒一次（且一键可跳过）比默默残废好。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/OnboardingFlowTests.swift`：

```swift
import Foundation
import XCTest
@testable import IELTSCoachUI

final class OnboardingFlowTests: XCTestCase {

    private func steps(permission: PermissionState, questions: Int,
                       completed: Bool) -> [OnboardingStep] {
        OnboardingFlow.steps(permission: permission, questionCount: questions,
                             hasCompletedBefore: completed)
    }

    // MARK: - 全新安装

    func testFreshInstallWalksThroughEverything() {
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 0, completed: false),
                       [.welcome, .environment, .questionBank, .recordingChoice, .ready])
    }

    func testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere() {
        // 这正是「把数据目录拷过来的人」在新机器上第一次开 App 的样子：
        // 题库在，练习记录也在，再让他导一次题库是在浪费他时间、也让人怀疑数据没拷成功。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: false),
                       [.welcome, .environment, .recordingChoice, .ready])
    }

    func testFreshInstallStillExplainsThePermissionEvenWhenAlreadyGranted() {
        // 权限已经给了也要过一遍这一步：用户有权知道这个 App 拿辅助功能去干什么。
        XCTAssertTrue(steps(permission: .ready, questions: 5, completed: false)
                        .contains(.environment))
    }

    func testFirstStepIsAlwaysWelcomeAndLastIsAlwaysReady() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 100] {
                let result = steps(permission: permission, questions: count, completed: false)
                XCTAssertEqual(result.first, .welcome, "\(permission)/\(count) 的第一步不是欢迎")
                XCTAssertEqual(result.last, .ready, "\(permission)/\(count) 的最后一步不是完成")
            }
        }
    }

    // MARK: - 已经走过引导的人

    func testReturningUserWithEverythingReadySeesNothing() {
        XCTAssertTrue(steps(permission: .ready, questions: 217, completed: true).isEmpty)
        XCTAssertTrue(steps(permission: .ready, questions: 0, completed: true).isEmpty,
                      "题库空不该再弹引导——首页的空状态已经在引导他导入了")
    }

    func testReturningUserWithoutAccessibilitySeesOnlyTheEnvironmentStep() {
        // 换机器场景：数据拷过来了，题库和记录都在，但辅助功能授权是本机的，必须重给。
        // 少了这一步，用户会打开一个「看起来一切正常、点开始练习却报错」的 App。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithoutChatGPTSeesTheEnvironmentStep() {
        XCTAssertEqual(steps(permission: .needsChatGPT, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithAnUnrecognizedFailureSeesTheEnvironmentStep() {
        // 不能因为「没认出来」就当成就绪放过去——那会让用户点进去撞一堵没有线索的墙。
        XCTAssertEqual(steps(permission: .unknown, questions: 217, completed: true),
                       [.environment])
    }

    func testShouldPresentAgreesWithSteps() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 217] {
                for completed in [true, false] {
                    let hasSteps = !steps(permission: permission, questions: count,
                                          completed: completed).isEmpty
                    XCTAssertEqual(
                        OnboardingFlow.shouldPresent(permission: permission, questionCount: count,
                                                     hasCompletedBefore: completed),
                        hasSteps,
                        "\(permission)/\(count)/\(completed) 两者对不上")
                }
            }
        }
    }

    // MARK: - 每一步自己

    func testOnlyEnvironmentAndQuestionBankCanBeSkipped() {
        // welcome / ready 只是叙述，没有可跳过的东西；
        // recordingChoice 本身就是一个二选一（默认关也是一种选择），不该给「跳过」。
        XCTAssertEqual(Set(OnboardingStep.allCases.filter(\.canSkip)),
                       [.environment, .questionBank])
    }

    func testEveryStepHasChineseTitleBodyAndPrimaryAction() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) 没标题")
            XCTAssertFalse(step.body.isEmpty, "\(step) 没正文")
            XCTAssertFalse(step.primaryActionTitle.isEmpty, "\(step) 没有主按钮文案")
        }
    }

    func testEnvironmentStepTellsUserWhatHappensIfTheySkip() {
        // 跳过是允许的（设计文档第 7 节），但必须让他知道跳过之后是什么样子。
        XCTAssertTrue(OnboardingStep.environment.body.contains("半自动"),
                      "没说清跳过之后会怎样：\(OnboardingStep.environment.body)")
    }

    func testRecordingStepSaysItIsOffByDefault() {
        // 录音默认关、开启需明确同意（ROADMAP 第 5 节）。这一步必须说清楚。
        let body = OnboardingStep.recordingChoice.body
        XCTAssertTrue(body.contains("默认"), "没说默认状态：\(body)")
        XCTAssertTrue(body.contains("本机"), "没说录音只存在本机：\(body)")
    }

    // MARK: - 进度的存放

    func testStoreRoundTripsWithinOneVersion() {
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)

        XCTAssertEqual(store.completedVersion(), 0, "没记过就是 0，不能是别的什么")
        store.markCompleted(version: OnboardingFlow.currentVersion)
        XCTAssertEqual(store.completedVersion(), OnboardingFlow.currentVersion)
    }

    func testBumpingTheVersionMakesOldUsersSeeItAgain() {
        // 将来引导内容大改时，把 currentVersion 加 1，老用户会再看一次。
        // 不留这个口子的话，改了引导也没人看得到。
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.markCompleted(version: 1)

        XCTAssertTrue(store.completedVersion() >= 1)
        XCTAssertFalse(store.completedVersion() >= 2, "版本号涨了就该重新引导")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter OnboardingFlowTests`
Expected: 编译失败 —— `OnboardingFlow`、`OnboardingStep`、`UserDefaultsOnboardingStore` 未定义

- [ ] **Step 3: 实现步骤与流程**

`Sources/IELTSCoachUI/Onboarding/OnboardingFlow.swift`：

```swift
import Foundation

public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case environment
    case questionBank
    case recordingChoice
    case ready

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .environment: return "让它能替你操作 ChatGPT"
        case .questionBank: return "先把你的题库导进来"
        case .recordingChoice: return "要不要录下你的回答？"
        case .ready: return "可以开练了"
        }
    }

    public var body: String {
        switch self {
        case .welcome:
            return "这个工具替你打理练习前后的杂事：想今天练什么、输考官提示词、"
                + "把复盘和错题归档、记住上次的毛病。说英语的部分还是你自己来。\n"
                + "接下来三步，一分钟就能弄完。"
        case .environment:
            return "本工具靠系统的「辅助功能」权限替你操作 ChatGPT：新建会话、点开语音、"
                + "把考官提示词发过去、练完取回复盘。它不读你别的应用，也不上传任何东西。\n"
                + "你可以先跳过。跳过之后运行在半自动模式：提示词要你自己粘贴，复盘要你自己按 ⌘C，"
                + "其余功能照常。随时可以回到「关于」页重新开启。"
        case .questionBank:
            return "本工具不内置商业题库，只带原创样例——你的题库由你自己导入。\n"
                + "支持 CSV、JSON 和文字版 PDF（雅思季度题库通常是 PDF）。\n"
                + "现在没有也没关系，之后在「训练题库」页随时能导。"
        case .recordingChoice:
            return "开启后，练习时会用麦克风录下你的回答，练完能回听自己的发音、语调和卡顿。\n"
                + "这个开关默认关闭。录音只存在本机的数据目录里，不上传，随时可以单条删除。\n"
                + "只录你自己的声音，不录 ChatGPT——考官问了什么由逐字稿给文字。"
        case .ready:
            return "首页已经给你排好今天练什么了，点「开始」就行。\n"
                + "练完会自动归档复盘、错题、词汇和下次的重点目标，你只要关掉窗口。"
        }
    }

    public var primaryActionTitle: String {
        switch self {
        case .welcome: return "开始设置"
        case .environment: return "打开系统设置去授权"
        case .questionBank: return "现在导入题库…"
        case .recordingChoice: return "保持关闭"
        case .ready: return "开始使用"
        }
    }

    /// welcome / ready 只是叙述，没有可跳过的东西；
    /// recordingChoice 本身就是一个二选一（保持关闭也是一种选择），给「跳过」反而含糊。
    public var canSkip: Bool {
        switch self {
        case .environment, .questionBank: return true
        case .welcome, .recordingChoice, .ready: return false
        }
    }
}

public enum OnboardingFlow {
    /// 引导内容大改时把它加 1，老用户会再看一次。
    /// 不留这个口子的话，改了引导也没人看得到。
    public static let currentVersion = 1

    public static func steps(permission: PermissionState, questionCount: Int,
                             hasCompletedBefore: Bool) -> [OnboardingStep] {
        guard hasCompletedBefore else {
            var steps: [OnboardingStep] = [.welcome, .environment]
            // 题库已经有题（多半是把数据目录拷过来的），就别再让他导一次——
            // 那会让人怀疑自己的数据没拷成功。
            if questionCount == 0 { steps.append(.questionBank) }
            steps.append(.recordingChoice)
            steps.append(.ready)
            return steps
        }
        // 已经走过引导的人，只有一种情况会再看到它：环境不就绪。
        // 最典型的就是换了一台电脑——数据拷过来了，但辅助功能授权是本机 TCC 的，必须重给。
        return permission == .ready ? [] : [.environment]
    }

    public static func shouldPresent(permission: PermissionState, questionCount: Int,
                                     hasCompletedBefore: Bool) -> Bool {
        !steps(permission: permission, questionCount: questionCount,
               hasCompletedBefore: hasCompletedBefore).isEmpty
    }
}
```

`Sources/IELTSCoachUI/Onboarding/OnboardingProgressStore.swift`：

```swift
import Foundation

/// 「引导看过没有」存在哪里。
///
/// **刻意存本机 UserDefaults，不进数据目录。**
/// 数据目录里只放换机器时要跟着走的东西，而这个标记恰恰不该跟着走：
/// 换了机器，辅助功能授权是本机 TCC 的，必须重给一次，引导应该再出现。
/// 把它写进 state.json 的话，新机器上的用户一进来就没有引导，
/// 直接撞上一堵「点开始练习却报错」的墙——而他手上的数据看起来一切正常。
public protocol OnboardingProgressStore: AnyObject {
    /// 从没走完过就返回 0。
    func completedVersion() -> Int
    func markCompleted(version: Int)
}

public final class UserDefaultsOnboardingStore: OnboardingProgressStore {
    public static let key = "com.ielts.speakingcoach.onboardingCompletedVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func completedVersion() -> Int { defaults.integer(forKey: Self.key) }

    public func markCompleted(version: Int) { defaults.set(version, forKey: Self.key) }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter OnboardingFlowTests`
Expected: PASS（14 个测试）

- [ ] **Step 5: 突变验证（两条）**

**突变 A：** 把 `steps(...)` 最后一行
`return permission == .ready ? [] : [.environment]`
改成
`return []`
重跑：`testReturningUserWithoutAccessibilitySeesOnlyTheEnvironmentStep`、`testReturningUserWithoutChatGPTSeesTheEnvironmentStep`、`testReturningUserWithAnUnrecognizedFailureSeesTheEnvironmentStep` 三条必须同时变红。

**这条守的正是成品标准第 10 条真正落地的那一半**：把数据目录拷到新机器之后，题库和记录都在、界面一切正常，唯独辅助功能授权是本机的、必须重给。少了这一步，用户会对着一个「看起来好好的、点开始练习却报错」的 App 发呆。

**突变 B：** 把 `if questionCount == 0 { steps.append(.questionBank) }` 改成 `steps.append(.questionBank)`。
重跑：`testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere` 必须变红。

改回后确认全绿，把输出写进报告。

- [ ] **Step 6: 写引导界面并接进 RootView**

`WelcomeFlowView` 只给验收要求：

| 必须做到 | 判据 |
|---|---|
| 按 `OnboardingFlow.steps(...)` 逐步走 | 有「上一步 / 下一步」，显示 `第 N 步 / 共 M 步` |
| 每步显示 `title` / `body` / 主按钮 `primaryActionTitle` | 逐字来自 `OnboardingStep`，不得在视图里另写一套文案 |
| `canSkip == true` 的步骤才显示「先跳过」 | 由 `step.canSkip` 决定，不要写死 |
| `.environment` 这一步 | **复用 `PermissionGateView`**（Phase 3 Task 2），把 `AppState.permission` 与 `permissionMessages` 传给它。不要另写一套说同一件事的界面 |
| `.environment` 的主按钮 | 调 `NSWorkspace.shared.open(PermissionStatus.systemSettingsURL)`；旁边要有「重新检查」调 `app.recheckPermission()`，检查到就绪后自动前进一步 |
| `.questionBank` 的主按钮 | 走 `NSOpenPanel`，复用「训练题库」页已有的导入逻辑（含 PDF）。导入完成后显示导入了几题与全部 warnings |
| `.recordingChoice` | 一个开关，默认关。**开启时必须完整走 Phase 5 那条路**，见下面那段补注；保持关闭时 `settings` 一个字节都不动 |
| 走完最后一步或跳过 | 调 `store.markCompleted(version: OnboardingFlow.currentVersion)`，然后进主界面 |
| 全部走设计令牌与 Phase 3 的组件 | 视图里不得出现字面颜色、字号、圆角 |
| 尊重「减弱动态效果」 | `@Environment(\.accessibilityReduceMotion)` 打开时禁用步骤间的过渡动画 |

> ### ⚠️ `.recordingChoice` 不许自己写一遍开关逻辑（2026-08-06 跨阶段复审补入）
>
> 初稿写的是「用 `StateStore.mutate` 写 `settings.recordingEnabled = true` 与
> `settings.recordingConsentAt = ISO8601DateFormatter().string(from: Date())`」。
> **这么做会造出 Phase 5 明令禁止的那个状态**：开关显示「开」、但麦克风权限根本没申请过，
> 于是用户练完一场发现什么都没录，而且完全无从查起。Phase 5 计划开头那节
> 「这个阶段有一件事任何自动化都绕不过去」第 2 条原话是
> 「权限没拿到时，界面上的开关**必须停在「关」**」。
>
> 另外它也绕开了 `RecordingConsent.enable`，等于把「同意时间戳怎么记」这条规则实现了两遍。
>
> **正确做法**（与 Phase 5 Task 8 的 `RecordingSettingsViewModel.setEnabled(_:)` 完全一致）：
>
> 1. 先问权限：`MicrophoneAuthorizing.currentStatus()`；`.notDetermined` 时 `await requestAccess()`
> 2. 拿到 `.granted` 才写盘，且写盘走
>    `try store.mutate { $0.settings = RecordingConsent.enable($0.settings, at: 时间戳) }`
> 3. 没拿到 `.granted` → **开关弹回「关」**，并把 `MicrophonePermissionState.guidance` 显示出来
>
> **更省事也更不容易出错的做法：直接把 Phase 5 的 `RecordingSettingsView` 嵌进这一步**，
> 它已经把上面三条连同占用提示一起做完了。这样引导页与设置窗口永远说同一句话。
>
> 若 Phase 5 尚未交付（`ls Sources/IELTSCoachCore/Recording/` 为空），
> **这一步整步跳过，不要用初稿那种写法顶上**——录音开关宁可暂时没有，也不能是假的。

`RootView` 的改动：把原来「`app.permission != .ready && !app.permissionSkipped` 就显示 `PermissionGateView`」这个顶层分支，换成

```
if OnboardingFlow.shouldPresent(permission: app.permission,
                                questionCount: app.state.questions.count,
                                hasCompletedBefore: store.completedVersion() >= OnboardingFlow.currentVersion)
   && !dismissedThisLaunch {
    WelcomeFlowView(...)
} else {
    NavigationSplitView { ... }
}
```

`dismissedThisLaunch` 是一个 `@State` 布尔量，作用是「这次启动里已经跳过了，别在权限还没给的情况下又弹回来」——**跳过之后本次启动内不再打扰，下次启动若权限仍缺会再问一次**，理由见本任务开头第二条。

- [ ] **Step 7: 人工验证引导**

```bash
defaults delete com.ielts.speakingcoach 2>/dev/null || true
./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

`defaults delete` 把「看过引导」的标记清掉，等价于全新安装。

Expected:
1. 出现欢迎页，能一路走到「可以开练了」
2. 「环境」那一步点「打开系统设置」真的跳到 隐私与安全性 › 辅助功能
3. 「先跳过」能直接进主界面，且主界面可用（半自动模式）
4. 走完之后重新打开 App，**不再出现引导**
5. 到系统设置里把本 App 的辅助功能勾去掉，再打开 App：**只出现「环境」一步**，不是从欢迎页从头来

第 5 条就是换机器场景的本地等价物，务必真做一次。

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachUI/Onboarding/ Sources/IELTSCoachUI/RootView.swift Tests/IELTSCoachUITests/OnboardingFlowTests.swift
git commit -m "feat(ui): 首次使用引导"
```

---

## Task 9: 分发包与公证脚本（本期不执行公证）

**Files:**
- Create: `packaging/open-instructions.txt`
- Create: `scripts/package-app.sh`
- Create: `scripts/notarize.sh`
- Create: `Tests/PackagingTests/NotarizeScriptTests.swift`
- Create: `Tests/PackagingTests/PackagingContractTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `scripts/build-app.sh`（认 `IELTS_SIGN_IDENTITY` / `IELTS_SIGNATURE_CHANNEL`）、`packaging/IELTSCoach.entitlements`、`packaging/expected-designated-requirement.txt`
- Produces:
  - `.build/dist/IELTS Speaking Coach.zip` + `.build/dist/如何打开.txt`
  - `scripts/notarize.sh`：`--dry-run`（默认）/ `--execute` / `--help`
  - 测试 target `PackagingTests`（**不依赖任何产品代码**）

**本期不购买 Developer ID，也不实际执行公证**（设计文档第 10 节）。这个脚本存在的意义是：把「将来要怎么做」写成**可以直接跑、而且有测试守着**的东西，而不是写成一段没人验证过的文档。文档会烂，能跑的脚本不会。

### 换 Developer ID 会让辅助功能授权失效一次——这必须写在脚本里

Developer ID 是另一张证书，「指定要求」里的 `certificate leaf = H"…"` 会跟着变。系统会把重签后的 App 当成另一个程序，本机的辅助功能授权当场失效，得回系统设置重新勾一次，并且要把新的指定要求写进 `packaging/expected-designated-requirement.txt`（否则 `build-app.sh` 会一直拦着不让打包）。

**这一次失效躲不掉，但它只发生一次，而且只影响开发者自己这台机器**——拿到公证版本的其他人本来就要自己授权一次。脚本必须在动手前把这段话打出来。

- [ ] **Step 1: 写「如何打开」说明**

`packaging/open-instructions.txt`：

```
IELTS Speaking Coach —— 第一次打开怎么弄

1. 把「IELTS Speaking Coach.app」拖进「应用程序」文件夹。

2. 双击它。系统大概率会说「无法打开，因为 Apple 无法验证其是否包含恶意软件」。

   发生了什么：这个 App 是用作者本机的证书签名的，没有购买 Apple 开发者账号
   做「公证」。Apple 对所有未公证的 App 都会这么提示，与它本身是否安全无关。

   下一步：打开「系统设置」›「隐私与安全性」，往下翻到「安全性」一节，
   会看到一行「已阻止使用 IELTS Speaking Coach」，点它旁边的「仍要打开」，
   再确认一次即可。

   （旧版 macOS 也可以在「应用程序」里按住 Control 点它 →「打开」→「打开」。
     macOS 15 起 Apple 收紧了这条路径，若找不到这个入口，就走上面的系统设置。）

3. 第一次打开会请你授予「辅助功能」权限。

   它用来替你操作 ChatGPT：新建会话、点开语音、把考官提示词发过去、
   练完取回复盘。不读你别的应用，也不上传任何东西。
   你可以先跳过，跳过后运行在半自动模式：提示词自己粘、复盘自己按 ⌘C。

4. 需要先装好新版 ChatGPT 桌面应用（不是 ChatGPT Classic，Classic 没有语音）。

5. 你的数据存在这里：
   ~/Library/Application Support/IELTS Speaking Coach/
   换电脑时把这个文件夹整个拷过去就能接着用。备份就是拷贝它。

6. 卸载：把 App 拖进废纸篓即可。上面那个数据文件夹要不要留，你自己决定。
```

- [ ] **Step 2: 写 `scripts/package-app.sh`**

```bash
#!/bin/bash
set -euo pipefail

# 把签好名的 .app 打成一个可以直接发给别人的 zip。
#
# 必须用 ditto，不能用 zip：zip 不保留 macOS 的扩展属性，解压出来的
# .app 签名会坏掉，对方那边表现为「已损坏，应将其移到废纸篓」——
# 比「未公证」还吓人，而且完全是打包方式造成的。
# 脚本打完会自己解压回来验一次签名，确认这条没被破坏。

APP_NAME="IELTS Speaking Coach"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/.build/dist"
ZIP="$DIST/$APP_NAME.zip"

echo "▶︎ 先打包并签名…"
"$ROOT/scripts/build-app.sh"

echo "▶︎ 生成分发目录…"
rm -rf "$DIST"
mkdir -p "$DIST"
cp "$ROOT/packaging/open-instructions.txt" "$DIST/如何打开.txt"

echo "▶︎ 压缩（ditto，保留签名所需的扩展属性）…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ 自检：把 zip 解回来验签名…"
VERIFY_DIR="$DIST/.verify"
rm -rf "$VERIFY_DIR"; mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
if ! codesign --verify --strict "$VERIFY_DIR/$APP_NAME.app" 2>/dev/null; then
    echo "❌ 压缩包里的签名坏了。"
    echo "   发生了什么：打包过程破坏了 .app 的扩展属性，"
    echo "   对方解压后会看到「已损坏，应将其移到废纸篓」。"
    echo "   下一步：确认这里用的是 ditto -c -k --keepParent，不是 zip -r。"
    exit 1
fi
rm -rf "$VERIFY_DIR"

echo
echo "✅ 可以发出去了："
echo "   $ZIP"
echo "   $DIST/如何打开.txt"
echo "   大小 $(du -h "$ZIP" | cut -f1)"
echo "   SHA256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "ℹ️  这份包没有经过 Apple 公证，对方第一次打开会被系统拦下。"
echo "   「如何打开.txt」里已经写清了怎么办，记得一起发过去。"
```

- [ ] **Step 3: 写 `scripts/notarize.sh`**

```bash
#!/bin/bash
set -euo pipefail

# 公证脚本。
#
# **本期不购买 Developer ID，也不实际执行公证**（设计文档第 10 节）。
# 这个脚本存在的意义是把「将来要怎么做」写成可以直接跑、而且有测试守着的东西，
# 而不是写成一段没人验证过的文档。默认 --dry-run：只检查前置条件、
# 原样打印将来要跑的每条命令，一个文件都不动。
#
# 用法：
#   ./scripts/notarize.sh            # 等同 --dry-run
#   ./scripts/notarize.sh --execute  # 真的公证（需要 Developer ID 与钥匙串凭据）

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/$APP_NAME.app"
ZIP="$ROOT/.build/dist/$APP_NAME.zip"
ENTITLEMENTS="$ROOT/packaging/IELTSCoach.entitlements"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

# 形如 "Developer ID Application: 你的名字 (TEAMID)"
DEV_ID="${IELTS_DEVELOPER_ID:-}"
# xcrun notarytool store-credentials 存进钥匙串的档案名
PROFILE="${IELTS_NOTARY_PROFILE:-}"

MODE="dry-run"
for arg in "$@"; do
    case "$arg" in
        --dry-run) MODE="dry-run" ;;
        --execute) MODE="execute" ;;
        -h|--help) MODE="help" ;;
        *)
            echo "❌ 不认识的参数「$arg」。"
            echo "   下一步：只能传 --dry-run（默认）、--execute 或 --help。"
            exit 2
            ;;
    esac
done

if [[ "$MODE" == "help" ]]; then
    sed -n '3,20p' "$0"
    exit 0
fi

echo "════════════════════════════════════════════════════════════"
echo " 公证（模式：$MODE）"
echo "════════════════════════════════════════════════════════════"
echo
echo "⚠️  换成 Developer ID 证书会改变签名的「指定要求」。"
echo "   发生了什么：指定要求里带着证书指纹，换了证书它就变了，"
echo "   系统会把重签后的 App 当成另一个程序——本机已授予的辅助功能授权会失效。"
echo "   下一步（公证完成后立刻做这两件事）："
echo "     1. 把新的指定要求写进 packaging/expected-designated-requirement.txt 并提交，"
echo "        否则 build-app.sh 会一直拦着不让打包。"
echo "     2. 到 系统设置 › 隐私与安全性 › 辅助功能，删掉旧条目，重新勾选一次。"
echo "   这一次失效躲不掉，但只发生一次，而且只影响你自己这台开发机。"
echo

# ── 前置条件 ────────────────────────────────────────────────
# 顺序有意义：先查最难补的（证书要加入 Apple Developer Program，按年付费、还要等审核），
# 再查随手就能补的（.app 重打一次就有）。

MISSING=0

check() {   # $1=是否满足(0/1)  $2=名称  $3=发生了什么  $4=下一步
    if [[ "$1" -eq 0 ]]; then
        echo "✅ $2"
    else
        echo "⚠️  $2"
        echo "   $3"
        echo "   下一步：$4"
        MISSING=1
    fi
}

if [[ -n "$DEV_ID" ]]; then HAS_ENV=0; else HAS_ENV=1; fi
check $HAS_ENV "Developer ID 证书名（环境变量 IELTS_DEVELOPER_ID）" \
    "没设置。公证必须用 Apple 签发的 Developer ID Application 证书，自签名证书不行。" \
    "先加入 Apple Developer Program（按年付费），在 developer.apple.com 申请并下载
   「Developer ID Application」证书装进钥匙串，然后
   export IELTS_DEVELOPER_ID=\"Developer ID Application: 你的名字 (TEAMID)\""

if [[ -n "$DEV_ID" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEV_ID"; then
    HAS_CERT=0
else
    HAS_CERT=1
fi
check $HAS_CERT "该证书在钥匙串里且可用于签名" \
    "security find-identity 里找不到它。" \
    "双击下载来的 .cer 装进 login 钥匙串；确认它连着私钥（钥匙串里能展开出一条私钥）。"

if xcrun --find notarytool >/dev/null 2>&1; then HAS_TOOL=0; else HAS_TOOL=1; fi
check $HAS_TOOL "xcrun notarytool 可用" \
    "找不到 notarytool，它随 Xcode 提供。" \
    "安装 Xcode，然后 sudo xcode-select -s /Applications/Xcode.app"

if [[ -n "$PROFILE" ]]; then HAS_PROFILE=0; else HAS_PROFILE=1; fi
check $HAS_PROFILE "公证凭据档案名（环境变量 IELTS_NOTARY_PROFILE）" \
    "没设置。凭据必须先存进钥匙串，本脚本不接受把密码写在命令行上。" \
    "xcrun notarytool store-credentials \"ielts-notary\" --apple-id <你的 Apple ID>
   --team-id <TEAMID> --password <App 专用密码>
   注意那是在 appleid.apple.com 生成的「App 专用密码」，不是你的 Apple ID 登录密码。
   存好之后 export IELTS_NOTARY_PROFILE=ielts-notary"

if [[ -d "$APP" ]]; then HAS_APP=0; else HAS_APP=1; fi
check $HAS_APP "已有打好的 .app" \
    "找不到 $APP。" \
    "先跑 ./scripts/package-app.sh"

DEV_ID_DISPLAY="${DEV_ID:-<Developer ID Application: 你的名字 (TEAMID)>}"
PROFILE_DISPLAY="${PROFILE:-<你的公证凭据档案名>}"

echo
cat <<EOF
公证流程（共 5 步）：

  1. 用 Developer ID 证书重新签名（Hardened Runtime + entitlements + 安全时间戳）
       IELTS_SIGN_IDENTITY="$DEV_ID_DISPLAY" \\
       IELTS_SIGNATURE_CHANNEL=developer-id \\
       ./scripts/build-app.sh
       codesign --force --sign "$DEV_ID_DISPLAY" --identifier $BUNDLE_ID \\
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"
     （公证要求安全时间戳，所以这一步用 --timestamp 而不是本地打包的 --timestamp=none）

  2. 压成 zip —— 必须用 ditto，zip 命令会破坏签名所需的扩展属性
       ditto -c -k --keepParent "$APP" "$ZIP"

  3. 提交公证并等结果（通常几分钟）
       xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE_DISPLAY" --wait
     失败时用 xcrun notarytool log <submission-id> --keychain-profile "$PROFILE_DISPLAY"
     看具体是哪个二进制不合规。

  4. 把公证票据钉进 .app（钉过之后对方离线也能通过校验）
       xcrun stapler staple "$APP"

  5. 用系统自己的判定确认真的成了
       spctl -a -vvv -t exec "$APP"
     期望看到 accepted，且 source=Notarized Developer ID
     （现在这份自签名的包在这里是 rejected，那是正常的、也是必然的）

  公证完成后别忘了更新 $BASELINE，并重新授权辅助功能。
EOF

if [[ "$MODE" == "dry-run" ]]; then
    echo
    echo "（--dry-run：以上命令一条都没有执行，也没有改动任何文件。）"
    exit 0
fi

if [[ $MISSING -ne 0 ]]; then
    echo
    echo "❌ 前置条件没满足，不执行公证。"
    echo "   下一步：把上面标了 ⚠️ 的几条按提示补齐，再跑一次 --execute。"
    exit 1
fi

echo
echo "▶︎ 1/5 用 Developer ID 重新签名…"
IELTS_SIGN_IDENTITY="$DEV_ID" IELTS_SIGNATURE_CHANNEL=developer-id "$ROOT/scripts/build-app.sh"
codesign --force --sign "$DEV_ID" --identifier "$BUNDLE_ID" \
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"

echo "▶︎ 2/5 压缩…"
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ 3/5 提交公证（可能要等几分钟）…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▶︎ 4/5 钉票据…"
xcrun stapler staple "$APP"

echo "▶︎ 5/5 用系统判定确认…"
spctl -a -vvv -t exec "$APP"

echo
echo "✅ 公证完成。"
echo "   下一步：把新的指定要求写进 $BASELINE 并提交，"
echo "   然后到 系统设置 › 隐私与安全性 › 辅助功能 重新勾选一次。"
```

- [ ] **Step 4: 加 `PackagingTests` target**

`Package.swift` 的 `targets:` 数组末尾加一行：

```swift
        .testTarget(name: "PackagingTests")
```

它**不依赖任何产品代码**——守的是脚本与工程配置的契约，不是 Swift 逻辑。

- [ ] **Step 5: 写失败的测试**

`Tests/PackagingTests/NotarizeScriptTests.swift`：

```swift
import XCTest

/// 守打包脚本的契约。不依赖任何产品代码。
final class NotarizeScriptTests: XCTestCase {

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)     // Tests/PackagingTests/NotarizeScriptTests.swift
            .deletingLastPathComponent()     // Tests/PackagingTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // 仓库根
    }

    private struct Result { let status: Int32; let output: String }

    /// 用干净的环境跑脚本。
    /// 不继承开发机上可能已经设好的 IELTS_* 变量——否则这些测试在
    /// 「配好了证书的机器」和「没配的机器」上会得出不同结论，那种测试等于没有。
    private func run(_ script: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.repositoryRoot.appending(path: script).path] + arguments
        process.currentDirectoryURL = Self.repositoryRoot
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // 必须先读完再 wait，否则管道写满会死锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(data: data, encoding: .utf8) ?? "")
    }

    func testDryRunSucceedsWithoutAnyDeveloperIDAtAll() throws {
        // 本期不买 Developer ID。dry-run 必须在这台什么都没配的机器上跑得通，
        // 否则这个「预留」就是一段没人验证过的死文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertEqual(result.status, 0, "dry-run 应该退出 0：\n\(result.output)")
    }

    func testDefaultModeIsDryRunSoItNeverDoesAnythingByAccident() throws {
        let result = try run("scripts/notarize.sh", [])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("一条都没有执行"),
                      "不带参数时必须是 dry-run，且要说清什么都没做：\n\(result.output)")
    }

    func testDryRunSpellsOutEveryStepOfTheProcedure() throws {
        // 这五步就是「将来怎么做」的全部内容。少一步，将来那天就要现查文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        for needle in ["codesign", "--options runtime", "--entitlements",
                       "ditto -c -k", "notarytool submit", "stapler staple", "spctl"] {
            XCTAssertTrue(result.output.contains(needle),
                          "公证流程里缺了「\(needle)」：\n\(result.output)")
        }
    }

    func testDryRunWarnsThatSwitchingCertificateBreaksTheAccessibilityGrant() throws {
        // 这是换证书那天最容易被忘、后果又最烦人的一件事。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("辅助功能"),
                      "没警告辅助功能授权会失效：\n\(result.output)")
        XCTAssertTrue(result.output.contains("expected-designated-requirement.txt"),
                      "没提醒要同步更新签名基线，那会让 build-app.sh 从此一直报错：\n\(result.output)")
    }

    func testEveryMissingPreconditionComesWithANextStep() throws {
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("下一步"),
                      "缺东西时必须说下一步做什么：\n\(result.output)")
        XCTAssertTrue(result.output.contains("Developer ID"),
                      "至少要点名缺的是 Developer ID：\n\(result.output)")
    }

    func testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping() throws {
        // 静默跳过是本项目最危险的失败形态：以为公证了，其实什么都没发生。
        let result = try run("scripts/notarize.sh", ["--execute"])
        XCTAssertNotEqual(result.status, 0,
                          "没有凭据却退出 0，等于静默跳过公证：\n\(result.output)")
        XCTAssertTrue(result.output.contains("不执行公证"),
                      "要说清它没做什么：\n\(result.output)")
    }

    func testUnknownArgumentIsRejectedRatherThanIgnored() throws {
        // 参数打错被忽略，用户会以为自己 --execute 了。
        let result = try run("scripts/notarize.sh", ["--yolo"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("下一步"))
    }
}
```

`Tests/PackagingTests/PackagingContractTests.swift`：

```swift
import XCTest

final class PackagingContractTests: XCTestCase {

    private var root: URL { NotarizeScriptTests.repositoryRoot }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    func testAllPackagingScriptsAreExecutable() {
        // Task 10 会往这个列表里补 verify-portability.sh。
        for script in ["build-app.sh", "verify-signature-stability.sh",
                       "package-app.sh", "notarize.sh", "make-icon.sh"] {
            let path = root.appending(path: "scripts/\(script)").path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path),
                          "scripts/\(script) 没有可执行位——别人 clone 下来会直接跑不了")
        }
    }

    func testEntitlementsContainTheMicrophoneAndNothingElseUnjustified() throws {
        let entitlements = try text(at: "packaging/IELTSCoach.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"),
                      "缺了麦克风 entitlement，Hardened Runtime 下录音会被系统直接拒掉")

        // 下面这几条是「Hardened Runtime 报错时最容易被顺手粘上来」的。
        // 每一条都会实打实削弱 Hardened Runtime，而本项目一条都不需要
        // （实测 otool -L 显示只链接系统库；沙盒会让辅助功能驱动整个失效）。
        for forbidden in ["com.apple.security.app-sandbox",
                          "com.apple.security.cs.disable-library-validation",
                          "com.apple.security.cs.allow-unsigned-executable-memory",
                          "com.apple.security.cs.disable-executable-page-protection",
                          "com.apple.security.cs.allow-dyld-environment-variables"] {
            XCTAssertFalse(entitlements.contains(forbidden),
                           "多了一条不该有的 entitlement：\(forbidden)。"
                           + "若它真的必要，先在计划里写明为什么，再改这条测试。")
        }
    }

    func testDesignatedRequirementBaselineIsRecordedAndNotAdHoc() throws {
        let baseline = try text(at: "packaging/expected-designated-requirement.txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(baseline.hasPrefix("designated =>"),
                      "基线文件格式不对，应当就是 codesign -d -r- 输出的那一行：\(baseline)")
        XCTAssertTrue(baseline.contains("identifier \"com.ielts.speakingcoach\""),
                      "基线里的 bundle id 变了。辅助功能授权绑的就是它，任何阶段都不得更改。")
        XCTAssertTrue(baseline.contains("certificate leaf"),
                      "基线里没有证书条件，说明用的不是固定证书。")
        XCTAssertFalse(baseline.lowercased().contains("cdhash"),
                       "基线是 cdhash 形式，说明用了 ad-hoc 签名——"
                       + "cdhash 每次编译都变，用户的辅助功能授权会反复失效。")
    }

    func testProjectStillHasNoThirdPartyDependencies() throws {
        // 关于页的致谢里写着「第三方依赖：没有」。加了依赖却不改那句话，
        // 就变成了一句假话，而且没人会注意到。
        let manifest = try text(at: "Package.swift")
        XCTAssertFalse(manifest.contains(".package("),
                       "工程新增了第三方依赖。下一步：要么撤掉它，"
                       + "要么把它加进 AboutViewModel.acknowledgements 并改掉「没有第三方依赖」那句话。")
    }

    func testOpenInstructionsCoverGatekeeperAndTheDataDirectory() throws {
        // 这份说明是随包发出去的，收件人只有它。少一条他就卡住了。
        let instructions = try text(at: "packaging/open-instructions.txt")
        XCTAssertTrue(instructions.contains("仍要打开"), "没写怎么绕过 Gatekeeper")
        XCTAssertTrue(instructions.contains("辅助功能"), "没写要授予什么权限")
        XCTAssertTrue(instructions.contains("Application Support/IELTS Speaking Coach"),
                      "没写数据存在哪儿——换电脑和备份都靠它")
    }
}
```

- [ ] **Step 6: 运行，确认失败**

Run: `swift test --filter PackagingTests`
Expected: 失败 —— 脚本还没 `chmod +x`、或 `PackagingTests` target 还没建好

- [ ] **Step 7: 让它们通过**

```bash
chmod +x scripts/package-app.sh scripts/notarize.sh
```

Run: `swift test --filter PackagingTests`
Expected: PASS（11 个测试）

Run: `./scripts/package-app.sh`
Expected: 产出 `.build/dist/IELTS Speaking Coach.zip` 与 `如何打开.txt`，自检通过，打印大小与 SHA256

Run: `./scripts/notarize.sh`
Expected: 打印全部五步，前置条件里 Developer ID 与凭据显示 ⚠️（本期就是没有），退出 0

Run: `./scripts/notarize.sh --execute; echo "exit=$?"`
Expected: 打印 `❌ 前置条件没满足，不执行公证。`，`exit=1`

- [ ] **Step 8: 突变验证（两条）**

**突变 A：** 把 `notarize.sh` 里 `--execute` 分支的
`if [[ $MISSING -ne 0 ]]; then … exit 1; fi`
整段删掉，重跑 `swift test --filter NotarizeScriptTests`。
Expected: `testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping` 变红（脚本会带着空的 `$DEV_ID` 往下走）。改回后确认全绿。

**这条守的是本项目最危险的失败形态**：以为公证了，其实什么都没发生，直到把包发给别人才知道。

**突变 B：** 往 `packaging/IELTSCoach.entitlements` 里加一条
`<key>com.apple.security.cs.disable-library-validation</key><true/>`，
重跑 `swift test --filter PackagingContractTests`。
Expected: `testEntitlementsContainTheMicrophoneAndNothingElseUnjustified` 变红。删掉后确认全绿。

**这条守的是「Hardened Runtime 一报错就顺手粘一条 entitlement 上去」**——那是网上搜到的第一条建议，而本项目实测过 `otool -L` 只链接系统库，一条都不需要。

- [ ] **Step 9: 提交**

```bash
git add Package.swift packaging/open-instructions.txt scripts/package-app.sh scripts/notarize.sh Tests/PackagingTests/
git commit -m "feat(packaging): 分发包与公证脚本（预留，不执行）"
```

---

## Task 10: 「换了一台电脑」的自动化验证

**Files:**
- Create: `scripts/verify-portability.sh`
- Modify: `Tests/PackagingTests/PackagingContractTests.swift`

**Interfaces:**
- Consumes: `./.build/debug/coach portability`（Task 4）、`./.build/debug/coach questions list`、环境变量 `IELTS_SPEAKING_DATA_DIR`（`DataDirectory.resolve()` 认它）
- Produces: `scripts/verify-portability.sh`，退出 0 表示「拷过去能接着用，且这个结论不是蒙的」

**这一条兑现成品标准第 10 条。** 手工去另一台电脑上试一次是必要的（Task 11 会做），但那件事一年做不了几次；每天都在改代码的是这台机器，所以还需要一个能天天跑的版本。

**脚本的关键设计有两处，缺任何一处这个验证都是假的：**

1. **拷完之后把「原来那台机器」整个删掉。** 不删的话，就算代码里存的是绝对路径，它照样能读到原目录的文件，验证会通过——而真换机器时那些路径根本不存在。**这一步是这个脚本里唯一真正制造压力的地方。**
2. **必须带一个负例。** 造一份故意存了绝对路径的数据目录，断言 `coach portability` 一定要退出非零。没有负例的话，一个永远返回「没问题」的实现也能让脚本全绿。

- [ ] **Step 1: 写脚本**

`scripts/verify-portability.sh`：

```bash
#!/bin/bash
set -euo pipefail

# 验证「把数据目录拷到另一台电脑就能接着用」（成品标准第 10 条）。
#
# 关键设计有两处，缺任何一处这个验证都是假的：
#   1. 拷完之后把「原来那台机器」的目录整个删掉。不删的话，就算代码里存的是
#      绝对路径也能读到原目录，验证照样通过——而真换机器时那些路径根本不存在。
#   2. 必须带一个负例（故意存绝对路径的数据目录），断言检查一定要报错。
#      没有负例的话，一个永远返回「没问题」的实现也能让这个脚本全绿。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COACH="$ROOT/.build/debug/coach"

if [[ ! -x "$COACH" ]]; then
    echo "❌ 找不到 $COACH"
    echo "   下一步：先跑 swift build，再跑这个脚本。"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# $1 = 目录，$2 = 写进 reportPath 的内容
make_fixture() {
    local dir="$1" report_path="$2"
    mkdir -p "$dir/reports" "$dir/recordings"
    printf '{"must_correct":[]}' > "$dir/reports/s1.json"
    printf 'fake-audio'          > "$dir/recordings/s1.m4a"
    cat > "$dir/state.json" <<STATE
{
  "schemaVersion": 3,
  "learner": { "displayName": "", "createdAt": "2026-08-06T00:00:00Z" },
  "currentSession": null,
  "sessions": [
    {
      "id": "s1",
      "questionId": "q1",
      "focusPart": "Part 1",
      "startedAt": "2026-08-06T00:00:00Z",
      "endedAt": "2026-08-06T00:10:00Z",
      "goal": "",
      "transcript": [],
      "reportPath": "$report_path",
      "recordingPath": "recordings/s1.m4a"
    }
  ],
  "targets": [],
  "issues": [],
  "vocabulary": [],
  "plan": null,
  "questions": [
    { "id": "q1", "part": 1, "topic": "Home", "prompt": "Do you live in a house or a flat?" }
  ],
  "questionSources": [],
  "settings": { "recordingEnabled": false, "recordingConsentAt": "" },
  "questionCursor": { "part1": 0, "part2": 0, "part3": 0 }
}
STATE
}

echo "▶︎ 正例：造一份全用相对路径的数据目录…"
ORIGINAL="$WORK/machine-a"
COPY="$WORK/machine-b"
make_fixture "$ORIGINAL" "reports/s1.json"

echo "▶︎ 拷到「另一台电脑」，然后把原来那台整个删掉…"
cp -R "$ORIGINAL" "$COPY"
rm -rf "$ORIGINAL"

echo "▶︎ 在「另一台电脑」上检查…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" portability; then
    echo "❌ 拷过去之后检查没通过。"
    echo "   发生了什么：数据目录里有依赖原机器的东西，换电脑就断。"
    echo "   下一步：看上面每一条给出的位置与提示，逐条修写入这些字段的代码。"
    exit 1
fi

echo "▶︎ 确认题库真的读得到…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" questions list | grep -qF "[q1]"; then
    echo "❌ 拷过去之后读不到题库。"
    echo "   下一步：确认 state.json 跟着拷过来了，且 DataDirectory.resolve() 认 IELTS_SPEAKING_DATA_DIR。"
    exit 1
fi

echo "▶︎ 确认复盘文件真的跟过来了…"
if [[ ! -f "$COPY/reports/s1.json" ]]; then
    echo "❌ reports/ 没跟着过来。下一步：检查这个脚本的 cp -R 是不是漏了子目录。"
    exit 1
fi

echo
echo "▶︎ 负例：造一份故意存绝对路径的数据目录，检查必须把它揪出来…"
BAD="$WORK/machine-bad"
make_fixture "$BAD" "$WORK/somewhere-else/reports/s1.json"
if IELTS_SPEAKING_DATA_DIR="$BAD" "$COACH" portability > "$WORK/bad.log" 2>&1; then
    echo "❌ 负例没有被检出。"
    echo "   发生了什么：数据目录里存着绝对路径，检查却说「没问题」——"
    echo "   这说明上面那个正例的绿灯毫无意义，它对任何实现都会亮。"
    echo "   下一步：检查 DataPortabilityAudit.audit 是不是被改成了永远返回空。"
    cat "$WORK/bad.log"
    exit 1
fi
if ! grep -q "下一步" "$WORK/bad.log"; then
    echo "❌ 负例报出来了，但没告诉用户下一步做什么。"
    cat "$WORK/bad.log"
    exit 1
fi

echo
echo "✅ 数据目录可以整个拷到另一台电脑接着用（成品标准第 10 条）。"
echo "   正例：删掉原目录后仍然读得到题库与复盘。"
echo "   负例：存了绝对路径的目录被正确揪出，并给出了下一步。"
```

- [ ] **Step 2: 跑一次，确认通过**

Run: `chmod +x scripts/verify-portability.sh && swift build && ./scripts/verify-portability.sh`
Expected: 正例与负例都通过，最后打印 `✅ 数据目录可以整个拷到另一台电脑接着用…`

- [ ] **Step 3: 把它加进可执行位检查**

在 `Tests/PackagingTests/PackagingContractTests.swift` 的 `testAllPackagingScriptsAreExecutable` 里，把 `"verify-portability.sh"` 加进列表，并删掉那条 `// Task 10 会往这个列表里补…` 的注释。

Run: `swift test --filter PackagingContractTests`
Expected: PASS

- [ ] **Step 4: 突变验证（两条）**

**突变 A —— 让「换机器」变成假的：**
把 `verify-portability.sh` 里的 `rm -rf "$ORIGINAL"` 删掉，然后把 `make_fixture "$ORIGINAL" "reports/s1.json"` 的第二个参数改成 `"$ORIGINAL/reports/s1.json"`（绝对路径），重跑。
Expected: 正例仍会被 `coach portability` 判为失败并退出 1（因为审计看的是路径写法，不是文件在不在）。**改回后**再验一次真正的对照：把审计里的绝对路径规则临时去掉（见突变 B），正例就会通过——这说明 `rm -rf` 那一步配合负例才是真正的压力来源。

**突变 B —— 让审计永远说没问题：**
把 `DataPortabilityAudit.audit(state:)` 的函数体改成 `return []`，重跑 `./scripts/verify-portability.sh`。
Expected: 停在 `❌ 负例没有被检出。`，退出 1。改回后重跑必须通过。

**这条守的是「这个脚本不是在自我恭维」**——没有负例的话，一个什么都不检查的实现照样能让它全绿，而那正是本项目消灭过 15 次的那种测试。

把两次输出写进报告。

- [ ] **Step 5: 提交**

```bash
git add scripts/verify-portability.sh Tests/PackagingTests/PackagingContractTests.swift
git commit -m "feat(packaging): 数据目录搬迁的自动化验证"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase10-acceptance.md`

前面所有测试证明的是「逻辑对」和「脚本会拦」。下面这些只有人能判断，而且其中三项**必须在第二台电脑上做**。

- [ ] **Step 1: 全量回归**

Run: `time swift test`
Expected: 全绿，总耗时 2 秒以内（Phase 3 Task 10 定的预算）。若 `PackagingTests` 把总时长顶到 2 秒以上，记录实际数字并说明是哪几条测试占的——不要为了好看去删断言。

Run: `./scripts/verify-portability.sh`
Expected: 正例与负例都通过

- [ ] **Step 2: 签名稳定性（本阶段最关键的一条）**

Run: `./scripts/verify-signature-stability.sh`
Expected: `✅ 连打两次，「指定要求」完全一致，且与基线相符`

然后**不重新授权**直接打开 App：

Run: `open ".build/IELTS Speaking Coach.app"`
Expected: 仍然显示「环境就绪」，不再要求去系统设置勾选。

**若又要求重新授权，立刻停下并报告。** 那说明加了 Hardened Runtime 之后签名不稳定了，整个打包方案要重做——这一条一票否决，后面的验收都没有意义。

- [ ] **Step 3: 关于页逐项核对**

| 看什么 | 判据 |
|---|---|
| 版本 | 与 `Info.plist` 里的 `CFBundleShortVersionString`、`CFBundleVersion` 一致 |
| 提交 | 与 `git rev-parse --short HEAD` 一致 |
| 标识 | `com.ielts.speakingcoach` |
| 签名 | 「自签名（未经 Apple 公证）」，且说清了别人怎么打开 |
| 辅助功能 | 与实际状态一致；去系统设置里取消勾选后点「重新检查」，这一行要跟着变 |
| 数据目录 | 路径正确，「在访达中显示」能打开对的文件夹 |
| 数据可搬迁检查 | 用你**真实的**数据目录跑，看它说什么。**若报了问题，把每一条都记下来——那是真 bug，不是审计写错了** |
| 致谢与许可 | 逐条读一遍，有没有说得不准的地方 |
| 复制诊断信息 | `pbpaste` 之后逐行读，确认没有任何练习内容、姓名、逐字稿 |

- [ ] **Step 4: 首次引导（清标记重来一遍）**

```bash
defaults delete com.ielts.speakingcoach 2>/dev/null || true
open ".build/IELTS Speaking Coach.app"
```

| 看什么 | 判据 |
|---|---|
| 欢迎 → 环境 → 录音 → 完成 | 因为你的题库非空，**不该出现「导入题库」那一步** |
| 每一步的文案 | 找一个不懂技术的人读一遍，他知不知道要干什么 |
| 「先跳过」 | 点了能直接进主界面，且主界面可用 |
| 走完之后重开 App | 不再出现引导 |
| 去系统设置取消辅助功能勾选，重开 App | **只出现「环境」一步**，不是从欢迎页重来 |

最后一条是换机器场景的本地等价物，务必真做。

- [ ] **Step 5: 把 `.app` 给别人（成品标准之外，但这是本阶段的交付定义）**

```bash
./scripts/package-app.sh
```

然后在**另一台 Mac**（或另一个 macOS 用户账号）上：

1. 通过会打上隔离属性的方式传过去（AirDrop、邮件、下载链接都行；`cp` 到共享盘不会打隔离属性，那样测不出 Gatekeeper）
2. 解压、拖进「应用程序」、双击
3. 按「如何打开.txt」的步骤走一遍

| 看什么 | 判据 |
|---|---|
| 是否被 Gatekeeper 拦下 | 应该会（自签名未公证，实测 `spctl` 判定 rejected） |
| 按说明能不能打开 | **能。若说明里的路径在这台机器的系统版本上不存在，把实际路径记下来并改说明** |
| 打开后 | 出现首次引导，程序坞图标不是白纸 |
| 授予辅助功能后 | 显示「环境就绪」 |

- [ ] **Step 6: 数据目录换机器（成品标准第 10 条，必须真做）**

在第一台机器上：

```bash
cp -R ~/Library/Application\ Support/IELTS\ Speaking\ Coach ~/Desktop/coach-data-backup
```

把 `coach-data-backup` 拷到第二台机器的 `~/Library/Application Support/IELTS Speaking Coach`，打开 App。

| 看什么 | 判据 |
|---|---|
| 题库 | 题目数量与第一台一致 |
| 训练记录 | 条数一致，点开任意一条能看到题目与逐字稿 |
| 复盘报告 | 能打开，内容完整 |
| 录音 | 若开过录音，点播放能出声 |
| 错题本 / 词汇本 / 重训目标 | 数字与第一台一致 |
| 引导 | **只出现「环境」一步**（辅助功能要在这台机器上重给），不是从欢迎页重来 |

**任何一项对不上都要如实记下来，连同 `coach portability` 的输出一起。**

- [ ] **Step 7: 麦克风在 Hardened Runtime 下真的能用**

在关于页/设置里打开「保存我的回答录音」，看系统有没有弹出麦克风授权对话框，点「允许」，然后真的录一小段。

**这一步是 entitlement 唯一的真机判据。** 少了 `com.apple.security.device.audio-input`，Hardened Runtime 会直接拒掉麦克风，而单元测试和 `codesign` 自检都只能证明「entitlement 写进去了」，证明不了「系统认」。

- [ ] **Step 8: 界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节）**

关于页与引导页逐条走那十条清单。其中三条最容易被忽略：

- 打开系统「减弱动态效果」后，引导页的步骤切换是否无动画且功能正常
- 系统文字调到最大时，关于页是否不截断、不重叠（致谢那几段最长，最容易出问题）
- 关于页里有没有出现字面颜色、字号、圆角（翻一遍源码确认，不靠目测）

- [ ] **Step 9: 记录并提交**

把每一项的实际结果写进 `docs/phase10-acceptance.md`，含截图或原文。**包括不好的部分**——「哪里让我不想用」这类信息只有使用者有（成品标准第 5 节）。

```bash
git add docs/phase10-acceptance.md
git commit -m "docs: Phase 10 真机验收结果"
```

---

## 关于 Task 12–19（2026-08-06 跨阶段复审归入本阶段）

这八个任务是三块**跨全部页面**的收尾工作：深色模式（Task 12–13）、设置合并（Task 14–16）、「功能升级」与「问题反馈」两页（Task 17–18），最后 Task 19 是它们的人工验收。

**编号排在 Task 11 之后，但执行顺序上 Task 11 要往后挪。** Task 11 是整个阶段的真机验收，它要看的东西（关于页、引导页、界面十条清单）在 Task 12–18 之后都会变样。**建议的实际顺序是 1→10 → 12→18 → 11 → 19**，或者干脆把 Task 11 与 Task 19 合成一次做完。既有编号一个都不动，是为了让已经按编号领过任务的人不至于对不上。

**为什么这三块非要等到这里做：** 三块都要改到每一个页面。在页面还没写完的时候做深色模式，等于每新写一页就返一次工；在设置窗口还没有第四个分区的内容（数据与隐私要显示占用）时做合并，等于合到一半再拆。这一条是跨阶段复审的决策 7，理由与结论记在文末的附录里。

---

## Task 12: 深色模式的两套颜色令牌，与一个会算 alpha 的对比度

**Files:**
- Modify: `Sources/IELTSCoachUI/DesignSystem/Palette.swift`
- Create: `Sources/IELTSCoachUI/DesignSystem/ContrastMath.swift`
- Modify: `Tests/IELTSCoachUITests/DesignSystemTests.swift`
- Create: `Tests/IELTSCoachUITests/AppearanceContrastTests.swift`
- Modify: `docs/superpowers/DESIGN-SYSTEM.md`

**Interfaces:**
- Consumes: `Spacing` / `Radius`（Phase 3 Task 7，一个字不动）；`docs/superpowers/DESIGN-SYSTEM.md` 第 2 节的浅色取值
- Produces:
  - `enum Appearance: String, CaseIterable, Sendable { case light, dark }`
  - `struct PaletteTokens: Equatable, Sendable`，13 个 `let`：`accent`、`sidebarBackground`、`sidebarText`、`sidebarTextSelected`、`canvas`、`card`、`cardBorder`、`textPrimary`、`textSecondary`、`textOnAccent`、`success`、`warning`、`danger`；`init(accent:sidebarBackground:sidebarText:sidebarTextSelected:canvas:card:cardBorder:textPrimary:textSecondary:textOnAccent:success:warning:danger:)`
  - `Palette.light: PaletteTokens`、`Palette.dark: PaletteTokens`、`Palette.tokens(for: Appearance) -> PaletteTokens`
  - `Palette.accent` 等 13 个静态属性保持原名原类型（`Color`），但变成**随系统外观自动解析的动态颜色**——所有既有视图一行都不用改
  - `enum ContrastMath`：`struct Components { let red, green, blue, alpha: Double }`、`components(_:) -> Components`、`alpha(_:) -> Double`、`luminance(_:) -> Double`、`ratio(_ foreground: Color, over background: Color) -> Double`

### 三件必须先说清楚的事

**一、测试绝对不能拿 `Palette.accent` 去算对比度。**

它是动态颜色，`NSColor($0).usingColorSpace(.sRGB)` 会按**跑测试那一刻的系统外观**解析。开发者的机器是浅色，于是「深色模式的对比度测试」实际上测的是浅色，永远绿。所以两套取值必须是能被单独取出来的静态值（`Palette.light` / `Palette.dark`），测试只认它们。这也是把令牌拆成 `PaletteTokens` 这个值类型的全部理由。

**二、对比度必须先按 alpha 合成再算亮度，否则对半透明令牌是空转的。**

`Palette.textSecondary` 是 `Color.black.opacity(0.56)`。`NSColor(Color.black.opacity(0.56)).redComponent` 是 `0`——分量是纯黑，透明度在 alpha 上。忽略 alpha 直接算亮度，得到的是**纯黑对白底**的 21:1，而不是它在屏幕上真正的 4.94:1。

后果不只是数字不准：忽略 alpha 时，**Phase 3 Task 7 Step 5 那条突变验证（把 0.56 改成 0.40，`testSecondaryTextAlsoMeetsAA` 必须变红）根本不会红**——0.40 黑的分量同样是 0，算出来还是 21:1。那条突变会是绿的，而它本该是这份设计规范里最要紧的守门员。

> **2026-08-06 跨阶段复审已就地修好 Phase 3 计划**：`DesignSystemTests` 里的 `contrast(_:on:)`
> 现在先合成再算，并新增了 `testAlphaIsCompositedInsteadOfIgnored` 与突变 B 守着它。
> **开工前先确认源码里是哪一版：** `grep -n "fg.a" Tests/IELTSCoachUITests/DesignSystemTests.swift`
> ——有输出说明 Phase 3 已按修正版实现，本任务只是把这套算法提成 `ContrastMath`
> 让深色也能用；没输出说明源码停在忽略 alpha 的初稿上，本任务负责修，并在报告里写明。
> 两种情况下本任务要写的代码完全一样，区别只在报告怎么写。

**三、深色不是反色，是另一套单独定过对比度的取值。**

`DESIGN-SYSTEM.md` 第 2 节原话：「不要用反色实现深色模式——深色下要用降饱和的色调变体，并单独验证对比度」。下面两套取值就是照这条做的，每一组配对的比值都在注释里写了出来（手算，实现时以测试为准）。

### 两个不达标的语义色（`DESIGN-SYSTEM.md` 第 2 节的原值，2026-08-06 复审已同步修进 Phase 3 计划）

| 令牌 | 设计稿原值 | 实测比值 | 用 | 为什么必须改 |
|---|---|---|---|---|
| `Palette.success`（浅色）| `(0.13, 0.60, 0.35)` | 对白卡片 **3.64:1**、对内容区底色 3.44:1 | `(0.09, 0.50, 0.27)` → 约 5.02:1 / 4.58:1 | 低于 4.5:1 的不可协商底线 |
| `Palette.warning`（浅色）| `(0.85, 0.55, 0.10)` | 对白卡片 **2.72:1** | `(0.60, 0.39, 0.02)` → 约 5.05:1 / 4.60:1 | 同上。而且 Phase 8 明确用它显示一段中文说明（「`isMissing == true` 的行显示 `prompt` 里那段中文说明，用 `Palette.warning`」）——**那是正文，不是装饰** |

`Palette.danger`（`0.80, 0.20, 0.20`，5.14:1）不动。

**Phase 3 Task 7 已按修正值实现**（复审时补的），所以本任务多半只是把同样的值原样搬进 `Palette.light`。**开工前 `grep -n "0.85, green: 0.55" Sources/IELTSCoachUI/DesignSystem/Palette.swift`**：有输出说明源码停在设计稿原值上，本任务负责改，并在报告里写明。

**这两条是改视觉的，改完颜色会明显变深。** 若用户看了觉得太暗，可以再调，**但调完必须仍 ≥ 4.5:1**——那条线不可协商，测试会拦。已列进文末「需要用户参与的环节」。

**注意这两个新值对内容区底色（#F4F4F7）只有约 4.58 / 4.60，余量不到 0.15。** 上面那些比值是手算的；若矩阵实际跑出来差一点点（比如 4.47），**做法是把颜色再调深一档，不是把 4.5 改成 4.4**。那条线是这份规范里唯一不可协商的数字。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/AppearanceContrastTests.swift`：

```swift
import SwiftUI
import XCTest
@testable import IELTSCoachUI

/// 两套外观的对比度矩阵。
///
/// **为什么是矩阵而不是挑几条断言：** 任何一组只在浅色下被检查过的前景/背景配对，
/// 都是深色下的一个洞。深色下最典型的失败不是「难看」，是「那行字直接看不见了」，
/// 而写这行字的人多半用浅色开发，永远撞不上。
final class AppearanceContrastTests: XCTestCase {

    private struct Pair {
        let name: String
        let foreground: Color
        let background: Color
    }

    /// 所有承载文字的前景/背景配对。
    /// **背景一律用不透明令牌**——`ContrastMath` 只合成前景的 alpha，
    /// 背景是半透明时算出来的数跟屏幕上的观感没关系。
    private func textPairs(for appearance: Appearance) -> [Pair] {
        let t = Palette.tokens(for: appearance)
        return [
            Pair(name: "正文 vs 内容区底色", foreground: t.textPrimary, background: t.canvas),
            Pair(name: "正文 vs 卡片", foreground: t.textPrimary, background: t.card),
            Pair(name: "次要文字 vs 内容区底色", foreground: t.textSecondary, background: t.canvas),
            Pair(name: "次要文字 vs 卡片", foreground: t.textSecondary, background: t.card),
            Pair(name: "主色文字 vs 内容区底色", foreground: t.accent, background: t.canvas),
            Pair(name: "主色文字 vs 卡片", foreground: t.accent, background: t.card),
            Pair(name: "主色块上的文字", foreground: t.textOnAccent, background: t.accent),
            Pair(name: "侧边栏文字", foreground: t.sidebarText, background: t.sidebarBackground),
            Pair(name: "侧边栏选中文字", foreground: t.sidebarTextSelected,
                 background: t.sidebarBackground),
            Pair(name: "成功文字 vs 卡片", foreground: t.success, background: t.card),
            Pair(name: "成功文字 vs 内容区底色", foreground: t.success, background: t.canvas),
            Pair(name: "警告文字 vs 卡片", foreground: t.warning, background: t.card),
            Pair(name: "警告文字 vs 内容区底色", foreground: t.warning, background: t.canvas),
            Pair(name: "危险文字 vs 卡片", foreground: t.danger, background: t.card),
            Pair(name: "危险文字 vs 内容区底色", foreground: t.danger, background: t.canvas)
        ]
    }

    func testEveryTextPairMeetsAAInBothAppearances() {
        for appearance in Appearance.allCases {
            for pair in textPairs(for: appearance) {
                let ratio = ContrastMath.ratio(pair.foreground, over: pair.background)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(appearance.rawValue) 的「\(pair.name)」只有 "
                        + String(format: "%.2f", ratio)
                        + ":1，低于 4.5:1（DESIGN-SYSTEM 第 2 节，不可协商）")
            }
        }
    }

    func testEveryBackgroundTokenIsOpaque() {
        // ContrastMath 只合成前景的 alpha。背景一旦半透明，
        // 上面那条矩阵算出来的就只是个好看的数字，跟屏幕上看到的没关系。
        for appearance in Appearance.allCases {
            let t = Palette.tokens(for: appearance)
            for (name, color) in [("canvas", t.canvas), ("card", t.card),
                                  ("sidebarBackground", t.sidebarBackground),
                                  ("accent", t.accent)] {
                XCTAssertEqual(ContrastMath.alpha(color), 1.0, accuracy: 0.001,
                               "\(appearance.rawValue) 的 \(name) 不是不透明的")
            }
        }
    }

    func testDarkIsActuallyDark() {
        // 少了这一条，「深色模式」可以是一个把浅色原样返回的空实现，
        // 而上面那条矩阵会照样全绿——那正是本项目消灭过 15 次的空转。
        XCTAssertLessThan(ContrastMath.luminance(Palette.tokens(for: .dark).canvas),
                          ContrastMath.luminance(Palette.tokens(for: .light).canvas) / 4,
                          "深色的内容区底色并不比浅色暗，深色模式没有真做出来")
        XCTAssertGreaterThan(ContrastMath.luminance(Palette.tokens(for: .dark).textPrimary),
                             ContrastMath.luminance(Palette.tokens(for: .dark).canvas),
                             "深色下正文比背景还暗")
    }

    func testCardsStandOutFromTheCanvasInBothAppearances() {
        // 卡片靠「比背景亮一点」分层（DESIGN-SYSTEM 第 4 节：不加投影）。
        // 深色下把卡片做得比背景暗，每张卡片会变成一个洞。
        for appearance in Appearance.allCases {
            let t = Palette.tokens(for: appearance)
            XCTAssertGreaterThan(ContrastMath.luminance(t.card),
                                 ContrastMath.luminance(t.canvas),
                                 "\(appearance.rawValue) 的卡片没有比内容区底色亮")
        }
    }

    func testAlphaIsCompositedInsteadOfIgnored() {
        // 56% 黑压在白底上，观感等同 #747474，比值约 4.94:1。
        // 忽略 alpha 的实现会把它当成纯黑，算出 21:1 ——
        // 那样每个半透明令牌都「永远达标」，整条矩阵成了摆设。
        let ratio = ContrastMath.ratio(Color.black.opacity(0.56), over: .white)
        XCTAssertEqual(ratio, 4.94, accuracy: 0.2)
        XCTAssertLessThan(ratio, 6.0, "把半透明前景当成不透明色算了")
    }

    func testTheDarkPaletteIsNotJustTheLightOneInverted() {
        // DESIGN-SYSTEM 第 2 节：不要用反色实现深色模式，要用降饱和的色调变体。
        // 反色的判据：深色主色 ≈ 1 − 浅色主色（逐通道）。
        let light = ContrastMath.components(Palette.tokens(for: .light).accent)
        let dark = ContrastMath.components(Palette.tokens(for: .dark).accent)
        let inverted = abs((1 - light.red) - dark.red) < 0.02
            && abs((1 - light.green) - dark.green) < 0.02
            && abs((1 - light.blue) - dark.blue) < 0.02
        XCTAssertFalse(inverted, "深色主色是浅色主色的反色，规范明确禁止这种做法")
    }

    func testComponentsKeepAlphaSeparateFromTheColorItself() {
        // 这一条把「为什么忽略 alpha 会错」摆在明面上：
        // 56% 黑的三个分量就是纯黑，透明度全在 alpha 上。
        // 拿分量直接算亮度，算的是纯黑——21:1，而屏幕上是 4.94:1。
        let components = ContrastMath.components(Color.black.opacity(0.56))
        XCTAssertEqual(components.red, 0, accuracy: 0.001)
        XCTAssertEqual(components.green, 0, accuracy: 0.001)
        XCTAssertEqual(components.blue, 0, accuracy: 0.001)
        XCTAssertEqual(components.alpha, 0.56, accuracy: 0.01)
    }
}
```

同时把 `Tests/IELTSCoachUITests/DesignSystemTests.swift` **整个换成**下面这份。Phase 3 那几条对比度测试被上面的矩阵完全覆盖（矩阵对 `.light` 跑的是同样的配对，外加深色那一半），留着只会让同一件事有两个维护点：

> **搬家前先逐条对一遍：** Phase 3 的 `DesignSystemTests` 里有
> `testAlphaIsCompositedInsteadOfIgnored`、`testPrimaryTextMeetsAA`、`testSecondaryTextAlsoMeetsAA`、
> `testTextOnAccentMeetsAA`、`testSidebarTextMeetsAA`、`testSemanticColorsAreReadableAsText`。
> 上面的矩阵 + `testAlphaIsCompositedInsteadOfIgnored` 已经把它们**逐条**覆盖了。
> **若发现哪一条没有对应项，先把它补进矩阵再删**——删掉一条没有替身的测试，
> 就是这次「收紧」变成放松的唯一方式。

```swift
import XCTest
@testable import IELTSCoachUI

/// 令牌里可以自动验证的部分。
///
/// **对比度不在这里了。** Phase 3 的那几条对比度测试已经并进
/// `AppearanceContrastTests` 的矩阵：那份矩阵对浅色跑的是同样的配对，
/// 外加深色那一半，用的也是会合成 alpha 的算法。这是收紧，不是放松。
final class DesignSystemTests: XCTestCase {
    func testSpacingScaleIsMultiplesOfFour() {
        for value in [Spacing.xs, Spacing.sm, Spacing.md,
                      Spacing.lg, Spacing.xl, Spacing.section] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) 不是 4 的倍数")
        }
    }

    func testRadiusScaleIsOrdered() {
        // 控件比卡片更圆或一样圆，会让按钮看起来像卡片。
        XCTAssertLessThan(Radius.control, Radius.card)
        XCTAssertGreaterThan(Radius.pill, Radius.card)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AppearanceContrastTests`
Expected: 编译失败 —— `Appearance`、`PaletteTokens`、`ContrastMath` 未定义

- [ ] **Step 3: 实现对比度计算**

`Sources/IELTSCoachUI/DesignSystem/ContrastMath.swift`：

```swift
import AppKit
import SwiftUI

/// WCAG 对比度。**唯一存在的理由是它会合成 alpha。**
///
/// 直接拿 `NSColor(color).redComponent` 去算，`Color.black.opacity(0.56)`
/// 的分量是纯黑（透明度在 alpha 上），算出来是 21:1，而它在屏幕上只有 4.94:1。
/// 忽略 alpha 的对比度测试对每一个半透明令牌都是空转的。
public enum ContrastMath {

    public struct Components: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
    }

    /// 取不出分量时返回全 NaN。
    /// **不要改成「取不出就当黑色」**——那会让对比度变得非常好看，
    /// 而 NaN 会让任何 `XCTAssertGreaterThanOrEqual` 当场失败，这正是想要的。
    public static func components(_ color: Color) -> Components {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            return Components(red: .nan, green: .nan, blue: .nan, alpha: .nan)
        }
        return Components(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                          blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }

    public static func alpha(_ color: Color) -> Double { components(color).alpha }

    /// WCAG 相对亮度。忽略 alpha —— 调用方负责先合成。
    public static func luminance(_ color: Color) -> Double {
        let c = components(color)
        return luminance(red: c.red, green: c.green, blue: c.blue)
    }

    /// 前景压在背景上之后的对比度。背景必须是不透明令牌
    /// （`AppearanceContrastTests.testEveryBackgroundTokenIsOpaque` 守着这条约定）。
    public static func ratio(_ foreground: Color, over background: Color) -> Double {
        let fg = components(foreground)
        let bg = components(background)
        // 这三行就是这个类型存在的意义。删掉它们，所有半透明令牌都会「永远达标」。
        let red = fg.red * fg.alpha + bg.red * (1 - fg.alpha)
        let green = fg.green * fg.alpha + bg.green * (1 - fg.alpha)
        let blue = fg.blue * fg.alpha + bg.blue * (1 - fg.alpha)

        let front = luminance(red: red, green: green, blue: blue)
        let back = luminance(red: bg.red, green: bg.green, blue: bg.blue)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }

    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
```

- [ ] **Step 4: 实现两套令牌**

`Sources/IELTSCoachUI/DesignSystem/Palette.swift` 完整替换：

```swift
import AppKit
import SwiftUI

/// 两套外观。**深色不是浅色的反色**，是另一套单独定过对比度的取值
/// （DESIGN-SYSTEM 第 2 节）。
public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
}

/// 一整套颜色令牌的**静态**取值。
///
/// 为什么要有这个类型：`Palette.accent` 那一组是随系统外观解析的动态颜色，
/// 拿它去算对比度，算到的是「跑测试那一刻恰好是什么外观」——
/// 开发者的机器是浅色，于是「深色的对比度测试」实际测的是浅色，永远绿。
public struct PaletteTokens: Equatable, Sendable {
    public let accent: Color
    public let sidebarBackground: Color
    public let sidebarText: Color
    public let sidebarTextSelected: Color
    public let canvas: Color
    public let card: Color
    public let cardBorder: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textOnAccent: Color
    public let success: Color
    public let warning: Color
    public let danger: Color

    public init(accent: Color, sidebarBackground: Color, sidebarText: Color,
                sidebarTextSelected: Color, canvas: Color, card: Color, cardBorder: Color,
                textPrimary: Color, textSecondary: Color, textOnAccent: Color,
                success: Color, warning: Color, danger: Color) {
        self.accent = accent; self.sidebarBackground = sidebarBackground
        self.sidebarText = sidebarText; self.sidebarTextSelected = sidebarTextSelected
        self.canvas = canvas; self.card = card; self.cardBorder = cardBorder
        self.textPrimary = textPrimary; self.textSecondary = textSecondary
        self.textOnAccent = textOnAccent
        self.success = success; self.warning = warning; self.danger = danger
    }
}

public enum Palette {

    /// 浅色。取值来自设计稿（DESIGN-SYSTEM 第 2 节），
    /// 只有 success 与 warning 在 Phase 10 Task 12 被调深过——
    /// 原值分别只有 3.64:1 与 2.72:1，低于第 2 节那条不可协商的 4.5:1。
    public static let light = PaletteTokens(
        accent: Color(red: 0.361, green: 0.318, blue: 0.910),            // #5C51E8
        sidebarBackground: Color(red: 0.133, green: 0.118, blue: 0.239), // #221E3D
        sidebarText: Color.white.opacity(0.72),                          // 对侧边栏底 8.8:1
        sidebarTextSelected: .white,                                     // 15.9:1
        canvas: Color(red: 0.957, green: 0.957, blue: 0.969),            // #F4F4F7
        card: .white,
        cardBorder: Color.black.opacity(0.08),
        textPrimary: Color(red: 0.07, green: 0.07, blue: 0.09),          // 对卡片 18.7:1
        textSecondary: Color.black.opacity(0.56),                        // 对卡片 4.94:1
        textOnAccent: .white,                                            // 对主色 5.5:1
        success: Color(red: 0.09, green: 0.50, blue: 0.27),              // 对卡片 5.0:1
        warning: Color(red: 0.60, green: 0.39, blue: 0.02),              // 对卡片 5.0:1
        danger: Color(red: 0.80, green: 0.20, blue: 0.20))               // 对卡片 5.1:1

    /// 深色。**每一个值都是降饱和的色调变体，不是反色。**
    /// 两处刻意的不对称，都是为了守住 4.5:1：
    ///   · 主色调亮并降饱和（#A6A1E0），否则「强调数字」这种主色文字在深色卡片上只有 3:1；
    ///   · 主色块上的文字因此翻成近黑——白字压在调亮后的主色上只有 2.7:1。
    ///     一个令牌不可能同时满足「主色当文字用」和「白字压在主色上」，必须让一边翻面。
    public static let dark = PaletteTokens(
        accent: Color(red: 0.651, green: 0.631, blue: 0.878),            // 对卡片 6.9:1
        sidebarBackground: Color(red: 0.106, green: 0.094, blue: 0.188),
        sidebarText: Color.white.opacity(0.78),                          // 对侧边栏底 10.8:1
        sidebarTextSelected: .white,                                     // 17.2:1
        canvas: Color(red: 0.078, green: 0.078, blue: 0.102),
        card: Color(red: 0.118, green: 0.118, blue: 0.149),              // 比底色亮，卡片才不是个洞
        cardBorder: Color.white.opacity(0.14),
        textPrimary: Color(red: 0.929, green: 0.929, blue: 0.949),       // 对卡片 14.2:1
        textSecondary: Color.white.opacity(0.70),                        // 对卡片 8.7:1
        textOnAccent: Color(red: 0.078, green: 0.078, blue: 0.102),      // 对主色 7.7:1
        success: Color(red: 0.42, green: 0.79, blue: 0.56),              // 对卡片 8.2:1
        warning: Color(red: 0.95, green: 0.74, blue: 0.35),              // 对卡片 9.6:1
        danger: Color(red: 0.98, green: 0.53, blue: 0.51))               // 对卡片 7.0:1

    public static func tokens(for appearance: Appearance) -> PaletteTokens {
        switch appearance {
        case .light: return light
        case .dark: return dark
        }
    }

    // MARK: - 视图用的动态令牌
    //
    // 名字与类型跟 Phase 3 完全一样，所以既有视图一行都不用改。
    // 差别只在于：它们现在会跟着系统外观自己解析。

    public static let accent = dynamic(\.accent)
    public static let sidebarBackground = dynamic(\.sidebarBackground)
    public static let sidebarText = dynamic(\.sidebarText)
    public static let sidebarTextSelected = dynamic(\.sidebarTextSelected)
    public static let canvas = dynamic(\.canvas)
    public static let card = dynamic(\.card)
    public static let cardBorder = dynamic(\.cardBorder)
    public static let textPrimary = dynamic(\.textPrimary)
    public static let textSecondary = dynamic(\.textSecondary)
    public static let textOnAccent = dynamic(\.textOnAccent)
    public static let success = dynamic(\.success)
    public static let warning = dynamic(\.warning)
    public static let danger = dynamic(\.danger)

    /// 用 AppKit 的动态颜色，而不是 `@Environment(\.colorScheme)`。
    /// 理由：环境值只有 `View` 拿得到，而令牌是静态属性，被 `Components.swift`
    /// 里的组件直接引用。动态 NSColor 由绘制时的外观解析，不需要每个组件
    /// 都去读一次环境，也就不会漏掉任何一处。
    private static func dynamic(_ keyPath: KeyPath<PaletteTokens, Color>) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(tokens(for: isDark ? .dark : .light)[keyPath: keyPath])
        })
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter AppearanceContrastTests`
Expected: PASS（7 个测试）

Run: `swift test --filter DesignSystemTests`
Expected: PASS（2 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 6: 突变验证（三条，都要做）**

**突变 A —— 让对比度重新忽略 alpha：**
把 `ContrastMath.ratio` 里那三行合成
```swift
let red = fg.red * fg.alpha + bg.red * (1 - fg.alpha)
```
（连同 green、blue）改成
```swift
let red = fg.red
```
（连同 green、blue），重跑 `swift test --filter AppearanceContrastTests`。
Expected: `testAlphaIsCompositedInsteadOfIgnored` 变红（比值变成 21:1）。改回后确认全绿。

**这条守的是 Phase 3 那条突变验证本身。** 忽略 alpha 时，`textSecondary` 从 0.56 调到 0.40 也不会让任何测试变红——那条守门员就是失灵的。

**突变 B —— 让深色变成浅色的别名：**
把 `tokens(for:)` 的 `case .dark` 改成 `return light`，重跑。
Expected: `testDarkIsActuallyDark` 变红。**注意矩阵那一条仍然是绿的**——这正是为什么必须单独有一条测「深色确实是深的」：没有它，一个把深色模式做成空实现的改动可以全绿通过。改回后确认全绿。

**突变 C —— 把浅色警告色改回设计稿的原值：**
把 `light` 里的 `warning` 改回 `DESIGN-SYSTEM.md` 第 2 节写的 `Color(red: 0.85, green: 0.55, blue: 0.10)`，重跑。
Expected: `testEveryTextPairMeetsAAInBothAppearances` 变红，失败信息里写着「light 的「警告文字 vs 卡片」只有 2.72:1」。改回后确认全绿。

**这条把「顺带修的那个 bug」钉住**：以后谁觉得那个琥珀色太暗想调亮，测试会当场告诉他代价。

把三次的实际输出写进报告。

- [ ] **Step 7: 更新设计规范**

`docs/superpowers/DESIGN-SYSTEM.md` 第 2 节：

1. 把 `Palette` 的代码块换成新的两套取值（浅色注明 success / warning 已按对比度底线调深，并写明原值与实测比值），并**删掉代码块下面那个 2026-08-06 的 ⚠️ 注记**——它的全部内容都已落进代码块，留着就成了第二个说法。**前提是用户已经确认过观感**（文末「需要用户参与的环节」里那一条）；没确认就先留着注记，只改代码块。
2. 「深色模式」那一小节改写成「Phase 10 Task 12 已实现：两套静态取值 + 动态令牌，跟随系统外观，不提供手动切换（理由见 Phase 10 Task 13）」，并删掉那条「归属更正」的引用块。
3. 「对比度底线（不可协商）」那张表下面已经有一句「由 `DesignSystemTests`（浅色）与 `AppearanceContrastTests`（两套外观）逐对验证」——把它改成只提 `AppearanceContrastTests`，因为本任务已经把浅色那几条并进矩阵了。

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachUI/DesignSystem/Palette.swift \
        Sources/IELTSCoachUI/DesignSystem/ContrastMath.swift \
        Tests/IELTSCoachUITests/DesignSystemTests.swift \
        Tests/IELTSCoachUITests/AppearanceContrastTests.swift \
        docs/superpowers/DESIGN-SYSTEM.md
git commit -m "feat(ui): 深色模式的两套颜色令牌，对比度改为合成 alpha 后计算"
```

---

## Task 13: 让深色真的覆盖每一页——扫掉写死的颜色、字号与圆角

**Files:**
- Create: `Tests/PackagingTests/DesignTokenContractTests.swift`
- Modify: `Sources/IELTSCoachUI/Onboarding/PermissionGateView.swift`
- Modify: 巡检报出来的**每一个**视图文件（清单见 Step 2）

**Interfaces:**
- Consumes: `Palette`（Task 12 的动态令牌）、`NotarizeScriptTests.repositoryRoot`（Task 9）
- Produces: `Tests/PackagingTests/DesignTokenContractTests.swift`，跑通表示「`Sources/IELTSCoachUI/` 下除 `DesignSystem/` 外，没有任何字面颜色、字面字号、字面圆角」

**深色模式让这条约束从「风格问题」变成「功能问题」。** 一个写死的 `Color(red: 0.07, green: 0.07, blue: 0.09)` 在浅色下是漂亮的深灰正文，在深色下是一行**看不见的字**；而写它的人用浅色开发，永远不会撞上。Phase 3 的 Global Constraints 从第一天就写着「视图里不得出现字面颜色、字号、圆角」，但一直只靠人看——本任务给它一个会自己跑的守门员。

### 决策：深色模式只跟随系统，不做手动切换

**决策：** 不加「浅色 / 深色 / 跟随系统」三选一，`Palette` 的动态令牌跟着系统外观走，就这样。

**理由三条：**

1. **Mac 用户改外观的地方是系统设置，不是某个 App 的偏好面板。** 加一个三选一，等于在一个用户不会去找的地方放一个开关。
2. **每多一个偏好就多一份要同步的状态。** 本阶段 Task 14–16 正在做的事情恰恰是把散开的设置收回一处；同时又新造一个跨窗口要同步的外观状态，方向是反的。
3. **它会让 Task 12 的测试矩阵失去意义。** 手动强制浅色时，系统仍可能是深色，`NSVisualEffectView`、系统控件、滚动条的颜色不会跟着翻——那种半深半浅的界面，对比度矩阵一条都测不到。

**若将来真要做**，正确的做法是在设置窗口加第五个分区，用 `.preferredColorScheme(_:)` 施加到所有 Scene 上（含关于窗口与设置窗口本身，漏一个就会出现一深一浅两个窗口），并且把 Task 12 的矩阵改成对「强制值 × 系统值」四种组合都跑。**代价明显大于收益，本阶段不做。**

- [ ] **Step 1: 写失败的测试**

`Tests/PackagingTests/DesignTokenContractTests.swift`：

```swift
import XCTest

/// 守「视图里不得出现字面颜色、字号、圆角」——Phase 3 就写进 Global Constraints，
/// 一直只靠人看的那一条。
///
/// 深色模式让它从风格问题变成功能问题：写死的深灰正文在深色下是一行看不见的字，
/// 而写它的人用浅色开发，永远撞不上。
final class DesignTokenContractTests: XCTestCase {

    private var uiRoot: URL {
        NotarizeScriptTests.repositoryRoot.appending(path: "Sources/IELTSCoachUI")
    }

    /// 令牌只能定义在这个目录里。别处出现字面颜色就是 bug。
    private let tokenDirectory = "/DesignSystem/"

    private func swiftFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: uiRoot, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !url.path.contains(tokenDirectory) else { continue }
            files.append(url)
        }
        return files
    }

    func testThereAreActuallyFilesToScan() throws {
        // 路径写错时 enumerator 会安安静静返回空数组，下面两条就会「全绿」。
        // 那是最坏的一种绿：它对任何实现都亮。
        XCTAssertGreaterThan(try swiftFiles().count, 5,
                             "扫不到界面源码，先检查这个路径：\(uiRoot.path)")
    }

    func testNoViewHardcodesAColor() throws {
        try assertNoMatches(
            [#"Color\(red:"#,
             #"Color\(\.sRGB"#,
             #"\bNSColor\("#,
             #"Color\.(white|black|gray|red|blue|green|orange|yellow|pink|purple|indigo|teal|mint|brown|cyan)\b"#,
             #"foregroundStyle\(\.(white|black|gray|red|blue|green|orange|yellow|pink|purple|secondary|primary|tertiary)\)"#,
             #"foregroundColor\(\.[a-z]"#],
            why: "颜色必须走 Palette 令牌。深色模式下写死的颜色 = 一行看不见的字。"
                + "SwiftUI 的 .secondary 同样不行——它不在 Task 12 的对比度矩阵里，"
                + "没人验证过它在这两套底色上够不够 4.5:1。")
    }

    func testNoViewHardcodesAFontSizeOrCornerRadius() throws {
        try assertNoMatches(
            [#"\.font\(\.system\(size:\s*[0-9]"#,
             #"cornerRadius:\s*[0-9]"#],
            why: "字号走 SwiftUI 语义字体（DESIGN-SYSTEM 第 1 节，才能跟随系统文字大小），"
                + "圆角走 Radius 令牌（第 3 节）。")
    }

    private func assertNoMatches(_ patterns: [String], why: String) throws {
        for file in try swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                // 注释里写这些字样是允许的——注释不画到屏幕上。
                let code = String(line.split(separator: "//", maxSplits: 1).first ?? "")
                for pattern in patterns
                where code.range(of: pattern, options: .regularExpression) != nil {
                    XCTFail("\(file.lastPathComponent):\(index + 1) 有写死的样式："
                            + code.trimmingCharacters(in: .whitespaces) + "\n" + why)
                }
            }
        }
    }
}
```

- [ ] **Step 2: 运行，看它报出哪些文件**

Run: `swift test --filter DesignTokenContractTests`
Expected: 失败，并逐行列出违规位置。

**2026-08-06 已知的违规（Phase 3 刚交付到 Task 3 时的快照，之后各阶段还会新增，以测试实际报出的为准）：**

| 文件 | 行 | 现在写的 | 改成 |
|---|---|---|---|
| `Sources/IELTSCoachUI/Onboarding/PermissionGateView.swift` | 56 | `.foregroundStyle(notice.isFailure ? Color.red : Color.secondary)` | `.foregroundStyle(notice.isFailure ? Palette.danger : Palette.textSecondary)` |
| `Sources/IELTSCoachUI/RootView.swift`、`QuestionBank/QuestionBankView.swift`、`Today/TodayView.swift`、`Review/ReviewReportView.swift`、`Onboarding/PermissionGateView.swift` | 多处 | `.foregroundStyle(.secondary)` | `.foregroundStyle(Palette.textSecondary)` |

**这些是 bug，不是风格分歧。** `Color.red` 在深色底上是一个刺眼且对比度不足的红；`.secondary` 是 SwiftUI 自己的语义色，它确实会跟随外观，但**它的取值不在 Task 12 的矩阵里**——没有任何人验证过它压在 `Palette.canvas` / `Palette.card` 这两套底色上够不够 4.5:1。规范说「所有颜色必须走令牌」，走令牌的意义正是「每一个都被验过」。

- [ ] **Step 3: 逐个修掉，直到测试变绿**

Run: `swift test --filter DesignTokenContractTests`
Expected: PASS（3 个测试）

Run: `swift build && swift test`
Expected: 全绿

**在报告里逐条列出改了哪些文件的哪一行、从什么改成什么。** 这些是视觉改动，用户要能核对。

- [ ] **Step 4: 突变验证**

往 `Sources/IELTSCoachUI/Today/TodayView.swift` 里随便一个 `Text` 上加一行
```swift
.foregroundStyle(Color(red: 0.9, green: 0.1, blue: 0.1))
```
重跑 `swift test --filter DesignTokenContractTests`。
Expected: `testNoViewHardcodesAColor` 变红，并指出 `TodayView.swift` 的行号。删掉后确认全绿。

再做一次反向的：把 `uiRoot` 改成 `Sources/IELTSCoachUI-typo`，重跑。
Expected: `testThereAreActuallyFilesToScan` 变红。改回后确认全绿。

**第二条守的是「扫不到东西也会全绿」这种假绿**——路径一写错，两条禁令就同时失效，而且不会有任何提示。

把两次输出写进报告。

- [ ] **Step 5: 人工看一遍深色（这一步不可省，也不可由子代理代劳）**

```bash
./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

打开 系统设置 › 外观，切到「深色」，**App 保持开着**，逐页看过去：今日训练、训练题库、学习计划、复训中心、复盘报告、功能升级、问题反馈、训练记录、问题档案、我的词汇，再加上关于窗口、设置窗口、引导页、练习进行中的那个 sheet。

| 看什么 | 判据 |
|---|---|
| 有没有哪一行字看不见 | 一行都不许有 |
| 有没有哪张卡片消失成一个洞 | 卡片要比背景亮一点点（Task 12 有测试守，但屏幕是最终判据）|
| 主行动卡片 | 深色下是浅紫底 + 近黑字，读得清 |
| 侧边栏 | 深色下仍然与内容区分得开 |
| 系统控件（开关、下拉、滚动条）| 与自定义卡片放在一起不违和 |
| 切回浅色 | 一切照旧，没有留下深色的残迹 |

**发现任何一处，回 Step 3 修，不要记在待办里。** 深色下看不见的那一行字，跟没写是一样的。

- [ ] **Step 6: 提交**

```bash
git add Tests/PackagingTests/DesignTokenContractTests.swift Sources/IELTSCoachUI/
git commit -m "feat(ui): 全部视图改走颜色令牌，深色模式覆盖每一页"
```

---

## Task 14: 数据目录占用（Core，纯 Foundation）

**Files:**
- Create: `Sources/IELTSCoachCore/Storage/DataUsage.swift`
- Create: `Tests/IELTSCoachCoreTests/DataUsageTests.swift`

**Interfaces:**
- Consumes: `DataDirectory`（`root`、`reportsDirectory`、`recordingsDirectory`、`pendingReviewsDirectory`、`stateFile`）、`RecordingUsage.humanReadable(bytes:)`（Phase 5 Task 3）
- Produces:
  - `struct DataUsageReport: Equatable, Sendable`，字段 `totalBytes: Int64`、`stateBytes: Int64`、`reportBytes: Int64`、`recordingBytes: Int64`、`pendingReviewBytes: Int64`、`fileCount: Int`；`init(totalBytes:stateBytes:reportBytes:recordingBytes:pendingReviewBytes:fileCount:)`；`var summaryText: String`
  - `enum DataUsage { static func measure(directory: DataDirectory, fileManager: FileManager = .default) -> DataUsageReport }`

**这一条给两个地方用：** 设置窗口的「数据与隐私」分区（Task 16）与「问题反馈」页的诊断信息（Task 18）。放 Core 是因为它只依赖 Foundation，且命令行将来也可能要用。

**为什么 `measure` 不 `throws`：** 它是给「看一眼占用」用的。目录不存在、某个文件读不到，都只意味着那一块算 0，**不应该让整个设置页打不开**。真正读不到数据的错误由 `StateStore` 报，那才是要拦的。

**字节数怎么变成人话，复用 Phase 5 的 `RecordingUsage.humanReadable(bytes:)`，不要再写一份。** 两份格式化函数会让同一个文件夹在设置页显示 1.2 GB、在诊断信息里显示 1.15 GB，而用户会以为其中一个是 bug。

**动手前先确认它在：** `grep -n "humanReadable" Sources/IELTSCoachCore/Recording/RecordingStore.swift`。没有输出说明 Phase 5 还没交付，**停下来报告，不要在这里现写一个格式化函数**——那正是上面要避免的第二份。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/DataUsageTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class DataUsageTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "usage-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testEmptyDirectoryReportsZeroWithoutBlowingUp() {
        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertEqual(report.fileCount, 0)
    }

    func testMissingDirectoryReportsZeroInsteadOfFailing() {
        // 「看一眼占用」不该因为目录还没建就让整个设置页打不开。
        let nowhere = DataDirectory(root: FileManager.default.temporaryDirectory
            .appending(path: "does-not-exist-\(UUID().uuidString)"))
        XCTAssertEqual(DataUsage.measure(directory: nowhere).totalBytes, 0)
    }

    func testEachBucketIsCountedSeparatelyAndSumsToTheTotal() throws {
        try write(100, to: directory.stateFile)
        try write(200, to: directory.reportsDirectory.appending(path: "s1.json"))
        try write(400, to: directory.recordingsDirectory.appending(path: "s1.m4a"))
        try write(800, to: directory.pendingReviewsDirectory.appending(path: "p1.txt"))

        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.stateBytes, 100)
        XCTAssertEqual(report.reportBytes, 200)
        XCTAssertEqual(report.recordingBytes, 400)
        XCTAssertEqual(report.pendingReviewBytes, 800)
        XCTAssertEqual(report.totalBytes, 1_500)
        XCTAssertEqual(report.fileCount, 4)
    }

    func testNestedFilesAreCountedToo() throws {
        // reports/ 下将来可能按月分子目录。少算的话，用户看到的占用会比实际小，
        // 而他正是拿这个数字判断「要不要清一清」。
        try write(64, to: directory.reportsDirectory.appending(path: "2026-08/s1.json"))
        XCTAssertEqual(DataUsage.measure(directory: directory).reportBytes, 64)
    }

    func testFilesOutsideTheKnownBucketsStillCountTowardTheTotal() throws {
        // 总量必须是「这个文件夹占了多少地」，不是「我认识的那几类占了多少」。
        // 否则用户看到 2 MB、Finder 显示 900 MB，他会觉得这个数字在骗他。
        try write(4_096, to: directory.root.appending(path: "something-new.bin"))
        let report = DataUsage.measure(directory: directory)
        XCTAssertEqual(report.totalBytes, 4_096)
        XCTAssertEqual(report.reportBytes, 0)
        XCTAssertEqual(report.fileCount, 1)
    }

    func testSummaryTextIsHumanReadableAndNeverEmpty() throws {
        try write(2_048, to: directory.recordingsDirectory.appending(path: "s1.m4a"))
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("KB") || text.contains("MB") || text.contains("字节"),
                      "占用要写成人看得懂的单位：\(text)")
        XCTAssertFalse(text.contains("2048"), "别把原始字节数直接甩给用户：\(text)")
    }

    func testSummaryTextSaysZeroInsteadOfGoingBlank() {
        let text = DataUsage.measure(directory: directory).summaryText
        XCTAssertFalse(text.isEmpty, "空目录也要说一句话，空白会让人以为读失败了")
    }

    func testTheSameFormatterAsRecordingUsage() {
        // 两份格式化函数会让同一个文件夹在设置页显示 1.2 GB、
        // 在诊断信息里显示 1.15 GB，而用户会以为其中一个是 bug。
        XCTAssertTrue(DataUsageReport(totalBytes: 2_048, stateBytes: 0, reportBytes: 0,
                                      recordingBytes: 0, pendingReviewBytes: 0, fileCount: 1)
            .summaryText.contains(RecordingUsage.humanReadable(bytes: 2_048)))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DataUsageTests`
Expected: 编译失败 —— `DataUsage`、`DataUsageReport` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Storage/DataUsage.swift`：

```swift
import Foundation

/// 数据目录占了多少地，以及是被什么占的。
public struct DataUsageReport: Equatable, Sendable {
    /// 整个数据目录的大小。**不是几个已知桶的和**——
    /// 将来多出来的任何东西都要算进去，否则用户看到 2 MB、
    /// Finder 显示 900 MB，他会觉得这个数字在骗他。
    public let totalBytes: Int64
    public let stateBytes: Int64
    public let reportBytes: Int64
    public let recordingBytes: Int64
    public let pendingReviewBytes: Int64
    public let fileCount: Int

    public init(totalBytes: Int64, stateBytes: Int64, reportBytes: Int64,
                recordingBytes: Int64, pendingReviewBytes: Int64, fileCount: Int) {
        self.totalBytes = totalBytes; self.stateBytes = stateBytes
        self.reportBytes = reportBytes; self.recordingBytes = recordingBytes
        self.pendingReviewBytes = pendingReviewBytes; self.fileCount = fileCount
    }

    /// 复用 Phase 5 的格式化，不另写一份 —— 两份会给出两个不同的数字。
    public var summaryText: String {
        guard fileCount > 0 else { return "还没有任何数据（0 字节）。" }
        return "共 \(RecordingUsage.humanReadable(bytes: totalBytes))、\(fileCount) 个文件"
            + "（录音 \(RecordingUsage.humanReadable(bytes: recordingBytes))、"
            + "复盘 \(RecordingUsage.humanReadable(bytes: reportBytes))）。"
    }
}

/// 量一下数据目录。
///
/// **刻意不 throws。** 这是给「看一眼占用」用的：目录还没建、某个文件读不到，
/// 都只意味着那一块算 0，不该让整个设置页打不开。
/// 真正读不到训练数据的错误由 `StateStore` 报，那才是要拦的。
public enum DataUsage {
    public static func measure(directory: DataDirectory,
                               fileManager: FileManager = .default) -> DataUsageReport {
        var total: Int64 = 0
        var count = 0
        var state: Int64 = 0
        var reports: Int64 = 0
        var recordings: Int64 = 0
        var pending: Int64 = 0

        let reportsPath = directory.reportsDirectory.path
        let recordingsPath = directory.recordingsDirectory.path
        let pendingPath = directory.pendingReviewsDirectory.path
        let statePath = directory.stateFile.path

        guard let walker = fileManager.enumerator(
            at: directory.root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return DataUsageReport(totalBytes: 0, stateBytes: 0, reportBytes: 0,
                                      recordingBytes: 0, pendingReviewBytes: 0, fileCount: 0) }

        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            let bytes = Int64(size)
            total += bytes
            count += 1

            let path = url.path
            if path == statePath { state += bytes }
            else if path.hasPrefix(reportsPath + "/") { reports += bytes }
            else if path.hasPrefix(recordingsPath + "/") { recordings += bytes }
            else if path.hasPrefix(pendingPath + "/") { pending += bytes }
        }

        return DataUsageReport(totalBytes: total, stateBytes: state, reportBytes: reports,
                               recordingBytes: recordings, pendingReviewBytes: pending,
                               fileCount: count)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DataUsageTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证（两条）**

**突变 A：** 把 `total += bytes` 改成只在三个已知桶里累加（即把它挪进那三个 `else if` 分支里）。
重跑：`testFilesOutsideTheKnownBucketsStillCountTowardTheTotal` 必须变红。

**这条守的是「这个数字不能骗人」**——用户拿它判断要不要清理，比 Finder 小一大截的数字比不显示还糟。

**突变 B：** 把 `guard let walker = ... else { return 全 0 }` 改成 `let walker = fileManager.enumerator(...)!`。
重跑：`testMissingDirectoryReportsZeroInsteadOfFailing` 必须变红（崩溃）。改回后确认全绿。

把两次输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Storage/DataUsage.swift Tests/IELTSCoachCoreTests/DataUsageTests.swift
git commit -m "feat(core): 数据目录占用统计"
```

---

## Task 15: 统一设置的四个分区与跨窗口同步

**Files:**
- Create: `Sources/IELTSCoachUI/Settings/SettingsSection.swift`
- Create: `Sources/IELTSCoachUI/Settings/CoachSettingsViewModel.swift`
- Modify: `Sources/IELTSCoachUI/AppState.swift`
- Modify: `Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift`
- Create: `Tests/IELTSCoachUITests/CoachSettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `AppState`（`state`、`reload()`、`mutate(_:) -> String?`、私有 `store`）、`CoachSettings`（六个字段与 `normalized(_:)`）、`FeedbackTiming`、`Part2PrepMode`、`PracticeRoute`、`PracticeRoutePreference`、`WeeklyGoalEditor`、`DataUsage`（Task 14）、`RecordingSettingsViewModel`（Phase 5 Task 8）、`FakeMicrophoneAuthorizer`（Phase 5 的测试文件，同一个 test target 里可直接用）
- Produces:
  - `enum SettingsSection: String, CaseIterable, Identifiable, Sendable { case recording, goals, practice, data }`，含 `title` / `systemImage` / `summary`
  - `AppState.init(directory:checksPermissionOnLaunch:)`（新增第二个参数，默认 `true`）
  - `@MainActor @Observable public final class CoachSettingsViewModel`，含 `init(app:directory:)`、只读 `weeklyGoal` / `defaultRoute` / `feedbackTiming` / `part2PrepMode` / `transcriptEnabled` / `weeklyGoalHint` / `dataDirectoryURL` / `usage` / `error`，以及 `setWeeklyGoal(_:)` / `setDefaultRoute(_:)` / `setFeedbackTiming(_:)` / `setPart2PrepMode(_:)` / `setTranscriptEnabled(_:)` / `refreshUsage()`
  - `RecordingSettingsViewModel.init(store:recordings:authorizer:now:onChange:)`（末尾新增一个默认为空的回调）

### 三条决定了这个任务全部形状的判断

**一、所有取值都是从 `app.state` 直接读的计算属性，一个都不缓存。**

这不是风格偏好，**它就是「两个入口不可能不同步」的机制本身**。只要视图模型自己存一份 `weeklyGoal`，「设置窗口改了、主窗口还显示旧值」就从「不会发生」退化成「只要有人忘了刷新就会发生」，而这种 bug 在本机永远复现不了——你改完总会顺手看一眼那个窗口。

**二、设置窗口与主窗口共用同一个 `AppState` 实例。** 具体怎么共用见 Task 16（把它从 `RootView` 提到 App 层）。本任务只保证：**只要拿到的是同一个实例，两边就必然同步**，并且有测试守着。

**三、录音那一格是个例外，因为它必须先问麦克风权限。**

`RecordingSettingsViewModel`（Phase 5 Task 8）有一整套「权限没拿到时开关必须停在关」的逻辑，那是本项目踩过的坑，**绝不能为了统一而重写一遍**。它持有自己的 `StateStore`，所以它写完盘之后 `AppState` 并不知道。解决办法是给它加一个 `onChange` 回调，设置窗口传 `{ app.reload() }`。**加回调而不是让它去依赖 `AppState`**：视图模型一旦依赖 `AppState`，Phase 5 那 10 条测试就得先造一个会去启动 ChatGPT 的对象才能跑。

> ### 「记录对话逐字稿」是第四项练习偏好（Phase 4 Task 2 已交付，2026-08-06 复审改写）
>
> `CoachSettings.transcriptEnabled`（跨阶段决策 5，默认开）**归「练习偏好」分区**，与其余三项一样即时落盘。
> 本任务的 `CoachSettingsViewModel` 要多一个 `transcriptEnabled` 计算属性与 `setTranscriptEnabled(_:)`，测试照抄「反馈时机」那两条即可。
>
> **它现在有两个家，Task 16 负责拆掉旧的那个。** Phase 4 把开关放在**训练记录页顶部**，
> 并在 `AppState` 上留了一个 `setTranscriptEnabled(_:)`（那时还没有设置窗口，Phase 4 计划里
> 已写明「Phase 10 做设置合并时把它收进去，**不要两处都有一个开关**」）。
> 所以本任务只管加读写，**旧入口的删除在 Task 16 Step 2**，两处都做完才算合并干净。
>
> **确认方式：** `grep -n "transcriptEnabled" Sources/IELTSCoachCore/Model/CoachState.swift`。
> 没有输出就是 Phase 4 还没加，**不要在这里替它加**——那个字段的默认值与解码容错归 Phase 4 定；
> 此时把本条相关的属性、方法与测试一并跳过，并在报告里写明。

### `AppState` 为什么要多一个构造参数

Phase 8 Task 9 写得很清楚：`AppState.init` 会调 `recheckPermission()` → `AXDriver.preflight()`，而 `preflight()` 在 ChatGPT 没运行时**会真的去启动 ChatGPT** 并最多等 8 秒。于是 Phase 8 得出的结论是「`AppState` 没有自动化测试」。

但本任务要守的恰恰是 `AppState` 上的一件事：**改完立刻可见**。所以加一个只给测试用的开关：

```swift
public init(directory: DataDirectory = .resolve(), checksPermissionOnLaunch: Bool = true)
```

`false` 时跳过 `recheckPermission()`，`permission` 停在 `.unknown`。**生产代码一律不传这个参数**，行为与今天一模一样。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/CoachSettingsViewModelTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class CoachSettingsViewModelTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "settings-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    /// checksPermissionOnLaunch: false —— 不加这个，每跑一次测试就会去启动一次 ChatGPT
    /// 并等最多 8 秒（Sources/ChatGPTBridge/AXDriver.swift）。
    private func makeAppState() -> AppState {
        AppState(directory: directory, checksPermissionOnLaunch: false)
    }

    private func viewModel(_ app: AppState) -> CoachSettingsViewModel {
        CoachSettingsViewModel(app: app, directory: directory)
    }

    // MARK: - 分区

    func testThereAreExactlyFourSections() {
        // 断言确切数量而不是「至少四个」：多出来的第五个分区
        // 意味着又有设置散到别处去了，那正是这次合并要消灭的事。
        XCTAssertEqual(SettingsSection.allCases,
                       [.recording, .goals, .practice, .data])
    }

    func testEverySectionHasATitleAnIconAndOneLineOfWhatItIsFor() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty, "\(section) 没标题")
            XCTAssertFalse(section.systemImage.isEmpty, "\(section) 没图标")
            XCTAssertFalse(section.summary.isEmpty,
                           "\(section) 没写这一栏管什么——用户得点进去猜")
        }
    }

    func testSectionTitlesAreUnique() {
        let titles = SettingsSection.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "有两个分区重名")
    }

    // MARK: - 读

    func testReadsWhateverIsOnDisk() throws {
        try StateStore(directory: directory).mutate { state in
            state.settings.weeklyGoal = 7
            state.settings.feedbackTiming = .immediate
            state.settings.part2PrepMode = .learnerControlled
        }
        let settings = viewModel(makeAppState())
        XCTAssertEqual(settings.weeklyGoal, 7)
        XCTAssertEqual(settings.feedbackTiming, .immediate)
        XCTAssertEqual(settings.part2PrepMode, .learnerControlled)
    }

    // MARK: - 写

    func testChangingAGoalPersistsAndIsVisibleImmediately() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(9)

        XCTAssertNil(settings.error)
        XCTAssertEqual(settings.weeklyGoal, 9)
        XCTAssertEqual(app.state.settings.weeklyGoal, 9, "主窗口读的是同一个 AppState")
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 9,
                       "还得真的落盘，不能只是界面上变了个样子")
    }

    /// **本任务最要紧的一条。** 「在设置窗口改了，主窗口立刻看到」。
    /// 两个视图模型代表两个窗口，它们背后是同一个 AppState。
    func testASecondWindowSeesTheChangeWithoutBeingTold() {
        let app = makeAppState()
        let settingsWindow = viewModel(app)
        let mainWindow = viewModel(app)

        settingsWindow.setWeeklyGoal(9)
        settingsWindow.setFeedbackTiming(.immediate)

        XCTAssertEqual(mainWindow.weeklyGoal, 9,
                       "另一个窗口还显示旧的每周目标——这正是「设置散在两处」最难查的那种 bug")
        XCTAssertEqual(mainWindow.feedbackTiming, .immediate)
    }

    func testOutOfRangeGoalsAreClampedNotRejected() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(999)
        // 界面上的 Stepper 有边界，但手改过的 state.json、别的版本写进来的值都会走到这里。
        // 归一，不报错——一个坏掉的目标数字不该让人没法用设置页。
        XCTAssertEqual(settings.weeklyGoal, CoachSettings.defaultWeeklyGoal)
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal,
                       CoachSettings.defaultWeeklyGoal)
    }

    func testChangingTheDefaultRouteRoundTripsThroughTheStringInSettings() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        for route in PracticeRoute.allCases {
            settings.setDefaultRoute(route)
            XCTAssertEqual(settings.defaultRoute, route, "\(route) 存下去再读回来变了样")
        }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.defaultRoute,
                       PracticeRoutePreference.rawValue(for: PracticeRoute.allCases.last!))
    }

    func testEveryPracticePreferenceLandsOnDisk() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setFeedbackTiming(.immediate)
        settings.setPart2PrepMode(.learnerControlled)

        let saved = try StateStore(directory: directory).load().settings
        XCTAssertEqual(saved.feedbackTiming, .immediate)
        XCTAssertEqual(saved.part2PrepMode, .learnerControlled)
    }

    func testChangingOneSettingDoesNotResetTheOthers() throws {
        // CoachSettings 被 Phase 5 / 7 / 8 各加过字段。
        // 用「整体替换」的写法很容易把别人的字段顺手清成默认值，而且不会报错。
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(7)
        settings.setFeedbackTiming(.immediate)
        settings.setPart2PrepMode(.learnerControlled)
        settings.setWeeklyGoal(8)

        let saved = try StateStore(directory: directory).load().settings
        XCTAssertEqual(saved.weeklyGoal, 8)
        XCTAssertEqual(saved.feedbackTiming, .immediate, "改每周目标把反馈时机清掉了")
        XCTAssertEqual(saved.part2PrepMode, .learnerControlled, "改每周目标把准备模式清掉了")
    }

    // MARK: - 写不进去的时候

    func testAFailedWriteSaysSoAndDoesNotPretendItWorked() throws {
        let app = makeAppState()
        let settings = viewModel(app)
        // 把数据目录换成一个不可写的位置，制造真实的写盘失败。
        try FileManager.default.removeItem(at: directory.root)
        try Data("不是目录".utf8).write(to: directory.root)

        settings.setWeeklyGoal(9)

        let message = try XCTUnwrap(settings.error, "写盘失败却什么都不说")
        XCTAssertTrue(message.contains("下一步"), "没告诉用户下一步做什么：\(message)")
        XCTAssertNotEqual(settings.weeklyGoal, 9,
                          "没存进去却显示成 9 —— 用户下次打开会发现又变回去了，且永远不知道为什么")
    }

    // MARK: - 数据与隐私

    func testDataSectionShowsTheRealDirectoryAndItsUsage() throws {
        try Data(repeating: 0x41, count: 2_048)
            .write(to: directory.recordingsDirectory.appending(path: "a.m4a"))
        let settings = viewModel(makeAppState())
        settings.refreshUsage()

        XCTAssertEqual(settings.dataDirectoryURL, directory.root)
        XCTAssertEqual(settings.usage.totalBytes, 2_048)
        XCTAssertFalse(settings.usage.summaryText.isEmpty)
    }

    // MARK: - 文案

    func testTheWeeklyGoalHintComesFromTheSharedEditorNotAFreshCopy() {
        // WeeklyGoalEditor 是 Phase 7 定的文案，测试也在那边。
        // 设置窗口再写一份「还差几次」的句子，两处迟早说不一样的话。
        let app = makeAppState()
        let settings = viewModel(app)
        settings.setWeeklyGoal(5)
        XCTAssertEqual(settings.weeklyGoalHint,
                       WeeklyGoalEditor.hint(done: 0, goal: 5))
    }
}
```

再在同一个 target 里追加一条，守录音那一格的同步（用 Phase 5 测试里已有的 `FakeMicrophoneAuthorizer`）。放进 `Tests/IELTSCoachUITests/RecordingSettingsViewModelTests.swift`：

```swift
    /// Phase 10 Task 15 追加：录音开关持有自己的 StateStore，
    /// 写完盘之后 AppState 并不知道。onChange 就是那根线。
    @MainActor
    func testTurningRecordingOnTellsTheMainWindowToRefresh() async throws {
        let app = AppState(directory: directory, checksPermissionOnLaunch: false)
        let viewModel = RecordingSettingsViewModel(
            store: store, recordings: recordings,
            authorizer: FakeMicrophoneAuthorizer(current: .granted),
            onChange: { app.reload() })

        await viewModel.setEnabled(true)

        XCTAssertTrue(app.state.settings.recordingEnabled,
                      "在设置窗口开了录音，主窗口拿到的 AppState 还是旧的")
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter CoachSettingsViewModelTests`
Expected: 编译失败 —— `SettingsSection`、`CoachSettingsViewModel` 未定义，`AppState` 没有 `checksPermissionOnLaunch` 参数

- [ ] **Step 3: 给 `AppState` 加测试用的构造参数**

`Sources/IELTSCoachUI/AppState.swift`，**只改 `init`，其余成员一律不动**：

```swift
    /// - Parameter checksPermissionOnLaunch: **只有测试会传 false。**
    ///   `recheckPermission()` 会调 `AXDriver.preflight()`，而它在 ChatGPT 没运行时
    ///   会真的去启动 ChatGPT 并最多等 8 秒（Sources/ChatGPTBridge/AXDriver.swift）。
    ///   不关掉它，每跑一次单元测试就弹一次 ChatGPT。
    ///   生产代码一律用默认值，行为与从前完全一致。
    public init(directory: DataDirectory = .resolve(), checksPermissionOnLaunch: Bool = true) {
        self.store = StateStore(directory: directory)
        reload()
        if checksPermissionOnLaunch { recheckPermission() }
    }
```

- [ ] **Step 4: 实现分区与视图模型**

`Sources/IELTSCoachUI/Settings/SettingsSection.swift`：

```swift
import Foundation

/// 设置窗口的四个分区。**恰好四个，且六个用户可配置项全在里面**——
/// 多出第五个分区，或者哪个设置又跑到别的页面上去，都意味着这次合并白做了。
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case recording
    case goals
    case practice
    case data

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recording: return "录音"
        case .goals: return "训练目标"
        case .practice: return "练习偏好"
        case .data: return "数据与隐私"
        }
    }

    public var systemImage: String {
        switch self {
        case .recording: return "mic"
        case .goals: return "target"
        case .practice: return "slider.horizontal.3"
        case .data: return "folder"
        }
    }

    /// 这一栏管什么。没有这句话，用户得挨个点进去猜。
    public var summary: String {
        switch self {
        case .recording:
            return "要不要录下你的回答、麦克风权限、录音占了多少地方。"
        case .goals:
            return "每周想练几次。首页那格「本周 N/M 次」用的就是它。"
        case .practice:
            return "默认从哪条路线开练、考官什么时候给反馈、Part 2 的一分钟准备怎么算。"
        case .data:
            return "你的数据存在哪儿、占了多少、怎么备份和搬走。"
        }
    }
}
```

`Sources/IELTSCoachUI/Settings/CoachSettingsViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore
import Observation

/// 设置窗口里除录音之外的三个分区。
///
/// **所有取值都是从 `app.state` 直接读的计算属性，一个都不缓存。**
/// 这不是风格，是「两个窗口不可能不同步」的机制本身：只要这里自己存一份，
/// 「设置窗口改了、主窗口还显示旧值」就从「不会发生」退化成
/// 「只要有人忘了刷新就会发生」——而这种 bug 在本机永远复现不了，
/// 因为你改完总会顺手看一眼那个窗口。
///
/// 录音那一格不在这里：它必须先申请麦克风权限，那套逻辑在 Phase 5 的
/// `RecordingSettingsViewModel` 里，本窗口原样嵌用，不重写。
@MainActor
@Observable
public final class CoachSettingsViewModel {
    /// 写盘失败时的中文说明（发生了什么 + 下一步）。
    /// **非 nil 时界面必须显示。** 静默失败会让用户以为改好了，
    /// 下次打开发现又变回去，而且永远不知道为什么。
    public private(set) var error: String?
    public private(set) var usage = DataUsageReport(totalBytes: 0, stateBytes: 0, reportBytes: 0,
                                                    recordingBytes: 0, pendingReviewBytes: 0,
                                                    fileCount: 0)

    private let app: AppState
    private let directory: DataDirectory

    public init(app: AppState, directory: DataDirectory = .resolve()) {
        self.app = app
        self.directory = directory
        refreshUsage()
    }

    // MARK: - 读（一律现读，不缓存）

    public var weeklyGoal: Int { app.state.settings.weeklyGoal }
    public var defaultRoute: PracticeRoute {
        PracticeRoutePreference.route(fromSettings: app.state.settings.defaultRoute)
    }
    public var feedbackTiming: FeedbackTiming { app.state.settings.feedbackTiming }
    public var part2PrepMode: Part2PrepMode { app.state.settings.part2PrepMode }
    public var transcriptEnabled: Bool { app.state.settings.transcriptEnabled }
    public var dataDirectoryURL: URL { directory.root }

    /// 「本周已经练了 N 次，离目标还差 M 次」。文案来自 Phase 7 的 `WeeklyGoalEditor`，
    /// 不在这里另写一句——两处迟早会说不一样的话。
    public var weeklyGoalHint: String {
        WeeklyGoalEditor.hint(done: TodayViewModel(state: app.state).weekProgress.done,
                              goal: weeklyGoal)
    }

    // MARK: - 写（一律走 AppState.mutate，改完立刻可见）

    public func setWeeklyGoal(_ raw: Int) {
        let normalized = CoachSettings.normalized(raw)
        apply { $0.settings.weeklyGoal = normalized }
    }

    public func setDefaultRoute(_ route: PracticeRoute) {
        let raw = PracticeRoutePreference.rawValue(for: route)
        apply { $0.settings.defaultRoute = raw }
    }

    public func setFeedbackTiming(_ value: FeedbackTiming) {
        apply { $0.settings.feedbackTiming = value }
    }

    public func setPart2PrepMode(_ value: Part2PrepMode) {
        apply { $0.settings.part2PrepMode = value }
    }

    /// 「记录对话逐字稿」（Phase 4 Task 2 的字段，默认开）。
    /// **这里是它唯一的写入口**——Task 16 会把 `AppState.setTranscriptEnabled` 删掉。
    public func setTranscriptEnabled(_ value: Bool) {
        apply { $0.settings.transcriptEnabled = value }
    }

    public func refreshUsage() {
        usage = DataUsage.measure(directory: directory)
    }

    /// 逐字段赋值，**不整体替换 `settings`**。
    /// `CoachSettings` 被 Phase 5 / 7 / 8 各加过字段，整体替换的写法
    /// 很容易把别人的字段顺手清成默认值，而且一声不吭。
    private func apply(_ change: (inout CoachState) -> Void) {
        if let failure = app.mutate({ change(&$0) }) {
            error = failure
        } else {
            error = nil
        }
    }
}
```

`Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift` 只加两处（**其余一行不动**）：

```swift
    private let onChange: () -> Void

    public init(store: StateStore, recordings: RecordingStore,
                authorizer: any MicrophoneAuthorizing,
                now: @escaping () -> Date = Date.init,
                onChange: @escaping () -> Void = {}) {
        // …既有赋值原样保留…
        self.onChange = onChange
        refresh()
    }
```

以及在 `persist(_:)` 里 `refresh()` 之后加一行：

```swift
            refresh()
            onChange()      // 这一格持有自己的 StateStore，写完盘要让主窗口那个 AppState 重读
            return true
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter CoachSettingsViewModelTests`
Expected: PASS（13 个测试）

Run: `swift test --filter RecordingSettingsViewModelTests`
Expected: PASS（11 个测试 —— Phase 5 的 10 条 + 本任务追加的 1 条）

Run: `swift test`
Expected: 全绿

- [ ] **Step 6: 突变验证（三条，都要做）**

**突变 A —— 把取值缓存起来：**
把 `public var weeklyGoal: Int { app.state.settings.weeklyGoal }` 改成一个存储属性：
```swift
public private(set) var weeklyGoal: Int
```
在 `init` 里赋 `app.state.settings.weeklyGoal`，在 `setWeeklyGoal` 里也赋一次。
重跑：`testASecondWindowSeesTheChangeWithoutBeingTold` 必须变红（第二个窗口还显示旧值）。

**这条守的就是这次合并要解决的那个问题本身。** 注意 `testChangingAGoalPersistsAndIsVisibleImmediately` 在这个突变下**仍然是绿的**——所以那条测试不能替代这条。

**突变 B —— 让 `AppState.mutate` 不再 `reload()`：**
把 `Sources/IELTSCoachUI/AppState.swift` 里 `mutate` 的 `reload()` 那一行删掉。
重跑：`testChangingAGoalPersistsAndIsVisibleImmediately` 与 `testASecondWindowSeesTheChangeWithoutBeingTold` 必须同时变红。改回后确认全绿。

**突变 C —— 让录音那一格不再通知主窗口：**
把 `persist` 里的 `onChange()` 删掉。
重跑：`testTurningRecordingOnTellsTheMainWindowToRefresh` 必须变红。改回后确认全绿。

把三次输出写进报告。

- [ ] **Step 7: 提交**

```bash
git add Sources/IELTSCoachUI/Settings/SettingsSection.swift \
        Sources/IELTSCoachUI/Settings/CoachSettingsViewModel.swift \
        Sources/IELTSCoachUI/AppState.swift \
        Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift \
        Tests/IELTSCoachUITests/CoachSettingsViewModelTests.swift \
        Tests/IELTSCoachUITests/RecordingSettingsViewModelTests.swift
git commit -m "feat(ui): 统一设置的四个分区与跨窗口同步"
```

---

## Task 16: 设置窗口本体，与三处旧入口的去留

**Files:**
- Create: `Sources/IELTSCoachUI/Settings/SettingsWindowView.swift`
- Create: `Sources/IELTSCoachUI/Settings/SettingsNavigator.swift`
- Create: `Sources/IELTSCoachUI/Settings/WeeklyGoalEditor.swift`
- Delete: `Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift`
- Modify: `Sources/IELTSCoachUI/AppState.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Sources/IELTSCoachUI/Today/TodayView.swift`
- Modify: `Sources/IELTSCoachUI/Plan/PlanView.swift`
- Modify: `Sources/IELTSCoachUI/History/HistoryView.swift`（撤掉 Phase 4 放在页头的逐字稿开关）
- Modify: `Sources/IELTSCoachApp/main.swift`
- Create: `Tests/PackagingTests/SettingsHomeContractTests.swift`

**Interfaces:**
- Consumes: `SettingsSection` / `CoachSettingsViewModel`（Task 15）、`RecordingSettingsView` + `RecordingSettingsViewModel`（Phase 5 Task 8）、`WeeklyGoalEditor`（Phase 7 Task 9，本任务只搬家）、`AppState`、设计令牌与 `CoachCard` / `SectionHeader`
- Produces:
  - `@MainActor @Observable public final class SettingsNavigator`，含 `var section: SettingsSection`、`init()`、`func open(_:)`
  - `public struct SettingsWindowView: View`，`init(app:navigator:directory:)`
  - `RootView.init(app:navigator:)`（签名变了，见下）

### 决策：四处旧入口，一处升级、一处改成深链接、两处撤掉

用户在夜间复审里把这条留给实现者判断，理由与结论如下。**红线是「同一个设置不得有两个入口且可能不同步」**——所有保留下来的入口都必须打开**同一个窗口**，不许有第二份界面。

| 旧入口 | 决定 | 理由 |
|---|---|---|
| **`⌘,` 录音设置窗口**（Phase 5 Task 8）| **升级**成统一设置窗口的「录音」分区 | 入口没变、快捷键没变，只是窗口里多了三个分区。`RecordingSettingsView` **原样嵌进去**，不重写——它那套「权限没拿到时开关必须停在关」的逻辑是踩过坑换来的 |
| **首页齿轮按钮**（Phase 7 Task 9）| **保留按钮，行为改成「打开设置窗口并定位到「训练目标」」** | 首页那格写着「本周 3/5 次」，旁边不给一个改目标的入口，用户看得见目标却不知道去哪儿改。但它**不再自己弹一个 sheet**——`WeeklyGoalSheet` 整个删掉，它就是「第二份界面」的定义 |
| **学习计划页底部的三项练习偏好**（Phase 8 Task 9 H 节）| **撤掉**，换成一行说明 + 一个「打开设置 › 练习偏好」的按钮 | 那三项（默认路线、反馈时机、Part 2 准备）影响的是**每一场练习**，不只是计划；它们当初落在计划页页尾，只是因为那时还没有设置窗口。留在那儿就等于「练习偏好有两个家」 |
| **训练记录页顶部的「记录对话逐字稿」开关**（Phase 4 Task 9）| **撤掉开关本体**，换成一行说明 + 一个「打开设置 › 练习偏好」的按钮；连同 `AppState.setTranscriptEnabled(_:)` 一起删 | 与上一行同理：它决定**每一场练习**要不要采集逐字稿，不是训练记录页的属性。Phase 4 计划自己就写着「Phase 4 抢先建设置窗口只会让 Phase 5 重做，**Phase 10 做设置合并时把它收进去，不要两处都有一个开关**」——这里就是那个收口点 |

> **第四行是 2026-08-06 复审补进来的。** 初稿这张表只有三行，把 Phase 4 那个开关漏了；
> 而下面 `SettingsHomeContractTests` 的字段清单里也没有 `transcriptEnabled`——
> **于是唯一一个真的会有两个写入口的字段，恰好是那条契约测试看不见的字段。**
> 两处都已补上。
>
> **保留下来的那行说明必须仍然讲清它是什么**（Phase 4 定的文案，一字不改地搬到设置窗口去）：
> 「开着时，练习中会把考官的问题和你的回答记下来，方便复盘时回看。它只读 ChatGPT 窗口上已经显示的文字，不录音、不联网。」
> 训练记录页留下的那一行改成只读的现状 + 按钮，例如「逐字稿记录：开 · 在「设置 › 练习偏好」里更改」。

**为什么不干脆把齿轮也撤掉：** 那样每周目标就只能从 `⌘,` 进。而首页是这个 App 唯一一个「用户每天都会看」的页面，把它上面唯一一处提到目标的地方做成只读，是在为了架构整洁牺牲可达性。**深链接同时满足两边**：一个窗口、一份状态、两条到达路径。

**怎么跳到某个分区，不用私有 selector。** macOS 14 起有 `@Environment(\.openSettings)`：

```swift
@Environment(\.openSettings) private var openSettings
// …
Button { navigator.open(.goals); openSettings() } label: { … }
```

`SettingsNavigator` 是一个进程内的 `@Observable`，只存「当前选中哪一栏」。它和 `AppState` 一样由 App 层持有并传给两个 Scene。

- [ ] **Step 1: 搬走 `WeeklyGoalEditor`，删掉 `WeeklyGoalSheet`**

把 Phase 7 Task 9 写在 `Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift` 里的 `enum WeeklyGoalEditor` **原样**移到新文件 `Sources/IELTSCoachUI/Settings/WeeklyGoalEditor.swift`（一个字都不改），然后删掉 `WeeklyGoalSheet.swift` 整个文件。

Run: `swift test --filter WeeklyGoalEditorTests`
Expected: PASS（6 个测试，Phase 7 写的，**一行都不改**）

**那 6 条测试就是「搬家没搬坏」的守门员。** 它们不知道这次搬家发生过，这正是它们有价值的原因。

- [ ] **Step 2: 删掉 `AppState` 上的两个旧写入口**

`Sources/IELTSCoachUI/AppState.swift` 里删掉三样：

1. Phase 7 Task 9 加的 `setWeeklyGoal(_:)` 与 `settingsError`
2. **Phase 4 Task 9 加的 `setTranscriptEnabled(_:)`**（决策表第四行）

理由：现在唯一的写盘路径是 `AppState.mutate`（Phase 8），错误由 `CoachSettingsViewModel.error` 承担。**两处错误状态并存的话，界面会显示旧的那一份**，而且没人说得清该看哪个。

Run: `swift build`
Expected: 编译失败，报出所有还在调 `setWeeklyGoal` / `setTranscriptEnabled` / 读 `settingsError` 的地方——把它们一并改掉。**编译器在这里是资产，别绕过它。**

`HistoryView` 里那个 `Toggle` 因此会编译不过，正好：把它换成一行只读现状 + 「打开设置 › 练习偏好」按钮（`navigator.open(.practice); openSettings()`）。**Phase 4 写在开关下面的那句说明搬进设置窗口，不要两边各留一份。**

- [ ] **Step 3: 写 `SettingsNavigator`**

`Sources/IELTSCoachUI/Settings/SettingsNavigator.swift`：

```swift
import Observation

/// 设置窗口当前停在哪一栏。
///
/// 由 App 层持有，同时传给主窗口和设置窗口——所以首页齿轮
/// 可以先 `open(.goals)` 再调 `openSettings()`，窗口打开时就已经在那一栏了。
///
/// **它只管「停在哪一栏」，不管任何设置的值。** 值一律在 `AppState` 里，
/// 那是「两个窗口不可能不同步」的前提（Task 15）。
@MainActor
@Observable
public final class SettingsNavigator {
    public var section: SettingsSection = .recording

    public init() {}

    public func open(_ section: SettingsSection) { self.section = section }
}
```

- [ ] **Step 4: 写 `SettingsWindowView`（只给验收要求，布局自定）**

| 必须做到 | 判据 |
|---|---|
| 四个分区，用 `TabView` + `.tabViewStyle(.grouped)` 或左侧列表 | 分区、标题、图标全部来自 `SettingsSection`，**不得在视图里另写一套** |
| 当前分区绑定 `navigator.section` | 从首页齿轮进来时停在「训练目标」，从计划页进来时停在「练习偏好」 |
| 每个分区顶部显示 `section.summary` | 用户不用点进去猜这一栏管什么 |
| 「录音」分区 | **直接嵌 Phase 5 的 `RecordingSettingsView`**，视图模型构造时传 `onChange: { app.reload() }`。不重写它的任何一行 |
| 「训练目标」分区 | `Stepper`，范围 `WeeklyGoalEditor.range`，标题 `WeeklyGoalEditor.label(for:)`，下面一行 `viewModel.weeklyGoalHint`。**数字用 `.monospacedDigit()`**——从 9 跳到 10 时那一行不能抖 |
| 「练习偏好」分区 | 三项，取值与文案逐字沿用 Phase 8 Task 9 H 节那张表与那三句说明（默认练习路线 / 反馈时机 / Part 2 准备时间）。改动即时落盘 |
| 「数据与隐私」分区 | 数据目录完整路径（可选中复制）、`viewModel.usage.summaryText`、「在访达中显示」按钮（`NSWorkspace.shared.activateFileViewerSelecting`）、一句「换电脑时把这个文件夹整个拷过去就能接着用；备份就是拷贝它」、一句「你的练习内容只在这台电脑上，本工具不上传任何东西」 |
| `viewModel.error != nil` 时 | 用 `CoachCard` 显示全文，可选中；**且那一项的控件要显示回落盘的事实**，不能停在用户刚拨到的位置 |
| 窗口尺寸 | 四个分区里最高的那个不出现滚动条截断；文字放大到系统最大档时不重叠 |
| 全部走设计令牌 | 视图里不得出现字面颜色、字号、圆角（Task 13 的巡检会扫到这里）|
| 深色 | 在深色下逐分区看一遍（Task 19）|

- [ ] **Step 5: 改 `Sources/IELTSCoachApp/main.swift`（完整代码）**

这一段不是布局，是 Scene 的结构与状态的归属，摆错了「两个窗口共用一个 `AppState`」就不成立：

```swift
import IELTSCoachCore
import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    /// **`AppState` 必须建在这里，不能建在 RootView 里。**
    /// 设置窗口是另一个 Scene，它和主窗口只有共用同一个实例才可能同步；
    /// 各建各的话，「在设置窗口改了、主窗口立刻看到」就只能靠事后刷新去补，
    /// 而那种补法漏一处就是一个在本机永远复现不了的 bug。
    @State private var app = AppState()
    /// 只管「设置窗口停在哪一栏」，不管任何设置的值。
    @State private var settingsNavigator = SettingsNavigator()

    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") {
            RootView(app: app, navigator: settingsNavigator)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            // 替换系统默认的「关于 …」，指向我们自己的窗口。
            // 放在苹果菜单里是 Mac 应用的标准位置——不要为它在侧边栏加第 11 项。
            CommandGroup(replacing: .appInfo) { AboutMenuButton() }
        }

        // macOS 的设置窗口（⌘,）。四个分区：录音、训练目标、练习偏好、数据与隐私。
        // Phase 5 只放了录音；Phase 10 Task 16 把散在首页齿轮和学习计划页页尾的
        // 另外几项也收进来了，用户不用再猜某个设置藏在哪一页。
        Settings {
            SettingsWindowView(app: app, navigator: settingsNavigator)
        }

        Window("关于 IELTS Speaking Coach", id: AboutWindow.id) { AboutView() }
            .windowResizability(.contentSize)
    }
}

CoachApp.main()
```

- [ ] **Step 6: 改三个视图的入口**

`Sources/IELTSCoachUI/RootView.swift`：

- 签名改成 `public init(app: AppState, navigator: SettingsNavigator)`，**不再自己 `@State private var app = AppState()`**
- 工具栏那个齿轮按钮（Phase 7 Task 9 加的）：`Button { navigator.open(.goals); openSettings() }`，**不挂 `.keyboardShortcut(",", …)`**——`Settings` 场景自带 `⌘,`，两处绑同一个键会随机胜出（Phase 7 计划里那条补注说的就是这件事）
- 删掉 `.sheet(isPresented: $showingWeeklyGoal) { WeeklyGoalSheet(…) }` 与 `@State private var showingWeeklyGoal`

`Sources/IELTSCoachUI/Today/TodayView.swift`：

- 「本周训练」那格里的「改目标」按钮改成同样的 `navigator.open(.goals); openSettings()`
- 去掉 Phase 7 加的 `@Binding var showingWeeklyGoal: Bool` 参数

`Sources/IELTSCoachUI/Plan/PlanView.swift`：

- **删掉 H 节那整块「练习偏好」**（三个控件与三句说明）
- 原位置换成一行：「默认练习路线、反馈时机、Part 2 准备时间都在设置里改。」加一个按钮「打开设置 › 练习偏好」，走 `navigator.open(.practice); openSettings()`
- **那三句取舍说明不要删，把它们跟着控件一起搬到设置窗口**（Step 4 的表里已要求逐字沿用）。删掉它们等于让用户面对三个不知道该选哪个的开关

- [ ] **Step 7: 写守「一个设置只有一个家」的测试**

`Tests/PackagingTests/SettingsHomeContractTests.swift`：

```swift
import XCTest

/// 守「同一个设置不得有两个入口」。
///
/// Phase 10 之前，录音在 ⌘, 设置窗口、每周目标在首页齿轮、
/// 三项练习偏好在学习计划页页尾。合并之后必须**回不去**——
/// 而「回去」的形式往往只是某个页面里多了一行 `$0.settings.xxx = …`，
/// 代码审查一眼扫过去看不出来，用户却会遇到两个说法不一样的开关。
final class SettingsHomeContractTests: XCTestCase {

    private var sourcesRoot: URL {
        NotarizeScriptTests.repositoryRoot.appending(path: "Sources")
    }

    private func swiftFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func filesMatching(_ pattern: String) throws -> [String] {
        var owners: [String] = []
        for file in try swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.range(of: pattern, options: .regularExpression) != nil {
                owners.append(file.lastPathComponent)
            }
        }
        return owners.sorted()
    }

    func testThereAreFilesToScan() throws {
        XCTAssertGreaterThan(try swiftFiles().count, 20,
                             "扫不到源码，先检查这个路径：\(sourcesRoot.path)")
    }

    func testEverySettingIsWrittenFromExactlyOnePlace() throws {
        // 只匹配 `.settings.<字段> =` 这种「改的是某个 CoachState 里的设置」的写法。
        // CoachSettings 自己的 init 里写的是 `self.weeklyGoal = …`，不在此列，
        // 那是构造，不是入口。
        //
        // **transcriptEnabled 必须在这张清单里**（2026-08-06 复审补入）：
        // 它是 Phase 4 放在训练记录页顶部、又要收进设置窗口的那一个，
        // 也就是四个字段里**唯一真的出现过两个写入口**的那个。
        // 漏掉它，这条测试恰好看不见它本该拦住的那次事故。
        for field in ["transcriptEnabled", "weeklyGoal",
                      "defaultRoute", "feedbackTiming", "part2PrepMode"] {
            let owners = try filesMatching(#"\.settings\."# + field + #"\s*="#)
            XCTAssertEqual(owners, ["CoachSettingsViewModel.swift"],
                           "settings.\(field) 的写入口应当只有设置窗口的视图模型，实际在：\(owners)。"
                           + "同一个设置有两个写入口，迟早会出现两个说法不一样的开关。")
        }
    }

    func testNobodyBypassesTheRecordingConsentHelper() throws {
        // 录音那一格是例外：它得先申请麦克风权限，同意时间戳的规则在 Core 的
        // RecordingConsent 里（它内部写的是 `updated.recordingEnabled = …`）。
        // 别处一旦直接改 `state.settings.recordingEnabled`，就会造出 Phase 5 明令禁止的状态：
        // 开关显示「开」、麦克风权限根本没申请过，用户练完发现什么都没录，且无从查起。
        let offenders = try filesMatching(#"\.settings\.recordingEnabled\s*="#)
        XCTAssertTrue(offenders.isEmpty,
                      "有人绕开 RecordingConsent 直接改了录音开关：\(offenders)")
    }

    /// 训练记录页上那个逐字稿开关必须真的没了（决策表第四行）。
    /// 留着它就是「同一个设置两个家」——而且这两个家改的还是同一个字段，
    /// 只是一个走 AppState、一个走 CoachSettingsViewModel，
    /// **谁后写盘谁说了算**，用户看到的是随机结果。
    func testTheTranscriptToggleLeftTheHistoryPage() throws {
        guard let file = try swiftFiles().first(where: { $0.lastPathComponent == "HistoryView.swift" })
        else { return }   // Phase 4 未交付时跳过
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertNil(text.range(of: #"Toggle\("#, options: .regularExpression),
                     "训练记录页还留着一个开关。逐字稿只在设置窗口的「练习偏好」里改。")
        XCTAssertNil(text.range(of: "setTranscriptEnabled"),
                     "训练记录页还在自己写这个设置")
    }

    func testTheOldWeeklyGoalSheetIsGoneForGood() {
        // 它就是「第二份界面」的定义。留着它，早晚有人把它再挂回某个页面。
        let path = NotarizeScriptTests.repositoryRoot
            .appending(path: "Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                       "WeeklyGoalSheet.swift 还在。每周目标应当只在设置窗口里改。")
    }

    func testTheGearButtonDoesNotFightTheSettingsSceneForCommandComma() throws {
        // Settings 场景自带 ⌘,。别处再挂一个，SwiftUI 不报错，
        // 只会由其中一个随机胜出——用户按 ⌘, 时而弹这个、时而弹那个。
        for name in ["RootView.swift", "TodayView.swift", "PlanView.swift"] {
            guard let file = try swiftFiles().first(where: { $0.lastPathComponent == name })
            else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertNil(text.range(of: #"keyboardShortcut\(\s*","#, options: .regularExpression),
                         "\(name) 里给 ⌘, 挂了第二个动作")
        }
    }
}
```

- [ ] **Step 8: 运行**

Run: `swift test --filter SettingsHomeContractTests`
Expected: PASS（6 个测试）

Run: `swift build && swift test`
Expected: 全绿

Run: `./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"`
Expected: 按 `⌘,` 打开设置窗口，四个分区都在；首页齿轮打开的是**同一个窗口**并停在「训练目标」；学习计划页底部不再有三个开关、训练记录页顶部不再有逐字稿开关，两处都只剩一行说明和一个按钮

- [ ] **Step 9: 突变验证（两条）**

**突变 A —— 让某个设置重新长出第二个家：**
在 `Sources/IELTSCoachUI/Plan/PlanView.swift` 里随便加一行
```swift
_ = app.mutate { $0.settings.feedbackTiming = .immediate }
```
重跑 `swift test --filter SettingsHomeContractTests`。
Expected: `testEverySettingIsWrittenFromExactlyOnePlace` 变红，指出 `feedbackTiming` 在两个文件里被赋值。删掉后确认全绿。

**再用 `transcriptEnabled` 做一次同样的**（在 `HistoryView.swift` 里加 `_ = app.mutate { $0.settings.transcriptEnabled = false }`）：同一条测试必须变红。**这一次是真实发生过的形态，不是假想**——Phase 4 那个开关本来就在那个文件里。删掉后确认全绿。

**突变 B —— 把 `⌘,` 抢回来：**
给 `RootView` 的齿轮按钮加回 `.keyboardShortcut(",", modifiers: .command)`。
重跑：`testTheGearButtonDoesNotFightTheSettingsSceneForCommandComma` 变红。删掉后确认全绿。

把两次输出写进报告。

- [ ] **Step 10: 手动确认同步（这条自动测试替不了）**

主窗口停在「今日训练」，按 `⌘,` 打开设置，把每周目标从 5 改成 9，**不要关设置窗口**，把它拖到一边，直接看主窗口那格「本周 N/M 次」。

Expected: **M 当场就是 9**，不需要点任何地方、不需要切页面、不需要重启。

若要切一下页面才更新，说明两个窗口拿到的不是同一个 `AppState`——回 Step 5 检查是不是哪里又 `AppState()` 了一次。

- [ ] **Step 11: 提交**

```bash
git add Sources/IELTSCoachUI/Settings/ Sources/IELTSCoachUI/AppState.swift \
        Sources/IELTSCoachUI/RootView.swift Sources/IELTSCoachUI/Today/TodayView.swift \
        Sources/IELTSCoachUI/Plan/PlanView.swift Sources/IELTSCoachApp/main.swift \
        Tests/PackagingTests/SettingsHomeContractTests.swift
git commit -m "feat(ui): 设置合并成一个 ⌘, 窗口，四个分区，旧入口改成深链接"
```

---

## Task 17: 「功能升级」页 = 版本与更新记录

**Files:**
- Create: `Sources/IELTSCoachUI/Upgrade/Changelog.swift`
- Create: `Sources/IELTSCoachUI/Upgrade/UpgradeView.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Tests/IELTSCoachUITests/ChangelogTests.swift`
- Modify: `Tests/PackagingTests/PackagingContractTests.swift`

**Interfaces:**
- Consumes: `AppMetadata.current`（Task 3）、`SidebarItem`（Phase 3 Task 3）、`CoachCard` / `SectionHeader`、设计令牌
- Produces:
  - `struct ReleaseNote: Equatable, Identifiable, Sendable`，字段 `version: String`、`date: String`、`headline: String`、`changes: [String]`；`var id: String { version }`
  - `enum PhaseStatus: String, Equatable, Sendable { case shipped, inProgress, planned }`，含 `var title: String`
  - `struct PhaseMilestone: Equatable, Identifiable, Sendable`，字段 `label: String`、`title: String`、`summary: String`、`status: PhaseStatus`；`var id: String { label }`
  - `enum Changelog { static let releases: [ReleaseNote]; static let phases: [PhaseMilestone]; static var current: ReleaseNote }`
  - `struct UpgradeView: View`，`init(metadata: AppMetadata = .current)`
  - `SidebarItem.isImplemented` 对 `.upgrade` 返回 `true`

### 决策：更新记录写成一张 Swift 常量表，不做资源文件、更不在运行时读 git

用户给的约束是「不要在运行时读 git——打包出去的 `.app` 里没有 git 仓库」。剩下两条路各自的代价：

| 做法 | 代价 |
|---|---|
| SPM `resources:` + `Bundle.module` 读 JSON | **`scripts/build-app.sh` 只拷了可执行文件**。SPM 生成的 `IELTSCoachApp_IELTSCoachUI.bundle` 不在 `.app` 里，而 `Bundle.module` 找不到资源包时是 `fatalError` ——**开发时一切正常，打成 `.app` 一点「功能升级」就闪退**。要修就得改打包脚本去拷 `.bundle`，再加一条自检防止它以后被漏掉。为一张版本表付这个代价不值 |
| **手工维护的 Swift 常量表（采用）** | 加一条更新记录要改 Swift 源码。对一个自用工具来说这没什么——版本本来就是跟着代码一起发的 |

**采用常量表，并加一条测试守住「表里的最新版本号 = `build-app.sh` 里的 `APP_VERSION`」。** 没有这条，关于页显示 1.0.1、更新记录最新一条写着 1.0.0 是迟早的事，而那种不一致恰好出现在用户最想搞清楚「我手上这份到底是哪一版」的时候。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/ChangelogTests.swift`：

```swift
import XCTest
@testable import IELTSCoachUI

final class ChangelogTests: XCTestCase {

    func testThereIsAtLeastOneRelease() {
        XCTAssertFalse(Changelog.releases.isEmpty, "「功能升级」页一条记录都没有，等于还是占位页")
    }

    func testVersionsAreUniqueAndNewestFirst() {
        let versions = Changelog.releases.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count, "有重复的版本号")
        for (newer, older) in zip(versions, versions.dropFirst()) {
            XCTAssertEqual(newer.compare(older, options: .numeric), .orderedDescending,
                           "\(newer) 排在 \(older) 前面，但它并不更新")
        }
    }

    func testCurrentIsTheNewestOne() {
        XCTAssertEqual(Changelog.current, Changelog.releases.first)
    }

    func testEveryReleaseSaysWhatChanged() {
        for release in Changelog.releases {
            XCTAssertFalse(release.date.isEmpty, "\(release.version) 没有日期")
            XCTAssertFalse(release.headline.isEmpty, "\(release.version) 没有一句话概括")
            XCTAssertFalse(release.changes.isEmpty, "\(release.version) 一条改动都没写")
            for change in release.changes {
                XCTAssertFalse(change.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(release.version) 里有一条空的改动")
            }
        }
    }

    func testNoEmptyPromises() {
        // 「敬请期待」「即将支持」在一个自用工具的更新记录里没有任何信息量，
        // 而且它们会一直留在那儿——因为没人记得回来删。
        let banned = ["TBD", "待定", "敬请期待", "即将推出", "稍后补充", "todo", "TODO"]
        let everything = (Changelog.releases.flatMap { [$0.headline] + $0.changes }
                          + Changelog.phases.map { "\($0.title)\($0.summary)" }).joined()
        for word in banned {
            XCTAssertFalse(everything.contains(word), "更新记录里出现了「\(word)」")
        }
    }

    // MARK: - 十个阶段

    func testThereAreExactlyTenPhases() {
        // 本项目就是十个阶段（ROADMAP 第 4 节，Phase 0–1 合并算一个）。
        // 断言确切数量：少一个说明漏了，多一个说明有人在这儿加了个不存在的阶段。
        XCTAssertEqual(Changelog.phases.count, 10)
    }

    func testPhaseLabelsAreUniqueAndEndAtTen() {
        let labels = Changelog.phases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "有重复的阶段编号")
        XCTAssertEqual(labels.last, "10", "最后一个阶段不是 Phase 10")
    }

    func testEveryPhaseSaysWhatItIsAndWhereItStands() {
        for phase in Changelog.phases {
            XCTAssertFalse(phase.title.isEmpty, "Phase \(phase.label) 没有标题")
            XCTAssertFalse(phase.summary.isEmpty,
                           "Phase \(phase.label) 没写它给用户带来了什么——只写阶段名等于没写")
            XCTAssertFalse(phase.status.title.isEmpty, "Phase \(phase.label) 的状态没有中文说法")
        }
    }

    func testEveryStatusHasAChineseTitle() {
        // 页面上出现 "inProgress" 这种词，对用户等于没写。
        for status in [PhaseStatus.shipped, .inProgress, .planned] {
            XCTAssertFalse(status.title.isEmpty)
            XCTAssertFalse(status.title.contains(status.rawValue), "\(status) 直接把枚举名显示出来了")
        }
    }

    func testAtLeastOnePhaseIsAlreadyShipped() {
        XCTAssertTrue(Changelog.phases.contains { $0.status == .shipped },
                      "十个阶段全都没交付，那这个 App 是怎么跑起来的")
    }
}
```

在 `Tests/PackagingTests/PackagingContractTests.swift` 里**追加**一条：

```swift
    func testChangelogNewestVersionMatchesWhatTheBuildScriptStamps() throws {
        // 关于页显示 1.0.1、更新记录最新一条写着 1.0.0 —— 这种不一致
        // 恰好出现在用户最想搞清楚「我手上这份到底是哪一版」的时候。
        let script = try text(at: "scripts/build-app.sh")
        let match = try XCTUnwrap(
            script.range(of: #"APP_VERSION="[^"]+""#, options: .regularExpression),
            "build-app.sh 里找不到 APP_VERSION")
        let version = script[match]
            .replacingOccurrences(of: "APP_VERSION=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")

        let changelog = try text(at: "Sources/IELTSCoachUI/Upgrade/Changelog.swift")
        XCTAssertTrue(changelog.contains("version: \"\(version)\""),
                      "更新记录里没有 \(version) 这一版。"
                      + "下一步：要么在 Changelog.releases 顶上补一条，要么改回 build-app.sh 里的 APP_VERSION。")
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ChangelogTests`
Expected: 编译失败 —— `Changelog` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Upgrade/Changelog.swift`：

```swift
import Foundation

/// 一次发布改了什么。
public struct ReleaseNote: Equatable, Identifiable, Sendable {
    public var id: String { version }
    public let version: String
    public let date: String
    /// 一句话概括。用户扫一眼就知道这一版值不值得换。
    public let headline: String
    public let changes: [String]

    public init(version: String, date: String, headline: String, changes: [String]) {
        self.version = version; self.date = date
        self.headline = headline; self.changes = changes
    }
}

public enum PhaseStatus: String, Equatable, Sendable {
    case shipped
    case inProgress
    case planned

    /// 页面上出现 "inProgress" 这种词，对用户等于没写。
    public var title: String {
        switch self {
        case .shipped: return "已完成"
        case .inProgress: return "进行中"
        case .planned: return "还没开始"
        }
    }
}

/// 一个阶段。**summary 写的是「用户因此能做什么」，不是「实现了什么类」。**
public struct PhaseMilestone: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let title: String
    public let summary: String
    public let status: PhaseStatus

    public init(label: String, title: String, summary: String, status: PhaseStatus) {
        self.label = label; self.title = title
        self.summary = summary; self.status = status
    }
}

/// 版本记录与阶段进展。
///
/// **手工维护，运行时不读 git。** 打包出去的 `.app` 里没有 git 仓库，
/// 也不走 SPM 的资源包——`scripts/build-app.sh` 只拷可执行文件，
/// `Bundle.module` 在 `.app` 里会 fatalError，表现是「开发时好好的，
/// 打成 App 一点这一页就闪退」。
///
/// **改这里的时候记得同步 `scripts/build-app.sh` 里的 `APP_VERSION`**——
/// `PackagingContractTests` 有一条测试盯着这两处。
public enum Changelog {

    public static let releases: [ReleaseNote] = [
        ReleaseNote(
            version: "1.0.0",
            date: "2026-08-06",
            headline: "第一个能给别人的版本：双击就能开练，练完自动归档。",
            changes: [
                "今日训练、训练题库、学习计划、复训中心、复盘报告、训练记录、问题档案、我的词汇八页可用",
                "点一下「开始」就会自动打开 ChatGPT、进语音、发考官提示词，全程不用碰终端",
                "练完自动取回复盘并归档到错题本、词汇本与下次的重训目标",
                "可选开启录音，练完能回听自己的回答，可单条删除",
                "支持 CSV / JSON / 文字版 PDF 导入自己的题库",
                "深色模式，跟随系统外观",
                "设置合并成一个窗口（⌘,）：录音、训练目标、练习偏好、数据与隐私",
                "能在 Codex 里通过 MCP 调用，也能用 ieltscoach:// 唤起界面"
            ])
    ]

    public static var current: ReleaseNote { releases[0] }

    /// 本项目的十个阶段（ROADMAP 第 4 节，Phase 0–1 合并算一个）。
    /// **每一条写的是「你因此能做什么」**，不是「实现了哪个类」——
    /// 这一页是给使用者看的，不是给开发者看的。
    public static let phases: [PhaseMilestone] = [
        PhaseMilestone(label: "0–1", title: "探路与地基",
                       summary: "把「能不能用辅助功能驱动 ChatGPT」这件事在真机上试通，并搭好数据存储。",
                       status: .shipped),
        PhaseMilestone(label: "2", title: "驱动与命令行",
                       summary: "完整跑通一场练习：新建会话、启动语音、发提示词、判断结束、取回复盘。",
                       status: .shipped),
        PhaseMilestone(label: "3", title: "图形界面骨架",
                       summary: "有了能双击打开的 App：选题、开练、看复盘不用再开终端。",
                       status: .shipped),
        PhaseMilestone(label: "4", title: "逐字稿与训练记录",
                       summary: "每次练习留下完整问答记录，按月回看考官问了什么、你怎么答的。",
                       status: .shipped),
        PhaseMilestone(label: "5", title: "录音与回听",
                       summary: "可选录下自己的回答，练完回听发音、语调和卡顿。默认关闭。",
                       status: .shipped),
        PhaseMilestone(label: "6", title: "复训中心",
                       summary: "从复盘里挑一个目标带着重练，再换一道题验证是真会了还是只记住了答案。",
                       status: .shipped),
        PhaseMilestone(label: "7", title: "问题档案与词汇本",
                       summary: "看见反复出现的问题有没有变少，积累的词汇可以导出。",
                       status: .shipped),
        PhaseMilestone(label: "8", title: "学习计划与练习路线",
                       summary: "7/14/30 天计划、重点 Part，四条练习路线全部可用。",
                       status: .shipped),
        PhaseMilestone(label: "9", title: "在 Codex 里调用",
                       summary: "通过 MCP 在 Codex 里查题、开练、存复盘，也能直接唤起界面。",
                       status: .shipped),
        PhaseMilestone(label: "10", title: "打包与分发",
                       summary: "签名稳定所以授权不会反复失效，数据目录拷到另一台电脑就能接着用，"
                           + "并且这份 App 可以直接交给别人。",
                       status: .inProgress)
    ]
}
```

**实现时按仓库的真实情况改 `status`。** 若某个阶段实际没交付，就如实写 `.planned` 或 `.inProgress`，**不要为了页面好看全标成已完成**——这一页的全部价值就是「它说的是真的」。

- [ ] **Step 4: 写 `UpgradeView`（只给验收要求，布局自定）**

| 必须做到 | 判据 |
|---|---|
| 顶部显示当前版本 | `AppMetadata.current.versionLine`，旁边一行构建时间与提交号；**不得写死版本号** |
| 更新记录 | 逐条显示 `Changelog.releases`：版本、日期、`headline`、`changes` 列表。**最新一版默认展开** |
| 十个阶段一览 | 逐条显示 `Changelog.phases`：编号、标题、`summary`、`status.title`。状态用 `Palette.success` / `Palette.accent` / `Palette.textSecondary` 区分，**不得用 emoji** |
| 「当前版本」与更新记录最新一条不一致时 | 显示一行提示：「你现在跑的是 X，更新记录里最新的是 Y。下一步：这多半是从源码直接运行的开发版本，跑 `scripts/build-app.sh` 会得到带完整版本信息的 App。」——**开发运行时 `AppMetadata` 全是「未知（开发运行）」，这一页不能因此显得像坏了** |
| 不承诺任何未来功能 | 页面上不得出现「即将」「敬请期待」（测试守着数据层，视图里也不许自己加）|
| 全部走设计令牌 | Task 13 的巡检会扫到这里 |

- [ ] **Step 5: 把「功能升级」标成已实现**

`Sources/IELTSCoachUI/Navigation.swift` 的 `isImplemented` 加上 `.upgrade`；`RootView` 的 `detail` switch 里加 `case .upgrade: UpgradeView()`。

`Tests/IELTSCoachUITests/NavigationTests.swift` 里那条断言「已实现页面的确切集合」的测试同步加上 `.upgrade`。**那条测试断言的是确切集合而不是「至少包含」，就是为了让「标了已实现但没接上视图」当场变红**——只能改期望值，不能改成 `isSuperset`。

- [ ] **Step 6: 运行，确认通过**

Run: `swift test --filter ChangelogTests`
Expected: PASS（10 个测试）

Run: `swift test --filter PackagingContractTests`
Expected: PASS

Run: `swift test`
Expected: 全绿

- [ ] **Step 7: 突变验证（两条）**

**突变 A：** 把 `scripts/build-app.sh` 里的 `APP_VERSION="1.0.0"` 改成 `APP_VERSION="1.0.1"`。
重跑 `swift test --filter PackagingContractTests`：`testChangelogNewestVersionMatchesWhatTheBuildScriptStamps` 必须变红。改回后确认全绿。

**这条守的是「关于页和更新记录说的不是同一个版本」**——那种不一致恰好出现在用户最想搞清楚手上这份是哪一版的时候。

**突变 B：** 把 `Changelog.phases` 里删掉任意一条。
重跑：`testThereAreExactlyTenPhases` 必须变红。加回后确认全绿。

把两次输出写进报告。

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachUI/Upgrade/ Sources/IELTSCoachUI/Navigation.swift \
        Sources/IELTSCoachUI/RootView.swift \
        Tests/IELTSCoachUITests/ChangelogTests.swift \
        Tests/IELTSCoachUITests/NavigationTests.swift \
        Tests/PackagingTests/PackagingContractTests.swift
git commit -m "feat(ui): 功能升级页——版本记录与十个阶段的进展"
```

---

## Task 18: 「问题反馈」页 = 一键复制诊断信息（绝不自动发送任何东西）

**Files:**
- Create: `Sources/IELTSCoachUI/Feedback/LastErrorLog.swift`
- Create: `Sources/IELTSCoachUI/Feedback/FeedbackView.swift`
- Modify: `Sources/IELTSCoachUI/About/DiagnosticsReport.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Tests/IELTSCoachUITests/LastErrorLogTests.swift`
- Modify: `Tests/IELTSCoachUITests/DiagnosticsReportTests.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Tests/PackagingTests/FeedbackPrivacyContractTests.swift`

**Interfaces:**
- Consumes: `DiagnosticsReport` / `DiagnosticsInput`（Task 5）、`AppMetadata.current`（Task 3）、`DataUsage`（Task 14）、`AppState`（`permission`、`permissionMessages`、`recheckPermission()`、`state`）、`CoachError`
- Produces:
  - `enum DiagnosticsStage: String, CaseIterable, Sendable`，含 `var title: String`
  - `struct DiagnosticsError: Equatable, Sendable`，字段 `occurredAt: String`、`stage: DiagnosticsStage`、`code: String`；`var summary: String`
  - `enum DiagnosticsCode { static func of(_ error: any Error) -> String }`
  - `@MainActor @Observable public final class LastErrorLog`，含 `static let shared`、`init()`、`private(set) var last: DiagnosticsError?`、`record(_:at:now:)`、`clear()`
  - `DiagnosticsInput` 追加三个带默认值的参数：`usage: DataUsageReport?`、`environmentMessages: [String]`、`lastError: DiagnosticsError?`
  - `struct FeedbackView: View`，`init(app: AppState, log: LastErrorLog = .shared, directory: DataDirectory = .resolve())`
  - `SidebarItem.isImplemented` 对 `.feedback` 返回 `true`

### 这一页只做一件事，以及它绝不做的两件事

**做：** 把「版本、系统、数据目录与占用、环境检查结果、最近一次错误」凑成一段话，一键复制到剪贴板。粘给谁、发不发，用户自己决定。

**绝不做之一：不自动发送任何东西到任何地方。** 没有「提交」按钮、没有邮件、没有网络请求，连一个「去 GitHub 提 issue」的链接都不放——放了就等于替用户决定了他要把这段话发到哪儿。Task 18 有一条测试扫 `Sources/IELTSCoachUI/Feedback/` 的源码，出现任何联网符号就红。

**绝不做之二：诊断信息里不放任何练习内容。**

Task 5 已经守住了逐字稿、错题原句、词汇、姓名。**本任务新增的「最近一次错误」是一个新的泄漏口，而且是最隐蔽的一个：** `CoachError.invalidReviewText(...)` 的消息里完全可能带着复盘原文的片段，而复盘原文里全是用户说过的英语。

**所以规则是结构性的，不是靠自觉：诊断信息里只记「阶段 + 错误代号 + 时间」，一个字的错误原文都不记。** 错误代号（`review-invalid-text` 这种）保留了全部排障价值，而它不可能包含用户内容。想连原文一起发的人，自己去复盘报告页复制——那是他主动做的选择。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/LastErrorLogTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class LastErrorLogTests: XCTestCase {
    private let secret = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
    private let moment = Date(timeIntervalSince1970: 1_785_931_530)

    func testStartsEmpty() {
        XCTAssertNil(LastErrorLog().last)
    }

    func testRecordsTheStageAndTheCodeButNeverTheMessage() throws {
        // 这是本任务的核心约束。CoachError 的消息里完全可能带着复盘原文的片段，
        // 而复盘原文里全是用户说过的英语。
        let log = LastErrorLog()
        log.record(CoachError.invalidReviewText("复盘里出现了 \(secret)，解析不了"),
                   at: .parsingReview, now: moment)

        let last = try XCTUnwrap(log.last)
        XCTAssertEqual(last.stage, .parsingReview)
        XCTAssertEqual(last.code, "review-invalid-text")
        XCTAssertFalse(last.summary.contains(secret), "把错误原文带进来了：\(last.summary)")
        XCTAssertFalse(last.occurredAt.isEmpty)
    }

    func testOnlyTheMostRecentOneIsKept() {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("a"), at: .fetchingReview, now: moment)
        log.record(CoachError.planImpossible("b"), at: .buildingPlan, now: moment)
        XCTAssertEqual(log.last?.code, "plan-impossible")
    }

    func testClearingActuallyClears() {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("a"), at: .fetchingReview, now: moment)
        log.clear()
        XCTAssertNil(log.last)
    }

    func testEveryCoachErrorHasItsOwnCode() {
        // 六个 case 全挤成一个代号的话，「最近一次错误」就没有排障价值了。
        let errors: [CoachError] = [.invalidReviewText("x"), .reviewNotFound("x"),
                                    .reviewIncomplete("x"), .stateUnreadable("x"),
                                    .questionBankInvalid("x"), .planImpossible("x")]
        let codes = errors.map { DiagnosticsCode.of($0) }
        XCTAssertEqual(Set(codes).count, codes.count, "有两个错误共用了同一个代号：\(codes)")
        for code in codes {
            XCTAssertFalse(code.isEmpty)
            XCTAssertFalse(code.contains("x"), "代号里混进了错误消息：\(code)")
        }
    }

    func testUnknownErrorsStillGetAStableCodeWithoutLeakingAnything() {
        struct SomethingElse: Error { let detail: String }
        let code = DiagnosticsCode.of(SomethingElse(detail: "MY-SECRET-ANSWER"))
        XCTAssertFalse(code.isEmpty, "认不出来也得给个代号，不能是空的")
        XCTAssertFalse(code.contains("MY-SECRET"), "把错误内容带出来了：\(code)")
    }

    func testEveryStageHasAChineseTitle() {
        // 「最近一次错误：parsingReview」对用户等于没写。
        for stage in DiagnosticsStage.allCases {
            XCTAssertFalse(stage.title.isEmpty, "\(stage) 没有中文说法")
            XCTAssertFalse(stage.title.contains(stage.rawValue), "\(stage) 直接显示了枚举名")
        }
    }

    func testSummaryReadsLikeASentenceAndCarriesAllThree() throws {
        let log = LastErrorLog()
        log.record(CoachError.reviewNotFound("x"), at: .fetchingReview, now: moment)
        let summary = try XCTUnwrap(log.last).summary
        XCTAssertTrue(summary.contains(DiagnosticsStage.fetchingReview.title))
        XCTAssertTrue(summary.contains("review-not-found"))
        XCTAssertTrue(summary.contains("2026"), "没带时间：\(summary)")
    }
}
```

在 `Tests/IELTSCoachUITests/DiagnosticsReportTests.swift` 里**追加**四条（既有七条一行不改）：

```swift
    func testDiagnosticsCarryTheEnvironmentCheckOutput() {
        // 「ChatGPT 改版打断自动化」是已知风险（ROADMAP 第 6 节）。
        // 真出问题时，preflight 的原文就是最有用的那几行。
        let text = DiagnosticsReport.text(
            input(environmentMessages: ["✅ 找到 ChatGPT", "❌ 没有辅助功能权限"]))
        XCTAssertTrue(text.contains("没有辅助功能权限"), text)
    }

    func testDiagnosticsCarryTheDataDirectoryUsage() {
        let usage = DataUsageReport(totalBytes: 2_048, stateBytes: 48, reportBytes: 1_000,
                                    recordingBytes: 1_000, pendingReviewBytes: 0, fileCount: 3)
        XCTAssertTrue(DiagnosticsReport.text(input(usage: usage)).contains("KB"),
                      "占用要写成人看得懂的单位")
    }

    /// `LastErrorLog` 是 `@MainActor` 的（它是 `@Observable`，界面直接读），
    /// 所以这一条要标 `@MainActor`，否则 Swift 6 的并发检查过不去。
    @MainActor
    func testTheLastErrorNeverCarriesTheErrorMessageItself() {
        // 这一条是「最近一次错误」这个新字段唯一的存在条件。
        // CoachError 的消息里完全可能带着复盘原文，而复盘原文里全是用户说过的英语。
        let log = LastErrorLog()
        log.record(CoachError.invalidReviewText("复盘里出现了 \(secretAnswer)"),
                   at: .parsingReview, now: Date(timeIntervalSince1970: 1_785_931_530))
        let text = DiagnosticsReport.text(input(lastError: log.last))

        XCTAssertFalse(text.contains(secretAnswer), "诊断信息把错误原文带出去了：\n\(text)")
        XCTAssertTrue(text.contains("review-invalid-text"), "错误代号没带上，等于没记：\n\(text)")
    }

    func testSaysSoWhenNothingHasGoneWrongYet() {
        // 「最近一次错误：」后面空着，比不写还糟。
        let text = DiagnosticsReport.text(input(lastError: nil))
        XCTAssertTrue(text.contains("最近没有出错"), text)
    }
```

`DiagnosticsReportTests` 里那个 `input(...)` 辅助函数相应改成（**只加三个带默认值的参数，既有调用点一个不动**）：

```swift
    private func input(permission: PermissionState = .ready,
                       findings: Int = 0,
                       usage: DataUsageReport? = nil,
                       environmentMessages: [String] = [],
                       lastError: DiagnosticsError? = nil) -> DiagnosticsInput {
        DiagnosticsInput(metadata: metadata(),
                         dataDirectory: URL(fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach"),
                         systemVersion: "macOS 26.5.2",
                         permission: permission,
                         state: loadedState(),
                         portabilityFindingCount: findings,
                         usage: usage,
                         environmentMessages: environmentMessages,
                         lastError: lastError)
    }
```

`Tests/PackagingTests/FeedbackPrivacyContractTests.swift`：

```swift
import XCTest

/// 守「问题反馈页绝不自动发送任何东西」。
///
/// 这一页存在的前提就是「你复制，你决定发给谁」。一旦有人顺手加个
/// 「一键提交」或者一个 GitHub 链接，就等于替用户决定了他的练习环境信息发去哪儿。
final class FeedbackPrivacyContractTests: XCTestCase {

    private var feedbackRoot: URL {
        NotarizeScriptTests.repositoryRoot.appending(path: "Sources/IELTSCoachUI/Feedback")
    }

    private func sources() throws -> [(name: String, text: String)] {
        let urls = try FileManager.default.contentsOfDirectory(at: feedbackRoot,
                                                               includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testThereAreFilesToScan() throws {
        XCTAssertFalse(try sources().isEmpty,
                       "扫不到问题反馈页的源码，先检查这个路径：\(feedbackRoot.path)")
    }

    func testNothingInTheFeedbackPageCanReachTheNetwork() throws {
        for (name, text) in try sources() {
            for forbidden in ["URLSession", "NSURLConnection", "NWConnection",
                              "CFSocket", "mailto:", "http://", "https://"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(name) 里出现了「\(forbidden)」。这一页只能复制到剪贴板，"
                               + "发给谁由用户自己决定。")
            }
        }
    }

    func testTheFeedbackPageUsesTheSharedDiagnosticsTextInsteadOfWritingItsOwn() throws {
        let joined = try sources().map(\.text).joined()
        XCTAssertTrue(joined.contains("DiagnosticsReport.text("),
                      "问题反馈页没有用统一的诊断文本。自己再拼一份的话，"
                      + "Task 5 那些「不许带练习内容」的测试就管不到它了。")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter LastErrorLogTests`
Expected: 编译失败 —— `LastErrorLog`、`DiagnosticsStage`、`DiagnosticsCode` 未定义

- [ ] **Step 3: 实现「最近一次错误」**

`Sources/IELTSCoachUI/Feedback/LastErrorLog.swift`：

```swift
import Foundation
import IELTSCoachCore
import Observation

/// 出错的时候正在干什么。**取值是固定的一组，不是自由文本**——
/// 自由文本迟早会被塞进错误消息。
public enum DiagnosticsStage: String, CaseIterable, Sendable {
    case startingPractice
    case drivingChatGPT
    case fetchingReview
    case parsingReview
    case archivingReview
    case readingState
    case writingState
    case recording
    case importingQuestions
    case buildingPlan

    public var title: String {
        switch self {
        case .startingPractice: return "开始一场练习"
        case .drivingChatGPT: return "操作 ChatGPT"
        case .fetchingReview: return "取回复盘"
        case .parsingReview: return "解析复盘"
        case .archivingReview: return "归档复盘"
        case .readingState: return "读训练数据"
        case .writingState: return "写训练数据"
        case .recording: return "录音"
        case .importingQuestions: return "导入题库"
        case .buildingPlan: return "生成学习计划"
        }
    }
}

/// 一个稳定的错误代号。
///
/// **它替代的是错误原文。** 原文里可能有复盘片段，而复盘片段里全是用户说过的英语；
/// 代号保留了全部排障价值，且不可能包含用户内容。
public enum DiagnosticsCode {
    public static func of(_ error: any Error) -> String {
        if let coach = error as? CoachError {
            switch coach {
            case .invalidReviewText: return "review-invalid-text"
            case .reviewNotFound: return "review-not-found"
            case .reviewIncomplete: return "review-incomplete"
            case .stateUnreadable: return "state-unreadable"
            case .questionBankInvalid: return "question-bank-invalid"
            case .planImpossible: return "plan-impossible"
            }
        }
        // 认不出来时用类型与 NSError 的域/码。这两样都不可能带用户内容，
        // 而「未知错误」这种代号等于什么都没记。
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"
    }
}

/// 最近一次错误。**只有阶段、代号、时间，没有一个字的错误原文。**
public struct DiagnosticsError: Equatable, Sendable {
    public let occurredAt: String
    public let stage: DiagnosticsStage
    public let code: String

    public init(occurredAt: String, stage: DiagnosticsStage, code: String) {
        self.occurredAt = occurredAt; self.stage = stage; self.code = code
    }

    public var summary: String { "\(occurredAt) · \(stage.title) · \(code)" }
}

/// 进程内的「最近一次错误」。**刻意不落盘**：
/// 它是诊断用的即时信息，不是要跟着数据目录搬到另一台电脑的东西
/// （与「引导看过没有」同一条原则，见 Task 8）。
@MainActor
@Observable
public final class LastErrorLog {
    public static let shared = LastErrorLog()

    public private(set) var last: DiagnosticsError?

    public init() {}

    /// 记一次。**只取阶段与代号**——`error` 的消息一个字都不进来。
    public func record(_ error: any Error, at stage: DiagnosticsStage,
                       now: Date = Date()) {
        last = DiagnosticsError(occurredAt: ISO8601DateFormatter().string(from: now),
                                stage: stage, code: DiagnosticsCode.of(error))
    }

    public func clear() { last = nil }
}
```

- [ ] **Step 4: 扩展诊断文本**

`Sources/IELTSCoachUI/About/DiagnosticsReport.swift`：`DiagnosticsInput` 末尾追加三个**带默认值**的参数（`usage: DataUsageReport? = nil`、`environmentMessages: [String] = []`、`lastError: DiagnosticsError? = nil`），Task 5 的既有调用点因此一行都不用改。

`text(_:)` 在「数据可搬迁检查」那一行之后追加：

```swift
        if let usage = input.usage {
            lines.append("数据目录占用：\(usage.summaryText)")
        }
        if input.environmentMessages.isEmpty {
            lines.append("环境检查：没有输出（这本身就不正常，请一并说明）")
        } else {
            lines.append("环境检查：")
            lines += input.environmentMessages.map { "- \($0)" }
        }
        if let error = input.lastError {
            lines.append("最近一次错误：\(error.summary)")
        } else {
            lines.append("最近一次错误：最近没有出错")
        }
        lines.append("——错误只记阶段与代号，不记原文；原文里可能有你说过的英语。")
```

**注意 Task 5 那条 `testNoLineIsBlankOrEndsWithADanglingLabel`：** 「环境检查：」那一行后面必须紧跟至少一条 `- …`，而它自己以「：」结尾——所以那条测试需要放宽成「以『：』结尾的行，下一行必须以 `- ` 开头」。**改测试而不是改行为，这一次是对的**，理由写在测试里：一个后面跟着列表的标题行不是「标签后面没内容」。改法：

```swift
    func testNoLineIsBlankOrEndsWithADanglingLabel() {
        // 「版本：」后面空着，比不写还糟：用户会以为程序坏了。
        // 例外只有一种：以「：」结尾但下一行是列表项（如「环境检查：」后面跟着 - 开头的几行）。
        let text = DiagnosticsReport.text(input(environmentMessages: ["✅ 找到 ChatGPT"]))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "有空行：\n\(text)")
            guard line.hasSuffix("：") else { continue }
            let next = index + 1 < lines.count ? String(lines[index + 1]) : ""
            XCTAssertTrue(next.hasPrefix("- "),
                          "「\(line)」后面既没有内容也没有列表：\n\(text)")
        }
    }
```

- [ ] **Step 5: 写 `FeedbackView`（只给验收要求，布局自定）**

| 必须做到 | 判据 |
|---|---|
| 页面第一句话 | 「这一页不会把任何东西发到任何地方。复制之后要粘给谁、发不发，全由你决定。」——逐字，这是这一页的产品承诺 |
| 诊断信息全文 | 可滚动、可选中（`.textSelection(.enabled)`）。文本来自 `DiagnosticsReport.text(_:)`，**不得自己再拼一份** |
| 「复制诊断信息」按钮 | 整页唯一的主行动。写进 `NSPasteboard.general`，并给一句「已复制」的即时反馈（否则用户不知道点没点上）|
| 一句隐私说明 | 「这段文字里只有版本、系统、数据目录与错误代号，没有你说过的英语、没有题目、没有姓名。」|
| 「重新检查环境」按钮 | 调 `app.recheckPermission()`，刷新页面上的环境检查那几行 |
| 「打开数据目录」按钮 | `NSWorkspace.shared.activateFileViewerSelecting([directory.root])` |
| 最近没有出错时 | **不是空白**。显示「最近没有出错。」加一句「下一步：出问题的时候再回到这一页，把上面这段复制出去。」|
| 没有任何输入框、没有「提交」按钮、没有外链 | 有一条测试扫源码守着（Step 1）|
| 全部走设计令牌 | Task 13 的巡检会扫到这里 |

**把 `LastErrorLog.shared.record(_:at:)` 接到真正会出错的地方**：至少 `PracticeRunner` 的失败分支、复盘取回与解析的失败分支、`StateStore` 读写失败在界面上的捕获处。**接不上的地方就先不接**——`record` 没被调用时这一页显示「最近没有出错」，那是诚实的；比在这里塞一个假的错误好。

- [ ] **Step 6: 把「问题反馈」标成已实现，并确认十项全齐**

`Navigation.swift` 的 `isImplemented` 加上 `.feedback`；`RootView` 的 `detail` switch 里加 `case .feedback: FeedbackView(app: app)`。

`Tests/IELTSCoachUITests/NavigationTests.swift` 里那条确切集合的测试同步更新，并**追加一条**：

```swift
    func testEverySidebarItemIsImplementedByTheEndOfPhase10() {
        // Phase 3 起，未实现的页面显示占位。Phase 10 Task 17 / 18 之后，
        // 十项应当全部有内容——PlaceholderView 就此变成死代码。
        let missing = SidebarItem.allCases.filter { !$0.isImplemented }
        XCTAssertTrue(missing.isEmpty,
                      "这几项还是占位：\(missing.map(\.title))。"
                      + "若它们属于前面某个阶段（训练记录归 Phase 4、复训中心归 Phase 6、"
                      + "问题档案与我的词汇归 Phase 7、学习计划归 Phase 8），"
                      + "**不要改这条测试**——去把那个阶段补上，或者停下来报告。")
    }
```

然后删掉 `RootView.swift` 里的 `PlaceholderView` 与 `detail` switch 的 `default:` 分支，让 switch 变成穷尽的。

**穷尽的 switch 在这里是资产**：将来万一真要动侧边栏，编译器会当场报错，而不是默默显示一个空页面。

- [ ] **Step 7: 运行，确认通过**

Run: `swift test --filter LastErrorLogTests`
Expected: PASS（8 个测试）

Run: `swift test --filter DiagnosticsReportTests`
Expected: PASS（11 个测试 —— Task 5 的 7 条 + 本任务的 4 条）

Run: `swift test --filter FeedbackPrivacyContractTests`
Expected: PASS（3 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 8: 突变验证（三条，都要做）**

**突变 A —— 让诊断信息带上错误原文：**
把 `DiagnosticsError` 加一个 `message` 字段，`record` 里存 `error.localizedDescription`，并在 `summary` 里拼上它。
重跑：`testTheLastErrorNeverCarriesTheErrorMessageItself`（`DiagnosticsReportTests`）与 `testRecordsTheStageAndTheCodeButNeverTheMessage`（`LastErrorLogTests`）必须同时变红。改回后确认全绿。

**这条守的是整页的产品承诺。** 「顺手把错误原文也带上，好排查一点」是一个非常自然的改动，而这段文字的用途就是发给别人看。

**突变 B —— 在反馈页加一个「一键提交」：**
往 `Sources/IELTSCoachUI/Feedback/FeedbackView.swift` 里加一行
```swift
let endpoint = URL(string: "https://example.com/report")!
```
重跑 `swift test --filter FeedbackPrivacyContractTests`：`testNothingInTheFeedbackPageCanReachTheNetwork` 必须变红。删掉后确认全绿。

**突变 C —— 把某个错误代号并到别人身上：**
把 `DiagnosticsCode.of` 里 `.reviewIncomplete` 的返回值改成 `"review-not-found"`。
重跑：`testEveryCoachErrorHasItsOwnCode` 必须变红。改回后确认全绿。

把三次输出写进报告。

- [ ] **Step 9: 人眼复核一次**

```bash
./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

进「问题反馈」页，点「复制诊断信息」，然后 `pbpaste`，**逐行读一遍**：

- 有没有出现你说过的任何一句英语
- 有没有出现题目原文
- 有没有出现姓名
- 每一行是不是都有内容（没有「XX：」后面空着的）
- 「最近一次错误」那行是不是只有时间、阶段、代号

**这是 Step 1 那些测试之外的一次人眼复核，不能省。** 测试只能守住它知道的那几个字符串。

- [ ] **Step 10: 提交**

```bash
git add Sources/IELTSCoachUI/Feedback/ Sources/IELTSCoachUI/About/DiagnosticsReport.swift \
        Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/RootView.swift \
        Tests/IELTSCoachUITests/LastErrorLogTests.swift \
        Tests/IELTSCoachUITests/DiagnosticsReportTests.swift \
        Tests/IELTSCoachUITests/NavigationTests.swift \
        Tests/PackagingTests/FeedbackPrivacyContractTests.swift
git commit -m "feat(ui): 问题反馈页——一键复制诊断信息，绝不自动发送"
```

---

## Task 19: 追加部分的真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。追加进 `docs/phase10-acceptance.md`

**Task 11 与本任务合起来才是整个 Phase 10 的验收。** 建议一次做完：先按 Task 11 走一遍（签名稳定性、关于页、引导、拷给别人、换机器、麦克风），再走下面这些。

- [ ] **Step 1: 深色模式逐页看**

系统设置 › 外观切到「深色」，**App 保持开着**，十页 + 关于窗口 + 设置窗口 + 引导页 + 练习中的 sheet 逐个看过去。

| 看什么 | 判据 |
|---|---|
| 有没有哪一行字看不见 | 一行都不许有。发现一处就回 Task 13 Step 3 修 |
| 卡片 | 比背景亮一点，不是一个洞 |
| 主行动卡片 | 浅紫底 + 近黑字，读得清 |
| 图表、进度条、状态色 | 成功/警告/危险三种颜色在深色底上都读得清，且彼此分得开 |
| 切回浅色 | 一切照旧，没有深色残迹 |
| **在深色下重新看一遍浅色改过的两个语义色** | Task 12 把 `success` 与 `warning` 调深了（原值对比度不达标）。**浅色下它们现在明显更深，请确认能接受**；不能接受就说，重调的前提是仍 ≥ 4.5:1 |

- [ ] **Step 2: 设置窗口**

| 看什么 | 判据 |
|---|---|
| `⌘,` | 打开设置窗口，四个分区都在，每个分区顶部有一句「这一栏管什么」|
| 首页齿轮 | 打开的是**同一个窗口**，且停在「训练目标」 |
| 学习计划页底部 | 只有一行说明 + 一个「打开设置 › 练习偏好」按钮，**没有三个开关** |
| 训练记录页顶部 | 只有一行「逐字稿记录：开 · 在设置里更改」+ 按钮，**没有开关**；点按钮打开的是同一个窗口并停在「练习偏好」 |
| **跨窗口同步** | 主窗口停在「今日训练」，`⌘,` 把每周目标 5 改成 9，**不关设置窗口**，直接看主窗口那格 —— **M 当场就是 9** |
| 录音分区 | 与 Phase 5 那个窗口完全一样（因为就是同一个视图）；开一次关一次，占用数字跟着变 |
| 数据与隐私分区 | 路径正确，占用与 Finder 显示的接近，「在访达中显示」打开的是对的文件夹 |
| 改设置失败时 | 把数据目录改成只读再改一次设置，看是不是显示了中文错误、且控件回到了落盘的事实 |

- [ ] **Step 3: 「功能升级」页**

| 看什么 | 判据 |
|---|---|
| 当前版本 | 与 `codesign` 出来的 `.app` 的 `CFBundleShortVersionString` 一致 |
| 更新记录 | 读一遍，有没有说得不准的地方 |
| 十个阶段 | **逐条核对状态**。标成「已完成」但实际没做的，当场改掉——这一页的全部价值就是它说的是真的 |

- [ ] **Step 4: 「问题反馈」页**

| 看什么 | 判据 |
|---|---|
| 复制出来的内容 | `pbpaste` 逐行读，没有任何练习内容、题目、姓名 |
| 「最近一次错误」 | 人为制造一次失败（练习中途把 ChatGPT 关掉），回到这一页看它有没有记上，且只有时间、阶段、代号 |
| 页面上有没有任何「发送」的入口 | 一个都不该有 |
| 找一个不懂技术的人读一遍 | 他知不知道这一页要他做什么 |

- [ ] **Step 5: 侧边栏十项全齐**

点一遍十项，**一项都不该再是「还没做」的占位页**。

若有，说明前面某个阶段没交付完（训练记录归 Phase 4、复训中心归 Phase 6、问题档案与我的词汇归 Phase 7、学习计划归 Phase 8）。**如实记下来，不要通过改测试让它变绿。**

- [ ] **Step 6: 系统「减弱动态效果」与最大字号**

打开系统「减弱动态效果」：设置窗口切分区、引导页翻页、「功能升级」展开更新记录，都应无动画且功能正常。

系统文字调到最大档：设置窗口四个分区、「功能升级」页的更新记录、「问题反馈」页的诊断全文都不截断、不重叠。

- [ ] **Step 7: 记录并提交**

把每一项的实际结果追加进 `docs/phase10-acceptance.md`，**包括不好的部分**——「哪里让我不想用」这类信息只有使用者有（成品标准第 5 节）。

```bash
git add docs/phase10-acceptance.md
git commit -m "docs: Phase 10 追加部分（深色模式、设置合并、两页）的验收结果"
```

---

## 需要用户参与的环节（任何自动化都绕不过去）

集中列在这里，避免零散打断。

| 环节 | 在哪一步 | 用户要做什么 |
|---|---|---|
| **确认许可条款** | Task 6 开工前 | 默认「保留所有权利，个人自用」。若想开源（MIT 之类），现在说，改 `LICENSE` 与 `AboutViewModel.licenseNotice` 两处即可 |
| **确认版本号** | Task 1 | 计划里定为 `1.0.0`。若想用别的，改 `build-app.sh` 里的 `APP_VERSION` 一处 |
| 授予辅助功能权限 | Task 1 Step 4、Task 11 | 系统设置 › 隐私与安全性 › 辅助功能，勾选本 App |
| 允许麦克风 | Task 11 Step 7 | 弹窗点「允许」 |
| **第二台 Mac（或第二个用户账号）** | Task 11 Step 5、6 | 这两条**必须**在另一台机器上做。Gatekeeper 与 TCC 都是按机器算的，本机自己测不出来 |
| 界面观感判断 | Task 11 Step 3、4、8 | 关于页与引导页读起来顺不顺、说得清不清楚 |
| 公证（**本期不做**） | 将来 | 加入 Apple Developer Program（按年付费）→ 申请 Developer ID Application 证书 → `xcrun notarytool store-credentials` 存凭据 → `./scripts/notarize.sh --execute`。脚本会在动手前把「辅助功能授权会失效一次」和「要更新签名基线」两件事打出来 |
| **确认调深后的成功色与警告色** | Task 12 | 浅色的 `success`（原 3.64:1）与 `warning`（原 2.72:1）低于设计规范那条不可协商的 4.5:1，Task 12 把它们调深了，**看上去会明显更深**。能接受就不用说话；不能接受就说，重调的唯一前提是仍 ≥ 4.5:1 |
| **深色模式逐页看一遍** | Task 13 Step 5、Task 19 Step 1 | 十页 + 关于窗口 + 设置窗口 + 引导页 + 练习中的 sheet。**「哪一行字在深色下看不见」只有眼睛能判断**，测试只能守住令牌本身 |
| **确认四处旧设置入口的去留** | Task 16 | 计划里已经定了（`⌘,` 升级、首页齿轮改成深链接、学习计划页页尾撤掉、**训练记录页顶部的逐字稿开关撤掉**），理由见 Task 16 那张表。若你更希望某一处保留原样，现在说。**第四处是 2026-08-06 复审补进来的**：Phase 4 把逐字稿开关放在训练记录页顶部，不收口的话它会是唯一一个真的有两个写入口的设置 |
| **核对十个阶段的状态** | Task 17 Step 3、Task 19 Step 3 | 「功能升级」页把十个阶段的进展写成了一张表。**标成「已完成」但实际没做的，必须当场改掉**——这一页的全部价值就是它说的是真的 |
| **人眼复核一次诊断信息** | Task 18 Step 9、Task 19 Step 4 | `pbpaste` 之后逐行读，确认没有任何你说过的英语、题目原文、姓名。测试只能守住它知道的那几个字符串 |

---

## Phase 10 完成标准

- [ ] `swift test` 全绿；新增测试 120 条左右（Task 1–11 约 60 条 + Task 12–18 约 60 条），且**每一条关键逻辑都做过突变验证**，输出写进了报告
- [ ] `./scripts/build-app.sh` 产出的包带 `flags=0x10000(runtime)` 与麦克风 entitlement，且四项自检全过
- [ ] `./scripts/verify-signature-stability.sh` 通过：**连打两次，`codesign -d -r-` 的 designated 完全一致，且两次 CDHash 不同**（证明比较不是空转）
- [ ] `packaging/expected-designated-requirement.txt` 已提交，内容形如 `designated => identifier "com.ielts.speakingcoach" and certificate leaf = H"…"`，**不含 cdhash**
- [ ] 加了 Hardened Runtime 与 entitlements 之后，**授权过一次，重新打包不需要再授权**（真机验证）
- [ ] `packaging/IELTSCoach.entitlements` 只有麦克风一条，且有测试拦着不让加别的
- [ ] 关于页可从苹果菜单打开，六行信息齐全，「在访达中显示」「复制诊断信息」「重新检查」都能用
- [ ] 诊断信息里**没有任何练习内容**（测试守着 + 人眼复核过一次）
- [ ] 首次引导走得通；已走过引导的人只在环境不就绪时再看到它
- [ ] `./scripts/package-app.sh` 产出的 zip 解压后签名仍然有效，附带的「如何打开.txt」能让别人真的打开它
- [ ] `./scripts/notarize.sh` 的 dry-run 在**没有 Developer ID 的机器上**跑得通，打印全部五步，并警告换证书会让辅助功能授权失效
- [ ] `./scripts/verify-portability.sh` 通过，**且带负例**
- [ ] **成品标准第 10 条真机验证：把 `~/Library/Application Support/IELTS Speaking Coach/` 拷到第二台电脑，题库、训练记录、复盘、录音、错题本、词汇本全都对得上，接着就能用**
- [ ] `DESIGN-SYSTEM.md` 第 6 节十条清单在关于页与引导页上全部通过
- [ ] `docs/phase10-acceptance.md` 写完，含不好的部分

**Task 12–19（深色模式、设置合并、两页）：**

- [ ] `Palette` 有两套静态取值，**两套外观下每一组前景/背景配对都 ≥ 4.5:1**，由 `AppearanceContrastTests` 的矩阵逐对验证
- [ ] 对比度计算**会合成 alpha**——`ContrastMath.ratio(Color.black.opacity(0.56), over: .white)` 约等于 4.94，不是 21
- [ ] 有一条测试保证「深色确实是深的」，把 `tokens(for: .dark)` 改成返回浅色时它会红（**矩阵那条不会红，所以这条不能省**）
- [ ] 浅色的 `success` / `warning` 已调到 4.5:1 以上，并已请用户确认过观感
- [ ] `Sources/IELTSCoachUI/` 下除 `DesignSystem/` 外，**没有任何字面颜色、字面字号、字面圆角**，由 `DesignTokenContractTests` 扫源码守着；扫不到文件时它自己会红
- [ ] 十页 + 关于窗口 + 设置窗口 + 引导页在深色下逐个看过，**没有一行字是看不见的**
- [ ] 深色只跟随系统，**没有**新增「浅色/深色/跟随系统」这类开关
- [ ] `⌘,` 打开的设置窗口有且只有四个分区：录音、训练目标、练习偏好、数据与隐私
- [ ] **七个**用户可配置项全在这个窗口里（含 Phase 4 的「记录对话逐字稿」）；`SettingsHomeContractTests` 保证**每个设置只有一个写入口**（清单里必须有 `transcriptEnabled`），且没人绕开 `RecordingConsent` 直接改录音开关
- [ ] `WeeklyGoalSheet.swift` 已删除；`AppState` 上的 `setWeeklyGoal` / `settingsError` / `setTranscriptEnabled` 三样已删除
- [ ] 首页齿轮、学习计划页、训练记录页的按钮打开的是**同一个窗口**（深链接到对应分区）；训练记录页顶部不再有逐字稿开关
- [ ] `⌘,` 只有一个动作绑着（`Settings` 场景），别处没有第二个 `keyboardShortcut(",")`
- [ ] **在设置窗口改一个值，主窗口当场就变**：有自动化测试（两个视图模型共用一个 `AppState`），也在真机上肉眼确认过一次
- [ ] 「功能升级」页显示当前版本、各版本改了什么、十个阶段的进展；**最新版本号与 `build-app.sh` 里的 `APP_VERSION` 一致**（有测试守）
- [ ] 更新记录**运行时不读 git**，也不依赖 SPM 资源包（`.app` 里没有那两样）
- [ ] 十个阶段的状态**逐条核对过**，没有把没做的标成已完成
- [ ] 「问题反馈」页能一键复制诊断信息，诊断信息里含版本、系统、数据目录与占用、环境检查结果、最近一次错误
- [ ] 诊断信息里的「最近一次错误」**只有时间、阶段、错误代号，没有一个字的错误原文**（原文里可能有用户说过的英语）
- [ ] 「问题反馈」页**不会把任何东西发到任何地方**：没有提交按钮、没有外链、源码里扫不到任何联网符号（有测试守）
- [ ] 侧边栏**十项全部有内容**，`PlaceholderView` 已作为死代码删除，`RootView` 的 switch 是穷尽的

达成后，整个项目的十二条成品标准应当全部可当场演示。**若还剩哪一条演示不出来，写进验收报告，那是下一步的输入，不是可以含糊过去的事。**

---

## 附录：2026-08-06 夜间拍板的七个决策

跨阶段复审留下的开放问题，用户不在场（夜间无人值守），**按本项目既有原则逐条定下**。全部记在这里，便于早上一次性复核。

**其中只有决策 7 由本文件实施（Task 12–19）。决策 1–6 归 Phase 4 与 Phase 6，写在这里是为了不丢——写那两份计划时必须照此执行。**

| # | 决策 | 归属 | 状态（2026-08-06 复审后更新）|
|---|---|---|---|
| 1 | 会话编号统一成 `YYYY-MM-DD-NNN`，但 `SessionID.validated` 必须同时接受旧的 ISO8601 形状 | Phase 4 | ✅ 已写进 Phase 4 计划 Task 1（白名单含 `:` 与 `+`，两头都有测试）|
| 2 | 复盘取回失败后的补救做进界面（复盘报告页加「重新导入待处理的复盘」）| Phase 4 | ✅ Phase 4 Task 7 + Task 11 |
| 3 | `.history`（训练记录）由 Phase 4 标进 `SidebarItem.isImplemented` | Phase 4 | ✅ Phase 4 Task 9 |
| 4 | 单条训练记录删除归 Phase 4，且必须同时清理关联录音 | Phase 4 | ✅ Phase 4 Task 10（连复盘报告文件一起删，确认框逐条列明）|
| 5 | 「记录对话逐字稿」开关归 Phase 4，加进 `CoachSettings`，默认开 | Phase 4 | ✅ Phase 4 Task 2 + Task 9；**旧入口的收口在本文件 Task 16**（决策表第四行）|
| 6 | 复训目标 label 为空时回落成 targetKey 照常开练 | Phase 6 / **Phase 8** | ✅ Phase 6 本来就是这个做法；**Phase 8 Task 8 原本写的是「拒绝并说明下一步」，2026-08-06 复审已改成调 `RetrainingSetupBuilder.goalText(for:)`**，测试与突变验证一并改了 |
| 7 | 深色模式、设置合并、「功能升级」「问题反馈」两页全部推到 Phase 10 | **Phase 10** | **本文件 Task 12–19** |

### 逐条的决策与理由

**决策 1 —— 会话编号统一成 `YYYY-MM-DD-NNN`（如 `2026-08-05-003`）。**

人能读、能排序，而且模型注释与 Phase 9 的 `SessionID.next` 都已经是这个形状。

**但 `SessionID.validated` 必须同时接受旧的 ISO8601 形状**（`2026-08-05T14:03:11Z`）——用户现有的 `state.json` 里已经有那种 id 了，**拒绝它等于让已有练习记录全部失效**。新产生的一律用新形状。这条要有测试守：旧 id 读得进来，新 id 是新形状。

**决策 2 —— 复盘取回失败后的补救必须做进界面。**

现在唯一途径是终端里跑 `coach reimport`，这让成品标准第 2 条「全程不需要打开终端」在出错时不成立——**而出错恰恰是最需要它成立的时候**。在复盘报告页加一个「重新导入待处理的复盘」入口：列出 `pending-reviews/` 里的条目（时间、题目、字节数），可单条重试、可查看原文、可删除。归 Phase 4。

**决策 3 —— `.history`（训练记录）由 Phase 4 标进 `SidebarItem.isImplemented`。**

现有七份计划里没有一份认领这件事。**本文件 Task 18 Step 6 那条「十项全部已实现」的测试会把它兜住**：Phase 4 没做的话，那条测试会红并点名是哪几项，而它明确写着「不要改这条测试，去把那个阶段补上或停下来报告」。

**决策 4 —— 单条训练记录删除归 Phase 4**（ROADMAP Phase 4 交付清单第三条）。

删除必须**同时清理关联的录音文件**，否则会留下永远不会被引用的孤儿文件把磁盘吃满。Phase 5 尚未交付时，这段清理逻辑要写成「有 `recordingPath` 就删，没有就跳过」，不能硬依赖。

**决策 5 —— 「记录对话逐字稿」开关归 Phase 4**，加进 `CoachSettings`，**默认开**（ROADMAP 第 5 节）。

Phase 7 与 Phase 8 都会「整体替换」`CoachSettings`，那两份计划里已加了警示要保留既有字段；**Phase 4 的计划里也要点名提醒这件事**。

对本文件的影响（**2026-08-06 复审后已细化**）：那个开关归设置窗口的「练习偏好」分区，Task 15 已写明怎么接（含确认方式 `grep -n "transcriptEnabled" Sources/IELTSCoachCore/Model/CoachState.swift`），**且明确要求不要在 Phase 10 替 Phase 4 加这个字段**——默认值与解码容错归 Phase 4 定。

Phase 4 把开关放在了**训练记录页顶部**（因为 Phase 5 才建 ⌘, 场景），并在 `AppState` 上留了 `setTranscriptEnabled(_:)`。**收口在 Task 16**：那张「旧入口去留」表的第四行撤掉开关本体与 `AppState` 上的写方法，`SettingsHomeContractTests` 的字段清单里也已补上 `transcriptEnabled`——它是四个字段里唯一真的出现过两个写入口的那个。

**决策 6 —— 复训目标 label 为空时，一律回落成 targetKey 照常开练**（Phase 6 的做法），不采用 Phase 8 的「拒绝并说明下一步」。

理由：用户是来练英语的，因为一个内部字段是空的就不让他练，这个代价不成比例。

**2026-08-06 复审补记：** 这条当时只写在决策文件里，Phase 8 的计划**没有跟着改**——它的 `resolveRetrain` 仍然返回 `.unavailable(…)`，还有一条 `testRetrainRefusesAnEmptyTargetLabel` 和一条突变验证在守着相反的行为。照原样执行的话，「从复训中心进」和「从今日训练页进」会是两种行为，正是决策 6 要消除的东西。**已就地改掉 Phase 8 Task 8**：实现改成调 Phase 6 的 `RetrainingSetupBuilder.goalText(for:)`，测试改名为 `testRetrainFallsBackToTheTargetKeySoTheGoalIsNeverBlank`，突变验证改成「取消回落」。

**决策 7 —— 深色模式、设置合并、「功能升级」「问题反馈」两页，全部推到 Phase 10。**

理由：这三样都是**跨所有页面**的收尾工作，在所有页面存在之前做等于返工。具体到每一样：

- **深色模式**：每新写一页就要重新验一遍两套外观的对比度。等页面写齐再一次做完，验一遍就够。
- **设置合并**：合并的前提是四个分区的内容都到齐了（「数据与隐私」要显示占用，那是本阶段 Task 14 才有的东西）。提前合等于合到一半再拆。
- **两页**：「功能升级」要写十个阶段的进展——阶段没走完，那张表写不出真话；「问题反馈」的诊断信息要包含数据目录占用与环境检查，同样得等前面的东西齐了。

**本决策的代价也要说清楚：** 在 Phase 10 之前，深色模式下的界面是坏的（写死的颜色会让某些文字看不见），设置是散在三处的，两页是占位。**这段时间只有作者本人在用，可以接受；但它意味着 Phase 10 不做完，这个 App 不能给别人。** 这与本阶段的交付定义（「一个能给别人的 `.app`」）正好一致。
