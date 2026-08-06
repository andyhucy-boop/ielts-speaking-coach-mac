# Phase 5：录音与回听

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户可以在设置里打开「保存我的回答录音」（**默认关**），打开后每次练习会把自己说的话录成一条 `.m4a`；练完在「训练记录」页点开那次练习就能直接回听，也能单独把这条录音删掉；页面上能看到录音一共占了多少磁盘。练到一半插拔耳机时，录音**不会静默消失**——要么自动接上继续录，要么把已经录到的部分完整保存下来并明确告诉用户发生了什么。

**Architecture:** 新增一个 library target `IELTSCoachAudio`，它是全工程**唯一**依赖 `AVFoundation` 的地方。它内部再切一刀：真正跟硬件打交道的部分（`AVAudioEngine` 采集、AAC 写文件）躲在两个 protocol 后面（`AudioCaptureEngine` / `AudioSegmentWriter`），编排逻辑（`RecordingSession`）只依赖这两个 protocol。**这样「插拔耳机」这条最要紧的路径可以用假实现完整测试，不需要真麦克风、不需要真的去拔线。** 这是 Phase 2 做 `AXAccess` 接缝、Phase 3 做 `CoachBridge` 接缝换来的同一个红利，本阶段继续沿用。

纯逻辑（开关与同意时间戳、文件命名、占用统计、删除、权限状态的文案与判定）全部放在 `IELTSCoachCore`，只依赖 Foundation，因此在没有音频框架、没有图形界面的环境下也能完整单元测试。

**Tech Stack:** Swift 6.3.3（swift-tools-version 6.0，**Swift 6 语言模式，严格并发已开启**）、SPM、SwiftUI、AVFoundation、XCTest、`codesign`。无第三方依赖。

---

## Global Constraints

这一节的每一条都是硬约束，违反即返工。

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权与麦克风授权都绑定它。改了之后用户得把两个系统权限重新授一遍
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit 的代码放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 `IELTSCoachCore`、`ChatGPTBridge`、`IELTSCoachAudio`、SwiftUI
- `IELTSCoachAudio` 可依赖 `IELTSCoachCore`、AVFoundation。**不得依赖 `ChatGPTBridge`、不得依赖 SwiftUI**
- 所有面向用户的文案（错误、警告、空状态、开关说明）必须是中文，且同时说明「**发生了什么**」和「**下一步做什么**」
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- **界面必须遵循 `docs/superpowers/DESIGN-SYSTEM.md`。视图里不得出现字面颜色、字号、圆角——一律走 `Palette` / `Spacing` / `Radius` 令牌**
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- **只录用户自己的麦克风，绝不录 ChatGPT 的声音。** 这是明确的产品取舍（`DEFINITION-OF-DONE.md` 第 4 节、`ROADMAP.md` 3.3）：录对方声音需要「屏幕录制」权限，字面含义是「能看你屏幕」，观感代价不值。考官问了什么由 Phase 4 的逐字稿给文字。**任何人不得在本阶段引入 ScreenCaptureKit 或系统音频采集**
- **单元测试里绝不允许碰真硬件。** 不许构造 `SystemMicrophoneAuthorizer`、不许调用 `AVCaptureDevice.requestAccess`、不许调用 `AVAudioEngineCapture.start()`。`swift test` 跑的是没有 bundle id、没有 Info.plist 的命令行进程，调用麦克风 API 会直接崩溃或挂住（无限等待），两者都违反上面的硬约束。所有涉及硬件的路径一律用假实现测试，真硬件放到 Task 11 的人工验收

---

## 这个阶段有一件事任何自动化都绕不过去

**麦克风权限只能由用户本人在系统弹窗里点「允许」。**

macOS 的 TCC 机制决定了这一点：`AVCaptureDevice.requestAccess(for: .audio)` 会弹出一个系统对话框，那个对话框不属于本应用，脚本点不了、AX 也点不了，而且**一个 App 一辈子只会被问一次**——用户点了「不允许」之后系统再也不弹，只能让用户自己去「系统设置 › 隐私与安全性 › 麦克风」里打开。

这条约束直接决定了三处设计：

1. `MicrophonePermissionState` 必须把 `.notDetermined`（还没问过，弹窗有用）和 `.denied`（问过被拒，弹窗没用）**分成两个状态**。混成一个的话，被拒过的用户会点了开关之后对着一个永远不出现的弹窗干等——这就是「无限等待」
2. 权限没拿到时，界面上的开关**必须停在「关」**。显示成「开」却什么都不录，是本项目最不能接受的那种失败
3. Task 11 的第 1 步必须由用户亲自做，子代理不得代劳、不得假装做过

---

## 前置依赖：Phase 3 / Phase 4 必须已经提供的东西

**动手前先确认下面每一条都成立。任何一条不成立，停下来报告，不要自己发明一个替代品。**

| 编号 | 依赖 | 来自 | 怎么确认 |
|---|---|---|---|
| P3-1 | 设计令牌 `Palette` / `Spacing` / `Radius` 与组件 `CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView` | Phase 3 Task 7 | `ls Sources/IELTSCoachUI/DesignSystem/` |
| P3-2 | `@MainActor @Observable final class PracticeRunner`，含 `stage: PracticeStage`、`start(setup:) async throws`、`finishPractice() async`、`cancel()`；只依赖 `CoachBridge` protocol | Phase 3 Task 9 | `ls Sources/IELTSCoachUI/Session/PracticeRunner.swift` |
| P3-3 | `Tests/IELTSCoachUITests/` 下已有可编程的 `FakeBridge` 与 `FakePasteboard` | Phase 3 Task 9 | `grep -rn "class FakeBridge" Tests/IELTSCoachUITests/` |
| P3-4 | `.app` 打包脚本 `scripts/build-app.sh`，且 Info.plist 里已有 `NSMicrophoneUsageDescription` | Phase 3 Task 1 | `grep -n NSMicrophoneUsageDescription scripts/build-app.sh` |
| **P4-1** | **训练记录页** `Sources/IELTSCoachUI/History/HistoryView.swift` 与对应的视图模型，按月分组列出每次练习 | Phase 4 | `ls Sources/IELTSCoachUI/History/` |
| **P4-2** | **每次练习真的会在 `state.sessions` 里落一条 `PracticeSession`**，且 `id` 在归档时已分配 | Phase 4 | 练一场后 `grep -c '"id"' ~/Library/Application\ Support/IELTS\ Speaking\ Coach/state.json`，或读 `PracticeRunner` 的归档代码 |

**P4-2 特别要当心。** 写这份计划时（2026-08-06）命令行版 `Sources/coach/PracticeCommand.swift` **根本没有往 `state.sessions` 里追加过任何东西**——它只把复盘归档，会话记录是空的。Phase 4 必须补上这一条，否则「训练记录页」和本阶段的「回听」都无处可挂。

**Task 1–8 不依赖 P4-1 / P4-2**，可以先做。只有 Task 9（把播放器嵌进训练记录页）、Task 7 的最后一条测试、以及 Task 7b 的第一条测试需要它们。

> ### Phase 4 的实施计划已于 2026-08-06 写完，上面两条都由它交付（复审补记）
>
> 见 `docs/superpowers/plans/2026-08-06-phase4-transcript-and-history.md`。开工时按上表的命令实测确认，别只信这段话。它交付的形状与本阶段有关的有四条：
>
> | | Phase 4 的实际形状 | 对本阶段的影响 |
> |---|---|---|
> | P4-1 | `Sources/IELTSCoachUI/History/HistoryView.swift` + `HistoryViewModel.swift`；行模型 `HistoryRow` 已带 `hasRecording: Bool`（只看 `recordingPath` 非空，**不看文件在不在**）| Task 9 直接改那个文件，不要新建。文件不在时的 `.missing` 提示仍是 Task 9 的活 |
> | P4-2 | `PracticeRunner.finishPractice()` 里按 id upsert 进 `state.sessions`，私有方法 `upsertSession(id:reportPath:)` | **`recordingPath` 请给 `upsertSession` 加一个 `recordingPath: String?` 参数**，与 `reportPath` 同样处理（非 nil 才写）。不要另写一套会话落库逻辑 |
> | 签名 | `PracticeRunner(bridge:pasteboard:directory:transcript:now:)`，**没有 `store:`**，`directory:` 默认 `.resolve()` | 见 Task 7 Step 1 那个 ⚠️ 块。`recording:` 加在 `now:` 前后都行，带默认值 `nil` |
> | 删除 | Phase 4 的 `SessionDeleter` 已经会连带删录音文件（跨阶段决策 4）| Task 9 的 `RecordingPlaybackViewModel.delete()` 删的是「只删录音、保留记录」。两者不冲突，但**两个删除入口都要在界面上说清各自删了什么** |

---

## 一个已经定下来、不要再改的取舍：录音文件按「练习开始时刻」命名

`ROADMAP.md` 3.3 里写的是 `recordings/<sessionID>.m4a`。**本计划改为按练习开始时刻命名**：`recordings/2026-08-06T10-15-30Z.m4a`。

理由：`PracticeSession.id`（`YYYY-MM-DD-NNN`）是**练完归档时**才分配的，而录音在那之前十几分钟就已经在往磁盘上写了。要坚持用会话 id 命名，只有两条路：

- 先写成临时名、归档时改名 —— 「改名那一步失败」会让一整场练习的录音凭空消失。这正是成品标准第 7 条（任何一步失败，已产生的内容都还在）最不能接受的形态
- 练习开始前就先分配会话 id —— 那要求 `PracticeRunner` 在没练之前先往 `state.json` 里写一条空会话，把本阶段跟 Phase 4 的实现细节死死绑在一起

按开始时刻命名之后，**文件从第一秒起就在它最终该在的位置上**，谁也不用改名，谁也不用先占坑。会话与录音的关联由 `PracticeSession.recordingPath` 这个字段承担——这个字段 schema 里本来就有，不需要改 `schemaVersion`（schema 固定为 3，与上游及 Windows 版互通，见 spec 4.6）。

---

## File Structure

```
Sources/
├── IELTSCoachCore/
│   └── Recording/                                  新增目录，只依赖 Foundation
│       ├── MicrophonePermissionState.swift         权限状态 + 中文引导文案（纯逻辑）
│       ├── RecordingConsent.swift                  开关、同意时间戳、能不能录的判定（纯逻辑）
│       └── RecordingStore.swift                    命名、列举、占用、删除、孤儿检测
├── IELTSCoachAudio/                                新增 library：全工程唯一依赖 AVFoundation 的地方
│   ├── RecordingEngineError.swift                  中文错误
│   ├── AudioCaptureEngine.swift                    两个接缝 protocol（采集 / 写文件）
│   ├── RecordingSession.swift                      编排：启动、写入、设备切换、收尾（可测）
│   ├── AVAudioEngineCapture.swift                  真实采集实现（碰硬件，不做单元测试）
│   ├── AACSegmentWriter.swift                      真实写文件实现（不碰硬件，可测）
│   ├── MicrophoneAuthorizer.swift                  AVCaptureDevice 权限查询与申请
│   └── PracticeRecordingCoordinator.swift          把开关 + 权限 + 录音串起来给 PracticeRunner 用
├── IELTSCoachUI/
│   ├── Recording/
│   │   ├── RecordingSettingsViewModel.swift        开关、权限引导、占用提示（纯逻辑，可测）
│   │   ├── RecordingSettingsView.swift             设置窗口里的那一页
│   │   ├── RecordingSettingsScene.swift            组装真实依赖
│   │   ├── RecordingPlaybackViewModel.swift        单条录音的状态与删除（纯逻辑，可测）
│   │   └── RecordingPlayerView.swift               训练记录页里内嵌的播放器
│   ├── Session/PracticeRunner.swift                修改：把录音接进练习流程
│   └── History/HistoryView.swift                   修改：嵌入播放器（Phase 4 产出）
└── IELTSCoachApp/main.swift                        修改：加 Settings 场景（⌘,）
Tests/
├── IELTSCoachCoreTests/
│   ├── MicrophonePermissionStateTests.swift
│   ├── RecordingConsentTests.swift
│   └── RecordingStoreTests.swift
├── IELTSCoachAudioTests/                           新增 test target
│   ├── FakeAudioCapture.swift                      假麦克风 + 假文件写入器
│   ├── RecordingSessionTests.swift                 ← 插拔耳机的核心覆盖在这里
│   ├── AACSegmentWriterTests.swift                 ← 输入格式中途变化的核心覆盖在这里
│   ├── MicrophoneAuthorizerTests.swift
│   └── PracticeRecordingCoordinatorTests.swift
└── IELTSCoachUITests/
    ├── RecordingSettingsViewModelTests.swift
    ├── RecordingPlaybackViewModelTests.swift
    └── PracticeRunnerRecordingTests.swift
```

### 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略。**

理由与 Phase 3 计划第 79–86 行一致：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务里写明「必须显示什么、空状态说什么、失败时说什么、哪些元素必须能用键盘到达」，具体怎么摆由实现者定，由设计令牌约束，最后由 Task 11 的人工验收把关。

这与「禁止占位符」不冲突：占位符是「TBD、以后再说」，而这里给的是明确的验收标准。若实现者认为某处要求不清楚到无法动手，**应当停下来问，而不是猜**。

---

## Task 1: 新建 `IELTSCoachAudio` target + 麦克风权限状态

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Package.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Recording/MicrophonePermissionState.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/MicrophoneAuthorizer.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/MicrophonePermissionStateTests.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachAudioTests/MicrophoneAuthorizerTests.swift`

**Interfaces:**
- Consumes: `AVCaptureDevice.authorizationStatus(for:)`、`AVCaptureDevice.requestAccess(for:)`、`AVAuthorizationStatus`
- Produces:
  - `public enum MicrophonePermissionState: String, Equatable, Sendable, CaseIterable { case granted, notDetermined, denied, restricted }`
  - `public var MicrophonePermissionState.canPrompt: Bool`
  - `public var MicrophonePermissionState.guidance: String?`
  - `public static let MicrophonePermissionState.systemSettingsURLString: String`
  - `public protocol MicrophoneAuthorizing: Sendable { func currentStatus() -> MicrophonePermissionState; func requestAccess() async -> MicrophonePermissionState }`
  - `public struct SystemMicrophoneAuthorizer: MicrophoneAuthorizing`
  - `public static func SystemMicrophoneAuthorizer.map(_ status: AVAuthorizationStatus) -> MicrophonePermissionState`

**为什么把状态枚举放 Core 而不是放音频 target：** 判定与文案是纯逻辑，跟 `AVFoundation` 的具体枚举无关。放 Core 之后，「被拒过就别再弹窗」这条规则可以在完全不碰音频框架的情况下测到——而这恰恰是这个阶段最容易写错、错了又最难发现的一条。

- [ ] **Step 1: 更新 Package.swift**

在 `products` 里加一行，在 `targets` 里加两行，并给 `IELTSCoachUI` 加一个依赖。改完后完整内容应为：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IELTSCoach",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .library(name: "IELTSCoachAudio", targets: ["IELTSCoachAudio"]),
        .library(name: "IELTSCoachUI", targets: ["IELTSCoachUI"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"]),
        .executable(name: "IELTSCoachApp", targets: ["IELTSCoachApp"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        // 全工程唯一依赖 AVFoundation 的 target。刻意不让它依赖 ChatGPTBridge：
        // 录音与驱动 ChatGPT 是两件互不相干的事，混在一起会让任何一边的故障
        // 都变成「不知道断在哪」。
        .target(name: "IELTSCoachAudio", dependencies: ["IELTSCoachCore"]),
        .target(name: "IELTSCoachUI",
                dependencies: ["IELTSCoachCore", "ChatGPTBridge", "IELTSCoachAudio"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "IELTSCoachApp", dependencies: ["IELTSCoachUI"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachAudioTests", dependencies: ["IELTSCoachAudio"]),
        .testTarget(name: "IELTSCoachUITests", dependencies: ["IELTSCoachUI"])
    ]
)
```

- [ ] **Step 2: 写失败的测试**

`Tests/IELTSCoachCoreTests/MicrophonePermissionStateTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class MicrophonePermissionStateTests: XCTestCase {
    /// 这是本阶段最容易写错的一条规则。
    ///
    /// macOS 一个 App 一辈子只会为麦克风弹一次系统对话框：用户点过「不允许」之后
    /// 再调 requestAccess 会立刻返回拒绝，对话框根本不出现。若代码把 .denied 也
    /// 当成「可以再弹一次」，用户点了开关之后就会对着一个永远不来的弹窗干等——
    /// 这正是「禁止无限等待」要防的事。
    func testOnlyNotDeterminedCanPrompt() {
        XCTAssertTrue(MicrophonePermissionState.notDetermined.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.denied.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.restricted.canPrompt)
        XCTAssertFalse(MicrophonePermissionState.granted.canPrompt)
    }

    func testGrantedHasNothingToSay() {
        XCTAssertNil(MicrophonePermissionState.granted.guidance)
    }

    /// 每一条引导都必须同时说清「发生了什么」和「下一步做什么」。
    func testEveryBlockedStateExplainsWhatHappenedAndWhatToDoNext() {
        for state in MicrophonePermissionState.allCases where state != .granted {
            let guidance = state.guidance
            XCTAssertNotNil(guidance, "\(state) 没有给用户任何说明")
            XCTAssertTrue(guidance?.contains("下一步") == true,
                          "\(state) 的说明没写下一步做什么：\(guidance ?? "nil")")
        }
    }

    /// 被拒之后唯一的出路是系统设置，所以文案里必须点名它，
    /// 否则用户只会知道「不行」，不知道去哪儿改。
    func testDeniedPointsAtSystemSettings() {
        let guidance = MicrophonePermissionState.denied.guidance ?? ""
        XCTAssertTrue(guidance.contains("系统设置"))
        XCTAssertTrue(guidance.contains("麦克风"))
    }

    func testSystemSettingsURLIsTheMicrophonePane() {
        XCTAssertEqual(MicrophonePermissionState.systemSettingsURLString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertNotNil(URL(string: MicrophonePermissionState.systemSettingsURLString))
    }
}
```

`Tests/IELTSCoachAudioTests/MicrophoneAuthorizerTests.swift`：

```swift
import AVFoundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachAudio

final class MicrophoneAuthorizerTests: XCTestCase {
    /// 只测纯映射。**绝不能在这里调 currentStatus() 或 requestAccess()**：
    /// 前者的返回值取决于跑测试这台机器授过什么权（今天绿明天红），
    /// 后者会弹系统对话框把测试挂死。
    func testMapsEveryKnownAuthorizationStatus() {
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.authorized), .granted)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.notDetermined), .notDetermined)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.denied), .denied)
        XCTAssertEqual(SystemMicrophoneAuthorizer.map(.restricted), .restricted)
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter MicrophonePermissionStateTests`
Expected: 编译失败 —— `MicrophonePermissionState` 未定义

- [ ] **Step 4: 实现**

`Sources/IELTSCoachCore/Recording/MicrophonePermissionState.swift`：

```swift
import Foundation

/// 系统麦克风权限的状态。
///
/// 放在 Core（只依赖 Foundation）是刻意的：判定与文案是纯逻辑，与 AVFoundation
/// 的具体枚举无关，因此可以在完全不碰音频框架的情况下完整测试。音频 target 只负责
/// 把 AVAuthorizationStatus 映射到这里。
public enum MicrophonePermissionState: String, Equatable, Sendable, CaseIterable {
    /// 已授权，可以录。
    case granted
    /// 还没问过。**只有这种状态下弹系统对话框才有用。**
    case notDetermined
    /// 用户拒绝过。macOS 不会再弹第二次，只能让用户自己去系统设置里打开。
    case denied
    /// 被描述文件、MDM 或家长控制限制，用户自己也改不了。
    case restricted

    /// 能不能通过弹系统对话框拿到权限。
    public var canPrompt: Bool { self == .notDetermined }

    /// 给用户看的说明。granted 时为 nil（没什么要说的）。
    /// 其余每一条都必须同时说清「发生了什么」和「下一步做什么」。
    public var guidance: String? {
        switch self {
        case .granted:
            return nil
        case .notDetermined:
            return "还没有麦克风权限，所以现在还录不了。"
                + "下一步：点「开启录音」，系统会弹出一个对话框，请在那个对话框上点「允许」。"
        case .denied:
            return "麦克风权限被拒绝过，系统不会再弹第二次对话框。"
                + "下一步：打开「系统设置 › 隐私与安全性 › 麦克风」，"
                + "把「IELTS Speaking Coach」那一项打开，然后回到这里再点一次开关。"
        case .restricted:
            return "这台电脑的麦克风被系统策略限制了（例如描述文件或家长控制），本应用改不了。"
                + "下一步：找管理这台电脑的人解除限制；在那之前录音用不了，其余功能不受影响。"
        }
    }

    /// 系统设置里麦克风那一页。被拒之后这是唯一的出路。
    public static let systemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}
```

