# Phase 2：ChatGPTBridge + coach 命令行工具

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个命令行工具 `coach`，让用户能真的用它完成一次雅思口语练习并存下结构化复盘。

**Architecture:** 新增 `ChatGPTBridge` 模块，它是全工程唯一与 ChatGPT.app 交互的地方。为了让它可测，所有原始 Accessibility 调用收敛到一个 `AXAccess` protocol 后面——真实实现调 `AXUIElement` API，测试用假实现喂预设的元素树。`coach` 可执行文件把 `IELTSCoachCore` 的业务逻辑与 `ChatGPTBridge` 的驱动能力串成一场完整练习。界面留到 Phase 3。

**Tech Stack:** Swift 6.3.3、SPM、XCTest、AppKit、ApplicationServices。无第三方依赖。

## Global Constraints

- 最低系统版本 `macOS 14.0`
- `IELTSCoachCore` **只允许依赖 Foundation**。本阶段不得给它加任何新依赖
- `ChatGPTBridge` 可依赖 Core、AppKit、ApplicationServices
- 目标 ChatGPT 应用固定为 bundle id **`com.openai.codex`**（新 ChatGPT.app）。`com.openai.chat`（Classic）**没有 live 语音**，只在「装错了」的提示里出现
- 所有面向用户的错误信息必须是中文，且同时说明「发生了什么」和「下一步做什么」。**该标准已扩展到警告**
- **禁止静默失败，禁止无限等待**
- 复盘 JSON 内部 snake_case；`state.json` 顶层 camelCase
- 测试用 XCTest
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准，不接受从二进制内容、框架清单、Info.plist 措辞推断出的结论

## 三条实测硬规则（spec 2.3.1 / 2.3.2 / 2.3.3，违反必出 bug）

1. **按标签找元素必须加结构约束。** 控制按钮的子节点恰好一个且为 `AXImage`；侧边栏会话行嵌套 `AXButton`（含 `Pin chat`/`Archive chat`）。标签会变（实测见过 `Start voice chat` / `Start new voice chat` / `New voice chat` 三种），且**侧边栏的同名会话是本产品自己制造的**——每开一次语音 ChatGPT 就生成一条 `New voice chat`，用得越久误击中概率越高。
2. **元素出现有延迟。** 每个操作必须「等目标元素出现 → 操作 → 验证状态变化」。`kAXPressAction` 返回 0 **不等于**动作生效。
3. **`Voice chat active` 是会话级常驻**，静默 20 秒不消失（实测 40 次采样 0 次消失）。1.5 秒去抖窗口安全，**不要**加回上游的最短时长门槛。

## 测试有效性（本项目已消灭 14 处空转测试）

绿灯不等于有覆盖。每条测试都要能回答：**把被测逻辑改成空实现，这条测试会不会红？**

- 被测函数有多条降级路径时，走 happy path 的测试只能证明「函数能用」，不能证明「这条路径能用」。要验证第 N 条路径，必须先让第 1..N-1 条失效
- 修 bug 时新增的测试，必须先在未修复的代码上确认它变红

## 前置条件

| 条件 | 状态 |
|---|---|
| Swift 6.3.3 / Xcode 26.6 | ✅ 已装，许可已同意 |
| `IELTSCoachCore` | ✅ 115 测试全绿 |
| `axprobe` | ✅ doctor / dump / press 三个子命令可用 |
| ChatGPT.app (`com.openai.codex`) | ✅ 已装并验证可驱动 |
| 辅助功能权限 | ✅ 已授予运行终端 |

## File Structure

```
Sources/
├── IELTSCoachCore/              不变（本阶段只读不改）
├── ChatGPTBridge/               新增
│   ├── AXAccess.swift           protocol：原始 AX 调用的接缝，为可测性而存在
│   ├── AXElementRef.swift       元素引用与快照类型（不含 AXUIElement，可在测试里构造）
│   ├── LiveAXAccess.swift       AXAccess 的真实实现，唯一直接调 AXUIElement API 的文件
│   ├── AXLocator.swift          结构化查找 + waitForElement 重试原语
│   ├── ChatGPTLabels.swift      所有标签候选集合与结构判据，集中一处便于 ChatGPT 改版时修改
│   ├── CoachBridge.swift        对外 protocol + 相关类型
│   ├── AXDriver.swift           CoachBridge 的 AX 实现
│   └── ClipboardFallback.swift  剪贴板降级路径
├── axprobe/                     改为依赖 ChatGPTBridge，删掉自己那份 AXTree
└── coach/                       新增，命令行入口
    ├── main.swift               子命令分发
    ├── DoctorCommand.swift      环境预检
    ├── QuestionsCommand.swift   题库导入与列表
    └── PracticeCommand.swift    完整练习流程
Tests/
├── IELTSCoachCoreTests/         不变
└── ChatGPTBridgeTests/          新增
    ├── FakeAXAccess.swift       假实现，可编程的元素树
    ├── AXLocatorTests.swift
    ├── AXDriverTests.swift
    └── ChatGPTLabelsTests.swift
```

**为什么要 `AXAccess` 这层接缝：** `AXDriver` 里真正值钱的是「按结构筛掉侧边栏同名项」「等元素出现再操作」「操作后验证状态变化」「AX 失败降级到剪贴板」这些逻辑。它们全都能在没有 ChatGPT 的情况下测——前提是原始 AX 调用可以被替换。没有这层接缝，这些逻辑就只能靠人工真机验证，而真机验证既慢又不可重复。

---

## Task 1: 建 ChatGPTBridge 模块并把 AXTree 迁进去

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ChatGPTBridge/AXElementRef.swift`
- Create: `Sources/ChatGPTBridge/AXAccess.swift`
- Create: `Sources/ChatGPTBridge/LiveAXAccess.swift`
- Delete: `Sources/axprobe/AXTree.swift`
- Modify: `Sources/axprobe/Doctor.swift`、`DumpCommand.swift`、`PressCommand.swift`（改为 `import ChatGPTBridge`）
- Create: `Tests/ChatGPTBridgeTests/FakeAXAccess.swift`

**Interfaces:**
- Consumes: 无
- Produces: `AXElementRef`、`AXNodeSnapshot`、`protocol AXAccess`、`LiveAXAccess`、`FakeAXAccess`

- [ ] **Step 1: 定义与 AXUIElement 解耦的元素类型**

`Sources/ChatGPTBridge/AXElementRef.swift`：

```swift
import Foundation

/// 元素的不透明引用。真实实现里包着 AXUIElement，测试实现里就是一个整数 id。
/// 这样上层逻辑不直接接触 AXUIElement，才能在没有 ChatGPT 的情况下被测试。
public struct AXElementRef: Hashable, Sendable {
    public let rawID: Int
    /// 快照代次，每次 `snapshotTree()` 递增。
    ///
    /// **不能省。** rawID 每次快照都从 0 重新编号，若不校验代次，跨快照复用旧引用时
    /// `press`/`setValue` 不会安全失败，而会**静默命中新树里编号相同的另一个元素** ——
    /// 比「找不到」危险得多。而 AXLocator/AXDriver 的核心就是轮询（反复取快照），
    /// 「拿到元素 → 等某个状态 → 按下它」是极自然的写法，正好会踩中。
    public let epoch: Int
    public init(rawID: Int, epoch: Int) { self.rawID = rawID; self.epoch = epoch }
}

