# Phase 9：MCP server + Codex 插件

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个 `ielts-speaking-mcp` 可执行文件，在 Codex 里配置好之后，能用 7 个 tool 完成「建工作区 → 选题 → 取考官提示词 → 存复盘 → 看历史 → 看仪表盘 → 唤起 App」一整圈，全程不碰终端里的 `coach` 命令。

**Architecture:** MCP over stdio（JSON-RPC 2.0，NDJSON 逐行分帧），**协议层用 Foundation 手写，不引入任何第三方依赖**。沿用 Phase 3 已经验证过的「逻辑放 library、可执行文件只做组装」的拆法：新增 library target `IELTSCoachMCP`（只依赖 Foundation + `IELTSCoachCore`，可在无图形界面的环境里完整单元测试）与瘦可执行 target `ielts-speaking-mcp`（只多依赖一个 AppKit，用来 `NSWorkspace.open` 唤起 App）。**7 个 tool 全部是对 Core 既有类型的薄封装**，凡是需要新逻辑的地方（路由、会话编号、仪表盘聚合、复盘落盘）一律加在 Core 里由两端共享，不在 MCP 层另写一份。

**Tech Stack:** Swift 6.3.3、SPM（swift-tools-version 6.0，即 Swift 6 语言模式）、Foundation、XCTest、AppKit（仅可执行文件）、`codesign`、TOML（Codex 配置）。无第三方依赖。

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit 的代码放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、`IELTSCoachAudio`（Phase 5 加的）、SwiftUI
- **本阶段新增的 `IELTSCoachMCP` 只允许依赖 Foundation + `IELTSCoachCore`**；`ielts-speaking-mcp` 可执行文件可以再加 AppKit
- **`ielts-speaking-mcp` 不依赖 `ChatGPTBridge`**（spec 4.4）。它一行都不碰 ChatGPT，因此本阶段所有自动化步骤都不可能在用户账号里产生真实对话
- 所有面向用户的文案必须中文，且同时说明「发生了什么」和「下一步做什么」。**tool 的 description、错误文案、返回负载里的 `note` 全部适用**
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`（与本阶段无关，但不得因为本阶段改动）
- 界面必须走设计令牌（`Palette` / `Spacing` / `Radius`），视图里不得出现字面颜色、字号、圆角
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- **不引入任何第三方依赖。** 本项目至今零第三方依赖，JSON-RPC 与 MCP 的协议层用 Foundation 自己实现
- `state.json` 的 schema **保持 `schemaVersion: 3` 不变**（spec 4.6）。本阶段不新增任何顶层键
- 测试用 XCTest

## 本阶段明确不做的事

写下来防止范围扩散，每条都有出处：

| 不做 | 出处 |
|---|---|
| 不做 HTTP / SSE 传输，不复活上游 `127.0.0.1:43127` 那个服务 | spec 4.4：「上游的 HTTP 服务整体删除」 |
| 不在 MCP 里调用 OpenAI API | DEFINITION-OF-DONE 第 4 节 |
| 不在 MCP 里驱动 ChatGPT（不依赖 `ChatGPTBridge`） | spec 4.4 |
| 不给 `state.json` 加新顶层键 | spec 4.6 |
| 不预测雅思分数 | DEFINITION-OF-DONE 第 4 节 |
| 不实现 MCP 的 resources / prompts / sampling 能力 | 7 个 tool 已覆盖全部需求；未实现的方法一律返回规范的 `-32601`，不假装支持 |
| 不做 MCP 的批量请求（JSON-RPC batch） | MCP 2025-06-18 已移除批量支持；收到数组明确报错，不静默丢弃 |

## 前置依赖：Phase 3 没有提供、必须在本阶段补的东西

**Phase 3 交付了 `.app` 与打包脚本，但没有实现 `ieltscoach://` 这件事的任何一半。** 两半都缺，缺一半就等于 `open_dashboard` 是死的：

| 缺什么 | 现状 | 本阶段在哪补 |
|---|---|---|
| Info.plist 里的 `CFBundleURLTypes` | `scripts/build-app.sh` 生成的 plist 里没有这一项，系统根本不知道谁该处理 `ieltscoach://` | Task 11 修改 `scripts/build-app.sh` |
| App 内的 URL 处理 | `RootView` 没有 `.onOpenURL`，收到链接也不会跳页 | Task 11 新增 `DeepLinkResolver` + 改 `RootView` |

**其余 12 个任务与 Phase 3 完全无关**（MCP 只依赖 Core）。因此若 Phase 3 尚未收尾，Task 1–10、12–13 可以照常推进，只有 Task 11 必须等 Phase 3 的 `SidebarItem`、`AppState`、`RootView`、设计令牌就位。

## 本阶段假定 Phase 3 已产出的东西

以下签名来自 `docs/superpowers/plans/2026-08-05-phase3-gui-shell.md`，Task 11 会用到：

- `SidebarItem: String, CaseIterable, Identifiable`，十项：`today` / `questionBank` / `plan` / `retraining` / `reviewReports` / `upgrade` / `feedback` / `history` / `issues` / `vocabulary`，各带 `title: String`、`systemImage: String`、`isImplemented: Bool`
- `@Observable final class AppState`，含 `state: CoachState`、`permission: PermissionState`、`loadError: String?`、`reload()`、`recheckPermission()`
- `RootView`：`NavigationSplitView` 骨架，内部有 `@State private var selection: SidebarItem = .today`
- 设计令牌 `Palette` / `Spacing` / `Radius` 与组件 `CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView`
- `scripts/build-app.sh`：组装 `.app` + 用固定自签名证书 `IELTS Coach Dev` 签名

## spec 4.4 到底钉死了什么（读之前先看这段，省得自己发明）

spec 第 4.4 节原文钉死了三件事，**一个字都不能改**：

1. **7 个 tool 的名字，逐字如下**（顺序也照抄 spec 的书写顺序）：
   `initialize_ielts_workspace`、`open_dashboard`、`set_training_selection`、`get_training_context`、`save_session_review`、`list_practice_history`、`get_dashboard_data`
2. **传输方式**：MCP over stdio，JSON-RPC 2.0
3. **`open_dashboard` 的实现方式**：`NSWorkspace.open(URL(string: "ieltscoach://dashboard"))`，**不是**起一个 HTTP 服务

spec **没有**钉死每个 tool 的参数 schema 与返回负载。本计划里的参数与返回结构是从 Core 既有类型推导出来的（见每个 Task 的 Interfaces 块），推导规则只有一条：**能用 Core 现成类型表达的就直接用，不为 MCP 单造一套模型**。

## 一条贯穿全局的设计判断：选题存在哪

`set_training_selection` 要把「下次练哪道题」存下来，而 `state.json` 的 schema 不许动（spec 4.6）。

**选定的题目写进已有的 `CoachState.currentSession`（类型 `PracticeSession`）**，它本来就是「当前这场练习」的意思：`questionId`、`focusPart`、`goal`、`startedAt` 四个字段刚好够用。

代价说清楚：`durationMinutes`、`feedbackTiming`、`part2PrepMode` 这三项 `PracticeSession` 里没有位置，**因此它们不持久化，改由 `get_training_context` 的可选参数提供**，默认值与 `coach practice` 完全一致（Part 2 用 4 分钟、其余 6 分钟；`deferred`；`countdown`）。这样做的好处是 App 与命令行读到的 `currentSession` 语义不变，坏处是「上次用的时长」不会被记住——可接受，因为时长本来就该每次由用户当场定。

## File Structure

```
Sources/
├── IELTSCoachCore/                      本阶段新增 6 个文件（两端共享的逻辑都放这里）
│   ├── CoachError.swift                 Modify：加 invalidSessionID
│   ├── JSON/JSONValue.swift             Modify：加 intValue / doubleValue / boolValue
│   ├── Model/CoachRoute.swift           新增：ieltscoach:// 的路由表（MCP 拼 URL、App 解析 URL）
│   ├── Model/SessionID.swift            新增：会话编号生成与文件名安全校验
│   ├── Policy/IssueRanking.swift        新增：错题按出现次数排序
│   ├── Stats/PracticeSessionOrder.swift 新增（Task 9 复审）：「一场练习算在什么时候 + 从新到旧怎么排」的唯一一份规则
│   ├── Stats/TrainingStats.swift        Modify：取时间改调 PracticeSessionOrder
│   ├── Stats/SessionTimeline.swift      Modify：取时间改调 PracticeSessionOrder
│   ├── Review/DashboardSummary.swift    新增：仪表盘聚合（get_dashboard_data 的全部逻辑）
│   └── Storage/PendingReviewStore.swift 新增：复盘原文落盘（先落盘再解析）
├── IELTSCoachMCP/                       新增 library：协议层 + 7 个 tool
│   ├── JSONRPC.swift                    JSONRPCID / JSONRPCResponse / 错误码
│   ├── MCPServer.swift                  handle(line:) -> String?  ← 协议层的全部逻辑
│   ├── MCPTool.swift                    MCPTool / ToolOutcome / ToolJSON
│   ├── ToolArguments.swift              参数读取与中文校验错误
│   ├── MCPEnvironment.swift             依赖注入容器 + DashboardOpening + DashboardOpenError
│   ├── ToolCatalog.swift                7 个 tool 的装配（名字与顺序在此定死）
│   └── Tools/
│       ├── InitializeWorkspaceTool.swift
│       ├── OpenDashboardTool.swift
│       ├── SetTrainingSelectionTool.swift
│       ├── GetTrainingContextTool.swift
│       ├── SaveSessionReviewTool.swift
│       ├── ListPracticeHistoryTool.swift
│       └── GetDashboardDataTool.swift
├── ielts-speaking-mcp/                  新增可执行：stdio 循环 + NSWorkspace 唤起
│   └── main.swift
└── IELTSCoachUI/
    ├── DeepLink.swift                   新增：URL → 侧边栏页面
    ├── Navigation.swift                 Modify：SidebarItem.init(route:)
    └── RootView.swift                   Modify：.onOpenURL + 无法识别时的横幅
codex/
└── ielts-speaking-mcp.toml              新增：Codex 配置片段（给人抄的）
scripts/
├── build-app.sh                         Modify：注册 CFBundleURLTypes
├── install-codex-plugin.sh              新增：编译、安装到 ~/.local/bin、打印/写入 Codex 配置
└── mcp-smoke.sh                         新增：对真实可执行文件的 stdio 冒烟测试
Tests/
├── IELTSCoachCoreTests/                 5 个新测试文件
│   ├── CoachRouteTests.swift
│   ├── SessionIDTests.swift
│   ├── DashboardSummaryTests.swift
│   ├── PracticeSessionOrderTests.swift  Task 9 复审新增
│   └── PendingReviewStoreTests.swift
├── IELTSCoachMCPTests/                  新增测试 target
│   ├── TestSupport.swift
│   ├── MCPServerProtocolTests.swift     ← 畸形 JSON / 未知方法 / 缺参数 全在这里
│   ├── ToolArgumentsTests.swift
│   ├── WorkspaceToolsTests.swift
│   ├── SelectionToolsTests.swift
│   ├── SaveSessionReviewToolTests.swift
│   ├── HistoryToolsTests.swift
│   └── ToolCatalogTests.swift
└── IELTSCoachUITests/
    └── DeepLinkTests.swift              新增
```

### 关于本计划里 View 的写法

沿用 Phase 3 的规矩：**视图模型与纯逻辑给完整代码，`View` 只给验收要求不给布局代码。** 理由见 Phase 3 计划第 79–86 行——布局是需要看着调的东西，照抄一份没人看过的 SwiftUI 布局，实现者大概率还要推翻重来。

本阶段只有 Task 11 碰 `View`，且只碰两处：`.onOpenURL` 的闭包（**这是粘合逻辑，给完整代码**）与一个提示横幅（**只给验收要求**）。

---

## Task 1: Core 共享基础——路由表、会话编号、JSONValue 数值取值

**Files:**
- Create: `Sources/IELTSCoachCore/Model/CoachRoute.swift`
- Create: `Sources/IELTSCoachCore/Model/SessionID.swift`
- Modify: `Sources/IELTSCoachCore/JSON/JSONValue.swift`
- Modify: `Sources/IELTSCoachCore/CoachError.swift`
- Create: `Tests/IELTSCoachCoreTests/CoachRouteTests.swift`
- Create: `Tests/IELTSCoachCoreTests/SessionIDTests.swift`
- Modify: `Tests/IELTSCoachCoreTests/JSONValueTests.swift`

**Interfaces:**
- Consumes: `PracticeSession`（字段 `id`、`startedAt`）、`CoachError`
- Produces:
  - `public enum CoachRoute: String, CaseIterable, Sendable`，九个 case：`dashboard`、`today`、`questions`、`plan`、`retraining`、`reviews`、`history`、`issues`、`vocabulary`
  - `CoachRoute.scheme: String`（值为 `"ieltscoach"`）
  - `CoachRoute.url: URL`
  - `CoachRoute.parse(_ url: URL) -> CoachRoute?`
  - `public enum SessionID`：`static func next(existing: [PracticeSession], now: Date, timeZone: TimeZone) -> String`、`static func validated(_ raw: String) throws -> String`
  - `JSONValue.intValue: Int?`、`JSONValue.doubleValue: Double?`、`JSONValue.boolValue: Bool?`
  - `CoachError.invalidSessionID(String)`

**为什么路由表放 Core：** MCP 进程用它拼 URL，App 进程用它解析 URL。两边各写一份的话，改了一边忘了另一边，链接就静默失效——而**链接打不开时 macOS 不会给任何提示**，用户只会觉得「点了没反应」。

**为什么会话编号要有安全校验：** `save_session_review` 的 `sessionId` 由客户端（模型）给，而这个字符串会直接拼进文件名。放行 `../../..` 等于让调用方往数据目录外面写文件。这不是假想威胁——模型拼错一个路径就会发生。