`Sources/IELTSCoachAudio/MicrophoneAuthorizer.swift`：

```swift
import AVFoundation
import Foundation
import IELTSCoachCore

/// 查询与申请麦克风权限。做成 protocol 是为了让视图模型能用假实现测试——
/// 真实实现的返回值取决于跑测试这台机器授过什么权，直接依赖它的测试今天绿明天红。
public protocol MicrophoneAuthorizing: Sendable {
    func currentStatus() -> MicrophonePermissionState
    /// 弹一次系统对话框。
    ///
    /// **只有 `currentStatus() == .notDetermined` 时调用才有意义。** 用户拒绝过之后
    /// macOS 不再弹窗，这个方法会立刻返回 `.denied`——调用方必须据此给出「去系统设置」
    /// 的引导，而不是让用户等一个不会出现的对话框。
    func requestAccess() async -> MicrophonePermissionState
}

public struct SystemMicrophoneAuthorizer: MicrophoneAuthorizing {
    public init() {}

    public func currentStatus() -> MicrophonePermissionState {
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func requestAccess() async -> MicrophonePermissionState {
        let current = currentStatus()
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    /// 映射单独拆成静态函数是为了能测：AVAuthorizationStatus 的四个值可以直接写出来，
    /// 而 AVCaptureDevice 的真实状态测不了。
    public static func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        // 认不出来的新状态一律按「录不了」处理。**绝不能默认成 granted**——
        // 那会让 App 以为自己在录音，用户练完却什么都没有，且没有任何线索。
        @unknown default: return .denied
        }
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter MicrophonePermissionStateTests`
Expected: PASS（5 个测试）

Run: `swift test --filter MicrophoneAuthorizerTests`
Expected: PASS（1 个测试）

Run: `swift test`
Expected: 全绿，既有测试一个不少

- [ ] **Step 6: 突变验证**

把 `canPrompt` 的实现从 `self == .notDetermined` 改成 `self != .granted`，重跑：

Run: `swift test --filter MicrophonePermissionStateTests`
Expected: `testOnlyNotDeterminedCanPrompt` **变红**（`.denied.canPrompt` 与 `.restricted.canPrompt` 两条断言失败）

改回后重跑确认全绿。**把两次的输出原样写进报告。**

这条守的是本阶段唯一一处「会让用户干等」的地方：被拒过还去弹窗，界面上什么都不会发生，用户只能猜。

- [ ] **Step 7: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Package.swift \
        Sources/IELTSCoachCore/Recording/MicrophonePermissionState.swift \
        Sources/IELTSCoachAudio/MicrophoneAuthorizer.swift \
        Tests/IELTSCoachCoreTests/MicrophonePermissionStateTests.swift \
        Tests/IELTSCoachAudioTests/MicrophoneAuthorizerTests.swift
git commit -m "feat(audio): 新建 IELTSCoachAudio target 与麦克风权限状态"
```

---

## Task 2: 录音开关与同意时间戳

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Recording/RecordingConsent.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/RecordingConsentTests.swift`

**Interfaces:**
- Consumes: `CoachSettings`（既有类型，字段 `recordingEnabled: Bool`、`recordingConsentAt: String`）、`CoachState.empty()`、`MicrophonePermissionState`
- Produces:
  - `public enum RecordingReadiness: Equatable, Sendable { case ready; case disabledByUser; case blocked(String) }`
  - `public static func RecordingConsent.enable(_ settings: CoachSettings, at timestamp: String) -> CoachSettings`
  - `public static func RecordingConsent.disable(_ settings: CoachSettings) -> CoachSettings`
  - `public static func RecordingConsent.readiness(settings: CoachSettings, permission: MicrophonePermissionState) -> RecordingReadiness`

**这两个字段 `CoachSettings` 里本来就有**（`Sources/IELTSCoachCore/Model/CoachState.swift` 第 13–21 行），`CoachState.empty()` 里默认就是 `recordingEnabled: false, recordingConsentAt: ""`。本任务不改模型，只加围绕它的判定逻辑。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/RecordingConsentTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class RecordingConsentTests: XCTestCase {
    private let t1 = "2026-08-06T10:00:00Z"
    private let t2 = "2026-08-20T21:30:00Z"

    // MARK: - 默认关

    /// 产品决策：录音默认关闭（ROADMAP 第 5 节、spec 第 7 节）。
    /// 涉及麦克风权限与磁盘占用的东西，必须用户明确开启才做。
    func testRecordingIsOffOnAFreshInstall() {
        let settings = CoachState.empty().settings
        XCTAssertFalse(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, "")
        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted),
                       .disabledByUser)
    }

    // MARK: - 同意时间戳

    func testEnableRecordsWhenTheUserAgreed() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        XCTAssertTrue(settings.recordingEnabled)
        XCTAssertEqual(settings.recordingConsentAt, t1)
    }

    /// 同意是一次性的事实，不该因为界面重绘、重复点击而被刷新成「刚刚同意」。
    func testEnablingAgainKeepsTheOriginalConsentTime() {
        let once = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let twice = RecordingConsent.enable(once, at: t2)
        XCTAssertEqual(twice.recordingConsentAt, t1)
    }

    /// 关掉开关等于撤回同意。留着旧时间戳的话，state.json 里会存着一条
    /// 「用户其实已经反悔」的同意记录——这是隐私相关的记录，不能含糊。
    func testDisableClearsTheConsentTime() {
        let enabled = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let disabled = RecordingConsent.disable(enabled)
        XCTAssertFalse(disabled.recordingEnabled)
        XCTAssertEqual(disabled.recordingConsentAt, "")
    }

    func testTurningItBackOnRecordsTheNewTimeNotTheOldOne() {
        let first = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        let off = RecordingConsent.disable(first)
        let again = RecordingConsent.enable(off, at: t2)
        XCTAssertEqual(again.recordingConsentAt, t2)
    }

    // MARK: - 能不能录

    /// 开关是用户的意愿，权限是系统的许可。**开关关着时连问都不用问权限**——
    /// 顺序反过来的话，一个没开开关但授过权的用户会被判成「可以录」。
    func testTheSwitchBeatsThePermission() {
        var settings = CoachState.empty().settings
        settings.recordingEnabled = false
        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted),
                       .disabledByUser)
    }

    func testBlockedWithAnActionableMessageWhenPermissionIsMissing() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        guard case .blocked(let message) = RecordingConsent.readiness(settings: settings,
                                                                     permission: .denied) else {
            return XCTFail("开关开着但没权限时必须是 blocked，且要带一条能照着做的说明")
        }
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertTrue(message.contains("系统设置"))
    }

    /// 有人手工改过 state.json、或将来某个迁移写漏了，就会出现
    /// 「开关是开的、同意时间是空的」这种自相矛盾的状态。
    /// 这时候必须停下来问用户，而不是当成已经同意默默开录。
    func testEnabledWithoutAConsentTimeIsRefusedRatherThanAssumed() {
        var settings = CoachState.empty().settings
        settings.recordingEnabled = true
        settings.recordingConsentAt = ""
        guard case .blocked(let message) = RecordingConsent.readiness(settings: settings,
                                                                     permission: .granted) else {
            return XCTFail("没有同意记录就不能录")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testReadyWhenTheSwitchIsOnAndThePermissionIsGranted() {
        let settings = RecordingConsent.enable(CoachState.empty().settings, at: t1)
        XCTAssertEqual(RecordingConsent.readiness(settings: settings, permission: .granted), .ready)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RecordingConsentTests`
Expected: 编译失败 —— `RecordingConsent` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Recording/RecordingConsent.swift`：

```swift
import Foundation

/// 这次练习到底录不录。
public enum RecordingReadiness: Equatable, Sendable {
    case ready
    /// 用户没开开关。这是**默认状态，不是故障**——界面不该为此报警，
    /// 也不该显示「正在录音」的指示。
    case disabledByUser
    /// 开关开着却录不了。message 是中文，且写明了发生了什么与下一步做什么。
    /// 这种情况**必须让用户看见**：他以为在录，实际没录。
    case blocked(String)
}

/// 「保存我的回答录音」开关与同意时间戳的全部规则。纯函数，不做任何 IO。
public enum RecordingConsent {
    /// 打开开关并记下同意时间。已经打开且已有时间戳时原样返回——
    /// 同意是一次性的事实，不该被重复点击刷新成「刚刚同意」。
    ///
    /// **必须「复制后就地改两个字段」，绝不能用 `CoachSettings(recordingEnabled:recordingConsentAt:)`
    /// 重新构造一个。** `CoachSettings` 后续阶段还会加字段（Phase 7 的 `weeklyGoal`、
    /// Phase 8 的 `defaultRoute` / `feedbackTiming` / `part2PrepMode`），而那些新参数都带默认值——
    /// 重新构造会**编译通过、测试全绿**，然后在用户每次拨动录音开关时把他的每周目标、
    /// 默认路线、反馈时机悄悄重置回默认值。这正是本项目最忌讳的失败形态：不报错、不崩溃、
    /// 只是设置自己变回去了。
    public static func enable(_ settings: CoachSettings, at timestamp: String) -> CoachSettings {
        if settings.recordingEnabled && !settings.recordingConsentAt.isEmpty { return settings }
        var updated = settings
        updated.recordingEnabled = true
        updated.recordingConsentAt = timestamp
        return updated
    }

    /// 关掉开关并清空同意时间。关掉等于撤回同意，下次再开必须重新记一次。
    /// 同样只改这两个字段，其余设置原样保留（理由见 `enable` 上面那段注释）。
    public static func disable(_ settings: CoachSettings) -> CoachSettings {
        var updated = settings
        updated.recordingEnabled = false
        updated.recordingConsentAt = ""
        return updated
    }

    /// 顺序有意义：**先看开关，再看权限，最后看同意记录。**
    /// 开关关着时连问都不用问权限——那是用户的意愿，压过一切。
    public static func readiness(settings: CoachSettings,
                                 permission: MicrophonePermissionState) -> RecordingReadiness {
        guard settings.recordingEnabled else { return .disabledByUser }
        guard permission == .granted else {
            return .blocked(permission.guidance
                ?? "麦克风权限状态未知，这次不会录音。"
                 + "下一步：到「录音设置」（⌘,）把开关关掉再打开一次。")
        }
        guard !settings.recordingConsentAt.isEmpty else {
            return .blocked("录音开关是开的，但没有记录到你同意的时间，为稳妥起见这次不录音。"
                + "下一步：到「录音设置」（⌘,）把开关关掉再打开一次，就会重新记一次同意时间。")
        }
        return .ready
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RecordingConsentTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A：** 把 `disable` 改成只关开关、保留时间戳：

```swift
    public static func disable(_ settings: CoachSettings) -> CoachSettings {
        var updated = settings
        updated.recordingEnabled = false
        return updated                 // 少了 updated.recordingConsentAt = ""
    }
```

Run: `swift test --filter RecordingConsentTests`
Expected: `testDisableClearsTheConsentTime` 与 `testTurningItBackOnRecordsTheNewTimeNotTheOldOne` **两条变红**

**突变 B：** 把 `readiness` 里的前两个 guard 对调（先看权限再看开关）：

Run: `swift test --filter RecordingConsentTests`
Expected: `testTheSwitchBeatsThePermission` **变红**

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachCore/Recording/RecordingConsent.swift \
        Tests/IELTSCoachCoreTests/RecordingConsentTests.swift
git commit -m "feat(core): 录音开关与同意时间戳"
```

---

## Task 3: 录音文件的命名、列举、占用与删除

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachCore/Recording/RecordingStore.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachCoreTests/RecordingStoreTests.swift`

**Interfaces:**
- Consumes: `DataDirectory`（既有类型，`recordingsDirectory: URL`、`createIfNeeded() throws`）
- Produces:
  - `public struct RecordingUsage: Equatable, Sendable { let count: Int; let bytes: Int64 }`，含 `static func humanReadable(bytes: Int64) -> String`、`static let noticeThreshold: Int64`、`var summaryText: String`
  - `public enum RecordingStoreError: Error, Equatable, LocalizedError { case unsafePath(String); case deleteFailed(String) }`
  - `public struct RecordingStore: Sendable`，含
    - `init(directory: DataDirectory)`
    - `static let fileExtension: String`（`"m4a"`）、`static let relativePrefix: String`（`"recordings/"`）
    - `static func fileName(startedAt: Date, taken: Set<String>) -> String`
    - `func relativePath(fileName: String) -> String`
    - `func url(forRelativePath path: String) throws -> URL`
    - `func fileExists(relativePath: String) -> Bool`
    - `func existingFileNames() throws -> [String]`
    - `func delete(relativePath: String) throws`
    - `func usage() throws -> RecordingUsage`
    - `func orphanFileNames(referencedPaths: [String]) throws -> [String]`

**这里为什么要防路径穿越：** `recordingPath` 是从 `state.json` 里读出来的字符串。那个文件用户能手工改、将来的迁移脚本能写、Windows 版也能写。一旦出现 `"recordings/../../../state.json"`，「删掉这条录音」就会删掉用户的全部训练数据。**挡住它的成本是三行，不挡的代价是用户的全部记录。**

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/RecordingStoreTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class RecordingStoreTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: RecordingStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    /// 造一个占位录音文件。内容是什么无所谓，这一层只管路径与字节数。
    @discardableResult
    private func makeFile(_ name: String, bytes: Int) throws -> URL {
        let url = directory.recordingsDirectory.appending(path: name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: - 命名

    /// 按练习开始的时刻命名，UTC，文件名安全（不含冒号——冒号在 Finder 里会被显示成斜杠）。
    func testFileNameIsTheStartInstantInUTC() {
        // 1785931530 = 2026-08-06T10:45:30Z
        let name = RecordingStore.fileName(startedAt: Date(timeIntervalSince1970: 1_785_931_530),
                                           taken: [])
        XCTAssertEqual(name, "2026-08-06T10-45-30Z.m4a")
        XCTAssertFalse(name.contains(":"), "冒号在 Finder 里会显示成斜杠，别用")
    }

    /// 同一秒里开了两场（重开、崩溃后立刻重来）不能互相覆盖——
    /// 覆盖掉的是上一场已经录好的内容。
    func testFileNameAvoidsOverwritingAnExistingRecording() {
        let taken: Set<String> = ["2026-08-06T10-45-30Z.m4a"]
        XCTAssertEqual(
            RecordingStore.fileName(startedAt: Date(timeIntervalSince1970: 1_785_931_530), taken: taken),
            "2026-08-06T10-45-30Z-2.m4a")

        let takenTwice = taken.union(["2026-08-06T10-45-30Z-2.m4a"])
        XCTAssertEqual(
            RecordingStore.fileName(startedAt: Date(timeIntervalSince1970: 1_785_931_530), taken: takenTwice),
            "2026-08-06T10-45-30Z-3.m4a")
    }

    // MARK: - 路径安全

    /// state.json 里的 recordingPath 是可以被手工改坏的。
    /// 一个 "recordings/../state.json" 就能让「删掉这条录音」删掉全部训练数据。
    func testRefusesPathsThatEscapeTheRecordingsDirectory() {
        for evil in ["recordings/../state.json", "recordings/..", "recordings/a/b.m4a"] {
            XCTAssertThrowsError(try store.url(forRelativePath: evil), "\(evil) 应当被拒绝") { error in
                XCTAssertTrue("\(error)".contains("下一步"), "拒绝也要告诉用户下一步做什么")
            }
        }
    }

    func testRefusesPathsOutsideTheRecordingsPrefix() {
        for evil in ["state.json", "/etc/passwd", "reports/x.json", ""] {
            XCTAssertThrowsError(try store.url(forRelativePath: evil), "\(evil) 应当被拒绝")
        }
    }

    func testAcceptsANormalRecordingPath() throws {
        let url = try store.url(forRelativePath: "recordings/2026-08-06T10-45-30Z.m4a")
        XCTAssertEqual(url.lastPathComponent, "2026-08-06T10-45-30Z.m4a")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       directory.recordingsDirectory.standardizedFileURL)
    }

    // MARK: - 删除

    func testDeleteRemovesOnlyTheTargetFile() throws {
        try makeFile("a.m4a", bytes: 10)
        try makeFile("b.m4a", bytes: 10)

        try store.delete(relativePath: "recordings/a.m4a")

        XCTAssertFalse(store.fileExists(relativePath: "recordings/a.m4a"))
        XCTAssertTrue(store.fileExists(relativePath: "recordings/b.m4a"))
    }

    /// 用户要的是「这条录音没了」。文件早就没了同样满足这个要求，
    /// 这时候报错只会让人以为没删掉，然后反复去点。
    func testDeleteIsFineWhenTheFileIsAlreadyGone() {
        XCTAssertNoThrow(try store.delete(relativePath: "recordings/never-existed.m4a"))
    }

    // MARK: - 占用

    func testUsageCountsOnlyRecordingsAndSumsTheirSize() throws {
        try makeFile("a.m4a", bytes: 10)
        try makeFile("b.m4a", bytes: 20)
        try makeFile("notes.txt", bytes: 5_000)   // 不是录音，不该数进去

        let usage = try store.usage()
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.bytes, 30)
    }

    func testUsageOnAnEmptyDirectory() throws {
        let usage = try store.usage()
        XCTAssertEqual(usage.count, 0)
        XCTAssertEqual(usage.bytes, 0)
    }

    /// 刻意不用 ByteCountFormatter：它的输出随系统语言和版本变化，
    /// 断言会在别人的机器上莫名其妙地红。
    func testHumanReadableSizesAreStable() {
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 512), "0.5 KB")
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 36_175_872), "34.5 MB")
        XCTAssertEqual(RecordingUsage.humanReadable(bytes: 2_147_483_648), "2.00 GB")
    }

    func testEmptyUsageTellsTheUserWhatWouldShowUpHere() {
        let text = RecordingUsage(count: 0, bytes: 0).summaryText
        XCTAssertTrue(text.contains("还没有录音"))
    }

    /// 占用不大时不啰嗦；大到该清理时必须给出怎么清。
    func testLargeUsageTellsTheUserHowToCleanUp() {
        let small = RecordingUsage(count: 3, bytes: 30_000_000).summaryText
        XCTAssertTrue(small.contains("3 个"))
        XCTAssertFalse(small.contains("下一步"), "占用不大时不该催人清理")

        let large = RecordingUsage(count: 900, bytes: RecordingUsage.noticeThreshold).summaryText
        XCTAssertTrue(large.contains("下一步"))
    }

    // MARK: - 孤儿

    /// 练习中途崩溃会在磁盘上留下没有任何训练记录指向的录音。
    /// **不主动删**——用户的录音只有用户能决定删不删，但必须让他知道它们占着地方。
    func testOrphansAreRecordingsNoSessionPointsAt() throws {
        try makeFile("kept.m4a", bytes: 10)
        try makeFile("orphan.m4a", bytes: 10)

        let orphans = try store.orphanFileNames(
            referencedPaths: ["recordings/kept.m4a", "", "recordings/already-deleted.m4a"])
        XCTAssertEqual(orphans, ["orphan.m4a"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RecordingStoreTests`
Expected: 编译失败 —— `RecordingStore` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Recording/RecordingStore.swift`：

```swift
import Foundation

/// 录音目录的占用情况。
public struct RecordingUsage: Equatable, Sendable {
    public let count: Int
    public let bytes: Int64

    public init(count: Int, bytes: Int64) { self.count = count; self.bytes = bytes }

    /// 超过这个值就在提示里追加「怎么清理」。
    /// 1 GB 按 64 kbps 单声道算大约是 37 小时的练习，正常用一年也到不了；
    /// 到了就说明该清了。
    public static let noticeThreshold: Int64 = 1_073_741_824

    /// 刻意不用 ByteCountFormatter：它的输出随系统语言与版本变化，
    /// 断言会在别人的机器上莫名其妙地红。自己算，结果确定。
    public static func humanReadable(bytes: Int64) -> String {
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024
        let value = Double(bytes)
        if value < mb { return String(format: "%.1f KB", value / kb) }
        if value < gb { return String(format: "%.1f MB", value / mb) }
        return String(format: "%.2f GB", value / gb)
    }

    public var summaryText: String {
        guard count > 0 else {
            return "还没有录音。开启「保存我的回答录音」之后，你练习时说的话会存在这里。"
        }
        var text = "录音 \(count) 个，共占用 \(Self.humanReadable(bytes: bytes))。"
        if bytes >= Self.noticeThreshold {
            text += "下一步：到「训练记录」页把不再需要的录音逐条删掉。"
        }
        return text
    }
}

public enum RecordingStoreError: Error, Equatable, LocalizedError {
    case unsafePath(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let m), .deleteFailed(let m): return m
        }
    }
}

/// `recordings/` 目录的全部操作：命名、列举、占用、删除、孤儿检测。
/// 只依赖 Foundation（FileManager 属于 Foundation），因此留在 Core 里。
public struct RecordingStore: Sendable {
    public static let fileExtension = "m4a"
    public static let relativePrefix = "recordings/"

    public let directory: DataDirectory

    public init(directory: DataDirectory) { self.directory = directory }

    /// 用「练习开始的时刻」命名，不用 PracticeSession.id。
    ///
    /// 会话 id 是练完归档时才分配的，而录音在那之前十几分钟就已经在写了。
    /// 若坚持用会话 id 命名，录音就得先写成临时名、事后改名，而「改名那一步失败」
    /// 会让一整场练习的录音凭空消失——正是成品标准第 7 条最不能接受的形态。
    /// 按开始时刻命名，文件从第一秒起就在它最终该在的位置上。
    public static func fileName(startedAt: Date, taken: Set<String>) -> String {
        let formatter = DateFormatter()
        // 三行都不能省：locale 不定死会在中文/佛历等区域设置下出别的年份，
        // timeZone 不定死会让同一场练习在不同机器上叫不同名字。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"

        let stamp = formatter.string(from: startedAt)
        var candidate = "\(stamp).\(fileExtension)"
        var suffix = 2
        // 同一秒里重开一场时不能覆盖上一场——覆盖掉的是已经录好的内容。
        while taken.contains(candidate) {
            candidate = "\(stamp)-\(suffix).\(fileExtension)"
            suffix += 1
        }
        return candidate
    }

    public func relativePath(fileName: String) -> String { Self.relativePrefix + fileName }

    /// 把 state.json 里存的相对路径变成真实 URL，并挡掉危险路径。
    ///
    /// **不挡的代价：** recordingPath 是可以被手工改坏的字符串，
    /// 一个 "recordings/../state.json" 就能让「删掉这条录音」删掉用户的全部训练数据。
    public func url(forRelativePath path: String) throws -> URL {
        guard path.hasPrefix(Self.relativePrefix) else {
            throw RecordingStoreError.unsafePath(
                "录音路径「\(path)」不在 recordings 目录下，已拒绝操作，什么都没动。"
                + "下一步：这条训练记录的录音路径可能被改坏了；"
                + "打开数据目录里的 state.json，检查这一条的 recordingPath 字段。")
        }
        let name = String(path.dropFirst(Self.relativePrefix.count))
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw RecordingStoreError.unsafePath(
                "录音路径「\(path)」不是一个合法的文件名，已拒绝操作，什么都没动。"
                + "下一步：打开数据目录里的 state.json，检查这一条的 recordingPath 字段。")
        }
        return directory.recordingsDirectory.appending(path: name)
    }

    public func fileExists(relativePath: String) -> Bool {
        guard let url = try? url(forRelativePath: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func existingFileNames() throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.recordingsDirectory.path) else { return [] }
        return try manager.contentsOfDirectory(atPath: directory.recordingsDirectory.path)
            .filter { $0.hasSuffix(".\(Self.fileExtension)") }
            .sorted()
    }

    /// 删除一条录音。文件本来就不在时不报错——用户要的是「这条录音没了」，
    /// 文件早就没了同样满足；报错只会让人以为没删掉然后反复去点。
    public func delete(relativePath: String) throws {
        let url = try url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw RecordingStoreError.deleteFailed(
                "删不掉录音文件 \(url.path)：\(error.localizedDescription)。"
                + "下一步：确认这个文件没有正在被播放或被别的程序打开，然后再点一次删除。")
        }
    }

    public func usage() throws -> RecordingUsage {
        let names = try existingFileNames()
        var total: Int64 = 0
        for name in names {
            let url = directory.recordingsDirectory.appending(path: name)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += Int64(size ?? 0)
        }
        return RecordingUsage(count: names.count, bytes: total)
    }

    /// 磁盘上有、但没有任何训练记录指向它的录音。多半是练习中途崩溃留下的。
    /// **不主动删**——用户的录音只有用户能决定删不删，但必须让他知道它们占着地方。
    public func orphanFileNames(referencedPaths: [String]) throws -> [String] {
        let referenced = Set(referencedPaths.compactMap { path -> String? in
            guard path.hasPrefix(Self.relativePrefix) else { return nil }
            return String(path.dropFirst(Self.relativePrefix.count))
        })
        return try existingFileNames().filter { !referenced.contains($0) }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RecordingStoreTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（路径穿越）：** 把 `url(forRelativePath:)` 的整个函数体换成

```swift
        return directory.recordingsDirectory.appending(path: path)
```

Run: `swift test --filter RecordingStoreTests`
Expected: `testRefusesPathsThatEscapeTheRecordingsDirectory` 与 `testRefusesPathsOutsideTheRecordingsPrefix` **两条变红**

**突变 B（覆盖已有录音）：** 把 `fileName(startedAt:taken:)` 里的 `while` 循环整段删掉，直接 `return "\(stamp).\(fileExtension)"`：

Run: `swift test --filter RecordingStoreTests`
Expected: `testFileNameAvoidsOverwritingAnExistingRecording` **变红**

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachCore/Recording/RecordingStore.swift \
        Tests/IELTSCoachCoreTests/RecordingStoreTests.swift
git commit -m "feat(core): 录音文件的命名、占用统计与安全删除"
```

---

## Task 4: 录音编排 `RecordingSession`（插拔耳机不丢录音）

**这是本阶段风险最高的一个任务。** ROADMAP 第 6 节把「音频权限与设备切换（插拔耳机）的处理」列为 Phase 5 的风险，而「插拔耳机时不能静默丢掉录音」正是「禁止静默失败」这条硬约束在本阶段的具体形态。

**为什么会丢：** `AVAudioEngine` 在音频输入设备变化时（插拔耳机、切换声卡、蓝牙断连）会发出 `AVAudioEngineConfigurationChange` 通知，**并且引擎会停下来，输入节点的格式会变**。此时之前装的 tap 已经失效。若代码不做任何处理，后面用户说的每一句话都录不到，而且**不会抛任何错误**——用户练完点开回听，只有前三分钟。这正是「静默失败」最典型的样子。

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/RecordingEngineError.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/AudioCaptureEngine.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/RecordingSession.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachAudioTests/FakeAudioCapture.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachAudioTests/RecordingSessionTests.swift`

**Interfaces:**
- Consumes: `AVAudioPCMBuffer`（只当不透明的音频数据传递，不解释内容）
- Produces:
  - `public enum RecordingEngineError: Error, Equatable, LocalizedError { case noInputDevice(String); case engineStartFailed(String); case formatUnsupported(String); case writeFailed(String) }`
  - `public protocol AudioCaptureEngine: AnyObject { var onConfigurationChange: (@Sendable () -> Void)? { get set }; func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws; func stop() }`
  - `public protocol AudioSegmentWriter: AnyObject { func write(_ buffer: AVAudioPCMBuffer) throws; @discardableResult func finish() -> TimeInterval }`
  - `public struct RecordingInterruption: Equatable, Sendable { let at: Date; let recovered: Bool }`
  - `public struct RecordingOutcome: Equatable, Sendable { let relativePath: String; let duration: TimeInterval; let interruptions: [RecordingInterruption]; let warning: String? }`
  - `public final class RecordingSession`，含 `typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter`、`init(engine:writerFactory:fileURL:relativePath:clock:)`、`func start() throws`、`func finish() -> RecordingOutcome`

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachAudioTests/FakeAudioCapture.swift`：

```swift
import AVFoundation
import Foundation
@testable import IELTSCoachAudio

/// 可编程的假麦克风。
///
/// 有了它，「插拔耳机」这条路径可以在没有麦克风、没有权限、也不用真去拔线的
/// 情况下完整测到——这正是把 AVAudioEngine 藏在 protocol 后面的全部理由。
final class FakeCaptureEngine: AudioCaptureEngine, @unchecked Sendable {
    var onConfigurationChange: (@Sendable () -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// 第几次调用 start 要抛错（1 表示第一次）。nil 表示每次都成功。
    var failStartAtCall: Int?

    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        startCount += 1
        if failStartAtCall == startCount {
            throw RecordingEngineError.engineStartFailed("测试用的启动失败。下一步：这是测试。")
        }
        sink = onBuffer
    }

    func stop() { stopCount += 1; sink = nil }

    /// 模拟麦克风送来一段音频。
    func deliver(_ buffer: AVAudioPCMBuffer) { sink?(buffer) }

    /// 模拟用户插拔耳机 / 切换声卡。
    func unplugHeadphones() { onConfigurationChange?() }
}

final class FakeSegmentWriter: AudioSegmentWriter, @unchecked Sendable {
    private(set) var writtenCount = 0
    private(set) var finishCount = 0
    var failOnWrite = false
    /// finish() 报告的时长。设成 0 就是「一秒都没录到」。
    var secondsToReport: TimeInterval = 12

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if failOnWrite {
            throw RecordingEngineError.writeFailed("测试用的写入失败。下一步：这是测试。")
        }
        writtenCount += 1
    }

    func finish() -> TimeInterval { finishCount += 1; return secondsToReport }
}