/// 元素在某一时刻的属性快照。
public struct AXNodeSnapshot: Equatable, Sendable {
    public var element: AXElementRef
    public var role: String
    public var subrole: String
    public var title: String
    public var value: String
    public var descriptionText: String
    /// kAXIdentifierAttribute。**不能省** —— axprobe dump 靠它区分元素，
    /// 实测 640 个节点里有 152 个（24%）带这个属性。ChatGPT 改版后做取证对比时，
    /// 标签本身会变（已见过三种语音按钮标签），identifier 是少数相对稳定的线索。
    public var identifier: String
    public var childCount: Int
    public var childRoles: [String]

    public init(element: AXElementRef, role: String, subrole: String = "", title: String = "",
                value: String = "", descriptionText: String = "", identifier: String = "",
                childCount: Int = 0, childRoles: [String] = []) {
        self.element = element; self.role = role; self.subrole = subrole
        self.title = title; self.value = value; self.descriptionText = descriptionText
        self.identifier = identifier
        self.childCount = childCount; self.childRoles = childRoles
    }

    /// 标签优先取 description，为空时退到 title。ChatGPT 的控件两者都可能承载文字。
    public var label: String { descriptionText.isEmpty ? title : descriptionText }

    /// spec 2.3.1 的结构判据：真控制按钮的子节点恰好一个且为 AXImage。
    /// 侧边栏会话行嵌套 AXButton（含 Pin chat / Archive chat），不满足此条件。
    public var isIconOnlyControl: Bool { childRoles == ["AXImage"] }
}
```

- [ ] **Step 2: 定义 AXAccess 接缝**

`Sources/ChatGPTBridge/AXAccess.swift`：

```swift
import Foundation

/// 原始 Accessibility 调用的接缝。**唯一目的是可测性** ——
/// 有了它，AXDriver 里那些「结构筛选、等待重试、操作后验证、降级」的逻辑
/// 才能在没有 ChatGPT 的环境下被测试。
public protocol AXAccess: Sendable {
    /// 目标应用是否已安装
    func isTargetInstalled() -> Bool
    /// 目标应用是否正在运行
    func isTargetRunning() -> Bool
    /// 是否已获得辅助功能权限
    func isAccessibilityTrusted() -> Bool
    /// 启动目标应用（已在运行则无操作）
    func launchTarget() throws
    /// 唤醒 Chromium 的惰性无障碍树。返回是否观察到 AXWebArea。
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool
    /// 深度优先遍历当前树，返回全部节点快照。**每次调用都会开启新的代次**，
    /// 此前取得的 `AXElementRef` 随即失效。
    func snapshotTree() -> [AXNodeSnapshot]
    /// 设置元素的 kAXValueAttribute。返回是否成功。
    /// 元素来自过期代次时必须返回 false，不得操作任何元素。
    func setValue(_ text: String, on element: AXElementRef) -> Bool
    /// 对元素执行 kAXPressAction。返回是否成功。
    /// **注意：返回 true 不等于动作生效**（spec 2.3.1），调用方必须另行验证状态变化。
    /// 元素来自过期代次时必须返回 false，不得操作任何元素。
    func press(_ element: AXElementRef) -> Bool
    /// 向目标应用发送回车键
    func sendReturnKey() -> Bool
}
```

- [ ] **Step 3: 写 LiveAXAccess**

`Sources/ChatGPTBridge/LiveAXAccess.swift`：把原 `Sources/axprobe/AXTree.swift` 的实现搬过来并适配到上述 protocol。要点：

- 内部维护 `[Int: AXUIElement]` 映射，`snapshotTree()` 时分配 `rawID`。**每次 `snapshotTree()` 都要清空并重建映射**——AXUIElement 在界面重绘后会失效，缓存旧引用会操作到已消失的元素
- `wakeAccessibilityTree` 沿用已验证的做法：对 application 元素设 `AXManualAccessibility` 与 `AXEnhancedUserInterface`（**两者返回错误码是正常的，不得据此判定失败**），然后轮询直到出现 `AXWebArea` 或超时
- `bundleID` 常量为 `"com.openai.codex"`，Classic 的 `"com.openai.chat"` 单独定义供误装提示用
- `sendReturnKey` 用 `CGEvent(keyboardEventSource:virtualKey:keyDown:)`，keyCode 36

- [ ] **Step 4: 写 FakeAXAccess**

`Tests/ChatGPTBridgeTests/FakeAXAccess.swift`：

```swift
import Foundation
@testable import ChatGPTBridge

/// 可编程的假 AX 环境。测试通过设置 `nodes` 来摆出任意元素树，
/// 通过 `onPress` / `onSetValue` 注入「按下之后树会怎么变」的行为。
final class FakeAXAccess: AXAccess, @unchecked Sendable {
    var installed = true
    var running = true
    var trusted = true
    var wakeSucceeds = true
    var nodes: [AXNodeSnapshot] = []

    private(set) var pressedElements: [AXElementRef] = []
    private(set) var setValues: [(AXElementRef, String)] = []
    private(set) var returnKeyCount = 0
    private(set) var snapshotCount = 0

    /// 按下某元素后对树做的变更。用于模拟「按下启动语音 → Voice chat active 出现」。
    var onPress: ((AXElementRef, inout [AXNodeSnapshot]) -> Void)?
    var pressSucceeds = true

    func isTargetInstalled() -> Bool { installed }
    func isTargetRunning() -> Bool { running }
    func isAccessibilityTrusted() -> Bool { trusted }
    func launchTarget() throws { running = true }
    func wakeAccessibilityTree(timeout: TimeInterval) -> Bool { wakeSucceeds }
    func snapshotTree() -> [AXNodeSnapshot] { snapshotCount += 1; return nodes }
    func setValue(_ text: String, on element: AXElementRef) -> Bool {
        setValues.append((element, text)); return true
    }
    func press(_ element: AXElementRef) -> Bool {
        pressedElements.append(element)
        guard pressSucceeds else { return false }
        onPress?(element, &nodes)
        return true
    }
    func sendReturnKey() -> Bool { returnKeyCount += 1; return true }
}
```

- [ ] **Step 5: 更新 Package.swift**

```swift
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"])
    ]
