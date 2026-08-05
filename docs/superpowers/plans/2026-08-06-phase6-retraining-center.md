# Phase 6：复训中心

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从复盘给出的目标里挑一个，回看当时到底说了什么，带着这个目标把原题重答一遍（开口前把范答撤掉），然后**换一道题再练一次**——分清是真会了，还是只记住了那个答案。

**Architecture:** 纯数据规则（复训台账、换题候选、结果判定）放 `IELTSCoachCore`，只依赖 Foundation，Phase 9 的 MCP server 将来可直接复用；视图模型与流程编排放 `IELTSCoachUI`；驱动 ChatGPT 的部分**一行不写**——复用 Phase 3 已经做好的 `PracticeRunner`，本阶段只通过一个窄协议 `PracticeSessionLauncher` 与它对接，因此全部测试都能用假实现跑完，不碰真的 ChatGPT。

**Tech Stack:** Swift 6.3.3（`swift-tools-version: 6.0`，Swift 6 语言模式）、SPM、SwiftUI、XCTest。无第三方依赖。

---

## Global Constraints

以下每一条都是硬性的，任何任务都不得违反：

- 最低系统版本 **macOS 14.0**
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它，改了用户就要重新授权
- **`IELTSCoachCore` 只允许依赖 Foundation。** 需要 AppKit / AVFoundation / PDFKit 的代码放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 `IELTSCoachCore`、`ChatGPTBridge`、`IELTSCoachAudio`（Phase 5 加的）、SwiftUI
- **所有面向用户的文案必须是中文，且同时说明「发生了什么」和「下一步做什么」。** 这条同时适用于错误、警告、空状态、按钮说明
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- **界面必须走设计令牌**（`Palette` / `Spacing` / `Radius`，见 `docs/superpowers/DESIGN-SYSTEM.md`）。视图里不得出现字面颜色值、字号、圆角
- 涉及外部应用能力的判断，**一律以在运行中的应用上实测为准**，不接受从二进制、框架清单、文档措辞推断出的结论
- **本阶段的所有单元测试都必须用假实现，不得驱动真实 ChatGPT**——那会在用户的账号里产生真实对话
- 测试框架用 XCTest

---

## 本阶段为什么存在

`DEFINITION-OF-DONE.md` 第 2 节「改进闭环」写得很清楚，这是**产品真正的价值所在**：

1. 复盘给出**一个**具体目标（是「回答后补一个原因和例子」这种能做到的行为，不是「提高词汇量」这种空话）
2. 点一下「带着这个目标重练」，同一道题再来一次
3. **再换一道题验证——是真会了，还是只记住了那个答案**
4. 在问题档案里看到这个毛病的出现次数有没有下降

第 3 步是本阶段的重心。**只重练原题是不够的**：同一道题第二次答得好，可能只是记住了上次复盘里的高分版。换一道题还能做到，才说明那个行为真的进了肌肉记忆。

第 4 步属于 Phase 7（问题档案与趋势），本阶段不做。

---

## 前置依赖（开工第一件事就是逐条确认）

本阶段依赖 Phase 3 与 Phase 4 的产出。**下面每一条都要在动手前用命令确认，确认不了就停下来报告，不要假装它存在、也不要顺手替别的阶段把活干了。**

| # | 依赖 | 来自 | 怎么确认 | 不满足怎么办 |
|---|---|---|---|---|
| P1 | `PracticeStage` / `PracticeRunner`（含 `start(setup:)`、`finishPractice()`、`stage`）| Phase 3 Task 9 | `ls Sources/IELTSCoachUI/Session/` | 停下来报告：Phase 6 的流程无处挂载 |
| P2 | **一场练习结束后，会有一条 `PracticeSession` 被写进 `state.sessions`** | Phase 4 | `grep -rn "upsertSession\|sessions.append" Sources/IELTSCoachUI/` | **停下来报告。** 这是 Phase 4 的交付内容，不是 Phase 6 的；没有训练记录，复训进度、换题验证都无从谈起 |
| P3 | `PracticeRunner` 能报出刚归档那条记录的 id | Phase 4 | `grep -n "finishedSessionID" Sources/IELTSCoachUI/Session/PracticeRunner.swift` | 见下方「P3 的补法」，只加 2 行，属于本阶段可以自己补的范围 |
| P4 | `PracticeSession.transcript` 里有内容（逐字稿）| Phase 4 | 练一场后看 `state.json` | **可降级**：Task 7 的证据装配在逐字稿为空时仍然可用，只是少一块内容，并会显示中文说明 |

> ### Phase 4 的实施计划已于 2026-08-06 写完，P2 / P3 / P4 都由它交付（复审补记）
>
> 见 `docs/superpowers/plans/2026-08-06-phase4-transcript-and-history.md`。开工时仍按上表实测确认，别只信这段话。三条的实际形状：
>
> - **P2**：`PracticeRunner.finishPractice()` 里按 id **upsert**（不是无脑 append）——所以 `grep sessions.append` 只会命中 `upsertSession` 内部那一行。Phase 9 的 `save_session_review` 用同样的规则，**不要一边 append 一边 upsert**
> - **P3**：`finishedSessionID` 已经有了，而且是**在归档成功之后**才赋值的，与下面「P3 的补法」那条要求一致。**补法不用做了**
> - **P4**：`transcript` 里有内容，`role` 取 `"user"` / `"assistant"` / **`"unknown"`**。第三种是 Phase 4 刻意留的：说话人判不出来时**记 `unknown`，绝不猜**。`RetrainingEvidenceBuilder` 里 `$0.role == "user"` 那个筛选照旧能用，`unknown` 会被自然跳过——**这是可接受的降级，不要改成把 `unknown` 也算成学员说的话**
>
> 另外：**给 `PracticeSession` 加 retraining 字段时，新参数必须带默认值**——`PracticeRunner.upsertSession` 与 `coach practice` 都在构造 `PracticeSession`，不带默认值这两处会编译不过。
| P5 | 设计令牌 `Palette`/`Spacing`/`Radius` 与组件 `CoachCard`/`PrimaryActionCard`/`SectionHeader`/`EmptyStateView` | Phase 3 Task 7 | `ls Sources/IELTSCoachUI/DesignSystem/` | 停下来报告 |
| P6 | `SidebarItem` 十项导航与 `AppState` | Phase 3 Task 3 | `ls Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/AppState.swift` | 停下来报告 |
| P7 | 复盘报告页（`ReviewReportViewModel`）| Phase 3 Task 5 | `ls Sources/IELTSCoachUI/Review/` | 停下来报告 |

### P3 的补法

若 `PracticeRunner` 没有 `finishedSessionID`，在 `Sources/IELTSCoachUI/Session/PracticeRunner.swift` 里加：

```swift
    /// 本次练习归档后写进 `state.sessions` 的那条记录的 id。未完成时为 nil。
    /// 复训要靠它把「这一场」和「哪个目标」挂上钩（Phase 6）。
    public private(set) var finishedSessionID: String?
```

并在 `finishPractice()` 内、**把 `PracticeSession` 写进 `state.sessions` 成功之后**赋值：

```swift
        finishedSessionID = sessionID
```

**不要在归档之前赋值。** 赋了就等于宣称「这一场已经记下来了」，而万一归档失败，复训台账会挂到一条根本不存在的记录上。

---

## 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略**（沿用 Phase 3 计划第 79–86 行的理由）。

布局是需要看着调的东西。把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务写明「必须显示什么、空状态说什么、失败时说什么、什么绝对不能出现在屏幕上」，具体怎么摆由实现者定，由 `DESIGN-SYSTEM.md` 的令牌与组件约束，再由 Task 11 的人工验收把关。

这与「禁止占位符」不冲突：占位符是「TBD、以后再说」，这里给的是明确到可以判定通过与否的验收标准。若某处要求不清楚到无法动手，**停下来问，不要猜**。

---

## 本阶段的四个设计决定（连同理由，实现时不要推翻）

### 决定 1：不修改 `ReviewRequestPrompt`

复训会话与普通练习的区别，**只体现在考官提示词里的单点目标**（`ExaminerPrompt` 已经支持：`SessionSetup.goal` 非空时会追加「本次唯一目标：…」一段）。复盘请求的提示词一个字都不改。

理由是 spec 2.3.8 那条血的教训：**指令规定到哪一层，ChatGPT 的输出就对齐到哪一层。** `ReviewRequestPrompt` 现在把八个顶层键与每一项内部的字段名全都写死了，`ReviewArchiver` 逐字对着它读。往里面加任何一句「请特别评价学员是否做到了 XX」，都可能让模型顺手改动输出形状，而这种失败**不报错、不崩溃，只是悄悄什么都没归档**——用户练了一整场，错题本纹丝不动。

复训是否奏效，靠**新复盘自己给出的 `priority_target.id`** 判断（Task 3），不需要改指令。

### 决定 2：撤掉的是「答案」，留下的是「目标」

三步流程里的「撤掉提示」，撤的是**原话证据、当时的原答、复盘给的高分版**；保留的是**单点目标那一行**。

理由：目标是**行为指令**（「回答后补一个原因和例子」），不是答案。对着高分版念一遍不叫复训；而知道自己这次要做到什么，才叫带着目标练。两者性质不同，不能一起撤。

### 决定 3：换题验证不再回看证据，且只在同一个 Part 内换题

- **不再回看证据**：正因为不给看，才知道是不是真会了。换题验证的运行（`RetrainingRun.transfer`）直接从第二步开始。
- **只在同一 Part 内换**：Part 1 要短、Part 3 要展开，同一个目标在两者里的达成标准根本不一样（见 `AnswerUpgradePolicy` 的分 Part 规则）。跨 Part 换题验证的不是同一件事。
- **同话题的题目仍然可以用，但要标出来**：同话题太接近原题，验证力度打折；不给用又会让题库小的用户直接卡死。

### 决定 4：不自动退休目标，一次没被点名也不说「已掌握」

`RetrainingPolicy` 的源码注释写着：「这只是**推荐**，不得据此强制学员下次必须练它」。同理，系统也不该替用户宣布「你已经改掉了」——**一次没被点名不等于改掉了**。

所以：

- 目标状态从 `new` → `selected`（用户点了「带着本题进入复训」）→ `retired`（**用户自己**点「这个问题我不用再练了」）
- 换题验证之后的结果文案只能说「这一次没有再被点名」，**不得出现「已掌握」「已改掉」「已解决」**
- 「毛病有没有真的变少」由 Phase 7 的问题档案按出现次数趋势回答，不由单场结论回答

这与 `DEFINITION-OF-DONE.md` 第 4 节「不预测雅思分数」是同一条原则：不给用户一个看起来精确、实则站不住的结论。

---

## File Structure

```
Sources/
├── IELTSCoachCore/
│   ├── Model/
│   │   ├── PracticeSession.swift          【改】加 retraining 字段
│   │   └── RetrainingLink.swift           【新】复训标记 + 派生的 original/transfer 判定
│   └── Policy/
│       ├── RetrainingPolicy.swift         不动（已实现）
│       ├── RetrainingLedger.swift         【新】复训台账：进度、挂钩、状态流转
│       ├── RetrainingOutcome.swift        【新】换题验证的结果判定
│       └── TransferQuestionPolicy.swift   【新】换题验证的候选题挑选
├── IELTSCoachUI/
│   ├── Navigation.swift                   【改】.retraining 标为已实现
│   ├── NavigationState.swift              【新】页面选中项 + 跨页跳转意图（可测）
│   ├── AppState.swift                     【改】持有 NavigationState
│   ├── RootView.swift                     【改】接上复训中心页
│   ├── Today/TodayView.swift              【改】「复训一个旧问题」跳到复训中心
│   ├── Session/PracticeRunner.swift       【可能改】补 finishedSessionID（见 P3）
│   └── Retraining/
│       ├── RetrainingStep.swift           【新】三步流程与「撤掉提示」的规则（可测）
│       ├── RetrainingCenterViewModel.swift【新】待复训列表（可测）
│       ├── RetrainingEvidence.swift       【新】证据装配：原话/原答/高分版/逐字稿（可测）
│       ├── RetrainingSetupBuilder.swift   【新】复训会话与普通练习的区分（可测）
│       ├── RetrainingCoordinator.swift    【新】跑完一场复训并挂上台账（可测）
│       ├── RetrainingOutcomeText.swift    【新】结果文案（可测）
│       ├── RetrainingCenterView.swift     【新】页面（人工验收）
│       └── RetrainingFlowView.swift       【新】三步流程页（人工验收）
Tests/
├── IELTSCoachCoreTests/
│   ├── RetrainingLinkTests.swift
│   ├── RetrainingLedgerTests.swift
│   ├── RetrainingOutcomeTests.swift
│   └── TransferQuestionPolicyTests.swift
└── IELTSCoachUITests/
    ├── RetrainingStepTests.swift
    ├── RetrainingCenterViewModelTests.swift
    ├── RetrainingEvidenceTests.swift
    ├── RetrainingSetupBuilderTests.swift
    ├── RetrainingCoordinatorTests.swift
    ├── RetrainingOutcomeTextTests.swift
    ├── NavigationStateTests.swift
    └── NavigationTests.swift              【改】把 .retraining 加进已实现集合
docs/
└── phase6-acceptance.md                   【新】Task 11 的人工验收记录
```

---

## 既有类型的真实签名（照抄自源码，不要凭记忆写）

实现时会用到这些，**签名以源码为准**，下面是 2026-08-06 读到的真实内容：

```swift
// Sources/IELTSCoachCore/Policy/RetrainingPolicy.swift
public enum RetrainingPolicy {
    public static func extractTarget(from report: JSONValue, sessionID: String,
                                     createdAt: String) -> RetrainingTarget?
    /// 排序：证据命中高频错题的目标排前面。已退休的目标不参与。
    public static func rank(targets: [RetrainingTarget], issues: [IssueRecord]) -> [RetrainingTarget]
}

// Sources/IELTSCoachCore/Model/Records.swift
public struct RetrainingTarget: Codable, Equatable, Sendable, Identifiable {
    public var targetKey: String        // JSON 里的键名仍是 "id"，与上游兼容
    public var label: String
    public var status: String           // "new" | "selected" | "retired"
    public var evidence: [String]
    public var sourceSessionId: String
    public var createdAt: String
    public init(targetKey: String, label: String, status: String, evidence: [String],
                sourceSessionId: String, createdAt: String)
    /// targetKey 跨 session 会重复，拼上 sourceSessionId 才真正唯一
    public var id: String { "\(targetKey)@\(sourceSessionId)" }
}
public struct IssueRecord: Codable, Equatable, Sendable, Identifiable {
    public var id, learnerSaid, correction, whyItMatters: String
    public var occurrences: Int
    public var sourceSessionIds: [String]
    public var lastSeenAt: String
    public init(id: String, learnerSaid: String, correction: String, whyItMatters: String,
                occurrences: Int, sourceSessionIds: [String], lastSeenAt: String)
}

// Sources/IELTSCoachCore/Model/PracticeSession.swift（本阶段 Task 1 会加一个字段）
public struct PracticeSession: Codable, Equatable, Sendable, Identifiable {
    public var id, questionId: String
    public var focusPart: FocusPart
    public var startedAt, endedAt, goal: String
    public var transcript: [TranscriptTurn]
    public var reportPath, recordingPath: String
    public struct TranscriptTurn: Codable, Equatable, Sendable {
        public var role: String        // "user" | "assistant"
        public var text: String
        public var capturedAt: String
        public init(role: String, text: String, capturedAt: String)
    }
}

// Sources/IELTSCoachCore/Model/Question.swift
public struct Question: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var part: Int                // 1 / 2 / 3
    public var topic, prompt: String
    public var followups: [String]
    public var source, sourceUrl, importLevel, status: String
    public init(id: String, part: Int, topic: String, prompt: String,
                followups: [String] = [], source: String = "", sourceUrl: String = "",
                importLevel: String = "full-question", status: String = "new")
}

// Sources/IELTSCoachCore/Prompt/ExaminerPrompt.swift
public struct SessionSetup: Equatable, Sendable {
    public let question: Question
    public let focusPart: FocusPart
    public let durationMinutes: Int
    public let goal: String             // 可为空；非空时 ExaminerPrompt 会追加「本次唯一目标：…」
    public let feedbackTiming: FeedbackTiming
    public let part2PrepMode: Part2PrepMode
    public init(question: Question, focusPart: FocusPart, durationMinutes: Int, goal: String,
                feedbackTiming: FeedbackTiming = .deferred,
                part2PrepMode: Part2PrepMode = .countdown)
}
public enum ExaminerPrompt { public static func build(setup: SessionSetup) -> String }

// Sources/IELTSCoachCore/Storage/StateStore.swift
public final class StateStore: @unchecked Sendable {
    public init(directory: DataDirectory)
    public func load() throws -> CoachState
    @discardableResult
    public func mutate<T>(_ body: (inout CoachState) throws -> T) throws -> T
}

// Sources/IELTSCoachCore/JSON/JSONValue.swift
public enum JSONValue: Equatable, Sendable, Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    public static func decode(from text: String) throws -> JSONValue
    public subscript(key: String) -> JSONValue?
    public var arrayValue: [JSONValue]?
    public var objectValue: [String: JSONValue]?
    public var stringValue: String?
    public var isBlank: Bool
}
```