/// 造一段音频数据。内容是什么无所谓——编排层只是把它转手交给写入器。
func makePCMBuffer(sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
    buffer.frameLength = 1_024
    return buffer
}
```

`Tests/IELTSCoachAudioTests/RecordingSessionTests.swift`：

```swift
import AVFoundation
import XCTest
@testable import IELTSCoachAudio

final class RecordingSessionTests: XCTestCase {
    private let relativePath = "recordings/2026-08-06T10-45-30Z.m4a"
    private var root: URL!
    private var fileURL: URL!
    private var engine: FakeCaptureEngine!
    private var writer: FakeSegmentWriter!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "2026-08-06T10-45-30Z.m4a")
        engine = FakeCaptureEngine()
        writer = FakeSegmentWriter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession() -> RecordingSession {
        let writer = self.writer!
        return RecordingSession(
            engine: engine,
            // 真实的写入器会在这里建出文件，假的也要建——
            // 否则「0 秒录音要把空文件删掉」那条根本测不到。
            writerFactory: { url in
                FileManager.default.createFile(atPath: url.path, contents: Data())
                return writer
            },
            fileURL: fileURL,
            relativePath: relativePath,
            clock: { Date(timeIntervalSince1970: 1_785_931_530) })
    }

    // MARK: - 正常路径

    func testBuffersReachTheWriter() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        engine.deliver(makePCMBuffer())
        XCTAssertEqual(writer.writtenCount, 2)
    }

    func testFinishReturnsThePathAndDuration() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, relativePath)
        XCTAssertEqual(outcome.duration, 12)
        XCTAssertNil(outcome.warning, "一切正常时不该拿警告去打扰用户")
        XCTAssertTrue(outcome.interruptions.isEmpty)
        XCTAssertEqual(writer.finishCount, 1)
    }

    // MARK: - 插拔耳机（本阶段的核心风险）

    /// 换了输入设备之后必须重新启动采集。
    /// 不重启的话，后面用户说的每一句都录不到，而且不会抛任何错误——
    /// 用户练完点开回听，只有前三分钟。
    func testUnpluggingHeadphonesRestartsCaptureAndKeepsTheSameFile() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer(sampleRate: 48_000))

        engine.unplugHeadphones()
        engine.deliver(makePCMBuffer(sampleRate: 44_100))   // 新设备的采样率变了

        XCTAssertEqual(engine.startCount, 2, "换设备后必须重新启动采集")
        XCTAssertEqual(writer.writtenCount, 2, "换设备之后送来的音频也要写进去")
        XCTAssertEqual(writer.finishCount, 0, "能接回来就不该关文件——换设备不该换文件")
    }

    /// 接回来了也**必须**告诉用户：切换的那一两秒确实没录到。
    /// 「悄悄少了一段」同样是静默失败——用户回听时会以为自己当时没说话。
    func testRecoveredInterruptionIsStillReportedToTheUser() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())
        engine.unplugHeadphones()
        engine.deliver(makePCMBuffer())

        let outcome = session.finish()
        XCTAssertEqual(outcome.interruptions.count, 1)
        XCTAssertTrue(outcome.interruptions[0].recovered)
        let warning = try XCTUnwrap(outcome.warning, "中断过却什么都不说，用户永远不知道少了一段")
        XCTAssertTrue(warning.contains("耳机"), "要说人话，用户能对上号的是「插拔耳机」")
        XCTAssertTrue(warning.contains("下一步"))
        XCTAssertEqual(outcome.relativePath, relativePath, "接上了就还是同一条录音")
    }

    /// 接不回来时，**已经录到的部分必须当场落盘**。
    /// 练了半小时换来的录音，不能跟着一个错误一起蒸发。
    func testFailedRecoveryClosesTheFileSoAudioSoFarSurvives() throws {
        engine.failStartAtCall = 2      // 第一次 start 成功，重启时失败
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        engine.unplugHeadphones()

        XCTAssertEqual(writer.finishCount, 1,
                       "接不回来就要立刻把文件关好，而不是等着跟错误一起丢掉")

        let outcome = session.finish()
        XCTAssertEqual(writer.finishCount, 1, "文件不能被关第二次")
        XCTAssertEqual(outcome.relativePath, relativePath, "录到一半也是录音，路径必须给出来")
        XCTAssertEqual(outcome.duration, 12)
        XCTAssertEqual(outcome.interruptions.count, 1)
        XCTAssertFalse(outcome.interruptions[0].recovered)
        let warning = try XCTUnwrap(outcome.warning)
        XCTAssertTrue(warning.contains("下一步"))
    }

    // MARK: - 其他失败

    func testWriteFailureStopsRecordingButKeepsWhatWasWritten() throws {
        let session = makeSession()
        try session.start()
        writer.failOnWrite = true
        engine.deliver(makePCMBuffer())

        XCTAssertEqual(writer.finishCount, 1, "写失败也要先把文件关好再说")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1, "写不进去了就别再采了")

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, relativePath)
        XCTAssertTrue(try XCTUnwrap(outcome.warning).contains("下一步"))
    }

    func testStartFailureDoesNotLeaveAnOpenFile() {
        engine.failStartAtCall = 1
        let session = makeSession()
        XCTAssertThrowsError(try session.start())
        XCTAssertEqual(writer.finishCount, 1,
                       "采集起不来时要把刚建出来的文件关掉，否则 recordings 里会留一个孤儿")
    }

    /// 一秒都没录到时不能给出一个「看起来有录音」的路径——
    /// 那会让训练记录页显示一个点了没声音的播放器，用户只会以为程序坏了。
    func testSilentRecordingReportsItInsteadOfHandingBackAnEmptyFile() throws {
        writer.secondsToReport = 0
        let session = makeSession()
        try session.start()

        let outcome = session.finish()
        XCTAssertEqual(outcome.relativePath, "")
        XCTAssertTrue(try XCTUnwrap(outcome.warning).contains("下一步"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "0 秒的空文件不该留在 recordings 里占位置")
    }

    func testFinishIsIdempotent() throws {
        let session = makeSession()
        try session.start()
        engine.deliver(makePCMBuffer())

        let first = session.finish()
        let second = session.finish()
        XCTAssertEqual(first, second)
        XCTAssertEqual(writer.finishCount, 1, "重复调用 finish 不能把文件关两次")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RecordingSessionTests`
Expected: 编译失败 —— `RecordingSession`、`AudioCaptureEngine` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachAudio/RecordingEngineError.swift`：

```swift
import Foundation

/// 录音相关的全部错误。message 必须是中文，且同时说明发生了什么与下一步做什么。
public enum RecordingEngineError: Error, Equatable, LocalizedError {
    case noInputDevice(String)
    case engineStartFailed(String)
    case formatUnsupported(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noInputDevice(let m), .engineStartFailed(let m),
             .formatUnsupported(let m), .writeFailed(let m):
            return m
        }
    }
}
```

`Sources/IELTSCoachAudio/AudioCaptureEngine.swift`：

```swift
import AVFoundation
import Foundation

/// 麦克风采集的抽象。真实实现是 `AVAudioEngineCapture`；测试里用假实现。
///
/// **实现方在设备变化时只负责「报告」，不得自作主张重启。** 重启与否、重启失败
/// 怎么办、要不要告诉用户，全部由 `RecordingSession` 决定——那一段逻辑必须可测，
/// 藏进真实实现里就再也测不到了。
public protocol AudioCaptureEngine: AnyObject {
    /// 输入设备发生变化（插拔耳机、切换声卡、蓝牙断连）时被调用。
    var onConfigurationChange: (@Sendable () -> Void)? { get set }

    /// 开始采集。每采到一段音频就调用一次 onBuffer。
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws

    /// 停止采集。允许在没 start 过的时候调用，必须是无害的。
    func stop()
}

/// 一个正在写入的录音文件。
public protocol AudioSegmentWriter: AnyObject {
    /// 把一段麦克风音频写进文件。
    ///
    /// **输入格式与上一段不同时（用户换了设备），实现方必须自己重建转换器
    /// 继续往同一个文件里写，而不是抛错。** 换设备不该换文件，更不该丢录音。
    func write(_ buffer: AVAudioPCMBuffer) throws

    /// 关掉文件并返回已写入的秒数。重复调用只有第一次真的关文件，
    /// 但每次都要返回同一个时长。
    @discardableResult
    func finish() -> TimeInterval
}
```

`Sources/IELTSCoachAudio/RecordingSession.swift`：

```swift
import AVFoundation
import Foundation

/// 录音中途的一次中断（换了音频输入设备）。
public struct RecordingInterruption: Equatable, Sendable {
    public let at: Date
    /// 是否自动接上了。**接上了也必须告诉用户**——切换的那一两秒确实没录到。
    public let recovered: Bool

    public init(at: Date, recovered: Bool) { self.at = at; self.recovered = recovered }
}

public struct RecordingOutcome: Equatable, Sendable {
    /// 相对数据目录的路径，例如 "recordings/2026-08-06T10-45-30Z.m4a"。
    /// **一秒都没录到时是空字符串**——给一个指向空文件的路径，
    /// 只会让训练记录页显示一个点了没声音的播放器。
    public let relativePath: String
    public let duration: TimeInterval
    public let interruptions: [RecordingInterruption]
    /// 非 nil 时界面**必须**显示。中文，写明发生了什么与下一步做什么。
    public let warning: String?

    public init(relativePath: String, duration: TimeInterval,
                interruptions: [RecordingInterruption], warning: String?) {
        self.relativePath = relativePath; self.duration = duration
        self.interruptions = interruptions; self.warning = warning
    }
}

/// 一次练习的录音编排：启动采集、把音频交给写入器、处理设备切换、收尾。
///
/// 只依赖 `AudioCaptureEngine` 与 `AudioSegmentWriter` 两个 protocol，
/// 因此整条逻辑（含插拔耳机）可以用假实现完整测试，不碰任何硬件。
public final class RecordingSession: @unchecked Sendable {
    public typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter

    private let engine: AudioCaptureEngine
    private let writerFactory: WriterFactory
    private let fileURL: URL
    private let relativePath: String
    private let clock: @Sendable () -> Date

    // 音频回调来自另一条线程，下面这些状态一律用锁保护。
    private let lock = NSLock()
    private var writer: AudioSegmentWriter?
    private var interruptions: [RecordingInterruption] = []
    private var warnings: [String] = []
    private var duration: TimeInterval = 0
    /// 文件是否已经关掉了（不管是正常收尾还是出错收尾）。
    private var closed = false

    public init(engine: AudioCaptureEngine,
                writerFactory: @escaping WriterFactory,
                fileURL: URL,
                relativePath: String,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.writerFactory = writerFactory
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.clock = clock
    }

    public func start() throws {
        let made = try writerFactory(fileURL)
        lock.lock(); writer = made; lock.unlock()

        engine.onConfigurationChange = { [weak self] in self?.handleConfigurationChange() }
        do {
            try engine.start(onBuffer: { [weak self] buffer in self?.append(buffer) })
        } catch {
            // 采集起不来也要把刚建出来的文件关掉，否则 recordings/ 里会留下一个
            // 0 字节的孤儿文件，下次算占用时还会被数进去、还会被当成孤儿报警。
            closeWriter()
            throw error
        }
    }

    public func finish() -> RecordingOutcome {
        engine.stop()
        engine.onConfigurationChange = nil
        closeWriter()

        lock.lock()
        var allWarnings = warnings
        let seconds = duration
        let capturedInterruptions = interruptions
        lock.unlock()

        let hasAudio = seconds > 0
        if !hasAudio {
            // 空文件不留：它占着 recordings 目录、会被算进占用、还会被当成孤儿报警，
            // 而里面一点声音都没有。删掉它，然后把「为什么没录到」说清楚。
            try? FileManager.default.removeItem(at: fileURL)
            allWarnings.append(
                "这次一秒录音都没录到，已经把空文件删掉了。"
                + "下一步：打开「系统设置 › 声音 › 输入」，确认选中的麦克风在你说话时有输入电平；"
                + "若暂时不需要录音，到「录音设置」（⌘,）把开关关掉，界面就不会再提这件事。")
        }

        return RecordingOutcome(
            relativePath: hasAudio ? relativePath : "",
            duration: seconds,
            interruptions: capturedInterruptions,
            warning: allWarnings.isEmpty ? nil : allWarnings.joined(separator: "\n"))
    }

    // MARK: - 私有

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let target = closed ? nil : writer
        lock.unlock()
        guard let target else { return }

        do {
            try target.write(buffer)
        } catch {
            // 写不进去就立刻收摊，但**必须先把文件正常关掉**——
            // 已经录下的部分是用户练了半小时换来的，不能跟着错误一起蒸发。
            engine.stop()
            closeWriter()
            lock.lock()
            warnings.append(
                "录音在中途写不下去了：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响。"
                + "下一步：确认磁盘还有空间，然后重新练一次。")
            lock.unlock()
        }
    }

    /// 输入设备变了（插拔耳机、切换声卡、蓝牙断连）。
    ///
    /// AVAudioEngine 此时已经停了，输入节点的格式也变了，之前装的 tap 失效。
    /// **不重新装 tap 再启动的话，后面一句话都录不到，而且不会抛任何错误。**
    private func handleConfigurationChange() {
        lock.lock()
        let stillRecording = !closed
        lock.unlock()
        guard stillRecording else { return }

        engine.stop()
        let at = clock()
        do {
            try engine.start(onBuffer: { [weak self] buffer in self?.append(buffer) })
            lock.lock()
            interruptions.append(RecordingInterruption(at: at, recovered: true))
            warnings.append(
                "录音中途因为音频输入设备变化（多半是插拔了耳机）断了一下，已经自动接上继续录，"
                + "切换的那一两秒没有录进去。"
                + "下一步：回听时留意这一小段；若刚好是关键回答，把这道题再练一次。")
            lock.unlock()
        } catch {
            // 接不回来就收尾。**先关文件再报错**：已经录到的部分必须留在磁盘上。
            closeWriter()
            lock.lock()
            interruptions.append(RecordingInterruption(at: at, recovered: false))
            warnings.append(
                "录音在中途停了，因为音频输入设备变了而且接不回来：\(error.localizedDescription)"
                + "\n已经录到的部分完整保存在 \(relativePath)，练习本身不受影响，可以接着练完。"
                + "下一步：把耳机插回去，或到「系统设置 › 声音 › 输入」重新选一个麦克风；"
                + "下一次练习会重新开始录。")
            lock.unlock()
        }
    }

    /// 关文件。重复调用只有第一次生效——文件不能被关两次。
    private func closeWriter() {
        lock.lock()
        guard !closed, let target = writer else { lock.unlock(); return }
        closed = true
        writer = nil
        lock.unlock()

        let seconds = target.finish()
        lock.lock(); duration = seconds; lock.unlock()
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RecordingSessionTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证（三处，都要做）**

**突变 A（本阶段最要紧的一条）：** 把 `handleConfigurationChange` 的 `catch` 分支里的 `closeWriter()` 那一行删掉：

Run: `swift test --filter RecordingSessionTests`
Expected: `testFailedRecoveryClosesTheFileSoAudioSoFarSurvives` **变红**（`writer.finishCount` 是 0 而不是 1）

守的就是「插拔耳机时不能静默丢掉录音」：接不回来时若不当场把文件关好，已经录下的内容就停在缓冲区里，用户什么都拿不到。

**突变 B（悄悄少一段）：** 把 `handleConfigurationChange` 的 `do` 分支里 `warnings.append(...)` 那一整段删掉（保留 `interruptions.append`）：

Run: `swift test --filter RecordingSessionTests`
Expected: `testRecoveredInterruptionIsStillReportedToTheUser` **变红**（`outcome.warning` 是 nil）

**突变 C（重启本身）：** 把 `handleConfigurationChange` 里 `try engine.start(onBuffer:...)` 那一行删掉，只留 `engine.stop()`：

Run: `swift test --filter RecordingSessionTests`
Expected: `testUnpluggingHeadphonesRestartsCaptureAndKeepsTheSameFile` **变红**（`engine.startCount` 是 1、`writer.writtenCount` 是 1）

三次都改回，重跑确认全绿。**把六次输出原样写进报告。**

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachAudio/RecordingEngineError.swift \
        Sources/IELTSCoachAudio/AudioCaptureEngine.swift \
        Sources/IELTSCoachAudio/RecordingSession.swift \
        Tests/IELTSCoachAudioTests/FakeAudioCapture.swift \
        Tests/IELTSCoachAudioTests/RecordingSessionTests.swift
git commit -m "feat(audio): 录音编排，插拔耳机时不丢录音"
```

---

## Task 5: 真实的采集与写入实现

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/AACSegmentWriter.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/AVAudioEngineCapture.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachAudioTests/AACSegmentWriterTests.swift`

**Interfaces:**
- Consumes: `AudioSegmentWriter`、`AudioCaptureEngine`、`RecordingEngineError`、`AVAudioFile`、`AVAudioConverter`、`AVAudioEngine`、`Notification.Name.AVAudioEngineConfigurationChange`
- Produces:
  - `public final class AACSegmentWriter: AudioSegmentWriter`，含 `init(url: URL) throws`、`static let sampleRate: Double`（44100）、`static let bitRate: Int`（64000）
  - `public final class AVAudioEngineCapture: AudioCaptureEngine`，含 `init()`

**两个实现，测试待遇完全不同，理由要说清楚：**

| 实现 | 碰硬件吗 | 单元测试 |
|---|---|---|
| `AACSegmentWriter` | **不碰**。它只吃 `AVAudioPCMBuffer`，音频从哪来它不管 | **必须测，而且要测到「输入格式中途变了」这条** |
| `AVAudioEngineCapture` | 碰。一调 `start()` 就打开真麦克风 | **不做单元测试**，靠 Task 11 的人工验收。测试里只允许调 `stop()`（它在没 start 过时不碰输入节点） |

**为什么输出格式必须写死：** 插拔耳机会让输入设备的采样率变掉（常见是 48000 ↔ 44100）。若按第一段输入的格式建文件，格式一变就写不进去，只能另起一个文件，回听时用户得自己拼两段。改成「输出格式写死、输入变了就重建转换器」之后，**换设备不换文件**，用户听到的是连续的一条。这条设计是 Task 4 那句「换设备不该换文件」在文件层的落实。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachAudioTests/AACSegmentWriterTests.swift`：

```swift
import AVFoundation
import XCTest
@testable import IELTSCoachAudio

/// 这些测试**不碰麦克风**：音频是代码里现造的正弦波。
/// 因此它们不需要任何权限，也不需要真的插着耳机去拔。
final class AACSegmentWriterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-aac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 造一段 440 Hz 正弦波。用真波形而不是静音，是为了让 AAC 编码器
    /// 真的有东西可编——全 0 的输入有可能被压成几乎不占空间的一段，
    /// 那样「文件里到底有没有声音」就测不出来了。
    private func tone(seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(2.0 * .pi * 440.0 * Double(index) / sampleRate)) * 0.25
        }
        return buffer
    }

    private func durationOfFile(at url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    func testWritesAPlayableFile() throws {
        let url = root.appending(path: "a.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 1.0, sampleRate: 48_000))
        let reported = writer.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // AAC 编码会加 priming 帧，长度不会分毫不差，给出容差。
        XCTAssertEqual(reported, 1.0, accuracy: 0.15)
        XCTAssertEqual(try durationOfFile(at: url), 1.0, accuracy: 0.25)
    }

    /// **这是「插拔耳机」在文件层的样子：输入采样率中途变了。**
    /// 变了还能接着往同一个文件里写，用户回听时才是连续的一条，
    /// 而不是两个半截文件。
    func testKeepsWritingIntoTheSameFileWhenTheInputFormatChanges() throws {
        let url = root.appending(path: "b.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.5, sampleRate: 48_000))
        try writer.write(tone(seconds: 0.5, sampleRate: 44_100))   // 换了设备
        let reported = writer.finish()

        XCTAssertEqual(reported, 1.0, accuracy: 0.15, "换设备前后的两段都要在同一个文件里")
        XCTAssertEqual(try durationOfFile(at: url), 1.0, accuracy: 0.25)
    }

    /// m4a 的索引（moov atom）是在文件对象释放时才写出去的。
    /// 不释放的话，播放器要么打不开这个文件，要么显示时长为 0。
    func testFileIsReadableImmediatelyAfterFinish() throws {
        let url = root.appending(path: "c.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.4, sampleRate: 48_000))
        _ = writer.finish()

        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testFinishTwiceReportsTheSameLengthAndDoesNotCorruptTheFile() throws {
        let url = root.appending(path: "d.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.4, sampleRate: 48_000))

        let first = writer.finish()
        let second = writer.finish()
        XCTAssertEqual(first, second)
        XCTAssertNoThrow(try AVAudioFile(forReading: url))
    }

    /// finish 之后再来的音频要安静地丢掉，不能崩。
    /// 真实场景：文件已经收尾了，音频线程上还有一两个缓冲区在路上。
    func testWritingAfterFinishIsHarmless() throws {
        let url = root.appending(path: "e.m4a")
        let writer = try AACSegmentWriter(url: url)
        try writer.write(tone(seconds: 0.2, sampleRate: 48_000))
        _ = writer.finish()
        XCTAssertNoThrow(try writer.write(tone(seconds: 0.2, sampleRate: 48_000)))
    }

    func testUnwritableLocationFailsWithAnActionableChineseMessage() {
        let url = URL(fileURLWithPath: "/System/definitely-not-writable/x.m4a")
        XCTAssertThrowsError(try AACSegmentWriter(url: url)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("下一步"), "建不了文件也要告诉用户下一步做什么")
        }
    }
}
```

**若 `AVAudioFile(forWriting:)` 在你的环境里直接抛错（AAC 编码器不可用），不要跳过这些测试，也不要改成断言「抛错是对的」。** 停下来报告：录音功能的整个前提就是这台机器能编 AAC，编不了的话本阶段没有意义。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AACSegmentWriterTests`
Expected: 编译失败 —— `AACSegmentWriter` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachAudio/AACSegmentWriter.swift`：

```swift
import AVFoundation
import Foundation

/// 把麦克风送来的 PCM 转成固定格式的 AAC，写进一个 .m4a 文件。
///
/// **为什么输出格式写死：** 练到一半插拔耳机，输入设备的采样率会变
/// （常见是 48000 ↔ 44100）。若按第一段输入的格式建文件，格式一变就写不进去，
/// 只能另起一个文件，回听时用户得自己拼。这里改成「输出格式写死、输入变了就
/// 重建转换器」，换设备不换文件，用户听到的是连续的一条。
public final class AACSegmentWriter: AudioSegmentWriter, @unchecked Sendable {
    /// 44.1 kHz 单声道 64 kbps：人声足够清楚，一小时约 28 MB。
    /// 练口语不需要立体声，也不需要更高码率——那只会让磁盘占用翻倍。
    public static let sampleRate: Double = 44_100
    public static let bitRate = 64_000

    private let outputFormat: AVAudioFormat
    /// 刻意是 var 且是 Optional：finish() 时必须把它置 nil。
    /// m4a 的索引（moov atom）在文件对象释放时才写出去，不释放的话
    /// 播放器要么打不开，要么显示时长为 0。
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var writtenFrames: AVAudioFramePosition = 0
    private let lock = NSLock()

    public init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate
        ]
        let opened: AVAudioFile
        do {
            opened = try AVAudioFile(forWriting: url, settings: settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw RecordingEngineError.writeFailed(
                "建不了录音文件 \(url.path)：\(error.localizedDescription)。这次不会录音，练习本身不受影响。"
                + "下一步：确认数据目录可写、磁盘还有空间，然后重新开始一次练习。")
        }
        self.file = opened
        self.outputFormat = opened.processingFormat
    }

    public func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        // 已经收尾了，音频线程上还在路上的缓冲区安静丢掉，不要崩。
        guard let file else { return }

        if converterInputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                throw RecordingEngineError.formatUnsupported(
                    "麦克风换成了本工具转换不了的音频格式"
                    + "（\(Int(buffer.format.sampleRate)) Hz，\(buffer.format.channelCount) 声道）。"
                    + "已经录到的部分不会丢。"
                    + "下一步：到「系统设置 › 声音 › 输入」换一个常见的麦克风，再练一次。")
            }
            converter = made
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        // 采样率变了之后输出帧数跟输入不是一比一，容量要按比例算，
        // 再多留 1024 帧给重采样滤波器的延迟。算少了会被截断，也就是丢音频。
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw RecordingEngineError.writeFailed(
                "内存不够，装不下转换后的音频。已经录到的部分不会丢。"
                + "下一步：关掉一些别的程序，然后重新开始一次练习。")
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            // 一次只喂一个缓冲区。喂完之后报 noDataNow，让转换器把手上的东西吐出来。
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw RecordingEngineError.writeFailed(
                "音频转换失败：\(conversionError?.localizedDescription ?? "未知原因")。"
                + "已经录到的部分不会丢。"
                + "下一步：重新开始一次练习；若反复出现，到「系统设置 › 声音 › 输入」换一个麦克风。")
        }

        guard output.frameLength > 0 else { return }
        try file.write(from: output)
        writtenFrames += AVAudioFramePosition(output.frameLength)
    }

    @discardableResult
    public func finish() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        // 这一行不能省：m4a 的索引在文件对象释放时才写出去。
        file = nil
        return Double(writtenFrames) / outputFormat.sampleRate
    }
}
```

`Sources/IELTSCoachAudio/AVAudioEngineCapture.swift`：

```swift
import AVFoundation
import Foundation

/// 真实的麦克风采集。**只录麦克风，不录任何系统音频**——
/// 录 ChatGPT 的声音需要「屏幕录制」权限，这个代价已经明确判定为不值
/// （DEFINITION-OF-DONE 第 4 节、ROADMAP 3.3）。考官问了什么由逐字稿给文字。
///
/// **本类不做单元测试。** 一调 start() 就打开真麦克风，而 `swift test` 跑的是
/// 没有 bundle id、没有 Info.plist 的命令行进程，调用会崩溃或挂住。
/// 它的正确性由 Task 11 的人工验收保证；编排逻辑的正确性由 RecordingSession 的
/// 单元测试保证——这正是把它藏在 protocol 后面的理由。
public final class AVAudioEngineCapture: AudioCaptureEngine, @unchecked Sendable {
    public var onConfigurationChange: (@Sendable () -> Void)?

    private let engine = AVAudioEngine()
    private var observer: (any NSObjectProtocol)?
    private var tapped = false

    public init() {}

    public func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        // 每次 start 都要重新读一次输入格式。拔了耳机之后格式会变，
        // 拿着旧格式去装 tap 会直接崩。
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingEngineError.noInputDevice(
                "系统现在没有可用的麦克风输入设备，这次不会录音，练习本身不受影响。"
                + "下一步：到「系统设置 › 声音 › 输入」里选一个麦克风，然后重新开始一次练习。")
        }

        if tapped { input.removeTap(onBus: 0); tapped = false }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        tapped = true

        if observer == nil {
            // 插拔耳机、切换声卡、蓝牙断连都会发这个通知，同时引擎会停下来。
            // 这里只负责报告，重启与否由 RecordingSession 决定——那段逻辑必须可测。
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                self?.onConfigurationChange?()
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapped = false
            throw RecordingEngineError.engineStartFailed(
                "打不开麦克风：\(error.localizedDescription)。这次不会录音，练习本身不受影响。"
                + "下一步：确认没有别的程序独占麦克风（视频会议、录屏工具常见），"
                + "再到「系统设置 › 隐私与安全性 › 麦克风」确认本应用是打开的。")
        }
    }

    /// 允许在没 start 过时调用，必须无害。注意此路径**不碰 inputNode**——
    /// 碰它会在没权限的进程里触发麦克风初始化。
    public func stop() {
        if engine.isRunning { engine.stop() }
        guard tapped else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapped = false
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if engine.isRunning { engine.stop() }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AACSegmentWriterTests`
Expected: PASS（6 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（换设备就断）：** 把 `write` 里那段「输入格式变了就重建转换器」改成只在没有转换器时才建，格式不同时直接抛错：

```swift
        if converter == nil {
            guard let made = AVAudioConverter(from: buffer.format, to: outputFormat) else { ... }
            converter = made
            converterInputFormat = buffer.format
        }
        guard converterInputFormat == buffer.format else {
            throw RecordingEngineError.formatUnsupported("输入格式变了。下一步：这是突变验证。")
        }
```

Run: `swift test --filter AACSegmentWriterTests`
Expected: `testKeepsWritingIntoTheSameFileWhenTheInputFormatChanges` **变红**

这一条守的就是「插拔耳机时不能静默丢掉录音」在文件层的实现：格式一变就写不进去，后半场全丢。

**突变 B（时长报假）：** 把 `finish()` 的返回值改成 `0`：

Run: `swift test --filter AACSegmentWriterTests`
Expected: `testWritesAPlayableFile` 与 `testKeepsWritingIntoTheSameFileWhenTheInputFormatChanges` **两条变红**

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

**额外一条（结果可能不红，如实记录即可）：** 把 `finish()` 里的 `file = nil` 删掉，重跑 `testFileIsReadableImmediatelyAfterFinish`。预期它变红（m4a 索引没写出去，读不出长度）。**若它仍是绿的，不要粉饰**——在报告里写明「该断言未能覆盖到 `file = nil` 这一行」，并把这个事实留给 Task 11 的人工验收（那时若播放器显示时长为 0，就知道该看这里）。

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachAudio/AACSegmentWriter.swift \
        Sources/IELTSCoachAudio/AVAudioEngineCapture.swift \
        Tests/IELTSCoachAudioTests/AACSegmentWriterTests.swift
git commit -m "feat(audio): AAC 写入器（换设备不换文件）与 AVAudioEngine 采集"
```

---

## Task 6: 把开关、权限与录音串起来 —— `PracticeRecordingCoordinator`

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachAudio/PracticeRecordingCoordinator.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachAudioTests/PracticeRecordingCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RecordingConsent.readiness(settings:permission:)`、`RecordingReadiness`、`RecordingStore`、`CoachSettings`、`MicrophonePermissionState`、`RecordingSession`、`AudioCaptureEngine`、`AudioSegmentWriter`、`AVAudioEngineCapture`、`AACSegmentWriter`
- Produces:
  - `public enum RecordingBeginOutcome: Equatable, Sendable { case started(relativePath: String); case skippedByUser; case failed(String) }`
  - `public protocol PracticeRecording: AnyObject { func begin(startedAt: Date) -> RecordingBeginOutcome; func finish() -> RecordingOutcome? }`
  - `public final class PracticeRecordingCoordinator: PracticeRecording`，含 `typealias EngineFactory = @Sendable () -> AudioCaptureEngine`、`typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter`、`init(store:settings:permission:engineFactory:writerFactory:)`

**这一层存在的意义是给 `PracticeRunner` 一个「不用懂音频」的接口。** `PracticeRunner` 只需要在开练时调一次 `begin`、在收尾时调一次 `finish`，它不需要知道什么是采样率、什么是转换器、用户有没有授权。

**三个返回值必须分得清清楚楚：**

| 返回值 | 什么情况 | 界面该怎么办 |
|---|---|---|
| `.started` | 真的在录 | 显示「● 正在录音」 |
| `.skippedByUser` | 开关关着（**默认状态**）| **什么都不显示**。这不是故障，为它报警会天天骚扰用户 |
| `.failed(message)` | 想录但录不了 | **必须显示 message**。用户以为在录，实际没录——不说就是骗人 |

把 `.failed` 混成 `.skippedByUser` 是本任务最容易犯、后果最严重的错误：用户开了开关、以为练完能回听，练完却什么都没有，且全程没有任何提示。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachAudioTests/PracticeRecordingCoordinatorTests.swift`：

```swift
import AVFoundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachAudio

final class PracticeRecordingCoordinatorTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: RecordingStore!
    private var engine: FakeCaptureEngine!
    private var writer: FakeSegmentWriter!
    private var enginesMade = 0

    private let startedAt = Date(timeIntervalSince1970: 1_785_931_530)   // 2026-08-06T10:45:30Z

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = RecordingStore(directory: directory)
        engine = FakeCaptureEngine()
        writer = FakeSegmentWriter()
        enginesMade = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func enabledSettings() -> CoachSettings {
        RecordingConsent.enable(CoachState.empty().settings, at: "2026-08-01T00:00:00Z")
    }

    private func makeCoordinator(settings: CoachSettings,
                                 permission: MicrophonePermissionState) -> PracticeRecordingCoordinator {
        let engine = self.engine!
        let writer = self.writer!
        return PracticeRecordingCoordinator(
            store: store,
            settings: settings,
            permission: permission,
            engineFactory: { [self] in enginesMade += 1; return engine },
            writerFactory: { url in
                FileManager.default.createFile(atPath: url.path, contents: Data())
                return writer
            })
    }

    /// 开关关着时**连麦克风都不碰**。碰了就会在系统的「最近使用麦克风」里
    /// 留下记录，而用户明明没开这个功能——这是隐私问题，不只是逻辑问题。
    func testDoesNotTouchTheMicrophoneWhenTheSwitchIsOff() {
        let coordinator = makeCoordinator(settings: CoachState.empty().settings, permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt), .skippedByUser)
        XCTAssertEqual(enginesMade, 0, "开关关着就不该造出采集器")
        XCTAssertEqual(engine.startCount, 0)
    }

    /// 开关开着但没权限，必须是 failed 并带一条能照着做的说明。
    /// **混成 skippedByUser 就是静默失败**：用户以为在录，练完却什么都没有。
    func testMissingPermissionIsReportedNotSilentlySkipped() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .denied)
        guard case .failed(let message) = coordinator.begin(startedAt: startedAt) else {
            return XCTFail("开关开着却录不了，必须明说")
        }
        XCTAssertTrue(message.contains("系统设置"))
        XCTAssertTrue(message.contains("下一步"))
        XCTAssertEqual(engine.startCount, 0)
    }

    func testStartedRecordingIsNamedAfterTheStartInstant() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt),
                       .started(relativePath: "recordings/2026-08-06T10-45-30Z.m4a"))
        XCTAssertEqual(engine.startCount, 1)
    }

    /// 同一秒里重开一场（上一场刚崩）不能覆盖掉前一场已经录好的内容。
    func testASecondRecordingInTheSameSecondDoesNotOverwriteTheFirst() throws {
        let existing = directory.recordingsDirectory.appending(path: "2026-08-06T10-45-30Z.m4a")
        try Data("已经录好的内容".utf8).write(to: existing)

        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(coordinator.begin(startedAt: startedAt),
                       .started(relativePath: "recordings/2026-08-06T10-45-30Z-2.m4a"))
        XCTAssertEqual(try Data(contentsOf: existing).count,
                       Data("已经录好的内容".utf8).count, "前一场的录音不能被动过")
    }

    /// 麦克风打不开时同样是 failed，不是 skipped。
    func testEngineFailureIsReportedAsFailed() {
        engine.failStartAtCall = 1
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        guard case .failed(let message) = coordinator.begin(startedAt: startedAt) else {
            return XCTFail("采集起不来必须明说")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testFinishReturnsTheOutcomeOfWhatWasRecorded() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        _ = coordinator.begin(startedAt: startedAt)
        engine.deliver(makePCMBuffer())

        let outcome = coordinator.finish()
        XCTAssertEqual(outcome?.relativePath, "recordings/2026-08-06T10-45-30Z.m4a")
        XCTAssertEqual(outcome?.duration, 12)
    }

    /// 没在录的时候收尾必须无害——PracticeRunner 在任何失败路径上都会调它，
    /// 包括那些根本没开始录的路径。
    func testFinishWithoutBeginIsHarmless() {
        let coordinator = makeCoordinator(settings: CoachState.empty().settings, permission: .granted)
        XCTAssertNil(coordinator.finish())
    }

    func testFinishTwiceDoesNotReturnAStaleOutcome() {
        let coordinator = makeCoordinator(settings: enabledSettings(), permission: .granted)
        _ = coordinator.begin(startedAt: startedAt)
        XCTAssertNotNil(coordinator.finish())
        XCTAssertNil(coordinator.finish(), "第二次收尾时已经没有正在进行的录音了")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRecordingCoordinatorTests`
Expected: 编译失败 —— `PracticeRecordingCoordinator` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachAudio/PracticeRecordingCoordinator.swift`：

```swift
import AVFoundation
import Foundation
import IELTSCoachCore

/// 一次练习开始时，录音到底有没有跑起来。
public enum RecordingBeginOutcome: Equatable, Sendable {
    case started(relativePath: String)
    /// 用户没开开关。**这是默认状态，不是故障**——界面不该为它报警，
    /// 也不该显示「正在录音」。
    case skippedByUser
    /// 想录但录不了。message 是中文，写明了发生了什么与下一步做什么。
    /// **界面必须显示它**：用户以为在录，实际没录，不说就是骗人。
    case failed(String)
}

/// 给 `PracticeRunner` 用的接口：开练时调一次 `begin`，收尾时调一次 `finish`。
/// 做成 protocol 是为了让 `PracticeRunner` 的测试可以用假实现，
/// 不必真去开麦克风。
public protocol PracticeRecording: AnyObject {
    func begin(startedAt: Date) -> RecordingBeginOutcome
    /// 结束录音。**无论练习成功还是失败都必须调用**——练到一半出错时，
    /// 已经录下的部分不能跟着一起丢。没在录时返回 nil，且必须无害。
    func finish() -> RecordingOutcome?
}

public final class PracticeRecordingCoordinator: PracticeRecording, @unchecked Sendable {
    public typealias EngineFactory = @Sendable () -> AudioCaptureEngine
    public typealias WriterFactory = @Sendable (URL) throws -> AudioSegmentWriter

    private let store: RecordingStore
    /// 练习开始那一刻的开关快照。中途去设置里改开关不影响正在进行的这一场——
    /// 文件已经在写了，半路停下来只会得到一条莫名其妙截断的录音。
    private let settings: CoachSettings
    private let permission: MicrophonePermissionState
    private let engineFactory: EngineFactory
    private let writerFactory: WriterFactory

    private let lock = NSLock()
    private var session: RecordingSession?

    public init(store: RecordingStore,
                settings: CoachSettings,
                permission: MicrophonePermissionState,
                engineFactory: @escaping EngineFactory = { AVAudioEngineCapture() },
                writerFactory: @escaping WriterFactory = { try AACSegmentWriter(url: $0) }) {
        self.store = store
        self.settings = settings
        self.permission = permission
        self.engineFactory = engineFactory
        self.writerFactory = writerFactory
    }

    public func begin(startedAt: Date) -> RecordingBeginOutcome {
        // 顺序有意义：先看用户的意愿，再看系统的许可。开关关着时连采集器都不造——
        // 造了就会在系统的「最近使用麦克风」里留下记录，而用户根本没开这个功能。
        switch RecordingConsent.readiness(settings: settings, permission: permission) {
        case .disabledByUser:
            return .skippedByUser
        case .blocked(let message):
            return .failed(message)
        case .ready:
            break
        }

        do {
            try store.directory.createIfNeeded()
            let taken = Set(try store.existingFileNames())
            let name = RecordingStore.fileName(startedAt: startedAt, taken: taken)
            let relative = store.relativePath(fileName: name)
            let url = try store.url(forRelativePath: relative)

            let made = RecordingSession(engine: engineFactory(),
                                        writerFactory: writerFactory,
                                        fileURL: url,
                                        relativePath: relative)
            try made.start()
            lock.lock(); session = made; lock.unlock()
            return .started(relativePath: relative)
        } catch {
            return .failed(
                "这次练习没能开始录音：\(error.localizedDescription)"
                + "\n练习本身不受影响，可以照常练完。"
                + "下一步：练完之后到「录音设置」（⌘,）检查麦克风权限与磁盘空间。")
        }
    }

    public func finish() -> RecordingOutcome? {
        lock.lock()
        let current = session
        session = nil
        lock.unlock()
        return current?.finish()
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRecordingCoordinatorTests`
Expected: PASS（8 个测试）

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（无视开关）：** 把 `begin` 里的 `case .disabledByUser: return .skippedByUser` 改成 `case .disabledByUser: break`（即开关关着也照录）：

Run: `swift test --filter PracticeRecordingCoordinatorTests`
Expected: `testDoesNotTouchTheMicrophoneWhenTheSwitchIsOff` **变红**

**突变 B（静默跳过）：** 把 `case .blocked(let message): return .failed(message)` 改成 `case .blocked: return .skippedByUser`：

Run: `swift test --filter PracticeRecordingCoordinatorTests`
Expected: `testMissingPermissionIsReportedNotSilentlySkipped` **变红**

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

突变 B 守的是本阶段最隐蔽的失败：用户开了开关、以为练完能回听，练完却什么都没有，而且全程没有任何提示。

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachAudio/PracticeRecordingCoordinator.swift \
        Tests/IELTSCoachAudioTests/PracticeRecordingCoordinatorTests.swift
git commit -m "feat(audio): 练习录音协调器，串起开关、权限与录音"
```

---

## Task 7: 把录音接进练习流程

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Session/PracticeRunner.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Session/PracticeSheet.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/PracticeRunnerRecordingTests.swift`

**Interfaces:**
- Consumes: `PracticeRecording`、`RecordingBeginOutcome`、`RecordingOutcome`、`PracticeStage`（Phase 3）、`CoachBridge`（Phase 3）、`SessionSetup`、`StateStore`
- Produces（都是加在既有 `PracticeRunner` 上的）：
  - `PracticeRunner.init(..., recording: (any PracticeRecording)? = nil)` —— **新增参数，带默认值 nil，因此既有调用点一处都不用改**
  - `public private(set) var PracticeRunner.isRecording: Bool`
  - `public private(set) var PracticeRunner.recordingNotice: String?` —— 非 nil 时界面必须显示
  - `public private(set) var PracticeRunner.recordingRelativePath: String`

### 必须遵守的四条接线规则

1. **录音在 `.practicing` 那一刻开始**，即考官提示词已经发出去之后。更早开始只会录到用户等 ChatGPT 启动语音的那 9 秒沉默（spec 2.3.7）
2. **`begin` 失败绝不能让练习失败。** 录音是增强，不是必需——跟 Phase 4 的逐字稿同一条原则（ROADMAP 3.2「采样失败不得中断练习」）。`.failed` 时把消息放进 `recordingNotice`，**stage 照常进 `.practicing`**
3. **每一条会走到头的路径都必须调 `finish()`**：`finishPractice()` 的开头、`start(setup:)` 抛错的 catch 里、`cancel()` 里。漏掉任何一条，那条路径上的录音就停在缓冲区里，用户什么都拿不到
4. **`finish()` 要在结束语音之前调。** 用户已经不说话了，早一点关文件，后面取复盘那几十秒就不会被录进去

### 关于 `recordingPath` 写进 `PracticeSession`

归档时把 `recordingRelativePath` 写进这次 `PracticeSession.recordingPath`。这依赖 **P4-2（Phase 4 让 `PracticeRunner` 真的往 `state.sessions` 里落一条会话记录）**。

**若 `PracticeRunner` 目前根本不往 `state.sessions` 里写东西，停下来报告，不要在本任务里顺手发明一套会话落库逻辑。** 那是 Phase 4 的交付物，在这里补会让两个阶段的责任糊成一团，出问题时没人知道该改哪儿。Step 1 里最后那条测试届时会失败，那正是它存在的意义。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/PracticeRunnerRecordingTests.swift`：

```swift
import ChatGPTBridge
import IELTSCoachAudio
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假录音器。练习流程的接线因此完全不需要真麦克风就能测。
final class FakeRecording: PracticeRecording, @unchecked Sendable {
    var beginOutcome: RecordingBeginOutcome = .started(relativePath: "recordings/x.m4a")
    var outcome: RecordingOutcome? = RecordingOutcome(relativePath: "recordings/x.m4a",
                                                      duration: 300,
                                                      interruptions: [],
                                                      warning: nil)
    private(set) var beginCount = 0
    private(set) var finishCount = 0

    func begin(startedAt: Date) -> RecordingBeginOutcome { beginCount += 1; return beginOutcome }
    func finish() -> RecordingOutcome? { finishCount += 1; return outcome }
}

@MainActor
final class PracticeRunnerRecordingTests: XCTestCase {
    /// **每一个 runner 都必须拿到这个临时目录，一个都不能漏。**
    ///
    /// Phase 4 之后 `PracticeRunner.init` 的 `directory:` 参数默认值是 `.resolve()`，
    /// 也就是**用户真实的数据目录**；而 `finishPractice()` 会往那里写一条训练记录、
    /// 一份 reports/*.json 和一份 pending-reviews/*.txt。不传 `directory:` 的测试
    /// 会在用户的 state.json 里种下几条假练习记录——**测试全绿，数据已经脏了**。
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    private func runner(bridge: FakeBridge = FakeBridge(),
                        recording: FakeRecording) -> PracticeRunner {
        PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""),
                       directory: directory, recording: recording)
    }

    private static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "q1", part: 1, topic: "Home", prompt: "P"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }

    /// 录音在考官提示词发出去之后才开始。更早开始只会录到等 ChatGPT
    /// 启动语音的那 9 秒沉默（spec 2.3.7）。
    func testRecordingStartsOnlyAfterTheExaminerPromptWasSent() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertEqual(bridge.calls, ["newChat", "startVoice", "waitComposer", "sendText"])
        XCTAssertEqual(recording.beginCount, 1)
        XCTAssertTrue(runner.isRecording)
        XCTAssertEqual(runner.stage, .practicing)
    }

    /// 录音起不来**不能把练习也拖垮**。录音是增强，不是必需，
    /// 跟 Phase 4 的逐字稿是同一条原则。
    func testAFailedRecordingDoesNotStopThePractice() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        recording.beginOutcome = .failed("打不开麦克风。下一步：到系统设置里检查权限。")
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertEqual(runner.stage, .practicing, "录音失败不该让练习失败")
        XCTAssertFalse(runner.isRecording)
        XCTAssertTrue(try XCTUnwrap(runner.recordingNotice).contains("下一步"))
    }

    /// 开关关着是默认状态，不是故障——不能拿提示去骚扰用户。
    func testSwitchedOffMeansNoNoticeAndNoIndicator() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        recording.beginOutcome = .skippedByUser
        let runner = self.runner(bridge: bridge, recording: recording)

        try await runner.start(setup: Self.setup())

        XCTAssertFalse(runner.isRecording)
        XCTAssertNil(runner.recordingNotice, "没开开关是默认状态，不该报警")
    }

    /// 练习中途失败时，已经录下的部分不能跟着一起丢。
    func testRecordingIsFinalizedWhenTheStartSequenceFailsMidway() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)

        try? await runner.start(setup: Self.setup())

        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertEqual(recording.finishCount, 1, "失败路径上也必须把录音收尾")
    }

    /// 取复盘那一步失败是真实发生过的事（spec 2.3.9）。
    /// 那时候用户已经练了半小时，录音一秒都不能丢。
    func testRecordingIsFinalizedWhenTheReviewStepFails() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        bridge.failAt = .capturingReview
        await runner.finishPractice()

        XCTAssertEqual(recording.finishCount, 1)
        XCTAssertEqual(runner.recordingRelativePath, "recordings/x.m4a",
                       "复盘失败了，录音路径也还得在")
    }

    func testCancelAlsoFinalizesTheRecording() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        runner.cancel()

        XCTAssertEqual(recording.finishCount, 1)
    }

    /// 中断过就必须让用户看见——哪怕录音自动接上了，
    /// 中间那一两秒确实没录到。
    func testTheRecordingWarningReachesTheUserAfterFinishing() async throws {
        let bridge = FakeBridge()
        let recording = FakeRecording()
        recording.outcome = RecordingOutcome(
            relativePath: "recordings/x.m4a", duration: 300,
            interruptions: [RecordingInterruption(at: Date(), recovered: true)],
            warning: "录音中途因为插拔耳机断了一下，已自动接上。下一步：回听时留意这一小段。")
        let runner = self.runner(bridge: bridge, recording: recording)
        try await runner.start(setup: Self.setup())

        await runner.finishPractice()

        XCTAssertTrue(try XCTUnwrap(runner.recordingNotice).contains("耳机"))
    }

    /// 依赖 P4-2：Phase 4 必须已经让 PracticeRunner 往 state.sessions 里落会话记录。
    /// **若这条编译不过或断言失败，停下来报告，不要在本任务里补 Phase 4 的活。**
    func testTheRecordingPathIsStoredOnThePracticeSession() async throws {
        let recording = FakeRecording()
        let runner = self.runner(recording: recording)

        try await runner.start(setup: Self.setup())
        await runner.finishPractice()

        // 从同一个临时目录读回来。**不要另建一个指向别处的 StateStore**——
        // 那样测的就不是 runner 到底写到哪儿去了。
        let saved = try StateStore(directory: directory).load()
        XCTAssertEqual(saved.sessions.last?.recordingPath, "recordings/x.m4a")
    }
}
```

> ### ⚠️ `directory:` 不是可选的（2026-08-06 跨阶段复审改写，**必读**）
>
> 本计划初稿把 runner 写成 `PracticeRunner(bridge:pasteboard:recording:)`，并在一条测试里传 `store:`。
> **Phase 4 落地后的实际签名是 `PracticeRunner(bridge:pasteboard:directory:transcript:now:)`**，
> 没有 `store:` 这个参数（store 由它自己从 directory 派生），而 `directory:` 的默认值是 `.resolve()`
> ——**用户真实的数据目录**。
>
> 同时 Phase 4 让 `finishPractice()` 真的开始往磁盘上写东西：一条 `PracticeSession`、
> 一份 `reports/<id>.json`、一份 `pending-reviews/<id>.txt`。于是**任何一条不传 `directory:`
> 又调了 `finishPractice()` 的测试，都会在用户的 `state.json` 里种下一条假练习记录**——
> 测试全绿，训练记录页上凭空多出几场 "Home / P"，而且没有任何报错。
>
> 所以上面每一个 runner 都走 `self.runner(...)`，它必然带上临时目录。
> **本任务新增测试时也一律走它，不要现场 `PracticeRunner(...)`。**
>
> 其余参数（`bridge:`、`pasteboard:`）以源码实际签名为准；**若实际签名与上面不同，改测试去适配实际签名，不要为了迁就测试去改产品代码的参数名**，但 `directory:` 这一条不在「可以将就」之列。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRunnerRecordingTests`
Expected: 编译失败 —— `PracticeRunner` 没有 `recording:` 参数、没有 `isRecording` / `recordingNotice` / `recordingRelativePath`