```

`Sources/coach/main.swift` 先放一个只打印用法的占位，保证 target 目录存在（SPM 要求已声明的 target 必须有源码目录，否则会回退去扫包根并报 overlapping sources）。

- [ ] **Step 6: 改 axprobe 使用新模块**

`Doctor.swift`、`DumpCommand.swift`、`PressCommand.swift` 顶部加 `import ChatGPTBridge`，把 `AXTree.xxx` 调用改为通过 `LiveAXAccess` 的等价方法。**axprobe 的对外行为一个字都不能变**——它是排障工具，输出格式变了会让人对不上历史 dump。

- [ ] **Step 7: 验证**

Run: `swift build && swift test`
Expected: 115 个既有测试全部通过，构建无警告

Run: `swift run axprobe doctor`
Expected: 输出与迁移前一致

- [ ] **Step 8: 提交**

```bash
git add Package.swift Sources/ Tests/
git commit -m "refactor: 抽出 ChatGPTBridge 模块，AX 调用收敛到 AXAccess 接缝"
```

---

## Task 2: ChatGPTLabels —— 标签候选与结构判据集中管理

**Files:**
- Create: `Sources/ChatGPTBridge/ChatGPTLabels.swift`
- Create: `Tests/ChatGPTBridgeTests/ChatGPTLabelsTests.swift`

**Interfaces:**
- Consumes: `AXNodeSnapshot`
- Produces: `enum ChatGPTLabels`，含 `startVoice`/`stopVoice`/`voiceActiveIndicator`/`composer` 四组候选与 `matchControl(_:among:)`

**这个文件是 ChatGPT 改版时的唯一修改点。** 所有魔法字符串集中于此，别处不得硬编码标签。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import ChatGPTBridge

final class ChatGPTLabelsTests: XCTestCase {
    private func node(_ id: Int, role: String, desc: String, childRoles: [String]) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: role, descriptionText: desc,
                       childCount: childRoles.count, childRoles: childRoles)
    }

    func testMatchesIconOnlyStartVoiceButton() {
        let button = node(1, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [button])?.element,
                       AXElementRef(rawID: 1))
    }

    func testRejectsSidebarRowWithSameLabel() {
        // 侧边栏会话行：标签命中但结构不符（嵌套按钮而非单个图标）
        let row = node(2, role: "AXButton", desc: "New voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        XCTAssertNil(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row]),
                     "侧边栏同名会话行不得被当成控制按钮")
    }

    func testPrefersControlButtonWhenSidebarRowComesFirst() {
        // ⚠️ 两者标签必须**相同**，否则这条测试是装饰性的：
        // matchControl 按候选集合顺序查找，标签不同时靠优先级就能选对，
        // 结构判据根本不会被执行，删掉它这条测试照样绿。
        // 标签相同时，唯一的区分依据才是结构。
        let row = node(2, role: "AXButton", desc: "Start voice chat",
                       childRoles: ["AXGroup", "AXButton", "AXButton"])
        let button = node(3, role: "AXButton", desc: "Start voice chat", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(ChatGPTLabels.startVoice, among: [row, button])?.element,
                       AXElementRef(rawID: 3, epoch: 0),
                       "侧边栏行排在前面时仍必须选中结构合法的那个")
    }

    func testAcceptsCheckBoxControls() {
        // 静音类控件是 AXCheckBox subrole=AXToggleButton，同样单个 AXImage 子节点
        let mute = node(4, role: "AXCheckBox", desc: "Mute microphone", childRoles: ["AXImage"])
        XCTAssertEqual(ChatGPTLabels.matchControl(["Mute microphone"], among: [mute])?.element,
                       AXElementRef(rawID: 4))
    }

    func testStartVoiceCandidatesCoverAllObservedLabels() {
        // 实测在同一台机器上先后出现过这三种，缺一会导致启动语音失败
        for observed in ["Start voice chat", "Start new voice chat", "New voice chat"] {
            XCTAssertTrue(ChatGPTLabels.startVoice.contains(observed), "候选集合缺少实测标签：\(observed)")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ChatGPTLabelsTests`
Expected: 编译失败 —— `ChatGPTLabels` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation

/// ChatGPT.app 的界面特征。**ChatGPT 改版时只改这个文件。**
/// 别处不得硬编码任何界面标签。
public enum ChatGPTLabels {
    /// 启动语音。实测在同一台机器上先后出现过三种标签，全部保留。
    public static let startVoice = ["Start voice chat", "Start new voice chat", "New voice chat"]
    public static let stopVoice = ["Stop voice chat"]
    /// 语音进行中的标志。实测为会话级常驻，静默不消失（spec 2.3.3）。
    public static let voiceActiveIndicator = "Voice chat active"
    public static let composerDescription = "Work with ChatGPT"

    /// 按标签 + 结构双重条件查找控制元素。
    ///
    /// **只按标签匹配是缺陷**（spec 2.3.1）：ChatGPT 每开一次语音就自动生成一条
    /// 名为 "New voice chat" 的侧边栏会话，而侧边栏在深度优先遍历里常常排在真按钮前面。
    /// 只取第一个命中会点中历史会话——实测发生过，且返回码是成功的。
    /// 控制元素的合法 role。静音类是 AXCheckBox（subrole=AXToggleButton），
    /// 启停语音是 AXButton，两者结构判据相同（实测确认）。
    static let controlRoles: Set<String> = ["AXButton", "AXCheckBox"]

    public static func matchControl(_ candidates: [String],
                                    among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        for candidate in candidates {
            if let hit = nodes.first(where: {
                controlRoles.contains($0.role) && $0.label == candidate && $0.isIconOnlyControl
            }) { return hit }
        }
        return nil
    }

    /// 标签命中但结构不符的元素。查找失败时用它给出有用的诊断，而不是干巴巴一句「没找到」。
    ///
    /// 判据必须与 `matchControl` **对称**（role + label + 结构三重）。只查 label 和结构的话，
    /// 会漏报「label 命中、role 不符、但恰好只有一个 AXImage 子节点」的元素，
    /// 让诊断看起来比实际情况更干净——排查时反而误导人。
    public static func structuralMismatches(_ candidates: [String],
                                            among nodes: [AXNodeSnapshot]) -> [AXNodeSnapshot] {
        nodes.filter {
            candidates.contains($0.label) && !(controlRoles.contains($0.role) && $0.isIconOnlyControl)
        }
    }

    /// 找输入框。**不做无条件兜底。**
    ///
    /// 退到「任意 AXTextArea」会踩 `matchControl` 刻意规避的同款反模式：界面上若有别的
    /// 多行文本框（搜索框、重命名会话的输入框，或改版后被 Chromium 映射成 AXTextArea 的
    /// 任何东西），考官提示词会被**静默**写进去——用户只看到「点了开始什么都没发生」，
    /// 毫无线索可查。**响亮的失败比静默的错误好。**
    ///
    /// 折中：整个界面只有一个 AXTextArea 时不存在歧义，用它是安全的；
    /// 两个以上时返回 nil，由调用方报错并列出候选供诊断。
    public static func composer(among nodes: [AXNodeSnapshot]) -> AXNodeSnapshot? {
        if let exact = nodes.first(where: {
            $0.role == "AXTextArea" && $0.descriptionText == composerDescription
        }) { return exact }
        let textAreas = nodes.filter { $0.role == "AXTextArea" }
        return textAreas.count == 1 ? textAreas[0] : nil
    }

    /// 界面上全部的文本框。`composer` 找不到时用于给出可执行的诊断。
    public static func candidateComposers(among nodes: [AXNodeSnapshot]) -> [AXNodeSnapshot] {
        nodes.filter { $0.role == "AXTextArea" }
    }

