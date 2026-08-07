# Phase 8：学习计划页 + 完整练习路线

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付「学习计划」页——选 7/14/30 天周期、选重点 Part、看每日拆分与进度、随时调整并重新生成；同时把「按计划练今天」「继续上次练习」「复训一个旧问题」三条练习路线真正接通（第四条「从题库自由选题」在 Phase 3 已接通）。四条路线全部可用，且**界面上显示出来的路线，点下去一定能开练**。

**本阶段的硬底线：重新生成计划时不能丢掉已有进度。** 这是成品标准第 7 条「任何一步失败，已产生的内容都还在」在本阶段的具体形态。用户可能已经按 7 天计划练了 3 天，然后想改成 14 天、或把重点从全真模考换成 Part 2——那 3 天不能白练。这条要求有独立的任务（Task 4）与突变验证。

**Architecture:** 纯逻辑下沉到 `IELTSCoachCore`（只依赖 Foundation），展示逻辑放 `IELTSCoachUI` 的视图模型，`View` 只负责摆布局。四条练习路线由一个**单一解析函数** `PracticeRouteResolver.resolve` 统一变成 `SessionSetup`，再交给 Phase 3 已有的 `PracticeRunner` 执行——这样「哪条路线能用」与「这条路线练哪道题」只有一处定义，不会两处打架。

**Tech Stack:** Swift 6.3.3、SPM、SwiftUI、XCTest。无第三方依赖。

---

## Global Constraints

这一节的每一条都是硬性约束，违反即视为本阶段未完成。

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit 的代码必须放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 `IELTSCoachCore`、`ChatGPTBridge`、`IELTSCoachAudio`（Phase 5 加的）、SwiftUI
- **所有面向用户的文案必须是中文，且同时说明「发生了什么」和「下一步做什么」。** 这条不只管错误信息，也管警告、空状态、确认弹窗、按钮旁的说明
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- **界面必须走设计令牌**（`Palette` / `Spacing` / `Radius`，见 `docs/superpowers/DESIGN-SYSTEM.md`）。视图里不得出现字面颜色、字号、圆角
- 涉及外部应用能力的判断，**一律以在运行中的应用上实测为准**，不接受从二进制内容、框架清单、Info.plist 措辞推断出的结论
- 测试用 XCTest
- **本阶段的单元测试一律不驱动真实 ChatGPT。** 所有需要 `CoachBridge` 的地方用假实现。真机验证集中在 Task 11，由人工完成

---

## 依赖与前置条件

### 依赖 Phase 3（已交付，可直接使用）

确切签名见 `docs/superpowers/plans/2026-08-05-phase3-gui-shell.md` 各任务的 Interfaces 块。本阶段用到：

| 符号 | 出处 | 本阶段怎么用 |
|---|---|---|
| `Palette` / `Spacing` / `Radius` | Phase 3 Task 7 | 学习计划页的全部样式 |
| `CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView` | Phase 3 Task 7 | 计划页与路线卡片 |
| `@Observable final class AppState`（`state: CoachState`、`reload()`、`private let store: StateStore`）| Phase 3 Task 3 | Task 9 给它加一个 `mutate` |
| `enum SidebarItem`（含 `isImplemented`）| Phase 3 Task 3 | Task 9 把 `.plan` 标为已实现 |
| `RootView` 的 `detail` switch | Phase 3 Task 3 | Task 9 加 `case .plan` |
| `enum PracticeRoute`（`planToday` / `freePick` / `continueLast` / `retrain`，含 `title`、`subtitle`）| Phase 3 Task 6 | 本阶段**不重新定义它**，只加解析与排序 |
| `struct TodayViewModel`（`init(state:today:)`、`availableRoutes`、`todayQuestions`）| Phase 3 Task 6 | 保留；Task 8 的可用路线判断必须是它的子集 |
| `@MainActor @Observable final class PracticeRunner`（`start(setup:) async throws`、`finishPractice()`、`cancel()`、`stage`）| Phase 3 Task 9 | Task 10 把解析出来的 `SessionSetup` 交给它 |
| `PracticeSheet` | Phase 3 Task 9 | Task 10 从计划页/今日训练页弹出它 |

### 依赖 Phase 6（复训中心）——本阶段**不假设它存在**

ROADMAP 把 Phase 8 的依赖写成 Phase 6。真实的依赖关系是这样的：

- 「复训一个旧问题」这条路线**所需的全部数据在 Phase 0–2 就已经就绪**：`state.targets`（`RetrainingTarget`）、`RetrainingPolicy.rank(targets:issues:)`、`PracticeSession.goal`、`ExaminerPrompt` 里的「本次唯一目标」段落。因此本阶段可以独立把这条路线接通，**不需要 Phase 6 的任何符号**。
- Phase 6 交付的是**复训中心页**（回看证据 → 重答原题 → 撤掉提示 → 换题验证）这套更完整的流程。本阶段交付的是**从今日训练页一键带着最优先的目标重答原题**。
- **如果 Phase 6 已经交付了复训中心页**，Task 10 的「复训」卡片应当改成先导航到复训中心（一处改动，Task 10 Step 5 写明了怎么改），而 `PracticeRouteResolver` 仍然是「目标 → 题目 → SessionSetup」的唯一实现，Phase 6 的页面也该复用它。
- **如果 Phase 6 尚未交付**，本阶段照常完成，「复训」路线直接开练。

**所以：本阶段没有任何一个任务会因为 Phase 6 未完成而做不了。** 实现者不需要去找 Phase 6 的代码。

### 本阶段需要的、Phase 3 没有提供的东西（在 Task 9 里补）

- `AppState` 只有读（`reload()`），**没有写**。学习计划页要生成/重新生成/删除计划、要保存练习偏好，必须能写。Task 9 给 `AppState` 加一个 `mutate(_:) -> String?`。
- **`AppState` 不能放进单元测试。** 它的 `init` 会调 `recheckPermission()` → `AXDriver.preflight()`，而 `preflight()` 在 ChatGPT 没运行时会**真的去启动 ChatGPT**，并最多等 8 秒唤醒无障碍树（见 `Sources/ChatGPTBridge/AXDriver.swift` 第 18–46 行）。在测试里构造它等于每跑一次测试就弹一次 ChatGPT。因此本阶段所有可测逻辑都做成不依赖 `AppState` 的纯函数，`AppState.mutate` 本身只有三行、由 Task 11 人工验收。

---

## 范围边界：本阶段明确不做的事

写下来是为了防止范围膨胀，也为了让实现者不去猜。

| 不做 | 为什么 | 归谁 |
|---|---|---|
| 按日历推进计划（「你落后 2 天」）| 计划里没有日期字段，进度只随「练完一题」前进。请假两天回来就被界面指责，只会让人不想练 | 永久不做，见 Task 5 的注释 |
| 复盘失败时也推进计划进度 | 计划进度由 `ReviewArchiver.advancePlan` 在归档时前进。复盘取不回来时原文已落盘在 `pending-reviews/`，**到「复盘报告」页点「重新导入待处理的复盘」补进去即可**（Phase 4 Task 11，跨阶段决策 2），进度随之前进。在这里额外加一条「没复盘也算练过」的路径，会让用户开练 3 秒就退出也被算成完成 | 已有机制覆盖，本阶段不动。**本阶段任何面向界面的文案都不许再让用户去终端跑 `coach reimport`**——那是成品标准第 2 条 |
| 换题验证（同一目标换一道题再练）| 这是 Phase 6 复训中心的核心流程 | Phase 6 |
| 每周训练次数目标可配置 | ROADMAP 第 5 节把它排在 Phase 7 | Phase 7 |
| 深色模式 | 全部颜色已走令牌，Phase 7 改一个文件即可 | Phase 7 |
| 改 `PlanBuilder.build` 的签名 | 它是 Phase 0–2 冻结的代码，已有 7 条测试覆盖。本阶段只在它外面包一层 | 不动 |

---

## File Structure

```
Sources/
├── IELTSCoachCore/
│   ├── Model/
│   │   ├── TrainingPlan.swift              Modify  加 focusPart + 向后兼容解码
│   │   └── CoachState.swift                Modify  CoachSettings 加三项练习偏好 + 向后兼容解码
│   └── QuestionBank/
│       ├── PlanScope.swift                 Create  按重点 Part 选题 / 可行性判据 / 中文标签
│       └── PlanRegenerator.swift           Create  重新生成计划且不丢进度
├── IELTSCoachUI/
│   ├── Navigation.swift                    Modify  .plan 标为已实现
│   ├── RootView.swift                      Modify  detail 里加 case .plan
│   ├── AppState.swift                      Modify  加 mutate(_:) -> String?
│   ├── Plan/
│   │   ├── PlanViewModel.swift             Create  计划页的只读展示逻辑
│   │   ├── PlanDraft.swift                 Create  生成前的草稿与预览
│   │   └── PlanView.swift                  Create  学习计划页（只给验收要求）
│   ├── Session/
│   │   ├── PracticeRoutePreference.swift   Create  默认路线 + RouteDefaults
│   │   └── PracticeRouteResolver.swift     Create  四条路线 → SessionSetup
│   └── Today/
│       └── TodayView.swift                 Modify  三条路线接通（只给验收要求）
Tests/
├── IELTSCoachCoreTests/
│   ├── TrainingPlanCodableTests.swift          Create
│   ├── CoachSettingsCompatibilityTests.swift   Create
│   ├── PlanScopeTests.swift                    Create
│   └── PlanRegeneratorTests.swift              Create
└── IELTSCoachUITests/
    ├── PlanViewModelTests.swift                Create
    ├── PlanDraftPreviewTests.swift             Create
    ├── PracticeRoutePreferenceTests.swift      Create
    ├── PracticeRouteResolverTests.swift        Create
    └── NavigationTests.swift                   Modify  已实现页面集合加 .plan
docs/
└── phase8-acceptance.md                        Create  Task 11 的人工验收记录
```

### 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给验收要求不给代码——这是刻意的，不是省略。**

理由与 Phase 3 一致（见该计划第 79–86 行）：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务写明「必须显示什么、空状态说什么、失败时说什么、确认弹窗的原话是什么」，具体怎么摆由实现者定，由设计令牌约束，再由 Task 11 的人工验收把关。

这与「禁止占位符」不冲突：占位符是「TBD、以后再说」，而这里给的是可以逐条打勾的验收标准。若实现者认为某处要求不清楚到无法动手，**应当停下来问，而不是猜**。

---

## Task 1: `TrainingPlan` 记住重点 Part，且旧数据仍然读得出来

**Files:**
- Modify: `Sources/IELTSCoachCore/Model/TrainingPlan.swift`
- Create: `Tests/IELTSCoachCoreTests/TrainingPlanCodableTests.swift`

**Interfaces:**
- Consumes: `FocusPart`（`Sources/IELTSCoachCore/Model/FocusPart.swift`，`String` 原始值 `"Part 1"` / `"Part 2"` / `"Part 3"` / `"full mock"`）
- Produces:
  - `TrainingPlan.focusPart: FocusPart`（新增存储属性）
  - `TrainingPlan.init(lengthDays: Int, createdAt: String, days: [PlanDay], focusPart: FocusPart = .fullMock)`
  - `TrainingPlan.init(from: any Decoder) throws`（手写，缺字段时回落 `.fullMock`）

**为什么必须做：** 计划页要显示「这个计划的重点是 Part 2」，重新生成时要以当前重点为默认值。计划本身不记这件事，重开 App 就忘了用户选过什么。

**这一步真正的风险不是加字段，是加字段的方式。** `CoachState.init(from:)` 用 `decodeIfPresent(TrainingPlan.self, forKey: .plan)` 读计划——**`decodeIfPresent` 只在键不存在时返回 nil；键存在但里面缺字段，仍然会抛错**，而这个错会一路冒泡出去，让 `StateStore` 报「训练数据文件已损坏」。用户硬盘上那份 state.json 是旧版本写的，plan 里没有 `focusPart`。若解码要求这个字段必须存在，**用户的全部练习记录会在升级后当场看不见**。

> ### ⚠️ 与 Task 2 的规则冲突（2026-08-07 复审补入，已在下面的代码块里修好）
>
> 本计划 **Task 2 结尾**写死了一条通用规则：「枚举的 `decodeIfPresent` 遇到**不认识的字符串**会抛
> `dataCorrupted`，不是返回 nil……**所以枚举字段一律「先读字符串、再转枚举、转不出来就用默认值」**」。
> 初稿 Task 1 的 Step 3 代码块（`focusPart = try c.decodeIfPresent(FocusPart.self, ...) ?? .fullMock`）
> **违反了这条规则**，而 `focusPart` 恰恰是本阶段第一个枚举字段。
>
> 实测确认：`state.json` 里 `"plan":{...,"focusPart":"Part 4",...}` →
> `JSONDecoder().decode(CoachState.self, ...)` 抛 `DecodingError.dataCorrupted` →
> `StateStore` 报「训练数据文件已损坏」→ **用户全部练习记录当场看不见**，
> 与「缺字段」的后果一模一样，只是触发条件换成了「坏值」。触发来源真实存在：
> 手改过的 state.json，以及将来给 `FocusPart` 加新 case 之后回退 / 跨机同步到的旧版本 App。
>
> 下面 Step 1 与 Step 3 的代码块**已按 Task 2 的规则改好**，Step 5 也补了对应的突变。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/TrainingPlanCodableTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class TrainingPlanCodableTests: XCTestCase {

    /// 这条守的是最贵的那种失败：用户硬盘上已经有一份 state.json，
    /// 里面的 plan 是旧版本写的、没有 focusPart 字段。若解码要求这个字段必须存在，
    /// 整份 state.json 会解不出来，StateStore 会报「训练数据文件已损坏」，
    /// 用户的全部练习记录当场看不见了。
    func testDecodesLegacyPlanWithoutFocusPart() throws {
        let legacy = """
        {"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z",
         "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]}
        """
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: Data(legacy.utf8))
        XCTAssertEqual(plan.focusPart, .fullMock, "旧计划没有这个字段时按全真模考处理")
        XCTAssertEqual(plan.lengthDays, 7)
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertEqual(plan.days[0].completedQuestionIds, ["q1"], "已完成的题不能在解码时丢掉")
    }

    func testDecodesFocusPartWhenPresent() throws {
        let json = """
        {"lengthDays":14,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 2","days":[]}
        """
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.focusPart, .part2)
    }

    /// 比上一条更隐蔽的同类失败：键**在**，但值是这个版本不认识的字符串。
    /// 枚举的 decodeIfPresent 只在「键不存在」时返回 nil，遇到不认识的字符串会抛
    /// dataCorrupted——照样一路冒泡到 StateStore 的「训练数据文件已损坏」，
    /// 用户全部练习记录当场看不见。触发来源是真实的：手改过的 state.json，
    /// 以及将来给 FocusPart 加了新 case 之后回退/跨机同步的旧版本 App。
    /// 为了一个展示用的字段丢掉全部练习记录，不成比例。
    func testDecodesUnknownFocusPartStringAsFullMockInsteadOfBrickingTheWholeFile() throws {
        let json = """
        {"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 4",
         "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]}
        """
        let plan = try JSONDecoder().decode(TrainingPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.focusPart, .fullMock, "认不出来的重点 Part 按全真模考处理，不许抛错")
        XCTAssertEqual(plan.days[0].completedQuestionIds, ["q1"], "练过的题不能因为一个坏字段丢掉")

        // 用户真正会碰到的是整份 state.json：plan 里一个坏枚举值不许把整份记录挡在门外。
        let state = """
        {"schemaVersion":3,
         "plan":{"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z","focusPart":"Part 4",
                 "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]}}
        """
        let decoded = try JSONDecoder().decode(CoachState.self, from: Data(state.utf8))
        XCTAssertEqual(decoded.plan?.focusPart, .fullMock)
        XCTAssertEqual(decoded.plan?.days[0].completedQuestionIds, ["q1"],
                       "整份 state.json 必须仍然读得出来，否则 StateStore 会报「训练数据文件已损坏」")
    }

    func testEncodesFocusPartSoItSurvivesARoundTrip() throws {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z",
                                days: [PlanDay(id: 1, questionIds: ["q1"], completedQuestionIds: [])],
                                focusPart: .part3)
        let data = try JSONEncoder().encode(plan)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"focusPart\""),
                      "字段没写进去，重开 App 就忘了用户选的重点 Part")
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data).focusPart, .part3)
    }

    /// PlanBuilder.build 与 Phase 0–2 的测试都用三参数构造。
    /// 加字段不能把它们打断——那会变成一次跨阶段的返工。
    func testThreeArgumentInitStillCompilesAndDefaultsToFullMock() {
        let plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z", days: [])
        XCTAssertEqual(plan.focusPart, .fullMock)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TrainingPlanCodableTests`
Expected: 编译失败 —— `TrainingPlan` 没有 `focusPart`

- [ ] **Step 3: 实现**

把 `Sources/IELTSCoachCore/Model/TrainingPlan.swift` 里的 `TrainingPlan` 改成：

```swift
public struct TrainingPlan: Codable, Equatable, Sendable {
    public var lengthDays: Int             // 7 | 14 | 30
    public var createdAt: String
    public var days: [PlanDay]
    /// 这个计划的重点 Part。计划页要显示它，重新生成时以它为默认值。
    public var focusPart: FocusPart

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    // focusPart 带默认值，是为了不打断 PlanBuilder.build 与 Phase 0–2 已有的调用点。
    public init(lengthDays: Int, createdAt: String, days: [PlanDay],
                focusPart: FocusPart = .fullMock) {
        self.lengthDays = lengthDays; self.createdAt = createdAt
        self.days = days; self.focusPart = focusPart
    }

    enum CodingKeys: String, CodingKey {
        case lengthDays, createdAt, days, focusPart
    }

    /// 手写解码，只为一件事：**旧版本写的 plan 里没有 focusPart，缺了也必须读得出来。**
    /// CoachState 用 decodeIfPresent 读 plan，而 decodeIfPresent 只在「键不存在」时返回 nil；
    /// 键存在但内部缺字段照样抛错，那个错会一路冒泡，让 StateStore 报
    /// 「训练数据文件已损坏」——为了一个新加的字段，把用户全部练习记录挡在门外。
    ///
    /// focusPart 要先读字符串再转枚举，是因为**枚举的 decodeIfPresent 只挡「键不存在」，
    /// 遇到不认识的字符串会抛 dataCorrupted**，后果与缺字段完全一样（整份 state.json 读不出来）。
    /// 触发来源是真实的：手改过的 state.json，以及将来给 FocusPart 加新 case 之后
    /// 回退或跨机同步到的旧版本 App。认不出来就按默认值处理，不许连累其余记录。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lengthDays = try c.decode(Int.self, forKey: .lengthDays)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
        focusPart = FocusPart(rawValue: try c.decodeIfPresent(String.self, forKey: .focusPart) ?? "")
            ?? .fullMock
    }

    public var isComplete: Bool { days.allSatisfy(\.isComplete) }
}
```

`PlanDay` 不动。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TrainingPlanCodableTests`
Expected: PASS（5 个测试）