- [ ] **Step 3: 实现**

在 `PracticeRunner` 上按下面的要求改，**不要改动它既有的阶段流转顺序**（spec 2.3.5 定的「先新建会话 → 再启动语音 → 等输入框 → 最后发提示词」一个字都不能动）：

1. 新增存储属性与初始化参数：

```swift
    private let recording: (any PracticeRecording)?

    /// 是否正在录音。界面据此显示「● 正在录音」。
    public private(set) var isRecording = false
    /// 录音相关的提示。**非 nil 时界面必须显示**——用户以为在录、实际没录，
    /// 或者录音中途断过，都得让他知道。
    public private(set) var recordingNotice: String?
    /// 这次录音的相对路径，归档时写进 PracticeSession.recordingPath。
    public private(set) var recordingRelativePath = ""
```

初始化参数加在最后并给默认值：`recording: (any PracticeRecording)? = nil`。**给默认值是为了让 Phase 3 既有的调用点一处都不用改。**

2. 在 `start(setup:)` 里，**发完考官提示词、把 `stage` 置为 `.practicing` 之前**插入：

```swift
        switch recording?.begin(startedAt: Date()) {
        case .started(let path):
            isRecording = true
            recordingRelativePath = path
        case .failed(let message):
            // 录音是增强，不是必需：起不来就照常练，但必须让用户知道这次没录。
            isRecording = false
            recordingNotice = message
        case .skippedByUser, .none:
            // 开关关着是默认状态，不是故障，什么都不说。
            isRecording = false
        }
```