    public static func isVoiceActive(_ nodes: [AXNodeSnapshot]) -> Bool {
        nodes.contains { $0.role == "AXImage" && $0.descriptionText == voiceActiveIndicator }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ChatGPTLabelsTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

把 `matchControl` 里的 `&& $0.isIconOnlyControl` 删掉，重跑：`testRejectsSidebarRowWithSameLabel` 与 `testPrefersControlButtonWhenSidebarRowComesFirst` 必须变红。确认后改回。把失败输出记进报告。

- [ ] **Step 6: 提交**

```bash
git add Sources/ChatGPTBridge/ChatGPTLabels.swift Tests/ChatGPTBridgeTests/
git commit -m "feat(bridge): 界面标签与结构判据集中管理"
```

---

## Task 3: AXLocator —— 等待重试原语

**Files:**
- Create: `Sources/ChatGPTBridge/AXLocator.swift`
- Create: `Sources/ChatGPTBridge/CoachBridge.swift`（本任务只放 `BridgeError`，protocol 在 Task 4 补）
- Create: `Tests/ChatGPTBridgeTests/AXLocatorTests.swift`

**Interfaces:**
- Consumes: `AXAccess`、`AXNodeSnapshot`、`ChatGPTLabels`
- Produces: `struct AXLocator`，含 `init(access:pollInterval:)`、`waitForControl(_:timeout:)`、`waitForComposer(timeout:)`、`waitUntil(_:timeout:)`

**为什么需要它：** spec 2.3.2 是实测出来的——按下启动语音成功后**立即**查找 `Stop voice chat` 会报找不到，等界面渲染完成后重试则存在。语音浮层的渲染晚于 `kAXPressAction` 返回。任何「按完就假设下一个元素已就位」的代码都会随机失败。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import ChatGPTBridge

final class AXLocatorTests: XCTestCase {
    private func control(_ id: Int, _ desc: String) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: "AXButton",
                       descriptionText: desc, childCount: 1, childRoles: ["AXImage"])
    }