Run: `swift test`
Expected: 全绿（既有的 `PlanBuilderTests`、`CoachStateTests`、`ReviewArchiverTests` 都会走到这段代码）

- [ ] **Step 5: 突变验证**

两个突变都要做（2026-08-07 复审补入第二个），因为这一行同时挡两种失败：

突变 A（挡「坏值」的部分）：把 `focusPart` 那一行改回
`focusPart = try c.decodeIfPresent(FocusPart.self, forKey: .focusPart) ?? .fullMock`，重跑：

Run: `swift test --filter TrainingPlanCodableTests`
Expected: `testDecodesUnknownFocusPartStringAsFullMockInsteadOfBrickingTheWholeFile` **变红**（`dataCorrupted`）

突变 B（挡「缺键」的部分）：再改成 `focusPart = try c.decode(FocusPart.self, forKey: .focusPart)`，重跑：

Run: `swift test --filter TrainingPlanCodableTests`
Expected: `testDecodesLegacyPlanWithoutFocusPart` **变红**（`keyNotFound`）

改回后重跑确认全绿。把三次的输出写进报告。

**这条守的是本阶段最贵的那种失败：升级之后用户的训练数据整份读不出来。**

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/TrainingPlan.swift Tests/IELTSCoachCoreTests/TrainingPlanCodableTests.swift
git commit -m "feat(core): 计划记住重点 Part，旧 state.json 仍可读"
```

---

## Task 2: `CoachSettings` 记住三项练习偏好，且旧数据仍然读得出来

**Files:**
- Modify: `Sources/IELTSCoachCore/Model/CoachState.swift`
- Create: `Tests/IELTSCoachCoreTests/CoachSettingsCompatibilityTests.swift`

**Interfaces:**
- Consumes: `FeedbackTiming`、`Part2PrepMode`（`Sources/IELTSCoachCore/Model/PracticeMode.swift`）
- Produces:
  - `CoachSettings.defaultRoute: String`
  - `CoachSettings.feedbackTiming: FeedbackTiming`
  - `CoachSettings.part2PrepMode: Part2PrepMode`
  - `CoachSettings.defaultRouteFallback: String`（静态常量，值为 `"planToday"`）
  - `CoachSettings.init(recordingEnabled:recordingConsentAt:transcriptEnabled:weeklyGoal:defaultRoute:feedbackTiming:part2PrepMode:)`，后五个带默认值（`transcriptEnabled` 来自 Phase 4、`weeklyGoal` 来自 Phase 7，本任务只是合并保留）
  - `CoachSettings.init(from: any Decoder) throws`（手写）

> ### ⚠️ 跨阶段冲突（2026-08-06 复审补入，必读）
>
> **Phase 7 Task 1 已经整体替换过一次 `CoachSettings`，给它加了 `weeklyGoal`**
> （字段、`defaultWeeklyGoal` / `weeklyGoalRange` / `normalized(_:)`、memberwise init 的第三参、
> `CodingKeys` 里的 `weeklyGoal`、手写 `init(from:)` 里的那一行）。
>
> 本任务同样是「整体替换 `CoachSettings`」。**照初稿那份代码抄下去，会把 `weeklyGoal` 连同它的
> 三个静态成员一起删掉**：`WeeklyGoalTests`、`WeeklyGoalEditorTests`、首页四格与设置面板全部编译失败，
> 而且用户已经存进 `state.json` 的每周目标会在下一次写盘时被丢掉。
>
> 下面 Step 3 的代码**已经把两个阶段的字段合并**。动手前先跑一次
> `grep -n "weeklyGoal" Sources/IELTSCoachCore/Model/CoachState.swift`：
>
> - 有输出 → 按下面这份合并版替换，`weeklyGoal` 那几处一个字都不要动
> - 没输出 → 说明 Phase 7 还没做，把 `weeklyGoal` 相关的行删掉再用（但要在报告里写明，Phase 7 届时得自己合并回来）
>
> **Phase 4 Task 2 加的 `transcriptEnabled`（默认开）同样要保留。**
> 下面 Step 3 的代码**已经把 Phase 4 与 Phase 7 两个阶段的字段都合并进去了**
> （2026-08-06 复审补入——初稿只在这段文字里提醒，代码块里没有，而实现者照抄的是代码块）。
> 动手前先跑 `grep -n "transcriptEnabled" Sources/IELTSCoachCore/Model/CoachState.swift`：
>
> - 有输出 → 按下面这份合并版替换，`transcriptEnabled` 那几处一个字都不要动
> - 没输出 → 说明 Phase 4 还没做，把 `transcriptEnabled` 相关的五处删掉再用（并在报告里写明）
>
> **验收时跑一次 `swift test --filter TranscriptSettingsTests`（Phase 4 的 5 条）与
> `swift test --filter WeeklyGoalTests`（Phase 7 的 9 条）——它们不知道这次重写发生过，
> 这正是它们有价值的原因。红了就是抄丢了字段，去补字段，不要改测试。**

**为什么是 String 而不是枚举：** `defaultRoute` 存的是 `PracticeRoute` 的 rawValue，而 `PracticeRoute` 定义在 `IELTSCoachUI` 里。**`IELTSCoachCore` 不允许依赖 UI**，所以 Core 只能存字符串。两个模块之间的对齐由 Task 7 的一条跨模块测试守住。

**默认值依据 ROADMAP 第 5 节：** 练习路线默认「按计划练今天」，反馈时机默认 `deferred`（全程零反馈），Part 2 准备默认 `countdown`（一分钟倒计时）。

**这里有一个比 Task 1 更隐蔽的坑：** 枚举的 `decodeIfPresent` 遇到**不认识的字符串**会抛 `dataCorrupted`，不是返回 nil。手改过的 state.json、或将来版本写进去的新取值，都会让整份训练数据变成不可读。**为了一个偏好设置丢掉全部练习记录，不成比例。** 所以枚举字段一律「先读字符串、再转枚举、转不出来就用默认值」。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/CoachSettingsCompatibilityTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class CoachSettingsCompatibilityTests: XCTestCase {

    func testDecodesLegacySettingsWithoutTheNewFields() throws {
        let legacy = #"{"recordingEnabled":true,"recordingConsentAt":"2026-08-01T00:00:00Z"}"#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, "2026-08-01T00:00:00Z")
        XCTAssertEqual(settings.defaultRoute, CoachSettings.defaultRouteFallback)
        XCTAssertEqual(settings.feedbackTiming, .deferred, "ROADMAP 第 5 节：默认全程零反馈")
        XCTAssertEqual(settings.part2PrepMode, .countdown, "ROADMAP 第 5 节：默认一分钟倒计时")
    }

    /// 枚举字段直接 decode 时，遇到不认识的取值会抛错，
    /// 而这个错会一路冒泡到 CoachState，让 StateStore 报「训练数据文件已损坏」。
    /// 为了一个偏好设置丢掉全部练习记录，不成比例。
    func testUnknownEnumValuesFallBackInsteadOfBlowingUpTheWholeFile() throws {
        let weird = """
        {"recordingEnabled":false,"recordingConsentAt":"",
         "feedbackTiming":"someday","part2PrepMode":"whenever"}
        """
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(weird.utf8))
        XCTAssertEqual(settings.feedbackTiming, .deferred)
        XCTAssertEqual(settings.part2PrepMode, .countdown)
    }

    func testRoundTripsTheNewFields() throws {
        let settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     defaultRoute: "retrain", feedbackTiming: .immediate,
                                     part2PrepMode: .learnerControlled)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CoachSettings.self, from: data), settings)
    }

    func testEmptyStateCarriesTheDocumentedDefaults() {
        let settings = CoachState.empty().settings
        XCTAssertEqual(settings.defaultRoute, "planToday")
        XCTAssertEqual(settings.feedbackTiming, .deferred)
        XCTAssertEqual(settings.part2PrepMode, .countdown)
    }

    /// 真实用户硬盘上那份文件长这样：plan 里没有 focusPart、settings 只有两个字段。
    /// 整份 state.json 必须照样读得出来，一个字段都不能丢。
    func testWholeLegacyStateJSONStillDecodes() throws {
        let json = """
        {"schemaVersion":3,"learner":{"displayName":"Andy","createdAt":"2026-01-01T00:00:00Z"},
         "currentSession":null,"sessions":[],"targets":[],"issues":[],"vocabulary":[],
         "plan":{"lengthDays":7,"createdAt":"2026-08-01T00:00:00Z",
                 "days":[{"id":1,"questionIds":["q1"],"completedQuestionIds":["q1"]}]},
         "questions":[],"questionSources":[],
         "settings":{"recordingEnabled":false,"recordingConsentAt":""},
         "questionCursor":{"part1":0,"part2":0,"part3":0}}
        """
        let state = try JSONDecoder().decode(CoachState.self, from: Data(json.utf8))
        XCTAssertEqual(state.plan?.focusPart, .fullMock)
        XCTAssertEqual(state.plan?.days.first?.completedQuestionIds, ["q1"],
                       "升级不能把已经练过的题变回没练过")
        XCTAssertEqual(state.settings.defaultRoute, CoachSettings.defaultRouteFallback)
        XCTAssertEqual(state.settings.feedbackTiming, .deferred)
    }

    /// **跨阶段回归。** 本任务整体替换了 `CoachSettings`，最容易犯的错就是把
    /// 前面阶段加的字段顺手删掉——那样编译能过（默认参数顶上了），
    /// 只是用户存过的取值在下一次写盘时被默认值盖掉，没有任何报错。
    ///
    /// 一条测两个字段：Phase 4 的 `transcriptEnabled` 与 Phase 7 的 `weeklyGoal`。
    /// **哪个阶段还没交付，就把对应的两行注释掉并在报告里写明，不要删整条。**
    func testEarlierPhasesFieldsSurviveThisRewrite() throws {
        let json = #"""
        {"recordingEnabled":false,"recordingConsentAt":"",
         "transcriptEnabled":false,"weeklyGoal":3}
        """#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.weeklyGoal, 3, "weeklyGoal 被这次重写弄丢了")
        XCTAssertFalse(settings.transcriptEnabled, "transcriptEnabled 被这次重写弄丢了")

        let roundTripped = try JSONDecoder().decode(
            CoachSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(roundTripped.weeklyGoal, 3, "weeklyGoal 没有被编码回去")
        XCTAssertFalse(roundTripped.transcriptEnabled, "transcriptEnabled 没有被编码回去")
    }

    /// **跨阶段回归。** Phase 5 的录音开关每拨一次就会走一遍
    /// `RecordingConsent.enable` / `disable`。那两个函数若用
    /// `CoachSettings(recordingEnabled:recordingConsentAt:)` 重新构造，
    /// 本任务新加的三项偏好与 Phase 7 的每周目标会被静默重置回默认值。
    func testTogglingTheRecordingSwitchKeepsEveryOtherSetting() {
        let original = CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     transcriptEnabled: false,
                                     weeklyGoal: 3, defaultRoute: "retrain",
                                     feedbackTiming: .immediate,
                                     part2PrepMode: .learnerControlled)

        let on = RecordingConsent.enable(original, at: "2026-08-06T10:00:00Z")
        XCTAssertFalse(on.transcriptEnabled)
        XCTAssertEqual(on.weeklyGoal, 3)
        XCTAssertEqual(on.defaultRoute, "retrain")
        XCTAssertEqual(on.feedbackTiming, .immediate)
        XCTAssertEqual(on.part2PrepMode, .learnerControlled)

        let off = RecordingConsent.disable(on)
        XCTAssertFalse(off.transcriptEnabled)
        XCTAssertEqual(off.weeklyGoal, 3)
        XCTAssertEqual(off.defaultRoute, "retrain")
        XCTAssertEqual(off.feedbackTiming, .immediate)
        XCTAssertEqual(off.part2PrepMode, .learnerControlled)
        XCTAssertFalse(off.recordingEnabled)
        XCTAssertEqual(off.recordingConsentAt, "")
    }
}
```

> 上面最后两条是 2026-08-06 跨阶段复审补进来的。第二条依赖 Phase 5 的 `RecordingConsent`；
> 若 Phase 5 尚未交付，把它整条注释掉并在报告里写明，**不要删**。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter CoachSettingsCompatibilityTests`
Expected: 编译失败 —— `CoachSettings` 没有 `defaultRoute`

- [ ] **Step 3: 实现**

把 `Sources/IELTSCoachCore/Model/CoachState.swift` 里的 `CoachSettings` 换成：

```swift
public struct CoachSettings: Codable, Equatable, Sendable {
    /// PracticeRoute.rawValue 的默认值。**PracticeRoute 定义在 IELTSCoachUI 里，
    /// 而 Core 不允许依赖 UI**，所以这里只能存字符串。两边的对齐由
    /// Tests/IELTSCoachUITests/PracticeRoutePreferenceTests.swift 里的一条测试守住。
    public static let defaultRouteFallback = "planToday"

    public var recordingEnabled: Bool
    public var recordingConsentAt: String
    /// 「记录对话逐字稿」（Phase 4 Task 2 加的，本任务原样保留，不得删）
    public var transcriptEnabled: Bool
    /// 每周训练目标次数（Phase 7 Task 1 加的，本任务原样保留，不得删）
    public var weeklyGoal: Int
    /// 用户偏好的练习路线（ROADMAP 第 5 节，默认「按计划练今天」）
    public var defaultRoute: String
    /// 考官何时给反馈（ROADMAP 第 5 节，默认全程零反馈）
    public var feedbackTiming: FeedbackTiming
    /// Part 2 的一分钟准备怎么处理（ROADMAP 第 5 节，默认倒计时）
    public var part2PrepMode: Part2PrepMode

    // ↓ 来自 Phase 4 Task 2，原样保留
    public static let defaultTranscriptEnabled = true

    // ↓ 三个常量与 normalized(_:) 来自 Phase 7 Task 1，原样保留
    public static let defaultWeeklyGoal = 5
    public static let weeklyGoalRange = 1...21
    public static func normalized(_ raw: Int?) -> Int {
        guard let raw, weeklyGoalRange.contains(raw) else { return defaultWeeklyGoal }
        return raw
    }

    // 后五个参数带默认值，是为了不打断 CoachState.empty() 与 Phase 0–2 已有的调用点。
    // **参数顺序沿用前面阶段定下的位置**（transcriptEnabled 第三、weeklyGoal 第四），
    // 换位置会打断 Phase 4 / Phase 7 已有的调用点。全带默认值，只传其中一个也能编译。
    public init(recordingEnabled: Bool, recordingConsentAt: String,
                transcriptEnabled: Bool = CoachSettings.defaultTranscriptEnabled,
                weeklyGoal: Int = CoachSettings.defaultWeeklyGoal,
                defaultRoute: String = CoachSettings.defaultRouteFallback,
                feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.recordingEnabled = recordingEnabled
        self.recordingConsentAt = recordingConsentAt
        self.transcriptEnabled = transcriptEnabled
        self.weeklyGoal = CoachSettings.normalized(weeklyGoal)
        self.defaultRoute = defaultRoute
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }

    enum CodingKeys: String, CodingKey {
        case recordingEnabled, recordingConsentAt, transcriptEnabled, weeklyGoal
        case defaultRoute, feedbackTiming, part2PrepMode
    }