3. 在 `start(setup:)` 的 `catch`（转入 `.failed` 的那一段）里，**在设置 `.failed` 之前**加一行 `finalizeRecording()`。

4. 在 `finishPractice()` 的**第一行**加 `finalizeRecording()`——早于结束语音、早于发复盘请求。用户已经不说话了，早点关文件，后面取复盘那几十秒就不会被录进去。

5. 在 `cancel()` 里加 `finalizeRecording()`。

6. 新增私有方法：

```swift
    /// 收尾录音。可以被重复调用——`PracticeRecording.finish()` 在没在录时返回 nil。
    private func finalizeRecording() {
        guard let outcome = recording?.finish() else { isRecording = false; return }
        isRecording = false
        recordingRelativePath = outcome.relativePath
        if let warning = outcome.warning {
            recordingNotice = [recordingNotice, warning].compactMap { $0 }.joined(separator: "\n")
        }
    }
```

7. 归档那一段（写 `PracticeSession` 的地方）把 `recordingPath: recordingRelativePath` 填上。

`PracticeSheet` 的改动（**只给要求，不给布局代码**）：

- `.practicing` 阶段且 `isRecording == true` 时，显示一个明确的录音指示：一个 SF Symbol（`record.circle`，**不许用 emoji**）+ 文字「正在录音」。颜色走 `Palette.danger`，**不得写字面颜色**
- `recordingNotice != nil` 时，在练习界面上显示它，样式用 `CoachCard`，文字可选中（`.textSelection(.enabled)`），**不得因为练习还在进行就把它藏起来**
- 录音指示与提示都不得抢走「我练完了」按钮的视觉主位——每页只有一个主行动（DESIGN-SYSTEM 第 4 节）
- 尊重「减弱动态效果」：录音指示**不许做呼吸闪烁动画**，静态就好（DESIGN-SYSTEM 第 5 节禁止循环装饰动画）

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRunnerRecordingTests`
Expected: PASS（8 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（失败路径丢录音）：** 把 `start(setup:)` 的 `catch` 里那行 `finalizeRecording()` 删掉：

Run: `swift test --filter PracticeRunnerRecordingTests`
Expected: `testRecordingIsFinalizedWhenTheStartSequenceFailsMidway` **变红**

**突变 B（录音失败拖垮练习）：** 在 `start(setup:)` 里 `beginRecording()` 的**下一行**插一句，
让录音起不来就把整场练习判死：

```swift
            beginRecording()
            if let notice = recordingNotice { stage = .failed(notice); return } // ← 突变 B
            stage = .practicing