---

## Task 1: 复训标记 —— 把一场练习和一个目标挂上钩

**Files:**
- Create: `Sources/IELTSCoachCore/Model/RetrainingLink.swift`
- Modify: `Sources/IELTSCoachCore/Model/PracticeSession.swift`
- Create: `Tests/IELTSCoachCoreTests/RetrainingLinkTests.swift`

**Interfaces:**
- Consumes: `PracticeSession`、`RetrainingTarget`
- Produces:
  - `struct RetrainingLink: Codable, Equatable, Sendable`，含 `targetKey: String`、`sourceSessionId: String`、`originalQuestionId: String`、`init(targetKey:sourceSessionId:originalQuestionId:)`、`var targetID: String`
  - `enum RetrainingKind: String, Equatable, Sendable { case original, transfer }`
  - `PracticeSession.retraining: RetrainingLink?`（新字段，默认 nil）
  - `PracticeSession.retrainingKind: RetrainingKind?`（派生属性）

**为什么 kind 是派生的而不是存的：** 存一个 `kind` 字段，就有「存的值和实际题目对不上」的可能；而「换题验证到底做过没有」是本产品最核心的判断，一旦串台，用户会拿着一个假结论以为自己练成了。派生就不可能不一致。

**为什么必须存 `originalQuestionId`：** 训练记录允许单条删除（Phase 4 的交付内容）。源 session 一旦被删，就再也回查不到当时练的是哪道题，而「这次算原题重练还是换题验证」必须永远能判定。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/RetrainingLinkTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class RetrainingLinkTests: XCTestCase {
    private func session(id: String, questionId: String,
                         link: RetrainingLink?) -> PracticeSession {
        PracticeSession(id: id, questionId: questionId, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private let link = RetrainingLink(targetKey: "logic-explain-example",
                                      sourceSessionId: "2026-08-05-001",
                                      originalQuestionId: "p1-home-001")

    /// 普通练习不能被当成复训——否则复训进度会凭空多出几场，
    /// 用户以为自己已经换题验证过了，其实一次都没练。
    func testPlainSessionHasNoRetrainingKind() {
        XCTAssertNil(session(id: "s1", questionId: "p1-home-001", link: nil).retrainingKind)
    }

    func testSameQuestionIsCountedAsOriginalRetry() {
        XCTAssertEqual(session(id: "s1", questionId: "p1-home-001", link: link).retrainingKind,
                       .original)
    }

    /// 这一条守的是本阶段的核心：换了题才叫验证。
    func testDifferentQuestionIsCountedAsTransfer() {
        XCTAssertEqual(session(id: "s2", questionId: "p1-work-007", link: link).retrainingKind,
                       .transfer)
    }

    /// 用户已经练过的记录里没有 retraining 这个键。解码必须容忍它缺失，
    /// 否则升级到这一版之后，全部历史训练记录会一起读不出来。
    func testDecodesOldSessionJSONWithoutTheNewField() throws {
        let json = """
        {"id":"2026-08-05-001","questionId":"p1-home-001","focusPart":"Part 1",
         "startedAt":"2026-08-05T10:00:00Z","endedAt":"2026-08-05T10:20:00Z","goal":"",
         "transcript":[],"reportPath":"reports/2026-08-05-001.json","recordingPath":""}
        """
        let decoded = try JSONDecoder().decode(PracticeSession.self, from: Data(json.utf8))
        XCTAssertNil(decoded.retraining)
        XCTAssertNil(decoded.retrainingKind)
    }

    func testRoundTripsThroughJSON() throws {
        let original = session(id: "s2", questionId: "p1-work-007", link: link)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self, from: data), original)
    }

    /// link 与 target 必须能对上，否则界面上「这条训练记录属于哪个目标」永远匹配不到，
    /// 复训进度会一直显示「还没开始」。
    func testTargetIDMatchesRetrainingTargetID() {
        let target = RetrainingTarget(targetKey: "logic-explain-example", label: "补一个原因和例子",
                                      status: "new", evidence: [],
                                      sourceSessionId: "2026-08-05-001", createdAt: "t")
        XCTAssertEqual(link.targetID, target.id)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingLinkTests`
Expected: 编译失败 —— `RetrainingLink` 未定义、`PracticeSession.init` 没有 `retraining` 参数

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Model/RetrainingLink.swift`：

```swift
import Foundation

/// 把一场练习标记成「某个复训目标的复训会话」。
///
/// **为什么要同时记 targetKey 和 sourceSessionId：** `RetrainingTarget.targetKey` 跨 session
/// 会重复（见 Records.swift 里的注释）。只记 targetKey，会把两份不同复盘里同名的目标
/// 混成一个，复训进度就会串台——界面显示「已经换题验证过了」，其实验证的是另一次复盘
/// 里的那个目标。
public struct RetrainingLink: Codable, Equatable, Sendable {
    public var targetKey: String
    public var sourceSessionId: String

    /// 目标来源那次练习用的题目 id。**必须存下来，不能靠回查 sourceSessionId 得到**：
    /// 训练记录允许单条删除，源 session 被删之后就再也回查不到了，
    /// 而「这次算原题重练还是换题验证」必须永远能判定。
    public var originalQuestionId: String

    public init(targetKey: String, sourceSessionId: String, originalQuestionId: String) {
        self.targetKey = targetKey
        self.sourceSessionId = sourceSessionId
        self.originalQuestionId = originalQuestionId
    }

    /// 与 `RetrainingTarget.id` 同构，两边才对得上。
    public var targetID: String { "\(targetKey)@\(sourceSessionId)" }
}

/// 一场复训会话在复训里扮演的角色。
public enum RetrainingKind: String, Equatable, Sendable, CaseIterable {
    /// 重答原题。
    case original
    /// 换一道题验证——**这一项才是本产品的价值所在**：
    /// 只重练原题，分不清是真会了还是只记住了那个答案。
    case transfer
}

extension PracticeSession {
    /// 这场练习在复训里扮演什么角色。不是复训会话时为 nil。
    ///
    /// **派生而非存储**：存一个 kind 字段就有「存的值与实际题目对不上」的可能，
    /// 而这两者一旦不一致，「换题验证做过没有」这个最核心的判断就会出错。
    public var retrainingKind: RetrainingKind? {
        guard let link = retraining else { return nil }
        return questionId == link.originalQuestionId ? .original : .transfer
    }
}
```

`Sources/IELTSCoachCore/Model/PracticeSession.swift` 的两处改动：

1. 在 `recordingPath` 之后加一个属性：

```swift
    /// 非 nil 表示这是一场复训会话（Phase 6）。普通练习为 nil。
    /// Optional 属性由 Swift 合成的解码器走 decodeIfPresent，
    /// 因此不带这个键的历史记录仍然能正常读出来——不要改成非 Optional。
    public var retraining: RetrainingLink?
```

2. `init` 末尾加一个**带默认值**的参数（默认值保证既有调用点一行都不用改）：

```swift
    public init(id: String, questionId: String, focusPart: FocusPart, startedAt: String,
                endedAt: String, goal: String, transcript: [TranscriptTurn],
                reportPath: String, recordingPath: String,
                retraining: RetrainingLink? = nil) {
        self.id = id; self.questionId = questionId; self.focusPart = focusPart
        self.startedAt = startedAt; self.endedAt = endedAt; self.goal = goal
        self.transcript = transcript; self.reportPath = reportPath
        self.recordingPath = recordingPath; self.retraining = retraining
    }
```

**不要给 `PracticeSession` 手写 `CodingKeys`。** 一旦手写，将来加字段忘了同步就会静默丢数据；现在靠合成的键名与属性名天然一致。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingLinkTests`
Expected: PASS（6 个测试）

Run: `swift test`
Expected: 全绿。若有别的测试因为 `PracticeSession` 多了一个字段而变红，**先看它断言的是什么**：断言 JSON 键集合的测试要按「新增可选字段、缺省时不写入」的原则更新；断言业务行为的测试变红说明这次改动确实破坏了行为，要停下来查。

- [ ] **Step 5: 突变验证**

两处，都要做，两次输出都写进报告：

1. 把 `retrainingKind` 里的 `questionId == link.originalQuestionId` 改成 `true`（永远返回 `.original`），重跑：`testDifferentQuestionIsCountedAsTransfer` **必须变红**。
   *守的是：换题验证被记成原题重练，用户永远看不到「已换题验证」，或者更糟——原题重练被当成换题验证，用户拿着假结论以为练成了。*
2. 把 `targetID` 的拼接顺序改成 `"\(sourceSessionId)@\(targetKey)"`，重跑：`testTargetIDMatchesRetrainingTargetID` **必须变红**。
   *守的是：link 与 target 对不上，整个复训进度永远显示「还没开始」，且不报任何错。*

两处都改回，确认 `swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/RetrainingLink.swift Sources/IELTSCoachCore/Model/PracticeSession.swift Tests/IELTSCoachCoreTests/RetrainingLinkTests.swift
git commit -m "feat(core): 复训标记 RetrainingLink 与派生的原题/换题判定"
```

---

## Task 2: 复训台账 —— 进度、挂钩、状态流转

**Files:**
- Create: `Sources/IELTSCoachCore/Policy/RetrainingLedger.swift`
- Create: `Tests/IELTSCoachCoreTests/RetrainingLedgerTests.swift`

**Interfaces:**
- Consumes: `CoachState`、`PracticeSession`、`RetrainingTarget`、`RetrainingLink`、`RetrainingKind`
- Produces:
  - `enum RetrainingStage: String, Equatable, Sendable { case notStarted, retriedOriginal, triedTransfer }`
  - `enum RetrainingStatus: String, Equatable, Sendable, CaseIterable { case new, selected, retired }`
  - `struct RetrainingProgress: Equatable, Sendable`，含 `targetID: String`、`originalRetrySessionIDs: [String]`、`transferSessionIDs: [String]`、`init(targetID:originalRetrySessionIDs:transferSessionIDs:)`、`var stage: RetrainingStage`
  - `RetrainingLedger.progress(for target: RetrainingTarget, sessions: [PracticeSession]) -> RetrainingProgress`
  - `RetrainingLedger.attach(_ link: RetrainingLink, toSessionWithID: String, in state: inout CoachState) -> Bool`
  - `RetrainingLedger.setStatus(_ status: RetrainingStatus, of targetID: String, in state: inout CoachState) -> Bool`

**这个台账是纯函数集合，放 Core**：它只依赖 Foundation，Phase 9 的 MCP server 要暴露「复训进度」时可以直接复用，不必在 UI 层重写一遍。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/RetrainingLedgerTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class RetrainingLedgerTests: XCTestCase {
    private func target(_ key: String, session: String, status: String = "new") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "补一个原因和例子", status: status,
                         evidence: ["I just like it."], sourceSessionId: session,
                         createdAt: "2026-08-05T10:00:00Z")
    }

    private func session(_ id: String, question: String,
                         link: RetrainingLink? = nil) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private func link(_ key: String, source: String, original: String) -> RetrainingLink {
        RetrainingLink(targetKey: key, sourceSessionId: source, originalQuestionId: original)
    }

    // MARK: - progress

    func testProgressIsNotStartedWhenNoSessionIsLinked() {
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1"), session("s2", question: "q2")])
        XCTAssertEqual(progress.stage, .notStarted)
        XCTAssertTrue(progress.originalRetrySessionIDs.isEmpty)
        XCTAssertTrue(progress.transferSessionIDs.isEmpty)
    }

    func testProgressSeparatesOriginalRetriesFromTransfers() {
        let l = link("k", source: "s0", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1", link: l),      // 重答原题
                       session("s2", question: "q9", link: l),      // 换题验证
                       session("s3", question: "q1", link: l)])     // 又重答一次原题
        XCTAssertEqual(progress.originalRetrySessionIDs, ["s1", "s3"])
        XCTAssertEqual(progress.transferSessionIDs, ["s2"])
        XCTAssertEqual(progress.stage, .triedTransfer)
    }

    func testStageIsRetriedOriginalUntilAQuestionIsSwapped() {
        let l = link("k", source: "s0", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q1", link: l)])
        XCTAssertEqual(progress.stage, .retriedOriginal,
                       "只重练了原题就说「验证过了」，正是这个产品要防的事")
    }

    /// targetKey 跨 session 会重复。只按 key 匹配，两个不同复盘里同名的目标会串台，
    /// 用户会看到「已换题验证」而其实验证的是另一个目标。
    func testProgressMatchesFullIdentityNotJustTargetKey() {
        let mine = link("k", source: "s0", original: "q1")
        let someoneElses = link("k", source: "s-other", original: "q1")
        let progress = RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q9", link: someoneElses)])
        XCTAssertTrue(progress.transferSessionIDs.isEmpty,
                      "别的复盘里同名目标的复训会话，不能算进这个目标的进度")
        XCTAssertEqual(RetrainingLedger.progress(
            for: target("k", session: "s0"),
            sessions: [session("s1", question: "q9", link: mine)]).transferSessionIDs, ["s1"])
    }

    // MARK: - attach

    func testAttachWritesTheLinkOntoTheSession() {
        var state = CoachState.empty()
        state.sessions = [session("s1", question: "q9")]
        let l = link("k", source: "s0", original: "q1")
        XCTAssertTrue(RetrainingLedger.attach(l, toSessionWithID: "s1", in: &state))
        XCTAssertEqual(state.sessions[0].retraining, l)
        XCTAssertEqual(state.sessions[0].retrainingKind, .transfer)
    }

    /// 挂不上必须能被调用方发现。静默返回成功，用户会看到「复训已记录」，
    /// 而台账里其实什么都没有——本项目已知最危险的失败形态。
    func testAttachReportsFailureWhenTheSessionIsNotThere() {
        var state = CoachState.empty()
        state.sessions = [session("s1", question: "q9")]
        XCTAssertFalse(RetrainingLedger.attach(link("k", source: "s0", original: "q1"),
                                               toSessionWithID: "不存在的记录", in: &state))
        XCTAssertNil(state.sessions[0].retraining)
    }

    func testAttachDoesNotOverwriteALinkThatBelongsToAnotherTarget() {
        var state = CoachState.empty()
        let existing = link("k1", source: "s0", original: "q1")
        state.sessions = [session("s1", question: "q9", link: existing)]
        XCTAssertFalse(RetrainingLedger.attach(link("k2", source: "s0", original: "q1"),
                                               toSessionWithID: "s1", in: &state))
        XCTAssertEqual(state.sessions[0].retraining, existing, "已有的挂钩不许被覆盖")
    }

    func testAttachIsIdempotentForTheSameLink() {
        var state = CoachState.empty()
        let l = link("k", source: "s0", original: "q1")
        state.sessions = [session("s1", question: "q9", link: l)]
        XCTAssertTrue(RetrainingLedger.attach(l, toSessionWithID: "s1", in: &state),
                      "重复挂同一个 link 不算失败——重试路径上会发生")
    }

    // MARK: - setStatus

    func testSetStatusFlipsTheTarget() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        XCTAssertTrue(RetrainingLedger.setStatus(.selected, of: "k@s0", in: &state))
        XCTAssertEqual(state.targets[0].status, "selected")
        XCTAssertTrue(RetrainingLedger.setStatus(.retired, of: "k@s0", in: &state))
        XCTAssertEqual(state.targets[0].status, "retired")
    }

    /// 同名不同来源的两个目标，改一个不能连累另一个。
    func testSetStatusOnlyTouchesTheTargetWithTheMatchingFullIdentity() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0"), target("k", session: "s1")]
        XCTAssertTrue(RetrainingLedger.setStatus(.retired, of: "k@s1", in: &state))
        XCTAssertEqual(state.targets[0].status, "new")
        XCTAssertEqual(state.targets[1].status, "retired")
    }

    func testSetStatusReportsFailureForAnUnknownTarget() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        XCTAssertFalse(RetrainingLedger.setStatus(.retired, of: "k@不存在", in: &state))
        XCTAssertEqual(state.targets[0].status, "new")
    }

    /// 退休之后必须真的从推荐里消失——RetrainingPolicy.rank 认的就是这个字符串。
    func testRetiredTargetDropsOutOfRank() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0")]
        _ = RetrainingLedger.setStatus(.retired, of: "k@s0", in: &state)
        XCTAssertTrue(RetrainingPolicy.rank(targets: state.targets, issues: []).isEmpty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingLedgerTests`
Expected: 编译失败 —— `RetrainingLedger` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Policy/RetrainingLedger.swift`：

```swift
import Foundation

/// 一个复训目标走到哪一步了。
public enum RetrainingStage: String, Equatable, Sendable, CaseIterable {
    /// 还没为它练过任何一场。
    case notStarted
    /// 重答过原题，但还没换题验证。
    case retriedOriginal
    /// 已经换过题练——**这一步才是本产品真正的价值**：
    /// 只重练原题，分不清是真会了还是只记住了那个答案。
    case triedTransfer
}

/// `RetrainingTarget.status` 的合法取值。原本只写在注释里，这里固化成类型，
/// 免得各处拼字符串拼错一个字母就静默失效。
public enum RetrainingStatus: String, Equatable, Sendable, CaseIterable {
    case new, selected, retired
}

public struct RetrainingProgress: Equatable, Sendable {
    public let targetID: String
    /// 重答原题的会话 id，按 sessions 里的先后顺序。
    public let originalRetrySessionIDs: [String]
    /// 换题验证的会话 id，按 sessions 里的先后顺序。
    public let transferSessionIDs: [String]

    public init(targetID: String, originalRetrySessionIDs: [String],
                transferSessionIDs: [String]) {
        self.targetID = targetID
        self.originalRetrySessionIDs = originalRetrySessionIDs
        self.transferSessionIDs = transferSessionIDs
    }

    public var stage: RetrainingStage {
        if !transferSessionIDs.isEmpty { return .triedTransfer }
        if !originalRetrySessionIDs.isEmpty { return .retriedOriginal }
        return .notStarted
    }
}

/// 复训台账。全是纯函数：吃进 state，吐出结果或就地改 state，不做任何 IO。
public enum RetrainingLedger {
    public static func progress(for target: RetrainingTarget,
                                sessions: [PracticeSession]) -> RetrainingProgress {
        // 必须按 targetID（key + 来源 session）匹配，不能只按 targetKey：
        // targetKey 跨 session 会重复，只按它匹配会让两份复盘里同名的目标串台。
        let mine = sessions.filter { $0.retraining?.targetID == target.id }
        return RetrainingProgress(
            targetID: target.id,
            originalRetrySessionIDs: mine.filter { $0.retrainingKind == .original }.map(\.id),
            transferSessionIDs: mine.filter { $0.retrainingKind == .transfer }.map(\.id))
    }

    /// 把复训标记挂到一条训练记录上。
    /// - Returns: 挂上了返回 true。**返回 false 时调用方必须把这件事告诉用户**，
    ///   不能当作没发生——用户会以为复训被记下了，其实台账是空的。
    @discardableResult
    public static func attach(_ link: RetrainingLink, toSessionWithID sessionID: String,
                              in state: inout CoachState) -> Bool {
        guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
            return false
        }
        if let existing = state.sessions[index].retraining {
            // 已经挂给别的目标了就不动它。覆盖会把另一个目标的进度悄悄抹掉。
            return existing == link
        }
        state.sessions[index].retraining = link
        return true
    }

    /// 改一个复训目标的状态。`targetID` 是 `RetrainingTarget.id`（即 "key@来源session"）。
    /// - Returns: 找到并改了返回 true；找不到返回 false，调用方须据此提示用户。
    @discardableResult
    public static func setStatus(_ status: RetrainingStatus, of targetID: String,
                                 in state: inout CoachState) -> Bool {
        guard let index = state.targets.firstIndex(where: { $0.id == targetID }) else {
            return false
        }
        state.targets[index].status = status.rawValue
        return true
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingLedgerTests`
Expected: PASS（11 个测试）

- [ ] **Step 5: 突变验证**

三处，逐个做，输出都写进报告：

1. 把 `progress` 里的 `$0.retraining?.targetID == target.id` 改成 `$0.retraining?.targetKey == target.targetKey`，重跑：`testProgressMatchesFullIdentityNotJustTargetKey` **必须变红**。
   *守的是本项目源码里已经白纸黑字警告过的坑（Records.swift：targetKey 跨 session 会重复）。*
2. 把 `attach` 里 `guard let index … else { return false }` 改成 `guard let index … else { return true }`，重跑：`testAttachReportsFailureWhenTheSessionIsNotThere` **必须变红**。
   *守的是「静默把失败当成功」——本项目反复栽的那一类。*
3. 把 `setStatus` 的匹配条件改成 `$0.targetKey == targetID.components(separatedBy: "@")[0]`，重跑：`testSetStatusOnlyTouchesTheTargetWithTheMatchingFullIdentity` **必须变红**。

三处都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Policy/RetrainingLedger.swift Tests/IELTSCoachCoreTests/RetrainingLedgerTests.swift
git commit -m "feat(core): 复训台账（进度、挂钩、状态流转）"
```

---

## Task 3: 换题验证的结果判定

**Files:**
- Create: `Sources/IELTSCoachCore/Policy/RetrainingOutcome.swift`
- Create: `Tests/IELTSCoachCoreTests/RetrainingOutcomeTests.swift`

**Interfaces:**
- Consumes: `JSONValue`
- Produces:
  - `enum RetrainingOutcome: String, Equatable, Sendable { case noReport, namedAgain, notNamedAgain }`
  - `RetrainingOutcome.judge(report: JSONValue?, targetKey: String) -> RetrainingOutcome`

**判据是什么、不是什么：** 复训之后 ChatGPT 会给出一份新复盘，里面有它自己选的 `priority_target`。若它**又点了同一个目标**（`priority_target.id` 与本次复训的 `targetKey` 相同），说明这个毛病这次还在；若它点的是别的（或没点），说明这次没有再被点名。

**这不等于「已经改掉了」**，判定的边界必须写进文案（Task 9）：ChatGPT 可能换了个 id 说同一件事，也可能这次只是碰巧没抓到。所以本阶段只报告「有没有被再次点名」这个可观测的事实，**不下结论**（见「决定 4」）。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/RetrainingOutcomeTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class RetrainingOutcomeTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    func testNoReportMeansWeSimplyDoNotKnow() {
        XCTAssertEqual(RetrainingOutcome.judge(report: nil, targetKey: "logic-explain"), .noReport)
    }

    func testSameTargetNamedAgain() throws {
        let value = try report(#"""
        {"must_correct":[],"priority_target":{"id":"logic-explain","label":"补一个原因和例子",
         "status":"new","evidence":["I just like it."]}}
        """#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"), .namedAgain)
    }

    func testDifferentTargetMeansItWasNotNamedAgain() throws {
        let value = try report(#"""
        {"must_correct":[],"priority_target":{"id":"tense-consistency","label":"时态别乱跳",
         "status":"new","evidence":[]}}
        """#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)
    }

    func testNoPriorityTargetAtAllMeansItWasNotNamedAgain() throws {
        let value = try report(#"{"must_correct":[],"summary":"整体不错"}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)
    }

    /// 一份根本不成形的「复盘」（比如解析降级后拿到的是一个字符串）不能被当成通过。
    /// 把没认出来的东西当成好消息，正是本项目栽过跟头的那一类。
    func testGarbageReportIsUnknownNotAPass() throws {
        XCTAssertEqual(RetrainingOutcome.judge(report: .string("ChatGPT 说了一堆没有 JSON 的话"),
                                               targetKey: "logic-explain"), .noReport)
        XCTAssertEqual(RetrainingOutcome.judge(report: .array([]), targetKey: "logic-explain"),
                       .noReport)
        XCTAssertEqual(RetrainingOutcome.judge(report: .null, targetKey: "logic-explain"), .noReport)
    }

    /// ChatGPT 输出的 id 可能带前后空白；`RetrainingPolicy.extractTarget` 也是去空白后再用的，
    /// 两处判据不一致会导致「明明是同一个目标却说没被点名」。
    func testWhitespaceAroundIDsDoesNotChangeTheVerdict() throws {
        let value = try report(#"{"priority_target":{"id":"  logic-explain  ","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"), .namedAgain)
    }

    func testBlankIDIsTreatedAsNotNamedAgain() throws {
        let value = try report(#"{"priority_target":{"id":"   ","label":"L"}}"#)
        XCTAssertEqual(RetrainingOutcome.judge(report: value, targetKey: "logic-explain"),
                       .notNamedAgain)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingOutcomeTests`
Expected: 编译失败 —— `RetrainingOutcome` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Policy/RetrainingOutcome.swift`：

```swift
import Foundation

/// 一场复训之后，这个目标有没有被新复盘再次点名。
///
/// **这不是「改没改掉」的结论。** ChatGPT 完全可能换一个 id 说同一件事，也可能这一次
/// 碰巧没抓到。所以这里只报告一个可观测的事实，措辞上不许升级成结论（见计划的「决定 4」）。
public enum RetrainingOutcome: String, Equatable, Sendable, CaseIterable {
    /// 还没有可判断的复盘（没练完、复盘没取回、或取回的东西不成形）。
    case noReport
    /// 新复盘又把同一个目标点了出来。
    case namedAgain
    /// 新复盘没有再点它。
    case notNamedAgain

    public static func judge(report: JSONValue?, targetKey: String) -> RetrainingOutcome {
        // 不成形的东西一律算「不知道」。把没认出来的输入当成好消息，
        // 会让用户拿着一个假结论以为自己练成了。
        guard let report, report.objectValue != nil else { return .noReport }

        guard let target = report["priority_target"], target.objectValue != nil else {
            return .notNamedAgain
        }
        let id = (target["id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return .notNamedAgain }

        return id == targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
            ? .namedAgain : .notNamedAgain
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingOutcomeTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

1. 把 `guard let report, report.objectValue != nil else { return .noReport }` 改成 `guard let report else { return .noReport }`，重跑：`testGarbageReportIsUnknownNotAPass` **必须变红**。
   *守的是本项目最典型的失败：把没认出来的输入当成成功。*
2. 去掉两处 `trimmingCharacters`，重跑：`testWhitespaceAroundIDsDoesNotChangeTheVerdict` **必须变红**。

都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Policy/RetrainingOutcome.swift Tests/IELTSCoachCoreTests/RetrainingOutcomeTests.swift
git commit -m "feat(core): 换题验证的结果判定"
```

---

## Task 4: 换题验证的候选题挑选

**Files:**
- Create: `Sources/IELTSCoachCore/Policy/TransferQuestionPolicy.swift`
- Create: `Tests/IELTSCoachCoreTests/TransferQuestionPolicyTests.swift`

**Interfaces:**
- Consumes: `Question`、`PracticeSession`、`RetrainingTarget`、`RetrainingLink`
- Produces:
  - `struct TransferCandidate: Equatable, Sendable, Identifiable`，含 `question: Question`、`sameTopicAsOriginal: Bool`、`init(question:sameTopicAsOriginal:)`、`var id: String`
  - `TransferQuestionPolicy.candidates(for:originalQuestion:questions:sessions:) -> [TransferCandidate]`

**挑选规则（顺序即优先级，实现必须逐条对得上）：**

1. 排除原题本身——换题就是不能再用它
2. 排除已经为**这个目标**练过的题——同一目标反复练同一道题不叫换题
3. **只在同一个 Part 内换**（见「决定 3」）
4. 同 Part 内，**话题与原题不同的排前面**；同话题的仍然返回，但打上 `sameTopicAsOriginal` 标记，由界面写明「和原题同一个话题，验证力度打折」
5. 其余保持题库原有顺序——结果稳定可预期，用户每次打开看到的顺序一样

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/TransferQuestionPolicyTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class TransferQuestionPolicyTests: XCTestCase {
    private func question(_ id: String, part: Int, topic: String) -> Question {
        Question(id: id, part: part, topic: topic, prompt: "prompt-\(id)")
    }

    private func target(_ key: String = "k", session: String = "s0") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "补一个原因和例子", status: "new",
                         evidence: [], sourceSessionId: session, createdAt: "t")
    }

    private func session(_ id: String, question: String, link: RetrainingLink?) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "",
                        retraining: link)
    }

    private let original = Question(id: "p1-home-001", part: 1, topic: "Home",
                                    prompt: "Do you live in a house or a flat?")

    func testExcludesTheOriginalQuestion() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    /// Part 1 要短、Part 3 要展开，同一个目标在两者里的达成标准不一样。
    /// 跨 Part 换题验证的根本不是同一件事。
    func testNeverCrossesParts() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p2-trip-001", part: 2, topic: "Travel"),
                        question("p3-edu-001", part: 3, topic: "Education"),
                        question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    /// 换题验证的意义在于换语境。同话题的题目太接近原题，等于换汤不换药，
    /// 所以不同话题的必须排前面。
    func testDifferentTopicComesFirst() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-home-002", part: 1, topic: "Home"),
                        question("p1-work-001", part: 1, topic: "Work")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001", "p1-home-002"])
    }

    func testSameTopicIsKeptButMarked() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-home-002", part: 1, topic: "  home  ")],
            sessions: [])
        XCTAssertEqual(result.count, 1, "题库小的时候不能直接不给题，否则用户当场卡死")
        XCTAssertTrue(result[0].sameTopicAsOriginal, "大小写与空白不同不等于话题不同")
    }

    func testExcludesQuestionsAlreadyUsedForThisTarget() {
        let l = RetrainingLink(targetKey: "k", sourceSessionId: "s0",
                               originalQuestionId: "p1-home-001")
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-work-001", part: 1, topic: "Work"),
                        question("p1-food-001", part: 1, topic: "Food")],
            sessions: [session("s1", question: "p1-work-001", link: l)])
        XCTAssertEqual(result.map(\.id), ["p1-food-001"],
                       "同一个目标不该反复拿同一道题「验证」")
    }

    /// 另一个目标练过这道题，不影响这个目标——否则题库会被越练越空。
    func testDoesNotExcludeQuestionsUsedForAnotherTarget() {
        let other = RetrainingLink(targetKey: "another", sourceSessionId: "s0",
                                   originalQuestionId: "p1-home-001")
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p1-work-001", part: 1, topic: "Work")],
            sessions: [session("s1", question: "p1-work-001", link: other)])
        XCTAssertEqual(result.map(\.id), ["p1-work-001"])
    }

    func testKeepsBankOrderForTiedCandidates() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original,
                        question("p1-work-001", part: 1, topic: "Work"),
                        question("p1-food-001", part: 1, topic: "Food"),
                        question("p1-sport-001", part: 1, topic: "Sport")],
            sessions: [])
        XCTAssertEqual(result.map(\.id), ["p1-work-001", "p1-food-001", "p1-sport-001"],
                       "顺序必须稳定，否则同一页每次打开都换个样")
    }

    func testEmptyWhenTheBankHasNothingElseInThisPart() {
        let result = TransferQuestionPolicy.candidates(
            for: target(), originalQuestion: original,
            questions: [original, question("p3-edu-001", part: 3, topic: "Education")],
            sessions: [])
        XCTAssertTrue(result.isEmpty, "返回空，由界面给「去导入更多题目」的空状态")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TransferQuestionPolicyTests`
Expected: 编译失败 —— `TransferQuestionPolicy` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Policy/TransferQuestionPolicy.swift`：

```swift
import Foundation

public struct TransferCandidate: Equatable, Sendable, Identifiable {
    public let question: Question
    /// 与原题同一个话题。仍然可以练，但界面必须标出来——同话题换题的验证力度打折。
    public let sameTopicAsOriginal: Bool

    public init(question: Question, sameTopicAsOriginal: Bool) {
        self.question = question
        self.sameTopicAsOriginal = sameTopicAsOriginal
    }

    public var id: String { question.id }
}

/// 「同一目标换一道题再练」的候选题挑选。
///
/// **这是整个 Phase 6 的价值所在**（DEFINITION-OF-DONE 第 2 节）：
/// 只重练原题，分不清是真会了还是只记住了那个答案。
public enum TransferQuestionPolicy {
    /// 规则顺序即优先级：
    /// 1. 排除原题本身
    /// 2. 排除已经为**这个目标**练过的题
    /// 3. 只在同一个 Part 内换（Part 1 要短、Part 3 要展开，标准不同）
    /// 4. 话题与原题不同的排前面；同话题的保留但打标
    /// 5. 其余保持题库原有顺序，保证界面每次打开顺序一样
    public static func candidates(for target: RetrainingTarget,
                                  originalQuestion: Question,
                                  questions: [Question],
                                  sessions: [PracticeSession]) -> [TransferCandidate] {
        // 按 targetID 匹配，不是按 targetKey：别的目标练过这道题不该影响这个目标。
        let alreadyUsed = Set(
            sessions.filter { $0.retraining?.targetID == target.id }.map(\.questionId))
        let originalTopic = normalized(originalQuestion.topic)

        return questions.enumerated()
            .filter { $0.element.part == originalQuestion.part }
            .filter { $0.element.id != originalQuestion.id }
            .filter { !alreadyUsed.contains($0.element.id) }
            .map { entry in
                (offset: entry.offset,
                 candidate: TransferCandidate(
                    question: entry.element,
                    sameTopicAsOriginal: normalized(entry.element.topic) == originalTopic))
            }
            .sorted { left, right in
                if left.candidate.sameTopicAsOriginal != right.candidate.sameTopicAsOriginal {
                    return !left.candidate.sameTopicAsOriginal   // 换话题的排前面
                }
                return left.offset < right.offset               // 同档保持题库原有顺序
            }
            .map(\.candidate)
    }

    /// 话题比对要忽略大小写与前后空白：题库来自 CSV/JSON/PDF 三条导入路径，
    /// 同一个话题写成 "Home" / "home" / " Home " 都很常见，
    /// 按字面比会把同话题误判成换了话题，让验证形同虚设。
    private static func normalized(_ topic: String) -> String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TransferQuestionPolicyTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证**

四处，逐个做：

1. 删掉 `.filter { $0.element.part == originalQuestion.part }`，重跑：`testNeverCrossesParts` **必须变红**
2. 删掉 `.filter { !alreadyUsed.contains($0.element.id) }`，重跑：`testExcludesQuestionsAlreadyUsedForThisTarget` **必须变红**
3. 把排序里的话题比较整段删掉（只留 `left.offset < right.offset`），重跑：`testDifferentTopicComesFirst` **必须变红**
4. 把 `normalized` 改成直接返回原字符串，重跑：`testSameTopicIsKeptButMarked` **必须变红**

四处都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Policy/TransferQuestionPolicy.swift Tests/IELTSCoachCoreTests/TransferQuestionPolicyTests.swift
git commit -m "feat(core): 换题验证的候选题挑选"
```

---

## Task 5: 三步流程与「撤掉提示」的规则

**Files:**
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingStep.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingStepTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum RetrainingStep: String, CaseIterable, Identifiable, Equatable, Sendable { case evidence, rehearsal, speaking }`，含 `stepNumber: Int`、`title: String`、`explanation: String`、`showsEvidence: Bool`、`showsModelAnswer: Bool`、`showsGoal: Bool`、`canStartPractice: Bool`、`next: RetrainingStep?`
  - `enum RetrainingRun: String, CaseIterable, Equatable, Sendable { case original, transfer }`，含 `firstStep: RetrainingStep`、`title: String`

**这个 enum 就是「带着本题进入复训」流程本身。** 它是纯逻辑，因此能测；界面只负责按它显示。

**核心不变量：一旦学员开始答题，屏幕上不许再出现任何范答。** 对着高分版念一遍不叫复训。而「本次唯一目标」那一行要一直留着——它是**行为指令**（「回答后补一个原因和例子」），不是答案（见「决定 2」）。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RetrainingStepTests.swift`：

```swift
import XCTest
@testable import IELTSCoachUI

final class RetrainingStepTests: XCTestCase {
    func testThereAreExactlyThreeStepsNumberedFromOne() {
        XCTAssertEqual(RetrainingStep.allCases, [.evidence, .rehearsal, .speaking])
        XCTAssertEqual(RetrainingStep.allCases.map(\.stepNumber), [1, 2, 3])
    }

    func testEveryStepHasChineseTitleAndExplanation() {
        for step in RetrainingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) 没有标题")
            XCTAssertFalse(step.explanation.isEmpty, "\(step) 没有说明")
        }
    }

    /// 全项目的硬性约束：面向用户的文案要同时说清「发生了什么」和「下一步做什么」。
    func testEveryExplanationTellsTheLearnerWhatToDoNext() {
        for step in RetrainingStep.allCases {
            XCTAssertTrue(step.explanation.contains("下一步"),
                          "\(step) 的说明没写下一步该做什么")
        }
    }

    /// **本任务最重要的一条。** 一旦开始答题还看得见高分版，学员就是在照着念，
    /// 复训退化成朗读，而界面上一点异常都看不出来。
    func testModelAnswerIsOnlyVisibleWhileReviewingEvidence() {
        XCTAssertTrue(RetrainingStep.evidence.showsModelAnswer)
        for step in RetrainingStep.allCases where step != .evidence {
            XCTAssertFalse(step.showsModelAnswer, "\(step) 还在显示高分版——那等于照着念")
        }
    }

    func testEvidenceIsAlsoWithdrawnOnceTheLearnerStartsAnswering() {
        XCTAssertTrue(RetrainingStep.evidence.showsEvidence)
        for step in RetrainingStep.allCases where step != .evidence {
            XCTAssertFalse(step.showsEvidence, "\(step) 还在显示当时的原话")
        }
    }

    /// 目标是行为指令，不是答案。撤掉它，学员就不知道这一次要做到什么，
    /// 复训和随便再练一遍就没区别了。
    func testTheSinglePointGoalStaysVisibleTheWholeTime() {
        for step in RetrainingStep.allCases {
            XCTAssertTrue(step.showsGoal, "\(step) 把本次唯一目标也撤掉了")
        }
    }

    func testOnlyTheRehearsalStepCanStartThePractice() {
        XCTAssertEqual(RetrainingStep.allCases.filter(\.canStartPractice), [.rehearsal])
    }

    func testStepsChainInOrderAndStopAtSpeaking() {
        XCTAssertEqual(RetrainingStep.evidence.next, .rehearsal)
        XCTAssertEqual(RetrainingStep.rehearsal.next, .speaking)
        XCTAssertNil(RetrainingStep.speaking.next)
    }

    /// 换题验证不再回看证据——**正因为不给看，才知道是不是真会了**。
    func testTransferRunSkipsTheEvidenceStep() {
        XCTAssertEqual(RetrainingRun.original.firstStep, .evidence)
        XCTAssertEqual(RetrainingRun.transfer.firstStep, .rehearsal)
    }

    func testBothRunsHaveChineseTitles() {
        for run in RetrainingRun.allCases {
            XCTAssertFalse(run.title.isEmpty, "\(run) 没有标题")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingStepTests`
Expected: 编译失败 —— `RetrainingStep` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Retraining/RetrainingStep.swift`：

```swift
import Foundation

/// 「带着本题进入复训」的三步：回看证据 → 重答原题 → 撤掉提示，开口说。
///
/// **撤掉的是答案，留下的是目标。** 原话、原答、高分版属于答案，开口前必须收走；
/// 「本次唯一目标」是一句行为指令（「回答后补一个原因和例子」），要一直留着。
/// 前者撤掉，复训才不是朗读；后者留着，复训才不是随便再练一遍。
public enum RetrainingStep: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 第一步：回看当时到底说了什么，以及复盘给的高分版长什么样。
    case evidence
    /// 第二步：提示已经撤掉，屏幕上只剩题目和这一次的唯一目标。
    case rehearsal
    /// 第三步：练习进行中，什么范答都不给看。
    case speaking

    public var id: String { rawValue }

    public var stepNumber: Int {
        switch self {
        case .evidence: return 1
        case .rehearsal: return 2
        case .speaking: return 3
        }
    }

    public var title: String {
        switch self {
        case .evidence: return "回看证据"
        case .rehearsal: return "重答原题"
        case .speaking: return "撤掉提示，开口说"
        }
    }

    public var explanation: String {
        switch self {
        case .evidence:
            return "先看清上次到底说了什么，以及复盘给的高分版是什么样。"
                + "下一步：点「重答这道题」，证据和高分版会被收走，只留下题目和这次的目标。"
        case .rehearsal:
            return "提示已经撤掉了——照着高分版念一遍不叫复训。"
                + "下一步：点「开始练习」，对着 ChatGPT 把这道题重新答一遍，答的时候记着这一次的目标。"
        case .speaking:
            return "练习进行中，屏幕上不会再出现任何范答。"
                + "下一步：说完之后点「我练完了」，复盘会自动取回并存档。"
        }
    }

    /// 是否显示当时说过的原话与逐字稿。
    public var showsEvidence: Bool { self == .evidence }

    /// 是否显示复盘给的高分版。**只有第一步能显示。**
    public var showsModelAnswer: Bool { self == .evidence }

    /// 是否显示「本次唯一目标」那一行。**三步都要显示**，理由见类型注释。
    public var showsGoal: Bool { true }

    /// 这一步能不能按「开始练习」。
    public var canStartPractice: Bool { self == .rehearsal }

    public var next: RetrainingStep? {
        switch self {
        case .evidence: return .rehearsal
        case .rehearsal: return .speaking
        case .speaking: return nil
        }
    }
}

/// 这一趟复训练的是原题还是换的题。
public enum RetrainingRun: String, CaseIterable, Equatable, Sendable {
    /// 重答原题。
    case original
    /// 换一道题验证。
    case transfer

    /// 换题验证**不再回看证据**：正因为不给看，才知道是不是真会了，
    /// 还是只记住了那个答案（DEFINITION-OF-DONE 第 2 节）。
    public var firstStep: RetrainingStep {
        switch self {
        case .original: return .evidence
        case .transfer: return .rehearsal
        }
    }

    public var title: String {
        switch self {
        case .original: return "带着这个目标重答原题"
        case .transfer: return "换一道题验证"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingStepTests`
Expected: PASS（10 个测试）

- [ ] **Step 5: 突变验证**

1. 把 `showsModelAnswer` 改成 `{ self != .speaking }`（即 rehearsal 也显示高分版——这是实现时最容易「顺手放宽」的一处），重跑：`testModelAnswerIsOnlyVisibleWhileReviewingEvidence` **必须变红**。
   *守的是：学员在开口前一眼扫到高分版，复训退化成朗读，而界面上完全看不出异常。*
2. 把 `RetrainingRun.transfer.firstStep` 改成 `.evidence`，重跑：`testTransferRunSkipsTheEvidenceStep` **必须变红**。
   *守的是：换题验证前又给看了一遍答案，验证就废了。*

都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Retraining/RetrainingStep.swift Tests/IELTSCoachUITests/RetrainingStepTests.swift
git commit -m "feat(ui): 复训三步流程与撤掉提示的规则"
```

---

## Task 6: 复训中心的待复训列表

**Files:**
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingCenterViewModel.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingCenterViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState`、`RetrainingPolicy.rank(targets:issues:)`、`RetrainingLedger.progress(for:sessions:)`、`RetrainingProgress`、`RetrainingStage`
- Produces:
  - `enum RetrainingSourceIssue: Equatable, Sendable { case sessionMissing, questionMissing }`，含 `message: String`
  - `struct RetrainingItem: Equatable, Sendable, Identifiable`，含 `target`、`progress`、`originalQuestion: Question?`、`sourceIssue: RetrainingSourceIssue?`、`id: String`、`statusLabel: String`、`canRetryOriginal: Bool`
  - `struct RetrainingCenterViewModel: Sendable`，含 `init(state:)`、`pending: [RetrainingItem]`、`retired: [RetrainingItem]`、`emptyStateMessage: String`、`item(id:) -> RetrainingItem?`

**排序必须直接用 `RetrainingPolicy.rank`，不许在这里另写一套。** 那个函数已经实现并测过：证据命中高频错题的目标排前面，已退休的不参与。在界面层再排一次，只会造出第二套说法。

**源题找不到不许藏起来。** 目标 → 来源 session → 题目，这条链有两处会断：训练记录被单条删除（Phase 4 的功能），或者换季导入了新题库、旧题不在了（`DEFINITION-OF-DONE` 硬标准第 12 条讲的正是这件事）。断了就写清楚断在哪、下一步怎么办，**而不是让那一条从列表里消失**——凭空消失会让用户以为练习记录丢了。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RetrainingCenterViewModelTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingCenterViewModelTests: XCTestCase {
    private func target(_ key: String, session: String, evidence: [String],
                        status: String = "new") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: "目标-\(key)", status: status,
                         evidence: evidence, sourceSessionId: session,
                         createdAt: "2026-08-0\(session.count)T10:00:00Z")
    }

    private func session(_ id: String, question: String,
                         link: RetrainingLink? = nil) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "reports/\(id).json",
                        recordingPath: "", retraining: link)
    }

    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "prompt-\(id)")
    }

    /// 排序是 RetrainingPolicy.rank 的职责，界面不许另排一套。
    func testPendingFollowsRetrainingPolicyRank() {
        var state = CoachState.empty()
        state.targets = [target("rare", session: "s1", evidence: ["I just like it."]),
                         target("common", session: "s2", evidence: ["I very like it."])]
        state.issues = [IssueRecord(id: "i1", learnerSaid: "I very like it.",
                                    correction: "I really like it.", whyItMatters: "",
                                    occurrences: 5, sourceSessionIds: ["s2"], lastSeenAt: "t")]
        state.sessions = [session("s1", question: "q1"), session("s2", question: "q2")]
        state.questions = [question("q1"), question("q2")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.map(\.id), ["common@s2", "rare@s1"])
        XCTAssertEqual(vm.pending.map(\.target),
                       RetrainingPolicy.rank(targets: state.targets, issues: state.issues),
                       "顺序必须与 RetrainingPolicy.rank 完全一致")
    }

    func testRetiredTargetsLeavePendingButAreStillListed() {
        var state = CoachState.empty()
        state.targets = [target("live", session: "s1", evidence: []),
                         target("done", session: "s2", evidence: [], status: "retired")]
        state.sessions = [session("s1", question: "q1"), session("s2", question: "q2")]
        state.questions = [question("q1"), question("q2")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.map(\.id), ["live@s1"])
        XCTAssertEqual(vm.retired.map(\.id), ["done@s2"],
                       "退休的目标不能凭空消失——用户会以为记录丢了")
    }

    func testStatusLabelReflectsProgress() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: [])]
        let l = RetrainingLink(targetKey: "k", sourceSessionId: "s0", originalQuestionId: "q1")
        state.sessions = [session("s0", question: "q1"),
                          session("s1", question: "q1", link: l)]
        state.questions = [question("q1")]

        let onlyOriginal = RetrainingCenterViewModel(state: state)
        XCTAssertTrue(onlyOriginal.pending[0].statusLabel.contains("换题验证"),
                      "只重练了原题时，必须提醒还差换题验证——这是本产品的价值所在")

        state.sessions.append(session("s2", question: "q9", link: l))
        let withTransfer = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(withTransfer.pending[0].progress.stage, .triedTransfer)
        XCTAssertTrue(withTransfer.pending[0].statusLabel.contains("1"),
                      "换题验证做过几次要显示出来")
    }

    /// 换季导入新题库后旧题可能不在了（DEFINITION-OF-DONE 硬标准第 12 条）。
    /// 这时必须说清楚，而不是让这一条从列表里消失。
    func testMissingSourceQuestionIsReportedNotHidden() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: ["I just like it."])]
        state.sessions = [session("s0", question: "已经不在题库里的题")]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.count, 1)
        XCTAssertEqual(vm.pending[0].sourceIssue, .questionMissing)
        XCTAssertNil(vm.pending[0].originalQuestion)
        XCTAssertFalse(vm.pending[0].canRetryOriginal)
        XCTAssertTrue(vm.pending[0].sourceIssue!.message.contains("下一步"))
    }

    func testMissingSourceSessionIsReportedNotHidden() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "被删掉的记录", evidence: [])]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.pending.count, 1)
        XCTAssertEqual(vm.pending[0].sourceIssue, .sessionMissing)
        XCTAssertTrue(vm.pending[0].sourceIssue!.message.contains("下一步"))
    }

    func testHealthyItemCarriesTheOriginalQuestionAndNoIssue() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: [])]
        state.sessions = [session("s0", question: "q1")]
        state.questions = [question("q1")]

        let item = RetrainingCenterViewModel(state: state).pending[0]
        XCTAssertNil(item.sourceIssue)
        XCTAssertEqual(item.originalQuestion?.id, "q1")
        XCTAssertTrue(item.canRetryOriginal)
    }

    /// targetKey 跨 session 会重复。按 key 查会取到错的那一条，
    /// 用户点开 A 目标却看到 B 目标的证据。
    func testLookupUsesFullIdentityNotJustTargetKey() {
        var state = CoachState.empty()
        state.targets = [target("k", session: "s0", evidence: ["老的那句"]),
                         target("k", session: "s1", evidence: ["新的那句"])]
        state.sessions = [session("s0", question: "q1"), session("s1", question: "q1")]
        state.questions = [question("q1")]

        let vm = RetrainingCenterViewModel(state: state)
        XCTAssertEqual(vm.item(id: "k@s1")?.target.evidence, ["新的那句"])
        XCTAssertEqual(vm.item(id: "k@s0")?.target.evidence, ["老的那句"])
        XCTAssertNil(vm.item(id: "k@不存在"))
    }

    func testEmptyStateSaysWhatToDoNext() {
        let vm = RetrainingCenterViewModel(state: .empty())
        XCTAssertTrue(vm.pending.isEmpty)
        XCTAssertTrue(vm.emptyStateMessage.contains("下一步"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingCenterViewModelTests`
Expected: 编译失败 —— `RetrainingCenterViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Retraining/RetrainingCenterViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 目标 → 来源练习 → 原题 这条链断在哪里。
/// **断了要说清楚，不能把这一条从列表里藏掉**——凭空消失会让用户以为练习记录丢了。
public enum RetrainingSourceIssue: Equatable, Sendable {
    /// 目标来源的那次练习记录已经不在了（多半是在训练记录里被单条删除）。
    case sessionMissing
    /// 记录还在，但题库里已经没有那道题了（多半是换季导入了新题库）。
    case questionMissing

    public var message: String {
        switch self {
        case .sessionMissing:
            return "这个目标来自的那次练习记录已经不在了，找不回当时练的是哪道题。"
                + "下一步：仍然可以带着这个目标从题库里自己挑一道题练；"
                + "「重答原题」这一条则用不了了。"
        case .questionMissing:
            return "当时那道题已经不在题库里了，多半是换季导入了新题库。"
                + "下一步：仍然可以带着这个目标从题库里自己挑一道题练；"
                + "想重答原题，就重新导入包含那道题的题库。"
        }
    }
}

public struct RetrainingItem: Equatable, Sendable, Identifiable {
    public let target: RetrainingTarget
    public let progress: RetrainingProgress
    /// 目标来源那次练的题。链断了就是 nil，此时 `sourceIssue` 非 nil。
    public let originalQuestion: Question?
    public let sourceIssue: RetrainingSourceIssue?

    public init(target: RetrainingTarget, progress: RetrainingProgress,
                originalQuestion: Question?, sourceIssue: RetrainingSourceIssue?) {
        self.target = target; self.progress = progress
        self.originalQuestion = originalQuestion; self.sourceIssue = sourceIssue
    }

    public var id: String { target.id }

    /// 「带着本题进入复训」这条路能不能走。
    public var canRetryOriginal: Bool { originalQuestion != nil }

    public var statusLabel: String {
        switch progress.stage {
        case .notStarted:
            return "还没开始复训"
        case .retriedOriginal:
            return "已重答原题 \(progress.originalRetrySessionIDs.count) 次，还差换题验证"
        case .triedTransfer:
            return "已换题验证 \(progress.transferSessionIDs.count) 次"
        }
    }
}

public struct RetrainingCenterViewModel: Sendable {
    public let state: CoachState

    public init(state: CoachState) { self.state = state }

    /// 待复训目标。**顺序直接来自 `RetrainingPolicy.rank`**：证据命中高频错题的排前面，
    /// 已退休的不参与。不要在这里另排一套——那会造出第二套说法。
    public var pending: [RetrainingItem] {
        RetrainingPolicy.rank(targets: state.targets, issues: state.issues).map(makeItem)
    }

    /// 已退休的目标。仍然列出来（折叠区），退休不等于删除。
    public var retired: [RetrainingItem] {
        state.targets
            .filter { $0.status == RetrainingStatus.retired.rawValue }
            .reversed()
            .map(makeItem)
    }

    public func item(id: String) -> RetrainingItem? {
        // 按完整身份（key@来源session）查，不能只按 targetKey：
        // targetKey 跨 session 会重复，按 key 查会取到错的那一条。
        guard let target = state.targets.first(where: { $0.id == id }) else { return nil }
        return makeItem(target)
    }

    public var emptyStateMessage: String {
        "还没有待复训的目标。下一步：先完整练一场，复盘会给出一个具体目标，它会自动出现在这里。"
    }

    // MARK: - 私有

    private func makeItem(_ target: RetrainingTarget) -> RetrainingItem {
        let progress = RetrainingLedger.progress(for: target, sessions: state.sessions)

        guard let source = state.sessions.first(where: { $0.id == target.sourceSessionId }) else {
            return RetrainingItem(target: target, progress: progress,
                                  originalQuestion: nil, sourceIssue: .sessionMissing)
        }
        guard let question = state.questions.first(where: { $0.id == source.questionId }) else {
            return RetrainingItem(target: target, progress: progress,
                                  originalQuestion: nil, sourceIssue: .questionMissing)
        }
        return RetrainingItem(target: target, progress: progress,
                              originalQuestion: question, sourceIssue: nil)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingCenterViewModelTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证**

1. 把 `pending` 改成 `state.targets.filter { $0.status != "retired" }.map(makeItem)`（即绕开 `rank`，用数组原序），重跑：`testPendingFollowsRetrainingPolicyRank` **必须变红**。
   *守的是：界面自己排一套，用户以为最该练的排在最前面，其实不是。*
2. 把 `makeItem` 里 `guard let question … else { return … .questionMissing }` 改成 `guard let question … else { return nil }`（需把 `makeItem` 改成返回 Optional 并在 `pending` 里 `compactMap`），重跑：`testMissingSourceQuestionIsReportedNotHidden` **必须变红**。
   *守的是：题库换季之后目标从列表里悄悄消失，用户以为练习记录丢了。*
3. 把 `item(id:)` 的匹配条件改成 `$0.targetKey == id.components(separatedBy: "@")[0]`，重跑：`testLookupUsesFullIdentityNotJustTargetKey` **必须变红**。

三处都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Retraining/RetrainingCenterViewModel.swift Tests/IELTSCoachUITests/RetrainingCenterViewModelTests.swift
git commit -m "feat(ui): 复训中心的待复训列表"
```

---

## Task 7: 证据装配 —— 回到你真正说过的话

**Files:**
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingEvidence.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingEvidenceTests.swift`

**Interfaces:**
- Consumes: `RetrainingTarget`、`JSONValue`、`PracticeSession.TranscriptTurn`
- Produces:
  - `struct RetrainingEvidence: Equatable, Sendable`，含 `quotes: [String]`、`originalAnswer: String`、`modelAnswer: String`、`changes: [String]`、`learnerTurns: [PracticeSession.TranscriptTurn]`、`missingNote: String?`
  - `RetrainingEvidenceBuilder.build(target:report:transcript:) -> RetrainingEvidence`

**这一步兑现 `DEFINITION-OF-DONE` 第 2 节的「回到你真正说过的话，而不是空泛点评」。** 四份材料：

| 来源 | 内容 | 可能缺席吗 |
|---|---|---|
| `target.evidence` | 复盘摘出来的原话 | 几乎不会（在 `state.json` 里）|
| 复盘 `answer_upgrades[].original_answer` | 当时的完整原答 | 会：报告文件读不到、或字段名对不上 |
| 复盘 `answer_upgrades[].revised_answer` + `changes` | 高分版与改了什么 | 同上 |
| `PracticeSession.transcript` | 逐字稿里学员说过的话 | 会：Phase 4 之前的记录没有逐字稿 |

**函数保持纯净：报告与逐字稿由调用方读好了传进来。** 文件 IO 放在 Task 10 的视图层，这样这段逻辑能完整测试。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RetrainingEvidenceTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingEvidenceTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    private func target(evidence: [String]) -> RetrainingTarget {
        RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                         evidence: evidence, sourceSessionId: "s0", createdAt: "t")
    }

    private func turn(_ role: String, _ text: String) -> PracticeSession.TranscriptTurn {
        PracticeSession.TranscriptTurn(role: role, text: text, capturedAt: "2026-08-05T10:00:00Z")
    }

    /// 一份复盘里通常有好几道题的原答。必须挑出**含有这条证据原话**的那一条，
    /// 否则学员看到的是另一道题的答案，整个「回看证据」就是错的。
    func testPicksTheUpgradeEntryThatContainsTheEvidenceQuote() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Do you like your hometown?","original_answer":"It is fine, nothing special.",
           "revised_answer":"It's a comfortable place...","changes":["补了原因"]},
          {"question":"Do you like reading?","original_answer":"I just like it.",
           "revised_answer":"I like it because it helps me switch off.","changes":["补了原因","补了例子"]}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["I just like it."]), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "I just like it.")
        XCTAssertEqual(evidence.modelAnswer, "I like it because it helps me switch off.")
        XCTAssertEqual(evidence.changes, ["补了原因", "补了例子"])
        XCTAssertNil(evidence.missingNote)
    }

    func testFallsBackToTheFirstUsableEntryWhenNothingMatches() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Q1","original_answer":"","revised_answer":"空原答的这条要跳过"},
          {"question":"Q2","original_answer":"Something I actually said.","revised_answer":"Better."}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["对不上的一句话"]), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "Something I actually said.")
        XCTAssertNil(evidence.missingNote, "有可用的原答就不算缺材料")
    }

    /// 报告读不到要说清楚。空着不说，用户只会看到一片空白，以为程序坏了。
    func testMissingReportIsExplainedNotSilentlyEmpty() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["I just like it."]), report: nil, transcript: [])
        XCTAssertEqual(evidence.quotes, ["I just like it."], "原话来自 state，报告读不到也还在")
        XCTAssertEqual(evidence.originalAnswer, "")
        let note = try? XCTUnwrap(evidence.missingNote)
        XCTAssertTrue((note ?? "").contains("下一步"))
    }

    /// ChatGPT 曾把数组输出成对象（spec 2.3.8）。界面绝不能崩，最多是这一块没内容。
    func testSurvivesWrongShapedAnswerUpgrades() throws {
        let value = try report(#"{"answer_upgrades":{"question":"Q","original_answer":"A"}}"#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: []), report: value, transcript: [])
        XCTAssertEqual(evidence.originalAnswer, "")
        XCTAssertNotNil(evidence.missingNote)
    }

    func testKeepsOnlyLearnerTurnsFromTheTranscript() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: []), report: nil,
            transcript: [turn("assistant", "Do you like reading?"),
                         turn("user", "I just like it."),
                         turn("user", "   "),
                         turn("assistant", "Why?")])
        XCTAssertEqual(evidence.learnerTurns.map(\.text), ["I just like it."],
                       "考官说的话不是「你说过的话」；空白轮次也不该占一行")
    }

    func testBlankQuotesAreDropped() {
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["  ", "I just like it.", ""]), report: nil, transcript: [])
        XCTAssertEqual(evidence.quotes, ["I just like it."])
    }

    func testQuoteMatchingIgnoresCase() throws {
        let value = try report(#"""
        {"answer_upgrades":[
          {"question":"Q1","original_answer":"Nothing here.","revised_answer":"X"},
          {"question":"Q2","original_answer":"I JUST LIKE IT, really.","revised_answer":"Y"}]}
        """#)
        let evidence = RetrainingEvidenceBuilder.build(
            target: target(evidence: ["i just like it"]), report: value, transcript: [])
        XCTAssertEqual(evidence.modelAnswer, "Y")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingEvidenceTests`
Expected: 编译失败 —— `RetrainingEvidenceBuilder` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Retraining/RetrainingEvidence.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 复训第一步要给学员看的全部材料。
public struct RetrainingEvidence: Equatable, Sendable {
    /// 复盘摘出来的原话。
    public let quotes: [String]
    /// 当时那道题的完整原答。
    public let originalAnswer: String
    /// 复盘给的高分版。**只在第一步显示**，见 RetrainingStep。
    public let modelAnswer: String
    /// 复盘写的「改了什么」。
    public let changes: [String]
    /// 逐字稿里学员自己说过的话。
    public let learnerTurns: [PracticeSession.TranscriptTurn]
    /// 材料不齐时的中文说明（发生了什么 + 下一步）。齐全时为 nil。
    public let missingNote: String?

    public init(quotes: [String], originalAnswer: String, modelAnswer: String,
                changes: [String], learnerTurns: [PracticeSession.TranscriptTurn],
                missingNote: String?) {
        self.quotes = quotes; self.originalAnswer = originalAnswer
        self.modelAnswer = modelAnswer; self.changes = changes
        self.learnerTurns = learnerTurns; self.missingNote = missingNote
    }
}

public enum RetrainingEvidenceBuilder {
    /// - Parameters:
    ///   - report: 目标来源那次练习的复盘。读不到就传 nil——**不要为了「看起来正常」编一份空的**。
    ///   - transcript: 那次练习的逐字稿。Phase 4 之前的老记录可能是空的，属正常。
    public static func build(target: RetrainingTarget,
                             report: JSONValue?,
                             transcript: [PracticeSession.TranscriptTurn]) -> RetrainingEvidence {
        let quotes = target.evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let learnerTurns = transcript.filter {
            $0.role == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let report, report.objectValue != nil else {
            return RetrainingEvidence(
                quotes: quotes, originalAnswer: "", modelAnswer: "", changes: [],
                learnerTurns: learnerTurns,
                missingNote: "这个目标来源那次练习的复盘报告读不到，屏幕上只剩复盘当时摘出来的原话。"
                    + "下一步：到「复盘报告」页确认那份报告还在不在；就算读不到，也可以带着目标继续复训。")
        }

        let upgrades = report["answer_upgrades"]?.arrayValue ?? []
        let usable = upgrades.filter { !($0["original_answer"] ?? .null).isBlank }
        // 先找含有证据原话的那一条；找不到再退回第一条可用的。
        // 直接取第一条会让学员看到另一道题的答案，「回看证据」整个就是错的。
        let matched = usable.first { entry in
            let original = entry["original_answer"]?.stringValue ?? ""
            return quotes.contains { original.localizedCaseInsensitiveContains($0) }
        } ?? usable.first

        guard let matched else {
            return RetrainingEvidence(
                quotes: quotes, originalAnswer: "", modelAnswer: "", changes: [],
                learnerTurns: learnerTurns,
                missingNote: "这份复盘里没有可对照的原答（answer_upgrades 是空的，"
                    + "或者字段名与本工具读的对不上）。"
                    + "下一步：上面的原话仍然可用；想看完整原答，到「复盘报告」页打开那次的完整报告。")
        }

        return RetrainingEvidence(
            quotes: quotes,
            originalAnswer: matched["original_answer"]?.stringValue ?? "",
            modelAnswer: matched["revised_answer"]?.stringValue ?? "",
            changes: (matched["changes"]?.arrayValue ?? []).compactMap(\.stringValue),
            learnerTurns: learnerTurns,
            missingNote: nil)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingEvidenceTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

1. 把挑选逻辑改成只 `usable.first`（去掉按原话匹配那一段），重跑：`testPicksTheUpgradeEntryThatContainsTheEvidenceQuote` **必须变红**。
   *守的是：学员回看到的是另一道题的答案，而屏幕上看不出任何异常。*
2. 把 `report == nil` 分支里的 `missingNote:` 改成 `nil`，重跑：`testMissingReportIsExplainedNotSilentlyEmpty` **必须变红**。
   *守的是：材料缺了却一声不吭，用户对着空白以为程序坏了。*

都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Retraining/RetrainingEvidence.swift Tests/IELTSCoachUITests/RetrainingEvidenceTests.swift
git commit -m "feat(ui): 复训证据装配（原话、原答、高分版、逐字稿）"
```

---

## Task 8: 复训会话与普通练习的区分

**Files:**
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingSetupBuilder.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingSetupBuilderTests.swift`

**Interfaces:**
- Consumes: `RetrainingTarget`、`Question`、`FocusPart`、`FeedbackTiming`、`Part2PrepMode`、`SessionSetup`、`ExaminerPrompt.build(setup:)`
- Produces:
  - `RetrainingSetupBuilder.goalText(for target: RetrainingTarget) -> String`
  - `RetrainingSetupBuilder.makeSetup(target:question:feedbackTiming:part2PrepMode:) -> SessionSetup`

**这就是「复训会话与普通练习的区分」的全部。** `ExaminerPrompt` 已经支持：`SessionSetup.goal` 非空时，提示词末尾会多一段

```
本次唯一目标：<目标>
考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
```

所以本任务不改 Core 的任何提示词，只负责**把目标正确地放进 `SessionSetup.goal`**，并用真实的 `ExaminerPrompt.build` 验证它确实出现在提示词里。

**测试直接调 `ExaminerPrompt.build`，但不碰 ChatGPT。** 它是纯字符串拼装函数，测它等于测「复训和普通练习到底有没有区别」这件事本身。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RetrainingSetupBuilderTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingSetupBuilderTests: XCTestCase {
    private func target(label: String, key: String = "logic-explain") -> RetrainingTarget {
        RetrainingTarget(targetKey: key, label: label, status: "new", evidence: [],
                         sourceSessionId: "s0", createdAt: "t")
    }

    private func question(_ id: String, part: Int) -> Question {
        Question(id: id, part: part, topic: "Home", prompt: "prompt-\(id)")
    }

    /// 复训会话的定义就在这一条上：考官提示词必须带上单点目标。
    func testRetrainingPromptCarriesTheSinglePointGoal() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "回答后补一个原因和例子"),
                                                     question: question("q1", part: 1))
        let prompt = ExaminerPrompt.build(setup: setup)
        XCTAssertTrue(prompt.contains("本次唯一目标：回答后补一个原因和例子"),
                      "没带上目标，这场就只是普通练习")
    }

    /// 对照组：普通练习的提示词里不该有目标段落。
    /// 两条一起看，才证明「区分」是真的存在，而不是两边都一样。
    func testPlainPracticePromptHasNoGoalBlock() {
        let plain = SessionSetup(question: question("q1", part: 1), focusPart: .part1,
                                 durationMinutes: 6, goal: "")
        XCTAssertFalse(ExaminerPrompt.build(setup: plain).contains("本次唯一目标"))
    }

    /// `RetrainingPolicy.extractTarget` 允许 label 为空（它只强制 id 非空）。
    /// label 一空，goal 就是空串，这场复训会**静默退化成普通练习**——
    /// 不报错、界面照常、只是这一场和复训毫无关系。
    func testEmptyLabelFallsBackToTargetKeySoTheGoalIsNeverBlank() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "   ", key: "logic-explain"),
                                                     question: question("q1", part: 1))
        XCTAssertEqual(setup.goal, "logic-explain")
        XCTAssertTrue(ExaminerPrompt.build(setup: setup).contains("本次唯一目标：logic-explain"))
    }

    func testGoalIsTrimmed() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "  补一个例子\n"),
                                                     question: question("q1", part: 1))
        XCTAssertEqual(setup.goal, "补一个例子")
    }

    func testFocusPartFollowsTheQuestionPart() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q1", part: 1)).focusPart,
                       .part1)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q2", part: 2)).focusPart,
                       .part2)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q3", part: 3)).focusPart,
                       .part3)
    }

    /// 题库里出现越界的 part（导入时可能有脏数据）不能让复训直接崩，
    /// 落到 full mock 是 FocusPart 里唯一的兜底取值。
    func testOutOfRangePartFallsBackToFullMock() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q9", part: 9)).focusPart,
                       .fullMock)
    }

    /// Part 2 是一段长答，时长与其他 Part 不同。与 coach practice 的既有取值保持一致。
    func testPart2GetsAShorterTargetLength() {
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q2", part: 2)).durationMinutes, 4)
        XCTAssertEqual(RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                        question: question("q1", part: 1)).durationMinutes, 6)
    }

    func testCarriesTheChosenPracticeModes() {
        let setup = RetrainingSetupBuilder.makeSetup(target: target(label: "L"),
                                                     question: question("q2", part: 2),
                                                     feedbackTiming: .immediate,
                                                     part2PrepMode: .learnerControlled)
        XCTAssertEqual(setup.feedbackTiming, .immediate)
        XCTAssertEqual(setup.part2PrepMode, .learnerControlled)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingSetupBuilderTests`
Expected: 编译失败 —— `RetrainingSetupBuilder` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Retraining/RetrainingSetupBuilder.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 把一个复训目标 + 一道题，变成一次**复训会话**的 `SessionSetup`。
///
/// 复训与普通练习的唯一区别就在 `goal`：`ExaminerPrompt` 在 goal 非空时会追加
/// 「本次唯一目标：…」一段，并要求考官不在考试过程中提及它、也不因此改变提问方式。
///
/// **不要为复训改 `ReviewRequestPrompt`。** 那份指令把八个顶层键与每项内部的字段名
/// 全写死了，`ReviewArchiver` 逐字对着它读；动它一句就可能让 ChatGPT 顺手改动输出形状，
/// 而这种失败不报错、不崩溃，只是悄悄什么都没归档（spec 2.3.8）。
public enum RetrainingSetupBuilder {
    /// 单点目标的文本。
    ///
    /// **label 为空时退回 targetKey**：`RetrainingPolicy.extractTarget` 只强制 id 非空，
    /// label 是允许为空的。goal 一旦是空串，`ExaminerPrompt` 就不会追加目标段落，
    /// 这场「复训」会静默退化成普通练习——不报错、界面照常，只是和复训毫无关系。
    public static func goalText(for target: RetrainingTarget) -> String {
        let label = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty
            ? target.targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
            : label
    }

    public static func makeSetup(target: RetrainingTarget,
                                 question: Question,
                                 feedbackTiming: FeedbackTiming = .deferred,
                                 part2PrepMode: Part2PrepMode = .countdown) -> SessionSetup {
        // FocusPart 的 raw value 就是 "Part 1"/"Part 2"/"Part 3"；
        // 题库里出现越界的 part 时落到 full mock，不让脏数据把复训整场卡死。
        let focusPart = FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
        return SessionSetup(question: question,
                            focusPart: focusPart,
                            // 与 coach practice 的既有取值一致：Part 2 是一段长答，4 分钟；其余 6 分钟。
                            durationMinutes: question.part == 2 ? 4 : 6,
                            goal: goalText(for: target),
                            feedbackTiming: feedbackTiming,
                            part2PrepMode: part2PrepMode)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingSetupBuilderTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证**

1. 把 `makeSetup` 里的 `goal: goalText(for: target)` 改成 `goal: ""`，重跑：`testRetrainingPromptCarriesTheSinglePointGoal` **必须变红**（`testEmptyLabelFallsBackToTargetKeySoTheGoalIsNeverBlank` 也会红）。
   *守的是本任务的全部意义：复训会话退化成普通练习，而界面上一点异常都没有。*
2. 把 `goalText` 里的 fallback 去掉（直接 `return label`），重跑：`testEmptyLabelFallsBackToTargetKeySoTheGoalIsNeverBlank` **必须变红**。

都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Retraining/RetrainingSetupBuilder.swift Tests/IELTSCoachUITests/RetrainingSetupBuilderTests.swift
git commit -m "feat(ui): 复训会话与普通练习的区分（提示词带单点目标）"
```

---

## Task 9: 复训编排 —— 跑完一场并挂上台账

**Files:**
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingCoordinator.swift`
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingOutcomeText.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingCoordinatorTests.swift`
- Create: `Tests/IELTSCoachUITests/RetrainingOutcomeTextTests.swift`
- Modify: `Sources/IELTSCoachUI/Session/PracticeRunner.swift`（只加 `finishedSessionID`，见前置依赖 P3；若已有则不改）

**Interfaces:**
- Consumes: `PracticeStage`、`PracticeRunner`、`SessionSetup`、`CoachState`、`RetrainingLedger`、`RetrainingLink`、`RetrainingSetupBuilder`、`RetrainingOutcome`
- Produces:
  - `protocol PracticeSessionLauncher: AnyObject`（`@MainActor`），含 `stage: PracticeStage { get }`、`finishedSessionID: String? { get }`、`start(setup: SessionSetup) async throws`、`finishPractice() async`
  - `extension PracticeRunner: PracticeSessionLauncher`
  - `@MainActor @Observable final class RetrainingCoordinator`，含 `init(launcher:mutate:)`、`failure: String?`、`linkedSessionID: String?`、`start(target:question:originalQuestionID:) async`、`finish(target:originalQuestionID:) async`
  - `RetrainingOutcomeText.headline(for:) -> String`、`RetrainingOutcomeText.detail(for:) -> String`

**为什么要一个窄协议：** `PracticeRunner` 里塞着 AX 驱动、剪贴板、归档；直接依赖它，本任务的测试就没法在不碰 ChatGPT 的前提下跑。协议只要四个成员，用假实现两行就能造出来——这正是 Phase 2 花力气做 `AXAccess` 接缝换来的红利。

**挂钩失败必须响。** 复训练完了却没挂上台账，用户会看到「已记录」而进度纹丝不动，且没有任何线索。这是本项目已知最危险的失败形态（`ArchiveOutcome.skipped` 的注释写的就是这件事）。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RetrainingCoordinatorTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

/// 可编程的假练习驱动。**不碰真的 ChatGPT**。
@MainActor
final class FakeLauncher: PracticeSessionLauncher {
    var stage: PracticeStage = .idle
    var finishedSessionID: String?
    var startError: Error?
    private(set) var startedSetups: [SessionSetup] = []
    private(set) var finishCount = 0

    func start(setup: SessionSetup) async throws {
        startedSetups.append(setup)
        if let startError {
            stage = .failed(startError.localizedDescription)
            throw startError
        }
        stage = .practicing
    }

    func finishPractice() async {
        finishCount += 1
        stage = .done
    }
}

/// 测试里的 state 容器。协调器只在主线程上用它。
@MainActor
final class StateBox {
    var state: CoachState
    init(_ state: CoachState) { self.state = state }
}

@MainActor
final class RetrainingCoordinatorTests: XCTestCase {
    private func target() -> RetrainingTarget {
        RetrainingTarget(targetKey: "logic-explain", label: "补一个原因和例子", status: "new",
                         evidence: [], sourceSessionId: "s0", createdAt: "t")
    }

    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "prompt-\(id)")
    }

    private func session(_ id: String, question: String) -> PracticeSession {
        PracticeSession(id: id, questionId: question, focusPart: .part1,
                        startedAt: "2026-08-06T10:00:00Z", endedAt: "2026-08-06T10:20:00Z",
                        goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func make(state: CoachState, launcher: FakeLauncher)
        -> (RetrainingCoordinator, StateBox) {
        let box = StateBox(state)
        let coordinator = RetrainingCoordinator(launcher: launcher,
                                                mutate: { body in body(&box.state) })
        return (coordinator, box)
    }

    func testStartMarksTheTargetAsSelectedAndSendsTheGoalIntoTheSetup() async {
        var state = CoachState.empty()
        state.targets = [target()]
        let launcher = FakeLauncher()
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.start(target: target(), question: question("q1"),
                                originalQuestionID: "q1")

        XCTAssertEqual(box.state.targets[0].status, "selected")
        XCTAssertEqual(launcher.startedSetups.count, 1)
        XCTAssertEqual(launcher.startedSetups[0].goal, "补一个原因和例子")
        XCTAssertNil(coordinator.failure)
    }

    func testFinishAttachesTheLinkToTheFinishedSession() async {
        var state = CoachState.empty()
        state.targets = [target()]
        state.sessions = [session("s9", question: "q-other")]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertEqual(launcher.finishCount, 1)
        XCTAssertEqual(box.state.sessions[0].retraining,
                       RetrainingLink(targetKey: "logic-explain", sourceSessionId: "s0",
                                      originalQuestionId: "q1"))
        XCTAssertEqual(box.state.sessions[0].retrainingKind, .transfer,
                       "练的是另一道题，就该记成换题验证")
        XCTAssertEqual(coordinator.linkedSessionID, "s9")
        XCTAssertNil(coordinator.failure)
    }

    /// **本任务最重要的一条。** 挂不上台账却一声不吭，用户会看到「已记录」
    /// 而复训进度纹丝不动，没有任何线索可查。
    func testMissingSessionIDIsReportedNotSwallowed() async {
        var state = CoachState.empty()
        state.targets = [target()]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = nil
        let (coordinator, _) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        let failure = try? XCTUnwrap(coordinator.failure)
        XCTAssertTrue((failure ?? "").contains("下一步"),
                      "失败信息必须说清发生了什么和下一步做什么")
        XCTAssertNil(coordinator.linkedSessionID)
    }

    func testAttachFailureOnAForeignSessionIsReported() async {
        var state = CoachState.empty()
        state.targets = [target()]
        var taken = session("s9", question: "q-other")
        taken.retraining = RetrainingLink(targetKey: "另一个目标", sourceSessionId: "sX",
                                          originalQuestionId: "qX")
        state.sessions = [taken]
        let launcher = FakeLauncher()
        launcher.finishedSessionID = "s9"
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.finish(target: target(), originalQuestionID: "q1")

        XCTAssertNotNil(coordinator.failure)
        XCTAssertEqual(box.state.sessions[0].retraining?.targetKey, "另一个目标",
                       "别人的挂钩不许被覆盖")
    }

    func testStartFailureDoesNotPretendTheRetrainingHappened() async {
        struct Boom: LocalizedError { var errorDescription: String? { "假装失败。下一步：这是测试用的。" } }
        var state = CoachState.empty()
        state.targets = [target()]
        state.sessions = [session("s9", question: "q1")]
        let launcher = FakeLauncher()
        launcher.startError = Boom()
        let (coordinator, box) = make(state: state, launcher: launcher)

        await coordinator.start(target: target(), question: question("q1"),
                                originalQuestionID: "q1")

        XCTAssertNotNil(coordinator.failure)
        XCTAssertNil(box.state.sessions[0].retraining, "没练成就不能记一笔")
        XCTAssertNil(coordinator.linkedSessionID)
    }
}
```

`Tests/IELTSCoachUITests/RetrainingOutcomeTextTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class RetrainingOutcomeTextTests: XCTestCase {
    func testEveryOutcomeHasChineseHeadlineAndDetail() {
        for outcome in RetrainingOutcome.allCases {
            XCTAssertFalse(RetrainingOutcomeText.headline(for: outcome).isEmpty, "\(outcome) 缺标题")
            XCTAssertFalse(RetrainingOutcomeText.detail(for: outcome).isEmpty, "\(outcome) 缺说明")
        }
    }

    /// 一次没被点名不等于改掉了。给一个看起来精确、实则站不住的结论，
    /// 会让人盯着结论而不是盯着问题——与「不预测雅思分数」是同一条原则
    /// （DEFINITION-OF-DONE 第 4 节）。
    func testGoodNewsIsNeverUpgradedIntoAVerdict() {
        let text = RetrainingOutcomeText.headline(for: .notNamedAgain)
            + RetrainingOutcomeText.detail(for: .notNamedAgain)
        for forbidden in ["已掌握", "已改掉", "已解决", "不用再练"] {
            XCTAssertFalse(text.contains(forbidden), "文案里出现了下结论的措辞：\(forbidden)")
        }
        XCTAssertTrue(RetrainingOutcomeText.headline(for: .notNamedAgain).contains("没有再被点名"))
    }

    func testEveryDetailTellsTheLearnerWhatToDoNext() {
        for outcome in RetrainingOutcome.allCases {
            XCTAssertTrue(RetrainingOutcomeText.detail(for: outcome).contains("下一步"),
                          "\(outcome) 的说明没写下一步该做什么")
        }
    }

    func testNoReportSaysTheDataIsMissingRatherThanClaimingSuccess() {
        let text = RetrainingOutcomeText.headline(for: .noReport)
            + RetrainingOutcomeText.detail(for: .noReport)
        XCTAssertFalse(text.contains("没有再被点名"), "拿不到复盘不能说成好消息")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RetrainingCoordinatorTests`
Expected: 编译失败 —— `PracticeSessionLauncher`、`RetrainingCoordinator` 未定义

Run: `swift test --filter RetrainingOutcomeTextTests`
Expected: 编译失败 —— `RetrainingOutcomeText` 未定义

- [ ] **Step 3: 实现**

先确认 `PracticeRunner` 有 `finishedSessionID`（前置依赖 P3），没有就按 P3 的补法加上。

`Sources/IELTSCoachUI/Retraining/RetrainingCoordinator.swift`：

```swift
import Foundation
import IELTSCoachCore
import Observation

/// 复训只需要练习驱动的四个能力。**刻意做窄**：`PracticeRunner` 里塞着 AX 驱动、
/// 剪贴板与归档，直接依赖它，本文件的测试就没法在不碰真 ChatGPT 的前提下跑。
@MainActor
public protocol PracticeSessionLauncher: AnyObject {
    var stage: PracticeStage { get }
    /// 本次练习归档后写进 `state.sessions` 的那条记录的 id。未完成时为 nil。
    var finishedSessionID: String? { get }
    func start(setup: SessionSetup) async throws
    func finishPractice() async
}

// PracticeRunner 已经具备这四个成员，直接声明遵从。
// 若它的 finishPractice 签名与协议不一致（例如带 throws），
// **不要去改 PracticeRunner**——在这里写一个适配方法，例如：
//     public func finishPractice() async { try? await finishPracticeThrowing() }
extension PracticeRunner: PracticeSessionLauncher {}

/// 跑一场复训会话，并把它挂到复训台账上。
@MainActor
@Observable
public final class RetrainingCoordinator {
    /// 出问题时给用户看的中文说明（发生了什么 + 下一步）。没问题时 nil。
    public private(set) var failure: String?
    /// 成功挂上台账的那条训练记录 id。
    public private(set) var linkedSessionID: String?

    private let launcher: any PracticeSessionLauncher
    private let mutate: ((inout CoachState) -> Void) throws -> Void

    /// - Parameter mutate: 执行一次 state 变更。App 里传
    ///   `{ body in try store.mutate { state in body(&state) } }`；测试里传一个内存容器。
    public init(launcher: any PracticeSessionLauncher,
                mutate: @escaping ((inout CoachState) -> Void) throws -> Void) {
        self.launcher = launcher
        self.mutate = mutate
    }

    /// 开一场复训：先把目标标成「正在练」，再启动练习。
    ///
    /// 标记放在启动之前是刻意的：万一中途崩溃，用户下次打开至少能看到自己选过它，
    /// 而不是回到「还没开始」——练了半场的事实不该被抹掉。
    public func start(target: RetrainingTarget, question: Question,
                      originalQuestionID: String) async {
        failure = nil
        linkedSessionID = nil

        do {
            try mutate { _ = RetrainingLedger.setStatus(.selected, of: target.id, in: &$0) }
        } catch {
            // 标记失败不阻断练习——练习本身比台账重要，但必须说出来。
            failure = "没能把这个目标标记成「正在复训」：\(error.localizedDescription)"
                + " 下一步：练习可以照常进行；练完若进度没更新，到「训练记录」页确认这一场是否已存档。"
        }

        do {
            try await launcher.start(
                setup: RetrainingSetupBuilder.makeSetup(target: target, question: question))
        } catch {
            failure = "这场复训没能启动：\(error.localizedDescription)"
        }
    }

    /// 练完之后收尾：让驱动把复盘取回并归档，然后把这一场挂到台账上。
    public func finish(target: RetrainingTarget, originalQuestionID: String) async {
        await launcher.finishPractice()

        guard let sessionID = launcher.finishedSessionID else {
            failure = "这场复训已经练完，复盘也走的是原来的存档流程，"
                + "但没能拿到本次练习的记录编号，因此没挂进复训进度。"
                + "下一步：到「训练记录」页确认这一场在不在；在的话复盘没丢，"
                + "只是这次不计入「换题验证」的次数。"
            return
        }

        let link = RetrainingLink(targetKey: target.targetKey,
                                  sourceSessionId: target.sourceSessionId,
                                  originalQuestionId: originalQuestionID)
        do {
            var attached = false
            try mutate { attached = RetrainingLedger.attach(link, toSessionWithID: sessionID, in: &$0) }
            if attached {
                linkedSessionID = sessionID
            } else {
                failure = "这场复训已经存档，但没能挂进复训进度："
                    + "训练记录「\(sessionID)」已经属于另一个复训目标，没有覆盖它。"
                    + "下一步：到「训练记录」页看看这一场是不是重复归档了；复盘本身没有丢。"
            }
        } catch {
            failure = "这场复训已经存档，但写复训进度时出错：\(error.localizedDescription)"
                + " 下一步：复盘没有丢；重开一次 App 再看复训中心，若进度仍未更新，请反馈这条信息。"
        }
    }
}
```

`Sources/IELTSCoachUI/Retraining/RetrainingOutcomeText.swift`：

```swift
import Foundation
import IELTSCoachCore

/// 换题验证结果的文案。
///
/// **措辞上限是「这一次没有再被点名」。** 不许升级成「已掌握」「已改掉」这类结论：
/// ChatGPT 可能换个 id 说同一件事，也可能这次碰巧没抓到。给一个看起来精确、
/// 实则站不住的结论，会让人盯着结论而不是盯着问题——与「不预测雅思分数」
/// 是同一条原则（DEFINITION-OF-DONE 第 4 节）。
public enum RetrainingOutcomeText {
    public static func headline(for outcome: RetrainingOutcome) -> String {
        switch outcome {
        case .noReport: return "这一场还没有可对照的复盘"
        case .namedAgain: return "这个目标又被点了一次"
        case .notNamedAgain: return "这一次没有再被点名"
        }
    }

    public static func detail(for outcome: RetrainingOutcome) -> String {
        switch outcome {
        case .noReport:
            return "复盘还没取回来，或取回的内容不成形，所以判断不了这次表现。"
                + "下一步：到「复盘报告」页看看这一场的报告在不在；不在的话可以重新生成一次复盘。"
        case .namedAgain:
            return "ChatGPT 在这次的复盘里又把同一个目标挑了出来，说明它还在。"
                + "下一步：再换一道题练一次，或者回到证据看看这次和上次差在哪。"
        case .notNamedAgain:
            return "ChatGPT 这次的复盘没有再挑出这个目标。"
                + "注意它换个说法描述同一件事也是可能的，一次结果说明不了全部。"
                + "下一步：再换一道题练一次会更有把握；也可以到「问题档案」看这个毛病的出现次数在怎么变。"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RetrainingCoordinatorTests`
Expected: PASS（5 个测试）

Run: `swift test --filter RetrainingOutcomeTextTests`
Expected: PASS（4 个测试）

- [ ] **Step 5: 突变验证**

1. 把 `finish` 里 `guard let sessionID … else { … }` 的整个 else 体换成 `return`（拿不到 id 就悄悄返回），重跑：`testMissingSessionIDIsReportedNotSwallowed` **必须变红**。
   *守的是：用户练完一场复训，界面一切正常，而进度永远停在「还没开始」，没有任何线索。*
2. 把 `attached` 为 false 时的 `failure = …` 删掉，重跑：`testAttachFailureOnAForeignSessionIsReported` **必须变红**。
3. 把 `RetrainingOutcomeText.headline(for: .notNamedAgain)` 改成 `"这个问题已经改掉了"`，重跑：`testGoodNewsIsNeverUpgradedIntoAVerdict` **必须变红**。
   *守的是「决定 4」：不替用户宣布一个站不住的结论。*

三处都改回，`swift test` 全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Retraining/RetrainingCoordinator.swift Sources/IELTSCoachUI/Retraining/RetrainingOutcomeText.swift Sources/IELTSCoachUI/Session/PracticeRunner.swift Tests/IELTSCoachUITests/RetrainingCoordinatorTests.swift Tests/IELTSCoachUITests/RetrainingOutcomeTextTests.swift
git commit -m "feat(ui): 复训编排与结果文案"
```

> 若 `PracticeRunner.swift` 这次没有改动，把它从 `git add` 里去掉。**不要用 `git add -A`。**

---

## Task 10: 复训中心页、复训流程页与导航接线

**Files:**
- Create: `Sources/IELTSCoachUI/NavigationState.swift`
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingCenterView.swift`
- Create: `Sources/IELTSCoachUI/Retraining/RetrainingFlowView.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/AppState.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Sources/IELTSCoachUI/Today/TodayView.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Tests/IELTSCoachUITests/NavigationStateTests.swift`

**Interfaces:**
- Consumes: `RetrainingCenterViewModel`、`RetrainingItem`、`RetrainingStep`、`RetrainingRun`、`RetrainingEvidenceBuilder`、`RetrainingCoordinator`、`RetrainingOutcome`、`RetrainingOutcomeText`、`TransferQuestionPolicy`、`RetrainingLedger`、`Palette`/`Spacing`/`Radius`、`CoachCard`/`PrimaryActionCard`/`SectionHeader`/`EmptyStateView`
- Produces:
  - `@Observable final class NavigationState`，含 `selection: SidebarItem`、`pendingRetrainingTargetID: String?`、`openRetrainingCenter(preselecting:)`、`consumePendingRetrainingTarget() -> String?`
  - `AppState.navigation: NavigationState`
  - `RetrainingCenterView`、`RetrainingFlowView`
  - `SidebarItem.isImplemented` 把 `.retraining` 算进去

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/NavigationStateTests.swift`：

```swift
import XCTest
@testable import IELTSCoachUI

@MainActor
final class NavigationStateTests: XCTestCase {
    func testOpenRetrainingCenterSelectsThePageAndRemembersTheTarget() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: "logic-explain@s0")
        XCTAssertEqual(nav.selection, .retraining)
        XCTAssertEqual(nav.pendingRetrainingTargetID, "logic-explain@s0")
    }

    func testOpeningWithoutATargetJustSwitchesPage() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: nil)
        XCTAssertEqual(nav.selection, .retraining)
        XCTAssertNil(nav.pendingRetrainingTargetID)
    }

    /// 只消费一次。不清空的话，用户在复训中心点开别的目标，
    /// 界面每次重绘都会把他弹回最初那个目标——他会以为点不动。
    func testPendingTargetIsConsumedOnlyOnce() {
        let nav = NavigationState()
        nav.openRetrainingCenter(preselecting: "logic-explain@s0")
        XCTAssertEqual(nav.consumePendingRetrainingTarget(), "logic-explain@s0")
        XCTAssertNil(nav.consumePendingRetrainingTarget())
        XCTAssertNil(nav.pendingRetrainingTargetID)
    }

    func testDefaultsToToday() {
        XCTAssertEqual(NavigationState().selection, .today)
    }
}
```

`Tests/IELTSCoachUITests/NavigationTests.swift` 的改动：找到那条断言「已实现页面集合」的测试（Phase 3 里叫 `testPhase3ImplementsExactlyThreePages`；若 Phase 4/5 已经改过名或改过集合，**以现状为准**，只往集合里加 `.retraining`，不要把别人加的删掉）。改成：

```swift
    func testSidebarMarksExactlyTheImplementedPages() {
        // 断言集合而不是「至少包含」—— 多标一个，用户会点进一个空页面；
        // 少标一个，做好的页面用户根本看不到。
        // Phase 6 把「复训中心」加了进来。Phase 4/5 已加的条目不要删。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertTrue(implemented.contains(.retraining), "复训中心这一页本阶段已经做完")
    }
```

**注意：** 若现有测试断言的是完整集合（`XCTAssertEqual(Set(implemented), [...])`），保留那种写法，只把 `.retraining` 加进期望集合里；上面这段只是在无法确定其他阶段状态时的写法。二选一，不要两条都留。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter NavigationStateTests`
Expected: 编译失败 —— `NavigationState` 未定义

Run: `swift test --filter NavigationTests`
Expected: 失败 —— `.retraining` 还没被标为已实现

- [ ] **Step 3: 实现（非 View 的部分，给完整代码）**

`Sources/IELTSCoachUI/NavigationState.swift`：

```swift
import Foundation
import Observation

/// 侧边栏选中项与跨页跳转意图。
///
/// **单独成类是为了能测**：`AppState` 的 init 会读磁盘、探辅助功能权限，
/// 在单元测试里既慢又依赖环境；导航是纯内存状态，拆出来就能直接测。
@MainActor
@Observable
public final class NavigationState {
    public var selection: SidebarItem = .today

    /// 从别的页面跳过来时要预先选中的复训目标（`RetrainingTarget.id`）。
    public private(set) var pendingRetrainingTargetID: String?

    public init() {}

    public func openRetrainingCenter(preselecting targetID: String?) {
        pendingRetrainingTargetID = targetID
        selection = .retraining
    }

    /// 取出并清空。**必须只生效一次**：不清空的话，用户在复训中心点开别的目标，
    /// 每次重绘都会被弹回最初那个目标，他会以为界面点不动。
    public func consumePendingRetrainingTarget() -> String? {
        defer { pendingRetrainingTargetID = nil }
        return pendingRetrainingTargetID
    }
}
```

`Sources/IELTSCoachUI/Navigation.swift`：把 `.retraining` 加进 `isImplemented`：

```swift
    public var isImplemented: Bool {
        switch self {
        // Phase 6 起「复训中心」已实现。其他阶段加的条目保留，不要删。
        case .today, .questionBank, .reviewReports, .retraining: return true
        default: return false
        }
    }
```

`Sources/IELTSCoachUI/AppState.swift`：加一个属性（**若 Phase 4/5 已经加过等价的导航状态，直接复用，不要再加第二个**）：

```swift
    /// 侧边栏选中项与跨页跳转意图。
    public let navigation = NavigationState()
```

`Sources/IELTSCoachUI/RootView.swift` 三处改动：

1. 把 `@State private var selection: SidebarItem = .today` 删掉，列表与 detail 一律改用 `app.navigation.selection`（`List(SidebarItem.allCases, selection: $app.navigation.selection)`）
2. `detail` 的 `switch` 增加 `case .retraining: RetrainingCenterView(app: app)`
3. `PlaceholderView.comingSoon` 里删掉 `.retraining` 那一行——这一页已经做了，留着是会误导人的死文案

`Sources/IELTSCoachUI/Today/TodayView.swift`：`PracticeRoute.retrain` 那张卡片的动作改为

```swift
app.navigation.openRetrainingCenter(preselecting: nil)
```

（`TodayViewModel.availableRoutes` 已经保证只有存在未退休目标时这条路线才出现，这里不必再判一次。）

- [ ] **Step 4: 实现（View 部分，只给验收要求，不给布局代码）**

**通用要求（两页都适用）：**

- 一切颜色、字号、圆角走 `Palette` / `Spacing` / `Radius`，视图里不得出现字面值
- 卡片用 `CoachCard`，主行动用 `PrimaryActionCard`，区块标题用 `SectionHeader`，空状态用 `EmptyStateView`
- 图标只用 SF Symbols，不用 emoji
- **每页只有一个主行动**
- 统计数字用 `.monospacedDigit()`
- 尊重「减弱动态效果」（`@Environment(\.accessibilityReduceMotion)`），开启时不做过渡动画
- 任何超过 300ms 的操作都要有进度提示

#### `RetrainingCenterView`（复训中心页）

必须显示：

1. `SectionHeader`，形如 `04 / RETRAINING / 一次只解决一个问题`
2. **待复训列表**，顺序就是 `RetrainingCenterViewModel.pending` 的顺序，**不许在视图里再排一次**。每条显示：
   - `item.target.label`（label 为空时显示 `item.target.targetKey`）
   - 第一条证据原话（`item.target.evidence.first`），有就显示，没有就不显示这一行
   - `item.statusLabel`
   - 来源日期（`item.target.createdAt`，显示成人能读的日期）
   - 原题（`item.originalQuestion?.prompt`）
3. 每条一个主行动：
   - `item.canRetryOriginal == true` → **「带着本题进入复训」**，点了打开 `RetrainingFlowView`，`run = .original`
   - `item.canRetryOriginal == false` → 改为显示 `item.sourceIssue!.message` 全文，主行动换成「挑一道题带着这个目标练」，点了直接打开换题选择（`TransferQuestionPolicy` 需要 `originalQuestion`，此路径下改为按 `item.target` 从题库自由选题，选中后仍走 `RetrainingFlowView`，`run = .transfer`）
4. 已经重答过原题的条目，额外显示次一级动作 **「换一道题验证」**
5. **空状态**（`pending` 为空）：显示 `vm.emptyStateMessage`，配一个跳到「今日训练」的按钮
6. 底部一个可折叠的「已经不用再练的目标」区，列出 `vm.retired`，每条给「重新放回待复训」（把状态改回 `.new`）
7. 页面出现时读一次 `app.navigation.consumePendingRetrainingTarget()`，非 nil 就自动选中并滚动到那一条

**绝对不能出现的：** 待复训列表按自己的规则排序；源题找不到时把这一条藏起来；退休目标凭空消失。

#### `RetrainingFlowView`（复训流程页，用 sheet 呈现）

顶部固定一条三步进度指示（`RetrainingStep.allCases` 的 `stepNumber` + `title`，当前步高亮）。`run == .transfer` 时第一步显示为已跳过（见「决定 3」）。

正文按 `RetrainingStep` 显示，**每一步都要显示 `step.explanation`**：

| 步骤 | 屏幕上必须有 | 屏幕上绝对不能有 |
|---|---|---|
| `.evidence` | 证据原话列表、`evidence.originalAnswer`、`evidence.modelAnswer`、`evidence.changes`、逐字稿里学员说过的话；`evidence.missingNote` 非 nil 时原样显示出来；主行动「重答这道题」 | — |
| `.rehearsal` | 题目全文、「本次唯一目标：…」一行、主行动「开始练习」 | **任何范答**：`modelAnswer`、`originalAnswer`、证据原话 |
| `.speaking` | 复用 Phase 3 的 `PracticeSheet`（阶段文案、进度、「我练完了」）、「本次唯一目标：…」一行 | 同上 |

练完（`coordinator` 收尾之后）显示结果卡片：

- `RetrainingOutcomeText.headline(for:)` 与 `detail(for:)`
- `coordinator.failure` 非 nil 时**原文显示出来**，不许折叠、不许省略
- 两个后续动作：
  - **「换一道题验证」**——列出 `TransferQuestionPolicy.candidates(...)` 的前 5 条，`sameTopicAsOriginal` 的条目标注「和原题同一个话题，验证力度打折」；候选为空时给 `EmptyStateView`：「题库里没有第二道 Part N 的题可以换。下一步：到「训练题库」导入更多题目。」并配跳转按钮
  - **「这个问题我不用再练了」**——调 `RetrainingLedger.setStatus(.retired, …)`。**这个动作只能由用户点，系统不许自动做**（见「决定 4」）

复盘读取（这一段是文件 IO，放在视图层）：

```swift
// 若 Phase 3/4 已经有「按 session 读复盘」的函数，直接复用，不要再写一份。
private func loadReport(for session: PracticeSession, in directory: DataDirectory) -> JSONValue? {
    guard !session.reportPath.isEmpty else { return nil }
    let url = directory.root.appending(path: session.reportPath)
    guard let text = try? String(contentsOf: url, encoding: .utf8),
          let value = try? JSONValue.decode(from: text) else { return nil }
    return value
}
```

**读不到就传 nil 给 `RetrainingEvidenceBuilder`，不要编一份空的顶上。** 它会给出中文说明，那才是用户需要的（Task 7 已经测过）。

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter NavigationStateTests`
Expected: PASS（4 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 6: 突变验证**

把 `NavigationState.consumePendingRetrainingTarget()` 里的 `defer { pendingRetrainingTargetID = nil }` 删掉，重跑：`testPendingTargetIsConsumedOnlyOnce` **必须变红**。改回后确认全绿。

*守的是：用户从今日训练跳进复训中心后，想点别的目标却每次都被弹回最初那一个，界面看起来像卡住了。*

- [ ] **Step 7: 提交**

```bash
git add Sources/IELTSCoachUI/NavigationState.swift Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/AppState.swift Sources/IELTSCoachUI/RootView.swift Sources/IELTSCoachUI/Today/TodayView.swift Sources/IELTSCoachUI/Retraining/RetrainingCenterView.swift Sources/IELTSCoachUI/Retraining/RetrainingFlowView.swift Tests/IELTSCoachUITests/NavigationStateTests.swift Tests/IELTSCoachUITests/NavigationTests.swift
git commit -m "feat(ui): 复训中心页、复训流程页与导航接线"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase6-acceptance.md`

前面所有测试跑在纯逻辑上，证明的是「数据变换对」，不是「这个流程好不好用」。下面每一条只能人来判断。

**这一步必须用户亲自做，任何自动化都绕不过去**（ROADMAP 3.4）：它需要真的对着 ChatGPT 说英语，且要判断「哪里让我不想用」。

- [ ] **Step 1: 打包并打开**

```bash
cd ~/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

Expected: 不需要重新授权辅助功能（签名稳定，Phase 3 已验证）。若又要求授权，**立刻停下报告**——那是打包方案出了问题，不是本阶段的事。

- [ ] **Step 2: 造一个真实的复训目标**

从今日训练页完整练一场（普通练习），练完确认复盘已归档、「重训目标」数字从 0 变正。

**若已经有练过的记录，跳过这一步直接用它。**

- [ ] **Step 3: 复训中心页逐项验收**

| 看什么 | 判据 |
|---|---|
| 待复训列表 | 目标出现了吗？label 是人话吗？证据原话对得上吗？ |
| 排序 | 出现次数多的问题排在前面吗？（对照「问题档案」里的次数，Phase 7 之前可直接看 `state.json` 的 `issues[].occurrences`）|
| 进度文案 | 「还没开始复训」显示对吗？ |
| 空状态 | 把 `state.json` 的 `targets` 临时清空（先备份！），页面是不是给了说明 + 下一步 + 按钮，而不是一片空白 |
| 未实现的六页 | 占位文字还在吗？「复训中心」不该再出现在占位里 |

- [ ] **Step 4: 走完「带着本题进入复训」（本阶段的成败判据之一）**

1. 点「带着本题进入复训」
2. **第一步**：当时的原话、原答、高分版、逐字稿都看得到吗？哪一样缺了、缺的时候有没有说清楚？
3. 点「重答这道题」
4. **第二步：盯着屏幕看一遍——还看得见高分版吗？** 看得见就是缺陷，立刻记下来
5. 点「开始练习」，真的把这道题重答一遍
6. **第三步进行中：屏幕上有没有任何范答漏出来？**「本次唯一目标」那一行在不在？
7. 点「我练完了」，等复盘回来

- [ ] **Step 5: 验证复训会话真的和普通练习不一样**

打开 ChatGPT 窗口，往上翻到这次发出去的考官提示词，确认末尾有：

```
本次唯一目标：<你选的那个目标>
考试过程中不要提及这个目标，也不要因此改变提问方式。它只用于最后的复盘。
```

**没有这一段，Task 8 就是白做的。** 同时确认考官在考试过程中**没有**把这个目标念出来。

- [ ] **Step 6: 换题验证（本阶段真正的交付物）**

1. 结果卡片上点「换一道题验证」
2. **候选题是同一个 Part 吗？排在前面的是不是换了话题的？**
3. 同话题的候选有没有标注「验证力度打折」？
4. 选一道，走完流程（注意：这一趟**不应该**再让你回看证据）
5. 练完看结果文案——它有没有说「已掌握」这类话？**说了就是缺陷**
6. 回到复训中心，那条目标的状态是不是变成了「已换题验证 1 次」

- [ ] **Step 7: 检查落盘**

```bash
python3 -c "
import json,os
p=os.path.expanduser('~/Library/Application Support/IELTS Speaking Coach/state.json')
s=json.load(open(p))
for x in s['sessions'][-3:]:
    print(x['id'], x['questionId'], x.get('retraining'))
"
```

Expected: 最近两场复训会话都带 `retraining` 字段；原题那场的 `originalQuestionId` 与 `questionId` 相同，换题那场不同。

- [ ] **Step 8: 「复训一个旧问题」路线**

回到今日训练页，点「复训一个旧问题」→ 应当直接跳到复训中心。**数一下从双击图标到进入复训流程一共点了几次**（目标 ≤ 3）。

- [ ] **Step 9: 界面验收（对照 DESIGN-SYSTEM.md 第 6 节）**

逐条走那十条清单。本阶段最容易出问题的三条：

- 复训流程页的三步进度指示，在系统文字调到最大时会不会挤成一团
- 「减弱动态效果」打开后，步骤切换是不是无动画且功能正常
- 「已换题验证 N 次」这个数字用的是等宽数字吗（N 从 1 变 10 时整行不许抖）

- [ ] **Step 10: 记录并提交**

把每项的实际结果写进 `docs/phase6-acceptance.md`，含截图或原文描述。**包括不好的部分**——「哪里让我不想用」这类信息只有你有（`DEFINITION-OF-DONE` 第 5 节）。

特别要写清楚的一条：**换题验证这件事，用起来到底有没有让你更清楚「是真会了还是只记住了答案」。** 这是本阶段存在的全部理由；如果实际用下来它没做到，功能表上打多少勾都不算做完。

```bash
git add docs/phase6-acceptance.md
git commit -m "docs: Phase 6 真机验收结果"
```

---

## Phase 6 完成标准

- [ ] `swift test` 全绿
- [ ] 复训中心页可用，待复训列表的顺序**直接来自 `RetrainingPolicy.rank`**
- [ ] 「带着本题进入复训」三步流程走得通：回看证据 → 重答原题 → 撤掉提示
- [ ] **开口之后屏幕上不会出现任何范答**（人工验收 Step 4 第 4、6 点确认）
- [ ] 复训会话的考官提示词里确实带着单点目标（人工验收 Step 5 在 ChatGPT 窗口里确认）
- [ ] **换题验证可用：同一目标能换一道题再练，候选题不跨 Part，换了话题的排前面**
- [ ] 换题验证的结果文案只报告「有没有被再次点名」，**没有出现「已掌握」这类结论**
- [ ] 复训会话在 `state.json` 里带 `retraining` 字段，原题/换题区分正确
- [ ] 源题找不到（记录被删 / 题库换季）时**有中文说明与下一步**，那一条不会从列表里消失
- [ ] 挂不上台账时**用户看得到**，不是静默失败
- [ ] 每个关键逻辑都经突变验证确认测试有约束力（Task 1、2、3、4、5、6、7、8、9、10 各自的突变步骤都跑过并记录）
- [ ] `DESIGN-SYSTEM.md` 第 6 节十条验收清单全部通过

达成后进 Phase 7：问题档案、词汇本、统计趋势——那一阶段回答「这个毛病到底有没有变少」，是本阶段的下一环。

**本阶段与 ROADMAP 的差别：** ROADMAP 只写了四条交付。实际拆出来多了三件必须做的事——(1) `PracticeSession` 需要一个复训标记字段，否则「换题验证做过没有」根本无处记录；(2) 换题候选需要一套明确的挑选规则，否则「换一道题」会退化成「随便再练一道」；(3) 结果判定与文案需要单独把关，否则很容易顺手写出「已掌握」这种站不住的结论。三件事都已排进上面的任务里。