    /// 先读字符串再转枚举，转不出来就用默认值。
    /// 直接 decode 枚举的话，遇到不认识的取值会抛 dataCorrupted，而这个错会一路
    /// 冒泡到 CoachState，让 StateStore 报「训练数据文件已损坏」——
    /// 为了一个偏好设置丢掉全部练习记录，不成比例。
    private static func stringEnum<T: RawRepresentable>(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, fallback: T
    ) -> T where T.RawValue == String {
        let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        return raw.flatMap(T.init(rawValue:)) ?? fallback
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordingEnabled = try c.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? false
        recordingConsentAt = try c.decodeIfPresent(String.self, forKey: .recordingConsentAt) ?? ""
        // Phase 4 Task 2 的那一行，原样保留。删了它，用户关掉的逐字稿开关会在
        // 下一次写盘时被默认值盖回「开」，而且没有任何报错。
        transcriptEnabled = try c.decodeIfPresent(Bool.self, forKey: .transcriptEnabled)
            ?? CoachSettings.defaultTranscriptEnabled
        // Phase 7 Task 1 的那一行，原样保留。删了它，用户存过的每周目标会在
        // 下一次写盘时被默认值盖掉，而且没有任何报错。
        weeklyGoal = CoachSettings.normalized(
            try c.decodeIfPresent(Int.self, forKey: .weeklyGoal))
        defaultRoute = try c.decodeIfPresent(String.self, forKey: .defaultRoute)
            ?? CoachSettings.defaultRouteFallback
        feedbackTiming = CoachSettings.stringEnum(c, .feedbackTiming, fallback: .deferred)
        part2PrepMode = CoachSettings.stringEnum(c, .part2PrepMode, fallback: .countdown)
    }
}
```

`CoachState` 的其余部分不动——`CoachState.empty()` 里那句
`CoachSettings(recordingEnabled: false, recordingConsentAt: "")` 因为默认参数照样成立。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter CoachSettingsCompatibilityTests`
Expected: PASS（7 个测试；Phase 5 未交付时把录音那条注释掉，则是 6 个）

Run: `swift test --filter TranscriptSettingsTests`
Expected: PASS（Phase 4 的 5 条，一条都不能红）

Run: `swift test --filter WeeklyGoalTests`
Expected: PASS（Phase 7 的 9 条，一条都不能红）

**上面两组是这次整体替换的守门员。任何一条红了，都是「字段被抄丢」——去把字段补回来，不要改测试。**

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

做两次，每次改完跑一遍再改回来：

1. 把 `feedbackTiming = CoachSettings.stringEnum(c, .feedbackTiming, fallback: .deferred)`
   换成最「自然」的那种写法：
   `feedbackTiming = try c.decodeIfPresent(FeedbackTiming.self, forKey: .feedbackTiming) ?? .deferred`
   Expected: `testUnknownEnumValuesFallBackInsteadOfBlowingUpTheWholeFile` **变红**
   （解码 `"someday"` 会抛 `dataCorrupted`，测试里的 `try` 把它抛出去 → 红，不是崩溃）
2. 把 `defaultRoute = try c.decodeIfPresent(...) ?? CoachSettings.defaultRouteFallback`
   改成 `defaultRoute = try c.decode(String.self, forKey: .defaultRoute)`
   Expected: `testDecodesLegacySettingsWithoutTheNewFields` 与 `testWholeLegacyStateJSONStillDecodes` **都变红**

两次都改回后确认全绿，把四次输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/CoachState.swift Tests/IELTSCoachCoreTests/CoachSettingsCompatibilityTests.swift
git commit -m "feat(core): 练习偏好持久化，旧 state.json 仍可读"
```

---

## Task 3: `PlanScope` —— 按重点 Part 选题，以及「这个计划到底做不做得出来」

**Files:**
- Create: `Sources/IELTSCoachCore/QuestionBank/PlanScope.swift`
- Create: `Tests/IELTSCoachCoreTests/PlanScopeTests.swift`

**Interfaces:**
- Consumes: `Question`（字段 `id`、`part: Int`、`topic`、`prompt`）、`FocusPart`、`PlanBuilder.supportedLengths: [Int]`
- Produces:
  - `PlanScope.select(from questions: [Question], focusPart: FocusPart) -> [Question]`
  - `PlanScope.blockingReason(questionCount: Int, lengthDays: Int, focusPart: FocusPart) -> String?`
  - `PlanScope.label(for focusPart: FocusPart) -> String`

**这个任务解决三件事：**

1. **重点 Part 选题。** `PlanBuilder.build` 吃什么题就排什么题，它不知道「重点 Part」这回事。筛选放在它外面。
2. **全真模考要交错。** 题库的自然顺序是「Part 1 一整块、然后 Part 2、然后 Part 3」（`QuestionBankImporter.importJSON` 就是这么写的）。照搬这个顺序分 7 天，会出现前几天全是 Part 1、最后几天全是 Part 3——**那不叫全真模考**。
3. **拦住做不出来的计划。** `PlanBuilder.build(questions: 12 道, lengthDays: 30)` 不会报错，它会给前 12 天各分 1 题、**后 18 天各分 0 题**。而 `PlanDay.isComplete` 的定义是 `!questionIds.isEmpty && ...`——空天永远不算完成，于是 `TrainingPlan.isComplete` **永远为假**，「计划完成」这件事再也不会发生。这是个不报错、不崩溃、只是永远差一点的失败，正是本项目最难发现的那一类。所以要在生成之前就拦住它，并告诉用户改成几天能行。

**`blockingReason` 必须是生成前预览与真正生成共用的唯一判据**，否则会出现「预览说能生成、点下去却报错」——最伤信任的一类界面缺陷。Task 4 与 Task 6 各有一条测试守这个一致性。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/PlanScopeTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class PlanScopeTests: XCTestCase {

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    /// 模拟题库的自然顺序：Part 1 一整块，然后 Part 2，然后 Part 3。
    private var bank: [Question] {
        [q("a1", 1), q("a2", 1), q("a3", 1), q("b1", 2), q("b2", 2), q("c1", 3)]
    }

    func testSinglePartKeepsOnlyThatPartInBankOrder() {
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part1).map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part2).map(\.id), ["b1", "b2"])
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .part3).map(\.id), ["c1"])
    }

    /// 照搬题库顺序去分 7 天，会出现前几天全是 Part 1、最后几天全是 Part 3。
    /// 那不叫全真模考。
    func testFullMockInterleavesAcrossParts() {
        XCTAssertEqual(PlanScope.select(from: bank, focusPart: .fullMock).map(\.id),
                       ["a1", "b1", "c1", "a2", "b2", "a3"])
    }

    func testFullMockKeepsEveryQuestionExactlyOnce() {
        let selected = PlanScope.select(from: bank, focusPart: .fullMock)
        XCTAssertEqual(selected.count, bank.count)
        XCTAssertEqual(Set(selected.map(\.id)), Set(bank.map(\.id)))
    }

    /// state.json 是纯文本、可以手改；PDF 提取器也可能吐出意外的 part。
    /// 认不出 Part 的题既不能被丢掉，也不能让轮转卡在死循环里。
    func testFullMockSurvivesOutOfRangePartValues() {
        let dirty = bank + [q("x", 9)]
        let selected = PlanScope.select(from: dirty, focusPart: .fullMock)
        XCTAssertEqual(selected.count, dirty.count)
        XCTAssertEqual(selected.last?.id, "x", "认不出 Part 的题排在最后，但不能被丢掉")
    }

    func testEmptyBankSelectsNothing() {
        XCTAssertTrue(PlanScope.select(from: [], focusPart: .fullMock).isEmpty)
        XCTAssertTrue(PlanScope.select(from: [], focusPart: .part2).isEmpty)
    }

    func testNoBlockingReasonWhenThereAreEnoughQuestions() {
        XCTAssertNil(PlanScope.blockingReason(questionCount: 7, lengthDays: 7, focusPart: .part1))
        XCTAssertNil(PlanScope.blockingReason(questionCount: 40, lengthDays: 30, focusPart: .fullMock))
    }

    /// 题数少于天数时 PlanBuilder 会给尾部若干天分 0 题，而空天的 isComplete
    /// 永远是 false，「计划完成」这件事就再也不会发生。所以要在生成前拦住。
    func testBlockingReasonWhenFewerQuestionsThanDays() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 12, lengthDays: 30, focusPart: .part2))
        XCTAssertTrue(reason.contains("12"), "要说清现在有多少题")
        XCTAssertTrue(reason.contains("30"), "要说清想分几天")
        XCTAssertTrue(reason.contains("改成 7 天"), "12 道题最多撑 7 天，要给一个真的办得到的建议")
        XCTAssertTrue(reason.contains("下一步"))
    }

    func testBlockingReasonWhenEvenTheShortestCycleIsImpossible() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 3, lengthDays: 7, focusPart: .part2))
        XCTAssertFalse(reason.contains("改成"),
                       "3 道题连 7 天都分不满，不能建议一个同样办不到的天数")
        XCTAssertTrue(reason.contains("至少 7 道"))
        XCTAssertTrue(reason.contains("下一步"))
    }

    func testBlockingReasonWhenThatPartHasNoQuestionsAtAll() throws {
        let reason = try XCTUnwrap(
            PlanScope.blockingReason(questionCount: 0, lengthDays: 7, focusPart: .part2))
        XCTAssertTrue(reason.contains("Part 2"), "要说清是哪个 Part 没题")
        XCTAssertTrue(reason.contains("训练题库"), "要指出去哪儿解决")
        XCTAssertTrue(reason.contains("下一步"))
    }

    func testLabelsAreChineseAndDistinct() {
        let labels = FocusPart.allCases.map(PlanScope.label(for:))
        XCTAssertEqual(Set(labels).count, labels.count, "四个重点 Part 的说明不能重名")
        XCTAssertTrue(PlanScope.label(for: .fullMock).contains("全真模考"))
        XCTAssertTrue(PlanScope.label(for: .part1).contains("Part 1"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PlanScopeTests`
Expected: 编译失败 —— `PlanScope` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/QuestionBank/PlanScope.swift`：

```swift
import Foundation

/// 「重点 Part」这件事的全部规则：挑哪些题、按什么顺序排、以及这个计划做不做得出来。
public enum PlanScope {

    // MARK: - 选题

    public static func select(from questions: [Question], focusPart: FocusPart) -> [Question] {
        switch focusPart {
        case .part1: return questions.filter { $0.part == 1 }
        case .part2: return questions.filter { $0.part == 2 }
        case .part3: return questions.filter { $0.part == 3 }
        case .fullMock: return interleaveByPart(questions)
        }
    }

    /// 全真模考：按 Part 1 → Part 2 → Part 3 轮转交错，各 Part 内部保持题库原有顺序。
    /// 某个 Part 先用完就跳过它继续轮转。
    ///
    /// 不交错的话，题库的自然顺序（导入器先写完整块 Part 1、再写 Part 2/3）会让
    /// 7 天计划的前几天全是 Part 1、最后几天全是 Part 3——那不叫全真模考。
    ///
    /// part 落在 1–3 之外的脏数据（手改过的 state.json）排在最后，**不丢弃**：
    /// 全真模考的语义是「题库里的全部题目」，悄悄少排几道是静默失败。
    private static func interleaveByPart(_ questions: [Question]) -> [Question] {
        var buckets: [[Question]] = [[], [], []]      // 下标 0/1/2 对应 Part 1/2/3
        var unknown: [Question] = []
        for question in questions {
            if (1...3).contains(question.part) { buckets[question.part - 1].append(question) }
            else { unknown.append(question) }
        }

        var result: [Question] = []
        var cursors = [0, 0, 0]
        var advanced = true
        while advanced {
            advanced = false
            for index in 0..<3 where cursors[index] < buckets[index].count {
                result.append(buckets[index][cursors[index]])
                cursors[index] += 1
                advanced = true
            }
        }
        return result + unknown
    }

    // MARK: - 可行性

    /// 返回 nil 表示这个计划做得出来；否则返回中文说明（发生了什么 + 下一步做什么）。
    ///
    /// **生成前的预览与真正生成时必须用同一个判据**，否则会出现
    /// 「预览说能生成、点下去却报错」——最伤信任的一类界面缺陷。
    public static func blockingReason(questionCount: Int, lengthDays: Int,
                                      focusPart: FocusPart) -> String? {
        guard questionCount > 0 else {
            return "题库里没有\(label(for: focusPart))的题目，生成不了计划。"
                + "下一步：换一个重点 Part，或到「训练题库」页导入含该 Part 的题目。"
        }
        guard questionCount < lengthDays else { return nil }

        // 题数少于天数时 PlanBuilder 会给尾部若干天分 0 题，而空天的 isComplete
        // 永远是 false —— 那样的计划永远显示不出「已完成」，用户会一直以为自己还差一点。
        let advice: String
        if let usable = PlanBuilder.supportedLengths.filter({ $0 <= questionCount }).max() {
            advice = "下一步：把周期改成 \(usable) 天，或先到「训练题库」页导入更多题目。"
        } else {
            advice = "下一步：到「训练题库」页导入更多题目——最短的 7 天计划也需要至少 7 道题。"
        }
        return "\(label(for: focusPart))现在只有 \(questionCount) 道题，分不满 \(lengthDays) 天，"
            + "会有整天没题可练。\(advice)"
    }

    // MARK: - 文案