```

Run: `swift test --filter PracticeRunnerRecordingTests`
Expected: `testAFailedRecordingDoesNotStopThePractice` **变红**，报的是
`XCTAssertEqual failed: ("failed(...)") is not equal to ("practicing") - 录音失败不该让练习失败`

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

突变 B 守的是：一个没给麦克风权限的用户，本来只是听不了回放，若因此连练都练不了，那就是拿一个可选功能把主功能废掉了。

> ### ⚠️ 突变 B 原来是假的（2026-08-06 复审就地更正，**必读**）
>
> 本计划初稿的突变 B 写的是「把 `case .failed(let message):` 分支改成把 `stage` 置为 `.failed(message)`」。
> **那个突变实测不会变红**——复审亲手做过：照原文改完跑 `swift test --filter PracticeRunnerRecordingTests`，
> 结果是「Executed 11 tests, with 0 failures」。
>
> 原因是计划自相矛盾：本任务 Step 3 第 2 条要求 `beginRecording()` 在 `stage = .practicing`
> **之前**调用（实现照做了），于是在那个 switch 里设的任何 `stage` 都会被下一行的
> `stage = .practicing` 原地覆盖掉。换句话说，那不是一个「破坏行为的改动」，
> 而是一个**根本没有效果**的改动——它证明不了任何测试有牙齿。
>
> **这条被守住的行为本身没问题**：换成上面这个真的会改变行为的突变，
> `testAFailedRecordingDoesNotStopThePractice` 确实变红。所以要改的是计划，不是产品代码。
>
> 教训（对后面每一个任务都成立）：**写突变之前先问「这一改会让产品行为真的变吗」。**
> 一个被下一行覆盖掉的赋值、一个没人读的字段、一段死代码，改了都不算突变。
> 突变验证的意义是证明测试有约束力；用一个空转的突变去做，证明出来的只有「它没红」。

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachUI/Session/PracticeRunner.swift \
        Sources/IELTSCoachUI/Session/PracticeSheet.swift \
        Tests/IELTSCoachUITests/PracticeRunnerRecordingTests.swift
git commit -m "feat(ui): 把录音接进练习流程，失败路径也不丢录音"
```

---

## Task 7b: 把录音接到 App 上（2026-08-06 复审补的任务，**Task 8 开工前必须已完成**）

> **这个任务是复审补进来的，因为整份 Phase 5 计划漏了它。** 原计划十一个任务里
> `makePracticeRunner` 出现 0 次，`PracticeRecordingCoordinator` 只在 Task 6（造它）出现过，
> Task 8 / 9 / 10 / 11 的 Files 清单里都没有 `AppState.swift`。后果是：Task 7 把录音接进了
> `PracticeRunner`（那是对的，Task 7 明写「既有调用点一处都不用改」），但**没有任何一个任务
> 负责把录音器交到 `PracticeRunner` 手上**——`AppState.makePracticeRunner()` 不传 `recording:`，
> 默认值 nil，于是真机上这个 .app 永远不会录音，而全套测试仍然全绿。
> Task 11 Step 3 明写要在练习界面上看到「● 正在录音」、在训练记录里看到「有录音」标记，
> 那一步会当场做不到。
>
> **这是 Phase 4 那个缺口原样长出的第二遍**：Phase 4 的十三个任务也没有一个认领
> 「把 `AXTranscriptSampler` 接到 App 上」，`AppState.swift` 里那段注释讲的就是这件事。
> 一个组件写好了、测好了、却没人负责把它插到 App 上——**这是本项目已经犯过两次的错，
> 后面每个阶段的计划都要专门留一个「接线」任务**。
>
> 编号用 `7b` 而不是重排 8–11，是为了不让别处引用的任务号全部作废。

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/AppState.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/AppStateTests.swift`

**Interfaces:**
- Consumes: `PracticeRecordingCoordinator`（Task 6）、`SystemMicrophoneAuthorizer`（Task 1）、`RecordingStore`（Task 3）、`CoachSettings`、`PracticeRunner.init(recording:)`（Task 7）
- Produces:
  - `AppState.liveRecording(authorizer:) -> @Sendable (RecordingStore, CoachSettings) -> any PracticeRecording` —— 生产默认那一台。`authorizer` 带默认值 `{ SystemMicrophoneAuthorizer() }`，**唯一理由是让测试能把这份生产代码原样跑一遍而不构造它**（Global Constraints：单元测试绝不允许碰真硬件）
  - `AppState.init(..., makeRecording:)` —— 新增参数带默认值 `AppState.liveRecording()`，既有调用点一处都不用改
  - `makePracticeRunner()` 真的把录音器传给 `PracticeRunner`

### 三条必须遵守的接线规则

1. **每场造一台录音器。** `PracticeRecordingCoordinator` 手上是开练那一刻的开关快照与
   麦克风权限快照，复用同一台等于永远用第一场的那一份
2. **开练前从磁盘重读一次设置。** 录音开关是在系统「设置」窗口（⌘,，Task 8）里拨的，
   那个窗口有它自己的 `StateStore`，不经过 `AppState`。只信内存里那份的话，用户刚打开开关、
   转身开练，录音器收到的还是启动 App 那一刻的旧值——开关看着是开的，练完却一个录音都没有，
   而且没有任何报错
3. **「录不录」的判断不在 `AppState` 里重做一遍。** 开关关着时协调器自己返回 `.skippedByUser`
   （`RecordingConsent.readiness`）。两处各判一次，迟早会走岔

- [x] **Step 1: 写失败的测试**（`Tests/IELTSCoachUITests/AppStateTests.swift`，新增一组四条）

照着同文件里「采样器必须真的接到练习上（复审 BI-2）」那一组的样子写，用假录音器与假 Bridge，
不碰麦克风、不碰真实 ChatGPT（铁律 5）：

1. `testPracticeStartedFromTheAppReallyRecords` —— 从 `makePracticeRunner()` 拿到的驱动器
   真的在录（`beginCount == 1`、`isRecording`），且录音路径真的落进了 `state.sessions`
   那条记录（守「接上了」）
2. `testTheRecorderGetsTheSwitchThatIsOnDiskRightNow` —— 用**另一个** `StateStore` 打开录音开关
   （模拟设置窗口），再 `makePracticeRunner()`，断言交到录音器工厂手上的 `CoachSettings`
   开关是开的、同意时间戳也在，且它拿到的 `RecordingStore` 与训练数据同一个目录（守「开关真的算数」）
3. `testTheRecorderIsNotToldTheSwitchIsOnWhenItIsOff` —— 开关关着时交出去的快照也必须是关的
   （守隐私方向：没有它，「一律按开着传」也是绿的）
4. `testTheProductionDefaultReallyBuildsARecordingCoordinator` —— `AppState.liveRecording()`
   造出来的真的是 `PracticeRecordingCoordinator`（守「真机上录的是真麦克风」；
   前三条都是假录音器，把生产默认换成空实现它们照样全绿）。
   **跑的必须是那份生产代码本身**，只把权限查询换成假的（`authorizer:`）——
   照抄一份长得像的替身去测，等于没测

- [x] **Step 2: 运行，确认失败**

Run: `swift test --filter AppStateTests`
Expected: 编译失败 —— `type 'AppState' has no member 'liveRecording'`、`extra argument 'makeRecording' in call`

- [x] **Step 3: 实现**（`AppState.swift`）

加 `liveRecording(authorizer:)` 静态工厂（默认那份 `SystemMicrophoneAuthorizer().currentStatus()`
只读系统状态、不弹窗，构造协调器本身没有副作用）、`makeRecording` 存储属性与带默认值的初始化参数；
`makePracticeRunner()` 里先 `reload()` 再取 `state.settings`，把 `RecordingStore(directory:)`
与这份设置交给工厂，结果传给 `PracticeRunner(recording:)`。

- [x] **Step 4: 运行，确认通过**：`swift test --filter AppStateTests` → 25 passed；`swift test` → 794 passed

- [x] **Step 5: 突变验证（四处）**

| 突变 | 改法 | 该变红的 |
|---|---|---|
| W1 | `makePracticeRunner()` 里去掉 `recording:` 参数（即复审发现的原状） | `testPracticeStartedFromTheAppReallyRecords` |
| W2 | 去掉 `makePracticeRunner()` 开头的 `reload()` | `testTheRecorderGetsTheSwitchThatIsOnDiskRightNow` |
| W3 | 交出去之前 `settings.recordingEnabled = true` | `testTheRecorderIsNotToldTheSwitchIsOnWhenItIsOff` |
| W4 | `liveRecording(authorizer:)` 返回的闭包改成一个永远 `.skippedByUser` 的空实现 | `testTheProductionDefaultReallyBuildsARecordingCoordinator` |

- [x] **Step 6: 提交**（与 Task 7 的计划更正同一个提交）

---

## Task 8: 「保存我的回答录音」开关 + 权限引导 + 占用提示

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Recording/RecordingSettingsView.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Recording/RecordingSettingsScene.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachApp/main.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/RecordingSettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `StateStore.load()`、`StateStore.mutate`、`RecordingStore.usage()`、`RecordingStore.orphanFileNames(referencedPaths:)`、`RecordingConsent.enable/disable`、`MicrophoneAuthorizing`、`MicrophonePermissionState`、`Palette`/`Spacing`/`Radius`/`CoachCard`/`SectionHeader`
- Produces:
  - `@MainActor @Observable public final class RecordingSettingsViewModel`，含 `init(store:recordings:authorizer:now:)`、`refresh()`、`setEnabled(_ turnOn: Bool) async`、只读属性 `enabled`、`consentAt`、`permission`、`notice`、`usage`、`orphanNotice`、`isWorking`、`consentText`、`recordingsFolderURL`
  - `public struct RecordingSettingsView: View`
  - `public struct RecordingSettingsScene: View`

**为什么放在系统「设置」窗口而不是侧边栏：** 侧边栏那十项是产品设计稿定死的（`ROADMAP.md` 第 1 节），加第十一项会破坏它。macOS 的惯例本来就是 `⌘,` 打开设置窗口，SwiftUI 的 `Settings { }` 场景直接支持。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RecordingSettingsViewModelTests.swift`：

```swift
import IELTSCoachAudio
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

/// 可编程的假权限查询。真实实现的返回值取决于跑测试这台机器授过什么权，
/// 直接依赖它的测试今天绿明天红。
final class FakeMicrophoneAuthorizer: MicrophoneAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var current: MicrophonePermissionState
    private let afterRequest: MicrophonePermissionState
    private(set) var requestCount = 0

    init(current: MicrophonePermissionState, afterRequest: MicrophonePermissionState? = nil) {
        self.current = current
        self.afterRequest = afterRequest ?? current
    }

    func currentStatus() -> MicrophonePermissionState {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func requestAccess() async -> MicrophonePermissionState {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        current = afterRequest
        return current
    }
}

@MainActor
final class RecordingSettingsViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private var recordings: RecordingStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
        recordings = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func makeViewModel(_ authorizer: FakeMicrophoneAuthorizer,
                               now: Date = Date(timeIntervalSince1970: 1_785_931_530))
    -> RecordingSettingsViewModel {
        RecordingSettingsViewModel(store: store, recordings: recordings,
                                   authorizer: authorizer, now: { now })
    }

    // MARK: - 默认关

    func testStartsOffOnAFreshInstall() {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.consentAt, "")
    }

    // MARK: - 打开

    func testTurningOnWithPermissionAlreadyGrantedPersistsConsent() async throws {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await viewModel.setEnabled(true)

        XCTAssertTrue(viewModel.enabled)
        XCTAssertFalse(viewModel.consentAt.isEmpty)
        // 必须真的落盘，不能只是界面上变了个样子。
        let saved = try StateStore(directory: directory).load()
        XCTAssertTrue(saved.settings.recordingEnabled)
        XCTAssertEqual(saved.settings.recordingConsentAt, viewModel.consentAt)
    }

    func testTurningOnPromptsExactlyOnceWhenPermissionWasNeverAsked() async {
        let authorizer = FakeMicrophoneAuthorizer(current: .notDetermined, afterRequest: .granted)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertEqual(authorizer.requestCount, 1, "还没问过就该弹一次系统对话框")
        XCTAssertTrue(viewModel.enabled)
    }

    /// **本任务最要紧的一条。** 权限没拿到时开关必须停在「关」。
    /// 显示成「开」却什么都不录，用户练完发现没录音时完全无从查起。
    func testTheSwitchStaysOffWhenThePermissionIsRefused() async throws {
        let authorizer = FakeMicrophoneAuthorizer(current: .notDetermined, afterRequest: .denied)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertFalse(viewModel.enabled, "没权限时开关必须停在关")
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("下一步"))
        let saved = try StateStore(directory: directory).load()
        XCTAssertFalse(saved.settings.recordingEnabled, "更不能把「开」写进 state.json")
    }

    /// 被拒过之后再点开关**不能再去弹窗**——系统不会弹，用户只会对着界面干等。
    /// 必须直接给「去系统设置」的引导。
    func testAlreadyDeniedDoesNotPromptAgainAndPointsAtSystemSettings() async throws {
        let authorizer = FakeMicrophoneAuthorizer(current: .denied)
        let viewModel = makeViewModel(authorizer)
        await viewModel.setEnabled(true)

        XCTAssertEqual(authorizer.requestCount, 0, "被拒过就别再弹了，系统根本不会弹")
        XCTAssertFalse(viewModel.enabled)
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("系统设置"))
    }

    // MARK: - 关闭与重新打开

    func testTurningOffClearsTheConsentAndSaysRecordingsAreKept() async throws {
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        await viewModel.setEnabled(true)
        await viewModel.setEnabled(false)

        XCTAssertFalse(viewModel.enabled)
        XCTAssertEqual(viewModel.consentAt, "")
        let saved = try StateStore(directory: directory).load()
        XCTAssertEqual(saved.settings.recordingConsentAt, "")
        // 关开关不等于删录音，必须说清楚，否则用户会以为录音也一起没了。
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("不会被删除"))
    }

    func testTurningItBackOnRecordsAFreshConsentTime() async {
        let authorizer = FakeMicrophoneAuthorizer(current: .granted)
        let first = makeViewModel(authorizer, now: Date(timeIntervalSince1970: 1_785_931_530))
        await first.setEnabled(true)
        let firstConsent = first.consentAt
        await first.setEnabled(false)

        let second = makeViewModel(authorizer, now: Date(timeIntervalSince1970: 1_786_931_530))
        await second.setEnabled(true)

        XCTAssertNotEqual(second.consentAt, firstConsent)
        XCTAssertFalse(second.consentAt.isEmpty)
    }

    // MARK: - 占用提示

    func testUsageReflectsWhatIsOnDisk() throws {
        try Data(repeating: 0x41, count: 2_048)
            .write(to: directory.recordingsDirectory.appending(path: "a.m4a"))
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        XCTAssertEqual(viewModel.usage.count, 1)
        XCTAssertEqual(viewModel.usage.bytes, 2_048)
    }

    /// 没有任何训练记录指向的录音要报出来。不主动删——那是用户的录音——
    /// 但得让他知道有东西在占地方。
    func testOrphanRecordingsAreReportedWithAWayToDealWithThem() throws {
        try Data(repeating: 0x41, count: 16)
            .write(to: directory.recordingsDirectory.appending(path: "orphan.m4a"))
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        let notice = try XCTUnwrap(viewModel.orphanNotice)
        XCTAssertTrue(notice.contains("1 个"))
        XCTAssertTrue(notice.contains("下一步"))
    }

    func testNoOrphanNoticeWhenEveryRecordingIsReferenced() throws {
        try Data(repeating: 0x41, count: 16)
            .write(to: directory.recordingsDirectory.appending(path: "kept.m4a"))
        try store.mutate { state in
            state.sessions = [PracticeSession(id: "2026-08-06-001", questionId: "q1",
                                              focusPart: .part1, startedAt: "t", endedAt: "t",
                                              goal: "", transcript: [], reportPath: "",
                                              recordingPath: "recordings/kept.m4a")]
        }
        let viewModel = makeViewModel(FakeMicrophoneAuthorizer(current: .granted))
        viewModel.refresh()

        XCTAssertNil(viewModel.orphanNotice)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RecordingSettingsViewModelTests`