> ### ⚠️ 开工前先确认全工程的会话编号是同一种形状（2026-08-06 跨阶段复审补入）
>
> 现在有**两种**：
>
> - `Sources/coach/PracticeCommand.swift` 归档时用 `ISO8601DateFormatter().string(from: Date())`
>   → `2026-08-05T14:03:11Z`
> - `PracticeSession.id` 的文档注释与本任务的 `SessionID.next` 用 `YYYY-MM-DD-NNN`
>   → `2026-08-05-003`
>
> **下面这个 `validated(_:)` 的白名单里没有冒号，因此它会拒绝第一种。**
> 也就是说：如果 Phase 4 让界面按 ISO8601 写会话 id，那么用户在 App 里练出来的每一场，
> 在 Codex 里都无法用 `save_session_review` 补录——而错误文案还写着
> 「改用 `list_practice_history` 里列出的编号」，那些编号恰恰全都会被拒。**用户会被指着走进死胡同。**
>
> **动手前跑一次** `grep -rn "let sessionID" Sources/ | grep -i iso`：
>
> - 全工程已统一成 `YYYY-MM-DD-NNN`（Phase 4 应当采用 `SessionID.next`）→ 照本任务实现
> - 仍有 ISO8601 形状 → **两条路二选一，并在报告里写明选了哪条**：
>   (a) 把 `:` 与 `+` 加进白名单（它们不构成路径穿越，只是文件名里不好看）；
>   (b) 先统一 Phase 4 的写法。**不要沉默地保持现状。**
>
> ### ✅ 已由跨阶段决策 1 定案，且由 Phase 4 提前落地（2026-08-06 复审第二轮）
>
> **选的是 (a)**：新产生的编号一律 `YYYY-MM-DD-NNN`，但 `validated` 的白名单**含 `:` 与 `+`**——
> 用户现有的 `state.json` 里已经有 ISO8601 形状的 id，拒绝它等于让已有练习记录全部失效。
>
> **`Sources/IELTSCoachCore/Model/SessionID.swift` 与 `CoachError.invalidSessionID` 已由 Phase 4 Task 1 建好。**
> 先跑 `ls Sources/IELTSCoachCore/Model/SessionID.swift`：
>
> - 存在 → **不要新建、不要把冒号从白名单里删掉**，跑一次 `swift test --filter SessionIDTests` 确认全绿，直接进下一个任务
> - 不存在 → Phase 4 还没做，照本任务实现，**但白名单里必须加上 `:` 与 `+`**（下面 Step 3 的代码要相应改）

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/CoachRouteTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class CoachRouteTests: XCTestCase {
    func testEveryRouteProducesAValidIeltscoachURL() {
        // url 属性内部用 preconditionFailure 兜底非法拼装。这条测试的意义是：
        // 将来有人加了带空格或大写的 case，红的是测试，不是用户机器上的崩溃。
        for route in CoachRoute.allCases {
            XCTAssertEqual(route.url.scheme, "ieltscoach", "\(route) 的 scheme 不对")
            XCTAssertEqual(route.url.absoluteString, "ieltscoach://\(route.rawValue)")
        }
    }

    func testParseAcceptsHostForm() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://history"))
        XCTAssertEqual(CoachRoute.parse(url), .history)
    }

    func testParseIgnoresCaseAndTrailingSlash() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://Dashboard/"))
        XCTAssertEqual(CoachRoute.parse(url), .dashboard)
    }

    func testParseAcceptsSchemeColonForm() throws {
        // 有些客户端会拼成 ieltscoach:reviews（没有双斜杠），host 是 nil、路径才是页面名。
        let url = try XCTUnwrap(URL(string: "ieltscoach:reviews"))
        XCTAssertEqual(CoachRoute.parse(url), .reviews)
    }

    func testParseRejectsOtherSchemes() throws {
        // 不能只看 host —— https://history 也有 host "history"，认了就等于
        // 谁都能用一条网页链接把 App 支使到某一页去。
        let url = try XCTUnwrap(URL(string: "https://history"))
        XCTAssertNil(CoachRoute.parse(url))
    }

    func testParseRejectsUnknownPage() throws {
        let url = try XCTUnwrap(URL(string: "ieltscoach://nope"))
        XCTAssertNil(CoachRoute.parse(url))
    }

    func testRawValuesAreStableBecauseTheyAreThePublicURLContract() {
        // 这些字符串会出现在用户抄进 Codex 的链接里、也会出现在 tool 的参数枚举里。
        // 改了就是破坏兼容，必须让改动者先看到这条测试红掉。
        XCTAssertEqual(CoachRoute.allCases.map(\.rawValue),
                       ["dashboard", "today", "questions", "plan", "retraining",
                        "reviews", "history", "issues", "vocabulary"])
    }
}
```

`Tests/IELTSCoachCoreTests/SessionIDTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class SessionIDTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let noon = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!

    private func session(_ id: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: "",
                        endedAt: "", goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    func testFirstSessionOfTheDayIsNumberedOne() {
        XCTAssertEqual(SessionID.next(existing: [], now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testContinuesFromTheHighestNumberNotTheCount() {
        // 用「已有条数 + 1」会在有空缺时撞号：只剩 003 时会算出 002，
        // 而 002 可能只是被删掉的那条，历史记录会张冠李戴。
        let existing = [session("2026-08-06-003")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-004")
    }

    func testCountsOnlyTheSameDay() {
        let existing = [session("2026-08-05-009"), session("2026-08-06-001")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-002")
    }

    func testIgnoresSessionIDsInOtherFormats() {
        // 旧数据里的 sessionID 是 ISO8601 时间戳（coach practice 当初就是这么生成的），
        // 不能因为解析不出编号就崩，也不能让它影响今天的编号。
        let existing = [session("2026-08-06T10:00:00Z"), session("随便什么")]
        XCTAssertEqual(SessionID.next(existing: existing, now: noon, timeZone: utc), "2026-08-06-001")
    }

    func testValidatedAcceptsNormalIDs() throws {
        XCTAssertEqual(try SessionID.validated("2026-08-06-001"), "2026-08-06-001")
        XCTAssertEqual(try SessionID.validated("  sync-1785940167 "), "sync-1785940167")
    }

    func testValidatedRejectsAnythingThatCouldEscapeTheDataDirectory() {
        // 这个字符串会直接拼进 pending-reviews/<id>.txt 和 reports/<id>.json。
        for bad in ["../evil", "a/b", "..", ".", "", "   ", "a\u{0000}b", "~/secret"] {
            XCTAssertThrowsError(try SessionID.validated(bad), "「\(bad)」不该被放行") { error in
                XCTAssertTrue("\(error.localizedDescription)".contains("下一步"),
                              "错误信息必须告诉用户下一步做什么")
            }
        }
    }
}
```

在 `Tests/IELTSCoachCoreTests/JSONValueTests.swift` **末尾追加**（保持原有测试不动）：

```swift
extension JSONValueTests {
    func testIntValueOnlyAcceptsWholeNumbers() {
        XCTAssertEqual(JSONValue.number(20).intValue, 20)
        XCTAssertEqual(JSONValue.number(-3).intValue, -3)
        // 3.5 静默截断成 3 是最坏的处理方式：调用方以为自己传的是 3.5，
        // 拿到的行为却是 3，而且没有任何提示。
        XCTAssertNil(JSONValue.number(3.5).intValue)
        XCTAssertNil(JSONValue.string("20").intValue, "字符串不能被当成数字")
        XCTAssertNil(JSONValue.bool(true).intValue)
        XCTAssertNil(JSONValue.null.intValue)
    }

    func testDoubleAndBoolAccessors() {
        XCTAssertEqual(JSONValue.number(1.5).doubleValue, 1.5)
        XCTAssertNil(JSONValue.string("1.5").doubleValue)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertNil(JSONValue.number(0).boolValue, "0 不是 false，JSON 里这是两种类型")
    }
}
```

> `JSONValueTests` 是既有类型（`final class JSONValueTests: XCTestCase`）。`final class` 也可以写 extension 加方法，XCTest 照样能发现它们。若实现者觉得 extension 别扭，直接把这两个方法写进原类体内也可以，测试内容不能少。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter CoachRouteTests`
Expected: 编译失败 —— `CoachRoute` 未定义

Run: `swift test --filter SessionIDTests`
Expected: 编译失败 —— `SessionID` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Model/CoachRoute.swift`：

```swift
import Foundation

/// App 的深链接路由：`ieltscoach://<route>`。
///
/// **放在 Core 是因为两个进程都要用它**：MCP server 用它拼 URL（open_dashboard），
/// App 用它解析收到的 URL。各写一份的话，改了一边忘了另一边，链接就静默失效——
/// 而链接打不开时 macOS 不给任何提示，用户只会觉得「点了没反应」。
///
/// 十项导航里的「功能升级」「问题反馈」刻意没有路由：从外部唤起这两页没有意义，
/// 少两个 case 就少两处要维护的字符串。
public enum CoachRoute: String, CaseIterable, Sendable {
    case dashboard, today, questions, plan, retraining, reviews, history, issues, vocabulary

    public static let scheme = "ieltscoach"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        guard let url = components.url else {
            // rawValue 全是小写 ASCII 字母，走不到这里。真走到了说明有人加了
            // 带空格或非 ASCII 的 case——那种情况必须当场炸给开发者看，
            // 不能返回一个打不开的 URL 让用户去猜为什么没反应。
            preconditionFailure(
                "CoachRoute.\(rawValue) 拼不出合法 URL。下一步：把这个 case 的 rawValue 改成纯小写 ASCII 字母。")
        }
        return url
    }

    /// 解析一条深链接。scheme 不对、页面名不认识都返回 nil，由调用方给中文提示。
    public static func parse(_ url: URL) -> CoachRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        // 两种写法都要认：ieltscoach://reviews（host 形式）与 ieltscoach:reviews（路径形式）。
        let candidate = (url.host(percentEncoded: false) ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return CoachRoute(rawValue: candidate)
    }
}
```

`Sources/IELTSCoachCore/Model/SessionID.swift`：

```swift
import Foundation

public enum SessionID {
    /// 会话编号 `YYYY-MM-DD-NNN`，与 `PracticeSession.id` 的文档格式一致。
    ///
    /// 取当天已有编号的**最大值 +1**，不是「条数 +1」：有空缺时后者会撞号，
    /// 而撞号意味着两次练习的复盘写到同一个 `reports/<id>.json` 上，后一次直接盖掉前一次。
    public static func next(existing: [PracticeSession], now: Date, timeZone: TimeZone) -> String {
        var formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")   // 不跟随用户的日历（否则可能出佛历年份）
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)

        let highest = existing.reduce(0) { current, session in
            guard session.id.hasPrefix("\(today)-") else { return current }
            let suffix = session.id.dropFirst(today.count + 1)
            guard let number = Int(suffix) else { return current }   // 旧格式（ISO8601 时间戳）忽略掉
            return max(current, number)
        }
        return String(format: "%@-%03d", today, highest + 1)
    }

    /// 会话编号会直接拼进 `pending-reviews/<id>.txt` 与 `reports/<id>.json`。
    /// 放行 `/`、`..`、控制字符，等于让调用方往数据目录外面写文件——
    /// 而 sessionId 是客户端（模型）给的字符串，拼错一次就会发生。
    public static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard !trimmed.isEmpty,
              trimmed != ".", trimmed != "..",
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CoachError.invalidSessionID(
                "会话编号「\(raw)」不合法：只能用字母、数字、连字符、下划线和点，且不能是 . 或 .. 。"
                + "下一步：省略 sessionId 让工具自动生成，或改用 list_practice_history 里列出的编号。")
        }
        return trimmed
    }
}
```

在 `Sources/IELTSCoachCore/JSON/JSONValue.swift` 的 `extension JSONValue` 里追加（放在 `stringValue` 之后）：

```swift
    public var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    /// 只接受整数。3.5 不会被截断成 3——静默截断意味着调用方传了 3.5、
    /// 拿到的却是 3 的行为，而且没有任何提示。
    public var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        guard value.rounded() == value,
              value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
```

`Sources/IELTSCoachCore/CoachError.swift` 改两处（加一个 case，并把它接进 `errorDescription`）：

```swift
public enum CoachError: Error, Equatable, LocalizedError {
    case invalidReviewText(String)
    case reviewNotFound(String)
    case reviewIncomplete(String)
    case stateUnreadable(String)
    case questionBankInvalid(String)
    case planImpossible(String)
    case invalidSessionID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReviewText(let m), .reviewNotFound(let m), .reviewIncomplete(let m),
             .stateUnreadable(let m), .questionBankInvalid(let m), .planImpossible(let m),
             .invalidSessionID(let m):
            return m
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter CoachRouteTests`
Expected: PASS（7 个测试）

Run: `swift test --filter SessionIDTests`
Expected: PASS（6 个测试）

Run: `swift test --filter JSONValueTests`
Expected: PASS（原有测试 + 新增 2 个）

- [ ] **Step 5: 突变验证**

三处，逐个做，每次只改一处，验完立刻改回：

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `SessionID.next` 里的 `max(current, number)` 改成 `current + 1` | `testContinuesFromTheHighestNumberNotTheCount` |
| `SessionID.validated` 里的 `trimmed.unicodeScalars.allSatisfy(...)` 整个条件删掉 | `testValidatedRejectsAnythingThatCouldEscapeTheDataDirectory` |
| `JSONValue.intValue` 里的 `value.rounded() == value` 删掉 | `testIntValueOnlyAcceptsWholeNumbers` |

三次的输出都写进报告，改回后确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/CoachRoute.swift Sources/IELTSCoachCore/Model/SessionID.swift Sources/IELTSCoachCore/JSON/JSONValue.swift Sources/IELTSCoachCore/CoachError.swift Tests/IELTSCoachCoreTests/CoachRouteTests.swift Tests/IELTSCoachCoreTests/SessionIDTests.swift Tests/IELTSCoachCoreTests/JSONValueTests.swift
git commit -m "feat(core): 深链接路由、会话编号与 JSONValue 数值取值"
```

---

## Task 2: Core 仪表盘聚合

**Files:**
- Create: `Sources/IELTSCoachCore/Policy/IssueRanking.swift`
- Create: `Sources/IELTSCoachCore/Review/DashboardSummary.swift`
- Create: `Tests/IELTSCoachCoreTests/DashboardSummaryTests.swift`

**Interfaces:**
- Consumes: `CoachState`、`Question`、`PracticeSession`、`IssueRecord`、`RetrainingTarget`、`TrainingPlan`、`PlanDay`、`RetrainingPolicy.rank(targets:issues:)`
- Produces:
  - `public struct PlanProgress: Equatable, Sendable`，字段 `lengthDays: Int`、`completedDays: Int`、`currentDay: Int?`、`todayQuestionIds: [String]`
  - `public struct DashboardSummary: Equatable, Sendable`，字段 `questionTotal`、`questionPracticed`、`sessionTotal`、`weekDone`、`weekGoal`、`undatedSessionCount`、`issueTotal`、`vocabularyTotal`（均 `Int`）、`topIssues: [IssueRecord]`、`nextTargets: [RetrainingTarget]`、`plan: PlanProgress?`，以及计算属性 `warnings: [String]`（2026-08-07 复审补入，见下）
  - `DashboardSummary.build(state: CoachState, now: Date, weeklyGoal: Int? = nil, topIssueLimit: Int = 5, targetLimit: Int = 3) -> DashboardSummary` —— `weeklyGoal` 传 nil 时取 `state.settings.weeklyGoal`（Phase 7 Task 1 加的字段）
  - `public enum IssueRanking`：`static func top(_ issues: [IssueRecord], limit: Int) -> [IssueRecord]`

**为什么这段逻辑放 Core 而不是 MCP：** 「不要在 MCP 层重新实现业务逻辑」是本阶段的硬要求。`get_dashboard_data` 需要的聚合（本周练了几次、计划走到第几天、哪些错题最频繁）是**产品逻辑**，Phase 7 的首页统计要用同一套。放 Core，MCP 只做「调一次 + 编码成 JSON」。

**~~已知的重叠：~~（2026-08-07 复审更正，原文已过时，勿照做）** 原文写的是：「Phase 3 的 `TodayViewModel.weekProgress` 里有一份相同的『本周训练次数』算法，本阶段不动它，留给 Phase 7 收口」。**写计划时的这个前提在动手时已经不成立**——Phase 7 已经交付，算法早就收进了 Core 的 `TrainingStats.compute`（`Sources/IELTSCoachCore/Stats/TrainingStats.swift`），`TodayViewModel.weekProgress` 现在只剩一行 `(stats.weeklyDone, stats.weeklyGoal)` 的转发。所以「重叠」不在 UI 与 Core 之间，而会发生在 **Core 内部的两个函数之间**，且两者语义不同：`TrainingStats` 在 `startedAt` 缺失时会退回 `CoachTime.parseDayPrefix(session.id)`（`SessionTimeline` 同样如此），只认 `startedAt` 的写法会把 Phase 4 之前的记录整条漏掉。

**因此本任务的做法是：`DashboardSummary.build` 不自己算本周次数，直接 `TrainingStats.compute(state:now:)` 取 `weeklyDone` 与 `undatedSessionCount`。** Core 里「本周训练次数」只许有一份实现；要改口径就改 `TrainingStats.compute` 那一处。第一版实现照抄了上面这段过时说明、自己写了一份只认 `startedAt` 的 `weekDone`，结果是同一份 state.json，App 首页显示「本周 1/5」、Codex 里 `get_dashboard_data` 回 0/5，两边都不报错（复审记录：`XCTAssertEqual failed: ("0") is not equal to ("1")`）。

**同时补一个诊断字段 `undatedSessionCount` 与 `warnings`：** 首页四格靠 `TrainingStats.undatedSessionCount` 说出「另有 N 场练习读不出时间，没能算进本周」（`TodayViewModel.weekTile`）。MCP 这边如果只吐一个算少了的数字而不给任何提示，就是铁律 7 的静默失败。`warnings` 里的每条都要同时说清「发生了什么」和「下一步做什么」（铁律 6）。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import IELTSCoachCore

final class DashboardSummaryTests: XCTestCase {
    private let formatter = ISO8601DateFormatter()

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func session(_ id: String, startedAt: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, said: String, occurrences: Int) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: said, correction: "c", whyItMatters: "w",
                    occurrences: occurrences, sourceSessionIds: ["s"], lastSeenAt: "t")
    }

    private func target(_ key: String, status: String, evidence: [String] = []) -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "L-\(key)", status: status, evidence: evidence,
                         sourceSessionId: "s-\(key)", createdAt: "t")
    }

    private func question(_ id: String, status: String = "new") -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "P-\(id)", status: status)
    }

    func testEmptyStateProducesAllZerosAndNoPlan() {
        let summary = DashboardSummary.build(state: .empty(), now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.questionTotal, 0)
        XCTAssertEqual(summary.sessionTotal, 0)
        XCTAssertEqual(summary.weekDone, 0)
        XCTAssertEqual(summary.weekGoal, 5)
        XCTAssertNil(summary.plan)
        XCTAssertTrue(summary.topIssues.isEmpty)
    }

    /// 2026-08-06 跨阶段复审补入：每周目标是用户设置里的东西（Phase 7 Task 1）。
    /// 写死 5 的话，App 首页显示 3、Codex 里问出来是 5，两处数字对不上而且没人查得到。
    func testWeekGoalFollowsTheUsersSetting() {
        var state = CoachState.empty()
        state.settings.weeklyGoal = 3
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekGoal, 3)
    }

    func testCountsPracticedQuestions() {
        var state = CoachState.empty()
        state.questions = [question("a", status: "practiced"), question("b"), question("c", status: "practiced")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.questionTotal, 3)
        XCTAssertEqual(summary.questionPracticed, 2)
    }

    func testWeekProgressCountsOnlyThisWeek() {
        // 取的日期离周界都超过 14 小时，任何时区下都不会漂到隔壁周去，
        // 免得这条测试在别的机器上莫名其妙地红。2026-08-03 是周一。
        var state = CoachState.empty()
        state.sessions = [
            session("in-1", startedAt: "2026-08-05T12:00:00Z"),
            session("in-2", startedAt: "2026-08-04T12:00:00Z"),
            session("out", startedAt: "2026-07-20T12:00:00Z")
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 2)
        XCTAssertEqual(summary.sessionTotal, 3)
    }

    func testUnparsableStartedAtDoesNotCountAndDoesNotCrash() {
        var state = CoachState.empty()
        state.sessions = [session("weird", startedAt: "上周三下午")]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.weekDone, 0)
        XCTAssertEqual(summary.sessionTotal, 1)
    }

    func testPlanProgressPointsAtTheFirstIncompleteDay() throws {
        var state = CoachState.empty()
        let questions = (1...14).map { question("q\($0)") }
        state.questions = questions
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for id in plan.days[0].questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) }
        state.plan = plan

        let progress = try XCTUnwrap(DashboardSummary.build(state: state,
                                                            now: date("2026-08-05T12:00:00Z")).plan)
        XCTAssertEqual(progress.lengthDays, 7)
        XCTAssertEqual(progress.completedDays, 1)
        XCTAssertEqual(progress.currentDay, 2)
        XCTAssertEqual(progress.todayQuestionIds, plan.days[1].questionIds)
    }

    func testFinishedPlanHasNoCurrentDay() throws {
        var state = CoachState.empty()
        let questions = (1...7).map { question("q\($0)") }
        state.questions = questions
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for day in plan.days { for id in day.questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) } }
        state.plan = plan

        let progress = try XCTUnwrap(DashboardSummary.build(state: state,
                                                            now: date("2026-08-05T12:00:00Z")).plan)
        XCTAssertNil(progress.currentDay)
        XCTAssertTrue(progress.todayQuestionIds.isEmpty)
    }

    func testTopIssuesAreOrderedByOccurrencesAndTruncated() {
        var state = CoachState.empty()
        state.issues = [
            issue("i1", said: "a", occurrences: 1),
            issue("i2", said: "b", occurrences: 9),
            issue("i3", said: "c", occurrences: 5)
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"),
                                             topIssueLimit: 2)
        XCTAssertEqual(summary.topIssues.map(\.id), ["i2", "i3"])
        XCTAssertEqual(summary.issueTotal, 3, "截断的是展示条数，总数必须是全量")
    }

    /// 回归护栏，**没有对应的突变**：Swift 的 `sorted` 在小数组上恰好是稳定的，
    /// 把 offset 兜底去掉这条也可能不变红。留着它是为了将来换排序实现时兜住，
    /// 别把它当成「这段逻辑被测住了」的证据。
    func testEqualOccurrencesKeepTheirOriginalOrder() {
        var state = CoachState.empty()
        state.issues = [issue("i1", said: "a", occurrences: 3),
                        issue("i2", said: "b", occurrences: 3),
                        issue("i3", said: "c", occurrences: 3)]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.topIssues.map(\.id), ["i1", "i2", "i3"])
    }

    func testRetiredTargetsAreExcludedAndTheRestAreRanked() {
        var state = CoachState.empty()
        state.issues = [issue("i1", said: "I very like it.", occurrences: 4)]
        state.targets = [
            target("cold", status: "new"),
            target("retired-one", status: "retired", evidence: ["I very like it."]),
            target("hot", status: "new", evidence: ["I very like it."])
        ]
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"))
        XCTAssertEqual(summary.nextTargets.map(\.targetKey), ["hot", "cold"],
                       "证据命中高频错题的目标要排前面，已退休的一个都不能出现")
    }

    func testTargetLimitIsRespected() {
        var state = CoachState.empty()
        state.targets = (1...5).map { target("t\($0)", status: "new") }
        let summary = DashboardSummary.build(state: state, now: date("2026-08-05T12:00:00Z"),
                                             targetLimit: 2)
        XCTAssertEqual(summary.nextTargets.count, 2)
    }
}
```

**2026-08-07 复审补入的四条测试**（正文见 `Tests/IELTSCoachCoreTests/DashboardSummaryTests.swift` 的「本周次数必须与首页四格是同一个数」一节）：

| 测试 | 守的是什么 |
|---|---|
| `testWeekDoneFallsBackToTheDateInTheSessionIDLikeTheHomeScreenDoes` | `startedAt` 为空、时间只剩在 id 里的记录必须算进本周 |
| `testWeekDoneAgreesWithTheHomeScreenStatOnTheSameState` | 同一份 state 下 `summary.weekDone == TrainingStats.weeklyDone`，谁改一处漏一处就红 |
| `testUndatedSessionsAreCountedAndExplainedInsteadOfSilentlyDropped` | 算不进去的场次必须有计数、且 `warnings` 里带「下一步」 |
| `testNoWarningWhenEverySessionHasATime` | 没问题时不许报警（否则警告失去意义） |

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DashboardSummaryTests`
Expected: 编译失败 —— `DashboardSummary` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Policy/IssueRanking.swift`：

```swift
import Foundation

public enum IssueRanking {
    /// 按出现次数从多到少取前 limit 条。次数相同的保持原有顺序——
    /// Swift 的 `sorted` 不保证稳定，不用下标兜住的话，同次数的条目每次
    /// 运行顺序都可能不一样，界面上看就是「列表自己在跳」。
    public static func top(_ issues: [IssueRecord], limit: Int) -> [IssueRecord] {
        guard limit > 0 else { return [] }
        return issues.enumerated()
            .sorted {
                $0.element.occurrences == $1.element.occurrences
                    ? $0.offset < $1.offset
                    : $0.element.occurrences > $1.element.occurrences
            }
            .prefix(limit)
            .map(\.element)
    }
}
```

`Sources/IELTSCoachCore/Review/DashboardSummary.swift`：

```swift
import Foundation

public struct PlanProgress: Equatable, Sendable {
    public let lengthDays: Int
    public let completedDays: Int
    /// 第一个还没做完的那天（从 1 开始）。全部做完时为 nil。
    public let currentDay: Int?
    public let todayQuestionIds: [String]

    public init(lengthDays: Int, completedDays: Int, currentDay: Int?, todayQuestionIds: [String]) {
        self.lengthDays = lengthDays; self.completedDays = completedDays
        self.currentDay = currentDay; self.todayQuestionIds = todayQuestionIds
    }
}

/// 首页与 MCP 的 get_dashboard_data 共用的聚合结果。纯函数：吃进 state，吐出数字，不做 IO。
public struct DashboardSummary: Equatable, Sendable {
    public let questionTotal: Int
    public let questionPracticed: Int
    public let sessionTotal: Int
    public let weekDone: Int
    public let weekGoal: Int
    /// 诊断字段：startedAt 与 id 都读不出时间、因此进不了任何一周的场次。
    /// 非 0 时调用方必须把 `warnings` 说给用户听（铁律 7）。
    public let undatedSessionCount: Int
    public let issueTotal: Int
    public let vocabularyTotal: Int
    public let topIssues: [IssueRecord]
    public let nextTargets: [RetrainingTarget]
    public let plan: PlanProgress?

    public init(questionTotal: Int, questionPracticed: Int, sessionTotal: Int, weekDone: Int,
                weekGoal: Int, undatedSessionCount: Int, issueTotal: Int, vocabularyTotal: Int,
                topIssues: [IssueRecord], nextTargets: [RetrainingTarget], plan: PlanProgress?) {
        self.questionTotal = questionTotal; self.questionPracticed = questionPracticed
        self.sessionTotal = sessionTotal; self.weekDone = weekDone; self.weekGoal = weekGoal
        self.undatedSessionCount = undatedSessionCount
        self.issueTotal = issueTotal; self.vocabularyTotal = vocabularyTotal
        self.topIssues = topIssues; self.nextTargets = nextTargets; self.plan = plan
    }

    /// 「这些数字为什么可能偏小」的中文说明。界面与 MCP 都必须原样显示出来。
    /// 完整文案见 Sources/IELTSCoachCore/Review/DashboardSummary.swift。
    public var warnings: [String] {
        guard undatedSessionCount > 0 else { return [] }
        return ["有 \(undatedSessionCount) 场练习读不出练习时间……下一步：……"]
    }