    func testFindsControlAlreadyPresent() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Stop voice chat")]
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertEqual(try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.5).element,
                       AXElementRef(rawID: 1))
    }

    func testWaitsForControlThatAppearsLate() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        // 第 3 次快照时元素才出现，模拟语音浮层渲染延迟
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [control(2, "Stop voice chat")]
        }
        XCTAssertEqual(try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 2.0).element,
                       AXElementRef(rawID: 2))
    }

    func testTimeoutErrorIsChineseAndActionable() {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.1)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("下一步"), "超时错误缺少下一步指引：\(message)")
            XCTAssertTrue(message.contains("Stop voice chat"), "错误信息应指明找的是什么：\(message)")
        }
    }

    func testTimeoutReportsStructuralMismatchesWhenLabelMatched() {
        let access = FakeAXAccess()
        // 标签对上了但结构不符——这正是「点中侧边栏同名会话」那个 bug 的现场
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 3), role: "AXButton",
                                       descriptionText: "New voice chat",
                                       childCount: 3, childRoles: ["AXGroup", "AXButton", "AXButton"])]
        let locator = AXLocator(access: access, pollInterval: 0.01)
        XCTAssertThrowsError(try locator.waitForControl(ChatGPTLabels.startVoice, timeout: 0.1)) { error in
            XCTAssertTrue("\(error)".contains("结构不符"),
                          "标签命中但结构不符时，错误信息必须说清楚，否则用户完全看不出问题在哪：\(error)")
        }
    }

    func testWaitUntilPollsUntilConditionHolds() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 4), role: "AXImage",
                                           descriptionText: ChatGPTLabels.voiceActiveIndicator)]
        }
        try locator.waitUntil({ ChatGPTLabels.isVoiceActive($0) }, timeout: 2.0,
                              describing: "语音开始")
    }

    func testPollsRepeatedlyRatherThanSnapshottingOnce() throws {
        let access = FakeAXAccess()
        access.nodes = []
        let locator = AXLocator(access: access, pollInterval: 0.01)
        _ = try? locator.waitForControl(ChatGPTLabels.stopVoice, timeout: 0.1)
        XCTAssertGreaterThan(access.snapshotCount, 2,
                             "必须反复取快照，只取一次就等于没有等待重试")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AXLocatorTests`
Expected: 编译失败 —— `AXLocator` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 「等目标元素出现 → 再操作」的原语。
///
/// spec 2.3.2 是实测结论：按下启动语音成功后**立即**查找 Stop voice chat 会报找不到，
/// 等界面渲染完成后重试则存在。语音浮层的渲染晚于 kAXPressAction 返回。
/// 任何「按完就假设下一个元素已就位」的代码都会随机失败。
public struct AXLocator: Sendable {
    private let access: any AXAccess
    private let pollInterval: TimeInterval

    public init(access: any AXAccess, pollInterval: TimeInterval = 0.3) {
        self.access = access
        self.pollInterval = pollInterval
    }

    public func waitForControl(_ candidates: [String], timeout: TimeInterval) throws -> AXNodeSnapshot {
        var lastNodes: [AXNodeSnapshot] = []
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            lastNodes = access.snapshotTree()
            if let hit = ChatGPTLabels.matchControl(candidates, among: lastNodes) { return hit }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline

        let mismatches = ChatGPTLabels.structuralMismatches(candidates, among: lastNodes)
        if !mismatches.isEmpty {
            throw BridgeError.elementNotFound(
                "找到了标签为「\(candidates[0])」的元素 \(mismatches.count) 个，但都结构不符，"
                + "不是真正的控制按钮（很可能是侧边栏里的同名历史会话）。"
                + "下一步：确认 ChatGPT 窗口停在对话界面而不是设置或侧边栏；"
                + "若 ChatGPT 刚更新过，运行 axprobe dump 查看当前界面结构。")
        }
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到「\(candidates[0])」。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话；"
            + "若 ChatGPT 刚更新过，运行 axprobe dump 查看当前界面结构。")
    }

    public func waitForComposer(timeout: TimeInterval) throws -> AXNodeSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = ChatGPTLabels.composer(among: access.snapshotTree()) { return hit }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        throw BridgeError.elementNotFound(
            "等了 \(Int(timeout)) 秒仍未找到 ChatGPT 的输入框。"
            + "下一步：确认 ChatGPT 窗口可见且已打开一个会话，然后重试。")
    }

    /// 轮询直到条件成立。用于「操作后验证状态真的变了」——
    /// kAXPressAction 返回成功不等于动作生效（spec 2.3.1）。
    public func waitUntil(_ condition: ([AXNodeSnapshot]) -> Bool, timeout: TimeInterval,
                          describing what: String) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition(access.snapshotTree()) { return }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        throw BridgeError.stateNotReached(
            "等了 \(Int(timeout)) 秒，\(what)仍未发生。"
            + "下一步：看一眼 ChatGPT 窗口当前的状态；若与预期不符，运行 axprobe dump 收集诊断信息。")
    }
}
```

同时新建 `Sources/ChatGPTBridge/CoachBridge.swift` 的错误类型部分（完整 protocol 在 Task 4）：

```swift
import Foundation

public enum BridgeError: Error, Equatable, LocalizedError {
    case targetNotInstalled(String)
    case accessibilityDenied(String)
    case treeNotAwake(String)
    case elementNotFound(String)
    case stateNotReached(String)
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .targetNotInstalled(let m), .accessibilityDenied(let m), .treeNotAwake(let m),
             .elementNotFound(let m), .stateNotReached(let m), .actionFailed(let m):
            return m
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AXLocatorTests`
Expected: PASS（6 个测试）

- [ ] **Step 5: 突变验证**

把 `waitForControl` 的轮询循环改成只取一次快照就返回失败，重跑：`testWaitsForControlThatAppearsLate` 与 `testPollsRepeatedlyRatherThanSnapshottingOnce` 必须变红。确认后改回。

- [ ] **Step 6: 提交**

```bash
git add Sources/ChatGPTBridge/ Tests/ChatGPTBridgeTests/
git commit -m "feat(bridge): 等待重试原语与中文可执行错误信息"
```

---

## Task 4: CoachBridge protocol 与 AXDriver

**Files:**
- Modify: `Sources/ChatGPTBridge/CoachBridge.swift`
- Create: `Sources/ChatGPTBridge/AXDriver.swift`
- Create: `Tests/ChatGPTBridgeTests/AXDriverTests.swift`

**Interfaces:**
- Consumes: `AXAccess`、`AXLocator`、`ChatGPTLabels`、`BridgeError`
- Produces:
  - `struct BridgeReadiness { let ok: Bool; let messages: [String] }`
  - `protocol CoachBridge`：`preflight()`、`sendText(_:)`、`startVoice()`、`isVoiceActive()`、`endVoice()`、`captureLatestAssistantMessage()`
  - `final class AXDriver: CoachBridge`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import ChatGPTBridge

final class AXDriverTests: XCTestCase {
    private func composer(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: "AXTextArea",
                       descriptionText: ChatGPTLabels.composerDescription)
    }
    private func control(_ id: Int, _ desc: String) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: "AXButton",
                       descriptionText: desc, childCount: 1, childRoles: ["AXImage"])
    }
    private func voiceActive(_ id: Int) -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: id), role: "AXImage",
                       descriptionText: ChatGPTLabels.voiceActiveIndicator)
    }
    private func driver(_ access: FakeAXAccess) -> AXDriver {
        AXDriver(access: access, locator: AXLocator(access: access, pollInterval: 0.01))
    }

    func testPreflightFailsWhenTargetMissing() {
        let access = FakeAXAccess(); access.installed = false
        let readiness = driver(access).preflight()
        XCTAssertFalse(readiness.ok)
        XCTAssertTrue(readiness.messages.joined().contains("下一步"))
    }

    func testPreflightFailsWithoutAccessibilityPermission() {
        let access = FakeAXAccess(); access.trusted = false
        let readiness = driver(access).preflight()
        XCTAssertFalse(readiness.ok)
        XCTAssertTrue(readiness.messages.joined().contains("辅助功能"))
    }

    func testSendTextWritesComposerThenPressesReturn() throws {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]
        try driver(access).sendText("你好")
        XCTAssertEqual(access.setValues.count, 1)
        XCTAssertEqual(access.setValues[0].1, "你好")
        XCTAssertEqual(access.returnKeyCount, 1, "写入之后必须真的发送")
    }

    func testStartVoiceVerifiesIndicatorAppeared() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat")]
        access.onPress = { _, nodes in nodes.append(self.voiceActive(9)) }
        try driver(access).startVoice()
        XCTAssertEqual(access.pressedElements, [AXElementRef(rawID: 1)])
    }

    func testStartVoiceFailsWhenIndicatorNeverAppears() {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Start voice chat")]
        access.onPress = nil   // 按下了但界面没变 —— 正是「假阳性点击」的现场
        XCTAssertThrowsError(try driver(access).startVoice()) { error in
            XCTAssertTrue("\(error)".contains("下一步"))
            XCTAssertTrue(error is BridgeError)
        }
    }

    func testStartVoiceRejectsSidebarRowAndReportsWhy() {
        let access = FakeAXAccess()
        access.nodes = [AXNodeSnapshot(element: AXElementRef(rawID: 5), role: "AXButton",
                                       descriptionText: "New voice chat",
                                       childCount: 3, childRoles: ["AXGroup", "AXButton", "AXButton"])]
        XCTAssertThrowsError(try driver(access).startVoice()) { error in
            XCTAssertTrue("\(error)".contains("结构不符"))
        }
        XCTAssertTrue(access.pressedElements.isEmpty, "结构不符的元素一次都不能按")
    }

    func testEndVoiceVerifiesIndicatorDisappeared() throws {
        let access = FakeAXAccess()
        access.nodes = [control(1, "Stop voice chat"), voiceActive(9)]
        access.onPress = { _, nodes in nodes.removeAll { $0.descriptionText == ChatGPTLabels.voiceActiveIndicator } }
        try driver(access).endVoice()
        XCTAssertFalse(ChatGPTLabels.isVoiceActive(access.nodes))
    }

    func testCaptureReturnsLongestAssistantText() throws {
        let access = FakeAXAccess()
        access.nodes = [
            AXNodeSnapshot(element: AXElementRef(rawID: 1), role: "AXStaticText", value: "短"),
            AXNodeSnapshot(element: AXElementRef(rawID: 2), role: "AXStaticText",
                           value: String(repeating: "复盘内容", count: 40))
        ]
        let captured = try driver(access).captureLatestAssistantMessage()
        XCTAssertTrue(captured.count > 100)
    }

    func testCaptureFailsWithActionableMessageWhenNothingReadable() {
        let access = FakeAXAccess()
        access.nodes = [composer(1)]
        XCTAssertThrowsError(try driver(access).captureLatestAssistantMessage()) { error in
            XCTAssertTrue("\(error)".contains("⌘C"), "读不到时必须提示用户改用剪贴板：\(error)")
            XCTAssertTrue("\(error)".contains("下一步"))
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AXDriverTests`
Expected: 编译失败 —— `AXDriver`、`CoachBridge`、`BridgeReadiness` 未定义

- [ ] **Step 3: 实现**

`CoachBridge.swift` 追加：

```swift
public struct BridgeReadiness: Equatable, Sendable {
    public let ok: Bool
    public let messages: [String]
    public init(ok: Bool, messages: [String]) { self.ok = ok; self.messages = messages }
}

/// App 层只依赖这个 protocol，不感知内部用的是 AX 还是剪贴板。
public protocol CoachBridge {
    func preflight() -> BridgeReadiness
    func sendText(_ text: String) throws
    func startVoice() throws
    func isVoiceActive() -> Bool
    func endVoice() throws
    func captureLatestAssistantMessage() throws -> String
}
```

`AXDriver.swift`：

```swift
import Foundation

public final class AXDriver: CoachBridge {
    private let access: any AXAccess
    private let locator: AXLocator
    private let shortTimeout: TimeInterval
    private let stateTimeout: TimeInterval

    public init(access: any AXAccess, locator: AXLocator,
                shortTimeout: TimeInterval = 5.0, stateTimeout: TimeInterval = 8.0) {
        self.access = access; self.locator = locator
        self.shortTimeout = shortTimeout; self.stateTimeout = stateTimeout
    }

    public func preflight() -> BridgeReadiness {
        var messages: [String] = []
        var ok = true
        if !access.isTargetInstalled() {
            messages.append("❌ 没找到 ChatGPT（新版桌面应用）。"
                + "下一步：从 openai.com/chatgpt/download 安装。注意 ChatGPT Classic 没有 live 语音，不能用。")
            ok = false
        }
        if !access.isAccessibilityTrusted() {
            messages.append("❌ 没有辅助功能权限，无法驱动 ChatGPT。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把运行本工具的终端加进去并勾选，然后重跑。")
            ok = false
        }
        guard ok else { return BridgeReadiness(ok: false, messages: messages) }

        if !access.isTargetRunning() {
            try? access.launchTarget()
        }
        if !access.wakeAccessibilityTree(timeout: 8.0) {
            messages.append("⚠️ ChatGPT 的无障碍树没能唤醒，可能读不到对话内容。"
                + "下一步：把 ChatGPT 窗口切到前台并打开一个会话，然后重跑；仍失败请运行 axprobe dump 收集诊断信息。")
        }
        messages.append("✅ 环境就绪")
        return BridgeReadiness(ok: true, messages: messages)
    }

    public func sendText(_ text: String) throws {
        let composer = try locator.waitForComposer(timeout: shortTimeout)
        guard access.setValue(text, on: composer.element) else {
            throw BridgeError.actionFailed("写入 ChatGPT 输入框失败。"
                + "下一步：确认 ChatGPT 窗口没有被弹窗挡住，然后重试。")
        }
        guard access.sendReturnKey() else {
            throw BridgeError.actionFailed("文字已写入输入框但没能发送。"
                + "下一步：切到 ChatGPT 窗口手动按一下回车。")
        }
    }

    public func startVoice() throws {
        let button = try locator.waitForControl(ChatGPTLabels.startVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下语音按钮失败。"
                + "下一步：确认 ChatGPT 窗口在前台，然后重试。")
        }
        // kAXPressAction 返回成功不等于动作生效（spec 2.3.1），必须验证状态真的变了
        try locator.waitUntil({ ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话开始")
    }

    public func isVoiceActive() -> Bool { ChatGPTLabels.isVoiceActive(access.snapshotTree()) }

    public func endVoice() throws {
        let button = try locator.waitForControl(ChatGPTLabels.stopVoice, timeout: shortTimeout)
        guard access.press(button.element) else {
            throw BridgeError.actionFailed("按下结束语音按钮失败。"
                + "下一步：切到 ChatGPT 窗口手动结束通话。")
        }
        try locator.waitUntil({ !ChatGPTLabels.isVoiceActive($0) },
                              timeout: stateTimeout, describing: "语音会话结束")
    }

    /// 读回最新的助手消息。取 AXStaticText 里最长的一条——
    /// 复盘 JSON 远长于界面上任何其他文字，这个启发式在实测中稳定。
    public func captureLatestAssistantMessage() throws -> String {
        let texts = access.snapshotTree()
            .filter { $0.role == "AXStaticText" }
            .map(\.value)
            .filter { $0.count >= 40 }
        guard let longest = texts.max(by: { $0.count < $1.count }) else {
            throw BridgeError.elementNotFound(
                "没能从 ChatGPT 窗口读到足够长的文字，复盘可能还没生成完。"
                + "下一步：等 ChatGPT 输出完再重试；若已经输出完，请在 ChatGPT 里选中复盘全文按 ⌘C，"
                + "然后用 coach practice --from-clipboard 继续。")
        }
        return longest
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AXDriverTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证（两条）**

1. 把 `startVoice` 里的 `waitUntil` 整行删掉（按完就返回），确认 `testStartVoiceFailsWhenIndicatorNeverAppears` 变红
2. 把 `sendText` 里的 `sendReturnKey` 调用删掉，确认 `testSendTextWritesComposerThenPressesReturn` 变红

两次都要记录真实失败输出，确认后改回。

- [ ] **Step 6: 提交**

```bash
git add Sources/ChatGPTBridge/ Tests/ChatGPTBridgeTests/
git commit -m "feat(bridge): CoachBridge protocol 与 AX 实现"
```

---

## Task 5: ClipboardFallback —— AX 读不到时的降级路径

**Files:**
- Create: `Sources/ChatGPTBridge/ClipboardFallback.swift`
- Modify: `Tests/ChatGPTBridgeTests/AXDriverTests.swift`（追加测试）

**Interfaces:**
- Consumes: 无（只用 AppKit 的 `NSPasteboard`）
- Produces: `protocol PasteboardAccess`、`SystemPasteboard`、`FakePasteboard`（测试用）、`enum ClipboardFallback` 含 `readReview(from:)`

spec 决定复盘回收是「AX 全自动打底 + 剪贴板兜底」。AX 读不到时，用户在 ChatGPT 里选中复盘按 ⌘C，工具从剪贴板取。

- [ ] **Step 1: 写失败的测试**

```swift
final class ClipboardFallbackTests: XCTestCase {
    func testReadsPlainTextFromPasteboard() throws {
        let pasteboard = FakePasteboard(contents: "  <<<IELTS_REVIEW_JSON>>>x<<<END_IELTS_REVIEW_JSON>>>  ")
        XCTAssertEqual(try ClipboardFallback.readReview(from: pasteboard),
                       "<<<IELTS_REVIEW_JSON>>>x<<<END_IELTS_REVIEW_JSON>>>")
    }

    func testEmptyPasteboardGivesActionableChineseError() {
        XCTAssertThrowsError(try ClipboardFallback.readReview(from: FakePasteboard(contents: ""))) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("剪贴板"))
            XCTAssertTrue(message.contains("下一步"))
        }
    }

    func testTooShortContentIsRejected() {
        // 用户可能没选中就按了 ⌘C，剪贴板里是上一次复制的零碎内容
        XCTAssertThrowsError(try ClipboardFallback.readReview(from: FakePasteboard(contents: "ok"))) { error in
            XCTAssertTrue("\(error)".contains("太短"))
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ClipboardFallbackTests`
Expected: 编译失败

- [ ] **Step 3: 实现**

```swift
import AppKit
import Foundation

public protocol PasteboardAccess: Sendable {
    func readString() -> String?
}

public struct SystemPasteboard: PasteboardAccess {
    public init() {}
    public func readString() -> String? { NSPasteboard.general.string(forType: .string) }
}

public enum ClipboardFallback {
    /// 复盘 JSON 至少这么长。低于此长度多半是用户没选中就按了 ⌘C。
    public static let minimumLength = 40

    public static func readReview(from pasteboard: any PasteboardAccess) throws -> String {
        let raw = (pasteboard.readString() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw BridgeError.elementNotFound("剪贴板是空的。"
                + "下一步：在 ChatGPT 里选中整段复盘（含首尾标记）按 ⌘C，然后重试。")
        }
        guard raw.count >= minimumLength else {
            throw BridgeError.elementNotFound("剪贴板里的内容太短（\(raw.count) 个字符），不像是一份复盘。"
                + "下一步：确认已经选中整段复盘再按 ⌘C，然后重试。")
        }
        return raw
    }
}
```

测试用的 `FakePasteboard` 放在 `Tests/ChatGPTBridgeTests/FakeAXAccess.swift` 里：

```swift
struct FakePasteboard: PasteboardAccess {
    let contents: String
    func readString() -> String? { contents }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ClipboardFallbackTests`
Expected: PASS（3 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/ChatGPTBridge/ClipboardFallback.swift Tests/ChatGPTBridgeTests/
git commit -m "feat(bridge): 剪贴板降级路径"
```

---

## Task 6: coach doctor —— 环境预检命令

**Files:**
- Modify: `Sources/coach/main.swift`
- Create: `Sources/coach/DoctorCommand.swift`

**Interfaces:**
- Consumes: `LiveAXAccess`、`AXLocator`、`AXDriver`、`DataDirectory`
- Produces: 命令 `coach doctor`

- [ ] **Step 1: 写 main.swift 的子命令分发**

```swift
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    coach — 雅思口语练习

    用法：
      coach doctor                  检查环境是否就绪
      coach questions import <文件>  导入题库（CSV 或 JSON）
      coach questions list [part]   列出题库
      coach practice <题目id>        开始一次练习
    """)
    exit(2)
}

switch command {
case "doctor":
    exit(DoctorCommand.run())
default:
    print("未知命令：\(command)。运行 coach 查看用法。")
    exit(2)
}
```

- [ ] **Step 2: 写 DoctorCommand**

```swift
import ChatGPTBridge
import Foundation
import IELTSCoachCore

enum DoctorCommand {
    static func run() -> Int32 {
        let access = LiveAXAccess()
        let driver = AXDriver(access: access, locator: AXLocator(access: access))
        let readiness = driver.preflight()
        readiness.messages.forEach { print($0) }

        let directory = DataDirectory.resolve()
        do {
            try directory.createIfNeeded()
            let state = try StateStore(directory: directory).load()
            print("✅ 训练数据：\(directory.root.path)")
            print("   题库 \(state.questions.count) 题，练习记录 \(state.sessions.count) 次，"
                + "错题 \(state.issues.count) 条，词汇 \(state.vocabulary.count) 条")
            if state.questions.isEmpty {
                print("ℹ️  题库是空的。下一步：coach questions import <你的题库文件>")
            }
        } catch {
            print("❌ 读取训练数据失败：\(error.localizedDescription)")
            return 1
        }
        return readiness.ok ? 0 : 1
    }
}
```

- [ ] **Step 3: 验证**

Run: `swift run coach doctor`
Expected: 打印环境检查结果与训练数据统计。ChatGPT 在运行时退出码 0。

- [ ] **Step 4: 提交**

```bash
git add Sources/coach/
git commit -m "feat(coach): doctor 环境预检命令"
```

---

## Task 7: coach questions —— 题库导入与列表

**Files:**
- Create: `Sources/coach/QuestionsCommand.swift`
- Modify: `Sources/coach/main.swift`

**Interfaces:**
- Consumes: `QuestionBankImporter.importCSV/importJSON/merge`、`StateStore.mutate`
- Produces: 命令 `coach questions import <文件>`、`coach questions list [part]`

- [ ] **Step 1: 实现**

```swift
import Foundation
import IELTSCoachCore

enum QuestionsCommand {
    static func run(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            print("用法：coach questions import <文件>  或  coach questions list [1|2|3]")
            return 2
        }
        switch sub {
        case "import": return importBank(path: args.count > 1 ? args[1] : nil)
        case "list": return list(partFilter: args.count > 1 ? Int(args[1]) : nil)
        default:
            print("未知子命令：\(sub)。可用：import、list")
            return 2
        }
    }

    private static func importBank(path: String?) -> Int32 {
        guard let path else {
            print("❌ 没有指定题库文件。下一步：coach questions import ~/Downloads/题库.csv")
            return 2
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("❌ 读不到文件：\(url.path)")
            print("   下一步：确认路径正确、文件是 UTF-8 编码的文本，然后重试。")
            return 1
        }
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let result = url.pathExtension.lowercased() == "json"
                ? try QuestionBankImporter.importJSON(text, sourceTitle: title)
                : try QuestionBankImporter.importCSV(text, sourceTitle: title)

            result.warnings.forEach { print("⚠️  \($0)") }

            let directory = DataDirectory.resolve()
            try directory.createIfNeeded()
            let total = try StateStore(directory: directory).mutate { state -> Int in
                state.questions = QuestionBankImporter.merge(existing: state.questions,
                                                             incoming: result.questions)
                state.questionSources.append(result.source)
                return state.questions.count
            }
            print("✅ 导入 \(result.questions.count) 题，题库现共 \(total) 题")
            if result.questions.isEmpty {
                print("ℹ️  这次没有导入任何题目。下一步：检查上面的警告。")
            }
            return 0
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
    }

    private static func list(partFilter: Int?) -> Int32 {
        do {
            let state = try StateStore(directory: DataDirectory.resolve()).load()
            let questions = partFilter == nil ? state.questions
                                              : state.questions.filter { $0.part == partFilter }
            guard !questions.isEmpty else {
                print("题库里没有符合条件的题目。下一步：coach questions import <你的题库文件>")
                return 0
            }
            for question in questions {
                let mark = question.status == "practiced" ? "✓" : " "
                print("\(mark) [\(question.id)] Part \(question.part) · \(question.topic)")
                print("    \(question.prompt)")
            }
            print("\n共 \(questions.count) 题")
            return 0
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
    }
}
```

`main.swift` 的 switch 里加：

```swift
case "questions":
    exit(QuestionsCommand.run(Array(args.dropFirst())))
```

- [ ] **Step 2: 验证**

用上游的样例题库建一个测试 CSV：

```bash
cat > /tmp/sample.csv <<'CSV'
id,part,topic,prompt,followups
p1-home-001,1,Home,What do you like most about your home?,
p2-skill-001,2,Skills,Describe a useful skill you learned,"How you learned it|Why it is useful"
CSV
swift run coach questions import /tmp/sample.csv
swift run coach questions list
```

Expected: 导入 2 题、列出 2 题。再跑一次 import 应显示题库仍是 2 题（id 相同被合并）。

- [ ] **Step 3: 提交**

```bash
git add Sources/coach/
git commit -m "feat(coach): 题库导入与列表命令"
```

---

## Task 8: coach practice —— 完整练习流程

**Files:**
- Create: `Sources/coach/PracticeCommand.swift`
- Modify: `Sources/coach/main.swift`

**Interfaces:**
- Consumes: `AXDriver`、`ExaminerPrompt.build`、`ReviewRequestPrompt.build/marker`、`ReviewParser.parse`、`ReviewArchiver.archive`、`StateStore.mutate`、`ClipboardFallback.readReview`
- Produces: 命令 `coach practice <题目id> [--immediate] [--self-paced] [--goal "..."]`

**这是本阶段的核心交付。** 它把前面所有单元串成一场真实练习。

- [ ] **Step 1: 实现**

```swift
import ChatGPTBridge
import Foundation
import IELTSCoachCore

enum PracticeCommand {
    static func run(_ args: [String]) -> Int32 {
        guard let questionID = args.first, !questionID.hasPrefix("--") else {
            print("❌ 没有指定题目。下一步：先 coach questions list 看有哪些题，再 coach practice <题目id>")
            return 2
        }
        let feedbackTiming: FeedbackTiming = args.contains("--immediate") ? .immediate : .deferred
        let prepMode: Part2PrepMode = args.contains("--self-paced") ? .learnerControlled : .countdown
        let goal = valueFor("--goal", in: args) ?? ""

        let directory = DataDirectory.resolve()
        let store = StateStore(directory: directory)

        let question: Question
        do {
            guard let found = try store.load().questions.first(where: { $0.id == questionID }) else {
                print("❌ 题库里没有 id 为「\(questionID)」的题目。")
                print("   下一步：coach questions list 查看可用题目。")
                return 1
            }
            question = found
        } catch {
            print("❌ \(error.localizedDescription)"); return 1
        }

        let access = LiveAXAccess()
        let driver = AXDriver(access: access, locator: AXLocator(access: access))
        let readiness = driver.preflight()
        readiness.messages.forEach { print($0) }
        guard readiness.ok else { return 1 }

        let focusPart = FocusPart(rawValue: "Part \(question.part)") ?? .fullMock
        let setup = SessionSetup(question: question, focusPart: focusPart,
                                 durationMinutes: question.part == 2 ? 4 : 6, goal: goal,
                                 feedbackTiming: feedbackTiming, part2PrepMode: prepMode)

        do {
            print("\n▶︎ 正在把考官提示词发给 ChatGPT…")
            try driver.sendText(ExaminerPrompt.build(setup: setup))

            print("▶︎ 正在启动语音…")
            try driver.startVoice()
            print("\n✅ 开练了。跟 ChatGPT 说话就行。")
            print("   练完之后在 ChatGPT 里结束通话即可；也可以回到这里按回车。\n")

            waitForSessionEnd(driver: driver)

            if driver.isVoiceActive() {
                print("▶︎ 正在结束语音…")
                try driver.endVoice()
            }

            let requestID = "sync-\(Int(Date().timeIntervalSince1970))"
            print("▶︎ 正在请 ChatGPT 生成复盘…")
            try driver.sendText(ReviewRequestPrompt.build(requestID: requestID, focusPart: focusPart))

            print("▶︎ 等 ChatGPT 写完…（约 30 秒）")
            Thread.sleep(forTimeInterval: 30)

            let raw = captureReview(driver: driver)
            guard let raw else { return 1 }

            let report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
            let sessionID = ISO8601DateFormatter().string(from: Date())
            try directory.createIfNeeded()
            try raw.write(to: directory.pendingReviewsDirectory.appending(path: "\(requestID).txt"),
                          atomically: true, encoding: .utf8)

            try store.mutate { state in
                state = ReviewArchiver.archive(report: report, into: state, sessionID: sessionID,
                                               questionID: question.id,
                                               at: ISO8601DateFormatter().string(from: Date()))
            }
            let state = try store.load()
            print("\n✅ 复盘已存档。")
            print("   错题本 \(state.issues.count) 条，词汇本 \(state.vocabulary.count) 条，"
                + "重训目标 \(state.targets.count) 个")
            return 0
        } catch {
            print("\n❌ \(error.localizedDescription)")
            return 1
        }
    }

    /// 等练习结束。spec 定的是「AX 探测 + 手动按钮双保险」，两条都要接上：
    /// 后台线程读一行 stdin 作为手动兜底，主循环用 VoiceEndPolicy 判断语音是否已结束。
    /// 只做手动那一半的话，Phase 1 造的 VoiceEndPolicy 就成了死代码；
    /// 只做自动那一半的话，AX 万一失灵用户就卡住了。
    private static func waitForSessionEnd(driver: AXDriver) {
        let manualStop = ManualStopFlag()
        Thread.detachNewThread {
            _ = readLine()
            manualStop.set()
        }

        var state = VoiceEndState()
        while !manualStop.isSet {
            state = VoiceEndPolicy.advance(previous: state,
                                           voiceActive: driver.isVoiceActive(),
                                           busy: false)
            if state.shouldFinalize {
                print("▶︎ 检测到语音已结束（\(state.reason)）")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)   // 与 requiredInactiveTicks=3 配合约 1.5 秒去抖
        }
        print("▶︎ 已手动结束")
    }

    /// 跨线程的一次性标志。用类而非局部 var，因为要被后台线程写。
    private final class ManualStopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    /// 先试 AX 自动读，失败则降级到剪贴板。两条路都失败时给出可执行的下一步。
    private static func captureReview(driver: AXDriver) -> String? {
        do { return try driver.captureLatestAssistantMessage() } catch {
            print("⚠️  \(error.localizedDescription)")
            print("\n请在 ChatGPT 里选中整段复盘按 ⌘C，然后回到这里按回车。")
            _ = readLine()
            do { return try ClipboardFallback.readReview(from: SystemPasteboard()) } catch {
                print("❌ \(error.localizedDescription)")
                return nil
            }
        }
    }

    private static func valueFor(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
```

`main.swift` 的 switch 里加：

```swift
case "practice":
    exit(PracticeCommand.run(Array(args.dropFirst())))
```

- [ ] **Step 2: 验证（不开语音，只验参数与错误路径）**

Run: `swift run coach practice 不存在的题号`
Expected: 退出码 1，中文错误 + 「下一步：coach questions list」

Run: `swift run coach practice`
Expected: 退出码 2，提示先看题目列表

- [ ] **Step 3: 提交**

```bash
git add Sources/coach/
git commit -m "feat(coach): 完整练习流程"
```

---

## Task 9: 真机端到端联调（人工，必须真跑一次）

**Files:** 无代码改动。产出 `docs/phase2-e2e-findings.md`

**这一步不能省，也不能靠单元测试代替。** 前面所有测试都跑在 `FakeAXAccess` 上，证明的是「逻辑对」，不是「在真 ChatGPT 上能跑通」。时序、渲染延迟、ChatGPT 的实际反应都只有真跑才知道。

- [ ] **Step 1: 准备**

```bash
swift run coach doctor
```

确认全绿。ChatGPT 打开并停在一个新会话上。

- [ ] **Step 2: 跑一次完整练习**

```bash
swift run coach practice p1-home-001
```

**逐项记录到 `docs/phase2-e2e-findings.md`：**

| 观察项 | 记什么 |
|---|---|
| 考官提示词有没有真的发出去 | ChatGPT 收到了吗？开场白是不是提示词里指定的那句？ |
| 语音有没有真的启动 | 菜单栏有没有出现橙色麦克风指示？ |
| 提示词发送与语音启动之间的时序 | 有没有出现「提示词还没发完就开了语音」？ |
| ChatGPT 演得像不像考官 | 有没有一次问一个问题？有没有中途给反馈（deferred 模式下不该给）？ |
| 结束语音是否成功 | `Voice chat active` 有没有消失？ |
| 复盘请求 | ChatGPT 有没有按定界格式输出？30 秒够不够？ |
| **AX 能不能读到完整复盘** | **这是 spec 假设 5 的最终验证** |
| 存档 | 错题本、词汇本、重训目标数量对不对？ |

- [ ] **Step 3: 用 `--immediate` 再跑一次**

```bash
swift run coach practice p1-home-001 --immediate
```

确认 ChatGPT 每答完一题真的用中文给了**一到两句**的点评，而不是长篇大论、也不是完全不给。这是产品负责人特意选的模式，行为不对要记下来。

- [ ] **Step 4: 关闭 spec 假设 5**

练一场**长对话**（30 轮以上），然后：

```bash
swift run axprobe dump /tmp/long-session.txt
grep -c 'AXStaticText value="[^"]\{60,\}"' /tmp/long-session.txt
```

统计能读到的消息条数，与实际轮次比对，把结论写进 `docs/phase2-e2e-findings.md` 并回填 spec 第 11 节。

- [ ] **Step 5: 提交发现**

```bash
git add docs/
git commit -m "docs: Phase 2 真机联调结果，关闭 spec 假设 5"
```

---

## Phase 2 完成标准

- [ ] `swift test` 全绿（115 个既有 + ChatGPTBridge 新增约 23 个）
- [ ] `swift run coach doctor` 环境全绿
- [ ] `swift run coach questions import` 能导入真实题库
- [ ] **`swift run coach practice <id>` 能完成一次真实练习并存下复盘** ← 本阶段的定义性交付
- [ ] spec 假设 5 有明确结论
- [ ] `VoiceEndPolicy` 真的被 `coach practice` 用上了（不是死代码），且自动探测与手动按回车两条路都验证过
- [ ] `ChatGPTBridge` 的每条测试都经突变验证确认有约束力

达成后进 Phase 3：SwiftUI 界面（届时业务流程已被真机验证过，界面只需管界面）。