    /// 重点 Part 的中文说明。界面与 Core 的错误信息共用这一份，避免两处文案漂移。
    public static func label(for focusPart: FocusPart) -> String {
        switch focusPart {
        case .part1: return "Part 1（日常话题问答）"
        case .part2: return "Part 2（个人陈述）"
        case .part3: return "Part 3（深入讨论）"
        case .fullMock: return "全真模考（Part 1 + 2 + 3）"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PlanScopeTests`
Expected: PASS（10 个测试）

- [ ] **Step 5: 突变验证**

做两次：

1. 把 `case .fullMock: return interleaveByPart(questions)` 改成 `case .fullMock: return questions`
   Expected: `testFullMockInterleavesAcrossParts` **变红**
2. 把 `guard questionCount < lengthDays else { return nil }` 改成 `guard questionCount < 1 else { return nil }`
   Expected: `testBlockingReasonWhenFewerQuestionsThanDays` 与 `testBlockingReasonWhenEvenTheShortestCycleIsImpossible` **都变红**

两次都改回后确认全绿。把四次输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/QuestionBank/PlanScope.swift Tests/IELTSCoachCoreTests/PlanScopeTests.swift
git commit -m "feat(core): 按重点 Part 选题与计划可行性判据"
```

---

## Task 4: `PlanRegenerator` —— 重新生成计划，一格进度都不丢

**Files:**
- Create: `Sources/IELTSCoachCore/QuestionBank/PlanRegenerator.swift`
- Create: `Tests/IELTSCoachCoreTests/PlanRegeneratorTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`questions`、`plan`）、`TrainingPlan`、`PlanDay`、`PlanBuilder.build(questions:lengthDays:createdAt:)`、`PlanBuilder.markCompleted(plan:questionID:)`、`PlanScope.select`、`PlanScope.blockingReason`、`PlanScope.label`、`CoachError.planImpossible`
- Produces:
  - `struct PlanRegenerationOutcome: Equatable, Sendable`，字段 `plan: TrainingPlan`、`carriedOver: [String]`、`dropped: [String]`、`summary: String`
  - `PlanRegenerator.carryOverProgress(from old: TrainingPlan?, to fresh: TrainingPlan) -> TrainingPlan`
  - `PlanRegenerator.regenerate(state: CoachState, lengthDays: Int, focusPart: FocusPart, createdAt: String) throws -> PlanRegenerationOutcome`
  - `PlanRegenerator.apply(_ outcome: PlanRegenerationOutcome, to state: inout CoachState)`

**这是本阶段的核心任务。**

用户已经按 7 天计划练了 3 天，现在想改成 14 天、或把重点从全真模考换成 Part 2。`PlanBuilder.build` 造出来的是一份全新的计划，`completedQuestionIds` 全是空的——**直接用它覆盖，那 3 天就白练了**。

搬运进度靠**题目 id**。题目 id 是内容哈希（见 `QuestionBankImporter.questionID`），换季重新导入题库后同一道题的 id 不变，所以这个搬运在换季场景下依然成立——这正是成品标准第 12 条守的东西。

**`apply` 只写 `state.plan`，别的一个字段都不碰。** 「重新生成计划」是重排今后练什么，不是清空练过什么。顺手把 `question.status` 重置成 `"new"`、或清掉 `sessions` 这类「看起来很合理」的改动，会让用户一次点击丢掉全部历史。Step 5 的突变验证就是专门为这种改动准备的。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/PlanRegeneratorTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class PlanRegeneratorTests: XCTestCase {

    // MARK: - 工具

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    /// 14 道 Part 1 + 14 道 Part 2。够分 7 天，也够分 14 天。
    private func bank() -> [Question] {
        (1...14).map { q("a\($0)", 1) } + (1...14).map { q("b\($0)", 2) }
    }

    private func state(questions: [Question], plan: TrainingPlan? = nil) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.plan = plan
        return s
    }

    private func completed(_ plan: TrainingPlan) -> Set<String> {
        Set(plan.days.flatMap(\.completedQuestionIds))
    }

    // MARK: - 核心：重新生成不能丢进度

    func testCarriesCompletedQuestionsAcrossACycleChange() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "2026-08-06T00:00:00Z").plan
        // 练完前两天
        for id in plan.days[0].questionIds + plan.days[1].questionIds {
            plan = PlanBuilder.markCompleted(plan: plan, questionID: id)
        }
        s.plan = plan
        let done = completed(plan)
        XCTAssertEqual(done.count, 4, "14 题分 7 天，每天 2 题，两天就是 4 题")

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 14, focusPart: .part1,
                                                         createdAt: "2026-08-07T00:00:00Z")
        XCTAssertEqual(regenerated.plan.lengthDays, 14)
        XCTAssertEqual(completed(regenerated.plan), done, "换周期后，练过的题必须还是练过的")
        XCTAssertEqual(Set(regenerated.carriedOver), done)
        XCTAssertTrue(regenerated.dropped.isEmpty)
    }

    func testCarriesProgressWhenTheFocusPartNarrows() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .fullMock,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a1")
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "b1")
        s.plan = plan

        let narrowed = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                      createdAt: "t2")
        XCTAssertEqual(completed(narrowed.plan), ["a1"], "还在范围内的那道题保持已完成")
        XCTAssertEqual(narrowed.carriedOver, ["a1"])
        XCTAssertEqual(narrowed.dropped, ["b1"], "b1 是 Part 2，新计划里没有它")
    }

    func testReportsCompletedQuestionsThatTheBankNoLongerHas() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a1")
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a2")
        s.plan = plan
        // 换季重新导入，出题方把 a1 删掉了
        s.questions = s.questions.filter { $0.id != "a1" }

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                         createdAt: "t2")
        XCTAssertEqual(regenerated.dropped, ["a1"])
        XCTAssertEqual(regenerated.carriedOver, ["a2"])
        XCTAssertTrue(regenerated.summary.contains("没有丢"),
                      "必须明确告诉用户那次练习的记录还在，否则 dropped 看起来就像数据被删了")
    }

    /// 成品标准第 12 条：题库换季重新导入后，旧的练习记录不能错位。
    /// 题目 id 是内容哈希，同一道题重新导入后 id 不变，所以进度照样对得上。
    func testKeepsProgressAfterASeasonalReimport() throws {
        var s = state(questions: bank())
        var plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                  createdAt: "t1").plan
        plan = PlanBuilder.markCompleted(plan: plan, questionID: "a5")
        s.plan = plan
        // 换季：新增 6 道 Part 1 排在最前面，整体顺序全变了，但老题的 id 没变
        s.questions = (1...6).map { q("new\($0)", 1) } + s.questions

        let regenerated = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                         createdAt: "t2")
        XCTAssertTrue(completed(regenerated.plan).contains("a5"),
                      "换季重新导入后，练过的题不能变回没练过")
        XCTAssertTrue(regenerated.dropped.isEmpty)
    }

    // MARK: - 其余行为

    func testWorksWhenThereIsNoOldPlan() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part2, createdAt: "t")
        XCTAssertEqual(outcome.plan.days.count, 7)
        XCTAssertTrue(outcome.carriedOver.isEmpty)
        XCTAssertTrue(outcome.dropped.isEmpty)
    }

    func testRegeneratingTwiceGivesTheSamePlan() throws {
        var s = state(questions: bank())
        s.plan = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                createdAt: "t1").plan
        let again = try PlanRegenerator.regenerate(state: s, lengthDays: 7, focusPart: .part1,
                                                   createdAt: "t1")
        XCTAssertEqual(again.plan, s.plan, "同样的题库、同样的参数，重新生成不该产生不一样的计划")
    }

    func testStoresTheFocusPartOnThePlan() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part2, createdAt: "t")
        XCTAssertEqual(outcome.plan.focusPart, .part2)
        XCTAssertTrue(outcome.plan.days.flatMap(\.questionIds).allSatisfy { $0.hasPrefix("b") },
                      "选了 Part 2 就只能排 Part 2 的题")
    }

    func testSummaryAlwaysSaysWhatToDoNext() throws {
        let outcome = try PlanRegenerator.regenerate(state: state(questions: bank()),
                                                     lengthDays: 7, focusPart: .part1, createdAt: "t")
        XCTAssertTrue(outcome.summary.contains("下一步"),
                      "所有面向用户的文案都要说明下一步做什么")
    }

    // MARK: - 拒绝

    func testRefusesWhenThePartHasFewerQuestionsThanDays() {
        let s = state(questions: (1...5).map { q("b\($0)", 2) })
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                            focusPart: .part2, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("5"))
            XCTAssertTrue(error.localizedDescription.contains("下一步"))
        }
    }

    func testRefusesWhenThePartHasNoQuestions() {
        let s = state(questions: (1...10).map { q("a\($0)", 1) })
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                            focusPart: .part3, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Part 3"))
            XCTAssertTrue(error.localizedDescription.contains("下一步"))
        }
    }

    func testRejectsUnsupportedCycleLength() {
        let s = state(questions: bank())
        XCTAssertThrowsError(try PlanRegenerator.regenerate(state: s, lengthDays: 10,
                                                            focusPart: .part1, createdAt: "t")) { error in
            XCTAssertTrue(error.localizedDescription.contains("7、14、30"))
        }
    }

    /// 拒绝的判据必须与界面预览用的判据完全一致，
    /// 否则会出现「预览说能生成、点下去却报错」。
    func testRefusalMatchesPlanScopeBlockingReason() {
        for count in 0...20 {
            for days in PlanBuilder.supportedLengths {
                let s = state(questions: (0..<count).map { q("b\($0)", 2) })
                let blocked = PlanScope.blockingReason(questionCount: count, lengthDays: days,
                                                       focusPart: .part2) != nil
                var threw = false
                do {
                    _ = try PlanRegenerator.regenerate(state: s, lengthDays: days,
                                                       focusPart: .part2, createdAt: "t")
                } catch { threw = true }
                XCTAssertEqual(threw, blocked, "题数 \(count)、周期 \(days) 天：两处判断不一致")
            }
        }
    }

    // MARK: - apply 的边界

    /// 「重新生成计划」是重排今后练什么，不是清空练过什么。
    /// 顺手把 question.status 重置成 new、或清掉 sessions 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史。这条测试就是为了让那种改动立刻变红。
    func testApplyOnlyTouchesThePlan() throws {
        var s = state(questions: bank())
        s.questions[0].status = "practiced"
        s.sessions = [PracticeSession(id: "s1", questionId: "a1", focusPart: .part1,
                                      startedAt: "2026-08-01T00:00:00Z",
                                      endedAt: "2026-08-01T00:10:00Z",
                                      goal: "回答后补一个原因和例子", transcript: [],
                                      reportPath: "reports/s1.json", recordingPath: "")]
        s.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                correction: "I really like it", whyItMatters: "very 不能修饰动词",
                                occurrences: 3, sourceSessionIds: ["s1"],
                                lastSeenAt: "2026-08-01T00:10:00Z")]
        s.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good", betterExpression: "rewarding",
                                         collocation: "a rewarding trip", priority: "high",
                                         sourceSessionIds: ["s1"])]
        s.targets = [RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子",
                                      status: "new", evidence: ["I just like it."],
                                      sourceSessionId: "s1", createdAt: "2026-08-01T00:10:00Z")]
        let before = s

        let outcome = try PlanRegenerator.regenerate(state: s, lengthDays: 7,
                                                     focusPart: .part1, createdAt: "t")
        PlanRegenerator.apply(outcome, to: &s)

        XCTAssertEqual(s.plan, outcome.plan)
        XCTAssertEqual(s.questions, before.questions, "题目的已练标记不能被重新生成计划清掉")
        XCTAssertEqual(s.sessions, before.sessions)
        XCTAssertEqual(s.issues, before.issues)
        XCTAssertEqual(s.vocabulary, before.vocabulary)
        XCTAssertEqual(s.targets, before.targets)
        XCTAssertEqual(s.settings, before.settings)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PlanRegeneratorTests`
Expected: 编译失败 —— `PlanRegenerator` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/QuestionBank/PlanRegenerator.swift`：

```swift
import Foundation

public struct PlanRegenerationOutcome: Equatable, Sendable {
    public let plan: TrainingPlan
    /// 从旧计划带过来、且仍在新计划里的已完成题 id，顺序与它们在新计划里的出现顺序一致。
    public let carriedOver: [String]
    /// 旧计划里已完成、但新计划范围内已经没有的题 id
    ///（换了重点 Part，或换季重新导入时被出题方删掉）。
    public let dropped: [String]
    /// 给用户看的中文说明：发生了什么 + 下一步做什么。
    public let summary: String

    public init(plan: TrainingPlan, carriedOver: [String], dropped: [String], summary: String) {
        self.plan = plan; self.carriedOver = carriedOver
        self.dropped = dropped; self.summary = summary
    }
}

/// 重新生成学习计划。**唯一的硬要求：已经练过的题，重新生成之后还是练过的。**
public enum PlanRegenerator {

    /// 把旧计划里「已完成」的标记搬到新计划上。
    ///
    /// 只按题目 id 匹配。题目 id 是内容哈希（见 QuestionBankImporter.questionID），
    /// 换季重新导入题库后同一道题的 id 不变，所以这个搬运在换季场景下依然成立——
    /// 这正是成品标准第 12 条守的东西。
    public static func carryOverProgress(from old: TrainingPlan?,
                                         to fresh: TrainingPlan) -> TrainingPlan {
        guard let old else { return fresh }
        let alreadyDone = Set(old.days.flatMap(\.completedQuestionIds))
        var updated = fresh
        for id in fresh.days.flatMap(\.questionIds) where alreadyDone.contains(id) {
            updated = PlanBuilder.markCompleted(plan: updated, questionID: id)
        }
        return updated
    }

    public static func regenerate(state: CoachState, lengthDays: Int, focusPart: FocusPart,
                                  createdAt: String) throws -> PlanRegenerationOutcome {
        let selected = PlanScope.select(from: state.questions, focusPart: focusPart)
        if let reason = PlanScope.blockingReason(questionCount: selected.count,
                                                 lengthDays: lengthDays, focusPart: focusPart) {
            throw CoachError.planImpossible(reason)
        }

        // lengthDays 不在 7/14/30 里时由 PlanBuilder 抛错，它的消息已经说清了下一步。
        var fresh = try PlanBuilder.build(questions: selected, lengthDays: lengthDays,
                                          createdAt: createdAt)
        fresh.focusPart = focusPart

        let carriedPlan = carryOverProgress(from: state.plan, to: fresh)
        let carriedOver = carriedPlan.days.flatMap(\.completedQuestionIds)

        let freshIDs = Set(fresh.days.flatMap(\.questionIds))
        var seen = Set<String>()
        let dropped = (state.plan?.days.flatMap(\.completedQuestionIds) ?? [])
            .filter { !freshIDs.contains($0) && seen.insert($0).inserted }

        return PlanRegenerationOutcome(
            plan: carriedPlan, carriedOver: carriedOver, dropped: dropped,
            summary: summary(lengthDays: lengthDays, focusPart: focusPart,
                             questionCount: selected.count,
                             carriedOver: carriedOver.count, dropped: dropped.count))
    }

    /// **只写 plan，别的一个字段都不碰。**
    /// 「重新生成计划」是重排今后练什么，不是清空练过什么。顺手把 question.status
    /// 重置成 new、或清掉 sessions 这类「看起来很合理」的改动，
    /// 会让用户一次点击丢掉全部历史。
    public static func apply(_ outcome: PlanRegenerationOutcome, to state: inout CoachState) {
        state.plan = outcome.plan
    }

    // MARK: - 文案

    private static func summary(lengthDays: Int, focusPart: FocusPart, questionCount: Int,
                                carriedOver: Int, dropped: Int) -> String {
        var text = "已生成 \(lengthDays) 天计划：\(PlanScope.label(for: focusPart))，共 \(questionCount) 道题。"
        if carriedOver > 0 {
            text += "你之前练过的 \(carriedOver) 道题仍然算已完成。"
        }
        if dropped > 0 {
            text += "另有 \(dropped) 道练过的题不在新计划范围内（换了重点 Part，或换季重新导入时题库里没有它了）；"
                + "它们的练习记录与复盘仍然保留在「训练记录」和「复盘报告」里，没有丢。"
        }
        text += "下一步：回「今日训练」页点「按计划练今天」就能开始。"
        return text
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PlanRegeneratorTests`
Expected: PASS（13 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（本阶段最重要的两条）**

做两次，每次改完跑一遍再改回来：

1. 把 `carryOverProgress` 的函数体整个换成 `return fresh`（即「重新生成就是重新开始」）
   Expected: `testCarriesCompletedQuestionsAcrossACycleChange`、`testCarriesProgressWhenTheFocusPartNarrows`、`testKeepsProgressAfterASeasonalReimport`、`testReportsCompletedQuestionsThatTheBankNoLongerHas` **全部变红**
2. 在 `apply` 里加一行「顺手重置」：
   ```swift
   for index in state.questions.indices { state.questions[index].status = "new" }
   ```
   Expected: `testApplyOnlyTouchesThePlan` **变红**

两次都改回后确认全绿。把四次输出写进报告。

**第 2 条守的正是那种「看起来很合理」的改动**——重新生成计划顺手把题目状态清一遍，代码审查时很容易放过去，而用户会因此丢掉全部「练过」的标记。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/QuestionBank/PlanRegenerator.swift Tests/IELTSCoachCoreTests/PlanRegeneratorTests.swift
git commit -m "feat(core): 重新生成计划且不丢已有进度"
```

---

## Task 5: `PlanViewModel` —— 计划页的只读展示逻辑

**Files:**
- Create: `Sources/IELTSCoachUI/Plan/PlanViewModel.swift`
- Create: `Tests/IELTSCoachUITests/PlanViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`plan`、`questions`）、`TrainingPlan`、`PlanDay`、`Question`、`FocusPart`
- Produces:
  - `struct PlanQuestionRow: Equatable, Identifiable, Sendable`，字段 `id: String`、`part: Int`、`topic: String`、`prompt: String`、`isCompleted: Bool`、`isMissing: Bool`
  - `struct PlanDayRow: Equatable, Identifiable, Sendable`，字段 `id: Int`、`items: [PlanQuestionRow]`、`isComplete: Bool`、`isToday: Bool`
  - `struct PlanViewModel: Sendable`，含 `init(state:)`、`hasPlan: Bool`、`lengthDays: Int?`、`focusPart: FocusPart?`、`todayNumber: Int?`、`progress: (done: Int, total: Int)`、`isFinished: Bool`、`dayRows: [PlanDayRow]`

**两条容易做错的地方，都有测试守着：**

1. **「今天」与日历无关。** 计划里没有日期字段，进度只随「练完一题」前进。「今天」= 第一个还有题没做完的那一天。用日历推进会让请假两天的人一打开就看到「落后 2 天」——那只会让人不想练，与产品目标背道而驰。
2. **不能用 `TrainingPlan.isComplete` 判断计划完成。** 题数少于天数时（旧版本或命令行生成的计划就是这种形状），尾部会留下没有题的空天，而 `PlanDay.isComplete` 的定义要求 `!questionIds.isEmpty`，空天永远不算完成。用它判断，这类计划永远显示不出「已完成」。进度按**题目**算，不按天算。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PlanViewModelTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PlanViewModelTests: XCTestCase {

    private func q(_ id: String, _ part: Int = 1) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "P-\(id)")
    }

    private func state(_ questions: [Question], _ plan: TrainingPlan?) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.plan = plan
        return s
    }

    private func plan(_ days: [PlanDay], length: Int = 7,
                      focus: FocusPart = .part1) -> TrainingPlan {
        TrainingPlan(lengthDays: length, createdAt: "2026-08-06T00:00:00Z",
                     days: days, focusPart: focus)
    }

    func testNoPlanMeansEmptyEverything() {
        let vm = PlanViewModel(state: state([q("a")], nil))
        XCTAssertFalse(vm.hasPlan)
        XCTAssertTrue(vm.dayRows.isEmpty)
        XCTAssertNil(vm.todayNumber)
        XCTAssertEqual(vm.progress.total, 0)
        XCTAssertFalse(vm.isFinished)
    }

    /// 「今天」= 第一个还有题没做完的那一天，与日历日期无关。
    /// 用日历推进会让请假两天的人一打开就看到「落后 2 天」——那只会让人不想练。
    func testTodayIsTheFirstDayThatStillHasSomethingToDo() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a", "b"]),
            PlanDay(id: 2, questionIds: ["c", "d"], completedQuestionIds: ["c"]),
            PlanDay(id: 3, questionIds: ["e"], completedQuestionIds: [])
        ])
        let vm = PlanViewModel(state: state(["a", "b", "c", "d", "e"].map { q($0) }, p))
        XCTAssertEqual(vm.todayNumber, 2, "第 2 天还有一道没做完，它就是「今天」")
        XCTAssertEqual(vm.dayRows.first(where: \.isToday)?.id, 2)
        XCTAssertEqual(vm.dayRows.filter(\.isToday).count, 1, "「今天」只能有一天")
    }

    func testProgressCountsQuestionsNotDays() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a", "b"]),
            PlanDay(id: 2, questionIds: ["c", "d"], completedQuestionIds: ["c"])
        ])
        let vm = PlanViewModel(state: state(["a", "b", "c", "d"].map { q($0) }, p))
        XCTAssertEqual(vm.progress.done, 3)
        XCTAssertEqual(vm.progress.total, 4)
        XCTAssertFalse(vm.isFinished)
    }

    /// 题数少于天数时（旧版本与命令行生成的计划就是这种形状），尾部会留下没有题的空天，
    /// 而 PlanDay.isComplete 要求 questionIds 非空，空天永远不算完成。
    /// 若进度沿用 TrainingPlan.isComplete，这类计划永远显示不出「已完成」，
    /// 用户会一直以为自己还差一点。
    func testFinishedEvenWhenLegacyPlanHasTrailingEmptyDays() {
        let p = plan([
            PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"]),
            PlanDay(id: 2, questionIds: ["b"], completedQuestionIds: ["b"]),
            PlanDay(id: 3, questionIds: [], completedQuestionIds: []),
            PlanDay(id: 4, questionIds: [], completedQuestionIds: [])
        ])
        let vm = PlanViewModel(state: state([q("a"), q("b")], p))
        XCTAssertTrue(vm.isFinished)
        XCTAssertNil(vm.todayNumber, "全做完之后不该再有「今天」")
        XCTAssertEqual(vm.dayRows.count, 2, "没有题的空天不该出现在列表里")
    }

    func testRowsCarryPromptAndCompletionFromTheBank() throws {
        let p = plan([PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a"])])
        let vm = PlanViewModel(state: state([q("a"), q("b", 2)], p))
        let day = try XCTUnwrap(vm.dayRows.first)
        XCTAssertEqual(day.items.map(\.id), ["a", "b"])
        XCTAssertEqual(day.items[0].prompt, "P-a")
        XCTAssertTrue(day.items[0].isCompleted)
        XCTAssertFalse(day.items[1].isCompleted)
        XCTAssertEqual(day.items[1].part, 2)
        XCTAssertFalse(day.items.contains(where: \.isMissing))
    }

    /// 换季重新导入时出题方删掉了某道题，计划里还留着它的 id。
    /// 这一行必须显示成「这道题没了 + 怎么办」，不能是一行空白——
    /// 空白会让用户以为程序坏了。
    func testMissingQuestionBecomesAnExplainedRowNotABlankOne() throws {
        let p = plan([PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])])
        let vm = PlanViewModel(state: state([q("a")], p))
        let row = try XCTUnwrap(vm.dayRows.first?.items.first)
        XCTAssertTrue(row.isMissing)
        XCTAssertFalse(row.prompt.isEmpty)
        XCTAssertTrue(row.prompt.contains("下一步"))
    }

    func testExposesLengthAndFocusPartOfTheCurrentPlan() {
        let p = plan([PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])],
                     length: 14, focus: .part3)
        let vm = PlanViewModel(state: state([q("a")], p))
        XCTAssertEqual(vm.lengthDays, 14)
        XCTAssertEqual(vm.focusPart, .part3)
    }

    /// 手工拼的题库里同一个 id 出现两次很常见（复制粘贴忘改编号）。
    /// 用 Dictionary(uniqueKeysWithValues:) 建索引会直接 fatalError 闪退整个 App——
    /// QuestionBankImporter 里已经栽过一次，那条注释还在。
    func testDuplicateQuestionIDsInTheBankDoNotCrash() {
        let p = plan([PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])])
        let vm = PlanViewModel(state: state([q("a"), q("a")], p))
        XCTAssertEqual(vm.dayRows.first?.items.count, 1)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PlanViewModelTests`
Expected: 编译失败 —— `PlanViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Plan/PlanViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct PlanQuestionRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// 题目已不在题库里时为 0
    public let part: Int
    public let topic: String
    /// 题目已不在题库里时，这里放的是中文说明（发生了什么 + 下一步），不是空字符串
    public let prompt: String
    public let isCompleted: Bool
    public let isMissing: Bool

    public init(id: String, part: Int, topic: String, prompt: String,
                isCompleted: Bool, isMissing: Bool) {
        self.id = id; self.part = part; self.topic = topic; self.prompt = prompt
        self.isCompleted = isCompleted; self.isMissing = isMissing
    }
}

public struct PlanDayRow: Equatable, Identifiable, Sendable {
    /// 第几天，从 1 开始
    public let id: Int
    public let items: [PlanQuestionRow]
    public let isComplete: Bool
    public let isToday: Bool

    public init(id: Int, items: [PlanQuestionRow], isComplete: Bool, isToday: Bool) {
        self.id = id; self.items = items; self.isComplete = isComplete; self.isToday = isToday
    }
}

public struct PlanViewModel: Sendable {
    public let state: CoachState

    public init(state: CoachState) { self.state = state }

    public var hasPlan: Bool { state.plan != nil }
    public var lengthDays: Int? { state.plan?.lengthDays }
    public var focusPart: FocusPart? { state.plan?.focusPart }

    /// 「今天」是第一个还有题没做完的那一天，**与日历日期无关**。
    /// 计划里没有日期字段，进度只随「练完一题」前进——用日历推进会让请假两天的人
    /// 一打开就看到「落后 2 天」，那只会让人不想练。
    /// 全部做完时返回 nil。
    public var todayNumber: Int? {
        state.plan?.days.first { !$0.isComplete && !$0.questionIds.isEmpty }?.id
    }

    /// 进度按**题目**算，不按天算。
    public var progress: (done: Int, total: Int) {
        guard let plan = state.plan else { return (0, 0) }
        let scheduled = plan.days.flatMap(\.questionIds)
        let done = Set(plan.days.flatMap(\.completedQuestionIds))
        return (scheduled.filter { done.contains($0) }.count, scheduled.count)
    }

    /// **不能用 TrainingPlan.isComplete。** 题数少于天数时尾部会留下没有题的空天，
    /// 而 PlanDay.isComplete 要求 questionIds 非空，空天永远不算完成——
    /// 那样的计划永远显示不出「已完成」，用户会一直以为自己还差一点。
    /// 旧版本与命令行生成的计划正是这种形状。
    public var isFinished: Bool {
        let current = progress
        return current.total > 0 && current.done == current.total
    }

    public var dayRows: [PlanDayRow] {
        guard let plan = state.plan else { return [] }
        let today = todayNumber
        // uniquingKeysWith 不能省：手工拼的题库里同一个 id 出现两次很常见，
        // Dictionary(uniqueKeysWithValues:) 遇到重复 key 会 fatalError 闪退整个 App。
        let byID = Dictionary(state.questions.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })

        return plan.days.filter { !$0.questionIds.isEmpty }.map { day in
            let done = Set(day.completedQuestionIds)
            let items = day.questionIds.map { id -> PlanQuestionRow in
                guard let question = byID[id] else {
                    // 空白行会让用户以为程序坏了。这里必须说清发生了什么和下一步做什么。
                    return PlanQuestionRow(
                        id: id, part: 0, topic: "",
                        prompt: "这道题已经不在题库里了（换季重新导入时可能被删掉）。"
                            + "下一步：在本页重新生成计划把它换掉，已经练过的进度不会丢。",
                        isCompleted: done.contains(id), isMissing: true)
                }
                return PlanQuestionRow(id: id, part: question.part, topic: question.topic,
                                       prompt: question.prompt,
                                       isCompleted: done.contains(id), isMissing: false)
            }
            return PlanDayRow(id: day.id, items: items,
                              isComplete: day.isComplete, isToday: day.id == today)
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PlanViewModelTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证**

把 `isFinished` 的实现换成 `state.plan?.isComplete ?? false`，重跑：

Run: `swift test --filter PlanViewModelTests`
Expected: `testFinishedEvenWhenLegacyPlanHasTrailingEmptyDays` **变红**

改回后确认全绿。

**这条守的是一个不报错、不崩溃的失败**：用户明明把题都练完了，界面上「计划完成」四个字永远不出现。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Plan/PlanViewModel.swift Tests/IELTSCoachUITests/PlanViewModelTests.swift
git commit -m "feat(ui): 学习计划页的展示逻辑"
```

---

## Task 6: `PlanDraft` —— 生成之前先告诉用户会得到什么

**Files:**
- Create: `Sources/IELTSCoachUI/Plan/PlanDraft.swift`
- Create: `Tests/IELTSCoachUITests/PlanDraftPreviewTests.swift`

**Interfaces:**
- Consumes: `CoachState.questions`、`FocusPart`、`PlanScope.select`、`PlanScope.blockingReason`
- Produces:
  - `struct PlanDraft: Equatable, Sendable`，字段 `lengthDays: Int`、`focusPart: FocusPart`，`init(lengthDays: Int = 7, focusPart: FocusPart = .fullMock)`
  - `struct PlanDraftPreview: Equatable, Sendable`，字段 `questionCount: Int`、`perDayText: String`、`canBuild: Bool`、`blockingReason: String`
  - `PlanDraftPreviewBuilder.preview(state: CoachState, draft: PlanDraft) -> PlanDraftPreview`

**为什么要有预览：** 用户在计划页拖动周期、切换重点 Part 时，得当场看到「Part 2 现在 18 题，分 7 天，每天 2–3 题」。选到一个做不出来的组合时，**「生成」按钮要能明确说清为什么不能点**，而不是让人点下去撞一个报错。

**预览与真正生成必须用同一个判据。** 「预览说能生成、点下去却报错」是最伤信任的一类界面缺陷。本任务有一条穷举测试守这个一致性。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PlanDraftPreviewTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PlanDraftPreviewTests: XCTestCase {

    private func q(_ id: String, _ part: Int) -> Question {
        Question(id: id, part: part, topic: "T", prompt: "P-\(id)")
    }

    private func state(_ questions: [Question]) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        return s
    }

    func testDefaultDraftIsSevenDaysFullMock() {
        let draft = PlanDraft()
        XCTAssertEqual(draft.lengthDays, 7)
        XCTAssertEqual(draft.focusPart, .fullMock)
    }

    func testEvenSplitReadsAsASingleNumber() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...21).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertEqual(preview.questionCount, 21)
        XCTAssertEqual(preview.perDayText, "每天 3 题")
    }

    func testUnevenSplitReadsAsARange() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...23).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertEqual(preview.perDayText, "每天 3–4 题")
    }

