# Phase 7：问题档案、词汇本、统计趋势

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户**看见问题有没有变少**。交付三样东西：问题档案页（错题按出现次数排序、「新问题」标记、每条带趋势）、我的词汇页（按优先级排序、可导出到 Anki）、首页统计（本周 N/5 次目标、累计训练、本周开口时长、出现变少的毛病数量）与「你的问题正在怎么变化」列表。每周训练目标次数可配置，默认 5 次。

**Architecture:** 沿用既有分层。所有统计与趋势的**计算**放 `IELTSCoachCore`（只依赖 Foundation，因此完全可单元测试）；`IELTSCoachUI` 里只放「把计算结果变成界面要显示的行」的视图模型与 `View`。Anki 导出的**文本生成**同样放 Core（纯字符串），只有「弹保存面板、写文件」这一步在 UI 层。

**Tech Stack:** Swift 6.3.3（`swift-tools-version: 6.0`，即 Swift 6 语言模式，严格并发检查已开启）、SPM、SwiftUI、XCTest。无第三方依赖。

---

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit / UniformTypeIdentifiers 的代码一律放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、`IELTSCoachAudio`（Phase 5 加的）、SwiftUI
- 所有面向用户的文案（错误、警告、空状态、脚注、趋势说明）必须是中文，且**同时说明「发生了什么」和「下一步做什么」**
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- 界面必须走设计令牌（`Palette` / `Spacing` / `Radius`），**视图里不得出现字面颜色、字号、圆角**
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- **统计数字必须用 `.monospacedDigit()`**（`DESIGN-SYSTEM.md` 第 1 节与第 6 节最后一条）。否则「本周 3/5 次」跳到「本周 10/5 次」时整行会横向抖动，这是让界面显廉价的头号可察觉缺陷
- **本阶段不得出现任何形式的雅思分数预测**（`DEFINITION-OF-DONE.md` 第 4 节明令禁止）。给「你大概 6.5 分」这种数字既不准也有害——会让人盯着数字而不是盯着问题。趋势只呈现「这个毛病出现了几次、最近有没有变少」。**Task 8 里有一条专门守这件事的自动化测试**
- 本阶段**不安排任何驱动真实 ChatGPT 的自动化步骤**。所有单元测试用假数据，真机验收由用户自己决定要不要练

---

## Swift 6 语言模式的两个硬坑（动手前先读）

本包的 `swift-tools-version: 6.0` 意味着 Swift 6 语言模式，严格并发检查开启。两条会让人卡半小时的规则：

1. **不要把 `ISO8601DateFormatter` / `DateFormatter` 提成 `static let`。** 它们不是 `Sendable`，Swift 6 语言模式下 `public enum` 里的 `static let` 会直接编译不过（"static property is not concurrency-safe"）。本计划里所有 formatter 都在函数内部新建。本项目现有代码（`QuestionBankImporter`、`PracticeCommand`）也是这么做的。数据量是几百条，开销可以忽略。
2. **不要用 `Dictionary(uniqueKeysWithValues:)` 建索引。** 遇到重复 key 会 `fatalError` 闪退整个 App，而不是报错。`state.json` 被外部工具改坏、或上游 Windows 版写入过重复 id，都会踩到。本项目在 `QuestionBankImporter.merge` 里已经为同一个坑写过一段注释。一律用 `for` 循环逐个赋值。

---

## 前置依赖：Phase 4 必须已经提供的东西（**不要假装它已经存在**）

本阶段的统计以「训练记录」为数据源。开工前**必须先确认下面两条**，确认方式是打开源码看，不是猜：

### 依赖 1：`state.sessions` 里要有真实的练习记录

`CoachState.sessions: [PracticeSession]` 这个字段**在模型里早就有了**，但截至写这份计划时（2026-08-06），**全工程没有任何一行代码往它里面写**。已核对：

- `Sources/coach/PracticeCommand.swift` 走完整场练习后只调 `ReviewArchiver.archive(...)`，不追加 session
- `ReviewArchiver.archive` 只动 `issues` / `vocabulary` / `targets` / `plan` / `questions`，不动 `sessions`
- Phase 3 计划 Task 9 的 `PracticeRunner` 同样只归档复盘

**Phase 4 的交付物「训练记录页」必然要求把每场练习写进 `state.sessions`。** 若你接手时 `state.sessions` 仍然没人写：

- 「累计训练」「本周 N/5」「本周开口时长」三格全是 0
- 趋势会退化为只靠 `IssueRecord.sourceSessionIds` 里的时间戳来划窗口（本计划的 `SessionTimeline` 已经按这个降级路径设计好了，**不会算错，只是窗口以「时间」而不是「第几场」为准**）

**这种情况下不要停工，也不要自己顺手去实现 Phase 4。** 照本计划做完，然后在 Task 11 的验收报告里写明「`state.sessions` 为空，统计三格为 0，等 Phase 4 接上后复验」。

> **2026-08-06 复审补记：Phase 4 的实施计划已经写完**（`plans/2026-08-06-phase4-transcript-and-history.md` Task 6），
> `PracticeRunner.finishPractice()` 会按 id upsert 一条带 `startedAt` / `endedAt` / `transcript` / `reportPath` 的 `PracticeSession`。
> 按正常执行顺序（3→4→5→6→7），你接手时**依赖 1 应该已经成立**，三格会有真实数字，
> Task 11 的报告里不用再写「等 Phase 4 接上后复验」。
> **但仍然按上面的方式实测确认**——降级路径别删，它守的是「命令行时期练的那些场次」。

### 依赖 2：session id 的取值必须前后一致

`PracticeSession.id` 的注释写的是 `"YYYY-MM-DD-NNN"`，而 `PracticeCommand.swift` 第 115 行归档时用的 sessionID 是：

```swift
let sessionID = ISO8601DateFormatter().string(from: Date())
```

即 `"2026-08-05T14:03:11Z"`。**两种形状都以 `YYYY-MM-DD` 开头**，所以本计划的 `CoachTime.parseDayPrefix` 两种都能解析出日期。若 Phase 4 把两者统一了，`SessionTimeline` 会走更精确的那条路（直接用 `PracticeSession.startedAt`）；若没统一，走日期兜底路径并在界面上给出警告。**两条路都已写进测试，不需要你做选择。**

> **2026-08-06 复审补记：** 跨阶段决策 1 已定案并落进 Phase 4 Task 1——
> **新产生的编号一律 `YYYY-MM-DD-NNN`，`startedAt` 也填好了**，所以会走精确那条路；
> **但用户现有 `state.json` 里的 ISO8601 编号仍然存在**（`SessionID.validated` 的白名单特意含 `:` 与 `+`，
> 就是为了不让已有记录失效）。**`CoachTime.parseDayPrefix` 那条兜底路径不要删。**

### Phase 3 必须已提供（若缺，先补，别绕过）

| 来自 Phase 3 | 本阶段怎么用 |
|---|---|
| `Palette` / `Spacing` / `Radius` | 所有新视图的颜色、间距、圆角 |
| `CoachCard` / `PrimaryActionCard` / `SectionHeader(number:label:title:)` / `EmptyStateView(message:hint:actionTitle:action:)` | 卡片、区块标题、空状态 |
| `AppState`（含 `state: CoachState`、`reload()`、私有 `store: StateStore`） | 读数据；Task 9 给它加一个写方法 |
| `SidebarItem`（十项，含 `isImplemented`） | Task 6 / Task 7 各解锁一项 |
| `RootView`（`NavigationSplitView` 骨架 + `detail` 的 `switch selection`） | 挂两个新页面 + 一个设置面板 |
| `TodayViewModel`（含 `weekProgress: (done: Int, goal: Int)`，goal 硬编码 5） | Task 8 改成读设置 |

---

## File Structure

```
Sources/
├── IELTSCoachCore/
│   ├── CoachTime.swift                        新增：时间戳解析（Task 1）
│   ├── Model/
│   │   ├── CoachState.swift                   修改：CoachSettings 加 weeklyGoal（Task 1）
│   │   └── VocabularyPriority.swift           新增：词汇优先级归一（Task 5）
│   ├── Stats/
│   │   ├── SessionTimeline.swift              新增：会话时间轴与窗口划分（Task 2）
│   │   ├── IssueTrendAnalyzer.swift           新增：趋势判定（Task 3）
│   │   └── TrainingStats.swift                新增：首页统计（Task 4）
│   └── Export/
│       └── VocabularyExporter.swift           新增：Anki 导出（Task 5）
├── IELTSCoachUI/
│   ├── AppState.swift                         修改：加 setWeeklyGoal（Task 9）
│   ├── Navigation.swift                       修改：解锁 .issues / .vocabulary（Task 6 / 7）
│   ├── RootView.swift                         修改：挂两页 + 设置面板（Task 6 / 7 / 9）
│   ├── Issues/
│   │   ├── IssueArchiveViewModel.swift        新增（Task 6）
│   │   └── IssueArchiveView.swift             新增（Task 6）
│   ├── Vocabulary/
│   │   ├── VocabularyViewModel.swift          新增（Task 7）
│   │   ├── ExportTextDocument.swift           新增（Task 7）
│   │   └── VocabularyView.swift               新增（Task 7）
│   ├── Today/
│   │   ├── StatTile.swift                     新增（Task 8）
│   │   ├── TodayViewModel.swift               修改（Task 8）
│   │   └── TodayView.swift                    修改（Task 8）
│   └── Settings/
│       └── WeeklyGoalSheet.swift              新增（Task 9）
scripts/
└── seed-demo-data.swift                       新增：造演示数据供人工验收（Task 10）
Tests/
├── IELTSCoachCoreTests/
│   ├── CoachTimeTests.swift                   Task 1
│   ├── WeeklyGoalTests.swift                  Task 1
│   ├── SessionTimelineTests.swift             Task 2
│   ├── IssueTrendAnalyzerTests.swift          Task 3
│   ├── TrainingStatsTests.swift               Task 4
│   └── VocabularyExporterTests.swift          Task 5
└── IELTSCoachUITests/
    ├── IssueArchiveViewModelTests.swift       Task 6
    ├── VocabularyViewModelTests.swift         Task 7
    ├── HomeStatsTests.swift                   Task 8
    └── NavigationTests.swift                  修改（Task 6 / 7）
```

### 关于本计划里 `View` 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略。**

理由与 Phase 3 计划第 79–86 行一致：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务里写明「必须显示什么、空状态说什么、失败时说什么、哪些数字必须等宽」，具体怎么摆由实现者定，由设计令牌约束、由 Task 11 的人工验收把关。

**这与「禁止占位符」不冲突**：占位符是「TBD、以后再说」，这里给的是明确到能逐条打勾的验收标准。若某处要求不清楚到无法动手，停下来问，不要猜。

---

## Task 1: 时间戳解析 `CoachTime` + 每周训练目标写进设置

**Files:**
- Create: `Sources/IELTSCoachCore/CoachTime.swift`
- Modify: `Sources/IELTSCoachCore/Model/CoachState.swift`
- Create: `Tests/IELTSCoachCoreTests/CoachTimeTests.swift`
- Create: `Tests/IELTSCoachCoreTests/WeeklyGoalTests.swift`

**Interfaces:**
- Consumes: `CoachState`、`CoachSettings`、`StateStore(directory:)`、`DataDirectory(root:)`
- Produces:
  - `CoachTime.parse(_ text: String) -> Date?`
  - `CoachTime.parseDayPrefix(_ text: String) -> Date?`
  - `CoachTime.dayString(_ date: Date, calendar: Calendar = .current) -> String`
  - `CoachTime.string(from date: Date) -> String`
  - `CoachSettings.weeklyGoal: Int`
  - `CoachSettings.defaultWeeklyGoal: Int`（= 5）
  - `CoachSettings.weeklyGoalRange: ClosedRange<Int>`（= 1...21）
  - `CoachSettings.normalized(_ raw: Int?) -> Int`
  - `CoachSettings.init(recordingEnabled:recordingConsentAt:weeklyGoal:)`（第三参有默认值，**既有调用点不用改**）