    /// - Parameter weeklyGoal: 传 nil 就用用户在设置里定的那个数
    ///   （`CoachSettings.weeklyGoal`，Phase 7 Task 1 加的）。
    ///   **不要写死 5。** 写死的话，用户把每周目标改成 3，App 首页显示 3、
    ///   Codex 里问 `get_dashboard_data` 却回 5，两处数字对不上，而且没人会想到去查这里。
    public static func build(state: CoachState, now: Date, weeklyGoal: Int? = nil,
                             topIssueLimit: Int = 5, targetLimit: Int = 3) -> DashboardSummary {
        let goal = weeklyGoal ?? state.settings.weeklyGoal
        // 「本周练了几次」不在这里重算，直接取首页四格用的那一份。
        // 自己再写一遍就会与 TrainingStats 的口径分叉（它在 startedAt 缺失时会退回
        // 从 session id 的日期前缀取时间），同一份 state.json 首页与 Codex 两个数。
        // 解析不出时间的场次不计入本周，但仍计入 sessionTotal，并从
        // stats.undatedSessionCount 带出来报给用户——算少了必须出声（铁律 7）。
        let stats = TrainingStats.compute(state: state, now: now)

        let planProgress = state.plan.map { plan -> PlanProgress in
            let firstIncomplete = plan.days.first { !$0.isComplete && !$0.questionIds.isEmpty }
            return PlanProgress(lengthDays: plan.lengthDays,
                                completedDays: plan.days.filter(\.isComplete).count,
                                currentDay: firstIncomplete?.id,
                                todayQuestionIds: firstIncomplete?.questionIds ?? [])
        }

        return DashboardSummary(
            questionTotal: state.questions.count,
            questionPracticed: state.questions.filter { $0.status == "practiced" }.count,
            sessionTotal: state.sessions.count,
            weekDone: stats.weeklyDone,
            weekGoal: goal,
            undatedSessionCount: stats.undatedSessionCount,
            issueTotal: state.issues.count,
            vocabularyTotal: state.vocabulary.count,
            topIssues: IssueRanking.top(state.issues, limit: topIssueLimit),
            nextTargets: Array(RetrainingPolicy.rank(targets: state.targets, issues: state.issues)
                .prefix(targetLimit)),
            plan: planProgress)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DashboardSummaryTests`
Expected: PASS（11 个测试）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `firstIncomplete` 的条件里去掉 `!$0.isComplete`（永远取第一天） | `testPlanProgressPointsAtTheFirstIncompleteDay` |
| `IssueRanking.top` 里的 `occurrences > ` 改成 `occurrences < ` | `testTopIssuesAreOrderedByOccurrencesAndTruncated` |
| `TrainingStats.compute` 里的 `week.contains(started)` 恒为真（本周次数现在从那里来） | `testWeekProgressCountsOnlyThisWeek` |
| `TrainingStats.compute` 里去掉 `?? CoachTime.parseDayPrefix(session.id)` 兜底 | `testWeekDoneFallsBackToTheDateInTheSessionIDLikeTheHomeScreenDoes` |
| `undatedSessionCount: stats.undatedSessionCount` 改成 `0` | `testUndatedSessionsAreCountedAndExplainedInsteadOfSilentlyDropped` |
| `warnings` 恒返回 `[]` / 去掉文案里的「下一步」 | 同上 |

改回后确认全绿，每次输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Policy/IssueRanking.swift Sources/IELTSCoachCore/Review/DashboardSummary.swift Tests/IELTSCoachCoreTests/DashboardSummaryTests.swift
git commit -m "feat(core): 仪表盘聚合与错题排序"
```

---

## Task 3: Core 复盘原文落盘

**Files:**
- Create: `Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`
- Create: `Tests/IELTSCoachCoreTests/PendingReviewStoreTests.swift`

**Interfaces:**
- Consumes: `DataDirectory`（`pendingReviewsDirectory`、`createIfNeeded()`）、`SessionID.validated(_:)`、`CoachError`
- Produces: `PendingReviewStore.write(rawText: String, sessionID: String, directory: DataDirectory) throws -> URL`

**为什么单独一个任务：** 这是成品标准第 7 条（「任何一步失败，已产生的内容都还在」）在本阶段的落点。用户练了半小时换来的复盘，不能因为解析出错就没了。`coach practice` 里已经有一份「先落盘再解析」的内联实现，本阶段把它做成可复用、有测试的东西，`save_session_review` 直接用。

**不改 `PracticeCommand`。** 它现在跑得好好的，改它会把 Phase 2 的验收拖进来。留一句注释指过来即可。
（**2026-08-06 复审补记：** Phase 4 Task 12 会为了会话编号与会话落库改 `PracticeCommand`。本任务仍然不用管它。）

> ### ✅ 这个文件已由 Phase 4 Task 7 提前建好（2026-08-06 复审第二轮）
>
> 决策 2 要求「复盘取回失败后的补救做进界面」，Phase 4 因此提前建了 `PendingReviewStore`，
> **`write` 与本任务这份逐字一致**，另外多了清点用的 `list` / `read` / `markImported` / `delete`
> 与常量 `importedSuffix`。
>
> 先跑 `ls Sources/IELTSCoachCore/Storage/PendingReviewStore.swift`：
>
> - 存在 → 跑一次 `swift test --filter PendingReviewStoreTests` 确认全绿，**直接进下一个任务**，
>   本任务不产生任何改动（在报告里写明「Phase 4 已交付，本任务只做验证」）
> - 不存在 → 照本任务实现

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import IELTSCoachCore

final class PendingReviewStoreTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-pending-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    func testWritesTheRawTextAndCreatesTheDirectoryOnItsOwn() throws {
        // 刻意没有先 createIfNeeded：落盘这一步发生在最危险的时刻，
        // 不能因为目录还不存在就把用户的复盘丢了。
        let url = try PendingReviewStore.write(rawText: "复盘原文", sessionID: "2026-08-06-001",
                                               directory: directory)
        XCTAssertEqual(url.lastPathComponent, "2026-08-06-001.txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "复盘原文")
    }

    func testWritingTheSameTextTwiceReusesTheSameFile() throws {
        let first = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1", directory: directory)
        let second = try PendingReviewStore.write(rawText: "同样的内容", sessionID: "s1", directory: directory)
        XCTAssertEqual(first, second, "重试一次不该多出一个一模一样的文件")
        let files = try FileManager.default.contentsOfDirectory(
            atPath: directory.pendingReviewsDirectory.path)
        XCTAssertEqual(files.count, 1)
    }

    func testDifferentTextNeverOverwritesWhatIsAlreadyThere() throws {
        let first = try PendingReviewStore.write(rawText: "第一次的复盘", sessionID: "s1", directory: directory)
        let second = try PendingReviewStore.write(rawText: "第二次的复盘", sessionID: "s1", directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "s1-2.txt")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "第一次的复盘",
                       "先落盘的那份一个字都不能被覆盖")
    }

    func testRejectsSessionIDsThatEscapeTheDataDirectory() {
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "x", sessionID: "../escaped",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
        // 目录外面不能凭空多出文件
        let escaped = directory.root.deletingLastPathComponent().appending(path: "escaped.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testGivesUpWithAnActionableErrorInsteadOfLoopingForever() throws {
        // 同一个 sessionID 塞满 100 个不同内容之后必须报错退出，不能无限试下去
        //（禁止无限等待）。这条同时保证了上面那个循环有出口。
        for index in 0..<100 {
            _ = try PendingReviewStore.write(rawText: "内容 \(index)", sessionID: "s1", directory: directory)
        }
        XCTAssertThrowsError(try PendingReviewStore.write(rawText: "第 101 份", sessionID: "s1",
                                                          directory: directory)) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("下一步"))
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PendingReviewStoreTests`
Expected: 编译失败 —— `PendingReviewStore` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 把复盘原文落到 `pending-reviews/`。
///
/// **必须在解析之前调用。** spec 第 5 节：「复盘先落盘再入库，中途崩溃或误关窗口
/// 都不丢数据」。反过来写的话，解析一抛错，用户练了一整场换来的原文就没了，
/// 只能从头再练一次。`coach practice` 里也是这个顺序（见 PracticeCommand 的注释）。
public enum PendingReviewStore {
    /// 同名文件已存在时的行为：
    /// - 内容完全相同 → 直接复用，重试不会堆出一堆一样的文件
    /// - 内容不同 → 改用 `<id>-2.txt`、`<id>-3.txt`…，**绝不覆盖已经落盘的内容**
    @discardableResult
    public static func write(rawText: String, sessionID: String,
                             directory: DataDirectory) throws -> URL {
        let safeID = try SessionID.validated(sessionID)
        try directory.createIfNeeded()

        var candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID).txt")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if let existing = try? String(contentsOf: candidate, encoding: .utf8),
               existing == rawText {
                return candidate
            }
            guard suffix <= 100 else {
                throw CoachError.stateUnreadable(
                    "同一个会话编号「\(safeID)」下已经有 100 份内容不同的复盘原文，不再继续新建文件。"
                    + "下一步：到 \(directory.pendingReviewsDirectory.path) 清理掉不需要的文件，"
                    + "或换一个 sessionId 再试。")
            }
            candidate = directory.pendingReviewsDirectory.appending(path: "\(safeID)-\(suffix).txt")
            suffix += 1
        }

        try rawText.write(to: candidate, atomically: true, encoding: .utf8)
        return candidate
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PendingReviewStoreTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| 整个 `while` 循环删掉（永远写 `<id>.txt`） | `testDifferentTextNeverOverwritesWhatIsAlreadyThere` |
| `existing == rawText` 改成 `false` | `testWritingTheSameTextTwiceReusesTheSameFile` |
| `guard suffix <= 100` 删掉 | `testGivesUpWithAnActionableErrorInsteadOfLoopingForever`（会挂住而不是红——**若它挂住超过 30 秒就手动中断，这同样算突变生效**，并把现象写进报告） |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Storage/PendingReviewStore.swift Tests/IELTSCoachCoreTests/PendingReviewStoreTests.swift
git commit -m "feat(core): 复盘原文落盘（先落盘再解析）"
```

---

## Task 4: MCP target 骨架 + JSON-RPC / MCP 协议层

**Files:**
- Modify: `Package.swift`
- Create: `Sources/IELTSCoachMCP/JSONRPC.swift`
- Create: `Sources/IELTSCoachMCP/MCPTool.swift`
- Create: `Sources/IELTSCoachMCP/MCPServer.swift`
- Create: `Tests/IELTSCoachMCPTests/MCPServerProtocolTests.swift`

**Interfaces:**
- Consumes: `JSONValue`（`decode(from:)`、下标、`stringValue`、`arrayValue`、`objectValue`、`intValue`）、`CoachError`
- Produces:
  - `public enum JSONRPCID: Equatable, Sendable, Encodable { case number(Int); case string(String); case null }`
  - `public enum JSONRPCErrorCode`：`parseError = -32700`、`invalidRequest = -32600`、`methodNotFound = -32601`、`invalidParams = -32602`、`internalError = -32603`
  - `public struct ToolOutcome: Equatable`，含 `text: String`、`isError: Bool`、`static func success(_:)`、`static func failure(_:)`
  - `public struct MCPTool`，含 `name: String`、`description: String`、`inputSchema: JSONValue`、`run: (JSONValue) -> ToolOutcome`
  - `public final class MCPServer`：`init(tools: [MCPTool])`、`func handle(line: String) -> String?`、`static let supportedProtocolVersions: [String]`、`static let serverName/serverVersion: String`

**这个任务是本阶段的地基，也是最容易被糊弄过去的地方。** 协议层一旦崩，整条 stdio 连接就断了，客户端只会显示「服务器没响应」，用户拿不到任何线索——这正是「禁止静默失败」要防的形态。因此协议测试**不用真的 tool**，用两个假 tool 把「协议怎么回话」和「工具做什么」彻底分开。

**分帧方式：** MCP 的 stdio 传输是 **NDJSON**——每条消息一行、行内不得有裸换行。**不是** LSP 那种 `Content-Length` 头。`MCPServer.handle(line:)` 吃一行、吐一行，读写 stdin/stdout 的事留给 Task 10 的可执行文件，这样协议逻辑百分之百可测。

**几条不显然但必须照做的规矩：**

| 规矩 | 不照做会怎样 |
|---|---|
| 请求 id 是整数就必须原样回整数 | Codex 是 Rust 写的，`7.0` 反序列化进 `i64` 直接失败。症状是「服务器明明回了，客户端说协议错误」，极难查 |
| 通知（没有 `id` 的消息）**永远不回**，哪怕它是畸形的 | 回了会让客户端收到一条对不上号的消息 |
| 畸形 JSON 只能回 `id: null` | 连 id 都没解析出来，编不出别的 |
| 工具自身失败走 `result.isError`，不走协议错误 | 协议错误会让模型看不到失败原因，也就无从自我纠正。MCP 规范就是这么分的 |
| 未知的 tool 名走协议错误 `-32602` | 这是调用方用错了 API，不是工具执行失败 |

- [ ] **Step 1: 更新 Package.swift**

> **⚠️ 这是「往现有清单里加四行」，不是「用下面这段覆盖整个文件」**（2026-08-06 跨阶段复审补注）。
> Phase 5 已经加过 `IELTSCoachAudio`（一个 product、一个 target、一个 test target，
> 并把它加进了 `IELTSCoachUI` 的依赖）。照抄覆盖会把录音功能整块删掉，
> 症状是「几十个文件突然找不到 `RecordingSession`」，而原因在 `Package.swift` 里，很难联想到。
> **动手前先跑 `grep -n IELTSCoachAudio Package.swift`**：有输出就保留它的四处，只加 MCP 的四处。
> 下面这份已经把 Phase 5 与本阶段合并好了。

```swift
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .library(name: "IELTSCoachAudio", targets: ["IELTSCoachAudio"]),   // Phase 5，勿删
        .library(name: "IELTSCoachUI", targets: ["IELTSCoachUI"]),
        .library(name: "IELTSCoachMCP", targets: ["IELTSCoachMCP"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"]),
        .executable(name: "IELTSCoachApp", targets: ["IELTSCoachApp"]),
        .executable(name: "ielts-speaking-mcp", targets: ["ielts-speaking-mcp"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        // Phase 5：全工程唯一依赖 AVFoundation 的 target。勿删。
        .target(name: "IELTSCoachAudio", dependencies: ["IELTSCoachCore"]),
        .target(name: "IELTSCoachUI",
                dependencies: ["IELTSCoachCore", "ChatGPTBridge", "IELTSCoachAudio"]),
        // 只依赖 Core：MCP 一行都不碰 ChatGPT（spec 4.4），
        // 也因此它的测试在没有 ChatGPT、没有图形界面的环境里能全跑。
        .target(name: "IELTSCoachMCP", dependencies: ["IELTSCoachCore"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "IELTSCoachApp", dependencies: ["IELTSCoachUI"]),
        .executableTarget(name: "ielts-speaking-mcp", dependencies: ["IELTSCoachMCP"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachAudioTests", dependencies: ["IELTSCoachAudio"]),  // Phase 5，勿删
        .testTarget(name: "IELTSCoachUITests", dependencies: ["IELTSCoachUI"]),
        .testTarget(name: "IELTSCoachMCPTests", dependencies: ["IELTSCoachMCP", "IELTSCoachCore"])
    ]
```

**先把两个目录建出来再改 Package.swift**（`Sources/ielts-speaking-mcp/`、`Tests/IELTSCoachMCPTests/`），否则 SPM 会报「target 目录不存在」，或者退化去扫包根然后报 overlapping sources。`Sources/ielts-speaking-mcp/main.swift` 这一步先放一行 `// Task 10 实现` 之外加一句 `print` 也行，Task 10 会整个替换掉；只要能编过即可。

- [ ] **Step 2: 写失败的测试**

`Tests/IELTSCoachMCPTests/MCPServerProtocolTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

/// 协议层测试。**刻意不用真的 tool**——用两个假的，把「协议怎么回话」
/// 和「工具做什么」分开测。协议层崩了，客户端只会看到「服务器没响应」，
/// 拿不到任何线索。
final class MCPServerProtocolTests: XCTestCase {
    private static let initializeLine = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#

    private func makeServer(initialized: Bool = true) -> MCPServer {
        let echo = MCPTool(
            name: "echo",
            description: "把 message 原样返回，测试用。",
            inputSchema: .object(["type": .string("object")]),
            run: { arguments in .success(arguments["message"]?.stringValue ?? "(没有 message)") })

        let explode = MCPTool.throwing(
            name: "explode",
            description: "总是抛错，测试用。",
            inputSchema: .object(["type": .string("object")])) { _ in
                throw NSError(domain: "test", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "假装炸了"])
            }

        let server = MCPServer(tools: [echo, explode])
        if initialized { _ = server.handle(line: Self.initializeLine) }
        return server
    }

    /// 发一行、收一行、解析成 JSONValue。顺手把「响应必须是单独一行」也验了——
    /// 响应里混进换行会把 NDJSON 分帧撕成两半，客户端从此对不上号。
    private func respond(_ server: MCPServer, to line: String,
                         file: StaticString = #filePath, testLine: UInt = #line) throws -> JSONValue {
        let raw = try XCTUnwrap(server.handle(line: line),
                                "这条请求应当有响应，实际什么都没返回", file: file, line: testLine)
        XCTAssertFalse(raw.contains("\n"), "响应必须是单独一行，实际是：\(raw)", file: file, line: testLine)
        return try JSONValue.decode(from: raw)
    }

    // MARK: - 畸形输入

    func testMalformedJSONBecomesParseErrorInsteadOfCrashing() throws {
        let response = try respond(makeServer(), to: "{ 这不是 JSON")
        XCTAssertEqual(response["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32700)
        XCTAssertEqual(response["id"], JSONValue.null, "连 id 都没解析出来，只能回 null")
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("下一步"),
                      "错误信息必须说清下一步做什么")
    }

    func testServerKeepsWorkingAfterMalformedInput() throws {
        let server = makeServer()
        _ = server.handle(line: "{ 坏消息")
        let response = try respond(server, to: #"{"jsonrpc":"2.0","id":9,"method":"tools/list"}"#)
        XCTAssertNotNil(response["result"]?["tools"]?.arrayValue,
                        "一条坏消息不能让后面所有请求都废掉")
    }

    func testTopLevelValueMustBeAnObject() throws {
        let response = try respond(makeServer(), to: #""就一个字符串""#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testBatchRequestsAreRejectedWithAnExplanation() throws {
        // MCP 2025-06-18 已经移除批量请求。收到数组要明确说不支持，
        // 不能默默丢掉——默默丢掉的话客户端会一直等那条永远不来的响应。
        let response = try respond(makeServer(), to: #"[{"jsonrpc":"2.0","id":1,"method":"tools/list"}]"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("批量"))
    }

    func testBlankLinesAreIgnored() {
        let server = makeServer()
        XCTAssertNil(server.handle(line: ""))
        XCTAssertNil(server.handle(line: "   "))
    }

    func testTrailingCarriageReturnIsTolerated() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":4,"method":"ping"}"# + "\r")
        XCTAssertNotNil(response["result"])
    }

    // MARK: - 请求形状

    func testWrongJSONRPCVersionIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"1.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testMissingMethodIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":2}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testNonStringNonIntegerIDIsInvalidRequest() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
    }

    func testIntegerIDComesBackAsAnIntegerNotAFloat() throws {
        let raw = try XCTUnwrap(makeServer().handle(line: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#))
        // 客户端把 id 反序列化成整数；回 7.0 会让它当场解析失败，
        // 症状是「服务器有响应，客户端说协议错误」，是最难查的一类故障。
        XCTAssertTrue(raw.contains("\"id\":7"), "id 必须原样回整数 7，实际响应：\(raw)")
        XCTAssertFalse(raw.contains("7.0"), "实际响应：\(raw)")
    }

    func testStringIDComesBackAsAString() throws {
        let raw = try XCTUnwrap(makeServer().handle(line: #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#))
        XCTAssertTrue(raw.contains(#""id":"abc""#), "实际响应：\(raw)")
    }

    // MARK: - 通知

    func testNotificationsNeverGetAResponse() {
        let server = makeServer()
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        // 不认识的通知也不能回。JSON-RPC 规定通知没有响应，
        // 回一条错误会让客户端收到对不上号的消息。
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#))
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"完全不认识的通知"}"#))
    }

    // MARK: - 握手

    func testRequestsBeforeInitializeAreRejectedWithInstructions() throws {
        let response = try respond(makeServer(initialized: false),
                                   to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32600)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("initialize"))
    }

    func testInitializeAdvertisesToolsCapabilityAndServerInfo() throws {
        let response = try respond(makeServer(initialized: false), to: Self.initializeLine)
        XCTAssertEqual(response["result"]?["protocolVersion"]?.stringValue, "2025-06-18")
        XCTAssertNotNil(response["result"]?["capabilities"]?["tools"]?.objectValue)
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"]?.stringValue, "ielts-speaking-mcp")
        XCTAssertFalse((response["result"]?["serverInfo"]?["version"]?.stringValue ?? "").isEmpty)
    }

    func testUnknownProtocolVersionFallsBackToOneWeActuallySupport() throws {
        let response = try respond(makeServer(initialized: false),
                                   to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01","capabilities":{}}}"#)
        let version = try XCTUnwrap(response["result"]?["protocolVersion"]?.stringValue)
        XCTAssertTrue(MCPServer.supportedProtocolVersions.contains(version))
        XCTAssertNotEqual(version, "1999-01-01", "不能鹦鹉学舌地回一个我们并不支持的版本")
    }

    // MARK: - tools/list 与 tools/call

    func testToolsListReturnsNameDescriptionAndSchemaForEveryTool() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try XCTUnwrap(response["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools.compactMap { $0["name"]?.stringValue }, ["echo", "explode"])
        for tool in tools {
            XCTAssertFalse((tool["description"]?.stringValue ?? "").isEmpty)
            XCTAssertEqual(tool["inputSchema"]?["type"]?.stringValue, "object")
        }
    }

    func testUnknownMethodIsMethodNotFoundAndNamesTheMethod() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32601)
        XCTAssertTrue((response["error"]?["message"]?.stringValue ?? "").contains("resources/list"))
    }

    func testToolsCallWithoutParamsIsInvalidParams() throws {
        let response = try respond(makeServer(), to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call"}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testToolsCallWithoutNameIsInvalidParams() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"arguments":{}}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testUnknownToolNameIsInvalidParamsAndListsTheRealOnes() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
        let message = response["error"]?["message"]?.stringValue ?? ""
        XCTAssertTrue(message.contains("nope"))
        XCTAssertTrue(message.contains("echo"), "报错时要把真实存在的工具名列出来")
    }

    func testArgumentsMayBeOmitted() throws {
        // MCP 允许省略 arguments。省略时报错的话，所有无参工具都调不动。
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo"}}"#)
        XCTAssertEqual(response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue,
                       "(没有 message)")
        XCTAssertEqual(response["result"]?["isError"], JSONValue.bool(false))
    }

    func testArgumentsMustBeAnObjectWhenPresent() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo","arguments":[1,2]}}"#)
        XCTAssertEqual(response["error"]?["code"]?.intValue, -32602)
    }

    func testToolResultIsWrappedAsMCPTextContent() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"echo","arguments":{"message":"你好"}}}"#)
        let content = try XCTUnwrap(response["result"]?["content"]?.arrayValue)
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"]?.stringValue, "text")
        XCTAssertEqual(content[0]["text"]?.stringValue, "你好")
    }

    func testToolFailureIsAResultWithIsErrorNotAProtocolError() throws {
        let response = try respond(makeServer(),
                                   to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"explode","arguments":{}}}"#)
        XCTAssertNil(response["error"],
                     "工具自身失败必须走 result.isError；变成协议错误的话，模型看不到失败原因，也就无从自我纠正")
        XCTAssertEqual(response["result"]?["isError"], JSONValue.bool(true))
        let text = try XCTUnwrap(response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("假装炸了"), "原始错误信息不能被吞掉")
        XCTAssertTrue(text.contains("下一步"))
    }

    func testServerStillWorksAfterAToolThrows() throws {
        let server = makeServer()
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"explode","arguments":{}}}"#)
        let response = try respond(server, to: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        XCTAssertNotNil(response["result"])
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter MCPServerProtocolTests`
Expected: 编译失败 —— `MCPServer`、`MCPTool` 未定义

- [ ] **Step 4: 实现**

`Sources/IELTSCoachMCP/JSONRPC.swift`：

```swift
import Foundation
import IELTSCoachCore

/// JSON-RPC 2.0 的请求 id。**必须区分整数与字符串并原样回**：
/// 客户端（Codex 是 Rust 写的）把整数 id 反序列化成 i64，回 `7.0` 会让它
/// 直接解析失败，而症状是「服务器有响应，客户端报协议错误」——最难查的一类。
public enum JSONRPCID: Equatable, Sendable, Encodable {
    case number(Int)
    case string(String)
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

struct JSONRPCErrorObject: Encodable {
    let code: Int
    let message: String
}

/// `result` 与 `error` 二选一。两个都是 Optional，Swift 合成的 encode 走
/// encodeIfPresent，nil 的那个自然不会出现在 JSON 里。
struct JSONRPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    var result: JSONValue?
    var error: JSONRPCErrorObject?

    static func success(id: JSONRPCID, result: JSONValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }

    static func failure(id: JSONRPCID, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCErrorObject(code: code, message: message))
    }
}
```

`Sources/IELTSCoachMCP/MCPTool.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 一次工具调用的结果。`isError` 为真时 MCP 客户端仍然收到一条正常的 result，
/// 只是内容标着「这次失败了」——模型能读到失败原因并自我纠正。
/// 这与协议错误是两回事，别混：协议错误的文本模型看不到。
public struct ToolOutcome: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text; self.isError = isError
    }

    public static func success(_ text: String) -> ToolOutcome { ToolOutcome(text: text, isError: false) }
    public static func failure(_ message: String) -> ToolOutcome { ToolOutcome(text: message, isError: true) }
}

public struct MCPTool {
    public let name: String
    /// 面向用户与模型的中文说明。必须说清「这个工具干什么」，
    /// 需要前置条件的还要说清「先调哪个」。
    public let description: String
    public let inputSchema: JSONValue
    public let run: (JSONValue) -> ToolOutcome

    public init(name: String, description: String, inputSchema: JSONValue,
                run: @escaping (JSONValue) -> ToolOutcome) {
        self.name = name; self.description = description
        self.inputSchema = inputSchema; self.run = run
    }

    /// 把会抛错的实现包成绝不抛错的 `run`。
    /// **任何异常都不许穿透到协议层**——协议层挂了整条 stdio 就断了，
    /// 客户端只会看到「服务器没响应」，一点线索都没有。
    public static func throwing(name: String, description: String, inputSchema: JSONValue,
                                body: @escaping (ToolArguments) throws -> String) -> MCPTool {
        MCPTool(name: name, description: description, inputSchema: inputSchema) { arguments in
            do {
                return .success(try body(ToolArguments(arguments)))
            } catch let error as ToolInputError {
                return .failure(error.message)
            } catch let error as DashboardOpenError {
                return .failure(error.message)
            } catch let error as CoachError {
                // CoachError 的文案本来就是中文且带「下一步」，原样透出即可
                return .failure(error.errorDescription ?? "\(error)")
            } catch {
                return .failure("工具「\(name)」执行失败：\(error.localizedDescription)。"
                    + "下一步：把这条消息连同刚才的调用参数一起反馈给开发者。")
            }
        }
    }
}

enum ToolJSON {
    /// 工具的返回负载统一用 Codable struct 编码：
    /// 字段是 Int 就编成 `5`，不会变成 `5.0`，也不用手工拼 JSON。
    static func text<Payload: Encodable>(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolInputError(message: "工具的返回内容无法编码成文本。"
                + "下一步：把这条消息连同刚才的调用参数一起反馈给开发者。")
        }
        return text
    }
}
```

> `ToolArguments`、`ToolInputError`、`DashboardOpenError` 在 Task 5 才写。**本任务只需要它们能编过**：先在 `MCPTool.swift` 里放最小定义（`ToolInputError` 与 `DashboardOpenError` 各是一个只含 `message: String` 的 struct，`ToolArguments` 是一个只含 `value: JSONValue` 与 `init(_:)` 的 struct），Task 5 再把 `ToolArguments` 补全并把两个错误类型挪到各自的文件。**这不是占位符**：这两个类型在本任务里就有确切定义、被真实调用、被上面的 `explode` 测试覆盖。

`Sources/IELTSCoachMCP/MCPServer.swift`：

```swift
import Foundation
import IELTSCoachCore

/// MCP over stdio 的协议层。**只做一件事：吃一行、吐一行。**
/// 真正读写 stdin/stdout 的代码在可执行文件里，这样协议逻辑百分之百可测。
///
/// 分帧是 NDJSON（每条消息一行、行内无裸换行），不是 LSP 那种 Content-Length 头。
public final class MCPServer {
    /// 从新到旧。客户端要的版本在列表里就原样回，不在就回列表第一个——
    /// 鹦鹉学舌地回一个自己并不支持的版本，比明确降级更糟。
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverName = "ielts-speaking-mcp"
    public static let serverVersion = "0.9.0"

    private let tools: [MCPTool]
    private var initialized = false

    public init(tools: [MCPTool]) { self.tools = tools }

    /// 返回要写回 stdout 的一行；通知与空行返回 nil（通知不许有响应）。
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let message = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.parseError,
                message: "收到的这一行不是合法 JSON，无法解析。"
                    + "下一步：按 MCP stdio 规范每行发送一条完整的 JSON-RPC 消息（消息内部不能有裸换行）。"))
        }

        if message.arrayValue != nil {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "本服务器不接受批量请求（JSON-RPC batch），MCP 2025-06-18 已移除该特性。"
                    + "下一步：把每条请求单独发一行。"))
        }
        guard message.objectValue != nil else {
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "JSON-RPC 消息的顶层必须是对象。下一步：改发形如 "
                    + #"{"jsonrpc":"2.0","id":1,"method":"tools/list"} 的对象。"#))
        }

        let method = message["method"]?.stringValue

        switch parseID(message["id"]) {
        case .notification:
            // 通知没有响应，哪怕它是畸形的。回一条会让客户端收到对不上号的消息。
            if method == "notifications/initialized" { initialized = true }
            return nil
        case .invalid:
            return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest,
                message: "请求的 id 必须是字符串或整数。下一步：改用 \"id\": 1 或 \"id\": \"abc\" 这样的形式。"))
        case .value(let id):
            return encode(dispatch(id: id, method: method, message: message))
        }
    }

    // MARK: - 分发

    private func dispatch(id: JSONRPCID, method: String?, message: JSONValue) -> JSONRPCResponse {
        guard message["jsonrpc"]?.stringValue == "2.0" else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "缺少 jsonrpc 字段或它不是 \"2.0\"。下一步：每条消息都带上 \"jsonrpc\": \"2.0\"。")
        }
        guard let method, !method.isEmpty else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "缺少 method 字段。下一步：带上 method，例如 \"method\": \"tools/list\"。")
        }

        if method == "initialize" {
            initialized = true
            return .success(id: id, result: initializeResult(params: message["params"]))
        }

        guard initialized else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidRequest,
                message: "还没完成 initialize 握手，不能调用「\(method)」。"
                    + "下一步：先发一条 initialize 请求，再发其他请求。")
        }

        switch method {
        case "ping":
            return .success(id: id, result: .object([:]))
        case "tools/list":
            return .success(id: id, result: toolsListResult())
        case "tools/call":
            return callTool(id: id, params: message["params"])
        default:
            return .failure(id: id, code: JSONRPCErrorCode.methodNotFound,
                message: "不支持的方法「\(method)」。"
                    + "下一步：本服务器只实现 initialize、ping、tools/list、tools/call 四个方法；"
                    + "所有能力都通过 tools/call 使用。")
        }
    }

    private func initializeResult(params: JSONValue?) -> JSONValue {
        let requested = params?["protocolVersion"]?.stringValue ?? ""
        let version = Self.supportedProtocolVersions.contains(requested)
            ? requested : Self.supportedProtocolVersions[0]
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": .object([
                "name": .string(Self.serverName),
                "version": .string(Self.serverVersion)
            ]),
            "instructions": .string(
                "本机的雅思口语训练工具。先调用 initialize_ielts_workspace 建好工作区，"
                + "再用 set_training_selection 选题、get_training_context 取考官提示词；"
                + "练完把 ChatGPT 输出的整段复盘交给 save_session_review。"
                + "所有数据都在本机，不联网。")
        ])
    }

    private func toolsListResult() -> JSONValue {
        .object(["tools": .array(tools.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        })])
    }

    private func callTool(id: JSONRPCID, params: JSONValue?) -> JSONRPCResponse {
        guard let params, params.objectValue != nil else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 缺少 params 对象。"
                    + "下一步：传 {\"name\": \"工具名\", \"arguments\": {…}}。")
        }
        guard let name = params["name"]?.stringValue, !name.isEmpty else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 的 params 里缺少 name。"
                    + "下一步：先调用 tools/list 看可用工具，再把工具名填进 name。")
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "没有名为「\(name)」的工具。"
                    + "下一步：可用的工具是 \(tools.map(\.name).joined(separator: "、"))。")
        }
        let arguments = params["arguments"] ?? .object([:])
        guard arguments.objectValue != nil else {
            return .failure(id: id, code: JSONRPCErrorCode.invalidParams,
                message: "tools/call 的 arguments 必须是 JSON 对象。"
                    + "下一步：不传参数时可以整个省略 arguments，或传 {}。")
        }

        let outcome = tool.run(arguments)
        return .success(id: id, result: .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(outcome.text)
            ])]),
            "isError": .bool(outcome.isError)
        ]))
    }

    // MARK: - id

    private enum IDParse {
        case notification            // 没有 id
        case invalid                 // 有 id，但既不是字符串也不是整数
        case value(JSONRPCID)
    }

    private func parseID(_ raw: JSONValue?) -> IDParse {
        guard let raw else { return .notification }
        if let text = raw.stringValue { return .value(.string(text)) }
        if let number = raw.intValue { return .value(.number(number)) }
        return .invalid              // 含 "id": null —— MCP 明确禁止 null id
    }

    // MARK: - 编码

    private func encode(_ response: JSONRPCResponse) -> String {
        let encoder = JSONEncoder()
        // 不能用 .prettyPrinted：NDJSON 要求一条消息一行。
        // .sortedKeys 让输出确定，测试才好断言。
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(response),
              let text = String(data: data, encoding: .utf8) else {
            // 连响应都编不出来时也必须回一条合法的 JSON-RPC 错误。
            // 什么都不回 = 客户端一直等下去（禁止无限等待）。
            return #"{"error":{"code":-32603,"message":"服务器无法编码本次响应。下一步：把这条消息连同复现步骤反馈给开发者。"},"id":null,"jsonrpc":"2.0"}"#
        }
        return text
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter MCPServerProtocolTests`
Expected: PASS（24 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 6: 突变验证**

这个任务是地基，突变要做三处：

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `JSONRPCID.encode` 里 `.number` 分支改成 `try container.encode(Double(value))` | `testIntegerIDComesBackAsAnIntegerNotAFloat` |
| `handle` 的 `.notification` 分支改成 `return encode(.failure(id: .null, code: JSONRPCErrorCode.invalidRequest, message: "x"))` | `testNotificationsNeverGetAResponse` |
| `MCPTool.throwing` 里的 `catch` 全删（改成 `return .success(try! body(...))`，让异常直接崩） | `testToolFailureIsAResultWithIsErrorNotAProtocolError` 与 `testServerStillWorksAfterAToolThrows` 双双变红（后者会直接 crash 掉测试进程——**那也算变红**，把现象写进报告） |

三次输出都写进报告，改回后确认全绿。

- [ ] **Step 7: 提交**

```bash
git add Package.swift Sources/IELTSCoachMCP/JSONRPC.swift Sources/IELTSCoachMCP/MCPTool.swift Sources/IELTSCoachMCP/MCPServer.swift Sources/ielts-speaking-mcp/main.swift Tests/IELTSCoachMCPTests/MCPServerProtocolTests.swift
git commit -m "feat(mcp): JSON-RPC over stdio 协议层"
```

---

## Task 5: 工具参数读取与运行环境

**Files:**
- Create: `Sources/IELTSCoachMCP/ToolArguments.swift`
- Create: `Sources/IELTSCoachMCP/MCPEnvironment.swift`
- Modify: `Sources/IELTSCoachMCP/MCPTool.swift`（把 Task 4 临时放在这里的 `ToolInputError` / `DashboardOpenError` / `ToolArguments` 最小定义挪走）
- Create: `Tests/IELTSCoachMCPTests/TestSupport.swift`
- Create: `Tests/IELTSCoachMCPTests/ToolArgumentsTests.swift`
- Create: `Tests/IELTSCoachMCPTests/MCPEnvironmentTests.swift`（复审补：见本节末尾「复审修订」）

**Interfaces:**
- Consumes: `JSONValue`（下标、`stringValue`、`intValue`）、`DataDirectory`、`StateStore`
- Produces:
  - `public struct ToolInputError: Error, Equatable`，含 `message: String`
  - `public struct DashboardOpenError: Error, LocalizedError, Equatable`，含 `message: String`、`errorDescription`
  - `public protocol DashboardOpening { func open(_ url: URL) throws }`
  - `public struct ToolArguments`：`init(_ value: JSONValue)`、`requiredString(_:trimmed:hint:) throws -> String`、`optionalString(_:) throws -> String?`、`optionalInt(_:in:default:hint:) throws -> Int`、`optionalChoice(_:allowed:default:hint:) throws -> String`
  - `public struct MCPEnvironment`：`init(directory:opener:now:timeZone:)`、属性 `directory`、`store`、`opener`、`now`、`timeZone`、`timestamp: String`
  - 测试用：`makeTemporaryDirectory()`、`FakeDashboardOpener`、`ServerHarness`

**为什么参数校验单独一层：** 7 个 tool 都要读参数、都要在参数不对时给中文提示。写 7 遍就会出现 7 种措辞，其中总有一两处忘了写「下一步」。

**一条硬规矩：越界不许悄悄夹紧。** `limit: 0` 传进来时返回 20（默认值）或 1（夹紧），都属于「调用方以为自己传的是 0，拿到的却是别的行为，而且没有提示」。这正是本项目反复消灭的那类静默失败。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachMCPTests/TestSupport.swift`（本任务建，后面每个 tool 任务都用它）：

```swift
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachMCP

/// 每个测试一个独立的临时数据目录。
/// **绝不能让测试写到 DataDirectory.resolve() 的真实目录**——那是用户的训练记录。
func makeTemporaryDirectory() -> DataDirectory {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ielts-mcp-\(UUID().uuidString)")
    return DataDirectory(root: root)
}

/// 记录被请求打开的 URL，永远不真的打开任何东西。
/// 真机上唤起 App 是 Task 13 的人工验收，单元测试里一次都不许发生。
final class FakeDashboardOpener: DashboardOpening {
    private(set) var opened: [URL] = []
    var errorToThrow: (any Error)?

    func open(_ url: URL) throws {
        if let errorToThrow { throw errorToThrow }
        opened.append(url)
    }
}

/// 固定时间的运行环境，测试里一律用它，免得断言随「今天几号」变化。
func makeEnvironment(directory: DataDirectory, opener: FakeDashboardOpener,
                     nowISO: String = "2026-08-06T12:00:00Z") -> MCPEnvironment {
    let now = ISO8601DateFormatter().date(from: nowISO)!
    return MCPEnvironment(directory: directory, opener: opener, now: { now },
                          timeZone: TimeZone(identifier: "UTC")!)
}

/// 让每个 tool 测试都**走一遍真实的协议层**再落到工具上。
/// 直接调 `tool.run` 会漏掉 tools/call 的参数校验，那部分同样会在真机上出事。
final class ServerHarness {
    let server: MCPServer
    private var nextID = 100

    init(tools: [MCPTool]) {
        server = MCPServer(tools: tools)
        _ = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#)
    }

    convenience init(environment: MCPEnvironment) {
        self.init(tools: ToolCatalog.tools(environment: environment))
    }

    enum HarnessError: Error { case noResponse, unexpectedProtocolError(String) }

    /// 返回工具的文本负载与 isError。落到协议错误上会直接让测试失败并打印原文——
    /// 那说明测试自己把参数传错了，不该被当成「工具返回了错误」。
    @discardableResult
    func callTool(_ name: String, _ arguments: [String: JSONValue] = [:],
                  file: StaticString = #filePath, line: UInt = #line)
        throws -> (text: String, isError: Bool) {
        nextID += 1
        let request = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(nextID)),
            "method": .string("tools/call"),
            "params": .object(["name": .string(name), "arguments": .object(arguments)])
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let requestLine = String(data: try encoder.encode(request), encoding: .utf8)!

        guard let responseLine = server.handle(line: requestLine) else {
            XCTFail("调用 \(name) 没有得到任何响应", file: file, line: line)
            throw HarnessError.noResponse
        }
        let response = try JSONValue.decode(from: responseLine)
        if let error = response["error"] {
            let message = error["message"]?.stringValue ?? "\(error)"
            XCTFail("调用 \(name) 落到了协议错误上：\(message)", file: file, line: line)
            throw HarnessError.unexpectedProtocolError(message)
        }
        let text = response["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        let isError = response["result"]?["isError"] == .bool(true)
        return (text, isError)
    }

    /// 工具成功时返回的是一段 JSON 文本，这里解析开好做断言。
    func callToolJSON(_ name: String, _ arguments: [String: JSONValue] = [:],
                      file: StaticString = #filePath, line: UInt = #line) throws -> JSONValue {
        let result = try callTool(name, arguments, file: file, line: line)
        XCTAssertFalse(result.isError, "\(name) 本应成功，实际返回：\(result.text)", file: file, line: line)
        return try JSONValue.decode(from: result.text)
    }
}
```

`Tests/IELTSCoachMCPTests/ToolArgumentsTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class ToolArgumentsTests: XCTestCase {
    private func arguments(_ pairs: [String: JSONValue]) -> ToolArguments {
        ToolArguments(.object(pairs))
    }

    private func message(from error: any Error) -> String {
        ((error as? ToolInputError)?.message) ?? "\(error)"
    }

    func testRequiredStringReturnsTrimmedValue() throws {
        let args = arguments(["questionId": .string("  p1-abc  ")])
        XCTAssertEqual(try args.requiredString("questionId", hint: "h"), "p1-abc")
    }

    func testRequiredStringCanKeepTheRawTextUntouched() throws {
        // 复盘原文两端的空白要原样留着——那是 ChatGPT 输出的一部分，
        // 存进 pending-reviews 的应该是它真正输出的样子。
        let args = arguments(["reviewText": .string("\n复盘\n")])
        XCTAssertEqual(try args.requiredString("reviewText", trimmed: false, hint: "h"), "\n复盘\n")
    }

    func testRequiredStringComplainsWhenMissing() {
        XCTAssertThrowsError(try arguments([:]).requiredString("questionId", hint: "先看题库拿题号。")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("questionId"), "错误信息要指名道姓说是哪个参数")
            XCTAssertTrue(text.contains("先看题库拿题号。"), "调用方给的 hint 必须出现在文案里")
        }
    }

    func testRequiredStringRejectsWrongTypeInsteadOfCoercing() {
        XCTAssertThrowsError(try arguments(["questionId": .number(3)]).requiredString("questionId", hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("字符串"))
        }
    }

    func testRequiredStringRejectsBlank() {
        XCTAssertThrowsError(try arguments(["questionId": .string("   ")]).requiredString("questionId", hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("空"))
        }
    }

    func testOptionalStringTreatsBlankAndNullAsAbsent() throws {
        XCTAssertNil(try arguments([:]).optionalString("goal"))
        XCTAssertNil(try arguments(["goal": .null]).optionalString("goal"))
        XCTAssertNil(try arguments(["goal": .string("  ")]).optionalString("goal"))
        XCTAssertEqual(try arguments(["goal": .string(" 补一个例子 ")]).optionalString("goal"), "补一个例子")
    }

    func testOptionalStringRejectsWrongTypeInsteadOfSilentlyDroppingIt() {
        // 复审补。「键在、但类型不对」不是「没传」，详见本节末尾「复审修订」。
        XCTAssertThrowsError(try arguments(["goal": .number(12345)]).optionalString("goal")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("goal"))
            XCTAssertTrue(text.contains("字符串"))
        }
        XCTAssertThrowsError(try arguments(["goal": .bool(true)]).optionalString("goal"))
        XCTAssertThrowsError(try arguments(["goal": .array([.string("a")])]).optionalString("goal"))
    }

    func testOptionalIntUsesTheDefaultWhenAbsent() throws {
        let value = try arguments([:]).optionalInt("limit", in: 1...200, default: 20, hint: "h")
        XCTAssertEqual(value, 20)
    }

    func testOptionalIntRejectsOutOfRangeInsteadOfClamping() {
        // 夹紧 = 调用方以为自己传的是 0、拿到的却是 1 的行为，且没有任何提示。
        // 这正是本项目反复消灭的那类静默失败。
        XCTAssertThrowsError(try arguments(["limit": .number(0)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "传 1–200。")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("1"))
            XCTAssertTrue(text.contains("200"))
            XCTAssertTrue(text.contains("传 1–200。"))
        }
        XCTAssertThrowsError(try arguments(["limit": .number(999)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h"))
    }

    func testOptionalIntRejectsFractionsAndStrings() {
        XCTAssertThrowsError(try arguments(["limit": .number(3.5)])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h")) {
            XCTAssertTrue(message(from: $0).contains("整数"))
        }
        XCTAssertThrowsError(try arguments(["limit": .string("12")])
            .optionalInt("limit", in: 1...200, default: 20, hint: "h"))
    }

    func testOptionalChoiceFallsBackWhenAbsentOrNull() throws {
        XCTAssertEqual(try arguments([:]).optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h"), "a")
        XCTAssertEqual(try arguments(["mode": .null])
            .optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h"), "a")
    }

    func testOptionalChoiceRejectsUnknownValueAndListsWhatIsAllowed() {
        XCTAssertThrowsError(try arguments(["mode": .string("c")])
            .optionalChoice("mode", allowed: ["a", "b"], default: "a", hint: "h")) {
            let text = message(from: $0)
            XCTAssertTrue(text.contains("c"))
            XCTAssertTrue(text.contains("a"))
            XCTAssertTrue(text.contains("b"))
        }
    }

    func testEveryErrorMessageTellsTheCallerWhatToDoNext() {
        // 逐条兜住「禁止只报错不给出路」。漏一条都算不合格。
        let failures: [() throws -> Any] = [
            { try self.arguments([:]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .number(1)]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .string(" ")]).requiredString("k", hint: "改这里。") },
            { try self.arguments(["k": .number(1)]).optionalString("k") as Any },
            { try self.arguments(["k": .number(0)]).optionalInt("k", in: 1...9, default: 5, hint: "改这里。") },
            { try self.arguments(["k": .number(1.5)]).optionalInt("k", in: 1...9, default: 5, hint: "改这里。") },
            { try self.arguments(["k": .string("x")]).optionalChoice("k", allowed: ["y"], default: "y", hint: "改这里。") }
        ]
        for (index, failure) in failures.enumerated() {
            XCTAssertThrowsError(try failure(), "第 \(index) 条本应报错") { error in
                XCTAssertTrue(self.message(from: error).contains("下一步"),
                              "第 \(index) 条的错误信息没有说下一步做什么：\(self.message(from: error))")
            }
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ToolArgumentsTests`
Expected: 编译失败 —— `ToolArguments.requiredString` 等方法未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachMCP/ToolArguments.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 参数不合法。会被 `MCPTool.throwing` 转成 `isError` 结果，模型能读到并自我纠正。
/// `message` 必须同时说清「哪里不对」和「下一步怎么改」。
public struct ToolInputError: Error, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

/// 读 tool 的 arguments。7 个 tool 共用这一层，
/// 免得同一种错误出现 7 种措辞，其中总有一两处忘了写「下一步」。
public struct ToolArguments {
    public let value: JSONValue

    public init(_ value: JSONValue) { self.value = value }

    public subscript(key: String) -> JSONValue? { value[key] }

    public func requiredString(_ key: String, trimmed: Bool = true, hint: String) throws -> String {
        guard let raw = value[key], raw != .null else {
            throw ToolInputError(message: "缺少必填参数「\(key)」。下一步：\(hint)")
        }
        guard let text = raw.stringValue else {
            throw ToolInputError(message: "参数「\(key)」必须是字符串。下一步：\(hint)")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolInputError(message: "参数「\(key)」是空的。下一步：\(hint)")
        }
        return trimmed ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }

    /// 缺失、null、空白一律当作「没传」；**键在、但不是字符串，报错**（复审修订，见本节末尾）。
    public func optionalString(_ key: String) throws -> String? {
        guard let raw = value[key], raw != .null else { return nil }
        guard let text = raw.stringValue else {
            throw ToolInputError(message: "参数「\(key)」必须是字符串。"
                + "下一步：把它改成字符串再传一次；本来就不想传这个参数的话，整个省掉即可。")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// **越界报错，不夹紧。** 夹紧等于「调用方以为自己传的是 0，拿到的却是 1 的行为，
    /// 而且没有任何提示」——本项目反复消灭的正是这类静默失败。
    public func optionalInt(_ key: String, in range: ClosedRange<Int>,
                            default fallback: Int, hint: String) throws -> Int {
        guard let raw = value[key], raw != .null else { return fallback }
        guard let number = raw.intValue else {
            throw ToolInputError(message: "参数「\(key)」必须是整数。下一步：\(hint)")
        }
        guard range.contains(number) else {
            throw ToolInputError(message:
                "参数「\(key)」必须在 \(range.lowerBound)–\(range.upperBound) 之间，收到的是 \(number)。"
                + "下一步：\(hint)")
        }
        return number
    }

    /// 同上：不认识的取值报错，不悄悄退回默认值。
    public func optionalChoice(_ key: String, allowed: [String],
                               default fallback: String, hint: String) throws -> String {
        guard let raw = value[key], raw != .null else { return fallback }
        guard let text = raw.stringValue else {
            throw ToolInputError(message: "参数「\(key)」必须是字符串。下一步：\(hint)")
        }
        guard allowed.contains(text) else {
            throw ToolInputError(message:
                "参数「\(key)」的取值「\(text)」不认识，只能是 \(allowed.joined(separator: "、"))。"
                + "下一步：\(hint)")
        }
        return text
    }
}
```

`Sources/IELTSCoachMCP/MCPEnvironment.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 唤起 App 的通道。抽成 protocol 是为了让单元测试用假实现——
/// **测试里一次都不许真的去开一个应用窗口。**
public protocol DashboardOpening {
    func open(_ url: URL) throws
}

public struct DashboardOpenError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// 7 个 tool 共用的运行环境。时间与时区都注入进来，
/// 测试断言才不会随「今天几号」「跑在哪个时区」变化。
public struct MCPEnvironment {
    public let directory: DataDirectory
    /// 由 directory 构造，两者不可能指向不同地方。
    public let store: StateStore
    public let opener: any DashboardOpening
    public let now: () -> Date
    public let timeZone: TimeZone

    public init(directory: DataDirectory, opener: any DashboardOpening,
                now: @escaping () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.directory = directory
        self.store = StateStore(directory: directory)
        self.opener = opener
        self.now = now
        self.timeZone = timeZone
    }

    /// 全项目统一的时间戳格式。各处格式不一致会让按 startedAt 的字符串排序错乱。
    public var timestamp: String { ISO8601DateFormatter().string(from: now()) }
}
```

同时把 Task 4 临时放在 `MCPTool.swift` 里的 `ToolInputError` / `DashboardOpenError` / `ToolArguments` 最小定义删掉（它们现在有正式的家了），`MCPTool.swift` 只保留 `ToolOutcome`、`MCPTool`、`ToolJSON`。

> `TestSupport.swift` 里引用了 `ToolCatalog`，而它在 Task 6 才出现。**本任务先不写 `ServerHarness.init(environment:)` 那个 convenience init**，Task 6 建了 `ToolCatalog` 之后再补上——本步骤只需要 `ToolArgumentsTests` 编得过、跑得通。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter 'ToolArgumentsTests|MCPEnvironmentTests'`
Expected: PASS（13 + 4 个测试）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `optionalInt` 里的越界分支改成 `return min(max(number, range.lowerBound), range.upperBound)`（夹紧） | `testOptionalIntRejectsOutOfRangeInsteadOfClamping` |
| `optionalChoice` 里的 `guard allowed.contains(text)` 改成 `return allowed.contains(text) ? text : fallback` | `testOptionalChoiceRejectsUnknownValueAndListsWhatIsAllowed` |
| 任意一条错误文案里的「下一步：\(hint)」改成只留前半句 | `testEveryErrorMessageTellsTheCallerWhatToDoNext` |
| `optionalString` 里「不是字符串就抛错」改回 `return nil`（静默当成没传） | `testOptionalStringRejectsWrongTypeInsteadOfSilentlyDroppingIt`、`testEveryErrorMessageTellsTheCallerWhatToDoNext` |
| `MCPEnvironment.init` 里 `StateStore(directory: directory)` 改成指向别的目录 | `testStoreWritesIntoTheInjectedDirectory` |
| `timestamp` 改成 `{ "" }` 或任意写死的常量 | `testTimestampUsesTheInjectedInstantInTheProjectFormat` |
| `self.timeZone = timeZone` 改成写死某个时区 | `testTimeZoneIsTheInjectedOneNotTheMachineDefault` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachMCP/ToolArguments.swift Sources/IELTSCoachMCP/MCPEnvironment.swift Sources/IELTSCoachMCP/MCPTool.swift Tests/IELTSCoachMCPTests/TestSupport.swift Tests/IELTSCoachMCPTests/ToolArgumentsTests.swift Tests/IELTSCoachMCPTests/MCPEnvironmentTests.swift
git commit -m "feat(mcp): 工具参数校验与运行环境"
```

**复审修订（2026-08-07）**

两处，都已改在计划正文里，实现与之一致：

1. **`optionalString` 从 `-> String?` 改成 `throws -> String?`。** 原写法对「键存在、
   但不是字符串」返回 nil，等于把类型错误静默当成「没传」——同一个文件里
   `requiredString` / `optionalInt` / `optionalChoice` 遇到类型不符统统报错，只有它吞掉。
   下游的实际后果：`save_session_review` 的 `sessionId` 写成数字时会被当成没给，
   于是新建一场会话、或把复盘挂到当前会话的题目上，用户看不到任何提示。
   这与铁律 7（禁止静默失败）和本任务自己那条「越界不许悄悄夹紧」是同一件事，
   属于铁律 11 说的「计划与铁律冲突」，在这一层修掉，不让 7 个 tool 都建在它上面。
   「缺失 / null / 空白 = 没传」的语义原样保留；4 个下游调用点相应加 `try`。

2. **补 `MCPEnvironmentTests.swift`。** 原计划里 `MCPEnvironment` 整个文件零执行覆盖：
   把 `store` 改成指向别的目录、把 `timestamp` 改成 `{ "" }`、把 `timeZone` 写死，
   1406 条测试全都不会红。其中 store 那条最危险——`TestSupport.swift` 开头写着
   「绝不能让测试写到 DataDirectory.resolve() 的真实目录」，却没有任何断言保证
   `store` 真的用的是注入进来的 directory；写成 `DataDirectory.resolve()` 的话，
   Task 6–9 的每一条 tool 测试都会往用户真实的训练记录里写，而测试照样全绿。
   时区与时刻各断言两个不同取值，免得「写死一个常量」恰好蒙对。

---

## Task 6: `initialize_ielts_workspace` 与 `open_dashboard`

**Files:**
- Create: `Sources/IELTSCoachMCP/ToolCatalog.swift`
- Create: `Sources/IELTSCoachMCP/Tools/InitializeWorkspaceTool.swift`
- Create: `Sources/IELTSCoachMCP/Tools/OpenDashboardTool.swift`
- Modify: `Tests/IELTSCoachMCPTests/TestSupport.swift`（补上 `ServerHarness.init(environment:)`）
- Create: `Tests/IELTSCoachMCPTests/WorkspaceToolsTests.swift`

**Interfaces:**
- Consumes: `DataDirectory.createIfNeeded()`、`StateStore.mutate`、`CoachState`、`CoachRoute`、`MCPEnvironment`、`ToolArguments`、`MCPTool.throwing`
- Produces:
  - `public enum ToolCatalog`：`static func tools(environment: MCPEnvironment) -> [MCPTool]`
  - `enum InitializeWorkspaceTool`：`static func make(environment: MCPEnvironment) -> MCPTool`
  - `enum OpenDashboardTool`：`static func make(environment: MCPEnvironment) -> MCPTool`

**`open_dashboard` 的实现方式由 spec 4.4 钉死**：`NSWorkspace.open(URL(string: "ieltscoach://dashboard"))`。真正调 `NSWorkspace` 的代码在 Task 10 的可执行文件里（那样 `IELTSCoachMCP` 库就不必依赖 AppKit，测试也能在无图形环境里跑）；这里只负责**拼出 URL、交给 `DashboardOpening`、把失败翻译成人话**。

- [ ] **Step 1: 写失败的测试**

先给 `TestSupport.swift` 补上这个 convenience init（Task 5 里留的口子）：

```swift
    convenience init(environment: MCPEnvironment) {
        self.init(tools: ToolCatalog.tools(environment: environment))
    }
```

`Tests/IELTSCoachMCPTests/WorkspaceToolsTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class WorkspaceToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        opener = FakeDashboardOpener()
        harness = ServerHarness(environment: makeEnvironment(directory: directory, opener: opener))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - initialize_ielts_workspace

    func testCreatesTheDataDirectoryAndStateFile() throws {
        // 刻意没有预先 createIfNeeded：这个工具的职责就是「让工作区存在」。
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.stateFile.path))

        let payload = try harness.callToolJSON("initialize_ielts_workspace")

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path))
        XCTAssertEqual(payload["createdStateFile"], JSONValue.bool(true))
        XCTAssertEqual(payload["dataDirectory"]?.stringValue, directory.root.path)
        XCTAssertEqual(payload["schemaVersion"]?.intValue, 3)
        XCTAssertEqual(payload["questionCount"]?.intValue, 0)
    }

    func testSecondCallReportsThatItDidNotCreateAnything() throws {
        _ = try harness.callToolJSON("initialize_ielts_workspace")
        let payload = try harness.callToolJSON("initialize_ielts_workspace")
        XCTAssertEqual(payload["createdStateFile"], JSONValue.bool(false),
                       "第二次调用不能还说自己新建了文件——用户会以为记录被重置了")
    }

    func testWritesDisplayNameOnlyWhenThereIsNoneYet() throws {
        _ = try harness.callToolJSON("initialize_ielts_workspace", ["displayName": .string("Andy")])
        XCTAssertEqual(try StateStore(directory: directory).load().learner.displayName, "Andy")

        _ = try harness.callToolJSON("initialize_ielts_workspace", ["displayName": .string("别人")])
        XCTAssertEqual(try StateStore(directory: directory).load().learner.displayName, "Andy",
                       "已有昵称不能被后来的调用覆盖")
    }

    func testEmptyBankNoteTellsTheUserWhatToDoNext() throws {
        let payload = try harness.callToolJSON("initialize_ielts_workspace")
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("下一步"), "题库为空时必须给出路，而不是只报一个 0")
    }

    // MARK: - open_dashboard

    func testOpensTheDashboardURLByDefault() throws {
        let payload = try harness.callToolJSON("open_dashboard")
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["ieltscoach://dashboard"])
        XCTAssertEqual(payload["opened"]?.stringValue, "ieltscoach://dashboard")
    }

    func testOpensTheRequestedSection() throws {
        _ = try harness.callToolJSON("open_dashboard", ["section": .string("history")])
        XCTAssertEqual(opener.opened.map(\.absoluteString), ["ieltscoach://history"])
    }

    func testUnknownSectionIsRejectedWithoutOpeningAnything() throws {
        let result = try harness.callTool("open_dashboard", ["section": .string("nope")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("dashboard"), "报错时要把可用的页面列出来")
        XCTAssertTrue(result.text.contains("下一步"))
        XCTAssertTrue(opener.opened.isEmpty, "参数不合法时一个窗口都不该被打开")
    }

    func testOpenFailureIsExplainedInPlainChinese() throws {
        opener.errorToThrow = DashboardOpenError(message:
            "系统没能打开 ieltscoach://dashboard。下一步：先手动打开一次 App。")
        let result = try harness.callTool("open_dashboard")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步：先手动打开一次 App。"),
                      "唤起失败的原文必须原样透出，不能被包成一句笼统的「执行失败」")
    }

    // MARK: - 目录

    func testCatalogOnlyContainsNamesFromSpec() {
        // spec 4.4 钉死了 7 个名字。这条先兜住「不许自己发明工具名」，
        // Task 9 再收紧成「恰好这 7 个、顺序也一致」。
        let specNames: Set<String> = [
            "initialize_ielts_workspace", "open_dashboard", "set_training_selection",
            "get_training_context", "save_session_review", "list_practice_history",
            "get_dashboard_data"
        ]
        let names = ToolCatalog.tools(environment:
            makeEnvironment(directory: directory, opener: opener)).map(\.name)
        XCTAssertEqual(Set(names).subtracting(specNames), [], "出现了 spec 4.4 之外的工具名")
        XCTAssertTrue(names.contains("initialize_ielts_workspace"))
        XCTAssertTrue(names.contains("open_dashboard"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter WorkspaceToolsTests`
Expected: 编译失败 —— `ToolCatalog` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachMCP/ToolCatalog.swift`（本任务先装两个，Task 7–9 逐步补齐到 7 个）：

```swift
import Foundation
import IELTSCoachCore

/// 7 个 tool 的装配点。**名字与顺序照抄 spec 第 4.4 节，一个字都不能改。**
public enum ToolCatalog {
    public static func tools(environment: MCPEnvironment) -> [MCPTool] {
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment)
        ]
    }
}
```

`Sources/IELTSCoachMCP/Tools/InitializeWorkspaceTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum InitializeWorkspaceTool {
    private struct Payload: Encodable {
        let dataDirectory: String
        let stateFile: String
        let createdStateFile: Bool
        let schemaVersion: Int
        let learnerName: String
        let questionCount: Int
        let sessionCount: Int
        let issueCount: Int
        let vocabularyCount: Int
        let targetCount: Int
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "initialize_ielts_workspace",
            description: "确保本机的雅思训练数据目录与 state.json 存在，并返回目录位置与各项数量。"
                + "第一次使用这套工具时先调用它。数据全部保存在本机，不联网。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "displayName": .object([
                        "type": .string("string"),
                        "description": .string("学员昵称。只在当前还没有昵称时写入，不会覆盖已有的。可省略。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let displayName = try arguments.optionalString("displayName") ?? ""
            // 先看文件在不在，再建目录——顺序反了就永远报「已经存在」。
            let existed = FileManager.default.fileExists(atPath: environment.directory.stateFile.path)
            try environment.directory.createIfNeeded()

            // mutate 会把 state 写回磁盘，所以即使什么都不改，state.json 也会被建出来。
            let state = try environment.store.mutate { state -> CoachState in
                if !displayName.isEmpty && state.learner.displayName.isEmpty {
                    state.learner.displayName = displayName
                }
                return state
            }

            return try ToolJSON.text(Payload(
                dataDirectory: environment.directory.root.path,
                stateFile: environment.directory.stateFile.path,
                createdStateFile: !existed,
                schemaVersion: state.schemaVersion,
                learnerName: state.learner.displayName,
                questionCount: state.questions.count,
                sessionCount: state.sessions.count,
                issueCount: state.issues.count,
                vocabularyCount: state.vocabulary.count,
                targetCount: state.targets.count,
                note: state.questions.isEmpty
                    ? "工作区就绪，但题库还是空的。下一步：在 App 的「训练题库」页导入题库文件，"
                        + "或在终端运行 coach questions import <文件>。"
                    : "工作区就绪。下一步：用 set_training_selection 选一道题。"))
        }
    }
}
```

`Sources/IELTSCoachMCP/Tools/OpenDashboardTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum OpenDashboardTool {
    private struct Payload: Encodable {
        let opened: String
        let section: String
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let allowed = CoachRoute.allCases.map(\.rawValue)
        return MCPTool.throwing(
            name: "open_dashboard",
            description: "唤起本机的 IELTS Speaking Coach 应用并跳到指定页面。"
                + "可选页面：\(allowed.joined(separator: "、"))，默认 dashboard（今日训练）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "section": .object([
                        "type": .string("string"),
                        "enum": .array(allowed.map { JSONValue.string($0) }),
                        "description": .string("要打开的页面，默认 dashboard。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let raw = try arguments.optionalChoice("section", allowed: allowed,
                default: CoachRoute.dashboard.rawValue,
                hint: "把 section 改成这几个之一：\(allowed.joined(separator: "、"))。")
            // optionalChoice 已经保证 raw 在 allowed 里，这里再兜一层是因为
            // allowed 与 CoachRoute 万一将来对不上，宁可报错也不要打开一个错的页面。
            guard let route = CoachRoute(rawValue: raw) else {
                throw ToolInputError(message: "无法识别的页面「\(raw)」。"
                    + "下一步：改用 \(allowed.joined(separator: "、")) 之一。")
            }

            try environment.opener.open(route.url)

            return try ToolJSON.text(Payload(
                opened: route.url.absoluteString,
                section: route.rawValue,
                note: "已请求系统打开 IELTS Speaking Coach。若窗口没出现，"
                    + "下一步：确认 .app 已经装好并手动双击打开过一次——"
                    + "系统只有在应用被打开过之后才会登记 ieltscoach:// 这个链接。"))
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter WorkspaceToolsTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `let existed = ...` 挪到 `createIfNeeded()` 之后 | `testCreatesTheDataDirectoryAndStateFile`（`createdStateFile` 变成 false）|
| `if !displayName.isEmpty && state.learner.displayName.isEmpty` 去掉后半个条件 | `testWritesDisplayNameOnlyWhenThereIsNoneYet` |
| `OpenDashboardTool` 里把 `try environment.opener.open(route.url)` 挪到 `optionalChoice` 之前（用默认路由先开一下） | `testUnknownSectionIsRejectedWithoutOpeningAnything` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachMCP/ToolCatalog.swift Sources/IELTSCoachMCP/Tools/InitializeWorkspaceTool.swift Sources/IELTSCoachMCP/Tools/OpenDashboardTool.swift Tests/IELTSCoachMCPTests/TestSupport.swift Tests/IELTSCoachMCPTests/WorkspaceToolsTests.swift
git commit -m "feat(mcp): initialize_ielts_workspace 与 open_dashboard"
```

---

## Task 7: `set_training_selection` 与 `get_training_context`

**Files:**
- Create: `Sources/IELTSCoachMCP/Tools/SetTrainingSelectionTool.swift`
- Create: `Sources/IELTSCoachMCP/Tools/GetTrainingContextTool.swift`
- Modify: `Sources/IELTSCoachMCP/ToolCatalog.swift`
- Create: `Tests/IELTSCoachMCPTests/SelectionToolsTests.swift`

**Interfaces:**
- Consumes: `CoachState.currentSession/questions`、`Question`、`PracticeSession`、`FocusPart`、`FeedbackTiming`、`Part2PrepMode`、`SessionSetup(question:focusPart:durationMinutes:goal:feedbackTiming:part2PrepMode:)`、`ExaminerPrompt.build(setup:)`、`ReviewRequestPrompt.build(requestID:focusPart:)`、`RetrainingPolicy.rank(targets:issues:)`、`IssueRanking.top(_:limit:)`、`SessionID.next(existing:now:timeZone:)`
- Produces:
  - `enum SetTrainingSelectionTool`：`static func make(environment: MCPEnvironment) -> MCPTool`
  - `enum GetTrainingContextTool`：`static func make(environment: MCPEnvironment) -> MCPTool`

**这两个 tool 是「薄封装」的标准样例：** 提示词一个字都不在 MCP 层拼，全部来自 `ExaminerPrompt` / `ReviewRequestPrompt`。**如果发现要在这里写 prompt 文本，说明走错了**——那两个类型里的英文契约句直接决定 ChatGPT 是否进入考官角色，只能有一份。

**选题存 `currentSession`**（理由见开头「一条贯穿全局的设计判断」）。`durationMinutes` / `feedbackTiming` / `part2PrepMode` 在 schema 3 里没有位置，因此是 `get_training_context` 的参数，默认值与 `coach practice` 一致。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class SelectionToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        opener = FakeDashboardOpener()
        harness = ServerHarness(environment: makeEnvironment(directory: directory, opener: opener))
        try StateStore(directory: directory).mutate { state in
            state.questions = [
                Question(id: "p1-home", part: 1, topic: "Home",
                         prompt: "Do you live in a house or a flat?"),
                Question(id: "p2-skill", part: 2, topic: "Skills",
                         prompt: "Describe a useful skill you learned.",
                         followups: ["what it is", "how you learned it"])
            ]
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - set_training_selection

    func testSelectionIsWrittenIntoCurrentSession() throws {
        let payload = try harness.callToolJSON("set_training_selection", [
            "questionId": .string("p2-skill"),
            "goal": .string("回答后补一个原因和例子")
        ])
        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        XCTAssertEqual(payload["focusPart"]?.stringValue, "Part 2", "没传 focusPart 时按题目自身的 part 推断")

        let session = try XCTUnwrap(StateStore(directory: directory).load().currentSession)
        XCTAssertEqual(session.questionId, "p2-skill")
        XCTAssertEqual(session.focusPart, .part2)
        XCTAssertEqual(session.goal, "回答后补一个原因和例子")
        XCTAssertEqual(session.endedAt, "", "刚选完题，练习还没结束")
        XCTAssertEqual(session.reportPath, "")
    }

    func testFocusPartCanBeOverriddenForFullMock() throws {
        let payload = try harness.callToolJSON("set_training_selection", [
            "questionId": .string("p1-home"),
            "focusPart": .string("full mock")
        ])
        XCTAssertEqual(payload["focusPart"]?.stringValue, "full mock")
        XCTAssertEqual(try StateStore(directory: directory).load().currentSession?.focusPart, .fullMock)
    }

    func testUnknownQuestionIsRejectedAndNothingIsWritten() throws {
        let result = try harness.callTool("set_training_selection", ["questionId": .string("不存在")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("不存在"))
        XCTAssertTrue(result.text.contains("下一步"))
        XCTAssertNil(try StateStore(directory: directory).load().currentSession,
                     "选题失败时不能留下半个选择——下一次 get_training_context 会拿它去练")
    }

    func testMissingQuestionIdIsRejectedWithInstructions() throws {
        let result = try harness.callTool("set_training_selection")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("questionId"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testUnknownFocusPartIsRejectedWithTheAllowedValues() throws {
        let result = try harness.callTool("set_training_selection", [
            "questionId": .string("p1-home"), "focusPart": .string("Part 9")
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Part 1"))
        XCTAssertTrue(result.text.contains("full mock"))
    }

    // MARK: - get_training_context

    func testBuildsExaminerPromptFromTheSelectedQuestion() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p2-skill")])
        let payload = try harness.callToolJSON("get_training_context")

        XCTAssertEqual(payload["question"]?["id"]?.stringValue, "p2-skill")
        XCTAssertEqual(payload["durationMinutes"]?.intValue, 4, "Part 2 默认 4 分钟，与 coach practice 一致")
        XCTAssertEqual(payload["feedbackTiming"]?.stringValue, "deferred")
        XCTAssertEqual(payload["part2PrepMode"]?.stringValue, "countdown")

        let prompt = try XCTUnwrap(payload["examinerPrompt"]?.stringValue)
        // 提示词必须是 ExaminerPrompt 生成的那一份，不是 MCP 层自己拼的。
        // 这三条分别来自契约段、题目段、Part 2 规则段。
        XCTAssertTrue(prompt.contains("You will act as an IELTS Speaking examiner."))
        XCTAssertTrue(prompt.contains("Describe a useful skill you learned."))
        XCTAssertTrue(prompt.contains("Section rules (Part 2)"))
        XCTAssertTrue(prompt.contains("how you learned it"), "followups 要一起进提示词")
    }

    func testDefaultDurationForNonPart2IsSixMinutes() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")
        XCTAssertEqual(payload["durationMinutes"]?.intValue, 6)
    }

    func testImmediateFeedbackChangesTheContract() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context",
                                               ["feedbackTiming": .string("immediate")])
        let prompt = try XCTUnwrap(payload["examinerPrompt"]?.stringValue)
        XCTAssertTrue(prompt.contains("ONE short correction"))
        XCTAssertFalse(prompt.contains("I will save all feedback until the end"),
                       "immediate 模式下开场白也要跟着换，不能只换反馈规则")
    }

    func testReviewRequestPromptIsIncludedAndCarriesAMatchingMarker() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")
        let requestID = try XCTUnwrap(payload["reviewRequestId"]?.stringValue)
        let reviewPrompt = try XCTUnwrap(payload["reviewRequestPrompt"]?.stringValue)
        XCTAssertTrue(reviewPrompt.contains("<<<IELTS_REVIEW_JSON:\(requestID)>>>"))
        XCTAssertTrue(reviewPrompt.contains("vocabulary 必须是数组"),
                      "复盘指令必须是 ReviewRequestPrompt 那一份——它把每条内部的字段名都写死了（spec 2.3.8）")
    }

    func testTheSameSelectionAlwaysYieldsTheSameReviewRequestId() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let first = try harness.callToolJSON("get_training_context")["reviewRequestId"]?.stringValue
        let second = try harness.callToolJSON("get_training_context")["reviewRequestId"]?.stringValue
        XCTAssertEqual(first, second, "同一场练习问两次上下文，标记必须一致，否则复盘对不上号")
    }

    func testWithoutASelectionItSaysWhatToDoNext() throws {
        let result = try harness.callTool("get_training_context")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("set_training_selection"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testSelectedQuestionDisappearingFromTheBankIsExplained() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        try StateStore(directory: directory).mutate { $0.questions = [] }   // 模拟换季重新导入
        let result = try harness.callTool("get_training_context")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("p1-home"))
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testOutOfRangeDurationIsRejected() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let result = try harness.callTool("get_training_context", ["durationMinutes": .number(0)])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testContextCarriesActiveTargetsAndRecurringIssues() throws {
        try StateStore(directory: directory).mutate { state in
            state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                        correction: "I really like it.", whyItMatters: "w",
                                        occurrences: 4, sourceSessionIds: ["s"], lastSeenAt: "t")]
            state.targets = [
                RetrainingTarget(targetKey: "retired", label: "旧的", status: "retired",
                                 evidence: [], sourceSessionId: "s0", createdAt: "t"),
                RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                                 evidence: ["I very like it."], sourceSessionId: "s1", createdAt: "t")
            ]
        }
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
        let payload = try harness.callToolJSON("get_training_context")

        let targets = try XCTUnwrap(payload["activeTargets"]?.arrayValue)
        XCTAssertEqual(targets.compactMap { $0["id"]?.stringValue }, ["logic-explain"],
                       "已退休的目标不能出现在下一场练习的上下文里")
        let issues = try XCTUnwrap(payload["recurringIssues"]?.arrayValue)
        XCTAssertEqual(issues.first?["learnerSaid"]?.stringValue, "I very like it.")
        XCTAssertEqual(issues.first?["occurrences"]?.intValue, 4)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SelectionToolsTests`
Expected: 编译失败 —— `SetTrainingSelectionTool` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachMCP/Tools/SetTrainingSelectionTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum SetTrainingSelectionTool {
    private struct Payload: Encodable {
        let sessionId: String
        let questionId: String
        let part: Int
        let topic: String
        let prompt: String
        let focusPart: String
        let goal: String
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let parts = FocusPart.allCases.map(\.rawValue)
        return MCPTool.throwing(
            name: "set_training_selection",
            description: "选定下一场练习的题目、Part 与单点目标，写进 state.json 的 currentSession。"
                + "App 与命令行都会读到同一份选择。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "questionId": .object([
                        "type": .string("string"),
                        "description": .string("题库里的题号，例如 p1-2f3k9x。用 get_dashboard_data 或 App 的「训练题库」页可以看到。")
                    ]),
                    "focusPart": .object([
                        "type": .string("string"),
                        "enum": .array(parts.map { JSONValue.string($0) }),
                        "description": .string("练哪一部分。省略时按题目自身的 part 推断。")
                    ]),
                    "goal": .object([
                        "type": .string("string"),
                        "description": .string("本次唯一的单点目标，例如「回答后补一个原因和例子」。可留空。")
                    ])
                ]),
                "required": .array([.string("questionId")]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let questionID = try arguments.requiredString("questionId",
                hint: "先调用 get_dashboard_data 或在 App 的「训练题库」页找到题号，再传进来。")
            let goal = try arguments.optionalString("goal") ?? ""

            // 整个「查题 + 写选择」放在同一次 mutate 里：查不到题就抛错，
            // mutate 的写入发生在 body 之后，因此磁盘上不会留下半个选择。
            let payload = try environment.store.mutate { state -> Payload in
                guard let question = state.questions.first(where: { $0.id == questionID }) else {
                    throw ToolInputError(message:
                        "题库里没有题号「\(questionID)」（当前共 \(state.questions.count) 题）。"
                        + "下一步：调用 get_dashboard_data 看看现在有哪些题，"
                        + "或先在 App 的「训练题库」页导入题库。")
                }
                let inferred = FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
                let focusRaw = try arguments.optionalChoice("focusPart", allowed: parts,
                    default: inferred.rawValue,
                    hint: "focusPart 只能是 \(parts.joined(separator: "、"))。")
                let focusPart = FocusPart(rawValue: focusRaw) ?? inferred

                let sessionID = SessionID.next(existing: state.sessions, now: environment.now(),
                                               timeZone: environment.timeZone)
                state.currentSession = PracticeSession(
                    id: sessionID, questionId: question.id, focusPart: focusPart,
                    startedAt: environment.timestamp, endedAt: "", goal: goal,
                    transcript: [], reportPath: "", recordingPath: "")

                return Payload(sessionId: sessionID, questionId: question.id, part: question.part,
                               topic: question.topic, prompt: question.prompt,
                               focusPart: focusPart.rawValue, goal: goal,
                               note: "已选定。下一步：调用 get_training_context 取考官提示词。")
            }
            return try ToolJSON.text(payload)
        }
    }
}
```

`Sources/IELTSCoachMCP/Tools/GetTrainingContextTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum GetTrainingContextTool {
    private struct QuestionPayload: Encodable {
        let id: String
        let part: Int
        let topic: String
        let prompt: String
        let followups: [String]
    }

    private struct TargetPayload: Encodable {
        let id: String
        let label: String
        let status: String
        let evidence: [String]
    }

    private struct IssuePayload: Encodable {
        let learnerSaid: String
        let correction: String
        let occurrences: Int
    }

    private struct Payload: Encodable {
        let sessionId: String
        let question: QuestionPayload
        let focusPart: String
        let durationMinutes: Int
        let goal: String
        let feedbackTiming: String
        let part2PrepMode: String
        let examinerPrompt: String
        let reviewRequestId: String
        let reviewRequestPrompt: String
        let activeTargets: [TargetPayload]
        let recurringIssues: [IssuePayload]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        let timings = FeedbackTiming.allCases.map(\.rawValue)
        let prepModes = Part2PrepMode.allCases.map(\.rawValue)

        return MCPTool.throwing(
            name: "get_training_context",
            description: "取当前选定题目的完整练习上下文：考官提示词、复盘请求指令、"
                + "待复训目标与反复出现的错题。调用前先用 set_training_selection 选题。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "durationMinutes": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(60),
                        "description": .string("这一场大约练多少分钟。省略时 Part 2 用 4 分钟、其余用 6 分钟。")
                    ]),
                    "feedbackTiming": .object([
                        "type": .string("string"),
                        "enum": .array(timings.map { JSONValue.string($0) }),
                        "description": .string("deferred＝全程零反馈、像真考试（默认）；immediate＝每答完一题当场用中文点一句。")
                    ]),
                    "part2PrepMode": .object([
                        "type": .string("string"),
                        "enum": .array(prepModes.map { JSONValue.string($0) }),
                        "description": .string("countdown＝一分钟准备倒计时（默认）；learner-controlled＝学员说准备好了再开始。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let state = try environment.store.load()
            guard let session = state.currentSession else {
                throw ToolInputError(message:
                    "还没有选定题目，没有可用的练习上下文。下一步：先调用 set_training_selection 选一道题。")
            }
            guard let question = state.questions.first(where: { $0.id == session.questionId }) else {
                throw ToolInputError(message:
                    "选中的题目「\(session.questionId)」已经不在题库里了（通常是换季重新导入过题库）。"
                    + "下一步：调用 set_training_selection 重新选一道题。")
            }

            let duration = try arguments.optionalInt("durationMinutes", in: 1...60,
                default: question.part == 2 ? 4 : 6,
                hint: "durationMinutes 传 1–60 之间的整数分钟；省略则 Part 2 用 4 分钟、其余用 6 分钟。")
            let timingRaw = try arguments.optionalChoice("feedbackTiming", allowed: timings,
                default: FeedbackTiming.deferred.rawValue,
                hint: "feedbackTiming 只能是 deferred 或 immediate。")
            let prepRaw = try arguments.optionalChoice("part2PrepMode", allowed: prepModes,
                default: Part2PrepMode.countdown.rawValue,
                hint: "part2PrepMode 只能是 countdown 或 learner-controlled。")

            // 提示词一个字都不在这里拼：英文契约句直接决定 ChatGPT 是否进入考官角色，
            // 只能有 ExaminerPrompt 那一份（spec 2.3.x 全靠它）。
            let setup = SessionSetup(
                question: question, focusPart: session.focusPart, durationMinutes: duration,
                goal: session.goal,
                feedbackTiming: FeedbackTiming(rawValue: timingRaw) ?? .deferred,
                part2PrepMode: Part2PrepMode(rawValue: prepRaw) ?? .countdown)

            // 标记由 sessionId 派生，所以同一场练习问几次上下文都是同一个值——
            // 换一个就意味着复盘里的标记和这边对不上号。
            let requestID = "sync-\(session.id)"

            return try ToolJSON.text(Payload(
                sessionId: session.id,
                question: QuestionPayload(id: question.id, part: question.part, topic: question.topic,
                                          prompt: question.prompt, followups: question.followups),
                focusPart: session.focusPart.rawValue,
                durationMinutes: duration,
                goal: session.goal,
                feedbackTiming: timingRaw,
                part2PrepMode: prepRaw,
                examinerPrompt: ExaminerPrompt.build(setup: setup),
                reviewRequestId: requestID,
                reviewRequestPrompt: ReviewRequestPrompt.build(requestID: requestID,
                                                              focusPart: session.focusPart),
                activeTargets: RetrainingPolicy.rank(targets: state.targets, issues: state.issues)
                    .prefix(3)
                    .map { TargetPayload(id: $0.targetKey, label: $0.label, status: $0.status,
                                         evidence: $0.evidence) },
                recurringIssues: IssueRanking.top(state.issues, limit: 3)
                    .map { IssuePayload(learnerSaid: $0.learnerSaid, correction: $0.correction,
                                        occurrences: $0.occurrences) },
                note: "下一步：把 examinerPrompt 原样发给已经进入 Live 语音的 ChatGPT；"
                    + "练完再发 reviewRequestPrompt，然后把 ChatGPT 输出的整段复盘交给 save_session_review。"))
        }
    }
}
```

`ToolCatalog.tools` 补成四个（顺序照 spec 4.4）：

```swift
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment),
            SetTrainingSelectionTool.make(environment: environment),
            GetTrainingContextTool.make(environment: environment)
        ]
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SelectionToolsTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `SetTrainingSelectionTool` 里查不到题时改成 `state.currentSession = nil; return Payload(...)`（不抛错） | `testUnknownQuestionIsRejectedAndNothingIsWritten` |
| `GetTrainingContextTool` 里的 `question.part == 2 ? 4 : 6` 改成 `6` | `testBuildsExaminerPromptFromTheSelectedQuestion` |
| `let requestID = "sync-\(session.id)"` 改成 `"sync-\(Int(environment.now().timeIntervalSince1970))-\(UUID().uuidString)"` | `testTheSameSelectionAlwaysYieldsTheSameReviewRequestId`（**注意：固定 now 的情况下前半段不变，所以必须把 UUID 也加上才是真突变**）|

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachMCP/Tools/SetTrainingSelectionTool.swift Sources/IELTSCoachMCP/Tools/GetTrainingContextTool.swift Sources/IELTSCoachMCP/ToolCatalog.swift Tests/IELTSCoachMCPTests/SelectionToolsTests.swift
git commit -m "feat(mcp): set_training_selection 与 get_training_context"
```

---

## Task 8: `save_session_review`

**Files:**
- Create: `Sources/IELTSCoachMCP/Tools/SaveSessionReviewTool.swift`
- Modify: `Sources/IELTSCoachMCP/ToolCatalog.swift`
- Create: `Tests/IELTSCoachMCPTests/SaveSessionReviewToolTests.swift`

**Interfaces:**
- Consumes: `PendingReviewStore.write(rawText:sessionID:directory:)`、`ReviewParser.parse(_:requireAnswerUpgrades:)`、`ReviewArchiver.archive(report:into:sessionID:questionID:at:)`、`ArchiveOutcome`（`state`、`skipped`）、`StateStore.mutate`、`SessionID.validated(_:)`、`SessionID.next(existing:now:timeZone:)`、`JSONValue`
- Produces: `enum SaveSessionReviewTool`：`static func make(environment: MCPEnvironment) -> MCPTool`

**这是本阶段最大的一块，也是最容易出人命的一块。** 三条铁律，每条都是本项目已经栽过的坑：

1. **先落盘，再解析。** 顺序反了，解析一失败，用户练了一整场换来的复盘原文就没了（成品标准第 7 条，`coach practice` 的注释里写着同一条）。
2. **归档 0 条必须报出来。** `must_correct` 存在却一条都没归进去，几乎肯定是 ChatGPT 用的字段名和我们读的对不上（spec 2.3.8）。`ArchiveOutcome.skipped` 已经把这件事算好了，**不许把它丢掉**——「静默的 0 是本项目已知最危险的失败形态」。
3. **`sessionId` 要过安全校验。** 它由模型给，会直接拼进文件名。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class SaveSessionReviewToolTests: XCTestCase {
    private var directory: DataDirectory!
    private var harness: ServerHarness!

    /// 一份结构完全正确的复盘，字段名与 ReviewRequestPrompt 规定的严格一致（spec 2.3.8）。
    private static let goodReview = """
    好的，这是你这次的复盘。

    <<<IELTS_REVIEW_JSON:sync-2026-08-06-001>>>
    {
      "summary": "整体流利度不错，细节偏少。",
      "must_correct": [
        {"learner_said": "I very like it.", "correction": "I really like it.",
         "why_it_matters": "very 不能直接修饰动词"}
      ],
      "natural_upgrades": [],
      "vocabulary": [
        {"basic": "good", "better": "rewarding", "collocation": "a rewarding experience",
         "priority": "high"}
      ],
      "habits": [],
      "logic_feedback": [],
      "answer_upgrades": [],
      "priority_target": {"id": "logic-explain", "label": "回答后补一个原因和例子",
                          "status": "new", "evidence": ["I just like it."]}
    }
    <<<END_IELTS_REVIEW_JSON:sync-2026-08-06-001>>>
    """

    /// 顶层键齐全、但每条内部的字段名是 ChatGPT 自己发挥的那一版（spec 2.3.8 实测记录）。
    /// 解析能过，归档一条都进不去——这正是最危险的形态。
    private static let wrongFieldNames = """
    <<<IELTS_REVIEW_JSON:x>>>
    {"must_correct": [{"issue": "very like", "examples": "I very like it.", "fix": "really"}],
     "vocabulary": [{"word": "good", "upgrade": "rewarding"}],
     "priority_target": {"id": "t1", "label": "L", "status": "new", "evidence": []}}
    <<<END_IELTS_REVIEW_JSON:x>>>
    """

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                             opener: FakeDashboardOpener()))
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "p1-home", part: 1, topic: "Home", prompt: "Q?")]
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func selectQuestion() throws {
        _ = try harness.callToolJSON("set_training_selection", ["questionId": .string("p1-home")])
    }

    func testArchivesEverythingAndClosesTheCurrentSession() throws {
        try selectQuestion()
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.goodReview)])

        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        XCTAssertEqual(payload["issuesAdded"]?.intValue, 1)
        XCTAssertEqual(payload["vocabularyAdded"]?.intValue, 1)
        XCTAssertEqual(payload["reportPath"]?.stringValue, "reports/2026-08-06-001.json")
        XCTAssertEqual(payload["skipped"]?.arrayValue?.count, 0)

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.issues.count, 1)
        XCTAssertEqual(state.issues[0].learnerSaid, "I very like it.")
        XCTAssertEqual(state.vocabulary.count, 1)
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.questions[0].status, "practiced", "练过的题要被标记")
        XCTAssertNil(state.currentSession, "存完复盘这一场就结束了，不能还挂在 currentSession 上")
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.sessions[0].id, "2026-08-06-001")
        XCTAssertEqual(state.sessions[0].reportPath, "reports/2026-08-06-001.json")
        XCTAssertFalse(state.sessions[0].endedAt.isEmpty)

        let reportFile = directory.reportsDirectory.appending(path: "2026-08-06-001.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportFile.path))
        let saved = try JSONValue.decode(from: String(contentsOf: reportFile, encoding: .utf8))
        XCTAssertEqual(saved["priority_target"]?["id"]?.stringValue, "logic-explain",
                       "reports/ 里存的必须是解析后的复盘本身")
    }

    func testKeepsTheRawTextWhenParsingFails() throws {
        try selectQuestion()
        let result = try harness.callTool("save_session_review",
                                          ["reviewText": .string("ChatGPT 这次答的完全不是复盘")])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))

        // 关键：原文必须已经落盘，而且路径要告诉用户。
        let pending = directory.pendingReviewsDirectory.appending(path: "2026-08-06-001.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path),
                      "解析失败也不能丢原文——用户练了一整场换来的就是它")
        XCTAssertEqual(try String(contentsOf: pending, encoding: .utf8), "ChatGPT 这次答的完全不是复盘")
        XCTAssertTrue(result.text.contains(pending.path), "错误信息里必须给出原文的路径")

        let state = try StateStore(directory: directory).load()
        XCTAssertTrue(state.issues.isEmpty)
        XCTAssertNotNil(state.currentSession, "没存成的话这一场还没结束，选择要留着")
    }

    func testReportsSilentlyEmptyArchivesInsteadOfClaimingSuccess() throws {
        try selectQuestion()
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.wrongFieldNames)])

        let skipped = try XCTUnwrap(payload["skipped"]?.arrayValue).compactMap(\.stringValue)
        XCTAssertEqual(Set(skipped), ["must_correct", "vocabulary"],
                       "顶层键存在却一条都没归进去，必须报出来（spec 2.3.8）")
        let warning = try XCTUnwrap(payload["warning"]?.stringValue)
        XCTAssertTrue(warning.contains("must_correct"))
        XCTAssertTrue(warning.contains("下一步"))
        XCTAssertTrue(warning.contains("reimport"), "要告诉用户这场练习还能补救，不必重练")
    }

    func testRejectsSessionIdThatCouldEscapeTheDataDirectory() throws {
        let result = try harness.callTool("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "sessionId": .string("../../escaped")
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))
        let escaped = directory.root.deletingLastPathComponent().appending(path: "escaped.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testEmptyReviewTextIsRejected() throws {
        let result = try harness.callTool("save_session_review", ["reviewText": .string("   ")])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("下一步"))
    }

    func testWorksWithoutAnySelectionByGeneratingItsOwnSessionID() throws {
        // 没走过 set_training_selection 也要能存——用户可能是在 ChatGPT 里
        // 自己练完才想起来存档，不该因为少了一步就把复盘拒之门外。
        let payload = try harness.callToolJSON("save_session_review",
                                               ["reviewText": .string(Self.goodReview)])
        XCTAssertEqual(payload["sessionId"]?.stringValue, "2026-08-06-001")
        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.issues.count, 1)
    }

    func testSavingTwiceForTheSameSessionDoesNotDuplicateTheSessionRow() throws {
        try selectQuestion()
        _ = try harness.callToolJSON("save_session_review", ["reviewText": .string(Self.goodReview)])
        _ = try harness.callToolJSON("save_session_review", [
            "reviewText": .string(Self.goodReview),
            "sessionId": .string("2026-08-06-001")
        ])
        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.sessions.count, 1, "同一个 sessionId 存两次不能变成两条练习记录")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SaveSessionReviewToolTests`
Expected: 编译失败 —— `SaveSessionReviewTool` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation
import IELTSCoachCore

enum SaveSessionReviewTool {
    private struct Payload: Encodable {
        let sessionId: String
        let questionId: String
        let reportPath: String          // 相对路径，与 PracticeSession.reportPath 一致
        let reportFile: String          // 绝对路径，方便用户直接打开
        let pendingReviewPath: String
        let issuesAdded: Int
        let vocabularyAdded: Int
        let issueTotal: Int
        let vocabularyTotal: Int
        let targetTotal: Int
        let skipped: [String]
        let warning: String?
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "save_session_review",
            description: "把 ChatGPT 输出的整段复盘存档：原文先落盘，再解析，然后并入错题本、"
                + "词汇本、重训目标，并推进计划进度。传整段原文（含 <<<IELTS_REVIEW_JSON…>>> 首尾标记）即可。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "reviewText": .object([
                        "type": .string("string"),
                        "description": .string("ChatGPT 输出的整段复盘原文，含首尾标记。不要自己改写或截断。")
                    ]),
                    "sessionId": .object([
                        "type": .string("string"),
                        "description": .string("这一场的会话编号。省略时用当前选题的编号，没有选题就自动生成。")
                    ]),
                    "questionId": .object([
                        "type": .string("string"),
                        "description": .string("这一场练的题号。省略时用当前选题的题号。")
                    ])
                ]),
                "required": .array([.string("reviewText")]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let rawText = try arguments.requiredString("reviewText", trimmed: false,
                hint: "把 ChatGPT 输出的整段复盘（含 <<<IELTS_REVIEW_JSON…>>> 首尾标记）原样传进来。")

            let state = try environment.store.load()
            let sessionID: String
            if let given = try arguments.optionalString("sessionId") {
                sessionID = try SessionID.validated(given)     // 会直接拼进文件名，必须校验
            } else if let current = state.currentSession {
                sessionID = current.id
            } else {
                sessionID = SessionID.next(existing: state.sessions, now: environment.now(),
                                           timeZone: environment.timeZone)
            }
            let questionID = try arguments.optionalString("questionId")
                ?? state.currentSession?.questionId ?? ""

            // ⚠️ 顺序不能改：先落盘，再解析。
            // 反过来写的话，解析一抛错，用户练了一整场换来的复盘原文就没了
            //（成品标准第 7 条；coach practice 里也是这个顺序）。
            let pendingURL = try PendingReviewStore.write(rawText: rawText, sessionID: sessionID,
                                                          directory: environment.directory)

            let report: JSONValue
            do {
                report = try ReviewParser.parse(rawText, requireAnswerUpgrades: false)
            } catch {
                throw ToolInputError(message:
                    "\(error.localizedDescription)\n"
                    + "好消息是原文没丢，已经存在 \(pendingURL.path)。"
                    + "下一步：打开这个文件看看 ChatGPT 到底输出了什么；"
                    + "让它按 get_training_context 给的 reviewRequestPrompt 重新输出一次后再调一次本工具；"
                    + "也可以在 App 的「复盘报告」页点「重新导入待处理的复盘」，"
                    + "或在终端运行 coach reimport 把已落盘的复盘补入库。")
            }

            let timestamp = environment.timestamp
            let reportRelativePath = "reports/\(sessionID).json"
            let reportURL = environment.directory.reportsDirectory.appending(path: "\(sessionID).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(report).write(to: reportURL, options: .atomic)

            let payload = try environment.store.mutate { state -> Payload in
                let issuesBefore = state.issues.count
                let vocabularyBefore = state.vocabulary.count

                let outcome = ReviewArchiver.archive(report: report, into: state,
                                                     sessionID: sessionID, questionID: questionID,
                                                     at: timestamp)
                state = outcome.state

                // 这一场的记录：优先接着 currentSession，其次接着已有的同号记录，
                // 都没有就新建一条。三条路都要走通——用户可能压根没调过 set_training_selection。
                var session = state.currentSession.flatMap { $0.id == sessionID ? $0 : nil }
                    ?? state.sessions.first { $0.id == sessionID }
                    ?? PracticeSession(id: sessionID, questionId: questionID,
                                       focusPart: focusPart(forQuestion: questionID, in: state),
                                       startedAt: timestamp, endedAt: "", goal: "",
                                       transcript: [], reportPath: "", recordingPath: "")
                session.endedAt = timestamp
                session.reportPath = reportRelativePath
                if session.questionId.isEmpty { session.questionId = questionID }

                if let index = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                    state.sessions[index] = session          // 重存不产生第二条记录
                } else {
                    state.sessions.append(session)
                }
                if state.currentSession?.id == sessionID { state.currentSession = nil }

                let warning = outcome.skipped.isEmpty ? nil :
                    "复盘里有 \(outcome.skipped.joined(separator: "、"))，但一条都没能归进档案。"
                    + "这通常意味着 ChatGPT 用的字段名和本工具读的对不上——归档 0 条不等于没错题。"
                    + "下一步：原文完整保存在 \(pendingURL.path)，"
                    + "让 ChatGPT 按 reviewRequestPrompt 里写死的字段名重新输出一次；"
                    + "也可以在 App 的「复盘报告」页点「重新导入待处理的复盘」，"
                    + "或在终端运行 coach reimport 重新入库，这场练习不会白费。"

                return Payload(
                    sessionId: sessionID,
                    questionId: session.questionId,
                    reportPath: reportRelativePath,
                    reportFile: reportURL.path,
                    pendingReviewPath: pendingURL.path,
                    issuesAdded: state.issues.count - issuesBefore,
                    vocabularyAdded: state.vocabulary.count - vocabularyBefore,
                    issueTotal: state.issues.count,
                    vocabularyTotal: state.vocabulary.count,
                    targetTotal: state.targets.count,
                    skipped: outcome.skipped,
                    warning: warning,
                    note: "已存档。下一步：用 get_dashboard_data 看看这次之后的整体情况，"
                        + "或用 open_dashboard 打开复盘报告页。")
            }
            return try ToolJSON.text(payload)
        }
    }

    /// 新建记录时用得上：题目还在题库里就按它的 part，找不到就按全真模考处理。
    private static func focusPart(forQuestion questionID: String, in state: CoachState) -> FocusPart {
        guard let question = state.questions.first(where: { $0.id == questionID }) else { return .fullMock }
        return FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
    }
}
```

`ToolCatalog.tools` 里在 `GetTrainingContextTool` 之后补 `SaveSessionReviewTool.make(environment: environment)`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SaveSessionReviewToolTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

这是本阶段最关键的一组突变，三条都要做：

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| 把 `PendingReviewStore.write(...)` 那一句挪到 `ReviewParser.parse` 成功之后 | `testKeepsTheRawTextWhenParsingFails` |
| `let warning = outcome.skipped.isEmpty ? nil : ...` 改成 `let warning: String? = nil` | `testReportsSilentlyEmptyArchivesInsteadOfClaimingSuccess` |
| `sessionID = try SessionID.validated(given)` 改成 `sessionID = given` | `testRejectsSessionIdThatCouldEscapeTheDataDirectory` |

三次输出写进报告。**第二条守的是本项目已知最危险的失败形态**：复盘写得好好的、工具报「成功」，而错题本纹丝不动。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachMCP/Tools/SaveSessionReviewTool.swift Sources/IELTSCoachMCP/ToolCatalog.swift Tests/IELTSCoachMCPTests/SaveSessionReviewToolTests.swift
git commit -m "feat(mcp): save_session_review（先落盘再解析，归档 0 条必报）"
```

---

## Task 9: `list_practice_history`、`get_dashboard_data` 与工具目录定稿

**Files:**
- Create: `Sources/IELTSCoachMCP/Tools/ListPracticeHistoryTool.swift`
- Create: `Sources/IELTSCoachMCP/Tools/GetDashboardDataTool.swift`
- Modify: `Sources/IELTSCoachMCP/ToolCatalog.swift`
- Create: `Tests/IELTSCoachMCPTests/HistoryToolsTests.swift`
- Create: `Tests/IELTSCoachMCPTests/ToolCatalogTests.swift`

**Interfaces:**
- Consumes: `CoachState.sessions/questions`、`PracticeSession`、`DashboardSummary.build(state:now:weeklyGoal:topIssueLimit:targetLimit:)`、`PlanProgress`
- Produces:
  - `enum ListPracticeHistoryTool`：`static func make(environment: MCPEnvironment) -> MCPTool`
  - `enum GetDashboardDataTool`：`static func make(environment: MCPEnvironment) -> MCPTool`
  - `ToolCatalog.tools(environment:)` 定稿为 7 个

**`get_dashboard_data` 里没有一行统计逻辑**——全在 Task 2 的 `DashboardSummary` 里。这个 tool 只做「调一次 + 编码成 JSON + 写一句下一步」。**如果实现时发现要在这里算什么，说明该算的东西没放进 Core。**

**2026-08-07 复审补入（Task 2 改动带来的连带要求）：** `DashboardSummary` 多了 `undatedSessionCount` 与 `warnings`。`weekDone` 在有「读不出时间」的场次时会比用户实际练的次数少，App 首页会在四格里把这件事说出来（`TodayViewModel.weekTile`）。**这里必须同样说出来**：`Payload` 加一个 `undatedSessionCount: Int` 字段，`note` 末尾拼上 `summary.warnings.joined()`。只吐一个算少了的数字而不提一个字，就是铁律 7 的静默失败。下面的 `Payload` 与 `note` 代码块已按此写，测试也要补一条：造一条 `startedAt` 为空、id 也不带日期的 session，断言 `payload["undatedSessionCount"]?.intValue == 1` 且 `note` 里出现「读不出」与「下一步」。

**`transcriptTurns` 现在恒为 0**：逐字稿是 Phase 4 的事，`PracticeSession.transcript` 目前不会被填。字段先留着并如实返回 0，好过将来加字段改协议。

**2026-08-07 第二次复审补入（`list_practice_history` 的排序）：** 本任务原稿里的 `state.sessions.sorted { $0.startedAt > $1.startedAt }` **是错的，别照抄**。它在 MCP 层重写了一份比 Core 弱的规则：没有 `CoachTime.parseDayPrefix(session.id)` 兜底，而「`startedAt` 空着、日期只剩在 id 里」是真实存在的数据（`TrainingStats` 与 `SessionTimeline` 都按这种数据处理）。后果是用户刚练完的那场被排到列表最后，传了 `limit` 就直接从返回里消失，而同一份 state 交给 `get_dashboard_data` 又把它算进「本周训练」——两个工具对同一份数据给出互相矛盾的答案，用户没有任何办法判断哪个是真的。

修法：**规则加在 Core 里，两端共享**（Architecture 段的原则）。新增 `Sources/IELTSCoachCore/Stats/PracticeSessionOrder.swift`：

- `startDate(of:) -> Date?`：`CoachTime.parse(startedAt) ?? CoachTime.parseDayPrefix(id)`。`TrainingStats.compute` 与 `SessionTimeline.build` 里原来各写一遍的那两行同时改成调它，全项目只留一份。
- `newestFirst(_:) -> (ordered: [PracticeSession], undatedIDs: [String])`：按时间倒序，同一时刻按 id 倒序（与 `SessionTimeline` 同一条 tie-break，Swift 的 `sorted` 不保证稳定）；两处都读不出时间的场次**不许丢**，排在最后并由 `undatedIDs` 列出来。

`list_practice_history` 的 payload 因此多两个字段：行内 `startTimeUnreadable: Bool`、顶层 `undatedSessionCount: Int`，且 `undatedSessionCount > 0` 时 `note` 必须说清是哪几个 id、补哪个字段能修好（铁律 7）。测试见 Step 1。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachMCPTests/HistoryToolsTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class HistoryToolsTests: XCTestCase {
    private var directory: DataDirectory!
    private var harness: ServerHarness!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        harness = ServerHarness(environment: makeEnvironment(directory: directory,
                                                             opener: FakeDashboardOpener()))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, question: String, startedAt: String,
                         reportPath: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1, startedAt: startedAt,
                        endedAt: startedAt, goal: "", transcript: [],
                        reportPath: reportPath, recordingPath: "")
    }

    // MARK: - list_practice_history

    func testEmptyHistoryExplainsHowToGetStarted() throws {
        let payload = try harness.callToolJSON("list_practice_history")
        XCTAssertEqual(payload["total"]?.intValue, 0)
        XCTAssertEqual(payload["sessions"]?.arrayValue?.count, 0)
        XCTAssertTrue((payload["note"]?.stringValue ?? "").contains("下一步"),
                      "空列表不能只回一个 0——用户不知道该干什么")
    }

    func testNewestFirstAndLimitApplies() throws {
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 1, topic: "Home", prompt: "Q1?")]
            state.sessions = [
                session("2026-08-01-001", question: "q1", startedAt: "2026-08-01T10:00:00Z"),
                session("2026-08-06-001", question: "q1", startedAt: "2026-08-06T10:00:00Z"),
                session("2026-08-03-001", question: "q1", startedAt: "2026-08-03T10:00:00Z")
            ]
        }
        let payload = try harness.callToolJSON("list_practice_history", ["limit": .number(2)])
        XCTAssertEqual(payload["total"]?.intValue, 3, "total 是全量，不是这次返回的条数")
        XCTAssertEqual(payload["returned"]?.intValue, 2)
        XCTAssertEqual(payload["sessions"]?.arrayValue?.compactMap { $0["sessionId"]?.stringValue },
                       ["2026-08-06-001", "2026-08-03-001"])
    }

    func testRowsCarryTheQuestionTextAndReportFlag() throws {
        try StateStore(directory: directory).mutate { state in
            state.questions = [Question(id: "q1", part: 2, topic: "Skills", prompt: "Describe a skill.")]
            state.sessions = [session("2026-08-06-001", question: "q1",
                                      startedAt: "2026-08-06T10:00:00Z",
                                      reportPath: "reports/2026-08-06-001.json")]
        }
        let row = try XCTUnwrap(try harness.callToolJSON("list_practice_history")["sessions"]?
            .arrayValue?.first)
        XCTAssertEqual(row["questionPrompt"]?.stringValue, "Describe a skill.")
        XCTAssertEqual(row["topic"]?.stringValue, "Skills")
        XCTAssertEqual(row["part"]?.intValue, 2)
        XCTAssertEqual(row["hasReport"], JSONValue.bool(true))
        XCTAssertEqual(row["questionMissing"], JSONValue.bool(false))
        XCTAssertEqual(row["transcriptTurns"]?.intValue, 0, "逐字稿是 Phase 4 的事，现在如实报 0")
    }

    func testDeletedQuestionIsMarkedInsteadOfSilentlyBlank() throws {
        // 换季重新导入题库后，旧记录指向的题可能已经不在了。
        // 显示成空白会让用户以为记录坏了，必须明确标出来。
        try StateStore(directory: directory).mutate { state in
            state.sessions = [session("2026-08-06-001", question: "已经没了",
                                      startedAt: "2026-08-06T10:00:00Z")]
        }
        let row = try XCTUnwrap(try harness.callToolJSON("list_practice_history")["sessions"]?
            .arrayValue?.first)
        XCTAssertEqual(row["questionMissing"], JSONValue.bool(true))
        XCTAssertEqual(row["questionId"]?.stringValue, "已经没了")
    }

    func testOutOfRangeLimitIsRejectedInsteadOfClamped() throws {
        for bad in [JSONValue.number(0), .number(9999), .number(2.5), .string("10")] {
            let result = try harness.callTool("list_practice_history", ["limit": bad])
            XCTAssertTrue(result.isError, "limit=\(bad) 本该被拒绝")
            XCTAssertTrue(result.text.contains("下一步"))
        }
    }

    // MARK: - get_dashboard_data

    func testDashboardReportsCountsPlanAndTargets() throws {
        try StateStore(directory: directory).mutate { state in
            let questions = (1...14).map {
                Question(id: "q\($0)", part: 1, topic: "T", prompt: "P\($0)")
            }
            state.questions = questions
            state.plan = try! PlanBuilder.build(questions: questions, lengthDays: 7,
                                                createdAt: "2026-08-01T00:00:00Z")
            state.sessions = [session("2026-08-05-001", question: "q1",
                                      startedAt: "2026-08-05T12:00:00Z")]
            state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                        correction: "I really like it.", whyItMatters: "w",
                                        occurrences: 3, sourceSessionIds: ["s"], lastSeenAt: "t")]
            state.vocabulary = [VocabularyRecord(id: "v1", basicWord: "good",
                                                 betterExpression: "rewarding", collocation: "c",
                                                 priority: "high", sourceSessionIds: ["s"])]
            state.targets = [RetrainingTarget(targetKey: "logic-explain", label: "补例子",
                                              status: "new", evidence: ["I very like it."],
                                              sourceSessionId: "s", createdAt: "t")]
        }

        let payload = try harness.callToolJSON("get_dashboard_data")
        XCTAssertEqual(payload["questionTotal"]?.intValue, 14)
        XCTAssertEqual(payload["sessionTotal"]?.intValue, 1)
        XCTAssertEqual(payload["weekDone"]?.intValue, 1, "环境固定在 2026-08-06，这条属于同一周")
        XCTAssertEqual(payload["weekGoal"]?.intValue, 5)
        XCTAssertEqual(payload["issueTotal"]?.intValue, 1)
        XCTAssertEqual(payload["vocabularyTotal"]?.intValue, 1)
        XCTAssertEqual(payload["plan"]?["currentDay"]?.intValue, 1)
        XCTAssertEqual(payload["plan"]?["lengthDays"]?.intValue, 7)
        XCTAssertEqual(payload["todayQuestions"]?.arrayValue?.count, 2, "14 题分 7 天，每天 2 题")
        XCTAssertEqual(payload["todayQuestions"]?.arrayValue?.first?["prompt"]?.stringValue, "P1",
                       "计划里存的是题号，返回给模型的必须是能读的题干")
        XCTAssertEqual(payload["nextTargets"]?.arrayValue?.first?["label"]?.stringValue, "补例子")
        XCTAssertEqual(payload["topIssues"]?.arrayValue?.first?["occurrences"]?.intValue, 3)
    }

    func testDashboardOnAnEmptyWorkspaceTellsTheUserWhatToDoNext() throws {
        let payload = try harness.callToolJSON("get_dashboard_data")
        XCTAssertEqual(payload["questionTotal"]?.intValue, 0)
        XCTAssertEqual(payload["plan"], JSONValue.null)
        let note = try XCTUnwrap(payload["note"]?.stringValue)
        XCTAssertTrue(note.contains("下一步"))
        XCTAssertTrue(note.contains("题库"), "题库空是最需要先解决的事，note 要点出来")
    }

    func testDashboardTakesNoArgumentsAndIgnoresNone() throws {
        // 无参工具最容易被写成「随便传什么都当没看见」。这里确认它至少能被正常调用。
        XCTAssertNoThrow(try harness.callToolJSON("get_dashboard_data"))
    }
}
```

`Tests/IELTSCoachMCPTests/ToolCatalogTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