Expected: 编译失败 —— `RecordingSettingsViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift`：

```swift
import Foundation
import IELTSCoachAudio
import IELTSCoachCore
import Observation

@MainActor
@Observable
public final class RecordingSettingsViewModel {
    /// 开关的当前值。**只反映已经落盘的事实。**
    /// 权限没拿到时它必须是 false——显示成「开」却什么都不录，
    /// 用户练完发现没录音时完全无从查起。
    public private(set) var enabled = false
    public private(set) var consentAt = ""
    public private(set) var permission: MicrophonePermissionState = .notDetermined
    /// 非 nil 时界面必须显示。中文，写明发生了什么与下一步做什么。
    public private(set) var notice: String?
    public private(set) var usage = RecordingUsage(count: 0, bytes: 0)
    /// 磁盘上有、但没有训练记录指向的录音。非 nil 时界面必须显示。
    public private(set) var orphanNotice: String?
    /// 正在等系统权限对话框时为 true，界面据此禁用开关，避免连点。
    public private(set) var isWorking = false

    private let store: StateStore
    private let recordings: RecordingStore
    private let authorizer: any MicrophoneAuthorizing
    private let now: () -> Date

    public init(store: StateStore, recordings: RecordingStore,
                authorizer: any MicrophoneAuthorizing,
                now: @escaping () -> Date = Date.init) {
        self.store = store
        self.recordings = recordings
        self.authorizer = authorizer
        self.now = now
        refresh()
    }

    /// 重新读一遍磁盘上的事实。**不清 notice**——用户刚做完的那个操作
    /// 说了什么，不该因为刷新一下就消失。
    public func refresh() {
        permission = authorizer.currentStatus()
        do {
            let state = try store.load()
            enabled = state.settings.recordingEnabled
            consentAt = state.settings.recordingConsentAt
            usage = try recordings.usage()

            var referenced = state.sessions.map(\.recordingPath)
            if let current = state.currentSession { referenced.append(current.recordingPath) }
            let orphans = try recordings.orphanFileNames(referencedPaths: referenced)
            orphanNotice = orphans.isEmpty ? nil
                : "有 \(orphans.count) 个录音文件在磁盘上，但没有任何训练记录指向它们"
                + "（多半是练习中途出错留下的）。"
                + "下一步：确认不需要之后，点下面的「打开录音文件夹」自己删掉；"
                + "本应用不会替你删任何录音。"
        } catch {
            notice = "读不到录音设置：\(error.localizedDescription)"
                + "\n下一步：确认数据目录（~/Library/Application Support/IELTS Speaking Coach/）"
                + "存在且可读写，然后重新打开这一页。"
        }
    }

    public func setEnabled(_ turnOn: Bool) async {
        isWorking = true
        defer { isWorking = false }
        notice = nil

        guard turnOn else {
            guard persist(RecordingConsent.disable) else { return }
            notice = "已关掉录音。已经录下的录音**不会被删除**。"
                + "若现在正有一场练习在进行，这一次仍会录完（文件已经在写了），下一次起不再录音。"
                + "下一步：想删已有录音的话，到「训练记录」页逐条删，或点下面的「打开录音文件夹」。"
            return
        }

        var status = authorizer.currentStatus()
        if status.canPrompt {
            // 这一步会弹出系统对话框。**只有用户本人能点「允许」**，任何自动化都替不了。
            // 被拒过的状态下不能走到这里——系统不会再弹，用户会对着界面干等。
            status = await authorizer.requestAccess()
        }
        permission = status

        guard status == .granted else {
            // 关键：权限没拿到就绝不能把开关置成开，也绝不能写进 state.json。
            enabled = false
            notice = status.guidance
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: now())
        guard persist({ RecordingConsent.enable($0, at: timestamp) }) else { return }
        notice = "已开启。从下一次练习开始，你的回答会录在本机的 recordings 目录里，"
            + "只存在这台电脑上，不上传任何地方，随时可以逐条删除。"
            + "下一步：建议戴耳机练——用外放的话，麦克风会把 ChatGPT 的声音也一起录进去。"
    }

    /// 打开录音文件夹用的 URL。视图拿它去调 NSWorkspace。
    public var recordingsFolderURL: URL { recordings.directory.recordingsDirectory }

    public var consentText: String {
        guard enabled, !consentAt.isEmpty else {
            return "录音默认关闭。打开之后才会申请麦克风权限。"
        }
        return "你在 \(consentAt) 同意保存录音。"
    }

    /// 落盘。**返回 false 时调用方必须直接返回**，不能接着报一句「已开启」——
    /// 那会在没保存成功的情况下告诉用户保存成功了。
    private func persist(_ transform: (CoachSettings) -> CoachSettings) -> Bool {
        do {
            try store.mutate { state in state.settings = transform(state.settings) }
            refresh()
            return true
        } catch {
            notice = "设置没能保存：\(error.localizedDescription)"
                + "\n下一步：确认数据目录（~/Library/Application Support/IELTS Speaking Coach/）"
                + "可写，然后再试一次。"
            return false
        }
    }
}
```

`Sources/IELTSCoachUI/Recording/RecordingSettingsView.swift`（**只给验收要求，布局自定**）：

- 一个开关，标题「保存我的回答录音」，副标题说明**默认关闭、只存本机、不上传**
- 开关的取值来自 `viewModel.enabled`，**不允许用本地 `@State` 另存一份**——那会让开关显示成「开」而实际没开
- `viewModel.isWorking == true` 时开关禁用（防止连点弹出多个权限请求）
- `viewModel.notice != nil` 时用 `CoachCard` 显示全文，文字可选中（`.textSelection(.enabled)`）
- `viewModel.permission == .denied || == .restricted` 时额外给一个「打开系统设置」按钮，走 `NSWorkspace.shared.open(URL(string: MicrophonePermissionState.systemSettingsURLString)!)`
- 一块「磁盘占用」区域，显示 `viewModel.usage.summaryText`；数字用 `.monospacedDigit()`（DESIGN-SYSTEM 第 1 节：统计数字必须等宽，否则数值变化时整行会抖）
- `viewModel.orphanNotice != nil` 时显示它
- 一个「打开录音文件夹」按钮，走 `NSWorkspace.shared.activateFileViewerSelecting([viewModel.recordingsFolderURL])`
- 显示 `viewModel.consentText`
- 一句**必须有**的说明：「本工具只录你自己的麦克风，不录 ChatGPT 的声音。考官问了什么，看训练记录里的逐字稿。」——这是产品取舍，用户有权知道
- 全部取值走 `Palette` / `Spacing` / `Radius`，**不得出现字面颜色、字号、圆角**
- 所有可点元素必须能用 Tab 到达且焦点环可见

`Sources/IELTSCoachUI/Recording/RecordingSettingsScene.swift`：

```swift
import IELTSCoachAudio
import IELTSCoachCore
import SwiftUI

/// 组装真实依赖。视图模型本身不知道 DataDirectory 从哪来，因此可测。
public struct RecordingSettingsScene: View {
    @State private var viewModel: RecordingSettingsViewModel

    public init(directory: DataDirectory = .resolve()) {
        _viewModel = State(wrappedValue: RecordingSettingsViewModel(
            store: StateStore(directory: directory),
            recordings: RecordingStore(directory: directory),
            authorizer: SystemMicrophoneAuthorizer()))
    }

    public var body: some View {
        RecordingSettingsView(viewModel: viewModel)
            .onAppear { viewModel.refresh() }
    }
}
```

`Sources/IELTSCoachApp/main.swift` 加一个场景：

```swift
import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") { RootView() }
            .defaultSize(width: 1100, height: 720)

        // macOS 的设置窗口（⌘,）。录音开关放这里，不塞进侧边栏——
        // 侧边栏那十项是产品设计稿定死的，加第十一项会破坏它。
        Settings { RecordingSettingsScene() }
    }
}

CoachApp.main()
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RecordingSettingsViewModelTests`
Expected: PASS（10 个测试）

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（界面骗人）：** 把 `setEnabled` 里的 `guard status == .granted else { ... }` 那一段整个删掉（即不管有没有权限都往下走去 persist）：

Run: `swift test --filter RecordingSettingsViewModelTests`
Expected: `testTheSwitchStaysOffWhenThePermissionIsRefused` **变红**

**突变 B（对着不会出现的弹窗干等）：** 把 `if status.canPrompt` 改成 `if status != .granted`：

Run: `swift test --filter RecordingSettingsViewModelTests`
Expected: `testAlreadyDeniedDoesNotPromptAgainAndPointsAtSystemSettings` **变红**（`requestCount` 是 1 而不是 0）

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachUI/Recording/RecordingSettingsViewModel.swift \
        Sources/IELTSCoachUI/Recording/RecordingSettingsView.swift \
        Sources/IELTSCoachUI/Recording/RecordingSettingsScene.swift \
        Sources/IELTSCoachApp/main.swift \
        Tests/IELTSCoachUITests/RecordingSettingsViewModelTests.swift
git commit -m "feat(ui): 录音开关、麦克风权限引导与磁盘占用提示"
```

---

## Task 9: 训练记录页内嵌播放器 + 单条录音删除

**依赖 P4-1 与 P4-2。** 若 `Sources/IELTSCoachUI/History/` 不存在，**停下来报告**——训练记录页是 Phase 4 的交付物，不要在这里现造一个。

**Files:**
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Recording/RecordingPlaybackViewModel.swift`
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/Recording/RecordingPlayerView.swift`
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Sources/IELTSCoachUI/History/HistoryView.swift`（Phase 4 产出；若文件名不同，改那个文件，**不要新建**）
- Create: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/Tests/IELTSCoachUITests/RecordingPlaybackViewModelTests.swift`

**Interfaces:**
- Consumes: `PracticeSession`（`id`、`recordingPath`、`transcript`、`reportPath`）、`StateStore.mutate`、`RecordingStore.url(forRelativePath:)`、`RecordingStore.delete(relativePath:)`、`AVAudioPlayer`
- Produces:
  - `public enum RecordingPlaybackState: Equatable, Sendable { case none; case missing(String); case ready(URL) }`
  - `@MainActor @Observable public final class RecordingPlaybackViewModel`，含 `init(sessionID:relativePath:store:recordings:)`、`refresh()`、`delete()`、`clearReferenceOnly()`、只读属性 `state`、`notice`、`deleteConfirmationText`
  - `public struct RecordingPlayerView: View`

**`.missing` 这个状态是本任务的重点。** 训练记录里写着有录音、文件却不在了（用户手工删过、拷贝目录时漏了、磁盘出过问题），此时**什么都不显示就是静默失败**——用户会以为自己记错了，或者以为程序坏了。必须明说「文件找不到了」并给一个能点的下一步。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/RecordingPlaybackViewModelTests.swift`：

```swift
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

@MainActor
final class RecordingPlaybackViewModelTests: XCTestCase {
    private var directory: DataDirectory!
    private var store: StateStore!
    private var recordings: RecordingStore!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ielts-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
        store = StateStore(directory: directory)
        recordings = RecordingStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    private func session(_ id: String, recordingPath: String) -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T10:45:30Z", endedAt: "2026-08-06T11:00:00Z",
                        goal: "补一个原因和例子",
                        transcript: [PracticeSession.TranscriptTurn(
                            role: "assistant", text: "Do you live in a house or a flat?",
                            capturedAt: "2026-08-06T10:46:00Z")],
                        reportPath: "reports/2026-08-06-001.json",
                        recordingPath: recordingPath)
    }

    @discardableResult
    private func makeRecordingFile(_ name: String) throws -> URL {
        let url = directory.recordingsDirectory.appending(path: name)
        try Data(repeating: 0x41, count: 128).write(to: url)
        return url
    }

    private func makeViewModel(_ practice: PracticeSession) -> RecordingPlaybackViewModel {
        RecordingPlaybackViewModel(sessionID: practice.id, relativePath: practice.recordingPath,
                                   store: store, recordings: recordings)
    }

    // MARK: - 三种状态

    /// 这次练习本来就没录音（开关关着）。不该显示播放器，也不该报警。
    func testNoRecordingPathMeansNoPlayerAndNoNoise() {
        let viewModel = makeViewModel(session("s1", recordingPath: ""))
        XCTAssertEqual(viewModel.state, .none)
        XCTAssertNil(viewModel.notice)
    }

    func testReadyWhenTheFileIsThere() throws {
        try makeRecordingFile("a.m4a")
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
        guard case .ready(let url) = viewModel.state else { return XCTFail("文件在就该能播") }
        XCTAssertEqual(url.lastPathComponent, "a.m4a")
    }

    /// **记录里有录音、文件却不在了，必须明说。**
    /// 什么都不显示的话，用户会以为自己记错了，或者以为程序坏了。
    func testAMissingFileIsSaidOutLoudInsteadOfSilentlyShowingNothing() throws {
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))
        guard case .missing(let message) = viewModel.state else {
            return XCTFail("文件不在了不能装作这次本来就没录音")
        }
        XCTAssertTrue(message.contains("找不到"))
        XCTAssertTrue(message.contains("下一步"))
    }

    /// 路径被改坏时同样要说出来，而且**绝不能照着这个路径去删东西**。
    func testAnUnsafePathIsReportedAndNothingOutsideRecordingsIsTouched() throws {
        try Data("重要的训练数据".utf8).write(to: directory.stateFile)
        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/../state.json"))

        guard case .missing = viewModel.state else { return XCTFail("路径不合法也要说出来") }
        viewModel.delete()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path),
                      "绝不能顺着一个被改坏的路径删到 recordings 外面去")
        XCTAssertTrue(try XCTUnwrap(viewModel.notice).contains("下一步"))
    }

    // MARK: - 删除

    func testDeleteRemovesTheFileAndClearsThePathOnThatSession() throws {
        try makeRecordingFile("a.m4a")
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/a.m4a")] }

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
        viewModel.delete()

        XCTAssertEqual(viewModel.state, .none)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.recordingsDirectory.appending(path: "a.m4a").path))
        XCTAssertEqual(try store.load().sessions.first?.recordingPath, "")
    }

    /// 删录音只删录音。题目、逐字稿、复盘一个都不能动——
    /// 那是用户练了半小时的成果，跟一条音频完全是两回事。
    func testDeletingARecordingKeepsTheTranscriptAndTheReport() throws {
        try makeRecordingFile("a.m4a")
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/a.m4a")] }

        makeViewModel(session("s1", recordingPath: "recordings/a.m4a")).delete()

        let saved = try XCTUnwrap(try store.load().sessions.first)
        XCTAssertEqual(saved.transcript.count, 1)
        XCTAssertEqual(saved.reportPath, "reports/2026-08-06-001.json")
        XCTAssertEqual(saved.goal, "补一个原因和例子")
    }

    func testDeletingOneRecordingLeavesTheOthersAlone() throws {
        try makeRecordingFile("a.m4a")
        try makeRecordingFile("b.m4a")
        try store.mutate {
            $0.sessions = [session("s1", recordingPath: "recordings/a.m4a"),
                           session("s2", recordingPath: "recordings/b.m4a")]
        }

        makeViewModel(session("s1", recordingPath: "recordings/a.m4a")).delete()

        let saved = try store.load()
        XCTAssertEqual(saved.sessions.first(where: { $0.id == "s2" })?.recordingPath,
                       "recordings/b.m4a")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.recordingsDirectory.appending(path: "b.m4a").path))
    }

    /// 文件早就没了也要能把记录里的指向清掉，否则这条会永远显示「找不到」。
    func testClearingAStaleReferenceWorksWithoutTheFile() throws {
        try store.mutate { $0.sessions = [session("s1", recordingPath: "recordings/gone.m4a")] }

        let viewModel = makeViewModel(session("s1", recordingPath: "recordings/gone.m4a"))
        viewModel.clearReferenceOnly()

        XCTAssertEqual(viewModel.state, .none)
        XCTAssertEqual(try store.load().sessions.first?.recordingPath, "")
    }

    /// 删之前必须问一声，而且要说清删了会失去什么、不会失去什么。
    func testTheDeleteConfirmationSaysWhatIsLostAndWhatIsKept() {
        let text = makeViewModel(session("s1", recordingPath: "recordings/a.m4a"))
            .deleteConfirmationText
        XCTAssertTrue(text.contains("听不到"))
        XCTAssertTrue(text.contains("复盘"))
        XCTAssertTrue(text.contains("下一步"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RecordingPlaybackViewModelTests`
Expected: 编译失败 —— `RecordingPlaybackViewModel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/Recording/RecordingPlaybackViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore
import Observation

public enum RecordingPlaybackState: Equatable, Sendable {
    /// 这次练习本来就没录音（开关关着，或那次录音失败了）。不显示播放器，也不报警。
    case none
    /// 记录里有录音路径，但文件不在了。
    /// **必须说出来**——什么都不显示的话，用户会以为自己记错了，或者以为程序坏了。
    case missing(String)
    case ready(URL)
}

@MainActor
@Observable
public final class RecordingPlaybackViewModel {
    public private(set) var state: RecordingPlaybackState = .none
    /// 非 nil 时界面必须显示。
    public private(set) var notice: String?

    public let sessionID: String
    private var relativePath: String
    private let store: StateStore
    private let recordings: RecordingStore

    public init(sessionID: String, relativePath: String,
                store: StateStore, recordings: RecordingStore) {
        self.sessionID = sessionID
        self.relativePath = relativePath
        self.store = store
        self.recordings = recordings
        refresh()
    }

    public func refresh() {
        guard !relativePath.isEmpty else { state = .none; return }
        do {
            let url = try recordings.url(forRelativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                state = .missing(
                    "这次练习的录音文件找不到了（记录里指向 \(relativePath)）。"
                    + "下一步：文件可能被手动删掉或移走了；"
                    + "点「清除这条录音记录」把这个指向去掉，"
                    + "这次练习的题目、逐字稿和复盘都不受影响。")
                return
            }
            state = .ready(url)
        } catch {
            state = .missing(error.localizedDescription)
        }
    }

    public var deleteConfirmationText: String {
        "删掉这条录音之后，就再也听不到这次练习你是怎么说的了。"
        + "这次的题目、逐字稿和复盘都会保留。"
        + "下一步：确定要删就点「删除录音」，不删就点「取消」。"
    }

    /// 删这一条录音：**先删文件，成功之后再清记录里的路径。**
    ///
    /// 顺序不能反。先清路径再删文件的话，删文件万一失败，那个文件就变成了
    /// 界面上看不见、用户也不知道存在的孤儿，只能靠 Finder 手动去翻。
    public func delete() {
        do {
            try recordings.delete(relativePath: relativePath)
        } catch {
            notice = error.localizedDescription
            return
        }
        clearReferenceOnly()
        notice = "录音已删除。这次练习的题目、逐字稿和复盘都还在。"
    }

    /// 只把记录里的路径清掉，不碰任何文件。用于文件已经不在的情况。
    public func clearReferenceOnly() {
        let target = sessionID
        do {
            try store.mutate { state in
                for index in state.sessions.indices where state.sessions[index].id == target {
                    state.sessions[index].recordingPath = ""
                }
                if state.currentSession?.id == target {
                    state.currentSession?.recordingPath = ""
                }
            }
            relativePath = ""
            state = .none
        } catch {
            notice = "训练记录没能更新：\(error.localizedDescription)"
                + "\n下一步：确认数据目录可写、没有别的实例正在运行，然后再试一次。"
        }
    }
}
```