    func testEmptyBankPointsAtTheQuestionBankPage() {
        let preview = PlanDraftPreviewBuilder.preview(state: state([]), draft: PlanDraft())
        XCTAssertFalse(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.contains("训练题库"))
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
    }

    func testPartWithoutQuestionsSaysWhichPart() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...10).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part2))
        XCTAssertFalse(preview.canBuild)
        XCTAssertEqual(preview.questionCount, 0)
        XCTAssertTrue(preview.blockingReason.contains("Part 2"))
        XCTAssertTrue(preview.blockingReason.contains("下一步"))
    }

    func testBlockingReasonIsEmptyWhenItCanBuild() {
        let preview = PlanDraftPreviewBuilder.preview(
            state: state((1...14).map { q("a\($0)", 1) }),
            draft: PlanDraft(lengthDays: 7, focusPart: .part1))
        XCTAssertTrue(preview.canBuild)
        XCTAssertTrue(preview.blockingReason.isEmpty)
    }

    /// 预览说「能生成」，点下去却报错，是最伤信任的一类界面缺陷。
    /// 两处必须用同一个判据，这条穷举验证它们从不分歧。
    func testPreviewAgreesWithWhatRegenerationActuallyDoes() {
        for count in 0...20 {
            for days in [7, 14, 30] {
                let s = state((0..<count).map { q("b\($0)", 2) })
                let preview = PlanDraftPreviewBuilder.preview(
                    state: s, draft: PlanDraft(lengthDays: days, focusPart: .part2))
                var succeeded = false
                do {
                    _ = try PlanRegenerator.regenerate(state: s, lengthDays: days,
                                                       focusPart: .part2, createdAt: "t")
                    succeeded = true
                } catch { succeeded = false }
                XCTAssertEqual(preview.canBuild, succeeded,
                               "题数 \(count)、周期 \(days) 天：预览与实际不一致")
            }
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PlanDraftPreviewTests`
Expected: 编译失败 —— `PlanDraft` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Plan/PlanDraft.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 计划页表单上的当前选择。还没落盘，只是用户正在挑的东西。
public struct PlanDraft: Equatable, Sendable {
    public var lengthDays: Int
    public var focusPart: FocusPart

    public init(lengthDays: Int = 7, focusPart: FocusPart = .fullMock) {
        self.lengthDays = lengthDays
        self.focusPart = focusPart
    }
}

public struct PlanDraftPreview: Equatable, Sendable {
    public let questionCount: Int
    /// 形如「每天 3 题」或「每天 3–4 题」；不能生成时为空字符串
    public let perDayText: String
    public let canBuild: Bool
    /// 不能生成时的中文说明（发生了什么 + 下一步）；能生成时为空字符串
    public let blockingReason: String

    public init(questionCount: Int, perDayText: String, canBuild: Bool, blockingReason: String) {
        self.questionCount = questionCount; self.perDayText = perDayText
        self.canBuild = canBuild; self.blockingReason = blockingReason
    }
}

public enum PlanDraftPreviewBuilder {
    /// 可行性判据**只有一处**：`PlanScope.blockingReason`。
    /// 这里绝对不能再写一套自己的判断——预览说能生成、点下去却报错，
    /// 是最伤信任的一类界面缺陷。
    public static func preview(state: CoachState, draft: PlanDraft) -> PlanDraftPreview {
        let count = PlanScope.select(from: state.questions, focusPart: draft.focusPart).count
        if let reason = PlanScope.blockingReason(questionCount: count,
                                                 lengthDays: draft.lengthDays,
                                                 focusPart: draft.focusPart) {
            return PlanDraftPreview(questionCount: count, perDayText: "",
                                    canBuild: false, blockingReason: reason)
        }
        let base = count / draft.lengthDays
        let remainder = count % draft.lengthDays
        let perDay = remainder == 0 ? "每天 \(base) 题" : "每天 \(base)–\(base + 1) 题"
        return PlanDraftPreview(questionCount: count, perDayText: perDay,
                                canBuild: true, blockingReason: "")
    }
}
```

**注意 `perDayText` 里用的是 en dash「–」，不是连字符「-」。** 测试里也是同一个字符，别改。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PlanDraftPreviewTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

把 `preview` 里那段 `if let reason = ...` 整块删掉（即永远认为能生成），重跑：

Run: `swift test --filter PlanDraftPreviewTests`
Expected: `testPreviewAgreesWithWhatRegenerationActuallyDoes`、`testEmptyBankPointsAtTheQuestionBankPage`、`testPartWithoutQuestionsSaysWhichPart` **全部变红**

改回后确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Plan/PlanDraft.swift Tests/IELTSCoachUITests/PlanDraftPreviewTests.swift
git commit -m "feat(ui): 生成计划前的可行性预览"
```

---

## Task 7: 默认练习路线与 `RouteDefaults`

**Files:**
- Create: `Sources/IELTSCoachUI/Session/PracticeRoutePreference.swift`
- Create: `Tests/IELTSCoachUITests/PracticeRoutePreferenceTests.swift`

**Interfaces:**
- Consumes: `PracticeRoute`（Phase 3 Task 6，`enum PracticeRoute: String, CaseIterable, Identifiable, Sendable`）、`CoachSettings`（含 Task 2 新增的三个字段）、`FeedbackTiming`、`Part2PrepMode`
- Produces:
  - `PracticeRoutePreference.fallback: PracticeRoute`
  - `PracticeRoutePreference.route(fromSettings raw: String) -> PracticeRoute`
  - `PracticeRoutePreference.rawValue(for route: PracticeRoute) -> String`
  - `struct RouteDefaults: Equatable, Sendable`，含 `feedbackTiming: FeedbackTiming`、`part2PrepMode: Part2PrepMode`、`init(feedbackTiming:part2PrepMode:)`（都带默认值）、`init(settings: CoachSettings)`

**这个任务只有一件难事：跨模块的对齐。** Core 存的是字符串（Core 不允许依赖 UI，看不见 `PracticeRoute`）。默认值写错一个字母，界面就会莫名其妙地退回到别的路线，而且不会报任何错。这里有一条专门的测试守它。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PracticeRoutePreferenceTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PracticeRoutePreferenceTests: XCTestCase {

    func testKnownRawValuesRoundTrip() {
        for route in PracticeRoute.allCases {
            XCTAssertEqual(
                PracticeRoutePreference.route(fromSettings: PracticeRoutePreference.rawValue(for: route)),
                route)
        }
    }

    /// state.json 是纯文本，可以被手改，也可能是别的版本写的。
    /// 认不出来的路线名必须退回默认路线，而不是让今日训练页空着。
    func testUnknownRawValueFallsBackToThePlanRoute() {
        XCTAssertEqual(PracticeRoutePreference.route(fromSettings: "somethingElse"), .planToday)
        XCTAssertEqual(PracticeRoutePreference.route(fromSettings: ""), .planToday)
    }

    /// Core 存的是字符串（Core 不允许依赖 UI，所以它看不见 PracticeRoute）。
    /// 这条测试是两个模块之间唯一的对齐点：默认值写错一个字母，这里就会红。
    func testCoreDefaultMatchesTheUIRoute() {
        XCTAssertEqual(PracticeRoute(rawValue: CoachSettings.defaultRouteFallback),
                       PracticeRoutePreference.fallback)
        XCTAssertEqual(PracticeRoutePreference.fallback, .planToday,
                       "ROADMAP 第 5 节：练习路线默认「按计划练今天」")
    }

    func testRouteDefaultsComeFromSettings() {
        var settings = CoachSettings(recordingEnabled: false, recordingConsentAt: "")
        settings.feedbackTiming = .immediate
        settings.part2PrepMode = .learnerControlled
        let defaults = RouteDefaults(settings: settings)
        XCTAssertEqual(defaults.feedbackTiming, .immediate)
        XCTAssertEqual(defaults.part2PrepMode, .learnerControlled)
    }

    func testRouteDefaultsFallBackToTheDocumentedDefaults() {
        let defaults = RouteDefaults()
        XCTAssertEqual(defaults.feedbackTiming, .deferred)
        XCTAssertEqual(defaults.part2PrepMode, .countdown)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRoutePreferenceTests`
Expected: 编译失败 —— `PracticeRoutePreference` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Session/PracticeRoutePreference.swift`：

```swift
import Foundation
import IELTSCoachCore

public enum PracticeRoutePreference {
    /// ROADMAP 第 5 节：练习路线默认「按计划练今天」。
    public static let fallback: PracticeRoute = .planToday

    /// state.json 里存的是 PracticeRoute 的 rawValue。
    /// 认不出来时退回默认路线，**不能返回 nil 让界面空着**——
    /// 手改坏的 state.json、别的版本写进去的路线名都会走到这里，
    /// 而用户该看到的是一个能用的默认值，不是一片空白。
    public static func route(fromSettings raw: String) -> PracticeRoute {
        PracticeRoute(rawValue: raw) ?? fallback
    }

    public static func rawValue(for route: PracticeRoute) -> String { route.rawValue }
}

/// 开练时那两个用户可选项（spec 3.1）。
/// 界面从设置里取，测试里可以直接构造。
public struct RouteDefaults: Equatable, Sendable {
    public let feedbackTiming: FeedbackTiming
    public let part2PrepMode: Part2PrepMode

    public init(feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown) {
        self.feedbackTiming = feedbackTiming
        self.part2PrepMode = part2PrepMode
    }

    public init(settings: CoachSettings) {
        self.init(feedbackTiming: settings.feedbackTiming,
                  part2PrepMode: settings.part2PrepMode)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRoutePreferenceTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

做两次：

1. 把 `route(fromSettings:)` 里的 `?? fallback` 改成 `?? .freePick`
   Expected: `testUnknownRawValueFallsBackToThePlanRoute` **变红**
2. 把 `Sources/IELTSCoachCore/Model/CoachState.swift` 里的
   `defaultRouteFallback = "planToday"` 改成 `= "today"`
   Expected: `testCoreDefaultMatchesTheUIRoute` **变红**（`PracticeRoute(rawValue: "today")` 是 nil）

两次都改回后确认全绿。

**第 2 条守的是跨模块的字符串对齐**——Core 与 UI 之间唯一靠约定而不是靠类型保证的地方。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Session/PracticeRoutePreference.swift Tests/IELTSCoachUITests/PracticeRoutePreferenceTests.swift
git commit -m "feat(ui): 默认练习路线与练习偏好默认值"
```

---

## Task 8: `PracticeRouteResolver` —— 四条路线统一解析成一场练习

**Files:**
- Create: `Sources/IELTSCoachUI/Session/PracticeRouteResolver.swift`
- Create: `Tests/IELTSCoachUITests/PracticeRouteResolverTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`plan`、`questions`、`sessions`、`targets`、`issues`）、`Question`、`PracticeSession`、`RetrainingTarget`、`RetrainingPolicy.rank(targets:issues:)`、`SessionSetup(question:focusPart:durationMinutes:goal:feedbackTiming:part2PrepMode:)`、`FocusPart`、`PracticeRoute`、`RouteDefaults`、**`RetrainingSetupBuilder.goalText(for:)`（Phase 6 Task 8）**、`TodayViewModel`（仅测试里用）

> **若 Phase 6 尚未交付**（`ls Sources/IELTSCoachUI/Retraining/RetrainingSetupBuilder.swift` 没有输出），
> 把 `resolveRetrain` 里那一行换成等价的内联写法并在报告里写明，**行为必须完全一样**：
> ```swift
> let trimmed = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
> let label = trimmed.isEmpty
>     ? target.targetKey.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
> ```
> Phase 6 交付后，**由 Phase 6 的实现者把这段换回调用 `goalText(for:)`**，两份判断不许长期并存。
- Produces:
  - `enum RouteResolution: Equatable, Sendable { case ready(SessionSetup), unavailable(String) }`
  - `PracticeRouteResolver.resolve(route:state:selectedQuestionID:defaults:) -> RouteResolution`
  - `PracticeRouteResolver.setup(for question: Question, goal: String, defaults: RouteDefaults) -> SessionSetup`
  - `PracticeRouteResolver.availableRoutes(state:preferring:defaults:) -> [PracticeRoute]`

**本任务确立本阶段最重要的一条不变量：界面上显示出来的路线，点下去一定能开练。**（「从题库自由选题」除外——它天生要先选题。）

Phase 3 的 `TodayViewModel.availableRoutes` 判断的是「前提成立」（有计划 / 有题 / 有记录 / 有目标）。但前提成立不等于能开练：上次练的那道题可能已经被换季删掉了；复训目标指向的那次练习记录可能已被删除；复盘给的 `priority_target.label` 可能是空的。**显示一条点了没用的路线，比不显示更糟——用户会以为程序坏了**（Phase 3 已经写下过这条判断）。

所以「能不能显示」直接由「能不能解析出 `SessionSetup`」决定，两者用同一段代码。

**关于空目标：** `RetrainingPolicy.extractTarget` 对 `label` 用的是 `?? ""`，所以 label 完全可能是空的。空目标带进 `ExaminerPrompt.build`，「本次唯一目标」那一整段会被跳过（见 `ExaminerPrompt.swift` 第 156–163 行），于是「复训」和普通练习一模一样——不报错、不崩溃，只是白练一场。**静默地什么都没发生，是本项目已知最危险的失败形态**（spec 2.3.8 的原话）。

**拦法由跨阶段决策 6（2026-08-06）定：回落成 `targetKey` 照常开练，不是拒绝开练。**（本任务初稿写的是返回 `.unavailable(…)`，已改。）拦的是「goal 变成空串」这件事，不是拦用户。Phase 6 的 `RetrainingSetupBuilder.goalText(for:)` 已经是这个口径，**两条路径必须走同一份实现**——否则从复训中心进和从今日训练页进会是两种行为，而这正是决策 6 要消除的东西。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PracticeRouteResolverTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class PracticeRouteResolverTests: XCTestCase {

    // MARK: - 构造 state 的工具

    private func q(_ id: String, _ part: Int = 1) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "P-\(id)")
    }

    private func session(_ id: String, question: String, startedAt: String,
                         goal: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: goal, transcript: [],
                        reportPath: "reports/\(id).json", recordingPath: "")
    }

    private func target(_ key: String, label: String, session: String,
                        status: String = "new", evidence: [String] = []) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: label, status: status, evidence: evidence,
                         sourceSessionId: session, createdAt: "2026-08-01T00:00:00Z")
    }

    private func state(questions: [Question] = [], planDays: [PlanDay]? = nil,
                       sessions: [PracticeSession] = [], targets: [RetrainingTarget] = [],
                       issues: [IssueRecord] = []) -> CoachState {
        var s = CoachState.empty()
        s.questions = questions
        s.sessions = sessions
        s.targets = targets
        s.issues = issues
        if let planDays {
            s.plan = TrainingPlan(lengthDays: 7, createdAt: "2026-08-06T00:00:00Z",
                                  days: planDays, focusPart: .part1)
        }
        return s
    }

    // MARK: - 按计划练今天

    func testPlanTodayPicksTheFirstQuestionThatIsNotDoneYet() {
        let s = state(questions: [q("a"), q("b"), q("c")],
                      planDays: [PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: ["a"]),
                                 PlanDay(id: 2, questionIds: ["c"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(route: .planToday, state: s) else {
            return XCTFail("应当能开练")
        }
        XCTAssertEqual(setup.question.id, "b", "a 今天已经练过了，再给它一次计划不会前进")
    }

    func testPlanTodayHonoursAnExplicitPickAmongTodaysQuestions() {
        let s = state(questions: [q("a"), q("b")],
                      planDays: [PlanDay(id: 1, questionIds: ["a", "b"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .planToday, state: s, selectedQuestionID: "b") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
    }

    func testPlanTodayIgnoresAPickThatIsNotOnTodaysList() {
        let s = state(questions: [q("a"), q("b"), q("c")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: []),
                                 PlanDay(id: 2, questionIds: ["b", "c"], completedQuestionIds: [])])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .planToday, state: s, selectedQuestionID: "c") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "a", "点了明天的题也只能练今天的，否则计划进度会乱")
    }

    func testPlanTodayUnavailableWithoutAPlan() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: state(questions: [q("a")])) else {
            return XCTFail("没有计划时不该能开练")
        }
        XCTAssertTrue(message.contains("学习计划"), "要告诉用户去哪儿生成计划")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testPlanTodayUnavailableWhenEverythingIsDone() {
        let s = state(questions: [q("a")],
                      planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"])])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: s) else { return XCTFail("练完了不该还能「按计划练今天」") }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testPlanTodayUnavailableWhenTodaysQuestionVanishedFromTheBank() {
        let s = state(questions: [q("other")],
                      planDays: [PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .planToday, state: s) else { return XCTFail("题没了就不该假装能练") }
        XCTAssertTrue(message.contains("重新生成"))
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 从题库自由选题

    func testFreePickNeedsASelection() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .freePick, state: state(questions: [q("a")])) else {
            return XCTFail("没选题就不该开练")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testFreePickUsesTheSelectedQuestion() {
        let s = state(questions: [q("a"), q("b", 2)])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "b") else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
        XCTAssertEqual(setup.focusPart, .part2)
        XCTAssertEqual(setup.durationMinutes, 4, "Part 2 是一张 cue card，4 分钟")
    }

    func testFreePickRejectsAnUnknownQuestionID() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .freePick, state: state(questions: [q("a")]),
            selectedQuestionID: "nope") else { return XCTFail("题库里没有这道题就不该开练") }
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 继续上次练习

    func testContinueLastUsesTheMostRecentSession() {
        let s = state(questions: [q("a"), q("b")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z"),
                                 session("s2", question: "b", startedAt: "2026-08-04T10:00:00Z")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "b")
    }

    func testContinueLastCarriesTheGoalFromThatSession() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z",
                                         goal: "回答后补一个原因和例子")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.goal, "回答后补一个原因和例子",
                       "「继续上次」的意思就是接着上次那件事再练一遍")
    }

    func testContinueLastUnavailableWithoutSessions() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .continueLast, state: state(questions: [q("a")])) else {
            return XCTFail("没有练习记录就没有「上次」")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testContinueLastUnavailableWhenThatQuestionIsGone() {
        let s = state(questions: [q("other")],
                      sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .continueLast, state: s) else { return XCTFail("题没了就不该假装能练") }
        XCTAssertTrue(message.contains("复盘报告"), "要告诉用户那次练习本身没丢")
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - 复训一个旧问题

    func testRetrainBringsTheTargetInAsTheSessionGoal() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("logic-explain", label: "回答后补一个原因和例子", session: "s1")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.question.id, "a", "复训先重答提出这个目标的那道原题")
        XCTAssertEqual(setup.goal, "回答后补一个原因和例子")
    }

    func testRetrainPrefersTheTargetRankedFirst() {
        // RetrainingPolicy.rank 会把「证据命中高频错题」的目标排前面。
        let s = state(questions: [q("a"), q("b")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z"),
                                 session("s2", question: "b", startedAt: "2026-08-02T10:00:00Z")],
                      targets: [target("t1", label: "目标一", session: "s1"),
                                target("t2", label: "目标二", session: "s2",
                                       evidence: ["I very like it"])],
                      issues: [IssueRecord(id: "i1", learnerSaid: "I very like it",
                                           correction: "I really like it",
                                           whyItMatters: "very 不能修饰动词", occurrences: 4,
                                           sourceSessionIds: ["s2"],
                                           lastSeenAt: "2026-08-02T10:00:00Z")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("应当能开练") }
        XCTAssertEqual(setup.goal, "目标二")
        XCTAssertEqual(setup.question.id, "b")
    }

    func testRetrainIgnoresRetiredTargets() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("t1", label: "已经改掉了", session: "s1", status: "retired")])
        guard case .unavailable = PracticeRouteResolver.resolve(route: .retrain, state: s) else {
            return XCTFail("已退休的目标不该还能被复训")
        }
    }

    /// 复盘里 priority_target 的 label 可能是空的（RetrainingPolicy.extractTarget 用的是 ?? ""）。
    /// 空目标带进 ExaminerPrompt，「本次唯一目标」那一整段会被跳过，
    /// 于是「复训」和普通练习一模一样——不报错、不崩溃，只是白练一场。
    ///
    /// **跨阶段决策 6（2026-08-06）：回落成 `targetKey` 照常开练，不拒绝。**
    /// 用户是来练英语的，因为一个内部字段是空的就不让他练，代价不成比例。
    /// 这与 Phase 6 的 `RetrainingSetupBuilder.goalText(for:)` 是同一个口径——
    /// **两条路径必须一致**，否则从复训中心进和从今日训练页进会是两种行为。
    func testRetrainFallsBackToTheTargetKeySoTheGoalIsNeverBlank() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                      targets: [target("t1", label: "   ", session: "s1")])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("label 是空的不该挡住练习") }
        XCTAssertEqual(setup.goal, "t1", "label 为空时要回落成 targetKey")
        XCTAssertFalse(setup.goal.isEmpty,
                       "goal 一旦是空串，复训会静默退化成普通练习——这是决策 6 真正要挡的东西")
    }

    func testRetrainUnavailableWhenTheSourceSessionIsGone() {
        let s = state(questions: [q("a")],
                      targets: [target("t1", label: "补一个例子", session: "missing")])
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .retrain, state: s) else { return XCTFail("找不到出处就不该开练") }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testRetrainUnavailableWithoutAnyTarget() {
        guard case .unavailable(let message) = PracticeRouteResolver.resolve(
            route: .retrain, state: state(questions: [q("a")])) else {
            return XCTFail("没有目标就不该能复训")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    // MARK: - SessionSetup 的取值

    func testDurationAndFocusPartFollowTheQuestionsPart() {
        let cases: [(Int, Int, FocusPart)] = [(1, 6, .part1), (2, 4, .part2), (3, 6, .part3)]
        for (part, minutes, focus) in cases {
            let s = state(questions: [q("x", part)])
            guard case .ready(let setup) = PracticeRouteResolver.resolve(
                route: .freePick, state: s, selectedQuestionID: "x") else {
                return XCTFail("Part \(part) 解析失败")
            }
            XCTAssertEqual(setup.durationMinutes, minutes)
            XCTAssertEqual(setup.focusPart, focus)
        }
    }

    func testOutOfRangePartFallsBackToFullMockInsteadOfCrashing() {
        let s = state(questions: [q("x", 9)])
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "x") else { return XCTFail("不该解析失败") }
        XCTAssertEqual(setup.focusPart, .fullMock)
    }

    func testDefaultsFlowIntoTheSetup() {
        let s = state(questions: [q("a")])
        let defaults = RouteDefaults(feedbackTiming: .immediate, part2PrepMode: .learnerControlled)
        guard case .ready(let setup) = PracticeRouteResolver.resolve(
            route: .freePick, state: s, selectedQuestionID: "a", defaults: defaults) else {
            return XCTFail("应当能开练")
        }
        XCTAssertEqual(setup.feedbackTiming, .immediate)
        XCTAssertEqual(setup.part2PrepMode, .learnerControlled)
    }

    // MARK: - 可用路线

    private func assortedStates() -> [CoachState] {
        [
            CoachState.empty(),
            state(questions: [q("a"), q("b")]),
            state(questions: [q("a"), q("b")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: [])]),
            state(questions: [q("a")],
                  planDays: [PlanDay(id: 1, questionIds: ["a"], completedQuestionIds: ["a"])]),
            state(questions: [q("other")],
                  planDays: [PlanDay(id: 1, questionIds: ["gone"], completedQuestionIds: [])]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")]),
            state(questions: [q("other")],
                  sessions: [session("s1", question: "gone", startedAt: "2026-08-01T10:00:00Z")]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                  targets: [target("t1", label: "补一个例子", session: "s1")]),
            state(questions: [q("a")],
                  sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")],
                  targets: [target("t1", label: "", session: "s1")]),
            state(questions: [q("other")],
                  targets: [target("t1", label: "补一个例子", session: "missing")])
        ]
    }

    /// 本阶段最重要的一条不变量：**界面上显示出来的路线，点下去一定能开练。**
    /// 显示一条点了没用的路线，用户只会以为程序坏了。
    /// 「自由选题」除外——它天生要先选题才能解析出题目。
    func testEveryShownRouteCanActuallyStart() {
        for s in assortedStates() {
            for route in PracticeRouteResolver.availableRoutes(state: s, preferring: .planToday)
            where route != .freePick {
                guard case .ready = PracticeRouteResolver.resolve(route: route, state: s) else {
                    return XCTFail("路线「\(route.title)」显示了却开不了练")
                }
            }
        }
    }

    /// 显示条件只能比 Phase 3 的前提判断更严，不能更松。
    func testShownRoutesNeverExceedPhase3Preconditions() {
        for s in assortedStates() {
            let shown = Set(PracticeRouteResolver.availableRoutes(state: s, preferring: .planToday))
            let preconditions = Set(TodayViewModel(state: s).availableRoutes)
            XCTAssertTrue(shown.isSubset(of: preconditions),
                          "显示的路线超出了今日训练页的前提判断：\(shown.subtracting(preconditions))")
        }
    }

    func testPreferredRouteComesFirst() {
        let s = state(questions: [q("a")],
                      sessions: [session("s1", question: "a", startedAt: "2026-08-01T10:00:00Z")])
        XCTAssertEqual(PracticeRouteResolver.availableRoutes(state: s, preferring: .continueLast),
                       [.continueLast, .freePick])
        XCTAssertEqual(PracticeRouteResolver.availableRoutes(state: s, preferring: .freePick),
                       [.freePick, .continueLast])
    }

    /// 默认路线是「按计划练今天」，但根本没有计划——
    /// 它不能因为「是默认」就被塞进列表。
    func testUnavailablePreferredRouteDoesNotSneakIn() {
        let routes = PracticeRouteResolver.availableRoutes(state: state(questions: [q("a")]),
                                                           preferring: .planToday)
        XCTAssertEqual(routes, [.freePick])
    }

    func testNoRoutesAtAllWhenThereIsNothingToPractice() {
        XCTAssertTrue(PracticeRouteResolver.availableRoutes(state: CoachState.empty(),
                                                            preferring: .planToday).isEmpty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRouteResolverTests`
Expected: 编译失败 —— `PracticeRouteResolver`、`RouteResolution` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Session/PracticeRouteResolver.swift`：

```swift
import Foundation
import IELTSCoachCore

public enum RouteResolution: Equatable, Sendable {
    case ready(SessionSetup)
    /// 中文说明：发生了什么 + 下一步做什么。界面必须把它显示出来。
    case unavailable(String)
}

/// 四条练习路线 → 一场具体的练习。
///
/// **「这条路线能不能显示」与「这条路线练哪道题」用的是同一段代码。**
/// 分成两处写，迟早会出现「卡片显示了、点下去说不行」——用户会以为程序坏了。
public enum PracticeRouteResolver {

    // MARK: - 一场练习的取值

    /// 取值与命令行保持一致（见 `Sources/coach/PracticeCommand.swift` 第 61–64 行）：
    /// Part 2 是一张 cue card，4 分钟够；其余 6 分钟。
    /// 题目的 part 落在 1–3 之外（手改坏的 state.json）时按全真模考处理，不崩。
    public static func setup(for question: Question, goal: String,
                             defaults: RouteDefaults) -> SessionSetup {
        SessionSetup(question: question,
                     focusPart: FocusPart(rawValue: "Part \(question.part)") ?? .fullMock,
                     durationMinutes: question.part == 2 ? 4 : 6,
                     goal: goal,
                     feedbackTiming: defaults.feedbackTiming,
                     part2PrepMode: defaults.part2PrepMode)
    }

    // MARK: - 解析

    public static func resolve(route: PracticeRoute, state: CoachState,
                               selectedQuestionID: String? = nil,
                               defaults: RouteDefaults = RouteDefaults()) -> RouteResolution {
        switch route {
        case .planToday:   return resolvePlanToday(state, selectedQuestionID, defaults)
        case .freePick:    return resolveFreePick(state, selectedQuestionID, defaults)
        case .continueLast: return resolveContinueLast(state, defaults)
        case .retrain:     return resolveRetrain(state, defaults)
        }
    }

    private static func resolvePlanToday(_ state: CoachState, _ selectedQuestionID: String?,
                                         _ defaults: RouteDefaults) -> RouteResolution {
        guard let plan = state.plan else {
            return .unavailable("还没有学习计划，所以没有「今天的题」。"
                + "下一步：到「学习计划」页选一个 7 / 14 / 30 天的周期，生成一份计划。")
        }
        guard let day = plan.days.first(where: { !$0.isComplete && !$0.questionIds.isEmpty }) else {
            return .unavailable("计划里的题目已经全部练完了。"
                + "下一步：到「学习计划」页重新生成一份计划，或改用「从题库自由选题」。")
        }
        let done = Set(day.completedQuestionIds)
        let pending = day.questionIds.filter { !done.contains($0) }

        // 优先用调用方指定的那道题（用户在今日题目列表里点了哪道就练哪道），
        // 但只认今天还没练的那几道。点一道已经练完的题却当成「按计划练今天」，
        // 计划进度不会前进，用户会以为程序坏了。
        let wanted = selectedQuestionID.flatMap { pending.contains($0) ? $0 : nil } ?? pending.first
        guard let questionID = wanted,
              let question = state.questions.first(where: { $0.id == questionID }) else {
            return .unavailable("今天安排的题目在题库里找不到了（换季重新导入时可能被删掉）。"
                + "下一步：到「学习计划」页重新生成计划，已经练过的进度不会丢。")
        }
        return .ready(setup(for: question, goal: "", defaults: defaults))
    }

    private static func resolveFreePick(_ state: CoachState, _ selectedQuestionID: String?,
                                        _ defaults: RouteDefaults) -> RouteResolution {
        guard !state.questions.isEmpty else {
            return .unavailable("题库还是空的。下一步：到「训练题库」页导入你的题库文件。")
        }
        guard let id = selectedQuestionID else {
            return .unavailable("还没选题。下一步：先在题目列表里点一道题，再点开始。")
        }
        guard let question = state.questions.first(where: { $0.id == id }) else {
            return .unavailable("题库里没有 id 为「\(id)」的题目。下一步：回题目列表重新选一道。")
        }
        return .ready(setup(for: question, goal: "", defaults: defaults))
    }

    private static func resolveContinueLast(_ state: CoachState,
                                            _ defaults: RouteDefaults) -> RouteResolution {
        // startedAt 是 ISO8601 字符串，同一格式下字典序即时间序。
        guard let last = state.sessions.max(by: { $0.startedAt < $1.startedAt }) else {
            return .unavailable("还没有练习记录，没有「上次」可以继续。"
                + "下一步：改用「按计划练今天」或「从题库自由选题」。")
        }
        guard let question = state.questions.first(where: { $0.id == last.questionId }) else {
            return .unavailable("上次练的那道题已经不在题库里了（换季重新导入时可能被删掉）。"
                + "下一步：改用「从题库自由选题」挑一道新的；那次练习的复盘仍然在「复盘报告」页里。")
        }
        // 上次的单点目标一并带上：「继续上次」的意思就是接着上次那件事再练一遍。
        return .ready(setup(for: question, goal: last.goal, defaults: defaults))
    }

    private static func resolveRetrain(_ state: CoachState,
                                       _ defaults: RouteDefaults) -> RouteResolution {
        // rank 已经排除了 status == "retired" 的目标，并把证据命中高频错题的排前面。
        guard let target = RetrainingPolicy.rank(targets: state.targets,
                                                 issues: state.issues).first else {
            return .unavailable("还没有待复训的目标。"
                + "下一步：先练一场并取回复盘，复盘会给出下一次的单点目标。")
        }
        // 空目标带进 ExaminerPrompt，「本次唯一目标」那一整段会被整块跳过，
        // 于是这场「复训」和普通练习一模一样——不报错、不崩溃，只是白练一场。
        // 静默地什么都没发生，是本项目已知最危险的失败形态（spec 2.3.8）。
        //
        // **跨阶段决策 6（2026-08-06）：不拒绝，回落成 targetKey 照常开练。**
        // 用户是来练英语的，因为一个内部字段是空的就不让他练，代价不成比例。
        // 直接复用 Phase 6 的那一份，**不要在这里再写一遍判断**——
        // 同一件事两份实现，迟早会出现「从复训中心进」和「从今日训练页进」不一样。
        let label = RetrainingSetupBuilder.goalText(for: target)
        guard let session = state.sessions.first(where: { $0.id == target.sourceSessionId }) else {
            return .unavailable("找不到这个目标是哪一次练习提出来的（那条训练记录可能被删过）。"
                + "下一步：改用「从题库自由选题」挑一道题，把目标手动写进去。")
        }
        guard let question = state.questions.first(where: { $0.id == session.questionId }) else {
            return .unavailable("这个目标对应的原题已经不在题库里了。"
                + "下一步：改用「从题库自由选题」挑一道同 Part 的题，把目标手动写进去再练一次。")
        }
        return .ready(setup(for: question, goal: label, defaults: defaults))
    }

    // MARK: - 可用路线

    /// 只返回**真的能开练**的路线，默认路线排在最前面。
    ///
    /// 「自由选题」是唯一的例外：它天生要先选题才能解析出题目，
    /// 所以它的条件就是「题库非空」。
    public static func availableRoutes(state: CoachState, preferring preferred: PracticeRoute,
                                       defaults: RouteDefaults = RouteDefaults()) -> [PracticeRoute] {
        var usable = PracticeRoute.allCases.filter { route in
            if route == .freePick { return !state.questions.isEmpty }
            if case .ready = resolve(route: route, state: state, defaults: defaults) { return true }
            return false
        }
        // 用户选的默认路线提到最前面，其余保持 PracticeRoute.allCases 的固定顺序。
        // 顺序固定很重要：每次打开卡片位置都在变，用户会点错。
        if let index = usable.firstIndex(of: preferred) {
            usable.remove(at: index)
            usable.insert(preferred, at: 0)
        }
        return usable
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRouteResolverTests`
Expected: PASS（27 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

做两次：

1. 把 `resolveRetrain` 里的 `let label = RetrainingSetupBuilder.goalText(for: target)`
   改成 `let label = target.label`（即取消回落）
   Expected: `testRetrainFallsBackToTheTargetKeySoTheGoalIsNeverBlank` **变红**
   *守的是决策 6：`goal` 是空串时复训会静默退化成普通练习，界面上一点异常都没有。*
2. 把 `availableRoutes` 里的过滤闭包整个换成 `{ _ in true }`
   Expected: `testEveryShownRouteCanActuallyStart`、`testShownRoutesNeverExceedPhase3Preconditions`、
   `testUnavailablePreferredRouteDoesNotSneakIn`、`testNoRoutesAtAllWhenThereIsNothingToPractice`
   **全部变红**

两次都改回后确认全绿。把四次输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Session/PracticeRouteResolver.swift Tests/IELTSCoachUITests/PracticeRouteResolverTests.swift
git commit -m "feat(ui): 四条练习路线统一解析成一场练习"
```

---

## Task 9: `AppState.mutate` 与学习计划页

**Files:**
- Modify: `Sources/IELTSCoachUI/AppState.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Sources/IELTSCoachUI/Plan/PlanView.swift`

**Interfaces:**
- Consumes: `StateStore.mutate(_:)`、`PlanViewModel`、`PlanDraft`、`PlanDraftPreviewBuilder.preview(state:draft:)`、`PlanRegenerator.regenerate(state:lengthDays:focusPart:createdAt:)`、`PlanRegenerator.apply(_:to:)`、`PlanScope.label(for:)`、`PlanBuilder.supportedLengths`、`CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView`、`Palette` / `Spacing` / `Radius`
- Produces:
  - `AppState.mutate(_ body: (inout CoachState) throws -> Void) -> String?`
  - `SidebarItem.isImplemented` 对 `.plan` 返回 `true`
  - `PlanView(app: AppState)`

**为什么 `AppState` 没有自动化测试：** 它的 `init` 会调 `recheckPermission()` → `AXDriver.preflight()`，而 `preflight()` 在 ChatGPT 没运行时**会真的去启动 ChatGPT**，并最多等 8 秒唤醒无障碍树（`Sources/ChatGPTBridge/AXDriver.swift` 第 33–43 行）。在单元测试里构造 `AppState` 等于每跑一次测试就弹一次 ChatGPT。因此本阶段所有可测逻辑都做成了不依赖 `AppState` 的纯函数（Task 3–8 共 70 条测试），`mutate` 本身只有几行，由 Task 11 人工验收。

- [ ] **Step 1: 给 `AppState` 加写入能力**

在 `Sources/IELTSCoachUI/AppState.swift` 的 `AppState` 里加：

```swift
    /// 改训练数据。成功返回 nil；失败返回中文说明（发生了什么 + 下一步）。
    ///
    /// **调用方必须把返回的消息显示出来。** 写盘失败却什么都不说，
    /// 用户会以为改动生效了，下次打开才发现全没了——那正是禁止静默失败要防的事。
    /// 刻意不加 @discardableResult：忽略返回值时编译器会警告。
    public func mutate(_ body: (inout CoachState) throws -> Void) -> String? {
        do {
            try store.mutate { try body(&$0) }
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
```

- [ ] **Step 2: 把「学习计划」标为已实现，并改一条既有测试**

`Sources/IELTSCoachUI/Navigation.swift` 里 `isImplemented` 的 `case` 加上 `.plan`：

```swift
    public var isImplemented: Bool {
        switch self {
        case .today, .questionBank, .reviewReports, .plan: return true
        default: return false
        }
    }
```

**若 Phase 4–7 已经往这个列表里加过页面，就在现有集合上追加 `.plan`，不要覆盖它们。**

`Tests/IELTSCoachUITests/NavigationTests.swift` 里那条断言「已实现页面的确切集合」的测试（Phase 3 里叫 `testPhase3ImplementsExactlyThreePages`）必须同步加上 `.plan`。**这条测试断言的是确切集合而不是「至少包含」，就是为了让「标了已实现但没接上视图」当场变红**——所以只能改期望值，不能把它改成 `isSuperset`。

Run: `swift test --filter NavigationTests`
Expected: 先红（集合对不上），改完期望值后 PASS

- [ ] **Step 3: 在 `RootView` 里接上这一页**

`Sources/IELTSCoachUI/RootView.swift` 的 `detail` switch 里加：

```swift
            case .plan: PlanView(app: app)
```

- [ ] **Step 4: 写 `PlanView`（只给验收要求，布局自定）**

**必须遵守 `DESIGN-SYSTEM.md`：全部走 `Palette` / `Spacing` / `Radius` 令牌，页面内边距 `Spacing.xl`，卡片内边距 `Spacing.lg`，统计数字用 `.monospacedDigit()`，图标只用 SF Symbols，整页只能有一个主行动。**

**A. 还没有计划时（`vm.hasPlan == false`）**

用 `EmptyStateView`，三样缺一不可：

- 说明现状：「你还没有学习计划。有计划之后，「今日训练」页会直接告诉你今天练哪几道题，不用每次自己想。」
- 说明下一步：指向本页下方的生成表单
- 一个能直接点的按钮

**B. 生成 / 调整表单（有没有计划都显示）**

- 周期选择：`PlanBuilder.supportedLengths`（7 / 14 / 30）三选一，分段控件
- 重点 Part 选择：`FocusPart.allCases` 四选一，每一项的文字用 `PlanScope.label(for:)`
- 已有计划时，两个选择器的初值取自 `vm.lengthDays` 与 `vm.focusPart`；没有计划时用 `PlanDraft()` 的默认值（7 天、全真模考）
- 每次选择变化都重新算 `PlanDraftPreviewBuilder.preview(state:draft:)`，并显示：
  - 能生成时：「Part 2（个人陈述）现在 18 题，分 7 天，每天 2–3 题」（题数与 `perDayText` 都来自 preview）
  - 不能生成时：显示 `preview.blockingReason` 全文，**且生成按钮禁用**。禁用的按钮旁边必须有这段文字，不能只是灰掉让人猜
- 生成按钮的文案：没有计划时是「生成计划」，已有计划时是「重新生成计划」

**C. 重新生成必须先确认（只在已有计划时）**

弹窗标题：`重新生成计划？`

弹窗正文逐字如下：

```
已经练过的题仍然算已完成，练习记录、复盘、错题本、词汇本都不受影响。
下一步：确认后会按你选的周期和重点 Part，重排今后的每日安排。
```

按钮：`重新生成` / `取消`。

**D. 生成的落盘动作**

```swift
let outcome = try PlanRegenerator.regenerate(
    state: app.state, lengthDays: draft.lengthDays, focusPart: draft.focusPart,
    createdAt: ISO8601DateFormatter().string(from: Date()))
if let failure = app.mutate({ PlanRegenerator.apply(outcome, to: &$0) }) {
    // 显示 failure（中文，已含「下一步」）
} else {
    // 显示 outcome.summary
}
```

`regenerate` 抛错时显示 `error.localizedDescription` 全文——它已经是中文且带「下一步」。
**两种失败都必须显示在界面上，不能只 print。**

**E. 计划概览（有计划时）**

- 「\(vm.lengthDays!) 天计划 · \(PlanScope.label(for: vm.focusPart!))」
- 进度：`vm.progress.done` / `vm.progress.total` 题，配一条进度条。**数字用等宽数字**，否则从 9 跳到 10 时整行会抖
- `vm.isFinished` 为真时显示「这份计划已经全部练完了。下一步：重新生成一份，或换个重点 Part 再来一轮。」
- 否则显示「今天是第 \(vm.todayNumber!) 天」，并**明确写一句**：「这里的「第几天」按练完的进度走，不按日历。中间停几天回来，它还在原地等你。」——不写这句，用户会以为自己落后了

**F. 每日拆分列表**

- 遍历 `vm.dayRows`，每天一个 `CoachCard`
- 每天显示「第 N 天」、当天题数、是否已完成
- `isToday` 的那一天要有明显的视觉标记（用 `Palette.accent`），并且**默认滚动到它**
- 每道题一行：Part 徽标、话题、题干、是否已完成
- `isMissing == true` 的行显示 `prompt` 里那段中文说明，用 `Palette.warning`，**不能显示成空行**

**G. 删除计划（有计划时，放在页面底部，视觉上明显次一级）**

弹窗标题：`删除计划？`

弹窗正文逐字如下：

```
删掉之后「今日训练」页的「按计划练今天」会消失，但练习记录、复盘和题目的已练标记都还在。
下一步：随时可以回到这一页重新生成一份计划。
```

按钮：`删除` / `取消`。动作是 `app.mutate { $0.plan = nil }`，失败时显示返回的消息。

**H. 练习偏好（本页底部一个独立区块）**

用 `SectionHeader`，三项设置，改动即时落盘：

| 设置 | 控件 | 取值 | 存到 |
|---|---|---|---|
| 默认练习路线 | 四选一 | `PracticeRoute.allCases`，文字用 `route.title` | `settings.defaultRoute = PracticeRoutePreference.rawValue(for:)` |
| 反馈时机 | 二选一 | 全程零反馈（`deferred`）/ 当场点出（`immediate`）| `settings.feedbackTiming` |
| Part 2 准备时间 | 二选一 | 一分钟倒计时（`countdown`）/ 自己决定（`learnerControlled`）| `settings.part2PrepMode` |

每项下面一行小字说明取舍，逐字如下（依据 spec 3.1）：

- 默认练习路线：「今日训练页会把这条路线排在最前面。」
- 反馈时机：「全程零反馈像真考试，但答砸的地方要等到最后才知道；当场点出纠正及时，代价是不再是真实考试节奏，单场时间也会拉长。」
- Part 2 准备时间：「一分钟倒计时像真考试，练的是压力下组织语言；自己决定适合刚起步时先把内容想清楚。」

落盘同样走 `app.mutate`，失败时显示返回的消息。

- [ ] **Step 5: 验证**

Run: `swift build`
Expected: 编译通过

Run: `swift test`
Expected: 全绿

Run: `./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"`
Expected: 侧边栏「学习计划」不再是占位页

- [ ] **Step 6: 突变验证**

本任务没有新增可自动验证的逻辑——计划页的全部判断都在 Task 3–6 的纯函数里，已各自经过突变验证。`AppState.mutate` 无法在单元测试里构造（见本任务开头的说明）。**因此本任务不做突变验证，验收由 Task 11 第 3 步人工完成。**

这不是省略，是把无法自动验证的部分明确交给人，并写清了为什么。

- [ ] **Step 7: 提交**

```bash
git add Sources/IELTSCoachUI/AppState.swift Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/RootView.swift Sources/IELTSCoachUI/Plan/PlanView.swift Tests/IELTSCoachUITests/NavigationTests.swift
git commit -m "feat(ui): 学习计划页"
```

---

## Task 10: 今日训练页接通三条路线

**Files:**
- Modify: `Sources/IELTSCoachUI/Today/TodayView.swift`

**Interfaces:**
- Consumes: `PracticeRouteResolver.availableRoutes(state:preferring:defaults:)`、`PracticeRouteResolver.resolve(route:state:selectedQuestionID:defaults:)`、`RouteResolution`、`PracticeRoutePreference.route(fromSettings:)`、`RouteDefaults(settings:)`、`TodayViewModel`（`todayQuestions`、`weekProgress`、`recentSessions`）、`PracticeRunner.start(setup:)`、`PracticeSheet`、`EmptyStateView` / `CoachCard` / `PrimaryActionCard` / `SectionHeader`
- Produces: 无新类型。本任务是接线

**这一条兑现 ROADMAP 对 Phase 8 的交付定义：四条练习路线全部可用。**

- [ ] **Step 1: 路线卡片改用解析器**

`TodayView` 里渲染路线的数据源，从 Phase 3 的 `TodayViewModel.availableRoutes` 改成：

```swift
let preferred = PracticeRoutePreference.route(fromSettings: app.state.settings.defaultRoute)
let defaults = RouteDefaults(settings: app.state.settings)
let routes = PracticeRouteResolver.availableRoutes(state: app.state,
                                                   preferring: preferred, defaults: defaults)
```

**为什么必须换：** Phase 3 的判断只看「前提成立」，而前提成立不等于能开练（上次那道题可能已被换季删掉、复训目标可能指向已删除的记录、复盘给的目标可能是空的）。换成解析器之后，**显示出来的每一条都保证点得动**——Task 8 有一条不变量测试守着这件事。

- [ ] **Step 2: 每张卡片的点击行为**

统一走这一条路径：

```swift
switch PracticeRouteResolver.resolve(route: route, state: app.state,
                                     selectedQuestionID: picked, defaults: defaults) {
case .ready(let setup):
    // 弹出 PracticeSheet 并 await runner.start(setup: setup)
case .unavailable(let message):
    // 就地把 message 显示在这张卡片下面
}
```

**`.unavailable` 的文案必须留在界面上**，不能用一闪而过的提示。那段文字本身就写着下一步该做什么，一闪就没了等于没说。

- [ ] **Step 3: 四条路线各自的卡片内容**

| 路线 | 卡片里必须显示 | 点击后 |
|---|---|---|
| 按计划练今天 | 今天是第几天、今天的题目列表（`vm.todayQuestions`，已练过的打勾） | 点整张卡片 → `selectedQuestionID = nil`（自动挑今天第一道没练的）；点某一道题 → 用那道题的 id |
| 从题库自由选题 | 题库总题数 | 打开选题弹层（Part 分段筛选 + 题目列表），选中后用它的 id 解析 |
| 继续上次练习 | 上次那道题的话题与题干、上次的时间；上次有单点目标时把目标也显示出来 | 直接解析并开练 |
| 复训一个旧问题 | **要复训的目标原文**（即 `setup.goal`）、它出自哪一次练习 | 直接解析并开练 |

**复训卡片必须显示目标原文。** 用户得在开练之前就知道自己这一场要盯着哪件事——不显示的话，这条路线和普通练习在他眼里没有区别。

- [ ] **Step 4: 排序、主行动与空状态**

- 卡片顺序就是 `availableRoutes` 的返回顺序（默认路线在最前）
- **只有第一张卡片用 `PrimaryActionCard`**，其余用 `CoachCard`。整页只能有一个主行动（`DESIGN-SYSTEM.md` 第 4 节）
- `routes.isEmpty` 时用 `EmptyStateView`：
  - 题库为空 →「题库还是空的，现在还没法开始练。下一步：到「训练题库」页导入你的题库文件。」+ 直接跳过去的按钮
  - 题库非空但一条路线都没有 →「暂时没有可以直接开始的路线。下一步：到「学习计划」页生成一份计划，或用「从题库自由选题」挑一道题。」+ 跳到学习计划页的按钮

- [ ] **Step 5: 如果 Phase 6 的复训中心已经交付**

**先确认再动手：**

Run: `ls Sources/IELTSCoachUI/Retraining/ 2>/dev/null; grep -rn "RetrainingCenterView" Sources/IELTSCoachUI/ || echo "复训中心尚未交付"`

- 输出「复训中心尚未交付」→ 本步骤跳过，复训卡片按 Step 2 直接开练
- 找到了复训中心页 → 把复训卡片的点击行为改成**先导航到复训中心**（Phase 6 的流程是「回看证据 → 重答原题 → 撤掉提示 → 换题验证」，比直接开练完整）

> ### ⚠️ Phase 6 已经有一份「目标 → SessionSetup」了（2026-08-06 跨阶段复审补入）
>
> 初稿这里写着「`PracticeRouteResolver` 是唯一实现，复训中心页也应当复用它」。
> **事实是 Phase 6 Task 8 已经先写了一份 `RetrainingSetupBuilder`**，
> 而且两份的行为并不完全一样：
>
> | | `PracticeRouteResolver`（本阶段） | `RetrainingSetupBuilder`（Phase 6） |
> |---|---|---|
> | part → FocusPart、Part 2 用 4 分钟 | 一样 | 一样 |
> | `feedbackTiming` / `part2PrepMode` | 从 `RouteDefaults(settings:)` 取，**跟随用户设置** | 参数默认值 `.deferred` / `.countdown`，**调用方不传就永远是默认** |
> | 目标 label 是空白时 | ~~返回 `.unavailable(…)`，明确拒绝~~ → **已按决策 6 改成直接调 Phase 6 的 `goalText(for:)`**（Task 8 Step 3）| 回落成 `targetKey`，照常开练 |
>
> 第二行是本阶段必须处理的：本任务刚刚让用户能在学习计划页选「当场点出」和「自己决定」，
> 而 `RetrainingCoordinator.start(...)` 调 `RetrainingSetupBuilder.makeSetup(target:question:)`
> 时一个都没传——**用户设了「当场点出」，一进复训又变回全程零反馈，而且没有任何提示。**
>
> **本阶段要做的（两处小改，不动 Phase 6 的判断逻辑）：**
>
> 1. 给 `RetrainingSetupBuilder.makeSetup` 加一个 `defaults: RouteDefaults = RouteDefaults()`
>    重载（或把现有的两个参数改成从 `RouteDefaults` 取），内部仍走原来的实现
> 2. `RetrainingCoordinator` 在构造 setup 时传 `RouteDefaults(settings: state.settings)`
>
> **第三行已在 2026-08-06 由跨阶段决策 6 定案：统一成 Phase 6 的做法（回落成 `targetKey` 照常开练）。**
> 落点是本阶段 **Task 8** 的 `resolveRetrain`，改动只有一行——直接调 `RetrainingSetupBuilder.goalText(for:)`。
> **别再写第二份判断**：同一件事两份实现，迟早会出现「从复训中心进」和「从今日训练页进」不一样。

- [ ] **Step 6: 验证**

Run: `swift build && swift test`
Expected: 编译通过，全绿

Run: `./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"`
Expected: 今日训练页的路线卡片按新规则显示

- [ ] **Step 7: 提交**

```bash
git add Sources/IELTSCoachUI/Today/TodayView.swift
git commit -m "feat(ui): 今日训练页接通四条练习路线"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase8-acceptance.md`

前面所有测试跑在纯函数上，证明的是「数据变换对」，不是「用起来对」。以下只能人来判断。

- [ ] **Step 1: 打包并打开**

```bash
cd ~/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

若又被要求重新授权辅助功能，**立刻停下并报告**——那说明签名稳定性回归了（Phase 3 完成标准的第 3、4 条）。

- [ ] **Step 2: 升级兼容性（本阶段最该先验的一条）**

**先备份，再验证：**

```bash
cp -R "$HOME/Library/Application Support/IELTS Speaking Coach" \
      "$HOME/Library/Application Support/IELTS Speaking Coach.phase8-backup"
```

然后打开 App，逐条确认：

| 看什么 | 判据 |
|---|---|
| 训练记录还在吗 | 复盘报告页、题库页的数字与升级前一致 |
| 有没有报「训练数据文件已损坏」 | 完全没有出现 |
| 已有的计划还在吗 | 学习计划页显示原来的天数，进度与升级前一致 |
| 原计划的重点 Part 显示成什么 | 应显示「全真模考」（旧数据没有这个字段，回落值） |

**任何一条不满足，立刻停下并报告。** Task 1、2 的向后兼容解码就是为这一步准备的，这里是它唯一的真机检验。

- [ ] **Step 3: 学习计划页逐项验收**

| 场景 | 看什么 |
|---|---|
| 没有计划时 | 空状态是否说清了「现状 + 下一步」，按钮能不能直接点 |
| 切换周期与重点 Part | 「现在 N 题，分 M 天，每天 X–Y 题」是否立刻跟着变，数字对不对 |
| 选一个题数不够的组合 | 生成按钮是否禁用，**旁边有没有写清为什么以及怎么办** |
| 生成计划 | 每日拆分的天数与题数对不对，「今天」那一天有没有被标出来并自动滚到 |
| 「第几天」的说明 | 那句「按练完的进度走，不按日历」有没有写出来 |
| 删除计划 | 确认弹窗的文字是否说清了「什么会消失、什么还在」 |
| 练习偏好 | 三项改完关掉 App 再打开，是否还是改后的值 |

- [ ] **Step 4: 重新生成不丢进度（本阶段的成败判据）**

按顺序做，每一步记下界面上的实际数字：

1. 生成一份 7 天计划（重点选 Part 1）
2. 真的练一场并让复盘归档成功 → 回到计划页，确认那道题变成已完成、进度从 0/N 变成 1/N
3. 把周期改成 14 天，点「重新生成计划」，确认弹窗文字，确认
4. **重新生成之后，那道题必须还是已完成，进度仍然是 1/N'**
5. 把重点 Part 改成「全真模考」，再重新生成一次，**那道题仍然必须是已完成**
6. 去复盘报告页与训练记录页，确认那次练习的记录、复盘、错题本、词汇本**一条都没少**

**第 4、5、6 步任何一条不满足，本阶段就没做完**——这正是成品标准第 7 条在本阶段的形态。

- [ ] **Step 5: 四条路线各走一遍（把终端关掉）**

| 路线 | 怎么验 |
|---|---|
| 按计划练今天 | 点开始能不能真的开练；练完后计划进度有没有前进一格 |
| 从题库自由选题 | 选题弹层能不能按 Part 筛选；选中后能不能开练 |
| 继续上次练习 | 卡片上显示的是不是上次那道题；上次有目标时目标有没有显示出来 |
| 复训一个旧问题 | **卡片上有没有显示要复训的目标原文**；开练后 ChatGPT 收到的提示词里有没有那段「本次唯一目标」 |

**最后一条要实际去 ChatGPT 窗口里翻一下发出去的提示词。** 目标没带进去而界面上什么都不说，正是本项目最危险的那种失败。

- [ ] **Step 6: 制造几种「路线不可用」的情况**

| 怎么造 | 应该看到什么 |
|---|---|
| 删掉计划 | 「按计划练今天」卡片消失，不是变灰也不是点了没反应 |
| 把计划里今天那道题从题库里删掉后重新导入一份不含它的题库 | 「按计划练今天」消失或给出「重新生成计划」的中文说明 |
| 全新的数据目录（`IELTS_SPEAKING_DATA_DIR` 指向一个空目录）| 只显示「从题库自由选题」之前的空状态，且空状态说清了下一步 |

**每一条都要能读懂**：找一个不懂技术的人试着照做（成品标准第 8 条的原话）。

- [ ] **Step 7: 界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节）**

逐条走那十条清单，其中三条最容易被忽略：

- 系统「减弱动态效果」打开后，计划页无动画且功能正常
- 系统文字调到最大时，每日拆分列表不截断、不重叠
- 进度数字（3/14 → 10/14）变化时不抖动（等宽数字）

- [ ] **Step 8: 记录并提交**

把每一项的实际结果写进 `docs/phase8-acceptance.md`，含截图或原文描述。**包括不好的部分**——「哪里让我不想用」这类信息只有使用者有（成品标准第 5 节）。

验证完成后删掉备份：

```bash
rm -rf "$HOME/Library/Application Support/IELTS Speaking Coach.phase8-backup"
git add docs/phase8-acceptance.md
git commit -m "docs: Phase 8 真机验收结果"
```

---

## Phase 8 完成标准

- [ ] `swift test` 全绿
- [ ] 升级后旧的 `state.json` 照常读得出来，训练记录一条不少（Task 11 Step 2 实测确认）
- [ ] 学习计划页可用：7/14/30 天周期、四种重点 Part、每日拆分、进度、生成、重新生成、删除
- [ ] 选到做不出来的组合时，生成按钮禁用**且旁边写清了为什么和怎么办**
- [ ] **重新生成计划后，已经练过的题仍然是已完成**（Task 11 Step 4 实测确认）
- [ ] **重新生成计划不影响练习记录、复盘、错题本、词汇本、重训目标**（`testApplyOnlyTouchesThePlan` + Task 11 Step 4 第 6 步）
- [ ] 四条练习路线全部能从今日训练页开练，且**显示出来的路线点下去一定能开练**
- [ ] 复训路线把复盘给的单点目标真的带进了考官提示词（Task 11 Step 5 实测确认）
- [ ] 路线不可用时，界面上留着一段说清「发生了什么 + 下一步」的中文
- [ ] 练习偏好（默认路线、反馈时机、Part 2 准备）能存下来，重开 App 仍在
- [ ] 每个关键任务都经突变验证确认测试有约束力（Task 1、2、3、4、5、6、7、8 共 13 次突变，输出全部写进报告）
- [ ] `DESIGN-SYSTEM.md` 第 6 节十条验收清单全部通过

达成后 ROADMAP 上只剩 Phase 9（MCP server + Codex 插件）与 Phase 10（打包与分发）。

---

## 附：本阶段一共写了多少条测试

| 文件 | 条数 | 主要防什么 |
|---|---|---|
| `TrainingPlanCodableTests` | 4 | 升级后旧 state.json 整份读不出来 |
| `CoachSettingsCompatibilityTests` | 5 | 同上，外加不认识的枚举取值炸掉全部数据 |
| `PlanScopeTests` | 10 | 全真模考不交错；生成出一份永远完不成的计划 |
| `PlanRegeneratorTests` | 13 | **重新生成丢进度**；顺手清空历史 |
| `PlanViewModelTests` | 8 | 「计划完成」永远不出现；缺题显示成空行；重复 id 闪退 |
| `PlanDraftPreviewTests` | 7 | 预览说能生成、点下去却报错 |
| `PracticeRoutePreferenceTests` | 5 | Core 与 UI 之间的字符串对不上 |
| `PracticeRouteResolverTests` | 27 | **显示了却开不了练**；复训的 goal 变成空串、白练一场（决策 6：回落成 `targetKey`，不拒绝）|
| 合计 | **79** | |

判据始终是同一条：**把被测逻辑改成空实现，测试会不会红。** 本项目已经消灭过 15 处不满足这条的空转测试，本阶段的 13 次突变验证就是为了不再制造新的。