final class ToolCatalogTests: XCTestCase {
    private var directory: DataDirectory!
    private var tools: [MCPTool]!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        tools = ToolCatalog.tools(environment: makeEnvironment(directory: directory,
                                                               opener: FakeDashboardOpener()))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    func testExposesExactlyTheSevenToolsNamedInSpec() {
        // spec 第 4.4 节逐字列的就是这七个，顺序也照抄。
        // 多一个、少一个、改一个字，都是把上游协议改掉了。
        XCTAssertEqual(tools.map(\.name), [
            "initialize_ielts_workspace",
            "open_dashboard",
            "set_training_selection",
            "get_training_context",
            "save_session_review",
            "list_practice_history",
            "get_dashboard_data"
        ])
    }

    func testEveryToolHasAChineseDescriptionAndAnObjectSchema() {
        for tool in tools {
            let hasChinese = tool.description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            XCTAssertTrue(hasChinese, "\(tool.name) 的说明必须是中文——面向用户的文案一律中文")
            XCTAssertEqual(tool.inputSchema["type"]?.stringValue, "object",
                           "\(tool.name) 的 inputSchema 必须是 object")
            XCTAssertNotNil(tool.inputSchema["properties"]?.objectValue, "\(tool.name) 缺 properties")
        }
    }

    func testRequiredParametersAreDeclaredForTheToolsThatHaveThem() {
        func required(_ name: String) -> [String] {
            let tool = tools.first { $0.name == name }
            return (tool?.inputSchema["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        }
        // schema 里不写 required，模型就会以为参数可省，然后收到一条本可以避免的错误。
        XCTAssertEqual(required("set_training_selection"), ["questionId"])
        XCTAssertEqual(required("save_session_review"), ["reviewText"])
        XCTAssertEqual(required("get_dashboard_data"), [], "这个工具本来就不吃参数")
    }

    func testToolNamesAreUnique() {
        XCTAssertEqual(Set(tools.map(\.name)).count, tools.count,
                       "重名的工具后一个永远调不到——tools.first(where:) 只会命中前一个")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter HistoryToolsTests`
Expected: 编译失败 —— `ListPracticeHistoryTool` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachMCP/Tools/ListPracticeHistoryTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum ListPracticeHistoryTool {
    private struct Row: Encodable {
        let sessionId: String
        let questionId: String
        let questionPrompt: String
        let topic: String
        let part: Int
        let questionMissing: Bool
        let focusPart: String
        let startedAt: String
        let endedAt: String
        let goal: String
        let hasReport: Bool
        let reportPath: String
        let hasRecording: Bool
        let transcriptTurns: Int
        /// startedAt 与场次 id 里都读不出时间。这种行排在最后，位置不代表它有多新。
        let startTimeUnreadable: Bool
    }

    private struct Payload: Encodable {
        let total: Int
        let returned: Int
        /// 读不出练习时间、排不进时间轴的场次数（按全量算）。非 0 时 note 里必须解释。
        let undatedSessionCount: Int
        let sessions: [Row]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "list_practice_history",
            description: "列出已经存档的练习记录，从新到旧。每条含题目、Part、时间、是否已有复盘。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(200),
                        "description": .string("最多返回几条，默认 20。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let limit = try arguments.optionalInt("limit", in: 1...200, default: 20,
                hint: "limit 传 1–200 之间的整数；省略则返回最近 20 条。")
            let state = try environment.store.load()

            // 排序规则不在这里另写一份（原稿写的 `sorted { $0.startedAt > $1.startedAt }` 是错的，
            // 见本任务开头 2026-08-07 那段复审补入）。
            let ordering = PracticeSessionOrder.newestFirst(state.sessions)
            let undated = Set(ordering.undatedIDs)
            let rows = ordering.ordered.prefix(limit).map { session -> Row in
                let question = state.questions.first { $0.id == session.questionId }
                return Row(
                    sessionId: session.id,
                    questionId: session.questionId,
                    questionPrompt: question?.prompt ?? "",
                    topic: question?.topic ?? "",
                    part: question?.part ?? 0,
                    // 换季重新导入题库后旧记录可能指向已经不存在的题。
                    // 显示成空白会让用户以为记录坏了，必须明确标出来。
                    questionMissing: question == nil,
                    focusPart: session.focusPart.rawValue,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    goal: session.goal,
                    hasReport: !session.reportPath.isEmpty,
                    reportPath: session.reportPath,
                    hasRecording: !session.recordingPath.isEmpty,
                    // 逐字稿是 Phase 4 的事，现在恒为 0，如实返回。
                    transcriptTurns: session.transcript.count,
                    startTimeUnreadable: undated.contains(session.id))
            }

            var note = state.sessions.isEmpty
                ? "还没有任何练习记录。下一步：用 set_training_selection 选题、"
                    + "get_training_context 取考官提示词，练完把复盘交给 save_session_review。"
                : "按练习开始时间从新到旧排列（startedAt 空着时退回按场次 id 里的日期算）。"
                    + "下一步：想看某一场的完整复盘，"
                    + "打开对应的 reportPath 文件，或用 open_dashboard 打开复盘报告页。"
            if !ordering.undatedIDs.isEmpty {
                // 顺序对这几条是不可信的，不说等于给了一个用户无法核对的列表（铁律 6、7）。
                let sample = ordering.undatedIDs.prefix(3).joined(separator: "、")
                note += "另有 \(ordering.undatedIDs.count) 场练习读不出练习时间"
                    + "（startedAt 空着或写坏了，场次 id 也不以 YYYY-MM-DD 开头），"
                    + "它们排在列表最后、行内 startTimeUnreadable 为 true，"
                    + "传了 limit 时可能根本没出现在这次返回里。"
                    + "下一步：打开数据目录里的 state.json，在 sessions 里找到这几个 id：\(sample)，"
                    + "把 startedAt 补成练习当天的时间戳（形如 2026-08-05T10:00:00Z），"
                    + "补上它们就会回到正确的位置。"
            }

            return try ToolJSON.text(Payload(
                total: state.sessions.count,
                returned: rows.count,
                undatedSessionCount: ordering.undatedIDs.count,
                sessions: Array(rows),
                note: note))
        }
    }
}
```

`Sources/IELTSCoachMCP/Tools/GetDashboardDataTool.swift`：

```swift
import Foundation
import IELTSCoachCore

enum GetDashboardDataTool {
    private struct QuestionBrief: Encodable {
        let id: String
        let part: Int
        let topic: String
        let prompt: String
    }

    private struct IssueBrief: Encodable {
        let learnerSaid: String
        let correction: String
        let occurrences: Int
        let lastSeenAt: String
    }

    private struct TargetBrief: Encodable {
        let id: String
        let label: String
        let status: String
        let evidence: [String]
    }

    private struct PlanBrief: Encodable {
        let lengthDays: Int
        let completedDays: Int
        let currentDay: Int?
    }

    private struct Payload: Encodable {
        let learnerName: String
        let dataDirectory: String
        let questionTotal: Int
        let questionPracticed: Int
        let sessionTotal: Int
        let weekDone: Int
        let weekGoal: Int
        /// 读不出练习时间、因此没算进 weekDone 的场次数。非 0 时 note 里必须解释。
        let undatedSessionCount: Int
        let issueTotal: Int
        let vocabularyTotal: Int
        let plan: PlanBrief?
        let todayQuestions: [QuestionBrief]
        let topIssues: [IssueBrief]
        let nextTargets: [TargetBrief]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "get_dashboard_data",
            description: "取训练总览：题库与练习数量、本周进度、计划走到第几天、"
                + "今天该练的题、反复出现的错题、下次的复训目标。不需要参数。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        ) { _ in
            let state = try environment.store.load()
            // 统计逻辑一行都不在这里——全在 Core 的 DashboardSummary，
            // Phase 7 的首页会用同一套。这里只做「调一次 + 编码 + 写一句下一步」。
            let summary = DashboardSummary.build(state: state, now: environment.now())

            let todayQuestions = (summary.plan?.todayQuestionIds ?? []).compactMap { id in
                state.questions.first { $0.id == id }
            }.map { QuestionBrief(id: $0.id, part: $0.part, topic: $0.topic, prompt: $0.prompt) }

            var note: String
            if summary.questionTotal == 0 {
                note = "题库还是空的，现在还没法开练。下一步：在 App 的「训练题库」页导入题库文件，"
                    + "或在终端运行 coach questions import <文件>。"
            } else if summary.plan == nil {
                note = "还没有学习计划。下一步：可以直接用 set_training_selection 挑一道题开练。"
            } else {
                note = "下一步：用 set_training_selection 选定 todayQuestions 里的一道题，"
                    + "再用 get_training_context 取考官提示词。"
            }
            // 本周次数可能算少了。少了就必须说，且要说下一步怎么补（铁律 6、7）。
            note += summary.warnings.joined()

            return try ToolJSON.text(Payload(
                learnerName: state.learner.displayName,
                dataDirectory: environment.directory.root.path,
                questionTotal: summary.questionTotal,
                questionPracticed: summary.questionPracticed,
                sessionTotal: summary.sessionTotal,
                weekDone: summary.weekDone,
                weekGoal: summary.weekGoal,
                undatedSessionCount: summary.undatedSessionCount,
                issueTotal: summary.issueTotal,
                vocabularyTotal: summary.vocabularyTotal,
                plan: summary.plan.map { PlanBrief(lengthDays: $0.lengthDays,
                                                   completedDays: $0.completedDays,
                                                   currentDay: $0.currentDay) },
                todayQuestions: todayQuestions,
                topIssues: summary.topIssues.map {
                    IssueBrief(learnerSaid: $0.learnerSaid, correction: $0.correction,
                               occurrences: $0.occurrences, lastSeenAt: $0.lastSeenAt)
                },
                nextTargets: summary.nextTargets.map {
                    TargetBrief(id: $0.targetKey, label: $0.label, status: $0.status,
                                evidence: $0.evidence)
                },
                note: note))
        }
    }
}
```

`ToolCatalog.tools` 定稿：

```swift
    public static func tools(environment: MCPEnvironment) -> [MCPTool] {
        // 名字与顺序照抄 spec 第 4.4 节，一个字都不能改。
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment),
            SetTrainingSelectionTool.make(environment: environment),
            GetTrainingContextTool.make(environment: environment),
            SaveSessionReviewTool.make(environment: environment),
            ListPracticeHistoryTool.make(environment: environment),
            GetDashboardDataTool.make(environment: environment)
        ]
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter HistoryToolsTests`
Expected: PASS（13 个测试）

Run: `swift test --filter ToolCatalogTests`
Expected: PASS（4 个测试）

Run: `swift test --filter PracticeSessionOrderTests`
Expected: PASS（5 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证**

| 把这一行改成 | 哪条测试必须变红 |
|---|---|
| `PracticeSessionOrder.newestFirst(state.sessions)` 退回 `sorted { $0.startedAt > $1.startedAt }` | `testSessionWhoseTimeOnlyLivesInItsIDIsStillSortedNewestFirst` |
| `PracticeSessionOrder.startDate` 去掉 `?? CoachTime.parseDayPrefix(id)` | `PracticeSessionOrderTests`、`TrainingStatsTests`、`SessionTimelineTests`、`DashboardSummaryTests`、`HistoryToolsTests` 一起红（证明兜底确实只有一份） |
| `startTimeUnreadable` / `undatedSessionCount` / note 里那段警告一起去掉（排序仍正确） | `testSessionWithNoReadableTimeIsListedLastAndFlagged` |
| `questionMissing: question == nil` 改成 `questionMissing: false` | `testDeletedQuestionIsMarkedInsteadOfSilentlyBlank` |
| `hasReport` / `hasRecording` 恒 true、`reportPath` / `focusPart` / `endedAt` / `goal` 恒空 | `testRowsCarryTheQuestionTextAndReportFlag`、`testSessionWithoutAReportIsNotReportedAsReviewed` |
| 删掉 note 里空历史那个三元分支，只留非空分支 | `testEmptyHistoryExplainsHowToGetStarted` |
| 从 `ToolCatalog.tools` 里删掉 `GetDashboardDataTool.make(...)` 那一行 | `testExposesExactlyTheSevenToolsNamedInSpec`、`testRequiredParametersAreDeclaredForTheToolsThatHaveThem` |

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Stats/PracticeSessionOrder.swift Sources/IELTSCoachCore/Stats/TrainingStats.swift Sources/IELTSCoachCore/Stats/SessionTimeline.swift Sources/IELTSCoachMCP/Tools/ListPracticeHistoryTool.swift Sources/IELTSCoachMCP/Tools/GetDashboardDataTool.swift Sources/IELTSCoachMCP/ToolCatalog.swift Tests/IELTSCoachCoreTests/PracticeSessionOrderTests.swift Tests/IELTSCoachMCPTests/HistoryToolsTests.swift Tests/IELTSCoachMCPTests/ToolCatalogTests.swift
git commit -m "feat(mcp): list_practice_history、get_dashboard_data 与七个工具定稿"
```

---

## Task 10: 可执行文件与 stdio 冒烟测试

**Files:**
- Modify: `Sources/ielts-speaking-mcp/main.swift`
- Create: `scripts/mcp-smoke.sh`

**Interfaces:**
- Consumes: `MCPServer`、`ToolCatalog.tools(environment:)`、`MCPEnvironment`、`DashboardOpening`、`DashboardOpenError`、`DataDirectory.resolve()`
- Produces: 可执行文件 `.build/debug/ielts-speaking-mcp`（与 release 版）、`scripts/mcp-smoke.sh`

**这一步的三个坑，每个都会让「单元测试全绿但真机上完全不能用」：**

| 坑 | 后果 |
|---|---|
| 往 stdout 打了一行日志 | 客户端解析失败，连接当场断掉。**stdout 只许出现协议消息，所有日志走 stderr** |
| stdout 是块缓冲（管道下不是行缓冲） | 响应堆在缓冲区里发不出去，客户端一直等 → 违反「禁止无限等待」。用 `FileHandle.standardOutput.write` 绕开整个缓冲问题 |
| 读到 EOF 不退出 | 客户端关闭后进程留着不走 |

- [ ] **Step 1: 实现可执行文件**

`Sources/ielts-speaking-mcp/main.swift`：

```swift
import AppKit
import Foundation
import IELTSCoachCore
import IELTSCoachMCP

/// 唤起 App 的生产实现。**放在可执行文件里而不是库里**，
/// 这样 IELTSCoachMCP 库只依赖 Foundation + Core，测试能在没有图形环境的地方跑。
/// 实现方式由 spec 4.4 钉死：NSWorkspace.open(URL(string: "ieltscoach://…"))。
struct WorkspaceDashboardOpener: DashboardOpening {
    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw DashboardOpenError(message:
                "系统没能打开 \(url.absoluteString)，通常是因为 IELTS Speaking Coach 还没被系统登记。"
                + "下一步：先运行 scripts/build-app.sh 生成 .app，"
                + "把它拖进「应用程序」并手动双击打开一次——"
                + "系统只有在应用被打开过之后才会登记 ieltscoach:// 这个链接。")
        }
    }
}

let directory = DataDirectory.resolve()
let environment = MCPEnvironment(directory: directory, opener: WorkspaceDashboardOpener())
let server = MCPServer(tools: ToolCatalog.tools(environment: environment))

let standardOutput = FileHandle.standardOutput
let standardError = FileHandle.standardError

/// 日志一律走 stderr。**往 stdout 打一行中文就会让客户端解析失败、连接当场断掉。**
func log(_ message: String) {
    standardError.write(Data("\(message)\n".utf8))
}

log("ielts-speaking-mcp \(MCPServer.serverVersion) 已启动。数据目录：\(directory.root.path)")

// 用 FileHandle 直接写而不是 print：print 走的是 C 的 stdout，
// 在管道下是块缓冲，响应会堆在缓冲区里发不出去，客户端一直等（禁止无限等待）。
// FileHandle.write 是无缓冲的 write(2)，不存在这个问题。
while let line = readLine(strippingNewline: true) {
    guard let response = server.handle(line: line) else { continue }
    standardOutput.write(Data((response + "\n").utf8))
}

// readLine 返回 nil 即 stdin 已关闭：客户端退出了，我们也退出。
log("stdin 已关闭，ielts-speaking-mcp 退出。")
```

- [ ] **Step 2: 写冒烟脚本**

`scripts/mcp-smoke.sh`（需 `chmod +x`）：

```bash
#!/bin/bash
set -euo pipefail

# MCP stdio 冒烟测试：把几条真实消息喂给真实的可执行文件。
#
# 单元测试测的是 MCPServer.handle(line:)；这里测的是单元测试碰不到的那几段——
# 进程真的起得来、真的从 stdin 读、真的往 stdout 写、坏消息之后还活着、
# stdout 里没有混进日志。对译上游 mcp/test-client.mjs（spec 第 8 节）。
#
# 数据目录指向临时目录：**绝不动用户真实的训练记录。**

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/debug/ielts-speaking-mcp"

echo "▶︎ 编译…"
swift build --product ielts-speaking-mcp

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export IELTS_SPEAKING_DATA_DIR="$WORK/data"

cat > "$WORK/in.jsonl" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"initialize_ielts_workspace","arguments":{}}}
{"jsonrpc":"2.0","id":5,"method":"resources/list"}
JSONL

echo "▶︎ 喂给 $BIN …"
"$BIN" < "$WORK/in.jsonl" > "$WORK/out.jsonl" 2> "$WORK/err.log"

fail() { echo "❌ $1"; echo "--- stdout ---"; cat "$WORK/out.jsonl"; echo "--- stderr ---"; cat "$WORK/err.log"; exit 1; }

# 6 条输入里有 1 条是通知（不该有响应），所以应当正好 5 行。
lines=$(wc -l < "$WORK/out.jsonl" | tr -d ' ')
[ "$lines" = "5" ] || fail "期望 5 行响应（通知不回），实际 $lines 行"

for tool in initialize_ielts_workspace open_dashboard set_training_selection \
            get_training_context save_session_review list_practice_history get_dashboard_data; do
    grep -q "\"$tool\"" "$WORK/out.jsonl" || fail "tools/list 的结果里没有 $tool"
done

grep -q -- '-32700' "$WORK/out.jsonl" || fail "半截 JSON 没有换来 -32700 解析错误"
grep -q -- '-32601' "$WORK/out.jsonl" || fail "未知方法 resources/list 没有换来 -32601"
[ -f "$WORK/data/state.json" ] || fail "initialize_ielts_workspace 没有把 state.json 建出来"

# stdout 里不许混进任何不是 JSON 的行——混进一行日志，客户端就废了。
if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r line; do
        printf '%s' "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' \
            >/dev/null 2>&1 || fail "stdout 里有不是 JSON 的行：$line"
    done < "$WORK/out.jsonl"
else
    echo "ℹ️  本机没有 python3，跳过「每行都是合法 JSON」这一项逐行校验。"
    echo "   下一步：想补上这项检查，装好 Xcode 命令行工具后重跑本脚本。"
fi

# 日志必须走 stderr，而且**启动那一行**必须真的有。
# 认准启动行自己的特征，不要只 grep 可执行文件名：退出日志「stdin 已关闭，ielts-speaking-mcp 退出。」
# 里也有那个名字，只 grep 名字的话，把启动日志整行删掉这条断言照样是绿的（半空转）。
startup_log="$(grep '已启动' "$WORK/err.log" || true)"
[ -n "$startup_log" ] || fail "stderr 里没有启动日志（找不到含「已启动」的那一行）"

# 版本号：不写死具体版本，只要求形如 x.y.z。
printf '%s' "$startup_log" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' || fail "启动日志里没有版本号：$startup_log"

# 数据目录：写错目录（比如没读环境变量、回退到用户真实的 Application Support）时，
# 这一行是唯一能看出来的线索，所以必须校验它等于本次真正生效的目录。
printf '%s' "$startup_log" | grep -qF "$IELTS_SPEAKING_DATA_DIR" \
    || fail "启动日志里的数据目录不是本次指定的 $IELTS_SPEAKING_DATA_DIR：$startup_log"

echo "✅ MCP stdio 冒烟测试通过：5 条响应、7 个工具齐全、坏消息之后仍存活、stdout 干净。"
```

- [ ] **Step 3: 验证**

Run: `chmod +x scripts/mcp-smoke.sh && ./scripts/mcp-smoke.sh`
Expected: 打印 `✅ MCP stdio 冒烟测试通过…`

Run: `swift test`
Expected: 全绿

- [ ] **Step 4: 突变验证**

| 把这一行改成 | 会怎样 |
|---|---|
| `main.swift` 里的 `log(...)` 改成 `print(...)`（即写到 stdout） | `mcp-smoke.sh` 的「每行都是合法 JSON」或「5 行响应」检查必须失败。**这一条是本任务的核心**——真机上它的症状是「Codex 说服务器有问题」，而单元测试全绿 |
| `while let line = readLine(...)` 改成 `while true { guard let line = readLine(...) else { continue } … }` | 脚本会挂住（EOF 后不退出）。**挂住超过 30 秒就手动中断，这算突变生效**，把现象写进报告 |
| 把 `log("ielts-speaking-mcp … 已启动。数据目录：…")` 整行注释掉 | 「启动日志」这一条必须失败。**只 grep `ielts-speaking-mcp` 是抓不住的**——退出日志里也有这个名字，那样断言就是半空转 |
| 启动日志里去掉 `MCPServer.serverVersion` | 「版本号」那一条必须失败 |
| 启动日志里把 `directory.root.path` 换成写死的路径 | 「数据目录」那一条必须失败 |

- [ ] **Step 5: 提交**

```bash
git add Sources/ielts-speaking-mcp/main.swift scripts/mcp-smoke.sh
git commit -m "feat(mcp): stdio 可执行文件与冒烟测试脚本"
```

---

## Task 11: App 侧接住 `ieltscoach://`

> **本任务依赖 Phase 3 已完成**（需要 `SidebarItem`、`RootView`、设计令牌）。Phase 3 若还没收尾，先做 Task 12，回头再补这一条。

**Files:**
- Create: `Sources/IELTSCoachUI/DeepLink.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `scripts/build-app.sh`
- Create: `Tests/IELTSCoachUITests/DeepLinkTests.swift`

**Interfaces:**
- Consumes: `CoachRoute`（`scheme`、`parse(_:)`）、`SidebarItem`（Phase 3）、`Palette` / `Spacing` / `Radius`（Phase 3）
- Produces:
  - `public extension SidebarItem { init(route: CoachRoute) }`
  - `public enum DeepLinkResolution: Equatable, Sendable { case open(SidebarItem); case rejected(String) }`
  - `public enum DeepLinkResolver { static func resolve(_ url: URL) -> DeepLinkResolution }`
  - `.app` 的 Info.plist 里出现 `CFBundleURLTypes`，scheme 为 `ieltscoach`

**两半都得有，缺一半 `open_dashboard` 就是死的：**

1. **系统那一半**：Info.plist 里的 `CFBundleURLTypes` 告诉 LaunchServices「`ieltscoach://` 归我管」。**没有它，`NSWorkspace.open` 只会返回 false**，而且系统不给任何提示。
2. **App 那一半**：`.onOpenURL` 收到链接后跳到对应页面。

**签名要重新验一次。** 改 Info.plist 会让签名重新封一遍，但**指定要求（designated requirement）不该变**——它绑的是「标识 + 证书」，不是文件内容。这条必须实测确认，否则用户的辅助功能授权会失效，而那是 Phase 3 花了大力气才稳住的（成品标准第 9 条）。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/DeepLinkTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class DeepLinkTests: XCTestCase {
    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testDashboardOpensTheTodayPage() throws {
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://dashboard")), .open(.today))
    }

    func testEveryRouteLandsOnSomePage() throws {
        // 路由表在 Core、页面枚举在 UI，两边靠这条测试对齐。
        // 少映射一个，用户点开链接就会停在原地，而且没有任何提示。
        for route in CoachRoute.allCases {
            let resolution = DeepLinkResolver.resolve(route.url)
            guard case .open = resolution else {
                return XCTFail("\(route.rawValue) 没有对应的页面：\(resolution)")
            }
        }
    }

    func testRoutesMapToTheExpectedPages() throws {
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://questions")), .open(.questionBank))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://reviews")), .open(.reviewReports))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://history")), .open(.history))
        XCTAssertEqual(DeepLinkResolver.resolve(try url("ieltscoach://vocabulary")), .open(.vocabulary))
    }

    func testUnknownPageIsRejectedWithAnActionableChineseMessage() throws {
        guard case .rejected(let message) = DeepLinkResolver.resolve(try url("ieltscoach://nope")) else {
            return XCTFail("不认识的页面必须被拒绝，而不是默默跳到首页")
        }
        XCTAssertTrue(message.contains("nope"))
        XCTAssertTrue(message.contains("dashboard"), "要把可用的页面名列出来")
        XCTAssertTrue(message.contains("下一步"))
    }

    func testOtherSchemesAreRejected() throws {
        guard case .rejected(let message) = DeepLinkResolver.resolve(try url("https://history")) else {
            return XCTFail("只认 ieltscoach:// —— 别的 scheme 一律拒绝")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testUnimplementedPagesStillOpenBecauseThePlaceholderExplainsItself() throws {
        // 还没做完的页面也要能跳过去：看到的是占位页，而占位页写明了
        // 「还没做、将来会有什么」——这比点了链接毫无反应强得多。
        //
        // ⚠️ 2026-08-06 跨阶段复审：初稿这里写的是
        //     XCTAssertFalse(SidebarItem.history.isImplemented)
        // 那条断言在 Phase 4（训练记录页）交付之后必然变红，而且红得毫无道理——
        // 它其实是在断言「某个页面还没做」，那不是深链接该管的事。
        // 现在改成断言真正要保证的东西：**没做完的页面也解析得出来，不会被拒绝。**
        for route in CoachRoute.allCases {
            let item = SidebarItem(route: route)
            XCTAssertEqual(DeepLinkResolver.resolve(route.url), .open(item),
                           "\(route.rawValue) 无论做没做完都必须能跳过去")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DeepLinkTests`
Expected: 编译失败 —— `DeepLinkResolver` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/DeepLink.swift`：

```swift
import Foundation
import IELTSCoachCore

public enum DeepLinkResolution: Equatable, Sendable {
    case open(SidebarItem)
    /// 无法处理的链接。文案必须说清「发生了什么」与「下一步做什么」——
    /// 点了链接、窗口跳出来却毫无反应，用户只会以为程序坏了。
    case rejected(String)
}

public enum DeepLinkResolver {
    public static func resolve(_ url: URL) -> DeepLinkResolution {
        guard url.scheme?.lowercased() == CoachRoute.scheme else {
            return .rejected("这个链接不是本应用能打开的：\(url.absoluteString)。"
                + "下一步：本应用只认 \(CoachRoute.scheme):// 开头的链接，"
                + "例如 \(CoachRoute.dashboard.url.absoluteString)。")
        }
        guard let route = CoachRoute.parse(url) else {
            let page = url.host(percentEncoded: false) ?? url.path
            return .rejected("链接里的页面名「\(page)」不认识。"
                + "下一步：改用这些之一——\(CoachRoute.allCases.map(\.rawValue).joined(separator: "、"))。")
        }
        return .open(SidebarItem(route: route))
    }
}
```

`Sources/IELTSCoachUI/Navigation.swift` 末尾追加：

```swift
extension SidebarItem {
    /// 深链接路由 → 侧边栏页面。switch 是穷尽的，
    /// 将来 CoachRoute 加了 case 而这里忘了映射，编译期就会红。
    public init(route: CoachRoute) {
        switch route {
        case .dashboard, .today: self = .today
        case .questions: self = .questionBank
        case .plan: self = .plan
        case .retraining: self = .retraining
        case .reviews: self = .reviewReports
        case .history: self = .history
        case .issues: self = .issues
        case .vocabulary: self = .vocabulary
        }
    }
}
```

`Sources/IELTSCoachUI/RootView.swift` 加一个状态与一个修饰器。**这段是粘合逻辑，照抄；横幅长什么样由实现者定（见下面的验收要求）。**

```swift
    @State private var deepLinkNotice: String?
```

> **⚠️ 先确认「当前选中哪一页」到底存在哪**（2026-08-06 跨阶段复审补注）。
> 本计划开头「本阶段假定 Phase 3 已产出的东西」里写的是
> `RootView` 内部有 `@State private var selection: SidebarItem = .today` —— 那是 **Phase 3 的形态**。
> **Phase 6 Task 10 把选中项搬进了 `AppState.navigation`**（`@Observable final class NavigationState`，
> 因为复训中心要能从「今日训练」页跨页跳过来）。
>
> 动手前跑一次 `grep -rn "class NavigationState" Sources/IELTSCoachUI/`：
>
> - **有输出**（Phase 6 已交付）→ 下面那段闭包里的 `selection = item` 必须写成
>   `app.navigation.selection = item`。写成局部 `@State`，深链接会去改一个根本没在驱动侧边栏的变量：
>   **窗口跳到前台、页面纹丝不动、没有任何报错**——正是本任务开头那句「缺一半就等于 `open_dashboard` 是死的」
> - **没有输出** → 按 Phase 3 的形态写局部 `@State selection`

在 `NavigationSplitView` 那一层（不是 detail 内部）挂上：

> **⚠️ 2026-08-07 复审更正：这句话说少了半句，照字面做会翻车。**
> 「不要挂在 detail 里」是对的，但 `NavigationSplitView` 所在的那个 `workspace`
> **本身就是 `RootRouter.screen` 的一条分支**：`AppState.isCheckingPermission` 初值是 `true`，
> 启动那一瞬间屏幕上是「正在检查运行环境…」（最长约十秒），`workspace` 整个不在视图树里。
> 而 App 没在跑时，`open_dashboard` 是先 `NSWorkspace.open` 把 App 拉起来再投链接——
> 正好投在这十秒中间，那时 `.onOpenURL` 还没注册，**而它不是队列，没有 handler 就直接丢**：
> 窗口跳到前台、页面纹丝不动、一句报错都没有（铁律 7）。环境检查没过时用户长期停在
> 授权引导页，那期间每一条链接都这么蒸发。
>
> **正确的层级是最外层那个身份稳定的容器（和 `.task` 同一层）**，那正是同一个文件里
> 「`.task` 必须挂在身份稳定的容器上」那条注释说的地方——`.onOpenURL` 是同一类东西。
> **横幅也要一起挪上去**：留在 `workspace` 里的话，用户停在授权引导页时 handler 跑了、
> 消息也存下了，屏幕上一个字都没有。`DeepLinkTests` 里
> `testTheAppReceivesDeepLinksOnEveryScreenNotOnlyInsideTheWorkspace` 钉着这两件事。

```swift
        .onOpenURL { url in
            switch DeepLinkResolver.resolve(url) {
            case .open(let item):
                // Phase 6 已交付时改成 app.navigation.selection = item（见上面那段补注）
                selection = item
                deepLinkNotice = nil
            case .rejected(let message):
                // 不能什么都不做——用户点了链接、窗口跳出来却毫无反应，
                // 只会以为程序坏了（禁止静默失败）。
                deepLinkNotice = message
            }
        }
```

**横幅的验收要求**（不给布局代码，理由见开头「关于本计划里 View 的写法」）：

- `deepLinkNotice` 非 nil 时，在内容区顶部显示一条横幅，显示这句中文全文，**不许截断**
- 用 `Palette.warning` 作为强调色、`Radius.card` 作为圆角、`Spacing.md` 作为内边距——**不得出现字面颜色、字号、圆角**
- 带一个关闭按钮，点了把 `deepLinkNotice` 置回 nil
- 用 SF Symbols 图标，不用 emoji
- 打开系统「减弱动态效果」时，横幅出现/消失不做动画

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DeepLinkTests`
Expected: PASS（6 个测试）

Run: `swift build`
Expected: 编译通过

- [ ] **Step 5: 在打包脚本里注册 URL scheme**

`scripts/build-app.sh` 的 Info.plist heredoc 里，在 `NSMicrophoneUsageDescription` 之后、`</dict>` 之前插入：

```xml
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.ielts.speakingcoach.deeplink</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>CFBundleURLSchemes</key>
            <array><string>ieltscoach</string></array>
        </dict>
    </array>
```

同时把版本号从 `0.3.0` 改成 `0.9.0`：

```xml
    <key>CFBundleShortVersionString</key><string>0.9.0</string>
```

并在 `plutil -lint` 那一段之后追加一条**针对性**校验（`-lint` 只管 plist 合不合法，管不了这个键在不在）：

```bash
# 光校验 plist 合法没用：少了 CFBundleURLTypes，plist 依然合法，
# 而 open_dashboard 会静默失效——NSWorkspace.open 返回 false，系统一句话都不说。
registered_scheme="$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw \
    "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$registered_scheme" != "ieltscoach" ]; then
    echo "❌ Info.plist 里没有正确注册 ieltscoach:// 这个 URL scheme（读到的是「$registered_scheme」）。"
    echo "   下一步：检查 build-app.sh 里 CFBundleURLTypes 那一段是否完整。"
    echo "   不修的话，MCP 的 open_dashboard 会永远打不开窗口，而且不报错。"
    exit 1
fi
```

- [ ] **Step 6: 验证打包与签名稳定性**

Run: `./scripts/build-app.sh`
Expected: 打印 `✅ 已生成 …`，且没有触发上面那条 scheme 校验的报错

Run: `plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"`
Expected: 打印 `ieltscoach`

Run: `./scripts/build-app.sh && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated`
Expected: **与 Phase 3 记录的 designated 完全一致**（形如 `identifier com.ielts.speakingcoach and certificate leaf = H"4bffcd37…"`）。**不一致就立刻停下报告**——那意味着改 Info.plist 动摇了签名稳定性，用户的辅助功能授权会失效（成品标准第 9 条）。

- [ ] **Step 7: 提交**

```bash
git add Sources/IELTSCoachUI/DeepLink.swift Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/RootView.swift scripts/build-app.sh Tests/IELTSCoachUITests/DeepLinkTests.swift
git commit -m "feat(app): 注册并处理 ieltscoach:// 深链接"
```

---

## Task 12: Codex 插件配置与安装脚本

**Files:**
- Create: `codex/ielts-speaking-mcp.toml`
- Create: `scripts/install-codex-plugin.sh`

**Interfaces:**
- Consumes: `.build/release/ielts-speaking-mcp`
- Produces: `~/.local/bin/ielts-speaking-mcp`（安装后）、一段可粘贴进 `~/.codex/config.toml` 的配置

**⚠️ 这个任务里有一条我没能在本机验证的事实：** Codex CLI 的 MCP 配置写在 `~/.codex/config.toml`，形如 `[mcp_servers.<名字>]` + `command` / `args` / `env`。**这一条以及 `codex mcp` 子命令是否存在，都必须在 Task 13 的第一步先用 `codex mcp --help`（或官方文档）核实。** 若键名不同，改 `codex/ielts-speaking-mcp.toml` 与脚本里的模板即可，其余任务不受影响。

**脚本绝不擅自改用户的配置文件。** 默认只编译、安装二进制、把该粘的内容打印出来；只有显式加 `--write` 才动 `~/.codex/config.toml`，而且要先备份、发现同名段落就拒绝并说明原因。

- [ ] **Step 1: 写配置片段**

`codex/ielts-speaking-mcp.toml`：

```toml
# IELTS Speaking Coach 的本机 MCP server。
# 把这一段追加到 ~/.codex/config.toml（用 scripts/install-codex-plugin.sh 可以自动生成带绝对路径的版本）。
#
# 为什么必须写绝对路径：Codex 启动 MCP server 时不保证继承你 shell 里的 PATH，
# 写成 ielts-speaking-mcp 很可能报「找不到命令」，而那条报错出现在 Codex 的日志里、不在终端上。

[mcp_servers.ielts_speaking]
command = "/Users/你的用户名/.local/bin/ielts-speaking-mcp"
args = []

# 可选：把训练数据指到别的目录。默认是 ~/Library/Application Support/IELTS Speaking Coach。
# 拿它做试验时很有用——试完删掉这一段就回到真实数据。
# [mcp_servers.ielts_speaking.env]
# IELTS_SPEAKING_DATA_DIR = "/Users/你的用户名/tmp/ielts-mcp-试验"
```

- [ ] **Step 2: 写安装脚本**

`scripts/install-codex-plugin.sh`（需 `chmod +x`）：

```bash
#!/bin/bash
set -euo pipefail

# 编译 ielts-speaking-mcp、装到 ~/.local/bin，并给出 Codex 配置。
#
# 默认只打印配置，不动你的 ~/.codex/config.toml。
# 想让脚本直接写进去，加 --write（会先备份，且发现同名段落会拒绝覆盖）。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/ielts-speaking-mcp"
CONFIG="$HOME/.codex/config.toml"
SECTION="[mcp_servers.ielts_speaking]"
WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1

echo "▶︎ 编译 release 版…"
swift build -c release --product ielts-speaking-mcp

echo "▶︎ 安装到 $BIN …"
mkdir -p "$BIN_DIR"
cp "$ROOT/.build/release/ielts-speaking-mcp" "$BIN"
chmod +x "$BIN"

SNIPPET="$SECTION
command = \"$BIN\"
args = []"

if [ "$WRITE" -eq 0 ]; then
    cat <<EOF

✅ 已安装：$BIN

下一步：把下面这段追加到 $CONFIG

$SNIPPET

追加完之后，用 codex mcp list（若你的 Codex 版本有这个子命令）确认它出现在列表里；
或者直接在 Codex 里问一句「列出可用的工具」。
想让本脚本代劳，重新运行：./scripts/install-codex-plugin.sh --write
EOF
    exit 0
fi

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

if grep -qF "$SECTION" "$CONFIG"; then
    echo "ℹ️  $CONFIG 里已经有 $SECTION 段落了，本脚本不会去改它。"
    echo "   下一步：手动确认那一段的 command 指向 $BIN；若不是，自己改过来。"
    echo "   （不自动覆盖是刻意的：那是你的配置文件，里面可能还有别的服务器。）"
    exit 0
fi

BACKUP="$CONFIG.bak-$(date +%Y%m%d%H%M%S)"
cp "$CONFIG" "$BACKUP"
printf '\n%s\n' "$SNIPPET" >> "$CONFIG"

echo "✅ 已把配置追加到 $CONFIG"
echo "   原文件已备份为 $BACKUP"
echo "   下一步：重启 Codex，然后问它「列出可用的工具」，应当能看到 7 个 ielts 开头的工具。"
```

- [ ] **Step 3: 验证（不写配置那一条路径）**

Run: `chmod +x scripts/install-codex-plugin.sh && ./scripts/install-codex-plugin.sh`
Expected: 打印 `✅ 已安装：…/.local/bin/ielts-speaking-mcp` 与那段 TOML；**`~/.codex/config.toml` 没有被改动**

Run: `ls -l ~/.local/bin/ielts-speaking-mcp`
Expected: 文件存在且可执行

Run: `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' | IELTS_SPEAKING_DATA_DIR="$(mktemp -d)" ~/.local/bin/ielts-speaking-mcp`
Expected: 打印一行含 `"serverInfo"` 的 JSON。**这一步用临时数据目录，不碰真实训练记录。**

- [ ] **Step 4: 提交**

```bash
git add codex/ielts-speaking-mcp.toml scripts/install-codex-plugin.sh
git commit -m "feat(codex): MCP server 的安装脚本与插件配置"
```

---

## Task 13: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase9-acceptance.md`

前面所有测试证明的是「协议对、逻辑对」。**「能在 Codex 里调用这个工具」这件事只能由人来确认**，因为它取决于 Codex 版本的配置格式、LaunchServices 有没有登记 App，这两样都不接受推断（spec 2.5 确立的规则：涉及外部应用能力的判断，一律以在运行中的应用上实测为准）。

**先说清楚安全边界：** 本阶段的 7 个 tool 一行都不碰 ChatGPT（不依赖 `ChatGPTBridge`），所以下面任何一步都不会在你的 ChatGPT 账号里产生真实对话。唯一有副作用的是 `save_session_review`——**它会往档案里写东西，所以验收时先把数据目录指到临时目录**。

- [ ] **Step 1: 先核实 Codex 的配置格式（这条不确认，后面全白搭）**

```bash
codex --version
codex mcp --help 2>&1 | head -30
```

确认 MCP server 的配置键名。**本计划假定是 `~/.codex/config.toml` 里的 `[mcp_servers.<名字>]` + `command`/`args`/`env`。** 若实际不是这个形状，按实际的改 `codex/ielts-speaking-mcp.toml` 与 `scripts/install-codex-plugin.sh`，并把实际格式记进验收文档——**下一个读这份计划的人需要知道真相是什么**。

- [ ] **Step 2: 装好并接上**

```bash
cd ~/Projects/ielts-speaking-coach-mac
./scripts/mcp-smoke.sh                       # 先确认可执行文件本身没问题
./scripts/install-codex-plugin.sh            # 打印配置
```

把打印出的那段追加进 `~/.codex/config.toml`（或运行 `--write` 让脚本代劳），重启 Codex。

- [ ] **Step 3: 在 Codex 里逐个调用（只读的那五个，用真实数据）**

在 Codex 里依次要求它调用，并把每次的返回记下来：

| 工具 | 看什么 |
|---|---|
| `initialize_ielts_workspace` | 返回的 `dataDirectory` 是不是 `~/Library/Application Support/IELTS Speaking Coach`？各项数量对不对？ |
| `get_dashboard_data` | 题库总数、本周次数、计划天数与你在 App 里看到的一致吗？ |
| `list_practice_history` | 最近几场练习都在吗？顺序是从新到旧吗？ |
| `set_training_selection` | 传一个真实题号，然后打开 App 看「今日训练」页有没有反映出这次选择 |
| `get_training_context` | `examinerPrompt` 是不是完整的考官提示词？把它和 `coach practice` 发出去的那份对比一眼 |

**还要故意做错一次**：传一个不存在的题号给 `set_training_selection`。看 Codex 收到的错误是不是中文、说没说清下一步。**这一条对应成品标准第 8 条。**

- [ ] **Step 4: `open_dashboard`（这是本阶段最容易失败的一步）**

前提：`.app` 已经打包好、**并且手动双击打开过至少一次**（LaunchServices 只有这样才会登记 `ieltscoach://`）。

```bash
./scripts/build-app.sh
open ".build/IELTS Speaking Coach.app"       # 手动打开一次，让系统登记
```

然后在 Codex 里调用 `open_dashboard`，分别试 `dashboard` 与 `history`：

- 窗口有没有被带到前台？
- 侧边栏有没有跳到对应的页面？
- 试一个不存在的 section（比如 `nope`），Codex 收到的是不是「列出了可用页面名」的中文错误？
- 手动在终端跑 `open "ieltscoach://nope"`，App 里有没有弹出那条中文横幅？**这一条验的是「禁止静默失败」在深链接上的落实。**

**若窗口打不开**：先确认 `plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw ".build/IELTS Speaking Coach.app/Contents/Info.plist"` 打印的是 `ieltscoach`，再确认 App 至少被打开过一次。两者都对还不行的话，停下来报告，不要在代码里乱试。

- [ ] **Step 5: `save_session_review`（用临时数据目录，别弄脏真实档案）**

先把配置里的数据目录临时指到别处：

```toml
[mcp_servers.ielts_speaking.env]
IELTS_SPEAKING_DATA_DIR = "/Users/你的用户名/tmp/ielts-mcp-试验"
```

重启 Codex 后：

1. 让它调 `initialize_ielts_workspace`，再手动往那个临时目录导一份小题库（`IELTS_SPEAKING_DATA_DIR=... coach questions import <文件>`）
2. `set_training_selection` 选一题
3. 把一份**过去真实练习留下的复盘原文**（`~/Library/Application Support/IELTS Speaking Coach/pending-reviews/` 里就有）交给 `save_session_review`
4. 确认：`reports/` 里出现了文件、错题本与词汇本数字从 0 变正、返回里没有 `warning`
5. 再故意传一段不是复盘的文字，确认：**返回是中文错误、指出了原文落盘的位置、而且那个文件真的在**

做完把 `env` 那一段删掉、重启 Codex，确认数据目录回到真实位置。

- [ ] **Step 6: 记录并提交**

把每一步的实际结果写进 `docs/phase9-acceptance.md`，**包括不顺的部分**——「哪一步让我觉得麻烦」这类信息只有你有（成品标准第 5 节）。至少要回答：

- Codex 的配置格式与本计划的假定一致吗？不一致的话实际是什么？
- 7 个工具在 Codex 里是不是都能调通？
- 工具的中文说明，模型是不是真的照着用了（有没有出现「参数传错了才发现说明写得不清楚」的情况）？
- `open_dashboard` 唤起窗口用了多久？体验上像不像一回事？
- **你会用它吗？** 还是宁可直接开 App？

```bash
git add docs/phase9-acceptance.md
git commit -m "docs: Phase 9 真机验收结果"
```

---

## Phase 9 完成标准

- [ ] `swift test` 全绿
- [ ] `./scripts/mcp-smoke.sh` 通过（5 条响应、7 个工具齐全、坏消息之后仍存活、stdout 干净）
- [ ] **`tools/list` 返回的 7 个名字与 spec 4.4 逐字一致，顺序也一致**
- [ ] 畸形 JSON、未知方法、缺参数、非法 id、批量请求，各自返回符合 JSON-RPC 2.0 规范的错误，**且服务器仍然存活**
- [ ] 通知（无 id 的消息）一条响应都不产生
- [ ] 工具自身失败走 `result.isError` + 中文文案，不变成协议错误
- [ ] **每个 tool 都是对 Core 的薄封装**：提示词来自 `ExaminerPrompt` / `ReviewRequestPrompt`，归档走 `ReviewArchiver`，统计走 `DashboardSummary`，MCP 层没有第二份业务逻辑
- [ ] `save_session_review` 先落盘再解析；解析失败时原文仍在，且错误里给出了路径
- [ ] `save_session_review` 在「顶层键存在却一条都没归进去」时会报警，不谎称成功
- [ ] 全项目零第三方依赖（`Package.swift` 里 `dependencies` 仍为空）
- [ ] `.app` 的 Info.plist 注册了 `ieltscoach://`，且**连续两次打包的 designated requirement 完全一致**
- [ ] 从 Codex 里能调通 7 个工具，`open_dashboard` 能真的把 App 窗口带到前台并跳对页面
- [ ] 每个关键任务都做过突变验证，且把「改哪一行、哪条测试变红」的实际输出写进了报告

达成后进 Phase 10：图标、关于页、Hardened Runtime 与公证脚本。

## 与 ROADMAP 的差别

ROADMAP 把 Phase 9 描述成「协议明确、与 Core 共享逻辑，风险低」。实际拆下来多出两件 ROADMAP 没写的事，都不是可选项：

1. **`ieltscoach://` 的两半（Info.plist 注册 + App 内处理）Phase 3 一件都没做**，不补的话 `open_dashboard` 是死的。已列为 Task 11，并连带修改 Phase 3 的打包脚本。
2. **仪表盘聚合、会话编号、复盘落盘这些「Core 里本该有、其实没有」的东西**要先补齐（Task 1–3），否则 MCP 层会被迫自己写一份，直接违反「不要在 MCP 层重新实现业务逻辑」。

另外 ROADMAP 说的「风险低」只对协议层成立。真正的风险集中在两处外部事实上：**Codex 的配置格式**与 **LaunchServices 对 URL scheme 的登记**，两者都只能实测（Task 13 第 1、4 步）。