`Sources/IELTSCoachUI/Recording/RecordingPlayerView.swift`（**只给验收要求，布局自定**）：

- 用 `AVAudioPlayer` 播放本地文件即可，**不要引入 AVKit 的 `VideoPlayer`**——那是给视频用的，界面上会出现一块黑框
- `state == .none` 时**整个播放器不渲染**（连标题都不要）。这次本来就没录音，摆一个灰着的播放器只会让人以为坏了
- `state == .missing(message)` 时显示 `message` 全文 + 一个「清除这条录音记录」按钮走 `clearReferenceOnly()`
- `state == .ready(url)` 时显示：播放/暂停按钮（SF Symbols `play.fill` / `pause.fill`，**不许用 emoji**）、可拖动的进度条、`当前时间 / 总时长`（`mm:ss` 格式，**必须 `.monospacedDigit()`**，否则每秒都在抖）、一个「删除录音」按钮
- 「删除录音」必须先弹确认（`.confirmationDialog` 或 `.alert`），文案用 `viewModel.deleteConfirmationText`，确认后调 `delete()`
- `notice != nil` 时显示它
- 视图消失时（`.onDisappear`）必须停掉播放器。不停的话切到别的记录还在响
- 全部取值走 `Palette` / `Spacing` / `Radius`；播放/暂停、进度条、删除都必须能用 Tab 到达且焦点环可见
- 若 `AVAudioPlayer` 初始化抛错（文件损坏、编码不认识），显示中文说明 + 下一步（「这个录音文件打不开，可能已损坏。下一步：点「删除录音」把它清掉，下次练习会重新录。」）。**不许 `try?` 之后一言不发**

`HistoryView` 的改动（**只给验收要求**）：

- 展开某一次练习时，在逐字稿区域**上方**嵌入 `RecordingPlayerView`——先听自己怎么说的，再对照文字，顺序符合「回到你真正说过的话」这件事本身
- 列表里每条练习，若 `recordingPath` 非空，加一个小的 SF Symbol（`waveform`）作为「这条有录音」的标记
- 录音删除之后要触发列表刷新，标记随之消失

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter RecordingPlaybackViewModelTests`
Expected: PASS（9 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 突变验证（两处，都要做）**

**突变 A（静默失败）：** 把 `refresh()` 里 `guard FileManager.default.fileExists` 的 else 分支改成 `{ state = .none; return }`：

Run: `swift test --filter RecordingPlaybackViewModelTests`
Expected: `testAMissingFileIsSaidOutLoudInsteadOfSilentlyShowingNothing` **变红**

这一条守的正是「禁止静默失败」：文件没了却装作这次本来就没录音，用户永远查不出发生了什么。

**突变 B（顺序反了）：** 把 `delete()` 改成先 `clearReferenceOnly()` 再删文件，且删文件失败时不做任何回退：

```swift
    public func delete() {
        clearReferenceOnly()
        try? recordings.delete(relativePath: relativePath)
        notice = "录音已删除。"
    }
```

Run: `swift test --filter RecordingPlaybackViewModelTests`
Expected: `testAnUnsafePathIsReportedAndNothingOutsideRecordingsIsTouched` **变红**（`notice` 里没有「下一步」——失败被 `try?` 吞掉了）

两次都改回，重跑确认全绿。**把四次输出原样写进报告。**

- [ ] **Step 6: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add Sources/IELTSCoachUI/Recording/RecordingPlaybackViewModel.swift \
        Sources/IELTSCoachUI/Recording/RecordingPlayerView.swift \
        Sources/IELTSCoachUI/History/HistoryView.swift \
        Tests/IELTSCoachUITests/RecordingPlaybackViewModelTests.swift
git commit -m "feat(ui): 训练记录页内嵌播放器与单条录音删除"
```

---

## Task 10: 打包脚本校验麦克风用途说明

**Files:**
- Modify: `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/scripts/build-app.sh`

**Interfaces:**
- Consumes: 无
- Produces: 无（脚本行为变更）

**为什么必须加这个检查：** `NSMicrophoneUsageDescription` 一旦从 Info.plist 里掉了，App 在第一次申请麦克风权限时会**直接崩溃**，而且崩溃报告里看不出跟这个键有任何关系。这个键现在是靠 `build-app.sh` 里的 heredoc 生成的——heredoc 是极容易被后续改动误伤的东西。**花三行挡住一次「不知道为什么一开录音就闪退」的排查。**

### 关于 Hardened Runtime 与 entitlement：本阶段不做

spec 第 7 节写着「Hardened Runtime、`com.apple.security.device.audio-input` entitlement、公证脚本在 Phase 5 一并配好」，那里的「Phase 5」指的是 **spec 自己的阶段划分（第 9 节：Phase 5 = 收尾）**，对应 `ROADMAP.md` 的 **Phase 10 · 打包与分发**，不是本阶段。

**本阶段不开 Hardened Runtime**，理由是具体的：开启它会改变签名的形态，而本项目最要紧的一条前提是「重新打包不需要重新授权」（成品标准第 9 条）——辅助功能授权已经绑在当前这套签名上了。为了一个本阶段用不到的东西去动签名，是拿已经验证过的东西去赌。**没有沙盒、没有 Hardened Runtime 时，`Info.plist` 里的 `NSMicrophoneUsageDescription` 就足以让 TCC 正常弹窗**，这一点会在 Task 11 第 1 步的真机上得到确认。

- [ ] **Step 1: 加校验并把版本号推到 0.5.0**

在 `scripts/build-app.sh` 里，把 heredoc 中的

```
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
```

改成

```
    <key>CFBundleShortVersionString</key><string>0.5.0</string>
```

然后在既有的 `plutil -lint` 检查**之后**，紧跟着插入：

```bash
# NSMicrophoneUsageDescription 一旦丢了，App 在第一次申请麦克风权限时会直接崩溃，
# 而崩溃报告里看不出跟这个键有任何关系。上面那段 heredoc 很容易在后续改动里被误伤，
# 所以这里当场验一次。
MIC_USAGE="$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$MIC_USAGE" ]; then
    echo "❌ Info.plist 里缺少 NSMicrophoneUsageDescription。"
    echo "   后果：App 一申请麦克风权限就会闪退，且崩溃信息看不出原因。"
    echo "   下一步：在 build-app.sh 的 Info.plist heredoc 里补回这个键，"
    echo "   内容要用中文说明「录音用来做什么、存在哪里、能不能删」。"
    exit 1
fi
echo "✓ 麦克风用途说明：$MIC_USAGE"
```

- [ ] **Step 2: 验证脚本能跑通**

Run: `cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh`
Expected: 打印 `✓ 麦克风用途说明：开启「保存我的回答录音」后…`，并成功生成 `.build/IELTS Speaking Coach.app`

- [ ] **Step 3: 突变验证（脚本也要验）**

把 heredoc 里 `<key>NSMicrophoneUsageDescription</key>` 与它下面那行 `<string>…</string>` 临时注释掉（或直接删掉），重跑：

Run: `cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh; echo "退出码=$?"`
Expected: 打印 `❌ Info.plist 里缺少 NSMicrophoneUsageDescription`，且**退出码非 0**

改回后重跑确认成功。**把两次输出原样写进报告。**

- [ ] **Step 4: 确认签名仍然稳定（不能被本阶段搞坏）**

Run: `cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh >/dev/null && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated && ./scripts/build-app.sh >/dev/null && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated`
Expected: **两行输出完全一致**，形如 `designated => identifier com.ielts.speakingcoach and certificate leaf = H"…"`

不一致就说明签名被搞不稳定了，辅助功能授权会反复失效——**立刻停下并报告，不要继续往下走**。

- [ ] **Step 5: 提交**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add scripts/build-app.sh
git commit -m "build: 校验麦克风用途说明，版本推到 0.5.0"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `/Users/huchengyuan/Projects/ielts-speaking-coach-mac/docs/phase5-acceptance.md`

前面所有测试跑在编排逻辑与视图模型上，证明的是「换设备时该干的事都干了」，不是「真的插拔耳机时录音没丢」。以下只能人来做。

**准备：戴上一副有线耳机（或任何可以插拔的音频设备）。** 蓝牙耳机也行，验证时用「关闭蓝牙」代替拔线。

- [ ] **Step 1: 授予麦克风权限（只有用户能做，任何自动化都替不了）**

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

1. 按 `⌘,` 打开设置窗口
2. 打开「保存我的回答录音」开关
3. **系统会弹出一个对话框问「IELTS Speaking Coach 想访问麦克风」——请点「允许」**

Expected：
- 弹窗里显示的用途说明是中文的那一句（来自 `NSMicrophoneUsageDescription`）
- 点「允许」之后开关变成「开」，界面上出现同意时间

**若点了「允许」开关却没变成开，或者根本没弹窗，停下并报告。** 前者说明落盘出了问题，后者说明这台机器上这个 bundle id 之前被拒过（去「系统设置 › 隐私与安全性 › 麦克风」里看有没有本应用、是不是关着）。

- [ ] **Step 2: 验证「拒绝」这条路走得通（可选但强烈建议）**

到「系统设置 › 隐私与安全性 › 麦克风」把本应用关掉，回到 App 的设置窗口点开关。

Expected：开关**停在关**，并显示「麦克风权限被拒绝过，系统不会再弹第二次…下一步：打开系统设置…」，还有一个「打开系统设置」按钮，点了能直接跳到麦克风那一页。

**这一步走不通就意味着有用户会卡死在这里**——他点开关、什么都不发生、也不知道去哪儿改。验完把权限打开回来。

- [ ] **Step 3: 录一场真的练习**

关掉终端，只用 App：在今日训练页开始一场练习，正常说几分钟，然后点「我练完了」。

| 看什么 | 判据 |
|---|---|
| 练习界面 | 有没有明确的「● 正在录音」指示？是不是**静止的**（没有闪烁动画）？ |
| 有没有抢戏 | 录音指示有没有把「我练完了」按钮的视觉主位抢走？ |
| 练完 | 训练记录里这一次有没有出现「有录音」的标记？ |

- [ ] **Step 4: 回听**

进「训练记录」页，展开刚才那一次。

| 看什么 | 判据 |
|---|---|
| 播放器 | 在不在逐字稿**上方**？点播放有没有声音？ |
| **总时长** | 是不是跟你实际练的时长接近？**若显示 0:00，回到 Task 5「额外一条」里说的 `file = nil`** |
| 时间数字 | 播放过程中「当前时间 / 总时长」有没有左右抖动？（必须是等宽数字） |
| **录到了谁** | **仔细听：里面是不是只有你自己的声音？** |
| 键盘 | Tab 能不能走到播放/暂停、进度条、删除按钮？焦点环看得见吗？ |

**关于「录到了谁」这一条要如实记录：** 本工具只采集麦克风、不采集系统音频，所以录音里**不会有一条 ChatGPT 的音轨**。但如果你练习时用的是**外放**，麦克风会从空气里把 ChatGPT 的声音一并收进去。这不是 bug，是物理。**戴耳机练就只有自己的声音**——设置页里那句提示说的就是这件事。请分别用耳机和外放各录一小段，把两种情况的实际听感写进验收报告。

- [ ] **Step 5: 插拔耳机（本阶段最关键的一步）**

再练一场（**这一场不必真的答题，说什么都行，目的是验录音**）：

1. **戴着耳机**开始，说 30 秒左右
2. **把耳机拔掉**，接着说 30 秒左右
3. 再**把耳机插回去**，再说 30 秒
4. 点「我练完了」

Expected：

| 判据 | 必须成立 |
|---|---|
| 练习本身 | **没有中断**，照常能练完 |
| 提示 | 练习界面上出现中文提示，说明「因为音频输入设备变化断了一下，已自动接上，切换的一两秒没录进去」，并有「下一步」 |
| 录音文件 | 训练记录里**只有一条**录音，不是两条、三条 |
| 回听 | 拔耳机**之前**说的话在，拔耳机**之后**说的话**也在** |
| 总时长 | 约等于 90 秒（允许因两次切换各少一两秒） |

**任何一条不成立都要停下并如实记录，不许含糊过去。** 这一步验的正是本阶段最核心的风险——「插拔耳机时不能静默丢掉录音」。测试里已经用假实现覆盖过编排逻辑与格式切换，但真实设备切换的时序、`AVAudioEngineConfigurationChange` 到底发不发、发几次，只有真机能告诉你。

**若发现录音只剩前 30 秒：** 说明 `AVAudioEngineCapture` 的重启路径在真机上没走通（多半是通知的 `object:` 过滤或 tap 重装的时机）。**报告实际现象，不要靠猜去改** ——先用 `Console.app` 过滤本应用看有没有音频相关日志。

- [ ] **Step 6: 删除一条录音**

在训练记录里点某条录音的「删除录音」。

| 看什么 | 判据 |
|---|---|
| 确认对话 | 有没有先问一声？文案有没有说清「会失去什么、会保留什么」？ |
| 删完 | 播放器消失了吗？ |
| **逐字稿和复盘** | **还在吗？**（删录音绝不能连累它们） |
| 磁盘 | 设置窗口里的占用数字有没有变小？ |
| 文件 | `ls ~/Library/Application\ Support/IELTS\ Speaking\ Coach/recordings/` 里那个文件是不是真没了？ |

- [ ] **Step 7: 制造一次「文件找不到」**

手动把某条录音文件从 `recordings/` 里移走（**移到桌面，别真删**），回 App 刷新那一页。

Expected：显示「这次练习的录音文件找不到了…下一步：点「清除这条录音记录」…」，点了之后这条恢复成「没有录音」的样子。把文件移回来验证一下没有别的副作用。

- [ ] **Step 8: 关掉再打开开关，检查同意时间戳**

1. 设置窗口里关掉开关 → 提示里应当说明「已经录下的录音不会被删除」
2. 再打开 → 应当记下一个**新的**同意时间

```bash
python3 -c "import json,pathlib;p=pathlib.Path.home()/'Library/Application Support/IELTS Speaking Coach/state.json';print(json.loads(p.read_text())['settings'])"
```

Expected：关掉时 `{"recordingEnabled": false, "recordingConsentAt": ""}`；重开后 `recordingConsentAt` 是刚才那一刻，不是第一次开启的那一刻。

- [ ] **Step 9: 界面验收（对照 DESIGN-SYSTEM.md 第 6 节）**

逐条走那十条清单，其中与本阶段最相关的四条：

- 打开系统「减弱动态效果」后，录音指示与播放器**无任何动画**且功能正常
- 系统文字调到最大时，设置页与播放器**不截断、不重叠**
- 播放器的时间数字与占用数字是**等宽数字**，变化时不抖动
- 视图里没有任何字面颜色值、字号、圆角

- [ ] **Step 10: 记录并提交**

把每一步的实际结果写进 `docs/phase5-acceptance.md`，含截图或原文描述。**包括不好的部分**——「哪里让我不想用」这类信息只有你有（成品标准第 5 节）。特别要写清：

- 插拔耳机那一场，录音到底完整不完整
- 用外放录出来的东西听着有多吵，这个提示够不够
- 权限被拒之后的引导，一个不懂技术的人能不能照着做出来

```bash
cd /Users/huchengyuan/Projects/ielts-speaking-coach-mac
git add docs/phase5-acceptance.md
git commit -m "docs: Phase 5 真机验收结果"
```

---

## Phase 5 完成标准

全部达成才算做完。

- [ ] `swift test` 全绿，且总耗时仍在 2 秒以内（本阶段新增的测试全部是纯逻辑与小文件 IO，不该拖慢套件）
- [ ] 五个 target 编译通过，`IELTSCoachCore` **仍然只依赖 Foundation**（`grep -rn "import AVFoundation\|import AppKit\|import SwiftUI" Sources/IELTSCoachCore/` 必须**零命中**）
- [ ] `./scripts/build-app.sh` 产出可双击打开的 `.app`，且连跑两次 `codesign -d -r-` 的 designated 完全一致
- [ ] 「保存我的回答录音」开关**默认关**，打开时记录同意时间戳，关闭时清空
- [ ] **权限被拒时开关停在关**，并给出「去系统设置」的可执行引导
- [ ] 录音只采集麦克风，**没有任何 ScreenCaptureKit 或系统音频采集代码**（`grep -rn "ScreenCaptureKit\|SCStream" Sources/` 必须零命中）
- [ ] **真机上练到一半插拔耳机，录音没有丢**：要么自动接上且完整，要么已录部分完整落盘并给出中文说明
- [ ] 训练记录页能回听、能单条删除；删录音不影响题目、逐字稿、复盘
- [ ] 录音文件找不到时**明说**，不是静静地什么都不显示
- [ ] 设置页显示录音数量与磁盘占用，孤儿文件会被报出来
- [ ] 每个关键任务都做过突变验证，改了哪一行、哪条测试变红，都写进了报告
- [ ] `docs/phase5-acceptance.md` 已产出，包含插拔耳机那一场的真实结果

达成后进 Phase 6：复训中心。

---

## 本阶段明确不做的事

写下来是为了防止范围扩大，也为了后面的人不用再重新讨论一遍。

| 不做 | 为什么 |
|---|---|
| **不录 ChatGPT 的声音** | 需要「屏幕录制」权限，字面含义是「能看你屏幕」，观感代价不值。考官问了什么由 Phase 4 的逐字稿给文字（DEFINITION-OF-DONE 第 4 节、ROADMAP 3.3）|
| **不做双轨混音、不做时间对齐** | 上一条的直接推论。没有第二条轨，就没有对齐问题，也不会有回声 |
| **不做语音转文字 / 不做发音评分** | 录音的用途是「听见自己怎么说的」。转文字有逐字稿，评分则违反「不预测雅思分数」（DEFINITION-OF-DONE 第 4 节）|
| **不做录音剪辑、裁剪、导出** | 用户要导出的话，`recordings/` 就是普通的 m4a，Finder 里拖走即可 |
| **不做录音自动清理** | 用户的录音只有用户能决定删不删。本阶段只**报出**占用与孤儿，绝不代劳 |
| **不开 Hardened Runtime、不加 entitlement、不做公证** | 属于 ROADMAP 的 Phase 10。为一个本阶段用不到的东西去动签名，等于拿已经验证过的「重新打包不用重新授权」去赌 |
| **不做录音波形图** | 好看，但对「听见自己怎么说的」没有帮助，而绘制波形要把整个文件解码一遍 |
| **不改 `schemaVersion`** | 录音只用到 `PracticeSession.recordingPath` 与 `CoachSettings` 里那两个字段，它们本来就在 schema 3 里。改版本号会破坏与上游及 Windows 版的互通（spec 4.6）|