**为什么第一件事是做时间解析：** 本阶段每一个数字都建立在「把字符串变成时间」这一步上。项目里的时间戳来自多处写法（命令行用 `ISO8601DateFormatter` 写、session id 是另一种形状、Phase 4/5 可能再换），只要有一种解析不了，那条记录就被当成「没有时间」，统计与趋势会**静默算少**——正是本项目最忌讳的失败形态。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/CoachTimeTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class CoachTimeTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testParsesPlainISO8601() {
        // 命令行现在就是用 ISO8601DateFormatter() 的默认选项写的，这条必须过。
        let date = CoachTime.parse("2026-08-05T10:00:00Z")
        XCTAssertEqual(date?.timeIntervalSince1970, 1785664800, accuracy: 1)
    }

    func testParsesFractionalSeconds() {
        // ISO8601DateFormatter 的默认选项解析不了小数秒。少了这条容错，
        // 任何用 .withFractionalSeconds 写出来的时间戳都会被当成「没有时间」，
        // 统计会静默算少而不报错。
        XCTAssertNotNil(CoachTime.parse("2026-08-05T10:00:00.123Z"),
                        "带小数秒的时间戳必须也能解析")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertNotNil(CoachTime.parse("  2026-08-05T10:00:00Z\n"))
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertNil(CoachTime.parse(""))
        XCTAssertNil(CoachTime.parse("   "))
        XCTAssertNil(CoachTime.parse("昨天下午"))
    }

    func testParsesDayPrefixFromSessionIDStyle() {
        // PracticeSession.id 的文档形状是 "YYYY-MM-DD-NNN"
        let date = CoachTime.parseDayPrefix("2026-08-05-003")
        XCTAssertEqual(CoachTime.dayString(date ?? .distantPast, calendar: utc), "2026-08-05")
    }

    func testParsesDayPrefixFromFullTimestamp() {
        // 命令行归档时用的 sessionID 是完整 ISO8601 时间戳，前十位同样是日期
        let date = CoachTime.parseDayPrefix("2026-08-05T14:03:11Z")
        XCTAssertEqual(CoachTime.dayString(date ?? .distantPast, calendar: utc), "2026-08-05")
    }

    func testRejectsDayPrefixThatIsNotADate() {
        // pending-reviews 里的 requestID 长这样，绝不能被当成日期
        XCTAssertNil(CoachTime.parseDayPrefix("sync-1754123456"))
        XCTAssertNil(CoachTime.parseDayPrefix("短"))
    }

    func testDayStringUsesTheGivenCalendarTimeZone() {
        // 晚上练的一场，UTC 日期和本地日期会差一天。「最近一次：8 月 6 日」
        // 显示成 8 月 5 日，用户会以为记录错了。
        let date = CoachTime.parse("2026-08-05T23:30:00Z")!
        XCTAssertEqual(CoachTime.dayString(date, calendar: utc), "2026-08-05")
        XCTAssertEqual(CoachTime.dayString(date, calendar: shanghai), "2026-08-06")
    }
}
```

`Tests/IELTSCoachCoreTests/WeeklyGoalTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class WeeklyGoalTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    // MARK: - 纯逻辑

    func testDefaultIsFive() {
        // ROADMAP 第 5 节：每周训练目标默认 5 次
        XCTAssertEqual(CoachSettings.defaultWeeklyGoal, 5)
        XCTAssertEqual(CoachState.empty().settings.weeklyGoal, 5)
    }

    func testNormalizedAcceptsValuesInRange() {
        XCTAssertEqual(CoachSettings.normalized(1), 1)
        XCTAssertEqual(CoachSettings.normalized(7), 7)
        XCTAssertEqual(CoachSettings.normalized(21), 21)
    }

    func testNormalizedFallsBackForOutOfRangeOrMissing() {
        // 0 会让「本周 3/0 次」变成没有意义的显示；999 是手滑输入。
        // 一个坏掉的目标数字不该让整份训练数据读不出来，所以是回落而不是抛错。
        XCTAssertEqual(CoachSettings.normalized(0), 5)
        XCTAssertEqual(CoachSettings.normalized(-3), 5)
        XCTAssertEqual(CoachSettings.normalized(999), 5)
        XCTAssertEqual(CoachSettings.normalized(nil), 5)
    }

    func testMemberwiseInitNormalizes() {
        XCTAssertEqual(CoachSettings(recordingEnabled: false, recordingConsentAt: "",
                                     weeklyGoal: 0).weeklyGoal, 5)
    }

    /// **跨阶段回归（2026-08-06 复审补入）。** 本任务整体替换了 `CoachSettings`，
    /// 最容易犯的错就是把 Phase 4 加的 `transcriptEnabled` 顺手删掉——
    /// 那样编译能过（新参数都带默认值），只是用户关掉的逐字稿开关会在下一次
    /// 写盘时被默认值悄悄盖回「开」，没有任何报错。
    ///
    /// **Phase 4 尚未交付时，把这条整条注释掉并在报告里写明，不要删。**
    func testTranscriptSwitchFromPhase4SurvivesThisRewrite() throws {
        let json = #"{"recordingEnabled":false,"recordingConsentAt":"","transcriptEnabled":false}"#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.transcriptEnabled, "transcriptEnabled 被这次重写弄丢了")

        let roundTripped = try JSONDecoder().decode(
            CoachSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertFalse(roundTripped.transcriptEnabled, "transcriptEnabled 没有被编码回去")
    }

    // MARK: - 落盘与读回

    func testWeeklyGoalPersistsThroughStateStore() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = 3 }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 3)
    }

    func testOldStateFileWithoutWeeklyGoalGetsDefaultAndKeepsOtherSettings() throws {
        // weeklyGoal 是 Phase 7 才加的字段。用合成解码器会因为缺键直接抛错，
        // 等于「升级一次版本，用户全部训练数据读不出来」。
        let json = #"""
        {"schemaVersion":3,
         "settings":{"recordingEnabled":true,"recordingConsentAt":"2026-01-01T00:00:00Z"}}
        """#
        try json.write(to: directory.stateFile, atomically: true, encoding: .utf8)

        let state = try StateStore(directory: directory).load()
        XCTAssertEqual(state.settings.weeklyGoal, 5)
        XCTAssertTrue(state.settings.recordingEnabled, "加新字段不能把已有设置读丢")
        XCTAssertEqual(state.settings.recordingConsentAt, "2026-01-01T00:00:00Z")
    }

    func testOutOfRangeWeeklyGoalOnDiskIsNormalizedOnLoad() throws {
        let json = #"""
        {"schemaVersion":3,
         "settings":{"recordingEnabled":false,"recordingConsentAt":"","weeklyGoal":0}}
        """#
        try json.write(to: directory.stateFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 5)
    }

    func testWeeklyGoalIsWrittenIntoStateFile() throws {
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = 4 }
        let text = try String(contentsOf: directory.stateFile, encoding: .utf8)
        XCTAssertTrue(text.contains("\"weeklyGoal\""), "新字段必须真的写进 state.json")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter CoachTimeTests`
Expected: 编译失败 —— `CoachTime` 未定义

Run: `swift test --filter WeeklyGoalTests`
Expected: 编译失败 —— `CoachSettings` 没有 `weeklyGoal`

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/CoachTime.swift`：

```swift
import Foundation

/// 时间戳解析。**项目里所有「字符串变时间」都必须走这里，不要各处 new formatter。**
///
/// 原因：`ISO8601DateFormatter` 的默认选项是 `.withInternetDateTime`，
/// 解析不了带小数秒的时间戳。项目里的时间戳来自多处写法，
/// 一处解析不了，那条记录就被当成「没有时间」——统计与趋势会静默算少而不报错。
public enum CoachTime {
    /// 解析完整的 ISO8601 时间戳。带不带小数秒都认。
    public static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // ⚠️ 不要把这两个 formatter 提成 static let。Swift 6 语言模式下
        // ISO8601DateFormatter 不是 Sendable，static let 会直接编译不过。
        // 每次新建的开销在本项目的数据量（几百条）下可以忽略。
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    /// 只认前十位的日期，用于从 session id 兜底取时间。
    ///
    /// 两种已知的 session id 形状都以 `YYYY-MM-DD` 开头：
    /// 命令行归档时写的是完整 ISO8601 时间戳，`PracticeSession.id` 的文档形状是
    /// `"YYYY-MM-DD-NNN"`。两种都能落在这里。
    public static func parseDayPrefix(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")   // 不受用户区域设置影响
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: String(trimmed.prefix(10)))
    }

    /// 给界面显示用的「YYYY-MM-DD」。
    ///
    /// **必须按传入的日历（含时区）算**：晚上练的一场，UTC 日期与本地日期会差一天，
    /// 直接截时间戳前十位会把「8 月 6 日练的」显示成 8 月 5 日。
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 写入用。与项目既有写法保持一致（UTC、无小数秒）。
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
```

`Sources/IELTSCoachCore/Model/CoachState.swift`：把既有的 `CoachSettings` **整体替换**为下面这段（其余部分一个字都不要动）：

> **⚠️ 替换前先看一眼里面已经有什么**（2026-08-06 跨阶段复审补入）。
> `CoachSettings` 是多个阶段都要往里加字段的地方，「整体替换」是这里最危险的动作：
> 少抄一个字段编译照样过（新参数都带默认值），只是那个设置在下一次写盘时被默认值悄悄盖掉。
>
> 先跑 `grep -n "public var" Sources/IELTSCoachCore/Model/CoachState.swift`，
> 把**已经存在的字段一个不落地抄进下面这段**，再加 `weeklyGoal`。特别当心
> **Phase 4 可能已经加了「记录对话逐字稿」开关**（`ROADMAP.md` 第 5 节：开/关，**默认开**）——
> 它连同 `CodingKeys` 里那一项与手写 `init(from:)` 里那一行都要保留。
>
> 同理，**Phase 8 Task 2 之后还会再整体替换一次**（加 `defaultRoute` / `feedbackTiming` /
> `part2PrepMode`），那份计划里已经写明要把本任务的 `weeklyGoal` 合并进去。

```swift
public struct CoachSettings: Codable, Equatable, Sendable {
    public var recordingEnabled: Bool
    public var recordingConsentAt: String
    /// 「记录对话逐字稿」。**Phase 4 Task 2 加的，本任务原样保留，不得删。**
    /// ROADMAP 第 5 节：开 / 关，默认开。
    public var transcriptEnabled: Bool
    /// 每周训练目标次数。ROADMAP 第 5 节：用户可配置，默认 5 次。
    public var weeklyGoal: Int

    /// ↓ 来自 Phase 4 Task 2，原样保留
    public static let defaultTranscriptEnabled = true

    public static let defaultWeeklyGoal = 5
    /// 上限 21 = 一天三场。给上限是为了让界面上的 Stepper 有边界，
    /// 也挡住手滑输入的 999——「本周 3/999 次」这种显示毫无意义。
    public static let weeklyGoalRange = 1...21

    /// 越界或缺失一律回落到默认值，而不是抛错——
    /// 一个坏掉的目标数字不该让用户整份训练数据读不出来。
    public static func normalized(_ raw: Int?) -> Int {
        guard let raw, weeklyGoalRange.contains(raw) else { return defaultWeeklyGoal }
        return raw
    }

    // 合成的 memberwise init 是 internal 的，App target 与 MCP target 构造不了。
    // 后两个参数给默认值，既有调用点（CoachState.empty、测试）不用改。
    // **transcriptEnabled 排在 weeklyGoal 前面，与 Phase 4 定下的位置一致**——
    // 换位置会打断 Phase 4 已有的调用点；两个都有默认值，只传 weeklyGoal: 照样能编译。
    public init(recordingEnabled: Bool, recordingConsentAt: String,
                transcriptEnabled: Bool = CoachSettings.defaultTranscriptEnabled,
                weeklyGoal: Int = CoachSettings.defaultWeeklyGoal) {
        self.recordingEnabled = recordingEnabled
        self.recordingConsentAt = recordingConsentAt
        self.transcriptEnabled = transcriptEnabled
        self.weeklyGoal = CoachSettings.normalized(weeklyGoal)
    }

    enum CodingKeys: String, CodingKey {
        case recordingEnabled, recordingConsentAt, transcriptEnabled, weeklyGoal
    }

    /// 手写解码：weeklyGoal 是 Phase 7 才加的字段，老的 state.json 里没有它。
    /// 合成的解码器遇到缺键会直接抛错，等于「升级一次版本，全部训练数据读不出来」。
    /// 这与 CoachState.init(from:) 的容错策略一致。
    ///
    /// 编码仍由 Swift 合成——只手写 Decodable 那一半时，Encodable 的合成不受影响。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? false
        recordingConsentAt = try container.decodeIfPresent(String.self, forKey: .recordingConsentAt) ?? ""
        // ↓ Phase 4 Task 2 的那一行，原样保留。删了它，用户关掉的逐字稿开关
        //   会在下一次写盘时被默认值悄悄盖回「开」，而且没有任何报错。
        transcriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .transcriptEnabled)
            ?? CoachSettings.defaultTranscriptEnabled
        weeklyGoal = CoachSettings.normalized(
            try container.decodeIfPresent(Int.self, forKey: .weeklyGoal))
    }
}
```

> **上面这份已经把 Phase 4 的 `transcriptEnabled` 合并进来了**（2026-08-06 复审补入——初稿只在文字里提醒，代码块里没有，而实现者照抄的是代码块）。
> 动手前先跑 `grep -n "transcriptEnabled" Sources/IELTSCoachCore/Model/CoachState.swift`：
> **没输出**说明 Phase 4 还没做，把上面 `transcriptEnabled` 相关的四处（字段、静态常量、init 参数与赋值、`CodingKeys` 与 `init(from:)` 各一行）删掉再用，并在报告里写明，Phase 4 届时自己合并回来。

**与上游 Windows 版的兼容性：** 这是一次纯追加的字段变更，`schemaVersion` 仍是 3。上游读到不认识的 `weeklyGoal` 键会忽略它；本工具读到没有该键的旧文件会补默认值。两个方向都不会丢数据，因此不需要升 schemaVersion。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter CoachTimeTests`
Expected: PASS（8 个测试）

Run: `swift test --filter WeeklyGoalTests`
Expected: PASS（9 个测试；Phase 4 未交付而把跨阶段那条注释掉时，是 8 个）

Run: `swift test --filter TranscriptSettingsTests`
Expected: PASS —— **Phase 4 的 5 条一条都不能红。** 红了说明 `transcriptEnabled` 在这次整体替换里被抄丢了，**去把字段补回来，不要改那些测试**

Run: `swift test`
Expected: 全绿（既有测试一条都不能红——`CoachSettings` 的新参数有默认值，调用点无需改动）

- [ ] **Step 5: 突变验证（两处）**

**突变 A：** 把 `CoachTime.parse` 里下面两行删掉

```swift
        if let date = fractional.date(from: trimmed) { return date }
```

重跑 `swift test --filter CoachTimeTests`：`testParsesFractionalSeconds` 必须变红。改回后确认全绿。

**突变 B：** 把 `CoachSettings.normalized` 的实现改成

```swift
    public static func normalized(_ raw: Int?) -> Int { raw ?? defaultWeeklyGoal }
```

重跑 `swift test --filter WeeklyGoalTests`：`testNormalizedFallsBackForOutOfRangeOrMissing`、`testMemberwiseInitNormalizes`、`testOutOfRangeWeeklyGoalOnDiskIsNormalizedOnLoad` 三条必须变红。改回后确认全绿。

两次的实际输出（哪条红了、报什么）都写进任务报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/CoachTime.swift Sources/IELTSCoachCore/Model/CoachState.swift Tests/IELTSCoachCoreTests/CoachTimeTests.swift Tests/IELTSCoachCoreTests/WeeklyGoalTests.swift
git commit -m "feat(core): 时间戳容错解析与每周训练目标设置"
```

---

## Task 2: 会话时间轴 `SessionTimeline`

**Files:**
- Create: `Sources/IELTSCoachCore/Stats/SessionTimeline.swift`
- Create: `Tests/IELTSCoachCoreTests/SessionTimelineTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`sessions`、`issues`、`vocabulary`、`targets`）、`PracticeSession`（`id`、`startedAt`）、`CoachTime.parse`、`CoachTime.parseDayPrefix`
- Produces:
  - `struct SessionTimeline: Equatable, Sendable`
    - `let orderedSessionIDs: [String]`（按时间**倒序**，最近的在最前）
    - `let unmatchedSessionIDs: [String]`
    - `let undatedSessionIDs: [String]`
    - `var warnings: [String]`
    - `static func build(state: CoachState) -> SessionTimeline`
    - `func window(size: Int, offset: Int) -> [String]`
    - `func recentWindow(size: Int) -> [String]`
    - `func earlierWindow(size: Int) -> [String]`

**这个类型解决什么问题：** 「这个毛病最近有没有变少」需要一个「最近」的定义。用**天数**定义不行——用户可能两周没练，那样所有毛病都会显示成「变少了」，这是在骗人。所以「最近」按**练习场次**定义：最近 5 场 vs 再往前 5 场。要划出这两个窗口，就得先把所有 session id 按时间排好。

**为什么不能只看 `state.sessions`：** 错题记录里的 `sourceSessionIds` 可能引用到 `state.sessions` 里没有的场次（Phase 4 之前用命令行练的那些）。那些是**真的练过**，不算进窗口会让「之前那批」凭空少几场，趋势就偏了。所以并入，但同时**报告出来**——静默并入等于悄悄改变了「最近 5 场」的含义。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/SessionTimelineTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class SessionTimelineTests: XCTestCase {

    /// 第 day 天的一场练习。id 用 "YYYY-MM-DD-001" 这种文档形状。
    private func session(day: Int, startedAt: String? = nil) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: startedAt ?? "\(stamp)T10:00:00Z",
                               endedAt: "\(stamp)T10:30:00Z", goal: "",
                               transcript: [], reportPath: "", recordingPath: "")
    }

    private func sessionID(day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func issue(_ id: String, sessions: [String]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said", correction: "fix", whyItMatters: "why",
                    occurrences: sessions.count, sourceSessionIds: sessions,
                    lastSeenAt: "2026-07-10T10:00:00Z")
    }

    private func state(sessions: [PracticeSession], issues: [IssueRecord] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.issues = issues
        return value
    }

    func testOrdersMostRecentFirst() {
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 3), session(day: 1), session(day: 2)]))
        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 3), sessionID(day: 2), sessionID(day: 1)])
    }

    func testFallsBackToDatePrefixOfTheIDWhenStartedAtIsEmpty() {
        // Phase 4 之前的数据、或写入时漏了 startedAt 的记录，
        // 不能因此被整条排除在趋势之外。
        let timeline = SessionTimeline.build(
            state: state(sessions: [session(day: 2, startedAt: ""), session(day: 1)]))
        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2), sessionID(day: 1)])
        XCTAssertTrue(timeline.undatedSessionIDs.isEmpty)
    }

    func testIncludesIssueOnlySessionsAndReportsThemAsUnmatched() {
        // 错题档案引用了一场 state.sessions 里没有的练习：
        // 它确实练过，必须并入时间轴，否则「之前那批」会凭空少一场；
        // 但也必须报出来，否则用户在训练记录页看不到它却影响了趋势。
        let orphan = "2026-07-05T09:00:00Z"
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 9), session(day: 1)],
            issues: [issue("i1", sessions: [orphan])]))

        XCTAssertEqual(timeline.orderedSessionIDs,
                       [sessionID(day: 9), orphan, sessionID(day: 1)])
        XCTAssertEqual(timeline.unmatchedSessionIDs, [orphan])
    }

    func testReportsUndatableIDsAndKeepsThemOutOfTheOrder() {
        // pending-reviews 的 requestID 混进来过一次就会毁掉窗口划分。
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456"])]))

        XCTAssertEqual(timeline.orderedSessionIDs, [sessionID(day: 2)])
        XCTAssertEqual(timeline.undatedSessionIDs, ["sync-1754123456"])
    }

    func testWarningsExplainWhatHappenedAndWhatToDoNext() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2)],
            issues: [issue("i1", sessions: ["sync-1754123456", "2026-07-05T09:00:00Z"])]))

        XCTAssertEqual(timeline.warnings.count, 2)
        for warning in timeline.warnings {
            XCTAssertTrue(warning.contains("下一步"), "警告必须说明下一步做什么：\(warning)")
        }
    }

    func testNoWarningsWhenEverythingLinesUp() {
        let timeline = SessionTimeline.build(state: state(
            sessions: [session(day: 2), session(day: 1)],
            issues: [issue("i1", sessions: [sessionID(day: 1)])]))
        XCTAssertTrue(timeline.warnings.isEmpty, "数据正常时不该吓唬用户")
    }

    func testRecentAndEarlierWindowsSplitTheTimeline() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...10).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5),
                       (6...10).reversed().map { sessionID(day: $0) })
        XCTAssertEqual(timeline.earlierWindow(size: 5),
                       (1...5).reversed().map { sessionID(day: $0) })
    }

    func testWindowsShrinkGracefullyWhenThereAreNotEnoughSessions() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...7).map { session(day: $0) }))
        XCTAssertEqual(timeline.recentWindow(size: 5).count, 5)
        XCTAssertEqual(timeline.earlierWindow(size: 5).count, 2, "只剩 2 场就只给 2 场，不能越界")
        XCTAssertEqual(SessionTimeline.build(state: state(sessions: []))
                        .earlierWindow(size: 5), [])
    }

    func testWindowRejectsNonsenseArguments() {
        let timeline = SessionTimeline.build(
            state: state(sessions: (1...3).map { session(day: $0) }))
        XCTAssertEqual(timeline.window(size: 0, offset: 0), [])
        XCTAssertEqual(timeline.window(size: 5, offset: 99), [])
        XCTAssertEqual(timeline.window(size: -1, offset: 0), [])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SessionTimelineTests`
Expected: 编译失败 —— `SessionTimeline` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Stats/SessionTimeline.swift`：

```swift
import Foundation

/// 把所有练习场次按时间排成一条轴，供「最近 N 场 vs 之前 N 场」的窗口划分使用。
///
/// **为什么窗口按场次而不按天数：** 用户可能两周没练。按天数划窗口的话，
/// 「最近 14 天」里一场都没有，所有毛病都会显示成「变少了」——那是在骗人。
public struct SessionTimeline: Equatable, Sendable {
    /// 按时间倒序，最近的一场在最前。
    public let orderedSessionIDs: [String]
    /// 在错题/词汇/目标档案里被引用、但 `state.sessions` 里没有对应记录的场次。
    /// 它们仍然参与窗口划分（确实练过），但必须让用户知道。
    public let unmatchedSessionIDs: [String]
    /// 连日期都解析不出来的 id。不参与任何窗口计算。
    public let undatedSessionIDs: [String]

    public init(orderedSessionIDs: [String], unmatchedSessionIDs: [String],
                undatedSessionIDs: [String]) {
        self.orderedSessionIDs = orderedSessionIDs
        self.unmatchedSessionIDs = unmatchedSessionIDs
        self.undatedSessionIDs = undatedSessionIDs
    }

    public static func build(state: CoachState) -> SessionTimeline {
        var timestamps: [String: Date] = [:]
        var undated: [String] = []
        var unmatched: [String] = []

        // ① 训练记录本身。优先用 startedAt，缺失时退回从 id 的日期前缀解析。
        for session in state.sessions {
            if let date = CoachTime.parse(session.startedAt)
                ?? CoachTime.parseDayPrefix(session.id) {
                timestamps[session.id] = date
            } else if !undated.contains(session.id) {
                undated.append(session.id)
            }
        }
        let recorded = Set(state.sessions.map(\.id))

        // ② 档案里引用到的场次。顺序固定（issues → vocabulary → targets），
        //    保证同一份数据每次得到同样的 unmatched 顺序，测试才有确定性。
        var referenced: [String] = []
        for issue in state.issues { referenced.append(contentsOf: issue.sourceSessionIds) }
        for record in state.vocabulary { referenced.append(contentsOf: record.sourceSessionIds) }
        for target in state.targets { referenced.append(target.sourceSessionId) }

        for id in referenced {
            guard timestamps[id] == nil, !undated.contains(id) else { continue }
            // 档案里的 sessionID 可能是完整时间戳，也可能是 "YYYY-MM-DD-NNN"，两种都试
            if let date = CoachTime.parse(id) ?? CoachTime.parseDayPrefix(id) {
                timestamps[id] = date
                if !recorded.contains(id), !unmatched.contains(id) { unmatched.append(id) }
            } else {
                undated.append(id)
            }
        }

        // 同一时刻的两场按 id 倒序，保证排序是确定的——不确定的排序会让
        // 同一份数据每次打开显示不同的趋势。
        let ordered = timestamps
            .sorted { $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value }
            .map(\.key)

        return SessionTimeline(orderedSessionIDs: ordered,
                               unmatchedSessionIDs: unmatched,
                               undatedSessionIDs: undated)
    }

    /// 界面必须显示这些警告。静默地把有问题的数据算进趋势，
    /// 等于给用户一个他无法核对的结论。
    public var warnings: [String] {
        var result: [String] = []
        if !unmatchedSessionIDs.isEmpty {
            result.append(
                "有 \(unmatchedSessionIDs.count) 次练习只在问题档案里留了记录，训练记录页看不到它们"
                + "（多半是早期用命令行练的）。它们仍按时间算进趋势，所以趋势本身是对的。"
                + "下一步：如果你在训练记录页找不到这几次，不用管这条提示；"
                + "如果你觉得根本没练过，去数据目录里的 state.json 核对一下。")
        }
        if !undatedSessionIDs.isEmpty {
            let sample = undatedSessionIDs.prefix(3).joined(separator: "、")
            result.append(
                "有 \(undatedSessionIDs.count) 条练习记录读不出时间，没有参与趋势计算，"
                + "因此「最近有没有变少」可能偏乐观。"
                + "下一步：打开数据目录里的 state.json，检查这几条记录的 startedAt 是不是空的：\(sample)")
        }
        return result
    }

    /// 从时间轴上取一段。参数不合理时返回空数组，不崩、不越界。
    public func window(size: Int, offset: Int) -> [String] {
        guard size > 0, offset >= 0, offset < orderedSessionIDs.count else { return [] }
        let end = min(offset + size, orderedSessionIDs.count)
        return Array(orderedSessionIDs[offset..<end])
    }

    public func recentWindow(size: Int) -> [String] { window(size: size, offset: 0) }

    public func earlierWindow(size: Int) -> [String] { window(size: size, offset: size) }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SessionTimelineTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证（两处）**

**突变 A：** 把 `build` 里的排序改成升序

```swift
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
```

重跑：`testOrdersMostRecentFirst`、`testRecentAndEarlierWindowsSplitTheTimeline` 必须变红。

**突变 B：** 把「并入档案里引用到的场次」那一支去掉——即在 `for id in referenced` 循环里把

```swift
                timestamps[id] = date
```

删掉（只保留 unmatched 的登记）。重跑：`testIncludesIssueOnlySessionsAndReportsThemAsUnmatched` 必须变红。

**这条守的是趋势的可信度**：漏掉几场旧练习，「之前那批」就变小，同样的出现次数会被算成「变多了」——用户会以为自己练退步了。

两次都改回，确认全绿，把输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Stats/SessionTimeline.swift Tests/IELTSCoachCoreTests/SessionTimelineTests.swift
git commit -m "feat(core): 会话时间轴与趋势窗口划分"
```

---

## Task 3: 趋势判定 `IssueTrendAnalyzer`

**Files:**
- Create: `Sources/IELTSCoachCore/Stats/IssueTrendAnalyzer.swift`
- Create: `Tests/IELTSCoachCoreTests/IssueTrendAnalyzerTests.swift`

**Interfaces:**
- Consumes: `CoachState.issues`、`IssueRecord`（`id`、`occurrences`、`sourceSessionIds`）、`SessionTimeline`
- Produces:
  - `enum IssueTrend: String, Equatable, Sendable, CaseIterable { case fresh, gone, decreasing, steady, increasing, notEnoughData }`
    - `var badge: String`（列表上的短标签）
    - `var explanation: String`（一句话，含「下一步」）
  - `struct IssueTrendResult: Equatable, Sendable, Identifiable`
    - `issueID`、`occurrences`、`recentHits`、`earlierHits`、`recentWindowSize`、`earlierWindowSize`、`isNew`、`trend`
    - `var id: String { issueID }`
    - `var detail: String`（带具体次数的一句话）
  - `enum IssueTrendAnalyzer`
    - `static let defaultWindowSize = 5`
    - `static let minimumEarlierWindow = 3`
    - `static let minimumSessionsForTrend = 8`
    - `static func analyze(state: CoachState, windowSize: Int = defaultWindowSize) -> [IssueTrendResult]`

### 判定规则（照这个表实现，不要自由发挥）

窗口：`recent` = 最近 `windowSize` 场，`earlier` = 再往前 `windowSize` 场（可能不足）。

`hits` 的含义是**「在窗口里的多少场练习中出现过」**，用 `sourceSessionIds` 与窗口取交集算，**不是** `occurrences`：要问的问题是「几场练习里犯了这个毛病」，不是「一共犯了几次」，而窗口交集是唯一能回答前者的算法。

> **注（Phase 4 之后的修正）**：`ReviewArchiver.mergeIssues` 已改成按 sessionID 去重（幂等），`IssueRecord.occurrences` 现在恒等于 `sourceSessionIds.count`。本文早先那句「同一份复盘里出现两次同样的错时会 `occurrences += 2`」已经不成立。`hits` 用窗口交集算这条结论不变（`occurrences` 是不分窗口的总数），但不要再拿「两者可能对不上」当理由。

| 判定顺序 | 条件 | 结果 |
|---|---|---|
| 1 | `earlier.count < minimumEarlierWindow`（3） | `.notEnoughData` |
| 2 | `isNew`（见下） | `.fresh` |
| 3 | `recentHits == 0` | `.gone` |
| 4 | `recentHits * earlier.count < earlierHits * recent.count` | `.decreasing` |
| 5 | `recentHits * earlier.count > earlierHits * recent.count` | `.increasing` |
| 6 | 其余 | `.steady` |

`isNew` = `recentHits > 0` 且 `earlierHits == 0` 且**没有任何一次出现落在两个窗口之外**。

**第 4、5 步为什么是交叉相乘而不是直接比 `recentHits` 与 `earlierHits`：** 两个窗口的大小可能不等（总共 9 场时，recent 有 5 场、earlier 只有 4 场）。直接比次数，「5 场里犯 2 次」和「4 场里犯 2 次」会被判成「没变化」，可实际上频率是从 50% 降到了 40%。交叉相乘等价于比较两个分数的大小，且**全程整数运算，不引入浮点相等判断**。

**第 1 步为什么要求之前那批至少 3 场：** 拿 1 场当作「之前」，然后告诉用户「这个毛病变少了」，那是在拿噪声当结论。样本不够就老老实实说样本不够。

**第 2 步为什么要有 `.fresh`：** 一个第一次出现的新毛病，按频率算必然是「变多了」（0 → N）。给用户显示「这个毛病比之前更常出现了」是错的——它之前根本不存在。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/IssueTrendAnalyzerTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class IssueTrendAnalyzerTests: XCTestCase {

    private func sessionID(_ day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func session(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: "\(stamp)T10:00:00Z", endedAt: "\(stamp)T10:30:00Z",
                               goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, days: [Int]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix-\(id)",
                    whyItMatters: "why-\(id)", occurrences: days.count,
                    sourceSessionIds: days.map(sessionID),
                    lastSeenAt: String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    /// `sessionCount` 场练习（第 1 天到第 sessionCount 天，每天一场）。
    private func state(sessionCount: Int, issues: [IssueRecord]) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessionCount > 0 ? (1...sessionCount).map(session) : []
        value.issues = issues
        return value
    }

    private func result(_ state: CoachState, _ issueID: String) throws -> IssueTrendResult {
        try XCTUnwrap(IssueTrendAnalyzer.analyze(state: state).first { $0.issueID == issueID })
    }

    // MARK: - 四种确定的趋势

    func testDecreasingWhenRecentHitsAreFewer() throws {
        // 10 场：最近 5 场是第 6–10 天，之前 5 场是第 1–5 天。
        // 之前犯了 4 场，最近只犯 1 场。
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3, 4, 10])]), "i")
        XCTAssertEqual(outcome.trend, .decreasing)
        XCTAssertEqual(outcome.recentHits, 1)
        XCTAssertEqual(outcome.earlierHits, 4)
    }

    func testGoneWhenAbsentFromTheRecentWindow() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3])]), "i")
        XCTAssertEqual(outcome.trend, .gone)
        XCTAssertFalse(outcome.isNew)
    }

    func testIncreasingWhenRecentHitsAreMore() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 8, 9, 10])]), "i")
        XCTAssertEqual(outcome.trend, .increasing)
    }

    func testSteadyWhenTheRateIsUnchanged() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [2, 3, 7, 8])]), "i")
        XCTAssertEqual(outcome.trend, .steady)
    }

    // MARK: - 窗口大小不等时必须比频率，不能比次数

    func testUnequalWindowsAreComparedByRateNotByRawCount() throws {
        // 9 场：最近 5 场（第 5–9 天），之前只有 4 场（第 1–4 天）。
        // 两个窗口各犯 2 场：2/5 = 40% < 2/4 = 50%，是在变少。
        // 若实现成直接比次数（2 vs 2），会误判成「还是老样子」。
        let outcome = try result(state(sessionCount: 9,
                                       issues: [issue("i", days: [3, 4, 8, 9])]), "i")
        XCTAssertEqual(outcome.recentHits, 2)
        XCTAssertEqual(outcome.earlierHits, 2)
        XCTAssertEqual(outcome.recentWindowSize, 5)
        XCTAssertEqual(outcome.earlierWindowSize, 4)
        XCTAssertEqual(outcome.trend, .decreasing, "窗口不等大时必须比频率")
    }

    // MARK: - 样本不够就不给结论

    func testNotEnoughDataWhenTheEarlierWindowIsTooSmall() throws {
        // 6 场：最近 5 场吃掉第 2–6 天，之前只剩第 1 天这一场。
        // 拿 1 场当「之前」再说「变少了」，那是拿噪声当结论。
        let outcome = try result(state(sessionCount: 6,
                                       issues: [issue("i", days: [1, 6])]), "i")
        XCTAssertEqual(outcome.trend, .notEnoughData)
    }

    func testNoSessionsAtAllStillProducesAResultInsteadOfCrashing() throws {
        let outcome = try result(state(sessionCount: 0,
                                       issues: [issue("i", days: [])]), "i")
        XCTAssertEqual(outcome.trend, .notEnoughData)
        XCTAssertEqual(outcome.recentHits, 0)
    }

    // MARK: - 新问题

    func testFirstTimeIssueIsMarkedNewInsteadOfIncreasing() throws {
        // 之前根本不存在的毛病，按频率算必然是 0 → N，
        // 显示成「比之前更常出现了」是错的。
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [9, 10])]), "i")
        XCTAssertTrue(outcome.isNew)
        XCTAssertEqual(outcome.trend, .fresh)
    }

    func testIssueWithHistoryOlderThanBothWindowsIsNotNew() throws {
        // 12 场：窗口覆盖第 3–12 天，第 1 天在两个窗口之外。
        // 这个毛病老早就犯过，不能标成「新问题」。
        let outcome = try result(state(sessionCount: 12,
                                       issues: [issue("i", days: [1, 12])]), "i")
        XCTAssertFalse(outcome.isNew)
        XCTAssertNotEqual(outcome.trend, .fresh)
    }

    // MARK: - hits 用「几场里出现过」而不是 occurrences

    func testHitsCountSessionsNotTotalOccurrences() throws {
        // 同一场里犯两次，ReviewArchiver 会让 occurrences = 2 但只记一个 sessionId。
        // 要问的是「几场练习里犯了这个毛病」，不是「一共犯了几次」。
        var record = issue("i", days: [10])
        record.occurrences = 7
        let outcome = try result(state(sessionCount: 10, issues: [record]), "i")
        XCTAssertEqual(outcome.recentHits, 1, "同一场里犯多次仍然只算一场")
        XCTAssertEqual(outcome.occurrences, 7, "occurrences 原样带出来给列表排序用")
    }

    // MARK: - 文案

    func testEveryTrendHasBadgeAndActionableExplanation() {
        for trend in IssueTrend.allCases {
            XCTAssertFalse(trend.badge.isEmpty, "\(trend) 缺少列表标签")
            XCTAssertTrue(trend.explanation.contains("下一步"),
                          "\(trend) 的说明必须告诉用户下一步做什么：\(trend.explanation)")
        }
    }

    func testDetailQuotesTheActualNumbers() throws {
        let outcome = try result(state(sessionCount: 10,
                                       issues: [issue("i", days: [1, 2, 3, 4, 10])]), "i")
        XCTAssertTrue(outcome.detail.contains("1"))
        XCTAssertTrue(outcome.detail.contains("4"))
    }

    func testAnalyzeCoversEveryIssueExactlyOnce() {
        let value = state(sessionCount: 10, issues: [issue("a", days: [1]),
                                                     issue("b", days: [10])])
        let results = IssueTrendAnalyzer.analyze(state: value)
        XCTAssertEqual(results.map(\.issueID), ["a", "b"], "顺序与 state.issues 一致，不得重排")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter IssueTrendAnalyzerTests`
Expected: 编译失败 —— `IssueTrendAnalyzer`、`IssueTrend` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Stats/IssueTrendAnalyzer.swift`：

```swift
import Foundation

/// 一个毛病最近的走向。
///
/// **这里不出现任何形式的分数。** 产品明确不做雅思分数预测
/// （DEFINITION-OF-DONE 第 4 节）：给「你大概 6.5 分」这种数字既不准也有害，
/// 会让人盯着数字而不是盯着问题。这里只回答「这个毛病出现了几次、最近有没有变少」。
public enum IssueTrend: String, Equatable, Sendable, CaseIterable {
    /// 最近才第一次出现的新毛病。
    case fresh
    /// 最近这一批练习里一次都没再出现。
    case gone
    case decreasing
    case steady
    case increasing
    /// 练习场次还不够，给不出可信的结论。
    case notEnoughData

    /// 列表里的短标签。
    public var badge: String {
        switch self {
        case .fresh: return "新问题"
        case .gone: return "最近没再出现"
        case .decreasing: return "出现变少了"
        case .steady: return "还是老样子"
        case .increasing: return "出现变多了"
        case .notEnoughData: return "还看不出趋势"
        }
    }

    /// 一句话说明「发生了什么 + 下一步做什么」。
    public var explanation: String {
        switch self {
        case .fresh:
            return "这是最近才冒出来的新毛病，之前没犯过。"
                + "下一步：先别急着当成老毛病治，看它下次还会不会出现。"
        case .gone:
            return "最近这几场练习里一次都没再出现。"
                + "下一步：换一道同类型的题再练一次，确认是真改掉了，而不是碰巧没说到。"
        case .decreasing:
            return "比之前少了。"
                + "下一步：保持现在的做法，别急着换目标——正在见效的东西不要中途改。"
        case .steady:
            return "和之前一样多，没有变化。"
                + "下一步：到复训中心把它设成下一次的单点目标，一次只盯这一个。"
        case .increasing:
            return "比之前更常出现了。"
                + "下一步：到复训中心带着这个问题重练一次，再换一道题验证。"
        case .notEnoughData:
            return "练习场次还不够，看不出它在变多还是变少。"
                + "下一步：再练几场，这里会自动开始显示趋势。"
        }
    }
}

public struct IssueTrendResult: Equatable, Sendable, Identifiable {
    public let issueID: String
    /// 档案里记的累计次数，原样带出来给列表排序用。
    public let occurrences: Int
    /// 最近这批练习里，有几场犯了这个毛病。
    public let recentHits: Int
    /// 再往前那批练习里，有几场犯了这个毛病。
    public let earlierHits: Int
    public let recentWindowSize: Int
    public let earlierWindowSize: Int
    public let isNew: Bool
    public let trend: IssueTrend

    public var id: String { issueID }

    public init(issueID: String, occurrences: Int, recentHits: Int, earlierHits: Int,
                recentWindowSize: Int, earlierWindowSize: Int, isNew: Bool, trend: IssueTrend) {
        self.issueID = issueID; self.occurrences = occurrences
        self.recentHits = recentHits; self.earlierHits = earlierHits
        self.recentWindowSize = recentWindowSize; self.earlierWindowSize = earlierWindowSize
        self.isNew = isNew; self.trend = trend
    }

    /// 把结论背后的原始数字摆出来，让用户能自己核对。
    public var detail: String {
        guard trend != .notEnoughData else {
            return "目前一共出现 \(occurrences) 次。练习场次还不够，看不出它在变多还是变少。"
        }
        return "最近 \(recentWindowSize) 场练习里有 \(recentHits) 场犯了它，"
             + "再往前 \(earlierWindowSize) 场里有 \(earlierHits) 场。"
    }
}

public enum IssueTrendAnalyzer {
    public static let defaultWindowSize = 5
    /// 「之前那批」少于这个数就不给趋势——拿 1 场当作「之前」再说「变少了」，
    /// 那是拿噪声当结论。
    public static let minimumEarlierWindow = 3
    /// 至少练满这么多场，才可能出现确定的趋势。界面用它来告诉用户「还差几场」。
    public static let minimumSessionsForTrend = defaultWindowSize + minimumEarlierWindow

    public static func analyze(state: CoachState,
                               windowSize: Int = defaultWindowSize) -> [IssueTrendResult] {
        let timeline = SessionTimeline.build(state: state)
        let recent = Set(timeline.recentWindow(size: windowSize))
        let earlier = Set(timeline.earlierWindow(size: windowSize))
        let inWindows = recent.union(earlier)

        return state.issues.map { issue in
            // hits 数的是「几场练习里出现过」，不是 occurrences：
            // ReviewArchiver 在同一份复盘里遇到两条同样的错会让 occurrences += 2，
            // 但 sourceSessionIds 只记一次。要问的是前者。
            let sources = Set(issue.sourceSessionIds)
            let recentHits = sources.intersection(recent).count
            let earlierHits = sources.intersection(earlier).count
            let hasOlderHistory = !sources.subtracting(inWindows).isEmpty
            let isNew = recentHits > 0 && earlierHits == 0 && !hasOlderHistory

            let trend: IssueTrend
            if earlier.count < minimumEarlierWindow {
                trend = .notEnoughData
            } else if isNew {
                // 之前根本不存在的毛病，按频率算必然是「变多了」，那是错的
                trend = .fresh
            } else if recentHits == 0 {
                trend = .gone
            } else {
                // 交叉相乘 = 比较 recentHits/recent.count 与 earlierHits/earlier.count，
                // 全程整数，不引入浮点相等判断。两个窗口大小可能不等
                // （总共 9 场时 recent 有 5 场、earlier 只有 4 场），
                // 直接比次数会把「5 场犯 2 次」和「4 场犯 2 次」判成没变化。
                let left = recentHits * earlier.count
                let right = earlierHits * recent.count
                if left < right { trend = .decreasing }
                else if left > right { trend = .increasing }
                else { trend = .steady }
            }

            return IssueTrendResult(issueID: issue.id, occurrences: issue.occurrences,
                                    recentHits: recentHits, earlierHits: earlierHits,
                                    recentWindowSize: recent.count,
                                    earlierWindowSize: earlier.count,
                                    isNew: isNew, trend: trend)
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter IssueTrendAnalyzerTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证（三处）**

**突变 A（最重要）：** 把交叉相乘改成直接比次数

```swift
                if recentHits < earlierHits { trend = .decreasing }
                else if recentHits > earlierHits { trend = .increasing }
                else { trend = .steady }
```

重跑：`testUnequalWindowsAreComparedByRateNotByRawCount` 必须变红（会判成 `.steady`）。

**突变 B：** 把样本量门槛那一支删掉，即把

```swift
            if earlier.count < minimumEarlierWindow {
                trend = .notEnoughData
            } else if isNew {
```

改成

```swift
            if isNew {
```

重跑：`testNotEnoughDataWhenTheEarlierWindowIsTooSmall` 必须变红。

**突变 C：** 把 `isNew` 里的 `!hasOlderHistory` 去掉。重跑：`testIssueWithHistoryOlderThanBothWindowsIsNotNew` 必须变红。

三次都改回，确认全绿，把每次的输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Stats/IssueTrendAnalyzer.swift Tests/IELTSCoachCoreTests/IssueTrendAnalyzerTests.swift
git commit -m "feat(core): 问题趋势判定（按场次窗口比频率，不做任何分数预测）"
```

---

## Task 4: 首页统计 `TrainingStats`

**Files:**
- Create: `Sources/IELTSCoachCore/Stats/TrainingStats.swift`
- Create: `Tests/IELTSCoachCoreTests/TrainingStatsTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`sessions`、`issues`、`settings.weeklyGoal`）、`CoachTime.parse`、`CoachTime.parseDayPrefix`、`IssueTrendAnalyzer.analyze`
- Produces:
  - `struct TrainingStats: Equatable, Sendable`，字段：`weeklyDone`、`weeklyGoal`、`totalSessions`、`weeklySpokenMinutes`、`improvingIssueCount`、`trackedIssueCount`、`sessionsMissingDuration`、`cappedSessionCount`、`undatedSessionCount`（全部 `Int`）
  - `TrainingStats.maxCountedMinutesPerSession: Int`（= 120）
  - `TrainingStats.compute(state:now:calendar:) -> TrainingStats`

### 三个诊断字段为什么必须存在

`weeklySpokenMinutes` 是由「每场的开始与结束时间之差」加出来的。三种情况会让这个数字与用户的实际感受对不上，**每一种都必须能在界面上解释清楚，不能悄悄吞掉**：

| 字段 | 什么情况 | 不报的后果 |
|---|---|---|
| `sessionsMissingDuration` | 本周有练习记录，但 `endedAt` 是空的、或早于 `startedAt` | 用户练了 40 分钟，界面显示 0 分钟，他会认为工具坏了 |
| `cappedSessionCount` | 单场超过 2 小时（多半是忘了点「我练完了」） | 「本周开口时长 743 分钟」会让整个统计失去可信度 |
| `undatedSessionCount` | `startedAt` 与 id 都解析不出时间 | 这场既进不了本周也进不了任何窗口，凭空消失 |

`totalSessions` 直接取 `state.sessions.count`，不做任何过滤——「累计练了多少场」应当是个不会因为解析失败而变小的数字。

**不做的事：** 这里没有、将来也不许有任何形如「预计分数」「水平评估」的字段。第四格统计是「出现变少的毛病有几个」，这是个可核对的计数，不是评判。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/TrainingStatsTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class TrainingStatsTests: XCTestCase {

    /// 固定「现在」= 2026-08-05T12:00:00Z。用 ISO 日历 + 上海时区，
    /// 本周是 2026-08-03（周一）00:00 CST 到 2026-08-10 00:00 CST。
    private let now = CoachTime.parse("2026-08-05T12:00:00Z")!

    private var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func session(_ id: String, started: String, ended: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: started,
                        endedAt: ended, goal: "", transcript: [],
                        reportPath: "", recordingPath: "")
    }

    private func state(_ sessions: [PracticeSession],
                       issues: [IssueRecord] = [],
                       weeklyGoal: Int? = nil) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.issues = issues
        if let weeklyGoal { value.settings.weeklyGoal = weeklyGoal }
        return value
    }

    private func compute(_ value: CoachState) -> TrainingStats {
        TrainingStats.compute(state: value, now: now, calendar: calendar)
    }

    // MARK: - 本周次数与累计次数

    func testWeeklyDoneCountsOnlyThisWeekButTotalCountsEverything() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T10:20:00Z")
        ]))
        XCTAssertEqual(stats.weeklyDone, 2)
        XCTAssertEqual(stats.totalSessions, 3, "累计次数不该被「本周」筛掉")
    }

    func testWeeklyGoalComesFromSettingsAndDefaultsToFive() {
        XCTAssertEqual(compute(state([])).weeklyGoal, 5)
        XCTAssertEqual(compute(state([], weeklyGoal: 3)).weeklyGoal, 3)
    }

    // MARK: - 本周开口时长

    func testWeeklySpokenMinutesSumsThisWeeksDurations() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T11:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 42, "30 + 12，上周那场不算")
        XCTAssertEqual(stats.sessionsMissingDuration, 0)
    }

    func testMissingEndTimeIsReportedInsteadOfSilentlyCountingZero() {
        // 用户练了一场却显示 0 分钟，他会认为工具坏了。必须能解释。
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "")
        ]))
        XCTAssertEqual(stats.weeklyDone, 1, "没有结束时间不影响「练了几场」")
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.sessionsMissingDuration, 1)
    }

    func testEndTimeEarlierThanStartTimeIsReportedNotSubtracted() {
        let stats = compute(state([
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T09:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, 0, "负时长绝不能被加进去")
        XCTAssertEqual(stats.sessionsMissingDuration, 1)
    }

    func testOverlongSessionIsCappedAndReported() {
        // 忘了点「我练完了」，一场记成 4 小时。
        // 「本周开口时长 240 分钟」会让整个统计失去可信度。
        let stats = compute(state([
            session("a", started: "2026-08-05T06:00:00Z", ended: "2026-08-05T10:00:00Z")
        ]))
        XCTAssertEqual(stats.weeklySpokenMinutes, TrainingStats.maxCountedMinutesPerSession)
        XCTAssertEqual(stats.cappedSessionCount, 1)
    }

    func testUndatableSessionIsReportedAndExcludedFromTheWeek() {
        let stats = compute(state([
            session("sync-1754123456", started: "", ended: ""),
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z")
        ]))
        XCTAssertEqual(stats.weeklyDone, 1)
        XCTAssertEqual(stats.undatedSessionCount, 1)
        XCTAssertEqual(stats.totalSessions, 2, "读不出时间也还是练过的一场")
    }

    func testSessionWithoutStartedAtFallsBackToTheDateInItsID() {
        // Phase 4 之前的记录可能只有 id。不能因此整条丢掉。
        let stats = compute(state([session("2026-08-05-001", started: "", ended: "")]))
        XCTAssertEqual(stats.weeklyDone, 1)
        XCTAssertEqual(stats.undatedSessionCount, 0)
    }

    // MARK: - 出现变少的毛病

    func testImprovingCountsGoneAndDecreasingOnly() {
        func julySession(_ day: Int) -> PracticeSession {
            let stamp = String(format: "2026-07-%02d", day)
            return session("\(stamp)-001", started: "\(stamp)T10:00:00Z",
                           ended: "\(stamp)T10:30:00Z")
        }
        func issue(_ id: String, days: [Int]) -> IssueRecord {
            IssueRecord(id: id, learnerSaid: "s-\(id)", correction: "c", whyItMatters: "w",
                        occurrences: days.count,
                        sourceSessionIds: days.map { String(format: "2026-07-%02d-001", $0) },
                        lastSeenAt: "2026-07-10T10:00:00Z")
        }
        let stats = compute(state((1...10).map(julySession), issues: [
            issue("gone", days: [1, 2]),                 // .gone
            issue("down", days: [1, 2, 3, 4, 10]),       // .decreasing
            issue("up", days: [1, 8, 9, 10])             // .increasing
        ]))
        XCTAssertEqual(stats.improvingIssueCount, 2)
        XCTAssertEqual(stats.trackedIssueCount, 3)
    }

    func testEmptyStateProducesAllZerosWithoutCrashing() {
        let stats = compute(CoachState.empty())
        XCTAssertEqual(stats.weeklyDone, 0)
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.weeklySpokenMinutes, 0)
        XCTAssertEqual(stats.improvingIssueCount, 0)
        XCTAssertEqual(stats.trackedIssueCount, 0)
        XCTAssertEqual(stats.weeklyGoal, 5)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TrainingStatsTests`
Expected: 编译失败 —— `TrainingStats` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Stats/TrainingStats.swift`：

```swift
import Foundation

/// 首页四格统计。
///
/// **这里不会、也不许出现任何形式的雅思分数预测**（DEFINITION-OF-DONE 第 4 节）。
/// 第四格是「出现变少的毛病有几个」——一个用户能自己数出来核对的计数，
/// 不是对他水平的评判。
public struct TrainingStats: Equatable, Sendable {
    public let weeklyDone: Int
    public let weeklyGoal: Int
    public let totalSessions: Int
    public let weeklySpokenMinutes: Int
    /// 趋势是 .gone 或 .decreasing 的毛病个数。
    public let improvingIssueCount: Int
    /// 问题档案里一共有几个毛病，给「N 个里的 M 个」这种说法用。
    public let trackedIssueCount: Int

    // MARK: 诊断字段。非 0 时界面必须解释，禁止静默吞掉。

    /// 本周有记录、但算不出时长的场次（缺 endedAt，或 endedAt 不晚于 startedAt）。
    public let sessionsMissingDuration: Int
    /// 本周超过 maxCountedMinutesPerSession 被截断的场次。
    public let cappedSessionCount: Int
    /// startedAt 与 id 都解析不出时间、因此进不了任何一周的场次。
    public let undatedSessionCount: Int

    /// 单场计入上限。忘了点「我练完了」会让一场记成好几个小时，
    /// 「本周开口时长 743 分钟」会让整个统计失去可信度。
    public static let maxCountedMinutesPerSession = 120

    public init(weeklyDone: Int, weeklyGoal: Int, totalSessions: Int,
                weeklySpokenMinutes: Int, improvingIssueCount: Int, trackedIssueCount: Int,
                sessionsMissingDuration: Int, cappedSessionCount: Int,
                undatedSessionCount: Int) {
        self.weeklyDone = weeklyDone; self.weeklyGoal = weeklyGoal
        self.totalSessions = totalSessions; self.weeklySpokenMinutes = weeklySpokenMinutes
        self.improvingIssueCount = improvingIssueCount; self.trackedIssueCount = trackedIssueCount
        self.sessionsMissingDuration = sessionsMissingDuration
        self.cappedSessionCount = cappedSessionCount
        self.undatedSessionCount = undatedSessionCount
    }

    /// - Parameters:
    ///   - calendar: 默认用 ISO8601 日历（周一为一周之始）。测试必须显式传入
    ///     固定时区的日历，否则结果随运行机器的时区变化。
    public static func compute(state: CoachState,
                               now: Date = Date(),
                               calendar: Calendar = Calendar(identifier: .iso8601)) -> TrainingStats {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)

        var weeklyDone = 0
        var minutes = 0
        var missingDuration = 0
        var capped = 0
        var undated = 0

        for session in state.sessions {
            guard let started = CoachTime.parse(session.startedAt)
                ?? CoachTime.parseDayPrefix(session.id) else {
                undated += 1
                continue
            }
            guard let week, week.contains(started) else { continue }
            weeklyDone += 1

            guard let ended = CoachTime.parse(session.endedAt), ended > started else {
                // 缺结束时间、或结束时间早于开始时间。按 0 计入，但必须报出来——
                // 用户练了 40 分钟却看到 0 分钟，会以为工具坏了。
                missingDuration += 1
                continue
            }

            let raw = Int((ended.timeIntervalSince(started) / 60).rounded())
            if raw > maxCountedMinutesPerSession {
                capped += 1
                minutes += maxCountedMinutesPerSession
            } else {
                minutes += raw
            }
        }

        let trends = IssueTrendAnalyzer.analyze(state: state)
        let improving = trends.filter { $0.trend == .gone || $0.trend == .decreasing }.count

        return TrainingStats(
            weeklyDone: weeklyDone,
            weeklyGoal: state.settings.weeklyGoal,
            totalSessions: state.sessions.count,
            weeklySpokenMinutes: minutes,
            improvingIssueCount: improving,
            trackedIssueCount: state.issues.count,
            sessionsMissingDuration: missingDuration,
            cappedSessionCount: capped,
            undatedSessionCount: undated)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TrainingStatsTests`
Expected: PASS（10 个测试）

- [ ] **Step 5: 突变验证（三处）**

**突变 A：** 把负时长那一支改成照常相减，即把

```swift
            guard let ended = CoachTime.parse(session.endedAt), ended > started else {
```

改成

```swift
            guard let ended = CoachTime.parse(session.endedAt) else {
```

重跑：`testEndTimeEarlierThanStartTimeIsReportedNotSubtracted` 必须变红（会加进一个负数）。

**突变 B：** 把截断那一支去掉，改成 `minutes += raw`。重跑：`testOverlongSessionIsCappedAndReported` 必须变红。

**突变 C：** 把 `totalSessions` 改成 `weeklyDone`。重跑：`testWeeklyDoneCountsOnlyThisWeekButTotalCountsEverything`、`testUndatableSessionIsReportedAndExcludedFromTheWeek` 必须变红。

三次都改回，确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Stats/TrainingStats.swift Tests/IELTSCoachCoreTests/TrainingStatsTests.swift
git commit -m "feat(core): 首页训练统计（含三个必须解释的诊断字段）"
```

---

## Task 5: 词汇优先级归一 + Anki 导出

**Files:**
- Create: `Sources/IELTSCoachCore/Model/VocabularyPriority.swift`
- Create: `Sources/IELTSCoachCore/Export/VocabularyExporter.swift`
- Create: `Tests/IELTSCoachCoreTests/VocabularyExporterTests.swift`

**Interfaces:**
- Consumes: `VocabularyRecord`（`id`、`basicWord`、`betterExpression`、`collocation`、`priority`、`sourceSessionIds`）、`CoachTime.dayString`、`JSONValue.decode`（仅测试用）
- Produces:
  - `enum VocabularyPriority: String, CaseIterable, Equatable, Sendable { case high, normal, low }`
    - `static func normalize(_ raw: String) -> VocabularyPriority`
    - `var title: String` / `var sortRank: Int` / `var ankiTag: String`
  - `struct ExportDocument: Equatable, Sendable { let text: String; let suggestedFileName: String; let exportedCount: Int; let skipped: [String] }`
  - `enum VocabularyExportFormat: String, CaseIterable, Identifiable, Sendable { case ankiTSV, ankiConnectJSON }`
    - `var title: String` / `var fileExtension: String` / `var howToUse: String`
  - `enum VocabularyExporter`
    - `static let defaultDeckName = "IELTS Speaking Coach"`
    - `static let defaultNoteType = "Basic"`
    - `static let baseTag = "ielts-speaking"`
    - `static func export(_ records: [VocabularyRecord], format:deckName:noteType:exportedAt:calendar:) -> ExportDocument`

### 为什么是两种格式

用户已经有一套 Anki 流程。导出必须**能直接对接**，而不是丢给他一个还要自己转换的文件：

| 格式 | 长什么样 | 用户怎么用 |
|---|---|---|
| `ankiTSV` | 制表符分隔的 `.txt`，开头带 Anki 的 `#` 指令行 | Anki 里「文件 › 导入」直接选它，牌组、笔记类型、标签列都已经写在文件里 |
| `ankiConnectJSON` | 一份可以原样 POST 的 `addNotes` 请求体 | `curl -s localhost:8765 -d @文件`，接他已有的 AnkiConnect 脚本 |

### 字段清洗规则（照做，不要自作主张改成加引号）

TSV 里一个制表符就是一次分列，一个换行就是一条新记录。词汇里出现制表符或换行会**静默地**把一条卡片切成两条、或多出一列——用户在 Anki 里根本不会发现。

处理办法是**清洗**而不是加引号：加引号要处理转义、要赌 Anki 版本认不认，清洗是确定性的、可测的。

```
制表符          → 一个空格
\r\n / \r / \n  → <br>          （所以文件头必须声明 #html:true）
首尾空白         → 去掉
```

### 什么时候跳过一条记录（必须报，不能静默少导）

| 情况 | 为什么跳过 |
|---|---|
| 清洗后 `basicWord` 为空 | Anki 会拒收正面为空的卡片 |
| `betterExpression` 与 `collocation` 都为空 | 卡片背面是空的，记它没有意义 |
| 词汇本整个是空的 | 不是错误，但导出一个只有文件头的文件必须说清楚 |

**每一条跳过都要生成一句中文说明，含「下一步」。** 这与 `ArchiveOutcome.skipped` 是同一个思路：静默的 0 是本项目已知最危险的失败形态。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/VocabularyExporterTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class VocabularyExporterTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let exportedAt = CoachTime.parse("2026-08-06T01:00:00Z")!

    private func record(_ id: String, basic: String, better: String = "rewarding",
                        collocation: String = "a rewarding trip",
                        priority: String = "high") -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: basic, betterExpression: better,
                         collocation: collocation, priority: priority,
                         sourceSessionIds: ["2026-08-01-001"])
    }

    private func tsv(_ records: [VocabularyRecord]) -> ExportDocument {
        VocabularyExporter.export(records, format: .ankiTSV,
                                  exportedAt: exportedAt, calendar: utc)
    }

    /// 去掉文件头之后的数据行。
    private func dataLines(_ document: ExportDocument) -> [String] {
        document.text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }

    // MARK: - 优先级归一

    func testPriorityNormalizationHandlesEveryShapeChatGPTMightEmit() {
        XCTAssertEqual(VocabularyPriority.normalize("high"), .high)
        XCTAssertEqual(VocabularyPriority.normalize("  HIGH "), .high)
        XCTAssertEqual(VocabularyPriority.normalize("low"), .low)
        // ChatGPT 写过 "medium"；上游默认值是 "normal"；也可能整个字段是空的。
        // 任何没见过的写法都当普通，不能崩、也不能凭空多出一个档次。
        XCTAssertEqual(VocabularyPriority.normalize("medium"), .normal)
        XCTAssertEqual(VocabularyPriority.normalize("normal"), .normal)
        XCTAssertEqual(VocabularyPriority.normalize(""), .normal)
        XCTAssertEqual(VocabularyPriority.normalize("紧急"), .normal)
    }

    func testPrioritySortRankPutsHighFirst() {
        XCTAssertLessThan(VocabularyPriority.high.sortRank, VocabularyPriority.normal.sortRank)
        XCTAssertLessThan(VocabularyPriority.normal.sortRank, VocabularyPriority.low.sortRank)
    }

    // MARK: - TSV

    func testTSVHeaderTellsAnkiEverythingItNeeds() {
        let text = tsv([record("v1", basic: "good")]).text
        for directive in ["#separator:tab", "#html:true", "#notetype:Basic",
                          "#deck:IELTS Speaking Coach", "#tags column:3"] {
            XCTAssertTrue(text.contains(directive), "文件头缺少 \(directive)")
        }
    }

    func testTSVRowHasThreeColumnsInTheDeclaredOrder() {
        let document = tsv([record("v1", basic: "good")])
        let lines = dataLines(document)
        XCTAssertEqual(lines.count, 1)
        let columns = lines[0].components(separatedBy: "\t")
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0], "good")
        XCTAssertEqual(columns[1], "rewarding<br>a rewarding trip")
        XCTAssertEqual(columns[2], "ielts-speaking ielts-speaking::high")
        XCTAssertEqual(document.exportedCount, 1)
    }

    func testTabsAndNewlinesInsideFieldsCannotBreakTheTable() {
        // 一个制表符就是一次分列，一个换行就是一条新记录。
        // 不清洗的话，一条卡片会被静默切成两条或多出一列，
        // 用户在 Anki 里根本不会发现。
        let document = tsv([record("v1", basic: "a\tb", better: "line1\nline2",
                                   collocation: "", priority: "normal")])
        let lines = dataLines(document)
        XCTAssertEqual(lines.count, 1, "换行必须被替换掉，不能变成第二行")
        let columns = lines[0].components(separatedBy: "\t")
        XCTAssertEqual(columns.count, 3, "制表符必须被替换掉，不能多出一列")
        XCTAssertEqual(columns[0], "a b")
        XCTAssertEqual(columns[1], "line1<br>line2")
    }

    func testRecordWithoutBasicWordIsSkippedWithAnActionableMessage() {
        let document = tsv([record("v1", basic: "   "), record("v2", basic: "good")])
        XCTAssertEqual(document.exportedCount, 1)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("下一步"))
    }

    func testRecordWithEmptyBackIsSkippedWithAnActionableMessage() {
        let document = tsv([record("v1", basic: "good", better: "", collocation: "")])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("good"), "说明里要指出是哪一条被跳过了")
        XCTAssertTrue(document.skipped[0].contains("下一步"))
    }

    func testEmptyVocabularySaysSoInsteadOfHandingOverAnEmptyFile() {
        let document = tsv([])
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains("下一步"))
        XCTAssertTrue(dataLines(document).isEmpty)
    }

    func testExportOrderFollowsTheGivenOrder() {
        let document = tsv([record("v1", basic: "a"), record("v2", basic: "b")])
        XCTAssertEqual(dataLines(document).map { $0.components(separatedBy: "\t")[0] },
                       ["a", "b"], "导出顺序必须等于传入顺序，界面才能所见即所得")
    }

    // MARK: - AnkiConnect JSON

    func testAnkiConnectPayloadIsAValidAddNotesRequest() throws {
        let document = VocabularyExporter.export([record("v1", basic: "good")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        let root = try JSONValue.decode(from: document.text)
        XCTAssertEqual(root["action"]?.stringValue, "addNotes")
        XCTAssertEqual(root["version"], .number(6))

        let notes = try XCTUnwrap(root["params"]?["notes"]?.arrayValue)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0]["deckName"]?.stringValue, "IELTS Speaking Coach")
        XCTAssertEqual(notes[0]["modelName"]?.stringValue, "Basic")
        XCTAssertEqual(notes[0]["fields"]?["Front"]?.stringValue, "good")
        XCTAssertEqual(notes[0]["fields"]?["Back"]?.stringValue, "rewarding<br>a rewarding trip")
        XCTAssertEqual(notes[0]["tags"]?.arrayValue?.compactMap(\.stringValue),
                       ["ielts-speaking", "ielts-speaking::high"])
        XCTAssertEqual(document.exportedCount, 1)
    }

    func testAnkiConnectSkipsTheSameRecordsAsTSV() throws {
        let document = VocabularyExporter.export([record("v1", basic: "")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        let notes = try XCTUnwrap(
            try JSONValue.decode(from: document.text)["params"]?["notes"]?.arrayValue)
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - 文件名与使用说明

    func testSuggestedFileNameCarriesTheDateAndTheRightExtension() {
        XCTAssertEqual(tsv([record("v1", basic: "good")]).suggestedFileName,
                       "ielts-vocabulary-2026-08-06.txt")
        XCTAssertEqual(VocabularyExporter.export([record("v1", basic: "good")],
                                                 format: .ankiConnectJSON,
                                                 exportedAt: exportedAt, calendar: utc)
                        .suggestedFileName,
                       "ielts-vocabulary-2026-08-06.json")
    }

    func testEveryFormatExplainsHowToUseItIncludingTheNextStep() {
        for format in VocabularyExportFormat.allCases {
            XCTAssertFalse(format.title.isEmpty, "\(format) 缺少显示名")
            XCTAssertTrue(format.howToUse.contains("下一步"),
                          "\(format) 必须告诉用户拿到文件之后干什么：\(format.howToUse)")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter VocabularyExporterTests`
Expected: 编译失败 —— `VocabularyPriority`、`VocabularyExporter` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Model/VocabularyPriority.swift`：

```swift
import Foundation

/// 词汇优先级。`VocabularyRecord.priority` 存的是 ChatGPT 给的原始字符串，
/// 写法不受控（见过 "high" / "medium" / "normal" / 空）。归一到三档再用。
public enum VocabularyPriority: String, CaseIterable, Equatable, Sendable {
    case high, normal, low

    /// 任何没见过的写法都当普通。**不要在这里抛错或新增档次**——
    /// 一个拼错的优先级不该让整页词汇显示不出来。
    public static func normalize(_ raw: String) -> VocabularyPriority {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "h", "1": return .high
        case "low", "l", "3": return .low
        default: return .normal
        }
    }

    /// 中文档次名。用「记不记」的说法而不是「高/中/低」——
    /// 用户要的是「先背哪个」，不是一个抽象等级。
    public var title: String {
        switch self {
        case .high: return "优先记"
        case .normal: return "有空再记"
        case .low: return "先放着"
        }
    }

    public var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    /// Anki 的层级标签写法。
    public var ankiTag: String { "ielts-speaking::\(rawValue)" }
}
```

`Sources/IELTSCoachCore/Export/VocabularyExporter.swift`：

```swift
import Foundation

/// 一份导出结果。`skipped` 必须被界面显示出来——
/// 静默少导出几条，用户在 Anki 里根本不会发现。
public struct ExportDocument: Equatable, Sendable {
    public let text: String
    public let suggestedFileName: String
    public let exportedCount: Int
    /// 每条都是一句中文说明，含「发生了什么 + 下一步做什么」。
    public let skipped: [String]

    public init(text: String, suggestedFileName: String, exportedCount: Int, skipped: [String]) {
        self.text = text; self.suggestedFileName = suggestedFileName
        self.exportedCount = exportedCount; self.skipped = skipped
    }
}

public enum VocabularyExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// 制表符分隔的 Anki 导入文件。
    case ankiTSV
    /// 可以原样 POST 给 AnkiConnect 的 addNotes 请求体。
    case ankiConnectJSON

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ankiTSV: return "Anki 导入文件（.txt）"
        case .ankiConnectJSON: return "AnkiConnect 请求（.json）"
        }
    }

    public var fileExtension: String {
        switch self {
        case .ankiTSV: return "txt"
        case .ankiConnectJSON: return "json"
        }
    }

    /// 界面必须把这段话显示在导出入口旁边。导出一个文件却不说怎么用，
    /// 等于没做这个功能。
    public var howToUse: String {
        switch self {
        case .ankiTSV:
            return "在 Anki 里选「文件 › 导入」，选中这个文件即可。"
                + "牌组、笔记类型、分隔符、标签列都已经写在文件开头，正常情况下不用改导入对话框里的任何设置。"
                + "下一步：如果你的 Anki 版本较老、导入对话框没有自动带出这些设置，"
                + "在对话框里手动把分隔符选成「制表符」，并把第 3 列指定为标签列。"
        case .ankiConnectJSON:
            return "这是一份可以直接发给 AnkiConnect 的 addNotes 请求。"
                + "下一步：确认 Anki 正在运行且已安装 AnkiConnect 插件，然后执行"
                + " curl -s localhost:8765 -d @<这个文件的路径>。"
        }
    }
}

public enum VocabularyExporter {
    public static let defaultDeckName = "IELTS Speaking Coach"
    public static let defaultNoteType = "Basic"
    public static let baseTag = "ielts-speaking"

    public static func export(_ records: [VocabularyRecord],
                              format: VocabularyExportFormat,
                              deckName: String = defaultDeckName,
                              noteType: String = defaultNoteType,
                              exportedAt: Date = Date(),
                              calendar: Calendar = .current) -> ExportDocument {
        let built = notes(from: records)
        var skipped = built.skipped
        if records.isEmpty {
            skipped.append("词汇本还是空的，导出的文件里没有任何卡片。"
                + "下一步：先练一场并让 ChatGPT 生成复盘，推荐词汇会自动进词汇本。")
        }

        let fileName = "ielts-vocabulary-"
            + CoachTime.dayString(exportedAt, calendar: calendar)
            + ".\(format.fileExtension)"

        let text: String
        switch format {
        case .ankiTSV:
            text = tsvText(built.notes, deckName: deckName, noteType: noteType)
        case .ankiConnectJSON:
            let outcome = jsonText(built.notes, deckName: deckName, noteType: noteType)
            text = outcome.text
            if let failure = outcome.failure { skipped.append(failure) }
        }

        return ExportDocument(text: text, suggestedFileName: fileName,
                              exportedCount: built.notes.count, skipped: skipped)
    }

    // MARK: - 从记录到卡片

    private struct Note {
        let front: String
        let back: String
        let tags: [String]
    }

    private static func notes(from records: [VocabularyRecord]) -> (notes: [Note], skipped: [String]) {
        var notes: [Note] = []
        var skipped: [String] = []

        for record in records {
            let front = sanitize(record.basicWord)
            guard !front.isEmpty else {
                skipped.append("跳过了一条词汇：它没有「原来的说法」，而 Anki 会拒收正面为空的卡片。"
                    + "下一步：到「我的词汇」页把这条删掉，或等下一次复盘把它补全。")
                continue
            }
            let parts = [sanitize(record.betterExpression), sanitize(record.collocation)]
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else {
                skipped.append("跳过了「\(front)」：它既没有更好的说法，也没有搭配，做成卡片背面是空的。"
                    + "下一步：等下一次复盘补上，或到「我的词汇」页把这条删掉。")
                continue
            }
            notes.append(Note(front: front,
                              back: parts.joined(separator: "<br>"),
                              tags: [baseTag, VocabularyPriority.normalize(record.priority).ankiTag]))
        }
        return (notes, skipped)
    }

    /// 让一段文本可以安全地放进 TSV 的一格里。
    ///
    /// **用清洗而不是加引号**：加引号要处理转义、还要赌 Anki 版本认不认；
    /// 清洗是确定性的、可测的。替换顺序不能变——先处理 \r\n，
    /// 否则会被拆成两个 <br>。
    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - TSV

    private static func tsvText(_ notes: [Note], deckName: String, noteType: String) -> String {
        // 这五行是 Anki 2.1.55 起支持的导入指令。带上它们，用户导入时
        // 不需要在对话框里点任何东西。#html:true 是必须的——
        // 清洗时把换行换成了 <br>。
        var lines = [
            "#separator:tab",
            "#html:true",
            "#notetype:\(sanitize(noteType))",
            "#deck:\(sanitize(deckName))",
            "#tags column:3"
        ]
        for note in notes {
            lines.append([note.front, note.back, note.tags.joined(separator: " ")]
                .joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - AnkiConnect

    private struct AnkiConnectRequest: Encodable {
        let action: String
        let version: Int
        let params: Params

        struct Params: Encodable { let notes: [Note] }

        struct Note: Encodable {
            let deckName: String
            let modelName: String
            let fields: [String: String]
            let tags: [String]
            let options: Options

            struct Options: Encodable {
                let allowDuplicate: Bool
                let duplicateScope: String
            }
        }
    }

    private static func jsonText(_ notes: [Note], deckName: String,
                                 noteType: String) -> (text: String, failure: String?) {
        let request = AnkiConnectRequest(
            action: "addNotes", version: 6,
            params: .init(notes: notes.map { note in
                .init(deckName: deckName, modelName: noteType,
                      fields: ["Front": note.front, "Back": note.back],
                      tags: note.tags,
                      // allowDuplicate: false —— 同一个词多次复盘都会被推荐，
                      // 重复导入不该在牌组里堆出十张一样的卡。
                      options: .init(allowDuplicate: false, duplicateScope: "deck"))
            }))

        let encoder = JSONEncoder()
        // sortedKeys 让输出稳定：同一份词汇本导两次得到同样的文件，
        // 用户 diff 得出来，测试也断言得了。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(request),
              let text = String(data: data, encoding: .utf8) else {
            return ("", "生成 AnkiConnect 请求失败，这个文件不能用。"
                + "下一步：改用「Anki 导入文件（.txt）」格式导出，它不经过 JSON 编码。")
        }
        return (text, nil)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter VocabularyExporterTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证（三处）**

**突变 A（最重要）：** 把 `sanitize` 里的制表符替换删掉

```swift
        text.replacingOccurrences(of: "\r\n", with: "<br>")
```

重跑：`testTabsAndNewlinesInsideFieldsCannotBreakTheTable` 必须变红（列数变成 4）。

**这条守的是一种不会被发现的错**：多出来的列不报错、不崩溃，只是让那张卡片在 Anki 里变成一堆乱码，而用户导入完根本不会逐张检查。

**突变 B：** 把「背面为空就跳过」那一支去掉（把 `guard !parts.isEmpty else {...}` 整段删掉，`back` 用 `parts.joined(...)`）。重跑：`testRecordWithEmptyBackIsSkippedWithAnActionableMessage` 必须变红。

**突变 C：** 把 `VocabularyPriority.normalize` 的 `default` 分支改成 `return .high`。重跑：`testPriorityNormalizationHandlesEveryShapeChatGPTMightEmit` 必须变红。

三次都改回，确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/Model/VocabularyPriority.swift Sources/IELTSCoachCore/Export/VocabularyExporter.swift Tests/IELTSCoachCoreTests/VocabularyExporterTests.swift
git commit -m "feat(core): 词汇优先级归一与 Anki 导出（TSV + AnkiConnect）"
```

---

## Task 6: 问题档案页

**Files:**
- Create: `Sources/IELTSCoachUI/Issues/IssueArchiveViewModel.swift`
- Create: `Sources/IELTSCoachUI/Issues/IssueArchiveView.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Tests/IELTSCoachUITests/IssueArchiveViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState.issues`、`IssueRecord`、`IssueTrendAnalyzer.analyze(state:windowSize:)`、`IssueTrendResult`、`IssueTrend`、`SessionTimeline.build(state:).warnings`、`CoachTime.parse`、`CoachTime.dayString`、`AppState.state`、Phase 3 的 `CoachCard` / `SectionHeader` / `EmptyStateView` / `Palette` / `Spacing` / `Radius`
- Produces:
  - `enum IssueFilter: String, CaseIterable, Identifiable, Sendable { case all, recurring, new, improving }`，含 `title`
  - `struct IssueArchiveRow: Equatable, Identifiable, Sendable`，字段：`id`、`learnerSaid`、`correction`、`whyItMatters`、`occurrences`、`sessionCount`、`isNew`、`trend`、`detail`、`lastSeenText`
  - `struct IssueArchiveViewModel: Sendable`
    - `init(state: CoachState, calendar: Calendar = .current, windowSize: Int = IssueTrendAnalyzer.defaultWindowSize)`
    - `let rows: [IssueArchiveRow]`
    - `let dataWarnings: [String]`
    - `func rows(filter: IssueFilter) -> [IssueArchiveRow]`
    - `var counts: (total: Int, new: Int, improving: Int)`
  - `IssueArchiveView`
  - `SidebarItem.isImplemented` 对 `.issues` 返回 `true`

**排序规则：** 出现次数倒序 → 最近一次出现时间倒序 → id 升序。第三级是为了让排序**完全确定**——不确定的排序会让同一份数据每次打开的顺序都不一样，用户会以为记录变了。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/IssueArchiveViewModelTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class IssueArchiveViewModelTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func sessionID(_ day: Int) -> String { String(format: "2026-07-%02d-001", day) }

    private func session(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return PracticeSession(id: "\(stamp)-001", questionId: "q", focusPart: .part1,
                               startedAt: "\(stamp)T10:00:00Z", endedAt: "\(stamp)T10:30:00Z",
                               goal: "", transcript: [], reportPath: "", recordingPath: "")
    }

    private func issue(_ id: String, occurrences: Int, days: [Int],
                       lastSeen: String? = nil) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix-\(id)",
                    whyItMatters: "why-\(id)", occurrences: occurrences,
                    sourceSessionIds: days.map(sessionID),
                    lastSeenAt: lastSeen
                        ?? String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    private func state(_ issues: [IssueRecord], sessionCount: Int = 10) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessionCount > 0 ? (1...sessionCount).map(session) : []
        value.issues = issues
        return value
    }

    private func viewModel(_ value: CoachState) -> IssueArchiveViewModel {
        IssueArchiveViewModel(state: value, calendar: utc)
    }

    // MARK: - 排序

    func testRowsAreSortedByOccurrencesDescending() {
        // 「错题按出现次数排序」是这一页的第一条产品要求。
        let model = viewModel(state([
            issue("a", occurrences: 2, days: [1]),
            issue("b", occurrences: 9, days: [2]),
            issue("c", occurrences: 5, days: [3])
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["b", "c", "a"])
    }

    func testTiesAreBrokenByLastSeenThenByIDSoTheOrderIsStable() {
        // 不确定的排序会让同一份数据每次打开顺序都不一样，
        // 用户会以为记录被改了。
        let model = viewModel(state([
            issue("z", occurrences: 3, days: [1], lastSeen: "2026-07-05T10:00:00Z"),
            issue("a", occurrences: 3, days: [1], lastSeen: "2026-07-05T10:00:00Z"),
            issue("m", occurrences: 3, days: [1], lastSeen: "2026-07-09T10:00:00Z")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["m", "a", "z"])
    }

    // MARK: - 行内容

    func testRowCarriesTrendAndNewFlagFromTheAnalyzer() {
        let model = viewModel(state([
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        let down = model.rows.first { $0.id == "down" }
        let fresh = model.rows.first { $0.id == "fresh" }
        XCTAssertEqual(down?.trend, .decreasing)
        XCTAssertEqual(fresh?.trend, .fresh)
        XCTAssertEqual(fresh?.isNew, true)
        XCTAssertEqual(down?.isNew, false)
    }

    func testSessionCountDeduplicatesRepeatedSessionIDs() {
        var record = issue("a", occurrences: 4, days: [1])
        record.sourceSessionIds = [sessionID(1), sessionID(1), sessionID(2)]
        XCTAssertEqual(viewModel(state([record])).rows[0].sessionCount, 2)
    }

    func testLastSeenTextUsesTheGivenCalendar() {
        let model = viewModel(state([
            issue("a", occurrences: 1, days: [5], lastSeen: "2026-07-05T23:30:00Z")
        ]))
        XCTAssertEqual(model.rows[0].lastSeenText, "最近一次：2026-07-05")
    }

    func testUnparsableLastSeenSaysSoInsteadOfShowingAWrongDate() {
        let model = viewModel(state([
            issue("a", occurrences: 1, days: [5], lastSeen: "")
        ]))
        XCTAssertEqual(model.rows[0].lastSeenText, "最近一次：时间不详")
    }

    func testDuplicateIssueIDsDoNotCrash() {
        // state.json 被外部工具改坏、或上游写入过重复 id 时，
        // 用 Dictionary(uniqueKeysWithValues:) 建索引会 fatalError 闪退整个 App。
        let model = viewModel(state([
            issue("dup", occurrences: 3, days: [1]),
            issue("dup", occurrences: 1, days: [2])
        ]))
        XCTAssertEqual(model.rows.count, 2)
    }

    // MARK: - 筛选与计数

    func testFiltersReturnTheRightSubsets() {
        let model = viewModel(state([
            issue("once", occurrences: 1, days: [1]),
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        XCTAssertEqual(Set(model.rows(filter: .all).map(\.id)), ["once", "down", "fresh"])
        XCTAssertEqual(Set(model.rows(filter: .recurring).map(\.id)), ["down", "fresh"])
        XCTAssertEqual(model.rows(filter: .new).map(\.id), ["fresh"])
        XCTAssertEqual(Set(model.rows(filter: .improving).map(\.id)), ["once", "down"])
    }

    func testCountsMatchTheFilters() {
        let model = viewModel(state([
            issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
            issue("fresh", occurrences: 2, days: [9, 10])
        ]))
        XCTAssertEqual(model.counts.total, 2)
        XCTAssertEqual(model.counts.new, 1)
        XCTAssertEqual(model.counts.improving, 1)
    }

    func testEveryFilterHasAChineseTitle() {
        for filter in IssueFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty, "\(filter) 缺少中文标题")
        }
    }

    // MARK: - 空与异常

    func testEmptyArchiveProducesNoRowsAndNoWarnings() {
        let model = viewModel(CoachState.empty())
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.dataWarnings.isEmpty)
        XCTAssertEqual(model.counts.total, 0)
    }

    func testDataWarningsAreSurfacedFromTheTimeline() {
        // 时间轴发现的问题必须一路传到界面上。埋在 Core 里没人看得见，
        // 等于没检查。
        var value = state([issue("a", occurrences: 1, days: [1])])
        value.issues[0].sourceSessionIds.append("sync-1754123456")
        let model = viewModel(value)
        XCTAssertFalse(model.dataWarnings.isEmpty)
        XCTAssertTrue(model.dataWarnings.joined().contains("下一步"))
    }
}
```

在 `Tests/IELTSCoachUITests/NavigationTests.swift` 里追加/修改（见下方 Step 3 的说明）：

```swift
    func testIssueArchivePageIsUnlocked() {
        XCTAssertTrue(SidebarItem.issues.isImplemented, "问题档案页已实现，必须在侧边栏可点")
    }

    func testUnbuiltPagesStayLocked() {
        // 多标一页会让用户点进一个还没做的空页面。
        XCTAssertFalse(SidebarItem.upgrade.isImplemented)
        XCTAssertFalse(SidebarItem.feedback.isImplemented)
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter IssueArchiveViewModelTests`
Expected: 编译失败 —— `IssueArchiveViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Issues/IssueArchiveViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public enum IssueFilter: String, CaseIterable, Identifiable, Sendable {
    case all, recurring, new, improving

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .recurring: return "反复出现"
        case .new: return "新问题"
        case .improving: return "正在变少"
        }
    }
}

public struct IssueArchiveRow: Equatable, Identifiable, Sendable {
    public let id: String
    /// 学员的原话。英文原样保留，不翻译。
    public let learnerSaid: String
    public let correction: String
    public let whyItMatters: String
    public let occurrences: Int
    /// 出现在几场不同的练习里。
    public let sessionCount: Int
    public let isNew: Bool
    public let trend: IssueTrend
    public let detail: String
    public let lastSeenText: String

    public init(id: String, learnerSaid: String, correction: String, whyItMatters: String,
                occurrences: Int, sessionCount: Int, isNew: Bool, trend: IssueTrend,
                detail: String, lastSeenText: String) {
        self.id = id; self.learnerSaid = learnerSaid; self.correction = correction
        self.whyItMatters = whyItMatters; self.occurrences = occurrences
        self.sessionCount = sessionCount; self.isNew = isNew; self.trend = trend
        self.detail = detail; self.lastSeenText = lastSeenText
    }
}

public struct IssueArchiveViewModel: Sendable {
    public let rows: [IssueArchiveRow]
    /// 时间轴发现的数据问题。**非空时界面必须显示**——埋在 Core 里没人看得见，
    /// 等于没检查。
    public let dataWarnings: [String]

    public init(state: CoachState,
                calendar: Calendar = .current,
                windowSize: Int = IssueTrendAnalyzer.defaultWindowSize) {
        // ⚠️ 不能用 Dictionary(uniqueKeysWithValues:)：state.json 被外部工具改坏、
        // 或上游写入过重复 id 时，它会 fatalError 闪退整个 App 而不是报错。
        // 本项目在 QuestionBankImporter.merge 里已经为同一个坑写过注释。
        var byID: [String: IssueTrendResult] = [:]
        for result in IssueTrendAnalyzer.analyze(state: state, windowSize: windowSize) {
            byID[result.issueID] = result
        }

        let sorted = state.issues.sorted { left, right in
            if left.occurrences != right.occurrences { return left.occurrences > right.occurrences }
            let leftSeen = CoachTime.parse(left.lastSeenAt) ?? .distantPast
            let rightSeen = CoachTime.parse(right.lastSeenAt) ?? .distantPast
            if leftSeen != rightSeen { return leftSeen > rightSeen }
            return left.id < right.id      // 第三级：让排序完全确定
        }

        rows = sorted.map { issue in
            let trend = byID[issue.id]
            let lastSeen = CoachTime.parse(issue.lastSeenAt)
                .map { "最近一次：" + CoachTime.dayString($0, calendar: calendar) }
            return IssueArchiveRow(
                id: issue.id,
                learnerSaid: issue.learnerSaid,
                correction: issue.correction,
                whyItMatters: issue.whyItMatters,
                occurrences: issue.occurrences,
                sessionCount: Set(issue.sourceSessionIds).count,
                isNew: trend?.isNew ?? false,
                trend: trend?.trend ?? .notEnoughData,
                detail: trend?.detail ?? IssueTrend.notEnoughData.explanation,
                // 读不出时间就说读不出，不要拿一个猜的日期糊弄过去
                lastSeenText: lastSeen ?? "最近一次：时间不详")
        }

        dataWarnings = SessionTimeline.build(state: state).warnings
    }

    public func rows(filter: IssueFilter) -> [IssueArchiveRow] {
        switch filter {
        case .all: return rows
        case .recurring: return rows.filter { $0.occurrences >= 2 }
        case .new: return rows.filter(\.isNew)
        case .improving: return rows.filter { $0.trend == .gone || $0.trend == .decreasing }
        }
    }

    public var counts: (total: Int, new: Int, improving: Int) {
        (rows.count, rows(filter: .new).count, rows(filter: .improving).count)
    }
}
```

`Sources/IELTSCoachUI/Navigation.swift`：把 `isImplemented` 里的 `.issues` 归入已实现：

```swift
    public var isImplemented: Bool {
        switch self {
        case .today, .questionBank, .reviewReports, .issues: return true
        default: return false
        }
    }
```

**注意：** Phase 4–6 可能已经往这个 `case` 列表里加过别的项（如 `.history`、`.retraining`）。**保留它们，只补 `.issues`**，不要把整行覆盖成只剩这四项。

`Tests/IELTSCoachUITests/NavigationTests.swift`：Phase 3 里有一条 `testPhase3ImplementsExactlyThreePages`，断言已实现集合**精确等于** `[.today, .questionBank, .reviewReports]`。

- **首选做法**：找到那条测试，把 `.issues` 加进它的期望集合（Task 7 再加 `.vocabulary`）。**保持它是精确相等断言**——精确相等正是它的价值：多标一页会让用户点进空页面，少标一页会让做好的页面点不进去，两种错都要当场红。
- **仅当**该测试已被后续阶段改名或删除、你无法确定完整的期望集合时，才追加 Step 1 里给出的那两条替代测试。

`Sources/IELTSCoachUI/RootView.swift`：在 `detail` 的 `switch selection` 里加一支：

```swift
            case .issues: IssueArchiveView(app: app)
```

同时把 `PlaceholderView.comingSoon` 里 `.issues` 那一行删掉（它已经不是占位页了，留着是死代码）。

`Sources/IELTSCoachUI/Issues/IssueArchiveView.swift`：**只给验收要求，布局自定。**

必须做到：

1. 顶部用 `SectionHeader(number: "01", label: "ISSUE ARCHIVE", title: "你的问题档案")`
2. 标题下方一行汇总：`共 N 个问题 · 其中 M 个是新问题 · K 个正在变少`。**这三个数字必须 `.monospacedDigit()`**
3. 一个筛选控件（`Picker` + `.segmented` 或同等物），四项来自 `IssueFilter.allCases`，用 `filter.title` 显示
4. `dataWarnings` 非空时，在列表**上方**用 `CoachCard` 逐条显示。用 `Palette.warning` 做左侧标记，文字仍用 `Palette.textPrimary`（不要用警告色写正文，对比度过不了）
5. 每行是一张 `CoachCard`，至少包含：
   - `learnerSaid`（原话，英文保留，`.body`）
   - `correction`（改法，`.body`，用 `Palette.accent` 或加粗与原话区分）
   - `whyItMatters`（为什么要改，`.callout` + `Palette.textSecondary`）
   - 出现次数：`Text("\(row.occurrences)").monospacedDigit()` + 「次」
   - `row.sessionCount`：「出现在 N 场练习里」，同样 `.monospacedDigit()`
   - 趋势标签 `row.trend.badge`，做成 pill（`Radius.pill`）
   - `row.detail`（带具体次数的一句话），`.monospacedDigit()`
   - `row.lastSeenText`
6. `row.isNew == true` 时显示「新问题」标记。**必须是 SF Symbol + 文字**（例如 `sparkles` + 「新问题」），不能只靠颜色——只靠颜色区分对色觉障碍用户等于没有
7. 趋势的语义色：`.gone` / `.decreasing` → `Palette.success`；`.increasing` → `Palette.danger`；`.steady` → `Palette.warning`；`.fresh` / `.notEnoughData` → `Palette.textSecondary`。**颜色只是辅助，文字标签必须始终在**
8. 点开一行（或行内一个「为什么」按钮）时展开 `row.trend.explanation`
9. 空状态用 `EmptyStateView`：
   - 说明现状：「问题档案还是空的」
   - 说明下一步：「练一场并让 ChatGPT 生成复盘，反复出现的毛病会自动记到这里。」
   - 按钮：「去今日训练」，点了切到 `.today`
10. 筛选后为空（比如选了「新问题」但一个都没有）**也要有空状态**，文案不同：「当前筛选下没有内容。下一步：换成「全部」看看。」
11. **整页不得出现任何分数、评级、水平判断**。这一页只回答「这个毛病出现了几次、最近有没有变少」
12. 视图里不得出现字面颜色、字号、圆角

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter IssueArchiveViewModelTests`
Expected: PASS（12 个测试）

Run: `swift test --filter NavigationTests`
Expected: PASS

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处）**

**突变 A：** 把排序的第一级改成升序

```swift
            if left.occurrences != right.occurrences { return left.occurrences < right.occurrences }
```

重跑：`testRowsAreSortedByOccurrencesDescending` 必须变红。

**突变 B：** 把 `dataWarnings` 改成常量空数组 `dataWarnings = []`。重跑：`testDataWarningsAreSurfacedFromTheTimeline` 必须变红。

**这条守的是「检查了但没告诉用户」**——本项目已经为同一个毛病写过 `ArchiveOutcome.skipped`：查出问题却不显示，等于没查。

两次都改回，确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Issues/ Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/RootView.swift Tests/IELTSCoachUITests/IssueArchiveViewModelTests.swift Tests/IELTSCoachUITests/NavigationTests.swift
git commit -m "feat(ui): 问题档案页（按出现次数排序、新问题标记、趋势）"
```

---

## Task 7: 我的词汇页（含导出）

**Files:**
- Create: `Sources/IELTSCoachUI/Vocabulary/VocabularyViewModel.swift`
- Create: `Sources/IELTSCoachUI/Vocabulary/ExportTextDocument.swift`
- Create: `Sources/IELTSCoachUI/Vocabulary/VocabularyView.swift`
- Modify: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Modify: `Tests/IELTSCoachUITests/NavigationTests.swift`
- Create: `Tests/IELTSCoachUITests/VocabularyViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState.vocabulary`、`VocabularyRecord`、`VocabularyPriority`、`VocabularyExporter.export(...)`、`ExportDocument`、`VocabularyExportFormat`、Phase 3 组件与令牌
- Produces:
  - `enum VocabularyFilter: String, CaseIterable, Identifiable, Sendable { case all, high, normal, low }`，含 `title`、`priority: VocabularyPriority?`
  - `struct VocabularyRow: Equatable, Identifiable, Sendable`，字段：`id`、`basicWord`、`betterExpression`、`collocation`、`priority: VocabularyPriority`、`sessionCount`
  - `struct VocabularyViewModel: Sendable`
    - `init(state: CoachState)`
    - `let rows: [VocabularyRow]`
    - `func rows(filter: VocabularyFilter) -> [VocabularyRow]`
    - `var counts: (total: Int, high: Int)`
    - `func exportDocument(format:filter:exportedAt:calendar:) -> ExportDocument`
  - `struct ExportTextDocument: FileDocument`
  - `VocabularyView`
  - `SidebarItem.isImplemented` 对 `.vocabulary` 返回 `true`

**排序规则：** 优先级（`sortRank` 升序，`high` 在前）→ 出现在几场练习里（倒序，反复被推荐的词更该先记）→ `basicWord` 升序 → `id` 升序。最后两级保证排序完全确定。

**导出必须跟随当前筛选。** 用户筛到「优先记」再点导出，却拿到全部词汇，是典型的「界面骗人」。所以 `exportDocument` 收一个 `filter` 参数，并且**按界面上看到的顺序**导出。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/VocabularyViewModelTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class VocabularyViewModelTests: XCTestCase {

    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let exportedAt = CoachTime.parse("2026-08-06T01:00:00Z")!

    private func record(_ id: String, basic: String, priority: String,
                        sessions: [String] = ["s1"]) -> VocabularyRecord {
        VocabularyRecord(id: id, basicWord: basic, betterExpression: "better-\(basic)",
                         collocation: "colloc-\(basic)", priority: priority,
                         sourceSessionIds: sessions)
    }

    private func state(_ records: [VocabularyRecord]) -> CoachState {
        var value = CoachState.empty()
        value.vocabulary = records
        return value
    }

    // MARK: - 排序

    func testRowsAreSortedByPriorityFirst() {
        // 「按优先级」是这一页的产品要求。
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "low"),
            record("v2", basic: "bbb", priority: "normal"),
            record("v3", basic: "ccc", priority: "high")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["v3", "v2", "v1"])
    }

    func testWithinTheSamePriorityMoreSessionsComeFirst() {
        // 反复被推荐的词更该先记。
        let model = VocabularyViewModel(state: state([
            record("once", basic: "aaa", priority: "high", sessions: ["s1"]),
            record("thrice", basic: "zzz", priority: "high", sessions: ["s1", "s2", "s3"])
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["thrice", "once"])
    }

    func testTiesAreBrokenDeterministically() {
        let model = VocabularyViewModel(state: state([
            record("v2", basic: "zebra", priority: "high"),
            record("v1", basic: "apple", priority: "high")
        ]))
        XCTAssertEqual(model.rows.map(\.id), ["v1", "v2"], "同优先级同场次时按词升序，顺序必须固定")
    }

    func testUnknownPriorityLandsInNormalWithoutCrashing() {
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "紧急")
        ]))
        XCTAssertEqual(model.rows[0].priority, .normal)
    }

    func testSessionCountDeduplicates() {
        let model = VocabularyViewModel(state: state([
            record("v1", basic: "aaa", priority: "high", sessions: ["s1", "s1", "s2"])
        ]))
        XCTAssertEqual(model.rows[0].sessionCount, 2)
    }

    // MARK: - 筛选与计数

    func testFiltersReturnTheRightSubsets() {
        let model = VocabularyViewModel(state: state([
            record("h", basic: "aaa", priority: "high"),
            record("n", basic: "bbb", priority: "normal"),
            record("l", basic: "ccc", priority: "low")
        ]))
        XCTAssertEqual(model.rows(filter: .all).map(\.id), ["h", "n", "l"])
        XCTAssertEqual(model.rows(filter: .high).map(\.id), ["h"])
        XCTAssertEqual(model.rows(filter: .normal).map(\.id), ["n"])
        XCTAssertEqual(model.rows(filter: .low).map(\.id), ["l"])
    }

    func testCounts() {
        let model = VocabularyViewModel(state: state([
            record("h1", basic: "aaa", priority: "high"),
            record("h2", basic: "bbb", priority: "high"),
            record("n1", basic: "ccc", priority: "normal")
        ]))
        XCTAssertEqual(model.counts.total, 3)
        XCTAssertEqual(model.counts.high, 2)
    }

    func testEveryFilterHasAChineseTitle() {
        for filter in VocabularyFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty, "\(filter) 缺少中文标题")
        }
    }

    // MARK: - 导出

    func testExportOnlyIncludesTheCurrentFilter() {
        // 用户筛到「优先记」再点导出，却拿到全部词汇，是典型的界面骗人。
        let model = VocabularyViewModel(state: state([
            record("h", basic: "aaa", priority: "high"),
            record("n", basic: "bbb", priority: "normal")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .high,
                                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 1)
        XCTAssertTrue(document.text.contains("aaa"))
        XCTAssertFalse(document.text.contains("bbb"))
    }

    func testExportFollowsTheDisplayedOrder() {
        let model = VocabularyViewModel(state: state([
            record("l", basic: "ccc", priority: "low"),
            record("h", basic: "aaa", priority: "high")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .all,
                                            exportedAt: exportedAt, calendar: utc)
        let words = document.text.split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("#") }
            .map { $0.components(separatedBy: "\t")[0] }
        XCTAssertEqual(words, ["aaa", "ccc"], "导出顺序必须与界面上看到的一致")
    }

    func testExportingAnEmptyVocabularyExplainsItselfInsteadOfFailingSilently() {
        let document = VocabularyViewModel(state: CoachState.empty())
            .exportDocument(format: .ankiTSV, filter: .all,
                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertFalse(document.skipped.isEmpty)
        XCTAssertTrue(document.skipped.joined().contains("下一步"))
    }

    func testExportingAFilterWithNoMatchesSaysItIsTheFilterNotAnEmptyBook() {
        // 词汇本明明不空，却告诉用户「词汇本还是空的」，会让他去找一个不存在的问题。
        let model = VocabularyViewModel(state: state([
            record("n", basic: "bbb", priority: "normal")
        ]))
        let document = model.exportDocument(format: .ankiTSV, filter: .high,
                                            exportedAt: exportedAt, calendar: utc)
        XCTAssertEqual(document.exportedCount, 0)
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped[0].contains(VocabularyFilter.high.title),
                      "要指出是哪个筛选下没有内容：\(document.skipped[0])")
        XCTAssertTrue(document.skipped[0].contains("下一步"))
        XCTAssertFalse(document.skipped[0].contains("词汇本还是空的"))
    }
}
```

在 `Tests/IELTSCoachUITests/NavigationTests.swift` 里补上（做法同 Task 6：优先把 `.vocabulary` 加进那条精确相等断言）：

```swift
    func testVocabularyPageIsUnlocked() {
        XCTAssertTrue(SidebarItem.vocabulary.isImplemented, "我的词汇页已实现，必须在侧边栏可点")
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter VocabularyViewModelTests`
Expected: 编译失败 —— `VocabularyViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Vocabulary/VocabularyViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public enum VocabularyFilter: String, CaseIterable, Identifiable, Sendable {
    case all, high, normal, low

    public var id: String { rawValue }

    public var priority: VocabularyPriority? {
        switch self {
        case .all: return nil
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        }
    }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .high, .normal, .low: return priority?.title ?? "全部"
        }
    }
}

public struct VocabularyRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let basicWord: String
    public let betterExpression: String
    public let collocation: String
    public let priority: VocabularyPriority
    /// 这个词在几场不同的练习里被推荐过。
    public let sessionCount: Int

    public init(id: String, basicWord: String, betterExpression: String, collocation: String,
                priority: VocabularyPriority, sessionCount: Int) {
        self.id = id; self.basicWord = basicWord; self.betterExpression = betterExpression
        self.collocation = collocation; self.priority = priority; self.sessionCount = sessionCount
    }
}

public struct VocabularyViewModel: Sendable {
    public let rows: [VocabularyRow]
    /// 导出要用原始记录（`VocabularyExporter` 吃的是 VocabularyRecord）。
    private let recordsByID: [String: VocabularyRecord]

    public init(state: CoachState) {
        // ⚠️ 不用 Dictionary(uniqueKeysWithValues:)：重复 id 会 fatalError 闪退整个 App。
        var index: [String: VocabularyRecord] = [:]
        for record in state.vocabulary { index[record.id] = record }
        recordsByID = index

        rows = state.vocabulary
            .map { record in
                VocabularyRow(id: record.id,
                              basicWord: record.basicWord,
                              betterExpression: record.betterExpression,
                              collocation: record.collocation,
                              priority: VocabularyPriority.normalize(record.priority),
                              sessionCount: Set(record.sourceSessionIds).count)
            }
            .sorted { left, right in
                if left.priority.sortRank != right.priority.sortRank {
                    return left.priority.sortRank < right.priority.sortRank
                }
                // 反复被推荐的词更该先记
                if left.sessionCount != right.sessionCount {
                    return left.sessionCount > right.sessionCount
                }
                if left.basicWord != right.basicWord { return left.basicWord < right.basicWord }
                return left.id < right.id      // 让排序完全确定
            }
    }

    public func rows(filter: VocabularyFilter) -> [VocabularyRow] {
        guard let priority = filter.priority else { return rows }
        return rows.filter { $0.priority == priority }
    }

    public var counts: (total: Int, high: Int) {
        (rows.count, rows.filter { $0.priority == .high }.count)
    }

    /// 导出**当前筛选**下的词汇，顺序与界面显示一致。
    ///
    /// 用户筛到「优先记」再点导出却拿到全部词汇，是典型的界面骗人。
    public func exportDocument(format: VocabularyExportFormat,
                               filter: VocabularyFilter,
                               exportedAt: Date = Date(),
                               calendar: Calendar = .current) -> ExportDocument {
        let selected = rows(filter: filter).compactMap { recordsByID[$0.id] }
        let document = VocabularyExporter.export(selected, format: format,
                                                 exportedAt: exportedAt, calendar: calendar)
        guard selected.isEmpty, !rows.isEmpty else { return document }

        // 词汇本不空、只是当前筛选下一条都没有。沿用 Exporter 那句
        // 「词汇本还是空的」会把用户支去找一个不存在的问题。
        return ExportDocument(
            text: document.text,
            suggestedFileName: document.suggestedFileName,
            exportedCount: 0,
            skipped: ["当前筛选（\(filter.title)）下一条词都没有，导出的文件里没有任何卡片。"
                      + "下一步：把筛选换成「全部」再导出一次。"])
    }
}
```

`Sources/IELTSCoachUI/Vocabulary/ExportTextDocument.swift`：

```swift
import SwiftUI
import UniformTypeIdentifiers

/// 导出用的纯文本文档。`.txt` 与 `.json` 共用它，靠 contentType 区分。
///
/// 若 Swift 6 的严格并发检查要求它 Sendable，直接加 `: FileDocument, Sendable`——
/// 它只含 `String` 与 `UTType`，两者都是 Sendable。
struct ExportTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    static var writableContentTypes: [UTType] { [.plainText, .json] }

    var text: String
    var contentType: UTType

    init(text: String, contentType: UTType) {
        self.text = text
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
```

`Sources/IELTSCoachUI/Navigation.swift`：把 `.vocabulary` 也归入已实现（**保留 Task 6 与其他阶段已加的项**）：

```swift
        case .today, .questionBank, .reviewReports, .issues, .vocabulary: return true
```

`Sources/IELTSCoachUI/RootView.swift`：`switch selection` 里加一支 `case .vocabulary: VocabularyView(app: app)`，并把 `PlaceholderView.comingSoon` 里 `.vocabulary` 那一行删掉。

`Sources/IELTSCoachUI/Vocabulary/VocabularyView.swift`：**只给验收要求，布局自定。**

必须做到：

1. 顶部 `SectionHeader(number: "01", label: "VOCABULARY", title: "我的词汇")`
2. 汇总行：`共 N 个词 · 其中 M 个要优先记`。两个数字 `.monospacedDigit()`
3. 筛选控件，四项来自 `VocabularyFilter.allCases`
4. 每行一张 `CoachCard`，至少包含：
   - `basicWord`（原来的说法）
   - `betterExpression`（更好的说法），与前者之间要有明确的方向感（箭头图标用 SF Symbol `arrow.right`，**不要用 emoji**）
   - `collocation`（搭配），`.callout` + `Palette.textSecondary`
   - 优先级 pill，显示 `row.priority.title`
   - 「出现在 N 场练习里」，`.monospacedDigit()`
5. **导出入口**（本任务的核心交付）：
   - 一个「导出…」菜单，两项来自 `VocabularyExportFormat.allCases`，用 `format.title` 显示
   - 选中格式后用 `.fileExporter` 弹保存面板，`document` 用 `ExportTextDocument(text:contentType:)`，
     `contentType` 按格式取 `.plainText` / `.json`，`defaultFilename` 用 `document.suggestedFileName`
   - **导出前后都要显示 `format.howToUse`**——导出一个文件却不说怎么用，等于没做这个功能
   - 导出完成后，若 `document.skipped` 非空，**必须把每一条都显示出来**（用 `CoachCard` 列在页面上，或用 `.alert` 弹出）。不能只显示「导出成功」
   - `.fileExporter` 的 `onCompletion` 收到 `.failure` 时，显示中文错误 + 下一步：「文件没能存下来：<原因>。下一步：换一个你有写入权限的位置再试一次。」
   - 另给一个「复制到剪贴板」按钮（`NSPasteboard.general.clearContents()` + `setString(document.text, forType: .string)`），用户已有的 AnkiConnect 脚本可以直接用剪贴板内容。点了要有明确反馈（按钮文字短暂变成「已复制」或显示一行提示），**不能点了没反应**
6. 空状态用 `EmptyStateView`：
   - 「词汇本还是空的」
   - 「练一场并让 ChatGPT 生成复盘，推荐词汇会自动记到这里。」
   - 按钮「去今日训练」
   - **词汇本为空时，导出按钮要禁用**（`.disabled(true)`），并在旁边说明为什么禁用
7. 筛选后为空也要有空状态，文案：「当前筛选下没有词。下一步：换成「全部」看看。」
8. 视图里不得出现字面颜色、字号、圆角

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter VocabularyViewModelTests`
Expected: PASS（12 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处）**

**突变 A：** 把排序里的优先级那一级删掉（只保留 sessionCount / basicWord / id 三级）。重跑：`testRowsAreSortedByPriorityFirst` 必须变红。

**突变 B：** 把 `exportDocument` 里的 `rows(filter: filter)` 改成 `rows`。重跑：`testExportOnlyIncludesTheCurrentFilter` 必须变红。

**这条守的是「界面显示的和实际导出的不是一回事」**——用户筛完再导出，拿到的却是全部，而他要到 Anki 里才会发现。

**突变 C：** 把 `exportDocument` 里那个 `guard selected.isEmpty, !rows.isEmpty else { return document }` 之后的整段删掉，直接 `return document`。重跑：`testExportingAFilterWithNoMatchesSaysItIsTheFilterNotAnEmptyBook` 必须变红（会回落到「词汇本还是空的」那句不实的说明）。

三次都改回，确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Vocabulary/ Sources/IELTSCoachUI/Navigation.swift Sources/IELTSCoachUI/RootView.swift Tests/IELTSCoachUITests/VocabularyViewModelTests.swift Tests/IELTSCoachUITests/NavigationTests.swift
git commit -m "feat(ui): 我的词汇页与 Anki 导出"
```

---

## Task 8: 首页统计四格 +「你的问题正在怎么变化」

**Files:**
- Create: `Sources/IELTSCoachUI/Today/StatTile.swift`
- Modify: `Sources/IELTSCoachUI/Today/TodayViewModel.swift`
- Modify: `Sources/IELTSCoachUI/Today/TodayView.swift`
- Create: `Tests/IELTSCoachUITests/HomeStatsTests.swift`

**Interfaces:**
- Consumes: `TrainingStats.compute(state:now:calendar:)`、`TrainingStats.maxCountedMinutesPerSession`、`IssueTrendAnalyzer.minimumSessionsForTrend`、`IssueArchiveViewModel`、`IssueArchiveRow`、Phase 3 的 `TodayViewModel`（`state`、`todayQuestions`、`availableRoutes`、`recentSessions`）
- Produces:
  - `struct StatTile: Equatable, Identifiable, Sendable { let id: String; let caption: String; let value: String; let unit: String; let footnote: String }`
  - `TodayViewModel.init(state:today:calendar:)`（**新增第三个参数，有默认值，既有调用点不用改**）
  - `TodayViewModel.stats: TrainingStats`
  - `TodayViewModel.statTiles: [StatTile]`
  - `TodayViewModel.issueChanges: [IssueArchiveRow]`
  - `TodayViewModel.weekProgress: (done: Int, goal: Int)`（**改为从 `settings.weeklyGoal` 取目标，不再硬编码 5**）

### 四格是什么（顺序固定，id 固定）

| id | caption | value | unit |
|---|---|---|---|
| `week` | 本周训练 | `3/5` | 次 |
| `total` | 累计训练 | `18` | 次 |
| `minutes` | 本周开口时长 | `42` | 分钟 |
| `improving` | 出现变少的毛病 | `2` | 个 |

**第四格不是分数，不是评级，也不是「初步改善度」这种听起来像评分的东西。** 它是一个用户能自己数出来核对的计数：问题档案里趋势为「最近没再出现」或「出现变少了」的毛病有几个。

### 这一格的文案守则（有自动化测试守着）

`DEFINITION-OF-DONE.md` 第 4 节第一条：**不预测雅思分数。** 给「你大概 6.5 分」这种数字既不准也有害——会让人盯着数字而不是盯着问题。

Step 1 里有一条 `testNoScorePredictionInAnyUserFacingText`，它会把首页四格的全部文案与所有趋势文案扫一遍，命中禁用词就红。**不要为了绕过它去改测试里的词表**——那正是这条测试存在的意义。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/HomeStatsTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class HomeStatsTests: XCTestCase {

    /// 固定「现在」= 2026-08-05T12:00:00Z（周三），上海时区下本周是 08-03 ~ 08-09。
    private let now = CoachTime.parse("2026-08-05T12:00:00Z")!

    private var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func session(_ id: String, started: String, ended: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: started,
                        endedAt: ended, goal: "", transcript: [],
                        reportPath: "", recordingPath: "")
    }

    private func julySession(_ day: Int) -> PracticeSession {
        let stamp = String(format: "2026-07-%02d", day)
        return session("\(stamp)-001", started: "\(stamp)T10:00:00Z", ended: "\(stamp)T10:30:00Z")
    }

    private func issue(_ id: String, occurrences: Int, days: [Int]) -> IssueRecord {
        IssueRecord(id: id, learnerSaid: "said-\(id)", correction: "fix", whyItMatters: "why",
                    occurrences: occurrences,
                    sourceSessionIds: days.map { String(format: "2026-07-%02d-001", $0) },
                    lastSeenAt: String(format: "2026-07-%02dT10:00:00Z", days.max() ?? 1))
    }

    private func model(_ value: CoachState) -> TodayViewModel {
        TodayViewModel(state: value, today: now, calendar: calendar)
    }

    private func thisWeekState(weeklyGoal: Int? = nil) -> CoachState {
        var value = CoachState.empty()
        value.sessions = [
            session("a", started: "2026-08-05T10:00:00Z", ended: "2026-08-05T10:30:00Z"),
            session("b", started: "2026-08-04T02:00:00Z", ended: "2026-08-04T02:12:00Z"),
            session("c", started: "2026-07-20T10:00:00Z", ended: "2026-07-20T10:20:00Z")
        ]
        if let weeklyGoal { value.settings.weeklyGoal = weeklyGoal }
        return value
    }

    // MARK: - 每周目标可配置

    func testWeekProgressGoalComesFromSettingsNotAHardcodedFive() {
        // ROADMAP 第 5 节：每周训练目标由用户配置，默认 5。
        XCTAssertEqual(model(thisWeekState()).weekProgress.goal, 5)
        XCTAssertEqual(model(thisWeekState(weeklyGoal: 3)).weekProgress.goal, 3)
        XCTAssertEqual(model(thisWeekState()).weekProgress.done, 2)
    }

    // MARK: - 四格

    func testFourTilesInAFixedOrderWithStableIDs() {
        let tiles = model(thisWeekState()).statTiles
        XCTAssertEqual(tiles.map(\.id), ["week", "total", "minutes", "improving"])
    }

    func testTileValuesRenderTheRealNumbers() {
        let tiles = model(thisWeekState(weeklyGoal: 4)).statTiles
        func tile(_ id: String) -> StatTile? { tiles.first { $0.id == id } }
        XCTAssertEqual(tile("week")?.value, "2/4")
        XCTAssertEqual(tile("week")?.unit, "次")
        XCTAssertEqual(tile("total")?.value, "3")
        XCTAssertEqual(tile("minutes")?.value, "42")
        XCTAssertEqual(tile("minutes")?.unit, "分钟")
    }

    func testEveryTileHasNonEmptyCaptionAndFootnote() {
        // 空脚注等于一块没人看得懂的数字。空白会让用户以为程序坏了。
        for value in [thisWeekState(), CoachState.empty()] {
            for tile in model(value).statTiles {
                XCTAssertFalse(tile.caption.isEmpty, "\(tile.id) 缺 caption")
                XCTAssertFalse(tile.value.isEmpty, "\(tile.id) 缺 value")
                XCTAssertFalse(tile.footnote.isEmpty, "\(tile.id) 缺脚注")
            }
        }
    }

    func testWeekFootnoteTellsYouHowManyMoreOrThatYouAreDone() {
        let notDone = model(thisWeekState(weeklyGoal: 5)).statTiles.first { $0.id == "week" }
        XCTAssertTrue(notDone?.footnote.contains("还差 3 次") == true, notDone?.footnote ?? "")
        XCTAssertTrue(notDone?.footnote.contains("下一步") == true)

        let done = model(thisWeekState(weeklyGoal: 1)).statTiles.first { $0.id == "week" }
        XCTAssertTrue(done?.footnote.contains("已经完成") == true, done?.footnote ?? "")
    }

    func testMinutesFootnoteExplainsMissingEndTimes() {
        var value = CoachState.empty()
        value.sessions = [session("a", started: "2026-08-05T10:00:00Z", ended: "")]
        let tile = model(value).statTiles.first { $0.id == "minutes" }
        XCTAssertTrue(tile?.footnote.contains("没有结束时间") == true, tile?.footnote ?? "")
        XCTAssertTrue(tile?.footnote.contains("下一步") == true)
    }

    func testMinutesFootnoteExplainsCappedSessions() {
        var value = CoachState.empty()
        value.sessions = [session("a", started: "2026-08-05T06:00:00Z",
                                  ended: "2026-08-05T10:00:00Z")]
        let tile = model(value).statTiles.first { $0.id == "minutes" }
        XCTAssertTrue(tile?.footnote.contains("小时") == true, tile?.footnote ?? "")
        XCTAssertTrue(tile?.footnote.contains("下一步") == true)
    }

    func testImprovingFootnoteSaysHowManyMoreSessionsAreNeeded() {
        // 练习太少时说「0 个毛病在变少」会被误读成「一点没进步」。
        // 必须说清是「还看不出来」，并给出还差几场。
        var value = CoachState.empty()
        value.sessions = (1...3).map(julySession)
        value.issues = [issue("a", occurrences: 1, days: [1])]
        let tile = model(value).statTiles.first { $0.id == "improving" }
        let needed = IssueTrendAnalyzer.minimumSessionsForTrend - 3
        XCTAssertTrue(tile?.footnote.contains("再练 \(needed) 次") == true, tile?.footnote ?? "")
    }

    func testImprovingTileCountsGoneAndDecreasing() {
        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = [issue("gone", occurrences: 2, days: [1, 2]),
                        issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
                        issue("up", occurrences: 4, days: [1, 8, 9, 10])]
        let tile = model(value).statTiles.first { $0.id == "improving" }
        XCTAssertEqual(tile?.value, "2")
        XCTAssertEqual(tile?.unit, "个")
    }

    // MARK: - 「你的问题正在怎么变化」

    func testIssueChangesAreSortedByOccurrencesAndCappedAtFive() {
        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = (1...7).map { issue("i\($0)", occurrences: $0, days: [$0 % 10 + 1]) }
        let changes = model(value).issueChanges
        XCTAssertEqual(changes.count, 5, "首页只放最要紧的五条，剩下的去问题档案页看")
        XCTAssertEqual(changes.map(\.id), ["i7", "i6", "i5", "i4", "i3"])
    }

    func testIssueChangesAreEmptyWhenTheArchiveIsEmpty() {
        XCTAssertTrue(model(CoachState.empty()).issueChanges.isEmpty)
    }

    // MARK: - 绝不预测分数

    func testNoScorePredictionInAnyUserFacingText() {
        // DEFINITION-OF-DONE 第 4 节第一条：不预测雅思分数。
        // 给「你大概 6.5 分」这种数字既不准也有害——
        // 会让人盯着数字而不是盯着问题。
        //
        // 不要为了让这条测试变绿去改下面的词表。它存在的意义就是拦住那件事。
        let banned = ["分数", "评分", "打分", "得分", "预测", "band", "Band", "BAND",
                      "几分", "水平分", "6.5", "7.0", "score", "Score"]

        var value = CoachState.empty()
        value.sessions = (1...10).map(julySession)
        value.issues = [issue("gone", occurrences: 2, days: [1, 2]),
                        issue("down", occurrences: 5, days: [1, 2, 3, 4, 10]),
                        issue("up", occurrences: 4, days: [1, 8, 9, 10]),
                        issue("fresh", occurrences: 2, days: [9, 10])]

        var texts: [String] = []
        for tile in model(value).statTiles {
            texts += [tile.caption, tile.value, tile.unit, tile.footnote]
        }
        for row in model(value).issueChanges {
            texts += [row.detail, row.trend.badge, row.trend.explanation, row.lastSeenText]
        }
        for trend in IssueTrend.allCases {
            texts += [trend.badge, trend.explanation]
        }
        // 空数据下的文案也要扫——空状态最容易被顺手写上一句「预计能到几分」
        for tile in model(CoachState.empty()).statTiles {
            texts += [tile.caption, tile.footnote]
        }

        for text in texts {
            for word in banned {
                XCTAssertFalse(text.contains(word),
                               "「\(text)」里出现了被禁止的分数用语「\(word)」"
                               + "（DEFINITION-OF-DONE 第 4 节）")
            }
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter HomeStatsTests`
Expected: 编译失败 —— `StatTile` 未定义、`TodayViewModel` 没有 `calendar` 参数与 `statTiles`

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Today/StatTile.swift`：

```swift
import Foundation

/// 首页的一格统计。
///
/// 把四格做成数据而不是散在视图里的字符串，有两个原因：
/// 一是 `value` 集中在一处，视图只要对它统一加 `.monospacedDigit()`，
/// 数值变化时整行就不会横向抖动（DESIGN-SYSTEM 第 6 节最后一条）；
/// 二是文案可测——`HomeStatsTests` 里那条「绝不预测分数」的守卫
/// 就是把这些字符串扫一遍。
public struct StatTile: Equatable, Identifiable, Sendable {
    public let id: String
    /// 这格是什么，例如「本周训练」。
    public let caption: String
    /// 数字本身，例如 "3/5"。**视图必须对它用 .monospacedDigit()**。
    public let value: String
    /// 单位，例如「次」「分钟」「个」。
    public let unit: String
    /// 一句话解释这个数字，并告诉用户下一步做什么。不允许为空。
    public let footnote: String

    public init(id: String, caption: String, value: String, unit: String, footnote: String) {
        self.id = id; self.caption = caption; self.value = value
        self.unit = unit; self.footnote = footnote
    }
}
```

`Sources/IELTSCoachUI/Today/TodayViewModel.swift` 的改动（**其余既有成员一律保留不动**）：

1. `init` 加第三个参数并存下 `calendar` 与 `stats`：

```swift
    public let state: CoachState
    private let today: Date
    private let calendar: Calendar
    /// 在 init 里算一次就好。放成 computed var 的话，四格 + 进度条会重复算四五遍。
    public let stats: TrainingStats

    public init(state: CoachState,
                today: Date = Date(),
                calendar: Calendar = Calendar(identifier: .iso8601)) {
        self.state = state
        self.today = today
        self.calendar = calendar
        self.stats = TrainingStats.compute(state: state, now: today, calendar: calendar)
    }
```

2. `weekProgress` 整个替换为（**Phase 3 里它把目标硬编码成了 5，现在改为读设置**）：

```swift
    /// 目标次数来自 `settings.weeklyGoal`（ROADMAP 第 5 节：用户可配置，默认 5）。
    public var weekProgress: (done: Int, goal: Int) { (stats.weeklyDone, stats.weeklyGoal) }
```

3. 新增 `statTiles`：

```swift
    /// 首页四格。顺序与 id 固定，视图按顺序渲染即可。
    public var statTiles: [StatTile] {
        [weekTile, totalTile, minutesTile, improvingTile]
    }

    private var weekTile: StatTile {
        var footnote: String
        if stats.weeklyDone >= stats.weeklyGoal {
            footnote = "本周目标已经完成。下一步：想继续练就继续，目标只是下限，不是上限。"
        } else {
            footnote = "离本周目标还差 \(stats.weeklyGoal - stats.weeklyDone) 次。"
                + "下一步：回到上面点「开始」，再练一场。"
        }
        if stats.undatedSessionCount > 0 {
            footnote += "另有 \(stats.undatedSessionCount) 场练习读不出时间，没能算进本周。"
                + "下一步：到训练记录页核对这几场。"
        }
        return StatTile(id: "week", caption: "本周训练",
                        value: "\(stats.weeklyDone)/\(stats.weeklyGoal)",
                        unit: "次", footnote: footnote)
    }

    private var totalTile: StatTile {
        let footnote = stats.totalSessions == 0
            ? "还没有任何练习记录。下一步：回到上面点「开始」，练第一场。"
            : "从第一场到现在的全部练习都算在里面。下一步：到训练记录页可以逐场回看。"
        return StatTile(id: "total", caption: "累计训练",
                        value: "\(stats.totalSessions)", unit: "次", footnote: footnote)
    }

    private var minutesTile: StatTile {
        var footnote = "按每场练习的开始与结束时间统计。"
        if stats.sessionsMissingDuration > 0 {
            footnote += "有 \(stats.sessionsMissingDuration) 场没有结束时间，没算进去。"
                + "下一步：练完记得点「我练完了」，时长才会被记上。"
        }
        if stats.cappedSessionCount > 0 {
            let hours = TrainingStats.maxCountedMinutesPerSession / 60
            footnote += "有 \(stats.cappedSessionCount) 场超过 \(hours) 小时，"
                + "已按 \(hours) 小时计入（多半是忘了点结束）。"
                + "下一步：到训练记录页核对这几场。"
        }
        if stats.sessionsMissingDuration == 0 && stats.cappedSessionCount == 0 {
            footnote += "下一步：想让这个数字变大，就多练几场，不用刻意拉长单场时间。"
        }
        return StatTile(id: "minutes", caption: "本周开口时长",
                        value: "\(stats.weeklySpokenMinutes)", unit: "分钟", footnote: footnote)
    }

    /// 第四格。**这里不是分数、不是评级。** 它是「问题档案里趋势为
    /// 『最近没再出现』或『出现变少了』的毛病有几个」——一个用户能自己数出来核对的计数。
    private var improvingTile: StatTile {
        let footnote: String
        if stats.trackedIssueCount == 0 {
            footnote = "问题档案还是空的。"
                + "下一步：练一场并让 ChatGPT 生成复盘，反复出现的毛病会自动记到这里。"
        } else if stats.totalSessions < IssueTrendAnalyzer.minimumSessionsForTrend {
            let needed = IssueTrendAnalyzer.minimumSessionsForTrend - stats.totalSessions
            footnote = "练习场次还不够，暂时看不出哪个毛病在变少。"
                + "下一步：再练 \(needed) 次，这里会自动开始显示。"
        } else {
            footnote = "档案里一共 \(stats.trackedIssueCount) 个问题，这里只数「最近变少了」的那些。"
                + "下一步：到问题档案页看每个毛病的具体变化。"
        }
        return StatTile(id: "improving", caption: "出现变少的毛病",
                        value: "\(stats.improvingIssueCount)", unit: "个", footnote: footnote)
    }
```

4. 新增 `issueChanges`：

```swift
    /// 首页的「你的问题正在怎么变化」列表：按出现次数取最要紧的五条。
    /// 剩下的去问题档案页看——首页塞十几条只会让人不想看。
    public var issueChanges: [IssueArchiveRow] {
        Array(IssueArchiveViewModel(state: state, calendar: calendar).rows.prefix(5))
    }
```

`Sources/IELTSCoachUI/Today/TodayView.swift`：**只给验收要求，布局自定。**

必须做到：

1. 四格统计横排（窗口窄时可折成两行），每格用 `CoachCard`：
   - `tile.value` 用 `.font(.title)` + `.fontWeight(.semibold)` + **`.monospacedDigit()`**（DESIGN-SYSTEM 第 1 节末行）
   - `tile.unit` 紧跟其后，`.callout` + `Palette.textSecondary`
   - `tile.caption` 在上，`.caption` + `Palette.textSecondary`
   - `tile.footnote` 在下，`.callout` + `Palette.textSecondary`。**不允许因为「太长了不好看」就不显示**——脚注正是「说清下一步」的地方
2. 「本周训练」那一格里额外放一个「改目标」按钮，点了打开 Task 9 的设置面板
3. 「你的问题正在怎么变化」区块：
   - `SectionHeader(number: "04", label: "ISSUE TRENDS", title: "你的问题正在怎么变化")`（编号按它在页面里的实际位置取，与既有区块连号）
   - 逐条渲染 `issueChanges`，每条至少显示：`learnerSaid`、`trend.badge`、`detail`、出现次数
   - 所有数字 `.monospacedDigit()`
   - 底部一个「查看全部问题」按钮，切到 `.issues`
   - `issueChanges` 为空时用 `EmptyStateView`：「还没有记录到反复出现的问题」/「练一场并让 ChatGPT 生成复盘，这里就会开始积累。」/ 按钮「开始练习」
4. **整页不得出现任何分数、评级、水平判断**
5. 视图里不得出现字面颜色、字号、圆角

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter HomeStatsTests`
Expected: PASS（12 个测试）

Run: `swift test --filter TodayViewModelTests`
Expected: PASS —— Phase 3 的既有测试一条都不能红。`init` 新增的第三个参数有默认值，`testWeekProgressCountsOnlyThisWeek` 断言的 goal 仍是 5（默认设置就是 5）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（三处）**

**突变 A：** 把 `weekProgress` 改回硬编码

```swift
    public var weekProgress: (done: Int, goal: Int) { (stats.weeklyDone, 5) }
```

重跑：`testWeekProgressGoalComesFromSettingsNotAHardcodedFive` 必须变红。

**突变 B（守「不预测分数」这条红线）：** 把 `improvingTile` 的 caption 改成 `"预测分数"`。重跑：`testNoScorePredictionInAnyUserFacingText` 必须变红，且报错信息要指出命中了哪个词。改回后确认全绿。

**这一步不是走过场。** 这条测试是整个产品立场的自动化守卫：本项目明确不做分数预测，因为盯着数字会让人不再盯着问题。突变验证要证明这条线真的有人守着，而不是写了一条永远绿的空转测试。

**突变 C：** 把 `issueChanges` 里的 `.prefix(5)` 去掉。重跑：`testIssueChangesAreSortedByOccurrencesAndCappedAtFive` 必须变红。

三次都改回，确认全绿，把三次的输出写进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Today/ Tests/IELTSCoachUITests/HomeStatsTests.swift
git commit -m "feat(ui): 首页统计四格与问题变化列表（等宽数字，无分数预测）"
```

---

## Task 9: 每周训练目标可配置

**Files:**
- Create: `Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift`
- Modify: `Sources/IELTSCoachUI/AppState.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Tests/IELTSCoachUITests/WeeklyGoalEditorTests.swift`

**Interfaces:**
- Consumes: `CoachSettings.weeklyGoalRange`、`CoachSettings.normalized(_:)`、`StateStore.mutate`、Phase 3 的 `AppState`（私有 `store`、`reload()`、`state`）
- Produces:
  - `enum WeeklyGoalEditor`
    - `static let range: ClosedRange<Int>`
    - `static func label(for goal: Int) -> String`
    - `static func hint(done: Int, goal: Int) -> String`
  - `AppState.setWeeklyGoal(_ goal: Int) -> Bool`（`@discardableResult`）
  - `AppState.settingsError: String?`（`public private(set)`）
  - `WeeklyGoalSheet`

**入口怎么开：** 不新建 `Settings` Scene，也不动 `IELTSCoachApp/main.swift`。理由是那需要把 `AppState` 从 `RootView` 提到 App 层、改 `RootView` 的 init 签名、再连一个私有的 `showSettingsWindow:` selector 才能从页面里唤起——三处改动，三处都可能踩坑，换来的只是一个菜单项。

改为：`RootView` 的工具栏放一个齿轮按钮弹出 `WeeklyGoalSheet`；首页「本周训练」那一格的「改目标」按钮翻同一个 binding。

> ### ⚠️ ⌘, 已经被 Phase 5 占用了（2026-08-06 跨阶段复审补入）
>
> 初稿在这个齿轮按钮上挂了 `.keyboardShortcut(",", modifiers: .command)`。
> **不要挂。** Phase 5 Task 8 已经在 `Sources/IELTSCoachApp/main.swift` 里建了一个 SwiftUI
> `Settings { RecordingSettingsScene() }` 场景（原话：「macOS 的惯例本来就是 `⌘,` 打开设置窗口，
> SwiftUI 的 `Settings { }` 场景直接支持」），而那个场景**自带**「设置…」菜单项与 ⌘,。
> 两处绑同一个快捷键，SwiftUI 不会报错，只会由其中一个随机胜出——用户按 ⌘,
> 时而弹录音设置、时而弹每周目标。Phase 5 计划里三处中文提示还写着
> 「到「录音设置」（⌘,）把开关关掉再打开一次」，那条指路会时灵时不灵。
>
> **动手前先确认：** `grep -n "Settings {" Sources/IELTSCoachApp/main.swift`
>
> - **有输出**（Phase 5 已交付）→ 齿轮按钮**不挂快捷键**，本任务的其余部分照做；
>   并把本阶段完成标准里「每周训练目标可配置（⌘, 打开）」改成「（首页齿轮按钮打开）」
> - **没有输出** → 可以按初稿挂 ⌘,
>
> **这只是消除快捷键冲突，没有解决「设置散在三个地方」这个更大的问题**
> （录音在 ⌘, 设置窗口、每周目标在首页齿轮、三项练习偏好在 Phase 8 的学习计划页底部）。
> 那是产品决策，已列进复审报告的「需要人定夺」，不在本任务范围内擅自合并。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/WeeklyGoalEditorTests.swift`：

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class WeeklyGoalEditorTests: XCTestCase {

    func testRangeMatchesTheSettingsModel() {
        // 界面上的可选范围必须和落盘时的归一范围一致。
        // 不一致的话，Stepper 让你选 30，存下去却变成 5，用户会以为设置没生效。
        XCTAssertEqual(WeeklyGoalEditor.range, CoachSettings.weeklyGoalRange)
        XCTAssertEqual(WeeklyGoalEditor.range.lowerBound, 1)
        XCTAssertEqual(WeeklyGoalEditor.range.upperBound, 21)
    }

    func testLabelStatesTheGoal() {
        XCTAssertTrue(WeeklyGoalEditor.label(for: 5).contains("5"))
        XCTAssertTrue(WeeklyGoalEditor.label(for: 5).contains("次"))
    }

    func testHintTellsYouHowManyMoreAndWhatToDoNext() {
        let hint = WeeklyGoalEditor.hint(done: 2, goal: 5)
        XCTAssertTrue(hint.contains("2"), hint)
        XCTAssertTrue(hint.contains("3"), "要算出还差几次：\(hint)")
        XCTAssertTrue(hint.contains("下一步"), hint)
    }

    func testHintSaysDoneWhenTheGoalIsAlreadyMet() {
        let hint = WeeklyGoalEditor.hint(done: 6, goal: 5)
        XCTAssertTrue(hint.contains("达到"), hint)
        XCTAssertTrue(hint.contains("下一步"), hint)
        XCTAssertFalse(hint.contains("还差"), "已经达标了还说「还差」是错的：\(hint)")
    }

    func testHintNeverShowsANegativeRemainder() {
        XCTAssertFalse(WeeklyGoalEditor.hint(done: 9, goal: 5).contains("-"))
    }

    func testNoScorePredictionInTheSettingsCopy() {
        // 与首页同一条红线（DEFINITION-OF-DONE 第 4 节）：
        // 「每周练 5 次大概能到几分」这种话在这里最容易被顺手写上。
        let banned = ["分数", "评分", "打分", "得分", "预测", "band", "Band", "几分", "6.5", "7.0"]
        var texts = [WeeklyGoalEditor.label(for: 5),
                     WeeklyGoalEditor.hint(done: 2, goal: 5),
                     WeeklyGoalEditor.hint(done: 6, goal: 5)]
        for goal in WeeklyGoalEditor.range { texts.append(WeeklyGoalEditor.label(for: goal)) }
        for text in texts {
            for word in banned {
                XCTAssertFalse(text.contains(word), "「\(text)」里出现了被禁止的分数用语「\(word)」")
            }
        }
    }
}
```

同时在 `Tests/IELTSCoachCoreTests/WeeklyGoalTests.swift`（Task 1 建的那个文件）里**追加**一条，覆盖 `AppState.setWeeklyGoal` 走的那条写盘路径：

```swift
    func testSettingWeeklyGoalThroughTheStoreClampsAndPersists() throws {
        // 这就是 AppState.setWeeklyGoal 做的事：先归一，再写盘。
        let store = StateStore(directory: directory)
        try store.mutate { $0.settings.weeklyGoal = CoachSettings.normalized(99) }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 5)

        try store.mutate { $0.settings.weeklyGoal = CoachSettings.normalized(7) }
        XCTAssertEqual(try StateStore(directory: directory).load().settings.weeklyGoal, 7)
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter WeeklyGoalEditorTests`
Expected: 编译失败 —— `WeeklyGoalEditor` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Settings/WeeklyGoalSheet.swift`：

```swift
import IELTSCoachCore
import SwiftUI

/// 「每周训练目标」这块设置里的纯文案与取值范围。
/// 拆出来是为了能测——`View` 测不了，这几句话能测。
public enum WeeklyGoalEditor {
    /// 与落盘时的归一范围保持同一个来源。两处写死两个范围的话，
    /// Stepper 让你选 30、存下去却变成 5，用户会以为设置没生效。
    public static let range = CoachSettings.weeklyGoalRange

    public static func label(for goal: Int) -> String { "每周练 \(goal) 次" }

    public static func hint(done: Int, goal: Int) -> String {
        if done >= goal {
            return "本周已经练了 \(done) 次，达到目标了。"
                + "下一步：想继续练就继续，这个目标只是下限，不是上限。"
        }
        return "本周已经练了 \(done) 次，离目标还差 \(goal - done) 次。"
            + "下一步：目标定得能坚持下来，比定得高有用——定不下来的目标只会让人不想打开这个 App。"
    }
}

/// 改每周训练目标的小面板。由 RootView 工具栏的齿轮按钮（⌘,）
/// 与首页「本周训练」格里的「改目标」按钮共用同一个 binding 打开。
///
/// 布局自定（见下方验收要求），但入口签名固定成这样，
/// 好让 RootView 与 TodayView 两处调用点一致。
public struct WeeklyGoalSheet: View {
    let app: AppState
    @Binding var isPresented: Bool
    /// 面板里正在编辑的取值。打开时用 app.state.settings.weeklyGoal 初始化，
    /// 点「保存」才写盘——半路改一半就关掉不该留下痕迹。
    @State private var draft: Int

    public init(app: AppState, isPresented: Binding<Bool>) {
        self.app = app
        self._isPresented = isPresented
        self._draft = State(initialValue: app.state.settings.weeklyGoal)
    }

    public var body: some View { /* 按下面的验收要求实现 */ }
}
```

**`WeeklyGoalSheet` 的验收要求（布局自定）：**

1. 标题「每周训练目标」
2. 一个 `Stepper`，范围 `WeeklyGoalEditor.range`，显示 `WeeklyGoalEditor.label(for:)`。**数字用 `.monospacedDigit()`**——从 9 跳到 10 时那一行不能抖
3. 下方一行 `WeeklyGoalEditor.hint(done:goal:)`，`done` 取 `TodayViewModel(state: app.state).weekProgress.done`
4. 「保存」按钮调 `app.setWeeklyGoal(...)`；返回 `true` 就关闭面板
5. `app.settingsError` 非 nil 时，**面板不关闭**，把错误全文显示出来（`.textSelection(.enabled)`）
6. 「取消」按钮直接关闭，不写盘
7. 面板打开时 Stepper 的初值取 `app.state.settings.weeklyGoal`
8. 走令牌，不写字面颜色、字号、圆角

`Sources/IELTSCoachUI/AppState.swift` 追加（**其余成员不动**）：

```swift
    /// 改设置失败时的中文说明。**非 nil 时界面必须显示，且不许关闭面板**——
    /// 静默失败会让用户以为目标改好了，下次打开发现又变回去，
    /// 而且他永远不知道为什么。
    public private(set) var settingsError: String?

    /// 改每周训练目标。越界的取值按 `CoachSettings.normalized` 归一，不抛错。
    /// - Returns: 是否写盘成功。界面据此决定要不要关闭设置面板。
    @discardableResult
    public func setWeeklyGoal(_ goal: Int) -> Bool {
        let normalized = CoachSettings.normalized(goal)
        do {
            try store.mutate { $0.settings.weeklyGoal = normalized }
            settingsError = nil
            reload()          // 立刻把新目标反映到首页的「本周 N/M」上
            return true
        } catch {
            settingsError = "每周训练目标没能存下来：\(error.localizedDescription)"
                + " 下一步：确认数据目录可写"
                + "（默认在 ~/Library/Application Support/IELTS Speaking Coach/），然后再试一次。"
            return false
        }
    }
```

`Sources/IELTSCoachUI/RootView.swift`：

```swift
    @State private var showingWeeklyGoal = false
```

- 在 `NavigationSplitView` 的 detail 上挂 `.toolbar { ToolbarItem { Button { showingWeeklyGoal = true } label: { Label("设置", systemImage: "gearshape") } .keyboardShortcut(",", modifiers: .command) } }`
- 挂 `.sheet(isPresented: $showingWeeklyGoal) { WeeklyGoalSheet(app: app, isPresented: $showingWeeklyGoal) }`
- 把这个 binding 传给 `TodayView`，供「改目标」按钮使用（`TodayView` 加一个 `@Binding var showingWeeklyGoal: Bool` 参数）

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter WeeklyGoalEditorTests`
Expected: PASS（6 个测试）

Run: `swift test --filter WeeklyGoalTests`
Expected: PASS（9 个测试）

Run: `swift build`
Expected: 编译通过（`View` 没有单元测试，至少要保证编得过）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处）**

**突变 A：** 把 `WeeklyGoalEditor.range` 改成 `1...30`。重跑：`testRangeMatchesTheSettingsModel` 必须变红。

**这条守的是「界面能选、存下去却不认」这类最难查的不一致**：用户选了 30，界面显示 30，重启后变回 5，而任何日志都不会提到这件事。

**突变 B：** 把 `hint` 里 `done >= goal` 那一支删掉（永远走「还差」分支）。重跑：`testHintSaysDoneWhenTheGoalIsAlreadyMet`、`testHintNeverShowsANegativeRemainder` 必须变红。

两次都改回，确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Settings/ Sources/IELTSCoachUI/AppState.swift Sources/IELTSCoachUI/RootView.swift Sources/IELTSCoachUI/Today/TodayView.swift Tests/IELTSCoachUITests/WeeklyGoalEditorTests.swift Tests/IELTSCoachCoreTests/WeeklyGoalTests.swift
git commit -m "feat(ui): 每周训练目标可配置（⌘, 打开，默认 5 次）"
```

---

## Task 10: 演示数据脚本（供人工验收用，绝不碰真实数据）

**Files:**
- Create: `scripts/seed-demo-data.swift`

**Interfaces:**
- Consumes: 无（脚本只依赖 Foundation，不 import 本工程任何模块）
- Produces: 一份写在**指定目录**里的 `state.json`，含 12 场练习、5 个不同趋势的问题、6 条词汇

**为什么需要它：** Task 11 的验收要看「趋势对不对、新问题标记对不对、导出跳过提示长什么样」。要在真实数据里看到确定的趋势，用户得先练满 8 场——那是好几天。这个脚本让验收在两分钟内能做完。

**这个脚本刻意不 import `IELTSCoachCore`**，直接手写 JSON。这样它同时是一次独立的 schema 校验：如果 App 读不出这份手写的 `state.json`，说明模型的容错解码有问题，而这正是要发现的事。

- [ ] **Step 1: 写脚本**

`scripts/seed-demo-data.swift`：

```swift
#!/usr/bin/env swift
// 造一份演示用的训练数据，供人工验收问题档案页/词汇页/首页统计。
//
// 用法：swift scripts/seed-demo-data.swift [输出目录]
// 不给参数时写到临时目录。
//
// ⚠️ 这个脚本会覆盖目标目录里的 state.json。它硬性拒绝写入真实数据目录。
import Foundation

// MARK: - 目标目录与安全闸

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSTemporaryDirectory() + "ielts-demo-data"
let target = URL(fileURLWithPath: outputPath).standardizedFileURL

let realRoot = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "IELTS Speaking Coach").standardizedFileURL.path

guard target.path != realRoot, !target.path.hasPrefix(realRoot + "/") else {
    FileHandle.standardError.write(Data("""
    ❌ 拒绝写入真实数据目录：\(realRoot)
       这个脚本会覆盖 state.json，写进真实目录会毁掉你已有的练习记录。
       下一步：换一个目录，例如
         swift scripts/seed-demo-data.swift /tmp/ielts-demo

    """.utf8))
    exit(1)
}

// MARK: - 时间工具

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]

let dayFormatter = DateFormatter()
dayFormatter.locale = Locale(identifier: "en_US_POSIX")
dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
dayFormatter.dateFormat = "yyyy-MM-dd"

let now = Date()
func daysAgo(_ count: Int) -> Date { now.addingTimeInterval(TimeInterval(-count * 86_400)) }

// MARK: - 12 场练习：11 天前到今天，每天一场

var sessions: [[String: Any]] = []
var sessionIDs: [String] = []          // 由旧到新

for ago in stride(from: 11, through: 0, by: -1) {
    let started = daysAgo(ago)
    let id = dayFormatter.string(from: started) + "-001"
    sessionIDs.append(id)
    sessions.append([
        "id": id,
        "questionId": "demo-q\(ago)",
        "focusPart": ago % 3 == 1 ? "Part 2" : "Part 1",
        "startedAt": iso.string(from: started),
        // 时长在 18–24 分钟之间变化，让「本周开口时长」不是个整齐的假数字
        "endedAt": iso.string(from: started.addingTimeInterval(60 * Double(18 + ago % 7))),
        "goal": "",
        "transcript": [],
        "reportPath": "",
        "recordingPath": ""
    ])
}

/// 取第 n 场（0 = 最旧）。窗口划分：最近 5 场是 7...11，再往前 5 场是 2...6。
func session(_ index: Int) -> String { sessionIDs[index] }

// MARK: - 5 个问题，覆盖全部趋势分支

func issue(_ id: String, said: String, correction: String, why: String,
           occurrences: Int, indices: [Int]) -> [String: Any] {
    [
        "id": id,
        "learnerSaid": said,
        "correction": correction,
        "whyItMatters": why,
        "occurrences": occurrences,
        "sourceSessionIds": indices.map(session),
        "lastSeenAt": iso.string(from: daysAgo(11 - (indices.max() ?? 0)))
    ]
}

let issues: [[String: Any]] = [
    // 出现变少了：之前 5 场里犯 4 场，最近 5 场里只犯 1 场
    issue("issue-decreasing", said: "I very like this place.",
          correction: "I really like this place.",
          why: "very 不能直接修饰动词，考官会当成基础语法错误",
          occurrences: 6, indices: [2, 3, 4, 5, 11]),
    // 最近没再出现
    issue("issue-gone", said: "I am agree with that.",
          correction: "I agree with that.",
          why: "agree 本身就是动词，不需要 be 动词",
          occurrences: 3, indices: [2, 3]),
    // 出现变多了
    issue("issue-increasing", said: "Yeah... you know... like...",
          correction: "去掉口头禅，改成一个短停顿",
          why: "填充词密集会明显拉低流利度印象",
          occurrences: 5, indices: [2, 9, 10, 11]),
    // 还是老样子
    issue("issue-steady", said: "It's very good.",
          correction: "It's genuinely rewarding.",
          why: "good/very 这类词反复出现会拉低词汇多样性",
          occurrences: 4, indices: [3, 4, 8, 9]),
    // 新问题：只出现在最近两场
    issue("issue-fresh", said: "In my country have many parks.",
          correction: "In my country, there are many parks.",
          why: "缺主语的句子在 Part 3 长回答里会成片出现",
          occurrences: 2, indices: [10, 11])
]

// MARK: - 6 条词汇，含两条会被导出跳过的

let vocabulary: [[String: Any]] = [
    ["id": "vocab-1", "basicWord": "good", "betterExpression": "rewarding",
     "collocation": "a rewarding experience", "priority": "high",
     "sourceSessionIds": [session(2), session(7), session(11)]],
    ["id": "vocab-2", "basicWord": "important", "betterExpression": "crucial",
     "collocation": "a crucial factor", "priority": "high",
     "sourceSessionIds": [session(5)]],
    ["id": "vocab-3", "basicWord": "a lot of", "betterExpression": "a great deal of",
     "collocation": "a great deal of effort", "priority": "normal",
     "sourceSessionIds": [session(6), session(9)]],
    ["id": "vocab-4", "basicWord": "happy", "betterExpression": "upbeat",
     "collocation": "in an upbeat mood", "priority": "medium",   // 没见过的写法，应归到「有空再记」
     "sourceSessionIds": [session(8)]],
    // 这条背面是空的，导出时必须被跳过并给出说明
    ["id": "vocab-5", "basicWord": "nice", "betterExpression": "",
     "collocation": "", "priority": "low",
     "sourceSessionIds": [session(3)]],
    // 这条正文里含制表符与换行，用来验证清洗（导出后应仍是一行三列）
    ["id": "vocab-6", "basicWord": "busy", "betterExpression": "swamped\twith work",
     "collocation": "I was swamped\nall week", "priority": "normal",
     "sourceSessionIds": [session(10)]]
]

// MARK: - 组装并落盘

let state: [String: Any] = [
    "schemaVersion": 3,
    "learner": ["displayName": "演示数据", "createdAt": iso.string(from: daysAgo(30))],
    "currentSession": NSNull(),
    "sessions": sessions,
    "targets": [[
        "id": "logic-explain-example",
        "label": "回答后补一个原因和一个例子",
        "status": "new",
        "evidence": ["I just like it."],
        "sourceSessionId": session(11),
        "createdAt": iso.string(from: daysAgo(0))
    ]],
    "issues": issues,
    "vocabulary": vocabulary,
    "plan": NSNull(),
    "questions": [],
    "questionSources": [],
    "settings": ["recordingEnabled": false, "recordingConsentAt": "", "weeklyGoal": 5],
    "questionCursor": ["part1": 0, "part2": 0, "part3": 0]
]

do {
    for sub in ["", "reports", "pending-reviews", "recordings"] {
        let url = sub.isEmpty ? target : target.appending(path: sub)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    let data = try JSONSerialization.data(withJSONObject: state,
                                          options: [.prettyPrinted, .sortedKeys])
    try data.write(to: target.appending(path: "state.json"), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("""
    ❌ 写入失败：\(error.localizedDescription)
       下一步：确认 \(target.path) 这个位置可写，或换一个目录再试。

    """.utf8))
    exit(1)
}

print("""
✅ 演示数据已写入 \(target.path)
   12 场练习（最近 12 天，每天一场）、5 个覆盖全部趋势的问题、6 条词汇。

   下一步：带着这个数据目录打开 App——

     IELTS_SPEAKING_DATA_DIR="\(target.path)" \\
       ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"

   （直接跑 .app 里的二进制，签名与辅助功能授权都不受影响。
     不要用 open 命令，那样传不进环境变量。）
""")
```

- [ ] **Step 2: 验证脚本**

Run: `swift scripts/seed-demo-data.swift /tmp/ielts-demo`
Expected: 打印「✅ 演示数据已写入 /tmp/ielts-demo」

Run: `python3 -c "import json;d=json.load(open('/tmp/ielts-demo/state.json'));print(len(d['sessions']),len(d['issues']),len(d['vocabulary']),d['settings']['weeklyGoal'])"`
Expected: `12 5 6 5`

- [ ] **Step 3: 验证安全闸真的拦得住**

Run: `swift scripts/seed-demo-data.swift ~/Library/Application\ Support/IELTS\ Speaking\ Coach`
Expected: 退出码非 0，打印「❌ 拒绝写入真实数据目录」，**且真实目录里的 `state.json` 修改时间没有变**

Run: `ls -l ~/Library/Application\ Support/IELTS\ Speaking\ Coach/state.json`
Expected: 修改时间仍是上一次练习的时间

**这一步不能跳。** 一个会覆盖用户全部练习记录的脚本，它的安全闸必须当场验过一次，不能靠读代码认为它对。

- [ ] **Step 4: 提交**

```bash
git add scripts/seed-demo-data.swift
git commit -m "chore: 演示数据脚本（供人工验收，硬性拒绝写入真实数据目录）"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase7-acceptance.md`

前面所有测试跑在视图模型与纯逻辑上，证明的是「数字算得对」，不是「看着有用」。以下只能人来判断。

**本任务不安排任何驱动真实 ChatGPT 的步骤。** 验收用 Task 10 造的演示数据即可完成；要不要顺手再练一场，由你自己决定。

- [ ] **Step 1: 打包并用演示数据打开**

```bash
cd ~/Projects/ielts-speaking-coach-mac
./scripts/build-app.sh
swift scripts/seed-demo-data.swift /tmp/ielts-demo
IELTS_SPEAKING_DATA_DIR=/tmp/ielts-demo ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"
```

**注意用的是 `.app` 里的二进制加环境变量，不是 `open`。** `open` 传不进环境变量，会打到真实数据目录上去。

- [ ] **Step 2: 首页四格**

| 看什么 | 期望 |
|---|---|
| 本周训练 | `N/5`。N 与本周实际的演示场次一致（演示数据每天一场，所以是本周已过天数 + 1） |
| 累计训练 | `12` |
| 本周开口时长 | 一个 100 上下的分钟数，不是 0，也不是几百 |
| 出现变少的毛病 | `2`（`issue-decreasing` 与 `issue-gone`） |
| 四条脚注 | 每条都读得懂，且都能看出「下一步做什么」 |
| **有没有任何一处出现分数、评级、band、几分** | **必须一个都没有** |

- [ ] **Step 3: 等宽数字（本阶段最容易被忽略、也最容易被察觉的一条）**

点**首页工具栏那颗齿轮**（或「本周训练」格里的「改目标」按钮）打开每周训练目标面板，把目标从 **9 调到 10**，再调回去，来回几次，**盯着面板里那一行和首页「本周训练」那一格**。

> **不要写成「按 ⌘,」。** ⌘, 归 Phase 5 的录音设置窗口（见本任务 Task 9 的补注），这颗齿轮**不挂快捷键**——照 ⌘, 那一步做只会弹出录音设置，改不到每周目标。

Expected: 那一行**横向纹丝不动**。若整行左右跳动，说明 `value` 上漏了 `.monospacedDigit()`。

同样的方法看「累计训练」（把演示数据改成 9 场再改成 10 场，或直接在那个面板里反复切目标观察分母）。

**这一条 `DESIGN-SYSTEM.md` 第 1 节与第 6 节最后一条都点了名。** 抖动的数字平时没人能一眼说出哪儿不对，只会觉得「界面有点廉价」。

- [ ] **Step 4: 问题档案页**

| 看什么 | 期望 |
|---|---|
| 排序 | 按出现次数从多到少 |
| `issue-fresh` | 带「新问题」标记，且标记**是图标 + 文字**，不是只有颜色 |
| `issue-decreasing` | 趋势显示「出现变少了」，detail 里写着「最近 5 场里有 1 场…再往前 5 场里有 4 场」 |
| `issue-gone` | 「最近没再出现」 |
| `issue-increasing` | 「出现变多了」 |
| `issue-steady` | 「还是老样子」 |
| 四个筛选 | 各自筛出来的内容说得通；筛到空时有空状态文案 |
| 展开某一条 | 能看到 `explanation`，里面有「下一步」 |
| 整页 | 没有任何分数、评级 |

再把 `/tmp/ielts-demo/state.json` 里某个 issue 的 `sourceSessionIds` 加一个 `"sync-1754123456"`，重开 App：

Expected: 列表上方出现数据警告，说清「有 1 条练习记录读不出时间」以及下一步。**看不到警告就是 Task 6 突变 B 那个坑没堵住。**

- [ ] **Step 5: 我的词汇页与导出（本阶段对接你已有 Anki 流程的部分）**

1. 排序是不是「优先记」在前
2. `vocab-4` 的 priority 是 `"medium"`，应显示成「有空再记」而不是崩溃或空白
3. 点「导出… › Anki 导入文件（.txt）」，存到桌面
   - 弹出的提示里必须写着这个文件怎么用（`howToUse`）
   - 导出完成后必须显示**跳过了哪几条、为什么**（`vocab-5` 背面为空）
4. 用文本编辑器打开导出的 `.txt`：
   - 开头五行是 `#separator:tab` 等指令
   - **`vocab-6` 那一行仍然是一行三列**（它的原文里有制表符和换行）
5. 在 Anki 里「文件 › 导入」这个文件——**这一步只有你能验**：牌组、笔记类型、标签是不是都自动带对了？导进去的卡片正反面对不对？
6. 点「导出… › AnkiConnect 请求（.json）」，按提示 `curl` 一次（Anki 要开着）。这一步验的是「能不能接上你已有的流程」
7. 点「复制到剪贴板」，确认有明确反馈，且粘出来的内容与文件一致
8. 筛到「优先记」再导出，确认**只导出了筛选后的那几条**

- [ ] **Step 6: 每周目标**

1. 首页工具栏那颗**齿轮**能不能打开每周训练目标面板（**不是 ⌘,**——见上面 Task 9 的补注：⌘, 归 Phase 5 的录音设置窗口，这颗齿轮不挂快捷键。顺手按一次 ⌘, 确认弹出来的是**录音设置**，不是每周目标）
2. 首页「本周训练」格里的「改目标」按钮能不能打开同一个面板
3. 改成 3，保存，首页立刻变成 `N/3`
4. 关掉 App 再打开，仍然是 3
5. 把 `/tmp/ielts-demo/state.json` 里的 `weeklyGoal` 手改成 `0`，重开 App：应显示 `N/5`，而不是 `N/0` 或崩溃

- [ ] **Step 7: 界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节十条）**

两个新页面 + 首页都要走一遍。其中四条最容易出问题：

- [ ] 打开系统「减弱动态效果」后，两页无动画且功能正常
- [ ] 系统文字调到最大时，四格统计与词汇行不截断、不重叠（**脚注很长，这里最容易崩**）
- [ ] Tab 能走遍筛选控件、导出菜单、每行的按钮，焦点环可见
- [ ] 每个列表的空状态都有「说明 + 下一步 + 按钮」（把演示数据里的 `issues` 与 `vocabulary` 清空成 `[]` 再开一次 App 来验）

- [ ] **Step 8: 用真实数据再看一眼**

关掉演示数据，用真实数据目录打开 App（正常双击 `.app`）。

Expected：

- 若 Phase 4 已经在写 `state.sessions`：三格统计有真实数字
- 若还没有：三格是 0，但**页面不能因此显示成一片空白**——脚注要说清「还没有任何练习记录。下一步：回到上面点「开始」，练第一场。」

**若三格是 0 而问题档案页有内容**，这不是缺陷，是 Phase 4 还没接上 `state.sessions`。照实写进验收报告即可，不要在本阶段顺手去实现 Phase 4。

- [ ] **Step 9: 记录并提交**

把每一项的实际结果写进 `docs/phase7-acceptance.md`，含截图或原文描述。**包括不好的部分**——「哪里让我不想用」这类信息只有你有（成品标准第 5 节）。

特别要写清楚的三件事：

1. 趋势的说法是不是**真的让你知道该干什么**，还是又一堆看不出所以然的数字
2. 导出的文件在你已有的 Anki 流程里是不是**真的能直接用**，还是又要手工调一遍
3. 首页四格里有没有哪一格你其实**根本不看**——不看的格子应该拿掉，而不是留着占位

```bash
git add docs/phase7-acceptance.md
git commit -m "docs: Phase 7 真机验收结果"
```

---

## Phase 7 完成标准

- [ ] `swift test` 全绿，总耗时仍在 2 秒以内（Phase 3 Task 10 定的线，不能被本阶段拖回去）
- [ ] 问题档案页：错题按出现次数排序、「新问题」有图标 + 文字的标记、每条带趋势与具体次数
- [ ] 我的词汇页：按优先级排序，可导出为 Anki 导入文件与 AnkiConnect 请求两种格式
- [ ] **导出的文件在真实 Anki 里导入成功一次**（人工验过）
- [ ] 首页四格：本周 N/目标、累计训练、本周开口时长、出现变少的毛病
- [ ] 首页有「你的问题正在怎么变化」列表，最多五条，可跳到问题档案页
- [ ] 每周训练目标可配置（首页工具栏齿轮按钮打开；⌘, 归 Phase 5 的录音设置窗口，见 Task 9 的补注），默认 5，改完立刻生效且重启后保留，越界值自动归一
- [ ] **所有统计数字用 `.monospacedDigit()`，来回改目标时那一行不抖**（人工验过）
- [ ] **全阶段没有任何形式的雅思分数预测**，且有一条自动化测试守着（`testNoScorePredictionInAnyUserFacingText`），并做过突变验证
- [ ] 每个关键任务都完成了突变验证，且把「改了哪一行、哪条测试红了」写进了报告
- [ ] 三个页面的空状态都有「说明 + 下一步 + 按钮」
- [ ] `SessionTimeline` 发现的数据问题会在界面上显示出来，不是只记在内存里
- [ ] 演示数据脚本能用，且**实测拒绝写入真实数据目录**

达成后进 Phase 8：学习计划页 + 四条练习路线全部可用。

---

## 本阶段刻意没做的事（写下来防止范围扩大）

| 没做 | 为什么 |
|---|---|
| **任何分数预测、水平评估、进步百分比** | `DEFINITION-OF-DONE.md` 第 4 节明令禁止。数字越像分数，人越会盯着数字而不是盯着问题 |
| 问题/词汇的手动删除与编辑 | 归档数据的编辑属于「训练记录」那一摊（Phase 4/5 的单条删除）。本阶段只读不写，唯一的写入是每周目标 |
| 词汇的复习排程（SRS） | 用户已有 Anki 流程。在这里再造一套间隔重复只会和他真正在用的工具打架 |
| 深色模式 | ⚠️ **这一条与 `DESIGN-SYSTEM.md` 不一致，需要用户拍板。** 那份文件第 2 节的原话是「Phase 3 只做浅色……这样**Phase 7** 加深色模式时只改这一个文件」——即深色模式是挂在**本阶段**名下的。本计划把它推后了，理由是本阶段已经有 11 个任务、而深色模式要重配一整套色值并重跑对比度测试（不能靠反色，见 `DESIGN-SYSTEM.md`）。**Phase 8–10 也都没有认领它**，所以照现在这七份计划走，做到 Phase 10 结束仍然只有浅色。要么用户同意推到 Phase 10 之后另开一阶段，要么把它加回本阶段——2026-08-06 跨阶段复审记 |
| 按时间范围筛选统计（近 30 天/近 90 天） | 「本周」加「累计」已经覆盖了「有没有在坚持」这个问题。多一个时间选择器只会多一个要维护的分支 |
| 趋势图表 | 一条折线要好看需要足够多的点，而这个产品的用户一周练 5 次。五个点的折线不如一句「最近 5 场里有 1 场犯了它，之前 5 场里有 4 场」说得清楚 |
